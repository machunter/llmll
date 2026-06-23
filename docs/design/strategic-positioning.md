# LLMLL — Strategic Positioning & Novelty Assessment

> **Source:** External review, April 2026  
> **Purpose:** What to emphasize, what to protect, what to stop overclaiming

---

## The One-Sentence Thesis

> **LLMLL turns programming into a constrained search problem over implementations, where the constraints are explicit, compositional, and partially machine-verifiable — and uses that as the substrate for multi-agent coordination.**

---

## What Is Genuinely Novel (protect these)

### 1. Verification as a coordination protocol

Not as a post-hoc filter — as **the interface between independent agents**. Agent A emits a contract, Agent B consumes it, the compiler enforces compatibility. This replaces conversational coordination with type-theoretic coordination. This is the core innovation.

### 2. Typed holes as distributed work allocation

Typed holes exist (Idris, Agda). Using them as **concurrency and decomposition primitives across agents** is new. `?hole : T` becomes a task with a formally specified contract, giving natural task boundaries, precise interfaces, and automatic dependency structure.

### 3. Trust-level propagation as first-class artifact

Other systems have `assume`/`sorry`/`axiom`. They do not **track and propagate epistemic uncertainty across the whole program**. Making uncertainty explicit, composable, and queryable — in a system where the authors (AI agents) are inherently uncertain — is a real step forward.

### 4. AST-level patching with verification gating

Structured patches to a typed AST, validated before merge. Fine-grained, deterministic, machine-native editing. Aligns with how LLMs actually operate (local rewriting, not file-level).

---

## What Is Borrowed (still valuable in composition)

| Idea | Source | LLMLL's contribution |
|------|--------|---------------------|
| Refinement types + SMT | Liquid Haskell, Dafny, F* | Integrating into an agent workflow |
| Lean integration | Standard for inductive proofs | Making it part of a tiered pipeline |
| Capability-based sandboxing | WASM, Koka | Tying it to agent-generated code |

---

## What Actually Improves AI Coding Outcomes

1. **Failure modes become visible instead of silent.** Even imperfect specs make bugs findable.
2. **Uncertainty becomes first-class.** "Asserted" vs "proven" — graded confidence, propagated. AI systems fail most dangerously when they appear confident but are wrong.
3. **Composable multi-agent development.** Types and contracts enforce composition. If this works at scale, it's the biggest practical win.
4. **Localized errors.** Exact AST node + structured feedback matches LLM strengths (local rewriting).
5. **Hallucination becomes search.** Generate → verify → reject/accept. Formally-filtered search, not unconstrained generation.

---

## What Is Overestimated (stop overclaiming)

| Claim | Reality |
|-------|---------|
| "Agents can write good specs" | Spec quality is the bottleneck, not code generation |
| "Verification solves hallucination" | It filters *some* hallucinations. Doesn't solve wrong specs, missing invariants, bad decomposition |
| "Small language removes training need" | Learning shifts from implementation to specification. Doesn't disappear |

---

## Target Domains (where LLMLL wins)

Domains where specs are natural, correctness matters, and composition is hard:

- **Financial systems** (regulatory constraints = contracts)
- **Protocol implementations** (RFCs = specifications)
- **Data pipelines with invariants** (schema compliance, data quality)
- **Safety-critical glue code** (verified interfaces between components)

### Bad fit:
- UI code
- Exploratory scripting
- Vague product logic

---

## The Strategic Bet

> **LLMLL implicitly bets that specifications matter more than implementations.**

If specifications become the bottleneck and the system makes specification quality visible and improvable, the bet pays off. If specification generation remains intractably hard for AI, the system's value is capped at domains where specs already exist externally (RFCs, regulations, standards).

---

## External Positioning (what to say)

### Don't say:
- "We solved verification"
- "We don't need training data"
- "Agents can write correct programs"

### Do say:
> **"We make AI-generated code composable, inspectable, and uncertainty-aware through explicit specifications and verification."**

---

## External Empirical Anchor — Constraint Decay (Dente et al., 2026)

> **Source:** Language-team revision, May 2026 — [`positioning-constraint-decay-proposal.md`](../archive/shipped-design-specs/positioning-constraint-decay-proposal.md) Rev 1 (settled 2026-05-25, professor review folded). This section was added on the spec-track promotion pass that followed the proposal's settlement; the rest of this document carries its original April 2026 external-review provenance unchanged.

### What the empirical anchor says (and doesn't say)

Recent empirical work measures the failure surface LLMLL's design premise targets. Dente, Satriani, and Papotti (arXiv 2605.06445, 2026) show that capable agent-model configurations on a fixed OpenAPI contract lose ~30 percentage points in assertion pass rate as non-functional constraints layer from L0 (functional spec only) to L3 (full structural constraints), with data-layer defects driving ~46% of agent failures. The fixed-contract premise is exactly the spec-source pathway LLMLL's design has bet on as its strongest near-term answer ([`specification-sources.md §1`](specification-sources.md), April 2026): when the contract surface is explicit, machine-readable, and external (OpenAPI, RFCs, NIST, ERC), the agent's task reduces to translation-plus-compliance rather than spec invention. Dente et al. measure what happens to translation-plus-compliance when the constraint stack grows; LLMLL's bet is that an explicit, machine-verifiable contract surface plus agent-loop integration around it shifts the failure curve measurably. This is the empirical anchor for the *input-shape half* of the pitch. The output-side claim — whether LLMLL's particular mechanisms reduce the measured failure — is an open empirical question we have not yet answered against their measurement set.

The anchor is part of a three-tradition citation triad to avoid single-source exposure on a 3-week-old preprint: program synthesis under specification complexity (Solar-Lezama, ASPLOS 2006; Alur et al., FMCAD 2013), LLM instruction-following under stacked constraints (Zhou et al., 2023 — IFEval), and verified-backend agent authorship under non-functional constraint layering (Dente et al., 2026). *Agent performance degrades monotonically as constraint complexity rises* is a recurring finding across three distinct research traditions; LLMLL targets the third.

### Candidate mechanisms (not differentiating capabilities)

None of the mechanisms below is a *differentiating verification capability* against the verified-language design-reference set. Liquid Haskell, F\*, Dafny, and Idris each have refinement types, capability-style enforcement, hole-driven elaboration, and tiered verification machinery, and have had them for years. LLMLL differentiates on *agent-loop integration of an existing verification surface*, not on the verification surface itself. The mechanisms below are how LLMLL composes that surface into an agent loop; they are not new verification primitives.

| Candidate mechanism | Status against current LLMLL surface | External register |
|---|---|---|
| Refinement predicates → constraint-shaped contract slots | Direction-of-fit. Scalar-shaped predicates over in-memory data are built; the SQL/ORM surface Dente et al.'s data-layer category measures is absent from LLMLL. | "A future direction; current refinement scope covers scalar invariants, not the SQL/ORM surface measured here." |
| Capability-typed effect rows → architecture-violation surface | Partial. CAP-1 catches reaches for undeclared IO capabilities at compile time. Project-architecture-convention violations (controller calls DB directly) are not enforced and would require a module-graph policy not currently specified. | "Compile-time error at the IO-effect seam; not at the controller/service/repository seam." |
| Typed holes with structured obligation reports → framework-idiosyncrasy slots | Direction-of-fit at small scale. OBLIG-0/1/2/3 shipped v0.10; demonstrated on banking-ledger / TOTP / hangman scale. Framework-conformance scale is unmeasured. | "Replaces guess-the-framework-idiom with constrained-search inside a contract-shaped slot; framework-scale evidence pending." |
| Three-channel obligation report → bounded-iteration convergence under structured feedback | Strongest mapping. Dente et al. report pass@1 collapse — the symptom of constraint-compliance failure absent corrective feedback. The three-channel obligation report supplies the corrective feedback signal, converting the same failure from a pass@1 problem into a pass@k convergence problem. | "Converts unbounded-divergence agent behavior under stacked constraints into bounded-iteration convergence under a structured compile-time feedback signal." |

The fourth row is the strongest direction-of-fit mapping. Note the metric reframing: pass@1 is the *symptom* the paper measures, not the metric LLMLL is engineered to address. The three-channel obligation report is designed for iteration, and the natural dependent variable for its claim is bounded-iteration convergence — pass@k under a repair-loop budget — aligning with [`empirical-methodology.md`](../../experiments/methodology.md)'s settled commitment that demotes first-round-only measurement to "one regime among several."

### Vocabulary discipline for external register

Reserve "stratified verification" for project-internal docs. In external register, use "three-channel obligation report" or "tiered verification." "Stratified" is overloaded in the broader PL literature (predicative type theory, Martin-Löf universe hierarchies, stratified negation in logic programming) and will misparse for external PL readers.

### What this section does *not* claim

It does not claim that LLMLL has empirically beaten Dente et al.'s measurement set; running their Conduit benchmark on LLMLL is a recorded deferred experiment, treated in [`language-comparison-experiments.md`](language-comparison-experiments.md) §"Deferred External Benchmarks." It does not claim that the verification machinery is a differentiator; the design-reference set has had the machinery for years. It does not claim that the paper validates the *solution* side of the pitch — only that it validates the failure-mode side.
