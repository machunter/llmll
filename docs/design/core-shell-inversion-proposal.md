# LT-INV — Core/Shell Grammar Inversion

> **Version:** Rev 1 — initial settled draft
> **Date:** 2026-05-23
> **Implements:** `docs/compiler-team-roadmap.md` v0.11 milestone, Implementation Item 1 (LT-INV); the v0.11 spine
> **Prerequisites:** Feature freeze lifted for v0.11 (`docs/compiler-team-roadmap.md` Feature Freeze Policy, lifted 2026-05-23 with the inversion's freeze-exception soundness argument as the rationale)
> **Origin:** 2026-05-23 external critique processed via professor channel ([`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §1); language-team triage at [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §4; STRICT-CORE-1 from the triage is subsumed by this proposal (the admissibility rules become grammatical, not adversarial-spec-only)
> **Companion:** Professor direction memo [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) is the upstream architectural direction
> **Reviewed:** Pending professor review at `core-shell-inversion-review.md`
> **Status:** Settled (proposal) — awaiting professor review, then compiler-engineer hand-off behind `--grammar=core-inversion` opt-in flag per §8 empirical-gate sequencing

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

`def` is the canonical strict-core form. `def-logic` is **retired** as a source-level keyword in v0.11 (parsing produces a deprecation diagnostic that auto-rewrites to `def` for core-eligible bodies and `def-shell` otherwise per the mechanical classifier in §6). The permissive form is `def-shell`.

**Rationale.** The inversion's thesis is "the verified-core fragment IS the language." Option 1 (keep `def-logic` for the strict core, introduce `def-boundary` for the marked form) preserves the project's identity-keyword for its strongest reading but leaves a *legacy keyword for the legacy regime* in the surface; an agent reading the corpus continues to see `def-logic` as the canonical form, and the inversion's polarity claim is undermined at the lexical level. Option 2 makes the polarity unambiguous: the agent reading `def` is in the verified fragment by syntactic guarantee; the agent reading `def-shell` is in the permissive fragment.

Per [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §Background, backward compatibility is not a v0.11 governor; the keyword break is the right cost.

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

### 3.4 `EApp` callee restriction — **adopt the strict reading**

`EApp` inside a `def` body admits **only callees whose own bodies are body-faithfully verified** — transitive closure required. The relaxed reading (v0.9.0 assume-guarantee unchanged per [`LLMLL.md §5.3.4:710-740`](../../LLMLL.md)) would let an `asserted`-bodied callee silently leak into a `def`-form claim of `verified`-via-its-postcondition; the entire inversion is undermined the moment one non-body-faithful callee enters the core's call graph.

**Operational rule.** At the call site `(f x y)` inside a `def` body, the typechecker queries the callee's `EvidenceRecord`. If `erBodyFaithful = True` for `f`, the call is admitted; otherwise the typechecker emits a *core-membership-violation* diagnostic. This requires per-function `EvidenceRecord` lookup at typecheck time, which means the typechecker needs read access to the trust-report state — an architectural move that did not exist in v0.10 (typecheck was independent of verify). MOD-1's `meContracts` extension to `ModuleEnv` is the natural seam.

**Cost calibration.** The v0.9.0 assume-guarantee mechanism stays unchanged for `def-shell`; it is only narrowed inside `def`. Migration cost: any function in the existing corpus whose call graph reaches a `tested`-only or `asserted` callee migrates to `def-shell`. This is the right discipline — those functions were not body-faithfully verified before, and the v0.10 trust report was the only signal; the inversion makes the signal syntactic.

### 3.5 Hole forms — admit authoring intermediates; forbid `?proof-required`

`?hole`, `?name`, `?choose`, `?request-cap`, `?scaffold`, `?delegate`, `?delegate-async` are **admitted inside `def`** — they are authoring intermediates and the function does not verify-complete until filled. `?proof-required` is **forbidden inside `def`** — it is an asserted-tier escape hatch and admitting it would re-introduce the very semantic non-uniformity the inversion fixes.

This distinction does not exist in [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs) today (per `Syntax.hs:233-243`, all `HoleKind` constructors are treated uniformly at parse). The inversion forces it: the grammar production in §3.2 lists the admitted hole forms explicitly; `?proof-required` is omitted from the core grammar.

Per LT-PPR §6.2, the predicate-carrying form of `?proof-required` (proposed in v0.11 separately) is also forbidden inside `def` for the same reason. Both leaf and predicate-carrying forms of `?proof-required` live exclusively in `def-shell`.

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

The two callouts the language-team explicitly decided:

- **`EApp` to contracted callees** (§3.4 above): strict reading. Transitive body-faithful closure required.
- **`letrec`** (§3.3 above): route (i). Outside the core as shell form in v0.11.

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

**Pass criteria** (per direction memo §8.2): at least one of (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts must improve over the pre-inversion baseline — and no axis must regress materially.

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

1. **Is the transitive body-faithful closure (§3.4) the right closure shape, or should the inversion instead require the closure under a *weaker* invariant** (e.g., "all callees are at minimum `contract-checked`")? The strict-reading rationale is principled: a `def`-form function asserting `verified` cannot rest on `asserted` callees without leaking that asserted-ness. But the principle has a cost — most useful programs have *some* opaque builtin in the transitive closure (`string-length`, `random-int`, `wasi.*`). The relaxed closure ("contract-checked or better") would let builtins-with-contracts pass while still excluding `asserted` and `tested`-only callees. Is there an established treatment in the Liquid Haskell / F\* literature of this "closure-under-evidence-tier" question, and does the established treatment match §3.4 strict or a relaxed variant?

2. **The migration scope (§6) treats syntactic classification as the migration's primary signal.** The risk is misclassification per Risk #3; the mitigation is conservative-mode plus human-confirmation. **Is there a known pattern in the language-migration literature** (e.g., F# 4.x → 5.x, Python 2 → 3, ES5 → ES6) **for syntactic-only migration tooling that handles intent-disambiguation better than the conservative-flag-plus-human-confirm route LT-INV proposes?** Specifically: is there a tractable static analysis that infers "the author wanted shell semantics" from surrounding context, or is the human-confirm requirement inherent?

---

## 14. Companion review

The professor review half of this proposal/review pair will land at [`core-shell-inversion-review.md`](core-shell-inversion-review.md). This proposal is the v0.11 architectural spine and is sequenced ahead of LT-CDP and LT-PPR per §8 — both gate-independent of LT-INV per the rollback paths.
