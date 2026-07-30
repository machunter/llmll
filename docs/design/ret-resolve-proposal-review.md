---
name: ret-resolve-proposal-review
title: "Professor review of ret-resolve-proposal.md, rounds 1-4"
status: "Standalone review, not folded. Rounds 1-2 folded into Rev 1 / Rev 2; rounds 3-4 produced SAFE-ARG and WILD-ASSUME instead of proposal changes"
date: 2026-07-29
author: professor
consumers: [user, language-team, compiler-engineer, documentation-lead]
---

# Professor review of `ret-resolve-proposal.md`, rounds 1-4

Four rounds against a proposal whose rule text stopped changing after round 1. Rounds 3 and 4 found a
live soundness defect that is not RET-RESOLVE's, routed to
[`finding-arg-position-false-safe.md`](finding-arg-position-false-safe.md). This file preserves the
findings in the order they were made, plus the two literature answers the language-team requested.

## Round 1: seven findings against Rev 0

1. **The `if`-join preference without a side condition reintroduces the guess Stage 1 was narrowed to
   exclude.** Rev 0 relocated RET-BRANCH-PREF Stage 2 into the resolution pass on the grounds that
   the pass cannot change acceptance. That removes the *acceptance* hazard and not the *correctness*
   one: preferring a concrete sibling over a foreign wildcard is still a guess about a callee's return
   type. Classification: soundness-adjacent. Recommendation: condition it on same-SCC membership,
   which generalizes Stage 1's self-call condition to its natural boundary (Milner 1978; Damas and
   Milner, POPL 1982; Jones, *Typing Haskell in Haskell*, Haskell Workshop 1999 §11). This also makes
   the SCC decomposition necessary, contradicting Rev 0's dismissal of it as descriptive, and gives a
   one-pass algorithm in reverse topological order.
2. **`τ_ret` gates admissibility, so the pass changes tier assignment and not only sorts.**
   `contractSigGuardsBlock` (`FixpointEmit.hs:1668-1673`) and the emit guard at `:842` evaluate
   `sigPairUnsafe` (`:2501-2507`) and `resultReturnUnsafe` (`:2515-2518`) against the post-`effRet`
   value. Rev 0's "the emitter needs no change at all" is true of the code and understates the reach.
   Classification: scope, spec-drift.
3. **The deferral of the type-environment fix is justified on grounds the spec does not supply.** The
   parent finding argues that breaking the two-pass loop requires SCC binding-group typing and that
   this is the "global unification" `LLMLL.md:358` disclaims. It is not: that clause sits beside
   "per-call-site instantiation" and follows Pierce–Turner (TOPLAS 2000), so it scopes over
   whole-program instantiation constraints. SCC-ordered binding-group typing is part of the
   Damas–Milner core the same sentence claims. The undecidable neighbour is *polymorphic* recursion
   inference (Mycroft 1984; Henglein, TOPLAS 1993; Kfoury–Tiuryn–Urzyczyn 1993), which is not what
   the fix needs. The real obstacles are corpus compatibility and importer strictness at `meExports`.
   Classification: spec-drift.
4. **The wildcard is the gradual dynamic type without casts, so the `L_mono` residue is a predicted
   consequence rather than an unspecified corner.** `compatibleWith (TVar _) _ = True`
   (`TypeCheck.hs:2185`) with the non-transitivity already documented at `LLMLL.md:401` is precisely
   Siek–Taha consistency (2006). Their soundness argument depends on cast insertion; `§3.4.5`
   forecloses casts, so there is no blame point (Wadler and Findler, ESOP 2009) and no gradual
   guarantee (Siek, Vitousek, Cimini and Boyland, SNAPL 2015). Classification: soundness.
5. **SC2 quantified over diagnostics only.** `recordHole` (`TypeCheck.hs:678-697`) appends to
   `tcHoles`, read as `sketchHoles` at `:2295`; a second synthesis pass duplicates hole
   registrations. Strengthen to a sandboxed state from which only the return map is extracted.
   Classification: ergonomic, artifact soundness.
6. **The brief-versus-verifier asymmetry widens.** The brief path keeps its own return-type
   derivation while the emitter's map becomes fully resolved. Classification: ergonomic. (Round 3
   correction: the brief reads the *raw* `mRet` at `Checkout.hs:1106`, not `synthRet`, so the
   asymmetry is wider and older than stated here.)
7. **`⊔` is not a join.** "concrete ⊔ anything = the original concrete" is not commutative when the
   two concretes differ. State the termination argument as Kleene iteration of a monotone update on a
   product of flat lattices (Cousot and Cousot, POPL 1977; Kildall, POPL 1973). The proof survives;
   the vocabulary misleads.

Recommendation: take the proposal. The stratification it describes, a fixpoint over a fixed base-type
skeleton downstream of type inference and forbidden from influencing acceptance, is how refinement
inference is staged in Liquid Haskell (Rondon, Kawaguchi and Jhala, PLDI 2008; Vazou, Seidel, Jhala,
Vytiniotis and Peyton Jones, ICFP 2014). Cite one of them in the spec sentence so a reader does not
read the second pass as a hack.

## Round 2: the effective-post channel

**`τ_ret` reaches `augmentContractPost` (`:688`) via the definition-site call sites (`:529-566`), so
the pass changes the effective postcondition.** Refinement aliases *are* synthesized, contrary to the
comment at `:412-413`, so `τ_body` can be a `TCustom` whose predicate is folded into the effective
post as a new obligation (`LLMLL.md:447`). The available direction is `verified` → `refuted`, which is
strictly stronger than the two directions Rev 1 enumerated. Rev 1's gate list therefore covered two of
three invariants; an obligation-set diff was missing, and `addEmittedPre` / `addEmittedPost`
(`:499`) already exist as hooks.

Also: I2 as written required a gain in `verified` to be traced to a named channel with its facts
recorded. Recording is insufficient, because the fact's truth depends on a producer whose annotation
was never validated. I2 needs the producer's verification status in its antecedent.

## Round 3: the latent false SAFE, and a fix that was wrong

**Finding:** the wildcard launders a `bytes` length mismatch (`P1_direct` rejected, `P2_wildcard`
clean), the length fact is then injected from the unvalidated declaration, the obligation becomes its
own premise, and only an incidental sort collapse prevents SAFE. Classification: soundness.

**My recommended fix was wrong and the language-team refuted it with measurement.** I proposed
reverting `resultLenFact` to read the declared `mRet` rather than the post-`effRet` value.
`P3_declared_lie` shows the false fact is injected from *declared* returns too, identically at
v0.14.71 and v0.14.72, so the revert targets the widening and not the defect. `P5_noncall` further
shows no call-free laundered lie exists, so the mask is structurally coupled to the laundering rather
than incidental. Both corrections stand.

**Literature answer requested in Rev 1, on migration staging.** The device exists. Gradual type
inference solves for the most precise types consistent with a program while retaining the dynamic
type as a legitimate solution (Rastogi, Chaudhuri and Hosmer, *The Ins and Outs of Gradual Type
Inference*, POPL 2012); the pitfalls of naive unification with the dynamic type are in Siek and
Vachharajani (DLS 2008); principality is settled in Garcia and Cimini (POPL 2015); and the
migration-blast-radius question is answered directly by Campora, Chen, Erwig and Walkingshaw,
*Migrating Gradual Types* (POPL 2018), whose variational typing computes the whole space of
annotations addable without breaking type-correctness. Decidability of the associated questions is
mapped in Migeed and Palsberg (POPL 2020). The practical form is one type system with a staged
diagnostic, not two type systems: `noImplicitAny` in TypeScript, `--disallow-untyped-defs` in mypy.

**Literature answer requested in Rev 1, on recording repair-shaped demotions.** Keep it out of the
lattice. `§5.3.4`'s meet ranks evidence strength at a point in time and overloading it with history
costs comparability. The correct reading is belief revision: withdrawing a conclusion because its
justification was defeated is contraction, not the assertion of a weaker claim (Alchourrón,
Gärdenfors and Makinson, JSL 1985), operationally a justification-based truth-maintenance record
(Doyle, AIJ 1979; de Kleer's ATMS, AIJ 1986). The assurance-case literature versions the argument
rather than re-grading the claim (Kelly and Weaver, GSN, 2004). In-project the device already exists:
`codegen_semantics_version` (`ProofArtifact.hs:201, 317`; `LLMLL.md:1050, 1056`) is specified for the
structurally identical case. (Rev 2 correction, accepted: the stamp has no reader, so it records
incomparability without enforcing it.)

## Round 4: the live false SAFE

**`Q1_argpos` verifies SAFE at both v0.14.71 and v0.14.72 and writes a `.verified.json`.** An
unannotated hop launders a `bytes[32]` into a `bytes[64]` *parameter*; the callee's VC asserts
`bytesLen(b) = 64` from the declared parameter type and discharges its index-in-bounds obligation
against it. The defect is not latent, is not gated on any hygiene fix, and predates the entire
FQ-RESULT-SORT-1 line. Round 3's coupling argument holds for the *return* position only: at an
argument position the false fact lands on a parameter of a function verified independently, whose VC
contains no call binder for it.

Consequent findings, all routed to the finding file:

- **WILD-INDEX as stated in Rev 3 was incomplete.** Keying the rule on checking positions misses
  argument passing, which is where the damage is. State it over the absorbing clause itself.
- **`indexed(τ)` was an enumeration in search of a criterion.** `Q2_alias` supplies it: a refinement
  alias carries type-level data and is safe, because `§3.4.1` obligates the producer to prove it and
  the probe is REFUTED. The criterion is "contributes a VC assumption that no obligation discharges",
  which is FACT-AG inverted.
- **The anti-laundering invariant covers records and not assumptions.** `LLMLL.md:1060` makes a
  positive-tier record ill-formed unless its fields cohere. Here they all cohere. The unguarded
  surface is the one that matters.

**Literature answer on refusing the dynamic type at data-carrying positions.** Every system that
admits it at a type index pays with a runtime check or with new normalization machinery: Lehmann and
Tanter, *Gradual Refinement Types* (POPL 2017), make refinement formulas imprecise and restore
soundness with checks; Eremondi, Tanter and Garcia, *Approximate Normalization for Gradual Dependent
Types* (ICFP 2019), allow `?` at indices and must introduce approximate normalization; Ou, Tan,
Mandelbaum and Walker (IFIP TCS 2004) insert coercions at the boundary; Tanter and Tabareau (DLS
2015) realize casts as axioms that fail at runtime. Since `§3.4.5` forecloses casts, refusing the
dynamic type at those positions is the only remaining sound option, and restricting the gradual
fragment while stating the guarantee over the remainder is ordinary practice. The design-reference
alternative is F\*'s length-indexed buffers (call-site proof) or Dafny's term-level `a.Length` (no
type-level lie expressible).

**Literature answer on class-indexed conservativity.** Keep the class index; it is not an artifact.
At scalar types a laundered wildcard yields a sort disagreement that fails closed (`L_mono`); at
data-carrying types it yields sort agreement with a false fact that fails open (`Q1_argpos`). State
the theorem as a commuting square over the elaboration with the criterion as its side condition,
which is how gradual typing states theorems over cast insertion (Siek and Taha 2006; Herman, Tomb and
Flanagan on coercions) and how refinement inference states them over elaborated Core (Vazou et al.,
ICFP 2014). The index disappears when the side condition holds everywhere, which is a goal rather
than a rephrasing.

## Convergence, and what the rounds cost

Four rounds, four reading paths, one defect. Round 2 enumerated the consumers of the post-`effRet`
value; round 3 asked whether an injected fact can be false; the language-team measured which fix
actually closes it; round 4 tested the completeness of the rule's position keying and found the live
case. None of the four steps would have found it alone.

The channel count for `τ_ret` moved 1 → 2 → 4 → 4-plus-parameters, each increment found by reading
rather than by deriving the consumer set from the emitter. That is the argument for the
language-team's own recommendation that the engineer re-derive the set mechanically; the derived table
now lives in the finding.
