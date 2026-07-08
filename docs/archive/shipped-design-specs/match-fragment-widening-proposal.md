---
name: match-fragment-widening-proposal
title: "MATCH-WIDEN — body-faithful verification of mixed-arm / sequential / nested matches"
status: "Rev 1 (professor folded) — ready for engineer feasibility read"
date: 2026-07-06
author: language-team
consumers: [professor, compiler-engineer]
---

# MATCH-WIDEN — widening the body-faithful EMatch fragment

## Restatement

The strict-core body-faithful fragment (`def`) admits only three `EMatch` shapes. Any richer
case-analysis — a two-arm sum with **mixed** nullary-and-payload arms, two **sequential** matches
in one body, or a **nested** match in an arm — falls out of the `verified` tier: the mixed-arm case
is *hard-rejected* at the syntactic gate ("unrestricted match"), while the sequential/nested cases
*pass* the syntactic gate but the body-VC emitter does not thread them, so they silently degrade to
`body-fallback` (post exported only `asserted`). The consequence is that any non-trivial control
flow — an error-propagation pipeline being the canonical case — must be atomized into trivial
single-`match` leaves plus a `def-shell` spine whose safety rides on call-preconditions. This
proposal widens the body-faithful `EMatch` fragment to admit these shapes, and argues the widening
is **decidability-preserving** — it stays inside `Σ_auto`, so it is an engineering restriction, not
a soundness boundary. It is the control-side sibling of `data-scope-extension.md` (the data-side
widening): that document's Lever C (recursion/induction) genuinely *leaves* `Σ_auto`; this proposal
does not.

## Context located

1. `compiler/src/LLMLL/Syntax.hs:673–709` — `isCoreBodySyntactic`; the `EMatch` clause (683–694)
   admits exactly three shapes (Result two-arm, all-nullary-enum N-arm, both-single-payload two-arm).
   **This is Gap 1** (the hard reject).
2. `compiler/src/LLMLL/TypeCheck.hs:825–829` — `checkStatement (SDef …)` gates on
   `isCoreBodySyntactic`, emitting `mkCoreGrammarViolation` ("unrestricted match") on failure.
3. `compiler/src/LLMLL/FixpointEmit.hs:600–650` — the body-VC `EMatch` path; `resultKeys`/`adtKeys`
   seed the `SortEnv` **per parameter** for `TResult` and for `TSumType [(c1, Just t1),(c2, Just t2)]`
   (both arms payload-bearing, both `admissiblePayload`). A nullary arm (`Just`/`Nothing` asymmetry)
   is not seeded, and the seeding is param-scoped/single-scrutinee. **This is Gap 2** (the silent
   fallback).
4. `compiler/src/LLMLL/FixpointIR.hs:299–301` — FQData lowering: "an admissible sum carries REAL
   fields (`ctor_i : sort`); inadmissible (recursive) and nullary ctors emit `{ }`." The nullary-tag
   discharge machinery already exists (COMP-3c); it is not yet composed with a payload arm.
5. `LLMLL.md §5.3.5` (row at `:404`): `def | SDef | … two-arm sum EMatch [Result / both-single-payload
   user ADT] … | verified`. This is the spec row the proposal widens (doc-lead's slot to edit).
6. `docs/compiler-team-roadmap.md` COMP-4 / PAIR-RET lines — built the *current* match discharge along
   the **payload-type** axis (what payloads discharge). This proposal is the **match-structure** axis
   (what match *shapes* discharge); it extends the same line and should be tracked as its successor
   (suggest tag `COMP-5` / `MATCH-WIDEN`). No in-flight draft on this axis exists in `docs/design/`
   (checked INDEX + grep); this is a from-scratch proposal.
7. `compiler/src/LLMLL/CodegenHs.hs:657–669` — exhaustiveness is handled at *codegen* (catch-all
   insertion, Either/Bool suppression); no hard *type-check-time* totality gate on user sums was
   located. Flagged below as a soundness precondition (Risk 2).

**Drift note.** `LLMLL.md §5.3.5:404` describes the admitted match set in prose ("both-single-payload
user ADT") that matches `Syntax.hs` but omits the all-nullary-enum disjunct (`isNullaryEnumArm`,
Syntax.hs:689) that the code also admits. Minor spec/code drift; doc-lead should reconcile the row
when this lands regardless.

## Design proposal

The current fragment is a coincidence of two independently-narrow components. The fix is two
independent widenings that compose.

### Gap 1 — the syntactic gate (`isCoreBodySyntactic`, Syntax.hs:683–694)

The `EMatch` clause admits an arm-set only if it is (Result two-arm) ∨ (all-nullary) ∨
(both-single-payload two-arm). A **mixed** two-arm sum — one nullary arm, one single-payload arm,
e.g. `Step = (| Continue) (| Abort int)` or `Verdict = (| Verified) (| Rejected int)` — satisfies
none, so a body matching on it is rejected outright.

**Proposed rule.** Admit an `EMatch` when every arm pattern is one of `{PWildcard, PVar,
PConstructor c []` (nullary)`, PConstructor c [PVar _]` (single-payload)`}`, the scrutinee's declared
type is an **acyclic** (non-recursive) sum, and the arm-set is **exhaustive and non-overlapping** for
that type. Arm count is the constructor count of the sum (bounded, finite); no fixed "two-arm" cap is
needed once the discharge (Gap 2) is arm-count-generic. Recursion stays excluded by the existing
`admissibleDatatype` acyclicity check — the syntactic gate defers the acyclicity decision to the
emitter's firewall, which already refuses recursive sums.

### Gap 2 — the body-VC emitter (`FixpointEmit.hs:600–650`)

Two limitations: (a) the sum seeding pattern `TSumType [(c1, Just t1),(c2, Just t2)]` requires both
arms payload-bearing, excluding mixed and nullary arms; (b) seeding is single-scrutinee/param-scoped,
so a second or nested match in the same body is not threaded and the whole body falls back.

**Proposed generalization.** Treat a body as a **case tree** and generate the VC by structural
recursion over it, threading an accumulating **path condition** `Γ` (a conjunction of
constructor-equality literals). For an `EMatch scrut arms` under path condition `Γ`:

- bind the scrutinee's discriminant and (if present) its injective selector: arm `i` extends `Γ` with
  `is-Cᵢ(⟦scrut⟧)` and, for a single-payload arm, `pᵢ = selᵢ(⟦scrut⟧)`;
- recurse into arm `i`'s body under `Γ ∧ is-Cᵢ(⟦scrut⟧) [∧ pᵢ = selᵢ(…)]`;
- the arm's contribution is the implication `(Γ ∧ path_i) ⇒ post[arm_i/result]`.

The obligation for the whole body is the finite conjunction over root-to-leaf paths. A **nullary**
arm contributes only the discriminant literal `is-Cᵢ(⟦scrut⟧)` (no selector) — this is exactly the
COMP-3c nullary-tag term (FixpointIR.hs:299–301), now composed with a payload sibling rather than
required to be uniform. This subsumes the three current shapes as special cases (single two-arm
match = a depth-1 tree).

**Passive-form VCgen keeps the VC polynomial (Rev 1 correction).** The Rev 0 concern that nested
matches blow up "exponential in depth" was overstated. A genuine *nested* match (a match inside an
arm body) has a leaf count equal to the **syntactic** number of arm-bodies — linear in program size,
no explosion. A product of arm counts arises only for **independent multi-scrutinee** combinations
where the postcondition couples several scrutinees. The on-point technique for that case is
**passive-form / SSA VCgen** — Flanagan & Saxe, *Avoiding Exponential Explosion: Generating Compact
Verification Conditions* (POPL 2001) — which names intermediate results so the VC is polynomial
rather than a path product. The existing `aNormalizeBody` pass (FixpointEmit, shipped v0.14.11 for
arg-position calls) is a special case of this: let-binding each match's result to a fresh binder
gives a *sequential* pipeline a VC *linear* in the number of matches. No depth budget is needed; the
Rev 0 Slice-3 budget is struck.

### Semantics (inference-rule form)

Let `⊢_Γ e ⇝ φ` mean "under path condition `Γ`, `e`'s body-VC is `φ`." **The rule must be
first-match/ordered (Rev 1).** Real match semantics is ordered — `CodegenHs.hs:651` emits a Haskell
`case`, and the fragment already admits `PWildcard`/`PVar` catch-alls (`Syntax.hs:704–706`). An arm's
verification-side path condition is therefore the conjunction of its own discriminant with the
**negation of every earlier arm's pattern**, not a bare tester. Let `patᵢ(⟦s⟧)` be arm `i`'s pattern
condition (`is-Cᵢ(⟦s⟧)` for a constructor arm, `⊤` for a wildcard/variable arm), and
`x̄ᵢ = selᵢ(⟦s⟧)` its payload binding (empty for nullary/wildcard). For a scrutinee `s : T`, `T` an
acyclic sum, arms `((patᵢ x̄ᵢ) eᵢ)` exhaustive:

```
   T acyclic sum,  arms exhaustive over C₁…Cₙ   (checkExhaustive, TypeCheck.hs:1136)
   for each i:   Γᵢ = Γ ∧ (⋀_{j<i} ¬patⱼ(⟦s⟧)) ∧ patᵢ(⟦s⟧) ∧ (x̄ᵢ = selᵢ(⟦s⟧))     ⊢_Γᵢ eᵢ ⇝ φᵢ
   ────────────────────────────────────────────────────────────────────────────────────  (VC-Match)
   ⊢_Γ (match s ((pat₁ x̄₁) e₁) … ((patₙ x̄ₙ) eₙ))  ⇝  ⋀ᵢ φᵢ
```

`is-Cᵢ`/`selᵢ` are the tester/selector of the SMT acyclic-datatype theory. The rule is the standard
weakest-precondition of *ordered* case-analysis. The `⋀_{j<i} ¬patⱼ` prefix is what makes a
catch-all's path condition correct (it covers exactly the constructors not matched above); dropping
it — the Rev 0 non-overlap simplification — is unsound for any overlapping arm-set. **The
implementation must reconcile with the existing all-nullary-enum desugar (COMP-3b-general nested
int-tag `if`s, `Syntax.hs:687–689`), which already realizes first-match ordering, rather than emit a
parallel path.** The LLMLL-specific side conditions are `T` acyclic (firewall) and exhaustiveness
(TypeCheck, see Risk 2).

## Edge cases and degenerate inputs

1. **Positive witness (the firing case) — mixed-arm nested pipeline.** Concrete:
   ```lisp
   (type Step    (| Continue) (| Abort int))
   (type Verdict (| Verified) (| Rejected int))
   (def finalize [a: Step b: Step sig: Step] -> Verdict
     (post (or (not (= result Verified)) (= sig Continue)))
     (match a ((Abort c) (Rejected c))
              ((Continue) (match b ((Abort c) (Rejected c))
                                    ((Continue) (match sig ((Abort c) (Rejected c))
                                                           ((Continue) Verified)))))))
   ```
   **Today:** hard-rejected ("unrestricted match", Gap 1). **Under the proposal:** `verified` — the
   only path reaching `Verified` carries `is-Continue(sig)`, discharging the post. The goto-fail twin
   (drop the innermost `match sig`, return `Verified` in `b`'s `Continue` arm) is **refuted**: the
   path `is-Continue(a) ∧ is-Continue(b)` reaches `Verified` without `is-Continue(sig)`, so the SMT
   finds `sig = Abort c` as a counterexample. Channel: **contract**. (This is the reduced core of the
   CVE-2014-1266 example; the `def-shell` single-`match` reduction verifies today, confirming the
   invariant is expressible — the gap is purely the multi-match *body shape*.)
2. **Non-exhaustive match (Rev 1: coverage already enforced).** `(match s ((Continue) e))` on `Step`
   (missing `Abort`). Expected: **rejected at type-check** — `checkExhaustive` (`TypeCheck.hs:1446`,
   wired into `inferExpr (EMatch …)` at `:1136`) computes the missing constructors of a `TSumType`
   (and `TResult`/`TBool`) and emits `tcEmitNonExhaustive`, a hard non-exhaustive-match error; a
   wildcard/variable arm satisfies coverage. Channel: **type**. **Rev 1 correction:** the Rev 0 "spec
   is silent — flag Risk 2" was wrong. The professor suspected no coverage gate existed; inward
   reading found one, wired, first-order, covering mixed-arm `TSumType` generically. `CodegenHs.hs:673`'s
   "trust the type-checker" is therefore justified, not drift. Residual to confirm (engineer): that
   `tcEmitNonExhaustive` is error-severity (not a warning) so a non-exhaustive match cannot reach
   `verified`. See Risk 2.
3. **Recursive scrutinee (firewall) — and a behavior change (Rev 1).** `(match xs ((Cons h t) …)
   ((Nil) …))` on a recursive `IntList`. Expected: **falls back** (`body-fallback`), not admitted —
   the `admissibleDatatype` acyclicity check (FixpointEmit.hs:73, `data-scope-extension.md` Post 5)
   refuses the sort; the syntactic gate defers to it. Channel: **trust** (fallback). **Rev 1
   behavior change to name:** under the deferring design a recursive-datatype match moves from
   *today's* hard `unrestricted match` error (Syntax.hs:683–694 rejects it up front) to a *silent*
   `body-fallback` (asserted). Consistent with the rest of the fallback model, but user-visible; the
   engineer should confirm the fallback is preferred over preserving the error.
4. **Overlapping / redundant arms (first-match).** `(match s ((Continue) e₁) ((Continue) e₂))`, or a
   specific-then-catch-all `((Continue) e) ((_) f)`. Expected: **first-match semantics** — arm 2's
   path condition is `¬pat₁ ∧ pat₂` (VC-Match, Rev 1), so a fully-shadowed arm is dead (its Γ is
   unsatisfiable, VC vacuous) and a catch-all covers exactly the residual constructors. Channel:
   **contract** (the ordered VC) + **type** (redundancy warning). This edge case is why the Rev 0
   non-overlap rule was unsound.
5. **Nullary-only construction in an arm.** `((Continue) Verified)` — constructing the nullary
   `Verified`. Expected: discharges by tag equality `is-Verified(result)` (COMP-3c machinery,
   FixpointIR.hs:299), now used *within* a mixed-arm sum rather than an all-nullary enum. Channel:
   **contract**.
6. **Branch-skolem interaction with R5 (cross-proposal).** A MATCH-WIDEN'd body binds each arm
   payload as an independent skolem (`FixpointEmit.hs:1782`). Expected: correct for the body-VC, but
   `differential-implementation-pressure-proposal.md:36` gates R5 stage-3 witness generation on
   *branch-skolem-free* bodies — so widening match discharge **shrinks** the set of bodies eligible
   for R5 stage-3 equivalence checking. Channel: **trust** (R5 coverage). Not a MATCH-WIDEN soundness
   issue; the two proposals must cross-reference so R5's coverage contraction is intentional, not
   silent.

## Verification mapping

Every obligation the proposal introduces is a per-path implication `(Γ ∧ path_i) ⇒ post[arm_i/result]`.

- **Channel:** contract (the body-VC), with a **type**-channel side condition (exhaustiveness +
  non-overlap coverage) and the existing **trust**-channel firewall (acyclicity → fallback).
- **Fragment:** **QF-LIA + datatype theory**, auto-discharged by liquid-fixpoint. Each path condition
  is a finite conjunction of tester/selector literals (`is-Cᵢ`, `selᵢ`) plus prior-pattern negations,
  polite-combined with QF-LIA. The number of paths is finite (bounded by syntactic match-tree size),
  so the VC is a finite quantifier-free formula. **No new theory, no quantifiers** ⇒ inside `Σ_auto`;
  "SAFE" stays a decidable predicate on a fixed VC (`§3.4.5` Theorem B preserved).
- **Decidability framing (Rev 1 correction).** The Rev 0 prose implied "acyclic ⇒ decidable,
  recursive ⇒ undecidable." That is imprecise: the **quantifier-free theory of *recursive* datatypes
  is itself decidable** (Barrett, Shikanian & Tinelli, *An Abstract Decision Procedure for the Theory
  of Recursive Data Types*, 2007) — a one-level `match` on a `list` (is it `Nil` or `Cons`?) is
  decidable. What is undecidable is reasoning that **unfolds recursive definitions / measures** —
  induction — which is a *different* obligation (`data-scope-extension.md` Lever C), not case-analysis.
  MATCH-WIDEN therefore stays in `Σ_auto` because it is a finite case-split, **not** because the
  datatype is acyclic. The `admissibleDatatype` firewall the proposal keeps is a **`Σ_auto`-definition
  / erasure-theorem** choice (`§3.4.5` excludes recursive-datatype VCs wholesale), **not** a
  decidability necessity. Keeping it is correct for project consistency; the *reason* is the erasure
  theorem, not intractability.
- **Combination (professor convergence — keep).** The invocation of **polite** theory combination
  (not plain Nelson–Oppen) is precisely right: the theory of datatypes is *not* stably infinite (a
  nullary enum like `Bool` has finite models), so Nelson–Oppen does not apply directly; politeness
  (Ranise–Ringeissen–Zarba 2005; Jovanović–Barrett, *Polite Theories Revisited*) is exactly the
  property that licenses the datatype + QF-LIA combination. Professor and language-team converge here.
- **Contrast with the data-side sibling.** `data-scope-extension.md` Lever C (recursion/induction)
  *leaves* `Σ_auto` — its VC needs measure unfolding / induction, undecidable in general. MATCH-WIDEN
  does not: it never unfolds a recursive definition, only splits on a constructor. This is the crux
  distinction and the reason the two siblings have very different cost/tier profiles.

## Affected surface

- `compiler/src/LLMLL/Syntax.hs:683–694` — widen the `EMatch` clause of `isCoreBodySyntactic`
  (Gap 1). Requires an acyclicity-aware or acyclicity-deferring predicate.
- `compiler/src/LLMLL/FixpointEmit.hs:600–650` — generalize sum seeding to mixed/nullary arms and to
  a case-tree walk with path-condition threading (Gap 2); reuse `aNormalizeBody` for match-result
  let-binding.
- `compiler/src/LLMLL/FixpointIR.hs:299–301` — compose the nullary-tag term with a payload sibling in
  one sum (mixed-arm FQData).
- `compiler/src/LLMLL/TypeCheck.hs:1136,1446` — **`checkExhaustive` already exists and is wired** into
  `inferExpr (EMatch …)`; it covers `TSumType`/`TResult`/`TBool` first-order. Rev 1 work here is
  narrow: confirm `tcEmitNonExhaustive` is error-severity, and add first-match **redundancy** flagging
  (a fully-shadowed arm) — not a new coverage gate.
- `LLMLL.md §5.3.5:404` (doc-lead) — widen the `def` verification-matrix row; reconcile the drift
  noted above.
- `docs/compiler-team-roadmap.md` (doc-lead) — new `COMP-5 / MATCH-WIDEN` row.
- **No JSON-AST schema change.** The `EMatch` node already exists (`AstEmit.hs:310`,
  `docs/llmll-ast.schema.json`); the proposal changes *which* `EMatch` shapes discharge, not the node.

## Risks and open questions

1. **First-match ordering is a soundness requirement of the VC rule (Rev 1 — promoted to top).**
   *Soundness.* The Rev 0 `VC-Match` assumed non-overlapping arms; with catch-alls (already in the
   fragment, `Syntax.hs:704–706`) and ordered `case` codegen (`CodegenHs.hs:651`), an arm's path
   condition **must** carry the negation of all prior patterns (VC-Match, Rev 1). A non-ordered rule
   lets the body-VC assume the wrong arm fires ⇒ a `verified` post that the running program violates.
   *Bite: blocks* until the rule and emitter are ordered. **Latent-today flag:** catch-all arms are
   already admitted (all-nullary-enum disjunct), so the engineer must confirm the *existing*
   nested-int-tag desugar already computes prior-pattern negations — if it does not, this is a
   pre-existing soundness bug in the shipped fragment, not only a widened-fragment concern.
2. **Exhaustiveness (Rev 1 — downgraded from blocking).** *Totality / spec-drift.* The Rev 0 "may be
   unenforced, blocks the proposal" was **wrong**: `checkExhaustive` (`TypeCheck.hs:1446`, wired at
   `:1136`) already enforces first-order constructor coverage as a hard error over `TSumType`/`TResult`/
   `TBool`, covering mixed-arm sums generically; `CodegenHs.hs:673`'s "trust the type-checker" is
   justified. A crash on an uncovered path is a *totality* gap under partial correctness (`§5.3.5`
   letrec disclaimer), not a partial-correctness soundness hole. *Bite: does not block.* Residual:
   confirm `tcEmitNonExhaustive` severity (error, not warning) so a non-exhaustive match cannot reach
   `verified`; if it is a warning, route through the letrec-style partial-correctness disclaimer
   rather than a new gate.
3. **VC size (Rev 1 — de-escalated).** *Verification-ergonomics.* Genuine nested matches are linear in
   syntactic size (one obligation per arm-body); a product arises only for independent multi-scrutinee
   combinations, handled by passive-form VCgen (Flanagan–Saxe, POPL 2001; `aNormalizeBody` is a
   special case). *Bite: only at scale, and mitigated.* The Rev 0 depth budget is **struck** as
   premature.
4. **Firewall preservation.** *Soundness.* The acyclicity check must gate every widened path; a
   recursive sum must still fall back. *Bite: blocks if the syntactic gate widening bypasses the
   emitter firewall.* The deferring design (syntactic gate admits shape; emitter refuses recursive
   sort) keeps a single firewall site. Note (Rev 1): this is an `Σ_auto`-definition choice, not a
   decidability necessity (see Verification mapping).
5. **R5 stage-3 coverage contraction.** *Scope / cross-proposal.* Widened matches multiply branch
   skolems (`FixpointEmit.hs:1782`), which DIP stage-3 excludes
   (`differential-implementation-pressure-proposal.md:36`). *Bite: only matters at scale;* requires a
   cross-reference so R5's shrinking eligibility set is intentional.
6. **Scope creep toward guards / view patterns.** *Scope.* The proposal admits constructor patterns
   only (nullary + single-`PVar` payload) plus wildcard/variable catch-alls. Pattern *guards*, nested
   *constructor* payloads (`(Cons h (Cons …))`), and literal patterns stay OUT. *Bite: none if scoped
   as stated.*

## Scoped slices

- **Slice 1 — mixed nullary/payload sums.** Widen Gap 1 for two-arm mixed sums; extend Gap 2 seeding
  to `TSumType [(c1,Nothing),(c2,Just t)]` (and the symmetric case). *Acceptance:* the `finalize`
  single-level mixed-arm match verifies `body-faithful`; the skip-arm twin is `refuted`;
  `checkExhaustive` (already present) refuses a partial mixed match. *Depends on:* nothing new —
  coverage already exists (Risk 2); confirm the ordered VC-Match rule (Risk 1) lands with this slice.
- **Slice 2 — sequential matches.** Thread the case-tree walk across multiple top-level matches
  (via `let`/`if`), with `aNormalizeBody` let-binding match results. *Acceptance:* a two-match
  Result-threading body verifies `body-faithful` (today: `body-fallback`); VC size linear in match
  count.
- **Slice 3 — nested matches.** Case-tree walk into arm bodies (first-match ordered). **No depth
  budget** (Rev 1) — passive-form VCgen keeps genuine nesting linear. *Acceptance:* the 3-deep
  `finalize` pipeline verifies; a mid-pipeline skip is `refuted`.

## Out of scope

Recursion / inductive datatypes (the firewall; that is `data-scope-extension.md` Lever C, and it is
genuinely undecidable — do not conflate). Pattern guards. Nested-constructor payloads. Literal /
range patterns. Non-linear arithmetic in arm bodies (unchanged `isLinearOp` restriction). N-arm
*mixed* matches beyond the constructor count of the declared sum.

## Professor review — resolved (Rev 1)

Both Rev 0 open questions were adjudicated by the professor pass and are now closed:

1. **VC blow-up / decision-DAG.** *Resolved.* Maranget's decision-DAGs are *runtime* dispatch and do
   not transfer to VC size; the on-point result is passive-form/SSA VCgen (Flanagan–Saxe, POPL 2001).
   Genuine nesting is linear; the depth budget is struck. See Verification mapping and Risk 3.
2. **Coverage discipline.** *Resolved.* First-order coverage suffices — LLMLL has no dependent
   indices, so no constructor is context-excluded; dependent-pattern-matching coverage (Coquand 1992;
   Agda/Idris) is correctly *not* needed. Cited only to mark what is not bought. Confirmed inward:
   `checkExhaustive` (`TypeCheck.hs:1446`) already implements exactly this first-order discipline over
   `TSumType`/`TResult`/`TBool` and is wired at `:1136` — no interaction with COMP-4(b) refined
   payloads, which are LIA predicates on selectors, not coverage constraints.

## Rev 1 changelog (professor fold)

Folded the professor critique of Rev 0. Substantive changes:

1. **`VC-Match` rewritten as first-match/ordered** (Semantics) — each arm's path condition now carries
   `⋀_{j<i} ¬patⱼ`. The Rev 0 non-overlap rule was unsound for catch-all arms (which the fragment
   already admits). Promoted to **Risk 1 (soundness, blocks)** with a *latent-in-shipped-code* flag:
   the engineer must confirm the existing nested-int-tag enum desugar already computes prior-pattern
   negations, else the current fragment has a pre-existing soundness bug.
2. **Risk 2 (exhaustiveness) downgraded from blocking.** Inward reading located `checkExhaustive`
   (`TypeCheck.hs:1446`, wired `:1136`) — first-order coverage, hard error, mixed-arm-generic. The
   professor's suspected `CodegenHs.hs:673` drift does **not** bite; coverage is enforced. Reclassified
   as totality + a residual severity check, not a soundness blocker. (Language-team corrects the
   professor here; named in the edge-case table and Risk 2.)
3. **Decidability framing corrected** (Verification mapping) — QF theory of *recursive* datatypes is
   itself decidable (Barrett–Shikanian–Tinelli 2007); MATCH-WIDEN stays in `Σ_auto` because it is a
   finite case-split, not because the datatype is acyclic. The firewall is a `Σ_auto`/erasure-theorem
   choice, not a decidability necessity.
4. **Blow-up mitigation corrected** — cite Flanagan–Saxe (POPL 2001) passive-form VCgen; **struck the
   Slice-3 depth budget**; nested matches are linear.
5. **Edge cases + risks extended** — recursive-match *behavior change* (hard error → silent fallback)
   named; **DIP cross-reference** added (branch-skolem multiplication shrinks R5 stage-3 coverage,
   `differential-implementation-pressure-proposal.md:36`).
6. **Convergence kept** — the polite-combination invocation is affirmed correct (datatypes not stably
   infinite ⇒ Nelson–Oppen insufficient; politeness licenses datatype+LIA).

**Two findings are about shipped code, not just this proposal, and should route to the engineer
independently of the widening:** (i) the first-match/ordering property of the *current* enum desugar
(Risk 1 latent flag), and (ii) `tcEmitNonExhaustive` severity (Risk 2 residual).
