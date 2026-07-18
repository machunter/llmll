# Data-Scope Lever A — The SMT Theory of Arrays for `bytes[n]` and `map[k,v]`

> **Status:** Rev 1.1 — professor-reviewed + review folded (Rev 1) + feasibility read folded (Rev 1.1: int-0/1 presence array, §5) — **A0 GO · A1 GO · A2 GO-WITH-CHANGES** per [`data-scope-lever-a-feasibility.md`](data-scope-lever-a-feasibility.md); ready to build
> **Review:** [`data-scope-lever-a-arrays-review.md`](data-scope-lever-a-arrays-review.md) (2026-07-11); dispositions in the Review-fold appendix
> **Track:** Data Scope Extension, Lever A ([`compiler-team-roadmap.md`](../compiler-team-roadmap.md) → *Future — Data Scope Extension*, row A — this document is that row's design record)
> **Didactic companion:** [`data-scope-extension.md`](data-scope-extension.md) Posts 6–8 (rationale); this document is the normative design.
> **Author:** language-team · 2026-07-11 (Rev 0), review fold 2026-07-11 (Rev 1), feasibility amendment 2026-07-11 (Rev 1.1)

---

## Restatement

Widen `Σ_auto` with the quantifier-free SMT theory of arrays (McCarthy `select`/`store`), backing the two compound types the surface already ships — `bytes[n]` and `map[k,v]` — so that array **index-in-bounds** and map **get-after-put** become statically dischargeable obligations. The design constraint inherited from `LLMLL.md` §5.3.3 is absolute: the extension must keep "SAFE" a decidable predicate on a fixed VC, which means the admitted fragment is QF_AX combined with QF-LIA by the polite-combination machinery the datatype class already uses, and everything outside it falls back through the existing four-item routing rather than silently degrading the guarantee. Rev 1 adds the symmetric constraint on the other verdict, as a named invariant: `refuted` must remain a genuine-counterexample claim, which forces every emitted body-faithful VC to be an **exact** reflection (§6.1) — anything reflected approximately routes out before emission.

This proposal **anticipates** the tracked Lever A roadmap row (it is that row's design document), **sidesteps** R1/Lever B (no dependent types are introduced — `bytes[n]`'s `n` is already a type-level literal; we only reflect it as a ground fact), and **defers** Lever C entirely (no induction, no recursive structures).

## Context located

1. `LLMLL.md` §3.2 (`:138`, `:140`) — `bytes[n]` and `map[k,v]` are shipped T1 type formers; `map[k,v]` has **no operations anywhere in §13**; `bytes[n]` is consumed only by the §13.11 crypto builtins.
2. `LLMLL.md` §5.3.3 (`:933–947`) — the `Σ_auto` signature definition, the polite-combination citations (Ranise–Ringeissen–Zarba FroCoS 2005; Jovanović–Barrett LPAR 2010), and the path-(a) ground-fact emission side-condition this proposal extends.
3. `LLMLL.md` §5.3.4 (`:952–989`) — body-faithful VC shape, PROVE/ASSUME call-site polarity, preconditions-never-stripped, `--strict-verified-core` conjuncts; `:962` — "UNSAFE is *refuted* — not *unproven*", the claim §6.1 protects.
4. `LLMLL.md` §5.3.5 (`:993–1038`) — the verification matrix rows this proposal adds to; the `:1004–1005` `ELet` row (single `PVar`, int RHS) that §5.1 extends; the `:1030` note on builtin admission legs and trust-tier propagation.
5. `LLMLL.md` §11.1 (`:2157`) — `=` on `map[k,v]` is **observational** (same key set, equal values at present keys); the semantic anchor of the F1 disposition (§7).
6. `LLMLL.md` §13.5/§13.6 (`:2198–2246`) — the `list-nth : … -> Result[a, string]` totality precedent this proposal deliberately departs from, and the Class-A boundary trust closure (`:2246`) the new runtime builtins join.
7. `compiler/src/LLMLL/FixpointEmit.hs` — `typeToSort` has **no `TBytes`/`TMap` case**; both hit the conservative `FQInt` default (audited at stage A1, §10). `exprToPred` literal cases are `LitInt`/`LitBool` only — no string literal reflects today (F2 disposition, §3). The `$ok`/`$err` binder-splitting precedent (`:738–739`) grounds the two-array map encoding; params/result/branch binders flow through `typeToSortA`/`FQSort` generically (`:620–621`, `:657`, `:815`) — the basis of the §5.1 sort-agnosticism rows.
8. `compiler/src/LLMLL/FixpointIR.hs:55–64` — `FQSort` constructor inventory; `emitSort` renders sorts textually to `.fq` (`FQList → "Lst"` was "probe-verified accepted bare" — the same probe discipline applies to an array sort).
9. `compiler/src/LLMLL/ObligationMining.hs:171` — `isQfLia`, the single central classifier seam (post-CLASSIFY-EOP, v0.14.30).
10. `docs/design/data-scope-extension.md` Posts 6–8 — bug-class inventory, Lever A rationale, the checkout-brief evaluation-integrity rule (Post 8).
11. `docs/compiler-team-roadmap.md` → "What's NOT on this Roadmap" postscript — the feature freeze was lifted at v0.11; a new builtin lands through design → professor → engineer **with a written soundness argument**. This document is that argument.
12. [`data-scope-lever-a-arrays-review.md`](data-scope-lever-a-arrays-review.md) — professor review of Rev 0; F1–F10, all folded here.

**Spec-drift findings surfaced during Rev 0 reading** (status as of v0.14.32):

- **D1.** `LLMLL.md:1869` (§11.1 treaty example) used unregistered `map-values`/`sum` with no "illustrative, not runnable" flag — **fixed in v0.14.32** (flag added).
- **D2.** `LLMLL.md:110` named `map-get` as an exemplar builtin while none exists — **fixed in v0.14.32** (exemplar swapped).
- **D3.** `data-scope-extension.md:116` — the "`bytes[n]` … the `n` is a type-level tag, not a solver fact" row flips when stage A1 ships; doc-lead updates the didactic table post-ship. **Still pending (post-A1).**

---

## Design proposal

### 1. Scope and non-goals

**In scope:** a minimal operation set over `bytes[n]` and `map[k,v]`; its typing rules; its reflection into SMT `select`/`store`; the `Σ_auto` extension and its decidability argument; the firewall for everything else; a staged delivery plan.

**Non-goals (explicit):** `list` indexing (Lever B — the bridge, depends on this lever); map cardinality/`map-size` (not expressible in QF_AX — counting is not an array-theory operation; a future measure would need its own Lever-B-style discipline and is **not** proposed); **`map-remove`** (deliberately absent — trivially expressible later as `store(m$has, k, false)`, but its absence preserves a put-only construction discipline for *constructed* map values that any future whole-structure reasoning would have to revisit; recorded so a later `map-remove` does not silently invalidate reasoning that leaned on it); **length polymorphism over `bytes[n]`** (the `n` is a literal, never a length variable — a function polymorphic over byte-lengths is inexpressible in v1; Lever B/R1 territory); bytes slicing/concatenation (sequence theory — deferred); quantified array properties ("all bytes are zero", sortedness — quantifiers leave the QF fragment; there is deliberately no surface to write them); recursive structures (Lever C); variable-length `bytes` (already deferred at `LLMLL.md:2413`); **string map keys** (deferred to v1.5 with the literal-distinctness design of §3 — F2 disposition).

### 2. Surface

No new type formers and no new syntax constructs. Both type formers exist in the S-expr grammar (`LLMLL.md:1959,1962` — spellings `bytes "[" INT "]"`, `map "[" type "," type "]"` confirmed against §12; the examples below use exactly the grammar's concrete syntax) and the JSON-AST schema (`llmll-ast.schema.json:400,432`). The entire surface delta is **eight new builtins** (§13-style, kebab-case), all ordinary `EApp`/`app` nodes in both surfaces:

| Builtin | Signature | Builtin contract (see §3) |
|---|---|---|
| `bytes-length` | `bytes[n] -> int` | post: `(= result n)` — the type-level `n`, reflected |
| `bytes-get` | `bytes[n] int -> int` | pre: `(and (<= 0 i) (< i n))`; post: `(and (<= 0 result) (<= result 255))` |
| `bytes-set` | `bytes[n] int int -> bytes[n]` | pre: `(and (<= 0 i) (< i n) (<= 0 v) (<= v 255))` |
| `bytes-zero` | `-> bytes[n]` | constructor; `n` inferred from usage (the `list-empty` precedent, `:2202`) |
| `map-has` | `map[k,v] k -> bool` | — (total) |
| `map-get` | `map[k,v] k -> v` | pre: `(map-has m k)` |
| `map-put` | `map[k,v] k v -> map[k,v]` | — (total); post: `(map-has result k)` |
| `map-empty` | `-> map[k,v]` | constructor; types inferred from usage |

(Eight rows; `bytes-zero`/`map-empty` are constructors required for T1 usability — today a `map[k,v]` value is not constructible by any shipped operation at all, a gap D1/D2 made visible. A bare `(bytes-zero)` or `(map-empty)` in a context that does not determine the type is a **type error** — `n` and `k,v` must resolve to concrete types; there is no length or sort polymorphism to fall back to.)

**The partial-read decision (professor-confirmed, review F8).** `bytes-get` and `map-get` carry **preconditions** instead of returning `Result` (the `list-nth` pattern, `:2212`). This is the pivotal ergonomic choice of the lever, made deliberately: a `Result`-returning read moves out-of-bounds into the dynamic error channel, where a hole-filling agent can satisfy any contract by propagating the error — the memory-safety claim becomes unfalsifiable at verify time. A pre-carrying read makes in-bounds a **PROVE-polarity caller obligation** (§5.3.4 item 1) that the solver must discharge from the caller's own precondition and path condition. The auto-active precedent is direct: Dafny's `a[i]` carries an implicit bounds obligation of exactly this polarity (Leino, LPAR 2010), and Liquid Haskell's vector idiom is the refined-precondition form (Vazou et al., ICFP 2014), with a `Maybe`-total variant only as a layered convenience. Under LLMLL's checkout protocol the obligation is additionally **non-negotiable at fill time** — patches are scope-checked to the hole subtree, so a fill agent cannot weaken the enclosing contract; it must discharge the bound from the brief's `assumptions` and path facts. Consequence recorded: agent-side dischargeability rides on checkout-brief completeness (the OBLIG-1 `assumptions` line, through v2b), so the A4 flagship implicitly tests OBLIG-1's adequacy too. Per the review, the over-strengthening hazard named in Rev 0's Q2 is confined to the contract-authoring and `refine`-spawn flows, where the CDP vacuity gate and over-annotation guardrail already operate. A `Result`-wrapped convenience (`map-get-opt`) can be layered later; **both read forms are deliberately not shipped initially** — the second form would reopen the unfalsifiability channel the first closes.

**Strict immutability.** `bytes-set` and `map-put` are functional updates returning new values — exactly the semantics of SMT `store`. No mutation, no aliasing; the theory and the language invariant coincide with no translation gap. Codegen targets persistent structures (engineer's choice; `Data.Map`/`ByteString` copy-on-write are both admissible).

### 3. Typing rules and admissibility gates

Let `Γ ⊢ e : τ` be the existing type-assignment judgment (§3.4.6).

```
Γ ⊢ b : bytes[n]    Γ ⊢ i : int
─────────────────────────────────  (T-BytesGet)     obligation at intro site: 0 ≤ i < n   [contract channel]
Γ ⊢ (bytes-get b i) : int

Γ ⊢ m : map[k,v]    Γ ⊢ e : k     k = int   (v1)
────────────────────────────────────────────────  (T-MapGet)   obligation: (map-has m e)   [contract channel]
Γ ⊢ (map-get m e) : v
```

(remaining rules are the evident analogues; `bytes-set` additionally obligates `0 ≤ v ≤ 255`.)

**Key-sort gate (type channel) — v1 keys are `int` only (F2 disposition).** v1 admits map **keys** in `{int}` and map **values** in `{int, bool, string}` for the *reflected* (verified) path. The Rev 0 gate admitted `string` keys, but `exprToPred` reflects no string literal today (`FixpointEmit.hs` — literal cases are `LitInt`/`LitBool` only), and the obvious rule — uninterpreted `Str` constants — is refutation-unsound: two distinct literals `"a"`, `"b"` are not provably distinct, so a model identifying them spuriously refutes true posts (e.g. `(= (map-get (map-put (map-put m "a" 1) "b" 2) "a") 1)` is UNSAFE in the model `"a" = "b"`). Int-only keys are chosen over the alternative (ground pairwise-distinctness facts) on staging risk: a string-literal reflection rule touches every string-literal-bearing contract, not only maps, and therefore needs its own examples-wide verdict inventory — an ENUM-EQ-FALLBACK-class blast radius — while stage A2 is already the heaviest increment (§5.1). Symbolic-key reasoning, where the theory earns its keep (get-after-put, aliased keys), is fully exercised at `int`.

**Deferred v1.5 — string keys via literal-distinctness facts.** The return path is specified now so it stays a side-condition, not a redesign: (i) reflect a string literal **only in map-key position** as an interned uninterpreted `Str` constant; (ii) emit ground pairwise-distinctness facts `lit_i ≠ lit_j` for every pair of distinct string literals occurring in the obligation (path-(a) register — a third ground-fact family alongside §4's two); (iii) literal/variable pairs get **no** fact (a variable may equal any literal — that is a genuine model); (iv) acceptance gate = a before/after verdict inventory over `examples/`, exactly the A1 discipline of §10. Sound by construction; complete for literal-keyed reasoning at quadratic-in-literals ground-fact cost (small in practice).

String **values** remain admitted: a string-valued `map-get` term is an opaque `Str`-sorted EUF term (composes with `string-length`, decidable equality between *terms*), and a post comparing a map value against a string **literal** contains an unreflected symbol, so it routes out-of-fragment by the exact-reflection rule (§6.1) — today's behavior for string-literal posts, unchanged. A map op at any other key type (e.g. `map[Color,int]`, `map[string,int]` in v1) is a **typechecker diagnostic on the operation** (the type former itself remains unrestricted T1); this mirrors how the strict-core gate refuses rather than pads (the REC-DESCENT refuse-not-pad precedent). Widening keys to `string` (v1.5 above) and to admissible sums (the datatype class is polite-combinable too — §6) is deferred, not blocked.

**Builtin-contract mechanism.** The four contracts above register in the `ContractEnv` the way contracted callees do, so the **existing** call-site machinery (§5.3.4: prove pre, assume post, bind fresh result) fires without a new obligation kind. The three admission legs at `checkCalleeAdmissibility` (`LLMLL.md:1030`) are unchanged; the new ops enter `builtinEnv` as **reflected** symbols — body-faithful by construction, like `+` and `first`/`second` — so they leave the trust meet unchanged (§4.4.1). This is the first builtin family carrying a PROVE-polarity pre; the mechanism is contract-registry-level, not a new channel.

### 4. Refinement-predicate vocabulary and reflection

No new user-facing logical symbols. The operation names **are** the contract vocabulary — the `first`/`second`-selector precedent (§5.3.3 datatype class), not a parallel `select`/`store` namespace. A pre/post/`where` predicate may contain `bytes-get`, `bytes-length`, `map-has`, `map-get`, `map-put`, `bytes-set` applied to in-scope terms. Reflection at VC emission (`exprToPred`/`bodyToPredM`):

| Surface term | SMT reflection |
|---|---|
| `(bytes-get b i)` | `select(b, i)` |
| `(bytes-set b i v)` | `store(b, i, v)` |
| `(bytes-length b)` | the literal `n` from `b`'s type `bytes[n]` (ground) |
| `(map-has m k)` | `select(m$has, k)` |
| `(map-get m k)` | `select(m$val, k)` |
| `(map-put m k v)` | the pair `⟨store(m$has, k, true), store(m$val, k, v)⟩` (both component arrays updated) |
| `(bytes-zero)` / `(map-empty)` | const-array `K(0)` / `K(false)` where the probe lands; **where const arrays are unavailable, any obligation mentioning a constructor routes out-of-fragment at classification (§6.1) — never an emitted free binder** |

**Ground-fact discipline (path-(a) extension).** Two fact families are emitted as **ground facts per occurring term**, never as quantified axioms — extending the §5.3.3 emission side-condition verbatim:

- per `bytes[n]`-typed binder `b` in the obligation: `bytes-length(b) = n` (the type-level length becomes a solver fact — this single fact is what turns the length *tag* into a checkable bound);
- per occurring `select(b, i)` term over a bytes binder: `0 ≤ select(b, i) ≤ 255` (the byte-range fact, the analogue of the measure range axiom).

(The v1.5 string-key path adds a third family — literal pairwise-distinctness, §3 — under the same register.)

### 5. Sort lowering and the map encoding

New IR sort: `FQArr FQSort FQSort` (element and index both restricted per §3). Lowering (`typeToSort`):

- `bytes[n]` → `FQArr FQInt FQInt` — one binder, plus the ground length fact of §4.
- `map[k,v]` → **two** binders per source binder `m`: `m$has : FQArr σₖ FQInt` (presence as an **int 0/1 array**: `(= (Map_select m$has k) 1)` means present) and `m$val : FQArr σₖ σᵥ` — the standard finite-map-as-presence-plus-value-array encoding, and a direct reuse of the emitter's established binder-splitting pattern (`FixpointEmit.hs:738–739` splits a `Result` binder into `v$ok`/`v$err` today). **(Rev 1.1, feasibility-driven amendment):** the presence array is int-0/1 rather than the Rev 1 `FQBool` because the pinned liquid-fixpoint's SMT bridge declares its array operations monomorphically at int elements — a `(Map_t int bool)` binder is a hard solver crash (`smt_map_sto` sort mismatch; feasibility probes p5/p5c), while the int-0/1 shape is proven end-to-end (probe p5b). The change is §6.1-exact (0/1 ↔ present/absent is a bijection, not an over-approximation — the same int-tag discipline the nullary-enum desugar already uses), bool-*valued* maps take the same encoding, and it incidentally moots the F5 `Arr σₖ Bool` politeness leg at the solver layer (the metatheory note in §6 stands as the general argument). See [`data-scope-lever-a-feasibility.md`](data-scope-lever-a-feasibility.md) §4.

**Encoding choice (professor-confirmed, review F9).** Presence-plus-value is the standard finite-map model across the auto-active tools — Dafny's map axiomatization (domain + elements), Boogie map models, F*'s `FStar.Map` (value array plus domain map), Why3's `fmap`. The array-of-option alternative (`FQArr σₖ (Option σᵥ)`) is not wrong but pays a datatype case-split under every read, drags `Option` into every array-lemma instantiation, and couples the constructor story to `K(None)`; no completeness cliff separates the two. **The two-array encoding's one real cost is named here so it travels with the decision:** the component arrays carry junk at absent keys (nothing constrains `select(m$val,k)` where `¬select(m$has,k)`; for `bytes[n]`, nothing constrains indices outside `[0,n)`), so representational array equality diverges from the language's observational `=` (`LLMLL.md:2157`). The encoding's soundness condition is therefore: **reads are gated by presence, and surface whole-structure `=` never reflects to array equality** (§7 row 4, per review F1).

**`.fq` rendering.** `emitSort` renders `FQArr` to liquid-fixpoint's built-in map sort (`Map_t`, with `Map_select`/`Map_store` as the operation symbols — liquid-fixpoint carries this theory for LiquidHaskell's `Data.Map` embedding and lowers it to SMT arrays; its `Map_default` symbol is const-array-shaped, external evidence that the constructor reflection lands too — review F10). This is the engineer's **first spike**: probe the textual `.fq` acceptance exactly as `Lst` was probe-verified (`FixpointIR.hs:196`). Expected outcome is positive; if the `.fq` surface refuses the map theory, the fallback is emitting SMT-LIB via the solver interface the `--leanstral` path already exercises — a feasibility question, not a design change (Risk 1).

**Activation gating (byte-inertness).** The `FQArr` lowering activates **only for functions whose contract or body mentions an array-class symbol**. Every other function — including the entire existing corpus (the §13.11 crypto examples pass `bytes[20]` values around without element access) — keeps today's lowering, guaranteeing **byte-identical `.fq` output** for programs that don't use the ops. This is the MATCH-WIDEN no-op discipline (v0.14.26 "n=2 byte-identical" precedent) applied at the sort layer.

#### 5.1 Body-coverage inventory (stage A2 scope — review F4)

The reflection table above is the *predicate* story; the following inventory is the *body* story, named so stage A2's effort is scoped by the design rather than discovered mid-build:

| Body shape | Status | A2 disposition |
|---|---|---|
| `ELet` with array-typed RHS — `(let [(m2 (map-put m k v))] (map-get m2 k))` | verification matrix (`LLMLL.md:1004–1005`) grants `ELet` body-faithful discharge only for "single `PVar`, int RHS"; without extension **every map pipeline falls back** — this is the normal shape of map code | **in scope, A2** — extend the `ELet` row to array-sorted RHS; the let-bound pipeline is an A2 acceptance example (§10) |
| Composite map-valued subterms — `(map-has (map-put m k v) k2)` | `map-put` reflects to a **pair** of arrays; binder splitting covers declared binders, but a map-valued *subterm* needs a two-component symbolic value threaded through `exprToPred`/`bodyToPredM` application nodes — **a new emitter shape, and the principal engineering mass of A2** | **in scope, A2** — the pair-threading rule: a map-typed subterm denotes the component pair `⟨has-term, val-term⟩`; each map-op reflection consumes/produces the pair |
| `EIf` branches of array type | path-split plumbing is sort-generic in the binder layer (`FixpointEmit.hs:620–621`, `:657`, `:815` — binders flow through `typeToSortA`/`FQSort` uniformly); preliminary confirmation by the language-team, per the review's request | **confirm in A2** with a branch-typed test; no new machinery expected |
| Array-typed arguments at contracted call sites (assume-guarantee over array sorts) | same generic-binder basis; mechanical | **confirm in A2** with a cross-call test; no new machinery expected |

### 6. The Σ_auto extension and its decidability argument

```
Σ_auto  =  QF-LIA core
        ∪  ( measure class  | path-(a) )
        ∪  ( datatype class | admissible sums )
        ∪  ( array class    | admissible index/element sorts, ground-fact discipline )   ← NEW
```

The array class is the quantifier-free extensional theory of arrays: McCarthy's read-over-write axioms (McCarthy, *Towards a Mathematical Science of Computation*, IFIP 1962) plus extensionality. Decidability of the quantifier-free extensional fragment: Stump–Barrett–Dill–Levitt, *A Decision Procedure for an Extensional Theory of Arrays*, LICS 2001. The implemented procedure including const arrays (needed for `bytes-zero`/`map-empty` reflection) is combinatory array logic: de Moura–Bjørner, *Generalized, Efficient Array Decision Procedures*, FMCAD 2009 — Z3's native procedure. For v1's scalar index and element sorts the extended fragment is textbook **QF_AUFLIA** (arrays + uninterpreted functions + linear integer arithmetic; Kroening–Strichman, *Decision Procedures*, ch. 7). Combination is by **strong politeness in the Jovanović–Barrett sense** (LPAR 2010 — the repaired form of the Ranise–Ringeissen–Zarba FroCoS 2005 definition, the same pair the datatype class already cites); the leg that genuinely needs politeness rather than plain Nelson–Oppen is `m$has : Arr σₖ Bool` — `Bool` is finite, hence not stably infinite. The deferred v2 key-widening to admissible sums stacks the datatype theory as a third leg; the modern citation is Sheng, Zohar, et al., *Politeness for the Theory of Algebraic Datatypes* (IJCAR 2020). Engineering note: Z3 implements combination via model-based theory combination rather than literal polite combination — the metatheory licenses decidability; the pinned solver's behavior is what the A1 probe measures. Complexity: read-over-write case-splitting is worst-case exponential in store-chain depth (de Moura–Bjørner's filters mitigate; LLMLL bodies keep chains short), and nothing in v1 approaches the known hard corners (nested arrays, quantified array properties). The `admissibleDatatype` acyclicity gate is untouched; arrays never appear as datatype payloads in v1 (a `bytes` payload inside a sum stays firewalled exactly as a `list` payload is today, §5.3.3 datatype-class bullet).

Consequence: for an obligation whose symbols lie in the extended `Σ_auto`, liquid-fixpoint/Z3 remains a **sound and complete decision procedure on the fixed VC** — SAFE stays a decidable side-condition, Theorem B's antecedent (§3.4.5) is preserved, and the trust-tier story does not change shape. No new tier, no new evidence kind.

#### 6.1 The exact-reflection rule (normative — review F3)

> **An obligation may be emitted as a body-faithful VC — and hence may `refute` — only when every symbol in it has an exact reflection: sound and complete per term. Any incompletely-reflected term forces the whole obligation to the §5.3.3 four-item routing at classification, before emission.**

Rationale: an over-approximated emission (e.g. a free binder standing for an unreflectable constructor) is sound for SAFE — a post proved over all valuations holds for the real value — but **unsound for UNSAFE**: the solver can exhibit a "counterexample" valuation the real semantics never produces, breaking §5.3.4's refuted-means-counterexample claim (`:962`). The existing `Σ_auto` machinery never faces this because fragment membership has always coincided with exactness; this rule makes the coincidence a stated invariant now that near-misses exist (constructors without const arrays; string literals without distinctness facts; whole-structure equality over a junk-carrying encoding — the F1/F2/F3 findings are all instances). **Every stage of §10 must satisfy it, and it is stage A3's correctness criterion**: the classifier's job is not vocabulary bookkeeping but deciding exact-reflectability per obligation.

### 7. Boundary and firewall

What stays **out**, and what happens when it's touched:

| Escape | Behavior |
|---|---|
| Aggregation/iteration over a structure (`sum` of map values, fold over bytes) | not in QF_AX; the four-item routing of §5.3.3 (`:925–929`): runtime assertion + `asserted` tier + `?proof-required` + trust-report propagation. `erBodyFallback` on the body side. |
| Quantified properties ("all bytes zero") | no surface exists to state them (no quantifier syntax in contracts); spec is silent — **intentional**. |
| `map-size` / cardinality | operation does not exist (§1 non-goal); nothing to fall back from. |
| Whole-structure equality posts (`(= m1 m2)` over maps; `=` over two `bytes[n]` values) | **unconditionally out-of-fragment in v1** (review F1) → four-item routing. Reason: the two-array/junk-carrying encoding makes representational array equality diverge from the observational `=` of `LLMLL.md:2157` (models may differ only at absent keys / out-of-range indices), so reflecting surface `=` as array equality risks **spurious refutation of an observationally true post** — a claim-accuracy break under §5.3.4 `:962`. This routing does not depend on the extensionality probe; the solver's internal use of extensionality is unaffected. The refute crux and get-after-put never need whole-structure `=`. v2 options, one sentence each: a normalization invariant pinning absent keys to a default is maintainable for *constructed* values while the op set is put-only (§1) but not assumable for symbolic parameters; for `bytes[n]` with literal `n`, a bounded index expansion (`n` conjuncts, quantifier-free) is viable for small `n`. |
| Constructor reflection when const arrays are unavailable | any obligation mentioning `bytes-zero`/`map-empty` is **classified out-of-fragment before emission** (exact-reflection rule, §6.1) — never an emitted free binder. Documented, not silent: the classifier labels it; flips to reflected if the probe lands (expected — §5). |
| Array-typed value crossing a firewalled position (sum payload, `list` element) | existing firewall verbatim — clean fallback, never a crash (the PAIR-RET-2 crash-to-fallback precedent, v0.13.12). |

### 8. Interaction with the measure catalog

**Coexist; the catalog stays closed at two.** `string-length` and `list-length` are unchanged, M1–M4 discipline unchanged. `bytes-length` is **not a measure** — it is a per-binder ground equality to a type-level literal (§4), strictly weaker machinery than a local theory extension (no congruence argument needed; the fact is ground by construction). `map-size` is deliberately absent (§1). Lever B, when it comes, bridges `list-length` to indexing *through* this lever's theory; nothing here pre-commits it.

### 9. Trust story

The reflected ops' **runtime implementations** must agree with `select`/`store` semantics — the same boundary-trust closure as the Class-A indexing primitives (`LLMLL.md:2246`): concrete `Int64` shims at the Haskell seam, structures assumed to fit `Int64` length, a sub-case of the §7 FFI-builtin closure. The new builtins join that note's inventory. Contract violations on the unverified path (a `bytes-get` whose pre was not discharged because the function fell back) remain **runtime assertions, never stripped** — preconditions are never stripped (§5.3.4), so the dynamic backstop the rest of the language relies on is intact here too.

### 10. Staged delivery plan

Modeled on MATCH-WIDEN/REC-DESCENT: surface-inert first, discharge second, byte-identical no-op guarantees at every stage. **Every stage is bound by the exact-reflection rule (§6.1).**

| Stage | Ships | Acceptance | No-op guarantee |
|---|---|---|---|
| **A0 — surface, verification-inert** | 8 builtins in `builtinEnv` + typechecker (incl. key-sort gate) + codegen + runtime; builtin contracts as **runtime assertions only**; classifier labels array contracts `non_qf_lia` → Advisory | ops run; existing suite green | zero `.fq` change anywhere (the REC-DESCENT Phase-1 "verification-inert" precedent, v0.14.24) |
| **A1 — bytes discharge** | `FQArr` sort + `.fq` probe + bytes reflection + ground facts (length, byte-range) + index/value obligations | the §11 refute crux **refutes** and its fixed twin **verifies**; positive-witness test required; **before/after verdict inventory over `examples/`** for the `typeToSort` lowering change of operated-on `TBytes`/`TMap` binders (review F7 — the ENUM-EQ-FALLBACK lesson, v0.14.32: a sort change ships with a sweep, not a hope) | byte-identical `.fq` for functions not mentioning array symbols (activation gate, §5) |
| **A2 — map discharge** | two-array binder splitting; `map-has`/`map-get`/`map-put` reflection; presence obligations; **the §5.1 inventory: `ELet` array-typed RHS, composite map-valued subterm pair-threading, `EIf`/call-site confirmations** | get-after-put verifies **including the let-bound pipeline shape** `(let [(m2 (map-put m k v))] (map-get m2 k))`, not only the single-call form; aliased-key crux refutes | same gate |
| **A3 — classifier & agent surface** | `isQfLia`/`classifyContractFragment` admit array-class symbols **centrally** (`ObligationMining.hs:171`; the CLASSIFY-EOP lesson: one predicate, `EOp` and `EApp` forms, parser-faithful tests — v0.14.30); obligation-report + checkout-brief vocabulary; CDP/weakness-check handle array-typed candidates | array contracts classify `qf_lia`-tier obligations; brief lists the ops; **classifier decides exact-reflectability per obligation (§6.1) — constructors-without-const-arrays and whole-structure `=` route out** | report-shape only; no schema bump expected |
| **A4 — the flagship data example** | the data-axis example (experiment-lead slot): an agent-filled hole whose checkout brief carries an index-bounds obligation, under the Post-8 sole-channel rule | out of this proposal's scope; named as the lever's acceptance demo (and, per review F8, an implicit adequacy test of the OBLIG-1 `assumptions` channel) | — |

### 11. Worked micro-examples

**The refute crux (index out of bounds — the Heartbleed-as-memory shape).** A bounds *check* that is off by one; the body looks correct:

```lisp
(def read-at [b: bytes[64] i: int] -> int
  (pre  (and (>= i 0) (<= i 64)))          ;; BUG: <= admits i = 64
  (post (and (>= result 0) (<= result 255)))
  (bytes-get b i))
```

The intro-site obligation is `pre ⟹ 0 ≤ i < 64` (§3). At `i = 64` the antecedent holds and the consequent fails: **`refuted`**, with the counterexample `i = 64` — the solver catches the off-by-one, not a length proxy. Tightening the pre to `(< i 64)` verifies, and the post discharges from the byte-range ground fact of §4. This pair is the stage-A1 acceptance test and the positive witness required by the edge-case discipline.

**Get-after-put (map correctness).** Keys are `int` in v1 (§3):

```lisp
(def cache-put [m: map[int,int] k: int v: int] -> map[int,int]
  (post (and (map-has result k) (= (map-get result k) v)))
  (map-put m k v))
```

Reflection: `result$has = store(m$has,k,true) ∧ result$val = store(m$val,k,v)`; both conjuncts discharge by read-over-write. **`verified`.** The discriminative twin — body `m` (dropping the put) — is **`refuted`** with a model where `¬select(m$has,k)`. The let-bound pipeline form of the same property — `(let [(m2 (map-put m k v))] (map-get m2 k))` returning `v` — is the additional A2 acceptance example (§5.1).

**Aliased symbolic keys.** Post `(= (map-get (map-put m k1 v) k2) v)` with no relation between `k1`,`k2` in the pre: **`refuted`** — read-over-write's else-branch yields `select(m$val,k2)` when `k1 ≠ k2`, and the solver produces exactly that counterexample. The theory reasons about symbolic key equality; nothing is concretized.

### 12. JSON-AST schema delta

**None.** Both type formers already exist as schema node kinds (`llmll-ast.schema.json:400` `map`, `:432` `bytes`); the eight operations are ordinary `{"kind":"app","fn":"bytes-get",…}` nodes, and builtins are name-resolved, not schema-encoded. `schemaVersion` stays 0.8.0. The checkout-brief/obligation-report vocabulary additions in A3 are data, not shape — no `brief_version` bump expected (the XMOD-SCOPE-BRIEF precedent bumped for a *shape* change; A3 adds none).

---

## Edge cases and degenerate inputs

1. **Positive witness (required for the pre-carrying guard).** Input: the `read-at` crux of §11 verbatim. Expected: `refuted`, counterexample `i = 64`; the `<`-twin `verified`. Channel: **contract** (intro-site obligation, §3). Cite: §5.3.4 PROVE polarity; stage-A1 acceptance row.
2. **Get-after-put and its dropped-put twin.** Input: `cache-put` of §11 and the body-`m` twin. Expected: `verified` / `refuted` respectively. Channel: **contract**. Cite: §4 reflection table.
3. **Aliased symbolic keys.** Input: the unconditional-`v` post of §11. Expected: `refuted` with a `k1 ≠ k2` model. Channel: **contract**. Cite: read-over-write else-branch.
4. **Opaque coexistence.** Input: `examples/totp_rfc6238/`-style code passing `bytes[20]` through `hmac-sha1` with no element access. Expected: verdicts and `.fq` **byte-identical** to today (activation gate, §5). Channel: **trust** (no change is the assertion). Cite: stage guarantees, §10.
5. **Inadmissible key sort.** Input: `(map-get m s)` where `m : map[string,int]` (or `map[Color,int]`). Expected: typechecker diagnostic on the operation (v1 keys are int-only, §3); the *type* `map[string,int]` itself remains legal T1, and code that only passes such a map around (no ops) is unaffected. Channel: **type**. Cite: key-sort gate, §3; F2 disposition.
6. **Underivable presence.** Input: `(map-get m k)` in a body whose pre says nothing about `k`. Expected: `refuted` (a model with `¬select(m$has,k)` exists; in the decidable fragment UNSAFE is a genuine counterexample, not "unproven"). Channel: **contract**. Cite: §5.3.4 (`:962`).
7. **Aggregate escape.** Input: a post summing map values (the `LLMLL.md:1869` shape). Expected: out-of-fragment → four-item routing, `erBodyFallback`, Advisory-tier obligation; never a crash. Channel: **trust** (tier degradation is the catch). Cite: §7 table; spec silent on aggregates — **intentional**.
8. **Constructor under a failed const-array probe.** Input: `(not (map-has (map-empty) k))` as a post. Expected: the obligation **classifies out-of-fragment before emission** (exact-reflection rule §6.1 — never an emitted free binder, which would license a spurious refutation); flips to reflected-and-`verified` if the probe lands (expected, §5). Channel: **trust** (routing + labeling). Cite: §7 row 5; review F3.
9. **Whole-structure equality post.** Input: `(post (= result m))` over map-typed `result`. Expected: unconditionally out-of-fragment → four-item routing (never reflected to array equality). Channel: **trust** (tier degradation), protecting **contract**-channel claim accuracy. Cite: §7 row 4; review F1; `LLMLL.md:2157`.

## Verification mapping

| Obligation | Channel | Fragment | Notes |
|---|---|---|---|
| `bytes-get`/`bytes-set` index-in-bounds at intro site | contract | **QF-LIA + array class — auto-discharged** | the bound `n` is a ground fact (§4); the comparison is pure QF-LIA |
| `bytes-set` value range `0 ≤ v ≤ 255` | contract | **QF-LIA — auto** | |
| `map-get` presence pre | contract | **array class — auto** | `select` on `m$has`; int keys (v1) |
| get-after-put / read-over-write posts | contract | **array class + QF-LIA — auto** | Stump et al. 2001; de Moura–Bjørner 2009; QF_AUFLIA overall (§6) |
| byte-range of a read (`0 ≤ select ≤ 255`) | contract | **QF-LIA — auto** | ground fact per occurring term, path-(a) discipline |
| whole-map/bytes equality posts | contract → trust | **out-of-fragment, unconditionally (v1)** → four-item routing | review F1; §7 row 4; junk-value divergence from observational `=` |
| obligations mentioning `bytes-zero`/`map-empty` under a failed const-array probe | contract → trust | **out-of-fragment at classification** (§6.1) | review F3; never an emitted free binder |
| string-literal-keyed map obligations | — | **inexpressible in v1** (int-only keys; op-level type diagnostic) | v1.5 path specified in §3 |
| aggregates, quantified properties, `map-size` | — | **out of `Σ_auto`** — routing per §5.3.3 `:925`; `map-size` has no surface | *not* routed to Lean by default (ergonomics inversion) |
| runtime agreement of builtin implementations with `select`/`store` | trust | boundary closure (not a VC) | §9; `LLMLL.md:2246` inventory |

## Affected surface

- `LLMLL.md`: §3.2 note on `bytes`/`map` gaining operations; §5.3.3 `Σ_auto` formula + a fourth completeness bullet (array class) + the exact-reflection rule (§6.1 here) as a stated side-condition; §5.3.4 coverage sentence; §5.3.5 new matrix rows (incl. the `ELet` array-RHS extension, §5.1); §11.1 `:2157` gains a clarifying sentence that whole-structure `=` over maps/bytes is not in the verified fragment (F1); §13.5-adjacent new builtin table + the `:2246` closure inventory; §13.11's "n is a tag" implications. (Doc-lead, post-ship.)
- `compiler/src/LLMLL/`: `FixpointIR.hs` (`FQArr`, `emitSort`), `FixpointEmit.hs` (`typeToSort` cases replacing the `FQInt` default for operated-on binders; `exprToPred`/`bodyToPredM` reflection incl. §5.1 pair-threading; binder splitting; ground facts; activation gate), `TypeCheck.hs` (`builtinEnv` + key-sort gate + builtin contracts), `CodegenHs.hs` (runtime ops + shims), `ObligationMining.hs:171` (`isQfLia` central extension + exact-reflectability decision, §6.1), `ObligationAssembly.hs`/`Checkout.hs` (A3 vocabulary), `CDP.hs`/`WeaknessCheck.hs` (array-typed candidates). (Engineer's decomposition, not a plan.)
- `docs/llmll-ast.schema.json`: **no change** (§12).
- `docs/design/data-scope-extension.md`: D3 table-row update post-A1 (doc-lead).
- Roadmap: Lever A row status moves on settlement; stage structure above maps onto its acceptance criteria.
- Freeze policy: **not applicable** — lifted at v0.11; this document is the required written soundness argument (Context item 11).

## Risks and open questions

1. **liquid-fixpoint `.fq` array-theory surface unprobed.** Feasibility. The map theory (`Map_t`/`Map_select`/`Map_store`, plus the const-array-shaped `Map_default`) exists in liquid-fixpoint for LH's use — external evidence the probe lands (review F10) — but the textual `.fq` acceptance and behavior are unverified in *our* pipeline (no `Map_*` symbol appears anywhere under `compiler/src/`). **Complicates (first engineer spike); does not block the design** — §6.1/§7 define sound classifier-level degradations for both probe outcomes, and F1's routing no longer depends on the probe at all. Cite: `FixpointIR.hs:196` probe precedent.
2. **Solver cost.** Array VCs are costlier than pure QF-LIA; read-over-write case-splitting is worst-case exponential in store-chain depth (§6). Bounded: per-function, only on array-mentioning obligations (activation gate), short chains in practice, and the measurement pattern exists (`experiments/cdp-perf-0/`). Verification-ergonomics; matters at scale only.
3. **Classifier recurrence.** CLASSIFY-EOP (v0.14.30) showed a vocabulary blind spot silently downgrades obligation tiers project-wide. Mitigation is structural: one central `isQfLia` change, parser-faithful regression tests (not hand-built `EApp`), stage A3 as its own gated increment, and §6.1 as the classifier's stated correctness criterion. Spec-drift class; complicates.
4. **CDP/weakness-check over array-typed results.** Identity/const candidate construction needs array-sorted skolems; unexamined. Verification-ergonomics; complicates A3, engineer to scope.
5. **Latent `typeToSort` default.** Today `TBytes`/`TMap` binders lower to `FQInt` (the conservative default) — two distinct maps mentioned by equality in a contract already unify as int-sorted terms. Benign today only because no operation is reflected. **Promoted to a stage-A1 acceptance criterion** (§10): a before/after verdict inventory over `examples/` gates the sort change (review F7).
6. **Byte-range facts and `machine-int`.** The `0–255` element story is orthogonal to INT-3's QF-BV track; if `machine-int` ever lands, `bytes` elements should *not* silently become bit-vectors (that would move the array class to QF_ABV — decidable but a different cost profile). Scope note for INT-3's design; only matters if INT-3 wakes.

---

## Review-fold appendix (Rev 1)

Professor review: [`data-scope-lever-a-arrays-review.md`](data-scope-lever-a-arrays-review.md), verdict **proceed-with-revisions**. Dispositions:

| Finding | Disposition in Rev 1 |
|---|---|
| **F1** (MAJOR) whole-structure `=` vs junk-carrying encoding | **Folded.** §7 row 4: whole-map/whole-bytes equality unconditionally out-of-fragment; probe-conditional admission deleted; reason (observational-`=` divergence, `LLMLL.md:2157`; spurious-refutation risk) stated in place; v2 options recorded in one sentence each. §5 names the encoding's soundness condition where the encoding is chosen (per F9). Edge case 9 and the verification-mapping row added. |
| **F2** (MAJOR) string keys vs literal distinctness | **Folded — int-only keys in v1.** §3 key-sort gate is `{int}`; rationale = staging risk (a string-literal reflection rule has an ENUM-EQ-FALLBACK-class blast radius beyond maps and needs its own verdict inventory, while A2 is already the heaviest stage) and undiminished payoff (symbolic-key reasoning is the theory's value; it is key-sort-independent). String keys move to the §1 deferred list with the full v1.5 design sketched in §3 (key-position-scoped literal reflection + ground pairwise-distinctness facts as a third path-(a) family + literal/variable pairs get no fact + verdict-inventory acceptance gate). §11 `cache-put` re-keyed to `map[int,int]`; edge case 5 updated. D1/D2 doc-drift notes updated (both fixed in v0.14.32). |
| **F3** (MAJOR) refutation-completeness rule; constructor degradation | **Folded.** §6.1 states the exact-reflection rule normatively; noted as subsuming F1/F2 and as stage A3's correctness criterion; §10 binds every stage to it. §4 constructor row and §7 row 5 pinned to classifier-level routing — never an emitted free binder; edge case 8 rewritten. |
| **F4** (MAJOR) body-coverage inventory | **Folded.** New §5.1: `ELet` array-typed RHS (in scope, A2; verification-matrix row cited), composite map-valued subterm pair-threading (named as A2's principal mass), `EIf`/call-site sort-agnosticism (preliminarily confirmed by the language-team against `FixpointEmit.hs:620–621,657,815` binder plumbing, per the review's open question 2; pinned by A2 tests). Stage A2 acceptance now includes the let-bound pipeline example. |
| **F5** (MINOR) metatheory precision | **Folded.** §6: QF_AUFLIA named; strong politeness (Jovanović–Barrett 2010) with the `Arr σₖ Bool` leg identified as the reason politeness (not plain Nelson–Oppen) is needed; Sheng–Zohar et al. (IJCAR 2020) cited for the v2 datatype-key widening; Z3 model-based-combination note; store-chain complexity sentence. |
| **F6** (MINOR) absent non-goals | **Folded.** §1: `map-remove` (with the put-only-discipline note) and length polymorphism over `bytes[n]` named as non-goals; §2: bare `(bytes-zero)`/`(map-empty)` in an unconstraining context is a type error. |
| **F7** (MINOR) verdict inventory placement | **Folded.** The Risk-5 audit is now a stage-A1 acceptance criterion (§10), citing the ENUM-EQ-FALLBACK lesson (v0.14.32); Risk 5 retained as a pointer. |
| **F8** (CONFIRMING, resolves Rev 0 Q2) | **Folded.** §2: PROVE-polarity reads kept; Dafny/LH precedent cited; checkout-protocol non-negotiability argument incorporated; both-forms option explicitly rejected for v1; OBLIG-1-adequacy dependency of A4 recorded (§10). |
| **F9** (CONFIRMING, resolves Rev 0 Q1) | **Folded.** §5: two-array encoding kept with the Dafny/Boogie/F*/Why3 precedent; array-of-option costs named; the encoding's one real cost (F1's junk divergence) stated alongside the choice. |
| **F10** (CONFIRMING) | **Folded.** §5/Risk 1: `Map_default` cited as const-array-shaped external evidence; probe expected positive, still the first spike. |
| **Syntax check** (review's out-of-scope note) | **Checked.** The proposal's `bytes[64]`/`map[…,…]` spellings match the §12 grammar exactly (`bytes-type = "bytes" "[" INT "]"`, `map-type = "map" "[" type "," type "]"`, `LLMLL.md:1959–1965`) and the §3.2 table (`:135–140`). No reconciliation needed; §11's key-type change is the F2 disposition, not a spelling fix. |

Rev 0's "Open questions for the professor" section is retired: Q1 → F9, Q2 → F8, both resolved as proposed.

### Addendum (2026-07-12): `bytes-zero` determining-context rule — v1 narrowing BLESSED

The A0 implementation shipped a determining context **narrower** than §2's row ("`n` inferred from
usage — the `list-empty` precedent"): `(bytes-zero)` is legal only as the **whole body** of a
`def`/`def-shell` whose declared return is a literal `bytes[n]` (`TypeCheck.hs:967-1004`, the two
dispatch arms; bare occurrences elsewhere are a type error naming the rule). The language team
records this narrowing as the **v1 design**, superseding the §2 prose, on three grounds. (1) The
`list-empty` precedent does not transfer: a list's element type is a `TVar` the unifier can solve,
while a `bytes` length is an `Int` index outside unification — "inferred from usage" has no
mechanism in the shipped infer-then-unify checker, which carries no expected-type flow into `EApp`.
(2) Neither parser accepts a type annotation on a `let` binding (`Parser.hs:712` — "could be added
later"; the JSON-AST binding shape has no type field), so the natural mid-body determining context
does not exist on any surface. (3) The narrowing costs a refactor, not expressiveness: a mid-body
zero buffer is `(def zeros [] -> bytes[64] (bytes-zero))` away — a helper whose call site is
body-faithful (A1 reflects the callee's constructed value through assume-guarantee). Two widening
levers are recorded, unscheduled: **let-binding type annotations** (surface + JSON-AST binding
schema delta — the smaller move, and independently useful) or **bidirectional expected-type flow
into `EApp`** (a checker-architecture move; REF-META-5 deliberately chose local inference, so this
lever re-opens a settled decision and needs its own proposal). Neither is justified by one
constructor's ergonomics alone; revisit if agent-authored corpora show mid-body buffer construction
at meaningful frequency. `map-empty` is unaffected (its type parameters are `TVar`s; the generic
constructor path types it).
