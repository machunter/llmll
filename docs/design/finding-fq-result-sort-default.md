---
name: finding-fq-result-sort-default
title: "FQ-RESULT-SORT-1: the `result` binder's sort defaults to `int` when the return type is unannotated"
status: "OPEN; Rev 2 settled 2026-07-28; found 2026-07-27 against compiler/src/ at b689340, unchanged through v0.14.71 (routed as FQ-BOOL-SORT-1)"
severity: "fail-closed crash, never a false SAFE; one scoped trust-boundary item"
found_by: main-agent, while probing RFC 4648 row A1
consumers: [compiler-engineer, documentation-lead, language-team, user]
---

# FQ-RESULT-SORT-1: the `result` binder's sort defaults to `int` when the return type is unannotated

**One line.** The contract channel derives the sort of the `result` binder from the
*optional* `-> RetType` annotation and falls back to `FQInt` when it is absent, while the
type channel derives it from the synthesized body type. When the two disagree, the emitted
`.fq` is ill-sorted and liquid-fixpoint crashes.

The workaround is to annotate the return type. The identical function with `-> bool`
emits `bind 1 result : { v : bool | true }` and returns a normal verdict.

This was routed as **FQ-BOOL-SORT-1**. That tag is wrong in three dimensions: the defect
is not bool-specific, not literal-body-specific, and its crashing site is not the one the
original diagnosis named. `FQ-BOOL-SORT-1` is retained as an alias so the RFC 4648
provenance link survives.

## Reproduction

Six lines, no imports:

```lisp
(def f [n: int] (pre (> n 0)) (post (not (= n 10))) true)
```

```
ERROR: liquid-fixpoint: elaborate solver elabBE 2 "VV##0"
  {VV##0 : int | [(VV##0 = true); (n > 0)]} failed on: VV##0 == true && n > 0
  with error  The sort bool is not numeric
  because Cannot unify int with bool in expression: VV##0 == true
```

The emitted constraint names the defect directly:

```
bind 1 result : { v : int | true }
constraint:
  lhs { result : int | (n > 0) && (result = true) }
  rhs { result : int | (not (n = 10)) }
```

### Measured trigger set

Twenty-four configurations run against `compiler/src/` at `b689340`, which is unchanged
from v0.14.67 through v0.14.71 (the version string lives in `compiler/package.yaml`, not
under `compiler/src/`, so the intervening releases moved the banner and not the compiler).
The binary reported `0.14.67` when the runs were made. The defect fires in ten, across
three return types. Every crash exits 1 and writes no `.verified.json`.

| Configuration | Unannotated | Annotated control |
|---|---|---|
| body `true` | **CRASH** | verdict |
| body `false` | **CRASH** | verdict |
| body `true`, `(post (= result true))` | **CRASH** | verdict |
| body `(if (> n 5) true false)` | **CRASH** | verdict |
| body `"x"` | **CRASH** (`The sort Str is not numeric`) | SAFE |
| body `(pair n n)`, `(post (= (first result) n))` | **CRASH** (`The sort (Pair2 …) is not numeric`) | verdict |
| `(post (and result (> n 0)))`, body `(> n 5)` | **CRASH** | SAFE / REFUTED per pre |
| `(post (or result (<= n 5)))`, body `(> n 5)` | **CRASH** | SAFE |
| `(post (not result))`, body `(> n 5)` | **CRASH** | REFUTED |
| recursive bool with a contract (both branch positions) | **CRASH** | REFUTED |
| `(post (= result e))`, body a comparison | agrees with control | agrees |
| no `post` clause | `body-fallback`, SAFE | same |
| `Result` return | `asserted` via fallback | same |

Two shapes survive, and knowing why matters for the fix. The `result : int` binder
elaborates without error only when every occurrence of `result` is an operand of `=` whose
other side elaborates at a compatible sort. Any *boolean-eliminating* use of `result` in
the post (`and`, `or`, `not`) is ill-sorted on its own and crashes independently of how the
body reflects. A boolean literal, a string literal, or a constructor term on the right of
the reflection equation crashes for the same reason.

## Root cause

`TypeCheck.checkStatement` synthesizes the body type and binds `result` at
`fromMaybe bodyType mRet`
([`TypeCheck.hs:967-979, 992`](../../compiler/src/LLMLL/TypeCheck.hs); the same expression
recurs at `:912`, `:946`, `:1025` for the four definition forms). That is the correct rule
and the type channel already follows it: an int-shaped post over a bool body is rejected
before the emitter runs (`type mismatch in '>=': expected int, got bool`).

The contract channel does not. `FixpointEmit` computes `maybe FQInt sortA1 mRet` at five
sites: `:765` (qualifier sort map), `:802` (legacy post path), `:1143` (array-path guard),
`:1156` (`retSort`, the body-VC path), `:1184` (`mapRetMode`). The crash comes from `:1156`,
consumed at `:1207` and `:1220-1221`. Two further sites hardcode `FQReft "result" FQInt`
at `:1101-1102` in the map-return-chain branch.

The two admissibility guards whose purpose is to force a clean fallback instead of a
crashing constraint are keyed on the same optional annotation and therefore **fail open on
exactly the input that needs them**: `sigPairUnsafe` computes `maybe False pairUnsafe mRet`
([`FixpointEmit.hs:2453-2458`](../../compiler/src/LLMLL/FixpointEmit.hs)) and
`resultReturnUnsafe` matches `case resolveAliasTy am <$> mRet of … _ -> False` (`:2467-2479`).
That is why the pair case crashes rather than falling back.

### The same root has been patched locally twice before

`synthRet` / `bodyIsBoolean` (`FixpointEmit.hs:265-287`, R1 bool-ret-synth, v0.14.14)
synthesizes `Just TBool` for an annotation-less, post-less function with a syntactically
boolean body, so that a caller's `calleeRetSort` sorts the callee's opaque result binder at
Bool. It is scoped by `Nothing <- contractPost contract`, which excludes the crashing
configuration by construction, and it sits on the local `buildContractEnvWith` path only.

The LEVER-A2.1 sort guard at `:1143` is the second: its own comment says "retSort
defaulting to FQInt," and it routes an array-sorted result away from an ill-sorted
`result = rVar`.

Each patch fixed one sort and left the others. A third partial re-derivation would fix
bool, string, and pair and leave whatever sort is added next. The sort is a derived
quantity and it should have one derivation site.

## What is *not* the cause

Two claims made during analysis were withdrawn after checking.

**The mis-sorted qualifier at `:765` is inert.** `FQFile`
([`FixpointIR.hs:205-211`](../../compiler/src/LLMLL/FixpointIR.hs)) has no well-formedness
constraint field, `FQKVar` exists in the predicate type at `:128` but nothing constructs
one, and no `wf` block is emitted anywhere in `compiler/src/`. liquid-fixpoint consumes
qualifiers only to solve KVars. The unannotated form does emit
`qualif Q_f_post_70(v : int, result : int, n : int)` where the annotated form emits
`result : bool`, and that difference cannot reach a verdict. Fix it for hygiene; do not
write an acceptance criterion against it.

**The type channel is not what contains the defect.** It closes one shape (an int-shaped
post over a non-int result). The rest is closed by the crash itself: `result : int` is
ill-sorted under any boolean elimination. Containment is a property of the contract
channel, not the type channel.

## Blast radius: zero in tree

A structural census over `examples/` and `compiler/test/fixtures/` finds 29 unannotated
contracted definition heads. Every one returns `int`, so the `FQInt` default happens to be
correct for all of them. The census is syntactic (a regex over definition heads plus a
nearby `post` clause), so treat it as an over-approximation of the population and a lower
bound on confidence. No bool-, string-, or pair-returning contracted definition without an
annotation exists in tree, which is consistent with this never having been hit.

Because the defect fails closed (exit 1, a crash, never a false SAFE), no prior verdict is
affected.

## The rule `[CT]`

### RESULT-SORT

Define the *verification-facing* effective return type:

```
    Γ, x̄:τ̄ ⊢ body ⇒ τ_body
    ────────────────────────────────  (Eff-Ret)
    τ_ret(f)  =  mRet(f) ▷ τ_body
```

where `▷` is `fromMaybe`. Two consumers read it, and two do not. The axis is **in-band
versus downstream relative to inference**.

| Consumer | Kind | Today | Under RESULT-SORT |
|---|---|---|---|
| contract channel (`FixpointEmit.hs:765, 802, 1143, 1156, 1184`) | verifier | `maybe FQInt sortA1 mRet` | `sortA1 τ_ret` |
| `meContracts` third slot (`Syntax.hs:911`, built `Module.hs:305-318`, read `FixpointEmit.hs:220, 323` and `ObligationAssembly.hs:851`) | verifier | raw `mRet` | `τ_ret` |
| `collectTopLevel` (`TypeCheck.hs:838-850`) | type env | `fromMaybe (TVar "?") mRet` | **unchanged** |
| `meExports` via `toExport` (`Module.hs:267-278`) | type env | `fromMaybe (TVar "?") mRet` | **unchanged** |

The type-environment rows stay put for two independent reasons.

`checkStatements` is a two-pass scheme: pass 1 is `mapMaybe collectTopLevel stmts`
(`TypeCheck.hs:761-764`), pass 2 checks each body (`:827-830`). `collectTopLevel`'s comment
at `:832` says "for forward references." Feeding it `τ_body` makes pass 1 depend on pass 2.
The programs T1 through T3 below are the witnesses that the loop is not hypothetical, and
breaking it requires dependency analysis into strongly-connected components with recursive
groups typed together, which is global unification over binding groups. `LLMLL.md §3.4.6`
states the checker has no global unification as a design commitment.

Separately, `meExports` seeds the *importing* module's `TypeEnv`
(`TypeCheck.hs:182, 745`). Because `compatibleWith (TVar _) _ = True` (`:2090-2091`), every
use of an imported unannotated function is currently accepted; narrowing the wildcard to a
concrete type makes the importer's checker strictly stronger and can reject programs that
type-check today. The module graph is acyclic (`Module.hs:120, 148-150`) so there is no
circularity here, but the strictness change is reason enough on its own. The verifier reads
`meContracts`, not `meExports`, so the fix does not need this row.

### `TVar "?"` is retained

It is a documented wildcard convention, not an accident. Eleven sites use it;
`TypeCheck.hs:1535` names `collectTopLevel` as the convention's origin; `:71` documents the
`compatibleWith` mechanism; `:1396` and `:1611` use it to stop error cascades. Its function
in `collectTopLevel` is to decouple the two passes. Under-documented, not junk.

### HOLE-RET (side condition on Eff-Ret)

`τ_ret` is total into `Type` but not into *sortable* types. When `isHoleVar τ_ret`
(`TypeCheck.hs:316-318`), the emitter routes to `addBodyFallback` and emits the
`unsortable-synthesized-return` warning. It does **not** emit at `FQInt`.

The guard must fire *before* the sort is computed. `sortA1 (TVar "?")` has a defined answer
today: `typeToSortA` falls through at `FixpointEmit.hs:2419` to `typeToSort _ = FQInt`
(`:2393`, commented "conservative default"). That answer is the original defect. A guard
placed downstream of `sortA1` sees a legitimate int and does nothing.

Three inputs reach HOLE-RET: a `?hole` body (which has no synthesizable type, and is why
the DEF-RET annotation exists), a recovered inference failure (`TypeCheck.hs:1396, 1509,
1544`), and the recursive residual described below.

### GUARD-EFFECTIVE

`sigPairUnsafe`, `resultReturnUnsafe`, and the array/map gates evaluate against `τ_ret`
rather than `mRet`, so a guard whose purpose is to force a fallback stops being disabled by
the absence it should react to.

### FALLBACK-VISIBLE

When the emitter routes to `addBodyFallback` because the return was *synthesized* and
unsortable, it emits a non-blocking warning with `diagKind = "unsortable-synthesized-return"`.

A declared unsortable return is an author's choice and legible in the source; a synthesized
one is invisible. Without the warning this change replaces a loud exit-1 with a green
`✅ SAFE` and a silently unproven post, because plain `llmll verify` prints SAFE on the
fallback path today. Fail-closed is a property of the verdict lattice; whether the operator
learns that something was not checked is a separate property, and only the second one is at
risk here. `--strict-verified-core` already rejects the fallback and needs nothing.

## What the rule does not fix

RESULT-SORT does not cover every member of the measured trigger set. A recursive
unannotated definition with the recursive call in **then** position synthesizes to
`TVar "?"`:

```lisp
;; T4a: crashes today; still would, without HOLE-RET
(def-shell countdown [n: int] (pre (>= n 0)) (post (not (= n 99)))
  (if (> n 0) (countdown (- n 1)) true))
```

`collectTopLevel` registers `countdown : int -> TVar "?"`; the recursive call synthesizes to
that wildcard; `inferExpr (EIf …)` returns `thenType` on branch agreement
(`TypeCheck.hs:1270-1271`); `compatibleWith` accepts the `TBool` else-branch. So
`τ_body = TVar "?"` and `sortA1` yields `FQInt`.

The sibling with the branches swapped (`(if (= n 0) true (countdown (- n 1)))`) has
`thenType = TBool`, so `τ_ret = bool` and it *is* fixed. Both crash today. Coverage of the
recursive class therefore depends on which branch holds the recursive call.

Under HOLE-RET, T4a becomes a visible non-verification (`asserted` post, warning, exit 0)
rather than a crash. That is the intended outcome and it should be stated in the spec
rather than left as an implementation detail, because it is the same absence-of-information
case that produced the original defect.

## Regression witnesses that must keep passing

These three verify today and are the guard against a future revision re-widening the rule
into the type environment. They cost nothing to add now.

| | shape | today |
|---|---|---|
| T1 | `def-shell caller … (if (is-big n) 1 0)` followed by an unannotated `(def is-big [n: int] (> n 5))` (forward reference) | SAFE |
| T2 | `(def-shell countdown [n: int] (if (> n 0) (countdown (- n 1)) true))` (self-recursive, no contract) | SAFE |
| T3 | mutually recursive unannotated `even?` / `odd?` | SAFE |

## Verification mapping

The rule introduces **no new obligation class** and moves nothing across the `Σ_auto`
boundary. It does introduce constraints that did not previously exist, because the
configurations it fixes emit no constraints today (they crash).

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| post over a `bool`-sorted `result` | contract | QF-LIA + Bool, auto-discharged | [`LLMLL.md §5.3.3`](../../LLMLL.md) names Bool as decidable in combination |
| post over a `Str`-sorted `result` | contract | QF-LIA + QF-EUF via interned constants and ground distinctness (STRLIT) | `LLMLL.md §5.3.3` |
| post over a `Pair2`-sorted `result` | contract | QF-LIA + acyclic datatype theory (Barrett–Shikanian–Tinelli, polite combination) | `LLMLL.md §5.3.3` |
| `isHoleVar τ_ret` (HOLE-RET) | trust | neither; fallback, post floors at `asserted`, warning emitted | `LLMLL.md §5.3.3` firewall |

Nothing escapes to Lean. Nothing becomes nonlinear.

The invariant "the emitted sort equals the checked type" is a compiler invariant discharged
by a differential fixture (annotated and unannotated forms of the same function differ in
the `.fq` only at sort tokens), not an SMT obligation.

## Trust-boundary note, scoped to the `result` binder

In the surviving `(= result e)` window, liquid-fixpoint elaborates the reflection equation
at Bool **despite the binder being declared `int`**, and computes correct verdicts. The
witness: body `(> n 5)` with `(post (= result (>= n 6)))` returns SAFE in both the annotated
and unannotated forms, which requires deciding that two syntactically distinct comparisons
are equivalent over the integers. The emitted `.fq` is internally inconsistent and the
solver silently recovers the intended sort from the equation's operands.

`LLMLL.md §5.3.3` grounds `Σ_auto` decidability on the emitted VC being the intended VC.
Here they differ, and the gap is closed by undocumented behavior of a pinned external tool.
RESULT-SORT removes the dependency **for the `result` binder**. It does not establish that
every emitted `.fq` is well-sorted; other `FQInt` defaults remain in the emitter. The note
belongs in [`verification-debate.md`](verification-debate.md), where the project frames its
trust boundary, and it should say `result`, not "the emitter."

## Spec status

**D1, independent of this finding.** [`LLMLL.md`](../../LLMLL.md) §12 Grammar Key Rule 1
reads "**No return-type annotation.** There is no `: ReturnType` after `[params]` in `def` /
`def-shell`. Return types are always inferred." This contradicts §4.1, which documents the
optional `-> RetType` as "optional and checking-mode" (DEF-RET), and contradicts the
grammar's own inline comments in the same section. It is stale from before DEF-RET shipped,
and it currently tells a reader that the workaround for this defect does not exist. Route
to documentation-lead now; it does not depend on the fix.

**The `do`-step carve-out survives.** `LLMLL.md` §9 states that a function called from
inside a `do`-block needs an explicit return-type annotation. That is the same
`TVar "?"` root: `collectTopLevel` supplies the wildcard and `expectPairType`
(`TypeCheck.hs:1604-1610`) rejects anything that is not a `TPair`. Retiring it requires the
type-environment row, which is out of scope for the reasons above. Track separately as
requiring declaration-group inference.

## Affected surface

**Compiler.**

1. `TypeCheck.hs:967-979, 1004-1012` and siblings at `:912, :946, :1025`: retain the
   synthesized `bodyType`. This requires `checkStatements :: [Statement] -> TC ()` (`:761`)
   to return a name-to-type map, and `runTC :: … -> TC a -> (a, [Diagnostic])` (`:572-575`)
   plus `typeCheck`'s signature (`:655`) to follow. `typeCheck` currently returns a
   `DiagnosticReport` and discards the value component at the binding site, so there are no
   types available to thread today.
2. `Module.hs:189-190`: thread the type map into `buildModuleEnv`. Inference already runs on
   the import path at `:189`, one line before `:190` builds the environment from `stmts`, so
   no second pass and no persisted-format change is needed.
3. `Module.hs:305-318`: `extractContracts` reads `τ_ret`. **`toExport` at `:267-278` is not
   touched.**
4. `Syntax.hs:911`: `meContracts` third slot becomes `Type`; the `ObligationAssembly.hs:851`
   destructure follows.
5. `FixpointEmit.hs:765, 802, 1143, 1156, 1184`: five sites collapse to `sortA1 τ_ret`.
   `:765` is hygiene only.
6. `FixpointEmit.hs:1101-1102`: map-chain hardcoded `FQInt`, brought in line with the sibling
   sites at `:806-807` and `:1220`. Not on the crash path.
7. `FixpointEmit.hs:2453-2458, 2467-2479`: guards take `τ_ret`.
8. `FixpointEmit.hs:265-287`: `synthRet` / `bodyIsBoolean` retired.
9. New HOLE-RET route plus the `unsortable-synthesized-return` diagnostic.
10. **Not touched:** `TypeCheck.hs:838-850` and every other `TVar "?"` site.

**Schema.** JSON-AST unchanged (`mRet` stays optional, no version bump). `.verified.json`
unchanged. The only shape change is the in-memory `meContracts` third slot.

**Docs (documentation-lead).** `LLMLL.md` §4.1 (state RESULT-SORT and HOLE-RET; say nothing
about retiring `TVar "?"`), §5.3.3 (fragment boundary over `τ_ret`; HOLE-RET as a fallback
trigger), §12 Key Rule 1 (D1). `LLMLL.md` §9 is **not** touched.
`docs/compiler-team-roadmap.md` row: retag **FQ-RESULT-SORT-1**, keep `FQ-BOOL-SORT-1` as an
alias, and correct the scope, the site attribution, and the control set.

**Freeze policy.** Nothing out of scope: no new builtin, syntax construct, FFI tier, or
orchestration feature. The new diagnostic is a warning on an existing path, which
CONTRACT-READ-LINT establishes as in-scope.

## Fixtures

The crash set with an annotated control for each: literal `true`, literal `false`, a literal
in a branch tail, boolean-eliminating posts (`and` / `or` / `not` over `result`), a string
literal, and a pair return.

The HOLE-RET pair: T4a (recursive call in then position; must reach `addBodyFallback` with
the warning and an `asserted` post, **not** merely avoid a crash) and T4b (recursive call in
else position; must reach a verdict).

The re-widening guards: T1, T2, T3.

A corpus byte-diff over the existing `.fq` output. All 29 unannotated contracted definitions
in tree return `int`, so `τ_ret = int` and every emitted `.fq` should be unchanged.

## Review log

Two standalone professor reviews exist for this finding and are ready for fold-and-archive
per DOC-CONSOLIDATE M2. Rev 0 to Rev 1 folded the trigger-set widening, the withdrawal of
the qualifier second-symptom claim, the `TVar "?"` root, and the FALLBACK-VISIBLE
diagnostic. Rev 1 to Rev 2 withdrew the type-environment row after the two-pass circularity
was demonstrated, restored `TVar "?"`, retracted the "one line" feasibility claim, and added
HOLE-RET.
