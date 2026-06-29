# COMP-4 — Payload-Bearing Sum Types (Refined Elimination, Construction, Totality)

> **Version:** Rev 3 — two professor reviews folded. Rev 1 enumerated the sub-slices and proposed a hand-rolled QF-LIA+EUF reflection for introduction. Rev 2 (professor v1 critique) redirected introduction to the **native `FQData` datatype path**, fixed the elimination distinctness conflation, and **resolved Risk 1 empirically** (payload-subtyping is unenforced today), flipping the staging to lead with `(d-elim)`. Rev 3 (professor v2 critique) folds three precision fixes: (1) the decidability justification is **polite-theory combination**, not Nelson–Oppen; (2) the recursive-type exclusion is **transitive-closure acyclicity**, not "T's own constructors"; (3) introduction is **constructor reflection into `FQData`, orthogonal to the trust tier** (reflection ⊥ trust).
> **Date:** 2026-06-27 (Rev 1; Rev 2; Rev 3)
> **Implements:** Active-Items row `COMP-3b-general / COMP-4` (`docs/compiler-team-roadmap.md`). Continues the COMP-3b → COMP-3c → COMP-3b-general line. **COMP-3b-general (opaque-sum elimination, exhaustiveness-only) shipped v0.13.6**; COMP-4 is the remainder.
> **Prerequisites:** COMP-3b-general machinery (binder-carrying `BranchVC`, `collectBranchBinders`, derived `SortEnv` payload-sort keys, the new `EMatch` clause — `FixpointEmit.hs`). The native datatype substrate: `FQData`/`FQDataDecl`/`fqcArgs`/`emitDataDecl` (`FixpointIR.hs:55-61,148-163,279`), already emitted per sum type by `typeSorts` (`FixpointEmit.hs:736-739`) and v0.13.3-debugged against liquid-fixpoint.
> **Reviewed:** Three professor critiques — Rev 1 → Rev 2 redirect; Rev 2 → Rev 3 precision fixes (both folded into the Version line above); plus a third pass on the (b) two forks (gating + emission channel) folded into §9/§13 at the v0.13.8 implementation. **No standalone review file** — the M2 fold is in-frontmatter.
> **Status:** Settled (Rev 3) — **FULLY SHIPPED.** `(d-elim)` v0.13.7 (`0cf53e9`); (b) + the payload-subtyping call-site obligation v0.13.8 (`ebf812d`); **(a)/(c) construction / payload-carrying `Rejected` totality v0.13.9** (`a6e5ff2` / `e6bae55`) — native `FQData` construction, gated on `admissibleDatatype` (§5), the first verification beyond pure QF-LIA. The COMP-4 line is complete; this proposal is retained as the shipped-design reference (archive-eligible).

---

## 1. Background

The COMP-3b/3c/3b-general line made *sum-type verification* progressively reachable in the QF-LIA core: COMP-3c (v0.13.5) verifies idiomatic **nullary enums** (constructors as int tags via `desugarCtorValues`); COMP-3b-general (v0.13.6) verifies an **opaque `Result`-typed variable match at any nesting depth**, binding each arm's payload as an **unconstrained skolem** (`FQTrue`) — *exhaustiveness-only*: it proves the post for *any* payload, and does not consume a matched payload's own refinement.

COMP-4 is the bundled remainder: everything sum-type-shaped that COMP-3b-general deferred. The Rev-1 decomposition holds, and the **organizing principle (professor↔language-team convergence)** is the **elimination/introduction split**: *eliminating* an opaque sum needs only a discriminator + payload skolems (no theory beyond the payload sorts); *introducing* a sum value — constructing it as a first-class logical term — is the only operation that requires representing the tagged union in the logic.

## 2. Sub-slice decomposition

| Slice | What | Fragment | Status |
|---|---|---|---|
| **(d-elim)** | two-arm **user-ADT** elimination (beyond `Result`) | QF-LIA (skolem-branch) | **first** — sound today |
| **(b)** | **completeness**: consume a matched payload's own refinement | QF-LIA + a new call-site obligation | gated on the payload-subtyping prerequisite |
| **(a)** | **construction** of a payload sum value as a logical term | QF-LIA + EUF + non-recursive datatypes | native `FQData` |
| **(c)** | payload-carrying `Rejected` for illegal→REJECTED **totality** | = (a) over an N-arm ADT | downstream of (a)+(d) |

(c) is **not independent** — it is (a) applied to an N-way ADT; it folds into (a)+(d).

## 3. Design — elimination: (d-elim) and (b)

**(d-elim) — general two-arm user-ADT elimination.** Generalize the `Result`-specific `classifyResultArms` to an arbitrary two-arm user `TSumType`: read the payload sorts from the `STypeDef`, bind each arm's payload as an `FQTrue` skolem at its declared sort, and emit the existing two-path `BranchVC` (`collectBranchBinders` declares the guard + payloads). **No new theory** — the skolem-branch is the shipped COMP-3b-general encoding; only the scrutinee classifier and the payload-sort lookup generalize (the derived-`SortEnv`-key mechanism extends directly). Distinctness/exhaustiveness are discharged **structurally** (the synthetic boolean guard's case-split + the type-checker's exhaustiveness check), exactly as today — *no datatype distinctness axiom needed for elimination*.

**(b) — completeness.** Replace the `FQTrue` payload binder with the payload's **guaranteed refinement**: for `r : Result[PositiveInt, E]`, the Success arm binds `n` at `{v:int | v > 0}`. This is a refinement-predicate strengthening on the already-declared binder — same QF-LIA fragment as the consuming post. **Sound sourcing rule:** the refinement is sourced from the value's *guaranteeing introduction* — the callee's return-type payload refinement (`cenv`, assume-guarantee) for a call scrutinee; the param's declared payload type for a param scrutinee. **Never** a bare local annotation.

**The hard gate on (b) (Risk 1, resolved Rev 2).** (b)'s soundness requires that call sites are obligated to supply a Result whose payload satisfies the declared refinement — i.e. `Result[T₁,E] <: Result[T₂,E] ⟸ T₁ <: T₂` is checked at the call. **This is empirically *unenforced* today** (`TypeCheck.hs` expands refinement aliases to base types at call sites — `LLMLL.md §3.3:213`; no obligation descends into a `Result` param's payload; COMP-3b-general's `FQTrue` binding is the corroborating tell). COMP-3b-general binds `FQTrue` *precisely to avoid this dependency*. Therefore **(b) cannot ship until the payload-subtyping call-site obligation is built** — it becomes a shared prerequisite for (b) and (a). This is the reason the staging leads with (d-elim) (§9).

## 4. Design — introduction: (a)/(c) on the native `FQData` path

Construction is the only fragment-extending slice. **It is built on the existing native datatype path, not a hand-rolled reflection.** liquid-fixpoint already declares user sum types as datatypes — `FQData Text` sort, `FQDataDecl` with `fqcArgs :: [FQSort]` (selector sorts), `emitDataDecl`, all v0.13.3-validated; `typeSorts` already emits a declaration per sum type (currently arity 0). (a) **activates** this:

- Extend `typeSorts` to emit **real payload arities and argument sorts** (`fqcArgs`) instead of `(c, 0)`.
- Add **constructor-application and selector translation** in `exprToPred`/`bodyToPredM` (which currently bail on construction). A constructed `(C e)` reflects to the datatype term; the solver reasons via Z3's datatype theory: `tag(C e) = k`, `sel_C(C e) = ⟦e⟧`, injectivity, distinctness.

Distinctness/injectivity for **introduction** come from the **datatype theory's per-constructor axioms** (Z3-supplied), **not** the elimination guard — the guard is an elimination device (the Rev-2 conflation fix). Nesting (`(Success (Bad x))`) is handled by Z3's selector composition natively — no per-term axiom recursion.

## 5. Admissibility predicate (the recursive-type firewall)

The native datatype path is **decidable**; and the **quantifier-free theory of recursive data types is itself decidable** (Barrett–Shikanian–Tinelli, CADE 2007; Reynolds–Blanchette, *A Decision Procedure for (Co)datatypes in SMT Solvers*, JAR 2018 — the procedure z3 runs), so the acyclicity exclusion does **not** guard datatype-theory decidability. What it firewalls is the recursive **measure** a recursive type invites — a measure's defining axiom (`len(cons x xs) = 1 + len(xs)`) is quantified, and its non-terminating instantiation escapes the decidable QF / local-theory-extension fragment. (PAIR-RET's single-constructor product is trivially acyclic and unaffected.) The exclusion predicate is **transitive-closure acyclicity** (the Rev-3 fix; the naive "T has no T-sorted argument" is *insufficient* — `Wrapper = Wrap Tree` over recursive `Tree` passes it yet drags `Tree` in):

> A `TSumType` `T` is **admissible** to the body-faithful tier **iff the type-dependency graph restricted to `T`'s transitive constructor-argument-sort closure is acyclic** — every type reachable from `T` by following constructor argument sorts (transitively) is itself non-recursive. Mutual recursion (`A = MkA B`, `B = MkB A`) is the cyclic case; the `Wrapper`/`Tree` case is the reachability case.

**Where it lives:** a pure `admissibleDatatype :: AliasMap → Type → Bool` (sited with `isIntLike`/`buildCtorTagMap`, `FixpointEmit.hs`) that walks the `STypeDef` graph and tests acyclicity of the reachable closure. The introduction *and* elimination translation consult it; any constructed or eliminated value whose type fails it routes to `exprToPred → Nothing` → `erBodyFallback` — the existing **soundness firewall** (`LLMLL.md §5.3.3:335`), mechanism unchanged. Recursive ADTs fall back soundly; they are out of COMP-4 scope.

## 6. Verification mapping

- **(d-elim):** contract, **QF-LIA** (skolem-branch). Cite `LLMLL.md §5.3.3`.
- **(b):** contract, **QF-LIA** (payload-binder refinement) + a new **payload-subtyping call-site obligation** (type/contract channel, the Risk-1 prerequisite).
- **(a)/(c):** contract, **QF-LIA + EUF + non-recursive datatypes**, **decidable**.

**Fragment-statement update (the Rev-3 decidability fix).** The certified fragment extends from QF-LIA(+EUF) to **QF-LIA + EUF + non-recursive datatypes**. The combination is decidable **by polite (strongly-polite) theory combination** — Ranise–Ringeissen–Zarba, *Combining Data Structures with Nonstably-Infinite Theories* (FroCoS 2005); Jovanović–Barrett, *Polite Theories Revisited* (LPAR 2010) — **not** classic Nelson–Oppen: the non-recursive datatype theory is **not stably-infinite** (a nullary enum has finite models — `ConnState` has exactly 5 elements), and politeness is what licenses combination over the **shared `int` sort** that selectors (`sel : Foo → int`) introduce. Z3 implements this. The `§5.3.4` "`SAFE` is a decidable predicate" closure argument **extends cleanly** — body-faithful VCs remain over a decidable fragment.

## 7. Reflection ⊥ trust (the introduction/trust boundary)

Introduction must **not** re-tier the constructor builtins. `ok`/`err` (`TypeCheck.hs:127-131`) are **trusted builtins with no LLMLL body**; "make them body-faithful" is a category error (body-faithfulness is a body-VC property). What (a) needs is **logical reflection** — the solver knowing `tag(ok x)=0 ∧ sel_ok(ok x)=x` via the native datatype theory — which is **orthogonal to the trust tier**. `LLMLL.md §5.3.3:313` already pins this orthogonality (erasure/proof-irrelevance vs. the *Refinement Reflection*, POPL 2018, boundary). So: `ok`/`err` and user constructors are **reflected into `FQData`** (gaining tag/selector axioms) **without changing their trust tier**; a function that *constructs and returns* `(ok x)` earns a **body-faithful VC for its own postcondition** (the construction reflected and reasoned about), while `ok` itself **remains trusted**. The trust closure stays clean — no builtin-with-no-body claims the body-faithful tier.

## 8. Edge cases and degenerate inputs

1. **Unrefined payload** `Result[int,E]`, Success arm uses `n`: (b) is a no-op (refinement `true`). *Channel: contract; silent-intentional.*
2. **Refined payload consumed** `Result[PositiveInt,E]`, post needs `n>0`: under (b), binder `{v|v>0}` — **sound only once the call-site payload obligation exists** (Risk 1). *Channel: contract (QF-LIA) + new call-pre.*
3. **Constructed value returned** `(def f … -> Result[int,E] (ok x))`: under (a), `(ok x)` reflects to `FQData`; `f` earns a body-faithful VC; `ok` stays trusted (§7). *Channel: contract (QF-LIA + datatypes).*
4. **Two-arm user ADT** match (non-Result): (d-elim) skolem-branch. *Channel: contract (QF-LIA).*
5. **Reachably-recursive ADT** `Wrapper = Wrap Tree`, `Tree = Leaf int | Node Tree Tree`: `admissibleDatatype` finds `Tree` in a cycle → both excluded; construct/eliminate falls back. *Channel: trust (firewall §5); intentional (§5).*
6. **Nested construction** `(Success (Bad x))`: native datatype theory composes selectors — no per-term-axiom recursion. *Channel: contract (datatypes).*

## 9. Staging (the soundness-critical result)

1. **(d-elim) first** — ✅ **SHIPPED v0.13.7** (`0cf53e9`). Pure elimination, exhaustiveness-only over user ADTs, QF-LIA, zero new soundness dependency; a direct extension of the shipped COMP-3b-general skolem-branch.
2. **The payload-subtyping call-site obligation** — ✅ **SHIPPED v0.13.8** (`ebf812d`). Built as a standalone refinement-subtyping Horn constraint at the **CallVC site** (`FixpointEmit.hs`), *not* a `TypeCheck.hs` check — the third professor pass resolved the emission-channel fork: refinement subtyping *is* an SMT implication, generated where the types meet and discharged by liquid-fixpoint, with a syntactic-reflexivity fast-path. **Declaration-driven** (the gating fork — the refinement is a caller contract derivable from the signature, like a `Word` bound).
3. **(b) completeness** — ✅ **SHIPPED v0.13.8** (`ebf812d`). The arm consumes the matched payload's refinement (a `ReaderT` `RefEnv` + an `FQPred` on the `BranchVC` binder field), sound because step 2 obligates callers. QF-LIA.
4. **(a)/(c) introduction** — ✅ **SHIPPED v0.13.9** (`a6e5ff2` construction, `e6bae55` totality example). Native `FQData` construction/selector reflection, gated on `admissibleDatatype` (§5); provenance-partitioned beside the int-tag/skolem; the first verification beyond pure QF-LIA (into the SMT datatype theory). Completes the COMP-4 line.

This inverts Rev 1's "(b) first": Rev 1 assumed payload-subtyping held; Rev 2 proved it does not, so the dependency-free (d-elim) leads. The assume/guarantee split for (b) is **clean, no double-counting**: elimination *assumes* the payload refinement; the call-site obligation *guarantees* it; the elimination does not re-prove it.

## 10. Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs` — (d-elim): generalize `classifyResultArms` + payload-sort lookup; **new `admissibleDatatype` + firewall wiring** (§5); `typeSorts` real arities (a); `exprToPred`/`bodyToPredM` constructor + selector translation (a); `collectBranchBinders`/EMatch binder refinement (b).
- `compiler/src/LLMLL/TypeCheck.hs` — **payload-subtyping call-site obligation** (the Risk-1 prerequisite); `collectConstructors` for payload ctors.
- `compiler/src/LLMLL/FixpointIR.hs` / `emitDataDecl` — exercise `fqcArgs` (already present).
- `LLMLL.md §3.3 / §5.3.3 / §5.3.5` — fragment statement (polite combination), admissibility predicate, the reflection⊥trust note (doc-lead, after engineer ships).
- No JSON-AST schema change for (d-elim)/(b). (a) may add a constructor-value node *only if* the existing `EApp`-to-constructor surface is insufficient (confirm during the (a) engineer pass; no bump for (d-elim)/(b)). No strict-immutability concern (construction is pure). No feature-freeze conflict (v0.12+ lane).

## 11. Risks and open questions

1. **Risk 1 — payload-subtyping unenforced** (resolved Rev 2; the gate). *Soundness.* (b) cannot lead; (d-elim) first. Cite `TypeCheck.hs §3.3:213` erasure.
2. **`admissibleDatatype` closure cost.** *Decidability/performance.* Graph traversal over `STypeDef`s; cheap; memoize per emit. Only matters at scale.
3. **Reflection emission discipline.** *Soundness (engineer-side).* Native `FQData` selectors must be emitted for every constructor-application subterm (bottom-up), else completeness gaps. Z3's datatype theory composes selectors — no hand-rolled per-term axioms. Flagged for the engineer.

**Open questions for the professor:** none — the two v2 open-questions are resolved (§5 pins the admissibility predicate; §7 + `§5.3.3:313` separate reflection from trust).

## 12. Provenance and convergence

The professor (datatype-theory reading path) and language-team (LLMLL-internal reading path) **converge** on the **elimination/introduction split**, the **native-`FQData`** introduction, and the **(d-elim)-first staging**. The three Rev-3 precision fixes (polite combination, reachable-closure acyclicity, reflection⊥trust) are repairs the professor surfaced from outside-PL literature; none overturned the direction. This cross-path agreement is the settling signal.

**Tracked-concept note.** COMP-4 sits on the roadmap `COMP-3b-general / COMP-4` row and *continues* (does not approximate or sidestep) the shipped COMP-3b/3c/3b-general mechanisms it cites; the native `FQData` path *activates* infrastructure emitted (inert) since v0.13.3.

## 13. Hand-off

**Code-track (compiler-engineer):** (d-elim) — ✅ shipped v0.13.7. Payload-subtyping obligation + (b) completeness — ✅ shipped v0.13.8 (a third professor pass resolved the gating + emission-channel forks; the obligation lands as an SMT Horn constraint at the CallVC, not a `TypeCheck.hs` check). **(a)/(c) construction — ✅ shipped v0.13.9** — native `FQData` constructor/selector reflection (`exprToPred`/`bodyToPredM`), `typeSorts` real arities, gated on `admissibleDatatype` (§5); the strict-core gate admits admissible-sum constructors. The COMP-4 line is complete.

**Doc-lead (M2):** no standalone review file — the three professor critiques are folded inline (Version line + §9). INDEX one-liner reflects the partial ship.
