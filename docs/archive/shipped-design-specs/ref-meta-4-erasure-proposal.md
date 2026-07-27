# REF-META-4 — Erasure Theorem with Construction-Side Discipline (Refinement-Aliased Type Surface)

> **Version:** Rev 3 — engineer trace folded (Risk 1 resolved: undischargeable refinement ⇒ `erBodyFallback` ⇒ off `verified`, a sound carve-out, mechanically enforced). Rev 2 (2026-06-13) folded professor review (recast Theorem A as a phase-distinction/proof-irrelevance result; demoted `M2 ↔ erasability` to co-occurrence; widened the precondition to the proof-irrelevance fragment; moved W-Closed to Theorem B). Rev 1 (2026-06-13) drafted the two-face decomposition and the construction-side discipline.
> **Date:** 2026-06-13 (Rev 1; Rev 2; Rev 3)
> **Implements:** `docs/compiler-team-roadmap.md` v0.12 post-freeze lane, REF-META-4; [`docs/design/v0.12-direction.md §1`](v0.12-direction.md) (REF-META-2..5 sequencing, REF-META-4 row).
> **Prerequisites:** REF-META-1 (Settled Rev 2, promoted to [`LLMLL.md §3.4.1-3`](../../../LLMLL.md)); REF-META-2 (solver-completeness statement / `Σ_auto`, promoted to [`LLMLL.md §5.3.3`](../../../LLMLL.md)); REF-META-3 (predicate well-formedness rule, promoted to [`LLMLL.md §3.4.4`](../../../LLMLL.md)). This proposal fills the erasure-theorem slot REF-META-1 §4.3 named and ref-meta-3 §4.4/§7 deferred here, and discharges the forward-reference at [`LLMLL.md §3.4.3:315`](../../../LLMLL.md).
> **Origin:** v0.12 full-memo scope (`v0.12-direction.md §1`); on the longest sequential REF-META chain (4 → 5). REF-META-5 (full bidirectional judgment) is blocked on this proposal.
> **Reviewed:** Professor review (2026-06-13, in-conversation) — recommendation `revise-and-resubmit` (architecture affirmed; both standing-hypothesis anchors required re-derivation). Five findings folded into Rev 2 (see `## Appendix — Professor review log`). Compiler-engineer trace (2026-06-13, in-conversation) — Risk 1 (tier-degradation vs. silent-drop) resolved as a sound carve-out (see `## Appendix — Engineer trace log`). No standalone `-review.md` file was produced; both are folded directly per the REF-META-1/3 appendix pattern.
> **Status:** Settled (Rev 3) — professor review + engineer trace folded; spec-track only (no compiler work — codegen erasure and the soundness firewall both already exist). Pending documentation-lead promotion to `LLMLL.md §3.4.5` (+ §3.4.4 / §3.4.3 / §5.3.5 reconciliation edits).

---

## 1. Motivation

LLMLL codegen lowers a refinement-aliased type `A ≜ (where [x: τ] p)` to its underlying base type `τ`, discarding the predicate `p` entirely: `emitTypeDef name (TDependent _ base _)` emits `type A = τ` ([`CodegenHs.hs:438-440`](../../compiler/src/LLMLL/CodegenHs.hs)) and `toHsType (TDependent _ b _) = toHsType b` ([`CodegenHs.hs:772`](../../compiler/src/LLMLL/CodegenHs.hs)). The erasure is **structural, total, and predicate-blind** — the predicate `Expr` is never inspected; at the Haskell boundary `Word` and `string` are the same type (`String`), and a value's membership in `Word` is unobservable at runtime.

REF-META-1 listed "an erasure theorem with construction-side discipline" among the five missing metatheory pieces; [`LLMLL.md §3.4.3:315`](../../../LLMLL.md) names the "formal derivation of the compositional closure" as **REF-META-4 territory** with standing hypothesis "all body VCs SAFE"; and ref-meta-3 §4.4/§7 deferred the erasure theorem here with the precondition `W-Closed ∧ non-goal #2 ∧ non-goal #4` and the `M2 ↔ erasability` hypothesis. REF-META-4 ships that theorem.

Because the predicate is dropped with **no runtime check** (confirmed in §4.1), the soundness question is sharp: *does the erased program behave as the predicate-carrying program, and does the invariant downstream code relies on actually hold at runtime even though nothing checks it?* The answer decomposes into two faces — a **phase distinction** (the predicate is computationally inert) and a **construction-side discipline** (the invariant was established statically at every introduction site, and that discharge composes across the verified-tier call graph).

## 2. Scope

**In scope.** The two-face erasure theorem for refinement-aliased types; the precise precondition (the proof-irrelevance non-goal fragment for Theorem A; the verified-tier construction-side discipline for Theorem B); the standing hypotheses and their per-face assignment; the `Σ_auto`-co-extensive scope boundary; the soundness-firewall identification; the distinction between the refinement-alias channel and the contract (`pre`/`post`) channel.

**Out of scope.** The full bidirectional typing judgment — REF-META-5. A mechanized soundness theorem against an independently-defined operational semantics — **Path B, declined** per [`LLMLL.md §3.4.3:319`](../../../LLMLL.md) and [`docs/design/verification-debate.md`](../../design/verification-debate.md); this proposal is a precise **commitment** (Path A), not a mechanized theorem. No new surface, no JSON-AST node-shape change, no `schemaVersion` bump, no `trust_report_version` change, **no `compiler/src/LLMLL/` change** (both the codegen erasure and the fallback firewall already exist).

## 3. Surface

No new surface. The theorem governs the existing `(type A (where [x: τ] p))` form — AST node `TDependent` ([`Syntax.hs:135`](../../compiler/src/LLMLL/Syntax.hs)). No S-expression or JSON-AST change.

## 4. Semantics

### 4.1 What erasure means in LLMLL, and the no-runtime-residue property

Refinement aliases are enforced **static-only**: the predicate is folded into the function's effective VC precondition (`augmentContractPre`, [`FixpointEmit.hs:1345-1359`](../../compiler/src/LLMLL/FixpointEmit.hs)) and discharged intro-side (call-pre obligations at call sites, [`FixpointEmit.hs:174`](../../compiler/src/LLMLL/FixpointEmit.hs)) and elim-side (assumed in the body VC, [`FixpointEmit.hs:391`](../../compiler/src/LLMLL/FixpointEmit.hs)). `augmentContractPre` is **verifier-local** — both call sites are in the `.fq` emitter; it never reaches the codegen runtime-assertion path. There is **no post-side analog** (return-value refinements are not folded into `contractPost`), and the codegen runtime assertions ([`CodegenHs.hs:530-541`](../../compiler/src/LLMLL/CodegenHs.hs)) fire **only** from user-authored `pre`/`post` clauses. Therefore refinement-alias predicates carry **zero runtime residue** at every introduction site (parameter, return, let-binding).

This is the load-bearing property: **LLMLL refinement aliases are *verify-or-trust* — there is no dynamic safety net.** On the design-reference axis this distinguishes LLMLL: Liquid Haskell can insert runtime refinement checks; Knowles–Flanagan hybrid type checking is static-*or-dynamic*; LLMLL is static-*or-trust-demote*. Erasability of the type-level annotation is therefore *unconditional* (codegen always drops `p`), while erasure-*soundness* is *conditional* — and the entire soundness load falls on the construction-side discipline (Theorem B), backstopped by a soundness firewall (§4.4).

### 4.2 Theorem A — Type-level erasure as a phase distinction

> Let `A ≜ (where [x: τ] p)` be well-formed (§3.4.4) and lie in LLMLL's **proof-irrelevance fragment**: `non-goal #2 ∧ #4 ∧ #5 ∧ #6` (no dependent pattern matching, no proof terms, no sigma types, no boolean-expression-as-type-equality). Then `p` occupies a proof-irrelevant position — it is never eliminated into a computationally-relevant position — and codegen's type-level drop `A ⟿ τ` is **observation-preserving**: the erased program is observationally equivalent to the predicate-carrying program.

This is a **phase distinction** (Harper–Mitchell–Moggi, *Phase Distinctions in Type Theory*, 1990), structurally a total erasure-function bisimulation (Mishra-Linger & Sheard, *Erasure and Polymorphism in Pure Type Systems*, FoSSaCS 2008: `e →* v ⟺ ⌈e⌉ →* ⌈v⌉`). Each conjunct removes one channel by which an erased predicate could change behavior:

- **ng#2** (no dependent pattern matching): no runtime control-flow branches on `p`; the eliminator binds base `τ`, and `p` is only a lexically-scoped logical hypothesis (§3.4.1 elim rule), never a runtime discriminant.
- **ng#4** (no proof terms): the *operative* guard — no inhabitant of `p` exists in the term language to be eliminated.
- **ng#5 / ng#6** (no sigma types, no propositional equality): close the two classic erasure-breakers — sigma-projection of a proof component, and transport along an equality. These are **currently vacuous** (LLMLL has no surface form for either), conjoined to future-proof the precondition against a later surface expansion; even were a form added, ng#4 keeps it erasure-safe by removing inhabitants.

Design anchor: Ou–Tan–Mandelbaum–Walker, *Dynamic Typing with Dependent Types* (IFIP TCS 2004) — the origin "erase refinements to base types" design. Modern comparator: Quantitative Type Theory / Idris 2 (Atkey, *Syntax and Semantics of Quantitative Type Theory*, LICS 2018), where LLMLL refinements are morally multiplicity-0 ghosts. **Knowles–Flanagan is not the anchor** — there are no casts on aliases to remove (§4.1; see Appendix finding F2).

**M2 as a co-property (not the hinge).** The M2/M4 measure abstraction (§3.4.4) — `string-length`/`list-length` reflected as uninterpreted symbols carrying only range axioms (`m(s) ≥ 0`), EUF congruence relating occurrences — is **logic-only**: no runtime projection, no leak across the erasability boundary. But M2 does **not cause** erasability; proof-irrelevance does. LLMLL exhibits *both* no-unfolding (for QF-LIA+EUF decidability, REF-META-2) and erasability (for proof-irrelevance) for **independent reasons**. Liquid Haskell erases *reflected* refinements too — reflection (Vazou et al., *Refinement Reflection*, POPL 2018) injects *logical* equations, not runtime terms; GHC compiles the plain Haskell — so the reflected/unreflected axis is orthogonal to erasability, and LLMLL would remain erasable even under a future path-(b) unfolding. The `M2 ↔ erasability` "↔" of ref-meta-3 §4.4 is accordingly **demoted to co-occurrence**; the upstream characterization "reflected ones inject term-level equalities that must survive to runtime" is superseded (Appendix finding F1).

### 4.3 Theorem B — Construction-side discipline & compositional closure

> For a program in which (a) every refinement-typed value originates at a **checked introduction site** whose obligation `p[e/x]` is discharged at solver-backed (`verified`) evidence (§3.4.1, §3.4.3) — `p` being **W-Closed** so the obligation is well-scoped in the ambient context — and (b) the `--strict-verified-core` admissibility set is closed under composition (§5.3.4), the erased generated program preserves every declared refinement invariant at runtime. Standing hypothesis: the discharged-VC-set "all body VCs SAFE" (§3.4.3:315, VCgen/Hoare sense). This is the formal derivation §3.4.3:315 promised.

Because Theorem A erased the type and §4.1 established that no runtime assertion was ever emitted, Theorem B carries the **entire** soundness load: the invariant holds at runtime *only if* it was statically discharged at construction at `verified` tier, and that discharge composes across the call graph by the assume-guarantee discipline of §5.3.4 (callee posts assumed, never bodies; trust meet = `verified`; no SCC circularity). **W-Closed lives here**, not in Theorem A: it guarantees `p[e/x]` mentions only ambient symbols (the capture-freedom of `renameVar` at [`FixpointEmit.hs:1322-1325`](../../compiler/src/LLMLL/FixpointEmit.hs) depends on exactly W-Closed) — a well-formedness/scoping condition, not a phase-distinction one.

### 4.4 The soundness firewall is mechanical and pre-existing

Because refinement aliases have no dynamic safety net, soundness requires that an *undischarged* refinement force the carrying function **off** the `verified` tier. This firewall already exists and is not bespoke machinery for REF-META-4 — it is the body-faithful-VC fallback policy:

- A refinement predicate outside `Σ_auto` is **non-emittable** (`exprToPred → Nothing`, [`FixpointEmit.hs:756`](../../compiler/src/LLMLL/FixpointEmit.hs); `regex-match`, nonlinear operators, and user functions all hit the catch-all).
- A non-emittable predicate folded into a function's effective precondition forces `erBodyFallback` at the **definition site** ([`FixpointEmit.hs:500`](../../compiler/src/LLMLL/FixpointEmit.hs)) and at any **call site** — the "soundness-critical" three-way pre distinction ([`FixpointEmit.hs:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs): *"cannot assume post without verifying pre"*) returns `Nothing` for the whole call, collapsing the caller's body VC to fallback ([`FixpointEmit.hs:509`](../../compiler/src/LLMLL/FixpointEmit.hs)).
- `erBodyFallback` functions are excluded from `verified` body-faithful evidence and rejected by `--strict-verified-core` ([`LLMLL.md §5.3.4:933`](../../../LLMLL.md)). A `CallVC` is only constructed when the precondition *translated* ([`FixpointEmit.hs:1185-1203`](../../compiler/src/LLMLL/FixpointEmit.hs)), so no obligation is ever silently dropped.

These are two **independent** mechanisms (definition-site and call-site fallback), backstopped by the transitive trust meet. The engineer trace (Appendix) establishes this is a **sound carve-out**, not a soundness hole.

### 4.5 Scope boundary — co-extensive with `Σ_auto`

Theorem B's `verified`-tier precondition is **mechanically co-extensive with `Σ_auto`-membership** of the refinement predicate (`Σ_auto`, REF-META-2, [`LLMLL.md §5.3.3:880`](../../../LLMLL.md)):

- **Predicate ∈ `Σ_auto`** (QF-LIA core ∪ measure class, post path-(a) commit `0a3c5c2`): translatable (`exprToPred`/`bodyToPredM` at [`FixpointEmit.hs:752-753, 971-974`](../../compiler/src/LLMLL/FixpointEmit.hs)) → the construction-side obligation discharges → erasure is sound with a `verified` guarantee. **Theorem B covers it** (`Word`, `Letter`, `PositiveInt`).
- **Predicate ∉ `Σ_auto`** (`regex-match` boolean-builtin class, nonlinear, user functions): non-emittable → `erBodyFallback` → not `verified`. The type still erases (unconditional codegen), but Theorem B makes no claim — **a carve-out**, exactly as §3.4.3 carves out `?delegate`/FFI/`asserted`-tier values.

REF-META-4 therefore *consumes* REF-META-2's `Σ_auto` as its exact scope edge — a clean dependency rather than a newly-invented boundary, closing the REF-META arc. The carve-out is **conservative**: some sound-but-untranslatable refinements also fall back (a completeness limitation inherited from the fallback policy, not a soundness gap).

### 4.6 Refinement-alias channel vs. contract channel

The erasure theorem governs the **refinement-alias channel** (§3.4 `where`-types): static-only, no casts, proof-irrelevance. This is *distinct* from the **contract channel** (`pre`/`post` clauses), which **does** emit runtime assertions ([`CodegenHs.hs:530-541`](../../compiler/src/LLMLL/CodegenHs.hs)) and where Knowles–Flanagan-style cast-elimination *does* apply — `--contracts=unproven` strips `verified`-and-body-faithful postcondition assertions ([`Contracts.hs:215`](../../compiler/src/LLMLL/Contracts.hs), [`LLMLL.md §5.3.4:931`](../../../LLMLL.md)). §3.4.5 keeps the two channels separate so a reader does not import the contract channel's runtime-assertion behavior into the alias channel.

## 5. Edge cases and degenerate inputs

### 5.1 Undischargeable non-`Σ_auto` alias predicate (the soundness firewall)

**Input.** A parameter typed `BlockID ≜ (where [s: string] (regex-match "^[a-f0-9]{64}$" s))`, with a caller passing a plain `string`.
**Behavior.** `regex-match ∉ Σ_auto` ⇒ `exprToPred → Nothing` ⇒ `erBodyFallback` at the definition site ([`FixpointEmit.hs:500`](../../compiler/src/LLMLL/FixpointEmit.hs)) and at any call site ([`:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs)→[`:509`](../../compiler/src/LLMLL/FixpointEmit.hs)) ⇒ excluded from `verified`/strict-core. No runtime assertion is emitted; no `verified`-with-silent-unchecked-invariant is possible. Theorem B declines to cover it (carve-out). **Sound, engineer-confirmed.**
**Channel.** Trust (soundness firewall, mechanically enforced).
**Cite.** [`FixpointEmit.hs:756,500,891-901`](../../compiler/src/LLMLL/FixpointEmit.hs); [`LLMLL.md §5.3.4:933`](../../../LLMLL.md). **Spec-drift flag:** [`LLMLL.md §5.3.5:963`](../../../LLMLL.md) Fallback column claims "runtime assertion + ?proof-required" — incorrect; actual = `erBodyFallback` → contract-only/`asserted` tier, no runtime check (§7).

### 5.2 Refinement-typed return value

**Input.** A function returning `Word`.
**Behavior.** A checked-introduction site for the *solver* (postcondition obligation via §3.4.1); **no `contractPost` fold, no runtime assertion** (no post-side analog exists, §4.1). Same static-only / verify-or-trust treatment as parameters — covered by Theorem B iff the predicate ∈ `Σ_auto`.
**Channel.** Contract (solver) / trust (if undischarged).
**Cite.** §4.1; [`CodegenHs.hs:530-541`](../../compiler/src/LLMLL/CodegenHs.hs) (post-assertion fires from user-authored post only).

### 5.3 Dependent-elimination attempt on a refined value

**Input.** A `match` on a `Letter` value expecting the predicate to drive a branch.
**Behavior.** non-goal #2 forbids it — the arm binds `s : string`; `p` is a lexically-scoped hypothesis (§3.4.1 elim), never a runtime discriminant. Theorem A's observation-equivalence holds; this is the conjunct's reason for living.
**Channel.** Type (non-goal #2).
**Cite.** [`LLMLL.md §3.4.2 #2`](../../../LLMLL.md); §3.4.1 elim rule.

### 5.4 Sigma / transport over a refinement (future surface)

**Input.** A hypothetical dependent pair projecting a proof of `p`, or a transport along a propositional equality.
**Behavior.** ng#5 / ng#6 close both; **currently vacuous** (no surface form exists); even if a form were added, ng#4 keeps it erasure-safe by removing inhabitants.
**Channel.** Type (ng#4/#5/#6).
**Cite.** [`LLMLL.md §3.4.2`](../../../LLMLL.md); Mishra-Linger & Sheard, FoSSaCS 2008.

### 5.5 Trivial-true predicate

**Input.** `(where [x: int] true)`.
**Behavior.** Erases to `int`; the introduction obligation `true` discharges immediately; both theorems hold vacuously. Confirms the theorem is well-behaved at the degenerate boundary.
**Channel.** Contract (trivially QF-LIA).
**Cite.** §3.4.4 (all WF conditions vacuous); §4.2–4.3.

## 6. Verification mapping

REF-META-4 introduces **no new proof obligation** — it is a metatheoretic statement *about* obligations the existing rules already emit; it adds no SMT obligation and no channel. This is what keeps it spec-track-only (as REF-META-2/3 were).

| Item | Channel | Fragment | Cite |
|---|---|---|---|
| Construction-side **witness** = the §3.4.1 intro obligation `p[e/x]` (reused, not new) | contract | **QF-LIA auto** (core); **QF-LIA+EUF auto** (measure class, path-(a)); non-`Σ_auto` → `erBodyFallback` (not a runtime check) | §3.4.1; [`LLMLL.md §5.3.3:880`](../../../LLMLL.md); [`FixpointEmit.hs:661-682,752-753`](../../compiler/src/LLMLL/FixpointEmit.hs) |
| Compositional-closure side-condition = "all body VCs SAFE" over the call graph | trust | Decidable **side-condition**, not a quantifier over solver runs (QF-LIA confinement, §5.3.4) | [`LLMLL.md §5.3.4:908,933`](../../../LLMLL.md); §3.4.3:315 |
| Soundness firewall (undischarged ⇒ `erBodyFallback`) | trust | Decidable; the fallback is the existing body-faithful-VC policy, QF-LIA-confined | [`FixpointEmit.hs:891-901,500,509`](../../compiler/src/LLMLL/FixpointEmit.hs) |
| Theorem A + B **themselves** | — | **Path-A commitment, NOT an obligation.** Path B (mechanized theorem against an independent operational semantics) is **declined** (§3.4.3:319). Not routed to liquid-fixpoint, not a `?proof-required`/Lean obligation. | §3.4.3:319; [`verification-debate.md`](../../design/verification-debate.md) |

If the Path-B decision were ever reversed, the Lean obligation would be the observational-equivalence statement of Theorem A (recast as a phase-distinction result, it is structurally a total-erasure bisimulation — among the cheapest metatheorems to mechanize). This remains **out of scope**, consistent with §3.4.3.

## 7. Affected surface

Spec-track only — **no `compiler/src/LLMLL/` change** (codegen erasure at [`CodegenHs.hs:438-440, 772`](../../compiler/src/LLMLL/CodegenHs.hs) and the fallback firewall at [`FixpointEmit.hs:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs) both already exist).

- **`LLMLL.md` — new §3.4.5 "Erasure theorem (REF-META-4)"** — Theorem A (phase distinction, proof-irrelevance fragment `ng#2,#4,#5,#6`, OTMW/MLS/QTT anchors, M2-as-co-property), Theorem B (construction-side discipline + W-Closed + "all body VCs SAFE"), the soundness firewall (§4.4), the `Σ_auto`-co-extensive scope boundary (§4.5), the verify-or-trust/no-dynamic-net headline, and the refinement-alias-channel-vs-contract-channel note (§4.6). *(doc-lead promotion after settlement — not authored here.)*
- **`LLMLL.md §3.4.4:354` — correction.** The "Erasability" paragraph asserts a false causal link ("Declining to unfold measure equations (M2) keeps every refinement on the erasable side"); reword so M2 is a co-property and the erasure precondition is the proof-irrelevance fragment (add non-goals #5/#6 to the existing #2/#4). *(doc-lead.)*
- **`LLMLL.md §3.4.3:315`** — replace the forward-reference "Formal derivation … is REF-META-4 territory" with "see §3.4.5."
- **`LLMLL.md §5.3.5:963` — drift reconciliation (engineer-confirmed).** Verbatim correction for the non-QF-LIA alias-intro Fallback cell: *"`erBodyFallback` → contract-only / `asserted` tier; no runtime assertion is emitted for a refinement-typed binding."* *(doc-lead + engineer.)*
- **`docs/compiler-team-roadmap.md`** REF-META-4 row → Promoted; **`docs/design/INDEX.md`** one-liner + status label. *(doc-lead.)*
- **Optional, non-gating follow-up:** the engineer recommended a pinning regression test (836 → 837 Haskell) guarding the [`FixpointEmit.hs:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs) firewall for the refinement-folded-pre case; route to compiler-engineer independently if desired — it does not gate the §3.4.5 promotion.
- **No schema, no `trust_report_version`, no CHANGELOG/version bump.** `TDependent` already exists ([`Syntax.hs:135`](../../compiler/src/LLMLL/Syntax.hs)).

## 8. Risks and open questions

1. **~~Tier-degradation vs. silent-drop for an undischargeable refinement call-pre~~ — RESOLVED.** *Classify: soundness.* *Cite:* [`FixpointEmit.hs:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs). The engineer trace (Appendix) establishes the case is a sound carve-out: the non-emittable predicate forces `erBodyFallback` via two independent mechanisms, excluding the function from `verified`/strict-core. The soundness firewall is mechanical and pre-existing; REF-META-4 introduces no new enforcement.
2. **§5.3.5:963 + §3.4.4:354 touch already-promoted spec.** *Classify: spec-drift (self).* *Cite:* [`LLMLL.md §5.3.5:963`](../../../LLMLL.md), [`§3.4.4:354`](../../../LLMLL.md). *Bite: complicates* — both edits must land in the same doc-lead pass as §3.4.5 for one-document consistency. Low effort.
3. **Firewall guarded by comment, not by a dedicated test.** *Classify: spec-drift / regression surface.* *Cite:* [`FixpointEmit.hs:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs). *Bite: only at scale* — a future `bodyToPredM` refactor could reopen the hole silently; the optional pinning test (§7) closes it. Non-gating for the spec.
4. **ng#5/#6 conjunction reads as redundant.** *Classify: scope.* *Cite:* §4.2. *Bite: only at scale* — a reader may ask why vacuous non-goals are conjoined; the one-sentence future-proofing rationale closes it.

## Appendix — Professor review log

Professor review (2026-06-13, in-conversation), recommendation `revise-and-resubmit`. The two-face architecture (local type-erasure + compositional construction-side discharge) was affirmed; the central justification and both standing-hypothesis anchors required re-derivation. Five findings, all folded into Rev 2:

- **F1 (→ §4.2).** `M2 ↔ erasability` is a non-sequitur — erasability is governed by proof-irrelevance, not by no-unfolding. Liquid Haskell erases *reflected* refinements too (reflection, POPL 2018, injects logical equations, not runtime terms), so the reflected/unreflected axis is orthogonal to erasability, and ref-meta-3 §4.4's "reflected ones inject term-level equalities that must survive to runtime" is incorrect. Demoted the "↔" to co-occurrence; superseded the upstream characterization.
- **F2 (→ §4.2, §4.6).** Knowles–Flanagan is the wrong anchor for the alias erasure theorem — LLMLL does static-or-trust-demote, not static-or-dynamic; there are no casts on aliases to remove. Re-anchored Theorem A to OTMW 2004 / Mishra-Linger-Sheard 2008 / QTT (Atkey 2018). KF retained only as a declined-alternative contrast; KF-style cast-elimination *does* live in LLMLL, but in the contract channel (`--contracts=unproven`), a distinct surface (§4.6).
- **F3 (→ §4.1, §4.4, §7).** §5.3.5:963 spec/code drift; the trust-tier carve-out is the soundness firewall, not a completeness scoping; aliases are "verify-or-trust" with no dynamic safety net. Confirmed inward and elevated the carve-out to a soundness precondition; routed §5.3.5:963 to doc-lead; surfaced Risk 1 (tier-degradation vs. silent-drop) for engineer confirmation.
- **F4 (→ §4.2).** The precondition `W-Closed ∧ ng#2 ∧ ng#4` is under-specified; ng#5 (no sigma) and ng#6 (no propositional equality) also gate erasability. Ruling: conjoin all four into the proof-irrelevance fragment, with ng#5/#6 currently vacuous and ng#4 as the operative inhabitant-removing guard.
- **F5 (→ §4.3).** W-Closed was mis-attributed to Theorem A. Moved to Theorem B — it is a well-formedness/obligation-scoping condition, not a phase-distinction condition; Theorem A holds regardless of whether `p` is closed, provided `p` is never eliminated.

Q1 (Knowles–Flanagan anchor) and Q2 (reflection-boundary range-axiom leak) were resolved by F2 and F1 respectively. No outstanding professor questions.

## Appendix — Engineer trace log (Risk 1 resolution)

Compiler-engineer trace (2026-06-13, in-conversation). **Verdict: SOUND CARVE-OUT — no compiler change required.** An undischargeable refinement-alias call-pre obligation is case (b) "entire call falls back," not case (c) "silently dropped":

- The caller's body VC reaches the callee through the **augmented** ContractEnv ([`FixpointEmit.hs:174`](../../compiler/src/LLMLL/FixpointEmit.hs) folds the refinement into the callee's effective pre). The "soundness-critical" three-way pre distinction ([`:891-901`](../../compiler/src/LLMLL/FixpointEmit.hs)) returns `Nothing` for a non-emittable callee pre (*"cannot assume post without verifying pre"*), collapsing the caller's body VC to fallback ([`:509`](../../compiler/src/LLMLL/FixpointEmit.hs)).
- A function that merely *has* a non-`Σ_auto` refinement parameter also falls back on its own body VC ([`:500`](../../compiler/src/LLMLL/FixpointEmit.hs)) — defense in depth, backstopped by the transitive trust meet.
- A `CallVC` is only constructed when the pre *translated* ([`:1185-1203`](../../compiler/src/LLMLL/FixpointEmit.hs)); the `Nothing → []` branch fires only for callees with genuinely no precondition. No obligation is ever silently dropped.
- The carve-out is co-extensive with `Σ_auto` (post path-(a), measure-class refinements translate and reach `verified`; only `regex-match`/nonlinear/user-functions fall back) and conservative (any untranslatable pre falls back, not only refinements).

Two spec-side notes carried into §7: (a) §5.3.5:963 "runtime assertion" is drift; (b) the firewall is guarded by inline comments only — an optional pinning regression test is recommended (non-gating).
