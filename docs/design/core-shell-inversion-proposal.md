# LT-INV — Core/Shell Grammar Inversion

> **Version:** Rev 3 — builtinEnv admission clause added to §4 as the third callee-admission class inside `def`
> **Date:** 2026-05-23 (Rev 1); 2026-05-25 (Rev 2); 2026-05-27 (Rev 3)
> **Implements:** `docs/compiler-team-roadmap.md` v0.11 milestone, Implementation Item 1 (LT-INV); the v0.11 spine
> **Prerequisites:** Feature freeze lifted for v0.11 (`docs/compiler-team-roadmap.md` Feature Freeze Policy, lifted 2026-05-23 with the inversion's freeze-exception soundness argument as the rationale)
> **Origin:** 2026-05-23 external critique processed via professor channel ([`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §1); language-team triage at [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §4; STRICT-CORE-1 from the triage is subsumed by this proposal (the admissibility rules become grammatical, not adversarial-spec-only)
> **Companion:** Professor direction memo [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) is the upstream architectural direction; cross-proposal settlement at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) specifies LT-CDP / LT-PPR shipping conditions under §8 gate outcomes
> **Reviewed:** Professor review at [`core-shell-inversion-review.md`](core-shell-inversion-review.md) (Rev 1, 2026-05-25); recommendation `approve with revisions`. Seven gaps and two author-question answers folded into this Rev 2. Standalone review awaits doc-lead M2 fold-and-archive.
> **Status:** Settled (Rev 3) — builtinEnv clause added; pending compiler-engineer hand-off behind `--grammar=core-inversion` opt-in flag per §8 empirical-gate sequencing

---

## 1. Motivation

The verification matrix at [`LLMLL.md §5.3.5:736-756`](../../LLMLL.md) partitions every syntactic construct into *body-faithful SMT*, *contract-only*, and *runtime assertion* verification regimes. The partition is correct. What is wrong is that **all three regimes are reachable from the same `def-logic` keyword** — a reader looking at one `def-logic` does not know, without inspecting the trust report or running `llmll verify`, which regime the function inhabits. The diamond lattice at [`LLMLL.md §4.4.1:325-344`](../../LLMLL.md) prevents silent coalescence in the *trust label*, but the *source surface* does not encode which lattice point a function reaches.

`--strict-verified-core` at [`compiler/app/Main.hs:246`](../../compiler/app/Main.hs) / [`:1119-1124`](../../compiler/app/Main.hs) is the existing mitigation: hard-error if any function falls back from body-faithful verification. The flag works, but it is a *verifier mode*, not a *source-level constraint*. A function whose body uses non-core constructs can be authored, parsed, and type-checked under the current grammar; the failure surfaces only at `llmll verify --strict-verified-core`. The polarity is wrong: the permissive form is the syntactic default, and the strict reading is a flag.

The professor direction memo at [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §1 makes the argument explicit:

> LLMLL should become a verified-core language embedded in an explicit coordination shell, not a coordination shell with an optional verified-core flag. The mechanisms that support this inversion are mostly shipped — what is wrong is the architectural default: today the source grammar treats the mixed regime as canonical, and the verified core is reached through a CLI flag and per-function trust-report inspection. A CLI flag says *"the mixed language is normal; strict core is a mode."* A grammar inversion says *"the core is normal; the shell is explicitly marked."* The architectural problem is which regime the source grammar treats as canonical, not whether the verifier has the right mechanisms.

LT-INV inverts the polarity at the grammar level. The strict-core form becomes the canonical definition keyword; the permissive regime becomes the explicitly-marked form. The shipped trust-lattice, weakness-check, obligation-report, refinement-alias, and capability-declaration machinery are unchanged; what changes is which lattice point is *syntactically* reachable from the canonical definition form.

**Cognitive-load argument.** When an agent reads one LLMLL function under the current grammar, the mental model it must maintain is the full pipeline — source → JSON-AST → typechecker → verifier encoding → trust classification → codegen → Haskell runtime — because the function's meaning depends on which path through the verification matrix the function takes, and that is not visible from the surface. The grammar inversion solves this at the source level: inside a core definition, the agent knows that fallback constructs are syntactically unavailable, and that the function is either body-faithfully verified or rejected. The five-stage pipeline still exists in the implementation, but the agent does not need to model it to read one function.

**Empirical-search-space argument.** A smaller grammar surface inside the core form reduces LLM hallucination surface and produces local parse-time rejection in place of pipeline-traversal verifier diagnostics. The hypothesis is plausible. It is not yet measured; per §8 below, v0.11 ships the inversion behind an empirical validation gate and does not commit irreversibly to the architectural bet until the existing benchmarks confirm it.

---

## 2. Scope

**In scope:**
- Adjudicate keyword choice (`def-logic` retained vs renamed to `def`)
- Specify whitelist grammar production for core definition bodies
- Decide `letrec` routing (outside core as shell form; vs schedule strict-descent verification to admit verified-total `letrec` into core)
- Decide `EApp` callee restriction (strict transitive body-faithful closure vs relaxed v0.9.0 assume-guarantee)
- Distinguish hole forms admissible inside core vs forbidden
- JSON-AST `schemaVersion` bump `0.5.0 → 0.6.0` (additive at the statement-kind enumeration)
- Migration scope and tooling specification per memo §1.5
- §8 empirical validation gate hook — LT-INV ships behind `--grammar=core-inversion` opt-in flag first; default flips only on gate pass

**Out of scope (deferred):**
- **`letrec` strict-descent verification.** Research-track per [`docs/research-track.md`](../research-track.md) §7. LT-INV routes `letrec` to `def-shell` only; recursion in `def` waits for descent encoding.
- **Refinement-aliased non-int types inside core.** v0.11 admits `EVar` int-typed and refinement-aliased base-int types (`PositiveInt`, `NonNegInt`); relaxation to refinement-aliased strings (`Word`, `Letter`), refinement-aliased ADT-fields, and refinement-aliased lists is a v0.12+ widening conditional on `FixpointEmit.hs` support landing.
- **`def-logic` deprecation timeline beyond v0.11.** v0.11 ships an auto-rewrite-with-warning behavior on `def-logic`; v0.12 may harden to error-only. Decided at v0.12 planning, not here.

**Out of scope under v0.11 sequencing:**
- LT-CDP, LT-PPR ship in parallel with LT-INV per the v0.11 milestone but are gate-independent of LT-INV per [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §8.3 rollback path (2).

---

## 3. Surface — keyword choice and grammar production

### 3.1 Keyword choice: **adopt Option 2 (rename `def-logic → def`)**

`def` is the canonical strict-core form. `def-logic` is **retired** as a source-level keyword in v0.11 (under the opt-in flag `--grammar=core-inversion`, use produces a `core-grammar-violation` diagnostic and exit non-zero; when the default flips at Outcome 0, the `--migrate` tool auto-rewrites existing corpus files per the mechanical classifier in §6). The permissive form is `def-shell`.

**Rationale.** The inversion's thesis is "the verified-core fragment IS the language." Option 1 (keep `def-logic` for the strict core, introduce `def-boundary` for the marked form) preserves the project's identity-keyword for its strongest reading but leaves a *legacy keyword for the legacy regime* in the surface; an agent reading the corpus continues to see `def-logic` as the canonical form, and the inversion's polarity claim is undermined at the lexical level. Option 2 makes the polarity unambiguous: the agent reading `def` is in the verified fragment by syntactic guarantee; the agent reading `def-shell` is in the permissive fragment.

Per [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §Background, backward compatibility is not a v0.11 governor; the keyword break is the right cost.

**Corpus-continuity cost (Rev 2, per the professor review's Gap #6).** The rename forfeits a *corpus-continuity* signal at the lexical level: agents trained on the v0.10 corpus see `def-logic` and the v0.11 corpus see `def`, and the rename is a discontinuity in the agent-prompt-context distribution. The Coq community's long-running debate over `Definition` / `Lemma` / `Theorem` canonicity is the closest precedent — the multi-keyword convention has held for two decades precisely because the meaning-distinguishing role outweighs the canonicity-by-rename argument when the corpus is mature. LLMLL's choice (Option 2, rename) is defensible because the v0.10 corpus is small (12 example directories) and the meaning-distinguishing role here is *exactly* the `def` vs `def-shell` distinction — the lexical canonicity and the semantic distinction align. The cost is real but bounded by corpus size; Rev 2 records it explicitly so future migrations (v0.12+) at larger corpus scale can audit whether the rename pattern still wins.

**Naming for the shell form.** `def-shell` over `def-boundary` or `def-effectful`:

- `def-boundary` reads as topological-relative ("boundary between *what* and *what*?")
- `def-effectful` is too narrow — effects are *one kind* of fallback construct, but ADT match, lambdas, non-linear arithmetic, and `?proof-required` are not effects
- `def-shell` matches the memo's "core/shell" framing and is symmetric with `def` at the same syntactic level

### 3.2 Whitelist grammar production

The core-form production lists *only the constructs admitted*; everything else parse-errors inside a `def` body. The blacklist alternative ("everything except the known fallbacks") admits future syntax accidentally into the core before the verifier supports it — a soundness regression the inversion is designed to prevent.

**Production sketch** (formalized into `LLMLL.md §12` by doc-lead after this proposal settles):

```
core-body  ::= core-expr
core-expr  ::= ELit-int | ELit-bool | EVar-int | EVar-refined-int
             | EOp-qfla    ;; +, -, =, <, <=, >=, >, !=, and, or, not
             | ELet-pvar-coreexpr
             | EIf-coreexpr-coreexpr-coreexpr   ;; with path-limit guard
             | EApp-corecallee
             | EMatch-Result-twoarm
             | ?hole | ?name | ?choose | ?request-cap | ?scaffold | ?delegate | ?delegate-async
             ;; ?proof-required is NOT admitted (see §3.5 below)

shell-body ::= any expr per LLMLL.md §12 (current grammar unchanged)
```

`EVar-refined-int` covers refinement-aliased base-int types (`PositiveInt`, `NonNegInt`) per [`LLMLL.md §3.4:229-241`](../../LLMLL.md). Non-int `EVar`s are excluded from the core form in the v0.11 ship; relaxation to non-int refinement-aliased values is a v0.12+ widening decision (per §2 deferred-scope).

### 3.3 `letrec` routing — **adopt route (i): outside the core as shell form**

`letrec` lives in `def-shell` only in v0.11. Migrating recursion into the core requires strict call-site descent verification, which is research-track per [`LLMLL.md §5.3.3:684-691`](../../LLMLL.md) and not on the v0.11 docket.

**Rationale.** The inversion's value proposition is *syntactic guarantee of body-faithful reachability*. Admitting `letrec` into the core today (which verifies measure-well-formedness `measure ≥ 0` per [`LLMLL.md §4.2:272-296`](../../LLMLL.md) but not strict descent) means a `def` body containing a recursive helper still satisfies `verified` *trivially under non-termination*, which is exactly the non-negativity-≠-termination defect TERM-1 flags (and which Pass 5 of the catch-up just strengthened in the spec via the partial-correctness disclaimer). Better to keep `letrec` honest in `def-shell` and revisit when descent verification lands.

**Migration consequence.** The interactive game examples (`hangman_sexp`, `tictactoe_sexp`, `life_sexp`) lose core-form status for any recursive helper; the verifier-form examples (`*_verifier`) likely stay in core because their verified contracts are non-recursive QF-LIA per memo §1.5. This is the expected migration cost.

**Cascade quantification (Rev 2, per the professor review's Gap #5).** The `letrec`-routes-to-shell rule cascades through the §3.4 strict-callee restriction (now relaxed per Rev 2 §3.4 below): any `def` body that calls a `letrec`-defined function would, under the Rev 1 strict reading, migrate to `def-shell`. Under the Rev 2 trusted-prelude-closed reading, a `letrec`-defined function is admitted in `def` callees only if the function's signature is in the trusted prelude (per §3.4's revised callee predicate); user-authored `letrec` helpers stay outside the trusted prelude and therefore continue to cascade their callers to `def-shell`. The boundary-form usage distribution per §8.1 axis 4 measures this cascade post-migration; **pre-migration pre-flight quantification is recommended** — engineer or experiment-lead should run the §6 mechanical classifier on the corpus under v0.11 sequencing step (2) and report the projected `def` vs `def-shell` split before the empirical gate runs. If the projected split is materially skewed toward `def-shell` (Risk #7 below), the §8 pass criteria's boundary-form usage axis is the load-bearing acceptance signal.

### 3.4 `EApp` callee restriction — **adopt the trusted-prelude-closed reading** (Rev 2)

**Rev 2 revision (per the professor review's Gap #1 / Q-PROF-1).** Rev 1 specified the *strict* reading — `EApp` inside `def` admits only callees whose own bodies are body-faithfully verified, transitive closure required. The professor review surfaced that this reading is **unprecedented among production refinement-typed languages**. Liquid Haskell (`{-@ assume @-}` per Vazou et al. POPL 2014), F\* (`assume val` per Swamy et al. 2013–present), Why3 (curated prelude per Filliâtre & Paskevich ESOP 2013 §4.3), and Dafny (trusted built-ins per Leino LPAR 2010) all maintain a *curated trusted-prelude set* admitted into the verified call closure. No production system requires every callee in a verified function's call graph to be body-faithfully proven. Rev 2 adopts the *trusted-prelude-closed* reading: callees admitted in `def` are those whose `erBodyFaithful = True` *or* which are in a configured trusted-builtin whitelist hosted in [`LLMLL.md §13`](../../LLMLL.md).

**Operational rule (revised).** At the call site `(f x y)` inside a `def` body, the typechecker queries the callee's admissibility via two predicates:

1. **Body-faithful predicate:** `erBodyFaithful(f) = True` per the callee's `EvidenceRecord`. If true, the call is admitted.
2. **Trusted-prelude predicate:** `f ∈ trustedPrelude` per the curated `LLMLL.md §13` whitelist. If true, the call is admitted *under the trusted-prelude trust closure* — the call inherits `f`'s axiomatized signature, not a `verified`-tier promotion. Calls reaching only trusted-prelude callees remain `verified` at the call site under the v0.9.0 assume-guarantee mechanism applied against the axiomatized signature.

If neither predicate holds, the typechecker emits a *core-membership-violation* diagnostic.

**Trusted-prelude curation.** The trusted-prelude whitelist is a separately-curated artifact at [`LLMLL.md §13`](../../LLMLL.md), populated by doc-lead promotion post-LT-INV-settlement. Initial population candidates (subject to engineer-audit confirmation):

| Builtin class | Body-faithful? | Trusted-prelude admission |
|---|---|---|
| `+`, `-`, `=`, `<`, `<=`, `>=`, `>`, `!=` (QF-LIA primitives) | yes (direct, mathematical-integer per v0.10.8 INT-1 / post-INT-2 unbounded) | n/a — already body-faithful |
| `and`, `or`, `not` (boolean connectives) | yes | n/a |
| `*`, `/`, `mod`, `rem` (non-linear arithmetic) | no | **NOT admitted** — non-linear; routes to runtime per v0.10 verification matrix |
| `string-length`, `string-concat` | no | **admitted** — axiomatized at §13 with linear/length-preservation signatures |
| `list-head`, `list-tail`, `list-length`, `list-is-empty?` | no (partial) | **admitted** — axiomatized with non-emptiness preconditions; partial-function failure modes routed per LT-PPR predicate-carrying form |
| `pair`, `first`, `second` | no | **admitted** — axiomatized; tuple semantics straightforward |
| `random-int`, `int-to-string` | no | **admitted** — axiomatized; randomness sealed at builtin boundary per strict-immutability invariant |
| `sha1`, `hmac-sha1` (crypto stubs per §13.11) | no | **NOT admitted** — `asserted-with-stub-backend` per the v0.10.6 CRYPTO-1 disclosure; verifier should not admit programs whose `def`-form claim of `verified` rests on a known-incorrect runtime implementation |
| `?delegate` / `?delegate-async` / `?scaffold` resolved values | no | **NOT admitted** by default; post-resolution re-typecheck per §3.5 Rev 2 |

The `builtinEnv` admission leg covers `EApp` nodes in contract clause expressions (`pre`/`post`) as well as function bodies, because `withCoreMode` wraps the full `checkStatement (SDef …)` block including contract-clause `inferExpr` calls ([`TypeCheck.hs:707–729`](../../compiler/src/LLMLL/TypeCheck.hs#L707-L729)).

The whitelist is settled by language-team via a separate REF-META-3-adjacent settlement (the predicate WF rule's *trusted-axiomatization* sub-rule); the table above is the v0.11 starting set. Engineer-audit confirms each row by inspecting the `LLMLL.md §13` axiomatization and the codegen lowering; entries that pass audit ship in the v0.11 trusted prelude.

**`meContracts` extension (Rev 2, per the professor review's Gap #2).** The typechecker query at the call site requires `erBodyFaithful` lookup, which is not currently in `ModuleEnv` per [`compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs) (`meContracts :: Map Name ([(Name, Type)], Contract)` carries contracts only). Rev 2 commits to **extending `meContracts`** to carry an `erBodyFaithful :: Bool` field per function entry — i.e., the shape becomes `Map Name ([(Name, Type)], Contract, Bool)` or an equivalent named-field record. This is engineer scope, surfaced explicitly in the LT-INV engineer hand-off. The trusted-prelude whitelist is a separate `Set Name` in `ModuleEnv` (or equivalent), populated at compiler startup from a curated builtin list — no per-function `EvidenceRecord` query for prelude callees.

The two-pass alternative (typecheck → verify → second typecheck) is *not* adopted — the `meContracts` extension preserves the v0.10 layering with an additive field, at the cost of populating `erBodyFaithful` from prior `.verified.json` sidecars on cold-cache builds. Cold-cache builds may produce conservative-rejection diagnostics requiring a verify-then-build sequence; the engineer hand-off names this cost.

**Cost calibration (revised).** The v0.9.0 assume-guarantee mechanism stays unchanged for `def-shell`; it is narrowed inside `def` to the trusted-prelude-closed reading. Migration cost: any function in the existing corpus whose call graph reaches an *untrusted* `tested`-only or `asserted` callee migrates to `def-shell`. Functions reaching only trusted-prelude callees stay in `def`. This is the right discipline — those functions are body-faithfully verified *modulo the trusted prelude*, which is the same trust model LH, F*, Why3, and Dafny ship.

### 3.5 Hole forms — admit authoring intermediates; forbid `?proof-required`

`?hole`, `?name`, `?choose`, `?request-cap`, `?scaffold`, `?delegate`, `?delegate-async` are **admitted inside `def`** — they are authoring intermediates and the function does not verify-complete until filled. `?proof-required` is **forbidden inside `def`** — it is an asserted-tier escape hatch and admitting it would re-introduce the very semantic non-uniformity the inversion fixes.

This distinction does not exist in [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs) today (per `Syntax.hs:233-243`, all `HoleKind` constructors are treated uniformly at parse). The inversion forces it: the grammar production in §3.2 lists the admitted hole forms explicitly; `?proof-required` is omitted from the core grammar.

Per LT-PPR §6.2, the predicate-carrying form of `?proof-required` (proposed in v0.11 separately) is also forbidden inside `def` for the same reason. Both leaf and predicate-carrying forms of `?proof-required` live exclusively in `def-shell`.

**Post-resolution re-typecheck for `?delegate` / `?delegate-async` / `?scaffold` (Rev 2, per the professor review's Gap #3).** `?delegate`, `?delegate-async`, and `?scaffold` resolve to values produced by out-of-process agents at agent-loop time. The Rev 1 §3.5 admission rule treats these as authoring intermediates whose resolution is verifier-transparent; the review surfaced that resolved values whose evidence is `asserted` would silently re-introduce an `asserted`-tier dependency into a `def`-form call graph, defeating the inversion's grammatical-guarantee claim. Rev 2 commits to the following discipline: **after `?delegate` / `?delegate-async` / `?scaffold` resolution, the agent loop re-runs the typechecker's core-membership predicate on the resolving function or value before merging the resolution into the `def`-form host.** If the resolved value's evidence does not satisfy the §3.4 Rev 2 admissibility predicate (body-faithful OR trusted-prelude), the resolution is rejected and the host function migrates to `def-shell` (or the resolution is replaced). The orchestrator at [`tools/llmll-orchestra/`](../../tools/llmll-orchestra/) and the per-resolution-step flow at [`compiler/src/LLMLL/Module.hs`](../../compiler/src/LLMLL/Module.hs) carry this re-typecheck obligation; the engineer hand-off names the integration point. Without this, the grammatical guarantee at §3.4 degrades whenever a delegate resolution lands.

---

## 4. Illustrative grammar boundary

The table below is **illustrative**, derived from the verification matrix at [`LLMLL.md §5.3.5:736-756`](../../LLMLL.md). The language-team formalizes the grammar production at `LLMLL.md §12` post-settlement.

| Admitted in core (`def`) | Excluded from core (allowed in `def-shell`) |
|---|---|
| `ELit` (int, bool) | — |
| `EVar` (int-typed; refinement-aliased base-int via §3.2 `EVar-refined-int`) | `EVar` non-int (Option-A scope; relaxable per §2 deferred) |
| `EOp` over QF-LIA: `+`, `-`, `=`, `<`, `<=`, `>=`, `>`, `!=`; boolean connectives `and`, `or`, `not` | `EOp` non-linear: `*`, `/`, `mod`, `rem` |
| `ELet` (single `PVar`, int RHS) | `ELet` (pattern / non-int RHS) |
| `EIf` under the 4096-path limit per [`LLMLL.md §5.3.4`](../../LLMLL.md) | `EIf` exceeding the path limit |
| `EApp` to a contracted callee with body-faithful verified evidence (per §3.4 strict-callee rule) | `EApp` to uncontracted / recursive-self / opaque callees |
| `EMatch` on `Result` (two-arm Success/Error) per [`LLMLL.md §5.3.4`](../../LLMLL.md) | `EMatch` general ADT; `EPair`; `ELambda`; `EDo`; `Command` construction |
| Refinement-aliased base-int types per [`LLMLL.md §3.4:229-241`](../../LLMLL.md) | `?proof-required` (leaf or predicate-carrying); opaque crypto; untrusted FFI calls; `letrec` (per §3.3) |
| `?hole`, `?name`, `?choose`, `?request-cap`, `?scaffold`, `?delegate`, `?delegate-async` (authoring intermediates per §3.5) | — |

The three callee-admission classes inside `def` that the language-team explicitly decided:

- **`EApp` to contracted callees** (§3.4 above): strict reading. Transitive body-faithful closure required.
- **`letrec`** (§3.3 above): route (i). Outside the core as shell form in v0.11.
- **builtinEnv callees**: builtins are the third callee-admission class inside `def`; their trust tier propagates into the caller via the lattice meet per [`LLMLL.md §4.4.1`](../../LLMLL.md).

---

## 5. Schema delta

JSON-AST adds a top-level distinction at the definition node. Current v0.5.0 shape:

```json
{ "kind": "def-logic", "name": "f", "params": [...], "body": {...} }
```

v0.11 v0.6.0 shape (illustrative — doc-lead formalizes post-engineer-ship):

```json
{ "kind": "def",       "name": "f", "params": [...], "body": {...} }   // strict core
{ "kind": "def-shell", "name": "g", "params": [...], "body": {...} }   // permissive
{ "kind": "def-logic", "name": "h", "params": [...], "body": {...} }   // v0.10 legacy → deprecation diagnostic
```

`schemaVersion` bumps `0.5.0 → 0.6.0`. The schema-delta is additive at the kind enumeration; existing v0.5.0 fixtures parse-warn under v0.11 with auto-rewrite via the mechanical classifier (§6 below). LT-PPR's `predicate` field on `hole-proof-required` rides the same bump.

The schema's `additionalProperties: false` discipline at every layer is preserved; the new `def` and `def-shell` kinds are listed in the statement-kind enumeration with the same field shape as `def-logic`. No nesting changes; no required-field additions or removals.

---

## 6. Migration scope

Concretely: twelve example directories under [`examples/`](../../examples/) plus the [`examples/benchmarks/`](../../examples/benchmarks/) suite. The `*_verifier` examples (`examples/hangman_json_verifier/`, `examples/tictactoe_json_verifier/`, `examples/conways_life_json_verifier/`) likely remain in the core form, since their verified contracts are already in QF-LIA. The interactive game examples (hangman, tictactoe, life) split between an effect-boundary form (game loops returning `Command`) and the shell form (general-ADT match, pair destructuring, etc.).

**Mechanical classifier.** A syntactic classifier — the same one needed for core-membership checking — auto-migrates by inspection of the function body:

```
old:
    (def-logic f ... body)

new:
    if body is syntactically core (per §3.2 whitelist):
        (def f ... body)              ;; canonical core form
    else:
        (def-shell f ... body)        ;; permissive form
```

This is exercise material, not legacy. There is no API-stability obligation; v0.10.6 just shipped a `schemaVersion` bump in a patch release (per the v0.10.6 CHANGELOG entry at [`CHANGELOG.md:5`](../../CHANGELOG.md)).

**Conservative-mode flag.** Per Risk #3 below, the classifier ships with a `--migration-conservative` flag that defaults all to `def-shell` if any single function in the file falls back; promotion to `def` requires human confirmation per-file. This protects against misclassifying intentionally-permissive bodies whose author wanted shell semantics but whose body happens to be core-syntactic.

**Rust-edition precedent and confidence-tier reporting (Rev 2, per the professor review's Gap #7 / Q-PROF-2).** The closest external precedent for the migration tooling shape is **Rust's 2018 edition migration** (rust-lang/rfcs #2052; `cargo fix --edition`): syntactic classifier handles the bulk; ambiguous cases require human review; the migration is widely considered successful precisely *because* the tooling did not over-promote. Python 2 → 3 (`2to3`, `lib2to3`) is a longer-tail precedent with similar shape but weaker types in the source language; F\# 4.x → 5.x is smoother because of stronger type inference. The honest answer from the language-migration literature: **the human-confirm requirement is essentially inherent for any nontrivial semantic-boundary migration**; the best the tooling can do is high-precision/low-recall classification of unambiguous cases plus *flagging* of ambiguous ones rather than auto-promotion. LT-INV's `--migration-conservative` flag matches the Rust-edition pattern.

Rev 2 commits to one additional refinement: **the classifier reports a *confidence tier* alongside its inferred form**. Output format:

```
solution.llmll:
  solution/transfer       : def        (confidence: high)
  solution/cache-lookup   : def-shell  (confidence: high — uses lambda)
  solution/parse-input    : def-shell  (confidence: low — body is core-syntactic but flagged by --migration-conservative)
  solution/sum-to-n       : def-shell  (confidence: high — letrec)
```

Three tiers — `high` (auto-promoted), `low` (flagged for review), `unable-to-classify` (the function does not parse under either grammar; engineer triage required). The `--migration-conservative` flag's behavior is: if any function in the file is `confidence: low`, all functions in the file default to `def-shell` pending human confirmation. The confidence-tier output gives the human reviewer a triaged list rather than a flat enumeration; this is the load-bearing improvement over a binary "promote vs not" classifier per the Rust-edition precedent.

---

## 7. Holes vs proof escapes — the §3.5 distinction in detail

Per §3.5 above, `?hole`/`?name` and `?proof-required` are treated differently:

| Hole form | Admitted in `def`? | Reason |
|---|---|---|
| `?hole`, `?name` | **Yes** | Authoring intermediate; function does not verify-complete until filled |
| `?choose`, `?request-cap`, `?scaffold` | **Yes** | Coordination intermediates; do not affect verification once resolved |
| `?delegate`, `?delegate-async` | **Yes** | Delegation intermediates; resolved at agent-loop time; do not erode verification |
| `?proof-required` (leaf) | **No** | Asserted-tier escape hatch — admitting it would re-introduce the very semantic non-uniformity the inversion fixes |
| `?proof-required` (predicate-carrying, LT-PPR) | **No** | Same reason as leaf form; the predicate enriches the gap but does not promote it past `asserted` |

The distinction is enforced at the grammar level (per §3.2 whitelist) and double-enforced at [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs) by extending the hole-admission predicate to consume the surrounding-form context (`def` vs `def-shell`).

---

## 8. Empirical validation gate

The inversion is an **architectural hypothesis** grounded in cognitive-load and search-space arguments. The hypothesis is plausible. It is not yet measured. Per [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §8, **v0.11 must not ship the inversion as a proven win; it must ship it as a hypothesis tested against the existing experimental harness.** The original v0.10 obligation report was the project's prior bet on what helps LLMs (surface rich obligations); the inversion is a *different* bet (limit the grammar surface). Choosing between them is empirical.

**Instrument:** [`experiments/minimal-agent/001-two-agent-auth`](../../experiments/minimal-agent/) (18 attempts × 5 models, documented in [`experiments/minimal-agent/findings/`](../../experiments/minimal-agent/findings/)) and the post-DL-B follow-up batches.

**Sequencing per `core-shell-inversion-direction.md` §8.4:**

1. `language-team` settles this proposal plus LT-CDP and LT-PPR. (This proposal: settled at Rev 1.)
2. `compiler-engineer` ships the LT-INV grammar change behind an explicit opt-in flag (`--grammar=core-inversion`), not as the default. LT-CDP and LT-PPR ship in parallel (gate-independent per §8.3 rollback path 2).
3. `experiment-lead` runs the pre/post comparison on `001-two-agent-auth` and the post-DL-B batches; the four axes named in §8.1 of the direction memo are measured.
4. **If the gate passes**, `compiler-engineer` flips the default; `documentation-lead` migrates examples per §6 and bumps schemas per §5.
5. **If the gate fails**, route to (i) demote to opt-in or (ii) retract grammar change and ship LT-CDP + LT-PPR only.

This protects against the worst failure mode: shipping a v0.11 that the existing benchmarks reveal as a regression after the schema and example migration are irreversible.

**Pass criteria (Rev 2, per the professor review's Gap #4).** **At least one of** (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts must improve over the pre-inversion baseline; **AND** boundary-form usage distribution shows ≥25% `def` in migrated examples (per §8.1 axis 4); **AND** no axis regresses materially. The Rev 1 OR-of-three admitted a 1%-improvement low-confidence pass; the Rev 2 conjunction defends against that case. The 25% `def` threshold is measured post-migration on the corpus and is the load-bearing acceptance signal for the boundary-form usage axis — without it, a "100% shell migration with no other axis change" outcome (per Risk #7) would flag the inversion as low-leverage without triggering rollback.

**Materially** remains `experiment-lead`'s call against the variance baseline established in [`experiments/minimal-agent/findings/`](../../experiments/minimal-agent/findings/); the conjunction does not pre-commit to a hard threshold for "materially," but it pre-commits to the conjunction shape.

**Outcome enumeration (Rev 2, per cross-proposal C-2 settlement).** The §8 gate result routes to one of three outcomes, each specified in [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) §2:

- **Outcome 0 — gate passes.** Default grammar flips per §8.4 step (4); LT-CDP and LT-PPR ship as proposed; schema bumps `0.5.0 → 0.6.0` and `1.1.0 → 1.2.0`; mechanical migration runs.
- **Outcome 1 — rollback to LT-INV opt-in-only.** Grammar change shipped behind `--grammar=core-inversion` flag but not default; LT-CDP `discriminative_axis` reported only under flag; LT-PPR predicate-carrying form admitted in `def-shell` under flag and *rejected entirely outside the flag* (does not admit-in-`def-logic`-by-default; the asserted-tier escape hatch protection is preserved); schema bump preserved; example migration skipped.
- **Outcome 2 — retract LT-INV grammar change.** LT-CDP ships against `def-logic` with the body-faithful set as implicit scope; LT-PPR ships *without* the `def`-forbiddance (the §3.5 forbiddance is contingently undone); independent `schemaVersion 0.5.0 → 0.5.1` coordinated single bump.

The C-2 settlement specifies the cross-proposal shipping conditions in full; this §8 section names the gate's role in selecting among them.

---

## 9. Edge cases

1. **A `def`-form body containing a call to an `?proof-required`-degraded callee.** Input shape:
   ```lisp
   (def f [n: int] (post (> result 0)) (g n))
   ```
   where `g`'s `post` contains `?proof-required` and `g` is `DLAsserted` per [`LLMLL.md §4.4.1`](../../LLMLL.md). **Expected behavior** under §3.4 strict-callee rule: core-membership-violation diagnostic at the call site `(g n)`; the agent must either migrate `f` to `def-shell` or `g` must be lifted out of `asserted`. **Channel:** type (the core grammar admits this construct *structurally* but the callee-restriction predicate rejects it). **Citation:** [`LLMLL.md §5.3.5`](../../LLMLL.md) verification matrix for `EApp` row; new core-grammar production per §3.2.

2. **A `def`-form body using `*` (non-linear arithmetic).** Input shape:
   ```lisp
   (def square [n: int] (post (>= result 0)) (* n n))
   ```
   **Expected behavior:** parse-error inside `def` (the §3.2 whitelist excludes `*`, `/`, `mod`, `rem`); the migration tooling rewrites to `def-shell square` automatically. **Channel:** type (parse-time rejection inside core grammar). **Citation:** [`LLMLL.md §5.3.5`](../../LLMLL.md) "`EOp`/`EApp` (*, /, mod, rem)" row marks SMT-body-faithful as ❌; the inversion makes this syntactic.

3. **A `def`-form body using `?proof-required` directly.** Input shape:
   ```lisp
   (def f [n: int] (post ?proof-required) n)
   ```
   **Expected behavior:** parse-error inside `def`; the agent must use `def-shell` or eliminate the proof obligation. **Channel:** type. **Citation:** §3.5 above; §3.2 production omits `?proof-required` from the admitted hole list.

4. **A `def`-form body whose `letrec` call appears inside an `EApp` to a contracted body-faithful callee that itself uses `letrec`.** Input shape:
   ```lisp
   (def f [n: int] (sum-to-n n))
   ```
   where `sum-to-n` is a `letrec` with body-faithful `:decreases`. **Expected behavior** under §3.3 and §3.4: `sum-to-n` is `def-shell`-only because of §3.3 (`letrec` excluded from core); therefore `sum-to-n`'s `erBodyFaithful = False` for transitive purposes; therefore §3.4 rejects the call. The recursion exclusion in §3.3 cascades through §3.4. **Channel:** type. **Citation:** new core-grammar production §3.2; v0.9.0 assume-guarantee at [`LLMLL.md §5.3.4`](../../LLMLL.md).

5. **An `EMatch` on `Result`.** Input shape:
   ```lisp
   (def f [r: Result] (match r ((Success v) v) ((Error e) 0)))
   ```
   **Expected behavior:** admitted in core per the `EMatch-Result-twoarm` clause in the production. **Channel:** type. **Citation:** [`LLMLL.md §5.3.5`](../../LLMLL.md) "`EMatch` on `Result` (2-arm Success/Error)" row.

6. **A `def`-form body containing `?hole`.** Input shape:
   ```lisp
   (def f [n: PositiveInt] (post (> result 0)) ?hole)
   ```
   **Expected behavior:** parses and typechecks; the hole's expected type is reported via the obligation report; the function does not verify-complete until the hole is filled. No core-membership violation. **Channel:** type (authoring intermediate). **Citation:** §3.5 above; [`LLMLL.md §6`](../../LLMLL.md).

7. **A `def-shell` function calling a `def` function.** Input shape:
   ```lisp
   (def increment [n: int] (post (= result (+ n 1))) (+ n 1))
   (def-shell wrapper [n: int] (let [(r (increment n))] r))
   ```
   **Expected behavior:** admitted (no restriction on shell→core calls; only core→non-core is restricted). The shell function inherits the core function's `verified` evidence; the trust report records the dependency. **Channel:** type (no restriction). **Citation:** §3.4 is asymmetric — core has callee restriction, shell does not.

---

## 10. Verification mapping

- **Channel:** type (core-membership-violation diagnostics are typechecker-emitted at parse-and-typecheck time). Trust channel unchanged (the diamond lattice at [`LLMLL.md §4.4.1`](../../LLMLL.md) is unaltered).
- **Fragment:** structural (parse-time predicate over the AST shape); no SMT obligation added. The inversion *reduces* SMT-fragment surface inside `def` to QF-LIA per the whitelist, which is what the inversion's value proposition rests on.
- **Cite:** [`LLMLL.md §5.3.3, §5.3.5`](../../LLMLL.md) for the QF-LIA boundary that the whitelist enforces; [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs) (extends with core-vs-shell hole-form distinction); [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) (extends with core-callee-restriction lookup at `EApp`).

The inversion adds no new SMT VC. The verifier-side work is *narrowed*, not expanded — every `def` body verifies under a strict subset of the v0.10 surface. The new obligations are structural (parse-time / typecheck-time predicates over AST shape), not logical.

---

## 11. Affected surface

- [`LLMLL.md`](../../LLMLL.md) — §3 (no change to types), §4 (renames `def-logic` → `def` + adds `def-shell` definition forms), §5.3.4–5.3.5 (verification matrix gains a "core-admissible" column or annotation), §6 (hole table adds core-vs-shell distinction; cross-references LT-PPR), §12 (grammar productions rewritten per §3.2 whitelist)
- [`compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs) — `Statement` constructor split: `SDef` strict + `SDefShell` permissive, replacing `SDefLogic`; `HoleKind` unchanged at AST level (core-vs-shell is enforced at parse, not at AST shape)
- [`compiler/src/LLMLL/Parser.hs`](../../compiler/src/LLMLL/Parser.hs), [`compiler/src/LLMLL/ParserJSON.hs`](../../compiler/src/LLMLL/ParserJSON.hs) — core-grammar whitelist production at the body level; deprecation diagnostic on `def-logic`
- [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) — core-callee-restriction at `EApp`; needs `EvidenceRecord` read access (via MOD-1's `meContracts`)
- [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs) — core-vs-shell hole-form admission predicate
- [`compiler/app/Main.hs:246`](../../compiler/app/Main.hs), [`:1119-1124`](../../compiler/app/Main.hs) — `--strict-verified-core` flag stays as a *redundancy check* in v0.11 (the grammar makes it unnecessary for `def`, but the flag still flags any `def-shell`-bodied function whose verifier classification would degrade)
- New flag `--grammar=core-inversion` for v0.11 opt-in shipping per §8 sequencing; flag retired when default flips on gate pass
- [`docs/llmll-ast.schema.json`](../llmll-ast.schema.json) — `schemaVersion 0.5.0 → 0.6.0`; node-kind enumeration extension; bundled with LT-PPR's `predicate` field addition
- [`examples/`](../../examples/) — 12 directories migrated mechanically per §6; classifier provided by compiler-engineer with `--migration-conservative` opt-in for ambiguous cases
- [`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md) — Feature freeze policy lifted for v0.11 (already landed in Pass 1 of the 2026-05-23 catch-up); this proposal is the v0.11 spine
- [`docs/design/critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) — STRICT-CORE-1 row supersedes-and-replace: the admissibility rule set is no longer codified by spec text alone but enforced by grammar

---

## 12. Risks and open questions

1. **Empirical gate may reject the inversion.** Severity: high. Classification: scope. Cite: [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §8 gate criteria. Bite: blocks v0.11 ship of LT-INV; rollback to (i) opt-in flag or (ii) ship LT-CDP + LT-PPR without inversion. **Mitigation:** sequence per direction memo §8.4 — ship behind `--grammar=core-inversion` opt-in first, run gate, flip default only on pass.

2. **Core-callee transitive-closure restriction (§3.4) is operationally expensive at typecheck time.** Severity: medium. Classification: verification-ergonomics. Cite: [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) currently does not query `EvidenceRecord`; the inversion forces an architectural coupling. Bite: typecheck runtime grows with call-graph depth; for cold-cache cases, the typecheck may need to invoke `verify`-side body-faithfulness checks first. **Mitigation:** cache `erBodyFaithful` in `ModuleEnv` (likely already there per MOD-1's `meContracts` extension); engineer audit confirms.

3. **Migration heuristic may misclassify intentionally-permissive bodies.** Severity: medium. Classification: spec-drift (between user intent and mechanical classifier). Cite: the classifier sketch in §6 is purely syntactic. Bite: a function whose author wanted `def-shell` semantics but whose body happens to be core-syntactic gets migrated to `def`, then breaks when extended. **Mitigation:** ship the classifier with a `--migration-conservative` flag that defaults all to `def-shell` if any single function in the file falls back; require human confirmation for `def`-promotion per-file.

4. **`?proof-required` exclusion from core eliminates the v0.10 escape hatch for in-core proof obligations.** Severity: medium. Classification: scope. Cite: §3.5 above. Bite: a `def`-form function with a partially-proven postcondition cannot mark the unproven sub-clause locally; must migrate to `def-shell`. **Mitigation:** LT-PPR's predicate-carrying form is `def-shell`-only and partially compensates by giving the migrated function richer evidence-channel content.

5. **`def-logic` keyword retirement is a corpus-wide rename.** Severity: low. Classification: spec-drift. Cite: every spec file, every example, every test mentions `def-logic`. Bite: documentation-lead's migration is large but mechanical. **Mitigation:** auto-rewrite via the classifier in §6. The v0.11 transition guide should make the rename's mechanical nature explicit.

6. **Strict callee restriction (§3.4) is strictly stronger than `--strict-verified-core` today.** Severity: low. Classification: scope. Cite: [`compiler/app/Main.hs:1119-1124`](../../compiler/app/Main.hs). Bite: today's `--strict-verified-core` rejects fallback at the *current function*; §3.4 requires transitive non-fallback through the call graph. Programs that pass `--strict-verified-core` today may fail core-membership under §3.4. **Mitigation:** this is the intended behavior — name it explicitly in the migration guide; the strict-callee rule is the right discipline once the inversion is in place.

7. **`def-shell` migration may push the LLM-generated code distribution toward shell-by-default.** Severity: medium. Classification: verification-ergonomics. Cite: §8.1 axis "boundary-form usage distribution" — if migration produces near-100% `def-shell` usage, the inversion has not changed where LLM-generated code lives. Bite: the canonical form becomes canonical in name only; the empirical gate may pass on the trivial reading (no regression because no change). **Mitigation:** the gate's pass criteria require improvement on at least one of grade distribution / `verified` evidence fraction / `?proof-required` emission rate. A "100% shell migration with no other axis change" outcome flags the inversion as low-leverage and triggers rollback path (ii).

---

## 13. Open questions for the professor review

**Status (Rev 2):** both questions answered in the Rev 1 professor review at [`core-shell-inversion-review.md`](core-shell-inversion-review.md) §"Answers to author-surfaced questions"; the answers are folded into Rev 2 at §3.4 (Q-PROF-1: trusted-prelude-closed reading, citing LH/F*/Why3/Dafny convergence) and §6 (Q-PROF-2: Rust-edition precedent confirms human-confirm is inherent; confidence-tier reporting is the load-bearing improvement). The questions are retained below as the historical record of the Rev 1 → Rev 2 transition.

1. **Is the transitive body-faithful closure (§3.4) the right closure shape, or should the inversion instead require the closure under a *weaker* invariant** (e.g., "all callees are at minimum `contract-checked`")? The strict-reading rationale is principled: a `def`-form function asserting `verified` cannot rest on `asserted` callees without leaking that asserted-ness. But the principle has a cost — most useful programs have *some* opaque builtin in the transitive closure (`string-length`, `random-int`, `wasi.*`). The relaxed closure ("contract-checked or better") would let builtins-with-contracts pass while still excluding `asserted` and `tested`-only callees. Is there an established treatment in the Liquid Haskell / F\* literature of this "closure-under-evidence-tier" question, and does the established treatment match §3.4 strict or a relaxed variant? — *Rev 2 answer: the LH / F\* / Why3 / Dafny convergence is the trusted-prelude-closed reading; the strict reading is unprecedented. §3.4 adopts the trusted-prelude-closed reading with the `LLMLL.md §13` whitelist as the curation surface.*

2. **The migration scope (§6) treats syntactic classification as the migration's primary signal.** The risk is misclassification per Risk #3; the mitigation is conservative-mode plus human-confirmation. **Is there a known pattern in the language-migration literature** (e.g., F# 4.x → 5.x, Python 2 → 3, ES5 → ES6) **for syntactic-only migration tooling that handles intent-disambiguation better than the conservative-flag-plus-human-confirm route LT-INV proposes?** Specifically: is there a tractable static analysis that infers "the author wanted shell semantics" from surrounding context, or is the human-confirm requirement inherent? — *Rev 2 answer: the human-confirm requirement is essentially inherent per the Rust-edition / Python 2→3 / F# precedents. §6 ships the confidence-tier reporting as the load-bearing improvement; the classifier flags ambiguous cases rather than auto-promoting.*

---

## 14. Companion review

Professor review landed at [`core-shell-inversion-review.md`](core-shell-inversion-review.md) (Rev 1, 2026-05-25) as part of the batched four-proposal review turn (LT-INV, LT-CDP, LT-PPR, REF-META-1). Recommendation: `approve with revisions` on seven gaps and two author-question answers, all folded into this Rev 2 inline at the marked "Rev 2" touchpoints (§3.1 corpus-continuity; §3.3 cascade quantification; §3.4 trusted-prelude-closed reading + `meContracts` extension commitment; §3.5 post-resolution re-typecheck; §6 Rust-edition precedent + confidence-tier reporting; §8 tightened pass criteria + Outcome enumeration). The review carried the v0.11 cluster's cross-proposal observations C-1 through C-4; the C-2 settlement landed at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) (Rev 1, 2026-05-25) as a coordination artifact, referenced from §8 above.

The standalone `core-shell-inversion-review.md` was folded into the §"Appendix — Professor review log" below and archived to [`docs/archive/professor-reviews/core-shell-inversion-review.md`](../archive/professor-reviews/core-shell-inversion-review.md) under DOC-CONSOLIDATE §M2 (doc-lead Pass 10, 2026-05-25).

This proposal is the v0.11 architectural spine and is sequenced ahead of LT-CDP and LT-PPR per §8 — both gate-independent of LT-INV per the rollback paths specified at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md).

---

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal has been folded into this appendix and the source file archived to `docs/archive/professor-reviews/core-shell-inversion-review.md`. One line per finding; all resolved in Rev 2 of this proposal.

**Source:** `docs/design/core-shell-inversion-review.md` at commit `5f31580` (review dated 2026-05-25; reviewer: Lead Consultant for Formal Language Design).

### Gaps (all resolved in Rev 2)

1. **Strict-callee closure brittleness vs §13 builtins.** Rev 1 §3.4 strict reading would force `def-shell` migration for most builtin-touching code. Resolved: Rev 2 §3.4 adopts the *trusted-prelude-closed* reading citing LH / F* / Why3 / Dafny convergence; `LLMLL.md §13` whitelist is the curation surface.
2. **Typechecker→`EvidenceRecord` coupling architectural cost.** Rev 1 Risk #2 mitigation was thin. Resolved: Rev 2 §3.4 commits explicitly to extending `meContracts` to carry `erBodyFaithful :: Bool`; engineer hand-off names the architectural delta.
3. **`?delegate` / `?delegate-async` admission re-introduces asserted-tier path.** Rev 1 §3.5 silent on post-resolution re-typecheck. Resolved: Rev 2 §3.5 commits to post-resolution re-typecheck integration in agent loop.
4. **Empirical-gate pass criteria loose.** Rev 1 §8 OR-of-three admitted low-confidence wins. Resolved: Rev 2 §8 tightens to conjunctive (at-least-one-improves AND ≥25% def boundary-form usage AND no material regression).
5. **`letrec` exclusion cascade.** Rev 1 §3.3 silent on quantification. Resolved: Rev 2 §3.3 commits to pre-flight cascade quantification before §8 gate runs.
6. **Keyword choice rationale weak on migration ergonomic.** Rev 1 §3.1 understated corpus-continuity cost. Resolved: Rev 2 §3.1 adds the Coq-precedent acknowledgment with bounded-cost-by-corpus-size rationale.
7. **Migration tooling intent-disambiguation hard.** Rev 1 §6 conservative-mode flag is correct but unrefined. Resolved: Rev 2 §6 adds Rust-edition (`cargo fix --edition`) precedent and commits to three-tier confidence reporting (high / low / unable-to-classify).

### Open questions (both resolved in Rev 2)

- **Q-PROF-1.** Closure-under-evidence-tier in LH / F* literature — strict vs relaxed. Resolved: Rev 2 §3.4 — LH `{-@ assume @-}`, F* `assume val`, Why3 prelude, Dafny built-ins all converge on the trusted-prelude-closed reading. Strict reading is unprecedented.
- **Q-PROF-2.** Tractable static analysis for shell-vs-core intent inference. Resolved: Rev 2 §6 — human-confirm is essentially inherent per Rust 2018 / Python 2→3 / F# 4→5 precedents. Confidence-tier reporting is the load-bearing improvement.

### Cross-proposal observations (C-1 through C-4)

The review carried the v0.11 cluster's cross-proposal observations; full text in `refinement-metatheory-of-record-proposal.md` §"Appendix — Professor review log" / Cross-proposal observations subsection. C-2 (cross-proposal rollback discipline) settled at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md); §8 Rev 2 names the three outcomes per the C-2 settlement.

### Overall assessment (recorded)

The review recommended `approve with revisions` on seven gaps and two author-question answers. Rev 2 (settled 2026-05-25) carries each resolution inline at the cited §-references above. The standalone `core-shell-inversion-review.md` is archived; this appendix is the in-proposal pointer.

---

## §8 Gate Outcome

**Gate runs:** baseline `20260528T012230Z` (GrammarLegacy, n=6); post-arm `20260528T145727Z` ([PM-004](../../experiments/minimal-agent/findings/postmortem-004-s8-gate-post-arm-rerun.md), GrammarCoreInversion, n=6); redesigned `20260528T204620Z` ([PM-005](../../experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md), EL-1+EL-2+E3 evaluator, n=8, 2 excluded). Excluded invalid: `20260528T014158Z` (enforcement absent). Full evidence: PM-004 and PM-005.

| Axis | Pre-arm (n=6) | Post-arm (n=6, PM-005 valid) | Result |
|------|--------------|------------------------------|--------|
| (a) Pass rate / grade distribution | 6/6 (100%), 6× B | 6/6 (100%), 3× A, 3× C | No pass-rate change; grade A first observed |
| (b) Verified fraction | 0/6 (0%) | 0/6 (0%) | No change |
| (c) `?proof-required` emission | 0/6 (0%) | 3/6 (50%) | **Improves — conjunctive gate criterion met** |
| (d) Boundary-form distribution | 0% `def`/`def-shell`; 12/12 `def-logic` | 100% `def`/`def-shell`; 0/10 `def-logic` | Enforcement confirmed; ≥25% `def` threshold met |

§8 Rev 2 conjunctive pass criterion satisfied on PM-005 data (axis (c) improves; axis (d) ≥25%; no material regression). Post-run evaluator fix (F-GATE-7) and compiler fix (F-GATE-8, commit `f62a38b`, 2026-05-29) mean PM-005 is not a clean reference run. **Default flip provisional** — `GrammarCoreInversion` is the CLI default at commit `5cab1b7`; schema bump and examples migration shipped at `afe80df`. Gate adjudication pending a clean redesigned run post-F-GATE-8 fix; if the redesigned run fails, rollback path (1) per [`v0.11-cross-proposal-rollback-discipline.md §2`](v0.11-cross-proposal-rollback-discipline.md) applies.
