# Professor Review: LT-PPR — Predicate-Carrying `?proof-required`

**Reviewer:** Lead Consultant for Formal Language Design
**Document under review:** [`proof-required-predicate-carrier-proposal.md`](proof-required-predicate-carrier-proposal.md) (Rev 1)
**Date:** 2026-05-25
**Status:** Review (Rev 1) — pending language-team adjudication

---

## Restatement

LT-PPR extends `HoleKind.HProofRequired Text` to `HProofRequired Text (Maybe Expr)`: the marker continues to carry the reason tag and now optionally carries the predicate it stands in for. The predicate typechecks as `bool` in the surrounding `pre`/`post` context; the verifier does not consume it (the clause routes to `asserted` per [`LLMLL.md §5.3.5`](../../LLMLL.md)); codegen emits a runtime-assertion fallback over the predicate; the trust report records `predicate_form` ∈ {`leaf`, `predicate-carrying`}, `predicate_text` (length-bounded), and `runtime_check_emitted` per clause. The predicate-carrying form is `def-shell`-only per LT-INV §1.4; admission inside `def` parse-rejects. The proposal supersedes the deferred-exploration seed at `proof-required-predicate-carrier.md`.

§6 settles two open clauses: trust label stays `asserted` (no fifth tier); core-grammar interaction adopts LT-INV §1.4 verbatim.

---

## Context located

- `compiler/src/LLMLL/Syntax.hs:243` — `HoleKind.HProofRequired Text`; the constructor signature change is the load-bearing AST edit.
- `LLMLL.md §6:780-789` — current "gap signal, not a predicate carrier" callout; LT-PPR §10 replaces it.
- `LLMLL.md §13.10` — `result` keyword scoping in `post`-position; binding rules unchanged.
- `LLMLL.md §5.3.5` — verification matrix `?proof-required` row; unchanged (the marker still routes to `asserted`).
- `LLMLL.md §4.4.1:325-344` — diamond lattice; §6.1 adjudicates that the lattice stays unchanged (no fifth tier).
- `compiler/src/LLMLL/CodegenHs.hs` — runtime-assertion-fallback emit site; new code path for predicate-carrying form.
- `compiler/src/LLMLL/TrustReport.hs` — `EvidenceRecord` schema; gains `predicate_form`, `predicate_text`, `runtime_check_emitted`.
- `experiments/minimal-agent/findings/postmortem-smoketest-001-002.md` finding #1 — empirical-demand signal (5 of 12 attempts surfaced the ambiguity at §13.8).
- `docs/design/core-shell-inversion-direction.md §1.4` — the def-forbiddance rationale this proposal inherits.
- Vazou et al., *Refinement Types for Haskell* (POPL 2014) §3 — LH's `{-@ assume @-}` declarations; the closest tradition to LT-PPR's predicate-carrying form. LH `assume` carries a refinement signature; the predicate is *part of the signature*, not a hole payload.
- The Lean 4 `sorry` mechanism (Leanprover/Lean4 source, `core.lean`) — admits a value of any type with `sorry`-tagged proof obligations recorded in `#print axioms`; carries *no* predicate, only the type.
- Coq's `Admitted` (Coq Reference Manual §1.5) — same shape as Lean's `sorry`; type-only.
- Filliâtre & Paskevich, *Why3 — Where Programs Meet Provers* (ESOP 2013) §4.3 — `assume` keyword carrying full predicate; the closest non-LH precedent.
- Leino, *Dafny: An Automatic Program Verifier for Functional Correctness* (LPAR 2010) §2 — `assume P` admits the predicate `P` into the proof context; *no* witness extraction from runtime-failed `assume`s (Dafny `assume`s are static, never runtime-checked).
- Brady, *Idris 2: Quantitative Type Theory in Practice* (2021) — `?hole` with elaborator-driven refinement; produces an interactive proof obligation, not a runtime artifact.
- Claessen & Hughes, *QuickCheck* (ICFP 2000) §4 — *shrinking* on failed property: the runtime counter-example is captured and minimized. The closest precedent for "witness extraction from runtime-failed assertion."
- Siek & Taha, *Gradual Typing for Functional Languages* (Scheme Workshop 2006) — the static/dynamic boundary; the gradual guarantee (Siek-Vitousek-Cimini-Tobin-Hochstadt POPL 2015) is the relevant precedent for the honor-the-gap-vs-opportunistic-discharge trade-off in author Q2.
- Cimini & Siek, *The Gradualizer: a Methodology and Algorithm for Generating Gradual Type Systems* (POPL 2016) — formalizes the trade-off; the gradual guarantee favors *opportunistic* checking where possible, but is consistent with *honor-the-gap* under explicit-cast semantics.

---

## Strengths

The empirical evidence at §1 is the right kind of motivation. 5 of 12 attempts across two model providers surfacing the same ambiguity is not noise — it is signal that the leaf-form-only design creates an authoring-time surface/spec mismatch agents reach to resolve. The deferred-exploration doc's revisit conditions (2)(b) are met by the LT-INV downstream-consumer benefit; (1) is met by the freeze-exception. The proposal correctly inherits the deferral doc's framing rather than re-deriving from first principles.

§6.1's adjudication — *trust label stays `asserted`; no new tier* — is correct. The diamond lattice's load-bearing role in `tier_profile` and `DisplayLevel` makes a fifth tier expensive (downstream-consumer migration cost); the predicate-carrying form's value is *informational*, not *epistemic*. The `predicate_form` field on the `EvidenceRecord` carries the distinction without polluting the tier system. This matches the principle that the diamond lattice expresses *epistemic certainty*, not *operational enhancement* — runtime-assertion fallback is an operational enhancement.

§6.2's adjudication — *predicate-carrying form forbidden inside `def`* — is correct. The marker is an `asserted`-tier escape hatch; admitting it in `def` re-introduces the polarity inversion's load-bearing semantic non-uniformity. The cleanly delegated rule (LT-INV §1.4 verbatim) is the right kind of cross-proposal coupling — explicit, not implicit.

The schema bundling with LT-INV (§7) is sensible. Bundling avoids two consecutive `schemaVersion` bumps for additive-back-compat changes; the v0.5.0 → v0.6.0 increment is justified by LT-INV's grammar production and absorbs LT-PPR's additive predicate field as a same-major-minor add.

The non-discharge choice (§4.2, §8 edge case #3) is principled: the marker's purpose is *explicit gap-signalling*. Opportunistic discharge when the predicate happens to be QF-LIA-tractable would erode the deliberate "this is a gap" semantics. The agent that wants discharge should write the regular `(post pred)` clause. The proposal correctly recognizes this as a *scope* decision, not a *capability* decision.

---

## Gaps and hazards

### 1. Runtime-assertion fallback semantic divergence from verifier symbolic interpretation

**Classify:** soundness.

Risk #2 acknowledges this concern but understates the bite. The runtime assertion evaluates the predicate using the *Haskell runtime semantics* of the underlying builtins (per `CodegenHs.hs` lowering). The verifier's symbolic interpretation uses the *axiomatized signatures* of the same builtins (per `Contracts.hs` constraint emission). The two diverge in several ways:

- **Partial functions.** A predicate using `list-head` evaluates at runtime to either the element or a partial-function error; the verifier's symbolic interpretation treats `list-head` as a refinement-preconditioned function (head requires non-empty list). A predicate-carrying `?proof-required` over `(= (list-head xs) v)` runtime-fails on empty `xs` *and* the verifier-symbolic-interpretation would have classified the empty case as a precondition violation rather than a postcondition refutation.
- **Numeric semantics post-INT-1 (v0.10.8).** Z3 reasons over mathematical integers; Haskell `Int` is `Int64`. The verifier-symbolic predicate `(> result 0)` is sound over mathematical integers; the runtime assertion is checked over `Int64`. Overflow-tainted predicates fail one but not the other.
- **Lazy evaluation.** The runtime assertion forces the predicate's evaluation; lazy contexts may produce divergent behavior (assertions that succeed under symbolic interpretation but loop forever under lazy evaluation on an infinite structure).

The proposal's mitigation (opt-out flag via codegen, `runtime_check_emitted` records the choice) is correct in shape but does not name the *divergence-class enumeration*. Risk #2's prose treats this as "partial function example"; the three cases above are distinct soundness failure modes.

The deeper issue: the predicate-carrying form blurs the verifier/runtime boundary that `--strict-verified-core` cleanly separates. A clause routed to `asserted` with `runtime_check_emitted: true` is *not* verified; the runtime check provides *additional* evidence (a witness that the predicate held on at least the inputs encountered). The proposal's §5 records the emission but does not commit to a story about *what the runtime check buys epistemically*. The honest answer: it buys *additional asserted-tier confidence*, not a tier promotion; a function whose runtime assertion holds for N invocations is at most `asserted-with-N-runtime-witnesses`, which is observationally indistinguishable from `asserted-with-PBT-coverage-N`.

**Bite:** medium. The soundness story is correct under the explicit tier-unchanged framing; the divergence-class enumeration should be made explicit so downstream consumers do not over-interpret the `runtime_check_emitted: true` signal.

---

### 2. The QF-LIA-tractable non-discharge choice has an opportunity-cost asymmetry the proposal does not name

**Classify:** verification-ergonomics.

§4.2 and edge case #3 settle this question: when the predicate is QF-LIA-tractable, the verifier *does not* attempt discharge. The agent who wants discharge writes `(post (> result 0))` directly; the agent who writes `(post (?proof-required (> result 0)))` accepts the asserted-tier classification.

The opportunity-cost asymmetry: an agent under repair-loop pressure who has marked a clause `?proof-required` *might* have a tractable predicate without realizing it. The proposal's choice forces the agent to *deliberately* downgrade their own mark to access the verifier's capability. Under the v0.10 leaf form this asymmetry doesn't exist (no predicate to discharge). Under the predicate-carrying form the asymmetry is real and visible.

Two alternative designs the proposal does not consider:

- **Verifier-side hint.** When parsing `(?proof-required (> result 0))`, the verifier emits an informational diagnostic: "predicate is QF-LIA-tractable; consider downgrading to `(post (> result 0))` for solver-backed evidence." The agent retains the choice; the system surfaces the asymmetry. Cost: one diagnostic.
- **Strict-mode opportunistic discharge.** `?proof-required` predicates are non-discharged by default; a `--opportunistic-discharge` flag opts in to discharge-when-tractable with the tier-classification *unchanged*. This preserves the gap-signal semantics for downstream tooling while letting `--strict-verified-core` benefit from solver-backed evidence opportunistically.

The proposal's choice (strict non-discharge, no diagnostic) is consistent with the agent-declares-intent philosophy. But the philosophy is being asserted, not derived; the alternative — *opportunistic discharge with intent preservation* — is equally defensible under the gradual-typing literature (Siek-Taha 2006; Cimini-Siek 2016).

**Bite:** low-medium. The agent-declares-intent philosophy is defensible but the alternative is real. Worth a sentence in §4.2 acknowledging that a verifier-side informational diagnostic is a non-disruptive improvement that the proposal does not commit to but that future work may explore.

---

### 3. Witness extraction from runtime-failed assertions is anticipated by author Q1 but not addressed in the design

**Classify:** scope.

Author Q1 names the question: do any traditions extract witnesses from runtime-failed assertions to upgrade the predicate-carrying form into structured evidence? The proposal anticipates this as a future-direction question but does not propose any mechanism.

The closest in-project precedent: OBLIG-PBT-3's `pbt_witnesses` SHA-256 hashes attached to `DLTested` entries (per `oblig-pbt-3-proposal.md` §5). The runtime-assertion fallback at LT-PPR §4.2 is functionally a single-execution property check; capturing the input on assertion failure produces a counter-example AST node, which is exactly the "structured evidence" Q1 names.

The QuickCheck-shrinking precedent (Claessen-Hughes ICFP 2000 §4) is the canonical external reference: a runtime-failed property is minimized to a small counter-example, which carries diagnostic value far beyond the single input. The shrinking machinery is non-trivial but the *capture* of the failing input is trivial.

**The opportunity:** when codegen emits the runtime assertion, the emit site can additionally emit a *capture handler* that, on assertion failure, writes the failing input + the predicate-evaluation trace to a structured diagnostic file (e.g., a `.assertion-failures.json` sidecar). The trust report on subsequent verify runs can read this sidecar and report `predicate_form: "predicate-carrying", runtime_check_emitted: true, observed_failures: [{input: ..., predicate_evaluation: false}, ...]`. The diamond lattice still classifies the clause as `asserted`, but the trust report carries actionable counter-example data.

The proposal does not propose this. It is appropriate for v0.11 to ship without it (the runtime assertion alone is a discrete and useful enhancement). But Q1's existence in the proposal flags that the design space includes this direction, and Rev 2 should either commit to "v0.12+ may extend this" or surface the design space explicitly.

**Bite:** low (for v0.11). The witness-extraction direction is a v0.12+ opportunity, not a v0.11 gap.

---

### 4. The predicate-text truncation at 256 chars is the right shape but creates a downstream-consumer fragmentation risk

**Classify:** scope.

Risk #1 names the predicate-text-bloat concern and proposes a configurable 256-char limit in the trust-report emit. The full predicate AST lives in `.verified.json`. This is correct in shape — the trust report is the *summary* surface; the sidecar is the *detail* surface.

The fragmentation risk: downstream consumers reading the trust report at scale (CI dashboards, agent-prompt context, governance-report consumers) see the truncated text; consumers reading the sidecar see the full AST. The two views diverge for non-trivial predicates. The consumer-facing documentation needs to be explicit that the trust report's `predicate_text` is *display-truncated* and that the sidecar carries the canonical form.

This is not a soundness issue; it is a discovery-and-debugging cost on a small fraction of cases (predicates exceeding 256 chars). The proposal handles the immediate concern; the fragmentation is the second-order concern that warrants one sentence of consumer-facing documentation.

**Bite:** low. The mitigation is correct; the documentation pointer is missing.

---

### 5. The schema bundling with LT-INV (§5 of LT-PPR) creates a coupling that is documented but not bounded

**Classify:** spec-drift.

Risk #5 acknowledges the bundling: LT-PPR's schema delta rides LT-INV's `0.5.0 → 0.6.0` bump. If LT-INV slips, LT-PPR has two paths: independent bump to `0.5.1` (additive-only) or wait. The mitigation is "bundling is intentional and recommended; if independent ship is needed, `0.5.0 → 0.5.1` is the additive-only path."

The deeper question: under what condition is the bundling *contingent*? The proposal does not commit. If LT-INV ships under §8 empirical-gate failure with the rollback path "demote to opt-in flag," LT-PPR's predicate-carrying form lands without the `def`-forbiddance enforcement that LT-INV's grammar provides. LT-PPR §6.2 enforces the rule via LT-INV §1.4 verbatim; if LT-INV is opt-in-only, the rule is enforced only when the opt-in flag is set. Outside the flag, the predicate-carrying form is admitted inside `def-logic` (the v0.10 keyword), and the asserted-tier escape hatch re-enters the v0.10 default form.

The proposal's mitigation does not name this. The honest answer: LT-PPR's `def`-forbiddance is *contingent on LT-INV's grammar production being the default*. If the empirical gate fails and LT-INV is rolled back to opt-in-only, LT-PPR should either also become opt-in-only (no predicate-carrying form by default) or accept that the asserted-tier escape hatch is admissible in the default grammar (which contradicts §6.2's adjudication).

**Bite:** medium. The cross-proposal coupling is not symmetric — LT-INV can ship without LT-PPR, but LT-PPR's `def`-forbiddance depends on LT-INV's grammar being canonical. Rev 2 should specify the contingent shipping rule: LT-PPR ships only if LT-INV's gate passes; rollback paths trigger LT-PPR rollback symmetrically.

---

### 6. Predicate-carrying form straddles `{-@ assume @-}` and `sorry`/`Admitted` — the proposal's positioning is closer to LH but the proposal does not commit

**Classify:** scope.

§9 (author Q1 paraphrase) notes that LT-PPR lands "closer to Liquid Haskell — predicate present, runtime-assertion fallback emitted, trust label `asserted`" than to Coq/Lean's type-only form. The positioning is correct but the proposal does not commit to a *primary tradition reference* in §1 motivation.

The three traditions:

- **LH `{-@ assume @-}` (Vazou et al. POPL 2014 §3).** Carries the predicate at the signature level. No runtime-assertion emission. The predicate is *trusted* by the verifier (admitted as a hypothesis); the discharge obligation is moved upstream (the assume's *correctness* is human-audited, not solver-checked). LT-PPR diverges: the predicate is *not* admitted as a verifier hypothesis (it stays `asserted` per §4.3), but it *is* emitted as a runtime check.
- **Coq `Admitted` / Lean `sorry`.** Carry no predicate. The proof obligation is recorded in `Print Assumptions` / `#print axioms`. Trust label is the type's; the predicate the type stands in for is *external to the AST* (lives in the surrounding proof script or documentation).
- **Why3 `assume P` (Filliâtre & Paskevich ESOP 2013 §4.3).** Carries the full predicate. The predicate *is* admitted as a verifier hypothesis. Trust label is `assumed` (a distinct tier in Why3's evidence model). No runtime-assertion emission.

LT-PPR is the *combination*: predicate carried (LH), predicate-not-admitted-as-hypothesis (LH+Coq+Lean), runtime-assertion emitted (none of the three). The combination is *novel*, not derivative. The proposal does not name this novelty in §1; it should.

**Bite:** low. The novelty is not a defect; the lack of explicit positioning means downstream readers (and the engineer) may default to LH's framing and miss the runtime-assertion mechanism's distinction. One paragraph in §1 acknowledging the novel combination would close the credit-loss against the precedent literature.

---

## Answers to author-surfaced questions

### Q-PROF-1. Third traditions on witness extraction — Idris's `?hole`, Dafny's `assume`, others?

**No production system extracts witnesses from runtime-failed assertions.** The closest precedent is QuickCheck shrinking; the predicate-carrying form's design space includes the direction but no production tradition has shipped it.

The detailed reading:

- **Idris `?hole` (Brady 2021)** is an *interactive* proof obligation, not a runtime artifact. The elaborator drives refinement at type-check time; failed elaboration produces a goal-state diagnostic, not a runtime witness. Idris 2's quantitative type theory enriches this with usage information but does not change the runtime/interactive boundary.
- **Dafny `assume P` (Leino LPAR 2010 §2).** Admits the predicate `P` as a verifier hypothesis. Dafny `assume`s are *not* runtime-checked; they are admitted into the static proof context. The closest Dafny analog to LT-PPR's runtime assertion is Dafny's `assert P; assume P;` idiom: a static assertion immediately followed by an assumption. The `assert` is verified; the `assume` is a no-op if `assert` succeeded. This is not witness extraction; it is *belt-and-suspenders* static verification.
- **Coq's `Print Assumptions`** lists axioms used in a proof but does not extract witnesses from any source — axioms are immutable proof-context entries.
- **Lean's `#print axioms`** is the same shape as Coq's `Print Assumptions`.
- **Why3's `assume P`** has no runtime-assertion emission and no witness extraction.

**The closest precedent for runtime-witness extraction is QuickCheck shrinking** (Claessen-Hughes ICFP 2000 §4). A failed property is minimized to a small counter-example, which carries diagnostic value far beyond the single input. The shrinking machinery is non-trivial but the *capture* of the failing input is straightforward — it requires only the runtime-assertion site to record the input on failure.

**Recommendation for the proposal:** retain §4.2 / §5 as-is for v0.11. Add a §11.2 "Future directions" sub-section (or a §6.3 adjudication) acknowledging witness extraction as a v0.12+ direction with the QuickCheck-shrinking precedent. The design space is well-formed; the proposal correctly defers it.

**On Q1's specific framing:** the witness-extraction direction *can* be implemented at LT-PPR's existing surface — the runtime-assertion emit site can write a `.assertion-failures.json` sidecar with the failing input, and the trust report on subsequent verify runs can ingest it as enriched evidence. This is an additive extension to the trust-report schema; it does not require a new tier (consistent with §6.1's adjudication).

### Q-PROF-2. Honor-the-gap vs opportunistic-discharge — gradual-typing literature's stance?

**The gradual-typing literature favors opportunistic checking; LLMLL's honor-the-gap choice is principled but unusual.**

The detailed reading:

- **Siek-Taha (Scheme Workshop 2006)** introduces the static/dynamic boundary with `?` as the dynamic type. The original framing is *opportunistic* — when both sides of an interaction are statically typed, the check is static; when either is dynamic, the check is runtime. The boundary's `?` is a *capability declaration*, not a *gap declaration*.
- **The gradual guarantee (Siek-Vitousek-Cimini-Tobin-Hochstadt POPL 2015)** formalizes the property that adding type annotations to a gradually-typed program does not introduce new runtime errors. This is consistent with opportunistic checking: more static information → more static checks → fewer runtime errors. The guarantee makes opportunistic checking the *expected* discipline.
- **Cimini-Siek (POPL 2016)** generalize the framework; the gradual guarantee can be relaxed (the "Gradualizer" produces gradual type systems with different guarantee strengths). Honor-the-gap is admissible but requires an explicit semantic argument.
- **Coercion-based gradual typing (Henglein 1994; Siek-Garcia 2010)** is the closest formal precedent for honor-the-gap. Coercions are *explicit casts* between static and dynamic; the coercion's *presence* is the gap declaration. Within coercion semantics, the cast is checked at the coercion site, not opportunistically along the call graph.

LLMLL's `?proof-required` is closer to a coercion in this sense: the marker's *presence* declares the gap, and the verifier honors the declaration by not attempting discharge. The opportunistic alternative is the "gradual guarantee" reading.

**Recommendation for the proposal:** retain §4.2 / edge case #3. Add a §11.3 (or §4.2 paragraph) acknowledging that the honor-the-gap choice is a *coercion-semantics* reading per Henglein 1994 / Siek-Garcia 2010, and that the alternative *gradual-guarantee* reading is also defensible. This is a scope decision, not a soundness decision, and the proposal should make the design philosophy explicit so downstream readers do not default to the gradual-guarantee assumption.

**On the specific opportunity-cost asymmetry from Gap #2 above:** the verifier-side hint diagnostic (one informational diagnostic per QF-LIA-tractable `?proof-required`) is *consistent* with honor-the-gap — the diagnostic surfaces the alternative without changing the semantics. This is the minimum disruption move; Rev 2 could commit to it without redesigning §4.2.

---

## Cross-proposal observation

LT-PPR's `def`-forbiddance (§6.2) is a *load-bearing inheritance* from LT-INV §1.4. If LT-INV ships under empirical-gate failure with rollback path (i) (opt-in-only), LT-PPR's enforcement also becomes opt-in-only; the predicate-carrying form is admissible in `def-logic` outside the opt-in flag and the asserted-tier escape hatch re-enters the default grammar. Rev 2 should commit to LT-PPR shipping contingent on LT-INV's gate pass; rollback paths trigger LT-PPR rollback symmetrically (per Gap #5 above).

LT-PPR interacts with LT-CDP via edge case #1 of LT-CDP: CDP is computed over the non-`?proof-required` portion of a contract. The predicate-carrying form makes the proof-required portion *informationally* rich; LT-CDP could in principle count this richness as a sub-component of the discriminative axis, but the proposal does not propose this (correctly — the predicate-carrying form is `asserted`-tier and CDP's `discriminative_axis` is orthogonal to evidence tier).

The fuller cross-proposal sequencing observation appears in `refinement-metatheory-of-record-review.md`.

---

## Recommendation

**Approve with revisions.**

The predicate-carrying form is the right move; the empirical demand is real and the design is principled. Three revisions are load-bearing:

1. **Specify the contingent shipping rule against LT-INV's gate (per Gap #5).** LT-PPR ships only if LT-INV's empirical gate passes; rollback paths trigger LT-PPR rollback symmetrically. Without this, the `def`-forbiddance is unenforced outside the opt-in flag and §6.2's adjudication is partially undone.

2. **Enumerate the runtime-vs-symbolic divergence classes explicitly (per Gap #1).** Partial functions, post-INT-1 numeric semantics, and lazy evaluation are three distinct divergence modes. Risk #2 names one example; the three-class enumeration belongs in §4.2 or §11.1, so downstream consumers do not over-interpret the `runtime_check_emitted: true` signal.

3. **Add a one-paragraph positioning statement to §1 (per Gap #6).** LT-PPR is the novel combination of LH's predicate-carrying form, Coq/Lean's no-hypothesis-admission, and runtime-assertion emission (none of the three precedents). The combination is defensible but should be explicit in the motivation so downstream readers do not default to LH's framing and miss the distinction.

The remaining gaps (#2 opportunity-cost asymmetry, #3 witness extraction, #4 predicate-text fragmentation) are addressable in-prose or deferrable to v0.12+; Rev 2 incorporates them as risk-section enrichments or text-level corrections.

The two §6 adjudications (trust label unchanged; def-forbiddance) are settled correctly and should not be re-litigated in Rev 2. The non-discharge choice (§4.2, edge case #3) is defensible under coercion-semantics framing; the verifier-side informational diagnostic per Gap #2 is the recommended non-disruptive enhancement.

---

## Open questions for the language-team

1. **Specify the runtime-assertion-emission semantics under the post-INT-1 overflow-taint regime.** When a predicate-carrying `?proof-required` clause contains arithmetic over `Int64`-folding values that pre-INT-1 would have been overflow-tainted, what does the runtime assertion check? The v0.10.8 `overflow_tainted` field on `EvidenceRecord` marks tainted verified evidence; LT-PPR's runtime-assertion fallback predicates the *same* arithmetic. If the runtime check fails under overflow, the assertion-failure handler must distinguish "predicate is genuinely false" from "overflow triggered the failure"; the spec should commit to which.

2. **Justify the non-emission of a verifier-side informational diagnostic for QF-LIA-tractable predicates (per Gap #2 / Q-PROF-2).** The honor-the-gap philosophy is defensible but the verifier-side hint is non-disruptive (one informational diagnostic per QF-LIA-tractable predicate-carrying `?proof-required`). Rev 2 should either commit to the diagnostic or explicitly justify its omission as a deliberate design choice consistent with coercion-semantics framing.
