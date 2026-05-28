# LT-PPR — Predicate-Carrying `?proof-required`

> **Version:** Rev 3 — truncation mitigation (Risk #1) dropped; sidecar-safety-valve framing removed; `predicate_text` confirmed unbounded (2026-05-28)
> **Date:** 2026-05-23 (Rev 1); 2026-05-25 (Rev 2); 2026-05-28 (Rev 3)
> **Implements:** `docs/compiler-team-roadmap.md` v0.11 milestone, Implementation Item 3 (LT-PPR)
> **Prerequisites:** LT-INV grammar inversion (sequenced after — predicate-carrying form is `def-shell`-only per memo §1.4). Cross-proposal shipping under LT-INV gate outcomes specified at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) §2 and §6.3 below.
> **Origin:** 2026-05-23 external critique processed via professor channel ([`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §3); language-team triage at [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §6 routing; supersedes [`proof-required-predicate-carrier.md`](proof-required-predicate-carrier.md) deferred-exploration seed material (status flipped to "Superseded by LT-PPR" 2026-05-23)
> **Reviewed:** Professor review at [`proof-required-predicate-carrier-review.md`](proof-required-predicate-carrier-review.md) (Rev 1, 2026-05-25); recommendation `approve with revisions`. Six gaps and two author-question answers folded into this Rev 2. Standalone review awaits doc-lead M2 fold-and-archive.
> **Status:** Settled (Rev 2) — professor review folded; pending compiler-engineer hand-off, contingent on LT-INV gate per §6.3

---

## 1. Motivation

`?proof-required` at [`LLMLL.md §6:780-789`](../../LLMLL.md) is currently a **leaf hole**. The constructor [`HoleKind.HProofRequired Text`](../../compiler/src/LLMLL/Syntax.hs) at `compiler/src/LLMLL/Syntax.hs:243` carries only a reason tag (one of `"manual"`, `"non-linear-contract"`, `"complex-decreases"`), not an expression payload. The marker stands in for an unverifiable predicate, but the intended predicate is documented adjacent to the marker in prose, function docstrings, or trust-report annotations — not in the AST.

This leaf-form design has held since v0.2. Two pressures now converge to motivate its expansion:

**Empirical agent-demand signal.** Per [`findings/postmortem-smoketest-001-002.md`](../../findings/postmortem-smoketest-001-002.md) finding #1, **5 of 12 attempts across two model providers** independently surfaced the same ambiguity when reading `§13.8`: *"the spec shows the S-expression form `(?proof-required (or …))` with an embedded predicate, but `llmll-ast.schema.json` defines only `kind` and `reason` — no field exists to carry the predicate."* The recurrence is a strong empirical signal that the predicate-carrying form is the intuitive default agents reach for, and that the leaf-form-only design creates a surface/spec mismatch agents must resolve at authoring time.

**Downstream-consumer benefit recognized via the LT-INV grammar inversion.** [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §1.4 makes the `def`/`def-shell` polarity inversion explicit: `?proof-required` is forbidden inside the core `def` form (it is an `asserted`-tier escape hatch and admitting it would re-introduce the very semantic non-uniformity the inversion is designed to prevent). This concentrates `?proof-required` in `def-shell` bodies, where its information value increases proportionally: it is the explicit boundary between body-faithfully-verified content and asserted gaps, and the predicate it stands in for is exactly the content downstream consumers (Lean-discharge ingestion, obligation-report mining, runtime-assertion tooling) want machine-readable.

The previously-tracked deferral conditions at [`proof-required-predicate-carrier.md:62-67`](proof-required-predicate-carrier.md) required:

> **(1)** Feature freeze is lifted, **and**
> **(2)** Either (a) ≥2 experiment batches post-DL-B show recurrent agent demand not explained by §13.8 confusion, **or** (b) a downstream consumer would meaningfully benefit from the predicate being machine-readable.

Condition (1) is met by LT-INV's v0.11 freeze-exception (`docs/compiler-team-roadmap.md` Feature Freeze Policy, lifted 2026-05-23). Condition (2)(b) is met by the LT-INV core/shell distinction itself — the predicate-carrying form is the natural escape hatch from core into shell with retained semantic content, exactly the downstream-consumer benefit the deferral doc anticipated. Condition (2)(a) is not formally satisfied (no post-DL-B experiment batch has been run), but (2)(b) alone is sufficient under the doc's disjunctive criterion.

LT-PPR ships the predicate-carrying form as a v0.11 spec move: surface, AST, parsers, typechecker, trust report, codegen runtime-assertion fallback. The verifier is **unchanged** — the predicate is not lifted to liquid-fixpoint; the clause continues to route to `asserted` per [`LLMLL.md §5.3.5`](../../LLMLL.md). The proposal is informational, not soundness-relevant; it makes an *existing* escape hatch carry more information *without* widening the verification surface.

**Positioning in the precedent literature (Rev 2, per the professor review's Gap #6).** LT-PPR lands as the **novel combination** of three adjacent traditions, not as a derivative of any one of them:

- **Liquid Haskell `{-@ assume @-}`** (Vazou et al. POPL 2014 §3) carries the predicate at the signature level *and* admits it as a verifier hypothesis (treating the assumed predicate as a given). LT-PPR carries the predicate but does *not* admit it as a verifier hypothesis — the clause stays `asserted` per §4.3.
- **Coq `Admitted` / Lean `sorry`** (Coq Reference Manual §1.5; Leanprover/Lean4 `core.lean`) carry only a type, not a predicate. The proof obligation is recorded in `Print Assumptions` / `#print axioms`. LT-PPR carries the predicate explicitly, surfacing what the gap stands in for.
- **Runtime-assertion emission** — no production refinement-typed system ships this. Liquid Haskell `{-@ assume @-}` emits no runtime check; Coq / Lean axioms are erased at compile time; Why3 `assume P` (Filliâtre & Paskevich ESOP 2013 §4.3) carries the predicate but emits no runtime check. LT-PPR emits a runtime assertion over the carried predicate at codegen per §4.2, providing *additional asserted-tier confidence* without promoting the trust tier.

The combination — predicate carried (LH), no verifier-hypothesis admission (Coq/Lean), runtime-assertion emitted (no precedent) — is novel. The novelty is not a defect; it reflects LLMLL's specific Path A stance (per [`docs/design/verification-debate.md`](verification-debate.md)) and the agent-authoring context's preference for explicit gap-signalling with operational reinforcement over either fully-trusted assumes (LH) or fully-erased axioms (Coq/Lean). Downstream consumers reading this proposal default to neither LH's framing nor Coq's framing; the trust-report `predicate_form` and `runtime_check_emitted` fields per §5 carry the LLMLL-specific semantics.

---

## 2. Scope

**In scope:**
- Extending `HoleKind.HProofRequired` to carry an optional `Expr` payload
- Surface support in both S-expression and JSON-AST parsers for the optional-predicate form
- Typechecker treatment of the predicate as `bool` in the surrounding `pre`/`post` context
- Trust-report enrichment with `predicate_form` and `predicate_text` fields on the `EvidenceRecord`
- Codegen runtime-assertion fallback over the predicate (the "weak verification" path the deferred-exploration doc anticipated)
- Spec text update at `LLMLL.md §6` replacing the "gap signal, not a predicate carrier" callout with the v0.11 dual-form documentation
- Core-grammar interaction per LT-INV §1.4 — predicate-carrying form is `def-shell`-only, forbidden in `def`

**Out of scope (deferred):**
- Verifier-side discharge of QF-LIA-tractable predicates in `?proof-required` clauses. The marker's purpose is explicit gap-signalling regardless of decidability; auto-discharge would erode the deliberate "this is a gap" semantics. If a predicate is QF-LIA-tractable, the agent should write a regular `(post pred)` clause instead.
- A new trust tier `asserted-with-runtime-check`. The diamond lattice at [`LLMLL.md §4.4.1:325-344`](../../LLMLL.md) stays unchanged; the runtime-assertion fallback is a *runtime artifact* (per the erasure framing), not a trust-tier promotion. See §6 below for the detailed adjudication.
- Lean-discharge ingestion of carried predicates. Lean integration is parking-lotted at [`compiler-team-roadmap.md`](../compiler-team-roadmap.md) LEAN-GA; LT-PPR makes the predicate machine-readable so a future Lean-integration ingest path can consume it directly, but ships no Lean wiring itself.

**Out of scope under v0.11 surface — sequencing:**
- LT-PPR ships **after** LT-INV (`def`/`def-shell` grammar split). The core-grammar-interaction clause at §6 below depends on LT-INV's whitelist production being in place.

---

## 3. Surface

### 3.1 S-expression

Both forms are accepted; the predicate slot is optional:

```lisp
;; v0.10 — leaf form (still accepted in v0.11; unchanged behavior)
(post (?proof-required))
(post (?proof-required :reason "non-linear-contract"))

;; v0.11 — predicate-carrying form (new)
(post (?proof-required (or (is-ok result) (= result (err "invalid")))))
(post (?proof-required :reason "manual"
                       (>= (total-balance ledger') (total-balance ledger))))
```

The predicate is a `bool`-typed expression in the contract context; `result` is in scope per [`LLMLL.md §13.10`](../../LLMLL.md) when the clause is in post-position. The optional `:reason` keyword preserves the v0.10 reason-tag mechanism; reason and predicate may coexist or appear independently.

### 3.2 JSON-AST

The `hole-proof-required` node shape gains an optional `predicate: Expr` field:

```json
{ "kind": "hole-proof-required" }

{ "kind": "hole-proof-required",
  "reason": "non-linear-contract" }

{ "kind": "hole-proof-required",
  "predicate": { "kind": "op",
                 "op": ">=",
                 "args": [ ... ] } }

{ "kind": "hole-proof-required",
  "reason": "manual",
  "predicate": { ... } }
```

`additionalProperties: false` is relaxed only to admit the `predicate` field. The existing `reason` tag stays optional.

### 3.3 Grammar restriction

Per LT-INV §1.4, `?proof-required` (predicate-carrying or leaf) is **forbidden inside `def`** (the strict-core form). It is admitted only in `def-shell`. The grammar production at LT-INV (b) whitelist excludes `?proof-required` from the core-admitted hole list; the parser rejects with a *core-membership-violation* diagnostic if encountered inside `def`.

---

## 4. Semantics

The predicate is parsed and typechecked but **not** sent to liquid-fixpoint. The verifier treats the clause as `asserted` per current v0.10 behavior; the predicate is *informational* — it tells the trust report, downstream tooling (Leanstral integration, obligation-report mining, runtime-assertion tooling), and the runtime-assertion fallback what the unproven property is.

### 4.1 Typing rule

```
Γ ⊢ predicate : bool        result : T ∈ Γ   (when in post-position)
─────────────────────────────────────────────────────────────────
Γ ⊢ (?proof-required predicate) : asserted-contract-clause
```

The clause type is `asserted-contract-clause` — distinct from the regular contract-clause type because the trust-tier degradation is structurally encoded. This mirrors the v0.10 leaf form's behavior; only the predicate slot is new.

When the clause appears in `pre`-position, `result` is not in scope per [`LLMLL.md §13.10`](../../LLMLL.md); the predicate must not reference it. When in `post`-position, `result` is bound to the function's declared return type. This matches the existing pre/post binding rules and requires no new binding semantics.

### 4.2 Evaluation behavior

The verifier does not attempt discharge. The clause routes to `asserted` per [`LLMLL.md §5.3.5`](../../LLMLL.md). The carried predicate is:

- **Recorded in the trust report** as a structured field on the per-clause `EvidenceRecord` (see §5 below)
- **Emitted at codegen as a runtime assertion** (`Control.Exception.assert` or equivalent) so the unverified property is checked at execution time even though static verification declined
- **Available to downstream tooling** for future ingestion paths (Lean discharge, obligation-report mining, agent-loop repair-suggestion generation)

**Runtime-vs-symbolic divergence class enumeration (Rev 2, per the professor review's Gap #1).** The runtime-assertion evaluation uses the Haskell runtime semantics of the underlying builtins (per [`CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs) lowering); the verifier's symbolic interpretation uses the axiomatized signatures of the same builtins (per [`Contracts.hs`](../../compiler/src/LLMLL/Contracts.hs) constraint emission). The two diverge in three distinct classes; downstream consumers reading `runtime_check_emitted: true` must not over-interpret the signal:

1. **Partial-function class.** Predicates using partial builtins (`list-head` on a list whose emptiness is not in scope, `int-divide` on a divisor not constrained ≠ 0, etc.) runtime-fail on the partial-input case; the verifier's symbolic interpretation treats the partial input as a precondition violation rather than a postcondition refutation. A runtime-failed assertion on an empty-list `list-head` is *not* a refutation of the carried predicate — it is a precondition violation upstream of the predicate's intended meaning.
2. **Numeric-semantics class (post-INT-1 / pre-INT-2).** Z3 reasons over mathematical integers; Haskell `Int` is `Int64`. The verifier-symbolic predicate `(> result 0)` is sound over mathematical integers; the runtime assertion is checked over `Int64`. Overflow-tainted predicates may fail one but not the other. The v0.10.8 `overflow_tainted` field per [`Syntax.hs:326-331`](../../compiler/src/LLMLL/Syntax.hs#L326-L331) marks tainted verified evidence; LT-PPR's runtime-assertion fallback over the *same* arithmetic must distinguish "predicate is genuinely false at runtime" from "overflow triggered the failure." Under v0.11 INT-2 (`int → Integer` codegen switch), this class is dormant on `int` and re-arms on the post-freeze `machine-int` primitive per INT-3.
3. **Lazy-evaluation class.** The runtime assertion forces the predicate's evaluation; lazy contexts may produce divergent behavior — predicates over infinite structures may succeed under symbolic interpretation (where laziness is invisible to the verifier) but loop forever under lazy evaluation. This class is rare in practice but soundness-relevant.

The three classes are distinct; the assertion-failure handler should distinguish them via a structured-diagnostic emission (one of `partial-input`, `overflow-tainted`, `non-terminating`, or `predicate-refuted`). The default codegen lowering at [`CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs) emits the assertion without diagnostic classification in v0.11; the structured-diagnostic enrichment is a v0.12+ direction (engineer ticket, not a v0.11 LT proposal).

**Verifier-side informational diagnostic for QF-LIA-tractable predicates (Rev 2, per the professor review's Gap #2).** When the verifier parses `(?proof-required (> result 0))` and the predicate is QF-LIA-tractable, the verifier emits an informational diagnostic: *"predicate is QF-LIA-tractable; consider downgrading to `(post (> result 0))` for solver-backed evidence."* This diagnostic is non-disruptive (the agent retains the choice to keep the `?proof-required` marker) and is consistent with the honor-the-gap design philosophy: the system *honors* the agent's explicit gap declaration *and* surfaces the asymmetry. The diagnostic emits at the trust-report or `--obligation-report` channel; the verifier does not attempt discharge or change the trust-tier classification. The honor-the-gap-vs-opportunistic-discharge trade-off (Q-PROF-2) is settled in favor of honor-the-gap per §4.2 below; the informational diagnostic is the minimal-disruption improvement that surfaces the alternative without changing the semantics.

### 4.3 Interaction with the trust closure

Functions whose `pre` or `post` contains a `?proof-required` clause continue to be capped at `asserted` for trust-closure purposes per [`LLMLL.md §4.4.1`](../../LLMLL.md). The predicate's presence does not promote the clause; it enriches what `asserted` means at this site (from "gap with reason tag" to "gap with explicit predicate plus reason tag plus runtime assertion").

---

## 5. Trust-report enrichment

The `EvidenceRecord` for a `?proof-required`-bearing clause gains two fields:

```json
{
  "clause": "post",
  "tier": "asserted",
  "predicate_form": "predicate-carrying",
  "predicate_text": "(or (is-ok result) (= result (err \"invalid\")))",
  "runtime_check_emitted": true
}

{
  "clause": "post",
  "tier": "asserted",
  "predicate_form": "leaf",
  "runtime_check_emitted": false
}
```

`tier` is `asserted` in both cases (the diamond lattice is unaltered). The *enrichment* is the predicate field. Downstream consumers reading `tier: "asserted"` are unaffected; consumers reading the new `predicate_form` field gain the distinction between leaf and predicate-carrying forms and can route accordingly.

**`runtime_check_emitted: bool` flag** records whether codegen produced the runtime assertion. Predicate-carrying forms default to `true`; leaf forms default to `false`. A future codegen flag can opt out of runtime-assertion emission for performance-critical paths, in which case `runtime_check_emitted: false` and the trust report flags the asymmetry.

**`predicate_text` note (Rev 3, replaces Rev 2 Gap #4 fragmentation note).** The trust report's `predicate_text` carries the full JSON-encoded predicate expression (`exprToJson` of the carried `Expr` payload), unbounded. The `.verified.json` sidecar stores the same `EvidenceRecord` representation including `erPredicateText`; both surfaces carry equivalent data and there is no divergence between them. This is documented in [`docs/llmll-trust-report.schema.json`](../llmll-trust-report.schema.json) (per-field `description` blocks) and in `LLMLL.md §4.4` (the evidence-model section).

---

## 6. Open clause adjudications

The deferred-exploration doc flagged two open clauses; both are settled here.

### 6.1 Trust-level effect — **adopt option 2 ("trust label unchanged")**

The trust label stays `asserted`; no new `asserted-with-runtime-check` tier is introduced. The diamond lattice at [`LLMLL.md §4.4.1`](../../LLMLL.md) is unaltered.

**Rationale.** The diamond lattice is load-bearing for downstream tooling (the `tier_profile` six-Int aggregate at [`LLMLL.md:412`](../../LLMLL.md); the `DisplayLevel` enumeration consumers in `compiler/src/LLMLL/TrustReport.hs`). Adding a fifth tier would force a `trust_report_version` bump and downstream-consumer migration for a *runtime-assertion enhancement* that does not change the epistemic status of the clause. The runtime assertion is a *runtime artifact*, not a trust-tier promotion. The predicate's presence shows up as a *field* on the `EvidenceRecord` (`predicate_form`, `predicate_text`, `runtime_check_emitted`), not as a *tier* shift.

Distinguishing the two cases in the trust report is the `predicate_form` field's job, not the tier system's. Consumers wanting to count "asserted with runtime check" as a stronger signal than "asserted without runtime check" can derive that locally from the field; the diamond lattice continues to express the *epistemic* status, not the *operational* enhancement.

### 6.2 Core-grammar interaction — **adopt LT-INV §1.4 verbatim**

`(?proof-required predicate)` is **forbidden inside `def`** per LT-INV (b) whitelist production. Admitted inside `def-shell`. The agent that needs the predicate-carrying form must use `def-shell`; admitting it inside `def` would re-introduce the very `asserted`-tier escape hatch that LT-INV's polarity inversion is designed to prevent.

This is unconditional. Even with the predicate present, the clause routes to `asserted`; admitting it in `def` would let a `def` function carry an `asserted` clause, breaking the inversion's syntactic guarantee that core-form functions are body-faithfully verifiable.

### 6.3 Contingent shipping under LT-INV gate outcomes (Rev 2, per the professor review's Gap #5)

§6.2's `def`-forbiddance adjudication is **contingent on LT-INV's grammar being canonical**. The professor review surfaced that under the LT-INV §8 empirical-gate failure paths, LT-PPR's enforcement degrades. The cross-proposal C-2 settlement at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) §2 specifies the three outcomes; LT-PPR ships per the outcome's contingent rule:

- **Outcome 0 — LT-INV gate passes.** §6.2 applies as written. Predicate-carrying form admitted in `def-shell`; rejected in `def` per the LT-INV §3.2 whitelist. Trust label stays `asserted` per §6.1. Runtime-assertion fallback emitted per §4.2. JSON-AST `schemaVersion 0.5.0 → 0.6.0` bundled with LT-INV.

- **Outcome 1 — LT-INV rollback to opt-in-only.** Predicate-carrying form admitted in `def-shell` *under the `--grammar=core-inversion` opt-in flag*; rejected in `def` per §6.2 (under flag). **Outside the opt-in flag, the predicate-carrying form is *also rejected* in `def-logic` (default).** This is the load-bearing Rev 2 rule: consumers do not get the feature as a default — they must explicitly opt into LT-INV's grammar to get any predicate-carrying form. The rationale is the §6.2 asserted-tier-escape-hatch protection: admitting the predicate-carrying form in `def-logic` (default) would re-introduce the very escape hatch the inversion is designed to prevent, defeating the v0.11 spec move. The proposal accepts that Outcome 1 means *no predicate-carrying form by default* rather than admitting the form unprotected. JSON-AST `schemaVersion 0.5.0 → 0.6.0` preserved (admits the new statement kinds for flag users).

- **Outcome 2 — LT-INV retracted.** §6.2 is **contingently undone**. The predicate-carrying form is admissible in `def-logic` (the v0.10 default form). The asserted-tier escape hatch re-enters the default grammar; LT-PPR ships *without* the §6.2 `def`-forbiddance protection. This is a contingent acceptance — the proposal's §6.2 rationale (no polarity inversion to protect under Outcome 2) makes the forbiddance moot. JSON-AST `schemaVersion 0.5.0 → 0.5.1` (additive predicate field on `hole-proof-required`); coordinated with LT-CDP under Outcome 2 per the C-2 settlement.

The contingent shipping rule means **LT-PPR's compiler-engineer parallel work is gate-conditional only at the integration step**, not at the implementation step. The `HoleKind.HProofRequired` extension, parser changes, typechecker treatment of the predicate as `bool`, trust-report fields, and codegen runtime-assertion fallback are implemented unconditionally. Only the grammar-admission discipline (`def`-forbiddance) is gate-conditional, and it is implemented as a parser predicate gated by the surrounding-form context. Under Outcome 2, the predicate degrades to `true` and the predicate-carrying form is admitted in `def-logic`.

---

## 7. Schema delta

JSON-AST node-shape change for `hole-proof-required`:

```json
"HoleProofRequired": {
  "type": "object",
  "required": ["kind"],
  "properties": {
    "kind": { "const": "hole-proof-required" },
    "reason": { "type": "string" },
    "predicate": { "$ref": "#/$defs/Expr" }
  }
}
```

`additionalProperties: false` is relaxed to admit `predicate` (and any future enrichment fields). The `reason` and `predicate` fields are both optional; either or both may appear.

**`schemaVersion` bump bundled with LT-INV** — `0.5.0 → 0.6.0`. No separate bump for LT-PPR; the LT-INV grammar inversion is already bumping major.minor and the additive predicate field rides in the same bump. Both LT-PPR's new field and LT-INV's whitelist grammar production are additive on the v0.5.0 baseline (LT-PPR adds a field; LT-INV adds `kind: "def"` and `kind: "def-shell"` to the statement-kind enumeration).

---

## 8. Edge cases

1. **A `?proof-required` clause inside `def`.** Input shape: `(def f [n: int] (post (?proof-required (> result 0))) ...)`. **Expected behavior:** parse-error per LT-INV (b) whitelist; the agent must migrate `f` to `def-shell` or eliminate the proof-required clause. **Channel:** type (the core grammar admits this construct *structurally* in v0.10 but the v0.11 LT-INV-tightened whitelist production rejects it at parse time). **Citation:** [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §1.4; LT-INV grammar production at the LT-INV-proposal §3.

2. **A predicate referencing `result` in pre-position.** Input shape: `(pre (?proof-required (> result 0)))`. **Expected behavior:** typecheck error — `result` is not bound in `pre`-position per [`LLMLL.md §13.10`](../../LLMLL.md). The predicate-carrying form inherits the same binding rules as regular pre/post clauses; the typecheck error is identical to the one a non-`?proof-required` `(pre (> result 0))` would produce. **Channel:** type. **Citation:** [`LLMLL.md §13.10`](../../LLMLL.md).

3. **A QF-LIA-tractable predicate.** Input shape: `(post (?proof-required (> result 0)))` where `(> result 0)` is QF-LIA. **Expected behavior:** the verifier *does not* attempt discharge — the marker is the agent's explicit declaration that this is a gap, regardless of the predicate's decidability. The clause routes to `asserted` and the trust report records `predicate_form: "predicate-carrying"`. The alternative (auto-discharge QF-LIA-tractable predicates and downgrade the marker) is rejected explicitly: the marker's purpose is explicit gap-signalling, not decidability-routing. If the agent wants the verifier to attempt discharge, they should write `(post (> result 0))` directly. **Channel:** trust (the marker's semantics is intentional non-discharge). **Citation:** §4.2 above; the explicit-marker-over-decidability-routing reading.

4. **A predicate using `?proof-required` recursively.** Input shape: `(post (?proof-required (?proof-required (> result 0))))`. **Expected behavior:** parse-error — `?proof-required` cannot appear inside its own predicate. The predicate slot's grammar is the regular `Expr` non-terminal restricted to non-hole expressions. **Channel:** type (parse-time rejection). **Citation:** §3.1 grammar above.

5. **A `?proof-required` clause with a predicate that fails typecheck.** Input shape: `(post (?proof-required (+ "x" 1)))`. **Expected behavior:** typecheck error per the predicate's expected type `bool` plus TC-EOP-1's arity/type-check fix (which makes `(+ "x" 1)` reject as type-incorrect rather than silently passing). The predicate-carrying form inherits the standard typecheck regime. **Channel:** type. **Citation:** §4.1 typing rule; TC-EOP-1 closes the EOp escape per [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §4.

6. **A predicate referencing a function whose body is not in scope.** Input shape: `(post (?proof-required (well-formed? state)))` where `well-formed?` is not imported. **Expected behavior:** typecheck error per standard `EVar`/`EApp` name-resolution. No special handling for `?proof-required` predicates; they are typechecked under the same `tcEnv` as any other contract-clause expression. **Channel:** type. **Citation:** standard typechecker name-resolution at [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs).

---

## 9. Verification mapping

- **Channel:** trust (the predicate is informational; the verifier does not consume it). Type-channel side-effect only: the predicate itself must typecheck as `bool`.
- **Fragment:** unchanged — the predicate is *not* lifted to liquid-fixpoint; the verifier sees the marker as a gap-signal and the clause routes to `asserted` per [`LLMLL.md §5.3.5`](../../LLMLL.md). The predicate is a *trust-report annotation* and a *runtime-assertion artifact*, not a verification obligation.
- **Cite:** [`LLMLL.md §6:780`](../../LLMLL.md) (gap-signal callout — text updated per §10 below); [`LLMLL.md §5.3.5`](../../LLMLL.md) (verification matrix `?proof-required` row, unchanged).

No new SMT obligations are emitted. No new fragment expansion. No new Lean ingest path is established (Lean integration is parking-lotted).

---

## 10. Affected surface

- [`LLMLL.md`](../../LLMLL.md) — §6 (replace the v0.10 "gap signal, not a predicate carrier" callout with the v0.11 dual-form documentation: leaf form unchanged behavior; predicate-carrying form gains the predicate slot and runtime-assertion fallback; both routed to `asserted`), §13.8 (canonical example update if needed — LT-B.1 corrective evidently already applied; verify no predicate-carrying example survives in `LLMLL.md`), §12 grammar (hole form gains optional predicate slot in the EBNF)
- [`compiler/src/LLMLL/Syntax.hs:243`](../../compiler/src/LLMLL/Syntax.hs) — `HProofRequired Text` extends to `HProofRequired Text (Maybe Expr)`; round-trip through `AstEmit.hs` for both forms
- [`compiler/src/LLMLL/Parser.hs`](../../compiler/src/LLMLL/Parser.hs), [`compiler/src/LLMLL/ParserJSON.hs`](../../compiler/src/LLMLL/ParserJSON.hs) — optional-predicate parsing in both frontends; both must produce identical AST shape from equivalent input
- [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) — typecheck the predicate as `bool` in the surrounding pre/post context with `result` bound where applicable
- [`compiler/src/LLMLL/TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs) — emit `predicate_form`, `predicate_text` (unbounded), and `runtime_check_emitted` fields in the `EvidenceRecord`
- [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs) — emit runtime-assertion fallback over the predicate (the runtime check the deferred-exploration doc anticipated); opt-out flag for performance-critical paths
- [`compiler/src/LLMLL/HoleAnalysis.hs`](../../compiler/src/LLMLL/HoleAnalysis.hs) — predicate-carrying form is one of the hole-forms forbidden in `def` per LT-INV (b) whitelist
- [`docs/llmll-ast.schema.json`](../llmll-ast.schema.json) — extends `hole-proof-required` shape with optional `predicate` field; bundled with LT-INV `schemaVersion 0.5.0 → 0.6.0` bump
- [`docs/llmll-trust-report.schema.json`](../llmll-trust-report.schema.json) — `EvidenceRecord` shape gains `predicate_form`, `predicate_text`, `runtime_check_emitted` fields; `trust_report_version` bump only if these are not purely additive on the existing v1.1.0 shape (assessment: additive, no bump required for LT-PPR alone)
- [`docs/design/proof-required-predicate-carrier.md`](proof-required-predicate-carrier.md) — supersession marker already landed in Pass 4 of the 2026-05-23 catch-up branch
- [`docs/design/critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) — triage row §6 "deferred, no move" is superseded by this proposal

---

## 11. Risks and open questions

1. **Predicate-text in the trust report is unbounded.** Severity: low (accepted). Classification: spec-drift (mitigation dropped — Rev 3). Cite: `TrustReport.hs:321` emits the full `exprToJson pred` without truncation; `Syntax.hs:386` `erPredicateText :: Maybe Text`. **Disposition (Rev 3):** Truncation mitigation dropped. The proposed safety valve — recovery from the `.verified.json` sidecar — does not exist: the sidecar stores `Map Name ContractStatus` with the same `erPredicateText :: Maybe Text`, not a richer predicate-AST representation. Truncation without a recovery path would be information-destroying. The predicate vocabulary in v0.11 scope (simple boolean expressions over builtins per §4.1) is compact in practice; the risk is accepted. A non-truncating size advisory (high-watermark warning, no information loss) is a v0.12+ direction if empirical evidence from the experiment harness warrants it.

2. **Runtime-assertion fallback over the predicate may diverge from the verifier's symbolic interpretation.** Severity: medium. Classification: soundness. Cite: erasure-theorem framing in [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §3.1 — runtime checks are *separate* from verifier checks. Bite: a predicate using a builtin whose runtime behavior differs from its symbolic interpretation (e.g., a partial function) may runtime-fail in cases the spec did not consider. **Mitigation:** runtime-assertion fallback is opt-in via a codegen flag (default: emit assertion). The trust report records emit/skip explicitly via `runtime_check_emitted`. Functions in `def-shell` with predicate-carrying `?proof-required` get the assertion automatically; pathological cases can opt out per-function.

3. **Agents may regress to the leaf form for terseness.** Severity: low. Classification: verification-ergonomics. Cite: empirical findings on agent verbosity bias. Bite: the predicate-carrying form's intent is to capture intent; if agents default to leaf form, the downstream-consumer value is unrealized. **Mitigation:** the `--obligation-report` repair-suggestion machinery (`compiler/src/LLMLL/ObligationMining.hs`) can prompt for the predicate-carrying form when an `asserted` clause has an obvious predicate inferable from the surrounding context. Promote this in a future iteration.

4. **Sequencing dependency on LT-INV.** Severity: low. Classification: scope. Cite: §6.2 above; the core-grammar interaction depends on LT-INV's whitelist production. Bite: if LT-INV ships first and LT-PPR slips, agents authoring predicate-carrying forms inside `def-shell` get them; agents who would naturally place them in `def` (the v0.10 default) get parse errors with no immediate workaround until LT-PPR lands. **Mitigation:** ship LT-INV and LT-PPR together in v0.11; the LT-INV transition guide should call out the LT-PPR predicate-carrying form as the recommended path for unprovable clauses in `def-shell`.

5. **Schema-bump bundling with LT-INV creates cross-proposal coupling.** Severity: low. Classification: spec-drift. Cite: §7 above. Bite: if LT-INV slips and LT-PPR is ready, LT-PPR must either bump `schemaVersion 0.5.0 → 0.5.1` independently (minor consumer-visible change) or wait for LT-INV. **Mitigation:** the bundling is intentional and recommended; if independent ship is needed, `0.5.0 → 0.5.1` is the additive-only path. The C-2 settlement at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) §3 coordinates Outcome-2 bumps to a single `0.5.1` rather than two independent bumps.

### 11.1 Future directions — witness extraction from runtime-failed assertions (Rev 2, per the professor review's Gap #3 / Q-PROF-1)

The runtime-assertion fallback per §4.2 produces a counter-example on failure: the failing input plus the predicate's evaluation trace are *available at the assertion site* but not currently captured into structured evidence. The closest external precedent is **QuickCheck shrinking** (Claessen-Hughes ICFP 2000 §4): a runtime-failed property is minimized to a small counter-example, which carries diagnostic value far beyond the single failing input. No production refinement-typed system (LH, F*, Why3, Dafny) has shipped this for `?proof-required`-style markers; the design space is well-formed but unexplored.

**v0.12+ direction.** When codegen emits the runtime assertion (§4.2), the emit site can additionally emit a *capture handler* that, on assertion failure, writes the failing input plus the predicate-evaluation trace to a structured diagnostic file (e.g., a `.assertion-failures.json` sidecar). The trust report on subsequent verify runs can read this sidecar and emit:

```json
{
  "clause": "post",
  "tier": "asserted",
  "predicate_form": "predicate-carrying",
  "predicate_text": "...",
  "runtime_check_emitted": true,
  "observed_failures": [
    {"input": {...}, "predicate_evaluation": false, "execution_timestamp": "..."}
  ]
}
```

The diamond lattice still classifies the clause as `asserted`; the trust report carries actionable counter-example data alongside. This is an additive extension to the trust-report schema; no new tier (consistent with §6.1). Witness extraction is deliberately deferred to v0.12+ — the v0.11 runtime-assertion fallback alone is a discrete and useful enhancement, and the witness-capture machinery requires additional design (per-process sidecar coordination, replay semantics, predicate-evaluation-trace serialization) that exceeds the v0.11 scope.

The QuickCheck-shrinking precedent suggests the captured counter-example can also be *minimized* — a runtime-failed input is shrunk to a small representative — but minimization is non-trivial and is left for the v0.12+ design pass.

---

## 12. Open questions for the professor review

**Status (Rev 2):** both questions answered in the Rev 1 professor review at [`proof-required-predicate-carrier-review.md`](proof-required-predicate-carrier-review.md) §"Answers to author-surfaced questions"; the answers are folded into Rev 2 at §11.1 (Q-PROF-1: no production system extracts witnesses from runtime-failed assertions; QuickCheck shrinking is the closest precedent; witness-extraction deferred to v0.12+) and §4.2 (Q-PROF-2: gradual-typing literature favors opportunistic; LLMLL's honor-the-gap choice is principled but unusual under coercion-semantics framing; verifier-side informational diagnostic ships as the minimal-disruption improvement). The questions are retained below as the historical record of the Rev 1 → Rev 2 transition.

1. **The predicate-carrying form straddles two adjacent traditions: Liquid Haskell's `{-@ assume @-}` (which carries the assumed predicate inline) and Coq/Lean's `sorry`/`Axiom` (which carry only a type, not a predicate).** LT-PPR lands closer to Liquid Haskell — predicate present, runtime-assertion fallback emitted, trust label `asserted`. Is there a third tradition — perhaps Idris's `?hole` with elaborator-driven refinement, or Dafny's `assume` with witness extraction — that LT-PPR should be benchmarked against for completeness? Specifically: do any of those traditions have a treatment of *witness extraction* from a runtime-failed assertion that could be used to upgrade the predicate-carrying form into structured evidence (e.g., a counter-example AST node attached to the trust report)? — *Rev 2 answer: no production system extracts witnesses from runtime-failed assertions. Idris `?hole` is interactive-time, not runtime. Dafny `assume` is static, no witness extraction. QuickCheck shrinking is the closest external precedent — runtime-failed property minimized to a small counter-example. §11.1 documents the v0.12+ direction.*

2. **The QF-LIA-tractable-predicate edge case (§8 edge #3) explicitly chooses non-discharge over decidability-routing.** The argument is that the marker's purpose is explicit gap-signalling. Is there an established treatment in the gradual-typing or "verification-as-collaboration" literature of the trade-off between *honoring the agent's explicit gap declaration* and *opportunistic discharge when the obligation turns out to be tractable*? The chosen design favors the former (LLMLL's "agent declares intent, system honors it" stance); an alternative that auto-discharges and reports "the marker was unnecessary" might also be defensible. — *Rev 2 answer: gradual-typing literature favors opportunistic checking (Siek-Taha 2006; Siek-Vitousek-Cimini-Tobin-Hochstadt POPL 2015 gradual guarantee). LLMLL's honor-the-gap is principled under coercion-semantics framing (Henglein 1994; Siek-Garcia 2010). §4.2 ships the verifier-side informational diagnostic as the minimal-disruption surfacing of the asymmetry without changing semantics.*

---

## 13. Companion review

Professor review landed at [`proof-required-predicate-carrier-review.md`](proof-required-predicate-carrier-review.md) (Rev 1, 2026-05-25) as part of the batched four-proposal review turn (LT-INV, LT-CDP, LT-PPR, REF-META-1). Recommendation: `approve with revisions` on six gaps and two author-question answers, all folded into this Rev 2 inline at the marked "Rev 2" touchpoints (§1 positioning paragraph; §4.2 divergence-class enumeration + verifier-side informational diagnostic; §5 fragmentation note; §6.3 contingent shipping rule under LT-INV gate outcomes; §11.1 witness-extraction v0.12+ direction). The review carried the v0.11 cluster's cross-proposal observations C-1 through C-4; the C-2 settlement landed at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) (Rev 1, 2026-05-25) as a coordination artifact, referenced from §6.3 above.

The standalone `proof-required-predicate-carrier-review.md` was folded into the §"Appendix — Professor review log" below and archived to [`docs/archive/professor-reviews/proof-required-predicate-carrier-review.md`](../archive/professor-reviews/proof-required-predicate-carrier-review.md) under DOC-CONSOLIDATE §M2 (doc-lead Pass 10, 2026-05-25).

This proposal supersedes the deferred-exploration seed material at [`proof-required-predicate-carrier.md`](proof-required-predicate-carrier.md) (status flipped 2026-05-23 in Pass 4 of the catch-up branch).

---

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal has been folded into this appendix and the source file archived to `docs/archive/professor-reviews/proof-required-predicate-carrier-review.md`. One line per finding; all resolved in Rev 2 of this proposal.

**Source:** `docs/design/proof-required-predicate-carrier-review.md` at commit `5f31580` (review dated 2026-05-25; reviewer: Lead Consultant for Formal Language Design).

### Gaps (all resolved in Rev 2)

1. **Runtime-vs-symbolic divergence class enumeration absent.** Rev 1 Risk #2 named one example; three classes exist. Resolved: Rev 2 §4.2 enumerates partial-function, numeric-semantics, and lazy-evaluation classes with assertion-failure handler classification.
2. **QF-LIA-tractable non-discharge has opportunity-cost asymmetry.** Rev 1 §4.2 silent on non-disruptive surfacing of the asymmetry. Resolved: Rev 2 §4.2 ships the verifier-side informational diagnostic per Q-PROF-2 answer.
3. **Witness extraction from runtime-failed assertions not addressed.** Rev 1 §-deferred. Resolved: Rev 2 §11.1 adds the v0.12+ direction with QuickCheck-shrinking precedent and trust-report sidecar design sketch.
4. **Predicate-text truncation fragmentation risk.** Rev 1 §5 silent on consumer documentation. Resolved: Rev 2 §5 adds the trust-report-vs-sidecar fragmentation note with documentation pointers to `LLMLL.md §4.4` and the schema.
5. **Schema bundling with LT-INV unbounded.** Rev 1 §-Risk-#5 did not name contingent shipping under gate failure. Resolved: Rev 2 §6.3 specifies the three-outcome contingent shipping rule per the C-2 settlement.
6. **LH / Coq / Lean positioning not named.** Rev 1 §1 silent on which precedent tradition LT-PPR inherits. Resolved: Rev 2 §1 adds the positioning paragraph — LT-PPR is the novel combination of LH (predicate-carried), Coq/Lean (no hypothesis admission), runtime-assertion emission (no precedent).

### Open questions (both resolved in Rev 2)

- **Q-PROF-1.** Third tradition on witness extraction (Idris, Dafny). Resolved: Rev 2 §11.1 — no production system extracts witnesses from runtime-failed assertions; Idris `?hole` is interactive-time, Dafny `assume` is static. QuickCheck shrinking is closest precedent; deferred to v0.12+.
- **Q-PROF-2.** Honor-the-gap vs opportunistic-discharge — gradual-typing literature. Resolved: Rev 2 §4.2 — gradual-typing literature favors opportunistic (Siek-Taha 2006; Siek-Vitousek-Cimini-Tobin-Hochstadt POPL 2015). LLMLL's honor-the-gap is principled under coercion-semantics framing (Henglein 1994; Siek-Garcia 2010). Verifier-side informational diagnostic ships as the minimal-disruption surfacing.

### Cross-proposal observations (C-1 through C-4)

The review carried the v0.11 cluster's cross-proposal observations; full text in `refinement-metatheory-of-record-proposal.md` §"Appendix — Professor review log" / Cross-proposal observations subsection. C-2 (cross-proposal rollback discipline) settled at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md); §6.3 Rev 2 contingent shipping rule references the C-2 settlement.

### Overall assessment (recorded)

The review recommended `approve with revisions` on six gaps and two author-question answers. Rev 2 (settled 2026-05-25) carries each resolution inline at the cited §-references above. The standalone `proof-required-predicate-carrier-review.md` is archived; this appendix is the in-proposal pointer.
