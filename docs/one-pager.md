# LLMLL — A Verification System for AI Agent Teams

> *Making AI-generated code composable, inspectable, and uncertainty-aware through explicit specifications and formal verification.*

---

## The Problem

Current AI coding tools (Copilot, Cursor, Devin) work by imitating human developers — generate code, run it, read the error, pattern-match on the fix, revise. This approach inherits three fundamental limitations:

**Coordination.** Two AI agents implementing different parts of a system have no guarantee their outputs are compatible. Integration is manual and doesn't scale to many agents.

**Verification.** AI-generated code today is checked by unit tests and acceptance tests — the same tools human developers use. But these are example-based: they verify that specific inputs produce expected outputs. They don't prove that a function satisfies its specification for *all* inputs. And they run *after* implementation, not at the point where code enters the system.

**Hallucination.** When an AI is uncertain, it guesses. There's no mechanism for it to say "I don't know how to implement this part" and hand it off. LLMLL solves this with *typed holes* — an agent emits a placeholder with a precise type signature when it's uncertain. The compiler infers the expected type from surrounding context. A different agent (or the same agent on retry) then fills the hole with full constraint information in hand. The resolution is explicit and traceable.

---

## The Approach

LLMLL is a system — a programming language, compiler, and verification pipeline — where the primary developers are AI agents, not humans. A lead agent architects the program, defining expressive types and contracts that specify *what* each component must do. Specialist agents fill in the *how*. The compiler verifies that every agent's code satisfies its specification before merging it into the program.

> **The key idea:** verification is not a post-hoc filter — it is the **coordination protocol itself**. Agents don't coordinate through conversation or task queues. They coordinate through formal specifications that the compiler enforces.

**An agent can hallucinate its implementation and that's fine** — as long as the implementation satisfies the formal contract. If the type signature says the function takes a positive integer and returns a list, and the contract says the output length equals the input length, then *any* implementation that passes those checks is correct *relative to its specification*. This turns hallucination from a failure mode into a **search strategy**: generate a candidate, verify it against the spec, reject or accept. It's generate-and-check search with a formal filter — and the filter is the compiler. The quality of the result is bounded by the quality of the specification — the system makes specification gaps visible, not impossible.

> **To be precise:** the system does not guarantee program correctness — it guarantees that all code is consistent with its declared specifications, whose strength is explicitly tracked. A "proven" contract has been verified by the SMT solver within its logical model. An "asserted" contract has not been verified yet. Both are visible, and the trust level propagates through dependencies — no "proven" claim rests silently on an unproven assumption.

---

## The Type System

Drawing from type-driven development (as pioneered in Idris and Lean), types in LLMLL can carry constraints directly — a `PositiveInt` is not just an `int`, it's an `int` where the compiler has proven `x > 0`. For richer properties like "returns a list of exactly n items," dependent types express that at the type level. For behavioral properties that go further — like "the list is sorted" — the system has two verification paths: an SMT solver (Z3) handles the decidable arithmetic fragment automatically, and an interactive prover (Lean 4, via Leanstral) handles inductive properties that require structural reasoning.

> Types handle structural guarantees; contracts handle behavioral ones; the proof system handles what's beyond both.

---

## Key Design Choices

### Types and contracts as the trust interface

Every function carries a typed specification. When Agent B calls Agent A's function, it reads the type signature and contract — never the implementation. The compiler checks compatibility against declared contracts. Agents trust each other's contracts, not each other's code.

*A natural question: can today's AI models actually write good type signatures and contracts?* Current reasoning models (o3, Gemini 2.5 Pro) can produce Haskell type signatures and Liquid Haskell refinements — they've been trained on this material. Whether they produce contracts that are *meaningful enough* to catch real bugs is an open question. But LLMLL's stratified verification gives a feedback signal: if a contract is too weak, the verification level stays at "asserted" rather than "proven," visibly flagging it. The system doesn't assume agents write perfect specs — it makes the quality of specs transparent.

### Multi-agent orchestration

A lead agent decomposes the program into typed holes and assigns them to specialist agents working in parallel. Each agent checks out its hole exclusively, submits a JSON patch to the program's abstract syntax tree, and the compiler re-verifies before accepting. An HTTP API lets many agents query the compiler concurrently. This opens the door to domain-specific agents — an encryption specialist, a financial compliance agent (regulatory constraints map directly to contracts), a smart contract auditor, a protocol implementation agent (TLS, OAuth) — each trained or prompted for its domain.

### Stratified verification

Not all contracts can be mathematically proven. The compiler tracks whether each contract is *proven* (SMT solver), *tested* (property-based testing), or just *asserted* (runtime check). Trust levels propagate: if a function depends on an unproven contract, it inherits the lower trust level — the system makes the full assumption chain visible. Code with weak or missing contracts still compiles, but no downstream conclusion is presented as stronger than its weakest dependency.

### Merging is JSON, not text

Agents don't write source code files that get merged with git-style diffs. They emit structured JSON objects (the program's abstract syntax tree) and submit patches to specific nodes. The compiler validates each patch against the type system before accepting. This eliminates structural merge conflicts (two agents editing the same text region); semantic conflicts are caught by the re-verification step.

---

## Status

The compiler is completed through **v0.3** (April 2026) with all planned features: Haskell code generation, formal contract verification (liquid-fixpoint/Z3), multi-agent checkout/patch, and async code generation.

Early stage — the compiler infrastructure works, validation on increasingly complex sample programs is ongoing. Open source (GPLv3). Solo project, supported by AI tools.

---

## The "No Training Data" Question

LLMLL is a new language — LLMs weren't trained on it. This is a real concern, but the difficulty is not where most people assume.

**What's easy.** Producing syntactically valid LLMLL is straightforward. The agent interface is structured JSON against a schema — models are already strong at schema-constrained generation. The language has ~20 core constructs; the full spec fits in a model's context window. And LLMLL compiles to Haskell, so a significant subset of Haskell's ecosystem (~15,000 Hackage packages) can potentially be back-translated into LLMLL for fine-tuning.

**What's hard — and not as hard as it sounds.** The real challenge is not writing code but writing good *specifications*. However, this concern is often overstated. LLMs are empirically better at writing constraints ("length preserved," "no duplicates," "result is positive") than at writing correct algorithms — because constraints are local and descriptive, not constructive. And agents don't write specs in isolation: typed holes like `?hole : List Int -> SortedList Int` already encode structure and partial invariants. The agent only needs to add *incremental refinements*, not invent specs from scratch. The remaining challenge is not specification correctness but **specification coverage** (what gets specified at all) and **decomposition quality** (choosing the right boundaries).

**What helps.** The compiler gives precise, structured feedback — errors point to exact AST nodes (JSON Pointers, not line numbers), and the verify-on-merge loop lets agents iterate quickly. More importantly, **the system makes specification weakness visible rather than hiding it.** In normal AI code generation, a weak specification is invisible — the code silently does the wrong thing. In LLMLL, weak specs surface as "asserted" rather than "proven" contracts, and trivial implementations that satisfy a too-weak spec are detectable.

**Where specifications come from.** In the target domains — encryption, financial compliance, protocol implementation — specifications already exist as external documents (RFCs, regulatory requirements, algorithm standards). The agent's task is to *translate* existing specifications into LLMLL contracts, not to *invent* them. For novel software, specification quality will depend on model capability and is expected to improve with domain-specific fine-tuning and synthetic training data.

---

## What's Next

| Milestone | Description |
|-----------|-------------|
| **v0.3.1** (in progress) | Interactive proof integration via Lean 4. Deterministic event-log replay — a machine-readable sequence of `(input, output, side-effects)` entries for debugging and auditability. |
| **Agent orchestrator** | Standalone tool for hole decomposition, specialist agent delegation, checkout/verify/merge cycle, and component registry querying. |
| **WASM sandboxing** (v0.4) | Contracts cover *correctness*; WASM covers *capability abuse*. Server-side runtimes (Wasmtime, WasmEdge) enforce that programs cannot access resources beyond their declared capabilities. |
| **Synthetic training corpus** | Haskell-to-LLMLL back-translation from Hackage for fine-tuning and benchmarking. |

---

## Related Work

| Reference | Relevance |
|-----------|-----------|
| Edwin Brady, *Type-Driven Development with Idris* (Manning, 2017) | Foundational text on types-as-specs with compiler-guided hole-filling. LLMLL's typed-hole workflow is directly influenced by this. |
| Ranjit Jhala & Niki Vazou, *Liquid Haskell* (UCSD) | Refinement types verified by SMT solvers. LLMLL uses the same underlying engine (liquid-fixpoint/Z3). |
| Bertrand Meyer, *Design by Contract* (1986) | Original formulation of pre/post conditions as formal interface specs. |
| LangGraph, CrewAI, AutoGen | Multi-agent AI frameworks. LLMLL differs: coordination through a *compiler*, not conversation. |
| Model Context Protocol (MCP) | Emerging standard for agent-tool interop. LLMLL's Leanstral uses MCP. |
| Lean 4 (Microsoft Research) | Interactive theorem prover for inductive proofs beyond SMT solvers. |

---

**GitHub:** [github.com/llmll](https://github.com/llmll) · **License:** GPLv3 with runtime exception
