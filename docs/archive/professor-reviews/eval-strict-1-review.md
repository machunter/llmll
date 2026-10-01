---
title: "Professor review: EVAL-STRICT-1 Rev 0, call-by-value for LLMLL"
status: "FOLDED and ARCHIVED 2026-09-29 (DOC-CONSOLIDATE M2), into docs/design/eval-strict-1-proposal.md's Appendix review log, at the settlement of Rev 2. One round, against Rev 0. All four recommended text changes were adopted in Rev 1."
author: professor
date: 2026-09-28
reviews: "docs/design/eval-strict-1-proposal.md (Rev 0)"
---

# Professor review: EVAL-STRICT-1 Rev 0

## Restatement

The proposal makes LLMLL call-by-value, with a closed list of non-strict forms
and no unevaluated components in any value, and requires the generated Haskell
to conform. The purpose is to make the verifier's existing partial-correctness
reading sound without termination side conditions.

## Context located

1. `compiler/src/LLMLL/FixpointEmit.hs`, `exprToPred`: a contract may apply only
   builtins, constructors (`isUpperCtorHead`) and the `is-ok`, `ok`, `err`
   encodings. A `pre` or `post` cannot mention a user function.
2. `compiler/src/LLMLL/CodegenHs.hs`, `emitOp`: `=>` lowers to `(not a || b)`,
   which short-circuits; `<=>` lowers to `(a == b)`, which evaluates both.
3. Swamy et al., *Dependent Types and Multi-Monadic Effects in F\**, POPL 2016.
   The `Div` effect gives partial correctness under call-by-value. Only `Tot`
   terms may appear in specifications.
4. Peyton Jones et al., *A Semantics for Imprecise Exceptions*, PLDI 1999. GHC
   does not fix the order in which strict sub-expressions are evaluated. When
   two fail, either failure may be observed.
5. Milner et al., *The Definition of Standard ML (Revised)*, 1997: constructors
   are strict, and a value is built only from values. Pierce, *TAPL* ch. 5.
   Turner, *Total Functional Programming*, JUCS 2004: for total programs the
   strategy does not change the result.
6. The OCaml manual and R7RS Scheme leave argument evaluation order
   unspecified.
7. `docs/design/` held no draft on this topic.

## Gaps and hazards

**1. The spec promises left-to-right order, and GHC does not keep it.**
Spec drift against the backend; complicates.

Rev 0 says arguments are evaluated "left to right". The `Strict` pragma, bang
patterns and `seq` guarantee that a value is evaluated; none fixes the order.
Under `-O`, strictness analysis may evaluate strict arguments in any order.
Order is observable only when two sub-expressions fail. In
`(f (spin x) (tally (- 0 5)))`, left-to-right evaluation hangs, and GHC may
report `Precondition violated` instead. Only `pseq` fixes order, and it would
be needed at every call.

**2. "Full values" is standard call-by-value, worded as something extra.**
Spec wording; complicates the codegen note.

In ML a constructor is strict, so every value is built from values. No separate
deep-forcing rule is needed. The sentence "no component of a value is left
unevaluated" invites a `deepseq` at every binding. The codegen note is also
wrong on `Data.Map.Strict`: it forces a map's values only to WHNF, so a map
whose values are lists holds unevaluated tails. Conformance must cover builtin
container contents, not only user types.

**3. The list of non-strict forms leaves out `=>`.** Precision; small.

`=>` short-circuits in generated code and is non-strict in its right operand.
`<=>` evaluates both operands.

**4. The reason call-by-value is enough is not in the spec.** Soundness
firewall; matters at scale.

Partial correctness is sound under call-by-value only while specifications
contain no term that can diverge. F\* enforces this with the `Tot`/`Div` split.
LLMLL enforces it only because `exprToPred` happens not to reflect user
functions. A later feature that reflects a `def-shell` function into contracts
would bring back unsoundness under either strategy.

**5. Convergence.** Functions in the verified core are total on their `pre`, so
by Turner's argument the strategy changes meaning only in `def-shell` code and
partial builtins. Language-team's edge cases 1, 2, 3, 5 and 6 are the right
witnesses. The crash-to-hang shift is real and acceptable: a program with
either behavior was already incorrect.

## Recommendation

Accept, with four text changes:

1. Leave argument order and the order of independent `let` bindings
   unspecified. When more than one sub-expression fails, which failure is
   observed is unspecified. `let` keeps its scoping order.
2. State call-by-value with strict constructors, applied to every builtin
   container. Correct the `Data.Map.Strict` claim. Add a map with list values
   as a conformance witness.
3. The non-strict forms are `if`, `match`, `and`, `or`, `=>` and a `fn` body.
   `<=>` evaluates both operands.
4. Add: "A contract mentions only builtins and constructors. A user function
   may enter a contract only if its termination is proved." Cite the F\*
   `Tot`/`Div` split as the reason.

A lazy-contracts design (Chitil, ICFP 2012; Degen, Thiemann and Wehr, 2012) is
not a better alternative. It keeps laziness, which LLMLL does not use, and adds
machinery. Rev 0's direction is correct.
