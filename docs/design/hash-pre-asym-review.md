---
name: hash-pre-asym-review
title: "Professor review of HASH-PRE-ASYM Rev 0: the meet is not a dependency key"
status: "Standalone, not folded. Round 1 reviews Rev 0; round 2 reviews Rev 1; round 3 (2026-10-02) reviews Rev 2."
date: 2026-10-02
author: professor
consumers: [language-team, user]
reviews: "hash-pre-asym-proposal.md Rev 0"
---

# Professor review of HASH-PRE-ASYM Rev 0

## Restatement

Rev 0 makes a function's evidence hash cover its effective contract (S1). It keeps a manual whole-sidecar epoch for changes the hash cannot see (S2), and it exempts pure widenings from the epoch (S3). A pre augmentation is meant to reach the callers that owe the new obligation through the §4.4.3 transitive meet, not through their own hashes.

## Context located

- `docs/design/hash-pre-asym-proposal.md` Rev 0: the draft under review.
- `compiler/src/LLMLL/PBT.hs`, `canonicalDefEvidenceHash`: the preimage is one function's own `(form, body, pre, post, decreases)` and nothing about its callees.
- `compiler/src/LLMLL/TrustReport.hs`, `downgradeStaleVerifiedSidecar`: compares each record only with its own function's live source.
- `compiler/src/LLMLL/ProgramGraph.hs`, `validated`: an imported module's sidecar is validated the same way, per function.
- `compiler/src/LLMLL/FixpointEmit.hs`, the call-site translation: a callee `pre` that does not translate makes the whole call fall back.
- `compiler/src/LLMLL/ObligationAssembly.hs`: `consumed_guarantees` exists, but only in the obligation report and the checkout brief. No sidecar records the callee contracts a caller relied on.
- `LLMLL.md` §5.3, the "persisted record" note: freshness is "the source has not drifted".

## Gaps and hazards

### H1. The meet restores a caller's tier when the callee re-proves, not when the caller does. (soundness; blocks S1 as written)

S1's last clause says a caller "loses its tier through the transitive meet (§4.4.3) until the callee is re-proved". That is the failure. The meet passes on the callee's current tier. It does not record which callee contract the caller's proof used.

Take module `B` with callee `g`, module `A` with caller `f`, and module `C` that imports `A`. A new binary augments `g`'s pre. The user re-verifies `B`, so `g` holds `verified` again under its new hash. `A` is not re-verified. When `C` is verified, `A`'s sidecar is read: `f`'s hash matches `f`'s unchanged source, and the meet over `g` passes. `f` reads `verified`, and nothing ever discharged the new call-site obligation.

The same path opens without any checker change. If a callee's `post` is weakened in the source and the callee is re-proved, every caller that assumed the old post keeps `verified`. So the gap is older than this row. HASH-PRE-ASYM is one way into it.

Within one file there is no gap, because `llmll verify` re-proves every function in it. The gap is cross-module and on paths that read a sidecar without running the solver: `--trust-report`, the warm-path admission of a `def`, and an importer's meet. No witness has been built. The engineer should build the three-module case above before anyone decides on S1.

### H2. The preimage leaves out the dependencies a modular proof actually has. (soundness; the root of H1)

Under assume-guarantee, a caller's verdict depends on three things: its own body and effective contract, the effective contracts of its direct callees (each `pre` it must prove and each `post` it assumes), and the checker. The preimage covers only the first. The literature treats a cache key missing a dependency as an incorrect key, not an optimization.

- **Boogie and Dafny.** Leino and Wüstholz, *Fine-Grained Caching of Verification Results* (CAV 2015), give each implementation a checksum and a dependency checksum. The dependency checksum covers the declarations it uses, callee specifications included. A changed callee spec invalidates the caller's cached result directly.
- **Build systems.** Mokhov, Mitchell and Peyton Jones, *Build Systems à la Carte* (ICFP 2018), define a correct verifying-trace store as one that records every input a task read. Under that definition, LLMLL's hash is a verifying trace with an input missing.

Direct callees are enough. A transitive change matters to `f` only by changing a direct callee's effective contract, and that callee's hash then moves. It is the same induction a modular verifier relies on.

### H3. S3 is sound only under a side condition the draft leaves unstated. (soundness; complicates S3)

S3's monotonicity argument holds for a change that turns a clause from "does not translate" into "translates". It assumes every clause that translated before still translates to the same term. A release could reinterpret a term that already translated, for example by turning an uninterpreted symbol into a reflected definition. That release is not a widening, and S3 would wrongly exempt it.

v0.27.1 met the side condition, and the evidence was measured: 222 of 222 in-tree `.fq` files were byte-identical. S3 should name the condition and require that measurement as its evidence. A corpus sweep is a sample, not a proof. It still checks the condition, which is better than nothing checking it.

### H4. S2 is a manual rule version, and that is the known weak point of the pattern. (ergonomic; matters at scale)

S2 matches Shake's `versioned` rule annotation (Mitchell, *Shake Before Building*, ICFP 2012). Bazel instead puts the tool binary's digest in the action key, and Lean's Lake traces include the toolchain. Those two are automatic and coarse. A manual version is precise but depends on a person seeing that a change needs it, which is how v0.14.76 shipped with no hash move. The C1 to C6 table is the right mitigation. It should be the release checklist item, not just a design table.

### H5. A hash over the emitted VC would make S1, the dependency key and most of S2 one mechanism. (scope; a research option, not this release)

Why3 sessions (Bobot, Filliâtre, Marché and Paskevich, *Preserving User Proofs across Specification Changes*, VSTTE 2013) key a stored proof on the generated proof task, not on the source. A caller's body VC already contains its callees' translated contracts and the checker's translation. So a canonical hash of the per-function VC would cover augmentations (C1, C2), callee edits (H1), translation corrections (C4) and widenings (C3) with no manual epoch.

The cost is real. Binder and constraint ids come from counters shared across functions, so a VC hash needs per-function canonical renaming first. Reading a tier would also mean running the emitter, which is fast next to the solver but is not free on the trust-report path. Record it as the long-term design, not this row's fix.

## Recommendation

1. **Fold the direct callees' effective contracts into the preimage.** This is a dependency checksum in the Boogie sense. The caller's hash covers its own effective contract plus each direct callee's `(name, effective pre, effective post)`, in a canonical order. It is the smallest change that closes H1 and H2, and it makes C2 hold through the caller's own hash. The meet stays as a display rule and stops being a freshness mechanism. Cost: a callee contract edit moves every direct caller's hash, which is the intended behavior. The release should count the moved population.
2. **Fold the augmented pre into the preimage, as Rev 0 proposes.** With recommendation 1 it is needed for the callee's own record. Without recommendation 1 it is not enough.
3. **Restate S3 with its side condition.** Previously translated clauses must emit the same terms, shown by a byte-identical `.fq` sweep over the corpus.
4. **Keep S2.** Make the C1 to C6 table a release checklist that each ceremony cites.
5. **Record H5 (a VC-keyed hash) in `docs/design/theory-questions.md` or as a research-track note.** Do not build it now.

This changes the row's scope from "fold the augmented pre" to "add a dependency key". The row's own defect, C2, is the case the narrow fix leaves open in the cross-module setting.

## Open questions for the language-team

1. Confirm that a direct-callee digest is enough for every channel the verifier reads across a call. The call-site translation in `FixpointEmit.hs` reads the callee's `ContractEnv` entry, including its return type (the third slot `calleeRetSort` uses) and its constructor tags, not only its pre and post. State which fields of that entry the digest must fold, and justify any that are left out.

---

# Round 2: review of Rev 1 (2026-10-02)

## Restatement

Rev 1 keys a stored verdict on the function's own parts, its signature's type declarations, and a digest of each direct callee's interface (§3: name, parameter types, effective pre and post, effective return type, type declarations). It adds S4: a non-SAFE run leaves no positive record for a function it did not prove. The round-1 recommendations 1 to 5 are all taken.

## Context located

- `compiler/src/LLMLL/TrustReport.hs`, `liveHashes` inside `downgradeStaleVerifiedSidecar`: the read side receives `[Statement]` for one module and hashes the declared `mRet`.
- `compiler/src/LLMLL/ProgramGraph.hs`, `validated`: an import's records are checked against `meStatements m` alone.
- `compiler/app/Main.hs`, the sidecar write: hashes the declared `mRet`; `retTypes` and the module cache exist in that scope but do not reach the hash.
- `compiler/src/LLMLL/FixpointEmit.hs`, the descent-site loop in `emitFnConstraints`: for a callee in `sccSet`, the obligation reads the callee's measure `gMeasEs` from `measureMap`.
- `compiler/src/LLMLL/FixpointEmit.hs`, `effRet` and `synthRet`: the third `ContractEnv` slot comes from the inferred `tau_ret` (`retTypes`) or from `bodyIsBoolean` over the callee's body.

## Gaps and hazards

### R1. The read sites cannot compute the key Rev 1 defines. (soundness and DX; blocks settlement as written)

S1 names fields only the emitter's environment holds: imported callee interfaces, aliases merged across modules, and the effective return type. The read sites hold less. `downgradeStaleVerifiedSidecar` sees one module's statements. `ProgramGraph.validated` sees `meStatements m`. Neither has `retTypes`. If the write side computes the key with more information than a read side, the two keys differ on every function that calls an imported or unannotated callee. Every such record is then downgraded on every read.

That failure is safe, but it makes the cache useless. The opposite failure is worse: a read site that quietly leaves out a callee it cannot resolve, together with a write side that does the same, would recreate this row's defect. The original defect was itself a write/read asymmetry (raw pre against augmented post).

GHC's recompilation avoidance is the closest precedent. A module's interface records the fingerprint of each imported entity it used (`mi_usages`). Its documented failures are dependencies left out of that record, which is Rev 1's §9 risk 1 in another compiler.

### R2. A descent obligation reads a callee's measure, and §3 does not fold it. (soundness; complicates S1)

For a call to a callee in the same SCC, the descent obligation compares the caller's measure with the callee's (`gMeasEs`). A record's descent flag (the `descentDischargedSet` membership written into `EvidenceRecord`) therefore rests on its SCC peers' measures. Suppose a peer's `decreases` clause is edited and the module is not re-verified. The caller's key does not move, and an importer reads a stale "termination discharged" flag. SCCs are confined to one module, so the exposure is that module's importers. That is the path the witness measured.

### R3. S1's last sentence is true only in a narrower form. (spec precision; complicates S1)

"A caller's proof never reads it [the callee's body]" is false as written. An unannotated callee's effective return type comes from the type checker's inferred `tau_ret` (`effRet`), or from `bodyIsBoolean` over its body (`synthRet`). Folding the effective return type into the digest is correct, so the body reaches the key through that field. The sentence should say so. Otherwise an engineer may read "never" as permission to hash the declared annotation, which is what both sides do today.

### R4. S4 is adequate. Its attribution source exists. (no change)

Each constraint carries a `ConstraintOrigin` naming its function, so a SAFE/UNSAFE result maps to functions. A function in the same file that assumed the refuted function's contract is still correctly proved relative to that contract, under modular assume-guarantee. On read, the refuted function holds no positive tier, so the meet lowers the dependent function's displayed tier. This is the meet's correct role: display, not freshness.

## Recommendation

Settle Rev 1 after three amendments:

1. **One key function, used at every site, plus a round-trip invariant.** Define a single function from (the cache-aware environment, a statement) to the key. Use it on the write side and on every read side: the entry-file read, `ProgramGraph.validated`, and the per-module reads in `TrustReport.hs`. Pass each read site the module cache and the inferred return types. Add one invariant test: for every function in the corpus, including imported ones, the key written by a fresh `verify` equals the key computed on the next read. A fresh sidecar must never be downgraded. That test catches R1 in both directions and costs one sweep.
2. **Fold the measures of callees in the same SCC** into the digest (R2). Name it as a seventh field in §3.
3. **Restate S1's last sentence** (R3): "A callee's body enters its callers' keys only through its effective return type, when it declares none."

No redesign is needed. Round-1 recommendation 5 (a VC-keyed hash) remains the end state, for the reason R1 shows: a field list must be kept in step with the emitter by hand.

---

# Round 3: review of Rev 2 (2026-10-02)

## Restatement

Rev 2 adds §3.1 (one key function at four sites, and a round-trip invariant), folds every direct callee's measure, and restates S1's body sentence. It declines to put SCC membership in the key, on the ground that membership is a whole-module property.

## Context located

- `compiler/src/LLMLL/TrustReport.hs`, `markDescentDischarged` and its comment: `partial_fns` is computed live from the call graph, then the persisted `termination_verified` set (`sidecarDischargedSet`) is subtracted on the solver-less path.
- `compiler/src/LLMLL/RespFact.hs`, module header: `moduleSites` reads which builtin each control tag is bound to from the issuing defs anywhere in the entry module. The emitter seeds the resulting refinement into a requesting def's VC (`respRefs` in `emitFnConstraints`).
- `compiler/src/LLMLL/FixpointEmit.hs`, the parameters of `emitFnConstraints`: the inputs that vary per program are `aliases`, `cenv`, `sccSet`, `measureMap` and `respRefs`.

## Gaps and hazards

### T1. The termination flag depends on SCC membership, and SCC membership is read from the record. (soundness; complicates Rev 2)

Rev 2 keeps SCC membership out of the key, and the reason is sound for the post: a post proof never reads it. The termination claim does read it. A function's descent obligations exist only at calls into its own SCC. On the solver-less path, the stored "termination discharged" flag removes the function from `partial_fns`.

Take module `a` with `f` and `g`, where `f` calls `g`. Then `g`'s body is edited to call `f`, and `a` is not re-verified. The live graph puts `f` and `g` in one SCC. `g`'s key moves, so its record is downgraded. `f`'s key does not move: `g`'s interface, measure included, is unchanged. So `f`'s stored flag still takes it out of `partial_fns`. Yet no obligation at the call `f -> g` was ever emitted.

The language team's objection does not apply to the fix. The read path already computes the live SCC for `partial_fns`. So the SCC can key the termination flag alone, compared at read time, and it does not enter the post's key.

### T2. A RESP-FACT refinement depends on other defs' bodies in the same module. (soundness; complicates Rev 2)

A requesting def's VC assumes a refinement on its `Response` arm binder. That refinement is fixed by the builtin each control tag is bound to, and the binding is read from issuing defs that need not be callees. An edit to an issuing def changes the fact. The requesting def's key does not move. Exposure needs a requesting def, an edit to its module, and a solver-less read before re-verification.

### T3. The field list can be made to follow the emitter by construction. (soundness at scale; addresses Rev 2 risk 1)

Rev 2's main residual risk is a new emitter input not added to §3. Both T1 and T2 are instances of it, found by auditing `emitFnConstraints`'s parameter list. That audit should be structural, not periodic. Build the key from the same per-function input record the emitter consumes, field by field. Adding an input to the emitter then forces a decision in the key function, or the code does not compile. This is the build-system rule (a task's key is its declared inputs) applied to one function's verification task. It is the cheapest step towards the VC-keyed end state.

### T4. One claim in the conversation is wrong: the invariant test is not red on v0.27.1. (precision; no spec impact)

Today the write side and the read sides hash the same fields: the raw pre, the declared return type, and no callees. So the round-trip invariant holds on v0.27.1. It guards the new code and does not reproduce the defect. The red cells are the two witness variants and the per-field cells.

## Recommendation

Settle after two further amendments and one change of method:

1. **Key each claim on what that claim read.** The post and pre records keep Rev 2's key. The termination flag (`termination_verified`) also carries the sorted names of its SCC, and each member's measure. On read, the flag counts only if the stored SCC equals the live SCC. The read path already has the live SCC.
2. **Fold the seeded RESP-FACT refinement** (the function's `rpRefEnvs` entry) into the key of a requesting def. Every def that is not a requesting def has none, so its key does not change.
3. **Build the key from the emitter's per-function inputs** (T3). State in §3 that each per-program input of `emitFnConstraints` is either in the key or ruled out in writing. `aliases`, `cenv` and `measureMap` are covered. `respRefs` is covered by amendment 2, and `sccSet` by amendment 1, for the claim that reads it.

With these, every per-program input to a function's VC is covered by a key or by the epoch. The proposal can then settle.
