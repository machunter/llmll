---
name: rec-body-vc-review
title: "Professor review — REC-BODY-VC (Rev 0)"
status: "Standalone review — folded into rec-body-vc-proposal.md Rev 1; ready for archive on settlement"
date: 2026-07-10
author: professor
reviews: rec-body-vc-proposal
---

# Professor Review — REC-BODY-VC (Rev 0)

> Standalone critique of the language-team's Rev 0. The language-team's Rev 1
> (`rec-body-vc-proposal.md`) incorporates all six findings and both open questions. Kept
> reviewable as an independent artifact per DOC-CONSOLIDATE; archive to
> `docs/archive/professor-reviews/` on settlement.

## Restatement

Rev 0 re-scoped REC-BODY-VC into (a) a call-graph-derived partiality marker, (b) a strict-core
admission guard refusing self/SCC callees regardless of persisted evidence, and (c) a `(decreases e)`
clause emitting per-call-site strict-descent obligations (single int-slice, QF-LIA, fully-body-faithful
SCCs; descent failure = hard `descent-refuted`). Charge: critique (b)'s soundness argument, the
`descent-refuted` claim-accuracy reasoning, the SCC-granularity rule, the Option-3 interaction, and the
two handed-out questions.

## Context located

1. `PBT.hs:596-607` — `canonicalDefEvidenceHash` covers `(semantics-tag, body, pre, post)`; def-form
   absent. The mechanical root of probe E; changes the recommendation on (b).
2. `TypeCheck.hs:395-417, 447-453` — `checkCalleeAdmissibility`; `erFullyVerifiedAdmissible`. Confirms
   probe A rejects a `def` self-call and probe E succeeds only via the persisted-evidence leg.
3. `FixpointEmit.hs:642-656` (letrec well-foundedness), `:1692-1759` (CallVC A-G, `_sccSet` unused).
4. `LLMLL.md §0.1:13`, `§3.4.3:271-284`, `§4.2:461-477`, `§5.3.5:1007,1013` — D1 internal
   contradiction.
5. `docs/design/cascading-refinement-proposal.md:69-94` — Option 3 rests on the same stale citation;
   this is load-bearing, not decorative.

External anchors Rev 0 did not cite: Abadi & Lamport, *Conjoining Specifications* (TOPLAS 17(3), 1995);
McMillan circular A-G (CAV/CHARME 1999); Appel & McAllester, *Indexed Model … Foundational PCC*
(TOPLAS 23(5), 2001); Nakano, *A Modality for Recursion* (LICS 2000); Leino, *Dafny* (LPAR-16, 2010);
Vazou et al., *Refinement Types for Haskell* (ICFP 2014); total-correctness variant rule
(Turing 1949; Hoare 1971; Apt, TOPLAS 1981).

## Gaps and hazards

**1. (b) as a blanket SCC refusal is the wrong-shaped fix for probe E; shipping (b) alone is harmful.**
Soundness / scope. Probe E succeeds because `canonicalDefEvidenceHash` omits the def-form
(`PBT.hs:596-607`). Surgical closure: put the def-form (recursion-status) into the hash preimage — the
flip then invalidates the sidecar and the normal `def` admissibility rejects the self-call as probe A
already does. The blanket guard refuses every self/SCC callee regardless of a future descent discharge;
shipped before (c), it strands legitimate total recursion with no re-admission path. Fix D3 at the
hash; let (b) be the fail-closed default (c) lifts. Bite: blocks the (b)-alone path.

**2. `descent-refuted` overclaims.** Soundness-of-report / claim-accuracy. A SAT model for
`pre ∧ path ∧ ¬(e′ < e)` refutes *the declared measure*, not the function (which may terminate under
another measure). Collides with `refuted` (`§4.4:533`, postcondition disproved). Keep the hard failure
(Dafny, LPAR-16 §3) but rename measure-scoped (`measure-not-decreasing`), applying the project's own
v0.14.2 `spec-inconsistent → spec-inconsistent-or-unproven` discipline reflexively. Bite: complicates
(rename before the vocabulary ossifies).

**3. Option-3 now grades the same program two ways.** Spec-drift / soundness-of-composition.
`cascading-refinement-proposal.md:90-94` degrades a spawn-created cycle to contract-only; a hand-written
cycle now gets body-faithful partial correctness (`§0.1:13`). Provenance-dependent tier — the category
error the trust model precludes. The (a) marker is the unifying repair. Bite: complicates both
proposals; reconcile in one place.

**4. Single-int-slice cannot verify tie-breaking mutual recursion; fail-closed hides it as "unproven."**
Decidability / ergonomic. The shared-measure rule handles decrementing mutual recursion but not the
lexicographic/tagged combination (McCarthy-91 / Ackermann). Fail-closed keeps it sound but the
diagnostic should distinguish "no measure declared" from "well-formed but a single int slice can't
discharge this cycle." Bite: matters for the emergent-decomposition use case.

**5. (b) refuses some genuinely-total functions — name the scope boundary.** Scope. Recursion total for
a reason QF-LIA can't see (structural recursion on an opaque `list`/`string` carrier) is refused by (b)
and unrescued by (c). Strict-core totality is now *decidable-measure* totality; such functions route to
`def-shell` + partial mark or to Lean. A scope divergence from Dafny/LH, not a defect — state it.

## Recommendation

Split into three independently-sound increments: (1) close probe E at the hash now (no blanket (b));
(2) ship (a) + reconcile D1/D2/Option-3; (3) ship (b1)+(c) together, (b1) the fail-closed default, (c)
the well-founded lifter.

**Q1 (evidence-independence in the certified-compilation/PCC literature).** The principled statement is
*circular assume-guarantee is sound only with a well-founded discharge* (Abadi–Lamport 1995; McMillan
1999); the PCC-native form is step-indexing (Appel–McAllester 2001) / the ▷ modality (Nakano 2000). The
descent measure IS the step-index: `e′ < e` is the "one step later" side condition; (b) is the
degenerate case where no index is declared so the assumption is unusable. This subsumes "evidence
independence"; SCC membership is the operational proxy for "this edge closes a circle with no index."

**Q2 (single-int-slice vs lexicographic surface).** Decouple surface from discharge. Ship the surface
as a list `(decreases e₁ … eₖ)` from day one (Dafny/LH take a metric list) so the schema field never
re-bumps; discharge only k=1 in v1, emit a specific diagnostic for k>1, keep the SCC partial-marked.
Single-int-slice *discharge* is defensible for v1; single-int-slice *surface* is not.

## Open questions for the language-team

1. Confirm the hash-preimage fix closes probe E across a module boundary: the read-side recompute is
   same-module (`TrustReport.hs:454-455`), imported evidence is seeded from `meStatements`
   (`FixpointEmit.hs:315`) — specify where the def-form enters the preimage so a cross-module flip is
   caught.
2. State the totality claim's new scope: "total" or "total modulo a decidable-measure witness"? The
   distinction governs whether `§3.4.3` precondition 2 reads "non-recursive or descent-discharged" or
   the stronger "… by a QF-LIA measure."
