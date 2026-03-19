# Engineering Review: Professor's Consolidated Proposals for LLMLL

> **Prepared by:** Compiler Team  
> **Date:** 2026-03-17  
> **Source documents:** `consolidated-proposals.md`, `proposal-haskell-target.md`, `analysis-leanstral.md`, `LLMLL.md`

---

## Overall Assessment

The proposals are coherent as a set and stem from a consistent intellectual framework: *LLMLL's primary audience is AI agents, so every design decision should be benchmarked against machine generation quality rather than human ergonomics.* That framing is correct and the proposals follow from it logically. They are also timely — they correct real costs that will compound if not addressed before v0.2 hardens the architecture.

My disagreements below are matters of degree and sequencing, not direction.

---

## Priority 1 — JSON-AST as Primary AI-to-Compiler Interface

**Verdict: Strong Yes. Start immediately.**

### What the proposal gets right

The core observation is empirically solid. The parentheses-drift problem with S-expressions is documented behavior of current LLMs. The proposed fix — schema-constrained JSON generation via OpenAI Structured Outputs / Gemini schema parameters — provides a *structural validation tier* that no amount of prompt engineering with S-expressions can match. The JSON Schema strategy of `additionalProperties: false` everywhere is particularly good; it prevents the LLM from expressing syntactically-valid but semantically-meaningless nodes, eliminating an entire category of hallucination.

The RFC 6901 JSON Pointer for error diagnostics is also excellent. Right now, a compiler error on a deeply nested expression gives an AI agent a text offset that it needs to correlate back to its own generated text — a lossy process. A pointer into the JSON AST is unambiguous and directly actionable.

The `llmll holes --json` output format is the correct substrate for every multi-agent workflow in §11. Without it, `?delegate` is purely decorative.

### Concerns

1. **S-expression parsing must not regress.** The proposal says JSON becomes *primary*, which could tempt the team to let the S-expression parser ossify. Human developers writing tests, debug scripts, and documentation examples will use S-expressions; they must remain fully supported and the two parsers must agree on every edge case. I'd recommend a round-trip regression test suite (`s-expr → JSON → s-expr → compile`) from day one.

2. **Schema version discipline.** The JSON Schema is the new source of truth. Any language evolution (new node kinds, new hole types) must bump the schema version. Without this discipline, generated JSON from an older LLM becomes silently invalid against a newer schema. Define the versioning policy before shipping.

### Recommendation

Adopt. This is the highest-leverage change in the set. The `ParserJSON.hs` module and the schema should be merged before any other v0.1.2 work begins, since all subsequent tooling (`llmll holes --json`, JSON diagnostics) depends on it.

---

## Priority 2 — Move Code Generation from Rust to Haskell

**Verdict: Conditionally Yes, but the team must be clear-eyed about what it's trading away.**

### What the proposal gets right

The semantic alignment argument is genuine. The mapping table in `proposal-haskell-target.md §3` is accurate: `def-logic` → Haskell function, `type T (| A t)(| B s)` → `data T = A t | B s`, `def-interface` → type class. These aren't approximations — they are the same concepts in the same mathematical framework. The Rust codegen has to fight against the ownership model at every step; the current preamble is already doing heavy lifting to paper over this.

The LiquidHaskell argument for v0.2 is the single strongest point. Building a Z3 binding layer from scratch for a Haskell compiler targeting Rust is months of engineering work. LiquidHaskell is a mature tool (15+ years, used in production at Microsoft Research and other labs) that already handles the exact refinement type fragment LLMLL needs: quantifier-free linear arithmetic and regex predicates. The proposal eliminates this entire deliverable from the roadmap.

The `-XSafe` sandboxing insight is also underappreciated. Safe Haskell is enforced by the type system at compile time, not at runtime. A generated module compiled with `-XSafe` *cannot* call `System.IO.hPutStrLn` even if someone injects code into it — the module simply won't typecheck. This is a stronger source-level guarantee than any WASM capability enforcement at the current spec stage.

### Concerns (significant)

1. **WASM demotion is a strategic bet, not a free lunch.** WASM-WASI is the only sandboxing model that is:
   - Hermetic from the host OS at the ABI boundary (not just the syscall boundary)
   - Portable across Linux, macOS, Windows, and cloud WASM runtimes
   - Auditable by the runtime (every import is a declared, typed capability)

   The Docker + `seccomp-bpf` + `-XSafe` stack provides *equivalent practical security* for research use, but it is not the same contract. A `seccomp-bpf` filter misconfiguration is silent; a WASM capability violation is a typed error. This matters if LLMLL's long-term goal is to be a trusted execution substrate for multi-agent AI programs. The proposal's v0.4 WASM path is real and technically sound (GHC's WASM backend reached production quality in GHC 9.10), but it's now a 3-version-away deliverable, not a current property.

   **Mitigation:** The team should commit publicly in the spec that WASM is a first-class goal deferred, not abandoned.

2. **GHC's WASM backend still has rough edges.** As of GHC 9.10, the WASM backend does not support all of GHC's runtime facilities (threads, `IORef`-heavy code, some GHC.Generics derivations). If the generated Haskell uses `polysemy` or `fused-effects` for the `Command`/effect model (as the proposal suggests), there is a real compatibility question about whether those libraries compile cleanly to WASM today. This needs a small proof-of-concept *before* committing to the Haskell target.

3. **The algebraic effects choice needs to be made explicitly.** The proposal mentions both `polysemy` and `fused-effects` for the `Command` model. These two libraries have very different codegen characteristics, different levels of GHC version support, and different communities. The team must pick one and commit. My recommendation is `effectful` (not mentioned in the proposals) which has better GHC WASM compatibility and simpler internals than either.

4. **Python FFI (Tier 3) is a bad idea at this stage.** The `python.*` tier via `inline-python` is the weakest part of the proposal. `inline-python` is fragile (it embeds a Python interpreter in the GHC process), breaks any hope of WASM compatibility for modules that use it, and adds a heavy operational dependency. This tier should be marked experimental and kept strictly out of the formal language spec until the other tiers are stable.

### Recommendation

Adopt, but with two preconditions: (a) a proof-of-concept that a non-trivial generated `.hs` file compiles with `--target wasm32-wasi` using GHC 9.10, and (b) an explicit effects library choice committed to in the spec. Drop or quarantine the Python FFI tier.

---

## Priority 3 — Promote Module System to an Explicit v0.2 Deliverable

**Verdict: Yes. This should be uncontroversial.**

### Analysis

The professor has found an actual inconsistency in the project documents. `LLMLL.md §8` explicitly says multi-file module resolution is "deferred to v0.2" and the roadmap's v0.2 section omits it entirely, jumping straight to liquid types. This is a documentation bug with real consequences: it means the v0.2 milestone as currently written *cannot actually unlock* the multi-agent swarm model from §11, because `?delegate` across module boundaries requires the module system.

The three specific deliverables proposed are exactly right and already partially specified in `LLMLL.md`:
- Multi-file `(import foo.bar ...)` with type-checking
- Namespace isolation per source file
- `llmll-hub` registry (prerequisite for `?scaffold`)

The module system is also the prerequisite for cross-module `def-invariant` verification, making it doubly critical for v0.2.

### Recommendation

Accept verbatim. Update `LLMLL.md §14 v0.2` and the roadmap document to explicitly list these three items. This should be a quick edit, not a discussion.

---

## Priority 4 — Integrate Leanstral as the v0.3 Proof Agent

**Verdict: Yes on integration; cautious on the timing pull-forward.**

### What the proposal gets right

The core observation is correct: the LLMLL v0.3 roadmap item "build a Lean 4 proof-synthesis agent" is now an integration task. Leanstral is Apache 2.0, runs via MCP, outperforms Claude Sonnet on formal proofs at 1/15th the cost per run. The MCP interface fits the hole lifecycle cleanly: `llmll holes --json` emits `?proof-required` as a structured JSON object, the compiler translates LLMLL's `TypeWhere` constraints into Lean 4 theorem obligations, Leanstral returns a verified term, and the compiler stores the certificate. This is the right architecture and it requires only one novel engineering piece — the `TypeWhere` → Lean 4 translation function.

The two-track verification model (Z3/LiquidHaskell for decidable QF linear arithmetic; Leanstral for everything else) is sound and mirrors how the formal verification community actually operates. It means LLMLL developers get automated proof coverage for ~80% of practical contracts and a clear escalation path for the remaining 20%.

### Concerns

1. **The cost figure needs scrutiny.** The $36/run figure is for a specific evaluation benchmark, not arbitrary proof obligations. Real LLMLL `pre`/`post` contracts might be simpler (and cheaper) or might require multi-step dialogues (and be more expensive). Before committing Leanstral to the architecture, run a cost model against realistic LLMLL programs (e.g., the Hangman and Todo implementations from the examples directory).

2. **The pull-forward to late v0.2 is risky.** The proposal argues that since the model is free, only the translation layer remains. This understates the engineering work: the compiler needs to (a) parse and represent LiquidHaskell annotations alongside raw `where` predicates, (b) decide which predicates to escalate (Z3 tracks some, Leanstral tracks others), and (c) store and validate Lean 4 certificates across builds. This is non-trivial. Adding it to v0.2 alongside the module system and LiquidHaskell integration risks overstuffing the milestone. My recommendation is to add the `?proof-required` hole type to the v0.2 *spec*, but leave the Leanstral integration call to v0.3.

3. **Leanstral availability and stability.** It is a brand-new release (March 2026). Making it a load-bearing part of the v0.2 architecture carries availability risk. The integration should have a clear fallback: if Leanstral is unreachable, `?proof-required` holes become `?delegate-pending` holes that block execution but don't fail the build.

### Recommendation

Accept the integration for v0.3 as specified. Extend the `?proof-required` hole type to the v0.2 *spec* only as a forward-compat placeholder. Do not pull the Leanstral call itself into v0.2.

---

## Priority 5 — Minimal Surface Syntax Fixes (Option A)

**Verdict: Mixed. Two of three changes are good; one is counterproductive.**

### Analysis

The professor's framing — "AI agents write JSON, humans write S-expressions, so fix human pain points only" — is the right lens.

**`let` double-bracket confusion → Accept.** The current `(let [[x e1] [y e2]] body)` double-bracket syntax is genuinely confusing and produces a high rate of errors even in examples in `LLMLL.md` itself. The proposed `(let [x = e1, y = e2] body)` is cleaner, though the `=` symbol in a binding context could conflict with the `=` operator. A potentially better form that stays closer to Lisp conventions is `(let [(x e1) (y e2)] body)` — single outer brackets, single inner brackets. Worth a design discussion before committing.

**`(list-empty)` / `(list-append ...)` → list literals: Accept with caution.** List literals `[]` and `[a b c]` are a genuine ergonomic improvement for humans writing tests. The caution is that `[...]` is currently used for parameter lists in `def-logic` and `def-interface`. Overloading it for list literals requires the parser to resolve ambiguity by position, which is doable but must be specced precisely.

**`(pair a b)` → `(, a b)` or `(a , b)`: Reject.** This is a bad tradeoff. `(pair a b)` is unambiguous and readable. The proposed `(, a b)` uses a punctuation mark as a function name, which is unusual syntax that saves two characters while introducing a new precedence and parsing edge case. Infix `(a , b)` is even worse — it creates an ambiguity between a pair constructor and a function call with two arguments. The current syntax is fine; leave it alone.

### Recommendation

Accept the `let` and list literal fixes with minor adjustments; reject the `pair` syntax change.

---

## Summary Table

| Proposal | Verdict | Priority |
|----------|---------|----------|
| JSON-AST as primary interface | **Adopt** | Immediate — unblocks everything else |
| Haskell codegen target | **Adopt with preconditions** | v0.1.2, after proof-of-concept |
| Module system in v0.2 | **Adopt** | Fix the roadmap doc now |
| Leanstral integration | **Adopt for v0.3; spec only in v0.2** | Don't pull the call forward |
| Surface syntax fixes | **Partial** | Accept `let` + list literals; reject `pair` change |

---

## One Broader Observation

The proposals collectively push LLMLL toward a *Haskell ecosystem play*: compiler in Haskell, generated code in Haskell, LiquidHaskell for compile-time verification, Lean 4 (which shares Haskell's intellectual heritage) for interactive proofs. This is coherent and intellectually elegant, but the team should be honest that it narrows the runtime deployment story significantly compared to WASM. The language spec should foreground that WASM remains the long-term deployment target (not just an optional compile flag in v0.4). Otherwise, external contributors and potential adopters will reasonably conclude that LLMLL programs run in Docker, not in sandboxed compute environments.

The core language design — S-expr/JSON surface, holes, contracts, capability model, Command/Response IO — is solid and should not change. The proposals correctly leave it untouched.
