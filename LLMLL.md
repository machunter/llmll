# LLMLL: Large Language Model Logical Language (v0.14.88)

**`llmll`** is a programming language designed specifically for AI-to-AI implementation under human direction. It prioritizes contract clarity, token efficiency, and ambiguity resolution over human readability.

> **Current version: v0.14.88.** See [`CHANGELOG.md`](CHANGELOG.md) for release notes and [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) for the schedule.

> **For AI code generators:** Every section contains at least one complete, compilable example. When generating LLMLL code, you must use only the constructs defined in this document. If a required construct is missing, emit a named `?hole` and document the gap — do not invent syntax.

---

## 0.1 Semantic Foundation

LLMLL's operational semantics are defined by the generated Haskell program. The compiler is the reference implementation: if the generated Haskell compiles and runs, that is the correct behavior. There is no separate formal semantics document. Verification conditions emitted by `llmll verify` are sound with respect to this generated-program semantics under mathematical-integer (unbounded) semantics — a verified contract holds for all well-typed inputs of the generated Haskell code, modulo the `Int64` overflow gap documented in §5.3.5. Compositional reasoning: when function `f` calls contracted function `g`, the verifier proves that `f` satisfies `g`'s precondition (obligation) and assumes `g`'s postcondition (hypothesis). This assume-guarantee composition is sound when both functions are independently verified. Functions in recursive call cycles are verified compositionally by the **mutual-recursion assume-guarantee rule** — each cycle member's body-VC assumes its callees' postconditions and proves its own body — which is sound at **partial** correctness (Hoare 1971; Apt, *Ten Years of Hoare's Logic*, TOPLAS 1981): a non-terminating recursion vacuously satisfies its postcondition. Termination is not discharged (the R7 strict-descent item would upgrade partial→total), and the trust report does not yet flag the partiality on the `def-shell` recursive path (§4.3).

---

## 1. Core Philosophy

1. **Strict Immutability:** There are no variables, only constants. State is transformed, never mutated. Re-binding the same name in the same scope is a compile error. Shadowing in nested scopes (e.g., a `let` binding that reuses a parameter name) is permitted but discouraged — the verifier alpha-renames shadowed bindings internally.
2. **Hole-Driven Development:** Ambiguity is a first-class citizen represented by Holes (`?`). A program with holes can be analyzed and type-checked but not executed until the holes are filled. Always prefer a typed hole over a hallucinated implementation.
3. **Typed Logic:** Every expression has a type. The type system prevents null pointer dereferences, type mismatches, and unguarded IO.
4a. **Design by Contract with Stratified Verification:** Logic functions declare `pre` and `post` conditions as formal specifications. These contracts are the trust interface between agents. Verification is stratified: contracts in the decidable arithmetic fragment (QF-LIA) are verified at compile time via liquid-fixpoint / Z3; contracts outside that fragment are enforced as runtime assertions and flagged with `?proof-required`. An interactive proof path (Lean 4 via Leanstral) is designed but not yet shipped (see §5.3.3). Each contract clause carries a *display level* — `verified`, `contract-checked`, `tested`, or `asserted` — so a caller can inspect trust without reading the implementation.
4b. **Transitive Trust Propagation:** Trust levels propagate through call chains: no `verified` conclusion rests silently on an `asserted` assumption. A function's effective display level is the lattice meet of its own level and all transitively reachable callees' levels.
5. **Compositional Verification:** Verification extends beyond isolated functions. When a function calls a contracted callee, the verifier proves the caller satisfies the callee's precondition and assumes the callee's postcondition holds (assume-guarantee reasoning). This enables body-faithful verification across multi-function call chains without inlining. Recursive cycles are verified compositionally via the mutual-recursion assume-guarantee rule at **partial** correctness (termination unverified — §4.3), not contract-only.
6. **Declared Effect Namespaces:** A module reaches no part of the system it has not imported, and the compiler rejects a `wasi.*` call whose namespace the calling module did not declare. Imports are non-transitive, so every module states its own reach. The `capability` clause on an import records the intended verb and target but is **not yet enforced** (§7); the checked property is namespace declaration, not least authority. Every side effect is modeled as a `Command` value returned from pure logic, never performed directly, and what performing it produced comes back as a `Response` (§9.7). See §7 for the sandbox implementation and the enforcement gap.

---

## 2. Syntax (S-Expressions)

`llmll` uses Lisp-style S-expressions to represent the Abstract Syntax Tree (AST) directly. This is token-efficient and eliminates parsing ambiguity.

### 2.1 Basic Tokens

- **Keywords:** `module`, `import`, `def`, `def-shell`, `def-interface`, `type`, `let`, `if`, `match`, `check`, `pre`, `post`, `for-all`, `gen`, `pair`, `fn`, `where`, `await`, `do`. Under `--grammar=legacy` only: `letrec`.
- **Reserved identifiers:** `result` (see §4.2), `unit`, `true`, `false`.
- **Primitive types:** `int`, `float`, `string`, `bool`, `unit`.
- **Holes:** Always start with `?` (e.g., `?logic_name`, `?choose(option1, option2)`).
- **Comments:** `;; text` — from `;;` to end of line. Ignored by the compiler.
- **Source encoding:** Source files are **UTF-8**. **Identifiers must be ASCII** (letters, digits, `-`, `_`, and `?` in terminal position only — e.g., `done?`, `string-empty?`, `is-game-over?`). A leading `?` denotes a hole (§6) and is lexed separately. A curated set of Unicode mathematical symbols are accepted as **aliases** for specific keywords and operators — see §2.4. All other non-ASCII characters are a lexer error.
- **S-expression string escapes:** `\n`, `\t`, `\r`, `\\`, `\"`, and `\uXXXX`. Standard Haskell-style character escapes.
- **JSON-AST string values** follow RFC 8259 — non-ASCII and control characters must be encoded as `\uXXXX` (e.g. `\u001b` for ESC). The C-style `\xNN` form is not valid JSON.

### 2.2 Qualified Identifiers

Capability-namespaced names use dot notation and are called **qualified identifiers** (`QualIdent`):

```
wasi.io.stdout
wasi.http.response
wasi.fs.write
```

A `QualIdent` is one or more plain identifiers joined by `.`. They are valid in function-call position (`app` expressions) and in `import` forms. Plain identifiers (`IDENT`) may not contain dots.

### 2.3 The Arrow Token

Both `->` (ASCII) and `→` (U+2192) are accepted and produce the same ARROW token. The lexer uses **maximal munch**: `->` is always tokenized as a single ARROW, never as subtraction followed by greater-than. There is no position ambiguity: ARROW only appears in type position (after a parameter list in `fn-type` or `def-interface`), while `-` (subtraction) and `>` (comparison) only appear in expression position.

### 2.4 Unicode Symbol Aliases

A curated set of Unicode mathematical symbols are accepted everywhere their ASCII equivalents are valid. Both forms compile to **identical AST nodes**. The compiler's canonical output and error messages always use the ASCII form. LLMs may use whichever form they prefer in generated code.

| ASCII | Unicode | U+ | Meaning |
|-------|---------|----|---------|
| `->` | `→` | U+2192 | Function / return arrow |
| `>=` | `≥` | U+2265 | Greater-or-equal |
| `<=` | `≤` | U+2264 | Less-or-equal |
| `!=` | `≠` | U+2260 | Not-equal |
| `and` | `∧` | U+2227 | Logical conjunction |
| `or` | `∨` | U+2228 | Logical disjunction |
| `not` | `¬` | U+00AC | Logical negation |
| `=>` | `⇒` | U+21D2 | Logical implication — sugar for `(or (not p) q)` |
| `<=>` | `⇔` | U+21D4 | Biconditional — sugar for `(and (=> p q) (=> q p))` |
| `for-all` | `∀` | U+2200 | Universal quantifier |
| `fn` | `λ` | U+03BB | Lambda / anonymous function |

**Implication sugar.** `=>` and `<=>` are binary `bool → bool → bool` operators, desugared at
verification-condition emission to the `or`/`not` forms above — the emitted `.fq` is byte-identical,
so nothing in the decidable fragment (§5.3.3) changes. Both are first-class in the S-expr surface and
the JSON-AST (op values `"=>"` / `"<=>"`, retained through round-trip); the schema op enum was
extended additively, with `schemaVersion` unchanged.

**What is NOT allowed:** Unicode-encoded variable names, function names, type names, or module names. Identifiers must be ASCII. This restriction prevents homoglyph attacks and invisible-character exploits in multi-agent AST merging (see `docs/archive/older_discussions_and_plans/unicode_decision.md` for full rationale).

**Mixed-form example** — both lines are semantically identical:

```lisp
;; ASCII form
(def-interface AuthSystem
  [hash-password (fn [raw: string] -> bytes[64])]
  [verify-token  (fn [token: string] -> bool)])

;; Unicode form
(def-interface AuthSystem
  [hash-password (λ [raw: string] → bytes[64])]
  [verify-token  (λ [token: string] → bool)])
```

### 2.5 Naming Conventions

LLMLL's identifier character class (§2.1) permits both `-` and `_`. The shipping language uses **kebab-case** as its canonical form. Agents emitting LLMLL should follow these conventions to remain idiomatic:

| Construct | Convention | Example |
|---|---|---|
| Function / variable / parameter names | **kebab-case** | `safe-subtract`, `account-id`, `from-balance` |
| Type names | **PascalCase** | `Ledger`, `Balance`, `PositiveInt` |
| Constructor / variant names | **PascalCase** | `Success`, `Error`, `Ok` |
| Boolean predicates | **kebab-case + trailing `?`** | `empty?`, `string-empty?`, `is-game-over?` |
| Built-in keywords and builtins | **kebab-case** (no underscore) | `def`, `def-shell`, `for-all`, `string-length`, `list-empty` |
| Reserved identifiers | **lowercase** | `result`, `unit`, `true`, `false` |

**Cross-language API spec translation.** When a language-neutral problem statement uses snake_case (`create_ledger`, `total_balance`) or camelCase (`createLedger`), the LLMLL solution must transliterate to kebab-case: `create-ledger`, `total-balance`. The grammar **accepts** snake_case and camelCase identifiers, but the canonical examples and built-in surface use only kebab-case; emitting non-kebab identifiers produces parseable but non-idiomatic LLMLL.

**Note on `_` vs `-` in the grammar.** Both characters are accepted in the identifier character class per §2.1. The choice is stylistic, not syntactic. The convention exists for consistency with shipping examples and built-ins, not because the grammar forbids alternative forms.

---

## 3. The Type System

### 3.1 Primitive Types

| Type | Description | Example values |
|------|-------------|---------------|
| `int` | Mathematical integer (unbounded; lowers to Haskell `Integer` at codegen) | `0`, `-1`, `9999` |
| `float` | 64-bit IEEE 754 double | `3.14`, `-0.5` |
| `string` | Immutable UTF-8 byte sequence | `"hello"`, `""` |
| `bool` | Boolean | `true`, `false` |
| `unit` | No-value type (result of pure IO commands) | `()` |

> [!NOTE]
> **`int` arithmetic and the verifier.** The verifier reasons over Z3 mathematical integers (unbounded), and `int` lowers to Haskell `Integer` (also unbounded) at codegen — both sides of the verifier/runtime boundary are now mathematical integers, and there is no `Int64` overflow gap on `int`. The `overflow_tainted` machinery — `erOverflowTainted` field on `EvidenceRecord`, `overflow_tainted` JSON projection, `--strict-verified-core` refusal — is preserved across the trust-report / sidecar / obligation surface; the trigger set is empty on `int` values (the body-VC emitter does not call the walker for `int` arithmetic). A future `machine-int` opt-in under QF-BV re-arms the trigger with type-awareness. See §5.3.5 for the verification-matrix row. The `int` row above describes the unbounded codegen lowering; the verifier-side semantics are at §0.1 (semantic foundation) and §5.3.5 (verification matrix + closure note).

### 3.2 Compound Types

| Type | Description | Example |
|------|-------------|---------|
| `bytes[n]` | Fixed-length byte array of exactly `n` bytes | `bytes[64]` |
| `list[t]` | Homogeneous ordered list | `list[int]`, `list[string]` |
| `map[k,v]` | Key-value dictionary | `map[string,int]` |
| `Result[t,e]` | Success (`t`) or Error (`e`) | `Result[int,string]` |
| `Promise[t]` | Pending async value | `Promise[ImageBytes]` |
| `(a, b)` | 2-tuple (product type) | `(int, string)` |
| `Command` | An IO effect (see §9) | _(constructed via capability constructors only)_ |
| `Response` | What performing a `Command` produced (see §9.7) | `(match r ((RText t) …))` |
| `Json` | An opaque JSON value (see §13.13) | _(produced by `json-parse` or the `json-of-*` injections)_ |

> `Command` is opaque: it is only produced by the standard command constructors (§13.9), and is currently emitted as Haskell `IO ()`. Calling any `wasi.*` constructor requires that the module declare that namespace (§7).

> `Response` is a builtin sum type with five arms (`RNone`, `RText string`, `RCode int`, `RErr string`, `RList list[string]`). Unlike `Command` it is transparent: a program matches on it to consume an effect's result. It is supplied by the console harness as the third argument to `:step` and is never constructed by user code.

> `Json` is **sealed and opaque**: no program-visible structure, no constructors, no `match` form. It is produced only by `json-parse` and the `json-of-*` injections (§13.13), and a program may not redefine the name. Its fourteen operations are `def-shell`-only, and equality is not defined on it (§13.2).

> `bytes[n]` and `map[k,v]` have a builtin operation family — indexing, update, presence, construction — catalogued in §13.12.


### 3.3 Algebraic Sum Types (Custom Variants)

User-defined tagged unions (also called ADTs or discriminated unions) are declared with the `type` keyword using `(| ConstructorName PayloadType)` arms:

```lisp
;; A sum type with two constructors
(type GameInput
  (| Start  Word)    ;; carries a Word value
  (| Guess  Letter)) ;; carries a Letter value

;; A sum type with nullary constructors (no payload)
(type Color
  (| Red)
  (| Green)
  (| Blue))

;; A sum type with multiple fields (use pair encoding)
(type Shape
  (| Circle  float)           ;; radius
  (| Rect    (float, float))) ;; width, height
```

**Construction:** A nullary constructor (`(| Variant)`) is written as a bareword identifier. A payload-bearing constructor is written as a function call with the payload:

```lisp
(let [[c Red]]                  ;; c : Color (nullary, bareword)
  ...)

(let [[ev (Start "hangman")]]   ;; ev : GameInput (payload-bearing, call form)
  ...)
```

For unit-payload constructors (discouraged for new code; see "Idiomatic guidance" below), the unit literal `()` is the payload — not the bareword `unit`, which parses only as a type:

```lisp
(let [[s (Idle ())]]            ;; s : Status, where Status is declared (| Idle unit)
  ...)
```

**Destruction:** Use `match` (see §3.4). Every `match` on a sum type must be exhaustive.

**Pattern arity.** Each constructor pattern's sub-pattern count must equal the declared arity of the constructor at its declaration site. A constructor declared `(| Red)` has arity 0 and matches with zero sub-patterns. A constructor declared `(| Red unit)` has arity 1 and matches with one sub-pattern (conventionally `_`). A constructor declared `(| Circle float)` has arity 1 and matches with one sub-pattern bound to the payload. Mismatch produces a typechecker warning.

**A constructor pattern is always parenthesized.** A nullary constructor matches as `((Red) …)`, never as `(Red …)`. A bare identifier in pattern position is a **binder**, so `(Red "stop")` would bind a fresh variable named `Red` and match everything, turning the arm into a catch-all and making every later arm dead. Because that reading is almost never what the author meant, and because it previously let the verifier reason about a different program than the one codegen emitted, the typechecker **rejects** a bare pattern variable whose name is a constructor of the scrutinee's type — user sum types and `Result` alike — and names the correct form in the diagnostic. A catch-all binder whose name is *not* a constructor of the scrutinee type (`(other …)`, `(_ …)`) is unaffected.

```lisp
(match light
  ((Red)    "stop")
  ((Green)  "go")
  ((Blue)   "wait"))

(match event
  ((Start word)      ...)           ;; payload bound to `word`
  ((Guess letter)    ...))
```

**Idiomatic guidance.** For Boolean-style enums where no constructor carries a payload, declare each variant in the **nullary form** `(| Variant)`. The unit-payload form `(| Variant unit)` is accepted by the parser and produces a distinct AST shape — the generated Haskell encodes it as `Variant ()`, not `Variant` (per `CodegenHs.hs`) — but is **discouraged** for new declarations. The unit-payload form is preserved for backward compatibility and for the narrow case of Haskell-codegen interop where a downstream consumer destructures the `Variant ()` shape directly.

**Note on `unit`.** The type `unit` is a singleton, with sole inhabitant `()`. A wildcard match `((Variant _) body)` against a unit-payload variant is information-free at the value level, but the AST and the generated Haskell preserve the unit-payload slot regardless. The arity-1 requirement is what keeps the surface consistent with the AST and the codegen target.



### 3.4 Refinement Type Aliases (Logic-Constrained)

Any base type can be constrained by a predicate using `(where [binding: base] predicate)`. These are **refinement-like annotations** — the predicates are checked by the verification layer (`llmll verify`) within the QF-LIA fragment, or enforced as runtime assertions depending on trust level. They are not dependent types in the Idris/Lean sense: LLMLL has no dependent elimination, proof terms, or sigma types.

```lisp
(type PositiveInt  (where [x: int]    (> x 0)))
(type Word         (where [s: string] (> (string-length s) 0)))
(type Letter       (where [s: string] (= (string-length s) 1)))
(type GuessCount   (where [n: int]    (>= n 0)))
(type BlockID      (where [s: string] (regex-match "^[a-f0-9]{64}$" s)))
```

Refinement type alias constraints are **checked at compile time**: the constraint expression is type-checked with the binding variable in scope. The type checker expands type aliases structurally at call sites — passing a `string` literal where a `Word` (defined as `where [s: string] ...`) is expected works correctly. Compile-time SMT verification of constraint *values* is performed by `llmll verify`. See §5.3.5 for a precise matrix of which constructs are verified at each level.

> [!NOTE]
> **Obligation-guided agent coding.** LLMLL provides the Idris workflow *feel* — goal-directed construction from rich obligations — through structured obligation reports that expose type, contract, and trust obligations to agents. `llmll verify --obligation-report` emits a JSON report with three channels per obligation, repair suggestions, and function lists. See [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md).

#### 3.4.1 Checking-mode inference rule

For a refinement-aliased type `A ≜ (where [x: τ] p)` (where `A` is the alias name, `τ` the underlying base type, and `p` the refinement predicate), the **checking-mode rule** is:

```
Γ ⊢ e : τ ⇝ O
Γ ⊢ p[e/x] obligation
─────────────────────────
Γ ⊢ e ⇐ A ⇝ O ∪ { p[e/x] }
```

**Introduction.** When checking `e` against `A`, the type checker confirms `e` synthesizes the underlying base type `τ` (structural compatibility via `expandAlias` and `unify`, both in `TypeCheck.hs`), and the refinement predicate `p[e/x]` joins the obligation set.

**Elimination** is the dual: when `Γ` binds `x : A`, uses of `x` add `p` as a hypothesis to the typing context for downstream obligations within `x`'s scope:

```
Γ, x : A ⊢ e' : τ' ⇝ O'
─────────────────────────────────────
Γ, x : τ, p ⊢ e' : τ' ⇝ O'   (elim)
```

Introduction emits an obligation; elimination introduces a hypothesis. The pair makes refinement aliases *checked invariants* without exposing a user-visible subtyping relation.

**Two-phase implementation.** [`TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs) handles structural compatibility via `inferExpr` / `checkExpr` / `unify`; [`Contracts.hs`](compiler/src/LLMLL/Contracts.hs) and [`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs) emit the refinement-predicate obligation at introduction sites and add the hypothesis at elimination sites. The unified spec-level judgment is the conjunction of both phases; no single-pass refactor is implied.

**Hypothesis lexical scoping.** The refinement hypothesis introduced at a binding site is *lexically scoped* — available within the binding's body but not propagated outside or across function boundaries. LLMLL has no flow-sensitive refinement reasoning; a variable's refinement hypothesis is determined by its declared type at the binding site (consequence of non-goal §3.4.2 #1).

#### 3.4.2 Non-goals (exhaustive)

The following features are **deliberately absent** from LLMLL's refinement surface. The list is closed; a proposed addition is adjudicated per [What's NOT on this Roadmap](docs/compiler-team-roadmap.md#whats-not-on-this-roadmap-and-why) and lands with a written soundness argument as part of its design record.

1. **No general refinement subtyping (`<:`).** LLMLL has no user-visible subtyping relation between refinement-aliased types. Refinement aliases interact only via the checking-mode rule (§3.4.1), which generates obligations at concrete introduction sites. This is operationally equivalent to Liquid Haskell's subtyping formulation at introduction sites (both produce the same obligation `p[e/x]`) — see Vazou et al. *Refinement Types for Haskell*, POPL 2014 — but the narrower surface pre-empts the closure of abstract, parametric, and bounded refinements that the broader subtyping framing invites.

2. **No dependent pattern matching.** Pattern matching on a refinement-aliased value binds the underlying base type. A `match` arm on a `Letter` value (where `Letter ≜ (where [s: string] (= (string-length s) 1))`) binds `s : string`. The refinement hypothesis is available within the arm's lexical scope via the elimination rule (§3.4.1) but does not refine the bound variable's declared type.

3. **No type-level computation.** Refinement predicates are first-order propositions in the QF-LIA fragment (or escape to `?proof-required`); they are not types. `(where [n: int] (> (factorial n) 0))` is not legal — the predicate must be a first-order proposition over base-typed bindings. See §3.4.4 (W-Catalog): the exclusion is formally a `Σ_ref` membership failure.

4. **No proof terms.** Users do not author proof terms in LLMLL surface. Proof obligations are discharged by the verifier (QF-LIA fragment via liquid-fixpoint, §5.3.3) or routed to `?proof-required` for offline discharge (Leanstral pipeline).

5. **No sigma types.** LLMLL has no dependent pair `Σ x : τ. p[x]`. A refinement-aliased type `A ≜ (where [x: τ] p)` is not a pair — no first projection extracting `x`, no second projection extracting a proof of `p[x]`.

6. **No boolean-expression-as-type-equality.** LLMLL has no propositional equality type `e₁ ≡ e₂`. A refinement predicate may use an equality expression (`(= x 0)`), but no type-level proposition `e₁ ≡ e₂` exists.

> Refinement-polymorphic functions and termination-via-refinement (Liquid Haskell, Vazou et al. ESOP 2013) are consequences of non-goals #1 and #3 respectively; deferred to the predicate well-formedness rule (§3.4.4) for explicit treatment of refinement-variable binding shapes.

#### 3.4.3 Soundness statement of record (tier-aware, Path A)

> If `Γ ⊢ e : τ ⇝ O`, all obligations in `O` are discharged at solver-backed evidence level, codegen is faithful for the involved constructs, and no trusted FFI/opaque primitive is used, then the erased generated program preserves the declared refinement predicates at checked introduction and elimination sites.

All four preconditions are necessary — dropping any one breaks the claim:

1. **Obligations discharged at solver-backed evidence level.** The function's evidence record (§4.4) is `verified` with body-faithful discharge — not `tested`, not `asserted`, not `verified` with body-fallback (the body-fallback path in `FixpointEmit.hs`).
2. **Codegen is faithful.** Per §5.3.5: non-recursive QF-LIA with compositional call-chain reasoning. Constructs outside that set lower into runtime assertions or fall back to contract-only verification; the soundness claim does not extend to them under the same tier.
3. **No trusted FFI or opaque primitive.** Functions reaching crypto stubs (§13.11) or other `asserted`-tier dependencies do not satisfy the precondition.
4. **`erBodyFallback` and `erOverflowTainted` are not set, and the body VC is not refuted.** The overflow-taint mechanism (`Syntax.hs`) marks overflow-tainted verified evidence; a body-faithful function whose VC the solver reports UNSAFE is *refuted* (§4.4) and assigns no `verified` evidence. `--strict-verified-core` refuses all three.

**Operational enforcement.** `--strict-verified-core` is the operational embodiment of this statement. The strict-tier admissibility set is the *closure under composition*: a function fails admission if any callee in its transitive call graph has `erBodyFallback = True`, `erOverflowTainted = True`, a **refuted** body VC (solver UNSAFE), or an `asserted`-tier dependency. The solver-verdict conjunct is a *side condition*, not a quantifier over solver runs, precisely because body-faithful VCs are confined to `Σ_auto` — QF-LIA, the measure class (a decidable local theory extension, §5.3.3), the **acyclic datatype theory** (decidable per Barrett–Shikanian–Tinelli; combined with QF-LIA by polite-theory combination), and the **Bool sort** (a native `bool` value — parameter, result, refinement atom, or `if`-condition — for which `QF-LIA + Bool` is decidable; `float`/`string`/`unit` stay outside as *carrier* sorts, `float` rejected inside int predicates and `string` measure-only for structure — though **string-literal (dis)equality and length** now reflect into `Σ_auto` via content-interned `Str` constants + ground pairwise-distinctness + per-literal code-point length pinning (QF_EUF + QF-LIA, STRLIT), so a `(= s "lit")` contract and its `(string-length s)` consequences discharge) — each of which is decidable, so "SAFE" is a decidable predicate on the fixed VC. The clean formulation degrades to run-dependence only if a VC outside `Σ_auto` (e.g. a recursive datatype, were the `admissibleDatatype` firewall bypassed) were admitted to the body-faithful tier. The formal derivation of the compositional closure is the erasure theorem (§3.4.5, Theorem B); its standing hypothesis is the discharged-VC-set ("all body VCs SAFE") in the VCgen/Hoare sense.

**Out-of-process-agent carve-out.** Values introduced by `?delegate` / `?delegate-async` / `?scaffold` holes are not checked-introduction sites — they arrive from out-of-process agents and fall under the trust tier per §4.4. The soundness statement does not extend to them.

**Path B declined.** A mechanized soundness theorem against an independently-defined operational semantics remains declined per [`docs/design/verification-debate.md`](docs/design/verification-debate.md). This statement is a precise *commitment*, not a mechanized *theorem*.

#### 3.4.4 Predicate well-formedness rule

A refinement alias `A ≜ (where [x: τ] p)` is **well-formed** under the admitted refinement-symbol signature `Σ_ref` when four conditions hold:

```
  x : τ ⊢ p : bool                                          (W-Sort)
  FV(p) ⊆ {x}                                               (W-Closed)
  symbols(p) ⊆ Σ_ref                                        (W-Catalog)
  every application in p saturated; no λ, no partial         (W-FirstOrder)
    application, no refinement variable
  ──────────────────────────────────────────────
  Σ_ref ⊢ (where [x: τ] p) wf
```

- **W-Sort.** `p` is `bool`-sorted under the single binding (the `p ∈ Bool` side condition; Vazou et al., *Refinement Types for Haskell*, POPL 2014). Enforced structurally by the type checker, as for the `?proof-required` predicate check.
- **W-Closed.** `FV(p) ⊆ {x}`: no free term variable other than the bound `x`. After substitution at a checked-introduction site, `p[e/x]` mentions only symbols in the ambient context.
- **W-Catalog.** Every applied function symbol is drawn from `Σ_ref` (below). User-defined functions — recursive ones especially — are excluded; this is the formalization of non-goal #3 (§3.4.2): `(where [n: int] (> (factorial n) 0))` is ill-formed because `factorial ∉ Σ_ref`, not because of a fragment failure.
- **W-FirstOrder.** `p` is first-order: no refinement variables (closing refinement-polymorphism, *Abstract Refinement Types*, ESOP 2013 — the consequence non-goal #1 names).

The judgment is **decidable** and runs at alias-definition time (the type channel); it is not an SMT obligation.

**The admitted signature `Σ_ref`** partitions into three classes with divergent discharge trajectories:

| Class | Symbols | Discharge |
|---|---|---|
| QF-LIA core | `+ - = ≠ < ≤ > ≥ and or not`, int/bool literals, `x` | QF-LIA auto |
| Measure class | `string-length`, `list-length` (`τ → int`) | **QF-LIA auto** (measure axiomatization is shipped) |
| String-literal (dis)equality + length | string literals in `=`/`≠` (interned nullary `Str` constants), and `string-length` on a literal | **QF_EUF + QF-LIA auto** (content-interned constants + ground pairwise-distinctness `injectStrLitDistinct`, plus each literal's code-point length pinned `strLen(strlit_s) = |s|` via `injectStrLitLen`; STRLIT Stage 1+2 complete — string *structure* stays out) |
| Boolean-builtin class | `regex-match` (+ builtins with a declared `bool` refinement signature) | runtime / `?proof-required`; never auto (needs an SMT string/regex theory — word equations with length is open) |

A `Word`/`Letter` refinement (measure class) reaches `verified`; a `BlockID` refinement (`regex-match`) stays `asserted` until the deferred string theory. The measure catalog is **closed** at `{string-length, list-length}`; extension requires team consensus with a totality+range argument.

**Measure-axiomatization discipline.** A measure `m : τ → int` is admissible only if it is **(M1)** total; **(M2)** reflected as an *uninterpreted* integer-valued function carrying only its range axiom (`string-length s ≥ 0`), defining equations not unfolded; **(M3)** applied to a well-formed base term over `{x}`; **(M4)** emitted as a single function-sorted symbol per measure, so the solver's congruence closure relates repeated occurrences — not abstracted to an independent fresh integer per site. Under M2+M4 the range axiom plus EUF congruence suffices for the bounded-length predicate class the catalog admits; the excluded inter-term structural relations (e.g. `len(concat s t) = len s + len t`) are exactly the predicates `Σ_ref` excludes. Auto-discharge of the measure class emits measure terms as single function-sorted UF applications with per-term ground range facts (the M4 emission discipline), placing the obligation in QF-LIA+EUF.

**Erasability.** All refinement-alias predicates erase at codegen with no computational content (§3.4.5). Erasability is governed by *proof-irrelevance* — the predicate is never eliminated into a computationally-relevant position (non-goals #2, #4, #5, #6) — not by the measure-unfolding discipline. Declining to unfold measure equations (M2) is a *co-property* governing verification decidability (QF-LIA+EUF), logic-only with no runtime projection (the reflection boundary of *Refinement Reflection*, POPL 2018, is orthogonal to erasure — refinement-reflecting systems erase all refinement content too). The full statement and its construction-side discipline are the erasure theorem (§3.4.5).

**Well-formedness versus discharge.** Well-formedness — legality, decidable, the type channel — is orthogonal to fragment classification (which well-formed predicates auto-discharge; see §5.3.3 / §5.3.5). A predicate may be well-formed yet route to a runtime assertion (`regex-match`). The rule partitions the predicates reaching the obligation channels; it introduces no new obligation.

**Stacked aliases.** A refinement over a refinement-aliased binding — `(type NonEmptyWord (where [s: Word] (> (string-length s) 1)))` with `Word ≜ (where [s: string] (> (string-length s) 0))` — is well-formed: the base expands structurally to `string`, and both predicates' obligations are incurred at the introduction site over a single common witness (`p_Word[e/s] ∧ p_NonEmptyWord[e/s]`), per the checking-mode rule (§3.4.1). This is definitional unfolding, not subtyping entailment (non-goal #1).

#### 3.4.5 Erasure theorem

Codegen lowers a refinement-aliased type `A ≜ (where [x: τ] p)` to its base type `τ`, discarding `p` (in `CodegenHs.hs`) — structurally, totally, and predicate-blind. Refinement-alias predicates carry **no runtime residue** at any introduction site: the predicate is folded into the effective VC precondition (`augmentContractPre`, in `FixpointEmit.hs`) and — for a refinement-aliased **return** — into the effective VC postcondition (`augmentContractPost`); both are verifier-local and never reach codegen. The codegen runtime assertions (in `CodegenHs.hs`) fire only for user-authored `pre`/`post`. LLMLL refinement aliases are therefore **verify-or-trust** — there is no dynamic safety net. The erasure theorem states when the predicate-blind drop is sound; like §3.4.3 it is a precise *commitment* (Path A), not a mechanized theorem (Path B declined).

**Theorem A — type-level erasure (phase distinction).**

> Let `A ≜ (where [x: τ] p)` be well-formed (§3.4.4) and lie in the **proof-irrelevance fragment** — non-goals #2, #4, #5, #6 (no dependent pattern matching, no proof terms, no sigma types, no boolean-expression-as-type-equality). Then `p` is never eliminated into a computationally-relevant position, and codegen's type-level drop `A ⟿ τ` is observation-preserving: the erased program is observationally equivalent to the predicate-carrying program.

Non-goal #2 removes runtime control flow on `p`; non-goal #4 removes any term-level inhabitant of `p` (the operative guard); non-goals #5/#6 close the sigma-projection and equality-transport erasure-breakers — currently vacuous (no surface form exists for either) but conjoined to keep the precondition robust against future surface expansion. This is a phase distinction (Harper–Mitchell–Moggi, *Phase Distinctions in Type Theory*, 1990), structurally a total erasure bisimulation (Mishra-Linger & Sheard, *Erasure and Polymorphism in Pure Type Systems*, FoSSaCS 2008); the design precedent is Ou–Tan–Mandelbaum–Walker, *Dynamic Typing with Dependent Types* (IFIP TCS 2004), and the modern comparator is Quantitative Type Theory / Idris 2 (Atkey, LICS 2018), where these refinements are multiplicity-0 ghosts.

**Theorem B — construction-side discipline (compositional closure).**

> For a program in which every refinement-typed value originates at a checked introduction site whose obligation `p[e/x]` is discharged at `verified` evidence (W-Closed ensuring the obligation is well-scoped), and whose `--strict-verified-core` admissibility set is closed under composition (§5.3.4), the erased program preserves every declared refinement invariant at runtime. Standing hypothesis: the discharged-VC-set "all body VCs SAFE" (the VCgen/Hoare reading of §3.4.3).

This is the formal derivation the soundness statement (§3.4.3) names. Because Theorem A erased the type and no runtime check exists, Theorem B carries the entire soundness load: the invariant holds at runtime only because it was discharged statically at construction and composes by the assume-guarantee discipline of §5.3.4. **W-Closed** is a Theorem-B condition (well-scopedness of the obligation), not a phase-distinction one.

**Soundness firewall.** Because there is no dynamic safety net, an *undischarged* refinement must force the carrying function off `verified`. This is enforced by the existing body-faithful-VC fallback policy, not by new machinery: a predicate outside `Σ_auto` (§5.3.3) is non-emittable (`exprToPred → Nothing`), forcing `erBodyFallback` at the definition site and at any call site (the soundness-critical three-way pre distinction in `FixpointEmit.hs`), excluding the function from `verified` and from `--strict-verified-core` (§5.3.4). No call-pre obligation is silently dropped.

**Scope boundary.** Theorem B's `verified`-tier precondition is co-extensive with `Σ_auto`-membership of the refinement predicate (§5.3.3). A predicate in `Σ_auto` (QF-LIA core + measure class) discharges, and erasure is sound with a `verified` guarantee (`Word`, `Letter`, `PositiveInt`). A predicate outside `Σ_auto` (`regex-match`, nonlinear, user functions) still erases, but the carrying function falls to `erBodyFallback` and the theorem makes no claim — a carve-out, as for the out-of-process-agent and FFI cases of §3.4.3.

**Measure abstraction is a co-property, not the hinge.** Declining to unfold measure equations (M2, §3.4.4) governs verification decidability, not erasure; it is logic-only (range axioms and EUF congruence have no runtime projection). Erasability is governed by proof-irrelevance (Theorem A), independently.

**Channel distinction.** The erasure theorem governs the refinement-alias channel (this section), distinct from the contract channel (`pre`/`post` clauses), which *does* emit runtime assertions and where `--contracts=unproven` strips `verified`-and-body-faithful postcondition assertions (§5.3.4) — the analogue of hybrid-type-checking cast-elimination. Alias predicates have no runtime residue; contract clauses do.

#### 3.4.6 Type-assignment judgment with hole-directed checking

LLMLL's type checker is **local type inference** (Pierce–Turner, *Local Type Inference*, TOPLAS 2000) over a Damas–Milner core (*Principal Type-Schemes*, POPL 1982): a single type-assignment (synthesis) judgment with per-call-site instantiation, no global unification, no subtyping (non-goal #1, §3.4.2). It carries a checking judgment, but type information enters from only two sources — **surface annotations** (parameter types, return types, annotated `let`) and **holes**. This judgment generalizes the checking-mode rule (§3.4.1) to the full surface; it is the type-assignment phase between predicate well-formedness (§3.4.4, upstream) and erasure (§3.4.5, downstream).

**Two judgments.** `Γ ⊢ e ⇒ τ` (synthesis / type assignment — the primary judgment) and `Γ ⊢ e ⇐ τ` (checking).

**Non-hole checking is definitional (Check-by-Synth).**

> ```
> Γ ⊢ e ⇒ τ'      τ ≡ τ'        (e not a hole)
> ─────────────────────────────────────────────
>                 Γ ⊢ e ⇐ τ
> ```

`τ ≡ τ'` is decidable definitional type equality: expand aliases, strip the refinement to its base, unify. This is *not* a subsumption rule: by Dunfield–Krishnaswami (*Bidirectional Typing*, CSUR 2021 §3.1), a checking judgment whose only non-hole rule is "synthesize then compare" recovers undirected type assignment. LLMLL has no subtyping and nothing for subsumption to do that `≡` does not; the type-level duality is **instantiation**, not subsumption.

**The one genuine bidirectional rule (Check-Hole).**

> ```
> ───────────────────────────────────────
> Γ ⊢ ?n ⇐ τ    ⇝ record goal τ for ?n
> ```

The sole rule where the expected `τ` flows into the term without synthesizing it — the goal-directed-construction mechanism of the sketch flow (§11.2). This is LLMLL's only bidirectional element.

**Refinement-alias instances (the §3.4.1 embedding).** At a surface-annotated position (parameter / return / annotated `let`) whose annotation is a refinement alias `A ≜ (where [x: τ_b] p)`, introduction reduces to Check-by-Synth on the base plus the contract-channel obligation:

> ```
> ⊢ A wf (§3.4.4)    Γ ⊢ e ⇒ τ'    expandAlias(A) ≡ τ'
> ─────────────────────────────────────────────────────  (⇐-Refine)
>          Γ ⊢ e ⇐ A   ⇝   { p[e/x] }
> ```

Elimination synthesizes the base type and adds the refinement as a lexically-scoped hypothesis (non-goal #2 keeps the eliminand at the base type):

> ```
> Γ(x) = A ≜ (where [y: τ_b] p)
> ─────────────────────────────────────────────
> Γ ⊢ x ⇒ τ_b      [hypothesis p[x/y] added to Γ]
> ```

The type channel checks `≡` on the base; the contract channel emits `p[e/x]` (the §3.4.1 two-phase split).

**Mode assignment.** All forms synthesize (⇒) — literals, variables, application/operator elimination, `match`, pairs, lambdas, `let` bodies. Expected types are supplied at parameter / return / annotated-`let` positions (checked via Check-by-Synth; `⇐-Refine` when the annotation is a refinement alias) and at holes (Check-Hole). The intro-checks/elim-synthesizes discipline of textbook bidirectional typing is *not* asserted: the checker is synthesis-primary. `if` reconciles its branches by one of three routes, selected by which branches are holes. With **exactly one hole**, the concrete branch is synthesized, the hole is *checked* against it (Check-by-Synth), and the concrete branch's type is the result. With **both branches concrete**, both are synthesized and compared for compatibility: an incompatible pair is diagnosed, and a compatible pair yields the then-branch's type, except that a branch synthesizing the `?` wildcard yields to a concrete sibling when that wildcard arose from a self-recursive call (RET-BRANCH-PREF). With **both branches holes**, each is synthesized independently and the result is `?`.

**The `?` wildcard.** `TVar "?"` denotes *inference produced no usable type at this position*, not *any type*. It is compatible with every type, which makes the compatibility relation reflexive and symmetric but **not** transitive. Because LLMLL erases and inserts no casts (§3.4.5), that compatibility is an **unchecked** admission rather than a deferred check: a program admitted through `?` carries no runtime guard and no verification obligation recording the gap. Consumers must treat a result derived through `?` as unproven rather than as trusted.

**WILD-ASSUME (v0.14.73; extended v0.14.74).** A bare `?` does **not** satisfy a position whose type contributes a fact to a verification-condition antecedent that no obligation discharges. That class is now exactly `map[k,bool]`, whose declared value type is asserted as the ground fact `0 ≤ select(m$val,k) ≤ 1` per binder (§5.3.3, array class), and it is the one arm of the restriction that carries a soundness claim. **The `bytes[n]` arm is retained in whole as a diagnostic and no longer as a soundness claim.** With FACT-AG-LEN complete the length is earned at every bytes position: parameter into the effective pre, `(bytes-zero)` construction by the constructor axiom, return into the effective post (§5.3.3), so no `bytes[n]` position is in the class stated above. A bare `?` there is refused anyway, because it would otherwise surface as a refuted obligation or an unlocalized fallback instead of a type error naming the remedy, which is a worse message and not an unsound one; the rejection reads *a length the verifier must prove at this position*, where the `map[k,bool]` rejection reads *a per-key value range that the verifier asserts from the declaration*. **Two predicates back the restriction, and they answer different questions.** `admits` is the soundness set, exactly what the emitter injects unearned, now `map[k,bool]` alone, and it is what ADMIT-OVER's over-approximation invariant is stated about; `wildAssumeRejects` is the diagnostic set, `admits` disjoined with the bytes arm, and it is what the two checker seams read. Containment holds by construction rather than as an asserted property, since the second is defined from the first. The `map[k,bool]` arm stays in the class permanently (§5.3.3 gives the reason). That arm (v0.14.74) is a measured member of the same class with no reaching-SAFE witness: both the argument and return shapes crash on a sort mismatch before a verdict, so it closes a class member rather than refuting a demonstrated exploit. The restriction is **directional**: it applies where `?` is the *synthesized* type meeting such a declaration, at argument, return, and annotated-`let` positions alike. A `?` in the *expected* position is unaffected, because the absence of a declaration asserts nothing there is to falsify. Named holes are unaffected, so hole-directed checking (Check-Hole, above) and sketch mode are preserved; so are the polymorphic type variables of §13 builtins, whose absorption is how a calling context determines their components. Without the restriction, a value of one length satisfies a parameter of another and the parameter's asserted length discharges an obligation that does not hold — a `verified` verdict for an out-of-bounds index (SAFE-ARG, affected v0.14.34 through v0.14.72). Refinement aliases are deliberately outside the class: their type-level predicate is an *obligation on the producer* (§3.4.1), not an assumption, so a mismatched alias is refuted rather than believed. That exclusion covers the *predicate a refinement carries*, not the base type it wraps: membership is decided on the base, so a `where`-wrapped `bytes[n]` or `map[k,bool]` is inside the class exactly as its bare form is, and the wrapper does not exempt it (v0.14.74).

**Verification.** The judgment introduces no new proof obligation and no new channel: the only refinement obligation it routes is the existing §3.4.1 `p[e/x]`, classified per §5.3.3 (QF-LIA core / measure-class auto / non-`Σ_auto` → `erBodyFallback`, §3.4.5).

**Return position is surface-expressible.** This judgment supplies an expected type at the **return** position. The optional `-> RetType` annotation (§4.1, §12) makes the def-body return position an instance of this judgment. A bare-hole body under a declared return is the Check-Hole rule above — it records `HoleTyped RetType` (the `expected_return_type` value path, §11.2); a concrete body is Check-by-Synth against `RetType`; a refinement-aliased return is the `⇐-Refine` instance, joining the §3.4.1 introduction obligation and **discharging** it: the predicate folds into the effective post (`augmentContractPost`), so the body-VC proves it and it is exported as a caller-assumable guarantee (§3.4.5, §5.3.5).

---

## 4. Logic Structures & Design by Contract

### 4.1 Function Declarations (`def` and `def-shell`)

All LLMLL functions are **stateless**: they take inputs and return a value. They cannot mutate state or perform IO directly (IO-capable functions route their effects through `Command` values and the `def-main` shell — see §9).

Two declaration forms are available under the default grammar (`GrammarCoreInversion`):

| Keyword | AST node | Body restriction | Verification tier reachable |
|---------|----------|-----------------|----------------------------|
| `def` | `SDef` | Strict-core whitelist (QF-LIA arithmetic, `ELet`, `EIf`, n-arm sum `EMatch` [`Result` / admissible user ADT of any arity: single-payload or nullary arms, nested and sequential], scrutinee-constructor posts, admissible-sum constructor application, `EApp` to admitted callees — see §5.3.5) | `verified` (body-faithful SMT) |
| `def-shell` | `SDefShell` | None | `contract-checked`, `tested`, `asserted` |

**Syntax (both forms are identical):**

```lisp
(def function-name [param1: Type1 param2: Type2]
  (pre  boolean-expression)   ;; optional precondition
  (post boolean-expression)   ;; optional postcondition
  body-expression)             ;; the return value
```

```lisp
(def-shell function-name [param1: Type1 param2: Type2]
  (pre  boolean-expression)   ;; optional
  (post boolean-expression)   ;; optional
  body-expression)
```

**Optional return-type annotation.** Both forms accept an optional `-> RetType` immediately after the parameter brackets, before the contract clauses:

```lisp
(def withdraw [balance: int amount: PositiveInt] -> int
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  ?body_impl)
```

The annotation is **optional and checking-mode**, consistent with the synthesis-primary checker (§3.4.6): omit it and the return type is fully inferred (`mRet = Nothing`); declare it and the body is checked against `RetType`. A bare-hole body under a declared return records `HoleTyped RetType`, so a function-body hole reports its type in the checkout brief / obligation report (the `expected_return_type` field, §11.2). A concrete (non-hole) body is synthesized and unified against `RetType`, with a mismatch attributed to the function. A refinement-aliased return (`-> PositiveInt`) additionally joins the §3.4.1 introduction obligation `p[body/result]` to the body-VC set and discharges it: the predicate folds into the effective post via `augmentContractPost` (the guarantee-side dual of `augmentContractPre`), so the body-VC proves it (`verified` / `refuted` / `erBodyFallback` per §5.3.3) and it is exported as a caller-assumable guarantee (assume-guarantee; tier rides the §5.3.4 meet); see §3.4.5 and §5.3.5. See [`docs/archive/shipped-design-specs/def-return-annotation-proposal.md`](docs/archive/shipped-design-specs/def-return-annotation-proposal.md) for the design rationale. When the body discharging a refinement-aliased return is itself a two-arm `match` on a `Result`-typed parameter, the predicate discharges **per arm** — each arm re-establishes `p[result/x]` on its own result (clean → `verified`; a violating arm → `refuted`, localized to that arm) — at any nesting depth (under `let`/`if`), and this extends to a two-arm *user* ADT scrutinee with QF-LIA-scalar payloads, not only when the body *is* the match. A matched arm additionally **consumes its payload's own declared refinement**, made sound by a declaration-driven call-site payload-subtyping obligation that obligates callers to honor it. Payload-carrying construction over an admissible sum discharges as well: a constructed `(Ctor e)` reflects into the native datatype term and a construction/totality post discharges by constructor equality (§5.3.3 datatype class, §5.3.5); nullary-variant construction `(Empty)` types as its sum. A *recursive* (non-acyclic) sum is firewalled — its constructors are rejected at the strict-core gate (`def-shell` required) — and a constructor-dependent post over a non-admissible type stays a deliberate fallback.

**When to use `def` vs `def-shell`.** Use `def` when the function body is composed exclusively of linear arithmetic, `let` bindings, conditionals, pair operations, `Result` 2-arm matching, and calls to builtins or body-faithfully verified functions. The typechecker enforces this at compile time and emits `core-grammar-violation`, `core-membership-violation`, or `core-excluded-builtin` on non-admitted constructs. The last covers builtins that are `def-shell`-only by construction: every `wasi.*` effect and every `json-*` operation (§13.13). Its remedy is always to move the caller to `def-shell`, never to verify the callee, since a sealed builtin has no LLMLL body to verify. Use `def-shell` for everything else: functions that use lambdas (`fn`), call user-defined functions from the same module, perform IO via `wasi.*`, contain `?proof-required` holes, or are self-recursive.

**Complete `def` example:**

```lisp
(def withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  (- balance amount))
```

**Complete `def-shell` example:**

```lisp
(def-shell format-greeting [name: string count: int]
  (string-concat "Hello " (string-concat name (string-concat " x" (int-to-string count)))))
```

> **Legacy grammar.** `def-logic` is **removed** — it is rejected under **all** grammar modes (including `--grammar=legacy`) with a `removed-construct` diagnostic and no auto-rewrite. Use `def` for strict-core functions and `def-shell` for permissive functions. `--grammar=legacy` is retained only for `letrec` (the explicit-recursion form); `def` and `def-shell` are not available under `--grammar=legacy`. See [`docs/getting-started.md §4.25`](docs/getting-started.md) for the grammar-mode table and `LLMLL.md §12` for the EBNF.

### 4.2 Recursive Functions (`def-shell`)

Self-recursive functions are declared with `def-shell`. The self-call is a user-defined callee and fails the `def` callee-admissibility predicate (in `TypeCheck.hs`), so an *undischarged* recursion is outside the strict-core fragment. An optional `(decreases e₁ … eₖ)` termination-measure clause on `def-shell` (int-typed expressions over the parameters — `result` is not in scope, as in `pre`) supplies a termination measure. For a **single measure (k = 1)** the verifier discharges termination: it emits **well-foundedness** (`pre ⟹ e ≥ 0`) and, at each intra-cycle call site, **strict descent** (`pre ∧ path ⟹ e[args'] < e`) — QF-LIA, over the well-founded order `<` on ℕ. When every member of a recursive cycle (SCC) declares a discharging k = 1 measure and is body-faithful, the whole SCC is **descent-discharged**: its `termination_unverified` flag clears, its evidence upgrades from partial to **total** correctness, and it becomes **strict-core admissible** (a `def` may call it). A declared measure that does **not** strictly decrease is a hard verification failure, `measure-not-decreasing` — a verdict distinct from `refuted` (the *declared measure* is refuted, not the function's postcondition). On the CLI the failing constraints print as `decreases-condition … not verified` (well-foundedness) and `descent-condition … not verified` (strict descent); the name `measure-not-decreasing` appears as the trust-report drift stamp. Different measures on distinct cycle members are permitted (they share the ℕ order); the discharge is per-edge, so a terminating cycle whose decrease is distributed across edges rather than holding on each edge is conservatively rejected. A **lexicographic (k > 1)** clause discharges via the lexicographic order on ℕᵏ: the per-call-site descent is the QF-LIA disjunction `⋁ᵢ (e₁'=e₁ ∧ … ∧ e_{i-1}'=e_{i-1} ∧ eᵢ'<eᵢ)`, each component floored `eⱼ≥0` (so ℕᵏ is well-founded). Self-recursion and **equal-arity** mutual recursion discharge; a mutual SCC whose members declare tuples of **different lengths** is conservatively **refused** (stays partial) — the discharge gate requires uniform tuple arity across the whole SCC, because a mismatched-arity edge emits no descent constraint and must not be stamped total vacuously. A nonlinear or opaque-carrier measure component is untranslatable and leaves the SCC partial (never silently total). The measure is part of the total-correctness evidence: editing it invalidates the cached verdict.

```lisp
(def-shell countdown [n: int]
  (if (= n 0) 0 (countdown (- n 1))))
```

**Partial-correctness caveat.** Without a discharging measure, the verifier proves postconditions under the assumption the function terminates (see [`docs/design/verification-debate.md`](docs/design/verification-debate.md) Q4 "Where is totality enforced?"). A recursive `def-shell` with no `decreases` clause verifies body-faithful and can reach a `verified` post (assume-guarantee over the cycle, §0.1), but that verdict is partial-correctness only, and every member of the cycle carries an automatic `termination_unverified` flag (a per-entry marker plus a top-level `partial_fns` list, §4.4.4). The flag does **not** lower the postcondition tier — it is an orthogonal marker beside the display level (the `refuted` / `overflow_tainted` precedent) — so a consumer reads both "post: verified" and "termination unverified" and can gate accordingly. A discharging `(decreases …)` measure — single (k = 1) or lexicographic (k > 1, equal-arity across the SCC) — clears the flag and upgrades the cycle to total correctness (see the `def-shell` measure paragraph above); distributed-decrease, mixed-arity mutual, and non-QF-LIA measures remain partial.

**Mutual recursion** follows the same rule: all mutually recursive functions are `def-shell`.

> **Legacy grammar (`--grammar=legacy`).** The `letrec` form is available and provides an explicit `:decreases` termination measure that is checked for well-foundedness (`measure ≥ 0`) by `llmll verify`. Strict recursive descent is **not** encoded on the `letrec` path — the shipped `(decreases …)` discharge above is `def-shell`-only. The trust report flags `letrec`-derived `verified` claims as partial-correctness when the descent obligation is unfulfilled. Under the default `GrammarCoreInversion`, `letrec` is rejected with a `core-grammar-violation` diagnostic.

`pre`/`post` contracts on recursive `def-shell` functions behave identically to non-recursive ones (see §4.3–4.4).

### 4.3 The `result` Keyword in `post` Clauses

Inside a `post` clause, the identifier `result` is **automatically bound to the return value of the function body**. It is a compile error to use `result` anywhere else (including `pre` clauses, `let` bindings, or as a parameter name).

```lisp
(def double [x: int]
  (post (= result (* x 2)))  ;; `result` = the value returned by the body
  (+ x x))                   ;; body uses (+ x x); (* x 2) is nonlinear and not admitted in def bodies

;; ILLEGAL — result in pre:
(def bad [x: int]
  (pre (> result 0))   ;; COMPILE ERROR: result not in scope here
  x)
```

### 4.4 Contract Semantics

| Context | What happens on violation |
|---------|--------------------------|
| `pre` violation | `AssertionError` raised before body executes. The caller is buggy. |
| `post` violation | `AssertionError` raised before result is returned. The implementation is buggy. |
| Both satisfied | Result is returned normally. |

#### 4.4.1 Display Levels

Every `pre` and `post` clause carries a **display level** — a structured evidence record describing how the contract has been checked. Display levels form a partial-order diamond lattice, not a total order:

```
        verified
       /        \
contract-checked  tested
       \        /
       asserted
```

| Level | Meaning | When assigned |
|-------|---------|---------------|
| `verified` | Body-faithful SMT proof: the solver proved the function body satisfies the contract for all well-typed inputs. | `llmll verify` reports SAFE and the function's body VC was emitted |
| `contract-checked` | The solver proved contract consistency (pre ⇒ post is valid — holds for all models of the contract pair), but the function body was not encoded as a VC. | `llmll verify` reports SAFE for a fallback function (non-QF-LIA body, path-limit exceeded, or self-recursive `def-shell`) |
| `tested` | Not formally proven, but not falsified by property-based testing. Trust is proportional to sample coverage. | `llmll test` reports `pass` and the property body resolves to a singleton head-position contracted callee under the PBT-Lift rule in §4.4.5 (a unique `def` or `def-shell` reachable as an `EApp` operator inside `propBody` whose contract has a `post` clause). Multi-subject properties produce a diagnostic and no lift. Also assignable via `:trust tested` source annotation. |
| `asserted` | Enforced as a runtime assertion only. No static or dynamic evidence of correctness beyond the assertion itself. | Default for any contract not yet run through `verify` or `test` |

`contract-checked` and `tested` are **incomparable** — neither implies the other. Their meet (greatest lower bound) is `asserted`. This prevents a `tested`-only function from being silently treated as equivalent to a solver-checked function, or vice versa.

> [!NOTE]
> **Epistemic status distinction.** `contract-checked` provides **logical evidence** over the contract pair: the solver proved that the pre/post relationship is internally consistent, independent of the function body. It cannot be falsified by a counterexample (though the body may still violate it). `tested` provides **statistical evidence** over a random sample of size N (default 100): the property was not falsified, but may fail on the N+1th input. These are categorically different kinds of evidence and should not be treated as interchangeable trust signals.

> [!NOTE]
> **Design divergence from Liquid Haskell.** LLMLL admits a statistical evidence channel (`tested`) into the trust-report partial order. This is a deliberate departure from Liquid Haskell (Vazou et al., *Refinement Types for Haskell*, POPL 2014), which restricts its refinement-display to logical evidence only. The rationale is that AI-agent-emitted code is often outside the QF-LIA fragment that admits liquid-fixpoint discharge, and an empirical channel — explicitly statistical, per the epistemic-status note above — gives the trust report something to surface for that majority. The diamond lattice's incomparability between `contract-checked` and `tested` prevents agents or readers from silently treating statistical evidence as logical (their meet is `asserted`, not either of them).

The display level is recorded per-clause in an `EvidenceRecord` that also carries a `body-faithful` flag and an optional `:source` provenance annotation. Display levels are stored per-function in the module's exported metadata (see §8 — `ModuleEnv` extensions).

> The `verified` and `contract-checked` levels carry a prover tag (e.g., `verified (liquid-fixpoint)`). This tag appears in `.verified.json` sidecars and `--trust-report` output but does not affect the surface grammar. The `(trust ...)` declaration accepts four keywords: `verified`, `contract-checked`, `tested`, `asserted`. For details on how body-faithfulness distinguishes `verified` from `contract-checked`, see §5.3.4.

> **`refuted` — an orthogonal trust status.** A body-faithful function whose body VC the solver reports UNSAFE is *disproved*, not merely *unproven*: it is reported as `refuted`, distinct from `asserted`. `refuted` is **not** a `DisplayLevel` lattice element. The diamond (`DLVerified > DLContractChecked ∥ DLTested > DLAsserted`) ranks *strength of positive evidence*; refutation is *negative* evidence (a counterexample), off that axis — modelling it as a ⊥ below `DLAsserted` would conflate the evidence-strength axis with the polarity axis and force changes to `evidenceMeet` / `evidenceCovers`. It is instead an orthogonal marker beside the display level, following the `erBodyFaithful` / `erOverflowTainted` precedent, leaving the diamond and the meet untouched. `refuted` is a **verify-time status, not persisted evidence**: a refuted function writes no `.verified.json` entry, so a solver-less `--trust-report` render shows the function as `asserted` (an explicit "not verified"), with the stronger refuted information available only when the solver runs. It surfaces in `--trust-report` as a per-entry `refuted` flag and a top-level `refuted_fns` list, and in the obligation report as a `refuted` obligation carrying the solver counterexample's JSON pointer. A caller of a refuted callee is flagged `depends-on-refuted` via the epistemic-drift channel (§5.3.5) at the strongest severity — its assume-guarantee proof rests on a postcondition known to be false.

#### 4.4.2 Runtime Assertion Modes

The `--contracts` flag controls which runtime assertions are compiled into the output:

| Mode | Assertions included | Default for |
|------|---------------------|-------------|
| `--contracts=full` | All contracts (verified + contract-checked + tested + asserted) | `llmll test` |
| `--contracts=unproven` | Only non-verified contracts; `verified` body-faithful postconditions are stripped | `llmll build` (when a cached verify result exists) |
| `--contracts=none` | No runtime assertions | Opt-in only; requires explicit flag |

Without a prior `llmll verify` pass, `llmll build` defaults to `--contracts=full`. The `--contracts` flag applies to Haskell code generation regardless of `--emit-only`.

> [!IMPORTANT]
> **Invariant:** Stripping a `verified` contract must not change observable behavior for any well-typed program. This invariant depends on `.fq` emitter faithfulness — see the [faithfulness invariant in FixpointEmit.hs](compiler/src/LLMLL/FixpointEmit.hs) and the [design spec for this invariant](docs/archive/shipped-design-specs/body-vc-0-spec.md).

#### 4.4.3 Trust-Level Propagation

When module B imports module A and calls a function whose contract is `tested` or `asserted`, the compiler emits a **downstream trust warning**:

```
⚠ Function foo.bar.withdraw has an unproven postcondition.
  Your module inherits this trust gap.
```

The downstream module can acknowledge the gap explicitly:

<!-- ci:roundtrip -->
```lisp
(trust foo.bar.withdraw :level asserted)
(trust auth.verify-token :level tested)
```

This silences the warning and makes the trust decision visible in source. An agent auditing module B can enumerate all `(trust ...)` declarations to see which unproven contracts it depends on.

`(trust ...)` declarations are per-function, allow multiple declarations per module, and are collected regardless of position (the parser enforces no ordering relative to `def`/`def-shell` — the same as `import`). Duplicate declarations for the same function are idempotent (not an error).

When the sidecar `.verified.json` file is missing for an imported module, all contracts default to `asserted`.

#### 4.4.4 Trust Report (`--trust-report`)

`llmll verify --trust-report` prints a per-function trust summary after verification. For each function with contracts, the report shows:

- The function's own verification level (verified/contract-checked/tested/asserted) for pre and post clauses
- Which cross-module functions it calls and their verification levels
- **Epistemic drift warnings:** when a `verified` conclusion depends transitively on an `asserted` or `tested` assumption upstream



```bash
stack exec llmll -- verify program.llmll --trust-report
# Trust Report
# ────────────────────────────────────────────────────────────
#   withdraw:
#     pre: asserted  |  post: verified (liquid-fixpoint)
#     ↳ calls safe-subtract (pre: asserted, post: verified (liquid-fixpoint))
```

Use `--trust-report --json` for machine-readable JSON output suitable for CI or downstream tooling. The JSON emit carries a `trust_report_version` field plus a six-Int `tier_profile` aggregate `{verified, proved, contract_checked, tested, asserted, no_contract}` over per-function effective tier classifications, intended for downstream tooling that needs a fixed-arity summary without scalarizing the diamond lattice — see [`docs/llmll-trust-report.schema.json`](docs/llmll-trust-report.schema.json) for the full shape.

**`termination_unverified` — the partiality marker.** Every function in a recursive call-graph cycle (a cyclic SCC over the whole-program call graph, entry plus cached modules) carries a per-entry `termination_unverified: true` flag, and the report gains a top-level `partial_fns` list of these names. Like `refuted` / `overflow_tainted`, it is an **orthogonal informational marker**, not a `DisplayLevel` element: it is **derived at report-build time** from the call graph — never persisted to the sidecar — so it is present even on a solver-less `--trust-report` render (unlike `refuted_fns`, which is verify-time only). It does not feed `evidenceMeet`, the effective level, `refutedClosure`, or strict-core admission; a recursive `def-shell` keeps whatever tier its body VC earned (typically `verified` post at partial correctness) and simply carries the flag. It marks that termination is unverified for the cycle, per the §4.2 partial-correctness caveat; REC-DESCENT (strict descent) would discharge it. `termination_unverified` arrived at `trust_report_version` `1.5.0`.

**`unvouched_cdp_meet` — the decomposition-trust meet.** Under `--cdp`, each function's `discriminative_axis` carries `unvouched_cdp_meet`: the lattice meet (weakest) of contract-discriminative-power scores over the function's *unvouched* transitive-callee subtree (subtree contracts with a present `pre`/`post` clause lacking a `:source` anchor), scoring the quality of an invented `refine` decomposition — a cascade with one hollow invented sub-contract reads weak even when every node is `verified`. It is two-axis: a `quality_meet` (`hollow ⊏ scored ⊏ strong`, `null` when no member is measured, kept distinct from hollow) plus a `coverage` object exposing the measured/unmeasured split and the `:source`-anchored members excluded from the meet (`excluded_fns`, so a forged `:source` exclusion of a hollow spawn is visible). A contract-only cyclic-SCC member sets `floored_by_cycle` without collapsing the quality meet. Like `refuted` / `termination_unverified` it is an **orthogonal report-only marker**: it does not feed `evidenceMeet`, the effective level, or strict-core admission. A cooperative-author diagnostic — adversarial `:source`-forgery is caught by R5, not this signal. `unvouched_cdp_meet` is an additive `discriminative_axis` field: it grew within the `trust_report_version` 1.x major without a bump, and first emits under `1.5.0`.

**Tier-profile pre/post split.** The trust-report JSON carries two top-level fields parallel to `tier_profile`: `tier_profile_pre` and `tier_profile_post`. Each classifies functions by their per-clause effective level (the clause's own evidence record meeting the transitive-callee effective level), rather than by the per-function meet of pre and post. A function with `pre = asserted` and `post = tested n` increments `tier_profile_pre.asserted` and `tier_profile_post.tested`, where the scalar `tier_profile.asserted` collapses both clauses via the diamond meet at §4.4.1. Downstream tooling that needs the post-side empirical signal (the R6d harness `Cred(R)` predicate is the canonical consumer) reads `tier_profile_post`.

**Sidecar invariant change.** The `.verified.json` sidecar for a source file `S` may carry entries keyed by **qualified imported names** (e.g., `lib.f`) when a `(check ...)` block in `S` lifted the contract of an imported function `f` from module `lib`. This extends the prior invariant that sidecars were keyed by locally-defined names only. Downstream consumers must accept qualified keys; the trust-report's `collectAllContractStatus` build path already merges by qualified name across the module cache (in `TrustReport.hs`), so the change is read-side compatible. The sidecar-write target for a PBT-lifted entry is the source file's sidecar (where the `(check)` lives), not the imported module's sidecar.

**`pbt_witnesses` provenance and staleness.** Each PBT-derived `tested` evidence record in `.verified.json` carries a `pbt_witnesses` list of `[{hash, description}]` entries, where `hash` is `sha256:` + 64 hex chars over a canonical s-expression serialization of `propBody`. On read, `buildTrustReport` validates each record's witnesses against the set of live property-body hashes (entry module + every cached imported module); records whose witness list is non-empty and disjoint from the live set are downgraded to `asserted` with a per-clause diagnostic in `--trust-report`. Editing a property body invalidates the cached `tested` evidence (next `llmll test` re-lifts with fresh hashes); deleting the property removes the lift entirely. This composes with the existing `ctVerifiedHash` staleness guard for imported-sidecar drift.

The report walks the full module cache (entry-point module plus all imported modules) and computes the transitive trust closure. An agent auditing a module can use the trust report to identify all points where the formal verification chain breaks down.

#### 4.4.5 PBT-Derived Trust Evidence

The `tested` display level can be assigned to a function's post clause from either (a) a source-annotated `(trust f :level tested)` declaration, or (b) a passing `(check ...)` block under the lift rule below. The lift rule, formalised:

```
              (SCheck p) ∈ Σ
              status(p) = PBTPassed
              evaluatedSamples(p) = n
              HEAD-contracted(propBody p, Σ) = {f}     (singleton)
              f ∈ contractedNames(Σ ∪ importedExposed(Σ))
              contractPost(f) = Just _
              body(f) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) }
              hash(propBody p) = h
            ─────────────────────────────────────────────────────       (PBT-Lift)
            csPost(f) ⊑  DLTested n   with  pbt_witnesses ∋ {h, desc(p)}
```

where `contractedNames(Σ)` is the set of names bound by any contracted statement form in `Σ`: `SDefLogic`, `SLetrec`, `SDef`, and `SDefShell`. This matches the `contractByName` union in `PBT.hs`. `⊑` denotes lattice-respecting monotonic upgrade: the lift applies only when `csPost.erDisplayLevel` is currently `DLAsserted`. Pre-existing `DLTested`, `DLContractChecked`, or `DLVerified` entries are preserved by the `evidenceCovers` rule at §4.4.1.

**Side conditions.**

1. **Subject scoping.** `f` may be a name local to the source file or a name imported via `(open path …)` and resolved through the assembled test statement list (`compiler/src/LLMLL/PBT.hs` `assembleTestStatements`). Imported subjects are keyed in the local sidecar under their qualified name `lib.f` per the sidecar invariant at §4.4.4.
2. **Multi-subject suppression (default path).** Properties whose head-position set contains two or more contracted callees, *without* explicit `:subject` / `:subjects` metadata, do not lift any of them; the property is reported as an informational diagnostic from `llmll test` ("property covers multiple contracted callees; no trust evidence recorded"). The explicit-attribution route is `:subject` / `:subjects` metadata; see the **Annotated-subject branch** below.
3. **Skip and fail suppress the lift.** `PBTSkipped` (static-evaluator bottoms, QuickCheck-discard saturation) contributes zero evidence per §5.1's outcome table. `PBTFailed` runs are surfaced as user-facing diagnostics but record no `pbt_witnesses` and do not retract any prior `DLTested` evidence.
4. **`PBTError` is treated as `PBTSkipped` for write-back.** Exceptions during QuickCheck propagate as user-facing diagnostics; the trust-report channel ignores them.
5. **Interface laws do not lift contracted-callee posts.** Properties extracted from `def-interface :laws` are parametric over implementations, not concrete evidence for contracted callees (`def` or `def-shell` form) invoked in the law body; they live on a distinct trust channel.
6. **Lift targets `csPost` only.** Preconditions are caller-side obligations whose evidence channel is the call-site VC at §5.3.4. Lifting `csPre` from PBT would conflate two evidence channels and produce false trust; the lift rule above is therefore strictly asymmetric.
7. **Delegation-body suppression.** When `body(f) ∈ { EHole(HDelegate _), EHole(HDelegateAsync _) }`, the lift is suppressed unconditionally regardless of whether the pre clause is evaluable by the static evaluator. `processRun` in `PBT.hs` returns `(Map.empty, [d])` with an informational diagnostic; `csPost(f)` remains at its current display level (typically `DLAsserted`). The rationale: `evalExprStaticWith` on `EHole(HDelegate _)` cannot execute the function body — it observes only the `on-failure` fallback path if present, or bottoms otherwise. Any `PBTPassed` result on an evaluable pre clause reflects the property's pre-condition exercise only; it carries no evidence about the actual postcondition. The grammar distinction (`def` vs. `def-shell`) is irrelevant pre-resolution. In PBT-Lift-Annotated, suppression is per-subject: `fᵢ` with a delegation body is excluded from the conclusion range; other subjects in the `:subjects` list still lift. See `delegateBodies` in `PBT.hs`; §5.3.5.

**Precondition-guarded samples.** Property evaluation ranges over precondition-satisfying samples only. A sample that violates a callee precondition — the `map-has` presence requirement of `map-get`, or the `0 ≤ i < n` bound of `bytes-get` (§13.12) — is *discarded*, contributing to neither the pass count nor a falsification, exactly as a `==>`-guarded QuickCheck case does. `tested` evidence therefore quantifies over the precondition-satisfying subset, consistent with the epistemic-status note at §4.4.4; a static evaluator that fabricated a value for an out-of-precondition read would mint `tested` evidence the tier definition (§4.4.4) excludes.

**Multi-property accumulation.** When multiple `(check ...)` blocks lift the same `f` (each singleton on `f`, each `PBTPassed`):

```
n_total(f)       = max  { evaluatedSamples(p) | p covers f, status(p) = PBTPassed }
pbt_witnesses(f) =   ⋃  {     hash(p), desc(p) | p covers f, status(p) = PBTPassed }
```

`max` is the **within-channel join**: independent passing properties each constitute a witness; the strongest single witness dominates. This is distinct from `evidenceMeet` at §4.4.1, which uses `min` on `(DLTested, DLTested)` pairs by design — that operation is the GLB across pre/post of a single function, not the join across independent properties on the same clause.

The compiler implementation, including the within-channel join and the sidecar staleness mechanic, lives at `compiler/src/LLMLL/PBT.hs` (`pbtTrustWriteback`, `mergePbtWriteback`, `canonicalPropBodyHash`).

**Annotated-subject branch.** When a `(check ...)` block carries explicit subject metadata — sexp `(check "d" :subject f (for-all …))` (singleton sugar) or `(check "d" :subjects [f₁ … fₖ] (for-all …))` (joint form), JSON-AST `CheckDecl.subjects: [...]` — the head-position scan is bypassed entirely and the lift rule fires per declared subject:

```
              (SCheck p) ∈ Σ
              status(p) = PBTPassed
              evaluatedSamples(p) = n
              subjects(p) = [f₁ … fₖ]                  (non-empty)
              fᵢ ∈ contractedNames(Σ ∪ importedExposed(Σ))              for each i
              contractPost(fᵢ) = Just _                                  for each i in lifted
              body(fᵢ) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) } for each i in lifted
              hash(propBody p) = h
            ──────────────────────────────────────────────────────  (PBT-Lift-Annotated)
            csPost(fᵢ) ⊑  DLTested n     with shared pbt_witnesses ∋ {h, desc(p)}
                          for each fᵢ with contractPost(fᵢ) = Just _
                              and body(fᵢ) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) }
```

Subjects declared in `:subjects` but lacking a `post` clause are skipped with an informational diagnostic (the S3 case from `processRun`); the remaining annotated subjects still lift. Duplicate names are deduped (`:subjects [f f]` produces one record per `f`). Empty `:subjects []` is rejected at parse time (S6). The shared `pbt_witnesses` hash across all per-subject records of one property is the canonical-body-hash invariant from the PBT-Lift rule above; consumers can detect joint provenance by inspection of the shared hash. Cross-module subjects key under their qualified path via the existing `qualMap` (the S8 case), preserving the §4.4.4 sidecar invariant.

The annotated branch is the language's explicit-attribution route for **metamorphic-relation properties** (Hughes 2020 *How to Specify It! A Guide to Specifying Properties*, §3 — a single property over a structural relation across multiple callees, where joint evidence is the agent's intent). LLMLL does not adopt `eqc_statem`-style command sequences ("state-machine properties" in the QuickCheck literature); `:subjects` is per-property explicit attribution at a single point, not a state machine.

**Pacheco-Lahiri-Ernst overallocation discipline.** The unannotated multi-callee diagnostic at side-condition 2 above continues to refuse implicit lift; the `:subjects` metadata is the agent's explicit consent to joint-evidence allocation across the declared callees. The schema-cost trade was deliberate: the additive optional `subjects: [Name]` AST field is a minor bump (`schemaVersion 0.4.0 → 0.5.0`); a conjoint-record alternative (`DLJointTested [Name] n` or a `subjects: [Name]` field on `DLTested`) would have required `trust_report_version 1.2.0`, coupling downstream tooling (notably the repair-loop harness's `Cred(R)` consumer) with a trust-report schema change at Phase 3 launch.

#### 4.4.6 Contract Discriminative Power (CDP)

The diamond-lattice evidence axis at §4.4.1 answers one question: *do we know this implementation satisfies the specification?* A second, orthogonal question — *does the specification rule out enough wrong implementations?* — is the **contract-discriminative-power (CDP)** axis. A function can simultaneously be `verified` (high evidence) and `0.18` DP (weak spec, admits most observable behaviors); the pair makes this visible without collapsing to a scalar.

**Score.** Shannon-normalized over a closed observation set `Ω`,

```
DP_Ω(S) = 1 − log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)
```

where `B_{T,U,Ω}` is the finite set of observable behaviors of functions `T → U` over candidate set `Ω`, and `⟦S⟧_Ω = { b ∈ B | b satisfies contract S }`. `DP = 0` when the contract admits every observable behavior; `DP = 1` when it admits exactly one. A zero-satisfying result (`|⟦S⟧_Ω| = 0`) is not reported as score 0 — it splits into two typed states, since `Ω` cannot itself distinguish a genuinely vacuous contract from one that is merely tight for this candidate set: `spec-too-tight-for-omega` when the post carries independent verification evidence (a strong-spec signal), or `spec-inconsistent-or-unproven` otherwise — an epistemic, not semantic, label, since no solver-UNSAT-on-`pre ∧ post` check independent of `Ω` exists in this DP score — though the `refine` feasibility gate (`LLMLL.Feasibility`, §11 refine op) does realize an `Ω`-independent semantic infeasibility check, `∃input. pre ∧ ∀result. ¬post`, for spawned sub-contracts (cf. the vacuity/coverage distinction in Chockler, Kupferman & Vardi, *Coverage Metrics for Formal Verification*, FMSD 2006, alongside DeMillo, Lipton & Sayward's original mutation-adequacy framing, *Hints on Test Data Selection*, IEEE Computer 1978). A candidate whose own trivial body falls outside the body-VC-translatable fragment (§5.3.3) is excluded from measurement entirely — `body-unfaithful-candidates-excluded` — rather than counted either way.

**Observational, not semantic.** The score is meaningful relative to `Ω` only — two implementations that disagree semantically but agree on every input in `Ω` collapse to one observed behavior. Cross-function and cross-version score comparison requires same-`Ω` discipline; the `basis` field in the trust-report `discriminative_axis` block records `Ω`'s identity for auditability. Consumers setting CI gates on CDP scores must respect this distinction or risk gating on the wrong reading. See [`docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md`](docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) §1 Rev 2.

**`(spec-entropy …)` annotation.** Three values per contracted `def` / `def-shell` function (under `--grammar=core-inversion`); `def-shell` functions receive `WarnDefShellOutOfScope` under `--cdp` and are not scored:

```lisp
;; Requires --grammar=core-inversion. def-shell functions are out of CDP scope under --cdp (only def is scored).
(def transfer [from: AccountId to: AccountId amount: PositiveInt]
  (pre  (>= (balance-of from) amount))
  (post (and (= (balance-of from) (- (old (balance-of from)) amount))
             (= (balance-of to)   (+ (old (balance-of to))   amount))))
  ;; (spec-entropy :strict)  — default; can be elided
  ...)

(def cache-lookup [k: Key]
  (post (or (is-ok result) (is-error result)))
  (spec-entropy :intentional)
  ...)
```

- **`:strict`** (default; can be elided) — low DP raises a diagnostic via `--cdp` / `--weakness-check`.
- **`:intentional`** — low DP is the design (caches admit any eviction; schedulers admit any ready thread; hash-map iteration order is unspecified). The annotation is the agent's explicit declaration; CDP is still computed and reported, but the diagnostic is suppressed. Self-attestation discipline: agents may over-annotate to silence warnings, so the trust report surfaces the annotation in `spec_entropy_annotation` and a module-level `over-annotation-warning` fires when the ratio of `:intentional` contracts exceeds 30% (configurable later). This ratio is an *abuse-rate* check, not a *per-instance* one: a single `:intentional` annotation in a module of four or more contracted functions stays below the threshold and raises no automated warning by design, because `:intentional` is a self-attestation channel with no independent oracle — per-instance justification is a human-review concern (as with Liquid Haskell's `{-@ assume @-}` and Rust's `#[allow(...)]`, both audited by rate, not per site). Under `--trust-report --json`, the top-level `over_annotation` object (`ratio`, `threshold`, `warning`) is populated whenever a trust report is built, independent of which flag (`--cdp`, `--weakness-check`, `--strict-verify`) requested it; together with each function's own `discriminative_axis` score and `spec_entropy_annotation`, it lets an external policy gate per instance — not only per module ratio — more strictly than the built-in threshold.
- **`:unknown`** — CDP is computed and reported but does not raise. For spec-development workflows where the contract is in flux.

**CLI.** `llmll verify <file> --cdp` runs the closed candidate-set sweep per §4.3.1 of the proposal after the SAFE result and emits one `discriminative_axis` block per contracted function. Combined with `--trust-report --json`, the score is paired with the diamond-lattice evidence level in the trust-report JSON (the `discriminative_axis` block arrived at `trust_report_version` `1.2.0`, additive; existing consumers ignore it).

**Scope.** `--cdp` scores only `def`-form (`SDef`) functions regardless of grammar mode. `def-shell` functions appear in the trust-report `discriminative_axis` block with `"score": null` and `"warnings": ["def-shell-out-of-scope"]`; the result map is uniform — every contracted function has an entry. `CDPScopeAllDefLogic` is available in the compiler for testing contexts but is not exposed via a CLI flag. See [`docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md §2`](docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) for the scope-selection rationale.

### 4.5 Suppression Governance (`weakness-ok`)

When a function is intentionally left without contracts (e.g., pure rendering logic, FFI wrappers, or configuration constants), the `weakness-ok` declaration acknowledges the gap and prevents the spec coverage gate from flagging it as unspecified:

```lisp
(weakness-ok render-board "pure string rendering — no meaningful postcondition")
(weakness-ok cache-evict "eviction policy is unspecified by design")
```

**Syntax:** `(weakness-ok fn-name "reason")`. Both arguments are required — the parser rejects bare `weakness-ok` without a reason string.

**Governance rules:**

| Code | Behavior |
|------|----------|
| `W601` | `weakness-ok` target doesn't match any function in the module → warning |
| `W602` | Function has contracts AND `weakness-ok` → contracts take priority; `weakness-ok` is redundant (warning) |
| `W603` | More than 50% of functions are suppressed → warning (bulk suppression guardrail) |

`weakness-ok` functions count toward `effective_coverage` (see §5.4) but are visually distinguished with a `⊘` marker in `--spec-coverage` output.

JSON-AST equivalent: `{"kind": "weakness-ok", "name": "render-board", "reason": "pure string rendering"}`.

### 4.6 Clause-Level Provenance (`:source`)

In LLMLL's target domains (financial compliance, protocol implementation, cryptographic standards), auditors require per-clause traceability to the originating standard. The `:source` annotation provides free-form provenance metadata on `pre` and `post` clauses:

```lisp
(def-shell transfer [from: string to: string amount: int]
  (pre (>= amount 0)
    :source "ERC-20 §transfer — amount must be non-negative")
  (post (= (total-supply result) (total-supply state))
    :source "ERC-20 §transfer — conservation invariant")
  ?transfer-impl)
```

**Semantics:** Pure metadata — no effect on type checking, verification, or codegen. The `:source` string is stored per-clause (`contractPreSource` / `contractPostSource`) and threaded through `--trust-report` output and `.verified.json` sidecars.

**Backward compatible:** Omitting `:source` yields `Nothing` — all existing programs parse and compile unchanged.

**Multiple clauses (SRC-CONJ-1):** A contract side may be authored as several `(pre ...)` or `(post ...)` clauses, each carrying its own `:source`. The effective predicate is the left `and`-fold of the clauses in author order; every clause keeps its citation (`contractPreClauses` / `contractPostClauses`). The trust report surfaces them as `pre_sources` / `post_sources` arrays (author order); `.verified.json` evidence records carry them as `sources`. For the decomposition-trust vouched predicate (§4.4), a multi-clause side is vouched only when **every** clause carries `:source`.

JSON-AST fields: `"pre_source"` / `"post_source"` (optional string, single-clause shape) or `"pre_clauses"` / `"post_clauses"` (arrays of `{"expr", "source"?}` for 2+ clauses; mutually exclusive with the scalar shape; a one-element array normalizes to it; `schemaVersion` 0.9.0).



---

## 5. Native Testing & Verification

### 5.1 Property-Based Testing (`check`)

`check` blocks declare universal properties. The test runner generates randomized edge-case inputs and attempts to falsify the property. A `check` block must contain exactly one `(for-all ...)` — bare boolean expressions are not valid.

```lisp
(check "Addition is commutative"
  (for-all [a: int b: int]
    (= (+ a b) (+ b a))))

(check "Withdraw never produces negative balance"
  (for-all [b: int a: PositiveInt]
    (if (>= b a)
        (>= (withdraw b a) 0)
        true)))
```

The test runner generates at least 100 random samples per `check`. For primitive types it targets edge cases: `0`, `-1`, `MAX_INT`, `MIN_INT`, `""`, `[]`.

**Property outcomes.** Each `check` block reports one of three statuses:

| Status | When | Trust contribution |
|--------|------|--------------------|
| `pass` | All samples evaluated to `true` | `tested` evidence on the singleton head-position contracted callee's post clause per the PBT-Lift rule in §4.4.5 (multi-subject properties produce a diagnostic and no lift). Persisted in `.verified.json` with a `pbt_witnesses` hash for staleness invalidation. |
| `fail` | At least one sample evaluated to `false`; counterexample reported | None — verification gate fails |
| `skip` | Property body could not reduce to a literal Bool on every sample (e.g., body calls `?delegate` without `on-failure`, or calls runtime-only operations like `wasi.io.stdout`) | None — does not contribute trust evidence |

A `skip` is **not** a `pass`. Property bodies that reach unevaluable terms (`?delegate` without fallback, `?proof-required` postcondition references, command constructors, `await`) are reported `skip` and contribute zero trust evidence. Static-evaluator coverage is documented at `compiler/src/LLMLL/Contracts.hs` `evalExprStaticWith` and `compiler/src/LLMLL/PBT.hs` `runPropertyWith`.

#### 5.1.1 `evaluatedSamples` Semantics

`DLTested n` records that `n` property-body evaluations reduced to `True`, with no evaluation reducing to `False`. This is a **lower bound on assertions of the postcondition**: under an implication-shape property `(if pre then post else true)`, samples for which `pre` fails count as `True` evaluations vacuously. A coverage-instrumented count distinguishing genuine postcondition witnesses from vacuous evaluations is a possible follow-on; `n` counts evaluations, not genuine exercises of the postcondition. The static-evaluator path always reports `n = 100`; the QuickCheck fallback path reports the non-discarded evaluation count from `Result.Success.numTests`.

### 5.2 Generators for Refinement Types (`gen`)

When a `for-all` binds a variable of a refinement type (e.g., `Letter`), the test engine must generate values that satisfy the type's `where` predicate. The default strategy is **rejection sampling**: generate a value of the base type, check the predicate, discard and retry if it fails. This terminates when 100 valid samples are accumulated, or reports a generation failure after 10,000 attempts.

For types where rejection sampling is inefficient (e.g., a 64-hex-digit string), register a custom **generator** with `gen`:

```lisp
;; Custom generator: produce random 1-character ASCII strings
(gen Letter
  (string-char-at "abcdefghijklmnopqrstuvwxyz"
                  (mod (random-int) 26)))

;; Custom generator: produce valid block IDs
(gen BlockID
  (hex-encode (random-bytes 32)))
```

A `gen` declaration applies to all `for-all` blocks in the same module that use the named type. If no `gen` is declared for a refinement type, rejection sampling is used automatically.

> **Illustrative, not currently runnable.** `string-char-at` is a real, codegen-backed builtin, but `random-int`, `hex-encode`, and `random-bytes` are not: none of the three exists anywhere in the compiler. `random-int` was removed at v0.14.81 (R-13), having carried a `trustedPrelude` core-membership entry and an orphaned codegen stub (always returned `42`) without a `builtinEnv` declaration, so a call to it passed core-membership on the strength of the allowlist entry and was then rejected as an unknown function before codegen was reached. These examples show the intended `gen` declaration syntax and are reserved names for future random-generation builtins, not code you can build today.

### 5.3 Verification

**`llmll verify`** is the compile-time verification command. It:

1. Walks the typed AST and emits a `.fq` constraint file for `liquid-fixpoint`.
2. Runs `fixpoint` (+ Z3) as a standalone binary — no GHC plugin required.
3. Reports SAFE or constraint-violation diagnostics with RFC 6901 JSON Pointers back to the original `pre`/`post` clause.

**Coverage:** Quantifier-free linear integer arithmetic (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`). Non-linear predicates and complex `letrec` termination measures are skipped (see `?proof-required` in §6).

**Qualifier strategy:** Qualifiers are auto-synthesized from `pre`/`post` predicates and seeded with the built-in set `{True, GEZ, GTZ, EqZ, Eq, GE, GT}`. No manual qualifier declarations are needed.

```bash
stack exec llmll -- verify ../examples/withdraw.llmll
# ✅ ../examples/withdraw.llmll — SAFE (liquid-fixpoint)
```


#### 5.3.1 Spec Weakness Detection

`llmll verify --weakness-check` is an advisory pass that runs **after** a SAFE verification result. For each contracted function, the compiler constructs trivial candidate bodies (identity, constant-zero, empty-string, `true`, empty-list) and checks whether they also satisfy the contract. If any trivial body passes, a `spec-weakness` diagnostic is emitted:

```
⚠ Spec weakness detected for `sort-list`:
  Your contract: (post (= (list-length result) (list-length input)))
  Trivial valid implementation: (def-shell sort-list [input: list[int]] input)
  Consider strengthening the postcondition.
```

This diagnostic is **non-blocking**: the function remains SAFE. It is an *advisory* signal that the specification may not distinguish correct implementations from trivial ones. The structured JSON diagnostic includes `trivial_implementation` and `suggested_postcondition` fields.

Weakness checking does not modify `FixpointEmit.hs` — it constructs synthetic single-statement programs and calls the existing `emitFixpoint` pipeline.

**CDP extends the trivial-body enumeration to a counted divergence metric.** Where legacy `--weakness-check` reports a binary "any trivial body passes?" diagnostic over the five-enumerator catalog, `llmll verify --cdp` extends the same per-candidate `emitFixpoint` + solver loop to count: `|{candidates that satisfy S}| / |{type-compatible candidates}|`, normalized as `DP_Ω(S) = 1 − log|⟦S⟧_Ω| / log|B_{T,U,Ω}|`. The candidate set is closed at [`docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md`](docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) §4.3.1 (identity over each param + small ints `{0, 1, -1, 42}` + both bools + `{"", "a"}` + list-empty / list-singleton + `Success`-default / `Error "default"` + pair-of-defaults); the score is reported with provenance in the trust-report `discriminative_axis` block. Legacy `--weakness-check` keeps the 5-enumerator catalog and the binary diagnostic surface unchanged; the two flags are orthogonal. See §4.4.6 for the evidence-axis framing and the observational-vs-semantic caveat that bounds what the score claims.

#### 5.3.2 Spec Coverage Gate

`llmll verify --spec-coverage` classifies every function in a module and computes the **effective specification coverage**:

```
effective_coverage = (contracted + suppressed) / total_functions
```

| Classification | Meaning |
|---|---|
| **Contracted** | Has at least one `pre` or `post` clause |
| **Suppressed** | Has a `(weakness-ok name "reason")` declaration and no contracts |
| **Unspecified** | No contract, no suppression |

> [!NOTE]
> **Suppression accounting rationale.** `effective_coverage` includes suppressed
> functions because a documented `(weakness-ok "reason")` represents an explicit
> engineering decision — the team has reviewed the function and determined that a
> contract is not required at this time. This is qualitatively different from an
> un-reviewed function with no contract.
>
> However, suppression is not specification. The D10 warning (>50% suppressed)
> guards against gaming. For governance reporting, `suppression_debt`
> (= suppressed / total) is reported alongside `effective_coverage` for governance visibility.

Example output:

```bash
stack exec llmll -- verify program.llmll --spec-coverage
# Spec Coverage Report
# ────────────────────────────────────────────
#   Functions with contracts:     4 / 7   (57%)
#     Proven:                     2
#     Tested:                     1
#     Asserted:                   1
#   Intentional Underspecification:
#     ⊘ cache-evict — "eviction policy is unspecified by design"
#   Unspecified:                  2
#     sort-list, validate-input
# ────────────────────────────────────────────
#   Effective coverage: 71% (5/7)
```

Use `--spec-coverage --json` for machine-readable output:

```json
{
  "summary": {
    "contracted": 12,
    "suppressed": 5,
    "unspecified": 3,
    "total": 20,
    "proven": 4,
    "tested": 3,
    "asserted": 5,
    "effective_coverage": 0.85
  },
  "entries": ["..."],
  "laws": [],
  "warnings": []
}
```

The JSON output includes per-function `entries`, aggregate `summary`, interface `laws`, and governance `warnings`. Summary fields: `effective_coverage` (= (contracted + suppressed) / total), `spec_coverage` (= contracted / total, excluding suppressions), and `suppression_debt` (= suppressed / total).

**Division guard:** A module with 0 functions has `effective_coverage = 100%`.

**Governance guardrails:** See §4.5 for the `weakness-ok` warning rules (`W601`–`W603`).

#### 5.3.3 Verification Scope

The following table precisely defines what `llmll verify` can prove, what it tracks but cannot prove, and what is designed but not yet operational:

| Fragment | Status | Prover | What it covers |
|----------|--------|--------|----------------|
| **QF-LIA** (quantifier-free linear integer arithmetic) | **Shipped** | Z3 via liquid-fixpoint | `+`, `-`, `=`, `≠`, `<`, `<=`, `>=`, `>`, and the boolean connectives `and`/`or`/`not`, over `int`/`bool`. Handles numeric bounds, conservation invariants, length preservation. ~80% of practical contracts. |
| **Termination** (`(decreases …)` measures) | **Shipped** | liquid-fixpoint | A `(decreases e₁ … eₖ)` clause on a recursive `def-shell` discharges termination: **well-foundedness** (`pre ⟹ eᵢ ≥ 0`) plus **call-site strict descent** (`measure(args') < measure(args)` at each intra-cycle call site; lexicographic order on ℕᵏ for k > 1, equal-arity across the SCC). A discharged SCC upgrades from partial to **total** correctness and becomes strict-core admissible; a non-decreasing measure is the hard verdict `measure-not-decreasing` (§4.2). Nonlinear/opaque measure components leave the SCC partial. The legacy `letrec :decreases` path checks non-negativity only; complex legacy measures emit `?proof-required(complex-decreases)`. |
| **Property-based testing** | **Shipped** | QuickCheck | `check`/`for-all` blocks generate randomized inputs and attempt to falsify properties. Contracts verified this way are marked `tested`. |
| **Lean path** (nonlinear arithmetic / inductive properties) | **Experimental `--leanstral` demo shipped (v0.14.8); production deferred** | Lean 4 + Mathlib kernel, via `labs-leanstral-1-5` | An **opt-in, experimental** `--leanstral` path (v0.14.8) discharges a *faithfully-translatable* obligation — the demo class is **nonlinear integer arithmetic** (`n*n`, the QF-NIA escape the QF-LIA core firewalls out) — by translating a **body-faithful** Lean 4 theorem (`result` bound to the body), having `labs-leanstral-1-5` prove it, and **kernel-checking the proof with `lake env lean` + Mathlib**. A SAFE kernel check records **`verified-lean`** (`DLVerifiedLean`) — a *distinct* evidence kind that is a **peer of SMT `verified`** (§5.3.4) — plus a re-checkable `.lean` certificate. This is **not the production Lean tier:** faithful translation across *all* escape classes (`/`/`mod` floor-vs-truncation, lists/inductive via the retry-with-error loop, Lean-staleness revalidation) remains the deferred **LEAN-GA** rebuild (see [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md)); general inductive properties in particular are **not** yet shipped. Needs `LLMLL_LEANSTRAL_API_KEY` + a local Lean 4 + Mathlib project; **fails closed** otherwise. The legacy `--leanstral-mock` path emits `by sorry` (rejected by the `sanitizeProof` anti-laundering guard). Scoped in [`docs/design/leanstral-demo-spec.md`](docs/archive/shipped-design-specs/leanstral-demo-spec.md) + [`docs/design/leanstral-integration-scope.md`](docs/design/leanstral-integration-scope.md). |
| **Cryptographic primitives** | **Asserted** | _(opaque — outside any decidable fragment)_ | `hmac-sha1` and `sha1` builtins are treated as axiomatically correct. Contracts on functions that use them are capped at `asserted` in the trust report. The TOTP benchmark (`examples/totp_rfc6238/`) demonstrates mixed display levels (verified + asserted + tested) across a single module. |

**What is NOT silently dropped:** Contracts outside the QF-LIA fragment are not ignored. They are:
1. Enforced as **runtime assertions** (unless stripped via `--contracts=none`)
2. Tracked as **`asserted`** verification level
3. Flagged with `?proof-required` holes when the predicate is detected as non-linear or requiring induction
4. Propagated through the **trust report** — downstream `verified` conclusions that depend on `asserted` assumptions are flagged as epistemic drift

**Refinement-alias predicate routing.** Refinement-alias predicate obligations — generated at introduction sites by the checking-mode rule at §3.4.1 — route through the same channels as ordinary contract obligations; no separate channel is introduced. A predicate `p` in `(where [x: τ] p)` that is linear over the base-type binding is QF-LIA and auto-discharged by liquid-fixpoint (contract channel, `Contracts.hs` / `FixpointEmit.hs`); a predicate outside QF-LIA falls to items 1–4 above. See §5.3.5 for per-construct rows.

**Solver-completeness statement.** The auto-discharge boundary is the signature `Σ_auto`, the subset of the well-formedness signature `Σ_ref` (§3.4.4) for which liquid-fixpoint/Z3 is a complete decision procedure:

```
  Σ_auto  =  QF-LIA core  ∪  ( measure class | path-(a) )  ∪  ( datatype class | admissible sums )  ∪  ( array class | bytes[n] + map[{int,string},{int,bool,string}], exact reflection )
  Σ_auto  ⊊  Σ_ref          ( boolean-builtin class ∈ Σ_ref \ Σ_auto )
```

For an obligation whose predicate uses only `Σ_auto` symbols, liquid-fixpoint/Z3 is a sound-and-complete decision procedure: it returns SAFE or UNSAFE on the fixed VC, and "SAFE" is a decidable side-condition, not a quantifier over solver runs (the body-VC instance of this statement is §5.3.4). For an obligation using any symbol outside `Σ_auto`, no completeness guarantee holds; it routes to the runtime-assertion / `?proof-required` channels above (the four-item routing). The boundary rests on three facts:

- **QF-LIA core — complete.** Quantifier-free linear integer arithmetic is decidable (NP-complete); Z3 is a complete decision procedure. The verifier operates under unbounded mathematical integers, so the fragment is genuine QF-LIA.
- **Measure class — complete as a *local theory extension* (path-(a)).** A measure (`string-length`, `list-length`) emitted as a single uninterpreted function symbol carrying the range axiom `∀s. m(s) ≥ 0` is a local theory extension of QF-LIA+EUF (Sofronie-Stokkermans, *Hierarchic Reasoning in Local Theory Extensions*, CADE 2005): the axiom is complete by finite, terminating, non-recursive instantiation at the obligation's ground measure-terms, after which the problem is quantifier-free QF-LIA+EUF — decidable and complete (no convexity required; LIA is non-convex, and the Nelson–Oppen combination is complete via its nondeterministic variant). **The measure class is in `Σ_auto`:** `exprToPred` emits `string-length`/`list-length` as UF applications under the emission discipline below.
- **Datatype class — complete (acyclic sums, single-constructor products, and their acyclic compositions).** A constructor / selector over an *admissible* two-arm sum **or single-constructor product (a pair)** — one whose reachable type-closure is acyclic, decided by `admissibleDatatype` (`FixpointEmit.hs`) — is the SMT theory of algebraic data types (Barrett–Shikanian–Tinelli, *An Abstract Decision Procedure for the Theory of Recursive Data Types*, CADE 2007; Reynolds–Blanchette, *A Decision Procedure for (Co)datatypes in SMT Solvers*, JAR 2018 — the procedure z3 runs: constructors, selectors, distinctness), combined with QF-LIA by **polite-theory combination** (Ranise–Ringeissen–Zarba, *Combining Data Structures with Nonstably Infinite Theories*, FroCoS 2005; Jovanović–Barrett, *Polite Theories Revisited*, LPAR 2010). The **quantifier-free theory of recursive data types is itself decidable** (BST 2007 / Reynolds–Blanchette 2018), so `admissibleDatatype`'s acyclicity gate is *not* guarding datatype-theory decidability; it firewalls the recursive **measure** a recursive type invites (`len(cons x xs) = 1 + len(xs)` is a quantified axiom whose non-terminating instantiation leaves the decidable local-theory-extension regime of the measure class above). `typeToSortA`/`typeToSort` lower an admissible sum binder to its native datatype sort and a pair to the polymorphic product `(Pair2 s0 s1)`; `bodyToPredM`/`exprToPred` reflect a constructor application `(Ctor e)` / `(pair a b)` to the constructor term and `first`/`second` to the selectors — including the lowercase Result builtins `ok`/`err`. Admissibility is **closed under acyclic composition**: a payload or component may itself be a pair, sum, or `Result` (pair-of-`Result`, nested `Result[Result[…]]`, composed `Result[(int,int),…]` all verify). A `list`-carrier payload and a recursive type stay firewalled (fall back cleanly). Nullary enums (int-tag) and opaque-received sums (skolem-branch, payload-consuming match) stay pure QF-LIA. A **recursive** datatype is firewalled and falls back — its constructors are rejected at the strict-core gate (`def-shell` required).
- **Array class — complete (`bytes[n]` + `map[{int,string},{int,bool,string}]`, exact reflection).** The bytes and map operations (§13.12) reflect into the quantifier-free extensional theory of arrays — `bytes-get`→`select`, `bytes-set`→`store`, `bytes-zero`→the const array, `bytes-length b`→the term `bytesLen(b)`, whose defining equation `bytesLen(v) = n` is earned per position rather than asserted per binder (below); a `map[int,int]` binder splits into the two-array presence-plus-value encoding (`m$has`/`m$val`, presence as an int 0/1 array), with `map-has`→`select(m$has,k)=1`, `map-get`→a presence-gated value select, `map-put`→paired stores, `map-empty`→const arrays — decidable per Stump–Barrett–Dill–Levitt (LICS 2001), with const arrays per de Moura–Bjørner's combinatory array logic (FMCAD 2009, Z3's native procedure), combined with QF-LIA by the same polite-combination citations as the datatype class. Byte-range facts (`0 ≤ select(…) ≤ 255`) are emitted ground per occurring **bytes-rooted** read (the path-(a) discipline extended; an int-valued map-component select carries no such fact, but a **bool**-valued map value read carries the ground `0 ≤ select(…) ≤ 1` fact — the same discipline at the value sort, making the `{0,1}` encoding exact). The bytes index-in-bounds/value-range and map key-presence preconditions are PROVE-polarity call-site obligations. Emission is **activation-gated** (a function participates only if its contract or body mentions a bytes/map op) and governed by the **exact-reflection rule** (design record: `docs/archive/shipped-design-specs/data-scope-lever-a-arrays-proposal.md` §6.1): a body-faithful VC — hence a `refuted` verdict — is emitted only when every symbol in the obligation reflects exactly; whole-`bytes`/`map` `=` never reflects to array equality, and the not-yet-reflected residue routes to the fallback channel whole. Read-modify-write map bodies, cross-call map assume-guarantee, map-returning callee results, conditional (`if`) map-store bodies (v0.14.64 — a map-valued `if` or an `if` in a stored value, path-split per arm), `map[int,bool]` (bool values via the int-0/1 value bridge, each value read range-pinned to `{0,1}`), and `map[int,string]` (string values via a genuine `Str` value-array sort `(Map_t int Str)`, a `map-get` comparable to the interned `strlit_` constants, composing with STRLIT distinctness + length) all discharge (v0.14.41–46). The string-value surface is complete for API-shaped code — string-map returns, param-string put values, and string RMW chains discharge (v0.14.51); string `map-empty` construction verifies via type-directed defaults (v0.14.50) and string KEYS are admitted (v0.14.51 — `{int, string}` is the key class, literal keys exact via STRLIT distinctness, literal/var key pairs deliberately fact-free); the residue is non-{int,string} key sorts and the degenerate direct read on `(map-empty)`. **The bytes length is earned at every position it can occupy, and no half of it is asserted from a declaration.** At a `bytes[n]` **parameter**, `bytesLenParamPre` conjoins `bytesLen(v) = n` into the effective precondition, so §5.3.4's call rule proves it at each call site under PROVE polarity and the callee assumes it, exactly as for a hand-written `pre`. At a `(bytes-zero)` **construction** the constructor establishes its own by axiom (below). At a `bytes[n]` **return**, `bytesLenRetPost` conjoins `bytesLen(result) = n` into the effective **post**, where `augmentContractPost` folds it in, so the body VC proves it as a goal and each caller recovers it as an assumed post through the ordinary assume-guarantee step (§5.3.4); `resultLenFact`, the constraint-LHS assertion that used to supply it, no longer exists (FACT-AG-LEN, Stages 1-3, v0.14.76-78). One consequence is a capability rather than a restriction: **a `bytes[n]`-returning function is body-faithful and verifiable with no hand-written contract at all**, since its declared return alone now supplies a post to prove, where before it fell back. The class is **not** closed for a *recursive* `bytes[n]`-returning function, whose post stays on the assumption channel at tier `asserted`, nor for a function whose whole body is a bytes-typed variable, which falls back on a body-VC fragment boundary independent of this rule. The asserted-and-unearned reading still applies unchanged to the `0 ≤ select(m$val,k) ≤ 1` value-range fact a `map[k,bool]` binder carries, and applies to it permanently: that fact is established by the sealed `map-empty` / `map-put` constructors and is uniform over the type's inhabitants rather than parametric in an index, so there is nothing to earn and nothing to export; that arm of the restriction ships in v0.14.74, extending `assumesFact` (renamed `admits` at ADMIT-SHARED, v0.14.75) to the map class at both the argument and return seams, with no reaching-SAFE witness for this arm (a measured class member, not a demonstrated exploit). **`(bytes-zero)` establishes its own length rather than borrowing it**: the constructor's VC node carries the axiom `bytesLen(result) = n`, read off the determining `-> bytes[n]` return the type checker already requires (§13.12). That axiom is what makes the length derivable at all, since the const array is a total function in the array theory carrying no length, so `bytesLen` applied to it is otherwise uninterpreted. **`Σ_auto` is unchanged by it.** No new symbol, sort, or theory is introduced: `bytesLen` is the family-1 UF the array class already declares and the const array is already the `bytes-zero` reflection, so the completeness statement above stands as written and no wider fragment is admitted. What the axiom adds is a trust-channel dependency rather than a decidability one. It is valid because codegen reads the same annotation to emit an n-length zero value, so it rides the `codegen_semantics_version` stamp (§3.5), the same category as `bytes-set`'s length-preservation fact, and it is disclosed on no reporting channel today (roadmap row TRUST-AXIOM).
- **Outside — no completeness.** Nonlinear integer arithmetic (`* / mod rem ^ **`) is QF-NIA, undecidable (Matiyasevich 1970, Hilbert's 10th); the decidable real case (QF-NRA, Tarski) does not apply, since `int` is a mathematical (unbounded) integer, so these route to `?proof-required`. The boolean-builtin class (`regex-match`) needs an SMT string/regex theory and is not auto-discharged.

**Emission side-condition (path-(a)).** The measure-class completeness is contingent on emitting the range bound as **ground facts `m(t) ≥ 0` per occurring measure-term `t`**, not as a quantified axiom `∀s. m(s) ≥ 0` left to E-matching — the quantified form forfeits completeness (the solver may return `unknown`). This extends the measure discipline of §3.4.4.

> [!IMPORTANT]
> **The production Lean verification path is deferred; an experimental `--leanstral` demo path ships (v0.14.8).** SMT verification (Z3/liquid-fixpoint) produces `verified`; the opt-in, experimental `--leanstral` path produces **`verified-lean`** (`DLVerifiedLean`) — a *distinct* evidence kind, a **peer** of SMT `verified` (§5.3.4), kernel-checked by Lean 4 + Mathlib — for a **faithfully-translatable** obligation only (the demo class is nonlinear arithmetic). This is **not** the production tier: faithful translation across all escape classes remains the deferred **LEAN-GA** rebuild (see [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md)). No SMT-`verified` claim rests on Leanstral, and a `verified-lean` result requires a live kernel check against a local Lean 4 + Mathlib project — it fails closed without `LLMLL_LEANSTRAL_API_KEY` + that project, and the `sanitizeProof` guard rejects any degenerate (`sorry`/`admit`/empty) proof term. Obligations outside the demo's faithful-translation class — including general inductive properties — remain tracked as `asserted` with explicit `?proof-required` holes until LEAN-GA.

#### 5.3.4 Body-Faithful Verification

The `.fq` emitter now encodes function bodies as verification conditions for functions in the decidable `Σ_auto` fragment (QF-LIA + measure + acyclic-datatype + Bool, §5.3.3). For a function with postcondition Q, precondition P, and body B, the emitter generates constraints of the form:

```
P ∧ (result = ⟦B⟧) ⟹ Q
```

where ⟦B⟧ is the body's symbolic translation into the liquid-fixpoint constraint language. This closes the faithfulness gap: when both the contract and the body are in `Σ_auto` (§5.3.3), `DLVerified "liquid-fixpoint"` with `erBodyFaithful = True` means "the implementation satisfies the contract for all well-typed inputs."

Body-faithfulness (VC emitted) is necessary but not sufficient: `DLVerified "liquid-fixpoint"` is assigned **only when liquid-fixpoint returns SAFE on the body VC** `P ∧ (result = ⟦B⟧) ⟹ Q`. A body-faithful VC the solver reports UNSAFE is *refuted* (§4.4) — not *unproven* — and assigns no `verified` evidence; it writes no `.verified.json` entry. Under QF-LIA confinement the SAFE verdict is a decidable side-condition on the fixed VC (liquid-fixpoint/Z3 is a sound-and-complete decision procedure for the fragment), not a quantifier over solver runs.

**Coverage:** `ELet` with alpha-renaming (shadowing-safe), `EIf` with path-sensitive constraint emission, `EApp` to contracted functions (assume-guarantee), an **n-arm sum `EMatch`** — `Result`, or a user ADT of **any arity** whose arms are single-payload or nullary constructors with admissible-scalar payloads (the int-tag discriminant is naturally n-ary — arm *i* guards on `<v>$tag = i`, the final arm or a wildcard is the `¬prior` else) — **at any nesting depth** (under `let`/`if`, nested within another arm, and **sequentially** — a multi-path match bound in a `let` and threaded into a following match), consuming the matched payload's declared refinement, an **admissible-sum constructor application** `(Ctor e)` (via the datatype theory §5.3.3), and all QF-LIA operators. Match exhaustiveness is enforced upstream by the type checker, so the verifier only sees exhaustive matches. A post that references the **matched scrutinee's constructor** (`result = C₁ ⇒ sig = C₂`) discharges: the arm discriminant is a free int-tag equality `(= sig$tag k)` with a range fact, and a scrutinee-constructor desugar rewrites `sig = C` to `sig$tag = k` (QF-LIA; no datatype testers). A constructor of a non-admissible (recursive) sum, `letrec` (own body), and non-linear expressions fall back conservatively to contract-only verification.

**Compositional call-chain verification:** When a body-faithful function calls a contracted callee, the verifier:
1. **Proves** the callee's precondition is satisfied at the call site (PROVE polarity — caller obligation)
2. **Assumes** the callee's postcondition holds for the call result (assume-guarantee)
3. **Binds** a fresh symbolic variable for the call result

**Sequential chains.** For a path with contracted calls `c₁ … cₙ` in evaluation order (chained via an `ELet` that binds a call result used by a later call, or by nested application), each call `cₖ`'s precondition is discharged under the accumulated context of the prior calls on its path:

```
guard_k  ∧  P_caller  ∧  ⋀_{i<k} Q_{c_i}[r_i]   ⟹   Pre_{c_k}[args_k]
```

where `Q_{c_i}[r_i]` is callee `cᵢ`'s contract postcondition over its fresh result variable `rᵢ` (ASSUME polarity), `rᵢ` is bound in the constraint environment, and `guard_k` is the path guard accumulated through enclosing `EIf`/`EMatch`. A `let`-bound call result is the call's result variable itself (no separate symbol), so a later call referencing an earlier result reasons about that result's assumed post. The single-call rule above is the `k = 1`, empty-prefix instance; the context is **per-path** — a call in one branch does not assume a post from a call in another. This is the standard modular procedure-call (sequential-composition) discipline.

**Trust-tier side-condition.** Discharging `cₖ`'s precondition under a prior call's *assumed* post is sound relative to that callee's own `(pre ⟹ post)` at its trust tier. The chaining function's effective tier is therefore the **meet (§4.4) over its own evidence and every transitive callee's tier**: a body-faithful function whose chain traverses an `asserted`-tier call degrades to `asserted`, not `verified`, even when its own VC is SAFE. (This meet is taken by the transitive trust closure over the syntactic call graph, independent of which call-pre obligations are emitted.)

Recursive functions (detected via `stronglyConnComp` SCC analysis) are excluded from body VC emission for their own body, but non-recursive callers may still use assume-guarantee against their contracts; the chained rule assumes callee contract posts, never callee bodies, so it introduces no circularity within an SCC. A `let`-bound *non-call* value used in a later call's precondition is threaded into the chain context as its defining equality, filtered to the subset of bindings in scope at the call.

**Cross-module callees.** An imported contracted callee is treated identically to a same-file one: its contract is seeded into the body-VC `ContractEnv` from the module cache (`emitFixpointWithCache`), so the caller proves the imported `pre` and assumes the imported `post` — the imported *body* is never re-verified. The caller is therefore **body-faithful across the `import` boundary**, with its tier riding the meet (§4.4) against the imported callee's tier (an imported `asserted` callee yields an `asserted` caller). Module import cycles are a hard error, so the import graph is acyclic and this is the ordinary compositional Hoare rule under a topological order — no fixpoint argument. Nullary-enum constructor values in an imported contract are desugared against the merged (entry ∪ imported) alias map, so their int tags agree with the caller's own body. Cross-module ADT identity is nominal-by-name (the unshipped MOD-5 structural check); this rides the type checker's resolution and does not widen that gap.

**Path limit:** Functions with >4096 execution paths (from deeply nested `EIf`) fall back to contract-only verification with a diagnostic warning. This prevents solver timeouts while maintaining soundness.

**Contract stripping:** `--contracts=unproven` strips postcondition runtime assertions for functions that are both `DLVerified` and body-faithful (`erBodyFaithful = True`). Preconditions are never stripped — body VCs prove postconditions, not preconditions. Functions that fall back to contract-only verification retain all runtime assertions regardless of proof status.

**Strict verified core:** `--strict-verified-core` hard-errors if any function in the transitive call graph (a) falls back from body-faithful verification (`erBodyFallback`; a genuine `Σ_auto` escape — a merely cross-module call is body-faithful, not a fallback), (b) carries overflow-tainted verified evidence (`erOverflowTainted`), (c) is **refuted** — body-faithful but the solver reported its body VC UNSAFE (§4.4) — or (d) has an `asserted`-tier dependency. Conjunct (c) is transitive by assume-guarantee composition: a caller cannot be admitted on a postcondition the solver disproved, even when the caller's own VC is SAFE. Use this to enforce that all functions in a module are fully verified.



#### 5.3.5 Verification Matrix

The following matrix documents the verification status of each syntax construct. "Typechecked" means the construct is accepted by the type checker. "Runtime assert" means contracts on functions using the construct are enforced as runtime assertions. "SMT contract" means the construct's contracts can be checked by the solver. "SMT body-faithful" means the construct's implementation is encoded as a verification condition.

| Construct | Typechecked | Runtime assert | SMT contract | SMT body-faithful | QuickCheck | Fallback behavior |
|---|---|---|---|---|---|---|
| `ELit` (int, bool) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `EVar` (int-typed) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `EVar` (non-int) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| `EOp`/`EApp` (+, -, =, <, <=, >=, >, !=) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `EOp`/`EApp` (*, /, mod, rem) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime + `?proof-required` |
| `ELet` (single `PVar`, int RHS) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `ELet` (pattern/non-int RHS) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| `EIf` (int guards, ≤4096 paths) | ✅ | ✅ | ✅ | ✅ (path-split) | ✅ | — |
| `EIf` (>4096 paths) | ✅ | ✅ | ✅ | ❌ | ✅ | contract-only + warning |
| `EApp` (contracted callee, non-recursive, same-file or imported) | ✅ | ✅ | ✅ | ✅ (assume-guarantee) | ✅ | — |
| `EApp` (uncontracted callee) | ✅ | ✅ | ✅ | ❌ | ✅ | contract-only |
| `EApp` (recursive self / cycle, contracted) | ✅ | ✅ | ✅ | ✅ (assume-guarantee; **partial** by default, **total** with a discharging `(decreases e₁ … eₖ)` — single or lexicographic, equal-arity SCC — §4.2) | ✅ | no measure → `termination_unverified` flag; discharge → total + strict-core admissible; bad measure → `measure-not-decreasing`; mixed-arity mutual SCC refused (stays partial) (§4.2, §4.4.4) |
| `EApp` (builtins: `string-length` etc.) | ✅ | ✅ | ✅ | ❌ | ✅ | contract-only |
| `EApp` (bytes ops: `bytes-get`/`bytes-set`/`bytes-length`/`bytes-zero`, §13.12) | ✅ | ✅ | ✅ (reflected: `select`/`store` / `bytesLen(b)`, with `= n` earned per position, §5.3.3 / const array) | ✅ (array class §5.3.3; index-in-bounds + value-range as PROVE call-site obligations; activation-gated to functions mentioning a bytes op) | ✅ | whole-bytes `=`, mixed bytes+map obligations, any non-exact reflection → contract-only (exact-reflection rule) |
| `EApp` (map ops: `map-has`/`map-get`/`map-put`/`map-empty`, §13.12) | ✅ | ✅ | ✅ (two-array int-0/1 presence encoding: presence select / presence-gated value select / paired stores / const arrays) | ✅ (array class §5.3.3; key-presence as a PROVE call-site obligation; `map[int,{int,bool,string}]` v1 — bool values via the int-0/1 bridge (range-pinned `{0,1}`), string values via a genuine `Str` value-array sort (a `map-get` comparable to interned `strlit_` constants); incl. let-bound put/get pipelines, read-modify-write bodies, cross-call assume-guarantee, map-returning results, conditional (`if`) map-store bodies; activation-gated) | ✅ | non-{int,string} key sorts / direct reads on `(map-empty)`, whole-map `=`, and a bool-get used outside `=`/`!=` → contract-only, whole (exact-reflection rule) |
| `EMatch` two-arm sum (`Result`, or user ADT both arms single-payload) | ✅ | ✅ | ✅ | ✅ (two-path, any nesting; consumes payload refinement) | ✅ | — |
| constructor application `(Ctor e)` / `(Ctor)` over an admissible sum (incl. Result `ok`/`err`) | ✅ | ✅ | ✅ | ✅ (datatype theory, §5.3.3) | ✅ | recursive sum / non-admissible Result payload → fallback; user-sum recursive ctor → strict-core gate → `def-shell` |
| `EMatch` n-arm admissible sum (mixed nullary/payload, nested, sequential) | ✅ | ✅ | ✅ | ✅ (n-ary int-tag chain; exhaustiveness type-checked) | ✅ | recursive/non-admissible payload → runtime |
| `EPair`/`first`/`second` (scalar / admissible-sum / nested / list component) | ✅ | ✅ | ✅ | ✅ (datatype theory, §5.3.3) | ✅ | opaque-pair / `Result` / recursive-sum / non-`Σ_auto` component → runtime |
| `letrec` (own body VC) | ✅ | ✅ | ⚠ measure well-formedness only | ❌ | ✅ | runtime + `:decreases` check |
| `EDo` | ✅ | ✅ | ❌ | ❌ | limited | runtime |
| `ELambda` | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| **Int overflow** | ✅ | ✅ | ✅ on `int` (Z3 `Int` = Haskell `Integer`, both unbounded) | n/a on `int` | ✅ | gap closed on `int`; re-arms on a future `machine-int` opt-in |
| `TCustom` alias predicate obligation at intro site (QF-LIA `p`) | ✅ | ✅ (host pre/post; alias predicate solver-only, never runtime-asserted — §3.4.5) | ✅ (contract channel) | ✅ | ✅ | no separate channel; routes via `Contracts.hs` / `FixpointEmit.hs`; §3.4.1 checking-mode rule |
| `TCustom` alias predicate obligation at intro site (non-QF-LIA `p`) | ✅ | ✅ (host pre/post; alias predicate solver-only, never runtime-asserted — §3.4.5) | ❌ | ❌ | ✅ | `erBodyFallback` → contract-only / `asserted` tier; **no** runtime assertion for a refinement-typed binding (`augmentContractPre` verifier-local — unlike a non-QF-LIA *contract* obligation, which does assert; §3.4.5) |
| Refinement-aliased return `-> A` introduction obligation `p[body/result]` | ✅ | ✅ (host pre/post; return-alias predicate solver-only — §3.4.5) | ✅ (QF-LIA `p`, contract channel) | ✅ (QF-LIA `p`) | ✅ | the §3.4.1 introduction at the return position (§3.4.6, §4.1), **discharged via `augmentContractPost`**: the body-VC proves `p[result/x]` (`verified` / `refuted` / `erBodyFallback` per §5.3.3) and the refinement is exported as a caller-assumable guarantee (assume-guarantee, §5.3.4 meet). A non-`Σ_auto` return refinement forces `erBodyFallback` (the §3.4.5 firewall) via the untranslatable-augmented-post path — no special guard. |
| `?delegate` / `?delegate-async` body (`def-shell`) | ✅ | ❌ (`on-failure` clause executes at runtime if present; unresolved → `?delegate-pending`) | ❌ (`asserted` tier; host-function contracts verified contract-only) | ❌ | skip | `asserted`; `guardDelegate` (in `PBT.hs`) blocks `DLTested` PBT write-back on delegate-body functions regardless of `on-failure` fallback path; `on-failure` enables runtime execution but does not promote trust; see §11.2 |
| `?delegate` / `?delegate-async` body (`def`, pre-resolution) | ✅ | ❌ | ❌ | ❌ | skip | authoring intermediate; admitted in `def` pending resolution; post-resolution, agent loop re-typechecks resolving value's admissibility before merging into `def`-form host; pre-resolution trust is `asserted` unconditionally regardless of pre-clause evaluability — two mechanisms converge: (a) `guardDelegate` in `PBT.hs` (`pbtTrustWriteback`) blocks `DLTested` write-back when body is `EHole(HDelegate _)` / `EHole(HDelegateAsync _)` for `SDef` forms — evaluable-pre path; (b) pre-clause unevaluability propagation (`QC.discard` saturation → `PBTSkipped` → no lift) — unevaluable-pre path. Mechanisms are independent and non-interfering. Post-resolution, the merging agent re-runs `checkCalleeAdmissibility` and re-verifies the resolved body; see §11.2. |

> [!NOTE]
> **Predicate-carrying `?proof-required` in `pre`/`post`.** When the predicate-carrying form `(?proof-required :reason "tag" pred-expr)` appears in a `pre` or `post` clause, the predicate `pred-expr` is type-checked as `bool` and emits a Haskell runtime assertion at codegen (Runtime assert column: ✅ — actively executed, not a no-op). If `pred-expr` contains non-linear operators (`*`, `/`, `mod`, `^`), `llmll check` emits a `QF-LIA` warning naming the function and clause. SMT contract and SMT body-faithful columns are ❌ for the carrying form regardless of predicate linearity — the predicate is enforced at runtime, not submitted to the solver. The bare `?proof-required` leaf in `pre`/`post`: Runtime assert is ✅ but the generated assertion is a no-op; the predicate-carrying form is what enables active runtime enforcement. Body-position `?proof-required` (either form) emits an `error` stub and is unaffected by this rule.

> [!NOTE]
> **Callee admissibility in `def` bodies.** Built-in LLMLL operators (members of `builtinEnv`) are unconditionally admitted inside `def` bodies, including operators appearing in contract clause expressions. The core-mode callee-admissibility check at `checkCalleeAdmissibility` (in `TypeCheck.hs`) applies three admission legs — body-faithful `EvidenceRecord`, `trustedPrelude` membership, and `builtinEnv` membership — identically whether the `EApp` node appears in the function body or in a `pre`/`post` predicate clause. The trust tier of `builtinEnv` callees propagates into the caller via the lattice meet per §4.4.1: QF-LIA primitives (`+`, `-`, `=`, `<`, etc.) are body-faithful by construction and leave the meet unchanged; axiomatized trusted-prelude builtins (`string-length`, `list-head`, etc.) produce the assume-guarantee tier at the call site. See the `§12` grammar production comment for the production-level statement.

> [!NOTE]
> **Integer overflow model.** Z3 reasons over mathematical integers (unbounded). LLMLL `int` lowers to Haskell `Integer` (unbounded) at codegen, so the verifier and runtime semantics agree on `int` — there is no overflow gap on `int`. The gap re-arms only for programs that opt into a future bounded `machine-int` primitive (per [`docs/design/int-3-machine-int-sketch.md`](docs/design/int-3-machine-int-sketch.md)) under QF-BV verification with the higher solver cost that implies; on `int` there is no overflow event.

> [!IMPORTANT]
> **`overflow_tainted` marking — dormant on `int`.** The `overflow_tainted` machinery (`erOverflowTainted` field on `EvidenceRecord`, `overflow_tainted` JSON projection in trust report / `.verified.json` sidecar / obligation-report trust channel, `--strict-verified-core` refusal, `bodyHasOverflowArith` walker) is preserved across the trust-report / sidecar / obligation surface, but the trigger is disarmed on `int`: the body-VC emitter call to `addOverflowTainted` (in `FixpointEmit.hs`) is commented out, and the walker — though still defined and round-trippable — is not reached on production verify runs. `examples/banking_ledger/banking.llmll`'s `safe-subtract` is the demonstrating case (admitted under `--strict-verified-core`). The **reader-side** counterpart — `VerifiedCache.sidecarNeedsRevalidation`, which invalidated any verified body-faithful sidecar *lacking* the field — is **disarmed**: with the emitter dormant the field is legitimately absent on every verified sidecar, so the trigger fired on all of them and `--trust-report` could never surface `verified`. The disarm is sound only while all `int` codegen is unbounded; a future `machine-int` opt-in under QF-BV (per [`docs/design/int-3-machine-int-sketch.md`](docs/design/int-3-machine-int-sketch.md)) re-arms the **emitter** with a type-aware predicate that fires on `machine-int` but not `int`, and must re-arm the **reader** via a `codegen_semantics_version` stamp (not field-absence) so the disarm's antecedent is not silently inherited by the bounded-codegen construct that falsifies it.
>
> **`overflow_tainted` trigger set:** the marking is purely syntactic — it does not consult refinement predicates that might witness bounds — and the trigger set is `EOp` / `EApp` applications of `+`, `-`, `*`, `/`, `mod`, `rem`, `^`, `**` whose operands are not all integer literals whose folded value fits `Int64`. Compile-time constant arithmetic like `(+ 40 2)` is cleared. The taint never propagates transitively across calls — it is per-function-body — because the call-site verification still proves the callee's post against the caller's pre under Z3's unbounded-integer semantics. The discharge paths are: (i) wrap the post-condition in `?proof-required` and complete via Leanstral; (ii) a future codegen switch; (iii) a future `machine-int` opt-in under QF-BV.

### 5.4 The Proof Artifact (`--proof-artifact` / `replay-artifact`)

**The proof artifact (staged MVP).** `llmll verify <file> --proof-artifact <FILE>` writes one serializable record per verification run that **consolidates** the justification surfaces — the trust report (§5.3 tiers, transitive closure, drifts), the obligation report (`consumed_guarantees`, `caller_obligations`), the `.fq` VC, and the `.verified.json` sidecar — plus the determinism-pin delta fields no other output carries: the solver versions/options, the `codegen_semantics_version` stamp (§5.3.5), and the source hash. It is a **synthesis, not a new verification primitive**: it introduces no new proof obligation, no `Σ_auto` growth (§5.3.3), and no `?proof-required`; it composes `trust_report_version` rather than bumping it. Design of record: [`docs/design/proof-artifact-proposal.md`](docs/archive/shipped-design-specs/proof-artifact-proposal.md).

**What it buys — hermetic, auditable re-verification, not solver-free checking.** `llmll replay-artifact <FILE>` recomputes the source hash and, on a match, re-runs the stored VC under the pinned `solver_version` / `solver_options` / `resource_limits`. The recorded verdict must reproduce; replay **fails closed** on any source/AST hash mismatch, any determinism-input mismatch, or an `unknown`/timeout outcome — a distinct non-verdict that demotes to "needs re-verify," never read as SAFE or UNSAFE. This is the **replay (R-) property** — the F\*-`.hints` (Swamy et al., POPL 2016) and Dafny-caching (Leino, LPAR 2010) precedent. It is **not** *independent checkability* (the C-property: validating a verdict without trusting or re-running the solver), which has a different trusted base and is reserved for the future Lean tier — the format-agnostic `certificate` field is populated there, never by a Z3 proof object. `unsat_core` is a reserved field (deferred; Z3's core is not cheaply surfaced through liquid-fixpoint); the staged MVP ships the R-property on the full `vc`.

**Anti-laundering as a well-formedness invariant.** A per-function record carrying a **positive tier** (`verified` / `contract-checked` / `tested`) is **ill-formed** unless its qualifying fields cohere: it is not `refuted`, its `fallback_reason` is empty when `verified` (body-faithful), and a recorded `discriminative_axis` carries its `basis`. This is enforced LCF-style by a smart constructor (Milner, *Edinburgh LCF*, 1979) — a positive-tier record is mintable **only** through the kernel that refuses the missing qualifiers, on both emit **and deserialization**, so a hand-forged artifact claiming `verified` while flagged `refuted` fails to parse. Evidence-laundering by field omission/contradiction is thereby an *unrepresentable state*, not a discouraged practice — a checkable, non-SMT condition with the same status as the §3.4.4 predicate well-formedness rule.

---

## 6. Hole-Driven Development (`?`)

When an LLM encounters ambiguity or an unimplemented TODO, it **must** use a Hole. Never guess or hallucinate an implementation — emit a hole and document what is needed.

A program with holes can be **parsed, type-checked, and analyzed** but **not executed** until all holes are resolved. The compiler reports the type of every hole so the resolving agent knows exactly what to produce.

| Hole form | When to use |
|-----------|-------------|
| `?name` | Named placeholder. The resolving agent must provide an expression of the inferred type. |
| `?choose(opt1, opt2, ...)` | Ask the human or Lead AI to pick one of the named options. |
| `?request-cap(wasi.net.connect)` | Request a capability grant from the human operator. |
| `?scaffold(template ...)` | Cold-start a module from a `llmll-hub` skeleton (see §6.1). |
| `?delegate @agent "description" -> Type` | Delegate implementation to a named agent (see §11.2). |
| `?delegate-async @agent "description" -> Type` | Non-blocking delegation. `return_type` is the inner type `T`; the compiler wraps it in `Promise[T]` (see §11.2). |
| `?proof-required` | A contract predicate outside the decidable QF arithmetic fragment. Two forms: (1) bare leaf `?proof-required` — marks the clause `asserted`, emits no runtime assertion; (2) predicate-carrying `(?proof-required :reason "tag" pred-expr)` in `pre`/`post` position — `pred-expr` is type-checked as `bool` and emits a Haskell runtime assertion at codegen; non-linear predicates emit a `QF-LIA` warning at `llmll check`. Body-position `?proof-required` (either form) emits an `error` stub and is unchanged. Non-blocking. See §6 and `getting-started.md §4.11`. |

> [!NOTE]
> **`?delegate` / `?delegate-async` trust and verification.** These hole forms are authoring intermediates admitted by the typechecker anywhere an expression of the declared type is expected. In `def-shell` bodies, the host function's trust tier is `asserted`; PBT `DLTested` write-back is suppressed by `guardDelegate` regardless of whether an `on-failure` clause provides a runtime fallback. In `def` bodies, both forms are admitted pending out-of-process resolution; post-resolution, the agent loop re-runs the typechecker's core-membership predicate before merging the resolving value into the `def`-form host. Pre-resolution trust is `asserted` unconditionally regardless of pre-clause evaluability: `guardDelegate` extends to `SDef` forms, blocking `DLTested` write-back on the evaluable-pre path; pre-clause unevaluability independently produces `PBTSkipped` on the unevaluable-pre path. Both paths converge on `asserted`. See §5.3.5 (verification matrix rows) and §11.2 (inference rules, `on-failure` type rule, async delegation flow).

> [!NOTE]
> **Bare `?proof-required`: a gap signal without a predicate payload.** The bare leaf form records that the clause involves reasoning outside the verifier's decidable fragment; no predicate expression is embedded. The intended predicate is documented in source comments, function docstrings, or trust-report annotations. The compiler treats bare `?proof-required` as `asserted` for trust-level purposes (per §5.3.5). **Predicate-carrying form:** `(?proof-required :reason "tag" pred-expr)` in `pre`/`post` position *does* embed the predicate as an optional `Expr` payload — `HoleKind.HProofRequired Text (Maybe Expr)` in [`compiler/src/LLMLL/Syntax.hs`](compiler/src/LLMLL/Syntax.hs). The compiler type-checks `pred-expr` as `bool` and emits a runtime assertion at codegen. Body-position `?proof-required` (either form) is unchanged and emits an `error` stub regardless of predicate presence.

**Usage in expressions:** A hole can appear anywhere an expression is expected:

```lisp
(def-shell display-word [word: Word guessed: list[Letter]]
  (post (= (string-length result) (string-length word)))
  ?display_word_impl)            ;; hole: compiler knows return type is string
```

### 6.1 Scaffold Holes (`?scaffold`)

A `?scaffold` hole solves the **cold-start problem**: before a Lead AI can write a `(def-interface ...)`, it needs a structurally valid starting point. Instead of generating a module from a blank slate (maximizing hallucination risk), the LLM requests a known-good skeleton:

```lisp
(?scaffold web-api-server
  :language llmll
  :modules  [routing auth persistence]
  :style    rest
  :version  "0.1")
```

`?scaffold` is the only hole type that **resolves at parse time** — the compiler fetches and expands the skeleton before semantic analysis begins. The expanded skeleton has all `def-interface` boundaries pre-typed and implementation details pre-filled as named `?` holes.

---

## 7. FFI & Capability System

`llmll` programs run in a sandbox and reach the outside world only through declared `import` statements. The sandbox implementation is Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` with WASM-WASI planned as a future deployment target.

**What the compiler checks, exactly.** When a `wasi.*` function is called, the type checker verifies that the calling module declares an import for that function's **namespace**, the first two segments of its dotted path. Calling `wasi.fs.read` requires `(import wasi.fs)` in that module. The check is non-transitive: module B importing module A does not inherit A's `wasi` imports, so each module re-declares what it reaches. It is implemented as `checkWasiCapability` in [`TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs) and exercised by the capability fixtures in [`compiler/test/fixtures/`](compiler/test/fixtures/).

```lisp
(module cloud-storage
  (import wasi.fs (capability read-write "/data"))
  (import wasi.http       (capability post "https://api.logging.com")))
```

> [!WARNING]
> **The `capability` clause is currently declarative, not enforced, and this section claimed otherwise for a long time.** The checker reads the import *path* and nothing else. Four consequences hold today:
>
> 1. A bare `(import wasi.fs)` **with no `capability` clause at all** authorizes every `wasi.fs.*` call. The clause is not required, even though the missing-import diagnostic asks for one.
> 2. The granted **verb** is not checked. `(capability read "/data")` authorizes `wasi.fs.write` and `wasi.fs.delete`.
> 3. The granted **target** is not checked, at compile time or at run time. `(capability read-write "/data")` does not confine anything to `/data`, and a computed path is unconstrained.
> 4. Any unrecognized verb parses and is ignored.
>
> So the property that holds is **module-scoped declaration of effect namespaces**, which is real and useful for auditing, and it is weaker than least authority. Earlier revisions of this section named the principle of least authority and §9.4 described a runtime `CapabilityError`; neither is earned. Whether LLMLL should adopt object-capabilities, enforce the verb statically, or route the target through the contract channel is an open design question tracked as `CAP-1-REAL` in [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md). Write the clause anyway: it is the declaration a future enforcing checker will read, and it is what the effect summary (§11.2) and reviewers use today.

Capabilities can carry the `:deterministic` flag (see §10a) to opt into event-log capture for replay:

```lisp
(import wasi.clock  (capability monotonic-read :deterministic true))
(import wasi.random (capability get-bytes      :deterministic true))
```

> **Known compiler bug (parser, fix in progress).** `get-bytes` currently fails to parse: the capability-kind parser tries the `get` alternative before `get-bytes`, and `get` matches without a word-boundary check, consuming the prefix. This is the correct, intended grammar — not a documentation error — but it will not parse until the parser fix lands.

**External Bridge (FFI):** To use existing Haskell packages or C libraries, define a Verified Wrapper using the `haskell.*` or `c.*` prefix:

```lisp
(import haskell.aeson (interface [
  [json-decode (fn [s: string] -> Result[TodoList, string])]
  [json-encode (fn [td: TodoList] -> string)]
]))
```

In LLMLL, FFI imports are resolved through a **two-tier lookup**. The compiler checks each tier in order:

| Tier | Prefix | Mechanism | Stub generated? |
|------|--------|-----------|----------------|
| **1 — Hackage** | `haskell.*` | Regular GHC `import`; package added to `package.yaml`. No stub generated. | No |
| **2 — C libraries** | `c.*` | GHC `foreign import ccall`; compiler generates `src/FFI/<lib>.hs` with typed stub. | Yes |

> The `rust.*` namespace is retired. The Haskell backend uses Tier 1 Hackage imports (e.g. `haskell.aeson`, `haskell.warp`) as direct replacements with no stub required.

**Tier 1 example — zero developer action:**

```lisp
;; Resolves to: import Data.Aeson — no stub file generated
(import haskell.aeson (interface [
  [json-decode (fn [s: string] -> Result[TodoList, string])]
  [json-encode (fn [td: TodoList] -> string)]
]))
```

**Tier 2 example — C FFI stub generated:**

```lisp
;; Compiler generates src/FFI/Libsodium.hs with foreign import ccall stubs
(import c.libsodium (interface [
  [crypto-sign (fn [msg: bytes[64] key: bytes[32]] -> bytes[96])]
]))
```

> [!CAUTION]
> **FFI stubs are NOT `?delegate` holes.**
> Tier 2 C stubs (`src/FFI/*.hs`) are resolved **by the developer writing Haskell FFI code** against the C library.
> `?delegate` holes are resolved **by the Lead-AI/Human reviewer writing LLMLL code** inside the `.llmll` source file. A `?delegate` must NEVER be manually implemented in generated code — that bypasses the verifier entirely.

> [!WARNING]
> **Pitfall: Declaring a C interface you don't fully implement.**
> If you declare `(import c.mylib (interface [...]))` but leave the generated `src/FFI/Mylib.hs` stub unimplemented, **the code will compile but fail at link time or panic at runtime**. Every `(import c.* ...)` you write must have a fully implemented stub before running the service.



---

## 8. Module System

The module system provides **multi-file compilation**, namespace isolation, export control, and the `llmll-hub` package registry.

### 8.1 Module Name and File Path

A `(module Name ...)` declaration is accepted at the top of any file. The module name is a single `IDENT` used for documentation and tooling display only — the **canonical module path** is derived from the file's location relative to the source root. This prevents mismatches between declared names and import paths.

```lisp
(module hangman
  (import wasi.io (capability stdin  :deterministic true))
  (import wasi.io (capability stdout :deterministic false))

  ;; Module body: type declarations, def/def-shell, def-interface, check, gen
  (type Word (where [s: string] (> (string-length s) 0)))

  (def-shell game-won? [state: GameState]
    (all-guessed? (state-word state) (state-guessed state))))
```

### 8.2 File-System Module Resolution

`(import foo.bar.baz ...)` is resolved using a configurable **module root list** (default: directory of the entry-point source file, then `~/.llmll/modules/`):

```
foo/bar/baz.llmll        (S-expression — tried first)
foo/bar/baz.ast.json     (JSON-AST      — tried second)
~/.llmll/modules/foo/bar/baz.llmll   (hub cache — tried last)
```

If both `.llmll` and `.ast.json` exist for the same path, `.llmll` takes precedence.

> [!NOTE]
> **Grammar-mode inheritance for imported modules.** All imported modules — whether
> resolved from the local source root, `extraRoots`, or the `llmll-hub` cache
> (`~/.llmll/modules/`) — are parsed under the **same `GrammarMode` as the invoking
> command**. The default grammar mode is `GrammarCoreInversion`.
>
> Any imported `.ast.json` file containing `{"kind": "def-logic"}` is rejected
> with a `removed-construct` diagnostic (exit 1) under **all** grammar modes —
> def-logic is not a valid construct. `{"kind": "letrec"}` produces a
> `core-grammar-violation` (exit 1) under `GrammarCoreInversion`. Hub publishers
> must ship `schemaVersion 0.11.0` modules using `def`/`def-shell` node kinds (`0.10.0`, `0.9.0`, `0.8.0`, `0.7.0` and `0.6.0` are still accepted by the reader).
>
> `wasi.*`, `haskell.*`, and `c.*` builtin-namespace imports carry no parseable
> file and are exempt from grammar-mode checking.

### 8.3 Declaration Ordering

All `import`, `open`, and `export` declarations should appear **before** any `def`, `def-shell`, `type`, or `def-interface` statements — both inside a `(module ...)` block and at file scope. The parser accepts declarations in any position, but **ordering has semantic impact**: the type-checker processes statements sequentially, so an `(open A)` placed after a `(def f ...)` will not inject A's names into `f`'s body scope.

Recommended order:
1. `import` declarations (trigger module loading)
2. `open` declarations (inject bare names into scope)
3. `export` declaration (restrict visibility to importers)
4. `type`, `def-interface`, `def`, `def-shell`, `letrec`, `check` declarations

### 8.4 Cycle Detection

Circular imports are a **compile error**. The compiler performs a DFS-based cycle check before loading any module. The diagnostic names the full cycle:

```json
{
  "kind":    "circular-import",
  "cycle":   ["foo.bar", "foo.baz", "foo.bar"],
  "message": "Circular import detected: foo.bar → foo.baz → foo.bar"
}
```

### 8.5 Namespace Resolution (Current Behavior)

`(import foo)` triggers DFS file loading and seeds the type-checker with **qualified names only** (`foo.f`, `foo.g`). Codegen concatenates all imported module statements into a single flat `Lib.hs` with bare Haskell names.

To call imported functions, use `(open foo)` to inject bare aliases into the type-checker's scope, then call with bare names:

```lisp
(import app.auth)
(open app.auth)                  ;; inject bare aliases for all exports

;; Call with bare name:
(hash-password raw-str)
```

The usable pattern is: **`import` → `open` → bare call.**

Qualified references (`app.auth.hash-password`) are accepted by the type-checker but **fail at codegen** — the flat `Lib.hs` emits bare Haskell names, not qualified ones.

> [!NOTE]
> **Loader permissiveness.** The DFS module loader uses permissive typechecking for
> imported modules — unbound bare names produce warnings, not errors. The entry-point
> file is checked with strict typechecking during `llmll build`. This asymmetry means
> imported modules may omit `(open ...)` declarations and still load successfully,
> but the entry-point file must include them.

#### 8.5.1 Qualified Access (Planned — Not Shipped)

The language design supports fully qualified access as the default namespace model:

```lisp
;; PLANNED (not currently operational at codegen):
(app.auth.hash-password raw-str)
```

This will become operational when codegen emits per-module Haskell files with proper qualified imports, replacing the current single-`Lib.hs` concatenation model.

### 8.6 `open` — Bare-Name Injection

`(open path)` injects a module's exported names into the current scope as bare names. This is **required** for calling imported functions under strict typechecking (used by `llmll build`). An optional name list restricts which names are injected:

```lisp
(open app.auth)                  ;; all exports as bare names
(open app.auth (hash-password))  ;; only hash-password as a bare name
```

`open` is a compile-time alias injection — it makes the type-checker aware of bare names. Codegen is unaffected (bare names already exist in the concatenated `Lib.hs`).

`(import A)` alone loads module A's definitions into `Lib.hs` but does **not** make them accessible by bare name in the type-checker. Without `(open A)`, only qualified names (`A.f`) are in scope, and qualified names do not resolve at runtime under the current flat-codegen model.

> **Collision policy:** If two `(open ...)` declarations export the same bare name, the second `open` wins (last wins). The compiler emits a `WARNING` diagnostic.

> **Property-based testing.** The PBT static evaluator used by `llmll test` honors the same bare-name injection rule: a `(check ...)` block whose body calls an imported function evaluates only when the imported module is in bare-name scope via `(open ...)`. Without `open`, the property body cannot reduce to a literal Bool and `llmll test` reports the check as `Skipped`. Qualified references (`module.fn ...`) inside check bodies share the codegen limitation described in §8.5.1 and currently do not resolve at runtime.

### 8.7 `export` — Visibility Control

```lisp
(export hash-password verify-token)   ;; only these two names visible externally
```

If no `export` declaration is present, **all** top-level `def`, `def-shell`, `type`, `def-interface`, and `gen` declarations are exported (open default). `check` and `def-invariant` blocks are **never exported**.

The `export` declaration must appear before the first `def` or `def-shell`.

> [!NOTE]
> **Export enforcement scope.** Export control is enforced at compile time during
> `llmll build` (which uses strict typechecking). Permissive `llmll check` reports
> unexported-name access as warnings, not errors.
>
> The generated `Lib.hs` contains all definitions from all imported modules, including
> unexported ones, because exported functions may depend on private helpers and type
> aliases. True codegen-level hiding requires per-module Haskell file emission with
> Haskell `module` export lists, planned for a future release.

### 8.8 Cross-Module `def-interface` Enforcement

When module B imports module A and calls a function declared under A's `def-interface`, the compiler:

1. Looks up the interface shape in A's exported `ModuleEnv`.
2. Checks structural compatibility for every method.
3. Expands type aliases from A's scope before comparison.
4. Emits a compile error if any method is missing or type-incompatible:

```json
{
  "kind":      "interface-mismatch",
  "module":    "app.auth",
  "interface": "AuthSystem",
  "method":    "hash-password",
  "expected":  "(fn [string] -> bytes[64])",
  "got":       "(fn [string] -> string)",
  "pointer":   "/statements/2/body"
}
```

### 8.8.1 Algebraic Laws for Interfaces (`:laws`)

Interfaces can declare **algebraic laws** that any conforming implementation must satisfy. Laws are `(for-all ...)` properties attached to a `def-interface` via the `:laws` clause. The compiler type-checks law expressions with interface methods and bindings in scope, and generates QuickCheck `prop_` functions for automated enforcement.

```lisp
;; Idempotent normalizer: normalizing twice is the same as normalizing once
(def-interface Normalizer
  [normalize (fn [x: string] -> string)]
  :laws [(for-all [x: string] (= (normalize (normalize x)) (normalize x)))])

;; Monoid laws: identity and associativity
(def-interface Monoid
  [mempty   (fn [] -> string)]
  [mappend  (fn [a: string b: string] -> string)]
  :laws [(for-all [x: string] (= (mappend (mempty) x) x))
         (for-all [x: string] (= (mappend x (mempty)) x))
         (for-all [a: string b: string c: string]
           (= (mappend (mappend a b) c) (mappend a (mappend b c))))])
```

**Note:** `def-interface` members must be function-typed (`(fn [args] -> ret)`) — there is no bare-value/constant member form, so a nullary-constant interface member like `mempty` is declared `(fn [] -> T)` and called as `(mempty)`, including inside `:laws`.

**Syntax:** `:laws` is an optional clause after the method list. It contains a list of `(for-all [bindings] expr)` properties. Each `for-all` binding follows standard typed-parameter syntax.

**Type checking:** Law expressions are type-checked in a scope where all interface methods are available as bound variables. The `for-all` bindings are added to this scope. The body expression must have type `bool`.

**Codegen:** Each law property generates a QuickCheck `prop_` function in the emitted Haskell. The properties are wired into `runPropertyTests` and appear as a separate "Interface laws" section in `--spec-coverage` reports.

**JSON-AST:** Laws are represented as an array of property objects in the `def-interface` node. `parseLawProperty` and `AstEmit.hs` law emission ensure round-trip compatibility.

```json
{
  "kind": "def-interface",
  "name": "Normalizer",
  "methods": [
    { "name": "normalize", "fn_type": { "kind": "fn-type", "params": [{"name": "x", "param_type": {"kind": "primitive", "name": "string"}}], "return_type": {"kind": "primitive", "name": "string"} } }
  ],
  "laws": [
    { "kind": "for-all",
      "bindings": [{"name": "x", "param_type": {"kind": "primitive", "name": "string"}}],
      "body": { "kind": "app", "fn": "=", "args": [
        { "kind": "app", "fn": "normalize", "args": [{ "kind": "app", "fn": "normalize", "args": [{ "kind": "var", "name": "x" }] }] },
        { "kind": "app", "fn": "normalize", "args": [{ "kind": "var", "name": "x" }] }
      ] }
    }
  ]
}
```

Omitting `:laws` is valid — interfaces without laws parse and compile unchanged.

> [!NOTE]
> **Cross-module contract metadata.** `ModuleEnv` stores per-function
> contract metadata via `meContracts :: Map Name ([(Name, Type)], Contract, Maybe Type)`,
> populated from `buildModuleEnv`. This enables cross-module compositional verification
> and obligation reports that reference imported contracts. See the
> [`CHANGELOG.md`](CHANGELOG.md) for when this shipped.

### 8.9 `llmll-hub` Registry

The `hub.` import prefix resolves modules from the local `llmll-hub` cache (`~/.llmll/modules/`). Fetch packages with:

```bash
llmll hub fetch llmll-crypto@0.1.0
```

Import syntax:

```lisp
(import hub.llmll-crypto.hash.bcrypt (interface [
  [bcrypt-hash (fn [raw: string] -> bytes[64])]
]))
```

The `hub.` prefix prevents local files from accidentally shadowing registry packages. Publishing, semantic versioning beyond `major.minor.patch`, and a web registry API are deferred (not version-pinned).

Modules declared in `llmll-hub` include verified proof metadata and are importable by name. Third-party modules must be explicitly wrapped (§7).

> [!NOTE]
> Hub-cached modules (both `.llmll` and `.ast.json`) inherit the invoking command's
> grammar mode per §8.2. Hub publishers must ship `def`/`def-shell` node kinds.

---

## 9. IO & Side Effects: The Command/Response Model

`llmll` uses a strictly functional approach to IO. **Logic functions never perform side effects.** Instead, they return `Command` values that *describe* the intended effect. The runtime executes these commands and feeds the result back as the next `Input`.

### 9.1 The Core Pattern

Every logic function that interacts with the world follows this signature:

```
(State, Input) -> (NewState, Command)
```

The AI's logic is pure. The runtime is the only actor that touches the OS.

```lisp
(def-shell handle-request [state: AppState request: string]
  (if (string-contains request "/valid")
      (pair (update-state state) (wasi.http.response 200 "OK"))
      (pair state                (wasi.http.response 400 "Bad Request"))))
```

### 9.2 Constructing Commands

Commands are constructed by calling **capability-namespaced constructor functions** (see §13.9 for the full list). These are qualified identifiers — they use dot notation and require the matching `import` declaration.

```lisp
;; Must have: (import wasi.io (capability stdout ...))
(wasi.io.stdout "Game initialized.\n")   ;; : Command

;; Must have: (import wasi.http (capability serve 8080))
(wasi.http.response 200 "OK")           ;; : Command

;; Must have: (import wasi.fs (capability write "/data"))
(wasi.fs.write "/data/log.txt" content) ;; : Command
```

Commands can be stored in `let` bindings and passed as values. They are opaque — you cannot pattern-match on a `Command` or inspect its fields.

### 9.3 Sequencing Multiple Commands (`seq-commands`)

If a single logic step must emit multiple side effects, use `seq-commands` to compose them into a single `Command`:

```lisp
(def-shell log-and-respond [state: AppState req: HttpRequest]
  (let [(log-cmd  (wasi.io.stderr "Request received"))
        (resp-cmd (wasi.http.response 200 "OK"))]
    (pair state (seq-commands log-cmd resp-cmd))))
```

`seq-commands` executes its arguments in order (left then right). It can be nested for three or more commands:

```lisp
(seq-commands cmd1 (seq-commands cmd2 cmd3))
```

**`seq-commands` is discard-left on the response channel.** A composed command performs both effects but yields only the **right** operand's `Response` (§9.7); the left operand's is overwritten. This follows from the composition being `a >> b`. A step that needs the left command's result must return that command alone and consume its response on the next turn.

### 9.4 Runtime Execution Loop

The LLMLL host runtime processes each `Command` as follows:

1. **Execute** the physical IO via the OS.
2. **Feed** the outcome back to the logic as a `Response` (§9.7), which the next `:step` receives as its third argument. `wasi.fs.read` yields the file's contents as `RText`, and an IO failure yields `RErr` rather than raising.

> [!IMPORTANT]
> **Authority is checked at compile time, not here.** Two steps that earlier revisions of this section described are **not implemented**, and the runtime performs neither. There is no runtime permission check and no `CapabilityError`: `CodegenHs` emits no capability code at all. There is no guarded mode and no interception of sensitive commands such as `wasi.fs.delete`. What the compiler does enforce is described in §7, and it is narrower than that section long claimed. This gap is tracked as `CAP-1-REAL` in [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md).

### 9.5 Entry Point Declaration (`def-main`)

`def-main` declares the program's runtime harness — how the compiled executable starts, reads input, and terminates. Without a `def-main`, the compiler generates a **library only** (no `Main.hs`).

#### Syntax

```lisp
(def-main
  :mode    (console | cli | http PORT)   ;; required, selects the harness template
  :init    init-expr                      ;; returns (State, Command) pair
  :step    step-fn                        ;; console: (State, string, Response) -> (State, Command)
  :done?   done-pred                      ;; State -> Bool (optional; console only)
  :on-done on-done-fn                     ;; State -> Command (optional)
  :status  status-fn)                     ;; State -> int (optional; console only)
```

Fields are parsed in the order shown. Every optional field is read sequentially, so a `def-main` that
writes `:on-done` ahead of `:done?`, or `:status` ahead of `:on-done`, does not parse.

A console `:step` takes **three** parameters. Declaring two, one, or a wrong third type is rejected with `def-main-step-arity`. The `cli` and `http` harnesses perform no command and so deliver no response; their `:step` is unchanged at `(State, string) -> (State, Command)`.

#### Modes

| Mode | Harness behaviour |
|------|-------------------|
| `console` | Interactive loop: `:init` creates state + welcome message, then loops on stdin calling `:step` until `:done?` returns `true`. When `:on-done` is also declared, it is called with the final state when `:done?` becomes `true` — before the loop exits. |
| `cli` | Single-shot: reads OS args, calls `:step` once, prints result. |
| `http PORT` | HTTP server on `PORT`: `:init` creates initial state, each request calls `:step`. |

#### Key semantics

- `:init` must return a `(State, Command)` pair. The `Command` is executed (e.g., print welcome message), and the `State` is passed to the first `:step` call.
- `:step` receives the current state and one line of input (for `console`) or the OS args (for `cli`). It must return a `(NewState, Command)` pair.
- `:done?` (optional, console only) receives the new state after each step. If it returns `true`, the loop exits.
- `:status` (optional, console only) is a **total projection from the state type to `int`**. It is applied to the final state when `:done?` holds, and the process exits with the result. Absent means exit 0. It is **not** consulted when stdin exhausts first; see "The terminal status" below.
- The `Command` returned by `:step` is executed directly as an IO action (it is **not** printed or shown).

#### Complete example

```lisp
(def-main
  :mode console
  :init (start-game "hangman")
  :step game-loop
  :done? is-game-over?)
```

#### The `:on-done` hook, and the terminating step

> [!IMPORTANT]
> **`:on-done` is the canonical place to print end-of-game messages**, and since RC-4 it is the
> *only* place that works.

**The terminating step's command is not performed.** The harness evaluates `:done?` on the state a
step produced, and when it returns `true` the loop settles without performing that step's `Command`:

1. `:step` runs and returns `(state', cmd)`.
2. The harness checks `:done?` on `state'`. If `true`, `cmd` is **discarded**, `:on-done` is called,
   and the loop exits.
3. Otherwise `cmd` is performed, its `Response` is delivered to the next `:step` (§9.7), and the loop
   continues.

This is what makes the response channel well defined: a response can only be delivered to a step that
runs, and no step runs after the terminating one, so performing its command would produce a response
with nowhere to go.

The consequence for output is direct. A `:step` that renders the final board on the turn that ends
the game renders nothing at all, because that turn's command is the one discarded. **Terminal output
for the final state must move into `:on-done`.**

```lisp
;; Anti-pattern: game-loop renders the final board as part of its own Command.
;; That command belongs to the terminating step, so it is discarded and the
;; board is never printed.
(def-main
  :mode console
  :init (start-game "hangman")
  :step game-loop           ;; renders board AND "You won!" on the winning turn
  :done? is-game-over?)

;; Canonical pattern: game-loop renders only on turns that continue.
;; show-result renders the final state exactly once, after the loop settles.
(def-main
  :mode console
  :init   (start-game "hangman")
  :step   game-loop         ;; renders the board on every non-final turn
  :done?  is-game-over?
  :on-done show-result)     ;; renders the final board and "You won!" / "Game over!"
```

`show-result` has signature `State -> Command`. It is called with the final state immediately before
the loop exits. Output produced by `:on-done` appears **after** the last performed `:step` command
and **exactly once**, regardless of how many times `:done?` is checked.

> [!WARNING]
> Before this rule, the terminating step's command *was* performed, and the hazard this section
> described was the opposite one: a final message rendered twice. Programs written against that
> behavior lose their last render rather than duplicating it. The four game examples under
> `examples/` have not yet been repaired and are known to be affected.

#### The terminal status (`:status`), and the two terminal paths

A console program has two ways to stop, and the harness does **not** treat them alike. `:status` is a
total projection from the state type to `int`, applied on one of them.

| `:done?` | Terminal path | Behaviour |
|---|---|---|
| declared | it holds | `:status` is applied to the final state and the process exits with the result. `:status` absent means exit **0** |
| declared | stdin exhausts first | The process exits a fixed, disclosed **70**. **`:status` is not consulted** |
| not declared | stdin exhausts | The process exits **0**. Normal termination |

**The discriminator is whether `:done?` is declared, not whether it fired.** A program that declares
no completion predicate can never signal completion, so exhaustion is its only terminal path, and for
such a program EOF is the normal end of input rather than starvation. Gating on firing would make
every run of a stream processor exit 70, a false alarm on a successful run. Gating on declaration
keeps the guarantee exactly where it means anything: **no program that declares a completion
predicate can exit 0 without reaching it**, whatever its state type.

**Exhaustion is a harness-level condition, which is why `:status` cannot report it.** A projection
from state alone cannot distinguish a run that completed every stage from one whose input ran out,
because the distinguishing information lives in `:done?`, a predicate *outside* the state. Asking the
program to score a state it does not consider terminal is asking it to describe a condition it has no
knowledge of. The harness knows; the program does not. The cost is disclosed rather than hidden: see
"70 is not reserved" below.

**Declare the range on the named function's contract. The compiler injects nothing.** A POSIX exit
status is the low 8 bits of the value, so the useful range is `0..255`:

```lisp
(def exit-status [s: RunState] -> int
  (post (and (>= result 0) (<= result 255)))
  (if (all-stages-passed? s) 0 2))
```

With that postcondition the obligation is ground QF-LIA and liquid-fixpoint discharges it
automatically (§5.3.3). Without it, nothing constrains the projection: a `:status` returning 300
truncates to 44, and one returning 256 exits **0 and reports success**. The refinement is the only
thing standing between the program and that outcome, and it binds only where it is written.

`llmll check` warns in three cases, none of them an error: `:status` declared on a `cli` or `http`
mode, which perform no `Command` and have no terminal state to project; `:status` declared with no
`:done?`, where the settle path is unreachable and the projection is dead code (the author asked for
an exit status and will silently get 0 on every run); and a named function whose return position is
not `int`.

**70 is not reserved from the program.** A `:status` may return 70 deliberately, so a shell can tell
that neither outcome is success but cannot separate exhaustion from a deliberate 70. Reserving it was
considered and rejected: it buys a distinction nothing currently needs, at the cost of a hole in an
otherwise total `0..255` range.

One consequence worth stating separately, because effects have already happened when it fires. The
harness performs `:init`'s command **before** the loop's first end-of-input test, so a program
invoked with argv and an empty stdin acquires its arguments, performs whatever `:init` commands, and
terminates without a single `:step`. Where `:done?` is declared that exits 70, correctly: the program
never reached a state it considers terminal. It is the one path where a nonzero status coexists with
completed side effects.

In JSON-AST:

```json
{
  "kind": "def-main",
  "mode": "console",
  "init": { "kind": "app", "fn": "start-game", "args": [{"kind": "lit-string", "value": "hangman"}] },
  "step": { "kind": "var", "name": "game-loop" },
  "done?": { "kind": "var", "name": "is-game-over?" }
}
```

The optional fields carry their surface names, minus the leading colon: `init`, `done?`, `on-done`,
and `status` (`schemaVersion` 0.11.0; a `def-main` that declares no `:status` emits no `status` key
and round-trips byte-identically).

### 9.6 `do`-notation State Threading

For complex sequences of actions that thread a state and accumulate commands, LLMLL provides a monadic `do`-notation block as a cleaner alternative to deeply nested `let` and `seq-commands`.

```lisp
(def-shell process-turn [state: GameState]
  (do
    [s1 <- (action1 state)]
    [s2 <- (action2 s1)]
    (action3 s2)))
```

#### Semantics

- **State threading enforced:** Every step inside a `do`-block must evaluate to exactly `(S, Command)`. The type `S` must be strictly identical across all steps in the block.
- **Named vs. Anonymous steps:** A named step `[s1 <- (expr)]` binds the state component of `expr`'s result to `s1` for subsequent steps. An anonymous step `(expr)` simply discards the state component and threads exactly the identical state. 
- **Compilation:** The `do` block is compiled directly into a pure `let` chain. No Haskell `do` or monads are emitted, ensuring soundness in `def`/`def-shell` pure contexts. Each step's `(State, Command)` pair is destructured via `let`; the final result is `(lastState, lastCommand)`.
- **Called functions need an explicit return-type annotation to be usable in a step.** Type inference for `do`-steps works in synthesis mode per step rather than resolving through unification: calling an unannotated `def`/`def-shell` function (no `-> RetType`) as a step infers `?` for its result and fails with `do-step-type-error`, even though the identical call outside a `do`-block, or with an explicit `-> (S, Command)` on the callee, type-checks fine. Give every function called from inside a `do`-block an explicit return-type annotation.
- **A dropped intermediate command must be declared (DISCARD-1).** A non-final step's `Command` component is bound but not executed. Because that is a surprise relative to monadic `do`-notation in other languages, where the point of sequencing is to execute effects in order, dropping one is an **error** unless the step carries an explicit `:discard` marker. **In LLMLL `def`/`def-shell`, effects are values, not statements; sequencing them is the agent's explicit responsibility.** The three ways to write a non-final step are: wrap the command in `seq-commands` (see §9.3) so it reaches the block's result, return it in the final tuple, or mark the step `:discard` to state that dropping it is intended. Code that looks effectful can no longer silently drop effects; it either sequences them or says it is discarding them.

  ```lisp
  (do
    [s1 <- (pair s0 (wasi.io.stdout "a")) :discard]
    (pair s1 (wasi.io.stdout "b")))
  ```

  The marker rides the **bracketed** step form only. A step that wants to discard its command and does not need the state binding writes `[_ <- (expr) :discard]`. It is rejected on a **final** step, whose `Command` is the block's result and is therefore never dropped.

  Note that the two discards a step can perform are orthogonal and both are explicit: omitting the binder (`(expr)` rather than `[s <- (expr)]`) discards the **state** component, and `:discard` declares that the **command** component is dropped.

> [!WARNING]
> Using an anonymous step `(expr)` when `expr` returns a new state will result in **state-loss**. The bound state from prior steps is retained, but the updated state from `(expr)` is discarded. Always use named steps `[s <- (expr)]` to thread modified states properly.


---

### 9.7 The Response Channel

A `Command` carries an effect. A `Response` carries what performing it produced. Together they close
the loop: a console program can read a file, receive its contents, and branch on them, without any
function ever performing IO.

`Response` is a builtin sum type with five arms:

| Arm | Payload | Produced by |
|-----|---------|-------------|
| `RNone` | none | a command with no observable result (`wasi.io.stdout`, `wasi.io.stderr`) |
| `RText string` | the text produced | `wasi.fs.read` |
| `RCode int` | a numeric outcome | operations whose result is a status or code |
| `RErr string` | the failure message | any command whose IO failed |
| `RList list[string]` | the entries produced | `wasi.fs.list`, `wasi.proc.args` |

```lisp
(def-shell read-step [s: int input: string r: Response] -> (int, Command)
  (match r
    ((RNone)     (pair s (wasi.fs.read "/tmp/data")))
    ((RText t)   (pair (string-length t) (wasi.io.stdout t)))
    ((RErr e)    (pair s (wasi.io.stderr e)))
    ((RCode n)   (pair n (wasi.io.stdout "")))
    ((RList ns)  (pair (list-length ns) (wasi.io.stdout "")))))
```

**Delivery rules.**

- **One response per performed command.** A step receives the response to the command *it* returned
  on the previous turn, never a stale one. The response slot is cleared before each command is
  performed and read after.
- **`:init` supplies the first response.** The command in `:init`'s `(State, Command)` pair is
  performed like any other, and its response reaches the first `:step`. A program with no `:init`
  starts at `RNone`.
- **`seq-commands` is discard-left.** A composed command yields the right operand's response (§9.3).
- **The terminating step's command is not performed**, so it produces no response (§9.5).

**Arms classify shape, not provenance.** `Response` says what kind of value came back, not which
command produced it. `RCode` therefore carries HTTP statuses, process exit codes, and clock readings
alike, and a program that needs to know which of several commands a response belongs to records that
in its own state, where the coupling is visible in the program's type rather than implicit in the
harness. An arm is admissible when it names a payload *shape* that no existing arm can carry; naming
an arm after the capability that produced it is not admissible.

**Bulk payloads travel through the filesystem, not through an arm.** An operation whose result is
large writes it to a path and returns the path, which keeps the arm set small at the cost of leaving
that payload out of the event log. That cost is accepted deliberately and is tracked as
`REPLAY-INJECT` in [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md).

> [!NOTE]
> Matching on `Response` is outside the body-faithful verification fragment, exactly as matching on
> any payload-carrying sum type is (§5.3.5). A `def` that matches on it falls back to contract-only
> verification. This is a pre-existing Σ_auto boundary rather than anything specific to `Response`.

## 10. Compilation & Execution Pipeline

The pipeline accepts two source formats: S-expressions (`.llmll`) and JSON-AST (`.ast.json`).

1. **AI Implementation:** LLM generates `.llmll` S-expressions *or* `.ast.json` (preferred for AI agents — schema-constrained, structurally valid by construction).
2. **Parse & Semantic Check:** Compiler parses the source, verifies types and immutability, catalogs all `?holes`. Reports structured JSON diagnostics with RFC 6901 JSON Pointers to offending AST nodes. `llmll holes --json` lists all unresolved holes.
3. **Human/Lead-AI Review:** Holes and sensitive `Command` effects (e.g., `wasi.fs.delete`) are resolved/approved via Chat/CLI.
4. **Transpilation:** Validated `.llmll` is converted to **Haskell** (`.hs` + `package.yaml`). Generated modules are compiled with `{-# LANGUAGE Safe #-}`, preventing any IO outside the declared capability model.
5. **Binary Generation:** `ghc` compiles the generated Haskell to a native binary.
6. **Contract & Property Testing:** The test runner executes `pre`/`post` runtime assertions and `check`/`for-all` QuickCheck blocks against the running binary. Failures are reported as JSON diagnostics.
7. **Sandboxed Execution:** The binary runs inside a Docker container with `seccomp-bpf` syscall filtering and filesystem/network policies derived from the module’s declared capabilities. WASM-WASI is planned as a future replacement.
8. **Event-Log Replay:** The runtime records a sequenced Event Log of `(Input, CommandResult, captures)` triples (see §10a). Replay is bitwise deterministic for all modules that use `:deterministic true` capability flags on clock and PRNG imports.



---

## 10a. Event Log Specification

Correct replay is the foundation of fault tolerance, audit trails, and SMT proof validation over execution traces.

### Sources of Non-Determinism

| Source | Problem | Runtime Fix |
|--------|---------|-------------|
| **IEEE 754 floats** | NaN canonicalization differs across host platforms | Reject non-canonical floats at the sandbox boundary (GHC NaN rules; `wasm-determinism` extension with WASM target) |
| **Monotonic clock** | Wall-clock calls diverge across replay runs | Virtualize via `:deterministic true`; log return value |
| **PRNG** | Non-seeded random generation diverges on replay | Log seed + call sequence; replay re-seeds from log |

### The `:deterministic` Capability Flag

```lisp
(import wasi.clock  (capability monotonic-read :deterministic true))
(import wasi.random (capability get-bytes      :deterministic true))
```

> **Known compiler bug (parser, fix in progress).** `get-bytes` currently fails to parse — see the note at its first occurrence above (§10, Capability Imports).

When `:deterministic true` is set, the runtime **captures the return value** of every call and appends it to the Event Log. On replay, these calls **read from the log** instead of invoking the real system call.

### Event Log Format

```lisp
(event
  :seq      42
  :input    (http.request GET "/checkout")
  :result   (http.response 200 "OK")
  :captures [(wasi.clock.monotonic 1741823200000)
             (wasi.random.bytes #x4f2a...)])
```

Replay feeds each `:input` to the logic in order. `:result` and `:captures` are injected directly, bypassing real system calls.

### Replayability Status

| Condition | Compiler Status |
|-----------|----------------|
| All non-deterministic capabilities use `:deterministic true` | ✅ **replayable** |
| Any non-deterministic capability without `:deterministic true` | ⚠️ **best-effort replay** |

---

## 11. Multi-Agent Concurrency (The Swarm Model)

`llmll` is designed to be written concurrently by a swarm of specialized AI agents. The language enforces a strict semantic division of labor to prevent hallucination propagation and merge conflicts.

### 11.1 Interface-First Compilation (The Treaty)

Before concurrent development begins, a Lead AI (or Human) defines the boundaries using `def-interface`. This establishes a contract all agents must adhere to.

```lisp
(def-interface AuthSystem
  [hash-password (fn [raw: string] -> bytes[64])]
  [verify-token  (fn [token: string] -> bool)])
```

In `def-interface`, parameter names in `fn-type` are **optional and documentation-only**. Both of the following are equivalent and valid:

```lisp
;; Named parameters (preferred: documents intent clearly)
[hash-password (fn [raw: string] -> bytes[64])]

;; Anonymous parameters (also valid)
[hash-password (fn [string] -> bytes[64])]
```

Once the interface is compiled, Agent A can implement the internal logic while Agent B concurrently writes the API that consumes it. The compiler guarantees structural compatibility.

### 11.2 Hole Delegation

A `?hole` does not always require human intervention. An AI can delegate a sub-task to a specialized agent while continuing to build the rest of its module.

#### Built-in Failure Type

`DelegationError` is a pre-declared sum type. All delegations may produce it:

```lisp
(type DelegationError
  (| AgentTimeout    unit)  ;; Agent did not respond within the runtime deadline
  (| AgentCrash      unit)  ;; Agent returned an error signal
  (| TypeMismatch    unit)  ;; Agent returned a result incompatible with the declared type
  (| AgentNotFound   unit)) ;; Named agent is unavailable
```

#### Blocking Delegation

`?delegate` requires an explicit `-> ReturnType` annotation. An optional `(on-failure ...)` clause provides a fallback:

```lisp
(def-shell login-route [req: HttpRequest fallback-hash: bytes[64]]
  (let [[password  (get req :pass)]
        [hashed-pw (?delegate @crypto-agent
                     "Implement secure PBKDF2 hashing"
                     -> bytes[64]
                     (on-failure fallback-hash))]]
    (db.insert user hashed-pw)))
```

The `(on-failure e)` side condition (`Γ ⊢ e : T`) requires `e` to already be a value of the delegate's return type — `bytes[64]` has no literal syntax in LLMLL, so a realistic fallback is a value threaded in from the caller (here, `fallback-hash`), not a literal constructed inline. `(err DelegationError)` would type as `Result[?, DelegationError]`, not `bytes[64]`, and is rejected.

Without `(on-failure ...)`, an unresolved delegation becomes a `?delegate-pending` hole — analyzable but not executable:

```lisp
hashed-pw (?delegate @crypto-agent "Implement PBKDF2 hashing" -> bytes[64])
;; Compiler: ?delegate-pending [type: bytes[64]] [agent: @crypto-agent]
```

#### Async Delegation

`?delegate-async` returns `Promise[t]` immediately and continues. The module runtime resolves the promise when the agent completes.

`return_type` is the inner type `T`, not `Promise[T]`. The compiler wraps it in `Promise[T]` automatically. A top-level `Promise[...]` in `return_type` is stripped as a legacy compatibility measure. `Promise[Promise[T]]` is a parse error.

**`await` returns `Result[t, DelegationError]`, not bare `t`.** The generated code wraps `Async.wait` in exception handling so that agent failures (crash, timeout, type mismatch) are captured as `Error` values carrying a `DelegationError` payload (constructed via `(err …)`; see §13.8) rather than propagating as uncaught exceptions. This preserves the LLMLL invariant that logic functions cannot crash from IO.

**Inference rules:**

```
?delegate @A "desc" -> T                    ⊢  T
?delegate @A "desc" -> T (on-failure e)     ⊢  T,  given Γ ⊢ e : T
?delegate-async @A "desc" -> T              ⊢  Promise[T]
await e : Promise[T]                         ⊢  Result[T, DelegationError]
```

The `(on-failure e)` rule's `Γ ⊢ e : T` side condition is enforced by `compiler/src/LLMLL/TypeCheck.hs` `inferHole HDelegate`. Ill-typed fallbacks (e.g., a `string`-returning fallback on an `int`-returning delegate) produce a typecheck error.

**Delegate return type vs interface method signature.** The `?delegate ... -> T` return type is determined at the delegation site, not by any `def-interface` method the agent identifier might also satisfy. A `def-interface` declares the agent's contract surface; a `?delegate` is a placeholder for a value of type `T` to be supplied at the delegation site. The two are linked by the agent identifier (`@agent-name`), not by syntactic return-type equality — the agent may produce a `T` shaped differently than any specific interface method's signature, and the typechecker checks only the local `?delegate -> T` and the `Γ ⊢ e : T` side condition on the fallback.

**JSON-AST `agent` field convention.** In JSON-AST, the `agent` field of `hole-delegate` / `hole-delegate-async` stores the **bare agent identifier without the `@` sigil**. The `@` is surface S-expression syntax (and `llmll holes` display-time rendering); it is not part of the stored identifier in the typed AST or the JSON. Example: surface `?delegate @crypto-agent ...` corresponds to JSON-AST `"agent": "crypto-agent"`.

```lisp
(def-shell build-report [state: AppState data: ReportData]
  (let [[chart-future (?delegate-async @viz-agent
                         "Render a bar chart from data"
                         -> ImageBytes)]]
    (let [[chart-result (await chart-future)]]
      (match chart-result
        ((Success img) (pair state (wasi.http.response 200 img)))
        ((Error err)   (pair state (wasi.http.response 500 "Agent failed")))))))
```

> [!IMPORTANT]
> **Type of `await`:** `await : Promise[t] -> Result[t, DelegationError]`. The type checker infers `Result[t, DelegationError]` for any `(await expr)` where `expr : Promise[t]`. An un-`await`ed `Promise[t]` remains `Promise[t]`.



#### Delegation Outcome Table

| Scenario | Compiler Result |
|----------|----------------|
| Delegation succeeds, type matches | AST node replaced with implementation |
| Delegation succeeds, type mismatch | Compile error: `TypeMismatch` |
| Agent unavailable, `on-failure` provided | Fallback expression inserted |
| Agent unavailable, no `on-failure` | `?delegate-pending` hole — blocks execution |
| `?delegate-async`, agent succeeds | `await` returns a `Success` value (matched as `(Success v)`) |
| `?delegate-async`, agent fails | `await` returns an `Error` value carrying `DelegationError` (matched as `(Error e)`) |

#### Hole Resolution via JSON-Patch

`?delegate` holes can be resolved programmatically by agents through the **checkout/patch lifecycle**. This is the primary agent-coordination mechanism for filling holes without human intervention.

**Workflow:**

1. **Checkout.** An agent calls `llmll checkout <file.ast.json> <pointer>` to lock a hole. The compiler validates the RFC 6901 pointer resolves to a `hole-*` node, creates a lock entry in `.llmll-lock.json`, and returns a checkout token. The lock has a 1-hour TTL; stale locks are auto-expired.

2. **Patch.** The agent submits an RFC 6902 JSON-Patch wrapped in an LLMLL envelope containing the checkout token and patch operations:

```json
{
  "token": "a1b2c3d4...",
  "patch": [
    { "op": "test",    "path": "/statements/2/body", "value": { "kind": "hole-delegate", ... } },
    { "op": "replace", "path": "/statements/2/body", "value": { "kind": "lit-int", "value": 42 } }
  ]
}
```

3. **Re-verify.** The compiler applies the patch to the JSON-AST, re-parses, re-typechecks, and — if the function carries contracts — re-verifies via SMT (`emitFixpoint` + `liquid-fixpoint`). If the patch introduces a type error, the result is `PatchTypeError` with diagnostic pointers referencing the patch operation (e.g., `patch-op/1/body` instead of `/statements/2/body`). If the patch violates a contract, the result is `PatchVerifyError` with SMT diagnostics. If `liquid-fixpoint` is not installed, the patch proceeds on typecheck success alone (graceful degradation).

4. **Commit or reject.** On success (`PatchSuccess`) the updated `.ast.json` is written and the lock is cleared. On failure (`PatchTypeError`, `PatchVerifyError`, `PatchApplyError`, `PatchAuthError`) the original file is unchanged and the lock is preserved for retry.

**Scope containment:** All patch operations must target nodes within the checked-out subtree. A token for `/statements/2/body` cannot be used to modify `/statements/0/body` — this prevents lateral hole theft between agents.

**Supported RFC 6902 operations:** `replace`, `add`, `remove`, `test`. The `test` operation is the agent's guard against stale patches — it asserts that the hole hasn't been modified since checkout.

**CLI commands:**

| Command | Purpose |
|---------|---------|
| `llmll checkout <file.ast.json> <pointer>` | Lock a hole, get token |
| `llmll checkout --release <file> <token>` | Explicitly abandon a checkout |
| `llmll checkout --status <file> <token>` | Query remaining TTL |
| `llmll patch <file.ast.json> <patch.json>` | Apply patch + re-verify |
| `llmll refine <file.ast.json> <refine.json>` | Fill a hole + spawn contracted sub-holes, atomically |

**HTTP endpoints** (via `llmll serve`): `POST /checkout`, `POST /checkout/release`, `POST /patch` — governed by the same bearer token auth as `POST /sketch`.

> Checkout requires `.ast.json` input. S-expression sources are rejected with: `"checkout requires .ast.json input; run 'llmll build --emit json-ast' first"`. Patches are restricted to hole-filling; `refine` (below) is the one bounded extension — general AST mutation is planned for a future release.

**The `refine` op — cascading decomposition.** `refine` is the dual of `patch`: one request installs a checked-out hole `H`'s body **and** adds new top-level contracted defs `Gᵢ` (each with a `?body`) that the body references, atomically, reusing the `patch` lifecycle (staleness compare-and-swap + assume-guarantee re-verify). `H` verifies *modulo* each `Gᵢ`'s contract; each `Gᵢ` becomes a new frontier hole — decomposition grows top-down instead of being authored up front. A **scope-relaxation safety predicate** bounds the op: a spawned def must be introduced by exactly one body-replace plus additive `add /statements/-` ops, **fresh** (name unbound), **body-referenced** by the fill, and hole-bodied. A **feasibility (no-miracle) gate** — running before the vacuity gate — rejects a spawn whose invented sub-contract *no* body can discharge (some input satisfies `pre` with no `result` satisfying the post, `∃input. pre ∧ ∀result. ¬post`), reported with a minimal witnessing input; z3-discharged under the `qsat` tactic (complete for quantified LIA), fail-open outside the decidable Int/Bool fragment and without z3 (`LLMLL.Feasibility`). A **CDP vacuity gate** rejects a spawn whose invented sub-contract a trivial identity/constant/projection body already satisfies. Each spawned sub-contract also carries an advisory `reuse_suggestions` list — in-scope defs whose contract *subsumes* it (contract subtyping `preₛ ⟹ pre_D ∧ post_D ⟹ postₛ`, α-normalized, solver-checked) — plus a non-blocking `W-REUSE` warning on an exact contract-equivalent; reuse retrieval never rejects a refine. Demo: `examples/refine-demo/`.

#### Context-Aware Checkout

`llmll checkout` returns the **local typing context** alongside the lock token. This is the single highest-impact feature for agent first-attempt accuracy — agents need not infer what’s in scope from surrounding AST context.

The checkout response includes four optional fields (present when the compiler has sketch data for the target hole):

| Field | Type | Content |
|-------|------|---------|
| `in_scope` | `[ScopeEntry]` | Bindings visible at the hole site (Γ delta: `tcEnv \ builtinEnv`). Each entry has `name`, `type` (LLMLL notation), and `source` (`param`, `let-binding`, `match-arm`, `open-import`). Sorted by source priority; truncated at 50 entries with `scope_truncated: true`. |
| `expected_return_type` | `string` | The expected type at the hole site (τ as a type label). **Populated** for a function-body hole when the enclosing function declares a return type (`-> RetType`, §4.1) — the body hole records `HoleTyped RetType` — and for a sub-expression hole whose type is fixed by local inference (siblings / surrounding context). Absent when neither applies (e.g. a body hole with no declared return and no inferable context). |
| `available_functions` | `[FuncEntry]` | **Populated** with the contracted-user vocabulary — every same-module `def`/`def-shell` carrying a `pre` or `post`, plus every **imported** exported contracted function under the name this module calls it by (bare when `(open ...)`-ed, qualified otherwise; `status: "imported"`) — and the function whose hole is being checked out marked `status: "hole"` (never `"filled"`) — as `name`, `params` (with types), `returns` / `return_type`, `pre` / `post` / `tier`, and `status`. (The broader vision — the full non-`wasi.*` Σ including builtins, monomorphized against concrete scope types so e.g. `list-head` reads `list[int] → Result[int, string]` when `xs : list[int]` is in scope — is only partly realized: builtins are not yet included.) |
| `type_definitions` | `[TypeDefEntry]` | User-defined types referenced by in-scope bindings. Sum types include constructors; aliases include the base type. Depth-bounded expansion (max 5 levels) with cycle detection (`recursive: true`). |
| `scope_truncated` | `bool` | `true` if the scope was truncated to the 50-entry limit; absent or `false` otherwise. |

**Contract context.** `checkout` also returns the enclosing function's contract context for the hole. Unlike the typing fields above (omitted when absent), these are emitted unconditionally — `null` when the enclosing function lacks the clause:

| Field | Type | Content |
|-------|------|---------|
| `contract_pre` | `string` \| `null` | The enclosing function's precondition as an S-expression (e.g. `(>= balance amount)`). |
| `postcondition_goal` | `string` \| `null` | The postcondition the fill must satisfy (e.g. `(= result (- balance amount))`). |
| `path_condition` | `[string]` \| `null` | Guard expressions on the path to the hole; non-empty only for holes inside `if` / `match` branches. |
| `assumptions` | `[string]` \| `null` | Facts that hold at the hole site, beyond `contract_pre`: the refinement predicate of each in-scope refinement-typed **param**, α-renamed to the binder (`x: PositiveInt` where `PositiveInt ≜ (where [v:int] (> v 0))` → `"(> x 0)"`, resolved through same-file aliases), the **definitional equality** `(= y e)` of each in-scope let-binding whose RHS the emitter can translate (any `Σ_auto` term — QF-LIA, measures, pair/constructor terms, the §5.3.3 array class; a call/opaque RHS is skipped), and the **case hypothesis** of each enclosing match arm on a variable scrutinee (`(= s (Ctor x))`; nullary arm: `(= s Ctor)`), accumulated outermost-first across nested and sequential matches — a binder that shadows a hypothesis's name drops that hypothesis rather than mis-scope it. Sourced strictly from the hole's in-scope binder set and path, so path-correct by construction. Sound but deliberately incomplete: complex scrutinees, wildcard/variable/literal arms, and `def-invariant` axioms are not yet surfaced (the body VC does assume the corresponding facts — a disclosed brief-vs-verifier asymmetry for the remaining provinces). |

These contract fields are assembled from a parse + sketch type-check (no constraint emission, no solver), so `checkout` stays at type-check cost. The whole-program view of the same obligations — across every hole, unproven contract, call-site failure, and `refuted_fns` — remains `llmll verify --obligation-report`.

**Effect summary.** `verify --obligation-report` additionally emits a top-level `effect_summary` — a per-function, sound *over-approximation* of the coarse capabilities each function may reach through its call graph — **composed across module imports**, so an imported function's reachable capabilities propagate into its caller's summary: a sorted array of labels (`stdout`, `fs.read`, `fs.write`, `net.http`, `nondet`, `crypto`) or `"unbounded"` (⊤ — may exercise any capability) at opaque boundaries (`?delegate`/`?scaffold` holes, `haskell.*`/`c.*` FFI, calls into a module not loaded, and `wasi.proc.run`, which runs an arbitrary program and can therefore reach anything the catalog names and more). It is **informational** and orthogonal to trust — it never affects a function's trust tier or verification verdict. The report's `cross_module` field is `"supported"` when imports are loaded, else `"single-file"`. `effect_summary` arrived at obligation-report `schema_version` `0.12.0`. See [`docs/archive/shipped-design-specs/bundle-b0-effect-summary-proposal.md`](docs/archive/shipped-design-specs/bundle-b0-effect-summary-proposal.md).

**Pointer normalization:** RFC 6901 pointer segments with leading zeros are normalized: `/statements/02/body` → `/statements/2/body`.

**Monomorphization:** Polymorphic signatures in `available_functions` are rewritten against concrete types found in the scope. This is a presentation-only transformation — the underlying `builtinEnv` is not mutated.

**Scope truncation:** When the in-scope binding count exceeds the limit, entries are retained by source priority: `param` > `let-binding` > `match-arm` > `open-import`. Shadowing safety is structurally guaranteed by the single-entry-per-key invariant of the scope map.

### 11.3 AST-Level Merging (Semantic Source Control)

> [!WARNING]
> **Designed, not yet implemented.** The following describes planned behavior for a future release. The current compiler does not implement AST-level merging beyond the JSON-Patch hole-filling pipeline of §11.2.

The design envisions that `llmll` will bypass text-based merge conflicts by operating exclusively on the AST:

- **Concurrent additions:** Agent A adds a function + Agent B adds a type → the compiler will merge tree nodes seamlessly.
- **Logical conflicts:** Two agents redefine the same node incompatibly → the compiler is designed to generate a `?conflict-resolution` hole and flag the Lead AI. No `<<<< HEAD` markers.

The current module system provides `mergeModuleEnvs` (name unification across imports) and `mergeCS` (evidence-record reconciliation) in [`Module.hs`](compiler/src/LLMLL/Module.hs), but there is no `?conflict-resolution` hole generator or general AST-merge mechanism.

### 11.4 Global Module Invariants (`def-invariant`)

> [!WARNING]
> **Parses on both surfaces; invariant *enforcement* not yet implemented (Phase 2b).** `def-invariant` produces its own `SDefInvariant` AST node — a first-class node, not a reduction to `SDefLogic`. It parses from **both** JSON-AST and S-expression source (the `(def-invariant …)` form landed in the S-expression parser in v0.12.1, `Parser.hs`), is type-checked, and registers as a logic predicate in the VC environment. What is **not** implemented is enforcement: Z3 verification, on AST merge, that declared invariants are preserved (Phase 2b). A `def-invariant` in `.llmll` source is accepted but has no invariant-enforcement effect.

A module can declare invariants that must hold over its state at all times. The example below is **illustrative, not runnable**: `sum`, `map-values`, `state-accounts`, and `state-total-supply` are not registered builtins or defined functions — they sketch the intended vocabulary of a future map-capable invariant surface (the data-scope extension track):

```lisp
(def-invariant balance-conservation [state: LedgerState]
  (= (sum (map-values (state-accounts state)))
     (state-total-supply state)))
```

This is the S-expression form (§12); it parses today (v0.12.1+) and produces a real `SDefInvariant` node — though this particular example additionally references undefined helpers (`sum`, `map-values`, …), so it type-checks only once those are defined. The equivalent JSON-AST:

```json
{ "kind": "def-invariant", "name": "balance-conservation",
  "param": { "name": "state", "param_type": { "kind": "named", "name": "LedgerState" } },
  "body": { "kind": "app", "fn": "=", "args": [
    { "kind": "app", "fn": "sum", "args": [{ "kind": "app", "fn": "map-values", "args": [
      { "kind": "app", "fn": "state-accounts", "args": [{ "kind": "var", "name": "state" }] } ] }] },
    { "kind": "app", "fn": "state-total-supply", "args": [{ "kind": "var", "name": "state" }] } ] } }
```

The design intent is that after any AST merge, the compiler will run Z3 verification of all declared invariants. A merge that breaks a global invariant would be rejected before it can produce runnable code. This is not yet implemented — the `def-invariant` form is accepted by the parser but has no runtime or verification effect.

---

## 12. Formal Grammar Reference

The grammar is given in EBNF. `{ x }` means zero or more `x`. `[ x ]` means optional `x`. `( x | y )` means a choice. Terminals are in `"double quotes"`. All source files must be **ASCII-only**.

```ebnf
(* ============================================================ *)
(* Top-level structure                                           *)
(* ============================================================ *)
program     = { statement } ;
statement   = type-decl | gen-decl | weakness-ok | def | def-shell
            | def-interface | def-invariant | def-main | module-decl | import
            | open-decl | export-decl
            | trust-decl
            | check | expr ;
              (* def / def-shell are the definition forms (GrammarCoreInversion,
                 the default). def-logic is rejected under
                 all grammar modes (removed-construct diagnostic + exit non-zero,
                 no auto-rewrite). letrec is available only under --grammar=legacy
                 (core-grammar-violation under --grammar=core-inversion).        *)

(* ============================================================ *)
(* Module                                                        *)
(* ============================================================ *)
module-decl = "(" "module" IDENT { import } { statement } ")" ;

(* ============================================================ *)
(* Imports                                                       *)
(* ============================================================ *)
import      = "(" "import" qual-ident
                [ "(" "capability" STRING { kv } ")" ]
                [ "(" "interface" { iface-fn } ")" ]
              ")" ;
kv          = ":" IDENT ( STRING | INT | "true" | "false" | IDENT ) ;

(* ============================================================ *)
(* Open and Export *)
(* ============================================================ *)
open-decl   = "(" "open" qual-ident [ "(" { IDENT } ")" ] ")" ;
              (* (open foo.bar)           — all exports into scope without prefix *)
              (* (open foo.bar (f g))     — only f and g are unprefixed           *)
              (* Must appear before any def / def-shell in the same scope.        *)

export-decl = "(" "export" { IDENT } ")" ;
              (* Listed names become the module's public interface.               *)
              (* Absent: all top-level defs exported (open default).             *)
              (* Collected regardless of position; parser enforces no ordering.  *)

(* ============================================================ *)
(* Trust declarations (§4.4.3) *)
(* ============================================================ *)
trust-decl  = "(" "trust" qual-ident ":level" TRUST_LEVEL ")" ;
TRUST_LEVEL = "verified" | "contract-checked" | "tested" | "asserted" ;
              (* Acknowledges an unproven contract from an imported function.    *)
              (* Per-function, multiple per module. Idempotent (duplicates OK).  *)
              (* Must appear before any def / def-shell (same ordering as import).*)

(* ============================================================ *)
(* Types                                                         *)
(* ============================================================ *)
type-decl   = "(" "type" IDENT type-body ")" ;

type-body   = where-type                             (* refinement type alias *)
            | { "(" "|" IDENT type ")" }            (* sum type / ADT *)
            ;

type        = primitive | list-type | map-type | result-type
            | promise-type | bytes-type | fn-type | where-type
            | pair-type | command-type | IDENT ;

primitive   = "int" | "float" | "string" | "bool" | "unit" ;
list-type   = "list" "[" type "]" ;
map-type    = "map" "[" type "," type "]" ;
result-type = "Result" "[" type "," type "]" ;
promise-type= "Promise" "[" type "]" ;
bytes-type  = "bytes" "[" INT "]" ;
pair-type   = "(" type "," type ")" ;
command-type= "Command" ;

fn-type     = "(" "fn" "[" { fn-param } "]" ARROW type ")" ;
fn-param    = type | typed-param ;   (* named param is doc-only *)
where-type  = "(" "where" "[" IDENT ":" type "]" expr ")" ;

ARROW       = "->" | "→" ;  (* both produce TokArrow; canonical output is "->" *)
              (* → = U+2192. All other non-ASCII codepoints are lexer errors. *)

(* ============================================================ *)
(* Shared definition sub-productions (used by def / def-shell)   *)
(* def-logic is rejected; see def / def-shell *)
(* productions below for the current definition forms.           *)
(* ============================================================ *)
typed-param    = IDENT ":" type ;
pre-clause     = "(" "pre"  expr [ ":source" STRING ] ")" ;
post-clause    = "(" "post" expr [ ":source" STRING ] ")" ;
decreases-clause = "(" "decreases" expr { expr } ")" ;
                  (* def-shell only. Termination measure: int-typed exprs over  *)
                  (* the params ('result' not in scope, as in pre). k = 1       *)
                  (* discharges via well-foundedness + call-site strict         *)
                  (* descent; k > 1 via the lexicographic order on ℕᵏ (§4.2).   *)
entropy-clause = "(" "spec-entropy" SPEC_ENTROPY ")" ;
SPEC_ENTROPY   = ":strict" | ":intentional" | ":unknown" ;
                  (* CDP: optional per-contract annotation; defaults to *)
                  (* :strict when absent. :intentional suppresses the low-DP     *)
                  (* diagnostic per §4.4.6. The parser also accepts the clause  *)
                  (* on `letrec`. Unknown labels are a parse error.             *)

(* ============================================================ *)
(* Core/shell grammar — GrammarCoreInversion is the default *)
(* Pass --grammar=legacy to parse letrec programs. *)
(* ============================================================ *)
def          = "(" "def"       IDENT "[" { typed-param } "]"
                 [ ARROW type ]
                 { pre-clause } { post-clause } [ entropy-clause ]
                 core-expr
               ")" ;
                 (* Repeated pre/post clauses and-fold left in author order;    *)
                 (* each keeps its own :source (SRC-CONJ-1, §4.6).              *)
                 (* Strict-core: body must satisfy isCoreBodySyntactic.         *)
                 (* Callee admission at EApp: body-faithful evidence, OR        *)
                 (* trustedPrelude membership, OR builtinEnv membership.        *)
                 (* Optional return-type annotation: when *)
                 (* present, the body is checked against `type` (Check-Hole at  *)
                 (* a bare-hole body records HoleTyped; Check-by-Synth else).   *)

def-shell    = "(" "def-shell" IDENT "[" { typed-param } "]"
                 [ ARROW type ]
                 { pre-clause } { post-clause } [ entropy-clause ]
                 [ decreases-clause ]
                 expr
               ")" ;
                 (* Repeated pre/post clauses: same and-fold + :source          *)
                 (* retention as def (SRC-CONJ-1, §4.6).                        *)
                 (* Permissive form: no body restriction; no callee check.      *)
                 (* Optional return-type annotation; same *)
                 (* checking semantics as on def.                               *)

core-expr    = literal | var | let | if | match | app | linear-op-expr | hole ;
                 (* Excluded: lambda, do, pair, await, non-linear ops.         *)

linear-op-expr = "(" ( "+" | "-" | "=" | "<" | "<=" | ">" | ">=" | "!=" )
                     expr expr { expr } ")" ;

(* ============================================================ *)
(* Interfaces                                                    *)
(* ============================================================ *)
def-interface = "(" "def-interface" IDENT { iface-fn }
                  [ ":laws" "[" { for-all } "]" ]
                ")" ;
iface-fn      = "[" IDENT fn-type "]" ;

(* ============================================================ *)
(* Invariants                                                    *)
(* ============================================================ *)
def-invariant = "(" "def-invariant" IDENT "[" typed-param "]" expr ")" ;

(* ============================================================ *)
(* Entry point                                                    *)
(* ============================================================ *)
def-main    = "(" "def-main"
                ":mode" ( "console" | "cli" | "(" "http" INT ")" )
                [ ":init"    expr ]
                ":step"     expr
                [ ":done?"   expr ]
                [ ":on-done" expr ]
                [ ":status"  expr ]
              ")" ;
              (* Fields are read in this order; an out-of-order optional
                 field does not parse. :status is console-only, a total
                 State -> int projection applied when :done? holds (§9.5). *)

(* ============================================================ *)
(* Property-based tests & generators                            *)
(* ============================================================ *)
check       = "(" "check" STRING [ subject-meta ] for-all ")" ;
subject-meta = ":subject" IDENT
             | ":subjects" "[" IDENT { IDENT } "]" ;
              (* Optional explicit-attribution clause; see Rule 10. *)
for-all     = "(" "for-all" "[" { typed-param } "]" expr ")" ;

gen-decl    = "(" "gen" IDENT expr ")" ;
              (* expr must have the base type of the named refinement type *)

weakness-ok = "(" "weakness-ok" IDENT STRING ")" ;
              (* Suppression governance — see §4.5.                        *)
              (* STRING is a non-empty reason for the suppression.         *)

(* ============================================================ *)
(* Expressions                                                   *)
(* ============================================================ *)
expr        = literal | var | let | if | match | app | qual-app
            | op | pair | await | do | lambda | hole ;

literal     = INT | "-" INT | FLOAT | STRING | "true" | "false" ;
              (* Negative integers: '-' immediately precedes digits with no whitespace *)
var         = IDENT ;

(* let is SEQUENTIAL: each binding is in scope for all subsequent bindings *)
(* PR 4: binding head is now a pattern, not just an identifier.           *)
let         = "(" "let" "[" { let-binding } "]" expr ")" ;
let-binding = "(" pattern expr ")"          (* canonical form *)
            | "[" pattern expr "]" ;        (* legacy form — also accepted *)
              (* Example: (let [(x 1) (y (+ x 1))] y)  => 2 (simple vars)         *)
              (* Example: (let [((pair s cmd) (authenticate state cred))] ...)      *)

if          = "(" "if" expr expr expr ")" ;

(* match: MUST be exhaustive. Use _ as the catch-all arm.              *)
(* Failing match (no arm matches, no _ ) raises MatchFailure at runtime *)
match       = "(" "match" expr { match-arm } ")" ;
match-arm   = "(" pattern expr ")" ;
pattern     = "_"                            (* catch-all wildcard *)
            | IDENT                          (* variable binding   *)
            | literal                        (* literal equality   *)
            | "(" IDENT { pattern } ")" ;   (* constructor pattern *)

app         = "(" IDENT { expr } ")" ;          (* plain function call *)
qual-app    = "(" qual-ident { expr } ")" ;     (* capability command  *)
op          = "(" OP { expr } ")" ;
pair        = "(" "pair" expr expr ")" ;
await       = "(" "await" expr ")" ;
do          = "(" "do" { do-step } ")" ;
do-step     = "[" IDENT "<-" expr [ ":discard" ] "]"  (* named: bind state component *)
            | expr ;                                    (* anonymous: discard state    *)
            (* ":discard" declares that a NON-FINAL step's Command is dropped;
               it rides the bracketed form only and is rejected on the final step. *)
lambda      = "(" "fn" "[" { typed-param } "]" expr ")" ;

qual-ident  = IDENT { "." IDENT } ;   (* e.g., wasi.io.stdout *)

hole        = "?" IDENT                                        (* named *)
            | "?" "choose" "(" { IDENT } ")"                  (* choice *)
            | "?" "request-cap" "(" STRING ")"                 (* capability request *)
            | "?" "scaffold" "(" IDENT { kv } ")"             (* scaffold *)
            | "?" "delegate" "@" IDENT STRING ARROW type
                [ "(" "on-failure" expr ")" ]                  (* blocking delegate *)
            | "?" "delegate-async" "@" IDENT STRING ARROW type ;  (* async delegate; type is inner T, not Promise[T] *)

(* ============================================================ *)
(* Operators (all built-in; see Section 13)                      *)
(* ============================================================ *)
OP = "+" | "-" | "*" | "/" | "=" | "!=" | "<" | ">" | "<=" | ">="
   | "and" | "or" | "not" | "mod" ;
```

### Grammar Key Rules

1. **Return-type annotation is optional, and its form is the arrow.** There is no `: ReturnType` after `[params]`; the form is `-> RetType`, placed immediately after the parameter brackets and before the contract clauses (the `[ ARROW type ]` element in the `def` and `def-shell` productions above). Omit it and the return type is inferred; declare it and the body is checked against it. See §4.1 for the checking semantics, the bare-hole-body case, and the refinement-aliased return.
2. **`check` requires exactly one `for-all`.** A bare boolean expression is not valid inside `check`.
3. **`check` block labels must be valid identifiers.** Labels become Haskell `prop_*` function names. Any character outside `[a-zA-Z0-9]` is automatically replaced with `_` by the compiler. Write labels like `"game-over-false-at-start"` rather than `"game over (initial state)"` — both are accepted but special chars are silently normalized.
4. **List literals** (`[]`, `[a b c]`) are valid in both S-expression and JSON-AST. In S-expression, `[expr ...]` in expression position desugars to `foldr list-prepend (list-empty)` — **not** a parameter list. In JSON-AST use `{ "kind": "lit-list", "items": [...] }`.

5. **`let` bindings are sequential.** Each binding sees all previous bindings. The current syntax is `(let [(x 1) (y (+ x 1))] y)` (evaluates to `2`). The double-bracket form `(let [[x 1] [y 2]] ...)` is also accepted and equivalent — both forms compile to identical AST nodes. The binding head may be a `pattern` instead of a simple identifier, enabling pair destructuring: `(let [((pair s cmd) expr)] ...)`. In JSON-AST, use `"pattern"` instead of `"name"` in the let-binding object.
6. **`match` must be exhaustive.** Use `_` as the final arm if not all cases are covered explicitly. A `match` without `_` that fails at runtime raises `MatchFailure`.
7. **`result` is reserved** inside `post` clauses. Do not use it as a variable or parameter name anywhere.
8. **Named parameters in `fn-type` are doc-only.** `(fn [raw: string] -> bytes[64])` and `(fn [string] -> bytes[64])` are type-equivalent.
9. **JSON-AST identifier shape is schema-enforced.** The JSON-AST schema at `docs/llmll-ast.schema.json` enforces:
   - `ExprApp.fn` matches `^[^.]+$` — no dots permitted in plain function-call position. The character class is intentionally permissive to accept operator identifiers (`+`, `-`, `<=`, `mod`, etc.) that may appear in `app` position when emitted by JSON-AST agents that do not partition operators into `EOp`.
   - `ExprQualApp.qual_fn` matches `^[A-Za-z_][A-Za-z0-9_?\-]*(\.[A-Za-z_][A-Za-z0-9_?\-]*)+$` — at least one dot required, character class matches `IDENT` per §2.1. This formalizes the `qual-ident = IDENT { "." IDENT }` EBNF rule above.
   Schema-level rejection happens before parser entry; the typechecker also emits a warning on dotted `app.fn` for S-expression sources where the schema is not consulted (`compiler/src/LLMLL/TypeCheck.hs` `inferExpr`).
10. **`check` may carry explicit subject metadata.** The optional `subject-meta` clause between the label STRING and the `for-all` expresses agent intent to lift trust evidence per declared callee. `:subject f` is singleton sugar for `:subjects [f]`. The annotated branch bypasses the head-position scan rule and lifts trust evidence per declared subject (§4.4.5). Empty `:subjects []` is rejected at parse time; duplicate names are deduplicated; cross-module subjects qualify through the existing `qualMap`. JSON-AST encodes this via the optional `CheckDecl.subjects: [Name]` field. See §4.4.5 *Annotated-subject branch* for the PBT-Lift semantics and the joint-witness scalar-exclusion rule.


---

## 13. Built-in Runtime Functions

These functions and operators are **always in scope**. They are provided by the LLMLL runtime and do not require a `capability` import, except for the command constructors in §13.9 which require the matching capability.

**Where a builtin takes two or more parameters of the same type, its row states the call form explicitly.** At such a signature a transposed call type-checks and `llmll check` reports OK, so nothing before execution catches it and the mistake surfaces only in the output. The orders are given per row because they are **not** uniform across this section: §13.6 alone holds three builtins that disagree about whether the subject or the operand comes first. Take the order from the row rather than from a neighbour.

### 13.1 Arithmetic Operators

| Operator | Signature | Notes |
|----------|-----------|-------|
| `+` | `int int -> int` | Addition |
| `-` | `int int -> int` | Subtraction |
| `*` | `int int -> int` | Multiplication |
| `/` | `int int -> int` | Integer division; raises `DivisionByZero` if right operand is `0`. **Codegen:** compiles to Haskell `` `div` `` (not `/`, which requires `Fractional`). |
| `mod` | `int int -> int` | Modulo |

### 13.2 Comparison & Equality Operators

The `=` operator is **polymorphic structural equality** defined over all LLMLL types:

- **`int`, `float`, `bool`:** numeric/value equality.
- **`string`:** byte-by-byte equality (UTF-8; locale-independent).
- **`list[t]`:** equal if same length and each pair of elements is `=`.
- **`map[k,v]`:** equal if same key set and each value is `=`.
- **`(a, b)` pairs:** equal if both components are `=`.
- **ADT constructors:** equal if same constructor tag and payload is `=`.
- **`Command`:** comparison is **not defined** — commands are opaque.
- **`Json`:** comparison is **not defined**, and `=`, `!=`, and `list-contains` are *rejected* at any argument type mentioning `Json` (including `list[Json]` and `Result[Json,string]`). Structural equality would make member order observable program behaviour; compare serializations instead: `(= (json-serialize a) (json-serialize b))`.

| Operator | Signature | Notes |
|----------|-----------|-------|
| `=` | `a a -> bool` | Polymorphic structural equality (see above) |
| `!=` | `a a -> bool` | Structural inequality |
| `<` `>` `<=` `>=` | `int int -> bool` | Ordered comparison (integers only) |

### 13.3 Logic Operators

| Operator | Signature | Notes |
|----------|-----------|-------|
| `and` | `bool bool -> bool` | Short-circuit AND (right side not evaluated if left is `false`) |
| `or` | `bool bool -> bool` | Short-circuit OR (right side not evaluated if left is `true`) |
| `not` | `bool -> bool` | Logical negation |

### 13.4 Pair / Record Operations

| Function | Signature | Notes |
|----------|-----------|-------|
| `pair` | `a b -> (a, b)` | Construct a 2-tuple (typed `TPair a b` internally) |
| `first` | `(a, b) -> a` | First projection — accepts any pair, including explicitly-annotated parameters |
| `second` | `(a, b) -> b` | Second projection — accepts any pair, including explicitly-annotated parameters |

> **Pair destructuring in `let` bindings.**
> `(let [((pair s cmd) (authenticate state cred))] ...)` destructures a pair result into `s` and `cmd`. Nested destructuring is supported: `(let [((pair word (pair g rest)) state)] ...)`. This works identically to pair patterns in `match` arms. In JSON-AST, use `"pattern"` instead of `"name"` in the let-binding object.

> **Pattern for records:** LLMLL has no native record syntax. Use nested `pair` values and named accessor functions. A 4-field record uses 3 levels of nesting:
> ```lisp
> ;; State = (word, (guessed, (wrong-count, max-wrong)))
> (def-shell make-state [w: Word g: list[Letter] wc: GuessCount mx: GuessCount]
>   (pair w (pair g (pair wc mx))))
> (def-shell state-word    [s] (first s))
> (def-shell state-guessed [s] (first (second s)))
> (def-shell state-wrong   [s] (first (second (second s))))
> (def-shell state-max     [s] (second (second (second s))))
> ```

### 13.5 List Operations

| Function | Signature | Notes |
|----------|-----------|-------|
| `list-empty` | `-> list[a]` | Empty list (monomorphic; type inferred from usage) |
| `list-append` | `list[a] a -> list[a]` | Append element to **end** of list |
| `list-prepend` | `a list[a] -> list[a]` | Prepend element to **front** of list |
| `list-contains` | `list[a] a -> bool` | Membership test using `=` |
| `list-length` | `list[a] -> int` | Number of elements |
| `list-head` | `list[a] -> Result[a, string]` | First element; `Error` on empty list |
| `list-tail` | `list[a] -> Result[list[a], string]` | All but first; `Error` on empty list |
| `list-map` | `list[a] (fn [a] -> b) -> list[b]` | Transform each element |
| `list-filter` | `list[a] (fn [a] -> bool) -> list[a]` | Keep elements satisfying predicate |
| `list-fold` | `list[a] b (fn [b a] -> b) -> b` | Left fold (accumulate from left) |
| `list-nth` | `list[a] int -> Result[a, string]` | Element at index; `Error` on out-of-range |
| `range` | `int int -> list[int]` | `(range from to)` produces `[from, from+1, ..., to-1]`. If `from >= to`, returns empty list. |

> **`range` example:**
> ```lisp
> (range 0 5)   ;; => list containing 0, 1, 2, 3, 4
> (range 3 3)   ;; => empty list
> (range 5 3)   ;; => empty list
> ```
>
> **List literals:** `[]` is the empty list; `[a b c]` is a three-element list — valid in both S-expression and JSON-AST syntax. In S-expression, `[expr ...]` in expression position desugars to `foldr list-prepend (list-empty)`. In JSON-AST, use `{ "kind": "lit-list", "items": [...] }`. The `list-empty` and `list-prepend` functions remain valid alternatives.
> ```lisp
> ;; list literal with let syntax:
> (let [(n       (string-length word))
>       (indices (range 0 n))]
>   (list-map indices (fn [i: int] (string-char-at word i))))
> ```

### 13.6 String Operations

> [!IMPORTANT]
> **The two-argument string builtins do not share an argument-order convention.** Each is `string string`, so a reversed call type-checks and `llmll check` reports OK. `string-contains` takes the **subject** first, `string-split` takes the **separator** first, and `regex-match` takes the **pattern** first. A reader who infers a rule from two of them will be wrong about the third, so take the order from the row.

| Function | Signature | Notes |
|----------|-----------|-------|
| `string-length` | `string -> int` | Length in characters |
| `string-contains` | `string string -> bool` | `(string-contains subject needle)` tests whether `needle` occurs in `subject`. The **subject comes first**, the opposite of `string-split` below; a reversed call type-checks. |
| `string-concat` | `string string -> string` | `(string-concat left right)` yields `left` followed by `right`. The **left operand comes first**; a reversed call type-checks and transposes the result. |
| `string-slice` | `string int int -> string` | `(string-slice s start end)` takes the `[start, end)` half-open slice. The **start comes first**; both indices are `int`, so a transposed pair type-checks and returns `""`. Out-of-range indices **clamp**: `start` and `end` are each clamped into `[0, string-length s]`, so a negative `start` reads from 0 and an `end` past the end reads to the end. This matches `string-char-at`'s out-of-range convention below. |
| `string-char-at` | `string int -> string` | Single character at index (as 1-char string). Returns `""` for negative or out-of-bounds indices. |
| `string-split` | `string string -> list[string]` | `(string-split sep subject)` splits `subject` on `sep`. The **separator comes first**; both parameters are `string`, so a reversed call type-checks and fails only in its output. |
| `string-trim` | `string -> string` | Strip leading/trailing whitespace and newlines (`Space`, `\t`, `\n`, `\r`) |
| `string-concat-many` | `list[string] -> string` | Concatenate a list of strings (variadic join without separator) |
| `regex-match` | `string string -> bool` | `(regex-match pattern subject)` matches `subject` against `pattern`. The **pattern comes first**, the opposite of `string-contains` above; a reversed call type-checks. POSIX ERE match via `regex-tdfa`. Invalid patterns return `False` (total). |
| `string-empty?` | `string -> bool` | True when string has length 0 |

> [!NOTE]
> **Class A indexing primitives — boundary trust closure.** The indexing primitives `list-length`, `list-nth` (§13.5), `string-length`, `string-slice`, `string-char-at` (§13.6) keep concrete `Int` (`Int64`) signatures at the Haskell runtime layer per [`docs/archive/shipped-design-specs/int-2-boundary-shims.md`](docs/archive/shipped-design-specs/int-2-boundary-shims.md) §3.1; codegen inserts `fromIntegral` shims at the LLMLL-to-Haskell call seam in `CodegenHs.hs`. The primitives assume the underlying Haskell representation fits in `Int64` — lists and strings whose length is at most `2⁶³ − 1 = 9_223_372_036_854_775_807` elements. Programs constructing collections beyond this bound are outside the builtin's input domain; the verification report does not cover their behavior. This is a sub-case of the existing FFI-builtin trust closure at §7.

### 13.7 Numeric Utilities

| Function | Signature | Notes |
|----------|-----------|-------|
| `int-to-string` | `int -> string` | Decimal representation |
| `string-to-int` | `string -> Result[int, string]` | Parse; `Error` on failure |
| `abs` | `int -> int` | Absolute value |
| `min` | `int int -> int` | Minimum |
| `max` | `int int -> int` | Maximum |

### 13.8 Result Helpers

| Function | Signature | Notes |
|----------|-----------|-------|
| `ok` | `a -> Result[a, e]` | Wrap in `Success` |
| `err` | `e -> Result[a, e]` | Wrap in `Error` |
| `is-ok` | `Result[a, e] -> bool` | `true` if `Success` |
| `unwrap` | `Result[a, e] -> a` | Extract value; raises `UnwrapError` on `Error` |
| `unwrap-or` | `Result[a, e] a -> a` | Default value on `Error` |

**The three layers of Result.**

LLMLL distinguishes three syntactic surfaces for `Result[t, e]` values, each with a distinct constructor name. AI agents must use the right surface in the right position; mixing them is a typecheck error.

| Layer | Surface | Where used | Compiler citation |
|-------|---------|------------|-------------------|
| **Construct** | `(ok x)`, `(err e)` | Expression position — function bodies, `on-failure` clauses, `let` RHS | `compiler/src/LLMLL/TypeCheck.hs` (`Result`-related builtins) |
| **Match** | `(Success v)`, `(Error e)` | `match`-arm pattern position only | `compiler/src/LLMLL/CodegenHs.hs` (rewrites to Haskell `Right`/`Left`) |
| **Test** | `(is-ok x)` | Boolean test in expression position | `compiler/src/LLMLL/TypeCheck.hs` |

`Result.Ok` and `Result.Error` are **not** registered constructor names. Use `(ok x)` and `(err e)` for construction and `(Success v)` / `(Error e)` for match arms.

```lisp
;; Construct
(def-shell safe-divide [a: int b: int]
  (if (= b 0) (err "division by zero") (ok (/ a b))))

;; Match
(match (safe-divide x y)
  ((Success q)  q)
  ((Error  msg) -1))

;; Test
(if (is-ok (safe-divide x y)) "ok" "fail")
```

**`?proof-required` for Result-returning contracts.**

When a contract on a Result-returning function asserts a property the verifier cannot discharge — typically because the postcondition involves a delegated call, nonlinear arithmetic, or map invariants — mark the contract clause `?proof-required` rather than weakening the spec or relying on `(weakness-ok ...)`. The marker promotes the obligation to the trust channel as `asserted` (per §5.3.5 verification matrix), records the gap in the trust report, and surfaces a structured hole to the obligation report. Agents receive credit for declaring the obligation; weakening the spec to silence the verifier is an anti-pattern.

```lisp
(def-shell verify-token [token: string]
  ;; Postcondition intent: result is Success or `err "invalid"`.
  ;; The predicate is non-linear (depends on the delegated body),
  ;; so the verifier cannot discharge it. Marker emitted; trust=asserted.
  (post ?proof-required)
  (?delegate @auth-agent "verify the token" -> Result[Claims, string]
    (on-failure (err "invalid"))))
```

**Bare-leaf form** (used in the example above): `?proof-required` records that the clause is outside the verifier's decidable fragment without embedding the predicate. In JSON-AST: `{"kind": "hole-proof-required", "reason": "non-linear-contract"}`. The intended predicate is documented in the surrounding source comment or trust-report annotation. Trust tier: `asserted`. See §6.

**Predicate-carrying form:** `(?proof-required :reason "non-linear-contract" pred-expr)` in `pre`/`post` position embeds the predicate and emits a Haskell runtime assertion at codegen. In JSON-AST: `{"kind": "hole-proof-required", "reason": "non-linear-contract", "predicate": { "kind": "op", "op": ">=", "args": [{"kind": "var", "name": "result"}, {"kind": "lit-int", "value": 0}] }}`. Non-linear predicates also emit a `QF-LIA` warning at `llmll check`.

### 13.9 Standard Command Constructors

These functions produce `Command` values. Each requires the corresponding `import` declaration — the compiler will reject a call to a command constructor whose capability has not been imported.

| Constructor | Signature | Required `import` | Effect |
|-------------|-----------|-------------------|--------|
| `wasi.io.stdout` | `string -> Command` | `(import wasi.io (capability stdout ...))` | Write text to standard output |
| `wasi.io.stderr` | `string -> Command` | `(import wasi.io (capability stderr ...))` | Write text to standard error |
| `wasi.http.response` | `int string -> Command` | `(import wasi.http (capability serve PORT))` | Return HTTP response (status, body) |
| `wasi.http.post` | `string string -> Command` | `(import wasi.http (capability post URL))` | Constructs a POST of `body` to `url`: `(wasi.http.post url body)`, the **URL first**. Both parameters are `string`, so a reversed call type-checks. **No network runtime in the Haskell backend**: the body is discarded and the command publishes `RErr`. See the note below this table |
| `wasi.fs.read` | `string -> Command` | `(import wasi.fs (capability read PATH))` | Read file at path |
| `wasi.fs.write` | `string string -> Command` | `(import wasi.fs (capability write PATH))` | Write content to file at path: `(wasi.fs.write path contents)`, the **path first**. A reversed call type-checks and treats the contents as the filename |
| `wasi.fs.delete` | `string -> Command` | `(import wasi.fs (capability delete PATH))` | Delete file at path (**sensitive**; see the note below) |
| `wasi.fs.list` | `string -> Command` | `(import wasi.fs (capability read PATH))` | List directory entries at path, sorted |
| `wasi.fs.mkdir` | `string -> Command` | `(import wasi.fs (capability write PATH))` | Create directory at path, with parents; idempotent |
| `wasi.fs.sha256` | `string -> Command` | `(import wasi.fs (capability read PATH))` | SHA-256 of the file's **bytes**, as lowercase hex |
| `wasi.fs.copy` | `string string -> Command` | `(import wasi.fs (capability read-write PATH))` | Copy a file's **bytes** from source to destination, overwriting; never decodes. `(wasi.fs.copy src dst)` puts the **source first**; a reversed call type-checks and overwrites the source instead |
| `wasi.clock.monotonic` | `Command` | `(import wasi.clock (capability read))` | Monotonic nanoseconds. **Nullary: a value, not a call** |
| `wasi.proc.args` | `Command` | `(import wasi.proc (capability exec NAME))` | This process's argument vector, `argv[0]` excluded. **Nullary: a value, not a call** |
| `wasi.proc.run` | `string list[string] string string string int -> Command` | `(import wasi.proc (capability exec NAME))` | Run executable with argv in a working directory, stdout/stderr redirected to paths, timeout in seconds: `(wasi.proc.run exe argv cwd stdout-path stderr-path timeout-secs)`. The three trailing `string` parameters are **working directory, stdout path, stderr path** in that order, and any permutation of them type-checks |
| `seq-commands` | `Command Command -> Command` | _(none, built-in)_ | Execute two commands in order: `(seq-commands first second)` runs `first`, then `second`. Both parameters are `Command`, so a reversed call type-checks and silently inverts the order |

> **What a `Command` returns.** A `Command` value is not the result of an effect; it is a request to
> perform one. `(string-length (wasi.fs.read p))` is a type error, because `wasi.fs.read` evaluates to
> a `Command`, not to the file's contents. The result arrives on the **response channel** instead: the
> harness performs the command and hands what it produced to the next `:step` as a `Response`
> (§9.7). A console program can therefore read a file and branch on its contents, with no function
> performing IO. `wasi.fs.read` delivers contents as `RText` and an IO failure as `RErr`;
> `wasi.fs.list` delivers entries as `RList`, an empty directory as `RList` with zero entries, and a
> missing directory as `RErr`. The `cli` and `http` harnesses perform no command and deliver no
> response.

> **The text commands are pinned to UTF-8**, not to the ambient locale, so the byte image of a read
> or a write is a property of the program rather than of the environment that launched it.
> `wasi.fs.read` of a file that is not valid UTF-8 delivers `RErr`, and `wasi.fs.write` encodes as
> UTF-8 regardless of `LANG`. Bytes that are not text do not belong on this channel: `wasi.fs.sha256`
> hashes them and `wasi.fs.copy` moves them, neither decoding on the way through.
>
> **The same pin covers the program's own standard handles.** A generated program sets its locale to
> UTF-8 and pins its standard handles before its first read or write, so `wasi.io.stdout` and
> `wasi.io.stderr` write UTF-8 under any `LANG` rather than failing to encode a non-ASCII string
> under a POSIX one. The property is the same one the filesystem commands state: what a program puts
> on a channel is a fact about the program, not about the shell that launched it.
>
> `wasi.fs.mkdir` delivers `RNone`, `wasi.fs.sha256` a lowercase hex digest as `RText`,
> `wasi.clock.monotonic` nanoseconds as `RCode`, and `wasi.proc.run` the child's exit status as
> `RCode` — with a budget overrun, a missing executable, or any IO failure arriving as `RErr`.
> `wasi.proc.args` delivers the argument vector as `RList`, and an invocation with **no** arguments
> as `RList` with zero entries rather than as `RNone`: `RNone` is what the response slot holds when
> nothing published, so collapsing the two would make "invoked with no arguments" indistinguishable
> from "no command published anything".
>
> **`wasi.proc.args` reads argv through the response channel, not through an entry-point parameter.**
> A program that wants its arguments issues it as `:init`'s command and receives the vector as the
> first `:step`'s `Response` (§9.7). `:init`'s arity does not move to carry it. `argv[0]` is
> excluded, so `console` and `cli` agree on what "the arguments" means. It shares the `wasi.proc`
> namespace with `wasi.proc.run`, and the capability check matches the namespace rather than the
> verb (§7), so one `(import wasi.proc ...)` clause grants both.
>
> **`wasi.proc.run` takes an executable and an argument vector, never a shell string**, so no
> metacharacter in argv is interpreted. Its `capability exec` clause makes the set of programs a
> module can invoke readable from the module header. Like every other capability clause it is **not
> enforced** (§7), and even once enforced it would bound *which program runs*, never what that
> program is told to do: where the named program interprets its arguments as instructions, the
> authority delivered through argv is unbounded. `wasi.clock.monotonic` reads a clock whose epoch is
> unspecified, so only differences of two readings taken in the same process are meaningful; a
> reading persisted to a file and read back returns as a string, and nothing in the type system can
> observe the round trip.
>
> Two limits that remain. `wasi.http.post` has **no network runtime in the Haskell backend**: it
> writes a diagnostic to stderr, performs no request, and `llmll build` warns at codegen when a
> program calls it. There is no `wasi.http.get`. And the "sensitive command triggers human review"
> behavior on `wasi.fs.delete` is **not implemented**; there is no guarded mode (§9.4). All are
> tracked in [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md).

**Example: Using multiple commands**

```lisp
(module game
  (import wasi.io (capability stdout :deterministic false))

  (def-shell initialize-game [word: Word]
    (pre (> (string-length word) 0))
    (let [[initial-state (make-state word (list-empty) 0 6)]]
      (pair initial-state (wasi.io.stdout "Game initialized.\n")))))
```

### 13.10 Clause-Scoped Bindings

The identifier `result` is a **reserved pseudo-binding** available only inside `post` clauses. It is automatically bound to the return value produced by the function body, after the body has been evaluated and before the postcondition is checked.

| Identifier | Scope | Value |
|------------|-------|-------|
| `result` | Inside `post` only | The return value of the function body |

```lisp
(def-shell add [x: int y: int]
  (post (= result (+ x y)))  ;; result = x + y, as returned by the body
  (+ x y))
```

`result` cannot appear in:
- `pre` clauses (the body has not run yet)
- `let` bindings (not a valid expression outside `post`)
- Parameter lists (reserved keyword — compile error)

### 13.11a Building Services (FAQ)

When building practical services (REST APIs, CLIs, etc.) in LLMLL, here are solutions to common patterns. All examples use the Haskell FFI model.

1. **HTTP Requests (Input):**
   LLMLL does not have a built-in `HttpRequest` sum type with headers and paths. If your service requires routing or header inspection, use the Tier 1 Hackage FFI:
   ```lisp
   (import haskell.warp (interface [
     [parse-request (fn [s: string] -> Result[HttpRequest, string])]
   ]))
   ```
   This resolves to `import Network.Wai` — no stub generated.

2. **CLI Arguments:**
   For structured argument parsing (e.g., `--port 8080 --file data.json`), you have two options:
   - Write a naive string-splitting parser in pure LLMLL S-expressions.
   - Use the Tier 1 Hackage FFI:
   ```lisp
   (import haskell.optparse-applicative (interface [
     [parse-args (fn [s: string] -> Result[CliArgs, string])]
   ]))
   ```

3. **JSON Parsing & Serialization:**
   Use the Tier 1 Hackage FFI — no stub file generated:
   ```lisp
   (import haskell.aeson (interface [
     [json-decode (fn [s: string] -> Result[TodoList, string])]
     [json-encode (fn [td: TodoList] -> string)]
   ]))
   ```
   This resolves to `import Data.Aeson`. The developer writes a `FromJSON`/`ToJSON` instance for the LLMLL type in a thin Haskell bridge file.

4. **Atomic File Writes:**
   The built-in `wasi.fs.write` does not guarantee atomicity. For ACID-like atomic writes, use the Tier 1 Hackage FFI:
   ```lisp
   (import haskell.unix (interface [
     [atomic-write (fn [path: string content: string] -> bool)]
   ]))
   ```
   This resolves to `import System.Posix.Files` and `atomicWriteFile` — no stub required.

### 13.11 Cryptographic Operations

Cryptographic builtins are **opaque primitives** — the compiler does not attempt to verify their correctness. Their results are classified as `asserted` in the trust report. Downstream contracts that depend on these builtins are capped at the `asserted` verification level.

| Function | Signature | RFC Reference | Notes |
|----------|-----------|---------------|-------|
| `hmac-sha1` | `bytes[20] bytes[20] → bytes[20]` | RFC 2104 (HMAC) | `(hmac-sha1 key message)`: the **key comes first**. Key and message are both `bytes[20]`, so a reversed call type-checks and returns a different MAC. Returns 20-byte MAC. |
| `sha1` | `bytes[20] → bytes[20]` | FIPS 180-4 (SHA-1) | Input is `bytes[20]`, output is 20-byte hash. |

> [!IMPORTANT]
> **Implementation note:** The preamble SHA-1 implementation in `CodegenHs.hs` is a **simplified stub** (polynomial hash, not a faithful SHA-1). The trust report correctly classifies all functions depending on these builtins as `asserted`. For production use, replace the preamble with a real Haskell crypto library (`crypton` or `cryptohash-sha1`). The `sha1_hash` binding in `CodegenHs.hs`'s runtime preamble carries a comment marking this. (`cryptohash-sha256` is already a dependency of every generated project, added for `wasi.fs.sha256`, so the sibling `cryptohash-sha1` costs no resolver movement.)

> [!NOTE]
> **Extensible namespace.** `§13.11` remains extensible for primitives whose inputs carry a
> statically known length: an opaque primitive with concrete `bytes[N]` types, backed by a real
> Haskell crypto library in the preamble. Variable-length byte types (`bytes` without a length
> parameter) are deferred.
>
> **`sha256` was expected here and landed elsewhere.** It ships as `wasi.fs.sha256` in §13.9, a
> `Command` over a *path* rather than a pure function over `bytes[N]`, because `bytes[N]` requires a
> literal type-level length and a file's length is not statically known. Hashing therefore happens
> inside the sealed builtin, on the file's bytes. The distinction is not cosmetic: composing
> `wasi.fs.read` with a pure hash would hash locale-decoded **text**, and a file that is not valid
> UTF-8 does not survive that read at all.
>
> **The two sections now differ in what they deliver.** `wasi.fs.sha256` is backed by
> `cryptohash-sha256` and is a real SHA-256, pinned by a known-answer test against the FIPS 180-4
> vector. `sha1` and `hmac-sha1` in this section are **stubs** and remain so: the preamble body is a
> polynomial rolling hash with no preimage or collision resistance, and `hmac-sha1` is built entirely
> from it. Neither is fit for any security purpose. Tracked as `CRYPTO-1`.

> [!IMPORTANT]
> **Stub-backend trust-tier annotation.** Distribution builds intended for production use **must** replace the preamble `sha1` / `hmac-sha1` stub in `CodegenHs.hs` with a verified crypto backend (`crypton` or `cryptohash-sha1`). The trust report annotates dependencies on these builtins as `asserted-with-stub-backend` until backend replacement is verified — a machine-readable signal distinguishing "asserted because the algorithm is opaque" (the diamond-lattice `asserted` tier per §4.4.1) from "asserted with a known-incorrect runtime implementation" (the additional stub-backend caveat). The symbols `sha1` and `hmac-sha1` retain their RFC 2104 / FIPS 180-4 contract names — they are not renamed to `sha1_stub` — because the contract is the standards specification; the stub status is an implementation defect documented in the trust report for downstream consumer transparency.

**Usage in TOTP benchmark:**

```lisp
(def-shell hmac-sha1-wrap [key: bytes[20] message: bytes[20]]
  (hmac-sha1 key message))

(weakness-ok hmac-sha1-wrap "Cryptographic hash correctness is outside QF-LIA; asserted per RFC 2104")
```

`:source` (§4.6) is grammatically a suffix on a `(pre ...)`/`(post ...)` clause — it cannot appear bare in a body. `hmac-sha1-wrap` has no `pre`/`post` predicate to attach it to (it's unconditionally trusted via `weakness-ok`, not a contract), so RFC provenance here lives in the `weakness-ok` reason string instead — matching the real fixture, [`examples/totp_rfc6238/totp_filled.ast.json`](examples/totp_rfc6238/totp_filled.ast.json).

The `weakness-ok` declaration acknowledges that the wrapper has no meaningful contract — its correctness rests entirely on the axiomatically assumed `hmac-sha1` builtin.

### 13.12 Bytes and Map Operations

Operations over the compound types `bytes[n]` and `map[k,v]` (§3.2). Reads carry **PROVE-polarity preconditions** — the caller owes the obligation (there is no `Result`-wrapped read form). Both families **discharge statically** in the array class of `Σ_auto` (§5.3.3): bytes index-in-bounds and value-range, and map **key-presence**, are solver-checked call-site obligations — an out-of-bounds read, a read without a presence proof, or a dropped update in a verified function is *refuted*, not merely asserted. Map discharge covers `map[{int,string},{int,bool,string}]` (the admitted key sorts are `{int, string}`; int, bool via the int-0/1 bridge, and **string** values (literals AND string params) via a genuine `Str` value-array sort are the reflected value classes), including read-modify-write bodies, cross-module assume-guarantee, and map-returning callee results — for string-valued maps too (v0.14.51); string `map-empty` construction and string keys shipped (v0.14.50/51); the residue that falls back whole is non-{int,string} key sorts and direct reads on `(map-empty)`. All preconditions are additionally runtime-asserted in generated code regardless of static discharge. Under `llmll test`, a `check` sample that violates one of these read preconditions (bytes index-in-bounds, map key-presence) is discarded rather than counted (§4.4.5).

| Function | Signature | Precondition | Notes |
|----------|-----------|--------------|-------|
| `bytes-length` | `bytes[n] → int` | — | Returns `n`. |
| `bytes-get` | `bytes[n] int → int` | `0 ≤ i < n` | The byte at index `i` (`0–255`). |
| `bytes-set` | `bytes[n] int int → bytes[n]` | `0 ≤ i < n` | `(bytes-set b i v)` writes value `v` at index `i`: the **index comes first**. Functional update; length-preserving. Both trailing parameters are `int`, so a transposed call type-checks and is caught only by the runtime precondition, and only when the swapped values violate it. |
| `bytes-zero` | `→ bytes[n]` | — | All-zero buffer. Legal only as the whole body of a `def`/`def-shell` whose declared return is a literal `bytes[n]` — the return type determines `n`. **The same annotation gives the constructor its length in verification, not only at runtime:** the body VC assumes the axiom `bytesLen(result) = n` alongside the constant-zero array, so `(bytes-length result)` is derivable of a constructed buffer. Without it the length is not derivable at all, since the const array is a total function in the array theory and carries no length. `n` is read from the declared return and never from the `post`; a `post` declaring a different length is refuted, not believed. The axiom is a claim about a sealed builtin whose validity rides the `codegen_semantics_version` stamp (§3.5), the same category as `bytes-set`'s length preservation, and it is not a solver discharge. |
| `map-has` | `map[k,v] k → bool` | — | Key-presence test. |
| `map-get` | `map[k,v] k → v` | `(map-has m k)` | Read of a present key. |
| `map-put` | `map[k,v] k v → map[k,v]` | — | Functional update. |
| `map-empty` | `→ map[k,v]` | — | Empty map; type from context. |

**Map keys are `{int, string}`** (`int` in v1, `string` added v0.14.51) — a map operation at any other key type is a typechecker diagnostic on the *operation*; the `map[k,v]` type former itself is unrestricted.

### 13.13 JSON Operations

Operations over the sealed opaque type `Json` (§3.2). All fourteen are **`def-shell`-only**: a `def` body calling one is rejected with `core-excluded-builtin` (§4.1). Every partial operation returns `Result`, because a JSON value's shape is not statically expressible and there is no `match` form to discriminate it.

| Function | Signature | Notes |
|----------|-----------|-------|
| `json-parse` | `string → Result[Json,string]` | RFC 8259. Rejects duplicate member names and nesting deeper than 512. |
| `json-serialize` | `Json → string` | Deterministic; one-space indent; members in stored order. |
| `json-get` | `Json string → Result[Json,string]` | Member by name; `err` if absent or the receiver is not an object. |
| `json-get-string` | `Json string → Result[string,string]` | `err` unless the member is a string. |
| `json-get-int` | `Json string → Result[int,string]` | `err` unless the member is an **integer lexeme**. |
| `json-get-bool` | `Json string → Result[bool,string]` | `err` unless the member is a bool. |
| `json-get-number` | `Json string → Result[string,string]` | The member's **source lexeme**, unparsed. |
| `json-array` | `Json → Result[list[Json],string]` | The bridge to `list[t]`, for iteration. |
| `json-object` | `Json` | The empty object. A **value**, not a call. |
| `json-set` | `Json string Json → Result[Json,string]` | `(json-set obj name value)`: the **receiver comes first** and the new value last. Functional update: replace in place, append when absent. Both `Json` positions share a type, so a transposed call type-checks. |
| `json-of-string` | `string → Json` | |
| `json-of-int` | `int → Json` | |
| `json-of-bool` | `bool → Json` | |
| `json-of-list` | `list[Json] → Json` | |

**Numbers are stored as source lexemes.** `json-parse` keeps a number's original text and `json-serialize` emits it unchanged, so a parsed number survives a round trip byte for byte and a large integer keeps full precision. `json-get-int` is therefore strict: `1.0` denotes an integral value but is not an integer lexeme, and returns `err`. There is no float projection; `json-get-number` returns the lexeme and the program decides what to do with it. Comparing that lexeme against a string literal is also what keeps such a check inside `Σ_auto`, where a float comparison would not be (§5.3.5).

**Duplicate member names are rejected**, compared after unescaping, per RFC 7493 §2.3. RFC 8259 §4 leaves the behaviour to the implementation; rejecting is what makes `json-set` replace-in-place total, so `(json-get (json-set v k x) k)` is `(ok x)` unconditionally.

**Verification.** `Json` lowers to an opaque carrier sort, exactly as `list[t]` does. No `json-*` name is reflected into the solver, so a body mentioning one takes the fallback routing of §5.3.3 and reaches `contract-checked` rather than a body-faithful VC. That is why the family is `def-shell`-only: the restriction makes the fallback explicit at `check` time instead of silent at emission. The accessors' *results* (`int`, `bool`, `string`) re-enter `Σ_auto` normally, which is the intended shape — extract scalars in a `def-shell`, then decide in a `def`.

**Trust tier.** The parser and serializer are sealed builtins backed by Haskell in the codegen preamble; their correctness is `asserted` (the §13.11 precedent). Unlike the §13.11 stubs they carry an oracle: BUILD-GATE-1's execution stage runs a round trip and a ten-case adversarial parse battery against hand-computed answers.

---
