# Professor review — REFINE-REUSE redundancy gate (Rev 0 sketch)

Reviewing `docs/design/refine-reuse-gate-proposal.md` (Rev 0). Standalone; not folded.

## Restatement

REFINE-REUSE adds a third `refine` gate keyed on **contract-subsumption** (contravariant
precondition `preₛ ⇒ pre_D`, covariant postcondition `post_D ⇒ postₛ`): an advisory
`reuse_suggestions` brief channel for any existing def that subsumes a spawned sub-contract, plus an
opt-in `--strict-refine` **fail-closed reject** on contract-*equivalence* with an in-scope,
type-exact candidate. It is positioned as the semantic generalization of the D2 freshness clause and
a sibling of the vacuity and orphan gates.

## Context located

1. `docs/design/refine-reuse-gate-proposal.md` — the proposal under review.
2. `compiler/src/LLMLL/PatchApply.hs` `validateRefineScope` (3)/(4) — freshness (name-collision) /
   orphan (unused spawn); the gate generalizes (3) from name to contract.
3. `compiler/src/LLMLL/CDP.hs:174–181`; `cascading-refinement-proposal.md` §"Layer 3" — the two
   existing contract-quality gates (vacuity, feasibility).
4. `compiler/src/LLMLL/FixpointEmit.hs:829–854` — the COMP-4(b) subtyping fast-path:
   `renameVar xbA "v" pA == renameVar xbP "v" pParamE` normalizes only the refinement binder, **not**
   free parameter variables; Vazou ICFP'14 cited at `:829` for the semantic (non-fast) path.
5. `compiler/src/LLMLL/Syntax.hs:825–831` — `ModuleEnv` (`meExports`, `meContracts`) is populated
   per loaded/imported module; peer modules are invisible until imported.
6. External, not consulted by the proposal: Zaremski & Wing, "Specification Matching of Software
   Components," ACM TOSEM 6(4), 1997 (exact / plug-in / relaxed match); Liskov & Wing, "A Behavioral
   Notion of Subtyping," ACM TOPLAS 16(6), 1994 (the pre-contravariant/post-covariant direction);
   Mili, Mili & Mittermeir, "Storing and Retrieving Software Components: A Refinement Based System,"
   IEEE TSE 23(7), 1997 (lattice-indexed spec store); Fischer & Schumann, NORA/HAMMR
   (signature-filter-then-prove retrieval, prover-cost engineering); Back & von Wright, *Refinement
   Calculus* (1998, the refinement lattice); Tate et al., "Equality Saturation," POPL 2009 / Willsey
   et al., "egg," POPL 2021 (congruence closure for canonicalization).

## Gaps and hazards

1. **Blocking on redundancy is a hygiene judgment, not a well-formedness one — the "sibling of
   vacuity/orphan" framing is a category error.** *Scope / design-category.* Vacuity (a trivial body
   already satisfies the contract, `CDP.hs:174`) and orphan (a spawned def nothing calls,
   `PatchApply.hs` clause 4) reject *malformed* decompositions — a spec defect and a dangling node
   respectively. A decomposition that is verified, non-vacuous, fully-referenced, and merely
   duplicates an existing contract is **well-formed**; it is non-canonical, not defective. The entire
   specification-matching / component-retrieval literature (Zaremski-Wing TOSEM'97; Mili et al.
   TSE'97; Fischer-Schumann) is *retrieval* — it ranks and suggests reuse; it never *forbids*
   authoring a fresh component. A fail-closed prohibition has no precedent there and therefore carries
   the burden of proof, which Rev 0 does not discharge. *Bite:* blocks the fail-closed tier as
   proposed; the advisory tier is untouched and is exactly what the literature sanctions.

2. **The gate is structurally blind to the concurrent parallel-module duplication it calls its
   sharper motivation.** *Scope.* The proposal motivates itself on parallel-module authoring where
   subtrees "never share a namespace," but the candidate pool is `{siblings} ∪ {imported (meContracts)}
   ∪ {hub}`. Two subtrees authored concurrently in *peer* modules have not imported each other —
   peers are not dependencies — so neither is in the other's `meContracts` (a `ModuleEnv` exists only
   for a loaded/imported module, `Syntax.hs:825–831`). Intra-module the CAS serializes and the brief
   is fresh, so the gate catches *sequential intra-module* duplication; across concurrently-authored
   peers it sees nothing. The stronger claim is precisely the case the mechanism cannot reach. *Bite:*
   blocks the parallel-module framing; the intra-module claim survives. Retract or heavily qualify.

3. **The fail-closed variant makes the decomposition artifact spawn-order-dependent.** *Scope /
   determinism.* On equivalence, the surviving representative is whoever spawned first; reverse the
   agent schedule and a different name survives and a different call graph results. Incremental dedup
   is inherently order-sensitive, but an *advisory* leaves the program identical regardless (only the
   suggestion differs) whereas a *block* mutates program structure as a function of lock-acquisition
   order — in tension with the determinism discipline adopted for PROOF-ARTIFACT (`roadmap:64`).
   Replay of a *committed* module is unaffected (soundness intact); reproducibility of *authoring* is
   not. *Bite:* mild, reproducibility not soundness; a further argument for advisory-over-blocking.

4. **The syntactic-reflexivity fast-path is weakest exactly in the motivating case.** *Ergonomic /
   cost.* The proposal leans on COMP-4(b)'s fast-path to resolve "the common identical-predicate
   case" without a solver call, but that path normalizes only the refinement binder
   (`FixpointEmit.hs:849–850`); free *parameter* names are not α-normalized. Blind, uncoordinated
   subtrees — the whole premise — will name parameters differently, so
   `(<=> result (= computed expected))` vs `(<=> result (= a b))` are semantically equal yet
   syntactically distinct after binder-renaming and fall through to the full liquid-fixpoint
   subtyping query (sound, Vazou ICFP'14, but not free). The advertised cost mitigation evaporates in
   the case it exists to serve; the proposal's positive witness (edge case 1) hides this by using
   identical parameter names. *Bite:* complicates the cost story; demands α-normalization of
   candidate contracts before the pairwise query, or the index of hazard 5.

5. **Pairwise `O(spawns × candidates)` scan is the known-inferior retrieval architecture.**
   *Ergonomic / scale.* The proposal inherits HubQuery's "brute-force scan, no index" and adds an
   implication query per surviving candidate — quadratic in the def population at the 163-function /
   parallel-module scale it invokes. The retrieval literature indexes by the refinement lattice (Mili
   et al. TSE'97) and keeps prover calls off the hot path with signature and rejection filters
   (Fischer-Schumann); for the *equivalence* sub-problem, congruence closure / equality saturation
   (Tate et al. POPL'09; `egg`, POPL'21) gives near-linear amortized dedup versus pairwise solver
   queries. *Bite:* matters at scale; adopt canonical-index-for-equivalence, reserve pairwise
   implication for the advisory plug-in tier.

6. **The precondition-bearing branch of subsumption is unwitnessed.** *Ergonomic / test-coverage.*
   Contravariant-pre (`preₛ ⇒ pre_D`) is the branch most exposed to a substitution/frame bug and the
   one every edge case leaves pre-free. By the language-team's own positive-witness discipline
   (`docs/UPDATE-PROTOCOL.md` D2), the proposal owes a witness with a nontrivial `pre_D` and a
   candidate whose precondition is *not* discharged by the spawn's — subsumption must *fail* on the
   precondition despite a matching postcondition. Zaremski-Wing's *guarded plug-in match* is the exact
   form. *Bite:* complicates; one more edge case.

## Recommendation

Ship the advisory tier; do not ship the fail-closed gate as proposed. Ranked:

1. **(Recommended) Advisory-only, plus at most a non-blocking warning under `--strict-refine`.** This
   is the literature-sanctioned design (retrieval, not prohibition), sidesteps hazards 1–3 entirely,
   and attacks the real failure mode ("the filling agent could not see the sibling"). Reclassify the
   item away from "third gate, sibling of vacuity/orphan": it is a *retrieval/hygiene* facility, not a
   well-formedness gate. Vacuity and orphan reject defects; reuse surfaces an opportunity.
2. **(Only if blocking is genuinely wanted) Equivalence-block gated on a canonical contract index,
   not pairwise queries.** Build a normalized-contract key (α-normalize parameters, canonicalize the
   predicate via congruence closure), index the def population by it, and block only on key collision
   with an in-scope def. This makes the block confluent over the *set* of equivalence classes
   (a deterministic representative tie-break is still owed), amortizes the cost (hazard 5), and closes
   the α-renaming hole (hazard 4) by construction. Heavier; justify against option 1's sufficiency.

To catch concurrent peer duplication (hazard 2) at all, you need a shared spec-index *across* the
co-authored modules — the Mili-style refinement store as a first-class cross-module artifact — which
is a materially larger proposal than a refine-time gate. Do not let the gate imply that reach.

**Convergence worth naming.** The proposal's own structure — signature filter → implication query —
is exactly Fischer-Schumann's NORA/HAMMR retrieval pipeline, and its subsumption direction is exactly
Liskov-Wing behavioral subtyping. The language-team reached these from inside LLMLL; the retrieval
literature reached them from outside. The agreement is signal that the *relation* is right. It is the
*blocking* framing, not the relation, that the outside view rejects.

## Open questions for the language-team

1. Justify a fail-closed reject given that the specification-matching literature is retrieval-only
   (Zaremski-Wing TOSEM'97; Mili et al. TSE'97; Fischer-Schumann). Name one case where a *verified,
   non-vacuous, fully-referenced* decomposition that duplicates a contract is a defect the compiler
   should refuse rather than warn on. If none, the gate collapses to Recommendation 1.
2. Provide the guarded positive witness hazard 6 asks for: a candidate with a nontrivial `pre_D` and
   parameter names different from the spawn's, exercising both the contravariant-pre branch and the
   α-renaming the fast-path (`FixpointEmit.hs:849`) does not normalize.
