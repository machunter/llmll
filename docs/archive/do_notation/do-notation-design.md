# `do`-Notation Design: Pair-Thread Model

> **Prepared by:** Professor Team (Lead Consultant, Formal Language Design)
> **Date:** 2026-04-05
> **Revision:** 2026-04-05 r2 — Language team review: PR 1 blast radius, three explicit acceptance criteria
> **Revision:** 2026-04-05 r3 — Language team Disagreement 2: §9.6 exposition corrected; `first`/`second` polymorphism documented
> **Revision:** 2026-04-05 r4 — Language team Disagreement 3: anonymous step threading formalised; silent state-loss hazard documented; `--sketch` clarification closed
> **Revision:** 2026-04-05 r5 — Decision 7: pair destructuring in `let`; BNF and §13.4 spec language; PR 4; §9.6 exposition updated
> **Revision:** 2026-04-05 r6 — Concern 1: `let-binding` BNF simplified to `"[" pattern expr "]"` per team review
> **Revision:** 2026-04-05 r7 — Concern 2: §5a Note block clarifies why `seq-commands` appears in desugar but not in source
> **Revision:** 2026-04-05 r8 — Compiler team clarification: Option A chosen for `ELet` ADT (`Name → Pattern`); PR 4 blast radius fully specified
> **Revision:** 2026-04-05 r9 — Duplicate `Examples` block in §5b removed (compiler team review)
> **Status:** Approved — Pending Implementation
> **Audience:** Language Team + Compiler Team
> **Governs:** LLMLL v0.3 `do`-notation feature (`compiler-team-roadmap.md §v0.3`)

---

## 1. Background and Motivation

The v0.3 roadmap includes `do`-notation sugar: `(do (<- x expr) ...)`. Two implementation options were evaluated:

- **Option A — Parse-time desugar:** `EDo` stripped at parse time; desugared to `seq-commands` + `ELet`. TC and codegen untouched.
- **Option B — First-class `EDo` with pair-thread enforcement:** `EDo` kept as a typed AST node; TC enforces the `(S, Command)` pair model; codegen emits a pure let-chain.

**Option A was rejected.** The reasons are architectural, not tactical:

1. `DoBind` steps whose bound variable is referenced in the body **cannot be desugared to `seq-commands`** — `seq-commands` has signature `Command → Command → Command` and discards the left-hand value. A binding `x <- e` where `x` is used downstream requires knowledge of `e`'s return type at desugar time, which is not available in the parser.
2. Parse-time desugar would **break the JSON-AST round-trip contract**. The schema already declares `ExprDo` with `"kind": "do"`. Stripping `EDo` at parse time means agents can write `{"kind":"do","steps":[...]}` but the node never reaches TC — a silent violation of the schema's semantic guarantees.
3. Option A is a shortcut that forecloses Option B. In a language's formative stage, the correct invariants should be established now, not patched later.

**Option B was chosen.** The rest of this document specifies the design decisions required to implement it correctly.

---

## 2. The Pair-Thread Model — Semantics

### 2.1 Core Invariant

LLMLL's IO model (§9.1) is:

```
(State, Input) → (NewState, Command)
```

Logic functions are **pure**. They return `Command` values that *describe* effects; they do not perform them. `do`-notation under the pair-thread model is a surface convenience for sequencing multiple such pure functions. It is **not a monad** and it is not Haskell's `IO do`.

> **Critical distinction for the language spec:** LLMLL `do`-notation is **structured let-binding for pair-returning functions**. State threading is explicit and manual — the programmer passes the state value from one step to the next as a function argument. There is no implicit state read or write. This distinction must appear verbatim in `LLMLL.md §9`.

### 2.2 Step Semantics

Every step in a `do`-block — bound or unbound — must return a value of type `(S, Command)`:

| Step form | Meaning |
|-----------|---------|
| `[x <- e]` | `e : (S, Command)`. `x` is bound to the **state component** `S` and is in scope for all subsequent steps. The `Command` component is accumulated. |
| Bare `e` (anonymous step) | `e : (S, Command)`. The state component is bound to a compiler-generated name `_s_k` (where `k` is the step index) and is **not expressible in LLMLL source**. The `Command` component is accumulated. |

> [!WARNING]
> **Anonymous intermediate step hazard:** Because LLMLL's pair-thread model is explicit — state is passed as a function argument, not threaded implicitly — the compiler-generated name `_s_k` for an anonymous step's state component is unreachable by any subsequent LLMLL step expression. If an intermediate step changes state and is anonymous, those state changes are **silently discarded**; subsequent steps will use the last *named* state variable in scope instead. Anonymous steps are therefore only semantically safe in the **terminal** (last) position of a `do`-block, or in positions where the program deliberately does not forward the state change. See §9.6 for a worked example.

### 2.3 Normative Type Rule

The type rule applies per step, distinguishing named and anonymous binding:

```
-- Named step (DoStep (Just x) e):
Γ ⊢ e : (S, Command)
──────────────────────────────────────────────────────────────
Γ, x:S ⊢ (remaining steps)           x is user-accessible

-- Anonymous step (DoStep Nothing e):
Γ ⊢ e : (S, Command)
──────────────────────────────────────────────────────────────
Γ, _s_k:S ⊢ (remaining steps)        _s_k is compiler-internal;
                                      not expressible in LLMLL source

-- Full block:
Γ ⊢ step₀           step₀ : (S, Command)   [infers S]
Γ' ⊢ step₁          step₁ : (S, Command)   [unify S]
  ...
Γⁿ ⊢ stepₙ          stepₙ : (S, Command)   [unify S]
──────────────────────────────────────────────────────────────
Γ ⊢ (do step₀ … stepₙ) : (S, Command)
```

- `S` is **homogeneous** across all steps — every step threads the same state type.
- `S` is **inferred** from the first step's expression type, then unified against all subsequent steps.
- A state-type mismatch between steps is a hard type error (`"type-mismatch"` diagnostic).
- The whole `do`-block returns `(S, Command)` where the final `S` is the last step's state component (named or `_s_k`) and the final `Command` is the `seq-commands`-composition of all steps' Commands.

### 2.4 Command Accumulation

All intermediate Commands are automatically composed via `seq-commands`. The programmer never writes `seq-commands` inside a `do`-block. Codegen handles the accumulation.

**Input:**
```lisp
(do
  [s1 <- (log-request state0 input)]
  [s2 <- (validate    s1     input)]
  (respond s2 input))
```

**Generated Haskell (pure let-chain — no Haskell `do`):**
```haskell
(let { (s1, _cmd_0)  = log_request state0 input
     ; (s2, _cmd_1)  = validate s1 input
     ; (s3, _cmd_2)  = respond s2 input
     ; _finalCmd     = seq_commands _cmd_0 (seq_commands _cmd_1 _cmd_2)
     } in (s3, _finalCmd))
```

> **Why not Haskell `do`?** The current `emitDo` emits `(do { x <- e; ... })` which requires a `Monad` instance. `def-logic` bodies are pure — there is no monad in scope. The generated Haskell is **unsound today** and would cause GHC type errors if a user were to place a `do`-block inside a non-IO `def-logic`. PR 3 replaces this entirely.

### 2.5 Where `do`-notation is Valid

`do` can appear anywhere an expression of type `(S, Command)` is expected. No syntactic restriction beyond type context is imposed — the type checker enforces the constraint. A `do`-block in a context expecting `int` produces a normal `type-mismatch` diagnostic.

---

## 3. Design Decisions — Full Record

### Decision 1 — Introduce `TPair` *(Gating Dependency)*

**Resolution:** Add `TPair Type Type` to `Syntax.hs`. Migrate `inferExpr (EPair a b)` from returning `TResult ta tb` to `TPair ta tb`.

**Justification:** The pair-thread model cannot be checked under `TResult` because `TResult` represents `Either e t` — a sum type with left-failure semantics. Enforcing `(S, Command)` requires a product type where both components are always present. Without `TPair`, the type checker cannot distinguish a `Result[S, Command]` (a sum: either `Success` or `Error`) from a `(S, Command)` pair. This is not theoretical — `checkExhaustive` would attempt to enforce `Success`/`Error` arms on step expressions.

**`CodegenHs.hs` impact:** Zero. `emitExpr (EPair a b)` already emits `(a, b)` as a Haskell tuple, which is the correct representation for both `TResult` (currently) and `TPair` (after migration).

> **This is the gating prerequisite.** PRs 2 and 3 cannot be implemented correctly without `TPair` in scope. No do-notation TC enforcement is sound against `TResult`.

> [!WARNING]
> **Language team review (2026-04-05):** The original document described PR 1 as having "zero codegen impact". This was imprecisely scoped — it holds for `CodegenHs.hs` only. Three additional sites in the compiler pipeline are affected and must be updated **within PR 1** or the PR will introduce regressions before PRs 2 and 3 land.

#### PR 1 — Required Changes Beyond `Syntax.hs` / `TypeCheck.hs`

**Site 1 — `TypeCheck.hs` `checkExhaustive` (lines 741–745)**

`checkExhaustive` has a dedicated `TResult _ _` arm that enforces `Success`/`Error` constructor coverage. After the migration, `EPair` returns `TPair`, not `TResult`. The concern is not that `TPair` will accidentally trigger the `TResult` arm — it will not, because `TPair` is a new constructor and will fall through to `_ -> pure ()`. The concern is subtler: if any internal path (e.g., `expandAlias`) resolves a `TCustom` alias that was previously used as a pair encoding to `TResult`, that alias expansion must also be updated to `TPair`. Verify with a targeted test: `match` on a value produced by `EPair` must not require `Success`/`Error` arms after the migration.

*Acceptance criterion:* A `match` expression on a pair-typed scrutinee does not produce a `"non-exhaustive-match"` diagnostic citing missing `Success` or `Error` arms.

**Site 2 — `TypeCheck.hs` `compatibleWith` (lines 817–836)**

`compatibleWith` has no `TPair a b` case. Without it, `unify` falls through to `a == b` structural equality, which means two `TPair` values are only compatible if they carry the **exact same types** — no covariant sub-typing, no `TVar` wildcard matching on either component. This immediately breaks the `def-main :init` path: today `:init` returns `TResult State Command` via `EPair`, which is accepted because `TResult` has an existing case. After the migration it returns `TPair State Command`, and without a `TPair` case in `compatibleWith`, `unify` will reject it as incompatible with any expected type that is itself a `TPair`. **This regression manifests in PR 1 before PR 2 or 3 are merged.**

Required addition to `compatibleWith`:
```haskell
compatibleWith (TPair a b) (TPair c d) =
  compatibleWith a c && compatibleWith b d
```

*Acceptance criterion:* `def-main :init` expressions returning `EPair` pass `llmll check` after PR 1. No false `type-mismatch` on pair-typed expressions.

**Site 3 — `AstEmit.hs` `typeToJson` (lines 153–180)**

`typeToJson` has no case for `TPair`. The function is exhaustive only up to `TSumType`; adding `TPair` without a case produces a **non-exhaustive pattern match** at runtime — GHC will emit a warning at build time and `error` at the call site whenever `llmll build --emit json-ast` encounters a pair type. This is a silent round-trip break, not a schema adjustment.

Required addition:
```haskell
typeToJson (TPair a b) = object
  [ "kind" .= ("pair-type" :: Text)
  , "fst"  .= typeToJson a
  , "snd"  .= typeToJson b
  ]
```

This maps to the existing `"pair-type"` `$def` in the JSON schema (`TypePair`), which already has `"fst"` and `"snd"` fields.

*Acceptance criterion:* `llmll build --emit json-ast` on any program containing `EPair` produces a valid JSON node with `"kind": "pair-type"`. The emitted JSON round-trips back through `ParserJSON.hs` without error.

#### Note on `first` / `second` and `TPair`

After PR 1, `EPair` produces `TPair ta tb`. The stdlib functions `first` and `second` in `builtinEnv` currently have type `TVar "p" → TVar "a"` — they are **fully polymorphic wildcards**, not typed to any specific pair representation. This means they will continue to unify with `TPair`-typed values after the migration, by the `TVar` wildcard rule in `compatibleWith`.

This is acceptable as a compatibility property, but it must not be promoted to a semantic guarantee. `first`/`second` are **structural coincidences** that happen to work on any pair-like value. They are not canonical `TPair` accessors, and the language spec must not describe them as such (see §9.6 annotation). No change to `builtinEnv` is required in PR 1.

---

### Decision 2 — Homogeneous State Type

**Resolution:** All steps in a `do`-block must thread the same state type `S`. `S` is inferred from the first step's expression and unified against all subsequent steps. Heterogeneous state evolution is a type error.

**Justification:** The LLMLL runtime model binds `State` to a single user-defined type for the duration of a `def-main :step` call. There is no runtime mechanism to coerce between different state types across steps. Allowing heterogeneous state would require full unification variables and effectively HM type inference — not on the roadmap. Homogeneous state is also the correct choice for `liquid-fixpoint` verification: every state transformation is visible at the call site with no implicit coercion for the solver to model.

---

### Decision 3 — Syntactic Validity Scope

**Resolution:** `do` is valid anywhere a `(S, Command)` expression is expected. No additional syntactic restriction.

**Justification:** A blanket restriction to `:step` bodies would require a separate grammar rule and a new check in `checkStatement`. The type checker already provides all necessary enforcement. Adding a syntactic gate buys nothing and reduces ergonomics — `do` is useful in any helper `def-logic` that composes multiple Command-returning calls.

---

### Decision 4 — Command Accumulation (All Steps)

**Resolution:** Every step's `Command` component is accumulated via `seq-commands`, in step order.

**Justification:** Silently discarding intermediate Commands would be a class of latent runtime bug directly contrary to the design philosophy: a step that calls `wasi.io.stderr "validation failed"` in a `DoBind` position would produce no side effect. Every `Command` produced by a step must be accounted for; this is what `seq-commands` was designed for.

---

### Decision 5 — `DoExpr` Semantics *(5B Confirmed)*

**Resolution:** Bare expression steps (`DoExpr e`) must return `(S, Command)`. They are definitionally identical to `DoBind "_" e`. The `DoStep` ADT is **collapsed** from two constructors to one:

```haskell
-- Before:
data DoStep
  = DoBind Name Expr
  | DoExpr Expr

-- After:
data DoStep = DoStep (Maybe Name) Expr
  -- Nothing    → anonymous step (former DoExpr)
  -- Just "x"  → named step     (former DoBind)
```

**Justification:** Once every step is required to return `(S, Command)`, keeping two constructors is representational redundancy — the only difference between the two is whether the state component is named. The collapsed form makes this semantic identity explicit and eliminates a pattern-match case in every phase: TC, codegen, S-expression parser, JSON parser, PBT, and AST emitter. Fewer constructs, same semantics.

**Agent implication:** An agent writing an anonymous step whose expression returns `Command` (not `(S, Command)`) — e.g., a bare `wasi.io.stdout` call — will receive a `"do-step-type-error"`. The fix is explicit: `(pair state (wasi.io.stdout "..."))`. This is intentional — the verbosity is the signal that the programmer must think about what state to thread.

---

### Decision 6 — Schema and JSON-AST

**Resolution:** Unify `"bind-step"` and `"expr-step"` into a single `"do-step"` kind with an optional `"name"` field:

```json
{
  "kind": "do-step",
  "expr": { ... },
  "name": "s1"    // optional; absent = anonymous step
}
```

Add an optional `"state_type"` hint field. It is used only when the step *expression itself* is a hole (`[s1 <- ?step-impl]`) and the TC needs to check the hole against `(S, Command)` without being able to infer `S` from argument types. It is not needed for holes in *argument position* within a step expression (see `--sketch` clarification below).

Emit a `"schema-migration-required"` diagnostic (not a hard error) when old `"bind-step"` / `"expr-step"` kinds are encountered, naming the replacement.

#### `--sketch` Propagation into `do`-Step Holes — Closed

**Language team clarification request:** Will `--sketch` propagate the `(S, Command)` type constraint into hole expressions that appear inside a `do`-step? E.g., should `?missing-arg` in `[s1 <- (log-request state ?missing-arg)]` receive an inferred type?

**Answer: Yes, in v0.3, as part of PR 2. No new infrastructure is required.**

The argument-position hole `?missing-arg` is inside an `EApp` node. The existing TC path is:

```
inferDoSteps → inferExpr (EApp "log-request" [..., EHole (HNamed "missing-arg")])
  → inferExpr (EApp ...) → checkExpr (EHole ...) expectedArgType
    → recordHole "missing-arg" (HoleTyped expectedArgType)
```

This already works via the `EApp → checkExpr → recordHole` chain (Phase 2c machinery). The only addition required in PR 2 is wrapping each step's `inferExpr` call in `withSegment "steps" (withSegment (tshow i) ...)` so that the RFC 6901 pointer for `?missing-arg` includes the step index (e.g., `/statements/2/body/steps/0/args/1`) rather than pointing only into the outer expression. This is a two-line addition per step in `inferDoSteps` — not a non-trivial change.

The hole-expression-as-step case (`[s1 <- ?step-impl]`) is also handled: `inferDoSteps` calls `inferExpr` on the step expression; for `EHole (HNamed "step-impl")`, this hits `inferHole → recordHole HoleUnknown` in synthesis mode. To record `HoleTyped (TPair S (TCustom "Command"))` for this case, PR 2 must check the hole against the expected pair type using `checkExpr`. This IS the motivation for the optional `"state_type"` hint — it lets the TC know `S` before it can infer it from arguments. Without the hint the type is recorded as `HoleUnknown`; with it the type is recorded as `HoleTyped`. Both are non-blocking.

**Compiler team confirmation required in PR 2:** Add `withSegment "steps" (withSegment (tshow i) ...)` wrappers in `inferDoSteps`. Verify with `--sketch` regression: a named hole in argument position inside a do-step must appear in the `sketchHoles` output with a pointer of the form `/statements/N/body/steps/K/args/J`.

---

### Decision 7 — Pair Destructuring in `let` and `match`

**Resolution:** Extend the `let` binding form and `match` pattern grammar to accept `(pair x y)` as a destructuring head. Both `let` and `match` already use the `pattern` production; the addition is a new `pattern` alternative.

**New syntax:**
```lisp
;; Destructuring let
(let [(pair s cmd) (authenticate state cred)]
  (do-something s cmd))

;; Destructuring match arm
(match (authenticate state cred)
  [(pair s cmd) (do-something s cmd)])
```

**Justification:**

1. **Constructor symmetry.** `pair` appears on both sides: `(pair s cmd)` constructs, `(pair s cmd)` in a binding head destructs. This is the most learnable pattern for an AI agent — the same word used to create a pair destroys it. It is also the LLMLL-idiomatic form of Haskell's `let (a, b) = ...` or ML's `let (a, b) = ...`.

2. **One-shot correctness.** The two-step workaround (`r0`, then `(first r0)`, `(second r0)`) doubles the number of bindings and naming decisions an agent must make correctly. Every additional name is an opportunity for a collision or transposition error. The pair model mandates that `(State, Command)` is the return type of every logic function that performs effects — if pairs are everywhere, binding both components in one step is not a convenience, it is a correctness requirement.

3. **Closes the `first`/`second` semantic gap.** `first` and `second` are fully polymorphic wildcards (`TVar "p" → TVar "a"`). They unify with `TPair` by coincidence, not by contract. After `TPair` is introduced (PR 1), the pair type system has a product type with no canonical destructor — an incomplete design. `(pair x y)` as a pattern gives `TPair` a typed destructor that the compiler can enforce: `checkPattern (PConstructor "pair" [PVar s, PVar c]) (TPair a b)` binds `s : a` and `c : b` with full type precision.

4. **Reuses existing infrastructure.** `PConstructor` already exists in the `Pattern` ADT. `checkPattern` is already dispatched per constructor. The new case is:
   ```haskell
   checkPattern (PConstructor "pair" [PVar s, PVar c]) (TPair a b) =
     pure [(s, a), (c, b)]
   ```
   No new AST node, no new parser combinator beyond an additional `pattern` alternative, no new codegen rule beyond emitting a Haskell tuple pattern.

**Timing:** The spec language (BNF and §13.4) lands before v0.3 ships to prevent spec inconsistency. Implementation may fold into PR 2 (same pattern infrastructure) or ship as PR 4. `first`/`second` are **not deprecated** — they remain valid for single-component access and for legacy code.

---

## 4. Implementation Plan — PR Sequence

### PR 1 — `TPair` Introduction *(prerequisite)*

**Files:** `Syntax.hs`, `TypeCheck.hs`, `CodegenHs.hs`, `AstEmit.hs`, `docs/llmll-ast.schema.json`

| Change | Detail |
|--------|--------|
| Add `TPair Type Type` to `Type` ADT | Between `TResult` and `TPromise` |
| `typeLabel (TPair a b)` | `"(" <> typeLabel a <> ", " <> typeLabel b <> ")"` |
| `compatibleWith (TPair a b) (TPair c d)` | `compatibleWith a c && compatibleWith b d` |
| `toHsType (TPair a b)` | `"(" <> toHsType a <> ", " <> toHsType b <> ")"` |
| `inferExpr (EPair a b)` | Change `pure (TResult ta tb)` → `pure (TPair ta tb)` |
| `typeToJson (TPair a b)` in `AstEmit.hs` | `object ["kind" .= "pair-type", "fst" .= typeToJson a, "snd" .= typeToJson b]` |
| Schema | Confirm `"pair-type"` `$def` fields `"fst"` and `"snd"` match the new emitter |

**Acceptance criteria (all must pass before PR 1 merges):**

1. All existing `llmll check` runs pass — zero new diagnostics on any example in `examples/`.
2. `def-main :init` expressions returning `EPair` pass type-checking — no false `type-mismatch` on pair-typed expressions.
3. A `match` expression on a pair-typed scrutinee does **not** produce a `"non-exhaustive-match"` diagnostic citing missing `Success` or `Error` arms.
4. `llmll build --emit json-ast` on any program containing `EPair` produces a valid JSON node with `"kind": "pair-type"` that round-trips through `ParserJSON.hs` without error.
5. `stack build` produces **no** `-Wincomplete-patterns` warning for `typeToJson` in `AstEmit.hs`.

---

### PR 2 — `DoStep` Collapse + TC Enforcement

**Files:** `Syntax.hs`, `Parser.hs`, `ParserJSON.hs`, `TypeCheck.hs`, `PBT.hs`, `AstEmit.hs`, `docs/llmll-ast.schema.json`

| Change | Detail |
|--------|--------|
| Collapse `DoStep` ADT | `data DoStep = DoStep (Maybe Name) Expr` |
| Rewrite `inferDoSteps` | Enforce pair type rule; bind `x` or `_s_k` per step; unify `S` across steps |
| Add `withSegment "steps" / withSegment (tshow i)` | Wrap each step's `inferExpr` call so holes inside step expressions receive correct RFC 6901 pointers for `--sketch` output |
| New diagnostic `"do-step-type-error"` | Emitted when step expression does not return `(S, Command)` |
| Update parsers | S-expr and JSON parsers use new ADT |
| Update schema | `DoStep` unified to `"do-step"` with optional `"name"` and optional `"state_type"` |
| Migration warning | `"bind-step"` / `"expr-step"` in JSON-AST emits `"schema-migration-required"` |

**Acceptance criteria:** Step expression returning `Command` (not a pair) produces `"do-step-type-error"`. State type mismatch between steps produces `"type-mismatch"` with the conflicting type labels. `llmll typecheck --sketch` on a do-block with a named hole in an argument position (e.g., `[s1 <- (fn state ?hole)]`) reports `inferredType` for `?hole` with the correct RFC 6901 pointer including the step index. `stack test` passes all existing examples.

---

### PR 3 — `emitDo` Rewrite

**Files:** `CodegenHs.hs`

Replace:
```haskell
-- REMOVE — emits unsound Haskell `do` inside pure context:
emitDo steps = "(do { " <> intercalate "; " (map emitStep steps) <> " })"
```

Implement pure let-chain emitter using index-based gensym for `_cmd_N` and `_s_N` names. The generated code must be a pure tuple expression, not a Haskell `do`-block.

**Acceptance criteria:** Generated Haskell for a `do`-block compiles with GHC without an `IO`/`Monad` context. The expression is a pure `let ... in (sN, _finalCmd)` tuple. Add regression examples: two-step and three-step `do`-block in both S-expression and JSON-AST format. `stack test` passes all examples including new regressions.

---

### PR 4 — Pair Destructuring in `let` *(Decision 7; may fold into PR 2)*

#### ADT Decision — Option A: `ELet [(Pattern, Maybe Type, Expr)] Expr`

Three options were evaluated for representing pattern-headed `let` bindings in the AST:

| Option | Approach | Verdict |
|--------|----------|---------|
| **A** | Promote `Name` to `Pattern` in `ELet` tuple | **Chosen** |
| B | Parse-time desugar to nested `ELet` + `first`/`second` | **Rejected** — re-introduces `TVar` wildcard at TC level; undermines typed destructor claim |
| C | Add `ELetDestructure` variant | **Rejected** — duplicates all `ELet` consumer logic without reducing blast radius |

**Rationale for Option A:** `PVar name` is a special case of `Pattern`. Every existing call site that matches `(n, mAnnot, e)` becomes `(PVar n, mAnnot, e)` — a mechanical rename with identical semantics for simple bindings. The `checkPattern (PConstructor "pair" [PVar s, PVar c]) (TPair a b)` case delivers a *typed* destructor: `s : a` and `c : b` precisely, not via `TVar` wildcard. This is the one time the upgrade is clean — before the codebase grows further.

**`Maybe Type` annotation policy (PR 4 scope):** The existing `Maybe Type` field annotates the bound expression's inferred type. For pattern-headed bindings, `Maybe Type` is always `Nothing` in PR 4. Annotated destructuring (e.g., `(let [(pair s: AppState cmd: Command) e] ...)`) is a future extension and does **not** block PR 4.

**Files:** `Syntax.hs`, `Parser.hs`, `ParserJSON.hs`, `TypeCheck.hs`, `CodegenHs.hs`, `AstEmit.hs`, `PBT.hs`, `docs/llmll-ast.schema.json`, `LLMLL.md`

| File | Change | Detail |
|------|--------|---------|
| `Syntax.hs` | `ELet [(Name, Maybe Type, Expr)] Expr` → `ELet [(Pattern, Maybe Type, Expr)] Expr` | Core ADT change |
| `Parser.hs` | `pLetBinding`: parse `[IDENT expr]` via `pPattern` instead of `IDENT`; add `(pair x y)` alternative to `pPattern` | Simple combinator extension |
| `ParserJSON.hs` | Parse `"binding"` object: if `"name"` key present, produce `PVar name` (backward compat); if `"pattern"` key present, parse as pattern node | Backward-compat path for existing JSON-AST files |
| `TypeCheck.hs` | `inferExpr (ELet bindings body)`: match `(PVar n, mAnnot, e)` → same as today; match `(PConstructor "pair" [PVar s, PVar c], Nothing, e)` → `checkPattern pat inferredTy` → `tcInsert s ta; tcInsert c tb` | ~8 lines; dispatch through existing `checkPattern` |
| `CodegenHs.hs` | `emitLet`: `toHsIdent n <> " = " <> emitExpr e` → `emitPat pat <> " = " <> emitExpr e`; add `emitPat (PConstructor "pair" [p1, p2]) = "(" <> emitPat p1 <> ", " <> emitPat p2 <> ")"` | One-line change + one new `emitPat` case; emits valid Haskell `let { (s, cmd) = expr }` |
| `AstEmit.hs` | `exprToJson (ELet bindings body)`: emit `"pattern"` key for non-`PVar` heads; emit `"name"` key for `PVar` heads (backward compat) | Two-branch emit |
| `PBT.hs` | Generators for `ELet` bindings: produce `PVar`-headed bindings (existing behaviour unchanged; no `PConstructor`-headed generation needed in PBT scope) | No functional change |
| Schema | `LetBinding`: add optional `"pattern"` field alongside existing `"name"`; both are mutually exclusive; existing files with `"name"` are valid without migration | Additive, backward-compatible |
| `LLMLL.md` | Update BNF `let` and `pattern` rules (see §5b); update §13.4; `do` keyword added to keyword list (already present) | Documentation only |

**Acceptance criteria:**
1. `(let [(pair s cmd) (authenticate state cred)] (do-something s cmd))` type-checks with `s : AppState`, `cmd : Command`.
2. `(match (authenticate state cred) [(pair s cmd) (do-something s cmd)])` type-checks identically to the `let` form.
3. All existing programs with simple `(let [(x expr)] body)` bindings continue to compile — zero regressions.
4. Nested destructuring `(let [(pair word (pair g rest)) state] ...)` type-checks, binding `word`, `g`, `rest` with the correct component types.
5. JSON-AST files with `"name"` binding keys continue to parse correctly via the backward-compat path.
6. `stack build` produces no `-Wincomplete-patterns` for `emitPat` or `inferExpr (ELet ...)`.
7. `stack test` regression suite passes.

---

## 5. Draft `LLMLL.md` Spec Language

*The following normative text is ready to land in `LLMLL.md`. Sections 5a and 5b are independent of each other. Both are language-team deliverables for v0.3.*

---

### 5a. Draft `LLMLL.md §9.6` — `do`-Notation (v0.3)

`do`-notation provides readable syntax for sequencing multiple pair-returning functions. It is **not monadic** — there is no implicit state read or write. The programmer threads state explicitly as function arguments.

**Syntax:**
```lisp
(do
  [x₁ <- expr₁]    ;; bind: x₁ receives the state component of expr₁'s result
  [x₂ <- expr₂]    ;; bind: x₂ receives the state component of expr₂'s result
  expr_final)       ;; anonymous or named final step; must return (State, Command)
```

**Type constraint:** Every step expression must return `(S, Command)` for the same type `S`. `S` is inferred from the first step and unified across all subsequent steps. The whole block returns `(S, Command)`.

**State threading:** The name in `[x <- e]` is bound to the **state component** of `e`'s result. The Command component is accumulated automatically. `x` is in scope for all subsequent steps and the final expression. The programmer is responsible for passing the state variable to the next function — it is not injected automatically.

**Command composition:** All intermediate Commands are composed with `seq-commands` in step order. Do not write `seq-commands` inside a `do`-block.

**Anonymous step:** A step without a name (bare expression) produces a `(S, Command)` pair where the state component is bound to a compiler-generated name (`_s_k`, where `k` is the zero-based step index). This name is **not accessible in LLMLL source**. Anonymous steps are safe only in the **terminal position** of a `do`-block, or when the programmer explicitly does not intend to forward the state change from that step. Using an anonymous step in a non-terminal position where the state change matters is a **silent state-loss bug** — the type checker cannot detect it, because subsequent steps will simply use the last named state variable in scope.

**Complete example:**
```lisp
(def-logic handle-multi [state: AppState input: string]
  (do
    [s1 <- (log-request   state  input)]
    [s2 <- (validate      s1     input)]
    (respond s2 input)))
```

This desugars to the following (shown for exposition only — do not write this by hand):

```lisp
;; With pair destructuring (v0.3 — see §13.4):
(let [(pair s1 c0) (log-request state input)]
  (let [(pair s2 c1) (validate s1 input)]
    (let [(pair s3 c2) (respond s2 input)]
      (pair s3 (seq-commands c0 (seq-commands c1 c2))))))
```

> **Note:** The compiler does NOT emit nested `let` like the above — it emits a flat Haskell pattern-matching let-chain (see §2.4). The desugared form above is in LLMLL surface syntax for exposition only. It uses `(pair x y)` destructuring (Decision 7) which is now the canonical way to bind both components of a pair. The `seq-commands` calls in the desugar are generated by the compiler's `do`-block elaboration — not instructions for the programmer. In a `do`-block, `seq-commands` is never written explicitly; writing it by hand inside a `do`-block is an error in intent even if it type-checks.

**Second example — anonymous step in non-terminal position (state-loss hazard):**
```lisp
(def-logic handle-with-metric [state: AppState cred: string input: string]
  (do
    [s1 <- (authenticate   state  cred)]
    (emit-metric s1 "auth-ok")          ;; anonymous: command accumulated; _s_1 unreachable
    [s3 <- (load-profile   s1    input)]))  ;; uses s1, NOT _s_1: emit-metric's state change is LOST
```

Generated Haskell let-chain for the anonymous middle step:
```haskell
(let { (s1, _cmd_0)  = authenticate state cred
     ; (_s_1, _cmd_1) = emit_metric s1 "auth-ok"   -- _s_1 bound but not referenced below
     ; (s3, _cmd_2)  = load_profile s1 input        -- uses s1, not _s_1
     ; _finalCmd     = seq_commands _cmd_0 (seq_commands _cmd_1 _cmd_2)
     } in (s3, _finalCmd))
```

> **State-loss hazard:** The Commands from all three steps (`_cmd_0`, `_cmd_1`, `_cmd_2`) are accumulated — the metric IS emitted. But if `emit-metric` modified `AppState` internally and returned a new state, that modification is discarded: `load-profile` receives `s1` (pre-metric state), not `_s_1` (post-metric state). The type checker cannot catch this because both `s1` and `_s_1` have type `AppState`. **Use a named step whenever state continuity matters.**

**Ill-formed uses:**
```lisp
;; ERROR: wasi.io.stdout returns Command, not (State, Command)
(do (wasi.io.stdout "hello"))

;; CORRECT: pair the command with the state explicitly
(do (pair state (wasi.io.stdout "hello")))

;; ERROR: state type mismatch between steps
(do [s1 <- (fn-returning-AppState  state  input)]
    [s2 <- (fn-returning-AuthState state  input)])  ;; type-mismatch: AppState vs AuthState
```

---

### 5b. Draft `LLMLL.md` — Pair Destructuring (v0.3)

*Two locations in LLMLL.md change: the BNF grammar (§13 or equivalent) and the §13.4 pair/record operations table.*

#### BNF Grammar Changes

The following rules replace or extend the current grammar at the `let` and `pattern` productions:

```ebnf
(* BEFORE: *)
let         = "(" "let" "[" { "[" IDENT expr "]" } "]" expr ")" ;
pattern     = "_"
            | IDENT
            | literal
            | "(" IDENT { pattern } ")" ;

(* AFTER: *)
let         = "(" "let" "[" { let-binding } "]" expr ")" ;
let-binding = "[" pattern expr "]" ;
              (* pattern may be IDENT, (pair x y), or any future pattern form;
                 nested destructuring (pair x (pair y z)) works without
                 changing the let rule *)  

pattern     = "_"                              (* catch-all wildcard  *)
            | IDENT                            (* variable binding    *)
            | literal                          (* literal equality    *)
            | "(" "pair" IDENT IDENT ")"       (* pair destructuring  *)
            | "(" IDENT { pattern } ")" ;      (* constructor pattern *)
```

> **Structural alignment with `match-arm`:** The grammar for `match-arm` is `"(" pattern expr ")"`. With this change, `let-binding` is `"[" pattern expr "]"` — the only difference is the bracket token. Both forms dispatch through the same `pattern` production and the same `checkPattern` implementation. This symmetry makes the grammar consistent: *wherever a pattern is legal, it can head either a `let` binding or a `match` arm*.

**Examples:**
```lisp
;; Simple binding (unchanged):
(let [(x 1) (y 2)] (+ x y))

;; Pair destructuring in let:
(let [(pair s cmd) (step state input)]
  (do-something s cmd))

;; Pair destructuring in match (unchanged form, new pattern alternative):
(match (step state input)
  [(pair s cmd) (do-something s cmd)])

;; Nested pair destructuring — works free from the unified pattern rule:
(let [(pair word (pair guessed rest)) state]
  (process word guessed rest))
```



**Type rule for pair destructuring in `let`:**

If `(pair x y)` appears as the binding head and the bound expression has type `(A, B)`, then `x : A` and `y : B` are in scope for the body.

```
Γ ⊢ e : (A, B)
Γ, x:A, y:B ⊢ body : T
───────────────────────────────────
Γ ⊢ (let [(pair x y) e] body) : T
```

Applying a pair destructuring binding to a non-pair type is a `type-mismatch` error.

#### Updated `LLMLL.md §13.4` — Pair / Record Operations

Replace the existing v0.1.1 no-record-syntax note with the following:

---

### 13.4 Pair / Record Operations

| Function | Signature | Notes |
|----------|-----------|-------|
| `pair` | `a → b → (a, b)` | Construct a 2-tuple |
| `first` | `(a, b) → a` | First component — use when only one component is needed |
| `second` | `(a, b) → b` | Second component — use when only one component is needed |

**Destructuring (v0.3):** When both components of a pair are needed, use the `(pair x y)` destructuring form in a `let` binding or a `match` arm. This is the canonical idiom — it binds both components in one step and is typed against `TPair`:

```lisp
;; Preferred: one binding, both components in scope
(let [(pair s cmd) (step state input)]
  (seq-commands cmd (do-more s)))

;; Also valid, but verbose: two bindings via first/second
(let [(r   (step state input))
      (s   (first  r))
      (cmd (second r))]
  (seq-commands cmd (do-more s)))
```

**Records:** LLMLL has no native record syntax. Use nested `pair` values and named accessor functions. A 4-field record uses 3 levels of nesting; bind with nested `(pair ...)` destructuring or dedicated accessor `def-logic` functions:

```lisp
;; Construction
(def-logic make-state [w: Word g: list[Letter] wc: GuessCount mx: GuessCount]
  (pair w (pair g (pair wc mx))))

;; Accessor functions (recommended for multi-field records)
(def-logic state-word    [s] (first s))
(def-logic state-guessed [s] (first  (second s)))
(def-logic state-wrong   [s] (first  (second (second s))))
(def-logic state-max     [s] (second (second (second s))))

;; Or: nested pair destructuring
(let [(pair word rest) s
      (pair guessed rest2) rest
      (pair wrong-count max-wrong) rest2]
  ...)
```

---

## 6. Open Questions

| Question | Status | Owner |
|----------|--------|-------|
| `"state_type"` hint: required or optional? | **Closed** — Optional. Not required for argument-position holes; used only when the step expression itself is a hole. | Compiler Team |
| `--sketch` propagation into do-step holes | **Closed** — Yes, v0.3, via existing `EApp → checkExpr` chain. PR 2 adds `withSegment` for pointer correctness. | Compiler Team |
| Single-step `(do expr)` block legal? | **Closed** — Yes. No Command accumulation; block returns that step's pair directly. | Language Team |
| Empty `(do)` block legal? | **Closed** — No. Parse error: no final state or Command. | Compiler Team |
| Migration path for `"bind-step"` / `"expr-step"` | **Closed** — `"schema-migration-required"` warning; not a hard build failure. | Compiler Team |
| Pair destructuring in `let` and `match` | **Closed** — Yes. `(pair x y)` as binding head; reuses `PConstructor` path; spec language drafted in §5b; PR 4. | Both Teams |
| Can the type checker detect anonymous-step state-loss? | **Open** — Currently no. A lint warning for non-terminal anonymous steps is a v0.4 candidate. | Language Team |
| Should `first`/`second` be deprecated now that `(pair x y)` destructuring exists? | **Open** — No for v0.3. They remain valid for single-component access and legacy code. Deprecation is a v0.5+ discussion. | Language Team |
