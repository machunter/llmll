# REF-META-1 — Refinement Metatheory of Record (Checking-Mode Rule + Non-Goals + Soundness Statement)

> **Version:** Rev 2 — incorporates professor review findings (six gaps and two author-question answers folded; cross-proposal observations C-1/C-2/C-3/C-4 acknowledged per the C-2 settlement at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md))
> **Date:** 2026-05-24 (Rev 1); 2026-05-25 (Rev 2)
> **Implements:** `docs/compiler-team-roadmap.md` v0.11 architectural lane, REF-META-1 row at [`docs/compiler-team-roadmap.md:316`](../../compiler-team-roadmap.md#L316)
> **Prerequisites:** None — promotes a settled framing decision into a proposal file. Drafts the inference rule, non-goals, and soundness statement adjudicated in [`critique-2026-05-23-triage.md §3.1`](../../design/critique-2026-05-23-triage.md) into the structured form `documentation-lead` consumes.
> **Origin:** 2026-05-23 external critique processed via professor channel; language-team triage at [`critique-2026-05-23-triage.md §3.1`](../../design/critique-2026-05-23-triage.md) adjudicated the framing (adopted the amended critic's checking-mode-only rule over the professor's Vazou-style subtyping framing); operationally equivalent — narrower-framing rationale per §3.1 below.
> **Reviewed:** Professor review at [`refinement-metatheory-of-record-review.md`](../professor-reviews/refinement-metatheory-of-record-review.md) (Rev 1, 2026-05-25); recommend `approve with revisions`. Six gaps and two author-question answers folded into this Rev 2. Standalone review awaits doc-lead M2 fold-and-archive.
> **Status:** Settled (Rev 2) — professor review folded; pending documentation-lead promotion to `LLMLL.md §3.4 / §5`. Spec-track only (no compiler work implied; the rule is consistent with the existing two-phase implementation per §7 below).

---

## 1. Motivation

LLMLL's [`§3.4` Refinement Type Aliases](../../../LLMLL.md) gives the surface form `(where [x: T] p)` and states that constraints are "checked at compile time" with "compile-time SMT verification of constraint *values* performed by `llmll verify`." It does not state the typing rule that produces the obligation. Five auxiliary pieces are also missing: an explicit non-goals list (what LLMLL does *not* promise), a soundness statement of record, a predicate well-formedness rule, an erasure theorem with construction-side discipline, and the full typing judgment.

REF-META-1 ships the first three: the **checking-mode inference rule**, the **non-goals list**, and the **soundness statement of record**. REF-META-2..5 (solver-completeness statement, erasure theorem, predicate WF rule, full typing judgment) are sequenced after this proposal as separate language-team turns, per the triage row at [`docs/compiler-team-roadmap.md:324`](../../compiler-team-roadmap.md#L324).

The external critic surfaced two missing-from-record items as P0 spec gaps:

1. The intro/elim rule for refinement-aliased types has no canonical statement in `LLMLL.md` — a reader must reverse-engineer it from prose at §3.4 and the verification-matrix table at [`§5.3.5`](../../../LLMLL.md). For AI agents consuming LLMLL.md as prompt context, this is a citation gap of the worst kind: load-bearing semantics with no addressable statement.
2. The set of features LLMLL *declines* to ship is partly implicit. The professor's Vazou-inspired framing implicitly opens the door to abstract refinements, bounded refinements, and parametric refinements; the amended critic's narrower framing closes that door explicitly. The triage §3.1 adjudication adopted the narrower framing precisely because LLMLL's surface (no user-side `<:` relation, no dependent elimination, no proof terms) does not match the broader Vazou-closure scope. The non-goals list makes the closure boundary load-bearing.

The soundness statement of record is the project's tier-aware analog to Liquid Haskell's preservation theorem. LLMLL has explicitly declined Path B (mechanized soundness against an independently-defined operational semantics) at [`verification-debate.md`](../../design/verification-debate.md); the soundness statement under Path A is what the project commits to and what `--strict-verified-core` enforces operationally.

---

## 2. Scope

**In scope:**

- Settle the checking-mode inference rule for refinement-aliased types (intro and elim).
- Settle the non-goals list (six items, exhaustive for v0.11).
- Settle the soundness statement of record (tier-aware version, adopted verbatim from the [`critique-2026-05-23-triage.md §3.1`](../../design/critique-2026-05-23-triage.md) adjudication).
- Specify the two-phase implementation correspondence (type-checker handles structural typing; verifier handles refinement-predicate obligation emission) so the spec-level rule and the compiler's actual flow stay consistent.

**Out of scope (deferred to REF-META-2..5):**

- **REF-META-2** — solver-completeness statement (which QF-LIA-shaped predicates the solver is *guaranteed* to discharge vs which fall back to `?proof-required`).
- **REF-META-3** — predicate well-formedness rule (when is `(where [x: T] p)` a legal type definition; restrictions on `p`).
- **REF-META-4** — erasure theorem with construction-side discipline (refinement predicates are erased at codegen; what construction-side discipline preserves their meaning at the Haskell boundary).
- **REF-META-5** — full typing judgment (subsumes REF-META-1's rule in a complete bidirectional system covering all introduction and elimination forms).

**Out of scope under v0.11 freeze policy:**

- No new syntax. `(where [x: T] p)` is the existing surface; this proposal does not change it.
- No new type constructor. `TCustom Name` continues to represent refinement aliases at the AST level per [`compiler/src/LLMLL/Syntax.hs:130`](../../compiler/src/LLMLL/Syntax.hs#L130); no `TRefined` constructor is proposed.
- No new schema field, no `schemaVersion` bump, no `trust_report_version` bump.

**Out of scope by deliberate framing (non-goals — see §4.2):**

- No general refinement subtyping relation `<:` exposed to the user.
- No dependent pattern matching.
- No type-level computation.
- No proof terms (proof obligations are routed to the verifier or to `?proof-required`; users do not author proofs in the surface language).
- No sigma types.
- No boolean-expression-as-type-equality.

---

## 3. Surface

No surface change. `(where [x: T] p)` remains the only form for refinement aliases per [`LLMLL.md §3.4`](../../../LLMLL.md):

```lisp
(type PositiveInt  (where [x: int]    (> x 0)))
(type Word         (where [s: string] (> (string-length s) 0)))
(type GuessCount   (where [n: int]    (>= n 0)))
```

Both S-expression and JSON-AST encodings unchanged. The proposal is a typing-rule clarification, not a surface extension.

---

## 4. Semantics

### 4.1 The checking-mode inference rule

For a refinement-aliased type `A ≜ (where [x: τ] p)` (where `A` is the alias name resolved by `expandAlias` at [`compiler/src/LLMLL/TypeCheck.hs:1443`](../../compiler/src/LLMLL/TypeCheck.hs#L1443) and `τ` is the underlying base type), the checking-mode rule is:

```
Γ ⊢ e : τ ⇝ O
Γ ⊢ p[e/x] obligation
─────────────────────────
Γ ⊢ e ⇐ A ⇝ O ∪ { p[e/x] }
```

**Reading.** Under environment `Γ`, when checking expression `e` against the refinement-aliased type `A`:

1. The expression `e` must synthesize the underlying base type `τ` (the structural compatibility step the type checker already performs at [`TypeCheck.hs:781-787`](../../compiler/src/LLMLL/TypeCheck.hs#L781-L787) and at unify sites at `:969-1003`).
2. The refinement predicate `p[e/x]` — the predicate `p` with the binding variable `x` substituted by the expression `e` — joins the obligation set `O` (the *checked introduction* obligation).
3. The combined judgment `e ⇐ A ⇝ O ∪ { p[e/x] }` says: *expression `e` checks against `A` with the augmented obligation set*.

**Elimination is the dual.** When `Γ` binds `x : A` (i.e., `x` has refinement-aliased type `A`), uses of `x` add `p` as a hypothesis to the typing context for reasoning about expressions containing `x`. Formally:

```
Γ, x : A ⊢ e' : τ' ⇝ O'
─────────────────────────────────────
Γ, x : τ, p ⊢ e' : τ' ⇝ O'   (elim)
```

This is the standard refinement-types pattern: introduction emits an obligation, elimination introduces a hypothesis. The pair makes refinement aliases function as *checked invariants* without exposing a user-visible subtyping relation.

**Two-phase implementation correspondence.** The compiler implements this rule across two phases, and the proposal does not require a refactor:

- **Phase 1 — type checker.** [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) handles the structural compatibility step (`Γ ⊢ e : τ`) via `inferExpr` / `checkExpr` / `unify`. Refinement aliases are resolved structurally via `expandAlias` at line `1443`; the underlying base type `τ` participates in unification.
- **Phase 2 — verifier emit.** [`compiler/src/LLMLL/Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs) and [`compiler/src/LLMLL/FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs) emit the refinement-predicate obligation `p[e/x]` at intro sites (function parameter binding, return-type checking, pattern destructuring of refinement-typed values) and add the corresponding hypothesis at elim sites.

The unified spec-level judgment `Γ ⊢ e ⇐ A ⇝ O ∪ { p[e/x] }` is the conjunction of both phases. The proposal does not require a single-pass implementation; it requires that both phases together discharge the rule.

### 4.2 Explicit non-goals

Six non-goals are part of the rule of record. Each closes a Vazou-closure scope expansion that LLMLL deliberately declines:

1. **No general refinement subtyping (`<:`).** LLMLL has no user-visible subtyping relation between refinement-aliased types. Liquid Haskell's `{x:Int | P} <: {x:Int | Q}` iff `P ⇒ Q` valid in QF-LIA is *not* exposed in LLMLL's surface; refinement aliases interact only via the checking-mode rule above, which generates obligations at concrete introduction sites rather than verifying entailment between types. The two are operationally equivalent at checked introduction (Liquid Haskell's "subtyping" is exactly the checking-mode rule under a different name), but LLMLL's narrower surface pre-empts the implicit closure of abstract refinements, parametric refinements, and bounded refinements that the broader subtyping framing would invite.

   **Operational-equivalence joint reading.** Per the Rev 1 professor review's Q-PROF-1 (folded), the operational equivalence is *load-bearing at the v0.11 surface*, not merely consonant — conditional on the §4.1 elimination rule's hypothesis-in-context discharge. At an introduction site `Γ ⊢ e ⇐ A`, both frameworks generate the same obligation `p[e/x]`. At an elimination site where `Γ` binds `x : A` and `x` flows into a call-site with refinement-aliased parameter type `B ≜ (where [x: τ] q)`, Vazou's subtyping discharges the call-site obligation `q[e/x]` against `<:` from `p`; LLMLL's checking-mode rule discharges the same obligation against the in-context hypothesis `p` introduced by the §4.1 elim rule at `x`'s binding site. The two systems converge on the same proof obligations and the same QF-LIA discharge. The Vazou *Abstract Refinement Types* (ESOP 2013) machinery — refinement variables, refinement polymorphism — is the only divergence; it is closed off per the Rev 2 §4.2 closure-scope clarification below.

2. **No dependent pattern matching.** Pattern matching on refinement-aliased values destructures the *underlying* base type. A `match` arm against a `Letter` value (where `Letter ≜ (where [s: string] (= (string-length s) 1))`) binds a `string`, not a "string-known-to-be-length-1." The refinement hypothesis is added to the typing context via the elimination rule (§4.1), but it does not refine the bound variable's type.

3. **No type-level computation.** Refinement predicates are first-order propositions in the QF-LIA fragment (or escape to `?proof-required`); they are not types. `(where [n: int] (> (factorial n) 0))` is not legal even if `factorial` is total — the predicate must be a first-order proposition over base-typed bindings, not a type-level computation.

4. **No proof terms.** Users do not author proof terms in LLMLL surface. Proof obligations are discharged by the verifier (QF-LIA fragment, auto-discharged by liquid-fixpoint per [`§5.3.3 / §5.3.5`](../../../LLMLL.md)) or routed to `?proof-required` for offline discharge (Leanstral pipeline). A function with an `?proof-required` hole produces an `asserted`-tier evidence record; no proof script is authored in LLMLL.

5. **No sigma types.** LLMLL has no dependent pair `Σ x : τ. p[x]`. The closest analog is the refinement-aliased type `A ≜ (where [x: τ] p)` itself, but `A` is not a pair — there is no first projection that extracts `x` and no second projection that extracts a proof of `p[x]`. Values of refinement-aliased types are values of the underlying base type that have been checked against the refinement at construction.

6. **No boolean-expression-as-type-equality.** LLMLL has no propositional equality type `e₁ ≡ e₂`. A refinement predicate may *use* an equality expression (`(= x 0)`), but no type-level proposition `e₁ ≡ e₂` exists, and no inhabitant of such a type can be constructed or pattern-matched on.

These six non-goals are exhaustive for v0.11. The list is closed; any feature beyond the surface in §3 and the rule in §4.1 requires explicit team consensus with a written soundness argument per the freeze-exception discipline at [`docs/compiler-team-roadmap.md:33-36`](../../compiler-team-roadmap.md#L33-L36).

**Closure-scope clarification (Rev 2, per the professor review's Gap #2).** Liquid Haskell ships several additional refinement-type features that lie within the Vazou-closure scope but are not enumerated above as separate non-goals: notably **refinement-polymorphic functions** (functions parametric over a refinement predicate, e.g. `forall (p : a -> Bool). ({x:a | p x} -> {y:a | p y})` per Vazou et al. *Abstract Refinement Types* ESOP 2013) and **termination-via-refinement** (refinement-encoded measures driving decreasing-call obligations). These are *not* separate v0.11 omissions; they are *consequences* of non-goal #1 (no general refinement subtyping) and non-goal #3 (no type-level computation) respectively, deferred to **REF-META-3 — predicate well-formedness rule** for explicit treatment of refinement-variable binding shapes. Future LT proposals that would re-introduce either feature must engage REF-META-3 first; that proposal's WF rule is the natural place to enumerate the refinement-predicate-binding shapes admitted (currently only `(where [x: T] p)` with a single free binding).

### 4.3 Soundness statement of record (tier-aware)

Adopted verbatim from [`critique-2026-05-23-triage.md §3.1`](../../design/critique-2026-05-23-triage.md):

> If `Γ ⊢ e : τ ⇝ O`, all obligations in `O` are discharged at solver-backed evidence level, codegen is faithful for the involved constructs, and no trusted FFI/opaque primitive is used, then the erased generated program preserves the declared refinement predicates at checked introduction and elimination sites.

**Tier-awareness.** The conditional structure of the statement is load-bearing. Soundness is asserted only when *all four* preconditions hold:

1. **Obligations discharged at solver-backed evidence level.** The function's evidence-tier record (per [`§4.4`](../../../LLMLL.md) evidence model) is `verified` with body-faithful discharge — not `tested`, not `asserted`, and not `verified` with body-fallback at [`FixpointEmit.hs:506-516`](../../compiler/src/LLMLL/FixpointEmit.hs#L506-L516).
2. **Codegen is faithful.** The construct lowering at [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs) preserves the semantics the verifier proved against. Per [`§5.3.5`](../../../LLMLL.md), the body-faithful set is non-recursive QF-LIA with compositional call-chain reasoning; constructs outside that set lower into runtime assertions or fall back to contract-only verification, and the soundness claim does not extend to them under the same tier.
3. **No trusted FFI or opaque primitive.** Functions transitively reaching crypto stubs (per [`§13.11`](../../../LLMLL.md) `asserted-with-stub-backend` channel) or other `asserted`-tier dependencies do not satisfy the precondition.
4. **`erBodyFallback` is not set, and `erOverflowTainted` is not set.** The v0.10.8 INT-1 mechanism at [`Syntax.hs:326-331`](../../compiler/src/LLMLL/Syntax.hs#L326-L331) explicitly marks overflow-tainted verified evidence; `--strict-verified-core` refuses such evidence per [`Main.hs:1119-1158`](../../compiler/app/Main.hs#L1119-L1158). The soundness statement applies under the strict tier.

> **Correction, 2026-08-19 (`CRYPTO-2`).** This document is archived and is left otherwise unchanged
> as a record. Precondition 3 above cites an `asserted-with-stub-backend` channel at `LLMLL.md`
> §13.11. That channel was never implemented and has been retracted. The precondition itself is
> unaffected, because it already turns on `asserted`-tier dependencies in general: a function whose
> trust closure reaches `sha1` or `hmac-sha1` is capped at `asserted`, and that cap is real and
> emitted. Read the citation as naming that cap, not a separate channel.

**Operational enforcement.** `--strict-verified-core` is the operational embodiment of this statement: a function whose evidence record satisfies all four preconditions is admitted; a function that fails any precondition (body-fallback, overflow-tainted, asserted dependency, or non-verified tier) is refused. The strict tier is the program-level evaluation of the soundness statement.

**Closure under composition (Rev 2, per the professor review's Gap #3).** The statement above is *single-function*: it asserts refinement-predicate preservation for one function under four preconditions. The multi-function reading — that refinement-predicate preservation extends through a function's transitive call graph — is the *closure under composition* of the single-function property. The closure is what `--strict-verified-core` enforces operationally: a function fails admission if any callee in its transitive call graph has `erBodyFallback = True`, `erOverflowTainted = True`, or an `asserted`-tier dependency. The strict-tier admissibility set is therefore the closure of the single-function property under composition, not an individual-function property. Formal derivation of the closure (e.g., a per-call-site preservation lemma plus a transitive inductive argument) is **REF-META-4 territory** (erasure theorem with construction-side discipline); the prose acknowledgment here closes the multi-function reading at the spec-of-record level. Liquid Haskell's analogous closure (Vazou et al. POPL 2014 §6) is similarly stated per-top-level-definition and inherited compositionally via the type system's structure; LLMLL inherits the same discipline.

**What is explicitly declined.** Path B (a mechanized soundness theorem proven against an independently-defined operational semantics) remains declined per [`verification-debate.md`](../../design/verification-debate.md) Q1-Q5. Liquid Haskell shipped without mechanized soundness for a decade; LLMLL inherits the same pragmatic stance. The soundness statement of record is a precise *statement* of the project's commitment, not a *theorem* in the mechanized sense.

---

## 5. Edge cases

Five representative edge cases, each classified by verification channel and citing the spec or compiler line that catches it.

### 5.1 Refinement-aliased return type on a `?hole`-bodied function

**Input shape.** A function declared with return type `PositiveInt` and body `?hole`:

```lisp
(def-logic safe-divisor [n: int] -> PositiveInt
  ?hole)
```

**Expected behavior.** The obligation report (per [`§4.4`](../../../LLMLL.md) obligation channels) reports `expected_type: PositiveInt` for `?hole`; the contract obligation channel surfaces `postcondition_goal: (> result 0)` as the refinement predicate `p[result/x]` substituted with the result expression once filled. At the hole, the predicate is not yet discharged because no concrete expression is present; it surfaces as a *goal*, not a *failure*.

**Verification channel.** Type (structural compatibility on the hole) + contract (refinement predicate as obligation goal). Per [`compiler/src/LLMLL/ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs) and the three-channel obligation report at [`docs/design/oblig-0-spec.md`](../../design/oblig-0-spec.md).

### 5.2 Refinement-aliased parameter at a call site with a literal vs a variable argument

**Input shape.** A function `consume :: PositiveInt -> int` called with `(consume 5)` versus `(consume x)` where `x: int`:

```lisp
(def-logic consume [n: PositiveInt] -> int (+ n 1))

(def-logic f [x: int] -> int
  (consume x))                  ;; obligation: (> x 0)

(def-logic g [] -> int
  (consume 5))                  ;; obligation: (> 5 0) — constant-folded
```

**Expected behavior.** At the literal call site `(consume 5)`, the obligation `(> 5 0)` is discharged by constant folding in the QF-LIA solver — `True` immediately. At the variable call site `(consume x)`, the obligation `(> x 0)` joins `f`'s body VC; the verifier proves it under whatever path conditions `f`'s caller-side preconditions imply (often by routing the obligation back to `f`'s callers via the assume-guarantee chain).

**Verification channel.** Contract; QF-LIA (auto-discharged by liquid-fixpoint at [`FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs)).

### 5.3 Refinement predicate that uses non-QF-LIA arithmetic

**Input shape.** A `BlockID` type defined with a `regex-match` predicate:

```lisp
(type BlockID (where [s: string] (regex-match "^[a-f0-9]{64}$" s)))
```

**Expected behavior.** The refinement predicate `regex-match` is outside QF-LIA. Per [`§5.3.3 / §5.3.5`](../../../LLMLL.md), the obligation channels to runtime assertion (the `asserted` tier) or, with explicit annotation, to `?proof-required` for offline discharge. The function carrying the refinement-typed binding is *not* in the strict-verified-core admissibility set; `--strict-verified-core` refuses it. This is the **intentional** consequence of the verification matrix: refinement predicates outside QF-LIA do not get free solver-backed evidence.

**Verification channel.** Trust (the obligation falls outside type and contract channels). Spec is silent on which non-QF-LIA primitives are admissible inside refinement predicates — *this is intentional* and is the seam REF-META-2 (solver-completeness statement) will codify; REF-META-1 does not promise more.

### 5.4 Pattern matching on a refinement-aliased value

**Input shape.** Pattern matching on a `Letter` (refined `string`):

```lisp
(type Letter (where [s: string] (= (string-length s) 1)))

(def-logic first-char [l: Letter] -> string
  (match l
    (s s)))                     ;; binds s : string; refinement (= (string-length s) 1) is a hypothesis
```

**Expected behavior.** The match arm binds `s : string` (the underlying base type, per non-goal §4.2 #2). The refinement `(= (string-length s) 1)` is added to the typing context as a *hypothesis* via the elimination rule (§4.1). Subsequent obligations involving `s` may use the hypothesis to discharge length-related predicates without recourse to the verifier.

**Lexical scoping (Rev 2, per the professor review's Gap #4).** The refinement hypothesis introduced at the binding site is *lexically scoped* — it is available within the match arm's body but does not propagate outside the arm into the surrounding expression. LLMLL has no flow-sensitive refinement reasoning: a variable's refinement hypothesis is determined by its declared type at the binding site (non-goal §4.2 #1 — no general refinement subtyping — is the load-bearing reason), not by program flow. If the agent needs the refinement to be available across multiple uses of `s`, the declared type of `s` must carry the refinement (e.g., a `where [s: string] (= (string-length s) 1)` parameter type or a refinement-aliased local binding); destructuring a wider type into an unrefined base type and then deriving a refinement hypothesis is admissible *within the destructuring arm only*. This matches LH's lexical-scoping treatment of refinement hypotheses (Vazou et al. POPL 2014 §3); LLMLL has not adopted the Vazou ESOP 2013 abstract-interpretation extension that would make the hypothesis flow-sensitive.

**Verification channel.** Type (the bound variable is `string`, not "string-known-to-be-length-1") + contract (the hypothesis is available to liquid-fixpoint for downstream obligations within the arm's lexical scope).

### 5.5 Refinement on a sum-type element

**Input shape.** A custom sum type `Result[PositiveInt, string]` where the `Success` constructor carries a `PositiveInt`:

```lisp
(type SuccessfulCount Result[PositiveInt, string])

(def-logic count-result [n: int] -> SuccessfulCount
  (if (> n 0)
      (Success n)
      (Error "non-positive")))
```

**Expected behavior.** The `Success n` construction is a checked introduction of `PositiveInt` — the refinement obligation `(> n 0)` joins the obligation set at the introduction site. Under the `(if (> n 0) ...)` guard, the path condition `(> n 0)` discharges the obligation via the existing path-condition mechanism at [`FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs) (`FlatPath` guards). Without the guard, the verifier would emit a `UNSAFE` diagnostic naming the unmet refinement obligation.

**Verification channel.** Contract; QF-LIA.

**Refinement on the sum type itself (Rev 2, per the professor review's Gap #5).** §5.5 demonstrates the *payload-refinement* case — a refinement (`PositiveInt`) on a `Success` constructor's payload. A distinct case is not shown: a refinement alias on the sum type itself, e.g. `(type SuccessOnly (where [r: Result] (is-ok r)))`. The `where` form syntactically admits this shape; whether the predicate `(is-ok r)` is QF-LIA-tractable depends on `is-ok`'s implementation (a builtin returning `bool` with a known refinement signature is QF-LIA; an opaque or recursive `is-ok` routes to runtime or `?proof-required` per §5.3). REF-META-1 does not enumerate the well-formedness conditions on such predicates; the formal treatment is **REF-META-3 territory** (predicate well-formedness rule). For v0.11, refinement-on-sum-type-itself is admitted syntactically and discharged per the per-predicate fragment classification at §5.3 (QF-LIA / nonlinear / `?proof-required`), with no separate channel introduced.

---

## 6. Verification mapping

No new obligation channel. No new verifier mechanism. REF-META-1's rule is a *codification* of the existing intro/elim machinery, not an extension.

| Channel | Fragment | Compiler module emitting the constraint |
|---|---|---|
| Type (structural compatibility, alias expansion) | n/a (typing, not VC) | [`TypeCheck.hs:1443`](../../compiler/src/LLMLL/TypeCheck.hs#L1443) (`expandAlias`), [`TypeCheck.hs:781-787, 969-1003`](../../compiler/src/LLMLL/TypeCheck.hs#L781) (`checkExpr` / `unify` sites) |
| Contract (refinement predicate as obligation at checked-intro sites) | **QF-LIA** when `p` is linear over the base-type binding (auto-discharged by liquid-fixpoint per [`§5.3.3`](../../../LLMLL.md)) | [`Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs), [`FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs) |
| Contract (refinement predicate at elim sites) | QF-LIA hypothesis added to the typing-context obligation under the elimination rule (§4.1) | [`Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs); per-clause hypothesis assembly |
| Trust (refinement predicate outside QF-LIA) | **Nonlinear or quantified** — escapes to runtime assertion (`asserted` tier) or to `?proof-required` for offline discharge | [`Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs) runtime-assertion fallback; [`LeanTranslate.hs`](../../compiler/src/LLMLL/LeanTranslate.hs) `?proof-required` translation |

**Boundary cite.** Per [`LLMLL.md §5.3.3 / §5.3.5`](../../../LLMLL.md): non-recursive QF-LIA is the body-faithful fragment; refinement predicates outside this fragment fall back to contract-only or runtime per the verification matrix.

**No fragment is forced into "Lean" by default.** Refinement predicates over `int` bindings with linear arithmetic remain in QF-LIA; only predicates the solver provably cannot discharge route to `?proof-required`. Default-routing refinement obligations to Lean would invert the project's verification ergonomics.

---

## 7. Affected surface

**Settled spec surface — `documentation-lead` promotion targets:**

- [`LLMLL.md §3.4`](../../../LLMLL.md) — current "Refinement Type Aliases" subsection. Add: the checking-mode inference rule (§4.1), explicit non-goals (§4.2), soundness statement of record (§4.3). Cross-reference §5.3.5 for the verification-channel matrix.
- [`LLMLL.md §5.3.3 / §5.3.5`](../../../LLMLL.md) — verification matrix. Add a row or cross-reference clarifying that refinement-alias predicate obligations route through the same QF-LIA / nonlinear / `?proof-required` channels as ordinary contract obligations; no separate channel introduced.
- [`LLMLL.md §11`](../../../LLMLL.md) — Multi-Agent Concurrency section is the closest to an "inference rules" subsection in the current spec; if a dedicated §X.Y "Inference Rules" subsection is added in REF-META-5, the rule from §4.1 migrates there. For REF-META-1, surfacing the rule in §3.4 prose with conventional notation is sufficient.

**No compiler-source change implied.** The two-phase implementation correspondence (§4.1) explicitly states that the proposal is consistent with the existing flow:
- Type checker handles structural typing via `expandAlias` / `checkExpr` / `unify` (no change).
- Verifier handles refinement-predicate emission at intro/elim sites via `Contracts.hs` / `FixpointEmit.hs` (no change).

If `compiler-engineer` audit reveals that the verifier does *not* emit refinement-predicate obligations at all the intro/elim sites the rule names (e.g., refinement aliases inside sum-type payloads at §5.5), that is a spec/code drift finding routed to a separate engineer ticket — REF-META-1 does not author the fix; it codifies the spec-level rule the audit measures against.

**No schema delta.** JSON-AST `schemaVersion` stays `0.5.0`. No `trust_report_version` bump. No new diagnostics. No new builtin.

**No CHANGELOG entry.** REF-META-1 promotion via `documentation-lead` is a spec pedagogy clarification; no user-visible compiler behavior changes. CHANGELOG silence is appropriate.

### 7.1 Verifier emission-site checklist (Rev 2, per the professor review's Gap #6)

The spec-level rule at §4.1 names introduction and elimination sites where the verifier should emit refinement-predicate obligations. The current compiler may emit at a subset of these sites. The Rev 2 checklist below is the *engineer-audit measurement target* — the named sites the verifier must be confirmed to emit at, with the audit's findings routed back to engineer for any gaps:

1. **Function parameter binding (callee-side intro).** When a function `f` has a refinement-aliased parameter `(x: A)` where `A ≜ (where [v: τ] p)`, the verifier emits the refinement obligation `p[arg/v]` at each call site `f(arg)`. Compiler module: [`compiler/src/LLMLL/Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs) + [`compiler/src/LLMLL/FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs).

2. **Return-type checking (caller-side intro).** When a function `f` has a refinement-aliased return type `-> A`, the verifier emits the refinement obligation `p[result/v]` against the body's actual return expression. Compiler module: same as (1).

3. **Pattern destructuring of refinement-typed values (elim).** When a `match` arm binds `x : A`, the verifier *adds* the refinement `p` as a hypothesis to the typing context for the arm body's downstream obligations. The hypothesis is lexically scoped per §5.4 Rev 2 commitment. Compiler module: [`compiler/src/LLMLL/Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs) (per-clause hypothesis assembly).

4. **Sum-type constructor application with refinement-typed payload (intro).** When a sum-type constructor `Success(e)` carries a refinement-typed payload `A`, the verifier emits the refinement obligation `p[e/v]` at the construction site per §5.5. Compiler module: same as (1).

5. **`let`-binding with refinement-typed RHS (intro).** When `(let [(x: A) e1] e2)` declares `x` at refinement-aliased type `A`, the verifier emits the obligation `p[e1/v]` at the `let` site and adds the hypothesis `p` to the context for `e2`. Compiler module: same as (1).

6. **`?hole` filling under refinement-typed expected type (deferred intro).** When `?hole` appears in a position whose expected type is refinement-aliased `A`, the obligation report surfaces `postcondition_goal: p[result/v]` (per §5.1) but no obligation is yet emitted to the verifier (the hole is unfilled). When the hole is filled with `e`, the obligation `p[e/v]` is emitted per (1)-(5) depending on the syntactic position. Compiler module: [`compiler/src/LLMLL/ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs) (goal-state reporting); [`compiler/src/LLMLL/Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs) (post-fill emission).

**Audit-finding routing.** Any site at which the verifier does *not* currently emit the named obligation is a *spec/code drift finding* routed to a separate compiler-engineer ticket (not a REF-META-1 revision). The audit measures the compiler against this checklist; the spec is the measurement target, not the implementation. If audit reveals gaps, the engineer ticket carries the citation (`§7.1 site N`) and the proposal stays at Rev 2 — the audit's findings do not re-litigate the spec.

---

## 8. Risks and open questions

1. **Spec/code drift between the rule (§4.1) and the verifier's actual emission sites.** *Classify: spec-drift.* Source: the proposal asserts the verifier emits refinement-predicate obligations at all the intro/elim sites the rule names. The Rev 2 §7.1 emission-site checklist enumerates the six named sites for the engineer audit; the current compiler may emit obligations at a subset of these sites. Bite: medium — if the audit finds gaps, the gap is a verifier-side bug to file as a separate engineer ticket; the proposal's rule does not change. Mitigation: REF-META-1 is the *spec of record* and §7.1 is the *audit checklist*; the audit measures the compiler against the spec, not vice versa. Audit-finding routing per §7.1's "Audit-finding routing" paragraph.

2. **Non-goals list completeness.** *Classify: scope.* Source: §4.2 enumerates six non-goals as "exhaustive for v0.11." Bite: low — the list closes the Vazou-closure scope that the §3.1 adjudication identified, but Liquid Haskell ships *other* refinement-type features (e.g., termination-via-refinement, refinement-polymorphic data types) the list does not name. Adjudication: the six items cover the v0.11 scope boundary; additional non-goals for refinement-polymorphic types, etc., are deferred to REF-META-3 (predicate WF rule) or post-v0.11.

3. **Path A soundness commitment under composition.** *Classify: soundness.* Source: §4.3 states the soundness statement under four preconditions; composition (function `f` satisfying preconditions when calling function `g`) inherits the strongest precondition of the composed pair. Bite: medium — at scale, a single `asserted`-tier dependency anywhere in a function's transitive call graph defeats the soundness claim for the whole graph. This is by design (per [`verification-debate.md`](../../design/verification-debate.md)) but the proposal should be explicit that the strict-verified-core admissibility set is the *closure under composition*, not an individual-function property. Mitigation: §4.3 ¶4 names the strict tier as the operational embodiment; further compositional reasoning is REF-META-4 territory (erasure theorem with construction-side discipline).

4. **Elimination-rule hypothesis scoping.** *Classify: verification-ergonomics.* Source: §4.1 elimination rule states the refinement `p` is added as a hypothesis to the typing context when `x : A` is in scope. The hypothesis remains valid throughout `x`'s lexical scope, but it does not automatically propagate across function boundaries — if `x` is passed to a function expecting `int`, the receiving function does not see the hypothesis unless it also takes a `PositiveInt`-typed parameter. Bite: low — this is the expected behavior of refinement aliases as values vs. dependent typing; the rule is consistent with Liquid Haskell's treatment.

5. **Soundness statement's "checked introduction and elimination sites" coverage.** *Classify: spec-drift.* Source: §4.3 says the statement covers "checked introduction and elimination sites." Some constructs in LLMLL — notably `?delegate` / `?delegate-async` / `?scaffold` holes per [`§6`](../../../LLMLL.md) — introduce values from out-of-process agents whose refinement predicates cannot be checked at compile time. These hole-introduced values are *not* checked-introduction sites under the rule. Bite: low — the soundness statement's wording is precise; out-of-process-agent-introduced values fall under the trust tier per the existing evidence model. Worth a sentence in §4.3 promotion to LLMLL.md naming the carve-out explicitly.

## 9. Open questions for the professor review

1. **Operational-equivalence claim load-bearing or merely consonant?** §4.2 #1 asserts that the amended critic's checking-mode rule is "operationally equivalent" to Liquid Haskell's subtyping-based formulation, and that the narrower framing is preferable on closure-scope grounds. Is the operational-equivalence claim *load-bearing* (the two systems prove the same set of programs valid) or merely *consonant* (they admit substantially overlapping but not identical programs)? Vazou's *Abstract Refinement Types* (ESOP 2013) introduces machinery the checking-mode rule does not have; whether that machinery is *needed* for any programs LLMLL admits is the precise question.

2. **Soundness-statement carve-outs vs the Idris elaboration alternative.** Idris-style elaboration would let users author the proof of `p[e/x]` directly in the surface language and verify it against the spec, avoiding both the QF-LIA-fragment restriction and the `?proof-required` escape hatch. LLMLL has declined this path. Is there a known instance in the literature where a project that adopted the checking-mode-only framing (LLMLL's position) later found the absence of user-authored proofs to be a load-bearing limitation under realistic use? Liquid Haskell's experience report at Haskell '14 is the closest reference; the professor channel's reading of whether that experience extends to LLMLL's agent-authoring conditions would be useful.

---

## 10. Companion review

Professor review landed at [`refinement-metatheory-of-record-review.md`](../professor-reviews/refinement-metatheory-of-record-review.md) (Rev 1, 2026-05-25) as part of the batched four-proposal review turn (LT-INV, LT-CDP, LT-PPR, REF-META-1). Recommendation: `approve with revisions` on six gaps and two author-question answers, all folded into this Rev 2 inline at the marked "Rev 2" touchpoints (§4.2 #1 joint reading; §4.2 closure-scope clarification; §4.3 closure-under-composition; §5.4 lexical scoping; §5.5 refinement-on-sum-type-itself; §7.1 emission-site checklist). The review carried the v0.11 cluster's cross-proposal observations C-1 through C-4; the C-2 settlement landed at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) (Rev 1, 2026-05-25) as a coordination artifact for the LT-INV / LT-CDP / LT-PPR engineer-build sequencing.

The standalone `refinement-metatheory-of-record-review.md` was folded into the §"Appendix — Professor review log" below and archived to [`docs/archive/professor-reviews/refinement-metatheory-of-record-review.md`](../professor-reviews/refinement-metatheory-of-record-review.md) under DOC-CONSOLIDATE §M2 (doc-lead Pass 10, 2026-05-25).

---

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal has been folded into this appendix and the source file archived to `docs/archive/professor-reviews/refinement-metatheory-of-record-review.md`. One line per finding; all resolved in Rev 2 of this proposal.

**Source:** `docs/design/refinement-metatheory-of-record-review.md` at commit `5f31580` (review dated 2026-05-25; reviewer: Lead Consultant for Formal Language Design).

### Gaps (all resolved in Rev 2)

1. **Operational-equivalence claim load-bearing vs consonant.** Rev 1 §4.2 #1 asserted equivalence without referencing the §4.1 elim rule's discharge. Resolved: Rev 2 §4.2 #1 adds the joint-reading paragraph naming the elim rule as the hypothesis-in-context discharge mechanism.
2. **Non-goals list completeness.** Rev 1 closed six non-goals; refinement-polymorphic functions and termination-via-refinement not explicitly named. Resolved: Rev 2 §4.2 adds the closure-scope-clarification paragraph routing both to REF-META-3 (predicate WF rule).
3. **Path A soundness under composition.** Rev 1 §4.3 stated single-function soundness only. Resolved: Rev 2 §4.3 adds the closure-under-composition paragraph naming `--strict-verified-core` as operational embodiment; formal derivation routed to REF-META-4.
4. **Elimination-rule hypothesis scoping.** Rev 1 §4.1 / §5.4 silent on flow-sensitivity. Resolved: Rev 2 §5.4 commits to lexical scoping with reference to non-goal §4.2 #1 as load-bearing reason.
5. **Refinement on sum type itself.** Rev 1 §5.5 demonstrated payload-refinement; sum-type-self refinement not addressed. Resolved: Rev 2 §5.5 adds the refinement-on-the-sum-type-itself paragraph routing the WF question to REF-META-3.
6. **Verifier emission-site checklist absent.** Rev 1 Risk #1 named the audit obligation without specifying the audit target. Resolved: Rev 2 §7.1 enumerates six named emission sites with compiler-module citations.

### Open questions (both resolved in Rev 2)

- **Q-PROF-1.** Is the operational-equivalence claim load-bearing or merely consonant? Resolved: Rev 2 §4.2 #1 — load-bearing at the v0.11 surface, conditional on the §4.1 elim rule's hypothesis-in-context discharge. Vazou ESOP 2013 abstract-refinement machinery is the only divergence; closed off by non-goal §4.2 #1 + Gap #2 routing to REF-META-3.
- **Q-PROF-2.** Idris-style elaboration alternative — LH experience extension? Resolved: yes, LH-user programs have benefitted from user-authored proofs (LH Haskell '14 §5); LLMLL routes these to `?proof-required` per design philosophy / Path A scope; not a soundness defect.

### Cross-proposal observations (C-1 through C-4)

The review carried the v0.11 cluster's cross-proposal observations. C-2 (cross-proposal rollback discipline) is the load-bearing finding; settled at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) (Rev 1, 2026-05-25). C-1 (coherence), C-3 (diagnostic-text ergonomics — deferred to v0.12+), C-4 (sequencing assessment — confirmed correct under all three outcomes) are recorded at the C-2 artifact and the four proposals' Rev 2 references.

### Overall assessment (recorded)

The review recommended `approve with revisions` on six gaps and two author-question answers. Rev 2 (settled 2026-05-25) carries each resolution inline at the cited §-references above. The standalone `refinement-metatheory-of-record-review.md` is archived; this appendix is the in-proposal pointer.
