# PROOF-ARTIFACT — Unified, Reproducible Verification Artifact

> **Version:** Rev 2 — professor review folded ([`proof-artifact-review.md`](proof-artifact-review.md), 2026-06-20, `revise-and-resubmit`). Six findings incorporated: (1) the two replay "modes" are recast as **two distinct properties with two trusted bases** — *replay reproducibility* vs. *independent checkability* — not two price points on one axis (§4.4); (2) the §1 motivation is restated to what the design actually delivers (hermetic, version-pinned re-verification), dropping "not a compiler run"; (3) the artifact ships the **unsat core**, not the raw `.fq` alone (formerly "Mode 1.5"), at F*-`.hints` granularity (§4.2/§4.4); (4) `unknown`/timeout is a distinct fail-closed outcome and the determinism inputs beyond `solver_version` are pinned (§4.3); (5) faithfulness is promoted from a risk to a **schema well-formedness invariant** enforced LCF-style by a smart constructor (§4.1); (6) the genuine certificate path is the **Lean tier**, not Z3 proof-object serialization (§4.4/§7). Rev 1 (2026-06-20) was the initial consolidation proposal.
> **Date:** 2026-06-20 (Rev 1; Rev 2)
> **Implements:** Active-Items row `PROOF-ARTIFACT` (`docs/compiler-team-roadmap.md`, doc-lead pass 2026-06-20). Originates from the two-round external critique adjudication.
> **Prerequisites:** None new. Consolidates the existing verification-output surface — `verify --fq-out` (`.fq`), `--trust-report`, `--obligation-report`, the `.verified.json` sidecar (`erVerifiedHash`), `consumed_guarantees`, `caller_obligations`. Leans on the VERIFY-RPT-1 sidecar hash-guard discipline ([`VerifiedCache.hs:201-228`](../../compiler/src/LLMLL/VerifiedCache.hs)) and the INT-3 `codegen_semantics_version` stamp requirement (`LLMLL.md §5.3.5:1051`).
> **Origin:** External critique rounds 1 and 2 (convergent recommendation, identical field list both rounds) — paraphrased "a verified claim should be reproducible from an artifact." Language-team adjudication confirmed the recommendation is untracked and in-scope.
> **Reviewed:** Professor review at [`proof-artifact-review.md`](proof-artifact-review.md) (2026-06-20), recommendation `revise-and-resubmit`; six findings folded into this Rev 2 (see Version line). Standalone review awaits doc-lead M2 fold-and-archive on settlement.
> **Status:** Proposed (Rev 2) — professor review incorporated; awaiting user adjudication and settlement.

---

## 1. Motivation

LLMLL already computes everything needed to justify a `verified` claim, but the justification is **scattered across five command surfaces and one sidecar**: the `.fq` constraint file (`verify --fq-out`), the trust report (`--trust-report`: tier, transitive closure, drifts, `discriminative_axis`), the obligation report (`--obligation-report`: per-hole/clause obligations, `effect_summary`, `consumed_guarantees`, `caller_obligations`), and the `.verified.json` sidecar (`erVerifiedHash`, solver verdict, `erBodyFallback`). A consumer who wants to answer *"why is this function `verified`, and on what does that rest?"* must run several commands and reconcile their outputs by hand.

The external reviewer's recommendation — arrived at in both critique rounds with the same field list — is to unify these into **one serializable artifact per verification run**. The honest value proposition (corrected in Rev 2 per professor finding 2) is **a hermetic, version-pinned, auditable re-verification record**: the artifact captures the exact verification *input* — the VC, the unsat core, the solver version and option set, the codegen-semantics stamp, the assumed callee guarantees, the caller obligations — so that the verdict can be **re-derived deterministically** and **audited in one place**, with every positive tier structurally inseparable from what it rests on. This is the project's anti-laundering discipline (round-2 critique §13; `verification-debate.md` "sound modulo trust") rendered as a single object whose well-formedness *forbids* presenting a tier without its qualifiers (§4.1).

Rev 2 explicitly does **not** claim "reproducible without a compiler run." Re-derivation re-invokes the solver; for a deterministic solver on a fixed VC that is near-tautological as a *correctness* statement. What it buys is *hermeticity and auditability* — the same value F\*'s `.hints` mechanism (Swamy et al., *Dependent Types and Multi-Monadic Effects in F\**, POPL 2016) and Dafny's verification caching (Leino, *Dafny*, LPAR 2010) provide: a pinned, replayable record. Independent checkability — validating a verdict *without* trusting or re-running the solver — is a strictly different property with a different trusted base (§4.4), reserved for the Lean tier (§7).

The `.verified.json` sidecar is already ~70% of the artifact (`erVerifiedHash`, solver verdict, `erBodyFallback`); PROOF-ARTIFACT consolidates the remaining surface plus the delta fields no current output carries: **the unsat core, the solver version and option/resource set, the callee-assumption set, the erased core, and the CDP basis `Ω`.** This is a synthesis, not a new verification primitive: **no new proof obligation, no fragment expansion, no `?proof-required`** (§6), and explicitly **decoupled** from fragment growth (§7).

## 2. Scope

**In scope.**
- A single serializable **proof-artifact object** (one per verify run, with a per-function projection) unifying the existing trust-report / obligation-report / `.fq` / sidecar fields plus the delta fields of §4.2.
- The **unsat core** as the primary proof-trace field (not the raw `.fq` alone).
- An emit path: `llmll verify <file> --proof-artifact <FILE>` (additive, informational).
- A replay path: `llmll replay-artifact <FILE>` that re-derives the recorded verdict and **fails closed** on any source/AST/solver/option mismatch *or* on `unknown`/timeout (§4.3).
- The artifact schema, its version stamp, and its well-formedness invariant (§4.1).

**Out of scope.**
- **Independent checkability for the SMT tier.** The artifact does not make an SMT verdict checkable without re-running the solver, and (per professor finding 6) does **not** pursue Z3 proof-object serialization — Z3 proofs are large, under-specified, and consumed by almost no independent checker (de Moura–Bjørner; the field moved to Alethe / cvc5 / SMTCoq for exactly this reason). The genuine certificate path is the Lean tier (§7).
- **Fragment expansion.** PROOF-ARTIFACT records what the verifier already proved; it does not enlarge `Σ_auto` (§5.3.3).
- **New builtins, syntax, FFI, or JSON-AST source change.** The artifact is an *output*, not a source form.

## 3. Surface

**Source surface: none.** No S-expression or JSON-AST change. The artifact is emitted, not authored.

**CLI surface (additive):**

```
llmll verify <file> --proof-artifact <FILE>     # emit the artifact for this run
llmll replay-artifact <FILE>                     # re-derive + check; fail closed on mismatch / unknown
```

**Freeze posture.** The feature freeze is lifted (`docs/compiler-team-roadmap.md:47`). The flags are additive and informational and introduce **no new escape hatch** — they expose existing verdicts and re-run an existing decision procedure. The written-soundness-argument discipline (`LLMLL.md §3.4.2`; roadmap `:33-36`) is satisfied by §6: the artifact is a conservative summary of decidable verdicts, and replay is the same QF-LIA decision under a pinned solver.

## 4. Semantics

### 4.1 The artifact is a conservative summary — enforced as a well-formedness invariant

The artifact asserts nothing the trust report does not already assert; its contribution is *colocation + reproducibility metadata*. Formally it is the trust-report-theorem reading (`LLMLL.md §5.3.4`): the labels are a conservative summary of the underlying VC verdicts and the assume-guarantee closure — soundness-of-abstraction in the Cousot sense.

**Faithfulness invariant (Rev 2, per professor finding 5 — promoted from a risk to a schema condition).** A per-function record carrying a **positive tier** (`verified` / `contract-checked` / `tested`) is **ill-formed unless its conjoined qualifying fields are present**: `caller_obligations`, the `fallback_reason` slot (empty iff body-faithful), the `refuted` flag (necessarily false), and — when present — the `discriminative_axis.basis`. This is the LCF discipline (Milner, *Edinburgh LCF*, 1979): a positive-tier record is mintable **only** through a smart constructor that refuses to build one without the qualifiers, exactly as a `Thm` is mintable only through the kernel. The invariant is a well-formedness rule on the artifact schema, analogous in status to the §3.4.4 predicate well-formedness rule — checkable, non-SMT. This is what makes evidence-laundering by field omission structurally impossible rather than merely discouraged.

### 4.2 Artifact fields

Per verification run (with a per-function projection); fields marked **†** are the delta no current output carries:

| Field | Source today | Note |
|---|---|---|
| `source_hash`, `ast_hash` | `erVerifiedHash` (`Syntax.hs:390-402`) | identity; drives staleness |
| `erased_core` **†** | codegen lowering (`CodegenHs.hs`) | the predicate-blind core the VC is taken over. **Records, does not certify** — codegen faithfulness remains a `§3.4.3` commitment (Path B declined), not closed here (professor finding 4) |
| `vc` | `.fq` emit (`verify --fq-out`) | the body-faithful VC `P ∧ (result = ⟦B⟧) ⟹ Q` per function |
| `unsat_core` **†** | Z3 tracked assertions / liquid-fixpoint constraint IDs | **primary proof trace** — the named subset of hypotheses (callee posts, refinement predicates, path conditions) the proof actually consumed; F\*-`.hints` granularity (professor finding 3). See §8 for the extraction feasibility note |
| `solver_result` | `.verified.json` | SAFE / UNSAFE(refuted) / no-VC(fallback) / **unknown(fail-closed)** |
| `solver_version`, `solver_options`, `resource_limits` **†** | — | pins the determinism inputs for replay, not version alone (professor finding 3) |
| `codegen_semantics_version` **†** | `LLMLL.md §5.3.5:1051` (defined, dormant) | distinguishes unbounded `int` from a future bounded `machine-int` |
| `callee_assumptions` | `consumed_guarantees` (v0.13) | assume-guarantee hypotheses imported at SAFE call sites |
| `caller_obligations` | `caller_obligations` axis (v0.13, `trust_report_version 1.4.0`) | preconditions the caller must discharge — **required** under §4.1 for any pre-bearing positive-tier fn |
| `sidecar_hashes` | `erVerifiedHash` | for cross-module verified composition |
| `fallback_reason` | `erBodyFallback` (`FixpointEmit.hs:891-901`) | why a construct left the body-faithful fragment — **required** slot (empty iff body-faithful) |
| `refuted` | `refuted` status (VERIFY-RPT-1) | orthogonal negative evidence; necessarily false on a positive tier |
| `evidence_level` | trust tier (`§4.4`) | the diamond-lattice tier |
| `discriminative_axis` (+ `basis` `Ω`) | `--cdp` (`§4.4.6`) | **`basis` required when present** — observational, not semantic (§9, Risk 4) |
| `effect_summary` (+ `cross_module`) | Bundle B0 (`LLMLL.md:1838`) | authority over-approximation; informational |
| `certificate` (reserved, optional) **†** | — | format-agnostic slot for the Lean-tier certificate (§4.4); **never** a Z3 proof object |

### 4.3 Replay-determinism (fail-closed)

`replay-artifact` recomputes `source_hash`/`ast_hash` against the named source, and — if they match — re-runs the recorded `vc` (seeded by `unsat_core`) under the pinned `solver_version` + `solver_options` + `resource_limits`. The recorded verdict must reproduce. **It fails closed on any of:** a differing source/AST hash; a differing `solver_version`, `solver_options`, `resource_limits`, or `codegen_semantics_version`; or a replay outcome of **`unknown`/timeout** — which is *neither* SAFE *nor* UNSAFE and must demote to "needs re-verify," never be read as a verdict (professor finding 3). The version/option stamp — *not* field-absence — is the trigger, exactly as the INT-3 forward-note insists (`§5.3.5:1051`), so the disarmed-overflow antecedent is never silently inherited.

`LLMLL.md §5.3.3` guarantees decidability of the *fragment*; it does **not** guarantee bit-reproducibility of a particular Z3 build across platform, options, resource limits, or seed. Pinning those inputs is what makes the re-run deterministic; `unknown` under matching inputs (unlikely for QF-LIA, possible under a tight resource limit) still fails closed.

### 4.4 Two reproducibility properties, two trusted bases — not one axis

Rev 2 corrects the Rev 1 "Mode 1 vs Mode 2, weaker vs stronger" framing (professor finding 1). Reproducibility of a machine-checked claim is two *distinct properties*:

- **Replay reproducibility** (the **R-property**). Re-run, get the same verdict. **Trusted base = the pinned solver build + determinism inputs.** This is what the artifact ships for the **SMT tier** (QF-LIA + measure class): `vc` + `unsat_core` + pinned `solver_*`. It is a legitimate, field-validated notion — F\*'s `.hints` (Swamy et al., POPL 2016) and Dafny's caching (Leino, LPAR 2010) are exactly this. It does **not** make the verdict checkable without the solver.
- **Independent checkability** (the **C-property**). A third party validates a verdict *without trusting or re-running the prover*, against a **small checker** (the de Bruijn criterion; Barendregt–Geuvers). The lineage is proof-carrying code (Necula, POPL 1997), SMTCoq (Ekici et al., CAV 2017), the Alethe format checked by Carcara (Schurr–Fleury–Barbosa, PxTP 2021), and the DRAT/LRAT certificates the SAT community adopted *because* solver-trust failed after repeated solver bugs.

These have different trusted bases and answer different questions; they are not two prices for one good. The artifact's design therefore **splits the certificate path by tier**:

- **SMT tier → R-property only.** Ship `unsat_core`; do **not** attempt the C-property via Z3 proof objects (professor finding 6 — wrong source for a checkable certificate).
- **Lean tier → C-property (the genuine certificate).** The §7 `verified(lean)` direction *is* independent checkability by construction: a Lean proof term is the certificate and Lean's kernel is the small checker, satisfying de Bruijn. The reserved, format-agnostic `certificate` field (§4.2) is populated **here**, tied to the Lean-replayability item and the `ProofCache.hs` SHA-256 discipline — not to Z3.

## 5. Edge cases and degenerate inputs

1. **Stale determinism inputs.** Artifact recorded under solver build / option set / resource limit *A*; replayed under *B*. *Expected:* fail closed — any of `solver_version` / `solver_options` / `resource_limits` mismatch invalidates the artifact; no verdict honored. *Channel:* trust. *Cite:* §4.3; `§5.3.5:1051`.
2. **Replay returns `unknown`/timeout** under matching inputs (e.g. a tightened resource limit). *Expected:* fail closed as a **distinct** outcome — demote to "needs re-verify," never read as SAFE or UNSAFE. *Channel:* trust. *Cite:* §4.3 (professor finding 3).
3. **Artifact for a fallback function.** *Expected:* `solver_result = no-VC`, `fallback_reason` populated, **no positive tier** — the §4.1 invariant makes a positive-tier-with-nonempty-fallback record unconstructible. *Channel:* trust. *Cite:* `§3.4.5:379` soundness firewall.
4. **Refuted VC.** *Expected:* `refuted = true`, orthogonal to the positive axis; never rendered `verified`; the §4.1 invariant forbids a positive tier with `refuted = true`. *Channel:* trust. *Cite:* VERIFY-RPT-1; `§5.3.4:982`.
5. **Cross-module callee not loaded.** *Expected:* `callee_assumptions` marked incomplete and `cross_module: single-file`; the claim is scoped to what was walked (∅-iff-fully-walked). No silent `verified` cross-module composition the open XMOD-COMP gap (3 fixed/2 open) cannot justify. *Channel:* trust. *Cite:* `cross-module-composition-finding.md`; B0 cross-module addendum.
6. **CDP basis drift.** *Expected:* `discriminative_axis.basis` records `Ω`; the §4.1 invariant requires `basis` when `discriminative_axis` is present, so cross-`Ω` comparison cannot silently occur. *Channel:* trust (advisory). *Cite:* `§4.4.6:702`.

## 6. Verification mapping

PROOF-ARTIFACT introduces **no new proof obligation**:

- **Artifact-faithfulness (§4.1 invariant)** — *Channel:* trust. *Fragment:* **not an SMT obligation** — a checkable well-formedness condition on the schema (smart-constructor-enforced), the same status as §3.4.4 predicate WF. *Cite:* `§5.3.4`; `§5.3.3:961`.
- **Replay-determinism (R-property)** — *Channel:* trust. *Fragment:* **QF-LIA** — re-runs the *same* fixed VC (seeded by `unsat_core`) under pinned determinism inputs; no new theory, no quantifiers. *Cite:* `§5.3.3:982`, `§5.3.5:1051`.

No obligation **escapes to Lean** in this proposal; the C-property (Lean tier) is recorded as the future home of a genuine certificate but is not implemented here. The artifact introduces no `?proof-required`. This is the structural signal that the recommendation is an integration/serialization move, not a verification-surface change.

## 7. Tracked-concept relation

- **Consolidates** the existing scattered surface (trust report, obligation report, `.fq`, `.verified.json`, `consumed_guarantees`, `caller_obligations`) into the single object those five surfaces project from.
- **Reaches F\*-`.hints` parity** for the SMT tier (R-property at unsat-core granularity) — ahead of Liquid Haskell (Vazou et al., POPL 2014), which trusts Z3 outright with no artifact; level with F\*/Dafny on replay; Idris (kernel-checked proof terms, no SMT) is a different quadrant, not a competitor on this axis.
- **Anticipates** the long-term `verified(lean)` = "independently checkable proof" item as the genuine **C-property** home: Lean kernel = de Bruijn checker, proof term = certificate; the reserved `certificate` field and `ProofCache.hs` are the seam.
- **Carries** the CDP `discriminative_axis` and Bundle B0 `effect_summary` as fields — and, for CDP, **carries its observational caveat with it** (`basis` required), so the artifact does not become a vector for the score-misreading the caveat warns against.
- **Orthogonal to / decoupled from** verification-fragment growth (round-2 push-back): fragment expansion (NIW measures, a future string theory) and artifact unification are independent workstreams; neither gates the other.
- **Builds on** VERIFY-RPT-1 (sidecar fail-closed) and the INT-3 stamp note — generalizing the sidecar hash-guard from "is this cached verdict stale?" to "is this published claim hermetically replayable?"

## 8. Affected surface

Not an implementation plan (engineer's slot) — the seam at which the engineer takes over:

- `compiler/src/LLMLL/TrustReport.hs` — the artifact is largely a re-projection of the trust-report assembly + the §4.1 smart constructor.
- `compiler/src/LLMLL/VerifiedCache.hs` — the `.verified.json` sidecar is the seed; the artifact is its superset.
- `compiler/src/LLMLL/ObligationAssembly.hs` — `consumed_guarantees`, `caller_obligations`, `effect_summary` source.
- `compiler/src/LLMLL/FixpointEmit.hs` / `FixpointIR.hs` — the `vc` text, `erBodyFallback`, and the **`unsat_core` extraction**. *Feasibility note:* liquid-fixpoint constraints carry IDs, but surfacing Z3's unsat core back through the fixpoint layer (vs. a fixpoint-level core, or a direct tracked-assertion path) is the engineer's feasibility check; if the core is not cheaply available, ship the R-property on the full `vc` first and add `unsat_core` as a follow-up — the schema reserves the field either way.
- `compiler/app/Main.hs` — the `--proof-artifact` / `replay-artifact` flags.
- `docs/llmll-ast.schema.json` (or a new `docs/proof-artifact.schema.json`) — artifact schema, version stamp, and the §4.1 well-formedness invariant.
- `LLMLL.md` — a new subsection under §5 (doc-lead, post-ship).
- `docs/compiler-team-roadmap.md` — the `PROOF-ARTIFACT` Active-Items row (doc-lead, landed 2026-06-20).

## 9. Risks and open questions

1. **Staleness / `unknown` must fail closed** — *soundness.* If replay does not invalidate on a determinism-input mismatch or on `unknown`, a stale or non-verdict launders an unverified claim. *Bite:* blocks the proposal unless §4.3's fail-closed discipline (now covering `unknown` and the full determinism-input set) is a hard precondition. Mitigated by reusing VERIFY-RPT-1.
2. **Evidence-laundering by field omission** — *soundness.* Resolved in Rev 2 by promoting the required-fields rule to the §4.1 smart-constructor invariant — a positive tier is unconstructible without its qualifiers. No longer a residual risk if §4.1 is implemented as stated.
3. **Unsat-core extraction feasibility** — *ergonomic / scope.* The most informative field (`unsat_core`) depends on surfacing Z3's core through liquid-fixpoint (§8). *Bite:* does not block the R-property (fall back to the full `vc`); only delays the minimized/auditable form.
4. **CDP observational caveat must travel** — *verification-ergonomics.* Enforced by §4.1 (`basis` required when `discriminative_axis` present). *Bite:* low, given the invariant.
5. **`certificate` field misuse** — *scope.* If a future contributor populates `certificate` with a Z3 proof object, the field's purpose is defeated. *Bite:* low; the schema should constrain `certificate` to the Lean-tier format and document the §4.4 rationale inline.
6. **Schema/version churn** — *spec-drift.* One more versioned surface (alongside `trust_report_version`, `orSchemaVersion`, `schemaVersion`). *Bite:* manageable; recommend the artifact embed the versions it composes rather than mint a wholly independent one.

## 10. Open questions for the professor — resolved (Rev 2)

The Rev 1 §10 question (is "reproducible proof artifact" a known notion; is re-run adequate or is a Z3 proof object required) was answered in [`proof-artifact-review.md`](proof-artifact-review.md): the notion bifurcates into the **R-property** (replay; trusted solver; F\*-`.hints` precedent) and the **C-property** (independent checkability; small checker; PCC/SMTCoq/Alethe/Lean), with different trusted bases. The two open questions the professor handed back to the language-team are resolved in this revision:

1. *Full `.fq` vs unsat core* → **adopt the unsat core** as the primary proof-trace field at F\*-hint granularity (§4.2), with the full `vc` retained as a fallback pending the §8 extraction-feasibility check.
2. *`unknown`/timeout and determinism inputs* → **`unknown`/timeout fails closed as a distinct outcome** (§4.3, §5 edge case 2), and the artifact pins `solver_version` + `solver_options` + `resource_limits` (+ `codegen_semantics_version`), not the version alone.

No open professor questions remain for Rev 2.

---

## Appendix — Professor review log

> Folded on settlement (M2). The standalone review is archived at [`docs/archive/professor-reviews/proof-artifact-review.md`](../archive/professor-reviews/proof-artifact-review.md). Shipped as v0.14.0 (staged MVP).

**Review of Rev 1** (professor, 2026-06-20) — recommendation **revise-and-resubmit**. The proposal was sound and in-scope; the central framing conflated two distinct properties, the §1 motivation overclaimed, and the closest external precedent (F\* hints) was omitted. Six gaps, all folded into Rev 2:

1. **Mode 1 vs Mode 2 are not one axis** — two properties with two trusted bases: *replay reproducibility* (re-run, same verdict; trusted base = the solver build; F\* `.hints`, Dafny caching) vs. *independent checkability* (validate without trusting/re-running the prover; trusted base = a small checker; PCC, de Bruijn, SMTCoq, Alethe/Carcara, DRAT/LRAT). → §4.4.
2. **§1 overclaims** — Mode 1 *is* a compiler run; what it delivers is hermetic, version-pinned re-verification, not "reproducible without a compiler run." → §1.
3. **`solver_version` insufficient; `unknown`/timeout unhandled** — pin options + resource limits (+ seed/platform), and make `unknown` a distinct fail-closed outcome. → §4.3.
4. **`erased_core` gives false end-to-end appearance** — codegen faithfulness stays a `§3.4.3` commitment (Path B declined); record, do not certify. → §4.2.
5. **Faithfulness was prose, not a representable invariant** — promote to a schema well-formedness condition enforced LCF-style by a smart constructor (a positive tier is unconstructible without its qualifiers). → §4.1.
6. **"Serialize Z3's proof object" is the wrong Mode 2** — Z3 proofs are large/under-specified/un-checked; the genuine certificate path is the Lean tier. The reserved `certificate` field is format-agnostic, Lean-only. → §4.4, §7.

**§10 answer (folded):** "reproducible proof artifact" bifurcates along the Mode 1/Mode 2 line as two properties; Mode 1 (now the R-property) is a legitimate, field-validated notion for the decidable QF-LIA fragment (F\*-`.hints` parity), and independent checkability (the C-property) is reserved for the Lean tier. Rev 1 → Rev 2 incorporated all six; no open questions remain.
