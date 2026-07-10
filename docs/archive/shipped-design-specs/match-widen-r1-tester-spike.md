---
name: match-widen-r1-tester-spike
title: "MATCH-WIDEN R1 spike — do we need datatype testers? (No: the mechanism is boolean branch-guards)"
status: "Spike complete"
date: 2026-07-06
author: compiler-engineer (fork)
---

# R1 spike — datatype testers for MATCH-WIDEN Strategy A

**Question:** can the FQ IR / liquid-fixpoint emit datatype testers (`is-C`) cheaply enough to lower
a payload-bearing match to an ordered nested `EIf` over testers+selectors (engineer-plan Strategy A)?

## Verdict

**The tester question is MOOT — Strategy A's premise is wrong, and that is good news.** The compiler
does **not** discriminate match arms with datatype testers. It uses a synthesized **boolean
branch-guard**, and that mechanism *already* encodes first-match ordering. Neither testers
(Strategy A) nor a heavy hand-threaded ordering pass (Strategy B) is required. The real path — call
it **A′** — is a bounded generalization of existing `BranchVC` machinery. **Effort: Slice 1 S–M,
total M; lower risk than the plan's M–L (the tester unknown is dissolved, not resolved-yes).**

## Evidence

1. **The FQ IR has no tester.** `FQPred` (FixpointIR.hs:81–92) is `FQTrue/FQFalse/FQVar/FQLit/
   FQBinPred/FQBinArith/FQAnd/FQOr/FQNot/FQKVar/FQApp`. No `is-C` / checker constructor; datatype
   sorts (`FQData`, `FQDataApp`) carry constructors with fields, and a selector is the field name
   `ctor_i` applied via `FQApp` (FixpointIR.hs:299–309). Emitting a tester would need a new `FQPred`
   node **plus** confirming liquid-fixpoint's surface accepts one — the risk the plan flagged.

2. **But the working 2-arm path never uses one.** Emitting `settle.llmll`'s constraints
   (`llmll verify … --fq-out`) shows the `Success`/`Error` match lowered to a **fresh boolean
   binder** `_bv__match_success_2 : bool` plus a separate payload binder `_bv_n_0 : int`, with three
   constraints:
   - Success/n≥0: `lhs { … | (_bv__match_success_2 && (_bv_n_0 >= 0)) && (result = _bv_n_0) }`
   - Success/n<0: `lhs { … | (_bv__match_success_2 && (not (_bv_n_0 >= 0))) && (result = 0) }`
   - Error:       `lhs { … | ((not _bv__match_success_2)) && (result = 0) }`

   The discriminator is a **boolean**, not a datatype tester; the datatype sort isn't consulted for
   branching at all. Source: `guardVar <- freshName "_match_success"` (FixpointEmit.hs:1749,1838)
   producing `BranchVC (FQVar "_match_success_N") bodyS_VC bodyE_VC` (FixpointEmit.hs:1687).

3. **First-match is already threaded.** The `Error` arm's guard is `(not _bv__match_success_2)` —
   i.e. the else-branch already carries the negation of the prior arm. The professor's ordered
   `VC-Match` rule (`Γᵢ = … ∧ ⋀_{j<i}¬patⱼ`) is, for the 2-arm case, *exactly* what `BranchVC`
   emits. Ordering falls out of the branch structure, not a separate pass.

4. **The mixed-arm blocker is a seeding restriction, not a discriminator one.** The payload seeding
   requires both arms payload-bearing: `TSumType [(c1, Just t1), (c2, Just t2)]` (FixpointEmit.hs:629,
   `adtKeys`). A nullary arm (`(c1, Nothing)`) fails this pattern → no payload key seeded → fallback.
   The boolean guard is independent of this; a mixed sum (`Verified | Rejected int`) needs only that
   the seeding stop demanding both `Just` and instead seed a payload key for whichever arm has one.

## Recommended path (A′) and effort

Generalize the existing `BranchVC`/discriminator machinery — no testers, no FQ-IR grammar change, no
liquid-fixpoint dependency risk:

- **Slice 1 (mixed 2-arm sums) — S–M.** Widen `isCoreBodySyntactic` (Syntax.hs:683–694) for a mixed
  arm-set; generalize the `adtKeys` seeding (FixpointEmit.hs:629) to seed payloads per-arm-that-has-
  one (nullary arm → no payload key). The boolean `BranchVC` is unchanged. **Unblocks the goto-fail
  leaf** (`finalize … -> Verdict`).
- **Slices 2–3 (sequential / nested, N-arm) — M.** Nest/compose `BranchVC`s; for N>2 arms either nest
  guards with `guard_i ∧ ¬(prior)` (ordering is the existing else-structure) or move to an int-tag
  guard as the nullary-enum path already does (`buildChain`, FixpointEmit.hs:1173). `collectBranchBinders`
  already walks the whole VC tree, so sequential/nested composition largely exists.

## Surprise (the load-bearing one)

The engineer plan's central R1 unknown — "can the FQ IR emit datatype testers?" — mis-framed the
mechanism. The compiler has *never* used testers for match discrimination; it uses boolean
branch-guards that already encode first-match. This **dissolves** the main risk rather than resolving
it, and makes MATCH-WIDEN lower-effort and lower-risk than the plan estimated. Strategy B's "inherits
the R5/branch-skolem interaction" caveat still applies (these guards *are* the branch skolems), so
the DIP stage-3 cross-reference in the proposal stands.
