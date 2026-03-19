# LLMLL Design Team Assessment: Proposals vs. the One-Shot Goal

> **Prepared by:** Language Design Team  
> **Date:** 2026-03-19  
> **Source documents reviewed:** `LLMLL.md` · `consolidated-proposals.md` · `proposal-review-compiler-team.md`  
> **Shared with:** Compiler Team  
> **Central criterion applied:** Does this change move LLMLL closer to *one-shot correct program generation* by an AI swarm — i.e., a swarm agent writes a program once, the compiler accepts it, contracts verify, no iteration required?

---

## The One-Shot Correctness Frame

The ideal we are designing toward is not "AI systems that write programs" — it is **AI systems that write correct programs the first time**. This is a stronger requirement. It implies:

1. **Structural validity on generation** — the agent cannot produce syntactically malformed output.
2. **Type-correct on first submission** — the type checker never rejects a well-intentioned program.
3. **Contract-verified without runtime discovery** — `pre`/`post` violations are caught before execution, not during.
4. **Unambiguous interface boundaries** — agents working in parallel share identical, machine-readable contracts.
5. **No hallucination surface** — every construct the agent can emit is defined; no "valid-looking but wrong" paths.

Every proposal must be evaluated against this frame, not against human ergonomics or general PL elegance.

---

## Proposal 1 — JSON-AST as Primary AI Interface

### Assessment: **Adopt immediately. This is the single highest-leverage change for one-shot correctness.**

The parentheses-drift problem is well-documented and directly defeats one-shot development. An AI agent generating 200 lines of nested S-expressions *will* drift. The structural error rate is not a function of model quality — it is a function of generation length vs. nesting depth. No prompt engineering fixes a statistical failure mode.

Schema-constrained JSON generation changes the mathematical guarantee:

- **S-expression model:** "Structurally valid if agent maintained nesting count across all tokens" → probabilistic, degrades with length.
- **JSON-schema model:** "Structurally valid because inference API enforces schema before emitting the first token" → deterministic, independent of generation length.

This removes structural invalidity as a failure mode entirely. The agent can now fail only on *semantic* errors (type mismatches, undefined names, violated contracts), which are tractable.

The `additionalProperties: false` constraint deserves special emphasis: it eliminates the "valid JSON but hallucinated field" failure mode, which is the JSON-native analogue of parentheses drift. Both the professor's proposal and the compiler team's review are correct that this is the right technique.

**Concern we add (not in compiler review):** The JSON Schema defines the *structure* of programs but not their *semantic density*. An agent generating maximally sparse programs (many `?holes`) is structurally valid but not one-shot correct. The schema should encode *hole limits per function* as a validation rule — a function body that is entirely a `?name` hole should trigger a warning from the validator, not pass silently. This nudges agents toward fewer, more targeted holes rather than hole-first stubs.

**Verdict: Adopt verbatim. Add a hole-density warning layer to the schema validator.**

---

## Proposal 2 — Move Codegen Target from Rust to Haskell

### Assessment: **Adopt with conditions. The semantic alignment argument is correct; the WASM demotion risk is real but manageable.**

The compiler team's analysis is thorough and accurate. Our design team's position:

### Why this matters for one-shot correctness

The Rust codegen impedance mismatch is not just an engineering inconvenience — it is a one-shot correctness threat. When LLMLL's semantics don't map cleanly onto the target language:

- **Codegen emits approximations**, which diverge from the specified semantics in edge cases.
- **Contract violations in codegen** (a `pre`/`post` that holds in the LLMLL model but is violated by the Rust translation) are invisible to the AI agent, who only sees the LLMLL layer.
- **FFI stub incompleteness** (`todo!()` bodies that compile but panic) is a class of silent runtime failure that is structurally incompatible with one-shot correctness. The agent cannot know a stub is incomplete at generation time.

All three of these failure modes are eliminated or severely reduced by targeting Haskell:

| One-shot failure mode | Rust target | Haskell target |
|-----------------------|-------------|----------------|
| ADT construction semantics drift | Possible (Rust enums ≠ LLMLL ADTs) | Eliminated (`data T = ...` is exact) |
| Contract (pre/post) runtime vs. compile-time | Both tiers needed; complex | LiquidHaskell checks at compile time via GHC plugin |
| FFI stub incompleteness | `todo!()` compiles, panics | Hackage imports are complete; no stubs |
| IO capability escape | Runtime WASM trap | `-XSafe` GHC pragma: type-system enforcement |

The LiquidHaskell point deserves elaboration. In the Rust target, compile-time contract verification (the v0.2 plan) requires building a Z3 binding layer from scratch — months of work, and a new source of bugs. In the Haskell target, `pre`/`post` and `where`-type constraints map directly to LiquidHaskell refinement types, which already have a mature GHC plugin. This means **v0.2 compile-time verification becomes a 2-week integration task instead of a 3-month engineering project**. The faster we reach compile-time contract verification, the faster we approach true one-shot guarantees.

### Conditions we add (extending compiler team)

1. **The algebraic effects library choice must be made now, not at v0.1.2 implementation time.** The compiler team recommends `effectful` (not `polysemy` or `fused-effects`). We agree — `effectful` has simpler internals, better GHC version support, and the best prospects for GHC WASM backend compatibility. This choice must be committed in the spec before the codegen module is written.

2. **The `Command` model must become a typed effect row, not an opaque type.** Currently `Command` is opaque — agents cannot inspect it. In the Haskell target, the `Command` effect model should be an open effect row (using `effectful`'s `Eff '[IOCapability, HTTP, FS, ...]` pattern). This preserves the guarantee that pure logic functions cannot perform side effects, while making the *type* of effects visible in the function signature. An AI agent generating a function with `Http :> es` in its signature immediately knows it needs the HTTP capability declared. This closes a current ambiguity gap where an agent can generate a `wasi.http.response` call without declaring the capability, and the v0.1.1 compiler silently accepts it.

3. **Drop or strictly quarantine the Python FFI tier.** The compiler team is correct — `inline-python` breaks WASM compatibility and adds deployment fragility. More critically for one-shot goals: Python semantics are dynamically typed and the return values cannot be verified against LLMLL types at compile time. This tier is incompatible with the one-shot model and should not appear in the formal spec.

**Verdict: Adopt. Commit `effectful` as effects library, move `Command` to a typed effect row, drop Python tier from spec.**

---

## Proposal 3 — Module System to Explicit v0.2

### Assessment: **Adopt. This is a prerequisite, not a feature.**

The compiler team correctly identifies this as a documentation inconsistency with real consequences. Our design team's analysis is stronger than either document makes explicit:

**The one-shot model *requires* the module system to function at all for multi-agent programs.** Here is the exact failure chain without it:

1. Agent A writes module `Auth` and delegates `hash-password` to Agent B via `?delegate @crypto-agent`.
2. Agent B writes module `Crypto` with `hash-password` implemented.
3. Neither agent can compile against the other's module, because there is no cross-module resolution.
4. The `def-interface` treaty (§11.1) — the entire foundation of parallel development — cannot be checked.
5. The swarm writes programs; no agent can verify they compose.

This is not a v0.2 nice-to-have. Without the module system, `def-interface` is decorative and §11 (Multi-Agent Concurrency) is a specification of future aspirations, not current capability. Every v0.1.2 multi-agent demo we build will be fake — all code in one file.

**Verdict: Adopt verbatim. Escalate priority — the module system should ship in v0.2 before Z3 or LiquidHaskell, since without it cross-module invariant verification has no substrate.**

---

## Proposal 4 — Leanstral as v0.3 Proof Agent

### Assessment: **Adopt for v0.3 as specified. Do not pull forward. Add one spec change now.**

The compiler team's timing analysis is correct: pulling the Leanstral call into v0.2 risks overstuffing the milestone. Our view:

The two-track verification architecture (Z3/LiquidHaskell for decidable QF arithmetic; Leanstral for the rest) is sound and exactly right for one-shot correctness. The key insight is that it eliminates the binary "verified or unverified" model. Under the two-track model:

- Programs with simple arithmetic contracts get **zero-iteration compile-time verification** (Z3 / LiquidHaskell).
- Programs with complex inductive properties get **near-zero-iteration verification** (Leanstral call; certificate cached for all future builds).

This matters for the one-shot goal because it does not require every program to be in the decidable fragment. The agent writes the program; the track is chosen automatically based on predicate complexity.

**One spec addition we propose (not in either document):** The `?proof-required` hole should carry a **complexity hint** generated by the compiler based on predicate structure:

```lisp
?proof-required           ;; simple: likely Z3-decidable
?proof-required :inductive ;; complex: Leanstral track
?proof-required :unknown  ;; compiler cannot classify
```

This allows the one-shot pipeline to route to the right prover without re-classification.

**Verdict: Adopt v0.3 timeline. Spec the `?proof-required` complexity hint in v0.2 forward-compat placeholder.**

---

## Proposal 5 — Surface Syntax Fixes (Option A)

### Assessment: **Partially adopt, but reframe the priority entirely.**

The professor's framing — "AI agents write JSON, humans write S-expressions" — is correct and makes this the lowest-priority item for the one-shot goal. Our position:

**Accept:** The `let` double-bracket fix (compiler team's alternative `(let [(x e1) (y e2)] body)` is better than both current and proposed). The double-bracket form generates a disproportionate number of errors even in `LLMLL.md`'s own examples.

**Accept:** List literals `[]` / `[a b c]` — ergonomic for humans writing test `check` blocks.

**Reject:** `(pair a b)` → `(, a b)`. Compiler team is correct; punctuation-as-function-name is a parsing edge case for three characters of savings.

**One addition the proposals miss:** The v0.1.1 limitation on `pair-type` in `typed-param` position is a type system gap, not a syntax issue. The workaround (use untyped parameters) forces agents to generate code with unverified parameter types — a one-shot correctness risk. This should be an explicit v0.2 type system fix, not just a documentation limitation.

**Verdict: Accept `let` + list literals. Reject `pair` syntax. Escalate `pair-type` in `typed-param` from a v0.1.1 limitation to a v0.2 type system fix.**

---

## Net Assessment: What This Means for One-Shot Correctness

The proposals, taken as a set, represent a coherent and necessary maturation trajectory. Ranked by impact on the one-shot goal:

| Proposal | One-shot impact | Our verdict |
|----------|-----------------|-------------|
| JSON-AST (P1) | **Critical** — eliminates structural invalidity as a failure mode | Adopt + hole-density warning |
| Module system (P3) | **Critical** — without it, multi-agent composition is unverifiable | Adopt + escalate priority in v0.2 |
| Haskell codegen (P2) | **High** — eliminates codegen semantic drift; unlocks LiquidHaskell | Adopt + `effectful` + typed effect row |
| Leanstral (P4) | **Medium** — completes the verification coverage for non-decidable properties | Adopt v0.3; spec hint in v0.2 |
| Syntax fixes (P5) | **Low** — humans only; AI agents use JSON | Partial adopt |

### The gap the proposals don't address

Both the professor and the compiler team focus on the *compiler* side of one-shot correctness. The *generation* side has a gap that neither proposal closes:

> **How does an AI agent know, before submitting, whether its program will pass the LLMLL type checker?**

Currently the answer is: it doesn't. The agent generates, submits, gets errors, iterates. This is the loop we want to eliminate.

The JSON Schema (P1) closes the structural validity gap. But type errors — wrong types passed to functions, incompatible ADT constructor arguments, missing match arms — are still discovered only at compile time.

**A design proposal we recommend adding:** A **lightweight type inference sketch** available as a JSON API (`llmll typecheck --sketch`) that an agent can call during generation, before committing to a full program. This is not a full type checker; it is a constraint-propagation pass over partial programs (programs with holes). The agent generates a skeleton, type-sketches it, fills holes consistent with the inferred types, and submits a type-consistent program. This is the missing loop-eliminator on the generation side.

---

## Divergence from the Compiler Team

This section documents specifically where the design team's positions differ from `proposal-review-compiler-team.md`. On all other points we are fully aligned.

### P2 — Haskell Codegen: `Command` as a typed effect row

**Compiler team position:** Accepts Haskell codegen and endorses `effectful`, but treats `Command` as-is — still opaque, not directly addressed.

**Design team position:** `Command` must become a **typed effect row** in generated Haskell (`Eff '[HTTP, FS, ...] r`). This is a materially different design. In v0.1.1 an agent can call `wasi.http.response` without declaring the HTTP capability, and the compiler silently accepts it. A typed effect row makes required capabilities visible in the function type signature — the type checker catches missing capability declarations, not a runtime guard. Opaque `Command` leaves this ambiguity gap open even after the Haskell migration.

### P2 — Haskell Codegen: `effectful` rationale

**Compiler team position:** Recommends `effectful` as a preference over `polysemy`/`fused-effects`, citing simpler internals and WASM compatibility.

**Design team position:** Agrees on the choice, but for an additional reason the compiler team doesn't articulate: `effectful`'s effect rows are *type-visible* to an AI agent reasoning about what capabilities a function requires. This is a design rationale tied directly to the one-shot goal, not just an implementation preference. The rationale should appear in the spec so future codegen decisions are anchored to it.

### P3 — Module System: Internal v0.2 ordering

**Compiler team position:** Accept verbatim; update the roadmap doc. No position on internal v0.2 ordering.

**Design team position:** The module system should be the **first deliverable within v0.2**, sequenced before LiquidHaskell/Z3 integration. Rationale: cross-module invariant verification (`def-invariant` + Z3) has no substrate without multi-file resolution. Shipping Z3 first produces a verifier with nothing cross-module to verify. The ordering matters and should be explicit in the roadmap.

### P4 — Leanstral: `?proof-required` complexity hint

**Compiler team position:** Adopt for v0.3; spec `?proof-required` as a forward-compat placeholder in v0.2.

**Design team position:** Agrees on timing, but adds that the `?proof-required` placeholder in v0.2 should carry a **compiler-assigned complexity hint** (`:inductive`, `:unknown`) so the pipeline can route automatically to Z3 vs. Leanstral without requiring the agent to classify the proof obligation. The compiler team's spec placeholder is silent on routing.

### P5 — Surface Syntax: `pair-type` in `typed-param`

**Compiler team position:** P5 discussion stays at the surface syntax level (`let`, list literals, `pair`). The `pair-type`-in-`typed-param` v0.1.1 limitation is not mentioned.

**Design team position:** This limitation is a **type system gap**, not a syntax issue. The workaround — emitting untyped lambda parameters (`[acc]` instead of `[acc: (int, string)]`) — forces agents to generate code with unverified parameter types. This is a silent one-shot correctness erosion that accumulates across every program using pair accumulators in folds or closures. It must be promoted from a documented v0.1.1 limitation to an explicit v0.2 type system fix.

### Summary of Divergence Points

| Item | Compiler Team | Design Team |
|------|--------------|-------------|
| `Command` typed effect row | Not addressed | Explicit requirement for Haskell target |
| `effectful` rationale | Implementation preference | Tied to type-visibility for AI agents (one-shot rationale) |
| v0.2 internal ordering | No position | Module system before Z3 |
| `?proof-required` complexity hint | Not addressed | Required in v0.2 forward-compat spec |
| `pair-type` in `typed-param` | Not mentioned | Escalate from limitation to v0.2 type system fix |

---

## Summary of Design Team Recommendations

| Item | Action |
|------|--------|
| JSON-AST | Adopt. Add hole-density warning to schema validator. |
| Haskell codegen | Adopt. Commit `effectful`. Move `Command` to typed effect row. Drop Python tier from spec. |
| Module system | Adopt. Escalate to first deliverable of v0.2, before Z3. |
| Leanstral | Adopt v0.3 timeline. Add `?proof-required :inductive/:unknown` hint in v0.2 spec. |
| Syntax fixes | Partial. Accept `let` + list literals, reject `pair`. Escalate `pair-type`-in-param to v0.2 fix. |
| **New proposal** | Add `llmll typecheck --sketch` API: partial-program type inference during AI generation phase. |
