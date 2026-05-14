# Professor Review: OBLIG-PBT-3 — PBT-to-Trust-Report Write-Back

**Reviewer:** Lead Consultant for Formal Language Design
**Document under review:** [`oblig-pbt-3-proposal.md`](oblig-pbt-3-proposal.md) (Rev 1, since revised to Rev 2 incorporating these findings)
**Date:** 2026-05-13

---

## Restatement

Rev 1 proposed that `runPropertyTests`'s `PBTPassed` verdicts write back into `.verified.json` as `DLTested n` entries on the postconditions of every `def-logic`/`letrec` named in head-position inside the property body, persisted by `mergeCS` and consumed unchanged by `TrustReport.buildTrustReport`. The proposal was freeze-compliant, accepted the diamond-meet's pinning of `tier_profile.tested`, and deferred property-body staleness to a future hash extension.

This review identifies seven gaps and two open questions. All seven gaps and both open questions are resolved in the Rev 2 proposal; the Resolution notes below indicate how.

---

## Context located

- `LLMLL.md §4.4.1` lines 325-351 — diamond lattice and the explicit incomparability of `DLContractChecked` vs `DLTested`; line 347 epistemic-status note correctly cordons statistical from logical evidence.
- `LLMLL.md §5.1` lines 481-489 — the outcome table the proposal repairs.
- `compiler/src/LLMLL/PBT.hs:163-184`, `:381-411` — `runPropertyTests`, `runQC`; `qcSamples = numTests` is the value `DLTested n` would carry, and that field's semantics under QuickCheck-discard are not what Rev 1 assumed.
- `compiler/src/LLMLL/Syntax.hs:344-371` — `evidenceMeet` is the cross-channel GLB; the within-channel join was reused in Rev 1 for a different operation.
- `compiler/src/LLMLL/TrustReport.hs:265-372` — `enrichEntry`, `effectiveLevel`, `aggregateTiers`. The `effectiveLevel = meet(pre, post)` reduction at line 304 produces the aggregate-pin.
- John Hughes, *How to Specify It! A Guide to Writing Properties of Pure Functions* (TFP 2020) §4 (coverage instrumentation), §11 (properties as light verification).
- Claessen & Hughes, *QuickCheck* (ICFP 2000) — discard semantics under `==>`.
- Pacheco, Lahiri, Ernst, *Feedback-directed random test generation* (ICSE 2007) — testing-as-contract-evidence framing.
- Vazou et al., *Refinement Types for Haskell* (POPL 2014) — LH has no QC-to-refinement-display channel; LLMLL's choice is a deliberate departure.
- Coq's `Print Assumptions` and Lean 4's `#print axioms` — per-axiom-class aggregates that never collapse via a lattice meet across separate obligation classes.

---

## Gaps and hazards

### 1. `DLTested n` carries a misleading sample count under QuickCheck-discard semantics

**Classify:** soundness (of evidence count).

QuickCheck's `Result.numTests` is the number of test evaluations, not the number of evaluations that genuinely exercised the property. A property of shape `(if pre then post else true)` (the Hughes/Claessen pattern instantiated at `examples/withdraw.llmll:14-16`) can pass 100 evaluations while exercising the postcondition on, say, 7. Rev 1's `pbtSamplesRun` flows through `qcSamples r` at `PBT.hs:407` and `DLTested n` records that as 100. A reader of `--trust-report` would read "tested (100 samples)" and assume that many witnesses of the postcondition exist.

Per Hughes 2020 §4, an honest sample count requires `aggregate`/`classify`-style coverage tracking that distinguishes "evaluations that satisfied the precondition" from "evaluations total."

**Bite:** high. Overstates trust on every property of vacuous-implication shape — the canonical PBT shape for contracted functions.

**Resolution in Rev 2:** §5 of the proposal explicitly defines `evaluatedSamples` and adds a spec disclosure to `LLMLL.md §4.4.1` and `§5.1` stating that `n` is "a lower bound on assertions of the postcondition." Coverage-instrumented counts deferred to OBLIG-PBT-4.

---

### 2. Body-name-broadcast over-credits multi-subject properties

**Classify:** soundness (of evidence attribution).

Rev 1's broadcast over head-position calls credits both `encrypt.csPost` and `decrypt.csPost` with `DLTested 100` from a single observation per sample in a round-trip property `(= x (decrypt (encrypt x)))`. The defense — that `DLTested` is already weak — conflates *evidence weakness* (the channel is statistical) with *evidence allocation* (which functions a single observation supports).

The Pacheco-Lahiri-Ernst framing (Randoop, ICSE 2007) — *contracts are violated by tests; tests do not independently witness each contract on the call chain* — is the standard treatment. A round-trip property cannot decompose into independent evidence for the two components; only the composite is witnessed.

**Bite:** medium-high. Silent at the call site; propagates through `enrichEntry`'s effective-level computation. Inflates H1-Assurance signal for benchmark cells.

**Resolution in Rev 2:** §3 of the proposal restricts the lift to **singleton head-position subjects**. Multi-subject properties produce an informational diagnostic from `llmll test` but no lift. OBLIG-PBT-4's `:subject`/`:subjects` metadata is the explicit-attribution route for multi-subject properties that should count.

---

### 3. Sidecar invariant change is not as invisible as Rev 1 claims

**Classify:** spec-drift / scope.

Rev 1 asserts no schema delta. The bytes are unchanged, but the **invariant** over `.verified.json` is changed: today the sidecar holds entries for functions defined in the corresponding source file; under the proposal, `solution.llmll.verified.json` may hold entries for `lib.f` (an imported function). Downstream tooling that relies on "sidecar entries are local to the source file" silently changes its semantics.

**Bite:** medium. The proposal's "no schema bump" framing understates the change.

**Resolution in Rev 2:** §8 of the proposal includes the explicit invariant statement to be added to `LLMLL.md §4.4.4`: "*The `.verified.json` sidecar for a source file `S` may carry entries keyed by qualified imported names…*"

---

### 4. The aggregate-pin is created by OBLIG-PBT-3, not merely exposed

**Classify:** verification-ergonomics; possibly soundness depending on how the aggregate is consumed.

Pre-OBLIG-PBT-3, the per-function meet was effectively a no-op because the verifier's SAFE write at `Main.hs:1186-1212` lifted only the postcondition to `DLVerified`, leaving `csPre = DLAsserted` — so `effectiveLevel` was already pinned to `DLAsserted` for any function with a precondition, and the `tpVerified` slot was already mostly empty for the same structural reason. That was a latent issue.

OBLIG-PBT-3 promotes it from latent to visible: downstream tooling reading `tier_profile` will see `tpAsserted` increment whenever a property covers a contracted function with a precondition, even though the per-entry post is `DLTested`. The roadmap row's promise that `tier_profile.tested` will reflect actually-passing checks is then not narrow — it is, on the canonical `withdraw`-shape function, false.

The Coq `Print Assumptions` precedent — emit per-class, do not meet — is the established move. Per-clause TierProfile (one vector for pre, one for post) is a small change to `TrustReport.hs:355-372` and a schema delta to the trust-report JSON, not a redesign of `aggregateTiers`.

**Bite:** high. Rev 1 as written would produce a v0.10.5 `tier_profile.tested` slot that increments rarely in practice on agent-emitted programs; postmortem-001 LT-B closure conditions depend on this aggregate moving.

**Resolution in Rev 2:** §9 of the proposal splits `tier_profile` into parallel `tier_profile_pre` and `tier_profile_post` vectors. Existing scalar `tier_profile` preserved for back-compat. `trust_report_version` bumps `1.0.0 → 1.1.0`. Not a freeze violation because the surface is downstream-tooling emit, not language source surface, per `TrustReport.hs:95-99`.

---

### 5. `min`-over-coverage is the wrong reduction within a single evidence channel

**Classify:** ergonomic / minor soundness.

Rev 1's side condition (5) takes `min` over multiple properties covering the same `f`. The justification cites `evidenceMeet (DLTested n1) (DLTested n2) = DLTested (min n1 n2)` at `Syntax.hs:351`. That clause was written for the **cross-clause** meet, not for **intra-clause accumulation** across distinct properties. Property-testing literature (Hughes 2020, Claessen-Hughes 2000) treats two independent properties on the same unit-under-test as additive evidence under independence assumptions — at minimum, `max` (the strongest single witness), more honestly `n1 + n2` with a caveat.

`min` is conservative to the point of being statistically inverted: it implies that running fewer covering properties produces stronger evidence than running more.

**Bite:** low-medium. Small in practice but a category error.

**Resolution in Rev 2:** §6 of the proposal uses `max` as the within-channel join, explicitly distinguishing it from `evidenceMeet` (cross-channel GLB). `sum` considered and rejected due to independence assumptions.

---

### 6. Property staleness is not deferrable

**Classify:** soundness (of cached evidence).

Rev 1 defers `propBody`-hash tracking to a hypothetical OBLIG-PBT-4. The verifier's analogous problem is already solved at `Module.hs` `ctVerifiedHash` because the sidecar entry's freshness can be re-checked against the body it claims to have proven. PBT does not have an analog: after the lift, the property is gone from the sidecar's purview, and editing the property body (or removing the `(check)` block entirely) does not invalidate the cached `DLTested n` on the previously-covered function.

**Bite:** medium-high. Once a property is deleted, the trust report continues to display `tested` evidence with no live source. The cache leaks evidence.

**Resolution in Rev 2:** §7 of the proposal requires every PBT-derived `DLTested` sidecar entry to carry SHA-256 hashes of all contributing property bodies. `buildTrustReport` validates on read; stale entries are downgraded to `DLAsserted` with a diagnostic.

---

### 7. The proposal does not consult Liquid Haskell on the philosophical point

**Classify:** design assertion vs derivation.

Rev 1 claims `DLTested` is a legitimate trust tier, citing §4.4.1's diamond. It does not engage the prior question: *why* admit a statistical channel at all, when the closest sibling system (Liquid Haskell) deliberately does not? OBLIG-PBT-3 is the first proposal where the design assertion becomes operative: the first time the channel actually fires from runtime evidence rather than from `(trust foo tested)` source annotations or sidecar round-trip.

**Bite:** low (rhetorical, not technical). The language-team should record why a statistical channel earns trust-report citizenship in the first place.

**Resolution in Rev 2:** §10 of the proposal adds an explicit design-divergence paragraph to `LLMLL.md §5.1`/§4.4.1, naming the departure from Liquid Haskell and citing Vazou et al. POPL 2014.

---

## Open questions

### Q-PROF-1. Justify rejection of `:subject` keyword on `(check ...)` blocks under feature-freeze

Rev 1 classes `:subject` as a new construct freeze-blocked. I read it as metadata on an existing construct, structurally analogous to `:source` per `LLMLL.md §4.6`, `:level` per `§4.4.3`, or `:decreases` per `§4.2`. If metadata is in-scope under freeze, the explicit-subject design is preferable on every axis — it eliminates Gap 2, makes Q1's cross-module write target an explicit user choice rather than a syntactic-inference outcome, and removes the design's only departure from the Liquid Haskell / Randoop tradition.

**Resolution in Rev 2:** §11 of the proposal explicitly accepts that `:subject` is metadata and admissible under freeze. The deferral to OBLIG-PBT-4 is reframed as a **scoping** choice rather than a freeze-compliance claim. The head-position-singleton fallback ships in v0.10.5; `:subject`/`:subjects` metadata ships in v0.10.6+ as OBLIG-PBT-4.

---

### Q-PROF-2. Specify how `DLTested n` is to be interpreted under implication-shape properties

Three answers are admissible: (a) record an effective count derived from QuickCheck `classify` / `cover` instrumentation; (b) drop the integer entirely (`DLTested {witnessing :: Bool}`); (c) keep `n` but document its honest semantics. Rev 1 does (c) implicitly without the disclosure.

**Resolution in Rev 2:** §5 of the proposal selects route (c) explicitly with a mandatory spec disclosure in `LLMLL.md §4.4.1` and `§5.1`. Coverage instrumentation (route a) is the natural OBLIG-PBT-4 scope alongside `:subject`. Route (b) is rejected because `DLTested { dlSamples :: Int }` is established surface and the constructor change would propagate breakage across `Syntax.hs:315`, `VerifiedCache.hs:40-41`, and downstream consumers.

---

## Overall assessment

Rev 1 was a freeze-respecting, schema-respecting proposal that worked within LLMLL's existing surface — its strength relative to a redesign-from-LH-or-Randoop alternative. Its weaknesses were attribution honesty (Gap 2), evidence-count honesty (Gap 1), and aggregation correctness (Gap 4) — all addressable within the same surface by tightening side conditions, splitting the trust-report aggregate at the emit layer, and adding spec disclosures.

Rev 2 ships the **narrower** of the two readings of OBLIG-PBT-3: singleton-subject, hashed provenance, per-clause aggregate, explicit semantics disclosure. The richer reading (`:subject` metadata, coverage-instrumented counts, multi-subject opt-in) is sequenced to OBLIG-PBT-4 with team-consensus permitted but not required.

The convergence between the language-team's settled Rev 2 and this review is significant: where the two surfaces (inward-facing LLMLL spec + code; outward-facing PL literature) agree on the same hazards via different reading paths, the design is well-founded. The two divergences this review opened — Q-PROF-1 (`:subject` as metadata) and Q-PROF-2 (sample-count semantics) — are scoping divergences resolved by sequencing, not soundness disagreements.

**Recommendation:** Approve Rev 2 for compiler-engineer hand-off. The seven gaps are closed within the proposal; OBLIG-PBT-4 row is the natural follow-on for the deferred items.
