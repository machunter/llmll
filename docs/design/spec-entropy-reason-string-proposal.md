# SPEC-ENTROPY-REASON — Mandatory-Justification String on `(spec-entropy :intentional …)`

> **Version:** Rev 0 — initial proposal.
> **Date:** 2026-07-03
> **Implements:** Follow-on to `experiments/adv-spec-weaken-0` **F-002** (settled 2026-07-03, `64b8700`). Sits on top of the LT-CDP research-track concept (`spec-entropy` annotation, `LLMLL.md §4.4.6`).
> **Origin:** Surfaced (and deliberately severed) by both the language-team and compiler-engineer adjudications of F-002. F-002 itself is closed as a design-scope limitation; this is a distinct, elective defense-in-depth proposal.
> **Prerequisites:** None new. Extends the existing `spec-entropy` clause; leans on the `weakness-ok` mandatory-reason precedent (`LLMLL.md §4.5`).
> **Status:** Proposed (Rev 0) — awaiting user adjudication.

---

## Restatement

Extend the existing `(spec-entropy :intentional)` annotation so that an `:intentional` declaration carries a free-text **justification string**, mirroring `weakness-ok`'s mandatory reason (`LLMLL.md §4.5:705`). This is **not** a fix for F-002's automated-detection floor — F-002 is settled-as-designed, because `:intentional` is a self-attestation channel with no independent oracle (CDP proposal §10 Risk #3 Rev 2; professor review Gap #5). It is **defense-in-depth**: it raises the marginal cost of spec-laundering from "add one keyword" to "write a plausible-looking justification," and it gives human code review and external CI a **per-site artifact** that does not exist today. It detects nothing automatically, and this proposal does not claim otherwise.

## Context located

1. `LLMLL.md §4.4.6:671-694` — the `(spec-entropy :strict | :intentional | :unknown)` annotation surface; the `:intentional` bullet (line 689, clarified in `64b8700`) already frames the channel as self-attestation with the 30% module-ratio abuse-rate check.
2. `LLMLL.md §4.5:696-717` — `weakness-ok` governance: mandatory reason string ("Both arguments are required — the parser rejects bare `weakness-ok`", line 705), the `W601/W602/W603` codes, and the JSON-AST form `{"kind":"weakness-ok","name":…,"reason":…}` (line 717). This is the in-surface template.
3. `compiler/src/LLMLL/Syntax.hs:309,326-346` — `Contract` record carries `contractSpecEntropy :: Maybe SpecEntropy`; `SpecEntropy` is a three-constructor sum (`Strict`/`Intentional`/`Unknown`) with `specEntropyLabel`/`parseSpecEntropy` wire round-trip. No reason field today.
4. `compiler/src/LLMLL/Parser.hs:558-565` — `pSpecEntropyClause` parses `(spec-entropy :<label>)` as a single parens form, one clause per contract (structurally forbids duplicates).
5. `compiler/src/LLMLL/ParserJSON.hs:224,238,298` + `docs/llmll-ast.schema.json:70,128` — the JSON-AST `spec_entropy` field is a **bare string enum** (`"strict"|"intentional"|"unknown"`) on both `DefCore` and `DefShell`. Decoded as a string; no object shape.
6. `compiler/src/LLMLL/CDP.hs:189-213` — `overAnnotationRatio` / `overAnnotationThreshold = 0.30` (the module ratio; unchanged by this proposal). `Syntax.hs:362-364` — `raiseLowDP` (per-function suppression; unchanged).
7. `experiments/adv-spec-weaken-0/fixtures/ax1-0{2,3,4}.llmll`, `compiler/test/fixtures/cdp/intentional.llmll:7`, `compiler/test/Spec.hs:8714` — the concrete `(spec-entropy :intentional)` source clauses (migration tail; see below).

**No spec/code drift found on the touched surface.** `LLMLL.md §4.4.6`, the schema, and `Syntax.hs`/`Parser.hs`/`ParserJSON.hs` agree that `spec_entropy` is a bare label today.

**Freeze check.** The v0.8.1a–v0.10 feature freeze (`docs/compiler-team-roadmap.md:26-31`) has expired (current line is v0.14.x). Regardless, this is an *extension of an existing construct*, not a new construct, FFI tier, or builtin — outside the freeze's ban even were it active.

## Design proposal

### Surface

```lisp
;; Slice 1 (recommended now): reason optional at parse time, governance-warned if absent on :intentional
(def cache-lookup [k: Key]
  (post (or (is-ok result) (is-error result)))
  (spec-entropy :intentional "cache admits any eviction order; looseness is by design")
  ...)
```

The reason is an optional trailing string literal on the `spec-entropy` clause. It is **meaningful only for `:intentional`** (see decision 2). `:strict` is the elided default and takes no reason; `:unknown` takes no reason.

### Schema delta

The current `spec_entropy` field is a bare string (`llmll-ast.schema.json:70,128`). Adding the reason **inside** it (`{"value":…,"reason":…}`) is **breaking** — every existing AST and every consumer reading `spec_entropy` as a string fails. Instead add an **additive sibling** field on `DefCore` and `DefShell`:

```jsonc
"spec_entropy":        { "type": "string", "enum": ["strict","intentional","unknown"] },   // unchanged
"spec_entropy_reason": { "type": "string", "description": "Justification for an :intentional annotation. Meaningful only when spec_entropy == 'intentional'." }
```

Additive → existing ASTs still parse, existing consumers ignore it, `SpecEntropy` (Syntax.hs:326) stays a simple sum. In `Syntax.hs` the `Contract` record (line 309) gains `contractSpecEntropyReason :: Maybe Text` alongside the existing `contractSpecEntropy`. This is a **minor schema-version bump** (additive), not a major one. The trust-report `spec_entropy_annotation` surface (`specEntropyLabel`, Syntax.hs:335; consumed in `TrustReport.hs`) carries the reason additively as well, following the F-001 `over_annotation` precedent — **no `trust_report_version` bump** (additive-field discipline, per `64b8700` and the `joint_pbt_witnesses` precedent).

### Decisions and recommendations

**1. Required vs optional reason for `:intentional`.** **Recommend: semantically required, mechanically warned (not parse-rejected) in Slice 1.** The design intent is that *every* `:intentional` carries a reason — that is the whole value of the construct. But enforce it via a governance W-code (decision 3), not a hard parse error, so the change is non-breaking. The `weakness-ok` precedent argues for hard-required; the asymmetry (below) argues for staging into it rather than a flag-day break.

**2. Does `:unknown` carry a reason?** **Recommend: no.** `:unknown` is the spec-in-flux state (`§4.4.6:690`, "for spec-development workflows where the contract is in flux"). Its defining property is that the author *has not yet decided* whether the looseness is intentional — so "why is this loose?" has no stable answer to record, and forcing one is noise that penalizes rapid spec iteration. Only `:intentional` makes the positive claim "this looseness is deliberate," and only a positive claim warrants a justification. A reason string on `:strict` or `:unknown` is a misplaced-justification governance warning (decision 5, W612).

**3. Hard parse error vs W-code warning (the load-bearing migration decision).** **Recommend: W-code warning (soft) as the shipping default, with a documented promotion path to hard-error parity with `weakness-ok`.** Two reasons the soft default is proportionate where `weakness-ok` chose hard:
   - *Surface asymmetry.* `weakness-ok` gates the **spec-coverage** channel (`§5.4`) — a harder surface where an unjustified suppression hides an entire unspecified function. `:intentional` only suppresses an **advisory CDP diagnostic**; the wrong impl still verifies against its (weak) post, and the diamond-lattice evidence level is untouched. Softer enforcement is proportionate to the softer surface.
   - *The warning is the migration driver.* A W-code that fires on every reason-less `:intentional` flags exactly the sites that need migrating (the ~5-site tail below), without breaking them. After the tail is cleaned, a Slice-2 flip of `pSpecEntropyClause` to reject the bare `:intentional` form reaches `weakness-ok` parity with no flag-day break.

   The migration tradeoff, explicit: hard-required now is a value-dependent grammar (reason mandatory iff the label is `:intentional`, `Parser.hs:559`) plus a breaking change to the ~5 source clauses and the doc examples. The tail is small enough that this is *feasible* pre-v1.0 — the recommendation for soft-first is about reversibility (a hard error is a one-way door) and proportionality, not about migration size.

**4. JSON-AST shape.** Covered in Schema delta: **additive `spec_entropy_reason` sibling**, not an in-place object. The trust-report `spec_entropy_annotation` carries it additively so CI and human review see it on the machine-readable surface (this is what makes the artifact *useful* — it rides the same JSON F-002's per-function `discriminative_axis` score already rides).

**5. Governance W-codes.** A new **W61x block**, distinct from `weakness-ok`'s W60x (which governs a different mechanism):
   - **W610** — `(spec-entropy :intentional)` with no reason string → warning (the core "justify your intentional looseness" nudge; the Slice-1 soft enforcement of decision 1).
   - **W611** — reason string present but empty / whitespace-only → warning (mirrors `weakness-ok`'s non-empty expectation, `§4.5:705`).
   - **W612** — `spec_entropy_reason` present on a `:strict` or `:unknown` annotation → warning (misplaced justification; per decision 2).

   No duplicate-reason code is needed: `pSpecEntropyClause` (Parser.hs:559) admits one clause per contract, so a duplicate is already a parse error, not a governance case.

## Edge cases and degenerate inputs

| # | Input | Expected behavior | Channel | Cite |
|---|---|---|---|---|
| 1 | `(spec-entropy :intentional)` (bare, Slice 1) | Parses; emits **W610** | trust (advisory governance) | `Parser.hs:559`; W610 |
| 2 | `(spec-entropy :intentional "")` (empty reason) | Parses; emits **W611** | trust | `§4.5:705` non-empty precedent |
| 3 | `(spec-entropy :strict "…")` / `(spec-entropy :unknown "…")` | Parses; emits **W612** (misplaced reason) | trust | decision 2; `§4.4.6:688,690` |
| 4 | Over-annotation module ratio (30%, `§4.4.6:689`) | **Unchanged** — the reason string does not touch `overAnnotationRatio`/threshold | trust (independent) | `CDP.hs:193-213`; F-002 settled |
| 5 | AstEmit round-trip of a reason-bearing contract | `spec_entropy_reason` must emit iff `Just`; a bare `:intentional` emits with the field absent (idempotent) | type / schema (round-trip well-formedness) | `ParserJSON.hs:224`; emitter must be updated **symmetrically** |
| 6 | Reason-less `:intentional` in an existing fixture (Slice 1) | Still compiles; W610 flags it for migration | trust | migration tail below |

Edge case 5 is the one with teeth: an additive JSON field is only round-trip-safe if the **emitter and the `ParserJSON` decoder are updated in lockstep**. Asymmetric ToJSON/FromJSON on contract nodes has bitten this project before (the datatype-constructor round-trip break); the engineer plan must treat emit+parse as one change.

## Verification mapping

**No new proof obligation.** The reason string is a parser/schema addition plus three governance checks (W610–W612) computed in Haskell — exactly parallel to `weakness-ok`, which introduces no VC (`§4.5` is pure governance). No refinement predicate reaches the obligation channels; nothing is emitted to liquid-fixpoint; the `Σ_auto` fragment boundary (`LLMLL.md §5.3.3`) is untouched. Fragment classification is therefore **N/A** (there is no obligation to classify), and this is stated affirmatively rather than punted: the construct is inert with respect to the QF-LIA / nonlinear / Lean partition of `§5.3.5`. The W61x codes are trust-channel advisory diagnostics, not verification conditions.

## Three-channel / trust mapping

A **trust-channel advisory surface with zero soundness impact.** It changes nothing about *what verifies*: the wrong implementation still verifies only against its weakened postcondition; the diamond-lattice evidence level is unchanged; the CDP score and the `raiseLowDP` suppression (`Syntax.hs:362-364`) are unchanged; the module over-annotation ratio is unchanged. It touches neither the type channel nor the contract (VC) channel. It adds (i) a governance signal (W61x) and (ii) a machine-readable justification artifact (`spec_entropy_reason`) for human/CI consumption. **F-002 remains settled** — this is orthogonal defense-in-depth, not a detection mechanism, and it does not reopen the automated-oracle question the professor review closed (Gap #5).

## Affected surface

*Not an implementation plan — the seam where `compiler-engineer` takes over.*

- `LLMLL.md §4.4.6` (spec-entropy surface) and the `§4.5`-adjacent governance table (new W61x rows) — **doc-lead's slot**, after the engineer ships.
- `docs/llmll-ast.schema.json:70,128` — additive `spec_entropy_reason` on `DefCore` + `DefShell`; minor schema-version bump.
- `compiler/src/LLMLL/Syntax.hs:309` — `contractSpecEntropyReason :: Maybe Text` on `Contract`; `SpecEntropy` sum (line 326) unchanged.
- `compiler/src/LLMLL/Parser.hs:558-565` — `pSpecEntropyClause` accepts an optional trailing string literal.
- `compiler/src/LLMLL/ParserJSON.hs:224,238,298` + the AST emitter — decode/encode `spec_entropy_reason` **symmetrically**.
- `compiler/src/LLMLL/CDP.hs` / `WeaknessCheck.hs` / `app/Main.hs` — emit W610/W611/W612; `overAnnotationRatio` (CDP.hs:189-213) unchanged.
- `compiler/src/LLMLL/TrustReport.hs` — carry the reason into the `spec_entropy_annotation` surface (additive; no `trust_report_version` bump).
- **Migration tail (~5 source sites + doc examples):** `experiments/adv-spec-weaken-0/fixtures/ax1-0{2,3,4}.llmll`, `compiler/test/fixtures/cdp/intentional.llmll:7`, `compiler/test/Spec.hs:8714`, plus the `§4.4.6` and `docs/getting-started.md` doc examples. Under Slice-1 W-code these keep compiling (W610-flagged); a Slice-2 hard-error promotion requires reasons added to each. Test plan is the engineer's slot.

## Risks and open questions

1. **Reason string is still self-attestation.** Classify: verification-ergonomics / scope. Cite: professor review Gap #5. Bite: caps the value — a launderer can write a plausible-but-false reason; the artifact's worth is entirely for human/CI review, never automated detection. This is the honest ceiling and the reason F-002 stays settled. If the team judges this deterrent too weak to justify even the small migration, the **null option is legitimate** (do nothing; external CI already gates on the machine-readable per-function score + annotation).
2. **AstEmit round-trip asymmetry.** Classify: spec-drift (parser/emitter). Cite: `ParserJSON.hs:224`. Bite: blocks round-trip correctness if the emitter is not updated in lockstep with the decoder; this class has bitten datatype-node ToJSON/FromJSON before.
3. **Value-dependent grammar on the Slice-2 promotion.** Classify: scope. Cite: `Parser.hs:559`. Bite: complicates only the hard-error path (reason required iff `:intentional`); Slice-1's soft W-code avoids it (reason always parse-optional, governance-checked after).
4. **W61x / over-annotation-warning double-reporting.** Classify: scope. Cite: `CDP.hs:193`. Bite: minor; the per-site W61x block and the module-ratio warning are independent signals and must not be conflated in output.
5. **Migration cost vs. benefit.** Classify: scope. Bite: the whole proposal is elective; the small tail (~5 sites) makes it cheap, but the deterrent is bounded (risk 1). A deliberate decision, not a default.

## Open questions for the professor

One, and it bears directly on decision 3 (is the Slice-2 hard-error promotion worth it?): **does mandatory-justification-string discipline have a studied effect on attestation-abuse rates in audited corpora?** The Rust `#[allow(...)]` / crater audit dataset and Liquid Haskell's `{-@ assume @-}` community practice (both cited in CDP proposal §10 Risk #3 Rev 2) are the obvious empirical anchors. If the literature shows mandatory reasons measurably reduce unjustified-suppression rates, that argues for promoting to hard-required; if the effect is negligible, the Slice-1 W-code is the terminal design and the promotion should be dropped.

---

**Hand-off (Rev 0 → user adjudication).** This is a fresh proposal, not a settlement. If the user approves the direction, the code-track hand-off to `compiler-engineer` is: additive `spec_entropy_reason` field (`Syntax.hs:309`, schema `:70,128`), optional-trailing-string parse in `pSpecEntropyClause` (`Parser.hs:559`), symmetric `ParserJSON` emit/decode, W610–W612 governance in `CDP.hs`/`WeaknessCheck.hs`, additive trust-report carry (`TrustReport.hs`, no version bump), and the ~5-site migration. A `professor` turn on the one empirical question above is warranted before committing to the Slice-2 hard-error promotion, but not before Slice 1.
