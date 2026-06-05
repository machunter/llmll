# VERIFIED-REFUTED — Solver-Verdict Conjunct on `verified` + `refuted` Trust Status

> **Version:** Rev 2 (initial draft into folder; Rev 1 + Rev 2 were in-conversation iterations)
> **Date:** 2026-06-04 (Rev 1, in-conversation); 2026-06-05 (Rev 2, drafted)
> **Implements:** the spec-track companion to `VERIFY-RPT-1` (`docs/compiler-team-roadmap.md`, v0.10.x patch lane); pins the spec language the engineer's Defect-3 fix implements against
> **Prerequisites:** Feature freeze lifted (v0.11 architectural lane); VERIFY-RPT-1 engineer plan (Defect 1 fail-closed + Defect 3 strict-core verdict) is the code-track sibling
> **Origin:** demo-readiness investigation surfaced three verify-path reporting defects, recorded at [`verify-reporting-defects-2026-06-04-bug.md`](verify-reporting-defects-2026-06-04-bug.md); Defect 3 (strict-core admits body-faithful-UNSAFE) has a spec-level twin this proposal closes
> **Reviewed:** Professor review in-conversation (2026-06-04/05); recommendation `adopt with one revision` — refuted≠asserted (Finding 1), VCgen anchor, QF-LIA antecedent. Folded into this Rev 2. Standalone `*-review.md` not yet emitted; awaits doc-lead M2 fold if a written review is produced.
> **Status:** Settled (Rev 2) — pending user adjudication and engineer hand-off. Bundles with VERIFY-RPT-1 Defect 3.

---

## 1. Motivation

The verification matrix at [`LLMLL.md §5.3.5`](../../LLMLL.md) and the body-faithful definition at [`LLMLL.md §5.3.4:848`](../../LLMLL.md) state that `DLVerified "liquid-fixpoint"` with `erBodyFaithful = True` means "the implementation satisfies the contract for all well-typed inputs." That sentence names one precondition — both contract and body in QF-LIA — and **elides the solver verdict entirely**. The strict-core definition at [`LLMLL.md §5.3.4:863`](../../LLMLL.md) compounds the omission: it defines `--strict-verified-core` purely as "hard-errors if any function falls back from body-faithful verification (`erBodyFallback`)," and promises this "enforce[s] that all functions in a module are fully verified."

Both statements conflate *body VC emitted* with *body VC discharged SAFE*. A function can be body-faithful (its VC was generated, so it is not in `erBodyFallback`), have its postcondition **disproved** by liquid-fixpoint, and still satisfy the spec's stated strict-core admission criterion. The compiler exhibits the same gap: the strict-core gate at [`compiler/app/Main.hs:1149-1178`](../../compiler/app/Main.hs) runs *before* the solver (invoked at `:1208`) and refuses only on `erBodyFallback ∪ erOverflowTaintedFns` — never on a solver-UNSAFE verdict. This is the spec-level twin of `VERIFY-RPT-1` Defect 3.

The empirical demonstration is the `examples/withdraw-demo` fixture: a body filled with `(+ balance amount)` against `post (= result (- balance amount))` is type-correct, body-faithful, and **refuted** by the solver, yet `--trust-report` renders it `post: asserted` and `--strict-verified-core` (pre-fix) admits it. Tiering a *disproved* contract as `asserted` — the same label a function gets when no proof was attempted — is a fail-open in the trust lattice: it discards the counterexample the solver actively computed and reports "we don't know" where the truth is "we proved it false."

This proposal pins two things into the spec: (1) the solver-SAFE verdict as an explicit conjunct of `DLVerified` and `--strict-verified-core`, and (2) a distinct `refuted` trust status so a disproved contract is never rendered as `asserted`.

## 2. The conflation, located in three sites

| Site | Current text (paraphrase) | Defect |
|---|---|---|
| [`§5.3.4:848`](../../LLMLL.md) | `DLVerified` + `erBodyFaithful` ⇒ "satisfies the contract"; only precondition named is "both in QF-LIA" | solver verdict elided |
| [`§5.3.4:863`](../../LLMLL.md) | `--strict-verified-core` refuses `erBodyFallback`; "enforce … fully verified" | refusal set omits solver-UNSAFE |
| [`§3.4.3:313`](../../LLMLL.md) | operational closure fails on `erBodyFallback ∨ erOverflowTainted ∨ asserted-dep` | no solver-verdict conjunct |

The soundness statement of record at [`§3.4.3:308`](../../LLMLL.md) (precondition 1: "evidence record is `verified`") is *correct* — the compiler assigns `DLVerified` only in the `FQSafe` branch ([`Main.hs:1254-1287`](../../compiler/app/Main.hs); `provenCS = Map.empty` on `FQUnsafe`). The gap is that the *operational* definitions at §5.3.4:863 and §3.4.3:313 decoupled "evidence = verified" from "VC discharged SAFE" by stating admission over `erBodyFallback` alone. The three sites must move together or the spec retains an internally inconsistent definition of `verified`.

## 3. Proposal

Semantics/prose tightening plus one additive trust-report status. **No surface-grammar change, no JSON-AST schema change, no `DisplayLevel` lattice change.**

### 3.1 `DLVerified` requires solver-SAFE (§5.3.4:848)

Body-faithfulness (VC emitted) is necessary but not sufficient. `DLVerified "liquid-fixpoint"` with `erBodyFaithful = True` is assigned **only when liquid-fixpoint returns SAFE on the body VC** `P ∧ (result = ⟦B⟧) ⟹ Q`. A body-faithful VC the solver reports UNSAFE assigns no `verified` evidence.

### 3.2 `refuted` trust status (new)

A body-faithful function whose body VC the solver reports UNSAFE is *disproved*, not *unproven*. It is reported as `refuted`, distinct from `asserted`.

**Design decision — `refuted` is an orthogonal status, not a `DisplayLevel` lattice element.** It follows the established pattern of `erBodyFaithful` / `erOverflowTainted` ([`Syntax.hs:378-383`](../../compiler/src/LLMLL/Syntax.hs)): a marker *beside* the display level, not a point *on* it. The `DisplayLevel` diamond ([`Syntax.hs:359-363`](../../compiler/src/LLMLL/Syntax.hs); `DLVerified > DLContractChecked ∥ DLTested > DLAsserted`) ranks *strength of positive evidence*; refutation is *negative* evidence (a counterexample), off that axis — not "weaker than `DLAsserted`." Modelling it as a ⊥ below `DLAsserted` would conflate the evidence-strength axis with the polarity axis and force changes to `evidenceMeet` / `evidenceCovers` ([`TrustReport.hs:419-439`](../../compiler/src/LLMLL/TrustReport.hs)). The orthogonal-flag model leaves the diamond and the meet untouched.

**`refuted` is a verify-time status, not persisted evidence.** A refuted function writes no `.verified.json` entry ([`Main.hs:1287`](../../compiler/app/Main.hs), `Map.empty` on `FQUnsafe`). The status is computed during a solver-backed verify run from the `FQUnsafe` verdict × the constraint-table function origin ([`DiagnosticFQ.hs`](../../compiler/src/LLMLL/DiagnosticFQ.hs) `ConstraintOrigin`), and surfaced in:
- `--trust-report`: per-entry `refuted: true` + top-level `refuted_fns`;
- the obligation report: a `refuted` obligation carrying the solver counterexample's JSON pointer to the `post` clause.

A solver-less trust-report render (the pre-solver path at [`Main.hs:1097-1104`](../../compiler/app/Main.hs)) shows the function as `asserted` (no sidecar entry) — honest "not verified," with the stronger refuted information available only when the solver runs. Persisting negative evidence is deliberately out of scope: a since-fixed function would carry a stale `refuted` tag.

**Transitive treatment reuses the drift channel.** A caller whose transitive callee is refuted has an unsound assume-guarantee proof — it *assumes* a postcondition the solver disproved. It is flagged `depends-on-refuted` via the existing `computeDrifts` / `teDrifts` mechanism ([`TrustReport.hs:448, 466`](../../compiler/src/LLMLL/TrustReport.hs)), at the strongest drift severity — not via `evidenceMeet`. This mirrors how asserted-dependencies already produce epistemic-drift warnings ([`§5.3.5`](../../LLMLL.md) item 4), strengthened because the dependency is *known-false*, not merely unknown.

### 3.3 `--strict-verified-core` as a four-way refusal (§5.3.4:863)

Refuse if any function in the transitive call graph has: (a) `erBodyFallback = True`, (b) `erOverflowTainted = True`, (c) **a body VC the solver reports UNSAFE (refuted)**, or (d) an `asserted`-tier dependency. Conjunct (c) is transitive *because* of assume-guarantee composition: [`§0.1:52`](../../LLMLL.md) already conditions soundness on "both functions independently verified," which a refuted callee violates — a caller of a refuted function cannot be admitted even if its own VC is SAFE, since that SAFE rests on a disproved assumption.

### 3.4 Operational closure + QF-LIA antecedent (§3.4.3:313)

The admissibility-failure set becomes `erBodyFallback ∨ erOverflowTainted ∨ refuted ∨ asserted-dep`. The solver-verdict conjunct sits as a *side condition*, not a quantifier over solver runs, **precisely because body-faithful VCs are confined to QF-LIA**, for which liquid-fixpoint/Z3 is a sound-and-complete decision procedure — so "SAFE" is a decidable predicate on the fixed VC, a total function of it. This antecedent must be stated explicitly: the clean formulation degrades to run-dependence if a non-QF-LIA VC were ever admitted to the body-faithful tier (REF-META-2 widening, [`v0.12-direction.md §1`](v0.12-direction.md)).

The REF-META-4 erasure statement should carry "all body VCs valid (SAFE)" as its hypothesis in the **VCgen/Hoare** sense (the discharged-VC-set as the standing antecedent, as in Dafny/Boogie VCgen soundness), not as a Liquid-Haskell application-site subtyping premise: LLMLL's body-faithful mode `P ∧ (result = ⟦B⟧) ⟹ Q` ([`§5.3.4:842-845`](../../LLMLL.md)) is verification-condition generation, not subtyping. This proposal *anticipates* REF-META-4 ([`v0.12-direction.md §1`](v0.12-direction.md)).

### 3.5 Sidecar `codegen_semantics_version` stamp — deferred

The professor's Finding 1 (in-conversation) recommends an additive `§4.4` invariant: a `verified` evidence record is sound relative to the codegen-semantics version that produced it; the eventual INT-3 `machine-int` taint re-arm keys on that stamp, not on field-absence. This is a separable TRUST- item; it does not block the present fix and is not bundled here. It is recorded so the connection is not lost.

## 4. Edge cases and degenerate inputs

1. **Body-faithful, solver UNSAFE** (`withdraw` `(+)` fill). No `DLVerified`; `refuted` in trust + obligation reports with counterexample pointer; `--strict-verified-core` exits non-zero. Channel: **contract** (body VC, QF-LIA) → **trust** (refuted). Cite: §5.3.4:848/863 post-edit; [`Main.hs:1254-1287`](../../compiler/app/Main.hs).
2. **Caller of a refuted callee.** Own VC may be SAFE, but flagged `depends-on-refuted` (strongest drift) and refused from strict core. Channel: **trust** (drift). Cite: [`§0.1:52`](../../LLMLL.md); [`TrustReport.hs:448`](../../compiler/src/LLMLL/TrustReport.hs).
3. **Solver-less `--trust-report` on a refuted function.** Shows `asserted` (no sidecar entry) — honest "not verified"; refuted detail unavailable without the solver. Channel: **trust** (spec silent on persisting negative evidence — intentional). Cite: [`Main.hs:1097-1104, 1287`](../../compiler/app/Main.hs).
4. **Body-faithful, solver SAFE.** `DLVerified`, `erBodyFaithful = True`, no refuted flag, strict-core admits. Channel: **contract**. Cite: §5.3.4:848.
5. **Contract-only fallback** (general `EMatch`, `letrec` own body). `erBodyFallback = True`, refused by conjunct (a); **not** `refuted` (no body VC attempted) — correctly distinct. Channel: **trust**. Cite: [`§5.3.4:850, 863`](../../LLMLL.md).

## 5. Verification mapping

No new proof obligation. The proposal makes the *discharge verdict* of the existing QF-LIA body VC load-bearing and adds a report-time status derived from it.

- **Channel:** contract (body VC) → trust (refuted status + depends-on-refuted drift). `refuted` is a trust-channel projection of a contract-channel verdict.
- **Fragment:** QF-LIA, auto-discharged by liquid-fixpoint ([`§5.3.5`](../../LLMLL.md); `FQInt` = unbounded SMT `Int`). No obligation moves to nonlinear or Lean. QF-LIA confinement is now an explicit antecedent of the soundness side-condition (§3.4), not merely an ergonomic boundary.
- **Boundary:** §5.3.3 / §5.3.5; [`FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs) body-VC emission; [`DiagnosticFQ.hs`](../../compiler/src/LLMLL/DiagnosticFQ.hs) `FQUnsafe` → refuted derivation.

## 6. Affected surface

- `LLMLL.md §5.3.4:848, :863` — `DLVerified` solver-SAFE conjunct; strict-core four-way refusal (doc-lead).
- `LLMLL.md §3.4.3:313` — closure conjunct + QF-LIA antecedent + VCgen REF-META-4 framing (doc-lead).
- `LLMLL.md §4.4` — `refuted` defined as orthogonal status (not a `DisplayLevel`); deferred version-stamp invariant (doc-lead).
- `LLMLL.md §5.3.5:907` — overflow NOTE corrected post-Defect-2 (doc-lead, after engineer ships).
- `compiler/src/LLMLL/TrustReport.hs` (per-entry `refuted` + `refuted_fns` + `depends-on-refuted` drift); `compiler/app/Main.hs:1143-1178` (strict-core conjunct); `DiagnosticFQ.hs` / `ObligationAssembly.hs` (refuted obligation + counterexample pointer) — **engineer's slot**; bundles with VERIFY-RPT-1 Defect 3.
- `trust_report_version` 1.2.0 → **1.3.0** (additive: `refuted` per-entry flag, `refuted_fns`, drift kind). `evidenceMeet` / `evidenceCovers` **untouched**. No AST-schema change. **No `DisplayLevel` change.**
- `docs/compiler-team-roadmap.md` VERIFY-RPT-1 row — doc-lead annotates the trust-model companion on settlement.

## 7. Risks and open questions

1. **`refuted` not persisted ⇒ solver-less trust report cannot show it.** Class: trust-model / scope. Cite: [`Main.hs:1287`](../../compiler/app/Main.hs), edge case 3. Bite: only matters at scale — acceptable; persisting negative evidence invites staleness. Deliberate scope exclusion.
2. **Three §-sites must move together.** Class: spec-drift / soundness. Cite: §3.4.3:308 hook vs §5.3.4:863 gate. Bite: blocks a clean fix if split — 848, 863, 313 are one definitional unit.
3. **`refuted`-as-status diverges from Dafny hard-fail.** Class: scope. Cite: design-reference set (Dafny rejects refuted programs outright). Bite: does not block — LLMLL's permissive trust-tier model is a deliberate scope choice; `refuted`-as-status serves the repair-loop agent that must read "disproved, fix the body" without the program being rejected. Scope divergence, not a soundness gap.
4. **Strict immutability:** unaffected — evidence/reporting semantics only.

## 8. Resolution log

- **Rev 1 → Rev 2:** Professor Finding 1 (refuted ≠ asserted) replaced Rev 1's "remains at prior tier" clause with the `refuted` status. Report-only-vs-lattice question resolved to **orthogonal status** (grounded in the `erBodyFaithful`/`erOverflowTainted` precedent and the two-channel `enrichEntry` propagation). Transitivity rationale (assume-guarantee, §0.1:52) and QF-LIA antecedent added per Findings 4 and 3. REF-META-4 anchor reframed to VCgen/Hoare per the citation correction. Erasure-theorem question answered: pure strengthening; solver verdict is a decidable side-condition under QF-LIA confinement, not a quantifier over solver runs.
