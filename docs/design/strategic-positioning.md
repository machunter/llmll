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
