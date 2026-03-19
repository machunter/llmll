# Analysis: Leanstral and Its Impact on LLMLL v0.3

> **Status:** Discussion Draft  
> **Authors:** PhD Research Team  
> **Source:** [Mistral AI — Leanstral announcement](https://mistral.ai/news/leanstral)  
> **Related:** `LLMLL.md §14 v0.3` · `docs/project-management/roadmap.md`

---

## 1. What Is Leanstral?

Mistral AI has released **Leanstral**, described as *"the first open-source code agent designed for Lean 4."*

Key facts:
- **Architecture:** Sparse MoE, 120B total parameters / **6B active parameters** — fast and cost-efficient at inference time
- **License:** Apache 2.0 — freely usable in research and production
- **Interface:** Exposes an MCP (Model Context Protocol) server; designed to work with `lean-lsp-mcp`
- **Training objective:** Realistic formal repositories, not isolated math competition problems
- **Benchmark:** Outperforms Claude Sonnet 4.6 on formal proof tasks at **1/15th the cost** ($36 vs $549 per evaluation run)

Demonstrated capabilities:
- Migrating Lean code across breaking version changes
- Converting Rocq/Coq definitions to Lean 4 and then proving properties about them
- Handling unfamiliar API changes by reasoning from first principles

---

## 2. Direct Mapping to LLMLL v0.3 Roadmap

The LLMLL v0.3 roadmap contains this item verbatim:

> *"Proof agent: Specialist Lean 4 proof-synthesis agent; receives AST node + constraint; returns verified proof term."*

**That agent now exists and is open-source.** The v0.3 work-item shifts from a research deliverable to an **integration task**.

| LLMLL v0.3 Item | Previous Status | Status After Leanstral |
|---|---|---|
| Lean 4 proof-synthesis agent | Must be built | **Exists — integrate via API** |
| `?proof-required` hole resolution | Blocked on agent | Unblocked immediately |
| `llmll check` certificate verification | Must be designed | Route to Leanstral's verifier |
| Tactic library S-expression macros | Must be curated | Leanstral handles tactics natively — library becomes optional |

---

## 3. Integration Architecture

### 3.1 The `?proof-required` Hole Lifecycle

The existing `llmll holes --json` command (v0.1.2) already produces structured JSON for every unresolved hole. For `?proof-required` holes, the natural flow is:

```
llmll build
   │  encounters ?proof-required hole
   ▼
llmll holes --json  →  { "kind": "hole-proof-required", "constraint": "...", "type": "..." }
   │
   ▼
Leanstral MCP call  →  receives: LLMLL type + constraint predicate
   │                              translated to Lean 4 obligation
   ▼
Leanstral returns verified Lean 4 proof term
   │
   ▼
llmll check stores certificate alongside .llmll source
   │
   ▼
Subsequent llmll check verifies certificate without re-running Leanstral
```

### 3.2 MCP Integration Point

Leanstral was specifically trained for `lean-lsp-mcp`. The LLMLL compiler can call it as a MCP tool directly. No custom model fine-tuning needed:

```json
{
  "tool": "leanstral",
  "input": {
    "obligation": "theorem withdraw_safe : ∀ (b a : Int), b ≥ a → b - a ≥ 0",
    "context": "-- LLMLL def-logic withdraw with pre: balance >= amount"
  }
}
```

The compiler translates LLMLL's `(where [x: int] (>= x 0))` constraints into Lean 4 theorem statements automatically. Leanstral returns the proof term; the compiler stores it.

---

## 4. Impact on LLMLL Verification Strategy

### 4.1 The Two-Track Verification Model

Leanstral clarifies that LLMLL should operate on a **two-track verification model** rather than a single Z3-or-Lean4 choice:

| Track | Tool | When Used | Coverage |
|-------|------|-----------|----------|
| **Automated** | LiquidHaskell / Z3 (v0.2) | Quantifier-free linear arithmetic, regex predicates | ~80% of practical contracts |
| **Interactive** | Leanstral / Lean 4 (v0.3) | Inductive proofs, non-linear arithmetic, structural properties | The remaining ~20% |

Z3 handles what is decidable in polynomial time. Leanstral handles the `?proof-required` escalations that Z3 cannot decide. The LLMLL developer never interacts with either tool directly.

### 4.2 Acceleration Opportunity: Pull `?proof-required` Into Late v0.2

Since the hardest part of the Lean 4 agent — the model itself — is now given to the project for free, there is a strong argument to **pull `?proof-required` holes and Leanstral integration forward from v0.3 into late v0.2**:

- The Z3/LiquidHaskell layer (v0.2) and the Lean 4 layer (Leanstral) are architecturally independent.
- The `?proof-required` hole type can be added to the spec at the same time as `{base | predicate}` liquid types.
- Developers get *immediate* escalation coverage for hard predicates as soon as they start writing liquid-typed contracts.

---

## 5. Relationship to the Haskell Target Proposal

The Haskell target proposal (see `docs/proposals/proposal-haskell-target.md`) strengthens the case for this integration:

- Lean 4 and Haskell share deep conceptual roots: both are functional languages with dependent type aspirations. The translation from LLMLL's `(where [x: int] predicate)` constraints into Lean 4 theorem statements is significantly more direct from a Haskell IR than from Rust IR.
- LiquidHaskell (v0.2) and Leanstral (v0.3) now together form a **complete verification stack** that the LLMLL project does not need to build from scratch.

| Layer | Tool | What the team builds |
|-------|------|---------------------|
| Runtime assertions | GHC + LLMLL contracts | Pre/post assertion wrapping in codegen |
| Compile-time SMT | LiquidHaskell | Just the translation from LLMLL `where` to LH syntax |
| Interactive proofs | Leanstral (MCP) | JSON → Lean 4 obligation translation + certificate storage |

---

## 6. Recommended Actions

1. **Add Leanstral to the v0.3 roadmap explicitly** as the designated Lean 4 proof agent (replacing "to be built").
2. **Evaluate pulling `?proof-required` holes into v0.2** given that the agent is now available.
3. **Prototype the translation layer**: write a function in the compiler that converts a LLMLL `TypeWhere` AST node into a Lean 4 `theorem` statement. This is the only novel engineering work the integration requires.
4. **Budget:** At ~$36 per proof-engineering evaluation run, Leanstral is feasible as a free-tier API call for most research workloads.
