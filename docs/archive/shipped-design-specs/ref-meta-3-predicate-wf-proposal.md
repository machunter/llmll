# REF-META-3 — Predicate Well-Formedness Rule (Refinement-Aliased Type Surface)

> **Version:** Rev 2 — professor review folded (M4 UF-emission discipline; M2↔erasability identity; stacked-alias α-discipline; recursive-function admission gate; two-sub-class labeling). Rev 1 (2026-06-12) drafted the four-condition WF judgment and the measure discipline M1–M3.
> **Date:** 2026-06-12 (Rev 1; Rev 2)
> **Implements:** `docs/compiler-team-roadmap.md` v0.12 post-freeze lane, REF-META-3; [`docs/design/v0.12-direction.md §1`](v0.12-direction.md) (REF-META-2..5 sequencing, REF-META-3 row).
> **Prerequisites:** REF-META-1 (Settled Rev 2, promoted to [`LLMLL.md §3.4`](../../../LLMLL.md) — checking-mode rule §3.4.1, non-goals §3.4.2, soundness of record §3.4.3). This proposal fills the predicate well-formedness slot REF-META-1 §4.2 (closure-scope clarification) and §5.5 (Gap #5) explicitly deferred here.
> **Origin:** v0.12 kickoff (highest-leverage critical-path start — unblocks REF-META-4 and the §2 non-int refinement widening). The WF rule formalizes REF-META-1 non-goal #3 (the `factorial` exclusion) and enumerates the refinement-predicate-binding shapes admitted (REF-META-1 §4.2: "currently only `(where [x: T] p)` with a single free binding").
> **Reviewed:** Professor review (2026-06-12, in-conversation) — recommendation `affirm-with-additive-folds`. Five findings folded into this Rev 2 (see `## Appendix — Professor review log`); the architecture (four WF conditions, WF-legality ⊥ fragment-discharge orthogonality) was affirmed, not contested. No standalone `-review.md` file was produced; the review is folded directly per the REF-META-1 appendix pattern.
> **Status:** Settled (Rev 2) — professor review folded; spec-track only (no compiler work implied by the WF rule itself; the path-(a) measure-emission precondition named in §6 is owned by the downstream non-int widening engineer build). Pending documentation-lead promotion to `LLMLL.md §3.4.4`.

---

## 1. Motivation

LLMLL's refinement surface `(where [x: τ] p)` ([`LLMLL.md §3.4`](../../../LLMLL.md)) gives a binding `x : τ` and a predicate `p`, but `LLMLL.md` does not state **when `p` is a legal predicate at all**. REF-META-1 shipped the checking-mode inference rule (§3.4.1), the non-goals (§3.4.2), and the soundness statement of record (§3.4.3), and at two sites explicitly deferred the well-formedness question to this proposal:

- §4.2 closure-scope clarification: refinement-polymorphic functions and termination-via-refinement "are *consequences* of non-goal #1 and non-goal #3 respectively, deferred to **REF-META-3 — predicate well-formedness rule** for explicit treatment of refinement-variable binding shapes … the natural place to enumerate the refinement-predicate-binding shapes admitted (currently only `(where [x: T] p)` with a single free binding)."
- §5.5 Gap #5: "REF-META-1 does not enumerate the well-formedness conditions on such predicates; the formal treatment is **REF-META-3 territory**."

REF-META-3 ships that judgment as a new **§3.4.4**. The central design decision is to hold **well-formedness (legality)** strictly orthogonal to **fragment classification (auto-discharge)**: a predicate may be well-formed yet route to a runtime assertion (e.g. `regex-match`). This keeps the proposal spec-track-only — it *partitions* the predicates that reach the existing obligation channels; it introduces no new SMT obligation and no new channel.

The WF rule is the explicit prerequisite for two downstream v0.12 items: **REF-META-4** (the erasure theorem erases from a well-formed predicate) and the **§2 non-int refinement widening** (Phase 1 admits `EVar-refined-string`/`EVar-refined-list` exactly where the predicate is WF over the measure class and lands in QF-LIA). Where the WF rule makes a choice those consumers depend on, this proposal calls it out.

---

## 2. Scope

**In scope.** The well-formedness judgment for `(where [x: τ] p)`; the admitted refinement-symbol signature `Σ_ref` and its sub-classes; the measure-function axiomatization discipline (M1–M4); the orthogonality of WF-legality and fragment-discharge; the load-bearing seams for REF-META-4 and the non-int widening.

**Out of scope.** Fragment classification (which WF predicates auto-discharge) — that is REF-META-2's slot, with which this proposal shares the `Σ_ref` partition as its interface (§4.5). The erasure theorem itself — REF-META-4. The core-grammar admission of refined non-int `EVar`s and the FixpointEmit path-(a) axiomatization — the non-int widening engineer build (this proposal *names* the IR precondition; it does not build it). No new surface, no JSON-AST node-shape change, no `schemaVersion` bump, no `trust_report_version` change.

---

## 3. Surface

No new surface. The judgment constrains the existing `(type A (where [x: τ] p))` form — AST node `TDependent` ([`TypeCheck.hs:1562-1566`](../../compiler/src/LLMLL/TypeCheck.hs)). No S-expression or JSON-AST change.

---

## 4. Semantics

### 4.1 The well-formedness judgment

For a candidate refinement-aliased type `A ≜ (where [x: τ] p)`, define `Σ_ref ⊢ (where [x: τ] p) wf` under the admitted refinement-symbol signature `Σ_ref` (§4.2):

```
  x : τ ⊢ p : bool                                          (W-Sort)
  FV(p) ⊆ {x}                                               (W-Closed)
  symbols(p) ⊆ Σ_ref                                        (W-Catalog)
  every application in p is saturated; p contains no λ,
    no partial application, no refinement variable           (W-FirstOrder)
  ──────────────────────────────────────────────────────
  Σ_ref ⊢ (where [x: τ] p) wf
```

Each side condition traces to a brief restriction and a REF-META-1 anchor:

1. **W-Sort** — `p` is `bool`-sorted under the single binding. LLMLL's analog of the `p ∈ Bool` well-formedness side condition (Vazou et al., *Refinement Types for Haskell*, POPL 2014 §3). Already enforced structurally by the type checker (`inferExpr` + `bool`-compatibility), exactly the precedent at the `?proof-required` predicate check ([`TypeCheck.hs:1207-1210`](../../compiler/src/LLMLL/TypeCheck.hs)).

2. **W-Closed** — `FV(p) ⊆ {x}`: no free term variable other than the bound `x`. A refinement alias is closed over its single binding; it does not capture enclosing scope. After substitution at a checked-introduction site, `p[e/x]` mentions only symbols bound in the ambient typing context. This is the local half of REF-META-4's erasure precondition (§7).

3. **W-Catalog** — `symbols(p) ⊆ Σ_ref`: every applied function symbol is drawn from the admitted signature (§4.2). User-defined functions — recursive ones especially — are excluded; this is the formal content of REF-META-1 non-goal #3 (`(where [n: int] (> (factorial n) 0))` "not legal"): the exclusion is a `Σ_ref` membership failure, not a fragment-classification failure.

4. **W-FirstOrder** — `p` is a first-order proposition: all applications saturated, no lambdas, no partial application, no **refinement variables**. This closes refinement-polymorphism (`∀p. {x | p x} → {y | p y}`, Vazou et al., *Abstract Refinement Types*, ESOP 2013) — the consequence REF-META-1 §4.2 deferred here.

The judgment is **decidable** and runs at alias-definition / type-check time (the type channel, §6) — it is not an SMT obligation.

### 4.2 `Σ_ref` — the admitted refinement-symbol signature

`Σ_ref` partitions into three classes with **explicitly divergent discharge trajectories**. REF-META-2 inherits this partition as the interface between WF-legality and fragment-classification (§4.5):

| Class | Symbols | Sort | v0.12 discharge | Trajectory |
|---|---|---|---|---|
| QF-LIA core | `+ - = ≠ < ≤ > ≥ and or not`, int/bool literals, `x` | — | QF-LIA auto | stable |
| **Measure class** | `string-length`, `list-length` | `τ → int` | **runtime today; QF-LIA auto once M4 / path-(a) lands** | *becomes* auto-dischargeable |
| **Boolean-builtin class** | `regex-match` (+ any builtin with a declared `bool` refinement signature) | `… → bool` | **runtime / `?proof-required`; never auto in v0.12** | needs SMT Str/regex theory (path (b), deferred v0.13+) |

The two non-core sub-classes are **not** interchangeable. A `Word` / `Letter` refinement (measure class) reaches `verified`-tier the moment M4 lands; a `BlockID` refinement (`regex-match`, boolean-builtin class — [`LLMLL.md §3.4:251`](../../../LLMLL.md)) stays **`asserted`-tier** until the deferred Str theory. Labeling the split here prevents REF-META-2 from rediscovering it.

The v0.12 measure catalog is **closed** at `{string-length, list-length}`. Extension requires team consensus with a written totality+range argument, mirroring the non-goals-closure discipline (`LLMLL.md §3.4.2`, roadmap freeze-exception clause).

### 4.3 Measure-function axiomatization discipline (M1–M4)

A function `m` is admissible into `Σ_ref`'s measure class iff:

- **(M1) Total** — `m` is a total `τ → int` builtin (no partiality, no `?proof-required`). `string-length`, `list-length` qualify.
- **(M2) Uninterpreted, range-axiom-only** — `m` is reflected into the logic as an **uninterpreted** integer-valued function whose *only* asserted axiom is its range (`string-length s ≥ 0`, `list-length xs ≥ 0`). Defining equations are **not** unfolded. This is the deliberately-weak path-(a) abstraction: it keeps every `m`-bearing obligation inside QF-LIA over `m`'s integer image, with no `Str`/`Array` theory. It is strictly weaker than Liquid Haskell's `{-@ measure @-}` reflection (Vazou et al., *LiquidHaskell in the Real World*, Haskell '14 §4), which introduces per-constructor structural equations — that is path (b), deferred.
- **(M3) Arguments are WF base terms** — `m`'s argument is itself a WF term over `{x}` using only `Σ_ref` (`(string-length s)` admissible; `(string-length (substring s 0 2))` ill-formed, since `substring ∉ Σ_ref`).
- **(M4) Single function-sorted symbol, not per-site abstraction** — each measure is emitted as **one** function-sorted uninterpreted symbol applied to its argument (`string_length(s)`), so the solver's EUF congruence closure (`s = t ⇒ string_length(s) = string_length(t)`, and functional consistency across repeated occurrences) relates identical applications. The measure **must not** be abstracted to an independent fresh integer per occurrence — that emission loses congruence and collapses M2 to "safe but inert."

**Why M4, and why the catalog is useful-as-shipped (not merely safe).** Under M2+M4, the range axiom plus EUF congruence — free in Z3's Nelson–Oppen EUF+LIA combination — is *sufficient* for the entire bounded-length predicate class the catalog admits (`(> (string-length s) 0)`, `(= (string-length s) 1)`, `(< (string-length s) 64)`, conjunctions thereof). This is exactly the Rondon–Kawaguchi–Jhala (*Liquid Types*, PLDI 2008 §2) treatment of measures over **opaque, non-constructed** values: the measure's defining equations matter only at *constructor* sites, and `Σ_ref` excludes the constructors (`concat`, `cons`, `substring` ∉ catalog). The catalog and the axiomatization are therefore **matched** — M2+M4 serves precisely the predicates `Σ_ref` admits, and the predicates it cannot serve (inter-term structural relations such as `len(concat s t) = len s + len t`) are exactly the ones `Σ_ref` excludes. The usefulness claim is **conditional on M4**: without it, the measure class is well-formed-but-inert.

**Recursive / user-function exclusion and the future admission gate.** User-defined functions are excluded from `Σ_ref` for two principled reasons, not by fiat:

- **(a) Totality is unverifiable.** M1 demands totality, but LLMLL has no termination certificate for `def-shell` recursion (the descent checker is research-track R7); a recursive user function cannot satisfy M1 by construction.
- **(b) Trust-tier laundering.** Admitting `f` with its contract as a refinement axiom injects `f`'s contract into the predicate; an `asserted`-tier contract so injected launders unverified facts into the verified core — a soundness leak across the [`LLMLL.md §4.4`](../../../LLMLL.md) trust lattice.

**Future admission gate:** a user function becomes `Σ_ref`-admissible only when it carries **both a totality certificate and a verified-tier contract**, at which point it may enter as an uninterpreted symbol axiomatized by its *verified* post-condition. This is the same coin as the M2↔erasability identity (§4.4): only verified, total content may be reflected.

### 4.4 M2 ↔ erasability

Declining to unfold measure equations (M2) is exactly what keeps every refinement on the **erasable** side of the Vazou et al. *Refinement Reflection* (POPL 2018) boundary: unreflected refinements carry no computational content and erase to nothing; reflected ones inject term-level equalities that must survive to the runtime boundary. By construction LLMLL reflects nothing, so all refinements are ghost/erasable, and REF-META-4's erasure theorem inherits a near-free standing hypothesis. This identity is the lemma REF-META-4 builds on (§7).

### 4.5 Orthogonality — WF-legality ⊥ fragment-discharge

Well-formedness (legality, decidable, type-channel) is held strictly orthogonal to fragment classification (QF-LIA auto-discharge vs runtime / `?proof-required`). A WF predicate is a *legal* refinement; whether its introduction obligation `p[e/x]` auto-discharges is a separate question owned by REF-META-2's solver-completeness statement. The two proposals must agree on exactly one interface point: **`Σ_ref`'s QF-LIA-core + measure class is the auto-discharge set REF-META-2 characterizes (post-M4); the boolean-builtin class is WF-legal but lands in REF-META-2's "outside QF-LIA → runtime / `?proof-required`" partition.** REF-META-2 classifies on the same `Σ_ref` partition this rule defines.

---

## 5. Edge cases and degenerate inputs

### 5.1 Nested non-catalog measure function

**Input.** `(where [s: string] (> (string-length (substring s 0 2)) 0))`.
**Behavior.** `substring ∉ Σ_ref` ⇒ **ill-formed** by W-Catalog / M3. If `substring` were later admitted as a total `string → string` symbol, M3 would admit the nesting — but it is not in the v0.12 catalog.
**Channel.** Type (WF check at alias definition, decidable).
**Cite.** W-Catalog (§4.2); M3 (§4.3); [`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs).

### 5.2 Predicate over another refinement alias (stacked aliases)

**Input.** `(type NonEmptyWord (where [s: Word] (> (string-length s) 1)))`, `Word ≜ (where [s: string] (> (string-length s) 0))`.
**Behavior.** WF: `τ = Word` expands structurally to `string` (`expandAlias` recurses the base type only, [`TypeCheck.hs:1566`](../../compiler/src/LLMLL/TypeCheck.hs)). **Conjunction-at-introduction is the Liquid Haskell-standard treatment** (LH unfolds nested aliases to conjoined refinements); framing it as *definitional unfolding* rather than `P ⇒ Q` entailment keeps it clear of non-goal #1 (no user-visible subtyping). **Binder-identification discipline:** the inner and outer binders are α-identified to a **single common witness** `e`; the introduction site emits `pred_Word[e/s] ∧ pred_NonEmptyWord[e/s]` — both predicates over the *same* raw value. Obligation duplication (overlapping conjuncts) is harmless: QF-LIA absorbs redundancy.
**Channel.** Contract; QF-LIA over the measure image (post-M4).
**Cite.** §4.1 W-Closed admits multiplicity; `expandAlias` base-only recursion; non-goal #1 ([`LLMLL.md §3.4.2`](../../../LLMLL.md)).

### 5.3 Empty / trivial-true predicate

**Input.** `(where [x: int] true)`.
**Behavior.** WF: `true : bool` (W-Sort), `FV ⊆ {x}` vacuously, `symbols ⊆ Σ_ref`. **Legal**, degenerate; the introduction obligation is `true`, discharged immediately; the type is observationally the base type `int`. Intentionally permissive — no benefit to rejecting it.
**Channel.** Contract (trivially QF-LIA).
**Cite.** §4.1 (all four conditions hold vacuously).

### 5.4 Multiple occurrences of `x`

**Input.** `(where [s: string] (and (> (string-length s) 0) (< (string-length s) 64)))`.
**Behavior.** WF: every occurrence is the single bound `s`, so `FV ⊆ {s}` holds; conjunctive predicate, both conjuncts QF-LIA over `string-length`'s image. Under M4, both `string-length s` occurrences congruence-close to the same logical term. **Legal.**
**Channel.** Contract; QF-LIA (post-M4).
**Cite.** W-Closed bounds the free-variable *set*, not occurrence count; M4 (§4.3).

### 5.5 Refinement variable / recursive user function

**Input.** `(where [x: int] (p x))` with `p` unbound; or `(where [n: int] (> (factorial n) 0))`.
**Behavior.** Both **ill-formed**: the former by W-FirstOrder (refinement variable / unsaturated symbol) and W-Closed (`p ∈ FV`); the latter by W-Catalog (`factorial ∉ Σ_ref`). The decidable formalization of REF-META-1 non-goals #1 and #3.
**Channel.** Type.
**Cite.** W-FirstOrder, W-Catalog (§4.1–4.2); non-goals #1, #3 ([`LLMLL.md §3.4.2`](../../../LLMLL.md)).

---

## 6. Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| The WF check itself (`Σ_ref ⊢ (where …) wf`) | **type** | Decidable, non-SMT — runs at alias-definition / type-check time, analog to the `?proof-required` bool-check | [`TypeCheck.hs:1207-1210`](../../compiler/src/LLMLL/TypeCheck.hs); [`LLMLL.md §3.4.1`](../../../LLMLL.md) |
| Introduction obligation `p[e/x]`, QF-LIA-core predicate | contract | **QF-LIA, auto** | [`FixpointEmit.hs:661-681`](../../compiler/src/LLMLL/FixpointEmit.hs); [`LLMLL.md §5.3.3`](../../../LLMLL.md) |
| `p[e/x]` with measure-class symbol (`string-length` / `list-length`) | contract | **QF-LIA auto *after* M4 / path-(a) axiomatization; runtime today** (`exprToPred → Nothing`) | [`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs); [`v0.12-direction.md §2`](v0.12-direction.md) |
| `p[e/x]` with non-linear arithmetic (`* / mod rem ^ **`) | contract | **nonlinear → not auto-discharged** (`Nothing`); needs restriction or `?proof-required` | [`FixpointEmit.hs:676`](../../compiler/src/LLMLL/FixpointEmit.hs) |
| `p[e/x]` with boolean-builtin symbol (`regex-match`) | trust | **outside QF-LIA → runtime / `?proof-required`** (never auto in v0.12) | [`LLMLL.md §5.3.5`](../../../LLMLL.md) |
| **Measure-application emission (path-a precondition)** | — | **Requires a `FixpointIR` function-sort + `FQApp` term extension — absent today** (`FQSort`, [`FixpointIR.hs:49-52`](../../compiler/src/LLMLL/FixpointIR.hs), has no function sort; `exprToPred`, [`FixpointEmit.hs:662-682`](../../compiler/src/LLMLL/FixpointEmit.hs), has no application node). M4 congruence is unobtainable until this lands. | spec-ahead-of-IR seam; owned by the non-int-widening engineer build |

The WF rule introduces **no new SMT obligation** — it is a decidable structural check that *partitions* the predicates reaching the existing channels; it adds no channel. This is what keeps REF-META-3 spec-track-only. The final row is REF-META-3 doing its job: naming the IR seam where the spec runs ahead of the compiler, so the downstream engineer build inherits an explicit, checkable precondition rather than an implicit congruence assumption.

---

## 7. Affected surface

- **`LLMLL.md §3.4`** — new **§3.4.4 Predicate well-formedness rule** (the judgment + `Σ_ref` sub-classed catalog + measure discipline M1–M4 + M2↔erasability + orthogonality); update non-goal #3 (§3.4.2) to cite §3.4.4 as its formalization; forward cross-ref from the §5.3.5 verification-matrix measure-class rows. *(doc-lead promotion after settlement — not authored here.)*
- **`docs/design/ref-meta-3-predicate-wf-proposal.md`** — this file. INDEX one-liner row + status label (doc-lead).
- **No `compiler/src/LLMLL/` change** from the WF rule (spec-track only). Downstream *consumers* name modules:
  - **REF-META-4 (erasure):** precondition is **`W-Closed ∧ non-goal #2 (no dependent pattern matching) ∧ non-goal #4 (no proof terms)`** — *not* W-Closed alone. W-Closed is the local closure half; Knowles–Flanagan (*Hybrid Type Checking*, POPL 2010) additionally requires the predicate never be eliminated into a computationally-relevant position, which LLMLL secures via non-goals #2 and #4. REF-META-4 conjoins all three; the M2↔erasability identity (§4.4) supplies the standing hypothesis. Module: [`CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs).
  - **Non-int widening Phase 1:** exactly this WF rule restricted to (a) the measure class and (b) the QF-LIA fragment, plus the two engineer moves the WF rule does not make — core-grammar admission of `EVar-refined-string`/`-list` ([`Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs), [`TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs)) and the path-(a) measure axiomatization including the §6 `FixpointIR` function-sort/`FQApp` extension ([`FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs)). The WF rule is the prerequisite; it defines the legal predicate shape the widening admits.
- **No schema, no `trust_report_version`, no CHANGELOG/version bump.**

---

## 8. Risks and open questions

1. **M2 range-axiom-only too weak for inter-term predicates.** *Classify:* verification-ergonomics. *Cite:* M2 (§4.3), [`FixpointEmit.hs:682`](../../compiler/src/LLMLL/FixpointEmit.hs). *Bite:* complicates — a predicate like `(= (string-length (concat s t)) (+ (string-length s) (string-length t)))` needs a structural equation `string-length` does not carry under M2; such predicates are WF but never auto-discharge. Intentional for v0.12 (path (b) deferred); REF-META-2 states the boundary.
2. **`Σ_ref` catalog closure vs agent expectation.** *Classify:* scope. *Cite:* W-Catalog (§4.2). *Bite:* only at scale — agents reach for `substring`, `to-upper`, length arithmetic; each ill-formed predicate is a clear type-channel error, but the catalog's smallness may surface as authoring friction. The closed-catalog-with-consensus-extension discipline is deliberate.
3. **Stacked-refinement conjunction is a new spec commitment.** *Classify:* spec-drift (spec currently silent). *Cite:* `expandAlias` base-only recursion, [`TypeCheck.hs:1566`](../../compiler/src/LLMLL/TypeCheck.hs). *Bite:* complicates — the compiler expands the base, but it is unverified whether it currently *emits* the inherited inner obligation at a `NonEmptyWord` introduction site. **Flag for the engineer:** confirm conjunction-at-introduction (§5.2) is emitted, or it is a spec-ahead-of-code gap.
4. **`Σ_ref` recursive-function exclusion reads as arbitrary if the gate is unstated.** *Classify:* scope / soundness. *Cite:* M1 (§4.3), [`LLMLL.md §4.4`](../../../LLMLL.md) lattice. *Bite:* only at scale — without the stated future gate (totality certificate ∧ verified-tier contract), a later LT proposal might re-admit recursive functions ad hoc and reintroduce the laundering leak. The gate makes the door principled.

---

## Appendix — Professor review log

Professor review (2026-06-12, in-conversation), recommendation `affirm-with-additive-folds`. The four WF conditions were affirmed individually sound; the WF-legality ⊥ fragment-discharge orthogonality affirmed as the proposal's correct structural spine. Five findings, all folded into Rev 2:

- **F1 (→ M4, §4.3 + §6 IR row).** M2 range-axiom-only is useful-as-shipped for the bounded-length class *because* EUF congruence is free in Z3's Nelson–Oppen EUF+LIA (Rondon–Kawaguchi–Jhala, PLDI 2008) — but only if the measure is emitted as a genuine uninterpreted-function application, not a per-site fresh integer. The current FQ IR cannot express a UF application (`FQSort` has no function sort, `FixpointIR.hs:49-52`; `exprToPred` has no application node, `FixpointEmit.hs:662-682`). Added M4 (single function-sorted symbol) and a verification-mapping row naming the `FixpointIR` function-sort/`FQApp` extension as the path-(a) engineer precondition.
- **F2 (→ §4.4 + §7).** M2-no-unfolding ↔ erasability (Vazou et al., *Refinement Reflection*, POPL 2018): unreflected ⇒ erasable. Stated the identity. W-Closed is necessary but not sufficient for erasure (Knowles–Flanagan, POPL 2010); REF-META-4's precondition is `W-Closed ∧ non-goal #2 ∧ non-goal #4`.
- **F3 (→ §5.2).** Conjunction-at-introduction is the LH-standard treatment; pinned the α-identification discipline (single common witness `e` substituted into both predicates).
- **F4 (→ §4.3 + Risk 4).** Recursive-function exclusion affirmed for two reasons (totality unverifiable; trust-tier laundering); named the future admission gate (totality certificate ∧ verified-tier contract).
- **F5 (→ §4.2).** Labeled the two non-core `Σ_ref` sub-classes (measure class vs boolean-builtin class) with divergent discharge trajectories, for REF-META-2 to inherit.
