# Empirical Methodology and the One-Shot Correctness Criterion

> **Status:** Design draft (2026-05-11)
> **Purpose:** Resolve an internal contradiction in `docs/compiler-team-roadmap.md` between the governing design criterion (line 6) and the v0.10 success metric (line 98), and establish the empirical-methodology framing that downstream experiment design (notably a verification-guided repair-loop experiment) can cite as authority.
> **Origin:** Routed by the `professor` skill (plan dated 2026-05-11, Open Question #1) as the antecedent to a repair-loop experiment design pass by `experiment-lead`.

---

## Diagnosis

The roadmap's governing design criterion at [docs/compiler-team-roadmap.md:6](../compiler-team-roadmap.md#L6) reads:

> *Every deliverable is evaluated against one-shot correctness — an AI agent writes a program once, the compiler accepts it, contracts verify, no iteration required.*

The v0.10 success metric at [docs/compiler-team-roadmap.md:94-98](../compiler-team-roadmap.md#L94-L98) reads:

> *Can a simple repair loop fill common holes using only the structured obligation report, without hidden compiler knowledge?*

Both statements are simultaneously in force. They contradict on a load-bearing point: the first disclaims iteration, the second names a repair loop as the success metric. The contradiction has been latent because the success metric was internalized by the compiler team while the criterion was inherited by the empirical apparatus.

The contradiction has produced two downstream effects:

1. The minimal-agent harness ([experiments/minimal-agent/README.md:209-221](../../experiments/minimal-agent/README.md#L209-L221)) implements the criterion's stop-policy reading literally: *"This keeps the measurement focused on first-round effectiveness rather than repair-loop effectiveness."* The harness consequently cannot exercise the regime in which v0.10's deliverables (OBLIG-3 EMatch branch obligations, OBLIG-4 repair suggestions, OBLIG-5 repair loop integration) most plausibly produce value.
2. The v0.10 deliverables themselves — every OBLIG- item is an iteration aid — sit inside a roadmap whose top-line criterion text disclaims them. A reader new to the project encounters an apparent contradiction the project has not internally resolved.

This is in-document spec drift. The language-team is in the natural position to catch and resolve it.

## The criterion conflates two distinct claims

The text at line 6 is doing two jobs that should be separated.

**(D) A design criterion for compiler deliverables.** Each release should move LLMLL closer to one-shot agent success. The test of a feature is whether it reduces the iteration burden, increases obligation completeness, or shortens the repair distance. The OBLIG-B benchmark operationalizes this claim concretely: a feature whose value is invisible to a simple repair loop is not pulling its weight against the criterion. This is the right governing criterion, it is load-bearing for the roadmap's structure, and it should be preserved.

**(M) A methodology criterion for empirical instruments.** Measurement should be a single attempt with no iteration. This was never the criterion's intent — OBLIG-B violates it directly, and [docs/design/strategic-positioning.md:50](strategic-positioning.md#L50) states the value claim as *"Hallucination becomes search. Generate → verify → reject/accept. Formally-filtered search, not unconstrained generation,"* which is iterative by definition. (M) is an artefact of the wording, and the harness has inherited it.

(D) is the criterion the project means. (M) is the criterion the text accidentally states. The revision below disambiguates them.

## Proposed roadmap-text revision

Replace [docs/compiler-team-roadmap.md:6](../compiler-team-roadmap.md#L6). The proposed text:

> **Governing design criterion:** Every compiler deliverable is evaluated against *progress toward one-shot correctness* — does this release reduce the iteration burden, increase obligation completeness, or shorten the repair distance for an AI agent producing LLMLL code? The intended terminal state is that an agent writes a program once, the compiler accepts it, contracts verify. We measure progress toward that state empirically, including via repair-loop experiments where the verification surface's iteration aid is the dependent variable. First-round measurement is one such empirical regime; it is not the only one, and it is not load-bearing for every feature.

The revision:

- Preserves (D) as the design criterion ("progress toward one-shot correctness").
- Preserves the terminal-state aspiration ("an agent writes a program once, the compiler accepts it, contracts verify").
- Eliminates (M) as a reading by explicitly endorsing repair-loop experiments as a measurement regime.
- Demotes first-round measurement to one regime among several, which is what the OBLIG-B benchmark already presupposes.

The revision is text-only. It sits inside the feature freeze at [docs/compiler-team-roadmap.md:26-31](../compiler-team-roadmap.md#L26-L31) (no new builtins, syntax, FFI, WASI, or orchestration features). No clause of [LLMLL.md §5.3.3 / §5.3.5](../../LLMLL.md) is affected. No SMT obligation is introduced. No JSON-AST node shape changes. The compiler is untouched.

## Downstream textual change

After the criterion lands, the *Stop Policy* section of [experiments/minimal-agent/README.md:209-221](../../experiments/minimal-agent/README.md#L209-L221) needs a one-paragraph clarification: the minimal-agent harness measures first-round effectiveness *as one empirical regime*, and is sibling-compatible with repair-loop instruments designed under the revised criterion. This is documentation-lead's slot, downstream of the roadmap revision.

## On novelty-claim ranking (Open Question #2)

The professor's plan asked which of the four novelty claims in [docs/design/strategic-positioning.md:14-31](strategic-positioning.md#L14-L31) is load-bearing for external positioning vs. aspirational. The language-team's reading of the artefacts:

- **Aspirational headline.** Claim 1 — *verification as a coordination protocol between independent agents.* This is the lead sentence in `strategic-positioning.md:16-18`, and *"composable"* is the first adjective in the external positioning line at [strategic-positioning.md:96](strategic-positioning.md#L96). The cross-agent contract interface is not yet built; the apparatus to host coordination experiments lives in [agent-orchestration.md](agent-orchestration.md), status *design draft*.
- **Operationally built.** Claim 2 — *typed holes as distributed work allocation* — is operationalized by OBLIG-0/1/2/3 ([roadmap.md:85-89](../compiler-team-roadmap.md#L85-L89)). Claim 3 — *trust-level propagation* — is operationalized by the v0.8.1b evidence model and the trust column of the three-channel report at [roadmap.md:79](../compiler-team-roadmap.md#L79).
- **Aspirational substrate.** Claim 4 — *AST-level patching with verification gating* — is gated on module-system codegen and orchestration work, not yet started.

Consequence for experiment sequencing: the professor's recommended order (repair-loop and differential-spec experiments first, coordination experiments later) is correct. Empirical instruments should measure what is built before they measure what is aspirational. Coordination experiments require multi-agent apparatus that does not exist; repair-loop and differential-spec experiments pull on built infrastructure — verifier output, obligation reports, trust tiers, the three-channel report.

This ranking is not encoded in any current design document. Capturing it here preserves the rationale for future archeology and gives the experiment-lead an explicit ordering to cite when sequencing experiments.

## Edge cases

The revised criterion must remain coherent across these regimes:

1. **First-round regression-sentinel experiments.** The minimal-agent harness as currently structured — closed task, first-error stop policy, measuring whether a v0.x.y release broke first-round ergonomics. Under the proposed criterion: first-class, explicitly preserved as *"one such empirical regime."* This is the role the harness should be repositioned to under the professor's plan, Move 1.
2. **Features whose value is overwhelmingly iterative** (EMatch counter-examples at OBLIG-3, weakness-check, repair suggestions at OBLIG-4, the repair loop itself at OBLIG-5). Under the current line-6 wording, technically disclaimed. Under the revised criterion, explicitly endorsed as "iteration aid" — the value claim is now legible.
3. **Repair loops that do not converge.** An agent iterates under a fixed budget and never satisfies the verifier. Under the revised criterion: divergence rate is part of the signal, not a methodological failure. The criterion does not need to enumerate this case; it only needs to not forbid measuring it, and the proposed text does not.
4. **Mixed-regime experiments.** An instrument that records both first-shot acceptance and repair-loop convergence on the same agent/task. Under the revised criterion: legitimate. The text uses *"including via repair-loop experiments,"* not *"instead of first-round."*
5. **Future coordination experiments** — two agents handing contracts to each other. Under the revised criterion: permitted, but the criterion is not the bottleneck. The bottleneck is apparatus, addressed downstream in [agent-orchestration.md](agent-orchestration.md).

## Risks

1. **Reading the revision as license to defer ergonomic features to iteration.** The freeze policy at [roadmap.md:26-31](../compiler-team-roadmap.md#L26-L31) independently bounds scope through v0.10. The revision's *"intended terminal state is one-shot"* clause preserves (D) as the design intent. A feature with zero first-shot value would still fail the design criterion after revision. Severity: low.
2. **Empirical regimes drift apart without a unifying axis.** If repair-loop, first-round-regression, and differential-spec experiments each ship with different metrics, results cannot be compared. Recommendation: the assurance-score rubric proposed in [language-comparison-experiments.md:213-226](language-comparison-experiments.md#L213-L226) is the shared dependent variable across all empirical instruments. This is a constraint for the experiment-lead's next turn. Severity: medium.
3. **External re-reads.** The revision could be read as *"LLMLL admits it needs repair loops to work."* But the current external pitch at [strategic-positioning.md:50](strategic-positioning.md#L50) is already *"hallucination becomes search,"* and search is iterative. The revision aligns the internal text with the already-public external framing. Address presentationally in the CHANGELOG entry. Severity: low-to-medium.

## Hand-off

The proposal implies no compiler work. The verifier, type checker, parser, JSON-AST schema, contract translation, and obligation pipeline are untouched. The hand-off is **spec-track**, directly to `documentation-lead`:

1. Promote the proposed text into [docs/compiler-team-roadmap.md:6](../compiler-team-roadmap.md#L6).
2. Update the *Stop Policy* section in [experiments/minimal-agent/README.md:209-221](../../experiments/minimal-agent/README.md#L209-L221) per the *Downstream textual change* section above.
3. Add a CHANGELOG entry under Process or Roadmap describing the criterion disambiguation and citing this draft.
4. Optionally add a one-line entry to [docs/design/INDEX.md](INDEX.md) under a new *Empirical Methodology* group or under *Future Infrastructure* alongside `language-comparison-experiments.md`.

The `experiment-lead` skill is unblocked on the repair-loop experiment design once the documentation-lead has landed the criterion revision. The downstream design will cite this draft and the revised roadmap criterion as authority. The `compiler-engineer` is not in this chain unless the repair-loop experiment subsequently surfaces a verifier diagnostic-surface ergonomics gap.

## Open questions

1. Should this draft acquire a paired professor review (`empirical-methodology-review.md`) before promotion, on the model of `invariant-discovery-proposal.md` + `invariant-discovery-review.md`? The professor has already weighed in on the upstream question (the plan dated 2026-05-11), so a separate review may be redundant; the user adjudicates.
2. Should the novelty-claim ranking discussion be split out into its own design note (e.g., `novelty-claim-ranking.md`) rather than living inside this methodology doc? Argument for splitting: the ranking is reused by experiment sequencing decisions beyond the criterion revision. Argument against: it is short and tightly coupled to the empirical sequencing argument here. Defer to user.
