# Verification Design Debate — LLMLL

> **Context:** This document archives a formal methods critique of LLMLL's verification claims, conducted April 2026. The critique forced a rigorous separation of engineering claims from metatheoretic claims, resulting in a more defensible positioning of the system.

---

## System Characterization (agreed)

> **A Haskell-generating, multi-agent programming system with refinement-style specifications, heuristic verification routing, and explicit propagation of trust levels across dependencies, using SMT solving and interactive theorem proving as auxiliary validation mechanisms.**

This is Path A (engineering-first), not Path B (foundations-first).

**Semantic anchor (Option A):** LLMLL is a Haskell-generating language with auxiliary verification metadata. The semantics of an LLMLL program IS the generated Haskell program. Contracts, trust levels, and verification metadata are external overlays — they constrain and annotate, but the operational meaning is defined by Haskell.

---

## The 5 Socratic Questions — Answered

### 1. What is the trusted core?

**GHC System FC** ensures structural soundness of the generated Haskell program; this guarantee depends on the correctness of the code generation step (`CodegenHs.hs`). If codegen is incorrect, GHC checks the wrong program and structural soundness no longer applies to the original LLMLL semantics.

The full Trusted Computing Base (TCB) includes:
- GHC (System FC) — structural soundness
- liquid-fixpoint encoding — refinement soundness
- Z3 — SMT solver correctness
- Lean 4 kernel — proof correctness
- `LeanTranslate.hs` — translation correctness (unverified)
- `CodegenHs.hs` — code generation correctness (unverified)

The translation layers (`LeanTranslate`, `CodegenHs`) are unverified parts of the TCB. If they are incorrect, guarantees collapse silently. This is standard for systems like CompCert, F*, and Why3, but must be acknowledged.

**User-provided specifications are also effectively part of the TCB.** Incorrect or incomplete specifications can invalidate all higher-level guarantees — a wrong spec means the system "proves" the wrong thing; an inconsistent spec makes everything provable. This is inherent to all specification-based systems (Dafny, F*, Coq via axioms) but must be stated explicitly.

### 2. Which logic is authoritative when SMT and Lean disagree?

They operate on **heuristically partitioned verification domains**:

| Classification | Route | Verifier |
|---|---|---|
| `:simple` — decidable arithmetic | liquid-fixpoint | Z3 |
| `:inductive` — structural recursion | Leanstral | Lean 4 kernel |
| `:unknown` — unclassifiable | none | runtime assertion |

Properties are routed to exactly one verifier based on classification. However:
- Classification is **heuristic**, not formally decidable
- Properties can straddle fragments (e.g., `sorted(xs) ⇒ sum(xs) >= 0`)
- Equivalent properties expressed differently may route to different verifiers

**Honest statement:** Fragment classification is heuristic and may route equivalent properties to different verifiers. The system does not enforce semantic coherence between verification fragments; equivalent properties may be validated under different logical models.

### 3. Can unproven contracts influence types?

**Yes.** A dependent type like `SortedList` whose predicate is only "asserted" creates a type whose guarantee rests on an unproven assertion. Downstream code inherits the lower trust level.

This is the same mechanism as:
- Liquid Haskell's `{-@ assume @-}` directive
- Lean's `sorry`
- Coq's `Axiom`

**LLMLL is sound modulo:**
- `(trust ...)` declarations
- encoding correctness (liquid-fixpoint → Z3)
- translation correctness (LeanTranslate)
- solver correctness (Z3, rare but real bugs exist)

### 4. Where is totality enforced?

- **Lean proof fragment:** Total. Lean's kernel enforces this.
- **LLMLL programs:** Not total. General recursion is allowed.
- **Mitigation:** `letrec` with `:decreases` measures for termination checking (partial).

**Consequence:** Proofs establish **partial correctness only**; termination is not guaranteed, and non-termination may vacuously satisfy postconditions. The `:decreases` mechanism provides termination evidence for specific recursive structures but does not constitute a global totality guarantee.

### 5. How are assumptions tracked across agent boundaries?

**Trust-level propagation.** Implemented in `VerifiedCache.hs`.

- A conclusion inherits the minimum trust level in its dependency chain
- If Agent A's contract is "asserted," anything Agent B derives from it is at most "asserted"
- The module-level verification report shows the full assumption chain

**What this achieves:** Transparency and traceability of assumptions.
**What this does NOT achieve:** Compositional correctness or logical soundness. Invalid conclusions can be derived from unproven contracts — they are annotated, not prevented.

**Risk: epistemic drift.** In large systems, this can lead to epistemic drift, where most guarantees are technically unproven but practically relied upon. This is a known failure mode in systems with `assume`/`sorry` and must be actively managed through review discipline and progressive verification (asserted → tested → proven).

---

## Key Concessions

### 1. Specification completeness is not enforced
The system makes specification gaps visible, not impossible. A degenerate spec (e.g., `length(output) = length(input)` for a sorting function) admits trivial implementations. This is inherent to all specification-based systems.

### 2. Multi-logic composition is engineering, not metatheory
Three verified backends (GHC, Z3, Lean) composed by engineering, not by unified type theory. The composition is standard practice (Liquid Haskell, F*, Dafny) but not formally proven sound.

### 3. Trust propagation ≠ compositional soundness
Trust propagation makes unsoundness visible but does not prevent invalid conclusions from being derived. Risk of "epistemic drift" in large systems where most guarantees are implicitly untrusted but practically relied upon.

### 4. Fragment classification is heuristic
Not formally decidable. Properties straddling fragments may be routed suboptimally. No cross-verifier consistency guarantee.

---

## Unresolved (Scoped for Future Work)

1. **Unified semantics across verification layers** — would require a core calculus
2. **Formal definition of fragment classification** — decision procedure for property routing
3. **Precise TCB boundary verification** — especially `LeanTranslate.hs`
4. **Effect system formal semantics** — currently checked structurally, not algebraically
5. **Specification adequacy** — inherent problem, partially mitigated by property-based testing

---

## Path Forward

The system is **engineering-first with explicit limitations**:
- Embrace "sound modulo trust"
- Focus on usability, orchestration, tooling
- Be explicit about what is and isn't guaranteed
- Treat SMT and Lean as auxiliary verification mechanisms, not foundational truth systems

A foundations-first approach (core calculus, soundness theorems, unified logic) is a valid future direction but is not required for the current system to be useful and defensible.
