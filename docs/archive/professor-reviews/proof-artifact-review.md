# Professor Review — PROOF-ARTIFACT (proof-artifact-proposal.md Rev 1)

> **Reviewer:** professor (outside-PL consultant)
> **Reviewing:** [`proof-artifact-proposal.md`](proof-artifact-proposal.md) Rev 1 (2026-06-20)
> **Date:** 2026-06-20
> **Recommendation:** **Revise and resubmit.** The proposal is sound and in-scope, but its central §10 framing conflates two distinct properties with two distinct trusted bases, its §1 motivation does not match what the recommended mode delivers, and it omits the closest external precedent (F* hints). Four concrete revisions below; none requires abandoning the design.

---

## Restatement

The proposal unifies LLMLL's scattered verification outputs (`.fq`, trust report, obligation report, `.verified.json` sidecar) into one serializable artifact per verify run, and adds a replay command that re-derives the recorded verdict and fails closed on staleness. It recommends "Mode 1" — store the fixed VC plus the solver version and re-run liquid-fixpoint/Z3 to reproduce — over "Mode 2" — serialize Z3's proof object for independent checking, which it defers. The §10 question asks whether Mode 1 is an adequate notion of "reproducible proof artifact" for a decidable QF-LIA fragment, or whether a legitimate certificate demands Mode 2.

## Context located

1. [`proof-artifact-proposal.md`](proof-artifact-proposal.md) §1, §4.1–4.4, §6, §7, §9, §10 — the artifact fields, the two replay modes, the faithfulness framing, the deferral of Mode 2.
2. `LLMLL.md §3.4.3:307-322` — "Path B declined": codegen faithfulness is a *commitment*, not a mechanized theorem. Bears directly on the `erased_core` field's trusted base.
3. `LLMLL.md §5.3.3:961,982` — QF-LIA SAFE is a decidable side-condition; liquid-fixpoint/Z3 sound-and-complete on the fragment. Grounds Mode 1's adequacy *and* its limits.
4. `README.md:160` — `ProofCache.hs` SHA-256 sidecar; the §7 hook for the genuine (Lean-tier) Mode 2.
5. External, not in the project's reading path: Necula (PCC, POPL 1997); Milner/Gordon/Wadsworth (LCF, 1979) and the de Bruijn criterion; Z3 proof production (de Moura–Bjørner); Alethe + Carcara (Schurr–Fleury–Barbosa, PxTP 2021); SMTCoq (Ekici et al., CAV 2017); DRAT/LRAT (Wetzler–Heule–Hunt, SAT 2014); Dedukti/λΠ-modulo (Boespflug–Dowek); **F* `.hints` / unsat-core recording** (Swamy et al., POPL 2016); Liquid Haskell's Z3-trusting model (Vazou et al., POPL 2014).

## Gaps and hazards

1. **Mode 1 and Mode 2 are not one axis — they answer different questions with different trusted bases.** *Classify: scope / framing (load-bearing).* The proposal presents Mode 2 as "stronger but heavier" (§4.4), i.e. a more-expensive point on a single reproducibility axis. The literature is unambiguous that these are two *properties*: (a) **replay reproducibility** — re-run, get the same verdict; trusted base = the entire solver build; this is F*'s `.hints` mechanism (Swamy et al., POPL 2016) and Dafny's verification caching (Leino, LPAR 2010). (b) **proof-carrying / independent checkability** — a third party validates *without trusting or re-running the prover*; trusted base = a small checker; this is PCC (Necula, POPL 1997), the de Bruijn criterion (Barendregt–Geuvers), SMTCoq (Ekici et al., CAV 2017), Alethe/Carcara, and the DRAT/LRAT lineage that the SAT community adopted *precisely because* "trust the solver" proved inadequate after repeated solver bugs. Bite: not a blocker, but the framing misleads every downstream consumer about what a "reproduced" verdict means.

2. **The §1 motivation overclaims what Mode 1 delivers.** *Classify: spec-drift (internal, motivation vs. mechanism).* §1 sells "reproducible from an artifact, not merely from a compiler run." Mode 1 *is* a compiler run — it re-invokes liquid-fixpoint/Z3 (§4.4). For a deterministic solver on a fixed VC, "re-run yields the same answer" is close to tautological and tells a consumer nothing they could not get by re-running `llmll verify`. What Mode 1 actually delivers is **hermetic, version-pinned re-verification** — a regression/audit guarantee that the *input* (VC, solver version, codegen semantics) is captured exactly — which is genuinely valuable but is a different claim. Bite: complicates the proposal's stated purpose; fixed by restating the motivation.

3. **`solver_version` is insufficient for determinism; `unknown`/timeout is not handled.** *Classify: soundness-adjacent / decidability.* §4.3 fails closed on version/hash mismatch, but Z3 determinism is not guaranteed by version alone — it depends on platform/arch, option set, resource and timeout limits, and `smt.random_seed`. Critically, a resource- or timeout-induced **`unknown` is neither SAFE nor UNSAFE**; under QF-LIA it is unlikely, but the artifact spec must treat `unknown` as a distinct fail-closed outcome and must pin the resource limits and option set, not merely the version. Bite: a real correctness hole at replay time, cheaply closed.

4. **`erased_core` gives the *appearance* of end-to-end reproducibility but the codegen link is uncertified.** *Classify: soundness / honesty.* Storing the erased core the VC was taken over does not close the source→generated-Haskell gap, which `LLMLL.md §3.4.3:314,322` explicitly keeps as a Path-A commitment ("Path B declined"). An artifact named "proof artifact" that records `erased_core` invites the reader to believe the trusted base is smaller than it is. Bite: honesty/over-claim; fixed by a one-line field annotation.

5. **Faithfulness (§4.1/§6) is stated as prose, not enforced as a representable invariant.** *Classify: soundness / ergonomic.* "Conservative summary" is the right idea — in Cousot's terms, soundness of the serialized abstraction — but §9 Risk 2 ("required fields") is the actual teeth and it is demoted to a risk. The faithfulness property *is* the well-formedness condition "no positive tier without its qualifying fields (`fallback_reason`/`refuted`/`caller_obligations`)," and it should be enforced the way LCF enforces "theorems come only from the kernel" (Milner 1979): a smart constructor / abstract type that *cannot* mint a positive-tier record without the qualifiers. Bite: elevates a risk into a guarantee at near-zero cost.

6. **Mode 2 "serialize Z3's proof object" names the wrong Mode 2.** *Classify: scope / feasibility.* Z3's proof objects are notoriously large, under-specified, and consumed by almost no independent checker — this is exactly why the field moved to **Alethe** (Schurr–Fleury–Barbosa) checked by Carcara, to cvc5's proofs, and to SMTCoq, rather than to Z3 proofs. A Mode 2 built on Z3 proof serialization is a research liability, not merely "heavier." Bite: would mis-route the eventual Mode 2 investment; the reserved `certificate` field must be format-agnostic.

## Recommendation

Adopt the design, but make four revisions and answer §10 as follows.

**§10 answer.** "Reproducible proof artifact" is a well-established notion, and it *bifurcates exactly along the proposal's Mode 1/Mode 2 line* — but as two properties, not two price points. Mode 1 delivers **replay reproducibility** (trusted base = the solver); it is adequate *for what it is*, and it has a mature, shipped precedent the proposal should cite: **F*'s `.hints`** (Swamy et al., POPL 2016) does precisely this — record per-query data and a hash so replay is stable and fast, while still re-running Z3. Mode 1 is therefore a legitimate and field-validated notion of reproducibility for a decidable QF-LIA fragment. It does **not** deliver independent checkability; that is Mode 2 (PCC/de Bruijn/SMTCoq/Alethe/LRAT), whose trusted base is a small checker, not the solver.

1. **Reframe Mode 1/Mode 2 as two properties with two trusted bases** (replay reproducibility vs. independent checkability), and **restate the §1 motivation** to "a hermetic, version-pinned, auditable re-verification record" — the claim Mode 1 actually supports — dropping "not a compiler run."

2. **Ship Mode 1.5: store the unsat core, not the full `.fq` alone.** This is the smallest principled improvement and it dominates plain Mode 1 on every axis: it matches F*'s hint granularity for replay *stability* (the same core stabilizes the solver's search), it yields a *minimized, auditable* record of exactly which hypotheses — callee postconditions, refinement predicates, path conditions — the proof consumed (far more informative to the agent/human than the raw VC), and it is the natural stepping-stone toward a real certificate. Z3 exposes unsat cores directly; liquid-fixpoint already names its constraints.

3. **Pin determinism inputs and make `unknown` fail closed.** Record option set, resource/timeout limits, platform, and seed alongside `solver_version`; treat replay `unknown`/timeout as a distinct, fail-closed outcome separate from UNSAFE.

4. **Promote faithfulness to a schema-level well-formedness invariant** enforced by a smart constructor (LCF discipline): a positive-tier artifact record is unconstructible without its conjoined qualifying fields. Annotate `erased_core` as "the core the VC was taken over; codegen faithfulness remains a `§3.4.3` commitment, not certified here."

**On Mode 2, when it comes:** split the trusted base by tier. The SMT tier should stay Mode 1.5 (re-run with unsat core; trusted solver) — do *not* pursue Z3 proof-object serialization. The genuine Mode 2 is the **Lean tier** already anticipated in §7: a Lean proof term *is* the certificate and Lean's kernel *is* the small checker, satisfying the de Bruijn criterion by construction. Tie the reserved, format-agnostic `certificate` field to the Lean-replayability item, not to Z3.

**On over/under-claiming vs. the design-reference set.** The proposal *under-claims* by omitting F* hints (its closest precedent) and *correctly does not over-claim novelty*: an artifact that re-runs a trusted solver is catching up to F*/Dafny, not surpassing Liquid Haskell (which trusts Z3 outright, no artifact). Idris sits in a different quadrant (kernel-checked proof terms, no SMT) and is not a competitor on this axis. The honest external positioning is: "Mode 1.5 brings LLMLL to F*-hint parity for the SMT tier; genuine proof-carrying assurance is the Lean tier."

## Open questions for the language-team

1. Justify storing the full `.fq` VC text over the unsat core, or adopt Mode 1.5. If the `.fq` is retained, state what auditing question it answers that the named unsat core does not — given that the core is strictly more informative about *which* hypotheses the proof used.
2. Confirm the artifact's replay contract treats `unknown`/timeout as fail-closed and distinct from UNSAFE, and specify which determinism inputs beyond `solver_version` (options, resource limits, platform, seed) the artifact pins — `LLMLL.md §5.3.3` guarantees decidability of the *fragment*, not bit-reproducibility of a particular Z3 build.
