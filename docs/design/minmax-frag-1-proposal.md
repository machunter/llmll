---
name: minmax-frag-1-proposal
title: "MINMAX-FRAG-1: min, max and abs are proved in a body as their if definitions"
status: "Rev 0, SETTLED and SHIPPED v0.26.17 (10fa705). The DECIDE chose reflection over a documented rewrite. Bodies only; the contract half is the residue row MINMAX-FRAG-1 residue (1)."
date: 2026-09-28
author: language-team
consumers: [compiler-engineer, documentation-lead, user]
reviews: "none"
related: "patch-proof-1 (the live fill that surfaced the cost); match-term-eq-1 (same session)"
---

# MINMAX-FRAG-1: `min`, `max` and `abs` are proved in a body as their `if` definitions

## 1. Problem

A body that uses `min`, `max` or `abs` falls back with cause `body-outside-fragment`, refused by `app:min`, `app:max` or `app:abs`, and its post is assumed. Each builtin is one `if` over one comparison, and that `if`, written out, proves. No in-tree program uses the three, so the cost falls on agents, which write them without being asked: a live `llmll-orchestra` fill merged `(min balance amount)` with its post assumed, and under `--require-proof` the agent rewrote it as the `if`.

The roadmap row offered two answers: reflect the builtins into the fragment, or keep them out and name the `if` rewrite in `LLMLL.md` §5.3.3 and the checkout brief. This record takes the first.

## 2. Decision

In a function body, each builtin reflects as its `if` definition, emitted as an int-valued if-then-else **term**:

```
min a b  ↦  (if (a <= b) then a else b)
max a b  ↦  (if (a <= b) then b else a)
abs a    ↦  (if (a < 0) then (0 - a) else a)
```

A term, not a branch split. Measured on v0.26.16, an `if` in argument position falls back (`(+ 1 (if (<= a b) a b))`, refused by `app:+`), so rewriting `min` to `if` would leave `(+ 1 (min a b))` outside. The term composes with every arithmetic context, and the clamp `(min (max x lo) hi)` nests.

## 3. Soundness

**The term equals the value the built program computes.** `int` lowers to Haskell `Integer`, which is unbounded, and the runtime binds `llmll_min = min`, `llmll_max = max` and `llmll_abs = abs` from the Prelude. The Prelude defines `min x y` as `if x <= y then x else y` and `max x y` as `if x <= y then y else x`; the reflection copies both, argument order included. On integers a tie returns equal values, so the order could not change a result anyway. `abs` on `Integer` has no overflow case.

**The fragment stays QF-LIA.** An if-then-else over linear integer terms is definable in QF-LIA (`ite` elimination introduces one fresh variable and two guarded equalities), so the decision procedure and its completeness are unchanged (§5.3.3).

**The builtin reading applies only to the builtin.** A program may declare its own function named `min`, and a parameter or inner binder may carry the name. A call is read as the builtin only when the function binds none of the three names, as a parameter or at any depth in the body, and no top-level function of the program or its imports has the name. Otherwise the call takes the path it took before, which falls back. The test is whole-body rather than scope-exact, so an error in it costs a proof and never produces one.

A first gate that consulted only the sort and renaming environments proved a function whose `min` was a function-typed parameter: that parameter is in neither environment. The fixture `compiler/test/fixtures/minmax-frag/shadow-param.llmll` pins that it now falls back.

## 4. Edge cases

1. **Argument position.** `(+ 1 (min a b))` proves. Contract channel, QF-LIA.
2. **Nesting.** `(min (max x lo) hi)` with `(pre (<= lo hi))` proves the clamp post; without the pre it is refuted, correctly, since `lo > hi` breaks the post.
3. **A measure operand.** `(min (string-length s) n)` proves: the operand translates first, and the term carries it.
4. **An operand outside the fragment.** The call falls back, refused by the operand's construct, as any operator does.
5. **A user function named `min`.** It is called as that function under assume-guarantee; nothing is reflected.
6. **A function-typed parameter named `min`.** Falls back (§3).
7. **`min` passed as a value**, as in `(list-fold xs 0 max)`. Not an application; unchanged, and `list-fold` falls back on its own.
8. **`min` in a `pre` or `post`.** Unchanged: it falls back. Contract translation has no view of the program's declarations, and giving it one touches more than a hundred call sites across nine modules. This is the residue row.

## 5. Evidence

hspec `MMF-1` to `MMF-8`; fixtures `compiler/test/fixtures/minmax-frag/subject.llmll` (seven functions, all proved), `wrong.llmll` (three refuted twins) and `shadow-param.llmll`. Removing the parameter guard fails `MMF-6`, and removing the top-level-name guard fails `MMF-7`. Removing the inner-binder guard fails nothing: no witness exists today, because every inner binder of function type already forces a fallback (`let`, `match-payload-sort`, `list-fold`). The guard stays for when those constructs enter the fragment. `llmll verify` gives the same verdict on all 255 in-tree programs before and after.
