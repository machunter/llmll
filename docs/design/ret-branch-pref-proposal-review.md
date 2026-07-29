---
name: ret-branch-pref-proposal-review
title: "Professor review of ret-branch-pref-proposal.md Rev 0"
status: "Rev 0, standalone review; not folded"
date: 2026-07-28
author: professor
consumers: [user, language-team, compiler-engineer, documentation-lead]
---

# Professor review of `ret-branch-pref-proposal.md` Rev 0

Unusual ordering: the adjudication was delivered before Rev 0 was written, so the proposal
already folds these findings. This file preserves the adjudication as a standalone artifact
and rules on the one divergence Rev 0 recorded against it.

## Restatement

RET-BRANCH-PREF makes `inferExpr (EIf …)` return the concrete branch's type when the other
branch synthesizes the checker's `?` wildcard, replacing the current unconditional `thenType`.
The routed question was whether preferring the more-defined branch is a recognized operation
or an ad-hoc bias that will demand a proper least-upper-bound once both branches are
concrete-but-different.

## Context located

1. [`ret-branch-pref-proposal.md`](ret-branch-pref-proposal.md): Rev 0, the proposal under
   review. Stage 1 narrowed to self-recursion; Stage 2 recorded and not proposed.
2. [`finding-fq-result-sort-default.md`](finding-fq-result-sort-default.md): Rev 3, the
   accepted residual this rule closes, and the corpus measurement behind it.
3. `compiler/src/LLMLL/TypeCheck.hs:1320-1331`: the both-concrete path. `tcWarnOrError` on
   incompatibility, then `pure thenType` regardless.
4. `compiler/src/LLMLL/TypeCheck.hs:2145-2148`: `compatibleWith (TVar _) _ = True`, symmetric.
   Reflexive, symmetric, and not transitive.
5. `compiler/src/LLMLL/TypeCheck.hs:243, 451-457`: `tcCurrentFn`, set by
   `withFunctionContext`, available throughout a body.
6. `compiler/src/LLMLL/FixpointEmit.hs:2441, 2467`: `typeToSort _ = FQInt` and `typeToSortA`'s
   fallthrough to it. This is the fact the divergence below turns on.
7. `LLMLL.md §3.4.5:334`: "verify-or-trust, there is no dynamic safety net."
8. `LLMLL.md §3.4.6:399`: the spec's stated `if` reconciliation discipline.

## Findings

### F-1 (MAJOR): the routed objection is already answered by the code

The worry that this rule "will need a real join the first time both branches are
concrete-but-different" describes a case that exists today and is not joined. `:1327-1331`
emits `if branches have different types: … vs …` and then picks `thenType` anyway.
Empirically, `(if (> n 0) true 1)` yields `error: if branches have different types: bool vs
int` followed by `error: type mismatch in 'k': expected int, got bool`. LLMLL already has an
arbitrary bias at this join point and already treats a genuine disagreement as a diagnostic
rather than a lattice operation. The rule's premises require one branch to be a wildcard, so
it never engages there. **Bite: dissolves the objection.**

### F-2 (MAJOR): the lattice invoked was the wrong one

"No lattice, having declined subtyping" conflates two orders. The operation is not a
least-upper-bound in the *subtype* order; it is the meet in the **precision** order, where `?`
is the least element and `? ⊓ τ = τ`. That is Siek and Taha's consistency-based treatment
(*Gradual Typing for Functional Languages*, Scheme and Functional Programming Workshop 2006);
Garcia, Clark and Tanter derive it from first principles in *Abstracting Gradual Typing*
(POPL 2016) by reading `?` as the set of all types, so the meet is set intersection. The
precision order is orthogonal to subtyping, so `LLMLL.md §3.4.2` non-goal 1 does not deny it.

`compatibleWith` (`:2145-2148`) **is** the Siek-Taha consistency relation already: reflexive,
symmetric, non-transitive, `?` compatible with everything. LLMLL implemented half of a gradual
type system without naming it. **Bite: the move is recognized and named, not ad hoc.**

### F-3 (MAJOR, reclassified below): consistency without casts

In gradual typing `? ⊓ τ = τ` is safe because every consistent-but-unequal use is guarded by a
cast that fails at runtime. `LLMLL.md §3.4.5:334` states there is no dynamic safety net. So
preferring the concrete branch converts "unknown" into "assumed equal to the other branch"
with nothing anywhere checking the assumption. I classified this as **soundness** and as
blocking the unrestricted rule. Rev 0 disputes the severity; see the ruling below.

### F-4 (MINOR): spec/code drift at the `if` reconciliation

`LLMLL.md §3.4.6:399` describes `if` as "checking one against the other's synthesized type."
`:1323-1331` synthesizes both, runs a symmetric compatibility test, and picks `thenType`. The
spec describes an asymmetric discipline the code does not implement. It cuts in a convenient
direction for this proposal, since under the spec's own wording the choice of which branch
supplies the expected type is already the checker's. Route independently. **Bite: complicates
the spec text; does not block.**

## Ruling on the recorded divergence

Rev 0 reclassifies F-3 from **soundness** to **scope**, on the grounds that under the
unrestricted rule `(if c (g n) 1)` with `g : … -> bool` would synthesize `int`, which is wrong,
but only for a program whose branches already disagree, and that downstream behaviour is
identical to today because `sortA1` maps both `?` and `int` to `FQInt`.

**The reclassification is correct and I withdraw the soundness classification.** The premise
checks out at `FixpointEmit.hs:2441, 2467`. Pushing it further than Rev 0 did: for the
unrestricted rule to produce a false SAFE rather than a crash, the wildcard branch's reflection
would have to be well-sorted at the inferred type while denoting a different type. The
wildcard branch is a call, and its binder is sorted at the callee's own `τ_ret`, so a genuine
disagreement is ill-sorted and fails closed. The one residual shape is a callee whose `τ_ret`
is *itself* a wildcard, which requires an unfilled hole body, and refilling a hole re-runs
verification. So no complete program reaches a false SAFE through this rule.

F-3 therefore stands as a **scope** finding: the rule commits to a type inference could not
determine, which is defensible on well-typed programs and merely wrong on programs LLMLL
already accepts-but-should-not. That is an argument for taking the smallest rule, not for
blocking the larger one on soundness grounds.

This is the second time on this line that a claim of mine was narrowed by measurement rather
than argument, and both times the measurement was cheap. Worth noting as a pattern rather than
an incident.

## Recommendation

**Unchanged: build Stage 1, narrowed to self-recursion.** The recommendation survives the
reclassification because it never depended on F-3 alone.

The self-recursion side condition is what makes the rule a derivation instead of a guess. In
that case the wildcard *is* the enclosing function's own return type and the concrete branch is
determining it, so preferring the concrete branch is a least-fixpoint step. That is the
standard treatment of a recursive binding (Milner 1978; Damas and Milner, POPL 1982; mechanised
in Mark P. Jones, *Typing Haskell in Haskell*, Haskell Workshop 1999 §11). It is a degenerate
one-step case of the binding-group inference the project declined, restricted to one definition
and one join point, so it needs no global unification and does not reopen the two-pass
circularity that forced the Rev 1 type-environment row of the finding to be withdrawn.

Rev 0's minimality argument now carries the weight that F-3 was carrying: the residual needs
only self-recursion, and the two prior over-reaches on this line both failed by applying a rule
broadly without measuring first. Stage 2 is correctly recorded rather than proposed.

Two build conditions, both cheap and both already in Rev 0:

1. Corpus `.fq` byte-diff against a rebuilt pre-change compiler. The suite passed with
   HOLE-RET's twelve-function regression present; it will not catch this either.
2. A negative fixture: `(if c (g x) 1)` with `g` a *different* unannotated function must still
   synthesize the wildcard. Without it the rule drifts back to the unrestricted form on the
   next edit.

## Open questions for the language-team

None. The one item I handed back (what `?` denotes) is answered in Rev 0's "What `?` denotes"
section, and the proposed `LLMLL.md §3.4.6` wording is the right reading: `?` is
"inference produced no usable type," not "any type," and the compatibility it licenses is an
unchecked admission rather than a deferred check. That distinction is broader than this rule
and should land in the spec whether or not Stage 1 ships.
