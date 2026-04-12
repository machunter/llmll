# Where Do Good Specifications Come From?

> **Source:** External critique of "no training data" argument, April 2026  
> **Status:** Open research question — informs roadmap and orchestrator design

---

## The Core Problem

LLMLL shifts the difficulty of AI code generation from **implementation** to **specification**. The system verifies that code satisfies its contracts — but the quality of the verification is bounded by the quality of the contracts. Where do good specifications come from?

### Capability Breakdown

| Stage | LLM ability without LLMLL training data | Notes |
|-------|----------------------------------------|-------|
| Syntax generation (JSON-AST) | Strong | Schema-constrained, ~20 constructs |
| Type-directed hole filling | Moderate | Constrained by type context, iterate on errors |
| Specification generation | **Weak** | Invariant discovery, spec minimality |
| System decomposition | Weak–Moderate | Choosing the right typed holes |
| Proof construction | Weak (except trivial) | Inductive reasoning gap |

The hard problems are spec generation and decomposition. These are **inductive reasoning tasks**, not pattern completion.

---

## Five Sources of Specifications

### 1. External Standards (strongest for target domains)

In LLMLL's target domains, specifications already exist as external documents:

- **Encryption:** NIST standards, algorithm specifications (AES, RSA, ECDSA)
- **Financial compliance:** Regulatory requirements (SOX controls, GDPR data handling rules)
- **Protocol implementation:** RFCs (TLS 1.3, OAuth 2.0, HTTP/2)
- **Smart contracts:** ERC standards (ERC-20, ERC-721), formal audit checklists

The agent's task is to **translate** existing specs into LLMLL contracts, not to **invent** specs from scratch. Translation from natural language to formal constraints is a task modern LLMs are reasonably good at, especially with examples.

**Implication for orchestrator:** The lead agent should be able to reference external spec documents as context when generating contracts.

### 2. Haskell Back-Translation (spec patterns via types)

Haskell code often carries implicit specifications via:
- Type signatures (including type-level constraints)
- Liquid Haskell refinement annotations (`{-@ ... @-}`)
- Property-based test suites (QuickCheck properties)
- Documentation assertions

A Haskell-to-LLMLL transpiler could extract:
- Type signatures → LLMLL type declarations
- QuickCheck properties → `pre`/`post` contracts
- Liquid Haskell annotations → refinement types

**Gap:** Most Haskell code lacks explicit specs. The transpiler would need a **specification lifting** phase — inferring contracts from implementations, tests, and types. This is a research problem but tractable for common patterns.

### 3. Progressive Refinement (start weak, strengthen)

Not all contracts need to start "proven." The workflow:

1. Lead agent writes **weak contracts** (type signatures, basic assertions)
2. Specialist agents implement against weak contracts
3. Compiler reports verification levels: many "asserted," few "proven"
4. Review identifies critical contracts (security, financial, correctness-critical)
5. Those contracts are strengthened and re-verified
6. Repeat until the trust profile is acceptable

The system supports this natively via stratified verification. The key insight: **you don't need perfect specs on day one.** You need visibility into where the specs are weak.

**Risk:** Epistemic drift — weak contracts never get strengthened because the program "works." Mitigation: `--trust-report` tooling (see action items).

### 4. Retrieval from Component Hub (spec reuse)

When a new typed hole is created, the orchestrator could query:
- The **project hub** — has this project already specified a similar component?
- The **global hub** — is there a published component with a compatible contract?

The query is by **type signature + contract shape**, not by name. A previously verified `sort-list` with contract `(post (sorted result) (= (length result) (length input)))` can be reused without re-specifying.

Over time, the hub accumulates specification patterns. Later projects benefit from earlier specification work.

**See:** [`component-hub.md`](component-hub.md)

### 5. Synthetic Corpus Generation (future work)

Generate LLMLL training data via:

1. **Transpile Hackage** — translate Haskell packages to LLMLL AST
2. **Lift specs** — infer contracts from QuickCheck properties and Liquid Haskell annotations
3. **Mine contract patterns** — extract common specification idioms (sorted, bounded, non-null, etc.)
4. **Generate variations** — produce equivalent programs with different contract strengths
5. **Benchmark** — measure agent performance on specification tasks

This produces a corpus of `(problem, specification, implementation)` triples for fine-tuning.

---

## The Honest Framing

> **LLMLL does not eliminate the need for training data. It shifts where that knowledge is required.** Models no longer need to memorize implementation patterns in the target language; instead, performance depends on their ability to generate useful specifications and decompositions. The system makes weaknesses in these areas explicit through unproven or weak contracts. Performance is expected to improve with domain-specific fine-tuning and synthetic training data, particularly for specification patterns.

---

## What This Means for the Roadmap

| Item | Priority | Team |
|------|----------|------|
| Spec-from-RFC pipeline (translate external standards) | **High** — strongest near-term answer | Orchestrator |
| `--trust-report` flag (epistemic drift detection) | **High** — enables progressive refinement | Compiler |
| Haskell-to-LLMLL transpiler (spec lifting) | Medium — research component | Compiler + Language |
| Hub query-by-signature | Medium — enables spec reuse | Orchestrator |
| Synthetic corpus generation | Medium — long-term investment | Research |
| Specification adequacy benchmark | Low — measures improvement | Research |

---

## The Research Angle

The reviewer's insight:

> **"LLMLL makes the lack of specification knowledge *visible*, which is not true in standard code generation."**

This is genuinely novel. In normal AI coding, bad specs are invisible — the code silently does the wrong thing. In LLMLL, weak specs surface as "asserted" contracts. This turns the specification-quality problem from an **invisible failure mode** into a **measurable metric**.

This opens a research direction: **specification quality as a first-class observable.** You could measure, benchmark, and optimize for specification quality across different models, domains, and fine-tuning strategies — something impossible in systems where specs are implicit.
