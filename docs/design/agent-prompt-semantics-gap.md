# Agent Prompt & Language Semantics Gap Analysis

> **Status:** Approved — ready for implementation  
> **Date:** 2026-04-18  
> **Context:** Discovered during orchestrator walkthrough documentation (v0.3.3)

### Review History

| Date | Team | Verdict |
|------|------|---------|
| 2026-04-18 | Language Team (PLT & Formal Verification) | ✅ Concur with diagnosis and phased approach. |
| 2026-04-18 | Professor (Formal Language Design) | ✅ Concur. Structural concerns identified and resolved. |
| 2026-04-18 | Language Team (second pass) | ✅ All verified against compiler source. |
| 2026-04-18 | Compiler Team (integration pass) | Integrated all review comments into main text. |
| 2026-04-18 | Language Team (Q5–Q7 responses) | All open questions resolved. |
| 2026-04-18 | Professor (final review) | ✅ Concur. Corrections applied: `unwrap` signature, status enum, shadowing-safety. |
| 2026-04-18 | Compiler Team (final integration) | All comments integrated. Document approved for implementation. |

---

## Problem Statement

The `llmll-orchestra` agent prompt gives LLMs enough information to produce
syntactically valid JSON-AST patches, but not enough to produce semantically
correct implementations reliably. The agents are effectively writing code in a
language they don't understand, compensating with general reasoning and the
compiler's retry loop.

This is not merely a "prompt engineering" issue — it is a **formal specification
gap**. The language has well-defined denotational and operational semantics
encoded in ~2,500 lines of Haskell, but those semantics exist only as
executable artifacts, not as a standalone specification. The retry loop
compensates for the absence of a specification by doing empirical constraint
solving via API calls, which violates the Compiler-First principle.

---

## 1. What the Agent Receives Today

The system prompt in `agent.py` provides:

```
SYSTEM_PROMPT (80 lines):
  ├── Valid expression node kinds (12 kinds with JSON shapes)
  ├── Valid type nodes (primitive, result, list — 3 types)
  ├── Patch format (RFC 6902 replace)
  └── Rules (no commentary, path must match, etc.)

User prompt (per hole):
  ├── Pointer, kind, status, context
  ├── Agent name, description
  ├── Dependencies (already filled)
  └── Checkout context (JSON blob)
```

**Source:** [`tools/llmll-orchestra/llmll_orchestra/agent.py:36-80`](file:///Users/burcsahinoglu/Documents/llmll/tools/llmll-orchestra/llmll_orchestra/agent.py#L36-L80)

### What's Present

| Category | Content | Sufficient? |
|----------|---------|-------------|
| JSON node shapes | `lit-int`, `var`, `app`, `op`, `if`, `let`, `match`, `pair`, `lambda` | ✅ Syntax is covered |
| Patch format | RFC 6902 `replace` operation | ✅ |
| Result constructors | `ok`/`err` as function calls | ✅ (but not `Success`/`Error` for patterns) |
| Output rules | "Return ONLY the JSON array" | ✅ |

### What's Missing

| Category | What the agent doesn't know | Impact |
|----------|----------------------------|--------|
| **Built-in functions** | No list of available functions or their signatures | Agent guesses function names; may invent non-existent ones |
| **Operators** | No list of valid operators or their types | Agent may use `&&` instead of `and`, `==` instead of `=` |
| **Pattern syntax** | `match` arm structure, `constructor`/`bind`/`wildcard` | Agent can't destructure `Result` without guessing the JSON shape |
| **Result constructors** | `Success`/`Error` (not `Ok`/`Err` or `Right`/`Left`) | Wrong constructor names → type errors on retry |
| **Evaluation model** | Strict evaluation, `let` scoping rules | Agent may assume lazy evaluation or parallel bindings |
| **Contract semantics** | `pre` throws at runtime; `on_failure` is runtime-only | Agent may confuse orchestration-time with runtime behavior |
| **Type system rules** | How types unify, what coercions exist | May produce type mismatches that waste retries |
| **In-scope variables** | What params and `let` bindings are visible at this hole | Agent has to infer scope from the description string |
| **Expected return type** | Structured type info for the hole | Only conveyed in the free-text description |
| **Type node coverage** | Only 3 of 13 type constructors present in prompt | Agent cannot express `TPair`, `TFn`, `TMap`, etc. |
| **Pair builtins** | `pair`/`first`/`second` absent | Agent cannot construct or destructure product types |

### Type Node Coverage Gap

The prompt provides 3 type nodes (`primitive`, `result`, `list`) but the
compiler's type universe has **13 type constructors**. The following are absent:

| Type Constructor | In Prompt? | In `TypeCheck.hs`? |
|---|---|---|
| `TPair` | ❌ | ✅ |
| `TMap` | ❌ | ✅ |
| `TBytes` | ❌ | ✅ |
| `TPromise` | ❌ | ✅ |
| `TFn` (higher-order) | ❌ | ✅ |
| `TCustom` (user ADTs) | ❌ | ✅ |
| `TDependent` | ❌ | ✅ |
| `TSumType` | ❌ | ✅ |
| `TVar` (polymorphic) | ❌ | ✅ |
| `TDelegationError` | ❌ | ✅ |

An agent that receives a hole with expected return type `(int, string)` has
**no type node** to represent `TPair` in its patch. This is a hard error, not
a soft gap. At minimum, `pair` and `fn-type` type nodes must be added to the
prompt.

### Parametricity Gap (`compatibleWith` wildcard)

The type checker's unification uses `TVar` as a universal wildcard:

```haskell
compatibleWith (TVar _) _ = True   -- TypeCheck.hs:911
compatibleWith _ (TVar _) = True   -- TypeCheck.hs:912
```

This means polymorphic builtins never produce type-parameter mismatch errors.
If the agent passes an `int` where a `list[a]` is expected, the checker may
silently accept it and produce a runtime crash instead of a compile-time
diagnostic. This is a known limitation of the v0.1 unifier (proper
substitution-based unification is deferred).

**Mitigations:**

1. **Phase A:** Add a parametricity self-enforcement note to the prompt:
   > *Polymorphic type variables (a, b, e) mean "any type," but you MUST be
   > consistent: if `a` appears twice in a signature, both uses must be the
   > same concrete type. The compiler does not enforce this — you must.*

2. **Phase C:** When the checkout context emits Σ (function signatures),
   monomorphize polymorphic signatures relative to the types in Γ. For example,
   if `x : list[int]` is in scope, then `list-head` should appear as
   `list-head : list[int] → Result[int, string]`, not
   `list-head : list[a] → Result[a, string]`. This resolves the parametricity
   gap at the specification level without touching the checker.

---

## 2. Why a Link to Documentation Won't Work

The orchestrator calls `chat.completions.create()` via the OpenAI SDK. During
inference, the model receives **exactly** the text in the `messages` array.

- **LLMs cannot follow URLs.** A link to `getting-started.md` is opaque characters.
- **LLMLL is not in training data.** It's a custom language. The model has zero
  prior knowledge of `string-empty?`, `hole-delegate`, or the JSON-AST schema.
- **The spec evolves.** Even if a future model crawled the docs during training,
  its knowledge would be stale by the next release.

**The spec text must be in the prompt, verbatim.**

---

## 3. Where Semantics Live Today

The language semantics are spread across three compiler modules, all written in
Haskell and inaccessible to the agent:

| Module | What it captures |
|--------|-----------------|
| [`TypeCheck.hs`](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs) | Type rules, bidirectional inference, unification, `Result` uses `Success`/`Error` |
| [`CodegenHs.hs`](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs) | Evaluation model: `let` is sequential, `pre` throws at runtime, strict evaluation |
| Runtime preamble (generated `Lib.hs`) | What every built-in does: `string-concat` is `(++)`, `ok` is `Right`, etc. |

There is **no standalone semantic specification**. The compiler implementation
*is* the spec. This is a formal gap — the truth lives in ~2,500 lines of Haskell
that no agent will ever read.

The retry loop partially compensates: the compiler rejects bad patches and
returns diagnostics, which get fed back to the agent. But this is expensive
(multiple API calls per hole) and unreliable (the agent may not understand the
diagnostic well enough to correct its approach).

---

## 4. Proposed Solutions

### Option A: Enhanced System Prompt (Immediate — ~1 day)

Add two blocks to `SYSTEM_PROMPT`:

#### A.1 — Built-in Function Reference

The following reference has been corrected against
[`builtinEnv`](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L52-L124)
(verified line-by-line by Language Team and Professor):

```
## Built-in Functions

### String
string-concat      : string → string → string
string-length      : string → int
string-contains    : string → string → bool
string-slice       : string → int → int → string
string-char-at     : string → int → string
string-split       : string → string → list[string]
string-trim        : string → string
string-concat-many : list[string] → string
regex-match        : string → string → bool

### Numeric
int-to-string  : int → string
string-to-int  : string → Result[int, string]
abs            : int → int
min            : int → int → int
max            : int → int → int

### List
list-empty     : list[a]                             (empty list literal)
list-append    : list[a] → a → list[a]
list-prepend   : a → list[a] → list[a]
list-contains  : list[a] → a → bool                  (requires Eq)
list-length    : list[a] → int
list-head      : list[a] → Result[a, string]
list-tail      : list[a] → Result[list[a], string]
list-map       : list[a] → (a → b) → list[b]
list-filter    : list[a] → (a → bool) → list[a]
list-fold      : list[a] → b → (b → a → b) → b
list-nth       : list[a] → int → Result[a, string]
range          : int → int → list[int]               (exclusive end)

### Pair
pair           : a → b → (a, b)
first          : (a, b) → a
second         : (a, b) → b

### Result
ok        : a → Result[a, e]
err       : e → Result[a, e]
is-ok     : Result[a, e] → bool
unwrap    : Result[a, e] → a                         (throws on Error)
unwrap-or : Result[a, e] → a → a

### Command Combinators
seq-commands   : command → command → command

### Operators (use "op" nodes)
Arithmetic:  +  -  *  /  mod     : int → int → int
Comparison:  =  !=               : a → a → bool     (polymorphic)
             <  >  <=  >=        : int → int → bool  (integer-only)
Logical:     and  or             : bool → bool → bool
             not                 : bool → bool

### Type Nodes
- {"kind": "primitive", "name": "int"|"float"|"string"|"bool"|"unit"}
- {"kind": "result", "ok_type": <type>, "err_type": <type>}
- {"kind": "list", "elem_type": <type>}
- {"kind": "pair", "fst_type": <type>, "snd_type": <type>}
- {"kind": "fn-type", "params": [<type>], "return": <type>}

### Match Patterns
constructor: {"kind":"constructor","constructor":"Success","sub_patterns":[{"kind":"bind","name":"x"}]}
bind:        {"kind":"bind","name":"x"}
wildcard:    {"kind":"wildcard"}

⚠ Result construction vs. destruction:
  - To CREATE a success value: {"kind": "app", "fn": "ok", "args": [...]}
  - To CREATE an error value:  {"kind": "app", "fn": "err", "args": [...]}
  - To MATCH a success:  {"kind": "constructor", "constructor": "Success", ...}
  - To MATCH an error:   {"kind": "constructor", "constructor": "Error", ...}
  ok/err are constructor FUNCTIONS.  Success/Error are PATTERN names.
  These are DIFFERENT names for the same thing.
```

**Excluded from reference (by design):**
- `is-valid?` — undocumented identity stub (`TFn [TBool] TBool`); see §7 D1
- `wasi.*` commands — require capability imports, context-dependent; belong in
  Option C's `available_functions`
- `string-empty?` — **does not exist in `builtinEnv` or `runtimePreamble`**;
  must be implemented before inclusion (see §6, action item A8)

#### A.2 — Evaluation Rules

```
## LLMLL Evaluation Rules

- Strict evaluation: all arguments are evaluated before function application.
- let: bindings evaluate left-to-right. Each binding is in scope for
  subsequent bindings and the body.
- if: evaluates the condition, then exactly one branch.
- match: first matching arm wins. Must be exhaustive for Result types
  (both Success and Error arms required).
- pre: evaluated at function entry; throws "pre-condition failed" if false.
  This is a runtime assertion, not a type constraint.
- on_failure: NOT evaluated during orchestration. It is a runtime fallback
  expression used if the agent process crashes at runtime.
- Result[ok, err] constructors are Success(value) and Error(value).
  Do NOT use Ok/Err, Right/Left, or other naming conventions.
- All functions are pure. Side-effects happen only via def-main commands.
- Operator arity is FIXED. (+ x y) takes exactly 2 arguments.
  (+ x y z) is a type error. Use nested calls: (+ x (+ y z)).
- Polymorphic type variables (a, b, e) mean "any type," but you MUST be
  consistent: if `a` appears twice in a signature, both uses must be the
  same concrete type. The compiler's unifier treats type variables as
  wildcards and will NOT catch inconsistent instantiation.
- In a letrec, the body may call itself. The `:decreases` expression must
  return a strictly smaller int on each call.
```

**Token budget:** A.1 (~600 tokens) + A.2 (~250 tokens) + type nodes/pair/callouts
(~100 tokens) = **~950 tokens total**, roughly 2–3% of a typical 32K context
window. The reduction in retry API calls will more than compensate.

---

### Option B: Compiler-Emitted Spec (`llmll spec --agent`) (Medium — ~3 days)

Add a new compiler command that generates the agent reference automatically
from the compiler's internals:

```bash
$ llmll spec --agent
```

Output: a JSON or text document containing:

```json
{
  "builtins": [
    {"name": "string-concat", "params": [["a","string"],["b","string"]], "returns": "string"},
    ...
  ],
  "operators": [
    {"op": "+", "params": ["int","int"], "returns": "int"},
    ...
  ],
  "constructors": {
    "Result": ["Success", "Error"]
  },
  "evaluation": "strict",
  "pattern_kinds": ["constructor", "bind", "literal", "wildcard"]
}
```

**Advantages:**

- Single source of truth — generated from the same code that type-checks patches
- Can't drift from the compiler
- Orchestrator calls it once, caches the result, includes it in the system prompt

**Implementation requirements:**

1. **New module `LLMLL/AgentSpec.hs`** — must `import LLMLL.TypeCheck (builtinEnv)`
   and serialize it directly. Must NOT maintain a parallel list. This is the only
   way to structurally guarantee spec faithfulness.

2. **Spec Faithfulness Invariant (proof obligation):**

   > ∀ (f, TFn [t₁...tₙ] r) ∈ builtinEnv ⟹ ∃ entry ∈ spec_output .
   > entry.name = f ∧ entry.params = [t₁...tₙ] ∧ entry.returns = r

   Proposed property test:

   ```haskell
   -- In test suite: AgentSpecTests.hs
   prop_specCoversAllBuiltins =
     let specEntries = agentSpecBuiltins  -- from AgentSpec.hs
         builtinKeys = Map.keys builtinEnv
     in all (`elem` map asName specEntries) builtinKeys
   ```

   Since operators and functions share the same `Map Name Type`, this test
   covers both automatically. The risk is only in the emitter: it must use a
   **partition** (functions vs operators), not a filter. If the serializer uses
   `isAlpha (T.head k)`, operators will be silently dropped.

3. **Polymorphic type representation:** Use Haskell-style notation
   (`a → Result[a, e]`), which LLMs trained on Haskell/ML will understand.

4. New CLI command `spec` with `--agent` flag.
5. Update `agent.py` to call `compiler.spec()` and prepend to `SYSTEM_PROMPT`.

---

### Option C: Context-Aware Checkout (Ambitious — ~5 days)

From a PLT perspective, this is the correct end-state — the only option that
provides the agent with a **local typing context**, the analogue of what the
type checker's `withEnv` provides to each sub-expression during inference.

The checkout response should include:

1. **Γ (typing context):** All in-scope bindings `(name : type)` at the hole
2. **τ (goal type):** The expected return type of this hole
3. **Σ (function signature environment):** Available signatures relevant to
   the types in Γ and τ

Example enriched checkout response:

```json
{
  "pointer": "/statements/3/body/body",
  "token": "a1b2c3d4...",
  "in_scope": [
    {"name": "username", "type": "string", "source": "param"},
    {"name": "password", "type": "string", "source": "param"},
    {"name": "hashed",   "type": "string", "source": "let-binding",
     "defined_by": "hash-password-impl(password)"}
  ],
  "expected_return_type": {
    "kind": "result", "ok_type": "string", "err_type": "string"
  },
  "available_functions": [
    {"name": "hash-password-impl", "params": [["raw-pw","string"]], "returns": "string",
     "status": "filled"},
    {"name": "verify-token-impl", "params": [["token","string"]], "returns": "bool",
     "status": "filled"}
  ]
}
```

`available_functions[].status` values: `"filled"` (implementation committed),
`"hole"` (still a `?named` hole), `"pending"` (delegate awaiting agent response).
This lets the agent reason about whether a called function will actually work
at runtime.

#### Implementation: Capturing Γ from the type checker

The `withEnv` combinator (TypeCheck.hs line 221) is scope-restoring:

```haskell
withEnv bindings action = do
  old <- gets tcEnv
  modify $ \s -> s { tcEnv = foldr (uncurry Map.insert) old bindings }
  result <- action
  modify $ \s -> s { tcEnv = old }  -- ← Γ is gone after this
  pure result
```

At the moment `inferHole (HNamed name)` fires (line 731), `tcEnv` contains the
correct Γ — but `inferHole` only calls `recordHole name HoleUnknown`. **The
environment is available at exactly the right moment but isn't saved.**

The fix:

1. Extend `SketchHole` with `shEnv :: TypeEnv`
2. In `inferHole (HNamed name)`, snapshot `gets tcEnv`
3. In `checkExpr (EHole (HNamed name)) expected`, do the same
4. Serialize delta (`Map.difference tcEnv builtinEnv`) in checkout response —
   this gives the agent exactly the user-introduced bindings without redundant
   builtins that are already in the system prompt

This approach automatically handles all scoping edge cases:

- **Nested let scoping** — both `x` and `y` appear because the snapshot runs
  inside nested `withEnv` calls
- **Shadowing** — `Map.insert` overwrites, so only the inner binding appears
- **Match arm bindings** — `checkPattern` runs inside `withEnv`, so `val : T`
  from a `Success(val)` arm is in `tcEnv` when the hole body is checked
- **Context Completeness Invariant** holds by construction: we are reading the
  same Γ that the type checker uses

**Additional requirements:**

- **Monomorphize Σ entries** against concrete Γ types (resolves the
  parametricity gap structurally)
- **Include `tcAliasMap` entries** for any `TCustom` types referenced by Γ or τ,
  so the agent can construct values of user-defined ADTs
- **Configurable scope limit** (`--checkout-scope-limit 50`) for serialization,
  prioritizing: (1) function parameters, (2) `let` bindings, (3) `match` arm
  bindings, (4) `open` imports (lowest priority, truncated first). When
  truncation occurs, add `"scope_truncated": true` to the checkout JSON.
- **Shadowing-safety constraint:** Never truncate a binding that shadows a
  higher-priority binding. If a `let` binding `x : string` shadows a parameter
  `x : int`, dropping the `let` binding would expose the wrong type to the
  agent. Implementation: inner scope entries always take precedence via
  `Map.union` (which `Map.insert` in `withEnv` already provides); the
  serialization truncation step must not re-expose shadowed names.
  Test: `prop_truncationPreservesShadowing`.

---

## 5. Recommendation

**Phase A (immediate):** Implement **Option A** — add the corrected built-in
reference and evaluation rules to the system prompt. This is a single-file edit
to `agent.py` and immediately improves fill accuracy.

**Pre-requisite for Phase A:** Fix the `string-empty?` phantom — either
implement it in the compiler (`builtinEnv` + `runtimePreamble` + LLMLL.md §13.6)
or remove it from the proposed prompt. Shipping a prompt that references a
non-existent function is worse than shipping no reference at all.

**Phase B (v0.3.4):** Implement **Option B** — `llmll spec --agent` so the
reference is compiler-generated and can't drift. Replace the hardcoded prompt
text with the compiler's output.

**Phase C (v0.4):** Implement **Option C** — context-aware checkout. This
becomes important when programs grow beyond a handful of functions and the
agent needs to understand scope and available APIs without the full program
in context.

---

## 6. Related Issues

- **`string-empty?` is a phantom function.** It does not exist in `builtinEnv`
  (TypeCheck.hs), `runtimePreamble` (CodegenHs.hs), or LLMLL.md §13.6. A call
  to `string-empty?` will emit an `"unbound variable"` warning during type
  checking, then fail at runtime. The codegen translates it to `string_empty'`
  in Haskell (via `toHsIdent`), but the preamble doesn't define it. The fix
  must touch all three locations:
  1. `builtinEnv` in TypeCheck.hs: `("string-empty?", TFn [TString] TBool)`
  2. `runtimePreamble` in CodegenHs.hs: `string_empty' s = null s`
  3. §13.6 in LLMLL.md

- **Agent mistakes doc:** [`getting-started.md §4.8`](file:///Users/burcsahinoglu/Documents/llmll/docs/getting-started.md#L478)
  lists common agent errors. This content should be promoted into the system
  prompt once Option A is implemented.

---

## 7. Resolved Design Questions

**Q1 — `letrec` semantics in prompt:**
Resolved. Add a minimal 2-line note to A.2 (already included above). No
compiler changes needed.

**Q2 — `gen`/`check` blocks in prompt:**
Resolved. Defer to v0.4. Agents currently fill only `?delegate` and `?named`
holes, not `check` property bodies.

**Q3 — Type definitions in Option C:**
Resolved. Include referenced type definitions from `tcAliasMap` in the checkout
response. For `TSumType` bodies, serialize constructor names and payload types.

**Q4 — Agent tool-use access to the type checker:**
Resolved. See §8 below. No compiler changes needed for Phase A/B.

**Q5 — Remove `is-valid?` from `builtinEnv`?**
**Decision: Remove.** A function `bool → bool` with no documented semantics
beyond identity is actively harmful — agents may discover it via trial-and-error
and insert semantically vacuous `is-valid?` calls. A missing function produces
an `"unbound variable"` diagnostic (clear correction path); a vacuous function
produces code that type-checks but does nothing (invisible, undebuggable).
Removal is a one-line delete with zero downstream impact — no LLMLL program in
`examples/` or `tests/` references it. If a future validation hook is needed,
re-introduce it with defined semantics. **Implementation note:** grep for
`is-valid?` in the test suite before deleting.

**Q6 — Is substitution-based unification on the roadmap?**
**Decision: The parametricity prompt note is permanent; Algorithm W is a
separate track.** The prompt note and the unifier upgrade solve *different
problems*:

- **The prompt note** solves the *agent specification* problem: the agent
  doesn't know that `TVar` is a wildcard, so it must be told to self-enforce
  consistency. This is needed **regardless** of the unifier.
- **Algorithm W** solves the *compiler soundness* problem: the type checker
  should reject `list-head (42 :: Int)` with a concrete diagnostic. This is
  **independent** of the agent.

Even with a sound unifier, the parametricity prompt note remains useful — it
teaches the agent what polymorphism means in LLMLL, which the agent doesn't
know from training data. Plan for the prompt note to be permanent. Treat
Algorithm W (full substitution-based unification with occurs checks,
let-generalization, and `TDependent` interaction) as a post-v0.4 independent
quality-of-life upgrade.

**Q7 — Payload size concern with `open` imports in `SketchHole`.**
**Decision: Add a configurable scope limit at the serialization boundary.**

- `SketchHole.shEnv` stores the **full** delta (`tcEnv \ builtinEnv`) for
  correctness and testing
- The limit applies only at the **serialization boundary** (`llmll checkout`
  JSON response)
- Default: `--checkout-scope-limit 50` (most holes have <20 in-scope bindings)
- When truncation occurs, add `"scope_truncated": true` to the JSON
- Truncation priority: (1) function parameters — always included,
  (2) `let` bindings — innermost-first, (3) `match` arm bindings,
  (4) `open` imports — truncated first
- **Shadowing-safety constraint:** Never truncate a binding that shadows a
  higher-priority binding. If `let x : string` shadows param `x : int`,
  dropping the `let` would expose the wrong type. Inner scope entries always
  take precedence. Test: `prop_truncationPreservesShadowing`.

---

## 8. Agent Pre-Validation Analysis

### Current Architecture

The orchestrator already runs the compiler in the loop
([`orchestrator.py:217`](file:///Users/burcsahinoglu/Documents/llmll/tools/llmll-orchestra/llmll_orchestra/orchestrator.py#L217)):

```
Agent generates patch → orchestrator writes to temp file →
  llmll patch (apply + re-verify) →
    if rejected: diagnostics fed back to agent → retry (up to 3)
```

`llmll patch` is atomic: it applies the RFC 6902 patch AND type-checks the
result in a single step. If verification fails, the patch is not committed
and the checkout lock is preserved.

### Analysis

**Reading 1: "Should the orchestrator pre-check before `llmll patch`?"**

No. This is redundant. `llmll patch` already runs the full type checker
before committing. Adding a `llmll check` call before `llmll patch` would
type-check the same AST twice. The only cost saved is the patch-application
step, which is negligible compared to the LLM API call.

**Reading 2: "Should the agent have tool-use access to the compiler?"**

This is the architecturally interesting version. Currently the agent is a
single-shot text generator. Giving the agent access to a type-checking oracle
(via `llmll serve`'s `POST /sketch`) would enable iterative refinement:

```
Agent internally:
  1. Draft candidate expression
  2. Query: "Is (list-map users (lambda [(u string)] (string-length u)))
             well-typed here?"
  3. Oracle responds: "No — u must be User, not string"
  4. Agent revises and re-queries
  5. Submit only when the oracle confirms
```

This transforms the agent from an **open-loop generator** into a
**closed-loop synthesizer** — the difference between *guess-and-check* and
*type-directed synthesis*. This aligns with the PLT concept of *proof search*
where the type system guides term construction. The `POST /sketch` endpoint
already exists.

The obstacle: current LLM APIs don't natively support iterative tool-use
within a single generation. This requires an agentic framework with
function-calling loops.

**Reading 3: "Should the orchestrator test multiple candidates?"**

A middle ground: generate N candidates, pre-check all N, submit only the
passing one. However, this duplicates AST management logic and adds complexity
for marginal gain.

### Recommendation

**Don't add pre-validation.** The current architecture is sound. Instead:

1. **Phase A (immediate):** Better prompts reduce the *rate* of bad patches by
   giving the agent enough semantic information to get it right on the first
   attempt. This attacks the root cause.

2. **Post v0.4:** When the architecture supports multi-turn agent loops, give the
   agent access to `POST /sketch` as a tool. This converts empirical constraint
   solving (guess → reject → guess) into type-directed search (query → refine →
   query → submit).

The key insight: **pre-validation doesn't reduce LLM API calls.** The cost is
dominated by inference, not compilation. Fix the prompt, and you fix the economics.

---

## 9. Compiler Team Action Items

Consolidated from all review comments. Items are grouped by phase.

### Phase A (immediate — ~1 day, single-file edit to `agent.py`)

| # | Action | Blocking? | Source |
|---|--------|-----------|--------|
| A1 | Add `pair`/`first`/`second` signatures to the prompt reference | ✅ Yes — blocks do-notation | §1, §4 |
| A2 | Fix comparison operators: `< > <= >=` are `int → int → bool`, not polymorphic | ✅ Yes — causes silent failures | §4 |
| A3 | Add `regex-match`, `seq-commands` to prompt reference | No | §4 |
| A4 | Remove `string-empty?` from prompt (or implement it first — see A8) | ✅ Yes — phantom function | §4, §6 |
| A5 | Add `pair` and `fn-type` type nodes to the Valid Type Nodes section | ✅ Yes — blocks pair return types | §1, §4 |
| A6 | Add ok/err vs Success/Error explicit callout block | No | §4 |
| A7 | Add fixed-arity operator rule and parametricity note to A.2 | No | §4 |
| A8 | **Pre-requisite:** Implement `string-empty?` in `builtinEnv` + `runtimePreamble` + LLMLL.md §13.6, OR remove from proposed prompt | ✅ Yes | §6 |
| A9 | Add minimal `letrec` note (2 lines) to evaluation rules | No | §7 Q1 |
| A10 | Exclude `is-valid?` and `wasi.*` from the builtin reference | No | §4, §7 Q5 |

### Phase B (v0.3.4 — ~3 days)

| # | Action | Source |
|---|--------|--------|
| B1 | New module `LLMLL/AgentSpec.hs` — must `import builtinEnv` directly | §4 |
| B2 | Partition functions vs operators in the emitter (do not filter symbolic keys) | §4 |
| B3 | Add `prop_specCoversAllBuiltins` property test | §4 |
| B4 | Use Haskell-style polymorphic notation (`a → Result[a, e]`) | §4 |

### Phase C (v0.4 — ~5 days)

| # | Action | Source |
|---|--------|--------|
| C1 | Extend `SketchHole` with `shEnv :: TypeEnv` | §4 |
| C2 | Snapshot `gets tcEnv` in `inferHole (HNamed name)` and `checkExpr (EHole (HNamed name))` | §4 |
| C3 | Serialize delta (`tcEnv \ builtinEnv`) in checkout response | §4 |
| C4 | Include `tcAliasMap` entries for `TCustom` types referenced by Γ or τ | §7 Q3 |
| C5 | Monomorphize polymorphic Σ signatures against concrete Γ types | §1, §4 |
| C6 | Add `--checkout-scope-limit N` flag for serialization cap | §4 |

### Resolved decisions (formerly open)

| # | Question | Decision | Source |
|---|----------|----------|--------|
| D1 | Remove `is-valid?` from `builtinEnv`? | **Yes — remove** (one-line delete, zero downstream impact) | §7 Q5 |
| D2 | Is substitution-based unification on the roadmap? | **No (for now)** — parametricity prompt note is permanent; Algorithm W deferred to post-v0.4 as independent track | §7 Q6 |
| D3 | Scope limit for `SketchHole` serialization? | **Yes — `--checkout-scope-limit 50`** with shadowing-safety constraint and `prop_truncationPreservesShadowing` test | §7 Q7 |
