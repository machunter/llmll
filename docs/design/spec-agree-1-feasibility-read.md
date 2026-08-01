---
title: "SPEC-AGREE-1 §9 feasibility read: constructor-capable subsumption and Sigma_witness widening"
status: "Feasibility read. Not an implementation plan; no approval requested for code."
author: compiler-engineer
date: 2026-07-31
consumers: [user, professor, language-team, experiment-lead]
answers: "docs/design/spec-agreement-proposal.md §9"
---

# SPEC-AGREE-1 §9 feasibility read

## Restatement

§9 asks the cost of (i) reusing the `FixpointEmit` declaration path so the subsumption query can
compare constructor-bearing contracts, and (ii) widening `baseSortText` to enum and constructor
sorts with `witnessOf` extended to match, and whether (ii) is separable from (i).

Both turn out to be gated on the same choice, and it is not the one §6.1 and §6.2 assume. The
choice is **int-tag encoding versus native datatype sorts**, and it splits each item into a cheap
tier and an expensive tier that do not have to ship together.

## Context located

1. `compiler/src/LLMLL/RefineReuse.hs:281-299` — `qfContract` and `ufBearing`. The comment at
   `:275-280` states the reason for the constructor abstention in the code's own words: "this
   driver's bare .fq declares no UF constants (strLen/listLen/pair2*/ctor terms would reach
   liquid-fixpoint undeclared; the fail-safe would abstain after a doomed solver spawn)."
2. `compiler/src/LLMLL/FixpointEmit.hs:2776-2778, 2885` — **`exprToPred` already lowers constructor
   terms.** A nullary uppercase `EVar` becomes `FQApp (fqCtorSym v) []`; an uppercase `EApp` becomes
   `FQApp (fqCtorSym ctor) args`. This is the finding that reshapes the estimate: §6.1 describes the
   work as teaching the query to compare constructor terms, but the lowering is already there.
   `ufBearing` is a **declaration guard, not a fragment limit**.
3. `compiler/src/LLMLL/RefineReuse.hs:201` — `buildSubsumptionFQ` returns
   `emptyFQFile { fqBinds = …, fqConstraints = … }`, and `emptyFQFile` is `FQFile [] [] [] [] []`
   (`FixpointIR.hs:213-214`). `fqDataDecls` and `fqConstants` are left empty. That is the entire gap.
4. `compiler/src/LLMLL/FixpointEmit.hs:2582-2593` — `typeSorts` already builds `[FQDataDecl]` from an
   in-scope sum type, with `admissibleDatatype` deciding payload-carrying versus tag-only. This is
   the declaration path §6.1 names, and it is directly reusable.
5. `compiler/src/LLMLL/FixpointEmit.hs:2629-2630, 253, 690` — `desugarCtorValues` plus
   `buildCtorTagMap` int-tag-desugars pure nullary enums (COMP-3b-general). Called only from the
   main emit path, never from `RefineReuse`.
6. `compiler/src/LLMLL/Feasibility.hs:187-191, 199-208, 256-284` — `baseSortText`, `scriptOf`,
   `minimizeWitness`, `witnessOf`. **This is a raw z3 SMT-LIB path, not liquid-fixpoint**
   (`runZ3`, `readProcessWithExitCode z3` at `:218-226`). It shares only `exprToPred` with the
   subsumption path, through `lowerE` at `:182-183`.
7. `compiler/app/Main.hs:72` — `reuseRetrieval` is wired; the gate is live, not shelved.
8. `experiments/spec-agree-1/` — the measurement harness behind §0. Used below to quantify each
   tier rather than estimate it.
9. `docs/compiler-team-roadmap.md` — searched for an existing `[CT]` row for SPEC-AGREE-1a. None
   exists; §6.3(a) proposes it. This read is the input to writing that row, and it argues the row
   should be **two** rows.

## The finding that changes the estimate

`exprToPred` translates constructor terms today. `buildSubsumptionFQ` therefore already produces a
well-formed `FQPred` for a constructor-bearing contract. What it does not produce is the
`data` and `constant` sections that make those symbols resolvable, so liquid-fixpoint would see
`FQApp "cRed" []` undeclared. `ufBearing` exists to stop that from reaching the solver.

This means §6.1's work is **not** "widen comparison to constructor terms". It is "populate two
already-typed fields of a record, then delete the guard clauses that compensated for their being
empty". The comparison capability is shipped; the declaration plumbing is what is missing.

## Quantified payoff, measured not estimated

Run through `experiments/spec-agree-1/` with the `ufBearing` clause disabled:

| Gate | Comparable defs | Comparable rows |
|---|---|---|
| Today | 3/21 (14.3%) | 9/85 (10.6%) |
| Without `ufBearing` | 21/21 (100%) | **61/85 (71.8%)** |

**71.8% is a hard ceiling, and it is not set by the solver fragment.** 61 is exactly the count of
`Encoded` rows cited by any clause (§0.3, row 4). The residual 24 rows are uncited, so no contract
work reaches them. §6.3(a)'s acceptance ("the comparable fraction rises from 9/85, republished")
should be written against 61/85 as its maximum, not left open.

Splitting the 18 abstaining defs by what they would actually require:

| Tier | Mechanism | Defs | Rows | Cumulative |
|---|---|---|---|---|
| 1 | int-tag desugar only, no declarations (+ a `signatureCompatible` fix, risk 1) | 9 | +25 | 9/85 → **34/85 (40.0%)** |
| 2 | native `FQDataDecl` emission | 9 | +27 | 34/85 → **61/85 (71.8%)** |

Tier 1 is every def whose uppercase terms all belong to pure nullary enums (TFTP `KRRQ`, `KWRQ`,
`Idle`, `Transferring`, `Terminated`, …; ARP `Eth`, `Six`, `Req`, `Rep`). Tier 2 is the defs
touching payload sums (TFTP `DataPkt`, `AckPkt`, `ErrPkt`, `NoPacket`; ARP `Bound`, `Absent`,
`Silent`, `Broadcast`, `Unicast`).

## Plan summary

Ship (i) as two `[CT]` rows, not one.

**SPEC-AGREE-1a-1 (tier 1).** Thread the type-def environment into `reuseRetrieval`, build the
ctor tag map with the existing `buildCtorTagMap`, apply `desugarCtorValues` to both contracts
before `alphaNormalizeContract`, and narrow `ufBearing`'s two uppercase clauses to constructors that
are *not* pure-nullary-enum members. No declaration emission, no new `.fq` sections, no sort
changes: pure nullary enums become int tags exactly as the main VC path already treats them, so the
query stays in QF-LIA and the existing `typeToSortA` binder sorts (`FQInt`) stay correct. This is
the cheapest 4x in the corpus (10.6% → 40.0%) and it reuses two functions verbatim.

**Tier 1 has a hard precondition, and it is not optional: `signatureCompatible` must gain a
type-identity check before the desugar lands.** See risk 1, which is confirmed rather than
suspected, with a witness in the committed ARP artifacts. Sequencing the identity check after the
desugar ships a false-equivalence suggestion into the corpus.

**SPEC-AGREE-1a-2 (tier 2).** Thread `[FQDataDecl]` from `typeSorts` into `buildSubsumptionFQ`'s
`fqDataDecls`, add the ctor and selector symbols to `fqConstants` following the sweep at
`FixpointEmit.hs:586-588` (which already excludes ctor and selector names from the measure-constant
sweep, so the exclusion logic is written), then drop the remaining `ufBearing` clauses for
admissible sums. Keep the measure clauses (`string-length`, `list-length`, `first`, `second`, `ok`,
`err`) and `contractMentionsArrOp` abstaining: the array case needs the A2 component-splitting
discipline that `RefineReuse.hs:269-274` names, and the corpus histogram shows **zero** array and
zero measure abstentions, so neither blocks the published number.

For (ii), see the separability section. The recommendation is that it is a **third** row, gated on
tier 2 shipping, and that its own tier 1 is again int-tag encoding.

## Affected surface

Grouped by module, entry point first.

- `compiler/src/LLMLL/RefineReuse.hs:242-263` — `reuseRetrieval` signature gains the type-def
  environment (or an `AliasMap`-derived tag map). Caller update at `compiler/app/Main.hs:72`.
- `compiler/src/LLMLL/RefineReuse.hs:281-299` — `qfContract` / `ufBearing`, clause narrowing in both
  tiers. This is the only behavioral gate.
- `compiler/src/LLMLL/RefineReuse.hs:181-201` — `buildSubsumptionFQ` gains `fqDataDecls` and
  `fqConstants` population (tier 2 only).
- `compiler/src/LLMLL/FixpointEmit.hs` — **no change**. `typeSorts`, `desugarCtorValues`,
  `buildCtorTagMap`, and `exprToPred` are consumed as-is. Export list may need widening; check
  `:99` (`desugarCtorValues` is already exported) and whether `typeSorts` and `buildCtorTagMap` are.
- `compiler/src/LLMLL/Feasibility.hs:187-191, 199-208` — (ii) only; see below.
- `docs/llmll-ast.schema.json` — **no bump**. No node shape changes; `reuse_suggestions` is
  advisory output, not AST.
- `LLMLL.md` — no surface-form change. `reuseRetrieval` is advisory and non-blocking (REFINE-REUSE
  settled Rev 1), so no spec text moves.
- `docs/compiler-team-roadmap.md` — new rows needed (documentation-lead's edit, not mine).

## Separability of (ii) from (i)

**(ii) is separable in the code and dependent in the product.**

Separable in the code: `Feasibility.hs` is a different backend. It renders SMT-LIB and shells to
z3 (`:199-208, 218-226`); the subsumption path renders `.fq` and shells to liquid-fixpoint
(`RefineReuse.hs:205-214`). They share exactly one function, `exprToPred`, and **neither tier needs
to change it**, because it already lowers constructors. There is no edit in (i) that forces an edit
in (ii) or vice versa.

Dependent in the product: (ii) widens what a *witness* can render. Nothing consumes a constructor
witness until (i) tier 2 has unlocked constructor comparison, which is §6.2's own observation read
in the other direction. Shipping (ii) first produces a widened `baseSortText` with no reaching
caller, which is the dead-guard pattern `docs/UPDATE-PROTOCOL.md` D2 exists to catch. **Order (i)
then (ii); do not bundle them.**

Two cost notes specific to (ii), both of which cut against §6.2's framing that it is one item:

1. `minimizeWitness` needs **no work** for the enum case. It is already degenerate-safe: `null
   intNames` short-circuits at `:262` and `boundExpr` returns `Nothing` at `:273`. Its cost function
   is Σ|input| over Int inputs only, which is meaningless for a datatype sort, and the existing
   guards already skip it. `witnessOf` (`:283-284`) is sort-agnostic; it looks up a model string by
   sanitized name. §9's "with `witnessOf` extended to match" overstates the work: the extension
   needed is a **reverse tag map for rendering**, not a change to either function's structure.
2. `scriptOf` puts the return sort under a quantifier: `(assert (forall ((result <sort>)) …))` at
   `:204`, discharged with `(check-sat-using qsat)`. The comment at `:206-207` pins that tactic
   choice to LIA: "z3's complete quantifier-satisfaction tactic for LIA (hand-verified on the pinned
   z3 4.15.4 build; plain (check-sat) uses incomplete MBQI)." **Putting a native datatype sort under
   that binder leaves the envelope the comment documents.** Int-tag encoding of pure nullary enums
   stays inside it. This is the sharpest reason to make (ii)'s tier 1 int-tag encoding as well, and
   it is the professor question below.

## Verification impact

Neither tier changes program acceptance. `reuseRetrieval` is advisory: it returns
`[ReuseSuggestion]` consumed as `reuse_suggestions` with a non-blocking `W-REUSE`, and
`contractSubsumes` is fail-safe (`RefineReuse.hs:217-219`, "a solver hiccup degrades a suggestion,
never a program"). No obligation is added or discharged, no trust-closure edge moves, no function
changes body-faithful status, and `.fq` output for the verification channel is untouched because
`FixpointEmit` is not edited.

Fragment: tier 1 stays in QF-LIA by construction (int tags). Tier 2 introduces `data` declarations
into the subsumption `.fq` only, matching what the main channel already emits for the same types.

The one real risk is the inverse of a false-safe: a *wrong* suggestion. Widening from 3 defs to 21
widens the surface where an incorrect `subsumes` verdict could suggest reusing a contract that does
not actually subsume. Because the output is advisory, the blast radius is a bad suggestion to an
agent, not an unsound verdict. It still wants refute cruxes (test plan below).

## Performance budget

- **GHC fan-out**: `RefineReuse.hs` is imported by `Main.hs` and `test/Spec.hs` only, so
  recompilation is shallow. `FixpointEmit.hs` is 4508 lines and imported widely; leaving it
  unedited is worth protecting, and both tiers can.
- **Solver cost**: `reuseRetrieval` is O(spawned × pool) solver spawns, each a two-constraint `.fq`.
  Tier 1 takes the corpus from 3 gate-passing defs to 12, tier 2 to 21, so **spawn count rises
  roughly 7x at full scope** against today. Each spawn is a process launch plus a trivial solve;
  the dominant term is process startup, not solving. This runs on the `refine` path, not on
  `verify`, so it does not touch the sub-second `llmll check` target. If it bites, the mitigation is
  the existing exact-key tier at `:257-258`, which already answers without a solver.
- **`.fq` size**: tier 2 adds `data` and `constant` lines to a temp file that is deleted at
  `:212`. No user-visible artifact grows.
- **ProofCache / VerifiedCache**: unaffected, different path.

## Test plan

**I did not run `stack test` for this read.** The baseline must be measured on the merge base before
either row lands; the last figure recorded in the skill brief is 1424 Haskell examples and 106
Python (2026-07-28), and that is a citation, not a measurement I am making. Per the build-hygiene
rule, `(cd compiler && stack build --dry-run llmll)` must report "Nothing to build." before any
verdict in this area is trusted.

- `compiler/test/Spec.hs` already imports `buildSubsumptionFQ` directly, so the `.fq` shape is
  unit-testable without a solver. Add golden assertions that tier 1 emits **no** `data` section
  (proving int-tag desugar happened) and tier 2 emits exactly the decls `typeSorts` produces.
- Positive fixtures: one per tier drawn from the measured corpus, so the test asserts the same thing
  the harness counts. TFTP `sender-next-state` (tier 1, pure nullary enum states) and ARP
  `arp-merge` (tier 2, `Bound`/`Absent` payload sum).
- **Refute cruxes, the criterion that matters.** Without these the tests show only that the widened
  path does not crash. Tier 1 already has its crux written for it by risk 1: assert that
  `arp-request-hrd` (`() -> HwType`, `(= result Eth)`) and `arp-request-hln` (`() -> Len`,
  `(= result Six)`) are **not** reported `exact-equivalent`. That test fails on the naive tier-1
  desugar and passes once `signatureCompatible` compares type identity, so it is the gate on the
  precondition rather than a check added after the fact. Tier 2 needs its own pair where the ctor
  terms differ within a single payload sum.
- A `?$N`-style dead-guard check: assert that the narrowed `ufBearing` still fires on a payload-sum
  contract after tier 1, so tier 1 cannot silently admit tier-2 shapes.
- Regression: re-run `experiments/spec-agree-1/scripts/sigma_subsume.py` and update the pins in
  `manifest.json` and §0.3 in the same commit. The harness exits 1 on drift, which is how the
  republished fraction in §6.3(a)'s acceptance gets checked rather than asserted.

## Rollback

Single revert per row. Tier 1 is a guard narrowing plus a desugar call, tier 2 adds two record
fields' population. Neither is behind a flag and neither needs one: the output is advisory, no
persisted artifact changes shape, no `.verified.json` or cached `.fq` in a user environment is
affected, and there is no schema version to pin. Worst-case unwind is one `git revert` plus
restoring the `manifest.json` pins.

## Risks and unknowns

1. **Tag collision across distinct enums** (verification, tier 1). **CONFIRMED, with a witness in
   the committed corpus. This blocks tier 1 as naively described.**

   `desugarCtorValues` maps each constructor to its declaration index
   (`FixpointEmit.hs:2603-2604`), so unrelated enums all yield tags 0,1,2. In the main VC path a
   typed binder keeps them apart. In the bare subsumption `.fq` they do not stay apart, because
   `signatureCompatible` (`RefineReuse.hs:158-164`) compares **sorts, not types**:
   `typeToSortA aliases ta == typeToSortA aliases tb`. A pure nullary enum has no real payload, so
   `typeToSortA` falls through to `typeToSort` (`FixpointEmit.hs:2467`) and lands on `FQInt`
   (`:2441`). Every pure nullary enum in a program therefore has the same signature sort.

   The witness, both defs present in `experiments/rfc-swarm/runs/rfc826/implementation.ast.json`:

   | def | signature | post |
   |---|---|---|
   | `arp-request-hrd` | `() -> HwType` | `(= result Eth)` |
   | `arp-request-hln` | `() -> Len` | `(= result Six)` |

   `HwType = Eth \| HwOther` and `Len = Six \| LenOther` are both pure nullary enums, so `Eth` and
   `Six` are both declaration index 0. Zero params each, and both return sorts are `FQInt`, so
   `signatureCompatible` passes. Under tier 1's desugar both postconditions become `(= v 0)`,
   `canonicalContractKey` matches, and `reuseRetrieval` emits
   `ReuseSuggestion "arp-request-hrd" "arp-request-hln" "exact-equivalent"` without ever reaching
   the solver (`:257-258`). That is false: one clause fixes the hardware-type field to Ethernet, the
   other fixes the length field to six. RFC 826 lines 177-178 and 179-180 respectively.

   Note what this says about the current guard: `ufBearing` abstains on both defs today, so the
   shipped behavior is correct. The guard is doing real work here, not just deferring work.

   Fix, cheapest first: strengthen `signatureCompatible` to compare resolved type identity, not
   just sort, when the resolved type is a nullary enum. Safe against today's behavior because every
   def this would newly separate is currently abstained by `ufBearing`, so no shipped suggestion
   changes. The alternative, namespacing tags per type, is more invasive and would diverge the
   subsumption path's encoding from the main VC path's for no additional coverage.

   Bite: **blocks tier 1** until fixed. It does not block tier 2, which declares real `FQData`
   sorts and so keeps the types distinct by construction.
2. **`qsat` completeness outside LIA** (verification, (ii) tier 2). `Feasibility.hs:206-207` pins the
   tactic's completeness to LIA and to a specific z3 build. A datatype sort under the `forall`
   leaves that. Bite: complicates (ii) tier 2 and is the professor question below; does not touch (i).
3. **71.8% ceiling is citation-bound, not fragment-bound** (scope). 24 of 85 rows are cited by no
   clause. No amount of backend work moves them; only authoring does. Bite: only matters if
   §6.3(a)'s acceptance is written as an open-ended "rises", which would let the row be judged
   against an unreachable target.
4. **Solver spawn count rises ~7x** (performance). Quantified above; on the `refine` path, not
   `verify`. Bite: at scale only, with an existing mitigation.
5. **`typeSorts` and `buildCtorTagMap` export status** (build). `desugarCtorValues` is exported at
   `FixpointEmit.hs:99`; I did not confirm the other two. Bite: trivial, widens the export list.
6. **The measurement is a transcription, not the compiler** (spec-drift). §0's own provenance note
   says the figures should be re-derived through the real `classifyContractFragment`,
   `contractMentionsArrOp`, and `ufBearing` before publication outside the document. This read
   inherits that caveat: every figure above comes from the Python transcription in
   `experiments/spec-agree-1/`, which agrees with the code by inspection at
   `RefineReuse.hs:281-299` but has not been differentially tested against it. Bite: the tier split
   (9/9 defs) is the number most exposed, since it depends on payload detection the transcription
   does independently.

## Open questions for the professor

1. **Is type-identity the right separation criterion for nullary enums, or is sort-identity
   defensible with a different tag encoding?** Risk 1 is settled empirically: sort-identity is
   currently too coarse and admits a false `exact-equivalent` between `arp-request-hrd` and
   `arp-request-hln`. The engineering recommendation is to compare resolved type identity. The
   soundness question that remains is whether *nominal* type identity is what subsumption should
   want here, or whether two structurally identical enums declared under different names ought to
   compare. Contract reuse across a renamed-but-identical enum is exactly the case a retrieval
   facility might be expected to find, and nominal identity forecloses it.
2. **Is `(check-sat-using qsat)` still complete with a finite datatype sort under the `forall`
   binder at `Feasibility.hs:204`?** If yes, (ii) tier 2 is a rendering change. If no, (ii) is
   restricted to the int-tag encoding, and §6.2's "widening `baseSortText` to enum sorts" is
   achievable only in the tag sense, which in turn changes what §8's answer can assume about what a
   rendered constructor witness would even look like.
