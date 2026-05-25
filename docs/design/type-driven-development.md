# Type-Driven Development for Agents: From Indexed Types to Obligation-Guided Coding

> **Status:** Dormant — partially promoted, R1 residual (obligation-guided part shipped v0.10; indexed-types residual is research-track-only per roadmap "What's NOT on this Roadmap")  
> **Original date:** 2026-04-11  
> **Major revision:** 2026-05-01  
> **Source:** Professor's five-round review + language team consensus (2026-05-01)  
> **Reviewed:** Language Team (2026-05-01) — approved with two P0 corrections (resolved)  
> **Key decision:** LLMLL preserves the Idris workflow insight; v0.10 implements it through obligations, not indexed types.

---

## 1. Executive Summary

The original type-driven development hypothesis is preserved: rich specifications help agents construct programs step by step. What changed is the implementation path. LLMLL does not pursue Idris-style indexed types for v0.10. Instead, it exposes type obligations, contract obligations, and trust obligations as structured machine-readable feedback. This gives agents much of the workflow benefit of dependent development without requiring a dependent typechecker.

| Aspect | Decision |
|---|---|
| **Original insight** | Rich specifications guide construction so strongly that filling holes becomes "matching the only shape that satisfies the obligations." Confirmed. |
| **v0.10 milestone** | Obligation-guided agent coding — structured obligation reports (JSON) exposing type, contract, and trust obligations. Promoted from this document. |
| **Research track** | Indexed types (`Vect n a`, GADTs, type-level arithmetic, bidirectional typechecking). Explicitly deferred. |
| **Architecture** | Types check structural shape (Algorithm W). Contracts check behavioral obligations (liquid-fixpoint). Trust reports classify evidence quality. All three channels feed the agent. |

---

## 2. Terminology

| Term | Meaning in LLMLL | Note |
|---|---|---|
| **Refinement type alias** | A `(where [x: base] predicate)` annotation — the predicate is checked by the verification layer or enforced at runtime. | Renamed from "Dependent Type" in v0.8.1a. |
| **Obligation-guided coding** | Agent workflow where the compiler emits structured obligations (type, contract, trust) and the agent fills holes iteratively using obligation feedback. | v0.10 scope. |
| **Type-driven development** | In the Idris sense: indexed types encode the specification in the type, and the typechecker rejects bad inhabitants. | Research track only. Not shipped. |
| **`TDependent`** | Internal AST constructor name. Historical — predates the rename. Implementation detail, not a user-facing concept. |

---

## 3. The Original Insight

When an AI agent encounters a `?hole`, its accuracy depends on how constrained the hole is. The more the specification narrows the space of valid expressions, the less the agent can hallucinate.

| Approach | Constraint strength | Agent freedom | Hallucination risk |
|---|---|---|---|
| Untyped hole | No constraint | Maximum | High |
| Simple type (`int → int`) | Shape only | High | Medium |
| Contract (`pre`/`post`) | Behavioral spec | Medium (must satisfy checker) | Medium (can satisfy incorrectly) |
| Rich obligations (type + contract + trust) | Structural + behavioral + evidentiary | Low | Low |
| Full dependent type (Idris-style) | Structural + behavioral (fused) | Lowest | Lowest |

**The key argument:** Step-by-step hole-filling decomposes a hard problem (produce a program satisfying a behavioral spec) into a sequence of easier problems (fill a hole where the obligations leave almost no choice). This is where LLMs are strong (pattern-matching against structured constraints) and weak (multi-step reasoning about behavioral correctness).

This insight is independent of *how* the constraints are expressed. Idris uses indexed types. LLMLL uses obligations. Both narrow the search space.

---

## 4. Two Architectures for the Same Workflow

### 4.1 The Idris Model: Type IS Specification

In Idris, the type carries the full specification. Development proceeds by:

1. **Write the type signature** — this is the spec
2. **Create a hole** — `?impl`
3. **Ask the compiler** what the hole's type is, given the context
4. **Case-split** on a variable — the compiler generates all branches with updated types
5. **Repeat** — each branch has a simpler type, narrowing the space of valid programs
6. **The implementation writes itself** — once the types are specific enough, there's often only one valid expression

```idris
-- Research-track architecture — NOT in v0.10 scope

data Vect : Nat -> Type -> Type where
  Nil  : Vect 0 a
  (::) : a -> Vect n a -> Vect (S n) a

head : Vect (S n) a -> a    -- type guarantees non-empty
head (x :: _) = x           -- only one case — empty is impossible
```

No contract needed. The type `Vect (S n) a` makes the precondition structural.

### 4.2 The LLMLL Model: Three Channels of Obligation

LLMLL separates the specification into three independent feedback channels:

```lisp
;; v0.10 architecture — obligation-guided coding

(def-logic safe-head [xs: list[a]]
  :return Result[a, string]
  (pre (> (list-length xs) 0))
  (post (match result
    (Success v) (= v (list-head xs))
    (Error _)   true))
  ?hole)
```

The agent receives a structured obligation report:

```json
{
  "kind": "hole-obligation",
  "hole": "?hole",
  "function": "safe-head",
  "expected_type": "Result[a, string]",
  "contract_context": {
    "preconditions": ["(> (list-length xs) 0)"],
    "postcondition_goal": "(match result (Success v) (= v (list-head xs)) (Error _) true)"
  },
  "path_condition": [],
  "in_scope": { "xs": "list[a]" },
  "assumptions": [{ "name": "list-length", "kind": "runtime-primitive" }],
  "suggestions": [{
    "expression": "(match xs ((cons head _) (Success head)) (_ (Error \"empty\")))",
    "reason": "satisfies postcondition under precondition (list-length xs) > 0"
  }]
}
```

The agent fills the hole using the obligation report, then the verifier classifies the evidence.

### 4.3 The "Guide vs. Prove" Distinction

The fundamental difference between the two architectures:

| Architecture | During construction | During checking | What the agent sees |
|---|---|---|---|
| **Idris-style indexed types** | Type indices refine the search space directly | Typechecker proves inhabitance of indexed type | Expected type narrows possible programs |
| **LLMLL obligation-guided coding** | Types, contracts, and evidence obligations guide the search | Verifier / tester / runtime / trust report classify the result | Structured obligation report with type, logic, path, and trust context |

**Idris asks:** "Can this program inhabit the indexed type?"  
**LLMLL asks:** "Given this structural type, contract, path condition, and evidence state, what obligations remain?"

Both guide the agent step by step. Idris constrains construction (the typechecker rejects bad values). LLMLL validates results (the verifier/tester/runtime classifies evidence). For agents, LLMLL's three-channel model provides *richer feedback* — at the cost of not rejecting bad constructions until after they are written.

### 4.4 Side-by-Side Comparison

| Goal | Idris route (🔬 research) | LLMLL v0.10 route (🔲 planned) |
|---|---|---|
| Guide the agent step by step | Indexed types and dependent pattern matching | Typed holes, branch obligations, contract context, trust obligations |
| Reject bad construction early | Typechecker rejects impossible inhabitants | Verifier/tester/trust report emits structured obligations |
| Main mechanism | Types are specifications | Types + contracts + evidence records |
| Feedback latency | Immediate (type error) | Fast (verifier + trust report cycle) |
| Architecture cost | Requires dependent type system, bidirectional TC, erasure | Reuses existing Algorithm W + contracts + verifier |

---

## 5. LLMLL v0.10: Obligation-Guided Agent Coding

> Cross-reference: [compiler-team-roadmap.md](../compiler-team-roadmap.md) § v0.10 for implementation items (OBLIG-0 through OBLIG-B).

### 5.1 The Three Obligation Channels

| Channel | Question answered | Source | Example |
|---|---|---|---|
| **Type obligations** | What shape must this expression have? | Type checker (`--sketch`) | `expected_type: "Result[a, string]"` |
| **Contract obligations** | What logical property must it satisfy? | Verifier (liquid-fixpoint) | `postcondition_goal: "(>= result 0)"` |
| **Trust obligations** | What evidence is still missing? | Trust report (v0.8.1b evidence model) | `assumptions: [{ "name": "sha1", "kind": "external-opaque" }]` |

No other agent-facing system integrates all three channels into a single machine-readable feedback format.

### 5.2 What v0.10 Delivers

| Item | Description |
|---|---|
| **Enriched typed holes** | `CheckoutToken` extended with contract preconditions, postcondition goal, path condition, assumption set |
| **Structured obligation JSON** | Machine-readable report for each `?hole`, unproven contract, and failed call-site precondition |
| **`EMatch` branch obligations** | Per-branch context with constructor-refined bindings and sub-goals |
| **Repair suggestions** | `ObligationMining.hs` proposes: add guard, strengthen precondition, choose candidate expression |
| **Agent repair loop** | `llmll verify --obligations` → orchestrator consumes → patch → re-verify → trust report |
| **Obligation quality benchmark** | Validates that reports are sufficient for mechanical repair |

### 5.3 Non-Goals for v0.10

> [!IMPORTANT]
> The following are explicitly **not in v0.10 scope**. They remain in the research track.

- Length-indexed vectors (`Vect n a`)
- State-indexed commands
- GADTs
- Type-level naturals
- Type-level arithmetic
- Dependent pattern matching (branch type refinement)
- Bidirectional typechecking
- Proof terms as values (`Refl`, `Cong`)
- Erasure analysis

This list protects the roadmap from sliding back into "build half of Idris."

---

## 6. Obligation Lifecycle

v0.10 is not "emit more JSON." It is a workflow:

```
hole or failed proof
  → structured obligation
    → agent repair
      → re-check
        → updated evidence record
          → trust report
```

### 6.1 Obligation Sources

| Source | Produces |
|---|---|
| Type checker (`llmll check`) | Typed hole with expected type, in-scope variables |
| Verifier (`llmll verify`) | Unproven contract clause, failed call-site precondition |
| Trust report (`llmll verify --trust-report`) | Missing evidence, assumption warnings, transitive degradation |

### 6.2 Obligation Shape

Each obligation contains:

| Field | Description |
|---|---|
| `kind` | `hole-obligation`, `contract-obligation`, `precondition-obligation` |
| `function` | Enclosing function name |
| `expected_type` | Structural type of the expression to fill |
| `contract_context` | Relevant preconditions and postcondition goal |
| `path_condition` | Guards accumulated from `EIf`/`EMatch` branches (from `bodyToPred` FlatPaths) |
| `in_scope` | Variables and their types available at the hole |
| `available_functions` | Functions callable from this context |
| `assumptions` | Unverified dependencies (from v0.8.1b `ContractStatus.csAssumptions`) |
| `suggestions` | Concrete repair candidates with justification |

### 6.3 Obligation Status

| Status | Meaning |
|---|---|
| **open** | No evidence yet — agent must act |
| **discharged** | Verified by solver, tests, or runtime assertion |
| **deferred** | Explicitly deferred via `(weakness-ok)` with reason |
| **asserted** | Runtime assertion only; no compile-time evidence |

### 6.4 Obligation Consumers

| Consumer | Uses obligations for |
|---|---|
| Agent | Repair loop: fill hole → re-check → iterate |
| Human developer | Review open obligations before merge |
| CI pipeline | Gate: no new open obligations without `(weakness-ok)` |
| Trust report | Aggregate evidence quality per function |

---

## 7. Infrastructure Inventory

### Status markers

| Marker | Meaning |
|---|---|
| ✅ | Shipped and tested |
| 🔲 | Planned (design not yet started) |
| 🔬 | Research track |

### Current state (May 2026)

| Ingredient | Status | Version | Notes |
|---|---|---|---|
| Typed holes with inferred constraints | ✅ | v0.2 | `--sketch` mode |
| `?hole` → agent fills → compiler re-checks | ✅ | v0.2 | `?delegate` workflow |
| Refinement type aliases with `where` clauses | ✅ | v0.1 | `TDependent` (internal name) |
| Pattern matching with exhaustiveness checking | ✅ | v0.1 | `checkExhaustive` |
| Context-aware checkout (Γ, τ, Σ) | ✅ | v0.3.5 | `CheckoutToken` with `ctInScope`, `ctExpectedReturnType`, `ctAvailableFunctions` |
| Skeleton generation from signatures | ✅ | v0.4 | Lead Agent |
| Obligation mining (basic) | ✅ | v0.4 | `ObligationMining.hs` |
| Body-faithful verification conditions | ✅ | v0.8.0 | `bodyToPred` for QF-LIA fragment |
| Path-sensitive constraint emission | ✅ | v0.8.0 | `EIf` → `FlatPath` guards |
| Orchestrator retry loop | ✅ | v0.3.5 | Python orchestrator `llmll-orchestra` |
| Structured evidence model (EVID-0) | ✅ | v0.8.1b | Four-tier `DisplayLevel` partial order |
| Assumption taxonomy | ✅ | v0.8.1b | `AKRuntimePrimitive`, `AKCompilerBuiltin`, `AKExternalOpaque` |
| Compositional verification (`EApp`) | 🔲 | v0.9 | Assume-guarantee encoding, correct precondition polarity |
| `EMatch` two-path encoding for `Result` | 🔲 | v0.9 | Path-sensitive per-constructor obligations |
| Call-site precondition diagnostics | 🔲 | v0.9 | Structured repair suggestions |
| Enriched typed holes (obligation JSON) | 🔲 | v0.10 | OBLIG-1 |
| `EMatch` branch obligations | 🔲 | v0.10 | OBLIG-3 |
| Repair suggestions from `ObligationMining` | 🔲 | v0.10 | OBLIG-4 |
| Agent repair loop integration | 🔲 | v0.10 | OBLIG-5 |
| Obligation quality benchmark | 🔲 | v0.10 | OBLIG-B |
| Indexed types (`Vect n a`) | 🔬 | — | Requires dependent type system |
| Interactive case-split (`llmll split`) | 🔬 | — | Requires indexed types |
| Type-level computation | 🔬 | — | Requires type-level evaluator |
| Proof terms as values | 🔬 | — | Requires rethinking `Expr` |

The infrastructure gap between "what exists" and "what v0.10 needs" is much smaller than originally estimated in April 2026.

---

## 8. Obligation Quality Benchmark

The success metric for v0.10:

> *Can a simple repair loop fill common holes using only the structured obligation report, without hidden compiler knowledge?*

### 8.1 Quality Criteria

| Criterion | Question |
|---|---|
| **Completeness** | Does the report include all information needed to attempt a repair? |
| **Minimality** | Does it avoid dumping irrelevant compiler state? |
| **Grounding** | Are suggestions tied to actual path conditions and contracts? |
| **Actionability** | Does it suggest concrete repairs: guard, strengthen precondition, choose expression, split branch? |
| **Stability** | Does the same source produce stable obligation IDs across small edits? |

### 8.2 Benchmark Cases

| Program | Hole | Required obligation fields | Expected candidate |
|---|---|---|---|
| `withdraw(balance, amount)` | body | expected type, path condition (`balance >= amount`), postcondition goal (`result >= 0`), in-scope vars | `(- balance amount)` |
| `clamp(value, lo, hi)` | body | expected type, two-branch path conditions | `(if (< value lo) lo (if (> value hi) hi value))` |
| `safe-head(xs)` | body | expected type (`Result[a, string]`), `EMatch` branch obligations (Cons vs Nil) | `(match xs ...)` with two arms |
| `abs(n)` | body | expected type, postcondition goal (`result >= 0`), single branch split | `(if (< n 0) (- 0 n) n)` |

### 8.3 Evaluation Protocol

For each benchmark case:

1. **Input:** LLMLL source with a `?hole` and contract
2. **Run:** `llmll verify --obligations` → obligation report JSON
3. **Check:** Does the report contain all required obligation fields?
4. **Check:** Does the report contain at least one repair suggestion that would close the obligation?
5. **Check:** If a simple agent loop applies the suggestion, does `llmll verify` succeed?

A benchmark case passes if all three checks succeed.

---

## 8.4 Edge Cases for OBLIG-0 Design

> **Source:** Language Team review (2026-05-01). These edge cases must be addressed in the OBLIG-0 design spec before implementation.

| # | Edge case | Problem | Where to address |
|---|---|---|---|
| EC-1 | **Polymorphic holes** | A `?hole : a` with no monomorphic grounding has an unconstrained type. The obligation report must distinguish "type is polymorphic (any value of any type)" from "type is unknown (inference failed)." | OBLIG-0 design — obligation should report unconstrained type variable explicitly |
| EC-2 | **Obligation ID stability under alpha-renaming** | If variable names change but structure is identical, obligation IDs should remain stable. Naive AST-position-based IDs would break across renames. | OBLIG-0 design — IDs should be content-addressed or path-based, not position-based |
| EC-3 | **N-ary sum type branch obligations** | v0.9 handles `Result` (2 constructors). User-defined sum types (`TSumType`) can have N constructors. Branch obligations must generalize to N paths. | OBLIG-3 implementation — generalize from 2-path to N-path |
| EC-4 | **Repair suggestion soundness scope** | Suggestions from `ObligationMining.hs` are candidates, not proofs. A suggestion may satisfy one path but violate another. The report must not imply suggestions are verified. | OBLIG-4 — label suggestions as "suggested, not verified" |
| EC-5 | **Decidability classification outside QF-LIA** | Obligations involving non-linear arithmetic, string predicates, or recursive functions may be undecidable. The report should flag these so agents know the verifier cannot discharge them automatically. | OBLIG-2 — add `"decidability": "undecidable"` field for obligations outside the decidable fragment |

---

## 9. Research Track: Indexed Types

> This section describes work that is **not on the v0.10 roadmap**. It is included for completeness and to record the long-term direction.

### 9.1 What Indexed Types Would Enable

True indexed types (`Vect n a`) would make preconditions structural rather than behavioral:

```idris
-- Research-track only

head : Vect (S n) a -> a    -- impossible to call on empty
append : Vect n a -> Vect m a -> Vect (n + m) a   -- length preserved by type
```

The typechecker would reject bad programs at compile time, with no SMT round-trip. For agents, this means even tighter search-space narrowing.

### 9.2 Requirements

| Requirement | Impact | Effort |
|---|---|---|
| Type-level naturals | New kind in the type system | High |
| Type-level computation (`n + m`) | Type-level evaluator in `TypeCheck.hs` | High |
| GADT-style pattern matching | Branch type refinement | High |
| Dependent elimination | Return type depends on matched constructor | High |
| Bidirectional typechecking | Replaces Algorithm W (Dunfield-Krishnaswami style) | Very high |
| Erasure analysis | Which type-level terms exist at runtime | Medium |

Each is a multi-week project with deep interactions with the existing type inference engine. Algorithm W does not handle GADTs.

### 9.3 Why Not v0.10

v0.10 achieves approximately 80% of the agent-facing benefit of Idris-style development through richer obligation reporting, without requiring any of the above. The indexed-type approach would:

- Require fundamental changes to `TypeCheck.hs` (Algorithm W → bidirectional)
- Risk scope creep — "just add `Vect`" quickly becomes "implement half of Idris"
- Compete with verification-boundary hardening for engineering time
- Not compose with the existing contract/trust architecture without significant integration work

### 9.4 Promotion Criteria

To promote indexed types from research to roadmap:

1. Design spec with typing rules for indexed types
2. Bidirectional typechecking migration plan
3. Erasure strategy
4. Demonstration that the indexed-type fragment composes with `bodyToPred` and the evidence model
5. Effort estimate accepted by both teams

### 9.5 Relationship to v0.10

v0.10 (obligation-guided coding) does not require indexed types and does not change Algorithm W. Indexed types would be an orthogonal addition. If promoted, they would extend the obligation report with index-refined expected types — but the obligation architecture itself is independent.

---

## 10. Resolved Open Questions

### Q1: Does step-by-step type-guided deduction actually improve LLM accuracy?

**Resolved (2026-05-01).** The hypothesis is confirmed in principle. The professor agrees that rich specifications help agents construct programs step by step. The implementation path is obligation-guided coding (v0.10), not indexed types. Empirical validation will come from the obligation quality benchmark (§8).

### Q2: Can the orchestrator automate the case-split workflow?

**Resolved (2026-05-01).** Reframed. The orchestrator does not perform Idris-style case-splits. Instead, it consumes structured obligation reports from `llmll verify --obligations`, patches the source using repair suggestions, and re-verifies. The agent sees branch obligations from `EMatch` (OBLIG-3), which serve the same role as case-split results — but generated by the verifier, not the typechecker.

### Q3: Should LLMLL adopt Idris's proof terms, or keep proofs external?

**Resolved (2026-05-01).** External proofs via liquid-fixpoint (and eventually Leanstral). LLMLL does not embed proof terms in the program. Agents produce code, not proofs. The evidence model (v0.8.1b) classifies the proof status; agents do not need to manipulate proof objects.

### Q4: What if types-as-specs makes contracts obsolete?

**Resolved (2026-05-01).** Types and contracts are permanent separate layers in LLMLL through v0.10. Types check structural shape under Algorithm W. Refinement predicates and contracts express behavioral obligations checked by the verifier, runtime assertions, tests, or evidence reports. LLMLL does not attempt to make contracts obsolete by moving all specifications into the type system.

Algorithm W operates on stripped structural types. Refinement predicates are preserved for obligation generation but erased for unification. This was formalized in the [Algorithm W × TDependent Resolution](algorithm_w_tdependent_resolution.md) (Strip-then-Unify, Option A).

### Q5: Obligation completeness benchmark (NEW — open)

**Open.** How do we measure whether an obligation report is "sufficient" for an agent? The five quality criteria (§8.1) and four benchmark cases (§8.2) define a starting point. The v0.10 success metric is:

> *Can a simple repair loop fill common holes using only the structured obligation report, without hidden compiler knowledge?*

This requires empirical validation during v0.10 implementation.

---

## Appendix: Document History

| Date | Change |
|---|---|
| 2026-04-11 | Original document: "Type-Driven Development in LLMLL." Hypothesis stated. `Vect n a` minimal experiment proposed. Deferred to v0.5+. |
| 2026-05-01 | Major revision. Obligation-guided agent coding promoted to v0.10. Indexed types deferred to research track. Four open questions resolved. Obligation lifecycle, quality benchmark, and non-goals added. Title updated. Professor's "guide vs. prove" distinction incorporated. |
| 2026-05-01 | Language Team review: two P0 corrections (`first` → `list-head` in safe-head example; EVID-0 status updated to shipped). Five edge cases added (EC-1 through EC-5) for OBLIG-0 design. |
