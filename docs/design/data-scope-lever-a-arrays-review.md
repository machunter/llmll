# Professor Review — Data-Scope Lever A: The SMT Theory of Arrays (Rev 0)

> **Reviewing:** [`data-scope-lever-a-arrays-proposal.md`](data-scope-lever-a-arrays-proposal.md) (Rev 0, 2026-07-11)
> **Reviewer:** professor · 2026-07-11
> **Verdict:** proceed-with-revisions — gating findings F1, F2, F3 (F4 gates stage A2, not the design). See the final line.

## Restatement

The proposal extends `Σ_auto` with the quantifier-free extensional theory of arrays, giving the shipped-but-inert `bytes[n]`/`map[k,v]` type formers a decidable verification theory through eight builtins whose names reflect to `select`/`store`, with PROVE-polarity preconditions on the partial reads, a presence-plus-value two-array encoding for maps, ground-fact emission for type-level lengths and byte ranges, and a MATCH-WIDEN-style staged delivery (A0 inert → A1 bytes → A2 maps → A3 classifier → A4 flagship). The decidability claim is that the extended fragment remains one on which liquid-fixpoint/Z3 is a sound and complete decision procedure, so SAFE stays a decidable side-condition and `refuted` stays a genuine-counterexample claim.

## Context located

1. `docs/design/data-scope-lever-a-arrays-proposal.md` — the artifact under review, read in full.
2. `LLMLL.md` §5.3.3 (`:933–947`) — the `Σ_auto` completeness statement, the path-(a) ground-fact side-condition, the polite-combination citation pair the proposal inherits.
3. `LLMLL.md` §5.3.4 (`:962`) — "A body-faithful VC the solver reports UNSAFE is *refuted* — not *unproven*"; the claim F1–F3 must protect.
4. `LLMLL.md` §5.3.5 matrix (`:1004–1005`) — `ELet` body-faithful only for "single `PVar`, int RHS"; the coverage row F4 targets.
5. `LLMLL.md` §11.1 (`:2157`) — the language's `=` on `map[k,v]`: "equal if same key set and each value is `=`" — **observational** equality; the semantic anchor of F1.
6. `compiler/src/LLMLL/FixpointEmit.hs` — `typeToSort` conservative `FQInt` default (Risk 5 confirmed); `$ok`/`$err` binder splitting (`:738–739`); `exprToPred` literal cases are `LitInt`/`LitBool` **only** — a string literal reflects to nothing today (F2).
7. `compiler/src/LLMLL/FixpointIR.hs:55–64, :196` — `FQSort` inventory and the `Lst` probe precedent; no `Map_t`/`Map_select` symbol appears anywhere in the pipeline (probe genuinely unexercised — Risk 1 correctly framed).
8. `docs/design/data-scope-extension.md` Posts 6–8 — the bug-class inventory and Lever A rationale; the proposal is faithful to it.
9. External literature consulted: Stump–Barrett–Dill–Levitt (LICS 2001); de Moura–Bjørner (FMCAD 2009); Ranise–Ringeissen–Zarba (FroCoS 2005); Jovanović–Barrett (LPAR 2010); Sheng, Zohar, et al., *Politeness for the Theory of Algebraic Datatypes* (IJCAR 2020); Vazou et al. (ICFP 2014); Leino, *Dafny* (LPAR 2010); Kroening–Strichman, *Decision Procedures*, ch. 7.

## Findings

### F1 — MAJOR (gates §7 row 4): whole-structure `=` must not reflect to array equality; the two encodings diverge on unobservable junk

**Targets:** §5 (two-array encoding), §7 row "whole-structure equality posts", §11 examples.

The language defines map equality observationally (`LLMLL.md:2157`: same key set, equal values at present keys). The two-array encoding carries junk: nothing constrains `select(m$val, k)` where `¬select(m$has, k)`, and for `bytes[n]` nothing constrains `select(b, i)` outside `[0, n)`. Two observationally equal values therefore differ as array pairs in some model, so reflecting a surface post `(= m1 m2)` as `m1$has = m2$has ∧ m1$val = m2$val` lets the solver return UNSAFE with a counterexample that differs only at absent keys — a **spurious refutation of an observationally true post**. Under §5.3.4's own vocabulary (`refuted` = genuine counterexample, `:962`) this is a claim-accuracy break, the exact property the proposal elsewhere protects. The sound reflection of observational equality (`m1$has = m2$has ∧ ∀k. select(m1$has,k) ⟹ select(m1$val,k) = select(m2$val,k)`) is quantified and leaves the QF fragment. Note the same argument applies to `bytes` equality via out-of-range indices, and that solver-internal extensionality is untouched by this finding — the decision procedure may use extensionality freely; the defect is only in equating surface `=` with representational array equality.

**Recommendation:** route whole-map and whole-bytes equality posts out-of-fragment **unconditionally** in v1 (four-item routing), deleting the "iff the extensionality probe lands" conditional admission in §7 row 4. The probe (Risk 1) remains necessary for the theory's internal operation but no longer licenses that row. If whole-structure equality is ever wanted, it needs either a normalization invariant (absent keys pinned to a default — maintainable while the op set has no `map-remove`, but not assumable for symbolic parameters, which range over arbitrary models) or a bounded-index expansion for `bytes[n]` with literal `n` (n conjuncts, quantifier-free, viable for small `n` — a v2 option worth one sentence).

### F2 — MAJOR (gates the key-sort set): string keys need a literal-distinctness discipline, or v1 keys should be int-only

**Targets:** §3 key-sort gate, §4 reflection table.

The gate admits `k ∈ {int, string}`. Strings are the opaque `Str` carrier; `exprToPred` currently reflects **no string literal at all** (`FixpointEmit.hs` — literal cases are `LitInt`/`LitBool` only), so admitting string keys forces A2 to add a literal-reflection rule. If string literals reflect as uninterpreted `Str` constants — the obvious rule — then two distinct literals `"a"` and `"b"` are **not provably distinct**, and worse, a model identifying them refutes true posts: `(= (map-get (map-put (map-put m "a" 1) "b" 2) "a") 1)` is UNSAFE in the model `"a" = "b"` (read-over-write collapses the two stores). Spurious refutation again, same class as F1 but a different source. The measure class never hit this because `string-length` facts are per-term and no reasoning ever depended on two literals being unequal.

**Recommendation:** either (a) restrict v1 map keys to `int` (smallest change; symbolic string keys and the §11 examples still work — they use variables, and *variable* keys are exactly where the theory earns its keep), or (b) admit string keys with an explicit path-(a)-style side-condition: emit ground pairwise-distinctness facts `lit_i ≠ lit_j` for every pair of distinct string literals occurring in the obligation. Both are sound; (b) is complete for literal-keyed reasoning at quadratic-in-literals ground-fact cost (small in practice). The proposal must pick one and say so; silence here ships a refutation-soundness hole inside the headline fragment.

### F3 — MAJOR (gates §7): the refutation-completeness rule must be stated normatively, and degraded constructor reflection must be classifier-level, not emission-level

**Targets:** §7 rows 5–6, edge case 8, §6.

The proposal's degradation story for `bytes-zero`/`map-empty` under a failed const-array probe reads two ways: "unconstrained fresh binder: sound (no false SAFE) but incomplete" suggests the VC is **emitted** with a free binder, while "the classifier labels it" suggests the obligation is **routed out before emission**. These are not equivalent. An over-approximated body equation (free binder) is sound for SAFE — any post proved over all valuations holds for the real value — but **unsound for UNSAFE**: the solver can exhibit a "counterexample" using a valuation the real constructor never produces (`(not (map-has (map-empty) k))` is true of the real semantics and refutable over a free binder). The existing machinery never faces this because `Σ_auto` membership is exactly completeness: every emitted body-faithful VC is over an exact reflection, which is what licenses §5.3.4's refuted-means-counterexample claim.

**Recommendation:** state the general rule in §6 or §7 as a normative sentence: *an obligation may be emitted as a body-faithful VC (and hence may `refute`) only when every symbol in it has an exact reflection — sound and complete; any incompletely-reflected term forces the whole obligation to the four-item routing before emission.* Then pin the constructor row to the classifier-level reading. This single rule also subsumes F1 and F2 (both are instances of inexact reflection) and gives stage A3's classifier its correctness criterion rather than leaving it as vocabulary bookkeeping.

### F4 — MAJOR (gates stage A2's acceptance): the body-coverage inventory is missing — `ELet` with array-typed RHS, and composite map-valued terms in the emitter

**Targets:** §5, §10 stage A2, Affected surface.

Two coverage gaps the proposal does not name. First, the verification matrix (`LLMLL.md:1004–1005`) grants `ELet` body-faithful discharge only for "single `PVar`, int RHS"; a map pipeline — `(let [(m2 (map-put m k v))] (map-get m2 k))` — is the *normal* shape of map-using code, and without extending the `ELet` row to array-sorted RHS every such body falls back, leaving get-after-put verifiable only for single-expression bodies like §11's `cache-put`. Second, the reflection table's `map-put` row produces a **pair** of arrays, which is a per-binder story in §5 (the `$ok`/`$err` precedent splits binders) but becomes an expression-level story the moment a map-valued term nests: `(map-has (map-put m k v) k2)` requires `exprToPred`/`bodyToPredM` to carry a two-component symbolic value for map-typed *subterms*, not just split declared binders. That is a new emitter shape (component-pair threading through application nodes), and it is the actual engineering mass of A2 — the proposal's "direct reuse of the binder-splitting pattern" undersells it.

**Recommendation:** add a coverage-inventory subsection to §5 naming: `ELet` array-typed RHS (in scope, A2), `EIf` branches of array type (in scope — path-split already sort-agnostic, confirm), array-typed arguments at contracted call sites (assume-guarantee over array sorts — mechanical, confirm), and composite map-valued subterm reflection (the pair-threading rule, stated). Make stage A2's acceptance include the let-bound pipeline example, not only the single-call `cache-put`.

### F5 — MINOR: the combination metatheory is right but under-specified; name the stack order and add the datatype-politeness citation for v2

**Targets:** §6.

For v1 — scalar index and element sorts — the extended fragment is quantifier-free arrays + uninterpreted functions + LIA, i.e. textbook QF_AUFLIA (Kroening–Strichman ch. 7; standard SMT-LIB logic), and the citation base suffices. Two precision points. (i) The politeness that matters is **strong politeness** — Jovanović–Barrett (LPAR 2010) exists precisely because the original RRZ witness-function definition was flawed; since the proposal leans on the pair already, one clause saying "strong politeness in the JB 2010 sense" closes it. The leg that genuinely needs politeness is `m$has : Arr σₖ Bool` — Bool is finite, hence not stably infinite, so Nelson–Oppen alone does not cover it; arrays-over-int would not have needed it. Saying this in one sentence makes the argument auditable. (ii) The deferred v2 widening (map keys over admissible sums) stacks a third theory; the modern citation is Sheng, Zohar, et al., *Politeness for the Theory of Algebraic Datatypes* (IJCAR 2020) — strong politeness for datatypes — which composes with the array result. Also note as engineering context that Z3 implements combination via model-based theory combination rather than literal polite combination; the metatheory licenses decidability, the implementation is Z3's own, and the pinned-solver behavior is what the A1 probe measures. Complexity cliffs worth one sentence each: read-over-write case-splitting is exponential in store-chain depth in the worst case (de Moura–Bjørner 2009's filters mitigate; LLMLL bodies keep chains short), and nothing in v1 approaches the known hard corners (nested arrays, quantified array properties).

### F6 — MINOR: two absent non-goals should be named — `map-remove`, and length polymorphism over `bytes[n]`

**Targets:** §1, §2.

The op set has no deletion; §1's non-goals do not say whether that is deliberate. It should (it is trivially expressible later as `store(m$has, k, false)`, and its absence incidentally preserves a put-only normalization invariant F1 discusses — worth recording so a future `map-remove` does not silently invalidate reasoning that leaned on it). Separately, `n` in `bytes[n]` is a literal with no length variables, so a function polymorphic over byte-lengths is inexpressible; `bytes-zero`'s "n inferred from usage" must resolve to a concrete literal or fail typing. One sentence in §2 saying a bare `(bytes-zero)` in an unconstraining context is a type error, and one non-goals line ("no length polymorphism — Lever B/R1 territory"), close both.

### F7 — MINOR: the Risk-5 verdict inventory belongs in stage A1's acceptance row, not only in Risks

**Targets:** §10, Risk 5.

Changing `typeToSort`'s lowering of operated-on `TBytes`/`TMap` binders from the `FQInt` default is exactly the kind of silent-verdict-flip hazard the ENUM-EQ-FALLBACK episode (v0.14.32, refutation lost for twenty versions) showed survives review when it is not gated. The proposal already prescribes the right audit ("inventory existing contracts mentioning bytes/map binders"); promote it from a risk note to a named acceptance criterion of A1 alongside the refute crux — a before/after verdict inventory over `examples/`, exactly as the v0.14.32 fix validated itself.

### F8 — CONFIRMING (answers Q2): PROVE-polarity reads are the right call; the checkout architecture strengthens the proposal's own argument

The falsifiability argument holds: with `Result`-total reads, "no out-of-bounds access" is not a static claim anywhere in the program — the obligation dissolves into dynamic handling an agent can thread. The auto-active literature agrees: Dafny's `a[i]` carries an implicit bounds obligation of exactly this polarity (Leino, LPAR 2010), and Liquid Haskell's flagship vector examples (Vazou et al., ICFP 2014) use the refined-precondition form, with the `Maybe`-total variant as a layered convenience — the layering order the proposal already anticipates via `map-get-opt`. The over-strengthening trap named in Q2 exists but lands elsewhere in *this* system: a hole-filling agent under the checkout protocol **cannot edit the enclosing contract at all** (patches are scope-checked to the hole subtree), so at fill time the obligation must be discharged from the brief's `assumptions` and path facts — it is non-negotiable, which is precisely the falsifiability the design wants. Over-strengthening is confined to the contract-authoring and `refine`-spawn flows, where the CDP vacuity gate and the over-annotation guardrail already live; an unsatisfiable-pre function verifies vacuously today independent of arrays, so this lever adds no new instance of that hazard. Do not ship both read forms initially — the second form would reopen the unfalsifiability channel the first was chosen to close. One consequential dependency to name in §2: agent-side dischargeability rides on brief completeness (the OBLIG-1 `assumptions` line, through v2b), so the A4 flagship implicitly tests OBLIG-1's adequacy too.

### F9 — CONFIRMING (answers Q1): the two-array encoding is established practice; its cost is exactly F1, which should be named in §5

Presence-plus-value is the standard finite-map model across the auto-active tools: Dafny's map axiomatization (domain + elements), Boogie map models, F*'s `FStar.Map` (value array plus domain), and Why3's `fmap`. The array-of-option alternative is not wrong but pays a datatype case-split under every read and drags `Option` into every array lemma instantiation; with const arrays it also needs `K(None)`, coupling the constructor story to the datatype theory. No completeness cliff exists either way — both stay decidable — the difference is case-split volume, and established practice matches the proposal's choice. The one real cost of two arrays is the junk-value divergence between representational and observational equality (F1); §5 should carry a sentence naming it so the encoding's soundness condition (reads gated by presence; no surface reflection of whole-map `=`) travels with the encoding decision rather than living only in §7.

### F10 — CONFIRMING: the decidability core claim stands; the probe will likely land, including const arrays

The v1 fragment (ground facts, QF, scalar sorts) sits inside decidable territory by the citations given (Stump et al. 2001 for extensional QF arrays; de Moura–Bjørner 2009 for the implemented procedure with const arrays, i.e. `K(0)`/`K(false)` for the constructors). On the feasibility side: liquid-fixpoint carries a map theory for LiquidHaskell's `Data.Map` embedding (`Map_t`/`Map_select`/`Map_store`, and a `Map_default` symbol that is const-array-shaped), which is external evidence the A1 probe should succeed including the constructor reflection — while confirming the proposal's framing that *our* pipeline has never exercised it (no `Map_*` symbol appears anywhere under `compiler/src/`). The probe stays the first spike; its expected outcome is positive.

## Recommendation

Proceed with revisions; the design's architecture — reflect ops as vocabulary, ground-fact discipline, activation gating, staged delivery — is sound and well-precedented, and both open questions resolve in favor of the proposal's own choices (F8, F9). The revisions that gate Rev 1: (1) make whole-structure equality unconditionally out-of-fragment (F1); (2) decide the string-key question — int-only v1 or literal-distinctness ground facts (F2); (3) state the refutation-completeness rule normatively and pin constructor degradation to classifier-level routing (F3). Before stage A2 is scoped, add the coverage inventory (F4) — it changes the A2 effort estimate materially. F5–F7 are one-sentence-to-one-paragraph edits. None of this alters the surface, the schema, or the staging skeleton.

## Open questions for the language-team

1. **F2 disposition:** if string keys survive v1, specify the literal-distinctness emission rule as a §4 side-condition (path-(a) register: ground `≠` facts per occurring literal pair) and say what happens for a literal-vs-variable pair (nothing — only literal/literal pairs get facts). If keys go int-only, update the key-sort gate, §11, and the D1/D2 doc-drift notes accordingly.
2. **F4 confirmation:** confirm that `EIf` path-splitting and call-site assume-guarantee are genuinely sort-agnostic as implemented (I read the binder plumbing as sort-generic, but the claim should be the language-team's, verified against `FixpointEmit.hs`, not the reviewer's).

---

**Verdict: proceed-with-revisions — F1, F2, F3 gate Rev 1; F4 gates stage A2 scoping; F5–F7 editorial; Q1/Q2 resolved as proposed (F9, F8).**
