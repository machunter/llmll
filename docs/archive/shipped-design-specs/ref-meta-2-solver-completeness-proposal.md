# REF-META-2 — Solver-Completeness Statement (Auto-Discharge Boundary)

> **Version:** Rev 2 — professor review folded (local-theory-extension rebasing of the measure-class completeness; ground-fact emission precondition extending REF-META-3 M4; literal-coefficient-multiplication conservatism finding; convexity / QF-NIA precision fixes). Rev 1 (2026-06-12) drafted the `Σ_auto` partition and the completeness statement.
> **Date:** 2026-06-12 (Rev 1; Rev 2)
> **Implements:** `docs/compiler-team-roadmap.md` v0.12 post-freeze lane, REF-META-2; [`docs/design/v0.12-direction.md §1`](v0.12-direction.md) (REF-META-2 row — "which QF-LIA-shaped predicates are guaranteed to discharge vs which fall back to `?proof-required`").
> **Prerequisites:** REF-META-1 (Settled, promoted — `LLMLL.md §3.4.3` soundness statement; the QF-LIA completeness assertion at `§5.3.3:893`); REF-META-3 (Settled, promoted — `LLMLL.md §3.4.4` `Σ_ref` partition + measure discipline M1–M4). REF-META-2 classifies on the **same `Σ_ref` partition** §3.4.4 defines and **extends M4** with an emission side-condition (§4).
> **Origin:** v0.12 REF-META-2, parallel to REF-META-3. Supplies the *decidability* (auto-discharge) companion to REF-META-3's *legality* (well-formedness). Largely consolidates and formalizes assertions already present in `LLMLL.md §5.3.3` (the QF-LIA matrix row, the outside-QF-LIA routing, the refinement-alias routing paragraph, the completeness assertion).
> **Reviewed:** Professor review (2026-06-12, in-conversation) — recommendation `affirm-with-additive-folds`. Four findings folded into Rev 2 (see `## Appendix — Professor review log`); the architecture (`Σ_auto ⊊ Σ_ref`, the auto/manual boundary, the REF-META-3 interface) was affirmed, not contested. No standalone `-review.md` produced; folded directly per the REF-META-1/3 appendix pattern.
> **Status:** Settled (Rev 2) — professor review folded; spec-track only (the boundary-moving measure emission and the named ground-fact precondition are owned by the downstream non-int-widening engineer build). Pending documentation-lead promotion to `LLMLL.md §5.3.3`.

---

## 1. Motivation

REF-META-3 (`LLMLL.md §3.4.4`) settled *which refinement predicates are legal* (the well-formedness signature `Σ_ref`). It deliberately held legality orthogonal to *which predicates the verifier decides automatically*, forward-referencing that question here. REF-META-2 supplies it: the **solver-completeness statement of record** — given a well-formed obligation, the precise boundary between those liquid-fixpoint/Z3 is *guaranteed* to decide (SAFE/UNSAFE) and those that necessarily route to runtime assertion or `?proof-required`.

This is not a new claim. `LLMLL.md §5.3.3` already asserts it in scattered prose: the QF-LIA matrix row (`§5.3.3:866`), the "contracts outside QF-LIA are flagged `?proof-required` when detected non-linear" routing (`:872-875`), the refinement-alias predicate routing paragraph (`:878`), and the completeness assertion ("liquid-fixpoint/Z3 is a sound-and-complete decision procedure for the fragment", `:893`). REF-META-2 consolidates these into a single statement, classifies on REF-META-3's `Σ_ref` partition, and — the one substantive addition — states precisely *why* the measure class is decidable-and-complete and *under what emission discipline*.

REF-META-2 + REF-META-3 together fully characterize a refinement obligation: **REF-META-3 = legality (well-formedness); REF-META-2 = decidability (auto-discharge).**

---

## 2. Scope

**In scope.** The auto-discharge signature `Σ_auto` and its relationship to `Σ_ref`; the completeness statement of record; the decidability basis for each class (with the load-bearing local-theory-extension justification for the measure class); the emission side-condition that makes the measure-class completeness operationally true; the per-class verification mapping.

**Out of scope.** The well-formedness judgment (REF-META-3). The path-(a) measure-emission extension and the `FixpointIR` function-sort/`FQApp` machinery that *move* the measure class into `Σ_auto` — owned by the non-int-widening engineer build; named here as a precondition, not built. Any pre-folding normalization that would widen `Σ_auto` to literal-coefficient multiplication (Risk 1 — future engineer optimization). No surface, schema, `trust_report_version`, or version change.

---

## 3. The completeness statement of record

Define the **auto-discharge signature** `Σ_auto` as the subset of `Σ_ref` (§3.4.4) for which liquid-fixpoint/Z3 is a complete decision procedure:

```
  Σ_auto  =  QF-LIA core  ∪  ( measure class  |  path-(a) emission )
  Σ_auto  ⊊  Σ_ref          ( boolean-builtin class ∈ Σ_ref \ Σ_auto )
```

**Statement (REF-META-2).** *For an obligation `O` whose predicate uses only symbols in `Σ_auto`, liquid-fixpoint/Z3 is a sound-and-complete decision procedure: it returns SAFE or UNSAFE on the fixed VC, and "SAFE" is a decidable side-condition on that VC — not a quantifier over solver runs. For an obligation using any symbol outside `Σ_auto` — nonlinear integer arithmetic, the boolean-builtin class, or (vacuously) quantifiers — no completeness guarantee holds; the obligation routes to runtime assertion and is flagged `?proof-required` when its non-decidability is detected.*

The statement rests on three decidability facts.

### 3.1 QF-LIA core → complete

Quantifier-free linear integer arithmetic is decidable (NP-complete); Z3 is a complete decision procedure for it. The verifier operates under unbounded mathematical integers ([`FixpointEmit.hs:188-194`](../../compiler/src/LLMLL/FixpointEmit.hs), LT-INT), so the fragment is genuine QF-LIA, not bounded `Int64`. This is the `§5.3.3:893` assertion, restated as the base case.

### 3.2 Measure class → complete as a *local theory extension*, conditional on path-(a)

A measure emitted per REF-META-3 M4 as a single uninterpreted function symbol places the obligation in **QF-LIA + EUF** carrying the range axiom `∀s. m(s) ≥ 0`. The completeness here does **not** follow from a bare Nelson–Oppen combination of two quantifier-free theories — Nelson–Oppen combines *quantifier-free* theories and does not, by itself, license adding a *universally quantified* axiom to EUF. The correct and stronger basis is **local theory extensions** (Sofronie-Stokkermans, *Hierarchic Reasoning in Local Theory Extensions*, CADE 2005):

- The range axiom is a single universal clause whose only function symbol is `m : τ → int`, and whose body introduces no new τ-term (it yields an `int` that never feeds back into `m`).
- In any obligation only finitely many ground measure-terms `m(t₁) … m(tₖ)` occur. Instantiating the axiom at exactly those terms — assert `m(tᵢ) ≥ 0` per occurring term — is a **finite, terminating, non-recursive** instantiation: no matching loop, because the body spawns no fresh measure-applications.
- After that one-round ground closure, the obligation is back in pure quantifier-free QF-LIA + EUF, which is **decidable and complete**.

The post-instantiation QF-LIA + EUF problem decides without convexity: **LIA is non-convex** (`x = 1 ∨ x = 2` is entailed, neither disjunct alone), and the Nelson–Oppen combination remains decidable and complete via the **nondeterministic arrangement-guessing** variant. Convexity buys *efficiency* (deterministic combination), not completeness, and is therefore not a precondition.

**The measure class is not in `Σ_auto` today.** `exprToPred` returns `Nothing` for `string-length` / `list-length` ([`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs)), so measure predicates route to runtime. The class enters `Σ_auto` exactly when the path-(a) measure-emission extension lands (the non-int-widening engineer build) — under the emission discipline of §4.

### 3.3 Outside `Σ_auto` → no completeness

- **Nonlinear integer arithmetic** (`* / mod rem ^ **`): the genuinely-undecidable case. **QF-NRA is decidable** (Tarski; nlsat is a complete procedure for the reals — Jovanović & de Moura, IJCAR 2012), but **QF-NIA is undecidable** (Matiyasevich 1970, via Hilbert's 10th problem). Because LT-INT makes LLMLL `int` a *mathematical* integer, nonlinear obligations land in the undecidable **integer** case, not the decidable real one — which is why the correct routing is `?proof-required`, not "Z3 will eventually decide it." `exprToPred:676` rejects these (→ `Nothing`).
- **Boolean-builtin class** (`regex-match`): needs an SMT string/regex theory (path (b), deferred to v0.13+) → runtime / `?proof-required`; never auto in v0.12.

---

## 4. Emission side-condition (extends REF-META-3 M4)

The measure-class completeness (§3.2) is contingent on **how** path-(a) emits the range axiom. This proposal names the discipline as a precondition (REF-META-2 is spec-track; the emission itself is the non-int-widening engineer build, the same seam pattern as REF-META-3's `FixpointIR` function-sort extension):

> **M4 (extended).** Each measure is emitted as a single function-sorted uninterpreted symbol (REF-META-3 M4), **and its range bound is emitted as ground facts `m(t) ≥ 0` per occurring measure-term `t` — not as a quantified axiom `∀s. m(s) ≥ 0` left to Z3 E-matching / triggers.** Emitting the quantified form forfeits completeness: the solver may return `unknown`. M4's single-symbol discipline is what makes the per-term ground facts attach to the congruence-closed shared term.

This is the one finding the engineer must honor for the §3 completeness statement to be operationally true, not merely theoretically true.

---

## 5. Edge cases and degenerate inputs

### 5.1 Predicate mixing QF-LIA core and a measure function

**Input.** `(and (> x 0) (> (string-length s) 1))`.
**Behavior.** Well-formed (REF-META-3), but **not auto-discharged today** — the `string-length` conjunct hits `exprToPred:682` → `Nothing`, so the whole obligation routes to runtime; the QF-LIA conjunct does not rescue the compound. Auto once path-(a) lands, at which point the predicate is QF-LIA + EUF (§3.2).
**Channel.** Contract; fragment **measure-conditional**.
**Cite.** [`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs); §3.4.4 measure class.

### 5.2 Multiplication — constant-foldable and literal-coefficient

**Input.** `(> (* 2 2) x)` and `(> (* 2 x) 4)`.
**Behavior.** **Not auto-discharged today** — `exprToPred:676` rejects `*` **unconditionally**, and the `allLitsInBounds` folder ([`FixpointEmit.hs:628-634`](../../compiler/src/LLMLL/FixpointEmit.hs)) is a separate Int64 overflow-taint mechanism, not predicate emission. This is conservative **below QF-LIA itself**: multiplication by an integer literal is **linear** — `k·x` is in QF-LIA by definition (linear combinations `Σ kᵢxᵢ`), hence decidable and Z3-complete. So the impl drops not only constant-foldable products but the entire **literal-coefficient class** (`(* 2 x)`, `(* x 3)`).
**Channel.** Contract; fragment **QF-LIA-but-impl-rejected**.
**Cite.** [`FixpointEmit.hs:676`](../../compiler/src/LLMLL/FixpointEmit.hs). See Risk 1.

### 5.3 A WF predicate that `exprToPred` returns `Nothing` for

**Input.** Any well-formed predicate outside the emitter's QF-LIA fragment (a measure call today; nonlinear arithmetic; a boolean builtin).
**Behavior.** Routes to **runtime assertion** (contract-only verification), and is **automatically** flagged `?proof-required` *when the predicate is detected non-linear or induction-requiring* (`§5.3.3:872-875`). The fallback is automatic — the author need not hand-write `?proof-required` for the runtime routing. A predicate that is `Nothing` for a non-nonlinear reason (e.g. an un-axiomatized measure call) routes to runtime without necessarily carrying the nonlinear flag.
**Channel.** Trust (outside type/contract auto).
**Cite.** `LLMLL.md §5.3.3:872-875`.

### 5.4 Quantifier-shaped predicate

**Input.** `∀` / `∃` inside a refinement.
**Behavior.** **Cannot arise.** REF-META-3 W-FirstOrder forbids refinement variables and unsaturated application; the WF predicate surface is quantifier-free by construction, so quantifier alternation never reaches the solver from a `where`-predicate.
**Channel.** Spec is silent (intentional) — precluded upstream at the WF rule.
**Cite.** `LLMLL.md §3.4.4` (W-FirstOrder).

---

## 6. Verification mapping

| Predicate class | Channel | Fragment / decidability | Cite |
|---|---|---|---|
| QF-LIA core (`+ - = ≠ < ≤ > ≥ and or not`, int/bool lits, bound var) | contract | **QF-LIA — auto, complete** (Z3 complete decision procedure) | [`FixpointEmit.hs:662-681`](../../compiler/src/LLMLL/FixpointEmit.hs); §5.3.3:866,893 |
| Measure class (`string-length`, `list-length`) | contract | **QF-LIA+EUF — complete as a *local theory extension* (Sofronie-Stokkermans 2005) via finite ground-instantiation; conditional on path-(a); runtime today** | [`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs); §3.4.4; REF-META-3 M4 |
| **Path-(a) emission side-condition** | — | **Range bound emitted as ground facts `m(t) ≥ 0` per measure-term, NOT a quantified axiom** — required for the measure-class completeness to hold operationally | owned by the non-int-widening engineer build (named precondition) |
| Nonlinear integer arithmetic (`* / mod rem ^ **`) | contract | **QF-NIA — undecidable (Matiyasevich 1970); decidable-real QF-NRA does not apply under LT-INT** → `?proof-required` | [`FixpointEmit.hs:676`](../../compiler/src/LLMLL/FixpointEmit.hs); §5.3.3:875 |
| Boolean-builtin class (`regex-match`) | trust | **outside QF-LIA — not auto in v0.12** (needs SMT Str/regex, path b); runtime / `?proof-required` | §5.3.3:870-875; §3.4.4 |
| Quantified predicate | — | **cannot arise** (W-FirstOrder precludes) | §3.4.4 |

REF-META-2 introduces **no new SMT obligation** — it characterizes the discharge fate of obligations the existing channels already emit. Spec-track only.

---

## 7. Affected surface

- **`LLMLL.md §5.3.3`** — consolidate the scattered completeness assertions (`:866`, `:872-875`, `:878`, `:893`) into a single **§5.3.3 "Solver-completeness statement (REF-META-2)"** subsection carrying the `Σ_auto` partition, the statement of record, the local-theory-extension basis for the measure class, and the emission side-condition; add the measure-conditional and quantifier-precluded rows; align the QF-LIA matrix row with the code (Risk 2). *(doc-lead promotion after settlement.)*
- **`docs/design/ref-meta-2-solver-completeness-proposal.md`** — this file. INDEX one-liner row.
- **No `compiler/src/LLMLL/` change** (spec-track only). The measure-class path-(a) emission that *moves* the boundary — including the §4 ground-fact discipline — is owned by the non-int-widening engineer build, named here, not built.
- **No schema, no `trust_report_version`, no CHANGELOG/version bump.**

---

## 8. Risks and open questions

1. **Literal-coefficient multiplication is QF-LIA but impl-rejected.** *Classify:* verification-ergonomics. *Cite:* [`FixpointEmit.hs:676`](../../compiler/src/LLMLL/FixpointEmit.hs). *Bite:* only at scale, but the surface is larger than "constant-folding" — `k·x` predicates (scaling, unit conversion, `2*n` bounds) are common in agent contracts and all route to runtime. A normalization recognizing literal-coefficient multiplication would widen `Σ_auto` **within the same decidable fragment** — no theory extension, no soundness cost. Documented boundary + future engineer optimization; out of REF-META-2 (spec-track) scope.
2. **`§5.3.3:866` QF-LIA matrix under-lists the code.** *Classify:* spec-drift. *Cite:* `§5.3.3:866` vs [`exprToPred:672,677-679`](../../compiler/src/LLMLL/FixpointEmit.hs). *Bite:* complicates only — the row omits `≠` and the boolean connectives `and`/`or`/`not`; doc-lead corrects on promotion (in-scope, not a code change).
3. **Measure-class boundary is conditional on unshipped engineer work.** *Classify:* scope. *Cite:* §3.4.4, [`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs). *Bite:* the statement must phrase the measure class as "complete *iff* path-(a) under the §4 emission discipline"; stating it as currently-auto would be a code lie. Handled in §3.2 and the §4 side-condition.

---

## Appendix — Professor review log

Professor review (2026-06-12, in-conversation), recommendation `affirm-with-additive-folds`. The architecture (`Σ_auto ⊊ Σ_ref`, the auto/manual boundary, the REF-META-3 interface) was affirmed. Four findings, all folded into Rev 2:

- **F1 (→ §3.2).** The measure-class completeness does not follow from a bare Nelson–Oppen of two quantifier-free theories — that does not license the universally-quantified range axiom. Rebased to **local theory extensions** (Sofronie-Stokkermans, CADE 2005): complete by finite, terminating, non-recursive ground-instantiation of the range axiom at the obligation's measure-terms. Stronger than a "modulo-guard" softening — recovers genuine completeness.
- **F2 (→ §4, verification mapping).** The completeness is contingent on emission: the range bound must be emitted as **ground facts `m(t) ≥ 0` per measure-term**, not a quantified axiom left to E-matching (which forfeits completeness → `unknown`). Added as an explicit M4 extension and a named engineer precondition.
- **F3 (→ §5.2, Risk 1).** The conservatism finding is larger than constant-folding: `exprToPred:676` rejects `*` unconditionally, but **literal-coefficient multiplication `k·x` is genuinely QF-LIA**. Reframed as "conservative below QF-LIA itself."
- **F4 (→ §3.2, §3.3).** (a) Removed "convexity" from the Nelson–Oppen preconditions — LIA is non-convex, the combination is still complete via the nondeterministic variant; convexity buys efficiency, not completeness. (b) Sharpened the nonlinear claim with the QF-NRA-decidable vs QF-NIA-undecidable asymmetry (Matiyasevich 1970) and the LT-INT consequence.
