---
name: cycle-verification-finding
title: "Cycle verification: LLMLL.md says contract-only, the compiler does circular assume-guarantee (spec/code drift)"
status: "Finding (Rev 0) — hypothesis (a); soundness/erasure-coverage routed to professor"
date: 2026-07-06
author: language-team
consumers: [professor, documentation-lead, compiler-engineer]
---

# Cycle verification — spec/code drift finding

## Restatement

`LLMLL.md §0.1` (`:24`, `:13`) and the erasure theorem's standing hypothesis (`§3.4.5`) state that
functions in recursive call cycles are **excluded from compositional encoding and verified
contract-only**. The compiler does not do this: a mutually-recursive `def-shell` pair verifies
**body-faithful (`verified`)** via circular assume-guarantee. This is a spec/code drift, and it
directly bears on the cascading-refinement Option-3 decision, which assumed cycles *silently degrade
to contract-only*.

## Context located / code trace

1. **Reproduced (shipped v0.14.12):**
   ```lisp
   (def-shell f [x: int] -> int (pre (>= x 0)) (post (>= result 0)) (g x))
   (def-shell g [y: int] -> int (pre (>= y 0)) (post (>= result 0)) (f y))
   ```
   → `llmll verify`: both `f` and `g` `verified` / body-faithful, SAFE.
2. **`FixpointEmit.hs:262-270`** — `recursiveNames` IS computed: `stronglyConnComp` over
   `buildCallGraph stmts`, `getRecursive (CyclicSCC ns) = ns`. For the pair above the call graph has
   `f→g, g→f`, so the SCC is `CyclicSCC [f,g]` and `recursiveNames = {f,g}`. The detection works.
3. **`FixpointEmit.hs:1607-1612`** — the load-bearing site. Verbatim comment: *"Issue 4 resolution:
   **SCC guard REMOVED**. Callers of recursive functions may use assume-guarantee against the
   recursive function's contract. The recursive function's own body VC remains excluded (§4.1). Trust
   degrades via evidenceMeet — see §4.4."* The `EApp fname args` equation binds **`_sccSet`
   (unused)** — so a call to a cycle member is translated by the *ordinary* contracted-call path
   (assume the callee's post, prove the callee's pre), with no cycle special-casing.
4. **`recursiveNames` is threaded but not applied.** It is passed into the per-def emission
   (`:340-366`) and down as `sccSet` through `bodyToPredM` (`:462,:696,:1476+`), but I found **no
   membership check** (`Set.member _ sccSet`) anywhere in the body-VC path that demotes a cycle
   member's own body-VC to contract-only. The value is computed and carried, inert for this case.
5. **Internal inconsistency:** the `:1610` comment claims "the recursive function's own body VC
   remains excluded," but the probe shows it is **not** excluded — `f`'s body-VC (which calls `g`) is
   emitted and discharged. The comment describes the pre-"Issue 4" design; the code moved, the comment
   (and the spec) did not.

## The finding: hypothesis (a) holds — it is circular assume-guarantee, and the spec has drifted

The compiler applies the **mutual-recursion Hoare rule**: each cycle member's body-VC *assumes each
callee's postcondition* (via the ordinary assume-guarantee call path) and *proves its own post*. For
the pair above: `f` is verified assuming `g`'s post (`result ≥ 0`) — its body `(g x)` yields
`result_f = result_g ≥ 0`; symmetrically for `g`. This is **partial-correctness-sound** by the
standard rule (assume all specs, prove each body). It is *not* the contract-only degradation the spec
describes. So:

- **`LLMLL.md §0.1:24` (+ `:13`, `:465`) is DRIFT** — it reflects the pre-Issue-4 "exclude the cycle,
  verify contract-only" design. The code intentionally removed the SCC guard at the call site
  (`:1608`) and now verifies cycle members body-faithful via assume-guarantee.
- **The professor's cycle-degradation premise, and cascading Option-3, were reasoning from the
  drifted spec.** Cycles are not *silently degrading to contract-only*; they are *circular-AG
  `verified`*. Option-3's "floor a contract-only cycle member" is therefore the **wrong fix** — there
  is no contract-only cycle member to floor.

**But — the real, unresolved soundness question (for the professor, below):** the erasure theorem
(`§3.4.5`, Theorem B) carries a *standing hypothesis* that recursive cycles are excluded from
compositional encoding. If the code instead admits them via circular AG, a `verified` recursive
function is **outside the theorem's stated coverage**. Either (i) the theorem extends to circular-AG
**partial** correctness (and the spec should be rewritten to say so, with a partial-correctness
disclosure), or (ii) the code should honor the exclusion (demote cycle members to contract-only) to
match the theorem. The empirical `verified` is consistent with (i) — standard mutual-recursion
partial correctness — but whether Theorem B's guarantee *extends* to it is a metatheory question I
cannot settle inward.

## The termination gap (why "verified" here is only partial)

The probe's `f`/`g` have **no base case** — they never terminate. Under partial correctness, a
non-terminating function *vacuously* satisfies any post (no result is ever produced to violate it).
So `verified` is honest for **partial** correctness but must not be read as **total**. This is the
same gap `letrec` already discloses (`§5.3.5` partial-correctness disclaimer) — and it is the crux:
the drift is not (necessarily) unsoundness, it is an **undisclosed partiality** on the `def-shell`
recursive path, whereas `letrec` discloses it.

## Edge cases

1. **Self-recursion** `(def-shell f [n:int] -> int (pre (>= n 0)) (post (>= result 0)) (f (- n 1)))`.
   *Expected under the code:* `verified` via assume-guarantee against `f`'s own contract (same SCC-guard-
   removed path). *Channel:* contract — but **partial** (no descent obligation; R7 would add totality).
   *Cite:* FixpointEmit.hs:1608.
2. **A base case present** `(def-shell f […] (if (= n 0) 0 (f (- n 1))))`. *Expected:* still
   `verified` partial — the compiler does **not** check the `(- n 1)` descent (R7 unbuilt), so the
   post is proved compositionally but termination is unverified. *Channel:* contract (partial).
3. **`def` (strict) mutual recursion.** `LLMLL.md:465` says all mutually-recursive functions must be
   `def-shell` (strict `def` rejects the cycle). *Expected:* the strict `def` path rejects — confirm
   the drift is `def-shell`-specific. *Channel:* type (core-grammar / SCC gate). *Cite:* :465 —
   whether *this* gate fires is the one residual inward check the engineer should confirm.

## Verification mapping

The circular-AG obligation is the existing per-node body-VC — **QF-LIA + the fragment already in
`Σ_auto`**, auto-discharged; no new obligation is introduced by *documenting* the behavior. The
**termination** obligation that would upgrade partial→total is the R7 strict-descent measure
(`measure(args') < measure(args)`), currently research-track — QF-LIA if a linear `:decreases`, else
out of scope. Classifying the *soundness* of circular-AG partial correctness against Theorem B is the
professor's call, not a fragment question.

## Recommendation

1. **Treat as spec/code drift, code side is (probably) right.** The smallest change is to **rewrite
   `LLMLL.md §0.1:24`** (doc-lead) from "recursive cycles fall back to contract-only" to the accurate
   "recursive cycles are verified compositionally via assume-guarantee at **partial** correctness;
   termination is unverified (R7)" — *pending* the professor confirming Theorem B extends (below).
   Fix the stale `FixpointEmit.hs:1610` comment (engineer).
2. **Add a partial-correctness disclosure** for `def-shell` recursive functions, mirroring the
   `letrec` disclaimer (`§5.3.5`) — a trust-report flag "verified (partial — recursive, termination
   unverified)". This is the honest surface, and it is **what cascading Option-3 actually needs**:
   not a demotion-floor, but a *partial-correctness disclosure* propagated up the refinement tree.
3. **Revise cascading Option-3** accordingly: the "cycle trust-floor" becomes "a refinement subtree
   containing a recursive cycle is disclosed as partial-correctness (termination unverified), not
   laundered to total `verified`." Same trust-closure hook, different label. Update
   `cascading-refinement-proposal.md` Layer 2(d) / Risk 1 after the professor turn.

## Open questions for the professor

1. **Does Theorem B (erasure, `§3.4.5`) extend to circular assume-guarantee at partial correctness,
   or is its "recursive cycle excluded" standing hypothesis load-bearing?** If it extends, the spec
   drift is a documentation fix (option (i)) and the code is sound-as-is (partial). If the hypothesis
   is load-bearing for the erasure guarantee, the code is *over-claiming* `verified` on a path the
   theorem does not cover, and the SCC guard should be restored (option (ii)) — which would make
   Option-3's original floor correct after all. This is the single adjudication that decides both the
   spec fix and the cascading design.
2. Is LLMLL's per-call "assume the callee's post" mechanism the *complete* mutual-recursion rule, or
   is there a cycle shape (e.g. a guard that makes one member's assumed post unreachable) where
   circular AG is unsound even for partial correctness?
