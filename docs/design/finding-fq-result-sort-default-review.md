---
name: finding-fq-result-sort-default-review
title: "Professor review of finding-fq-result-sort-default.md, Rev 0 and Rev 1"
status: "Two rounds, standalone review; not folded"
date: 2026-07-28
author: professor
consumers: [user, language-team, compiler-engineer, documentation-lead]
---

# Professor review of `finding-fq-result-sort-default.md`, Rev 0 and Rev 1

Two rounds against FQ-RESULT-SORT-1 (routed as FQ-BOOL-SORT-1). Round 1 reviewed Rev 0,
which scoped the fix to the emitter. Round 2 reviewed Rev 1, which widened it into the type
environment. Findings are numbered continuously so downstream citation is unambiguous; the
round is marked on each. Dispositions in Rev 2 are recorded at the end.

## Restatement

The proposal fixes a sort default: the contract channel derives the sort of the `result`
binder from the optional `-> RetType` annotation and falls back to `FQInt` when absent,
while the type channel derives it from the synthesized body type
([`TypeCheck.hs:992`](../../compiler/src/LLMLL/TypeCheck.hs), `fromMaybe bodyType mRet`).
Where the two disagree, the emitted `.fq` is ill-sorted and liquid-fixpoint crashes. The
direction is right in both revisions. The disagreements are about how wide the trigger set
is, what actually contains the defect, and how far into the compiler the corrected
derivation should reach.

## Context located

1. [`FixpointIR.hs:205-211`](../../compiler/src/LLMLL/FixpointIR.hs): `FQFile` has five
   fields and no well-formedness-constraint slot. `FQKVar` exists in the predicate type at
   `:128` but nothing constructs one; no `wf` block is emitted anywhere in `compiler/src/`.
2. [`FixpointEmit.hs:220`](../../compiler/src/LLMLL/FixpointEmit.hs):
   `type ContractEnv = Map Name ([(Name, Type)], Contract, Maybe Type)`. The third slot is
   the callee return type and it is a `Maybe`.
3. [`Module.hs:305-318`](../../compiler/src/LLMLL/Module.hs): `extractContracts` stores the
   raw `mRet` into `meContracts`. `synthRet` is not on this path.
4. `Module.hs:267-278`: `toExport` computes `fromMaybe (TVar "?") mRet`. The module
   interface has no representation for an unannotated function's return type.
5. `Module.hs:189-190`: `typeCheckWithCache` runs over the module's statements, and
   `buildModuleEnv modPath stmts baseEnv` on the next line builds the interface from
   `stmts`, not from the result.
6. `TypeCheck.hs:761-764, 827-830`: `checkStatements` is a two-pass scheme. Pass 1 is
   `mapMaybe collectTopLevel stmts`, commented "First pass: collect all top-level function
   and type names"; pass 2 checks each body. `collectTopLevel`'s own comment at `:832` says
   "for forward references."
7. `TypeCheck.hs:2090-2091`: `compatibleWith (TVar _) _ = True` and its symmetric case,
   documented at `:71`.
8. `TypeCheck.hs:1290, 1319, 1339, 1346, 1396, 1509, 1535, 1544, 1557, 1611`: ten further
   `TVar "?"` sites. `:1396` is commented "wildcard: don't inject false type mismatch
   downstream"; `:1535` says "wildcard: matches convention at line 844", naming
   `collectTopLevel` as the convention's origin.
9. `TypeCheck.hs:655-663`: `typeCheck :: GrammarMode -> TypeEnv -> [Statement] ->
   DiagnosticReport`, with `let (_, diags) = runTC gm env (checkStatements stmts)`. The
   value component is discarded at the binding site. `runTC` is at `:572-575`;
   `checkStatements :: [Statement] -> TC ()` at `:761`.
10. `TypeCheck.hs:1257-1275`: `inferExpr (EIf …)` returns `thenType` on branch agreement
    (`:1270-1271`).
11. `Module.hs:120, 143, 148-150`: post-order DFS load with cycle detection. The module
    dependency graph is acyclic by construction.
12. [`LLMLL.md`](../../LLMLL.md) §3.4.6: local type inference (Pierce-Turner) over a
    Damas-Milner core, with **no global unification** stated as a design commitment.
13. `docs/design/` grepped for the topic before Round 1: no in-flight draft existed. The
    proposal was from scratch.

All empirical results below are against `compiler/src/` at `b689340` (2026-07-25), with the
binary reporting `0.14.67` at the time of the runs. `git log b689340..HEAD -- compiler/src/`
is empty, so the measured behavior is the behavior at HEAD; the v0.14.68 through v0.14.71
releases moved the version banner in `compiler/package.yaml` without touching the compiler.

## Findings

### F-1 (MAJOR, Round 1): the containment argument is misattributed and the trigger set is under-sampled

Rev 0 attributed fail-closed behavior to the type channel, citing that `(>= result 0)` over
a bool body is rejected at typecheck. That is not the operative mechanism. Four
semantically non-trivial boolean posts, in which `result` appears in a boolean-eliminating
position rather than as an `=` operand:

| post | pre | expected | annotated | unannotated |
|---|---|---|---|---|
| `(and result (> n 0))` | `(> n 0)` | refuted | REFUTED | **CRASH** |
| `(and result (> n 0))` | `(> n 6)` | safe | SAFE | **CRASH** |
| `(or result (<= n 5))` | `(> n 0)` | safe | SAFE | **CRASH** |
| `(not result)` | `(> n 0)` | refuted | REFUTED | **CRASH** |

All four bodies are `(> n 5)`, the computed-bool shape both the roadmap row and Rev 0
treated as the quiet control. Rev 0's five non-crashing cells were all of the single shape
`(= result e)`, which is the only shape that survives. Enumerating the quiet corner of the
space is the failure mode the language-team's own edge-case discipline names.
**Bite: complicates.** It does not change the fix; it changes the fixture matrix and it
removes Rev 0's basis for its edge case 7.

### F-2 (MAJOR, Round 1): correct verdicts in the surviving window rest on an unrecorded liquid-fixpoint behavior

The window where `result : int` does not crash is narrow: `result` occurs in the post only
as an operand of `=`, and the body reflects to a comparison-headed predicate. Two probes
inside it:

- body `(> n 5)`, post `(= result (> n 4))`: refuted in both forms. Correct, `n = 5`
  separates them.
- body `(> n 5)`, post `(= result (>= n 6))`: **SAFE in both forms**. Correct, and
  non-trivial: it requires deciding that two syntactically distinct comparisons are
  equivalent over the integers.

The second establishes that liquid-fixpoint elaborates the reflection equation at Bool
while the binder is declared `{ v : int | true }`, recovering the intended sort from the
equation's operands. `LLMLL.md §5.3.3` grounds `Σ_auto` decidability on the emitted VC
being the intended VC; here they differ and the gap is closed by undocumented behavior of a
pinned external tool. The project frames its trust boundary in
[`verification-debate.md`](verification-debate.md) and this dependency does not appear
there. **Bite: does not block; the proposal removes it by construction.** It should be
recorded as a resolved-by-this-change item rather than passed over, because the same
recovery is what makes the current corpus look healthy.

### F-3 (MAJOR, Round 1): the module interface has no representation for an unannotated return, and "Schema delta: none" was overstated

`Module.hs:305-318` stores raw `mRet`; `Module.hs:273-275` exports `fromMaybe (TVar "?")
mRet`. Two consequences Rev 0 did not address. The shipped R1 fix (`synthRet`,
`FixpointEmit.hs:265-267`) sits on `buildContractEnvWith`'s local path and is not applied to
`extractContracts`, so it is intra-module by construction. And `LLMLL.md §9:1601` (do-step
callees need an explicit return annotation) is plausibly the same `TVar "?"` root surfacing
in a third place, which would make this the third prior local patch rather than the second.
One attempted cross-module crashing witness (an unannotated bool-returning callee imported
and consumed as an `if` guard) returned SAFE on both the cross-module and intra-module
forms, so no live defect at the boundary was demonstrated; the constraint on the fix is
readable in the code regardless. **Bite: complicates.**

### F-4 (MAJOR, Round 1): fail-closed is not fail-visible

Rev 0's FALLBACK-RESIDUAL converts the crash into `addBodyFallback`, the post reports
`asserted`, and plain `llmll verify` prints `✅ SAFE`. Fail-closed is a property of the
verdict lattice; whether the operator learns that something was not checked is a separate
property, and only the second is at risk. Rev 0 treated this as a fixture requirement. It
is a design decision: a fallback caused by an *unsortable synthesized* return is
distinguishable from one caused by a declared unsortable return, and CONTRACT-READ-LINT
already establishes the non-blocking `diagKind` warning as in-scope machinery.
**Bite: complicates.** Shipping the sort fix without the diagnostic trades a defect that
announces itself for one that does not.

### F-5 (MINOR, Round 1): the qualifier block is inert; the `:765` "second symptom" claim is cosmetic

`FQFile` has no well-formedness field and nothing constructs an `FQKVar`. liquid-fixpoint
consumes qualifiers only to solve KVars; with none emitted, the qualifier block cannot
influence a verdict, and empirically a mis-sorted `Q_f_post_70(v : int, result : int, n :
int)` sits in a file that returns a correct SAFE. Rev 0's D2 elevated `:765` to "a real
second symptom" and exhibited it in its four-line diff. Fix it for hygiene; an acceptance
criterion asserting on the qualifier's sort would be asserting on dead output.
**Bite: only matters at scale**, as wasted engineer effort.

### F-6 (MINOR, Round 1): "introduces no new proof obligations" is false in letter

Configurations that crash today emit no constraints; after the fix they emit constraints
that did not previously exist. The defensible statement is that the change introduces no new
obligation *class* and moves nothing across the `Σ_auto` boundary. The verification-mapping
section is the one downstream readers copy verbatim into the CHANGELOG. **Bite: cosmetic.**

### F-7 (BLOCKER, Round 2): the `collectTopLevel` row makes pass 1 depend on pass 2

Rev 1 generalized the fix to a total `τ_ret` read by three consumers, including
`collectTopLevel`. That row does not work. `checkStatements` builds the top-level
environment before checking any body (`:761-764`), which is what makes forward references
work. Under Rev 1's row 1, `collectTopLevel` needs `τ_body`, which only pass 2 computes.
Three programs that verify today are the witnesses:

| | shape | today |
|---|---|---|
| T1 | `def-shell caller … (if (is-big n) 1 0)` followed by `(def is-big [n: int] (> n 5))` | SAFE |
| T2 | `(def-shell countdown [n: int] (if (> n 0) (countdown (- n 1)) true))` | SAFE |
| T3 | mutually recursive unannotated `even?` / `odd?` | SAFE |

T1 requires `is-big`'s body type while checking `caller`, and `is-big` is defined
afterwards. T2 requires `τ_ret(countdown)` in terms of itself. T3 requires a mutual
fixpoint. All three pass today because `TVar "?"` is a wildcard under `compatibleWith`
(`:2090-2091`).

The machinery that solves this is standard: dependency analysis into strongly-connected
components, explicitly-typed bindings segregated so they are usable at their declared type
inside a group, implicitly-typed bindings in an SCC typed together against monomorphic
assumptions and generalized afterwards. Mark P. Jones, *Typing Haskell in Haskell* (Haskell
Workshop 1999) §11 is the reference implementation, and it is why the Haskell report
specifies declaration groups rather than a flat environment; the original treatment is
Milner (1978) and Damas-Milner (POPL 1982), already cited by LLMLL at `LLMLL.md §3.4.6`.

That machinery *is* global unification over binding groups, and `LLMLL.md §3.4.6` states the
checker has no global unification as a design commitment. Row 1 therefore does not land
inside LLMLL's existing surface. **Bite: blocks row 1.** It does not touch the
contract-channel or post-typing rows.

### F-8 (MAJOR, Round 2): `TVar "?"` is a documented wildcard convention, not junk

Rev 1 called it "a junk value" whose overloading "let the first meaning pass unexamined,"
and proposed retiring it as the representation of an unannotated return. Eleven sites use
it; `:1535` explicitly cross-references `collectTopLevel` as the convention's origin; `:71`
documents the `compatibleWith` mechanism; `:1396` and `:1611` use it to stop error cascades.
Its function in `collectTopLevel` is to decouple the two passes, the same decoupling that
lets `expectPairType` recover at `:1611` without cascading. Under-documented, not
accidental. This matters because Rev 1 proposed to carry the characterization into
`LLMLL.md §4.1`, and a spec sentence retiring a convention the checker relies on in eleven
places would be a durable error. **Bite: complicates**, and it is the sentence most likely
to survive into the spec unexamined.

### F-9 (MAJOR, Round 2): "thread `report` into `buildModuleEnv`, one line" understates the change

`typeCheck` and `typeCheckWithCache` return `DiagnosticReport` (`:655`, `:673`), and
`runTC`'s value component is discarded at the binding (`:657`). There are no synthesized
types in `report` to thread. Extracting them requires `checkStatements` to accumulate a
name-to-type map, `runTC`'s result to carry it, `typeCheck`'s signature to change, and every
caller to be updated. Rev 1 used the "one line" claim to dissolve F-3, and F-3 is only
partly dissolved. The favorable half stands: inference does already run on the import path
at `Module.hs:189`, so no second pass and no persisted-format change is required.
**Bite: complicates.** The engineer should not be handed "one line."

### F-10 (MAJOR, Round 2): retiring the `do`-step carve-out does not follow

Rev 1's edge case 6 claimed the change would retire `LLMLL.md §9:1601`. That requires the
call-site environment to carry the callee's synthesized return type, which is row 1. With
row 1 withdrawn, `expectPairType` (`:1604-1610`) still receives `TVar "?"` and still emits
`do-step-type-error`. Rev 1's affected-surface item 13 proposed retiring the spec carve-out
on this basis. **Bite: blocks that one edge case**, nothing else.

### F-11 (MINOR, Round 2): scope the trust-boundary discharge to the `result` binder

Rev 1 recorded the F-2 dependency as "removed by construction." The change removes it for
`result`, which is where it was demonstrated. It does not establish that every emitted `.fq`
is well-sorted, and other `FQInt` defaults remain in the emitter (the standalone
pre-constraint path builds `FQReft "v" FQInt` on both sides). Overclaiming in the direction
that made the original defect invisible is the wrong direction to overclaim.
**Bite: cosmetic**, but it is a trust-boundary sentence and those get quoted.

## Recommendation

### Round 1: adopt Rule R, reject Rule S, reject Rule A on structural grounds

Rev 0 argued for threading the checker's synthesized type (Rule R) over an emitter-local
syntactic re-derivation (Rule S) from an internal signal: two prior local patches at the same
root (`synthRet` at v0.14.14 for bool, the LEVER-A2.1 guard at `:1143` for arrays),
predicting a third. Good evidence, and we converge on the conclusion from different reading
paths. The external argument is stronger.

This defect class is architecturally unrepresentable in the system LLMLL models itself on.
Liquid Haskell generates constraints from GHC **Core**, not surface Haskell: every binder in
a `CoreExpr` carries an intrinsic `Type` and refinement sorts are computed from it, never
from a user signature (Vazou, Seidel, Jhala, Vytiniotis, Peyton Jones, *Refinement Types for
Haskell*, ICFP 2014; the constraint generator is
`Language.Haskell.Liquid.Constraint.Generate`). There is no phase at which a binder lacks a
type, so a "missing signature implies default sort" path could not be written. Dafny is the
closer analogue on surface, sharing explicit pre/post contracts and an SMT backend: its
Boogie translation runs after the resolver has populated `Expression.Type` on every node and
converts *that* type rather than consulting the declaration. Both place the sort derivation
on the elaborated artifact.

The general statement is the typed-intermediate-language argument: downstream phases need
types, reconstructing them later is expensive and error-prone, and the fix is to make later
phases consume a typed IR (Tarditi, Morrisett, Cheng, Stone, Harper, Lee, *TIL: A
Type-Directed Optimizing Compiler for ML*, PLDI 1996; carried further in Morrisett, Walker,
Crary, Glew, *From System F to Typed Assembly Language*, TOPLAS 1999). LLMLL's emitter is a
downstream phase that needs types, and `LLMLL.md §3.4.6` establishes that the checker
computes exactly the type it needs. Rule S asks a later phase to re-derive a quantity an
earlier phase already derived.

**Reject Rule A (mandate the annotation) on stronger grounds than agent-retry cost.** That
argument is contingent and priceable. The structural argument is that Rule A states an
annotation obligation in terms of a backend sort table rather than in terms of the mode
judgment, inverting a premise LLMLL has accepted. Pierce and Turner's local type inference,
cited at `LLMLL.md §3.4.6`, exists to characterize annotation positions structurally and
independently of any downstream consumer; Dunfield and Krishnaswami (*Bidirectional Typing*,
ACM Computing Surveys 54(5), 2021) give the modern statement that a well-designed
bidirectional discipline has a characterizable annotation rule stated in terms of the mode
judgment. "Annotate when the return type is not `int` and a contract is present" is not
stateable in the mode judgment; it is the verifier's sort table leaking into the typing
rules, and it would shift again with every future sort extension.

The same survey gives the crisp diagnosis of the bug. Bidirectional typing has two modes,
synthesize and check. `maybe FQInt sortA1 mRet` is neither: it is checking against a guess,
and a default is not a mode.

### Round 2: withdraw row 1; the axis is in-band versus downstream

Rev 1's error was not intra-module versus cross-module. It is **in-band versus downstream
relative to inference**. `collectTopLevel` constructs the environment inference consumes, so
feeding it synthesized types closes a loop (F-7). `FixpointEmit` and `extractContracts` run
after `checkStatements` completes, so `τ_body` is determined and no loop exists.
`toExport` is downstream relative to the *exporting* module, because `Module.hs:189` fully
type-checks a module before `:190` builds its environment and the module graph is acyclic.

Restate the rule as the *verification-facing* effective return type, consumed by the contract
channel and the verifier-facing contract environment, with the type environment explicitly
out of scope and `TVar "?"` retained there. That rule is stateable without touching
`LLMLL.md §3.4.6`, and it fixes every crash in the measured trigger set: all of them are
contract-channel constraints and none requires the call-site environment to know anything.

Add T1, T2, and T3 as regression fixtures. They are the cheapest guard against a future
revision re-widening into row 1, and they pass today.

## Open questions for the language-team

Both were posed and both were answered in Rev 2; recorded here for the fold.

**Q1 (Round 1). Is `LLMLL.md §9:1601` the same root?** *Answered: yes, and intra-module.*
`collectTopLevel` (`:838-850`) registers an unannotated return as `TVar "?"`;
`expectPairType` (`:1604-1610`) requires a `TPair` and rejects anything else. Derived from
the code; no runtime witness was built, since a valid `do` block needs `(S, Command)`
scaffolding. This makes the defect a three-instance pattern, and it is why Rev 1 restated the
root as `TVar "?"`.

**Q2 (Round 2). What does the rule yield when body inference failed and recovered with a
wildcard?** *Answered: side condition HOLE-RET.* When `isHoleVar τ_ret`
(`TypeCheck.hs:316-318`), route to `addBodyFallback` and emit the warning; do not emit at
`FQInt`. The guard must fire before `sortA1`, because `sortA1 (TVar "?")` already has a
defined answer (`typeToSortA:2419` falls through to `typeToSort _ = FQInt` at `:2393`) and
that answer is the original defect. Rev 2 additionally identified a third input reaching the
guard that neither round anticipated: a recursive unannotated definition with the recursive
call in **then** position synthesizes to `TVar "?"`, because `inferExpr (EIf …)` returns
`thenType` (`:1270-1271`). The branch-swapped sibling synthesizes to `TBool` and is fixed.
Both crash today, so coverage of the recursive class depends on branch position, and that
residual is now stated in the proposal rather than discovered later.

## Disposition in Rev 2

F-1 through F-11 were all accepted. Rev 0 to Rev 1 folded F-1 through F-6; Rev 1 to Rev 2
folded F-7 through F-11 and withdrew the type-environment row.

One place the language-team went further than recommended, correctly. Round 2 placed
`toExport` in the safe column, cleared on acyclicity. Rev 2 leaves it unchanged anyway, on a
**strictness** argument the review did not make: `meExports` seeds the importing module's
`TypeEnv` (`TypeCheck.hs:182, 745`), and because `compatibleWith (TVar _) _ = True` every use
of an imported unannotated function is currently accepted, so narrowing the wildcard to a
concrete type makes the importer's checker strictly stronger and can reject programs that
type-check today. The acyclicity argument is correct and insufficient. The narrowing costs
the proposal nothing, since the verifier reads `meContracts` rather than `meExports`
(`Syntax.hs:905, 911`; consumers at `ObligationAssembly.hs:851` and `FixpointEmit.hs:220,
323`). This is a scope boundary, not a soundness disagreement.
