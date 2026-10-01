---
title: "Professor review: SHELL-CALL-PRE-1 Rev 0, call-site preconditions in bodies that fall back"
status: "Standalone review. Not folded into the proposal; language-team folded all findings into Rev 1, and Rev 2 replaced the H1 remedy with EVAL-STRICT-1."
author: professor
date: 2026-09-28
reviews: "docs/design/shell-call-pre-1-proposal.md (Rev 0)"
---

# Professor review: SHELL-CALL-PRE-1 Rev 0

## Restatement

Part 1 repairs a lookup defect that hides the TRUST-PRE disclosure for callees
reached through `open`, and adds one `verify` line. Part 2 is hybrid checking:
at each call site in a body that falls back, it tries to prove the callee's
`pre` from a context of faithfully translated facts, reports proved, unproved
or violated, and keeps the runtime `pre` check in every case.

## Context located

1. `compiler/src/LLMLL/CodegenHs.hs`, `bodyWithPre`: generated code checks every
   declared `pre` at run time, placed before the body with `seq`. No build mode
   removes it.
2. `compiler/src/LLMLL/TrustReport.hs`, `markCallerObligations`: confirms the
   name-lookup defect (D2).
3. `compiler/src/LLMLL/FixpointEmit.hs`, the call-pre block and the F-NIW-4
   `ctxCalls` handling: the in-fragment path already assumes the `post` of the
   call that produced an argument.
4. Roadmap rows `DEF-ADMIT-XMOD-1` and `PARTIAL-FNS-GRAPH-1`.
5. Flanagan, *Hybrid Type Checking*, POPL 2006; Knowles and Flanagan, TOPLAS
   2010. Findler and Felleisen, *Contracts for Higher-Order Functions*, ICFP
   2002. Vazou et al., *Refinement Types for Haskell*, ICFP 2014. Xu, Peyton
   Jones and Claessen, *Static Contract Checking for Haskell*, POPL 2009.
   Godefroid et al., *Compositional May-Must Program Analysis*, POPL 2010.
   Bader, Aldrich and Tanter, *Gradual Program Verification*, VMCAI 2018.
6. `docs/design/` held no draft on this topic.

## Gaps and hazards

**1. A callee `post` in Γ_s is not a fact under lazy evaluation unless the
callee terminates.** Soundness; blocks Part 2 as written.

The generated code is lazy Haskell, and a `post` is proved as partial
correctness. A callee that never returns may carry any `post`, including
`false`. If Γ_s assumes the `post` of a callee whose result is never
evaluated, and that callee does not terminate, Γ_s can be inconsistent while
execution still reaches *s*: a false `proved`. Vazou et al. (ICFP 2014, §3)
found this defect in Liquid Haskell and admitted a binder's refinement only
for terms known to terminate. Callers that fall back are mostly `def-shell`
code, where unproved recursion lives, so this is the common case. The same gap
exists on the in-fragment path.

**2. The outcomes cannot tell an unreachable site from a proved one.**
Soundness of the report.

If Γ_s ⊢ false, the solver proves every goal at *s*. Rev 0 would call the site
`proved`. May/must analysis keeps these apart: check consistency first, and
report `unreachable` as its own outcome.

**3. The must-fail check is narrower than it needs to be, and its name is wrong
for a lazy language.** Ergonomics.

The general condition is Γ_s ⊢ ¬pre with Γ_s consistent, not only a closed
false term. It costs one more kvar-free constraint per site. Under `seq`, the
`pre` check runs only when the callee's result is evaluated, so
`violated-if-evaluated` is the accurate name under lazy code generation.

**4. Part 1 fixes a lookup that `PARTIAL-FNS-GRAPH-1` also has to fix.** Scope.
Use `LLMLL.ProgramGraph.qualifiedCallGraph` as the one resolver.

**5. A `SAFE` headline next to a must-fail site misstates the result.**
Ergonomics. Keep the exit status; put the counts in the headline.

**6. "Proved" needs a trust tier.** A site proved from an asserted `post` is
weaker evidence than one proved from `pre_f` alone. Use the §5.3.4 meet.

**7. Convergence.** Rev 0's separate query, whose failures are not
refutations, is Flanagan's three-outcome judgment (✓ / ✗ / ?), and the `?`
case already has its runtime check. Findler and Felleisen assign a violated
`pre` to the caller, which matches putting these obligations on the caller.

## Recommendation

1. Accept Part 1, built on `qualifiedCallGraph`. It can be planned now.
2. Accept Part 2 with three changes: (a) Γ_s admits a callee `post` only when
   the callee is not in `partial_fns` or `termination_assumed_fns`; (b) check
   `unreachable`, then `proved`, then `violated-if-evaluated`, then `unproved`;
   (c) a proved site's level is the meet of its facts' levels, and the headline
   carries the counts.
3. Keep the runtime `pre` check at every site, including proved ones. Code
   generation must not depend on an advisory query.
4. Keep the prototype gate: count each outcome on `pathlint` and `shape.llmll`
   before the design settles.

## Open questions for the language-team

1. The in-fragment path (F-NIW-4 `ctxCalls`) assumes callee posts under the
   same lazy semantics. State whether the termination filter applies to both
   paths, or whether the in-fragment case is filed separately. A filter on one
   path only would make the two paths disagree about the same call.

## Note added by language-team on folding (not part of the review)

The open question was answered by measurement. The in-fragment path has the
false proof today, and a built program shows it. Rev 1 drafted a separate row
for it. Rev 2 replaced the filter in (a) with EVAL-STRICT-1, which makes
evaluation call-by-value and removes the cause on both paths. Under
call-by-value, the H3 name `violated-if-reached` is accurate again.
