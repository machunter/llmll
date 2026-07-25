---
name: spec-agreement-proposal
title: "SPEC-AGREE-1: independent formalization with mechanical agreement"
status: "Rev 0, DRAFT - awaiting professor review"
date: 2026-07-25
author: main-agent
consumers: [professor, user, language-team, compiler-engineer, experiment-lead]
---

# SPEC-AGREE-1: independent formalization with mechanical agreement

## Restatement

Today the "what" of an RFC-derived specification is produced once and audited by a human. The
proposal: have **N agents independently formalize the same clause**, then **mechanically check
whether their formalizations agree**, and treat disagreement as a finding with a machine-generated
witness rather than as noise to be voted away.

The reason this is worth building is narrow and specific. The pipeline's own claim discipline
says `:source` is a traceability pointer and not a proof of fidelity, and that fidelity rests on
human audit ([`spec-from-rfc-pipeline.md`](spec-from-rfc-pipeline.md) §2). That is the last
unmechanized link in the chain from RFC text to verified artifact. Independent formalization plus
an agreement check is a mechanical signal exactly there.

## 1. Why agreement is checkable here and not merely rhetorical

Contract agreement in LLMLL is a **decidable query**, not a prose-similarity judgment. The
subsumption driver shipped with REFINE-REUSE (v0.14.29) decides
`pre_s ⟹ pre_d ∧ post_d ⟹ post_s` as two liquid-fixpoint Horn constraints over alpha-normalized
contracts (`LLMLL.RefineReuse.solveSubsumptionFQ`, `buildSubsumptionFQ`). Run it in both
directions and the result is logical equivalence. Two agents writing syntactically different
predicates for the same clause are recognized as agreeing when they are in fact the same
contract, and as disagreeing only when they genuinely differ.

The applicability of the check coincides with the set it needs to serve, by construction. A row
is `Encoded` precisely when it is carried by a contract that discharges in the decidable
fragment, and the decidable fragment is where subsumption is decidable. So SPEC-AGREE-1 applies
to every Encoded row and abstains exactly where the ledger has already recorded that automation
stops.

## 2. Which layers of the "what" are worth agreeing on

Not all of them, and the differences are large.

| Layer | Agreement meaningful? | Why |
|---|---|---|
| **Clause census** (which sentences are normative) | **Yes, already adopted** | The failure mode (overlooking a clause) is roughly independent across agents. Measured on TFTP: Jaccard 0.866, Cohen's kappa 0.938. |
| **Disposition** (Encoded vs excluded) | **No** | Follows from the fragment's documented limits, which every agent reads from the same source. Two agents agreeing is one piece of reasoning run twice. |
| **Architecture and signatures** | **Not mechanically** | Structural comparison of module decompositions has no decidable equivalence check. |
| **Contracts, given fixed signatures** | **Yes, the opportunity** | Equivalence is a solver query. This is where the proposal spends its agents. |
| **Bodies, given a contract** | **Already covered** | R5 `checkout --multi` + `diverge-report` measures implementation divergence. |

Note the duality worth stating explicitly: **R5 measures divergence among implementations given
one contract**, which is a contract-*tightness* signal. **SPEC-AGREE-1 measures divergence among
contracts given one clause**, which is a formalization-*fidelity* signal. They are the two halves
of the same question and neither substitutes for the other.

## 3. The procedure

**Precondition: signatures are frozen first.** Two contracts over different state
representations are not comparable even when both are correct. So the module architecture,
function signatures, and state types are fixed before formalization begins, and all N agents
write against them. This is a genuine cost, discussed as threat T3 below.

1. **Blind N-way formalization.** For each `Encoded` inventory row, N agents (N = 3 proposed)
   independently author the contract clause, seeing the verbatim RFC text, the inventory row, and
   the frozen signatures. They do not see one another's output. Each returns a `pre` or `post`
   predicate carrying the row's citation tag.
2. **Pairwise comparison.** For each row and each pair, run subsumption in both directions. The
   result is a **lattice position**, not a boolean:
   - **Equivalent** (`A ⟹ B` and `B ⟹ A`): the formalizations agree.
   - **Strictly ordered** (`A ⟹ B`, not conversely): one is a strictly stronger reading. This is
     informative rather than fatal, and it is not automatically a defect of the weaker one:
     the stronger contract may be over-strong and forbid a legal implementation.
   - **Incomparable**: the readings diverge in both directions.
3. **Witness generation on any non-equivalence.** Ask the solver for a model of `A ∧ ¬B`. The
   machinery exists: `LLMLL.Feasibility` already builds quantified-LIA queries and minimizes the
   returned model (`buildQuery`, `minimizeWitness`, `renderWitness`). The output is a concrete
   scenario the two readings treat differently.
4. **Adjudication against the source text, never by vote.** The witness converts "two agents
   disagree" into "here is a specific input where reading A permits what reading B forbids; what
   does the RFC say". That question is answerable from the verbatim text and the answer is
   recorded per row with its witness. **Majority voting is explicitly rejected**: it hides the
   disagreement and can certify a shared error.
5. **Outputs.** A per-row agreement record; the **agreement rate** as a headline measurement; the
   witness set; and the adjudication log. Each is publishable evidence about fidelity, which the
   project currently reports nothing about.

## 4. What this does and does not claim

**Claims.** That N independent formalizations of a clause were produced blind and their logical
relationship was decided mechanically; that every non-equivalence was adjudicated against the
verbatim source with a recorded witness.

**Does not claim.** That an agreed contract is correct. Agreement is corroboration, not proof,
and three threats bound it:

- **T1, correlated error.** Agents share training data. On a protocol as widely documented as
  TFTP they may share a misconception, in which case agreement certifies a shared error. This is
  the Knight and Leveson result on independently developed versions failing together far more
  than independence assumptions predict. The proposal does not claim statistical independence and
  should not report agreement as though errors were independent.
- **T2, agreement on a vacuous contract.** Two agents can agree on a formalization that is too
  weak to exclude any wrong behavior. Agreement therefore **never substitutes** for the adequacy
  machinery: the vacuity and discriminative-power checks (`--weakness-check`, `--cdp`) and the
  mutation kill matrix still gate. An agreed contract that no mutant can kill is agreed and
  worthless.
- **T3, framing by the frozen signatures.** Fixing the state representation before formalization
  is what makes contracts comparable, and it also constrains the formalizations toward each
  other, so the measured agreement is **conditional on the architecture** rather than
  unconditional. This must be disclosed whenever the agreement rate is reported. There is a real
  tension here (comparability requires shared vocabulary; shared vocabulary reduces
  independence) and the proposal resolves it toward comparability while stating the cost.

## 5. Edge cases the design must handle

1. **An agent omits a row entirely.** Not a disagreement; a coverage gap. RFC-COV-1
   (`scripts/rfc_coverage.py`) already catches an Encoded row cited by no clause.
2. **Both agents produce a vacuous contract.** Equivalent and worthless. Caught downstream by
   CDP, not here. The agreement record should carry the CDP verdict beside it so the two are read
   together.
3. **Subsumption abstains** (a contract outside the decidable fragment). By construction this
   should not occur on an `Encoded` row; if it does, the row's disposition was wrong, which is
   itself a finding routed back to the inventory.
4. **Contracts equivalent but citing different rows.** A tagging error, caught by RFC-COV-1's
   resolution check, not a formalization disagreement.
5. **N agents produce N distinct readings.** Legitimate outcome and the most interesting one. All
   pairwise witnesses are generated and the row is escalated with its full witness set; a clause
   this ambiguous is a candidate for re-dispositioning rather than for forced consensus.

## 6. Implementation surface

The primitives ship; what is missing is a way to call them on two arbitrary contracts.

| Piece | Status |
|---|---|
| Contract subsumption over alpha-normalized contracts | **Shipped**, `LLMLL.RefineReuse.solveSubsumptionFQ` / `buildSubsumptionFQ`, exported |
| Existential witness with minimization | **Shipped**, `LLMLL.Feasibility.buildQuery` / `minimizeWitness` / `renderWitness`, exported |
| Signature compatibility pre-filter | **Shipped**, `LLMLL.RefineReuse.signatureCompatible` |
| **A CLI surface to compare two named contracts and emit the lattice position plus witness** | **Missing.** New `[CT]` item, small: a subcommand wrapping the two library calls, JSON out. No new theory, no new solver path. |
| Harness to run N blind authors and tabulate | **Missing**, `[EXP]`, Python, sits beside the existing runner |

Effort: `[CT]` small (a wrapper over shipped internals), `[EXP]` medium (N-way authoring run plus
adjudication). Nothing here widens the verification fragment, and no schema change is implied.

## 7. Where it lands in the process

[`rfc-swarm-playbook.md`](rfc-swarm-playbook.md) stage K currently says root contracts are
authored by "agent(s)", which is exactly the vagueness this replaces. Amended shape: fix
signatures, N agents formalize blind, check pairwise, auto-accept unanimous rows, route
non-equivalence to witness-based adjudication, then proceed to the coverage lint and the freeze
as before. Stage D (dual blind extraction) is the same pattern one layer up, so the playbook
gains consistency rather than a new concept.

## 8. Questions for the professor

1. **Is independent formalization by models with shared training independent enough to carry any
   claim at all?** Given Knight and Leveson, what is the strongest defensible statement about an
   agreement rate measured this way, and is there a way to make the sample more independent
   (different model families, deliberately different prompt framings) that is worth its cost?
2. **Is the lattice-position result (equivalent / strictly ordered / incomparable) the right
   output**, or does the strictly-ordered case need its own disposition? A strictly stronger
   contract may be a better formalization or an over-strong one that forbids legal
   implementations, and nothing in the check distinguishes those.
3. **Does T3 (framing by frozen signatures) undermine the measurement enough to change the
   design?** The alternative, letting each agent choose its own state representation, buys
   independence and loses mechanical comparability entirely.
4. **What does the literature do here?** N-version programming's negative results are the obvious
   reference; is there a better-matched lineage for *specification* rather than implementation
   diversity, and does it report anything more useful than a raw agreement rate?
5. **Is a witness-adjudicated disagreement genuinely stronger evidence than a human audit**, or
   does it merely relocate the human judgment to a better-posed question? The proposal assumes
   the latter is worth a great deal; that assumption should be challenged.
