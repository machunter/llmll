# Professor Review: LT-INV — Core/Shell Grammar Inversion

**Reviewer:** Lead Consultant for Formal Language Design
**Document under review:** [`core-shell-inversion-proposal.md`](core-shell-inversion-proposal.md) (Rev 1)
**Date:** 2026-05-25
**Status:** Review (Rev 1) — pending language-team adjudication

---

## Restatement

LT-INV proposes a grammatical polarity inversion: rename `def-logic` → `def` as the canonical strict-core form, introduce `def-shell` as the explicitly-marked permissive form, and replace the v0.10 default-permissive-with-`--strict-verified-core`-mode regime with a whitelist core-body grammar. `EApp` inside `def` admits only callees whose `EvidenceRecord.erBodyFaithful = True`; `letrec` routes to `def-shell` only; `?proof-required` (leaf or predicate-carrying) is forbidden inside `def`; schema bumps `0.5.0 → 0.6.0`. The proposal ships behind a `--grammar=core-inversion` opt-in flag pending the §8 empirical-validation gate on `experiments/minimal-agent/001-two-agent-auth`; the default flips only on gate pass.

The proposal subsumes STRICT-CORE-1 from the 2026-05-23 triage by making admissibility grammatical rather than verifier-mode-spec'd.

---

## Context located

- `LLMLL.md §5.3.3 / §5.3.5` — verification matrix and QF-LIA boundary that the whitelist enforces at the source grammar.
- `LLMLL.md §4.4.1:325-344` — diamond lattice (`verified` / `contract-checked` / `tested` / `asserted`); the polarity inversion changes which lattice point is *syntactically* reachable from canonical-`def`, not the lattice itself.
- `compiler/app/Main.hs:246`, `:1119-1158` — `--strict-verified-core` flag; the proposal preserves it as a redundancy check while the grammar enforces the same invariant lexically.
- `compiler/src/LLMLL/Syntax.hs:243` — `HoleKind` enumeration; LT-INV §3.5 splits admission by surrounding-form context, not by `HoleKind` constructor identity.
- `compiler/src/LLMLL/HoleAnalysis.hs` — the proposed core-vs-shell hole-form admission predicate's natural home.
- `compiler/src/LLMLL/TypeCheck.hs:781-1003` — `checkExpr` / `unify` sites where the `EApp` strict-callee restriction would query `erBodyFaithful`.
- `compiler/src/LLMLL/Syntax.hs` `ModuleEnv` / `meContracts` — the MOD-1 seam the proposal proposes for typechecker→`EvidenceRecord` access.
- `LLMLL.md §4.2:272-296` — `letrec` measure-well-formedness as `measure ≥ 0`; non-negativity is not termination per TERM-1.
- `experiments/minimal-agent/findings/` — the empirical-gate measurement substrate per §8.
- Vazou et al., *LiquidHaskell: Experience with Refinement Types in the Real World* (Haskell '14) §4.3 — LH's treatment of native vs. user code via `{-@ assume @-}` and `{-@ measure @-}`; the closest external precedent for the strict-callee question.
- Mike Gordon, *Background on HOL and a comparison with Coq* (1996) — proof-assistant tradition of "axiomatized but not proven" signatures, which is the lineage LH's `assume` inherits.
- Filliâtre & Paskevich, *Why3 — Where Programs Meet Provers* (ESOP 2013) §4 — Why3's prelude is a curated assumed-signatures set; closure-under-evidence-tier is solved by *whitelisting trusted builtins*, not by relaxing the call-closure rule.
- Bird & Wadler, *Introduction to Functional Programming* (1988) §6 — algebraic data type pattern matching as the canonical elimination form; the proposal's grammatical core inherits this discipline.
- The Rust edition migration story (rust-lang/rfcs #2052 — Rust 2018) — *the* canonical syntactic-classifier-plus-conservative-mode language migration. The pattern LT-INV §6 proposes is the Rust edition pattern.

---

## Strengths

The polarity argument in §1 is correct in shape and in substance. A flag that says "behave strictly" is procedurally weaker than a grammar production that says "the body cannot contain non-strict constructs"; the former relies on the user remembering to invoke it, the latter relies on the parser. Programming-language design generally favors making invariants *lexical* over *procedural* where the lexical version is feasible — Rust's borrow checker, Standard ML's value restriction, Haskell's strict-vs-lazy modules.

The empirical-validation gate at §8 is exemplary. Most spec-evolution work in this project ships behind the language-team's own judgment; LT-INV correctly identifies that the inversion is an *architectural bet about LLM behavior under a smaller grammar surface* and that this bet is empirically falsifiable on `001-two-agent-auth`. The two rollback paths (opt-in-only vs ship CDP+PPR without inversion) preserve the option-value of the work even if the bet fails.

Choice of whitelist over blacklist at §3.2 is the only defensible direction for a strict-core grammar. Future syntax additions cannot accidentally fall into the core production; they must be explicitly admitted. This is the same discipline Coq applies to its `Restricted` mode and that F* applies to its `tot` effect.

§3.4's strict-callee reading is correct at the soundness level — assume-guarantee through `asserted`-tier callees would leak that asserted-ness into a `def`-form claim of `verified`, and the inversion's polarity claim would be undermined the first time a non-body-faithful callee entered the call graph. The proposal correctly recognizes this and pays the migration cost.

---

## Gaps and hazards

### 1. The strict-callee closure is brittle to the §13 builtin distribution

**Classify:** verification-ergonomics / scope.

The strict reading at §3.4 says `EApp` in `def` admits only callees whose `erBodyFaithful = True`. But the §13 builtins are the substrate of most useful programs, and the proposal does not specify which are body-faithful. `string-length`, `int-to-string`, `list-head`, `list-tail` are pervasive; if they are not `erBodyFaithful = True`, every `def` body that touches them migrates to `def-shell`. Conway's Life, hangman, tictactoe — every example using list or string primitives goes shell-only.

The Why3 precedent (Filliâtre & Paskevich, ESOP 2013 §4) is the relevant treatment: Why3 maintains a *curated trusted-prelude set* whose signatures are assumed but whose bodies are not proven. Liquid Haskell's `{-@ measure @-}` declarations function similarly — a measure on a list (`measure len :: [a] -> Int`) is part of the trusted base, and refinement obligations using `len` are discharged against the *axiomatized* measure, not against `[a]`'s actual cons-cell representation.

The proposal's Risk #1 (open question Q1) identifies this concern but routes it to the professor for adjudication. The answer is unambiguous: **the relaxed closure — admit callees whose `erBodyFaithful = True` *or* which are in a configured trusted-builtin whitelist — is the right shape**, with the trusted-builtin whitelist being a separately-curated artifact in `LLMLL.md §13` rather than a verifier-state property. This matches the LH / F* / Why3 tradition and prevents the migration cost from collapsing `def` usage to near-zero on builtin-heavy programs.

The proposal as written would force the empirical gate (§8) to interpret "100% shell migration" as the inversion's failure mode — but the failure mode would be the strict-closure choice, not the inversion itself.

**Bite:** high. If §13 builtins are not in scope for `def` callees, the inversion's value proposition collapses on every program longer than ~10 lines.

---

### 2. The typechecker→`EvidenceRecord` coupling is architecturally larger than §3.4 implies

**Classify:** spec-drift / verification-ergonomics.

§3.4 says "the typechecker queries the callee's `EvidenceRecord`." This is presented as a small architectural move via MOD-1's `meContracts`. It is not. `meContracts` carries `(Name, [(Name, Type)], Contract)` per `Syntax.hs` and does *not* carry `EvidenceRecord`; `EvidenceRecord` is computed by the verifier (`Contracts.hs`, `FixpointEmit.hs`, `TrustReport.hs`) after typecheck. The proposal's move requires either:

(a) Computing a *prefix* of `EvidenceRecord` — specifically `erBodyFaithful` — during typecheck, which means typecheck calls into the verifier, breaking the v0.10 separation.

(b) Two-pass compilation where typecheck runs first under permissive admission, the verifier classifies body-faithfulness, and a *second* typecheck pass enforces the core-callee restriction. This is what Risk #2 implicitly proposes ("cold-cache cases the typecheck may need to invoke verify-side body-faithfulness checks first").

Neither is a small move. (a) inverts the v0.10 layering; (b) doubles the typecheck cost on every build. The third option — (c) cache `erBodyFaithful` in `ModuleEnv` from a previous build's `.verified.json` sidecar — is what Risk #2's mitigation gestures at, but cold-cache cases (first build, CI fresh checkout, freshly-edited file) hit the same problem.

The grammar inversion's *parse-time* check works fine for the §3.2 whitelist constructs. The §3.4 transitive body-faithful closure is *not* parse-time; it requires verifier state.

**Bite:** medium-high. The implementation cost is real; the architectural seam is non-trivial. The proposal correctly flags this as Risk #2 but the mitigation ("engineer audit confirms") is light.

---

### 3. `?delegate` / `?delegate-async` admission inside `def` re-introduces an asserted-tier path

**Classify:** soundness.

§3.5 admits `?delegate` and `?delegate-async` inside `def` as "delegation intermediates; resolved at agent-loop time; do not erode verification." This is true at the *grammar-admission* level but not at the *trust-closure* level. When `?delegate` resolves to a function whose evidence is `asserted` (which is the common case for delegated work that hasn't been verified yet), the resulting `def`-form call graph contains an `asserted` dependency — the same shape §3.4 was designed to prevent.

The proposal's defense is that `?delegate` is "resolved at agent-loop time" and the resolved value undergoes the normal `EApp` strict-callee check. This is correct if the agent loop re-typechecks after resolution and the `--grammar=core-inversion` enforcement re-runs. If the agent loop merges the resolved delegate result into the AST *without* re-running the strict-callee check (which is how the v0.10 `?delegate` flow works per `compiler/src/LLMLL/Module.hs` and the orchestrator at `tools/llmll-orchestra/`), the inversion's call-closure guarantee silently degrades.

**Bite:** medium. The interaction is fixable — require post-resolution re-typecheck before any `def`-form function with resolved delegates is admitted as verified — but the proposal is silent on the interaction. `?scaffold` has the same shape.

---

### 4. The empirical gate's pass criteria are loose enough to admit a weak win

**Classify:** scope / verification-ergonomics.

§8 pass criteria: at least one of (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts must improve, and no axis regresses materially. "Materially" is `experiment-lead`'s call against the variance baseline.

This is a defensible compromise — pre-committing to a hard threshold would be brittle to the noise floor on `001-two-agent-auth`. But the OR-of-three structure means the inversion can ship with a 1% improvement on `?proof-required` emission rate and unchanged pass rate, declared a "win." The Rust edition decision (rust-lang/rfcs #2052) used a stronger framing — Rust 2018 shipped not because Rust 2015 was demonstrably worse on a single axis, but because the new defaults were *better defaults* on internal coherence grounds, with empirical validation as a sanity check rather than the deciding factor.

The proposal's framing is the inverse: empirical-validation as the deciding factor. This is correct for an architectural bet, but the bar should be commensurately strict. The two-axis "at least one improves, none regresses" bar is the *minimum* defensible bar; a stronger bar would be "at least one of (a)/(b)/(c) improves *and* one of the other two does not regress *and* the boundary-form usage distribution (§8.1 axis 4) shows at least 25% `def` usage in migrated examples."

**Bite:** medium. The looseness means a low-confidence pass is admissible; the rollback paths protect against this but the *default flip* under a low-confidence pass would still ship the inversion as canonical.

---

### 5. The `letrec` exclusion cascades through call-graph inheritance

**Classify:** scope.

§3.3 routes `letrec` to `def-shell` only. §3.4's strict-callee rule then means any `def` body that calls a `letrec`-defined function migrates to `def-shell`. The proposal's edge case #4 demonstrates this cascade but does not quantify it on the corpus.

The `*_verifier` examples avoid `letrec` (their verified contracts are non-recursive QF-LIA). The interactive examples (`hangman_sexp`, `tictactoe_sexp`, `life_sexp`) use `letrec` extensively. Conway's Life's `next-cell` is verifiable per the v0.10 trust report but its containing module uses `letrec` for game-loop iteration, and any `def`-form helper that touches game-loop state migrates to shell.

The proposal's §6 migration is "mechanical" but the *cascade* may produce more `def-shell` migration than the §3.2 grammar production alone would predict. Worth quantifying on the corpus before §8 measurement begins; the boundary-form usage distribution axis (§8.1 axis 4) will measure this post-hoc but a pre-flight count would inform the rollback decision.

**Bite:** medium. Compounds Gap #1.

---

### 6. Keyword choice rationale is weak on the migration ergonomic

**Classify:** ergonomic.

§3.1 chooses rename (`def-logic → def`) over keep-and-add (`def-logic` retained, `def-boundary` added). The rationale — "the agent reading the corpus continues to see `def-logic` as the canonical form" — is correct at the lexical level but understates the migration ergonomic for human readers and for the existing codebase.

The Coq community's migration from `Definition`/`Lemma`/`Theorem` to a single canonical `Definition` has been discussed for ~20 years without resolution precisely because the lexical-canonicity argument cuts both ways: a single canonical keyword forces all functions to *look the same* in source even when they have different verification regimes. The Coq community has settled on multiple keywords for the *meaning-distinguishing* role, with comments and tooling carrying the *canonicity* signal.

LLMLL's choice (Option 2, rename) is defensible because the meaning-distinguishing role is exactly what `def` vs `def-shell` carry. But the proposal should acknowledge that the rename forfeits a *corpus-continuity* signal — agents trained on the v0.10 corpus see `def-logic` and the v0.11 corpus see `def`, and the rename is a discontinuity in the agent-prompt-context distribution.

**Bite:** low. The decision is defensible; the rationale should acknowledge the cost.

---

### 7. Migration tooling intent-disambiguation is genuinely hard, and the conservative-mode default may underpromote

**Classify:** verification-ergonomics.

§6's `--migration-conservative` flag defaults to `def-shell` when ambiguous. The mitigation for Risk #3 (misclassification) is correct in shape but creates the opposite failure mode: every function that is *core-syntactic* but whose author would have wanted shell semantics also gets migrated to `def`, requiring per-file human confirmation. On a corpus of 12 example directories, this is manageable. On a real codebase, the human-confirm cost is the gating concern.

The Rust 2018 edition migration provides the closest precedent. `cargo fix --edition` performed syntactic classification with human confirmation, and the migration was *largely* mechanical but with non-trivial human review (the Async I/O edition migration was the harder case). The honest empirical answer to author Q2 is: yes, the human-confirm requirement is essentially inherent for any nontrivial semantic boundary; the relaxation possible is *flagging the ambiguous cases* (high-precision low-recall classifier) rather than auto-promoting.

**Bite:** low-medium. The proposal's mitigation is correct; the cost is visible but acceptable for v0.11's 12-directory corpus. Worth a sentence acknowledging that the cost scales with the migrated codebase.

---

## Answers to author-surfaced questions

### Q-PROF-1. Closure shape — transitive body-faithful vs relaxed "contract-checked or better"?

The Liquid Haskell, F*, Why3, and Dafny treatments converge on the same answer: **maintain a curated trusted-builtin set, and treat callees in that set as if they were body-faithful for closure purposes.**

- **Liquid Haskell** (Vazou et al., POPL 2014; *LiquidHaskell: Experience with Refinement Types in the Real World*, Haskell '14 §4.3): native primitives are declared via `{-@ assume @-}` or `{-@ measure @-}`; refinement obligations referencing these primitives discharge against the *axiomatized signature*, not against the implementation. The trusted set is small, audited manually, and lives in `Liquid.Prelude.Real`.
- **F\*** (Swamy et al., 2013–present): `assume val foo : ...` declarations are scattered across the standard library; the `Pure` effect requires termination *and* the absence of effect, but the body need not be `Pure`-proven — only the signature is `Pure`-asserted.
- **Why3** (Filliâtre & Paskevich, ESOP 2013 §4): the curated `Why3 prelude` provides axiomatized signatures for `int`, lists, options, etc.; user code reasons against the axiomatized signatures, and the prelude is the verification TCB.
- **Dafny**: built-in functions (`Math.Abs`, sequence operations) are admitted into Dafny's verification as trusted; the verifier reasons against them but does not prove them.

**The strict reading is *unprecedented* among production refinement-typed languages.** No production system requires that every callee in a verified function's call graph be body-faithfully proven — they all maintain a trusted-builtin/-prelude set and admit it into the verified call closure.

**Recommendation:** adopt the relaxed closure with an explicit configured trusted-builtin whitelist. The whitelist lives in `LLMLL.md §13` (the builtin section is already the natural home) with explicit annotations:

```
| Builtin | Body-faithful? | Trust justification |
|---|---|---|
| `+`, `-`, `=`, `<`, `<=`, `>=`, `>`, `!=` | yes (QF-LIA primitive) | direct |
| `*`, `/`, `mod`, `rem` | no | nonlinear arithmetic |
| `string-length`, `string-concat` | trusted | axiomatized in prelude |
| `list-head`, `list-tail` | trusted | partial; axiomatized |
| `sha1`, `hmac-sha1` | NOT admitted in core | crypto stub (per §13.11) |
```

This is a §13 change (within doc-lead's slot once LT-INV settles), not a spec-rule change. The closure-shape question becomes "trusted-prelude-closed" instead of "body-faithful-closed" — a Liquid-Haskell-faithful framing.

The strict reading should be reserved for a `--grammar=strictly-strict-core` mode for use cases where the trusted prelude is itself audited, but not the default.

### Q-PROF-2. Migration scope — syntactic classification vs context-aware intent inference?

The honest answer from the language-migration literature is: **the human-confirm requirement is essentially inherent for any nontrivial semantic-boundary migration; the best the tooling can do is high-precision/low-recall classification of unambiguous cases plus *flagging* of ambiguous ones rather than auto-promotion.**

- **Rust 2018 edition** (rust-lang/rfcs #2052; `cargo fix --edition`): syntactic classifier handles ~85% of cases automatically; the remaining ~15% (mostly module-system and async-related) require human review. The migration was widely considered successful precisely because the tooling did not over-promote.
- **Python 2 → 3** (`2to3`, `lib2to3`): syntactic classifier with manual review; the migration took ~13 years and is still incomplete in the long tail.
- **F\# 4.x → 5.x**: relatively smooth because F\# has *stronger* type inference than Python or pre-2018 Rust; the type checker catches more semantic boundary cases. LLMLL has even stronger types, which suggests a higher automation ceiling than Python's, but still not 100%.
- **ES5 → ES6** (`babel`, `babel-preset-env`): primarily a *transpilation* migration (source-to-source compilation), not a *semantic-mode* migration. Not directly comparable.

The pattern LT-INV §6 already proposes — syntactic classifier + `--migration-conservative` flag + human-confirm — is the canonical pattern. **The only meaningful improvement available is*** to *flag* ambiguous cases for human review rather than default them either way, with a per-file diff showing what the classifier inferred and what it could not infer. This matches `cargo fix --edition`'s `--allow-no-vcs` flow.

**Recommendation:** retain the §6 design. Add a sentence acknowledging that the human-confirm requirement is *essentially inherent* per the precedent literature, and consider exposing the classifier's confidence in the `--migration-conservative` output (e.g., "auto-promoted (confidence: high)" vs "flagged for review (confidence: low — function calls `letrec`-defined helper)") so the human reviewer has a triaged list rather than a flat enumeration.

---

## Cross-proposal observation

LT-INV is the architectural foundation for the v0.11 cluster. LT-CDP measures CDP against the `def` core form (its first-pass scope per LT-CDP §2); LT-PPR is `def-shell`-only per LT-PPR §6.2. Both downstream proposals inherit LT-INV's grammatical boundary; structural revisions to §3.2 (whitelist), §3.4 (callee restriction), or §3.5 (hole admission) cascade.

Specifically:
- If §3.4's strict-callee reading is relaxed per Gap #1 / Q-PROF-1, LT-CDP's `def`-only scope grows (more code stays in `def`); CDP measurements on the v0.11 baseline shift.
- If §3.5's `?proof-required` forbidden-in-`def` rule is relaxed, LT-PPR's §6.2 `def-shell`-only constraint must be relaxed in parallel, and the asserted-tier escape hatch re-enters the core form.

The proposal correctly identifies these dependencies. The cross-proposal recommendation in REF-META-1's review (`refinement-metatheory-of-record-review.md`) carries the broader sequencing observation.

---

## Recommendation

**Approve with revisions.**

The polarity inversion is the right direction. Three revisions are load-bearing:

1. **Adopt the relaxed closure (per Gap #1 / Q-PROF-1).** Replace the strict body-faithful-only callee rule at §3.4 with a curated trusted-prelude-closed rule, and route the trusted-prelude curation to `LLMLL.md §13` as a settled-companion artifact. Without this revision, the inversion's empirical-gate test is testing the wrong hypothesis — it measures the inversion *plus* an unforgiving callee discipline that no production system runs.

2. **Address the typechecker→`EvidenceRecord` coupling (per Gap #2).** Specify the architectural layering: either commit to a two-pass typecheck for `def` admission (and accept the cost), or pre-populate `ModuleEnv` from `.verified.json` sidecars and accept that cold-cache builds may produce conservative-rejection diagnostics requiring a verify-then-build sequence. The current Risk #2 mitigation is too thin.

3. **Tighten the empirical-gate pass criteria (per Gap #4).** Require *at least one of (a)/(b)/(c) improves AND boundary-form usage distribution shows non-trivial `def` usage (≥25% in migrated examples) AND no axis regresses materially*. The current OR-of-three admits a low-confidence pass that would still flip the default.

The remaining gaps (#3 delegate interaction, #5 letrec cascade, #6 keyword rationale, #7 migration ergonomics) are addressable in-prose without structural revision; Rev 2 incorporates them as risk-section enrichments or text-level corrections.

The empirical-validation gate at §8 is the right discipline. Once revisions 1-3 land in Rev 2, the proposal is ready for engineer hand-off behind `--grammar=core-inversion` per the §8.4 sequencing.

---

## Open questions for the language-team

1. **Justify or revise the strict-callee closure shape against the LH / F* / Why3 / Dafny convergence.** The four reference systems all maintain trusted preludes admitted into the verified call closure. LT-INV §3.4's strict reading is unprecedented; either commit to the unprecedented choice with an explicit soundness argument (what does LLMLL gain that LH/F*/Why3/Dafny do not?), or adopt the relaxed closure with a curated trusted-prelude whitelist per Q-PROF-1 above.

2. **Specify the typechecker's access to `erBodyFaithful` precisely.** The proposal says `meContracts` is the seam; `meContracts` does not currently carry `EvidenceRecord`. Either extend `meContracts` (engineer scope; flag in the engineer hand-off) or document the two-pass typecheck cost (current Risk #2 mitigation is light). The architectural layering question matters for the engineer build sequencing and for cold-cache build performance.
