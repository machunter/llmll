# Decisions

> **Provenance note.** No ADR-typed document was present in the ingest set (18 docs: 12 SPEC, 6 DOC).
> No document in the set carries an ADR `Accepted`/locked status, so **zero decisions are LOCKED**.
> The entries below are decision statements the source documents themselves record as decided,
> declined, deferred, or adjudicated. Every entry is `status: proposed` because no locked authority
> exists in this set. Absent fields are omitted rather than inferred.
>
> **Re-run note.** All 18 docs are synthesized; `docs/design/rfc-swarm-playbook.md` and
> `docs/design/spec-from-rfc-pipeline.md` are no longer withheld. Where the two disagree, the
> playbook governs, by both docs' own declaration and by the manifest precedence that transcribes it.
> `docs/design/spec-agreement-proposal.md` is read at HEAD as **Rev 1**; decisions extracted from
> Rev 0's withdrawn §1 and §6 have been replaced.

---

## Acyclicity policy for `refine` cycle-creating spawns — Option 3
- source: docs/compiler-team-roadmap.md (Future, Cascading Refinement)
- status: proposed (DECIDED, Option 3)
- decision: `refine` admits a cycle-creating spawn, detects the cycle, and degrades its members to contract-only, with the trust meet floored so nothing is laundered (the `letrec` partial-correctness treatment, `LLMLL.md §5.3.5`). A discharging `(decreases …)` measure on the cycle members upgrades the cycle to total (R7 strict-descent, shipped v0.14.25/27).
- scope: `refine` op, cascading refinement, cycle admission, trust meet

## Evaluation-integrity rule — the checkout brief is the sole information channel
- source: docs/compiler-team-roadmap.md (Future, Data Scope Extension, standing rule); docs/design/data-scope-extension.md (Post 8); docs/design/rfc-swarm-playbook.md §1
- status: proposed (standing rule)
- decision: For every example built on the data-scope track, and for every fill agent in an RFC-SWARM wave, the `checkout` brief is the sole information channel. Neither a failure is forced nor a hint leaked beyond the returned contract (pre/post goal, expected return type, in-scope bindings, callable contracts). The playbook states the same rule for the wave: fill agents get no reference solution, no hints, no sight of one another's attempts, and no forced failures, and their isolation is the demonstration.
- scope: example construction, blind-fill agent protocol, evaluation integrity

## CDP default-on — deferred, not pursued
- source: docs/compiler-team-roadmap.md (Active Items, CDP default-on row)
- status: proposed (DEFERRED, nice-to-have, not pursued)
- decision: `--cdp` / `--weakness-check` / `--spec-coverage` are not promoted into the default serious-verify path. All preconditions closed by v0.14.4 and wall-clock characterized (roughly 2-3x verify time on modules with candidates). Flipping the default was considered and deferred on cost/UX grounds; the `--strict-verify` opt-in is preferred. Revisit if a concrete need emerges.
- scope: verify CLI defaults, diagnostic surface

## Full categorical unification — declined
- source: docs/compiler-team-roadmap.md (Research track); docs/design/critique-2026-05-23-triage.md §3.2, §5
- status: proposed (Declined)
- decision: The full categorical apparatus (fibrations of refinements, graded monads, patch-merge invariant derived as a functoriality law) is rejected as disproportionate per professor adjudication. The patch-merge invariant stays **stipulated**. The narrower unification is adopted instead: contracts form a preorder under implication, denotation maps contracts to subobjects of a finite behavior space, and DP is a valuation on that subobject lattice.
- scope: research track, DP formalization (DP-FORM-1), patch-merge invariant

## Path B mechanized soundness theorem — declined
- source: docs/compiler-team-roadmap.md (Research track); docs/design/critique-2026-05-23-triage.md §5
- status: proposed (Declined)
- decision: A mechanized soundness theorem against an independently-defined operational semantics is explicitly declined; the Path A stance from `verification-debate.md` is inherited.
- scope: metatheory, soundness argument

## Refinement metatheory framing — adopt the amended critic's checking-mode framing
- source: docs/design/critique-2026-05-23-triage.md §3.1
- status: proposed (Adjudicated)
- decision: Adopt the checking-mode-only framing with explicit non-goals (no general refinement subtyping, no dependent pattern matching, no type-level computation, no proof terms, no sigma types, no boolean-expression-as-type-equality) over the Vazou-style subtyping framing. The two are operationally equivalent; the narrower framing matches LLMLL's actual surface and pre-empts implicit Vazou-closure scope creep.
- scope: refinement metatheory of record (REF-META-1), `LLMLL.md §3.4 / §5`

## Integer semantics — adopt option (a); `MachineInt` stays post-freeze
- source: docs/design/critique-2026-05-23-triage.md §4 (Q1 row, INT-PRE / INT-1 / INT-2 / INT-3)
- status: proposed (Adopted; INT-1/INT-2 shipped, INT-3 dormant)
- decision: Adopt integer-semantics option (a). `MachineInt` (INT-3, QF-BV alias) stays a dormant P3 item; INT-PRE cleared the cost gate at 1.015x against a 5x threshold, so INT-3 promotes to P1 only if a future cost gate fires.
- scope: integer semantics, INT-1/INT-2/INT-3

## `sha1` / `hmac-sha1` rename to `_stub` — declined
- source: docs/design/critique-2026-05-23-triage.md §5 (CRYPTO-1)
- status: proposed (Declined)
- decision: The symbols are not renamed. The spec contract is standards-grade (RFC 2104 / FIPS 180-4); stub status is an implementation concern, handled instead by CRYPTO-1's trust-tier annotation (`asserted-with-stub-backend`).
- scope: crypto primitives, naming, trust-tier annotation

## The if-join wildcard preference beyond self-recursion — one requirement, RET-RESOLVE SC3'
- source: docs/design/ret-resolve-proposal-review.md (Round 1, finding 1, lines 19-27); docs/design/ret-branch-pref-proposal.md (Rev 0, Stage 1 / Stage 2); docs/design/ret-resolve-proposal.md (Rev 2, SC3'); docs/design/ret-branch-pref-proposal-review.md (Recommendation, "Ruling on the recorded divergence")
- status: proposed (adjudicated at synthesis; reversible, see INFO in `.planning/INGEST-CONFLICTS.md`)
- decision: The general form of the if-join concrete-branch preference ships as **RET-RESOLVE SC3'**: a sandboxed verification-facing pass, conditioned on same-SCC membership, where acceptance is unchanged by construction, gated on a byte-identical `.fq` across all 128 corpus files. The type-channel **RET-BRANCH-PREF Stage 2** variant (two diffs, type-channel strictness) is not carried forward as a separate requirement. Authority: the professor review's Round 1 finding 1 classifies the unconditioned if-join preference as "soundness-adjacent" and recommends conditioning on same-SCC membership, "which generalizes Stage 1's self-call condition to its natural boundary", citing Milner 1978, Damas and Milner POPL 1982, and Jones, *Typing Haskell in Haskell*, Haskell Workshop 1999 §11; the same finding notes this makes the SCC decomposition necessary and gives a one-pass algorithm in reverse topological order. **Prior scope:** Stage 1 shipped v0.14.72 for self-recursion only.
- scope: `inferExpr (EIf …)`, RET-RESOLVE SC3', RET-BRANCH-PREF Stage 2, SCC-conditioned preference

## RET-BRANCH-PREF — build Stage 1 narrowed to self-recursion
- source: docs/design/ret-branch-pref-proposal.md (Rev 0, SETTLED); docs/design/ret-branch-pref-proposal-review.md (Recommendation)
- status: proposed (SETTLED; Stage 1 shipped v0.14.72)
- decision: The if-join concrete-branch preference fires **only** when the other branch is a self-recursive call, which makes the rule a least-fixpoint step rather than a guess. The professor's soundness classification of the unrestricted rule was withdrawn and reclassified to **scope** after measurement.
- scope: `inferExpr (EIf …)`, type inference, FQ-RESULT-SORT-1 residual

## LEAN-GA — scoped but deferred; T-B (server-as-checker) is the trust-correct transport
- source: docs/design/leanstral-integration-scope.md §4, §6
- status: proposed (Rev 0 scoping note; explicitly not a commitment to build)
- decision: LEAN-GA is a three-layer rebuild (translator, routing, transport), not a next-sprint integration. Transport shape **T-B** is adopted as trust-correct: the Leanstral model produces a candidate proof and `lean-lsp-mcp` only checks it (accept iff zero errors, zero open goals, no `sorry`). Sequencing: translator rewrite, then routing rework, then T-B transport. Hold the C-property marketing claim until layers 1-3 are real.
- scope: LEAN-GA, obligation translation, obligation routing, MCP transport, PROOF-ARTIFACT C-property

## SPEC-AGREE-1 scope — the instrument's domain is `Sigma_subsume`, computed per contract
- source: docs/design/spec-agreement-proposal.md Rev 1 §1, §0.4 (M-1, M-2)
- status: proposed (Rev 1; scope settled by measurement)
- decision: SPEC-AGREE-1 runs over the **full `Encoded` denominator** and emits per row one of `{equivalent, ordered, incomparable, not-comparable}`. `not-comparable` is decided by `qfContract` on that row's contracts and the row **remains in the denominator**. It is therefore **not** a pipeline stage amending stage K for all rows, because at 10.6% it cannot discharge stage K's obligation, and **not** class-scoped, because class and fragment partition the same set independently (M-2: of TFTP's ten `Encoded` C2 rows, five are comparable and five are not; ARP has zero `Encoded` C2 rows while two comparable C3 rows sit undecided). The comparable fraction is a first-class published output. Rev 0's §1 applicability claim ("applies to every `Encoded` row") is **withdrawn**.
- scope: SPEC-AGREE-1, `Sigma_subsume`, `qfContract`, `Encoded` denominator, `not-comparable`

## SPEC-AGREE-1 — the constructor-capable backend is in scope, ahead of the harness, with no Lever A dependency
- source: docs/design/spec-agreement-proposal.md Rev 1 §6.1, §6.3, §0.4 (M-3)
- status: proposed (Rev 1; answers the review's Q2)
- decision: The constructor-capable comparison backend is **in scope for this track**, **re-sequenced ahead of the N-way harness**, and carries **no Lever A dependency**. M-3: all 18 measured abstentions fire on `ufBearing`'s uppercase-head clauses; none fires on `contractMentionsArrOp` and none on a measure, so the A2 component-splitting discipline is not implicated on this evidence. Build order: (a) constructor backend, (b) effective-contract comparison plus three-valued verdicts, (c) comparison CLI with product position and difference query, (d) the two-arm gloss experiment, (e) N = 3 with adversarial framings. Each step has standalone value, so the sequence degrades gracefully if it stops early. Effort corrected from Rev 0's "`[CT]` small" to **`[CT]` medium-to-large**.
- scope: SPEC-AGREE-1, comparison backend, build order, effort estimate

## Majority voting on formalization disagreement — explicitly rejected
- source: docs/design/spec-agreement-proposal.md Rev 1 §3 step 6
- status: proposed (Rev 1)
- decision: Disagreement between independent formalizations is adjudicated against the verbatim source text with a machine-generated witness, never by vote. Majority voting hides the disagreement and can certify a shared error. Brilliant, Knight and Leveson's consistent comparison problem gives the second ground, that all-correct versions can disagree at a voter.
- scope: SPEC-AGREE-1, contract agreement, adjudication procedure

## Agreement reporting — detection yield, never an unstratified rate
- source: docs/design/spec-agreement-proposal.md Rev 1 §3 (Reporting rule), §4; docs/design/spec-agreement-review.md F-8
- status: proposed (Rev 1; F-8 adopted without qualification)
- decision: Never publish an unstratified agreement rate. The headline is the count and per-row list of `Encoded` rows where witness adjudication changed the frozen contract, as a fraction of rows that reached comparison, published beside the `not-comparable` count and the measured comparable fraction. That is detection yield rather than concordance, and weak contracts cannot inflate it. Agreement figures, where reported at all, are stratified by discriminative power. Rev 0's "agreement rate as a headline measurement" is **withdrawn**.
- scope: SPEC-AGREE-1, reporting discipline, detection yield

## RFC-SWARM target — TFTP (RFC 1350 + RFC 1123 §4.2.3.1) ratified
- source: docs/design/rfc-swarm-roadmap-proposal.md (Rev 1.1, §2.5); docs/design/rfc-swarm-playbook.md §3 anti-pattern 2
- status: proposed (target user-ratified 2026-07-24; Phase 0 complete)
- decision: RFC 1350 (TFTP, revision 2) with the RFC 1123 §4.2.3.1 amendment is the ratified RFC-SWARM target. Standing rule: do not widen `Sigma_auto` to rescue a target; halt and re-target instead. The playbook quantifies the rule on the first run: new language features would have recovered 3 rows out of 58, and the interactive-prover tier would have recovered **zero**. Let wave telemetry, not anticipation, promote residues.
- scope: RFC-SWARM, target selection, scope freeze

## Gate J — the exclusion-ratio ceiling is retired; three conditions replace it
- source: docs/design/rfc-swarm-playbook.md stage J, stage C
- status: proposed (Rev 0, derived from the TFTP execution)
- decision: Do not use an exclusion-ratio ceiling. A ratio of `excluded / total` tracks `(C4 + C6) / total`, which measures the genre composition of the target document, not the reach of the verifier; every complete protocol specification carries transport binding, timers, and deployment prose that add denominator and can never add numerator, so a ratio ceiling is unsatisfiable by any of them and fires before a single scoping judgment has been made. Compounding it, stage C's conservative "when in doubt, mark normative" tie-break deliberately over-includes, which makes the denominator safe and the exclusion *ratio* meaningless. Three conditions replace it: (1) class-stratified coverage, reported and not thresholded; (2) the characteristic-core invariant, no core row may disposition out, which is the condition that decides the target; (3) a closed barrier list, with a STOP if any row is excluded for a reason outside it. TFTP: 95.4% of verifiable subject matter carried, 15/15 core Encoded, zero unclassified exclusions; the retired ratio would have failed at 46.8%.
- scope: RFC-SWARM gate J, exclusion ratio, class-stratified coverage, closed barrier list

## The `B7` already-entailed exclusion rule — rewritten after RFC 4648
- source: docs/design/rfc-swarm-playbook.md stage G (Amendment 1, 2026-07-27)
- status: proposed (Amendment 1)
- decision: A row that is already entailed is not covered, and is excluded under `B7` naming what entails it. The earlier form asked whether "no mutant can exercise the row", which is undecidable in general and was shown false by probe on the very row that fired the gate. Two limits now bound the rule: `B7` requires an entailment you can **name**, not an absence you could not think past; and `B7` applies only to rows whose obligation the model can express, so a row that cannot be stated at all exits under the barrier naming why, and the existence of a weaker surrogate that *is* statable and vacuous does not convert it. Weakening a clause until it is vacuous and then excluding it for vacuity is the failure the rule exists to prevent. Companion rule: a row may be `Encoded` only if you can name the shape of the contract that carries it.
- scope: RFC-SWARM stage G, disposition rules, `B7` barrier

## The clause-carrying freeze is scoped, not blanket
- source: docs/design/rfc-swarm-playbook.md stage L
- status: proposed (Rev 0)
- decision: After the coverage lint, freeze the clause-carrying surface, scoped: root contracts bearing `:source` are immutable, while `refine`-spawned sub-contracts are additive, carry no `:source`, and are governed by the shipped spawn gates. `refine` grows the contract surface by definition, so a blanket freeze would forbid the mechanism the wave depends on. Weakening a spawned contract makes the root's obligation *harder* to discharge, not easier, so there is no laundering path from the spawn channel into the clause layer.
- scope: RFC-SWARM stage L, contract freeze, `refine` spawn gates

## Stale-binary detection — ask the build tool, not the version string and not mtimes
- source: docs/design/rfc-swarm-playbook.md §3 anti-pattern 4
- status: proposed (Rev 0, measured)
- decision: `stack exec llmll` resolves to a stale binary from some working directories, and the version string is not sufficient: it moves at a release cut while compiler source moves whenever someone commits (on 2026-07-28 a parallel session shipped `FQ-RESULT-SORT-1` stages (a) and (b) across five source files with the cut deliberately deferred; `llmll version` reported `0.14.71` before and after). Use `(cd compiler && stack build --dry-run llmll)`; "Nothing to build." means current, anything else means the binary predates a source change and every verdict it produced is suspect. **Do not compare mtimes**: `find compiler/src -newer <binary>` is wrong about correct input, measured rather than reasoned, because a `git checkout`, a branch switch or a stash pop rewrites a file's mtime without changing its content, Stack correctly rebuilds nothing, and the binary stays older than a source file it is up to date with.
- scope: build hygiene, gate reporting, `stack build --dry-run`

## The two-call pre-flight RFC screen — retired
- source: docs/design/rfc-swarm-target-selection.md §3, §5
- status: proposed (Rev 1; retired the same day it was written)
- decision: The `--preflight` mode and its two prompts are removed rather than shipped. It rejected seven of seven targets including both that reached the wave; the carried fraction inverts what it would need to track (77% for the target known to stop, 52% for one known to pass). The failure is structural: stage F **selects** a core from a reconciled census while the pre-flight **generates** one from prose. The tempting repair (telling the core-naming agent not to call format rows characteristic) is the circularity blindness exists to prevent, so **the repair is not available**. Replacement: run the real stages `--only A,B,C,D,E,F,G,G2,J` and stop at the gate.
- scope: RFC target screening, gate J, stages A-J

## R8 re-verify slice — the singleton `{F}`
- source: docs/design/incremental-reverify-r8-proposal.md (Rev 0); docs/compiler-team-roadmap.md (R8 row, SHIPPED v0.14.61)
- status: proposed (Rev 0 design settled; implementation shipped v0.14.61)
- decision: The sound-and-complete re-verify slice for `llmll patch` is the singleton `{F}` (the patched function). No callee slice and no staleness-recheck are needed, because `patch` fills only body-position holes (contracts never change) over assume-guarantee-modular VCs. Type-checking stays whole-module; only the SMT body-VC step is sliced. Fail-safe to whole-module on any unresolvable patch.
- scope: `llmll patch`, `PatchApply.reVerify`, body-VC emission

## Contract-position reads — status quo plus a scoped lint (disposition (c))
- source: docs/compiler-team-roadmap.md (Lever A row, language-team dispositions SETTLED 2026-07-12; CONTRACT-READ-LINT row)
- status: proposed (SETTLED 2026-07-12)
- decision: Contract-position reads are total selects, sound in both directions; the disposition is status quo plus a scoped non-blocking `contract-read-oob` lint on the decidable slice. The v1 `bytes-zero` context rule is blessed. Deferred: the `map-get`-without-`map-has` heuristic tier and the Dafny-style well-formedness side-obligation.
- scope: Lever A arrays, contract-position reads, CONTRACT-READ-LINT

## `:source` C4 provenance stays an unchecked reason-string convention (gap G3, accepted)
- source: docs/design/spec-from-rfc-pipeline.md §S3, §6 (G3 row)
- status: proposed (accepted, no owner)
- decision: `weakness-ok` functions have no `pre`/`post` to suffix, so RFC provenance for C4 opaque-primitive clauses lives in the reason string. This is a convention, not a checked channel; the trust report cannot distinguish an RFC-cited reason from a free-form one. Accepted at current scale and recorded as the boundary of what the §2 audit can lean on. Revisit only if an auditor consumer materializes.
- scope: `:source` provenance, C4 opaque primitives, `weakness-ok` reason strings
