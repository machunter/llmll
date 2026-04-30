# LLMLL — A Verification System for AI Agent Teams

> *Making AI-generated code composable, inspectable, and uncertainty-aware through explicit specifications and formal verification.*

> **Note:** LLMLL.md is the normative semantic specification. This document is a summary for external audiences.

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

Inspired by refinement types (Liquid Haskell) and type-driven development, types in LLMLL can carry constraints directly — a `PositiveInt` is not just an `int`, it's an `int` with a declared constraint `x > 0`, which the compiler can verify within the shipped QF-LIA arithmetic fragment via `llmll verify`. For behavioral properties — like "the list is sorted" — the system's **shipped** verification path is an SMT solver (Z3 via liquid-fixpoint) that handles the decidable quantifier-free linear arithmetic fragment automatically. Contracts outside this fragment — those requiring induction or non-linear reasoning — are tracked as `asserted` or `tested` and explicitly flagged with `?proof-required` holes. LLMLL does not have dependent elimination, proof terms, or sigma types — its type annotations are refinement-like predicates, not dependent types in the Idris/Lean sense.

> **Verification scope:** The **shipped** verification path is SMT (Z3 via liquid-fixpoint), covering quantifier-free linear integer arithmetic: `+`, `-`, `=`, `<`, `<=`, `>=`, `>`. This handles ~80% of practical contracts (numeric bounds, conservation invariants, length preservation). An interactive proof path (Lean 4, via Leanstral MCP) is **designed but not shipped** — translation infrastructure exists (`LeanTranslate.hs`, `MCPClient.hs`, `ProofCache.hs`), but real proof integration is blocked on `lean-lsp-mcp` availability and the current pipeline runs in mock mode only (`--leanstral-mock`). Contracts outside the SMT fragment are not silently dropped; they are tracked as `asserted` with explicit verification level propagation through dependencies.

> Types handle structural guarantees; contracts handle behavioral ones; the SMT solver handles the decidable arithmetic fragment; inductive properties are tracked as open proof obligations.

---

## Key Design Choices

### Types and contracts as the trust interface

Every function carries a typed specification. When Agent B calls Agent A's function, it reads the type signature and contract — never the implementation. The compiler checks compatibility against declared contracts. Agents trust each other's contracts, not each other's code.

*A natural question: can today's AI models actually write good type signatures and contracts?* Current reasoning models (o3, Gemini 2.5 Pro) can produce Haskell type signatures and Liquid Haskell refinements — they've been trained on this material. Whether they produce contracts that are *meaningful enough* to catch real bugs is an open question. But LLMLL has two feedback mechanisms: stratified verification flags unproven contracts as "asserted" rather than "proven," and the weakness checker (`llmll verify --weakness-check`, shipped v0.3.5) actively tests whether a trivial implementation (identity function, constant zero, empty string) satisfies the contract — if so, the spec is flagged as under-specified. The system doesn't assume agents write perfect specs — it makes the quality of specs transparent and *actively detects* when a spec is too weak to be useful.

### Multi-agent orchestration

A lead agent decomposes the program into typed holes and assigns them to specialist agents working in parallel. Each agent checks out its hole exclusively, submits a JSON patch to the program's abstract syntax tree, and the compiler re-verifies before accepting. An HTTP API lets many agents query the compiler concurrently. This opens the door to domain-specific agents — an encryption specialist, a financial compliance agent (regulatory constraints map directly to contracts), a smart contract auditor, a protocol implementation agent (TLS, OAuth) — each trained or prompted for its domain.

### Stratified verification

Not all contracts can be mathematically proven. The compiler tracks whether each contract is *proven* (SMT solver), *tested* (property-based testing), or just *asserted* (runtime check). Trust levels propagate: if a function depends on an unproven contract, it inherits the lower trust level — the system makes the full assumption chain visible. Code with weak or missing contracts still compiles, but no downstream conclusion is presented as stronger than its weakest dependency.

### Merging is JSON, not text

Agents don't write source code files that get merged with git-style diffs. They emit structured JSON objects (the program's abstract syntax tree) and submit patches to specific nodes. The compiler validates each patch against the type system before accepting. This eliminates structural merge conflicts (two agents editing the same text region); semantic conflicts are caught by the re-verification step.

---

## Status

LLMLL currently provides body-faithful SMT verification for a **non-recursive QF-LIA core**: literals, variables, simple let-bindings, conditionals, and linear arithmetic. Programs outside that fragment fall back to contract-only verification, tests, or runtime assertions with explicit trust labels.

**Verification boundary (v0.8.0):**

| Construct | SMT body-faithful | Fallback |
|---|---|---|
| `ELit`, `EVar` (int), linear ops | ✅ | — |
| `ELet` (PVar, int), `EIf` (≤4096 paths) | ✅ | — |
| `EApp` (builtins, user-defined) | ❌ | contract-only |
| `EMatch`, `EPair`, `ELambda`, `EDo`, `letrec` | ❌ | runtime |
| Non-linear ops (*, /, mod) | ❌ | `?proof-required` |
| **Int overflow** | ⚠ | Z3 `Int` ≠ Haskell `Int64` |

The compiler is at **v0.8.0** (April 2026): Haskell code generation, formal contract verification (liquid-fixpoint/Z3), multi-agent checkout/patch with context-aware typing context, trust hardening (`--trust-report`), compiler-emitted agent specifications (`llmll spec`), a Lead Agent (`llmll-orchestra --mode plan|lead|auto`) that architects programs end-to-end, and a specification quality layer — `--spec-coverage` gate with `(weakness-ok)` suppression governance, `:source` clause-level provenance on contracts, frozen ERC-20 and TOTP benchmarks with verification-scope matrices, and algebraic interface laws (`def-interface :laws`). v0.8.0 shipped **body-faithful verification conditions** — the verifier now encodes function bodies as `.fq` constraints for the QF-LIA fragment, so `VLProvenSMT` means the implementation satisfies the contract, not just that the contract is self-consistent. Postcondition runtime assertions can be safely stripped for body-faithful proven functions; preconditions are always preserved. The type checker implements sound unification (Algorithm W with occurs check and let-generalization) — the last known unsoundness was closed in v0.5.0. 320 Haskell + 37 Python tests passing.

Early stage — the compiler infrastructure works, validation on increasingly complex sample programs is ongoing. Open source (GPLv3). Solo project, supported by AI tools.

---

## The "No Training Data" Question

LLMLL is a new language — LLMs weren't trained on it. This is a real concern, but the difficulty is not where most people assume.

**What's easy.** Producing syntactically valid LLMLL is straightforward. The agent interface is structured JSON against a schema — models are already strong at schema-constrained generation. The language has ~20 core constructs; the full spec fits in a model's context window. And LLMLL compiles to Haskell, so a significant subset of Haskell's ecosystem (~15,000 Hackage packages) can potentially be back-translated into LLMLL for fine-tuning.

**What's hard — and not as hard as it sounds.** The real challenge is not writing code but writing good *specifications*. However, this concern is often overstated. LLMs are empirically better at writing constraints ("length preserved," "no duplicates," "result is positive") than at writing correct algorithms — because constraints are local and descriptive, not constructive. And agents don't write specs in isolation: typed holes like `?hole : List Int -> SortedList Int` already encode structure and partial invariants. The agent only needs to add *incremental refinements*, not invent specs from scratch. The remaining challenge is not specification correctness but **specification coverage** (what gets specified at all) and **decomposition quality** (choosing the right boundaries).

**What helps.** The compiler gives precise, structured feedback — errors point to exact AST nodes (JSON Pointers, not line numbers), and the verify-on-merge loop lets agents iterate quickly. More importantly, **the system makes specification weakness visible rather than hiding it.** In normal AI code generation, a weak specification is invisible — the code silently does the wrong thing. In LLMLL, weak specs surface in two ways: unproven contracts are tracked as "asserted" rather than "proven" (with trust-level propagation through dependencies), and the weakness checker (`--weakness-check`) actively constructs trivial candidate implementations and tests whether they satisfy the contract — if they do, the spec is flagged as under-specified with the specific trivial body that passed.

**Where specifications come from.** In the target domains — encryption, financial compliance, protocol implementation — specifications already exist as external documents (RFCs, regulatory requirements, algorithm standards). The agent's task is to *translate* existing specifications into LLMLL contracts, not to *invent* them. For novel software, specification quality will depend on model capability and is expected to improve with domain-specific fine-tuning and synthetic training data.

---

## What's Next

| Milestone | Description |
|-----------|-------------|
| **Documentation boundary clarity** (v0.8.1a) | Rename "Dependent Types" → "Refinement Type Aliases." Per-construct verification matrix in LLMLL.md, README, and one-pager. Integer overflow model gap documented. Docs only, no code changes. |
| **Evidence model refactor** (v0.8.1b) | Replace `VerificationLevel` total order with four-tier partial order: `verified` > `contract-checked` / `tested` > `asserted`. Assumption taxonomy (`runtime-primitive`, `compiler-builtin`, `external-opaque`). Structured `.verified.json` sidecar. Design review required. |
| **Compositional verification** (v0.9) | Assume-guarantee encoding for `EApp` with correct precondition polarity. `EMatch` on `Result`. SCC recursive fallback. Transitive trust degradation. `--strict-verified-core` mode. Design review required. |
| **Body-faithful VCs** (v0.8.0) ✅ | `bodyToPred` translates function bodies into verification conditions for the QF-LIA fragment. Closes the faithfulness gap. 320 tests (+26). |
| **Hardening** (v0.7) ✅ | `string-char-at` negative index guard, `regex-match` → POSIX ERE, `VLProvenSMT` constructor. 294 tests. |
| **Trust model fixes** (v0.6.3) ✅ | 7 critical bugs resolved: strict typecheck gate, transitive trust closure, body-faithful stripping guard, proof laundering protection. |
| **Algebraic interface laws** (v0.6.2) ✅ | `def-interface :laws` with `(for-all ...)` property syntax and QuickCheck codegen. |
| **Spec quality** (v0.6.0–v0.6.1) ✅ | `--spec-coverage` gate, `(weakness-ok)` governance, `:source` provenance, frozen ERC-20 and TOTP benchmarks. |
| **U-Full soundness** (v0.5.0) ✅ | Occurs check, let-generalization. Closes last known unsoundness. |
| **Lead Agent** (v0.4.0) ✅ | `llmll-orchestra --mode plan|lead|auto`. Automated skeleton generation. |
| **Context-aware checkout** (v0.3.5) ✅ | `llmll checkout` returns Γ, τ, Σ. `--weakness-check` detects trivial-body specs. |
| **WASM sandboxing** (planned) | WASM-WASI capability enforcement. `effectful` compatibility confirmed (v0.5.0 spike). |
| **Synthetic training corpus** (research) | Hackage back-translation for fine-tuning. |

---

## Claim-to-Evidence Map

> **Purpose:** Every major claim in this document maps to a specific shipped command, example, or benchmark with an explicit verification level. This table is the accountability index.

| Claim | Evidence | Verification level | Command / artifact |
|---|---|---|---|
| "Compiler accepts or rejects code against contracts" | All shipped examples type-check and verify | **Proven** (within QF-LIA) | `llmll check`, `llmll verify` |
| "Contracts are verified by SMT solver (Z3)" | liquid-fixpoint integration, 320 Haskell + 37 Python tests | **Proven** (QF-LIA) | `llmll verify examples/hangman_json_verifier/` |
| "Leanstral handles inductive properties" | Translation infrastructure exists; mock-only | **Not shipped** — mock pipeline | `llmll verify --leanstral-mock` |
| "Trust levels propagate through dependencies" | `--trust-report` emits transitive trust closure | **Shipped** (v0.3.2) | `llmll verify --trust-report` |
| "Weakness checker detects under-specified contracts" | Trivial-implementation construction | **Shipped** (v0.3.5) | `llmll verify --weakness-check` |
| "Lead Agent architects programs end-to-end" | Skeleton generation from intent | **Shipped** (v0.4.0) | `llmll-orchestra --mode auto` |
| "Context-aware checkout reduces hallucination" | Γ, τ, Σ in checkout response | **Shipped** (v0.3.5) | `llmll checkout --json` |
| "Sound unification (Algorithm W)" | Occurs check + let-generalization | **Shipped** (v0.5.0) | 320 Haskell tests, 0 failures |
| "Capability enforcement at compile time" | `wasi.*` calls rejected without matching import | **Shipped** (v0.4.0, CAP-1) | `llmll check` on `wasi.*` without import → error |
| "Spec coverage is a blocking gate" | `--spec-coverage` classifies functions, computes effective coverage, gates `--mode auto` | **Shipped** (v0.6.0) | `llmll verify --spec-coverage` |
| "Suppression governance for intentional underspecification" | `(weakness-ok fn "reason")` with mandatory reason, surfaced in trust report | **Shipped** (v0.6.0) | `llmll verify --spec-coverage`, `--trust-report` |
| "ERC-20 benchmark with external ground truth" | Frozen benchmark with verification-scope matrix, walkthrough, expected results | **Shipped** (v0.6.0) | `examples/erc20_token/` |
| "Clause-level provenance (`:source`)" | Per-clause `:source` annotation on `pre`/`post` contracts | **Shipped** (v0.6.0) | `(pre expr :source "RFC §...")` |
| "TOTP benchmark with RFC traceability" | Frozen benchmark, `:source` annotations | **Shipped** (v0.6.1) | `examples/totp_rfc6238/` |
| "Body-faithful verification" | `bodyToPred` encodes bodies as VCs; body-faithful postconditions can be stripped | **Shipped** (v0.8.0) | `llmll verify` on QF-LIA functions |
| "WASM sandboxing" | `effectful` compat spike GO; Docker is current sandbox | **Confirmed future** | `docs/effectful-wasm-spike.md` |

> [!NOTE]
> Items marked **Planned** or **Confirmed future** are not shipped. They are included in this table to prevent overreading — the distinction between "shipped" and "planned" must remain visible.

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
