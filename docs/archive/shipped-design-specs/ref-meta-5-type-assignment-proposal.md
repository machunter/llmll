# REF-META-5 — Type-Assignment Judgment with Hole-Directed Checking (Refinement-Aliased Type Surface)

> **Version:** Rev 2 — professor review folded (framing recast: the checker is *local type inference* + one genuine checking rule, not a "complete bidirectional system"; D–K §3.1 cited to justify the relabel; Pierce–Turner / Damas–Milner re-anchored; subsumption-replacement spine dropped; Pfenning intro/elim sentence deleted). Rev 1 (2026-06-14) drafted the judgment as a "full bidirectional system" with a `≡`-for-`<:` subsumption replacement.
> **Date:** 2026-06-14 (Rev 1; Rev 2)
> **Implements:** `docs/compiler-team-roadmap.md` v0.12 post-freeze lane, REF-META-5 (last item on the REF-META-2..5 chain); [`docs/design/v0.12-direction.md §1`](v0.12-direction.md).
> **Prerequisites:** REF-META-1 (checking-mode rule [`LLMLL.md §3.4.1`](../../../LLMLL.md), non-goals §3.4.2, soundness §3.4.3); REF-META-2 (Σ_auto solver-completeness §5.3.3); REF-META-3 (predicate well-formedness §3.4.4); REF-META-4 (erasure theorem §3.4.5, commits `70bdcb3`/`22c5778`/`639d01e`). The judgment cites and embeds each.
> **Origin:** v0.12 full-memo scope; completes the refinement metatheory of record. REF-META-5 was the only item blocked on REF-META-4 (the full judgment must cite each sub-rule).
> **Reviewed:** Professor review (2026-06-14, in-conversation) — recommendation `revise-and-resubmit` (framing recast; technical content affirmed). Four findings folded into this Rev 2 (see `## Appendix — Professor review log`); the rules, the §3.4.1 embedding, the WF/erasure bracketing, the no-new-obligation / spec-track classification were affirmed, not contested. No standalone `-review.md` file was produced; the review is folded directly per the REF-META-1/3/4 appendix pattern.
> **Status:** Settled (Rev 2) — professor review folded; spec-track only (no compiler work — documents `TypeCheck.hs` as shipped). Pending documentation-lead promotion to `LLMLL.md §3.4.6` (+ a roadmap-row reconciliation).

---

## 1. Motivation

REF-META-1 shipped the checking-mode inference rule for refinement-aliased types (`LLMLL.md §3.4.1`) as a single rule pair (introduction emits `p[e/x]`; elimination adds `p` as a context hypothesis). The v0.12 memo's last metatheory-of-record item, REF-META-5, was framed as promoting that rule into "a complete bidirectional system covering all introduction and elimination forms." Reading the compiler to verify the spec (the language-team discipline) shows the system already present in `TypeCheck.hs`, and shows that the "complete bidirectional" framing mislabels it.

LLMLL's checker is **local type inference** in the Pierce–Turner sense (*Local Type Inference*, TOPLAS 2000): a single type-assignment (synthesis) judgment with per-call-site instantiation of type variables, no global unification, no subtyping. It has a checking judgment, but for every non-hole expression the checking rule is `e ⇐ τ ≜ (e ⇒ τ′ ; τ ≡ τ′)` ([`TypeCheck.hs:896`](../../compiler/src/LLMLL/TypeCheck.hs)). By Dunfield–Krishnaswami (*Bidirectional Typing*, CSUR 2021 §3.1), a checking judgment whose only non-hole mode-change is this rule **is type assignment** — the rule recovers undirected (Curry-style) inference. The single genuine bidirectional element is the hole rule ([`TypeCheck.hs:892`](../../compiler/src/LLMLL/TypeCheck.hs)): a named hole records its expected type without synthesizing, which is exactly the goal-propagation the agent-authoring sketch flow needs.

REF-META-5 therefore documents what the compiler is: a decidable type-assignment judgment (local type inference) into which REF-META-1's checking-mode rule embeds, with hole-directed checking as the one bidirectional element. This is the honest metatheory-of-record, and it is the stronger **design-reference** position — LLMLL competes for adoption against Liquid Haskell, F\*, and Idris, whose authors know the inference-versus-bidirectional distinction; claiming "complete bidirectional typing" for local type inference would read as a category error to exactly that audience.

## 2. Scope

**In scope.** The two judgment forms (⇒ synthesis / type assignment; ⇐ checking) as the spec-level presentation of `inferExpr` / `checkExpr`; the definitional non-hole checking rule (Check-by-Synth) and the single genuine checking rule (Check-Hole); the embedding of REF-META-1's introduction/elimination as the refinement-alias instances (`⇐-Refine` / `⇒-Var-Refine`); the surface-annotation and hole sources of expected types; the WF (upstream) / erasure (downstream) bracketing.

**Out of scope.** **Genuine bidirectional typing** — direct checking rules for introduction forms (an unannotated value checked against a type without synthesis), which would reduce annotation burden and yield richer hole goals from type propagation. That is a real agent-authoring enhancement, but it is **compiler work** (new `checkExpr` rules), not a documentation pass; it is named here as a deferred code-track item, not REF-META-5. Also out of scope: any subtyping or subsumption (non-goal #1, §3.4.2); polymorphism beyond the shipped per-call-site instantiation. No new surface, no JSON-AST change, no `schemaVersion` bump, no `trust_report_version` change, **no `compiler/src/LLMLL/` change**.

## 3. Surface

No new surface. The judgment describes the typing of the existing expression forms; no S-expression or JSON-AST change.

## 4. Semantics

### 4.1 The two judgments

- **`Γ ⊢ e ⇒ τ`** — type assignment (synthesis): `e` produces a type. The **primary** judgment; `inferExpr` ([`TypeCheck.hs:899`](../../compiler/src/LLMLL/TypeCheck.hs)).
- **`Γ ⊢ e ⇐ τ`** — checking: `e` is validated against a supplied `τ`. `checkExpr` ([`TypeCheck.hs:890`](../../compiler/src/LLMLL/TypeCheck.hs)). Type information enters from exactly two sources: **surface annotations** (parameter types, return types, annotated `let` bindings) and **holes**.

LLMLL is local type inference (Pierce–Turner, TOPLAS 2000): no subtyping (non-goal #1), no subsumption, no global unification. Type-variable instantiation is **local** to each application — the U-Lite per-call-site substitution ([`TypeCheck.hs:1070-1086`](../../compiler/src/LLMLL/TypeCheck.hs)). The type-level duality is **instantiation**, not subsumption; there is no subtyping relation for a subsumption rule to mediate.

### 4.2 Non-hole checking is definitional (Check-by-Synth)

```
  Γ ⊢ e ⇒ τ'      τ ≡ τ'        (e not a hole)
  ─────────────────────────────────────────────   (Check-by-Synth)
                Γ ⊢ e ⇐ τ
```

`τ ≡ τ'` is **decidable definitional type equality**: `expandAlias` both sides (resolve `TCustom`, [`TypeCheck.hs:1566`](../../compiler/src/LLMLL/TypeCheck.hs)), `stripDep` the refinement ([`:1388`](../../compiler/src/LLMLL/TypeCheck.hs)), then `unify` ([`:896`](../../compiler/src/LLMLL/TypeCheck.hs), [`:1085`](../../compiler/src/LLMLL/TypeCheck.hs)). This is **not** a subsumption analogue: per D–K §3.1, a checking judgment whose only non-hole rule is "synthesize then compare" is type assignment. LLMLL has no `<:` and nothing for subsumption to do that `≡` does not; the earlier "we replace `<:`-subsumption with `≡`-subsumption" framing (Rev 1) described a transition between two things LLMLL never had, and is dropped.

### 4.3 The one genuine bidirectional rule (Check-Hole)

```
  ──────────────────────────────────────   (Check-Hole)
  Γ ⊢ ?n ⇐ τ    ⇝ record goal τ for ?n
```

The sole rule ([`TypeCheck.hs:892`](../../compiler/src/LLMLL/TypeCheck.hs), `recordHole name (HoleTyped expected)`) where the expected `τ` flows into the term **without synthesizing it**. This is LLMLL's only bidirectional element and the mechanism behind goal-directed construction in the sketch flow (§11.2). The spec claims exactly this much bidirectionality and no more.

### 4.4 Refinement-alias instances (the REF-META-1 embedding)

Introduction — `⇐-Refine`, an instance of Check-by-Synth fired at a **surface-annotated** position (parameter / return / annotated `let`) whose annotation is a refinement alias `A ≜ (where [x: τ_b] p)`:

```
  ⊢ A wf (§3.4.4)     Γ ⊢ e ⇒ τ'     expandAlias(A) ≡ τ'
  ──────────────────────────────────────────────────────   (⇐-Refine)
           Γ ⊢ e ⇐ A   ⇝   { p[e/x] }
```

The **type channel** checks `e ⇒ τ'` and `expandAlias(A) ≡ τ'` (base-stripped `≡`, [`TypeCheck.hs:1083-1085`](../../compiler/src/LLMLL/TypeCheck.hs)); the **contract channel** emits `p[e/x]` (`FixpointEmit` / `Contracts`), the §3.4.1 two-phase split. `⊢ A wf` (§3.4.4) is a side condition gating predicate legality before the obligation is formed.

Elimination — `⇒-Var-Refine`:

```
  Γ(x) = A ≜ (where [y: τ_b] p)
  ─────────────────────────────────────────────
  Γ ⊢ x ⇒ τ_b      [hypothesis p[x/y] added to Γ]
```

A refinement-aliased variable synthesizes its **base** type and contributes `p` as a lexically-scoped context hypothesis (§3.4.1). Non-goal #2 (no dependent pattern matching) keeps the eliminand at the base type.

### 4.5 Mode assignment for the surface forms

| Form | Judgment | Expected-type source |
|---|---|---|
| `ELit`, `EVar`, `EApp`/`EOp`, `EMatch`, `EPair`, `ELambda`, `ELet` body | **⇒** synthesize | — (type assignment) |
| Parameter / return / annotated-`let` position | ⇐ via Check-by-Synth | surface annotation (`⇐-Refine` if a refinement alias) |
| `EApp` argument | infer-then-`≡` (Check-by-Synth) | callee param type, locally instantiated ([`TypeCheck.hs:1082-1086`](../../compiler/src/LLMLL/TypeCheck.hs)) |
| `EHole (HNamed)` | **⇐ via Check-Hole** | the goal type recorded ([`:892`](../../compiler/src/LLMLL/TypeCheck.hs)) |

The Pfenning intro-checks/elim-synthesizes discipline is **not** asserted: the code is synthesis-primary, and the table reflects that. `EIf` reconciles its branches by checking one against the other's synthesized type ([`:964`](../../compiler/src/LLMLL/TypeCheck.hs)/[`:969`](../../compiler/src/LLMLL/TypeCheck.hs)) — itself Check-by-Synth, not a direct checking rule.

### 4.6 WF and erasure bracketing

§3.4.4 (well-formedness) is *upstream* of the judgment — the `⊢ A wf` side condition of `⇐-Refine`; a non-WF predicate is a type error before any obligation forms. §3.4.5 (erasure) is *downstream* — after type assignment and obligation discharge, codegen erases `A ⟿ τ_b` (`stripDep` at runtime). The judgment is the type-assignment phase between them; the three compose the obligation lifecycle (WF → typing → discharge → erasure).

**Strict-immutability check:** the judgment is pure static type-assignment — no construct, no mutation; trivially preserved.

## 5. Edge cases and degenerate inputs

### 5.1 Hole in synthesis position

**Input.** `(+ ?x 1)` with `?x` carrying no supplied type.
**Behavior.** Check-Hole requires a *supplied* expected type; in synthesis position `inferHole` has no principal type and wildcards (`?` / sketch `HoleTyped`, [`TypeCheck.hs:894`](../../compiler/src/LLMLL/TypeCheck.hs)/[`:1134`](../../compiler/src/LLMLL/TypeCheck.hs)). This is the one form genuinely requiring the checking direction — the reason LLMLL has a `⇐` judgment at all.
**Channel.** Type.
**Cite.** [`TypeCheck.hs:891-894`](../../compiler/src/LLMLL/TypeCheck.hs); §11.2 hole flow.

### 5.2 Refinement-aliased return position

**Input.** `(def f [...] : Word ... body)`.
**Behavior.** The surface annotation `Word` supplies the expected type; the body is checked via `⇐-Refine` → `p[result/x]` to the contract channel; the type channel checks the body synthesizes `string`.
**Channel.** Type (structural) + contract (`p`).
**Cite.** §3.4.1; return-type check [`TypeCheck.hs:640`](../../compiler/src/LLMLL/TypeCheck.hs).

### 5.3 `EMatch` on a refinement-typed scrutinee

**Input.** `(match (w : Word) ...)`.
**Behavior.** The scrutinee synthesizes its base `string` (`expandAlias` + `stripDep`, [`TypeCheck.hs:981`](../../compiler/src/LLMLL/TypeCheck.hs)); the refinement enters the arms as a hypothesis; arms bind the **base** type (non-goal #2 — no dependent matching).
**Channel.** Type.
**Cite.** §3.4.2 #2; [`TypeCheck.hs:977-1025`](../../compiler/src/LLMLL/TypeCheck.hs).

### 5.4 Annotated `let` against a refinement alias

**Input.** `(let [[x : Word e]] …)`.
**Behavior.** The annotation drives Check-by-Synth of `e` against `Word` (`unify` at [`TypeCheck.hs:929`](../../compiler/src/LLMLL/TypeCheck.hs)) → `⇐-Refine` → `p[e/x]`. The one explicit-annotation-driven checking position outside parameters/returns.
**Channel.** Type + contract.
**Cite.** [`TypeCheck.hs:920-940`](../../compiler/src/LLMLL/TypeCheck.hs).

## 6. Verification mapping

REF-META-5 introduces **no new proof obligation** and **no new channel**. The judgment is the **type channel** — decidable, structural (`unify` + `expandAlias`), non-SMT, the same status as the §3.4.4 WF check. The only refinement obligation it routes is the existing §3.4.1 `p[e/x]` at `⇐-Refine` sites, already classified per [`LLMLL.md §5.3.3`](../../../LLMLL.md): QF-LIA core auto / measure-class auto (Σ_auto) / non-Σ_auto → `erBodyFallback` (the §3.4.5 firewall). The judgment reorganizes the presentation of obligations the compiler already emits; it adds none. This is what keeps REF-META-5 spec-track-only — the same pattern as REF-META-2/3/4.

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| Type-assignment / `≡` checks (the judgment itself) | type | Decidable, non-SMT (`unify` + `expandAlias`) | [`TypeCheck.hs:896,1083-1085`](../../compiler/src/LLMLL/TypeCheck.hs) |
| `⇐-Refine` introduction obligation `p[e/x]` (reused, not new) | contract | QF-LIA core auto / measure-class auto / non-Σ_auto → `erBodyFallback` | §3.4.1; [`§5.3.3`](../../../LLMLL.md); §3.4.5 |

## 7. Affected surface

Spec-track only — **no `compiler/src/LLMLL/` change** (documents `inferExpr` / `checkExpr` / `expandAlias` / `stripDep` as shipped).

- **`LLMLL.md` — new §3.4.6 "Type-assignment judgment with hole-directed checking (REF-META-5)"** — the two judgments (§4.1), Check-by-Synth (§4.2), Check-Hole (§4.3), `⇐-Refine` / `⇒-Var-Refine` (§4.4), the mode-assignment table (§4.5), WF/erasure bracketing (§4.6). Anchors: Damas–Milner (POPL 1982, the inference core); Pierce–Turner (TOPLAS 2000, local type inference / per-call-site instantiation); D–K (CSUR 2021 §3.1, cited once to justify the type-assignment label). Cross-refs: §3.4.1 (generalized-by), §3.4.4 (WF side condition), §3.4.5 (erasure downstream), §5.3.3 (obligation routing). *(doc-lead promotion after settlement.)*
- **`docs/compiler-team-roadmap.md` REF-META-5 row — drift reconciliation.** The row says "complete bidirectional system"; this over-promises relative to the code (local type inference). Reconcile to "type-assignment judgment (local type inference) completing REF-META-1's checking-mode rule." *(doc-lead.)*
- **`docs/design/INDEX.md`** — one-liner + status label (doc-lead).
- **No schema, no `trust_report_version`, no CHANGELOG/version bump** beyond the spec-track Unreleased entry.
- **Deferred (named, not scoped here):** genuine bidirectional typing — direct `⇐` rules for introduction forms, richer hole goals from type propagation — is a future **code-track** enhancement, logged so the design memory captures the option the honest label leaves open.

## 8. Risks and open questions

1. **Roadmap row over-promises ("complete bidirectional system").** *Classify: spec-drift (research-track).* *Cite:* `docs/compiler-team-roadmap.md` REF-META-5 row vs [`TypeCheck.hs:896`](../../compiler/src/LLMLL/TypeCheck.hs). *Bite: complicates* — must be reconciled in the same doc-lead pass as §3.4.6, or the row and the section disagree on the system's identity. Low effort.
2. **Spec must mirror code, not idealize.** *Classify: spec-drift.* *Cite:* [`TypeCheck.hs:896`](../../compiler/src/LLMLL/TypeCheck.hs). *Bite: only at scale* — every rule cites its `TypeCheck.hs` site; the table is synthesis-primary; no Pfenning recipe asserted. Mitigated in this draft.
3. **Deferred bidirectional enhancement could be re-conflated with REF-META-5 later.** *Classify: scope.* *Cite:* §2 (out-of-scope). *Bite: only at scale* — the §7 "deferred / named" note keeps the option in design memory as a distinct code-track item so a future proposal does not retroactively claim it was REF-META-5.

## Appendix — Professor review log

Professor review (2026-06-14, in-conversation), recommendation `revise-and-resubmit` (framing recast; technical content affirmed). The rules, the §3.4.1 embedding, the WF/erasure bracketing, and the no-new-obligation / spec-track classification were affirmed. Four findings, all folded into Rev 2:

- **H1 (→ §1, §4.2, title).** The system is local type inference + one hole-checking rule, not a "complete bidirectional system." Per D–K CSUR 2021 §3.1, a checking judgment whose only non-hole rule is `synth + unify` ([`TypeCheck.hs:896`](../../compiler/src/LLMLL/TypeCheck.hs)) recovers undirected type assignment. Recast: retitled to "Type-assignment judgment with hole-directed checking"; dropped the "complete bidirectional covering all forms" claim; the genuine bidirectional content is the single Check-Hole rule.
- **H2 (→ §4.2).** "`≡` replaces subsumption" is true-but-inverted — HM / local type inference has no subsumption to replace; the relevant duality is instantiation. Dropped the subsumption-replacement spine; `≡` reframed as decidable definitional type equality (alias unfolding).
- **H3 (→ §4.5).** Internal contradiction — the mode-assignment table (all forms ⇒ except holes) contradicted the "intro-checks/elim-synthesizes per the standard discipline" sentence. Deleted the Pfenning-recipe sentence; the table is synthesis-primary, matching the code.
- **H4 (→ §1, §7).** Wrong primary anchor — Pierce–Turner *Local Type Inference* (TOPLAS 2000) for the per-call-site instantiation ([`:1070-1086`](../../compiler/src/LLMLL/TypeCheck.hs)) and Damas–Milner (POPL 1982) for the inference core, with D–K (CSUR 2021 §3.1) cited once to justify the type-assignment relabel — not as authority for "bidirectional."

The professor's Q1 (label decision) was adjudicated by the language-team: ship REF-META-5 as the type-assignment / local-type-inference judgment (spec-track, code-faithful, no compiler work — matching the REF-META-2/3/4 pattern); genuine bidirectional typing is deferred as a separate code-track enhancement (§2, §7). Q2 (scope the hole rule, cite the local-type-inference lineage) is folded into §4.3 and §1. The convergence is named in §1: the language-team's Rev 1 risk section already sensed the mislabel ("synthesis-primary, checking at holes; a bidirectional presentation, not full D–K"); the professor's outward reading supplied the decisive result (D–K §3.1) and the correct citation (Pierce–Turner).
