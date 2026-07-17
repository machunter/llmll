---
title: String-Valued Maps (A2.2-string) — `map[int,string]` in `Σ_auto`
status: SHIPPED v0.14.46 (Stage 1) + v0.14.47 (residue lift — returns + param-values + string RMW + cross-call A-G); remaining residue = map-empty construction + string keys
author: language-team · 2026-07-14 (Rev 0), professor fold same day (Rev 1)
track: Data Scope Extension Lever A2.2 (string values) — the sole remaining Lever-A item; downstream consumer of STRLIT
---

# String-Valued Maps (A2.2-string)

> **Status:** **SHIPPED v0.14.46** (Stage 1 — string-LITERAL values) **+ v0.14.47** (residue lift, Phase 1 of the A4 plan): string-valued map **RETURNS** (`strMapArraySort` marker `FQArr FQInt FQStr`; every `== mapArraySort` dispatch widened via `isMapArrRetSort`/`markerValSort`), **param-string put values** (`mapPutValVars` → carrier binder + body-`SortEnv` seeding), string **RMW chains** (`MRGet` carries the value sort), and **cross-call string-map A-G** (probed: caller failing a string-status pre refuted at the call site). Remaining residue: string `map-empty` construction + string KEYS (clean fallback). v0.14.46 also fixed a latent STRLIT range-fact crash (`strlit_… >= 0` ill-sorted; `injectRangeFacts` now excludes strlit constants).
> **Enabled by:** STRLIT (v0.14.44 distinctness + v0.14.45 code-point length), which made a string literal in map-value position reflect. Design record: [`string-literal-distinctness-proposal.md`](string-literal-distinctness-proposal.md).
> **Generalizes:** [`data-scope-lever-a-arrays-proposal.md`](data-scope-lever-a-arrays-proposal.md) §3 F2 disposition (lines 85–89), which specified string values as "remain admitted [but] routes out-of-fragment" pending literal reflection.

---

## Restatement

Admit **string-valued maps** (`map[int,string]`) into the reflected/verified path by threading a genuine `Str` sort for the value component array (`$val : (Map_t int Str)`), so a `map-get` result is a `Str`-sorted EUF term that composes with STRLIT's ground distinctness and length facts. String literals in map-value position now reflect (the STRLIT flip), so the "unreflected symbol" firewall that routed these clauses to Advisory (arrays §89) is gone. **String keys** (`map[string,int]`, `map[string,string]`) are a separable, larger increment (a second sort dimension) and are staged out.

## Background

The two-array map encoding splits a `map` param/result into `m$has` (presence) + `m$val` (values), both currently sorted `mapArraySort = FQMapArr` which renders `(Map_t int int)` (`FixpointIR.hs:220`). `map-get → Map_select m$val k`, `map-put → Map_store m$val k v` (native array theory); get-after-put and aliased/distinct int keys already discharge (A2/A2.1/A2.2-bool). The firewall on string values is `mapArrEncodableTy = isIntLike kt && isScalarLike vt` with `isScalarLike = isIntLike ∨ isBoolLike` (`FixpointEmit.hs:1526-1535`): a string value fails, so `mapClauseBlocked` routes the whole contract to Advisory fallback.

A2.2-bool (v0.14.43) rode bool values on the **int-0/1 bridge** (same `(Map_t int int)` `$val` + a `0 ≤ v ≤ 1` range fact). Strings **cannot** ride an int bridge — they need a genuine `Str` value-sort so `Map_select m$val k : Str` is comparable to the now-reflected `strlit_…` constants.

## Scope and staging

- **Stage 1 (this ship) — string values.** `map[int,string]`. One new sort dimension: the `$val` array's *range* becomes `Str`; `$has` is unchanged (`(Map_t int int)`, presence 0/1). Surface = param/result string-valued maps with `map-put` / `map-get` / literal-and-term comparison / `string-length`-on-value. **`map-empty` construction of a string-valued map is deferred** (see edge 5 / risk 3): its `Map_default (FQLit 0)` value default is int-sorted, and a Str default requires the value type at a syntactic site that lacks it — firewalled to fallback, not silently emitted.
- **Stage 2 (documented next step) — string keys.** `map[string,int]`, `map[string,string]`. A second sort dimension: both arrays' *domain* becomes `Str`, and every `Map_select`/`Map_store` key argument must be a `strlit_` constant or a `Str` carrier. Larger blast radius; staged out, mirroring STRLIT's own Stage 1/Stage 2 discipline.

## Design

### The value-array sort

Replace the constant `mapArraySort` at every **`$val`-position** binder site with a value-sort-aware function (`$has` keeps `mapArraySort` unconditionally):

```
mapValArraySort am vt
  | isStrLike am vt = FQArr FQInt FQStr    -- renders "(Map_t int Str)"
  | otherwise       = FQMapArr             -- "(Map_t int int)" — int / bool-0/1
```

`FQArr FQInt FQStr` already emits `(Map_t int Str)` (`FixpointIR.hs:219`); no new sort constructor is needed (unlike A2.1's `FQMapArr`-vs-`FQArr` distinction, which existed to render *identically* — the string value array renders *differently*, so it is self-identifying).

### The two body-channel threading sites (professor F1)

The gate widening is necessary but the **crash-relevant** sites are in the body channel, both currently hardwired to int and both recoverable from the `SortEnv se` (no `AliasMap` needed — resolving the `bodyToPredM`-has-no-`AliasMap` concern):

1. **`map-get` result sort** — `FixpointEmit.hs:2900` declares the fresh result `r FQInt` and equates it to `Map_select vl k`. For a string map that select is `Str`-sorted → sort-mismatch crash. `r`'s sort becomes `rangeOf (se ! vl$val)` (the already-threaded `$val` range).
2. **`map-put` value extraction** — `mapPairTermsB:1707` forces the put-value through `scalarIntTerm`, rejecting a `Str` value → silent `Nothing` → Advisory fallback (the comment at `:1692-1694` is the current firewall). A value-sort-aware extraction admits a `strlit_` literal (already reflected by `exprToPred`, the contract channel `mapPairTermsC:1681` gets this for free) and a `Str`-carrier param.

Because site 2 fails **silently** (fallback, not crash), the acceptance instrument is the `examples/` verdict inventory, not the type-checker.

### Gate widening

- `isStrLike am t` (new; alias-resolving, mirrors `isBoolLike`).
- `mapArrEncodableTy` value predicate → `isIntLike kt ∧ (isScalarLike vt ∨ isStrLike vt)`.
- `mapStrValuedTy` (new; mirrors `boolValuedMapTy`) — drives value-sort threading scope.
- `badPutValue` widens to admit a `Str` literal and a `Str`-carrier param.
- `syntEncodableMapTy` gains `TMap TInt TString`.

### No `boolMapUnsafe` analog is needed

`boolMapUnsafe` exists because a bool value is *int-bridged*; a bare bool-get in a `not`/`and`/`if` slot is an ill-sorted int-in-bool-position. A **string** value is a *genuine* `Str` sort; the typechecker already confines a `string`-typed term to string positions (`(+ (map-get m k) 1)` / `(= (map-get m k) 5)` are prior type errors). No string analog of the ill-sortedness guard is required — a structural simplification versus bool, contingent on the typechecker's string-position discipline (build-verify).

## Edge cases and degenerate inputs

1. **Positive witness — get-after-put verifies (was Advisory).** `def get-put [m: map[int,string] k: int] -> string (post (= result "admin")) (map-get (map-put m k "admin") k)` → `result = Map_select (Map_store m$val k strlit_admin) k`; select-after-store at the same key ⟹ `= strlit_admin`; post discharges. **Channel: contract → trust.** Cite `:1682-1685`, `:2377`.
2. **Value distinctness across keys — rides STRLIT distinctness.** `post (!= (map-get (map-put (map-put m 1 "a") 2 "b") 1) "b")` → select at key 1: distinct int keys `1 ≠ 2` (array theory) reduce it to `strlit_a`; `injectStrLitDistinct` supplies `strlit_a ≠ strlit_b` ⟹ SAFE. **Channel: contract.** Cite arrays §85.
3. **`string-length` on a map value — composes with STRLIT Stage 2.** `pre (= (map-get m k) "admin")`, `post (= (string-length (map-get m k)) 5)` → congruence `Map_select m$val k = strlit_admin` ⟹ `strLen(Map_select m$val k) = strLen(strlit_admin) = 5` (`injectStrLitLen`). SAFE. **Channel: contract.** Boundary: a select that does *not* reduce to a stored literal is an uninterpreted `Str` term with no length fact — sound but incomplete (the STRLIT edge-5 length-uniqueness gap, not new).
4. **`map-put` value forms.** Literal (`"x" → Map_store m$val k strlit_x`), `Str`-carrier param, string-typed callee result; a non-`Str` value is a prior **type** error. **Channel: type + contract.** Cite `badPutValue`, `mapPairTermsB:1707`.
5. **`map-empty` construction of a string map — out of Stage-1 scope (firewalled).** `Map_default (FQLit 0)` for the value array is int-sorted; a Str default needs the value type at a syntactic site (`mapPairTermsC:1685`) that lacks it. Routed to fallback (Advisory), not a crash. The default's *value* would be inert regardless — not by runtime partiality alone but by the **presence proof-obligation** `Map_select(m$has,k) = 1` (`:2897`): an unguarded `map-get` fails a PROVE-polarity obligation, so an absent-key value is never soundly observed. **Channel: trust (intentional deferral).** Cite `:1685/:1711`, `:2897`.
6. **Whole-map equality `(= m1 m2)` — firewalled (professor Q1, confirmed).** `wholeArrEqClause` (`:1481-1505`) detects whole-array/map equality and routes to contract-only fallback, keyed on `isMapTy` (value-type-agnostic), so `map[int,string]` inherits the firewall exactly as `map[int,int]`. This preserves the §5.3.4 UNSAFE-is-a-counterexample guarantee against the two-array split's pair-of-arrays pseudo-equality (arrays §F3). **Channel: contract (soundness firewall).**
7. **String keys — out of Stage-1 scope.** `map[string,int]` op routes to fallback/diagnostic exactly as today; Stage 1 neither regresses nor advances it. **Channel: type/trust (intentional deferral).** Cite arrays §227.

## Verification mapping

- **String-valued `map-get` comparison + length** — **Channel: contract. Fragment: (a) auto-discharged.** The obligation lands in the polite combination **QF_AX ⊕ QF_EUF ⊕ QF-LIA**: the value-array `Map_select m$val k` is a QF_AX select producing a `Str`-sorted term; equality/disequality against `strlit_…` is QF_EUF; `injectStrLitDistinct` (ground `≠`) and `injectStrLitLen` (ground `strLen = n`, QF-LIA) are quantifier-free ground facts.
- **Decidability (professor F4, affirmed).** The theories share *sorts* (`int` index, `Str` element), not *function symbols* (`select`/`store` vs `strLen` vs `+`); Nelson–Oppen combination (1979) propagates equalities over shared sorts — the shared *element* sort is no different in kind from the shared *index* sort A2 already ships. All obligations are **ground**, so we are not in the array-property fragment whose ∀-indexed properties approach undecidability (Bradley–Manna–Sipma, *What's Decidable About Arrays?*, VMCAI 2006). Decidable; `Σ_auto` (`LLMLL.md §5.3.3`).
- **Exact-reflection (§6.1) holds.** The select is over the split `$val` binder (no free binder) and the literal reflects (no unreflected symbol), so a solver UNSAFE is a genuine counterexample.
- **Classification** follows by construction: once `mapArrEncodableTy` admits string values and `exprToPred` reflects both the select and the literal, `isQfLia = isJust . exprToPred` (CLASSIFY-MEASURE) reclassifies these contracts with no separate classifier edit.

## Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs` — `isStrLike`, `mapStrValuedTy`, `mapValArraySort`; widen `mapArrEncodableTy` / `badPutValue` / `syntEncodableMapTy`; thread `mapValArraySort` through the `$val`-binder sites (`:685, :874-875, :956-958, :1099-1100, :3330`) and callee-return threading (`:2737, :2958-2960`); the two body-channel sites (`map-get` result sort `:2900`, `map-put` value extraction `mapPairTermsB:1707`), both off `SortEnv`; `map-empty` string-map firewall.
- `compiler/src/LLMLL/FixpointIR.hs` — none (`FQArr FQInt FQStr` already emits `(Map_t int Str)`).
- `TypeCheck.hs` — confirm `map[int,string]` ops typecheck and confine the `Str` result to string positions (build-verify; the no-`boolMapUnsafe`-analog claim rests on this).
- `ObligationMining.hs` / `ObligationAssembly.hs` — no direct edit (classifier follows via `isQfLia`); **`examples/` before/after verdict inventory is the acceptance gate.**
- Docs (post-ship, doc-lead): arrays §3 F2 (string values → SHIPPED, keys → Stage 2); `LLMLL.md §5.3.3` reflected-fragment row; roadmap row.
- **Schema:** none. **Surface syntax:** none. **Freeze:** N/A.

## Risks and open questions

1. **`$val` sort-threading completeness.** *Decidability/feasibility.* Every `$val`-binder + body-channel site must compute the value sort; a missed site emits `(Map_t int int)` for a `Str`-valued map → liquid-fixpoint sort-mismatch crash, OR (site `:1707`) a *silent* Advisory fallback. **Bite: the main build task — an exhaustive site sweep + a `.fq` emission probe on `map[int,string]` before wiring verdicts; the verdict inventory catches the silent case.**
2. **Blast-radius verdict flips.** *Verification-ergonomics.* String-valued-map contracts were Advisory; now verify/refute. A new **refute** is the dangerous direction (latent spec bug vs. real catch). **Bite: gates the ship** — the arrays §10 verdict inventory + a `refute-crux` pair.
3. **`map-empty` string default.** *Scope/soundness.* Deferred + firewalled (edge 5); the presence obligation (`:2897`) makes the default inert if a later stage threads it. **Bite: moot for Stage 1 under the firewall.**
4. **`Str`-param `map-put` value — DEFERRED (falls back cleanly).** *Verification-ergonomics.* A `string` param used as a `map-put` value (`(map-put m k s)`, `s : string`) needs both a `Str` carrier binder AND membership in the body-channel `SortEnv` (`buildSortEnv`, `FixpointEmit.hs:3983`, admits only scalar params today) — a coordinated change with a free-var-crash risk if the two drift. Stage 1 ships **string-LITERAL** values (the flagship status/tag-map pattern); a param-string value routes to Advisory fallback (sound, no crash), deferred to a follow-on. **Bite: an ergonomic gap on `set(m, k, name)`-shaped functions, not a soundness or crash risk.**

## Review-fold appendix — professor review (2026-07-14)

- **F1 (feasibility, folded):** the real crash sites are body-channel `FQInt` hardwiring — `map-get` result sort (`:2900`) and `map-put` value extraction (`mapPairTermsB:1707`), both recoverable from `SortEnv` (no `AliasMap`); site `:1707` fails *silently* → verdict inventory is the acceptance instrument. → §Design "two body-channel threading sites"; risk 1.
- **F2 (soundness, confirmed):** whole-map equality must stay firewalled. → Verified: `wholeArrEqClause:1481-1505`, value-type-agnostic; edge 6.
- **F3 (scope, folded):** `map-empty` default `FQLit 0` sort-crashes a string map; defer construction, and cite the presence obligation `:2897` (not just runtime partiality) for default-inertness. → §Scope, edge 5.
- **F4 (decidability, affirmed):** QF_AX ⊕ QF_EUF ⊕ QF-LIA with shared `Str` element sort is decidable (N–O shared sorts, not shared symbols; ground ⟹ not the array-property fragment, Bradley–Manna–Sipma 2006). → Verification mapping.
- **F5 (ergonomic, affirmed):** no `boolMapUnsafe` analog needed (genuine `Str` sort vs int bridge); `strLen`-over-non-literal-select incompleteness = STRLIT edge 5. → §Design, edge 3.

Recommendation: proceed to engineer. Scope = string values Stage 1 (param + `put`/`get`/compare/length; `map-empty` firewalled), keys Stage 2. Decidability settled; whole-map-equality firewall confirmed.
