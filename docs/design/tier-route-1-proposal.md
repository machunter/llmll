---
name: tier-route-1-proposal
title: "TIER-ROUTE-1: two tracks for a language change, and the executed witness a fast track must carry"
status: "Rev 1, DRAFT, awaiting user adjudication. A sealed builtin that adds no Response arm, no effect label and no authority currently receives the same pipeline as a type-system change. ENV-READ-1 is the measurement: 815 lines of design documentation for 189 lines of compiler source. THE POLICY IS NOT NEW AND THAT IS THE ARGUMENT FOR IT. CAP-PROC already shipped four operations as one batch at v0.14.81, and FS-COPY-1 shipped inside another change's release at v0.14.84, both without a design round each. This proposal names that practice, gives it a mechanical test, and adds the one clause the practice did not have. THE NEW CLAUSE IS CLAUSE 4, AND THIS SESSION EARNED IT: a no-new-authority claim must be discharged by a witness that was RUN, never by an argument. FS-EXISTS-1 is the positive witness for the clause. Its Rev 1 authority argument was written, reviewed, and refuted by executing it under a parent directory at mode 0111. A tier policy without clause 4 would have fast-tracked a false soundness claim. The test retro-classifies the project's own history correctly: ENV-READ-1 is Tier L because it widened the effect catalog, PROC-BOUNDARY-1 is Tier L because it moved the schema, wasi.proc.run is Tier L because it grants authority nothing else grants, and the CAP-PROC batch is Tier S. This axis is ORTHOGONAL to the campaign's BLOCKS / SHAPES / COSMETIC dispositions and replaces none of them. Home on settlement: docs/UPDATE-PROTOCOL.md D1. Roadmap row: TIER-ROUTE-1."
date: 2026-08-15
author: language-team
consumers: [documentation-lead, compiler-engineer, professor, user]
---

# TIER-ROUTE-1: two tracks for a language change

## Summary

Every change to LLMLL currently receives one process: a language-team proposal,
an optional professor round, an engineer plan, a doc-lead pass, and a release.

That process is correct for a change to the type system. **It is the wrong cost
for a sealed builtin that adds no `Response` arm, no effect label and no
authority.** This proposal routes the second class differently.

**The policy does not lower the bar. It removes duplicated rounds.** Section 7
lists what a fast-tracked change still owes, and the list is most of the bar.

## 1. What raised this

`ENV-READ-1` shipped `wasi.env.get` at v0.15.0. It cost:

| Artifact | Size |
|---|---|
| `docs/design/env-channel-proposal.md` | 301 lines |
| `docs/design/env-read-1-implementation-plan.md` | 514 lines |
| Compiler source added (commit `cd9cb42`) | **189 lines across four modules** |

**815 lines of design documentation for 189 lines of Haskell.**

Three filesystem rows then arrived together, and the request that produced them
asked for one design round instead of three. That request is the signal this
proposal answers.

**A second measurement bounds the class.** Of 82 distinct roadmap row names,
**22 are operating-system surface**: `FS-*`, `PROC-*`, `ENV-*`, `HTTP-*`,
`PATH-*`, `REGEX-*`, `LIST-*`, `RUN-*`. **None of the 22 concerns types,
refinement predicates, contracts, the obligation channels, or the trust model.**
So this is not a small class and it will not close soon.

## 2. This is a new axis and it replaces nothing

`docs/design/llmll-tooling-campaign.md` already classifies a gap three ways.
**BLOCKS**, **SHAPES** and **COSMETIC** record what a gap did to a port.

**That axis answers a different question and it stays exactly as it is.**

| Axis | Question it answers | Owner |
|---|---|---|
| BLOCKS / SHAPES / COSMETIC | What did this gap do to the port that met it? | The port's RFC |
| **Tier S / Tier L (this proposal)** | **What does the fix touch, and therefore how is it routed?** | The roadmap row |

The two are independent. `FS-RMDIR-1` is **BLOCKS** against port 006 and
**Tier S** by the test below. A gap can block a port and still be a small change.
Reading one axis off the other is the error this section exists to prevent.

## 3. The two tiers

**Tier S, standard-library surface.** A sealed builtin that adds nothing to the
language. Routed as a **batch**: one note covering several builtins, one
release, no separate professor round.

**Tier L, language surface.** Anything else. The full pipeline, unchanged.

**A batch takes the tier of its highest member.** CAP-PROC shipped four
operations at v0.14.81 and one of them was `wasi.proc.run`, which is Tier L by
clause 4. So that batch was a Tier L batch that carried three Tier S items.

## 4. The Tier S test

**A change is Tier S if and only if all four clauses hold.** The clauses are
conjunctive and each is checkable by reading or by running something. The shape
follows `docs/design/effect-response-channel-proposal.md:434-443`, which governs
`Response` arm admissibility with a four-part conjunctive rule. **That rule and
this one are different tests over different objects.** That rule admits an arm.
This one routes a change.

1. **Sealed builtins only.** The change adds no syntax, no type, no `def-main`
   field, and no JSON-AST schema delta. **Checkable by reading the diff.**
2. **Every response-bearing operation maps to an existing `Response` arm.** An
   operation that needs a new arm routes to the arm rule, which is Tier L by
   construction. **Checkable by reading the signature.**
3. **Σ_eff does not widen.** The change adds no `EffectLabel` to
   `compiler/src/LLMLL/ObligationAssembly.hs`. **Checkable by reading the diff.**
4. **The no-new-authority claim is discharged by a witness that was run.** The
   change grants no authority an already-shipped builtin grants, and **a
   recorded execution shows it**. An argument does not satisfy this clause.

## 5. Clause 4, and the case that earned it

Clauses 1 to 3 are mechanical and a reader can check them from a diff. **Clause
4 is the one that carries the risk, and this session produced its witness.**

`FS-EXISTS-1` was proposed with this argument: the probe grants no authority
`wasi.fs.list` already grants, because a listable parent already reveals every
name it holds. The argument was written, reviewed, and looked sound.

**Running it refuted it.** With the parent directory at mode 0111, meaning
search permitted and read denied:

```
listDirectory  = EXCEPTION (RErr)
exists(id_rsa) = True
exists(absent) = False
```

The probe answers about a directory the program cannot enumerate. A program can
test for `/root/.ssh/id_rsa` without listing `/root/.ssh`. Execute-without-read
is a standard configuration for a shared parent.

**A tier policy with only clauses 1 to 3 would have fast-tracked a false
soundness claim**, because `wasi.fs.exists` passes all three. Clause 4 is what
stops it, and only because the clause demands an execution rather than a
paragraph.

**Clause 4 is cheap where the claim is true.** `wasi.fs.rmdir` grants strictly
less than `wasi.fs.delete`, because an empty directory holds no bytes. The
witness is one run: `rmdir` on a non-empty directory answers `RErr`. That is a
line of output, not a section.

## 6. The demotion trigger

**Any of the following moves an item to Tier L immediately.** The item leaves
its batch and the batch ships without it.

1. The clause 4 witness fails, or nobody can construct it.
2. The implementation needs a dependency the generated project does not already
   carry.
3. A `Response` arm or an `EffectLabel` turns out to be needed after all.
4. **The chosen primitive conflates two outcomes the design separates.**

Trigger 4 is also from this session. `FS-EXISTS-1`'s design separates absent
from undecidable. Its first chosen primitive, `doesFileExist`, returns `False`
for a file that exists and cannot be reached, measured under a parent at mode
0000. **So the primitive collapsed exactly the distinction the design was built
on**, and the collapse was invisible until somebody ran it.

**Demotion is not a failure of the policy. It is the policy working.** Record the
demotion in the roadmap row so the next reader sees why the item left its batch.

## 7. What Tier S skips, and what it never skips

**Skipped:**

- A separate design proposal per builtin. One batch note covers the set.
- A separate professor round. The user may still invoke one at any time.
- A separate release per builtin. The batch is one version.

**Never skipped:**

- **The written soundness argument.** `docs/compiler-team-roadmap.md:276` lifted
  the feature freeze at v0.11 and requires a soundness argument in the design
  record of any addition. That requirement is unchanged. Under clause 4 the
  argument now carries a recorded run.
- **The edge-case enumeration, with a positive witness.**
- **The verification mapping.**
- **The roadmap row.** Rows are the gap register and they cost little.
- **The gap disposition.** BLOCKS, SHAPES or COSMETIC is recorded as today.
- **The `primEffect` placement check.** A clause must sit above the `wasi.`
  fallthrough in `compiler/src/LLMLL/ObligationAssembly.hs`, or the name reports
  the lattice top and every caller's `effect_summary` goes vacuous. That trap is
  already recorded twice, for `wasi.proc.args` and for `wasi.env.get`.

## 8. The external reference class

Three comparable projects separate a library addition from a language change,
and this proposal follows them rather than inventing a shape.

**Rust.** The `rust-lang/rfcs` process governs substantial changes. Minor
additions do not need an RFC and are decided on the pull request under a final
comment period, with accept, postpone and close as the outcomes.

**GHC.** The `ghc-proposals` process governs language extensions and major API
changes. A change to `base` goes to the Core Libraries Committee instead, which
is a lighter track.

**Python.** A PEP governs language and cross-cutting changes. An ordinary
standard-library addition goes through the issue tracker.

**The common structure is the point.** All three route by what the change
touches, not by how important it feels. None of them lets an author self-select
the light track without a stated criterion, which is what clause 4 supplies here.

## 9. The test applied

**Retro-classification, as a check on the test.** A routing test that
misclassifies the project's own history is not usable.

| Change | Tier | Clause that decides it |
|---|---|---|
| CAP-PROC's `wasi.fs.mkdir`, `wasi.fs.sha256`, `wasi.clock.monotonic` | **S** | All four hold. Shipped as a batch at v0.14.81, which is the precedent |
| `wasi.proc.run` (same batch) | **L** | Clause 4. It grants authority nothing else grants, which is why its grant must name the executable |
| `FS-COPY-1` (`wasi.fs.copy`, v0.14.84) | **S** | All four hold. Shipped inside another change's release with no design round of its own |
| `ENV-READ-1` (v0.15.0) | **L** | Clause 3. Σ_eff widened six to seven with `env.read` |
| `PROC-BOUNDARY-1` (v0.14.85) | **L** | Clause 1. `def-main` gained `:status` and the schema moved 0.10.0 to 0.11.0 |
| `FS-RMDIR-1` | **S** | All four hold. The clause 4 witness is one run |
| `FS-STAT-1` | **L** | Clause 4. Its consumer's precondition and its failure direction are design content |
| `FS-EXISTS-1` | **L** | Clause 4, by refutation. Section 5 |

**The test agrees with every decision the project already made.** That is the
evidence that it encodes existing judgement rather than replacing it.

**The remaining 18 operating-system rows are not classified here.** Applying the
test to each is one line of work per row and belongs to whoever picks the row up.
Classifying them in this document would be a claim with no reading behind it.

## 10. Edge cases and degenerate inputs

1. **A batch of three Tier S builtins where one is later demoted.** Expected: the
   demoted item leaves the batch and the other two ship. Channel: **process**.
   The roadmap row records the demotion and its trigger.
2. **A Tier S builtin whose clause 4 witness cannot be constructed, because the
   authority it grants has no already-shipped comparison.** Positive witness:
   `wasi.proc.run`, which spawns and therefore leaves the sandbox by
   construction. Expected: **Tier L**, and clause 4 fails by being
   unsatisfiable rather than by being refuted. Channel: **process**. The two
   failure modes are recorded differently, because "the claim is false" and
   "there is no claim to make" are different findings.
3. **A change that adds no builtin at all and only corrects a spec sentence.**
   Expected: **neither tier applies.** This policy routes additions.
   `docs/UPDATE-PROTOCOL.md` D1 already routes a doc-only change. Channel:
   **spec is silent (intentional)**.
4. **A Tier S batch that grows past a reviewable size.** Expected: **spec is
   silent (gap, flagged)**. This proposal sets no cardinality limit, because no
   measurement supports a number. Risk 3 records it.

## 11. Verification mapping

**This proposal introduces no proof obligation.** It is a routing policy over
documents and reviews. Nothing here emits a constraint, changes a refinement
predicate, or moves the QF-LIA boundary at `LLMLL.md §5.3.3` and `§5.3.5`.

Stating this is not a formality. **The policy must not be readable as a change to
what gets verified.** A Tier S builtin's own obligations are classified in its
batch note exactly as a Tier L builtin's are in its proposal, and section 7 keeps
that requirement.

## 12. Affected surface

- `docs/UPDATE-PROTOCOL.md`: the per-change update matrix (D1) gains a row for a
  Tier S batch. This is the policy's home on settlement and it is doc-lead's
  slot.
- `docs/compiler-team-roadmap.md`: a `TIER-ROUTE-1` row, and a tier marking on
  each operating-system row as it is picked up.
- `docs/design/llmll-tooling-campaign.md`: one sentence naming the second axis,
  so a reader does not read BLOCKS as a tier. Section 2.
- `docs/design/INDEX.md`: one row for this proposal.

**Not touched:** `LLMLL.md`, `CHANGELOG.md`, `README.md`,
`docs/llmll-ast.schema.json`, and every `compiler/src/LLMLL/` module. **This
proposal changes no code.**

## 13. Risks

1. **Tier S becomes a way to skip review.** Classify: **scope**. Cite: section 5,
   where a self-certified authority claim was false. Bite: **complicates, and it
   is the policy's main hazard.** Clause 4 and the demotion trigger are the whole
   mitigation. If clause 4 is ever softened to accept an argument, withdraw the
   policy rather than keep a weakened version.
2. **The batch note becomes a proposal by another name.** Classify:
   verification-ergonomics. Bite: only matters at scale. If a batch note reaches
   the length of a proposal, the batch was Tier L and the test was misapplied.
   That is a measurable signal and it should be watched.
3. **No cardinality limit on a batch.** Classify: scope. Cite: edge case 4. Bite:
   only matters at scale. A limit invented now would be a number with no
   measurement behind it, so the proposal states the gap instead.
4. **Two axes may be conflated by a reader.** Classify: spec-drift. Cite: section
   2. Bite: complicates. The campaign document needs the one sentence section 12
   names, or the next reader will treat COSMETIC as a synonym for Tier S.

## 14. Open questions for the professor

1. **Is a self-certified fast track ever safe without an executed witness?**
   Rust, GHC and Python all let an author propose the light track, and all three
   rely on a committee reading rather than on a run. LLMLL has no committee. So
   clause 4 substitutes execution for a second reader. Name whether any process
   in the literature makes that substitution, and what it loses. The answer
   decides whether clause 4 is sufficient alone or whether a Tier S batch needs
   one mandatory second reader regardless of tier.
