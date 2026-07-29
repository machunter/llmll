---
name: ret-branch-pref-proposal
title: "RET-BRANCH-PREF: prefer the concrete branch when the other synthesizes the `?` wildcard"
status: "Rev 0, SETTLED (professor adjudication folded); Stage 1 ready for engineer feasibility read"
date: 2026-07-28
author: main-agent
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# RET-BRANCH-PREF: prefer the concrete branch when the other synthesizes the `?` wildcard

**One line.** `inferExpr (EIf …)` returns `thenType` unconditionally, so a wildcard then-branch
silently wins over a concrete else-branch. Preferring the concrete branch closes the residual
that [`finding-fq-result-sort-default.md`](finding-fq-result-sort-default.md) Rev 3 accepted,
but only the **self-recursive** case is a derivation rather than a guess, and only that case
is proposed for Stage 1.

Routed out of that finding as a separate proposal because it changes what the type channel
*rejects*, and a stricter checker rejects programs that previously passed. That deserved its
own adjudication rather than riding on a bug fix.

## Background: the residual this closes

FQ-RESULT-SORT-1 stages (a) and (b) shipped. One member of the measured trigger set survives:
an unannotated, contracted, **recursive** definition whose recursive call sits in **then**
position still crashes the solver.

```lisp
(def-shell countdown [n: int] (pre (>= n 0)) (post (not (= n 99)))
  (if (> n 0) (countdown (- n 1)) true))
```

`collectTopLevel` registers `countdown : int -> TVar "?"`; the recursive call synthesizes to
that wildcard; `inferExpr (EIf …)` returns `thenType` on branch agreement
([`TypeCheck.hs:1323-1331`](../../compiler/src/LLMLL/TypeCheck.hs)); `compatibleWith` accepts
the concrete `TBool` else-branch without preferring it. So `τ_body = TVar "?"` and `sortA1`
lowers it to `FQInt`.

The residual has zero corpus instances, fails closed, and has a one-token workaround
(annotate the return). It is accepted in Rev 3 of the finding. This proposal is the
principled route to closing it anyway.

## Design

### Stage 1, recommended

```
    Γ ⊢ e₁ ⇒ τ₁    Γ ⊢ e₂ ⇒ τ₂    isHoleVar τ₁    ¬ isHoleVar τ₂
    e₁ is an application whose head is the enclosing definition
    ──────────────────────────────────────────────────────────────  (If-Prefer-Concrete-Rec)
    Γ ⊢ (if c e₁ e₂) ⇒ τ₂
```

Symmetric in the branches. The side condition restricts firing to a **self-recursive** call.

That restriction is what makes the rule a derivation. In the self-recursive case the wildcard
*is* the enclosing function's own return type, and the concrete branch is **determining** it,
so preferring the concrete branch is a least-fixpoint step rather than an assumption. This is
the standard treatment of a recursive binding (Milner 1978; Damas and Milner, POPL 1982;
mechanised in Mark P. Jones, *Typing Haskell in Haskell*, Haskell Workshop 1999 §11).

It reads only the enclosing-definition name (`tcCurrentFn`, `TypeCheck.hs:243, 451-457`) and
the two branch types, runs inside pass 2 of `checkStatements`, and never consults
`collectTopLevel`. It therefore does **not** reopen the two-pass circularity that forced the
Rev 1 type-environment row of the finding to be withdrawn.

### Stage 2, recorded but not proposed

Dropping the self-recursion side condition would additionally fix `(if c (g n) true)` for a
*foreign* unannotated callee, a strictly larger win than the residual. Gate it on a corpus
`.fq` byte-diff **and** a typecheck-acceptance diff over `examples/`, and ship only if both
are inert. Recorded so the option is not lost, not proposed now: the two prior over-reaches on
this line (the Rev 1 type-environment row, and HOLE-RET) both failed by applying a rule
broadly without measuring it first.

## What `?` denotes

The professor's routed question, answered here because it is spec text. Proposed wording for
`LLMLL.md §3.4.6`:

> **The `?` wildcard.** `TVar "?"` denotes *inference produced no usable type at this
> position*, not *any type*. It is compatible with every type
> (`compatibleWith`), which makes the compatibility relation reflexive and symmetric but
> **not** transitive. Because LLMLL erases and inserts no casts (§3.4.5), that compatibility
> is an **unchecked** admission rather than a deferred check: a program admitted through `?`
> carries no runtime guard and no verification obligation recording the gap. Consumers must
> treat a result derived through `?` as unproven rather than as trusted.

This distinction is broader than this rule. It is why Rev 3 of the finding could accept the
residual, and it would not survive the "any type, trust the author" reading.

## Why no join operation is needed

The objection this proposal was routed to answer was that preferring one branch is an ad-hoc
bias that will need a proper least-upper-bound the first time both branches are
concrete-but-different. Two reasons it does not.

**That case is already handled, by a diagnostic rather than a join.** `TypeCheck.hs:1327-1331`
emits `if branches have different types: … vs …` and then picks `thenType` anyway. Verified:
`(if (> n 0) true 1)` produces `error: if branches have different types: bool vs int`
followed by `error: type mismatch in 'k': expected int, got bool`. The rule's premises require
one branch to be a wildcard, so it never engages there. LLMLL already has an arbitrary bias at
this join point; this proposal does not introduce one.

**The order in play is precision, not subtyping.** The operation is the meet in the
**precision** order, where `?` is the least element and `? ⊓ τ = τ`. That is Siek and Taha's
consistency-based treatment (*Gradual Typing for Functional Languages*, Scheme Workshop 2006);
Garcia, Clark and Tanter derive it from first principles in *Abstracting Gradual Typing*
(POPL 2016) by reading `?` as the set of all types, so the meet is set intersection. The
precision order is orthogonal to subtyping, so declining subtyping (`LLMLL.md §3.4.2`
non-goal 1) does not deny it. `compatibleWith` (`TypeCheck.hs:2145-2148`) is already the
Siek-Taha consistency relation: reflexive, symmetric, non-transitive, `?` compatible with
everything.

The gap from gradual typing is the one recorded above: LLMLL has the consistency relation
without the casts that make it sound in that setting (`LLMLL.md §3.4.5:334`, "there is no
dynamic safety net").

## Edge cases

1. **Positive witness, the firing input.** The `countdown` definition above. `thenType` is the
   wildcard from the self-call, `elseType = TBool`, the call head equals the enclosing
   definition, so the rule fires and `τ_ret = bool`. The function reaches a verdict instead of
   the current crash. Channel: **type**, then contract.

2. **Must not fire: foreign unannotated callee.** `(if c (g n) 1)` with `g` a different
   unannotated function. `thenType` is a wildcard but the call head is not the enclosing
   definition, so the rule declines and the result stays `?`, as today. This is the fixture
   that pins the narrowing; without it the rule drifts to the general form on the next edit.
   Channel: **type**.

3. **Must not fire: both branches concrete and different.** `(if (> n 0) true 1)`. Already an
   error today; the rule's premises do not hold. Channel: **type**.

4. **Degenerate: both branches wildcards.** `(if c (g x) (h y))`, both callees unannotated.
   Neither premise holds, the result stays `?`, the emitter uses `FQInt` as before. Channel:
   **spec is silent (intentional)**.

5. **Mutual recursion is untouched.** `even?` / `odd?` both have concrete then-branches
   (`true`, `false`), so the rule never fires regardless of the side condition. The T3
   regression guard shipped with the finding is unaffected. Channel: **type**.

## Verification mapping

The rule is in the **type** channel and introduces **no proof obligation**. It changes which
type a synthesis judgment yields; it emits no constraint.

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| none introduced | type | not an SMT obligation; a branch-reconciliation rule discharged by the checker | `LLMLL.md §3.4.6` |
| downstream: `τ_ret = bool` instead of `?` for the residual shape | contract | **QF-LIA + Bool**, auto-discharged | `LLMLL.md §5.3.3` |

Nothing escapes to Lean, nothing becomes nonlinear, and the `Σ_auto` boundary does not move.
The residual moves *into* the Bool row that stages (a) and (b) already ship.

## Affected surface

1. `compiler/src/LLMLL/TypeCheck.hs:1323-1331`: one added case ahead of the existing
   compatibility test, in the `(False, False)` branch of `inferExpr (EIf …)`.
2. `compiler/src/LLMLL/TypeCheck.hs`: the side condition needs the **expression**, not the
   synthesized type: `thenType` is a `Type` and carries no provenance, so "arose from a
   self-call" has to inspect `e₁` for an application whose head is `tcCurrentFn`. This is the
   one non-trivial implementation question and the engineer's call.
3. Tests: the positive witness, both negative fixtures, and the shipped T1/T2/T3 guards.
4. `LLMLL.md §3.4.6`: the `?` definition above, plus the drift correction below. Doc-lead.
5. `docs/compiler-team-roadmap.md`: a new row. Doc-lead.

No new builtin, syntax construct, FFI tier, WASI capability, or orchestration feature, so
nothing is out of scope under the freeze policy.

## Spec drift found

`LLMLL.md §3.4.6:399` describes `if` as reconciling "its branches by checking one against the
other's synthesized type." `TypeCheck.hs:1323-1331` synthesizes **both**, runs a symmetric
compatibility test, and picks `thenType`. The spec describes an asymmetric checking discipline
the code does not implement.

This matters here in a convenient direction: under the spec's own wording, choosing which
branch supplies the expected type is already the checker's prerogative, so Stage 1 needs no
new spec concept. The drift should still be routed to doc-lead independently of whether this
proposal ships.

## Risks

1. **Provenance is not carried on the type.** Classify: scope. The side condition is a property
   of the expression, not of the synthesized type. **Bite: complicates**; it is the main thing
   for the engineer to price.
2. **Corpus byte-diff is mandatory.** Classify: verification-ergonomics. The 1427-example suite
   passed with HOLE-RET's 12-function regression present; only the `.fq` byte-diff against a
   rebuilt pre-change compiler caught it. That criterion is recorded in the finding and applies
   here. **Bite: blocks** shipping without it.
3. **The narrowing will look arbitrary later.** Classify: spec-drift. Without the fixpoint
   justification written down, someone will "simplify" it to the general form. Edge case 2 and
   this document are the guard. **Bite: only matters at scale.**
4. **`?` semantics are undocumented today.** Classify: spec-drift. Every compatibility check
   involving `?` is an unchecked admission and nothing says so. **Bite: complicates**, and it
   is broader than this rule.

## Review log

Adjudicated by the professor before Rev 0 was written, so the two are not a proposal/review
pair in the usual order. The verdict was build-it-narrowed-to-self-recursion, with the
narrowing named as the condition.

Findings folded: the "needs a proper least-upper-bound" objection dissolves because the
concrete-vs-concrete case is already a diagnostic (H1); the order in play is precision rather
than subtyping and `compatibleWith` is already Siek-Taha consistency (H2); LLMLL has that
consistency without casts (H3); and `§3.4.6:399` drifts from the code (H4).

**One divergence, recorded.** The professor classifies the unrestricted rule as blocked on
**soundness** (H3). Testing the witness gives a narrower reading: under the unrestricted rule
`(if c (g n) 1)` with `g : … -> bool` would synthesize `int`, which is wrong, but only for a
program whose branches genuinely disagree, and the downstream behaviour is identical to today
because `sortA1` maps both `?` and `int` to `FQInt`. Both crash at the solver; there is no
false SAFE and no verdict delta. The defensible classification is therefore **scope, not
soundness**. The narrowing is adopted anyway, on minimality: the residual needs only
self-recursion, and the two prior over-reaches on this line both failed by applying a rule
broadly without measuring it first.
