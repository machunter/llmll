---
name: proc-boundary-1-implementation-plan
title: "PROC-BOUNDARY-1: implementation plan and measurements"
status: "LANDED, uncommitted. Implemented against proposal Rev 3 at compiler v0.14.84, Rev 2 having been corrected on the point this implementation surfaced. Both halves shipped: wasi.proc.args on the existing RList arm under the existing ENonDet label with no grammar and no def-main change, and :status as an optional def-main field applied only on the :done? path. The exhaustion status is gated on whether :done? is DECLARED, so a program that declares a completion predicate cannot exit 0 without reaching it while a program that declares none exits 0 on EOF as it always did. NO SHIPPED PROGRAM CHANGES BEHAVIOUR, measured on all three in-tree console programs that declare no :done?. Schema 0.10.0 to 0.11.0, additive. Test suite 1616 to 1638 examples, 0 failures. Both directions of the rule carry a measured positive witness and a refute-crux. One finding routed out: the sibling :done? type check is a false positive on every correct program in the corpus, which is why the :status check was written from scratch rather than copied."
date: 2026-08-05
author: compiler-engineer
consumers: [user, language-team, documentation-lead, professor]
---

# PROC-BOUNDARY-1: implementation plan and measurements

## Restatement

Land the two halves of the process boundary
([`proc-boundary-1-proposal.md`](proc-boundary-1-proposal.md), Rev 3, settled): an
ambient read of the process argument vector as a WASI capability, and a terminal exit
status as a projection on `def-main`. Sub-phase 4a of DRIVER-LL Phase 4 is blocked on
both and consumes them later; `tools/llmll-driver/` is untouched here.

## What landed, by file

**Half one, `wasi.proc.args`.** Four lines of real change, exactly the shape §3 predicted.

- [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs): one
  `builtinEnv` entry, `TCustom "Command"`. Nullary, so it binds as a VALUE and
  `wasi.proc.args` is an expression rather than an application, matching
  `wasi.clock.monotonic` and `RNone`. `extractWasiNamespace` (`:1764`) takes the first
  two segments, so it lands under the `wasi.proc` capability `wasi.proc.run` already
  opens; no new namespace.
- [`compiler/src/LLMLL/ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs)
  adds a second disjunct to the `ENonDet` clause. Placement matters and is pinned by a
  test: below the `wasi.` fallthrough at `:476` the name would report ⊤ and every
  transitive caller's `effect_summary` would go vacuous. Σ_eff stays six-wide.
- [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs): one
  `runtimePreamble` body publishing `RList` through `llmll_publish_io`, plus
  `import System.Environment (getArgs)` in the emitted `Lib.hs`. base only, so no
  `package.yaml` entry is owed and the generated project's dependency closure does not
  move off 33.

No grammar change, no `def-main` change, no schema change for this half, exactly as §3
claimed: it rides RC-3, so a program issues `wasi.proc.args` as `:init`'s command and
receives `RList` as `r0`. `:init`'s arity does not move.

**Half two, `:status`.**

- [`compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs): `SDefMain`
  gains `defMainStatus :: Maybe Expr`.
- [`compiler/src/LLMLL/Parser.hs`](../../compiler/src/LLMLL/Parser.hs): one optional
  field, appended last. The existing fields are already parsed by sequential `optional`,
  so the order discipline is not new: `:on-done` before `:done?` has never parsed either.
- [`compiler/src/LLMLL/ParserJSON.hs`](../../compiler/src/LLMLL/ParserJSON.hs): one
  optional field, plus `expectedSchemaVersion` 0.10.0 → 0.11.0 and `0.11.0` prepended to
  `acceptedSchemaVersions`. Bumping the stamp without extending the accepted list is an
  emit/read asymmetry no type catches; pinned by PB-11.
- [`compiler/src/LLMLL/AstEmit.hs`](../../compiler/src/LLMLL/AstEmit.hs): emits
  `status` only when present, on the RD1-6 byte-inertness rule, so a `def-main` without
  it round-trips unchanged.
- [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs): the
  `:status` position is collectible, so a `?hole` there reaches checkout and an agent can
  be handed the projection to write.
- [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs):
  `checkStatusField`, three warnings: non-console mode, `:status` with no `:done?`
  (§6.6's flagged gap, `tcWarn` as the proposal names), and a non-int return position.
- [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs): the two
  terminal paths.
- [`docs/llmll-ast.schema.json`](../llmll-ast.schema.json): optional `status` on
  `DefMain`, `schemaVersion` const 0.11.0, `$id` to `/schemas/v0.11/` (C4 of
  `version_gate.sh` derives the URL from the version and would fail otherwise).

## The codegen shape, and the one place it deviates from the proposal's sketch

§8 says the change is "the two terminal paths in `emitMainBody`, the fall-through after
`loop` at `:1584` and `settle` at `:1653`". Both of those paths CONVERGE in the emitted
program: `settle` returns to `loop`, `loop` returns to `main`, `main` runs
`hClose logHandle` and falls off the end at exit 0. There is no point in the generated
code where the two are distinguishable, so a status cannot be applied "at `:1653`"
without first making them distinguishable.

`loop` therefore now returns `Maybe Integer`. `Nothing` is exhaustion, `Just n` is a
settled run carrying its status; `main` binds the outcome, closes the log, and calls a
`llmll_terminate` helper. Threading the outcome back rather than calling `exitWith` from
inside the branches is not tidiness. The header line written before the loop is the only
log write with no following `hFlush`, so a program reaching EOF before its first step
would lose the header entirely if the exit jumped over `hClose`. **Measured:** a
zero-input run leaves a 61-byte log holding exactly the header line. Pinned by PB-16.

`ExitFailure 0` raises in GHC, so the zero case branches to `exitSuccess` rather than
folding into the general clause; a generated program that folded them would crash on its
own success. Pinned by PB-17.

## Measurements

### Gates

| Gate | Before | After |
|---|---|---|
| `stack build` (compiler/) | clean | clean |
| `stack test` | 1616 examples, 0 failures | **1638 examples, 0 failures** |
| `bash scripts/build_smoke.sh` | 4 stages PASS | **5 stages PASS** |
| `python3 -m pytest scripts/tests/ -q` | 120 passed | 120 passed |
| `python3 scripts/doc_path_lint.py` | 789 citations / 158 files, all resolve | 796 citations / 159 files, all resolve |
| `bash scripts/version_gate.sh` | PASS at schema 0.10.0 | PASS at schema 0.11.0 |

The doc-lint delta is NOT this change: the linter reads `git ls-files '*.md'`, so it sees
only tracked files, and both files added here are untracked. The +7/+1 is commit
`a40772e`, a concurrent documentation pass committing the proposal itself. This plan
document's own 21 citations were run through the linter's `PATH`/`LABEL`/`ALLOW` logic
directly and all resolve; they will be counted once it is tracked.

The +22 examples are 21 new `PB-*` assertions plus one from the WASI-RT completeness
fold, which generates one example per `wasi.*` name in `builtinEnv` and so grows by
itself when a name lands. The name count assertion moved 13 to 14. PB-21 is the Rev 3
addition; PB-15 was rewritten in place rather than added, so it does not move the count.

### The positive witness, measured on both sides

The proposal's §6.1 asks for a run that exits 0 today and 70 after. Asserting that from
the diff is exactly the failure shape this line has recorded five times, so it was built
both ways. `scripts/build-smoke/proc_boundary.llmll` was compiled by the post-change
emitter; the emitted `Main.hs` was then reverted to the pre-change emitter's output
(the outcome plumbing removed, `return Nothing` → `return ()`, `settle`'s return →
`return ()`) and rebuilt. Same fixture, same GHC, same inputs.

| stdin | pre-change | post-change |
|---|---|---|
| 1 line (`:done?` needs 2, so starved) | **0** | **70** |
| 2 lines (`:done?` fires, `:status` returns 42) | **0** | **42** |
| 0 lines (immediate EOF) | **0** | **70** |

The pre-change column is the bug §1 fact 2 describes: partial state written, no
diagnostic, exit 0. Note the middle row: before this change, a program had no way to
produce 42 at all, which is what made 4a's acceptance criterion unmeetable rather than
awkward.

Argv, measured on the same binary: invoked with `alpha beta gamma` it prints `argc=3`,
invoked with none it prints `argc=0`. The negative half is in the gate too, because a
body publishing a constant three-element list would pass the positive assertion alone.

### The other half of the rule, and its own witness

The table above is the `:done?`-declared population. The no-`:done?` population needs a
witness of its own, and it has to be a **shipped** program: the claim there is that
nothing regresses, and a fixture written for this change cannot make a no-regression
claim about a corpus that predates it.

All three in-tree console programs that declare no `:done?` were built and run:

| program | 2 lines then EOF | immediate EOF |
|---|---|---|
| `examples/replay-demo/replay-demo.llmll` | **0** | **0** |
| `examples/proof_required_test/proof_required_test.llmll` | **0** | **0** |
| `compiler/test/fixtures/pair_type_test/pair_type_test.llmll` | **0** | **0** |

That is the whole measured population, not a sample, and it is why the
breaking-behaviour paragraph is deleted from the hand-off below rather than softened.

**Refute-crux.** A gate assertion that cannot fail proves nothing, so the same
revert-and-rebuild technique was pointed at this one: `replay-demo`'s emitted exhaustion
clause was set back to Rev 2's unconditional-70 rule and rebuilt. It exits **70**, so
`[ "$PB_RC" -eq 0 ]` in stage 7 discriminates rather than passing vacuously.

### Verification

`llmll verify` on the fixture reports `body-faithful: pb-status` and **SAFE
(liquid-fixpoint)**. §5 predicted the whole boundary lands in the auto-discharged
fragment and it does: the range obligation `{v : int | 0 <= v && v <= 255}` is ground
QF-LIA, nothing escapes to Lean, nothing is nonlinear, and no function newly falls back.
The fixture's `:status` body is `(if (>= s 2) 42 7)`, two literal branches, because
`(+ s 40)` would NOT verify, `s` being an unconstrained `int`. That is the refinement
doing its job rather than a fixture convenience.

## Findings

### 1. The sibling `:done?` check is a false positive on every correct program

`checkStatement (SDefMain …)` compares `inferExpr doneE` against `TBool`. `:done?` names
a FUNCTION, so its inferred type is `TFn [S] bool`, and `compatibleWith`
(`TypeCheck.hs:2805`) falls through to structural equality and returns False.

**Executed, not read.** `llmll check scripts/build-smoke/smoke.llmll` at v0.14.84, on an
unmodified tree, reports `OK (37 statements, 1 warning)` / `warning: :done? should return
bool; found non-bool type (ignored in v0.2)`. smoke.llmll is correct. The warning fires
on every console program in the corpus that names its `:done?`, so it carries no
information.

This is why `checkStatusField` was written from scratch rather than copied: it reads the
RETURN POSITION of a `TFn`, which is what the sibling meant to do, and produces no
warning on a correctly-typed named projection. PB-19 pins that as an anti-regression.

The sibling is **left alone**. Fixing it changes the diagnostic output of an unrelated
check on every console program in the tree, which is its own row and its own release
note, not a silent rider on this one. Routed to language-team / doc-lead as a new row.

### 2. Rev 2's exhaustion rule was wrong for programs with no `:done?`, and Rev 3 fixes it

**This finding was raised against Rev 2 and is now closed by Rev 3.** It is kept rather
than deleted because the shape is worth the record: the implementation was correct
against the specification, and the specification was wrong.

Rev 2 made the exhaustion status unconditional. §4.1's second row reads "stdin reaches
EOF first", §4.3 claims the guarantee is universal, and §6.2 restates it for the
`:status`-absent population. Implemented literally, that made **every** run of a program
with no `:done?` exit 70. Such a program can never signal completion, so exhaustion is
its only terminal path: the rule could only ever fire on a successful run and could never
distinguish anything about it. A false alarm, not a diagnostic.

Rev 3 gates on whether `:done?` is **declared**, not on whether it fired, which is also
the only signal available at emit time (`Nothing` reaching `llmll_terminate` already says
it did not fire). The guarantee survives exactly where "starved" is meaningful: no
program that declares a completion predicate can exit 0 without reaching it. That is
still unconditional on the caller's state modelling, which is what §4.3 was protecting.

**Consequence: there is no breaking behaviour change.** All three in-tree console
programs that declare no `:done?` exit 0 before and after, measured (table above).
Nothing else in the tree asserts a console program's exit code anyway: stages 5 and 6 of
`build_smoke.sh` swallow it with `|| true`, and `llmll replay` discards the child's
status at `Replay.hs:244` (`_ <- waitForProcess ph`). The release note loses its
breaking-behaviour paragraph.

### 3. The range refinement binds only the programs that declare it

§4.4 puts `{v : int | 0 <= v && v <= 255}` on "the declared contract of whatever function
`:status` names", and §6.3 says a `:status` returning 300 is "rejected at `llmll verify`
by the range refinement". That holds only where the contract was written. The compiler
does not inject the postcondition, and nothing here requires the named function to carry
one, so a `:status` with no `post` clause returning 300 reaches codegen and POSIX
truncates it to 44, or, at 256, to 0, reporting success.

Implemented as specified rather than designed around: adding a hard requirement is a spec
move, not an engineer's call, and §9 risk 2 records the trade deliberately.

**Closed as a spec defect, with one piece of work left open.** Rev 3 corrects edge case 3
to read "rejected at `llmll verify` if and only if the program declares the range as a
postcondition", which is what the code does. It also names a follow-on: *"The in-scope
move is a `tcWarn` when `:status` names a function carrying no range postcondition, on the
same precedent as edge case 6."*

**That `tcWarn` is NOT implemented here.** The correction arrived as one explicitly scoped
delta (the declaration gate), and adding an unrequested diagnostic on top of it is scope
expansion of the kind that should be surfaced rather than taken. It is cheap, it is a
sibling of the warning `checkStatusField` already emits, and it needs the contract of the
function `:status` names, which that function does not currently look up. Flagged so the
proposal's `IMPLEMENTED` status is read accurately: §4.1's table is implemented in full,
§6.3's named `tcWarn` is owed.

## Tests added

Twenty-one assertions in [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs), two
`describe` blocks placed next to the CAP-PROC and EFFECT-RESP blocks they extend.

`PB-1` … `PB-7` (half one): nullary VALUE binding and the negative that it is not a 0-arg
function; `primEffect` is `ENonDet` and specifically NOT the `wasi.` ⊤ fallthrough; label
sharing with the clock plus Σ_eff still six-wide; the RList arm is reused and `Response`
gains no sixth arm; the preamble defines the body and publishes through
`llmll_publish_io`; `getArgs` and not `getProgName`, so cli and console agree on what
"the arguments" means; the `evaluate` force is inside the `try`.

`PB-8` … `PB-21` (half two): S-expr parse into `defMainStatus`; JSON round trip both
directions; byte-inertness when absent; the accepted-versions symmetry; `settle` applies
`:status`; absent `:status` returns 0; **with `:done?` declared, EOF returns `Nothing`,
exits a fixed 70, and the exhaustion clause does not mention the status function at all**
(PB-14); **with no `:done?` declared, EOF exits 0** (PB-15); `hClose` precedes the exit on
both paths; `exitSuccess` rather than `ExitFailure 0`; the §6.6 dead-projection warning;
the anti-regression that a correct `:status` produces no return-type warning; a `?hole` in
`:status` is collected.

`PB-21` is the discriminator itself, written as a CONTRAST rather than as two independent
facts: two harnesses differing only in whether `:done?` is declared must differ in exactly
the `llmll_terminate Nothing` clause, and each must NOT carry the other's.

**End-to-end**, [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) stage 7 over
[`scripts/build-smoke/proc_boundary.llmll`](../../scripts/build-smoke/proc_boundary.llmll):
builds, runs, and asserts the four exit codes and both argv cases, plus a fifth
assertion on `examples/replay-demo/replay-demo.llmll`, a SHIPPED program with no
`:done?`, which must exit 0. That one deliberately does not use a purpose-built fixture:
the claim it makes is a no-regression claim about a corpus that predates the change, and
only a program from that corpus can make it. The `|| true` idiom stages 5 and 6 use
cannot be used anywhere in this stage; the exit code IS the observation.
`scripts/build-smoke/smoke.llmll` gains a `wasi.proc.args` call and the gate's
preamble-name list gains `wasi_proc_args`, keeping that fixture's stated contract that
every `wasi.*` name with a preamble body is called at least once.

## Rollback

Single revert. The schema bump is additive: 0.10.0 stays in `acceptedSchemaVersions`, no
field changed meaning, and a document written by the new emitter that reaches an old
reader fails on the version constant rather than parsing wrongly. No `.verified.json` or
`.fq` migration: nothing about the verification pipeline moved, and `:status`'s obligation
is an ordinary postcondition on an ordinary `def`. No shipped program's exit code moves in
either direction, so a revert has no behavioural blast radius beyond removing the two new
surfaces. The one thing a revert does NOT undo is a shell script downstream that started
depending on exit 70; that is a consumer concern, and 4a has not landed yet.

## Out of scope, deliberately

`tools/llmll-driver/` is untouched. The `:done?` false positive is left as-is (finding 1).
Rev 3 §6.3's `tcWarn` for a `:status` whose function declares no range postcondition is
named in the settled document and not built here (finding 3); it is the one piece of
`PROC-BOUNDARY-1` still owed.
`CHANGELOG.md`, `README.md`, `LLMLL.md`, `docs/compiler-team-roadmap.md` and
`docs/design/INDEX.md` are doc-lead's, and `LLMLL.md` §9 and §13 both owe text here.

## Hand-off to documentation-lead

Tag `PROC-BOUNDARY-1`. Two user-visible changes. (1) A new WASI builtin,
`wasi.proc.args : Command`, nullary, delivering the process argument vector on the
existing `RList` response arm under the existing `ENonDet` effect label; argv[0] is
excluded; it is issued as `:init`'s command and read as `r0`. Namespace `wasi.proc`, so
the capability import `wasi.proc.run` already needs covers it. (2) A new optional
`def-main` field, `:status`, a total function from the state type to `int`, applied to
the final state when `:done?` holds, the process then exiting with the result; absent
means exit 0. Declare `{v : int | 0 <= v && v <= 255}` on the named function's contract.
Where `:done?` IS declared and stdin exhausts first, the program exits a fixed **70** and
`:status` is not consulted; 70 is not reserved, so a shell can tell neither outcome from
success but cannot tell exhaustion from a deliberately-returned 70. Where `:done?` is NOT
declared, EOF is normal termination and the program exits 0, unchanged. **There is no
breaking behaviour change and the release notes should not claim one**: all three in-tree
console programs with no `:done?` were built and run, and all three exit 0 before and
after. Schema delta: 0.10.0 to 0.11.0, one additive-optional `status` property on
`DefMain`, `$id` moved to `/schemas/v0.11/`; no removals. Test count 1616 to 1638.
CHANGELOG `## Latest` candidate: "PROC-BOUNDARY-1: `wasi.proc.args` reads the argument
vector and `def-main :status` reports a terminal exit status; a program that declares
`:done?` and never reaches it now exits 70 instead of silently succeeding." Two rows are
owed on the roadmap: `PROC-BOUNDARY-1` itself (R-14's promotion rule, 4a is blocked on
it), and a new row for the `:done?` false-positive warning in finding 1.
