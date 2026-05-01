# Technical Items from Verification Debate (April 2026)

> **Source:** [`verification-debate.md`](verification-debate.md)  
> **Context:** External formal methods review of LLMLL's verification claims. The review surfaced concrete engineering obligations that the compiler and language teams should track.

---

## For the Compiler Team

### TCB Hardening (Priority: Medium)

The debate established that `CodegenHs.hs` and `LeanTranslate.hs` are **unverified members of the Trusted Computing Base**. If either is wrong, downstream guarantees (GHC type safety, Lean proof validity) collapse silently.

**Action items:**

- [ ] **[CT] CodegenHs round-trip testing.** For each generated `Main.hs`, parse it back and compare AST structure against the LLMLL source. Catches codegen bugs that produce well-typed but semantically wrong Haskell. Start with the 5 example programs.

- [ ] **[CT] LeanTranslate golden tests.** For each supported contract pattern (linear arithmetic, list induction, quantified variables), generate the Lean theorem and compare against a hand-verified golden file. Currently LeanTranslate is tested only via mock — need to verify the *content* of translations, not just that they're produced.

- [ ] **[CT] Fragment classification audit.** The `:simple`/`:inductive`/`:unknown` classification in `normalizeComplexity` (HoleAnalysis.hs) is heuristic. Audit for properties that straddle fragments, e.g., `sorted(xs) ⇒ sum(xs) >= 0`. Document which patterns are currently misclassified and add tests for edge cases.

### Trust Propagation Robustness (Priority: High)

Trust-level propagation is now the system's primary answer to the compositionality question. It must be correct.

- [ ] **[CT] Cross-module trust propagation test.** Write a multi-module test where Module A exports a function with an `(asserted)` contract, Module B imports and uses it with a `(proven)` contract. Verify that Module B's verification level is capped at `VLAsserted`, not `VLProven`.

- [ ] **[CT] Epistemic drift detection.** Add a `llmll verify --trust-report` flag that outputs a summary: how many contracts are proven/tested/asserted, and which "proven" conclusions depend on "asserted" assumptions (transitive closure). This is the tooling to combat epistemic drift in larger programs.

### Partial Correctness Documentation (Priority: Low)

- [ ] **[CT] Add `--warn-nonterminating` flag.** For `letrec` without `:decreases`, emit a warning: "This function may not terminate; postcondition verified under partial correctness only." Currently only `def-logic` self-recursion warns. Extend to `letrec`.

---

## For the Language Team

### Semantic Anchor Decision (Priority: High)

The debate resolved a key design question:

> **LLMLL is a Haskell-generating language with auxiliary verification metadata.**
> The semantics of an LLMLL program IS the generated Haskell. Contracts, trust levels, and verification metadata are external overlays.

**This is now a design decision**, not an open question. It should be reflected in `LLMLL.md`:

- [ ] **[SPEC] Add §0.1 "Semantic Foundation."** One paragraph stating that LLMLL's operational semantics are defined by the generated Haskell program, and that contracts/verification levels are a verification overlay, not part of the operational semantics.

### Effect System Specification (Priority: Medium)

The debate exposed that LLMLL's effect system (capabilities, `Command` ADT, typed effect rows) is **checked structurally but not formally specified**. A PL reviewer asked: "Are effects algebraic, monadic, or capability-based-but-extrinsic?"

- [ ] **[SPEC] Add §3.3 "Effect Model."** Define:
  - Effects are **capability-based with static checking** (compile-time type error if undeclared)
  - The `Command` ADT is the semantic model (monadic, fixed interpretation)
  - WASM enforcement is runtime hardening of the same policy
  - Not algebraic (no handlers), not row-polymorphic (capabilities are per-function, not variables)

### `(trust ...)` Mechanism (Priority: High)

`(trust ...)` is now the system's soundness boundary — "sound modulo trust declarations." It carries more weight than the current spec suggests.

- [ ] **[SPEC] Elevate `(trust ...)` in LLMLL.md.** Currently mentioned in §6. Should be more prominent:
  - Every `(trust ...)` is a point where the user/agent explicitly accepts responsibility
  - Trust boundaries propagate through dependencies
  - Future tooling should make trust declarations uncomfortable (warnings, review pressure)

### Specification Adequacy (Priority: Low — inherent problem)

User-provided specifications are effectively part of the TCB. A wrong spec means the system "verifies" the wrong thing. This is inherent to all specification systems, but should be documented.

- [ ] **[SPEC] Add a note in §6:** "The system verifies code against declared specifications. The correctness and completeness of specifications is the user's (or lead agent's) responsibility. Property-based testing (`check`/`for-all`) can falsify weak specifications but cannot guarantee specification adequacy."

---

## Future Work (from the debate, not yet roadmapped)

### Minimal Core Calculus

The reviewer's final suggestion: design a minimal core calculus that *explains* LLMLL's behavior without re-implementing it. Not a full formalization — a "semantic spine" that would let PL researchers assess the system's properties.

This would involve:
- A small dependently-typed core with refinement predicates
- A trust modality (`★` for proven, `?` for asserted)
- A formal statement of "sound modulo trust"
- ~10 pages, publishable as a workshop paper

**Not blocking any current work.** But would significantly strengthen credibility with the formal methods community.

### Fragment Classification Formalization

Currently heuristic. A formal decision procedure for property classification would:
- Guarantee no property straddles fragments
- Enable cross-verifier consistency arguments
- Allow agents to predict which verifier will handle their contracts

### Cross-Verifier Consistency

If the same property is expressible in both SMT and Lean, the two verifiers should agree. Currently not guaranteed. A future mitigation: for properties that straddle fragments, verify in both and compare results (redundant verification).
