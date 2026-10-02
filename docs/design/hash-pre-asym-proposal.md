---
name: hash-pre-asym-proposal
title: "HASH-PRE-ASYM: a stored verdict is keyed on everything its proof read"
status: "Rev 3, SETTLED and SHIPPED v0.27.2 (cd55c22). Folds hash-pre-asym-review.md rounds 1 to 3 (professor) and hash-pre-asym-witness.md (measured on v0.27.1). A stored claim is keyed on every per-program input its proof read, built from the emitter's own per-function inputs; one key function with a round-trip invariant; a failed-run rule. No compiler work in this document."
date: 2026-10-02
author: language-team
consumers: [user, compiler-engineer, documentation-lead]
reviews: "folded below; archived at docs/archive/professor-reviews/hash-pre-asym-review.md"
related: "hash-pre-asym-witness.md; fact-ag-proposal (Stage 1 augmented the pre, Stage 3 the post); minmax-frag-1-proposal (v0.27.1, the widening case)"
---

# HASH-PRE-ASYM: a stored verdict is keyed on everything its proof read

## 0. Changes from Rev 0

| Rev 0 | Rev 1 | Why |
|---|---|---|
| S1: the hash covers the function's own effective contract; callers are reached through the §4.4.3 meet "until the callee is re-proved" | S1: the hash covers the function's own effective contract, its signature's type declarations, and a digest of each direct callee's interface. The meet is a display rule only | Review H1, H2; witness F1: the meet passes again once the callee re-proves, and `--strict-verified-core` passed on an importer in both measured variants |
| No rule for a failed run | S4: a run that does not prove a function leaves no positive record for it | Witness F2: a failed `verify` kept `f: verified` byte-for-byte |
| S3 with no condition | S3 holds only if every clause that translated before emits the same term, shown by a byte-identical `.fq` sweep | Review H3 |
| C1 to C6 as a design table | The same table, as the release checklist each ceremony cites | Review H4 |
| (none) | A VC-keyed hash is recorded as deferred design, §7 | Review H5 |

Rev 0 §7 corrected two claims of the conversational review. Rev 1 withdraws a third: S1's meet clause.

**Changes from Rev 1** (professor round 2):

| Rev 1 | Rev 2 | Why |
|---|---|---|
| S1 defines the key; nothing says where it is computed | §3.1: one key function, called on the write side and at every read site, each given the module cache and the inferred return types; a round-trip invariant test | Round 2 R1: the read sites hold one module's statements and the declared `mRet`; they cannot compute Rev 1's key |
| §3 lists six callee fields | A seventh: the callee's measure (`decreases`), for every direct callee | Round 2 R2: a descent obligation reads an SCC peer's measure |
| S1: "a caller's proof never reads it" | "A callee's body enters its callers' keys only through its effective return type, when it declares none" | Round 2 R3: `effRet` and `synthRet` derive the third slot from the body |

**One choice differs from the professor's wording.** R2 asks for the measures of callees in the same SCC. Rev 2 folds the measure of every direct callee. SCC membership is a property of the whole module's call graph, and putting it in the key would make the key function read every other function's body. That is the dependency S1 is built to avoid. Folding all direct callees' measures costs a spurious re-proof only when a non-recursive callee's `decreases` clause is edited, which is rare.

**Changes from Rev 2** (professor round 3):

| Rev 2 | Rev 3 | Why |
|---|---|---|
| SCC membership is in no key | S1: a termination claim also carries its SCC (sorted member names and their measures), and counts only while the live SCC equals the stored one | Round 3 T1: `markDescentDischarged` subtracts the stored discharged set from a live `partial_fns` on the solver-less path |
| A RESP-FACT refinement is in no key | S1: a fact the compiler seeds into the function's VC from elsewhere in the module joins its key | Round 3 T2: `moduleSites` reads issuing defs that are not callees |
| §3 is a field list kept by hand | §3.2: the key is built from the emitter's per-function inputs; each per-program input of `emitFnConstraints` is either keyed or ruled out in writing | Round 3 T3 |

**One qualification on T3.** The emitter's inputs are whole-program values: `cenv` holds every function's contract. Keying on them whole would make every key depend on every function, and one contract edit would re-prove the corpus. The key is built from each input's **per-function projection**: the part of `cenv` this function's body reaches, the part of `respRefs` seeded for it, and so on. §3.2 names the projection for each input. The projection is what the type of the key function's argument enforces.

## 1. Problem

A `.verified.json` record keeps a `verified` tier across runs. It is read without running the solver by `--trust-report`, by the admission check for a `def`, and by every importer through the module cache (`ProgramGraph.validated`). Two mechanisms decide when a record must be thrown away.

1. **The per-function evidence hash.** `canonicalDefEvidenceHash` (`compiler/src/LLMLL/PBT.hs`) covers one function's own `(form, body, pre, post, decreases)`. Both callers pass the raw pre and the augmented post.
2. **The checker epoch.** `sidecarNeedsRevalidation` (`compiler/src/LLMLL/VerifiedCache.hs`) discards a whole sidecar whose `checker_soundness_version` differs from the binary's.

A caller's proof also reads its callees' interfaces: under assume-guarantee it proves each callee `pre` and assumes each callee `post`. The hash covers none of that. The witness (`hash-pre-asym-witness.md`) measured the consequence on v0.27.1. `f` in module `a` calls `g` in module `b`, and `c` imports `a`. After `g`'s pre was strengthened, or its post weakened, and only `b` was re-verified, `llmll verify c.llmll --strict-verified-core` passed with exit 0. `f` was refuted the moment `a` was checked. A failed `verify a.llmll` then left `a`'s sidecar unchanged, still claiming `f: verified`.

The original row (FACT-AG-LEN Stage 1 moved no hash when it augmented a pre) is one entry into this gap. The gap itself is a missing dependency, and it is live: a false pass under `--strict-verified-core`, measured, with no checker change needed.

## 2. Proposal: four sentences for `LLMLL.md` §5.3

Promote these, in the spec's register, next to the existing "persisted record" note. They replace its sentence "the `verified_hash` attests that the source has not drifted".

> **S1. A record is keyed on everything its proof read.** A record's `verified_hash` covers the function's body; its effective `pre`, `post` and measures (after the compiler adds the facts it derives from the signature); the declarations of the types in its signature; and, for each contracted function its body calls or passes as a value, that callee's interface: its resolved name, its parameter types, its effective `pre` and `post`, its effective return type, its measures, and the declarations of the types those name. It also covers any fact the compiler seeds into the function's verification from elsewhere in its module (a control-tag fact on a `Response` value, §9.7). A change to any of these changes the hash, and the record is downgraded on read and re-proved. A callee's body enters its callers' keys only through its effective return type, when it declares none. A termination claim is keyed, in addition, on its recursion group: the sorted names of the functions in it and each one's measures. It counts only while the live recursion group equals the stored one.

> **S2. The checker epoch covers what no key can see.** Every sidecar carries `checker_soundness_version`. A binary discards, whole, any sidecar whose stamp is absent or differs from its own. A release must increase the stamp when a recorded verdict may no longer hold and no key moves: a translation corrected because it was unsound, a fact or axiom withdrawn, or a builtin's meaning changed.

> **S3. A widening needs no new epoch.** A release whose only effect is that clauses which did not translate now translate, while every clause that translated before emits the same term, invalidates no recorded verdict: a function whose clause fell back never held `verified`, and a call whose callee `pre` did not translate fell back whole. The release shows the condition with a byte-identical `.fq` sweep over the corpus. It may still increase the stamp, and says why.

> **S4. A run that does not prove a function leaves no positive record for it.** When `verify` ends in anything but SAFE, the sidecar is rewritten so that no function the run refuted keeps `verified`; when the run cannot attribute the failure to functions (a solver crash, a timeout, an unknown result), no function in the module keeps a positive tier. A refuted verdict is still not persisted as such.

## 3. What the callee interface digest folds, and why each field

This answers the professor's open question. Each field is something the caller's body VC reads from the callee's `ContractEnv` entry or through it (`compiler/src/LLMLL/FixpointEmit.hs`, the call-site translation in `bodyToPredM` and the payload-refinement loop in `emitFnConstraints`).

| Field | Read by | Left out, it would miss |
|---|---|---|
| Resolved, module-qualified name | the `ContractEnv` lookup | an `open` re-pointed at a different module with a same-named function |
| Parameter types | the `pre` substitution; `payloadArms` and `payloadRefinement` over each argument | a payload refinement added to a parameter type |
| Effective `pre` | the call-site obligation (PROVE) | witness variant 1 |
| Effective `post` | the assumed result fact (ASSUME) | witness variant 2 |
| Effective return type (the third slot, after `effRet` and `synthRet`; inferred from the body when none is declared) | `calleeRetSort`, `calleeSorts` | a return type that changes the result binder's sort |
| Measures (`decreases`) | the descent obligation at a call to a callee in the same SCC (`gMeasEs` from `measureMap`) | a peer's measure edit under a stored "termination discharged" flag |
| Declarations of the types above, resolved through aliases (constructor names in declaration order, payloads, refinement aliases) | `buildCtorTagMap`, `buildCtorSums`, the result-domain bound over an enum returned through a call | a constructor added to a callee's return type, which widens what the call may return |

**Contracts, not hashes.** The digest folds the callee's interface text, not the callee's own hash. A callee's hash includes its body, which callers must not depend on (S1, last sentence). Folding interfaces also means a recursive SCC creates no cycle, because no hash refers to another hash.

**Direct callees suffice.** A change further down reaches `f` only by changing a direct callee's interface, which moves `f`'s key. A change that leaves every direct interface the same leaves `f`'s proof valid. This is the same modularity the verifier already relies on.

**Measures of every direct callee, not only SCC peers.** Only a callee in the same SCC has its measure read. Deciding SCC membership needs the module's whole call graph, so the key would then depend on other functions' bodies. Folding every direct callee's measure keeps the key a function of interfaces alone.

**The function's own signature types join its own key.** The same table applies to the function itself: a constructor added to its own parameter's sum type changes the scrutinee tags its body VC reads (`scrutTagMap`).

### 3.1 One key function, and the invariant that holds it in place

The key is defined once, as a function from the cache-aware interface environment (the merged alias map, the cache-aware `ContractEnv` with its third slot from the inferred return types, and the measure map) and one statement, to the key. Every site that writes or checks a key calls it:

- the write side, the sidecar write in `compiler/app/Main.hs`;
- the entry-file read, `downgradeStaleVerifiedSidecar` in `compiler/src/LLMLL/TrustReport.hs` (whose other callers in `Main.hs` inherit the change);
- the import read, `validated` in `compiler/src/LLMLL/ProgramGraph.hs`;
- the per-module reads in `TrustReport.hs` that validate imported sidecars.

Each read site therefore receives the module cache and the inferred return types, which it does not today. This is the cost round 2 R1 named, and it is the larger part of the change.

**The invariant.** For every function in the corpus, imported ones included, the key a fresh `verify` writes equals the key the next read computes. A fresh sidecar is never downgraded. A test over the corpus checks it. It fails in both directions: a read site with less information than the write side downgrades fresh records, and the test sees that; a read site and write side that leave out the same field agree with each other, so the per-field cells in §8 item 4 cover that direction.

### 3.2 The key is built from the emitter's per-function inputs

Every per-program input of `emitFnConstraints` is listed here, with the projection the key takes or the reason it takes none. A new input added to the emitter must be added to this table, and the key function's argument type makes that a compile error rather than a review item.

| Emitter input | Projection in the key | Claim it keys |
|---|---|---|
| the function's own statement | body, effective contract, measures, signature | all |
| `aliases` (merged alias map) | declarations of the types in the function's signature and in each direct callee's interface | all |
| `cenv` | each direct callee's interface (§3 table) | all |
| `measureMap` | the function's own measures and each direct callee's | all |
| `respRefs` | the refinement seeded for this function's `Response` binders, if any | all |
| `sccSet` | the sorted members of the function's recursion group, with each member's measures | the termination claim only |
| `EmitOptions` | none: `emitBodyVCs` decides whether a body VC exists, and a record without one is never `verified` (§5.3 note); `emitBodyVCTargets` is the patch path, which re-proves one function against unchanged contracts | none |
| the binary (builtin signatures, axioms, translation) | none: S2's epoch | none |

## 4. Cases (the release checklist)

Each ceremony cites the row its release matches.

| # | Change | Mechanism | Precedent |
|---|---|---|---|
| C1 | The compiler augments a **post** | S1: the function's key moves, and so does every direct caller's | FACT-AG-LEN Stage 3, v0.14.78 |
| C2 | The compiler augments a **pre** | S1: same; the callers' keys move, so they re-prove the new obligation | FACT-AG-LEN Stage 1, v0.14.76 (no key moved: this row) |
| C3 | Translation **widens**, previously translated clauses unchanged | S3: nothing; byte-identical `.fq` sweep is the evidence | v0.27.1 |
| C4 | Translation **narrows** because the old one was unsound | S2: epoch increases | SAFE-ARG |
| C5 | Translation narrows for another reason | Neither: the old proof stands | none in tree |
| C6 | A fact or axiom family is added | S3 allows keeping the stamp; v0.17.0 spent it anyway and said why | RESP-FACT-1, v0.17.0 |
| C7 | A user edits a callee's contract, or a type in its interface | S1: the callers' keys move | the witness, both variants |
| C8 | A user edits a callee's body only | Nothing for callers; the callee's own key moves | modular verification |
| C9 | A run fails | S4 | the witness, F2 |
| C10 | A body edit in the same module joins a function to a recursion group | S1, termination clause: the stored group differs from the live one, so the termination claim does not count | round 3, T1 |
| C11 | An issuing def is edited, so a control-tag fact changes | S1: the requesting def's key moves | round 3, T2 |

## 5. Edge cases

1. **Positive witness for S1 (variant 1).** `b`: `(def g [x: int] -> int (pre (>= x 5)) (post (= result x)) x)`, changed from `(>= x 0)`; `a`: `(def f [] -> int (post (= result 1)) (g 1))`; `c`: `(def h [] -> int (post (= result 1)) (f))`. Only `b` is re-verified. Expected: `f`'s key moves because `g`'s effective pre is in it, `f` is downgraded on read in `c`, and `llmll verify c.llmll --strict-verified-core` fails naming `f`. Channel: trust, `downgradeStaleVerifiedSidecar`.
2. **Positive witness for S4.** The same files, then `llmll verify a.llmll` reports `f` refuted. Expected: `a.llmll.verified.json` no longer gives `f` a positive tier. Channel: trust, the sidecar write in `compiler/app/Main.hs`.
3. **A callee body edit.** `g` declares its return type; its body changes and its contract does not. Expected: `f`'s key does not move; `g`'s does. This is the guard against over-invalidation. If `g` declares no return type and the edit changes its inferred one, `f`'s key moves, by S1's last sentence. Channel: trust.
4. **A recursive pair.** `p` and `q` call each other, both contracted. Expected: each key folds the other's interface text; no key refers to a hash, so no cycle. Channel: trust; spec is silent today (gap, closed by §3).
5. **A callee passed as a value** (`list-fold … g`). Expected: `g`'s interface is in the caller's key, even if the caller's VC does not translate the call today. Conservative: a future release that starts translating it needs no new rule. Channel: trust.
6. **Positive witness for the termination clause.** Module `a`: `f` calls `g`, `f` has a `decreases` measure and is recorded "termination discharged". Then `g`'s body is edited to call `f`, and `a` is not re-verified. Expected on a solver-less read: the live group is `{f, g}`, the stored group of `f` is `{f}`, so `f` stays in `partial_fns`. Channel: trust, `markDescentDischarged`.
7. **A function that requests no control-tag fact.** Expected: its key has no RESP-FACT part and does not change when an issuing def is edited. Channel: trust.
8. **The sidecar-only trust report.** It keeps its disclaimer. S1 makes its `verified` lines correct against the current interfaces; it still does not re-run the emitter. Channel: disclosure, unchanged.

## 6. Verification mapping

No proof obligation is introduced. S1 to S4 decide which trust-channel mechanism invalidates recorded evidence: the per-function key on load (`downgradeStaleVerifiedSidecar`, both for the entry file and through `ProgramGraph.validated` for imports), the whole-sidecar epoch on load (`sidecarNeedsRevalidation`), and the sidecar write at the end of a run (S4). Nothing reaches the solver.

## 7. Deferred design: a key over the emitted VC

The professor's H5 is recorded here and not in `docs/design/theory-questions.md`. It fails that file's negative test: whether it is worth building is a question about this repository, answerable by building it. A canonical hash of a function's emitted VC would cover S1's fields, S2's translation corrections and S3's condition with one mechanism, as Why3 sessions key a stored proof on the generated task. It needs per-function canonical renaming first, because binder and constraint ids come from counters shared across functions, and it puts the emitter on every read. S1's field list is the interim design. Its weakness is that a future emitter read not added to §3 is invisible, which the test plan in §8 item 4 guards against.

## 8. Affected surface

1. `LLMLL.md` §5.3, the "persisted record" note: replace its freshness sentence with S1 to S4 (documentation-lead, at the release).
2. `compiler/src/LLMLL/PBT.hs`, `canonicalDefEvidenceHash`: the preimage gains the own-signature type declarations and the callee interface digests. Change `admitVerifiedSemanticsTag` with it, so the format change is explicit in the preimage.
3. The four sites of §3.1, all calling the one key function. The read sites gain the module cache and the inferred return types as inputs.
4. Tests: the round-trip invariant of §3.1 over the corpus; the two witness variants as hspec cells over three modules; one cell per §3 field (seven) that perturbs that field alone and asserts the caller's key moves; a callee-body-only edit on an annotated callee that asserts it does not; the S4 rewrite on a refuted run; edge case 6 (the recursion group); an issuing-def edit under a requesting def. The red cells on v0.27.1 are the witness variants, the per-field cells, edge case 6 and the issuing-def cell. The round-trip invariant passes on v0.27.1, because today both sides hash the same fields; it guards the new code.
5. `compiler/app/Main.hs`, the non-SAFE branch of `verify`: S4's sidecar rewrite.
6. Effect on release: every key in the corpus changes once, because the preimage format changes. No epoch is spent. One re-verify per tree.
7. `docs/compiler-team-roadmap.md`: retitle the row (proposed: "a stored verdict is keyed on its own source only, so a callee change leaves callers `verified`"), keep the tag, add `[SPEC]`, and move it to G1 rank 1 with the witness cited. That is documentation-lead's edit.

## 9. Risks

1. **The §3 list can fall behind the emitter.** Classification: soundness, at scale. A new read of a callee entry, not added to the digest, reopens the gap for that field. Mitigation: §3.2 builds the key from the emitter's per-function inputs, so a new input is a compile error in the key function; §8 item 4's per-field cells; §7 as the end state. The round-trip invariant does not catch this case, because both sides leave out the same field.
2. **The read sites gain inputs.** Classification: scope. `downgradeStaleVerifiedSidecar` and `ProgramGraph.validated` change signature, and every caller passes the module cache and the inferred return types. Today's callers of `downgradeStaleVerifiedSidecar` in `compiler/app/Main.hs` already hold both. The invariant test is the check that none passes less.
3. **S4's attribution.** Classification: soundness. A failing constraint maps to a function through its origin; a run whose failure cannot be attributed downgrades the whole module. The engineer must show that an attributed refutation never leaves another function's positive record resting on the refuted one. A caller in the same file is re-proved in the same run, so the risk is confined to the attribution itself.
4. **Over-invalidation cost.** Classification: verification ergonomics. A widely called callee's contract edit downgrades all its direct callers. That is the intended behavior. A body-only edit costs nothing (edge case 3).
5. **The importer path re-reads interfaces.** Classification: performance, small. Computing the key for an imported record needs its callees' interfaces, which the module cache already holds.

## 10. Hand-off

Code track. On settlement: `compiler-engineer` plans S1 (shared preimage builder, §3 fields), S4 (the non-SAFE sidecar rewrite) and the §8 tests, as one release. The professor's review stays standalone until settlement, then documentation-lead folds and archives it.

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal is
folded here and the source file archived to
[`docs/archive/professor-reviews/hash-pre-asym-review.md`](../archive/professor-reviews/hash-pre-asym-review.md).
Folded at the settlement of Rev 3, 2026-10-02.

**Source:** `docs/design/hash-pre-asym-review.md` at commit `7743a2f` (reviewed 2026-10-02; reviewer:
Lead Consultant for Formal Language Design). Three rounds, against Rev 0, Rev 1 and Rev 2.

### Round 1, against Rev 0, and its outcome

**The meet is not a dependency key.** Rev 0 let a pre augmentation reach callers through the §4.4.3
transitive meet "until the callee is re-proved", which is the moment the meet passes again without the
caller being re-checked. The reviewer cited Boogie and Dafny's dependency checksums (Leino and
Wüstholz, CAV 2015) and the verifying-trace definition of *Build Systems à la Carte* (Mokhov, Mitchell
and Peyton Jones, ICFP 2018). Outcomes: the witness ([`hash-pre-asym-witness.md`](hash-pre-asym-witness.md))
confirmed the gap on v0.27.1 in both the pre and post variants, and found the failed-run defect (S4);
Rev 1 added the direct-callee digest, the side condition on S3, the release checklist, and recorded a
VC-keyed hash (Why3 sessions, VSTTE 2013) as deferred design (§7).

### Round 2, against Rev 1, and its outcome

**The read sites could not compute the key** (they held one module's statements and the declared return
type); **a descent obligation reads an SCC peer's measure**; **S1's "never reads the body" was false**
for an undeclared return type. The reviewer cited GHC's per-entity interface fingerprints as the closest
precedent and their history of omitted dependencies. Rev 2 added §3.1 (one key function at every site,
and the round-trip invariant), folded every direct callee's measure (a deliberate superset of SCC peers,
so the key never depends on the whole call graph), and restated S1's body sentence.

### Round 3, against Rev 2, and its outcome

**The termination flag depends on the recursion group** (`markDescentDischarged` subtracts the stored
flag from a live `partial_fns`), **a RESP-FACT refinement depends on issuing defs that are not callees**,
and **the field list should follow the emitter by construction**. Rev 3 keyed the termination claim on
its group, folded the seeded RESP-FACT refinement, and added §3.2 (the key built from the emitter's
per-function inputs, each projected to the function). The reviewer's correction that the round-trip
invariant passes on v0.27.1, and so guards the new code rather than reproducing the defect, is recorded
in §8.

**What shipped differs from Rev 3 in one place.** The engineer folded the recursion group into the
record's single key rather than adding a separate termination key field, which would have changed the
record format at about 100 construction sites. The whole record of a function whose group changes is
therefore demoted, not only its termination flag. This over-invalidates and never under-invalidates;
`LLMLL.md` §5.3 states the shipped behavior.

