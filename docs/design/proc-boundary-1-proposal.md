---
name: proc-boundary-1-proposal
title: "PROC-BOUNDARY-1: argv in, status out"
status: "Rev 4, SETTLED, SHIPPED v0.14.85. Rev 4 adds section 5.1, a verification-mapping limit measured by the DRIVER-LL sub-phase 4a port rather than predicted: the `0 <= status <= 255` obligation is discharged as a CONTRACT obligation always, but the function's BODY is proved to satisfy it only for a SCALAR state. `:status` is applied to the state, a real driver's state is composite (a pair of a run-common record and a phase sum), and a `def` projecting a component out of a pair falls back from body-faithful, measured on a bare `[s: (int,int)]` as much as on the driver's. This proposal's own fixture takes `[s: int]`, the provable case, so the smoke gate reports `body-faithful: pb-status` and a reader could conclude the obligation is proved in general; it is not, and the fixture's green line actively supports the misreading. Fragment limitation, not a defect, the same Sigma_auto boundary drawn elsewhere. The 4a port's response is the pattern to copy: keep the proved core scalar (a body-faithful `exit-code : Status -> int` carrying the range, its constructor mappings and a non-vacuity clause) and clamp at the composite boundary. Rev 3 was SETTLED and IMPLEMENTED EXCEPT ONE NAMED ITEM: section 4.1's semantics ship in full, and section 6.3's `tcWarn` (fire when `:status` names a function carrying no range postcondition) is OWED, not built. It needs `checkStatusField` to look up the named function's contract, which it does not do. Flagged by the implementing engineer against this document's own status line, on the ground that IMPLEMENTED unqualified would be read as covering everything the proposal names. Rev 3 removes a breaking change Rev 2 introduced, and it was found by an engineer implementing Rev 2 faithfully and reporting the consequence rather than by re-reading the spec. Rev 2 gated the exhaustion exit on whether `:done?` FIRED, so a program declaring no `:done?` could never signal completion, every run of it terminated by exhaustion, and every run exited 70 where it had exited 0. That is a false alarm on a successful run: a program with no completion predicate is a stream processor and for it EOF is the normal end of input, not starvation. Measured population: examples/replay-demo, examples/proof_required_test, compiler/test/fixtures/pair_type_test. Rev 3 gates on whether `:done?` is DECLARED. The guarantee survives exactly where it means anything (no program that declares a completion predicate can exit 0 without reaching it) and the breaking change disappears entirely. Rev 2 folded three findings the implementation measured, one of which is a defect in this document. (1) EDGE CASE 3 WAS WRONG AND CONTRADICTED THIS PROPOSAL'S OWN RISK 2: it said an out-of-range `:status` is rejected at `llmll verify` before codegen, and the compiler injects no postcondition, so the range binds only where the program declares it. An undeclared `:status` returning 300 truncates to 44 and one returning 256 exits 0 REPORTING SUCCESS, which is exactly what risk 2 described and edge case 3 denied. Corrected, with a `tcWarn` named as the in-scope move. (2) The two terminal paths are not separately addressable in the emitted program: `settle` returns to `loop` and `loop` returns to `main`, so the implementation threads the outcome back as `Maybe Integer` rather than exiting inside the branches, which keeps `hClose` on both paths. (3) A pre-existing sibling defect was found by executing rather than reading: the `:done?` check compares the whole expression's type against `TBool` where `:done?` names a FUNCTION of type `TFn [S] bool`, so it warns on every correct console program in the corpus and carries no information; `checkStatusField` reads the return position instead and does not copy it. The sibling is left alone and owed a row. Rev 1 specified the process boundary sub-phase 4a is blocked on: an entry that both receives argv and reports a defined terminal status. The two halves are deliberately different categories. Reading argv is an ambient nondeterministic read and lands in the capability system as `wasi.proc.args`, on the EXISTING `RList` arm under the EXISTING `ENonDet` label, riding RC-3's already-shipped path, with zero grammar and zero schema change. Setting a terminal status is NOT an effect, since nothing in the program observes it and the program does not continue past it, so it lands in `def-main` as `:status`, a pure projection from state to int. One refutation is folded from the drafting turn and it strengthened the design: Rev 1's first form applied `:status` at both terminal paths and claimed section 4's `Phase` sum would distinguish a starved run from a clean finish. It does not. All three arms (`Sequencing`, `Delegating`, `Waving`) are non-terminal and the distinguishing information lives in `:done?`, a predicate outside the state. EOF-before-`:done?` is therefore a harness-level condition and exits a fixed, disclosed 70 without consulting `:status`, which makes the no-silent-success guarantee universal rather than conditional on the caller's data modelling. Nothing escapes to Lean and nothing is nonlinear: the whole boundary lands in the auto-discharged fragment, which is the result that justifies this shape."
date: 2026-08-05
author: language-team
consumers: [compiler-engineer, documentation-lead, professor, user]
---

# PROC-BOUNDARY-1: argv in, status out

**One line.** No LLMLL entry mode combines argv, `Command` performance and a defined terminal
status; a shell driver needs all three; this is the smallest surface that closes the gap, and it
grows no catalog.

**Prerequisite state.** Compiler at v0.14.84. Sub-phase 4a of DRIVER-LL Phase 4 is specified,
planned, and blocked on this
([`driver-ll-phase4a-implementation-plan.md`](driver-ll-phase4a-implementation-plan.md)).

---

## 1. The gap, measured

Three facts, all read out of the compiler rather than inferred.

1. **`ModeCli` has argv and performs no `Command`.** `emitMainBody` generates
   `args <- getArgs` then `print (step args)`
   ([`CodegenHs.hs:1659-1663`](../../compiler/src/LLMLL/CodegenHs.hs)). It can read the flags and
   cannot act on them, so it cannot run a driver.
2. **`ModeConsole` performs `Command`s and never sees argv.** Its loop opens at
   `eof <- hIsEOF stdin` and takes `if eof then return ()` (`:1587-1588`), so a stdin that runs out
   before the run completes exits **0**, having written partial state, with no diagnostic of any
   kind. There is no terminal-marker check.
3. **Neither mode can set an exit status.** The RFC-pipeline rig asserts `returncode == 2` at four
   sites in `test_rfc_pipeline_integration.py`, and no entry mode can produce it.

The third is what makes this a capability gap rather than an ergonomics complaint: the acceptance
criterion of a shipped sub-phase is unmeetable, not merely awkward.

**Why not a shim.** A thin wrapper mapping flags in and status out would unblock 4a immediately. It
is rejected because the shim would sit between the test rig and the thing under test and mediate
every 4a acceptance result, and 4a exists precisely to establish that the port behaves as specified.
An oracle read through untested glue is not the oracle.

---

## 2. The two halves are different categories

Conflating them is what makes this look larger than it is.

**Reading argv is an effect.** It is an ambient read of process-supplied input, nondeterministic
from the program's standpoint, and it belongs in the capability system alongside the clock.

**Setting a terminal status is not an effect.** Nothing in the program observes it, and the program
does not continue past it. It is how the generated harness reports the terminal state outward. It
belongs in `def-main` as a projection.

Splitting on that line is what keeps the whole boundary inside the auto-discharged verification
fragment (§5).

---

## 3. Half one: argv, and it needs no surface change

**`wasi.proc.args`**, returning the argument vector.

| | |
|---|---|
| Response arm | **`RList [String]`**, existing ([`CodegenHs.hs:458`](../../compiler/src/LLMLL/CodegenHs.hs)), the arm `wasi.fs.list` already uses |
| Effect label | **`ENonDet`**, existing ([`ObligationAssembly.hs:399`](../../compiler/src/LLMLL/ObligationAssembly.hs)), whose documented class is "ambient nondeterministic" |
| Catalog growth | **none.** Six labels before, six after |
| Grammar change | **none** |
| Schema change | **none** |

CAP-PROC's four-part admissibility rule (`compiler-team-roadmap.md`, the CAP-PROC row) is satisfied
with nothing to admit: one `builtinEnv` signature, one `primEffect` clause, one codegen case, and a
response mapping to an **existing** arm. CAP-PROC states that needing a new arm is the signal
EFFECT-RESP's arm set was wrong; no new arm is needed.

**It rides RC-3 unchanged, and this is why no surface moves.** `:init`'s command already supplies
the first response, documented in the generated-code comment at `CodegenHs.hs:1594-1597`. A program
that wants argv issues `wasi.proc.args` as `:init`'s command and receives `RList` as `r0` in the
loop. `:init`'s arity does not move, so every console program shipped to date keeps working.

**Label-sharing follows in-tree precedent, not convenience.** CAP-PROC records `wasi.fs.list`
sharing `EFsRead` rather than widening the closed six-label catalog. Argv shares `ENonDet` on the
same rule. If argv later earns its own label the change is additive and carries no migration.

---

## 4. Half two: the status is a projection, and the harness owns exhaustion

`def-main` gains **one optional field**, `:status`, a total function from the state type to `int`.

```
(def-main
  :mode   console
  :init   driver-init
  :step   driver-step
  :done?  driver-terminal?
  :status driver-exit-status)
```

### 4.1 Semantics

Two terminal paths, and they are **not** treated alike.

Two terminal paths, and they are **not** treated alike. The exhaustion status is gated on whether
`:done?` is **declared**, not on whether it fired.

| `:done?` | Terminal path | Behaviour |
|---|---|---|
| declared | it holds | Apply `:status` to the final state, exit with the result. `:status` absent means exit 0 |
| declared | stdin exhausts first | Exit **70**, fixed and disclosed. **`:status` is not consulted** |
| **not declared** | stdin exhausts | **Exit 0.** Normal termination |

`:status` absent is today's behaviour for every shipped program, so the field is additive.

**The third row is Rev 3, and it exists because Rev 2 broke three shipped programs.** Rev 2 gated on
whether `:done?` *fired*, so a program declaring no `:done?` could never signal completion, every run
of it terminated by exhaustion, and every run exited 70. That is a false alarm on a successful run:
a program with no completion predicate is a stream processor, and for it EOF is not starvation but
the normal end of input. Measured population at v0.14.84: `examples/replay-demo`,
`examples/proof_required_test`, `compiler/test/fixtures/pair_type_test`.

Gating on **declaration** rather than on firing keeps the guarantee exactly where it means anything:
**no program that declares a completion predicate can exit 0 without reaching it.** A program that
declares none has no notion of starvation to be protected from. The correction was found by an
engineer implementing Rev 2 faithfully and reporting the consequence, not by re-reading the spec.

### 4.2 The refutation this section is built on

Rev 1's first form applied `:status` at **both** paths and argued that the driver's own state would
distinguish them, section 4 of the Phase 4 proposal having settled the run state as a sum over
phases. **That is false, and reading section 4 refuted it.** The settled encoding is

```
(| Sequencing int)  (| Delegating (string, int))  (| Waving ((list string), (int, int)))
```

and **none of the three arms is terminal**. A run that completed every stage and a run whose input
ran out both sit in `Sequencing i`. The information that separates them lives in `:done?`, which is
a predicate *outside* the state. A projection from state alone cannot see it.

The claim was a mechanism assertion checked against a document's vocabulary rather than its content,
which is the failure shape DRIVER-LL Phase 4 tracks as risk 3c and has now recorded five times.

### 4.3 Why the fix is better than what it replaced

Handing exhaustion to the harness rather than to `:status` is not a workaround. It is the stronger
design, for a reason that survives the refutation that produced it.

Under the original form, protection from the silent-success bug was **conditional on the caller's
data modelling**: a program that carefully modelled a terminal phase was protected, and a program
with a flat state type kept the bug. Under the revision, **no program that declares `:done?` can
exit 0 on a starved stdin**, whatever its state type. The guarantee stops depending on the caller
getting its data modelling right, and depends instead on the one declaration that defines what
starvation would even mean for that program.

Asking a program to score a state it does not consider terminal is asking it to describe a
condition it has no knowledge of. The harness knows; the program does not.

### 4.4 Refinement predicate

On the declared contract of whatever function `:status` names:

```
{v : int | 0 <= v && v <= 255}
```

### 4.5 Disclosure: 70 is not reserved from the program

A program may also return 70 deliberately from `:status`. A shell therefore cannot distinguish
"exhausted input" from "the program chose 70", only that neither is success. This is stated here so
it lands in the spec text rather than being left for a reader to infer. Making 70 unavailable to
`:status` was considered and rejected: it buys a distinction nothing currently needs, at the cost of
a hole in an otherwise total 0..255 range.

---

## 5. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| `0 <= status <= 255`, **where the program declares it** | contract | **QF-LIA, auto-discharged** by liquid-fixpoint (`LLMLL.md` §5.3.3). Nothing is auto-injected; see edge case 3. **Body-faithful only for a scalar state; see §5.1** |

### 5.1 The range obligation is proved for a scalar state and contract-checked for a real one

*(Added at Rev 4, measured by the DRIVER-LL sub-phase 4a port rather than predicted.)*

`:status` is applied to **the state**, and a real driver's state is composite: §4 of the Phase 4
proposal settles the run state as a pair of a run-common record and a sum over phases. A `def` that
projects a component out of a pair **falls back from body-faithful**, measured on a bare
`[s: (int,int)]` as much as on the driver's own state, while the same arithmetic over `[s: int]` is
body-faithful.

So the range predicate is discharged as a **contract** obligation in both cases, and the function's
**body** is proved to satisfy it only when the state is scalar. For any driver worth writing, the
`0..255` bound is checked at the boundary rather than established from the body.

**This proposal's own fixture cannot exhibit the limit**, which is worth stating plainly: it takes
`[s: int]`, the provable case, so `build_smoke.sh` stage 7 reports `body-faithful: pb-status` and a
reader could conclude the obligation is proved in general. It is not.

The 4a port's response is the pattern to copy rather than a workaround: put the weight on a
**scalar** `exit-code : Status -> int`, which is body-faithful and carries the range plus its
constructor mappings plus a non-vacuity clause, and clamp at the composite boundary. That keeps the
proved core scalar and confines the fallback to one projection.

This is a **fragment limitation, not a defect in this proposal**, and it is the same Σ_auto boundary
`LLMLL.md §5.3.5` draws elsewhere. It is recorded because §5's table would otherwise read as an
unconditional auto-discharge, and because the fixture's green line actively supports that misreading.
| `:status` total over the state type | type | decidable; `checkExhaustive` in [`TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) already enforces coverage for sum-typed scrutinees |
| `wasi.proc.args` carries `ENonDet` | trust | existing label; `EffectSummary`'s join is unchanged and nothing widens to `Unbounded` |

**Nothing escapes to Lean and nothing is nonlinear.** The whole process boundary lands in the
auto-discharged fragment. That is the result that justifies the split in §2: a design that made the
status an effect, or that threaded a terminal reason through a new type, would have paid for it
here.

---

## 6. Edge cases and degenerate inputs

**1. EOF before `:done?` ever fires.** *(Positive witness. This is the bug the proposal closes.)*
Feed a driver two lines when its wave needs four; the driver declares `:done?`, which is what makes
the shortfall observable. **Today:** partial state written, no diagnostic, **exit 0**. **Under this
proposal:** exit **70**, `:status` not consulted. Channel: **harness**, not
contract, and deliberately so per §4.3, since a contract obligation would only bind programs that
already modelled the case. Cite: `CodegenHs.hs:1587-1588`.

**2. `:status` absent.** Every console program shipped to date. Exit 0 on the `:done?` path; exit 70
on exhaustion **only where `:done?` is declared**, and 0 otherwise. Channel: **spec is silent by
design**, and the default is stated rather than left to inference.

**3. `:status` returns 300, or -1.** Rejected at `llmll verify` **if and only if the program declares
the range as a postcondition** on the function `:status` names. *(Corrected at Rev 2, measured
during implementation. Rev 1 said "rejected before codegen" without the conditional, which
contradicted this proposal's own risk 2.)* The compiler injects no postcondition, so an undeclared
`:status` returning 300 truncates to 44, and one returning **256 exits 0 and reports success**.
Channel: **contract, and only where declared**, QF-LIA when it is. The in-scope move is a `tcWarn`
when `:status` names a function carrying no range postcondition, on the same precedent as edge case
6; auto-injecting the predicate is the alternative and is a larger change, since it would put a
clause on a user function the user did not write.

**4. `:done?` holds on the first line.** `:status` applied to a state that consumed exactly one
line. Nothing special; the projection is total. Channel: **type**.

**5. `wasi.proc.args` responds `RErr`.** No argument vector available. `:init` must handle the arm,
as it must for every response-bearing command. Channel: **type**, match exhaustiveness. Note the
adjacency to `MATCH-CATCHALL-1`: a mixed constructor/literal match on the response ships with its
catch-all suppressed, so a program that matches `RList` against a literal arm is in that row's
population.

**6. A program declares `:status` but no `:done?`.** The `:done?` path is unreachable, so the only
exit is exhaustion, which under §4.1's third row is **0**, and `:status` is dead surface. Channel:
**spec is silent (gap, flagged)**. The in-scope move is a `tcWarn`, not an error, on the precedent
that `MATCH-CATCHALL-1`'s population is bounded by programs shipping past a warning.

**7. Empty stdin: `:init` runs, `:step` never does.** *(The degenerate limit of case 1, and it needs
saying separately because effects have already happened.)* The generated harness performs `:init`'s
command **before** the loop's first `hIsEOF` test (`CodegenHs.hs:1598-1602`, then `:1586-1588`). A
program invoked with argv and no stdin therefore acquires its arguments, performs whatever `:init`
commands, and terminates without a single `:step`. **Where `:done?` is declared it exits 70**, which
is correct, since the program never reached a state it considers terminal; it is the one path where
a nonzero status coexists with completed side effects. Where `:done?` is not declared it exits 0,
per §4.1's third row, and the side effects stand as the run's whole output. Channel: **harness**. It
is disclosed rather than prevented: preventing it would mean forbidding effects in `:init`, which
RC-3 depends on.

---

## 7. Strict immutability

Both halves preserve it without special pleading. `wasi.proc.args` is a read returning an immutable
list through the existing response channel; it threads into state exactly as every other response
does. `:status` is a pure function of state performing no `Command`. Neither introduces a reference,
an in-place update, or an aliasing question.

---

## 8. Affected surface

**Compiler** ([`compiler/src/LLMLL/`](../../compiler/src/LLMLL/))

- `TypeCheck.hs` — one `builtinEnv` signature for `wasi.proc.args`; the `def-main` field check
  accepts `:status` and checks its type against the state type.
- `ObligationAssembly.hs` — one `primEffect` clause near the label catalog at `:399`, mapping
  `wasi.proc.args` to `ENonDet`.
- `CodegenHs.hs` — one builtin case for `wasi.proc.args`; the two terminal paths in `emitMainBody`,
  the fall-through after `loop` at `:1584` and `settle` at `:1653`, gain the status application and
  the exhaustion exit.
- `Syntax.hs` — `SDefMain` gains `defMainStatus :: Maybe Expr`.
- `Parser.hs` and `ParserJSON.hs` — one optional field each.

**Schema** — [`docs/llmll-ast.schema.json`](../llmll-ast.schema.json): `def-main` gains optional
`status`; schema-version bump.

**Spec** — `LLMLL.md` §9 (functions and IO model) and §13 (builtins). Doc-lead's slot.

**Roadmap** — a row, on R-14's promotion rule: an R-item becomes a row the moment something is
blocked on it, which is how R-11 became `HTTP-GET-1`. Sub-phase 4a is blocked on it. Doc-lead's slot.

**Driver** — [`tools/llmll-driver/`](../../tools/llmll-driver/): sub-phase 4a consumes it and is
otherwise unchanged; its plan holds.

---

## 9. Risks

1. **`:status` is a second thing that looks like a termination control**, alongside `:done?`.
   *Scope.* It adds no termination path; it labels the two that already exist. Complicates the spec
   text, does not block.
2. **Exit-status range is a platform fact stated as a language refinement.** *Spec-drift.* POSIX
   truncates to the low 8 bits, and `{v : int | 0 <= v && v <= 255}` encodes that as if it were an
   LLMLL fact. Complicates. The alternative, leaving it unconstrained and letting the platform
   truncate silently, is worse: a `:status` returning 256 would exit 0 and report success.
3. **70 is not reserved.** *Verification-ergonomics.* §4.5. Only matters to a shell trying to
   distinguish exhaustion from a deliberate 70; it can always distinguish both from success.
4. **This is the fifth measurement of risk 3c in the DRIVER-LL line.** *Spec-drift.* Phase 4's
   §12:1102 asserted 4a needed no compiler change and an engineer measured otherwise; this
   proposal's own §4.2 claim was refuted the same way inside a single drafting turn. The pattern
   holds: a mechanism claim resting on a document's vocabulary rather than its content. Blocks
   nothing, and is recorded because the count is the finding.

---

## 10. Professor round: not taken, and why

Two questions were drafted and both were withdrawn before routing.

**"Is exit-status-as-terminal-state-projection a known framing, and does it break when the terminal
state is reached by exhaustion rather than acceptance?"** **Withdrawn: it was not a literature
question.** It was a checkable claim about §4 of the Phase 4 proposal, and checking it took one read
and refuted it (§4.2). Routing it outward would have spent a round to be told what the repository
already contained.

**"Is reading argv properly the same effect class as reading a clock?"** **Withdrawn: settled by
in-tree precedent.** CAP-PROC records `wasi.fs.list` sharing `EFsRead` rather than widening the
closed catalog, and the same rule gives argv `ENonDet`. A dedicated label is additive later and
carries no migration cost.

**The question that would be worth an outside read**, if one is wanted, is neither of those: whether
a fixed reserved status for harness-level termination is the right trade against threading a
terminal reason into `:status`. That is the one place this design trades expressiveness for a
universal guarantee (§4.3), and it is the only decision here whose alternative is not obviously
worse.
