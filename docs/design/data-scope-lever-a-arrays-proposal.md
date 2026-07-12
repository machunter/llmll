# Data-Scope Lever A — The SMT Theory of Arrays for `bytes[n]` and `map[k,v]`

> **Status:** Rev 0 — awaiting professor review
> **Track:** Data Scope Extension, Lever A ([`compiler-team-roadmap.md`](../compiler-team-roadmap.md) → *Future — Data Scope Extension*, row A: "Proposed — recommended first")
> **Didactic companion:** [`data-scope-extension.md`](data-scope-extension.md) Posts 6–8 (rationale); this document is the normative design.
> **Author:** language-team · 2026-07-11

---

## Restatement

Widen `Σ_auto` with the quantifier-free SMT theory of arrays (McCarthy `select`/`store`), backing the two compound types the surface already ships — `bytes[n]` and `map[k,v]` — so that array **index-in-bounds** and map **get-after-put** become statically dischargeable obligations. The design constraint inherited from `LLMLL.md` §5.3.3 is absolute: the extension must keep "SAFE" a decidable predicate on a fixed VC, which means the admitted fragment is QF_AX combined with QF-LIA by the polite-combination machinery the datatype class already uses, and everything outside it falls back through the existing four-item routing rather than silently degrading the guarantee.

This proposal **anticipates** the tracked Lever A roadmap row (it is that row's design document), **sidesteps** R1/Lever B (no dependent types are introduced — `bytes[n]`'s `n` is already a type-level literal; we only reflect it as a ground fact), and **defers** Lever C entirely (no induction, no recursive structures).

## Context located

1. `LLMLL.md` §3.2 (`:138`, `:140`) — `bytes[n]` and `map[k,v]` are shipped T1 type formers; `map[k,v]` has **no operations anywhere in §13**; `bytes[n]` is consumed only by the §13.11 crypto builtins.
2. `LLMLL.md` §5.3.3 (`:933–947`) — the `Σ_auto` signature definition, the polite-combination citations (Ranise–Ringeissen–Zarba FroCoS 2005; Jovanović–Barrett LPAR 2010), and the path-(a) ground-fact emission side-condition this proposal extends.
3. `LLMLL.md` §5.3.4 (`:952–989`) — body-faithful VC shape, PROVE/ASSUME call-site polarity, preconditions-never-stripped, `--strict-verified-core` conjuncts.
4. `LLMLL.md` §5.3.5 (`:993–1038`) — the verification matrix rows this proposal adds to; the `:1030` note on builtin admission legs and trust-tier propagation.
5. `LLMLL.md` §13.5/§13.6 (`:2198–2246`) — the `list-nth : … -> Result[a, string]` totality precedent this proposal deliberately departs from, and the Class-A boundary trust closure (`:2246`) the new runtime builtins join.
6. `compiler/src/LLMLL/FixpointEmit.hs` — `typeToSort` has **no `TBytes`/`TMap` case**; both hit the conservative `FQInt` default (latent hazard, Risk 5). The `$ok`/`$err` binder-splitting precedent (`:738–739`) grounds the two-array map encoding.
7. `compiler/src/LLMLL/FixpointIR.hs:55–64` — `FQSort` constructor inventory; `emitSort` renders sorts textually to `.fq` (`FQList → "Lst"` was "probe-verified accepted bare" — the same probe discipline applies to an array sort).
8. `compiler/src/LLMLL/ObligationMining.hs:171` — `isQfLia`, the single central classifier seam (post-CLASSIFY-EOP, v0.14.30).
9. `docs/design/data-scope-extension.md` Posts 6–8 — bug-class inventory, Lever A rationale, the checkout-brief evaluation-integrity rule (Post 8).
10. `docs/compiler-team-roadmap.md` → "What's NOT on this Roadmap" postscript — the feature freeze was lifted at v0.11; a new builtin lands through design → professor → engineer **with a written soundness argument**. This document is that argument.

**Spec-drift findings surfaced during reading** (flagged per discipline, routed to doc-lead; none blocks this proposal):

- **D1.** `LLMLL.md:1869` (§11.1 treaty example) uses `map-values` and `sum` — neither is a registered builtin, and unlike the `random-bytes` case (`:807`) the example carries no "illustrative, not runnable" flag.
- **D2.** `LLMLL.md:110` names `map-get` as an exemplar builtin in the naming-conventions table; no map builtin exists.
- **D3.** `data-scope-extension.md:116` — the "`bytes[n]` … the `n` is a type-level tag, not a solver fact" row flips when stage A1 ships; doc-lead updates the didactic table post-ship.

---

## Design proposal

### 1. Scope and non-goals

**In scope:** a minimal operation set over `bytes[n]` and `map[k,v]`; its typing rules; its reflection into SMT `select`/`store`; the `Σ_auto` extension and its decidability argument; the firewall for everything else; a staged delivery plan.

**Non-goals (explicit):** `list` indexing (Lever B — the bridge, depends on this lever); map cardinality/`map-size` (not expressible in QF_AX — counting is not an array-theory operation; a future measure would need its own Lever-B-style discipline and is **not** proposed); bytes slicing/concatenation (sequence theory — deferred); quantified array properties ("all bytes are zero", sortedness — quantifiers leave the QF fragment; there is deliberately no surface to write them); recursive structures (Lever C); variable-length `bytes` (already deferred at `LLMLL.md:2413`).

### 2. Surface

No new type formers and no new syntax constructs. Both type formers exist in the S-expr grammar (`LLMLL.md:1959,1962`) and the JSON-AST schema (`llmll-ast.schema.json:400,432`). The entire surface delta is **eight new builtins** (§13-style, kebab-case), all ordinary `EApp`/`app` nodes in both surfaces:

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

(Eight rows; `bytes-zero`/`map-empty` are constructors required for T1 usability — today a `map[k,v]` value is not constructible by any shipped operation at all, a gap D1/D2 make visible.)

**The partial-read decision.** `bytes-get` and `map-get` carry **preconditions** instead of returning `Result` (the `list-nth` pattern, `:2212`). This is the pivotal ergonomic choice of the lever, made deliberately: a `Result`-returning read moves out-of-bounds into the dynamic error channel, where a hole-filling agent can satisfy any contract by propagating the error — the memory-safety claim becomes unfalsifiable at verify time. A pre-carrying read makes in-bounds a **PROVE-polarity caller obligation** (§5.3.4 item 1) that the solver must discharge from the caller's own precondition and path condition — which is precisely the "index-in-bounds as a genuine obligation, not a length proxy" pitch of the lever. A `Result`-wrapped convenience (`map-get-opt`) can be layered later without disturbing this design. Queued for the professor (Q2).

**Strict immutability.** `bytes-set` and `map-put` are functional updates returning new values — exactly the semantics of SMT `store`. No mutation, no aliasing; the theory and the language invariant coincide with no translation gap. Codegen targets persistent structures (engineer's choice; `Data.Map`/`ByteString` copy-on-write are both admissible).

### 3. Typing rules and admissibility gates

Let `Γ ⊢ e : τ` be the existing type-assignment judgment (§3.4.6).

```
Γ ⊢ b : bytes[n]    Γ ⊢ i : int
─────────────────────────────────  (T-BytesGet)     obligation at intro site: 0 ≤ i < n   [contract channel]
Γ ⊢ (bytes-get b i) : int

Γ ⊢ m : map[k,v]    Γ ⊢ e : k     k ∈ {int, string}
────────────────────────────────────────────────────  (T-MapGet)   obligation: (map-has m e)   [contract channel]
Γ ⊢ (map-get m e) : v
```

(remaining rules are the evident analogues; `bytes-set` additionally obligates `0 ≤ v ≤ 255`.)

**Key-sort gate (type channel).** v1 admits map **keys** in `{int, string}` and map **values** in `{int, bool, string}` for the *reflected* (verified) path. `string` participates as the opaque `Str` carrier — a selected string value composes with the `string-length` measure but is otherwise opaque, unchanged from today. A map op at any other key type (e.g. `map[Color,int]`) is a **typechecker diagnostic on the operation** (the type former itself remains unrestricted T1); this mirrors how the strict-core gate refuses rather than pads (the REC-DESCENT refuse-not-pad precedent). Widening keys to admissible sums is a natural v2 (the datatype class is polite-combinable too) and is deferred, not blocked.

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
| `(bytes-zero)` / `(map-empty)` | const-array `K(0)` / `K(false)` where available; else an unconstrained fresh binder (sound, incomplete — §7) |

**Ground-fact discipline (path-(a) extension).** Two fact families are emitted as **ground facts per occurring term**, never as quantified axioms — extending the §5.3.3 emission side-condition verbatim:

- per `bytes[n]`-typed binder `b` in the obligation: `bytes-length(b) = n` (the type-level length becomes a solver fact — this single fact is what turns the length *tag* into a checkable bound);
- per occurring `select(b, i)` term over a bytes binder: `0 ≤ select(b, i) ≤ 255` (the byte-range fact, the analogue of the measure range axiom).

### 5. Sort lowering and the map encoding

New IR sort: `FQArr FQSort FQSort` (element and index both restricted per §3). Lowering (`typeToSort`):

- `bytes[n]` → `FQArr FQInt FQInt` — one binder, plus the ground length fact of §4.
- `map[k,v]` → **two** binders per source binder `m`: `m$has : FQArr σₖ FQBool` and `m$val : FQArr σₖ σᵥ` — the standard finite-map-as-presence-plus-value-array encoding, and a direct reuse of the emitter's established binder-splitting pattern (`FixpointEmit.hs:738–739` splits a `Result` binder into `v$ok`/`v$err` today).

The alternative — a single `FQArr σₖ (Option σᵥ)` array-of-datatype — is rejected for v1: it drags datatype selectors into every map atom and makes the polite-combination story three-theory-deep per term. The two-array form keeps each array's element sort scalar. Queued for the professor (Q1) since the choice is encoding-level, not surface-visible, and can be revisited without a spec change.

**`.fq` rendering.** `emitSort` renders `FQArr` to liquid-fixpoint's built-in map sort (`Map_t`, with `Map_select`/`Map_store` as the operation symbols — liquid-fixpoint carries this theory for LiquidHaskell's `Data.Map` embedding and lowers it to SMT arrays). This is the engineer's **first spike**: probe the textual `.fq` acceptance exactly as `Lst` was probe-verified (`FixpointIR.hs:196`). If the `.fq` surface refuses the map theory, the fallback is emitting SMT-LIB via the solver interface the `--leanstral` path already exercises — a feasibility question, not a design change (Risk 1).

**Activation gating (byte-inertness).** The `FQArr` lowering activates **only for functions whose contract or body mentions an array-class symbol**. Every other function — including the entire existing corpus (the §13.11 crypto examples pass `bytes[20]` values around without element access) — keeps today's lowering, guaranteeing **byte-identical `.fq` output** for programs that don't use the ops. This is the MATCH-WIDEN no-op discipline (v0.14.26 "n=2 byte-identical" precedent) applied at the sort layer.

### 6. The Σ_auto extension and its decidability argument

```
Σ_auto  =  QF-LIA core
        ∪  ( measure class  | path-(a) )
        ∪  ( datatype class | admissible sums )
        ∪  ( array class    | admissible index/element sorts, ground-fact discipline )   ← NEW
```

The array class is the quantifier-free extensional theory of arrays: McCarthy's read-over-write axioms (McCarthy, *Towards a Mathematical Science of Computation*, IFIP 1962) plus extensionality. Decidability of the quantifier-free extensional fragment: Stump–Barrett–Dill–Levitt, *A Decision Procedure for an Extensional Theory of Arrays*, LICS 2001. The implemented procedure including const arrays (needed for `bytes-zero`/`map-empty` reflection) is combinatory array logic: de Moura–Bjørner, *Generalized, Efficient Array Decision Procedures*, FMCAD 2009 — Z3's native procedure. Combination with QF-LIA (index and element arithmetic) and with the existing datatype class is by **polite theory combination** — the array theory is polite with respect to its index/element theories — citing the same pair the datatype class already rests on: Ranise–Ringeissen–Zarba (FroCoS 2005), Jovanović–Barrett (LPAR 2010). The `admissibleDatatype` acyclicity gate is untouched; arrays never appear as datatype payloads in v1 (a `bytes` payload inside a sum stays firewalled exactly as a `list` payload is today, §5.3.3 datatype-class bullet).

Consequence: for an obligation whose symbols lie in the extended `Σ_auto`, liquid-fixpoint/Z3 remains a **sound and complete decision procedure on the fixed VC** — SAFE stays a decidable side-condition, Theorem B's antecedent (§3.4.5) is preserved, and the trust-tier story does not change shape. No new tier, no new evidence kind.

### 7. Boundary and firewall

What stays **out**, and what happens when it's touched:

| Escape | Behavior |
|---|---|
| Aggregation/iteration over a structure (`sum` of map values, fold over bytes) | not in QF_AX; the four-item routing of §5.3.3 (`:925–929`): runtime assertion + `asserted` tier + `?proof-required` + trust-report propagation. `erBodyFallback` on the body side. |
| Quantified properties ("all bytes zero") | no surface exists to state them (no quantifier syntax in contracts); spec is silent — **intentional**. |
| `map-size` / cardinality | operation does not exist (§1 non-goal); nothing to fall back from. |
| Whole-structure equality posts (`(= m1 m2)` over maps) | v1-admitted **only if** the extensionality probe (Risk 1) lands; otherwise classified out-of-fragment → four-item routing. The refute crux and get-after-put never need it. |
| Constructor reflection when const arrays are unavailable | `bytes-zero`/`map-empty` result binder left unconstrained: **sound** (no false SAFE — the solver proves nothing *about* the fresh array) but incomplete (`(not (map-has (map-empty) k))` unprovable, falls back). Documented, not silent: the classifier labels it. |
| Array-typed value crossing a firewalled position (sum payload, `list` element) | existing firewall verbatim — clean fallback, never a crash (the PAIR-RET-2 crash-to-fallback precedent, v0.13.12). |

### 8. Interaction with the measure catalog

**Coexist; the catalog stays closed at two.** `string-length` and `list-length` are unchanged, M1–M4 discipline unchanged. `bytes-length` is **not a measure** — it is a per-binder ground equality to a type-level literal (§4), strictly weaker machinery than a local theory extension (no congruence argument needed; the fact is ground by construction). `map-size` is deliberately absent (§1). Lever B, when it comes, bridges `list-length` to indexing *through* this lever's theory; nothing here pre-commits it.

### 9. Trust story

The reflected ops' **runtime implementations** must agree with `select`/`store` semantics — the same boundary-trust closure as the Class-A indexing primitives (`LLMLL.md:2246`): concrete `Int64` shims at the Haskell seam, structures assumed to fit `Int64` length, a sub-case of the §7 FFI-builtin closure. The new builtins join that note's inventory. Contract violations on the unverified path (a `bytes-get` whose pre was not discharged because the function fell back) remain **runtime assertions, never stripped** — preconditions are never stripped (§5.3.4), so the dynamic backstop the rest of the language relies on is intact here too.

### 10. Staged delivery plan

Modeled on MATCH-WIDEN/REC-DESCENT: surface-inert first, discharge second, byte-identical no-op guarantees at every stage.

| Stage | Ships | Acceptance | No-op guarantee |
|---|---|---|---|
| **A0 — surface, verification-inert** | 8 builtins in `builtinEnv` + typechecker (incl. key-sort gate) + codegen + runtime; builtin contracts as **runtime assertions only**; classifier labels array contracts `non_qf_lia` → Advisory | ops run; existing suite green | zero `.fq` change anywhere (the REC-DESCENT Phase-1 "verification-inert" precedent, v0.14.24) |
| **A1 — bytes discharge** | `FQArr` sort + `.fq` probe + bytes reflection + ground facts (length, byte-range) + index/value obligations | the §11 refute crux **refutes** and its fixed twin **verifies**; positive-witness test required | byte-identical `.fq` for functions not mentioning array symbols (activation gate, §5) |
| **A2 — map discharge** | two-array binder splitting; `map-has`/`map-get`/`map-put` reflection; presence obligations | get-after-put verifies; aliased-key crux refutes | same gate |
| **A3 — classifier & agent surface** | `isQfLia`/`classifyContractFragment` admit array-class symbols **centrally** (`ObligationMining.hs:171`; the CLASSIFY-EOP lesson: one predicate, `EOp` and `EApp` forms, parser-faithful tests — v0.14.30); obligation-report + checkout-brief vocabulary; CDP/weakness-check handle array-typed candidates | array contracts classify `qf_lia`-tier obligations; brief lists the ops | report-shape only; no schema bump expected |
| **A4 — the flagship data example** | the data-axis example (experiment-lead slot): an agent-filled hole whose checkout brief carries an index-bounds obligation, under the Post-8 sole-channel rule | out of this proposal's scope; named as the lever's acceptance demo | — |

### 11. Worked micro-examples

**The refute crux (index out of bounds — the Heartbleed-as-memory shape).** A bounds *check* that is off by one; the body looks correct:

```lisp
(def read-at [b: bytes[64] i: int] -> int
  (pre  (and (>= i 0) (<= i 64)))          ;; BUG: <= admits i = 64
  (post (and (>= result 0) (<= result 255)))
  (bytes-get b i))
```

The intro-site obligation is `pre ⟹ 0 ≤ i < 64` (§3). At `i = 64` the antecedent holds and the consequent fails: **`refuted`**, with the counterexample `i = 64` — the solver catches the off-by-one, not a length proxy. Tightening the pre to `(< i 64)` verifies, and the post discharges from the byte-range ground fact of §4. This pair is the stage-A1 acceptance test and the positive witness required by the edge-case discipline.

**Get-after-put (map correctness).**

```lisp
(def cache-put [m: map[string,int] k: string v: int] -> map[string,int]
  (post (and (map-has result k) (= (map-get result k) v)))
  (map-put m k v))
```

Reflection: `result$has = store(m$has,k,true) ∧ result$val = store(m$val,k,v)`; both conjuncts discharge by read-over-write. **`verified`.** The discriminative twin — body `m` (dropping the put) — is **`refuted`** with a model where `¬select(m$has,k)`.

**Aliased symbolic keys.** Post `(= (map-get (map-put m k1 v) k2) v)` with no relation between `k1`,`k2` in the pre: **`refuted`** — read-over-write's else-branch yields `select(m$val,k2)` when `k1 ≠ k2`, and the solver produces exactly that counterexample. The theory reasons about symbolic key equality; nothing is concretized.

### 12. JSON-AST schema delta

**None.** Both type formers already exist as schema node kinds (`llmll-ast.schema.json:400` `map`, `:432` `bytes`); the eight operations are ordinary `{"kind":"app","fn":"bytes-get",…}` nodes, and builtins are name-resolved, not schema-encoded. `schemaVersion` stays 0.8.0. The checkout-brief/obligation-report vocabulary additions in A3 are data, not shape — no `brief_version` bump expected (the XMOD-SCOPE-BRIEF precedent bumped for a *shape* change; A3 adds none).

---

## Edge cases and degenerate inputs

1. **Positive witness (required for the pre-carrying guard).** Input: the `read-at` crux of §11 verbatim. Expected: `refuted`, counterexample `i = 64`; the `<`-twin `verified`. Channel: **contract** (intro-site obligation, §3). Cite: §5.3.4 PROVE polarity; stage-A1 acceptance row.
2. **Get-after-put and its dropped-put twin.** Input: `cache-put` of §11 and the body-`m` twin. Expected: `verified` / `refuted` respectively. Channel: **contract**. Cite: §4 reflection table.
3. **Aliased symbolic keys.** Input: the unconditional-`v` post of §11. Expected: `refuted` with a `k1 ≠ k2` model. Channel: **contract**. Cite: read-over-write else-branch.
4. **Opaque coexistence.** Input: `examples/totp_rfc6238/`-style code passing `bytes[20]` through `hmac-sha1` with no element access. Expected: verdicts and `.fq` **byte-identical** to today (activation gate, §5). Channel: **trust** (no change is the assertion). Cite: stage guarantees, §10.
5. **Inadmissible key sort.** Input: `(map-get m c)` where `m : map[Color,int]`. Expected: typechecker diagnostic on the operation; the *type* `map[Color,int]` itself remains legal T1. Channel: **type**. Cite: key-sort gate, §3.
6. **Underivable presence.** Input: `(map-get m k)` in a body whose pre says nothing about `k`. Expected: `refuted` (a model with `¬select(m$has,k)` exists; in the decidable fragment UNSAFE is a genuine counterexample, not "unproven"). Channel: **contract**. Cite: §5.3.4 (`:962`).
7. **Aggregate escape.** Input: a post summing map values (the `LLMLL.md:1869` shape). Expected: out-of-fragment → four-item routing, `erBodyFallback`, Advisory-tier obligation; never a crash. Channel: **trust** (tier degradation is the catch). Cite: §7 table; spec silent on aggregates — **intentional**.
8. **Constructor incompleteness under a failed const-array probe.** Input: `(not (map-has (map-empty) k))` as a post. Expected: falls back (unconstrained fresh binder — sound, incomplete), classifier labels it; flips to `verified` if the probe lands. Channel: **contract**, degrading to **trust**. Cite: §7 row 6, Risk 1.

## Verification mapping

| Obligation | Channel | Fragment | Notes |
|---|---|---|---|
| `bytes-get`/`bytes-set` index-in-bounds at intro site | contract | **QF-LIA + array class — auto-discharged** | the bound `n` is a ground fact (§4); the comparison is pure QF-LIA |
| `bytes-set` value range `0 ≤ v ≤ 255` | contract | **QF-LIA — auto** | |
| `map-get` presence pre | contract | **array class — auto** | `select` on `m$has` |
| get-after-put / read-over-write posts | contract | **array class + QF-LIA — auto** | Stump et al. 2001; de Moura–Bjørner 2009 |
| byte-range of a read (`0 ≤ select ≤ 255`) | contract | **QF-LIA — auto** | ground fact per occurring term, path-(a) discipline |
| whole-map/bytes equality posts | contract | array class **iff** extensionality probe lands; else **out-of-fragment** → four-item routing | Risk 1 |
| aggregates, quantified properties, `map-size` | — | **out of `Σ_auto`** — routing per §5.3.3 `:925`; `map-size` has no surface | *not* routed to Lean by default (ergonomics inversion) |
| runtime agreement of builtin implementations with `select`/`store` | trust | boundary closure (not a VC) | §9; `LLMLL.md:2246` inventory |

## Affected surface

- `LLMLL.md`: §3.2 note on `bytes`/`map` gaining operations; §5.3.3 `Σ_auto` formula + a fourth completeness bullet (array class); §5.3.4 coverage sentence; §5.3.5 new matrix rows; §13.5-adjacent new builtin table + the `:2246` closure inventory; §13.11's "n is a tag" implications. (Doc-lead, post-ship.)
- `compiler/src/LLMLL/`: `FixpointIR.hs` (`FQArr`, `emitSort`), `FixpointEmit.hs` (`typeToSort` cases replacing the `FQInt` default for operated-on binders; `exprToPred`/`bodyToPredM` reflection; binder splitting; ground facts; activation gate), `TypeCheck.hs` (`builtinEnv` + key-sort gate + builtin contracts), `CodegenHs.hs` (runtime ops + shims), `ObligationMining.hs:171` (`isQfLia` central extension), `ObligationAssembly.hs`/`Checkout.hs` (A3 vocabulary), `CDP.hs`/`WeaknessCheck.hs` (array-typed candidates). (Engineer's decomposition, not a plan.)
- `docs/llmll-ast.schema.json`: **no change** (§12).
- `docs/design/data-scope-extension.md`: D3 table-row update post-A1 (doc-lead).
- Roadmap: Lever A row status moves on settlement; stage structure above maps onto its acceptance criteria.
- Freeze policy: **not applicable** — lifted at v0.11; this document is the required written soundness argument (Context item 10).

## Risks and open questions

1. **liquid-fixpoint `.fq` array-theory surface unprobed.** Feasibility. The map theory (`Map_t`/`Map_select`/`Map_store`) exists in liquid-fixpoint for LH's use, but the textual `.fq` acceptance, const-array availability, and extensionality behavior are unverified in *our* pipeline. **Complicates (first engineer spike); does not block the design** — §7 defines sound degradations for both probe outcomes. Cite: `FixpointIR.hs:196` probe precedent.
2. **Solver cost.** Array VCs are costlier than pure QF-LIA. Bounded: per-function, only on array-mentioning obligations (activation gate), and the measurement pattern exists (`experiments/cdp-perf-0/`). Verification-ergonomics; matters at scale only.
3. **Classifier recurrence.** CLASSIFY-EOP (v0.14.30) showed a vocabulary blind spot silently downgrades obligation tiers project-wide. Mitigation is structural: one central `isQfLia` change, parser-faithful regression tests (not hand-built `EApp`), stage A3 as its own gated increment. Spec-drift class; complicates.
4. **CDP/weakness-check over array-typed results.** Identity/const candidate construction needs array-sorted skolems; unexamined. Verification-ergonomics; complicates A3, engineer to scope.
5. **Latent `typeToSort` default.** Today `TBytes`/`TMap` binders lower to `FQInt` (the conservative default) — two distinct maps mentioned by equality in a contract already unify as int-sorted terms. Benign today only because no operation is reflected; stage A1 must inventory existing contracts mentioning bytes/map binders before changing their sorts, so no verdict silently flips. Soundness-adjacent audit; small.
6. **Byte-range facts and `machine-int`.** The `0–255` element story is orthogonal to INT-3's QF-BV track; if `machine-int` ever lands, `bytes` elements should *not* silently become bit-vectors (that would move the array class to QF_ABV — decidable but a different cost profile). Scope note for INT-3's design; only matters if INT-3 wakes.

## Open questions for the professor

**Q1 — map encoding.** v1 encodes `map[k,v]` as presence+value array pairs (`m$has`, `m$val`) rather than a single array of an option datatype, trading a second binder for scalar element sorts. Is there established practice or a known completeness/performance cliff (combinatory array logic over ADT elements, nested polite combination) that argues for the option-array encoding instead — or a third standard finite-map encoding we should prefer while the choice is still surface-invisible?

**Q2 — partial reads with static preconditions vs total reads returning `Result`.** We commit `bytes-get`/`map-get` to PROVE-polarity preconditions (§2), diverging from our own `list-nth` totality precedent, on the argument that dynamic-error totality makes the safety claim unfalsifiable for a hole-filling agent. Dafny (array access with implicit bounds obligations) suggests the pre-carrying form; Liquid Haskell idiom varies. Is there a known ergonomic trap with obligation-carrying reads under *agent* (not human) authorship — e.g., systematic over-strengthening of caller preconditions to discharge them — that would argue for shipping both forms from the start?
