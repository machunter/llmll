# Language Team Resolution: Algorithm W × TDependent Interaction Semantics

> **Status:** Resolution issued 
> **Date:** 2026-04-19  
> **Requested by:** Compiler Team (U2 pre-requisite)  
> **Question:** When Algorithm W unification encounters a `TDependent`, should unification propagate the refinement constraint?

---

## Current Behavior (v0.3.4 baseline)

The type checker strips `TDependent` to its base type during compatibility checks:

```haskell
-- TypeCheck.hs:916-917
compatibleWith (TDependent _ a _) b   = compatibleWith a b
compatibleWith a (TDependent _ b _)   = compatibleWith a b
```

Every other module does the same:

| Module | Behavior |
|--------|----------|
| `Module.hs:346-347` | `compatibleTy` strips to base |
| `AgentSpec.hs:141` | `renderType` strips to base |
| `CodegenHs.hs:662` | `toHsType` strips to base |
| `PBT.hs:164` | `generateValue` strips to base |
| `FixpointEmit.hs` | Does not reference `TDependent` at all |

The constraint expression exists only in two places:
1. **`STypeDef` well-formedness** (TypeCheck.hs:454-458) — checks the constraint is boolean
2. **`AstEmit.hs:175`** — serializes it for JSON round-tripping

**In short:** The refinement constraint is parsed, stored in the AST, checked for well-formedness, and then completely ignored by unification, codegen, and verification. The constraint's verification role is delegated to `pre`/`post` contracts and the liquid-fixpoint layer.

---

## The Design Question

Algorithm W replaces the current `compatibleWith` (a boolean predicate) with substitution-based unification (a function that builds a substitution `Subst = Map Name Type`). When the unifier encounters:

```
unify (TDependent "x" TInt (> x 0))  TInt
```

Three possible semantics:

### Option A: Strip-then-Unify (preserve current behavior)

```haskell
unify (TDependent _ a _) b = unify a b
unify a (TDependent _ b _) = unify a b
```

The refinement constraint is discarded. Unification proceeds on the base type. `PositiveInt` and `int` unify.

### Option B: Propagate-Refinement

```haskell
unify (TDependent x a p) b = do
    subst <- unify a b
    -- Also record that b is constrained by p[x := b]
    addRefinement b (substitute x b p)
    return subst
```

The unifier propagates the constraint into the substitution. `int` touching `PositiveInt` acquires the positivity constraint.

### Option C: Refinement-Subtyping

```haskell
-- TDependent is a subtype of its base type, not equal
unify (TDependent _ a _) b = unify a b        -- PositiveInt → int: OK (upcast)
unify a (TDependent _ b p) = do                -- int → PositiveInt: need proof
    subst <- unify a b
    emitObligation p                            -- generate proof obligation
    return subst
```

The unifier distinguishes the direction: a refined type can flow into its base type, but the reverse requires a proof obligation.

---

## Resolution: Option A (Strip-then-Unify)

**The Language Team rules that unification operates on structural base types only. Refinement constraints are NOT propagated through unification.**

### Rationale

#### 1. Architectural alignment — the Two-Layer Design is intentional

LLMLL's type system is explicitly two-layered ([type-driven-development.md](../docs/design/type-driven-development.md)):

| Layer | Mechanism | Verified by |
|-------|-----------|-------------|
| **Structural** | Types, `where` clauses, `TDependent` base types | Type checker (compile-time) |
| **Behavioral** | `pre`/`post` contracts, constraint expressions | liquid-fixpoint / Leanstral (post-compilation) |

Re-read `TypeCheck.hs:12-13`:

```
-- Dependent types (TDependent) are partially supported: the constraint
-- expression is well-formedness checked but not evaluated at compile time.
```

This is not an oversight — it is the design. Constraints are behavioral specifications verified by the SMT backend. The type checker handles structure. Mixing constraint evaluation into unification would merge these layers.

#### 2. Soundness boundary — the unifier must be decidable

Algorithm W is decidable for System F₁ (first-order, no dependent types). Adding refinement propagation makes unification depend on SMT-satisfiability:

- **Can `int` unify with `(where [x: int] (> x 0))`?** Only if the calling context can prove `x > 0` — this requires an SMT query.
- **Can `PositiveInt` unify with `(where [x: int] (> x 5))`?** Requires checking `(> x 0) → (> x 5)` — an implication query.

This turns the type checker into a verification engine. The whole point of LLMLL's architecture is that verification is a **separate phase** (`llmll verify`, not `llmll check`).

#### 3. FixpointEmit has no TDependent awareness — and shouldn't need it from the unifier

`FixpointEmit.hs` currently does not reference `TDependent` at all. It translates `pre`/`post` contracts to `.fq` constraints. If refinement constraints were propagated through unification, the emitter would need to consume them — but the constraints are already available through the `STypeDef` declarations and the contracts that reference refinement types.

The right architecture is:
```
Type checker (Algorithm W)  →  structural correctness
                             ↓
FixpointEmit                →  reads STypeDef + contracts → .fq
                             ↓
liquid-fixpoint             →  refinement correctness
```

Adding refinement propagation to unification would create a redundant path that **could diverge** from the fixpoint verification.

#### 4. Agent compatibility — agents don't reason about refinement propagation

The agent prompt semantics gap analysis ([agent-prompt-semantics-gap.md](../docs/design/agent-prompt-semantics-gap.md)) already documents that agents struggle with the type system. Option B or C would make hole-filling harder: the agent would need to understand that passing an `int` where a `PositiveInt` is expected requires implicit proof, and the error messages would involve constraint propagation failures that are hard to act on.

With Option A, the boundary is simple: **types check structure, contracts check behavior.** The agent fills a hole structurally, and `llmll verify` checks the behavioral properties.

#### 5. The `TCustom` alias path already handles the practical case

When a user writes `(type PositiveInt (where [x: int] (> x 0)))`, the type checker registers `PositiveInt` as a `TCustom` alias resolved through `expandAlias`. The unifier already handles `TCustom`:

```haskell
-- TypeCheck.hs:942-948
unify ctx expected actual = do
    expected' <- expandAlias expected
    actual'   <- expandAlias actual
    unless (compatibleWith expected' actual') $
        tcTypeMismatch ctx expected' actual'
```

After `expandAlias`, `PositiveInt` becomes `TDependent "x" TInt (> x 0)`, which strips to `TInt` via `compatibleWith`. This means:

- `PositiveInt` and `int` unify ✅ (structurally compatible)
- `PositiveInt` and `string` fail ✅ (structurally incompatible)
- Whether the constraint `(> x 0)` actually holds is checked by `llmll verify` ✅

This is the correct behavior for a two-layer system.

---

## Implications for Algorithm W Implementation (U1–U4)

### What changes in the TDependent rule

The new `unify` function replaces `compatibleWith` with substitution-based unification. For `TDependent`, the rule is:

```haskell
unify :: Type -> Type -> TC Subst
unify (TDependent _ a _) b = unify a b    -- strip constraint, unify base
unify a (TDependent _ b _) = unify a b    -- symmetric
```

The substitution produced by `unify` binds type variables to **structural types** (never to `TDependent` wrappers). If `TVar "a"` unifies with `TDependent "x" TInt p`, the substitution records `a ↦ TInt`, not `a ↦ TDependent "x" TInt p`.

### Why this is safe

The constraint `p` is not lost. It exists in the `STypeDef` declaration and is available to:
- `FixpointEmit.hs` — which can extract it when emitting `.fq` constraints for functions that use refinement-typed parameters
- `WeaknessCheck` (proposed v0.3.5) — which can check whether contracts are consistent with type-level constraints
- The agent prompt — via `llmll spec` which already strips `TDependent` to its base type

### What Algorithm W must NOT do

1. **Must not propagate refinement constraints into the substitution.** `Subst` maps `Name → Type` where `Type` is structural only.
2. **Must not emit errors for `PositiveInt` vs `int` mismatches.** These are structurally compatible and the behavioral difference is a verification concern.
3. **Must not require `expandAlias` to preserve `TDependent` wrappers.** After alias expansion, `TDependent` should strip immediately. (This matches current behavior.)

### What Algorithm W SHOULD do (the actual U2 deliverable)

The `TDependent` interaction is the easy case. The hard parts of U1/U2 are:

1. **Occurs check** — `TVar "a"` cannot unify with `TList (TVar "a")`
2. **Let-generalization** — `let id = (lambda [(x a)] x) in ...` should generalize to `∀a. a → a`
3. **TVar consistency** — `list-head : list[a] → Result[a, string]` must bind `a` consistently across all uses in a single call site
4. **Substitution application** — after `unify`, apply the substitution to all pending type variables before continuing

All of these are structurally independent of `TDependent`. The refinement layer sits above unification and is unaffected.

---

## Future Considerations (v0.6+)

If the type-driven development experiment ([type-driven-development.md](../docs/design/type-driven-development.md)) succeeds and LLMLL moves toward richer dependent types (indexed families, proof terms), this decision may need revisiting. Specifically:

- **Option C (refinement-subtyping)** would become relevant if LLMLL adds subtype coercions and wants the type checker to generate proof obligations automatically.
- **Option B (propagate-refinement)** would become relevant if LLMLL adds type-level computation and wants the type checker to evaluate constraint expressions.

Both of these are explicitly deferred to v0.6+ in the roadmap. For v0.4, Option A is the correct choice.

---

## Summary

| Question | Answer |
|----------|--------|
| Does unification propagate refinement constraints? | **No.** |
| What does the unifier do with `TDependent`? | Strips to base type, unifies structurally. |
| Where are refinement constraints verified? | `FixpointEmit.hs` → liquid-fixpoint / Leanstral. |
| Does the substitution ever contain `TDependent`? | **No.** Type variables map to structural types only. |
| Is this permanent? | For v0.4–v0.5, yes. Subject to revisit if v0.6 type-driven development changes the architecture. |

**Decision is final for the v0.4 scope. U1–U4 may proceed.**
