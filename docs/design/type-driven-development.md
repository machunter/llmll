# Type-Driven Development in LLMLL

> **Status:** Design exploration  
> **Date:** 2026-04-11  
> **Context:** Tension between LLMLL's two-layer model (types + contracts) and Idris-style type-driven development where the type IS the specification.  
> **Key question:** Does step-by-step type-guided deduction help AI models fill holes more accurately?

---

## Current Model: Two Layers

LLMLL separates structural and behavioral properties:

| Layer | Mechanism | Example | Verified by |
|---|---|---|---|
| **Types** | `where` clauses, sum types, `TPair` | `(type PositiveInt (where [x: int] (> x 0)))` | Compiler (compile-time) |
| **Contracts** | `pre`/`post` | `(pre (> amount 0))` | liquid-fixpoint / Leanstral |

Both can express the same property. `(pre (> amount 0))` and typing the parameter as `PositiveInt` do the same job. The separation is currently deliberate: types are fast (compile-time), contracts are thorough (SMT/proof).

---

## The Idris Model: Type IS Specification

In Idris, you don't write contracts. The type carries the full specification. Development proceeds by:

1. **Write the type signature** — this is the spec
2. **Create a hole** — `?impl`
3. **Ask the compiler** what the hole's type is, given the context
4. **Case-split** on a variable — the compiler generates all pattern match branches with updated types
5. **Repeat** — each branch has a simpler type, narrowing the space of valid programs
6. **The implementation writes itself** — once the types are specific enough, there's often only one valid expression

### Example: safe head

**Idris:**
```idris
data Vect : Nat -> Type -> Type where
  (::) : a -> Vect n a -> Vect (S n) a

head : Vect (S n) a -> a    -- type guarantees non-empty
head (x :: _) = x           -- only one case — empty is impossible
```

No contract needed. The type `Vect (S n) a` makes the precondition structural.

**LLMLL today:**
```lisp
(def-logic safe-head [xs: list[a]]
  (pre (> (list-length xs) 0))   ;; behavioral — verified by SMT
  ...)
```

The precondition is a runtime/SMT concern, not a type-level guarantee.

---

## Why This Matters for AI Agents

The critical insight: **type-driven deduction may help AI models fill holes more accurately**.

### The hypothesis

When an AI agent encounters a `?hole`, its accuracy depends on how constrained the hole is. The more the type system narrows the space of valid expressions, the less the agent can hallucinate.

| Approach | Constraint strength | Agent freedom | Hallucination risk |
|---|---|---|---|
| Untyped hole | No constraint | Maximum | High |
| Simple type (`int → int`) | Shape only | High | Medium |
| Contract (`pre/post`) | Behavioral spec | Medium (must satisfy checker) | Medium (can satisfy incorrectly) |
| Rich dependent type | Structural + behavioral | Low | Low |

With Idris-style types, the agent doesn't need to "understand" the specification — it just needs to produce an expression that type-checks. The type system does the reasoning. This is exactly where LLMs are strong (pattern matching against type signatures) and weak (complex multi-step reasoning about behavioral correctness).

### The workflow comparison

**Current LLMLL (contracts):**
```
Agent sees:  ?impl : int → int → int
             (pre (> b 0))
             (post (= result (- a b)))

Agent must:  1. Read the contract
             2. Understand what it means
             3. Produce an implementation that satisfies it
             4. Wait for SMT feedback if wrong
```

**Idris-style LLMLL (types):**
```
Agent sees:  ?impl : (a : Int) → (b : PositiveInt) → Eq result (minus a b)

Agent must:  1. Read the type
             2. Case-split on b (compiler guides this)
             3. Fill the only well-typed expression

The type system rejects wrong answers immediately — no SMT round-trip.
```

The Idris model gives the agent **immediate, cheap feedback** at every step. The contract model gives **delayed, expensive feedback** (wait for SMT/Leanstral). For an agent swarm doing one-shot fills, immediate feedback is better.

### The step-by-step deduction advantage

Idris's interactive mode breaks hole-filling into a sequence of small steps:

1. Start with `?impl : Vect (S n) a → a`
2. Case-split on the input → compiler generates `(x :: xs) → ?rhs`
3. Now `?rhs : a` and `x : a` is in scope
4. The only value of type `a` in scope is `x`
5. Agent fills `x` — done

Each step has a tiny search space. An LLM can handle each step with high accuracy. Compare this to the current model where the agent sees the entire spec at once and must produce the full implementation in one shot.

**This is the key argument: type-driven development decomposes a hard problem (fill a hole satisfying a behavioral spec) into a sequence of easy problems (fill a hole where the type leaves almost no choice).**

---

## What LLMLL Would Need

### Already present

| Ingredient | Status |
|---|---|
| Typed holes with inferred constraints | ✅ `--sketch` mode |
| `?hole` → agent fills → compiler re-checks | ✅ `?delegate` workflow |
| Dependent types with `where` clauses | ✅ `TDependent` |
| Pattern matching with exhaustiveness checking | ✅ `checkExhaustive` |

### Missing (v0.5+ candidates)

| Feature | What it enables | Effort |
|---|---|---|
| **Indexed families** (`Vect n a`) | Non-emptiness, length-preservation as types | Medium — new `Type` constructor, parser, codegen |
| **Proof terms as values** | `Refl`, `Cong` — proofs are first-class expressions | High — requires rethinking `Expr` |
| **Interactive case-split** | `llmll split ?hole variable` → compiler generates branches | Medium — new CLI command + TypeCheck extension |
| **Type-level computation** | `(+ n 1)` at the type level | High — requires type-level evaluator |
| **Totality checking** | Guarantee termination (required for types-as-proofs) | Medium — extends `:decreases` to a totality checker |

### The minimal experiment

The smallest test of this hypothesis:

1. Add `Vect n a` as a built-in indexed type (like `list[a]` but length-indexed)
2. Add `llmll split ?hole <variable>` CLI command — compiler generates case-split branches with updated types
3. Run an agent through a 3-step type-driven fill of `safe-head`
4. Compare accuracy against the contract-based approach

If the agent succeeds in 3 steps with no SMT round-trips, the hypothesis is validated.

---

## The Case for Deferral

While the hypothesis is compelling, pursuing this now would:

- Require significant changes to `Syntax.hs` (indexed type families), `TypeCheck.hs` (type-level evaluation), and `CodegenHs.hs` (generating GADT-style Haskell)
- Compete with v0.3.1 (Event Log + Leanstral) and v0.4 (WASM hardening) for engineering time
- Risk scope creep — "just add Vect" quickly becomes "implement half of Idris"

The pragmatic path: **ship v0.3.1 and v0.4, then run the minimal experiment as a v0.5 spike.** If the experiment shows measurable accuracy improvement for agent hole-filling, promote it to a full feature.

---

## Open Questions

> **Q1: Does step-by-step type-guided deduction actually improve LLM accuracy?**
>
> This is empirically testable. Compare:
> - (A) Agent fills `?impl` with contract spec, one-shot
> - (B) Agent fills `?impl` via 3-step type-driven case-split
>
> Measure: success rate, iterations needed, token cost.

> **Q2: Can the orchestrator automate the case-split workflow?**
>
> In Idris, the *human* decides when to case-split and on which variable. In LLMLL, the *orchestrator* would make this decision. The compiler would need to expose a "suggest split" API: given a hole and its type, recommend which variable to split on.

> **Q3: Should LLMLL adopt Idris's proof terms, or keep proofs external (Leanstral)?**
>
> Idris embeds proofs in the program (`Refl : a = a`). LLMLL keeps proofs external (Leanstral returns a proof certificate). The external model is simpler and aligns with the agent-first architecture (agents produce code, not proofs). But embedded proofs would enable type-driven deduction without any external dependency.
>
> Leaning toward: external proofs for now, embedded proofs as a v0.6+ research direction.

> **Q4: What if types-as-specs makes contracts obsolete?**
>
> If dependent types are expressive enough, `pre`/`post` contracts become redundant. The stratified verification system (v0.3) would become a compatibility layer. This is fine — the contracts → types migration can be gradual, and the verifier infrastructure (liquid-fixpoint, Leanstral) remains useful for the decidable fragments.
