# EXPIRING-INTENTIONAL — Staleness detection for `(spec-entropy :intentional)` via the computed CDP diagnostic

> **Version:** Rev 0.2 — see revision notes.
> **Rev 0.1:** compiler-engineer feasibility folded as Appendix A; central *cost* claim confirmed against source (one constructor + one label + one guard clause).
> **Rev 0.2 (BLOCKED at implementation):** the W614 *predicate itself is unsatisfiable* — it can never fire (proof + empirical confirmation below). Rev 0.1's "build-ready" verdict is **retracted**. All three prior passes (language-team, compiler-engineer, and the parent's own crux check) verified the guard's inputs were computed-and-in-scope but not that the guard was *satisfiable*. No code shipped; implementation reverted.
> **Date:** 2026-07-03
> **Implements:** Successor to [`spec-entropy-reason-string-proposal.md`](spec-entropy-reason-string-proposal.md) (Rev 0.2), per the professor review folded there as Appendix B. Descends from settled `experiments/adv-spec-weaken-0` **F-002**.
> **Origin:** Professor-recommended reallocation of the reason-string's Slice-2 budget. Models Rust `#[expect]` (an *expiring* suppression) on LLMLL's existing CDP machinery.
> **Prerequisites:** None. No new surface syntax, no schema change, no `Contract`-record change — purely a governance diagnostic computed from values `buildWarnings` already produces.
> **Status:** **BLOCKED (Rev 0.2)** — the core predicate is unsatisfiable (below). Reopened as a language-team redesign question, not build-ready. The Restatement/Design/Appendix-A below are preserved as the (flawed) Rev 0.1 record; read the blocking finding first.

---

## ⚠ BLOCKING FINDING (Rev 0.2, found at implementation) — the W614 predicate can never fire

The guard specified throughout (Design §, Appendix A, Routing) —
`annotation == :intentional && isJust (computeScore (length satisfying) distinctAll) && not (identityOk || constOk)` —
**is unsatisfiable.** Proof, from source:

- `isConst` (`CDP.hs:430-431`) is `True` for *every* non-identity trivial body (`isConst (TrivIdentity _) = False; isConst _ = True`). Every `TrivialBody` is `TrivIdentity` or a `TrivConst*`, so for each satisfying candidate exactly one of `isIdentity`/`isConst` holds.
- Hence `identityOk || constOk = any (isIdentity ∨ isConst) satisfying = not (null satisfying) = satCount > 0`.
- But `isJust (computeScore satCount _)` *also* requires `satCount > 0` (`computeScore s _ | s <= 0 = Nothing`, `CDP.hs:414`).
- So the guard reduces to `… && satCount > 0 && satCount == 0` — **always False.**

**Empirically confirmed** (two diagnostic tests, both green, then reverted with the rest of the implementation): `:intentional` + loose (every trivial body satisfies) → score `Just 0.0` but W614 absent (`constOk` true); `:intentional` + tightened (nothing satisfies) → score `Nothing` so W614 absent — the state fires `spec-inconsistent-or-unproven` instead. W614 is dead code.

**Why every prior pass missed it:** language-team (author), compiler-engineer (feasibility), and the parent's own "crux" verification all confirmed `identityOk`/`constOk` were *computed and in scope* — none checked the predicate was *satisfiable*. The `isConst`-matches-all-non-identity collapse is invisible at the values-in-scope level.

**What the real "stale" state actually is.** In this CDP model, "no trivial body satisfies the post" ⟺ `satCount = 0` ⟺ the `inconsistent` branch — which already emits `WarnSpecTooTightForOmega` (verified) or `WarnSpecInconsistentOrUnproven` (not), *ungated by the annotation*, and which the proposal's own **decision 2 explicitly excluded** ("null-score → don't fire"). Consequences for any redesign:
- A stale `:intentional` (tightened until no trivial body passes, verified) **already** emits `spec-too-tight-for-omega` next to `spec_entropy_annotation: intentional` — the staleness is *already inferable* from the two emitted fields.
- A corrected predicate would be `:intentional && inconsistent && functionVerifies` — but that **reverses decision 2**, **co-fires with** `WarnSpecTooTightForOmega`, and only catches the *fully-tightened, verified* endpoint (at intermediate tightening the annotation still suppresses a real identity/const warning, so it is genuinely *not* stale).
- Net: on contact with the actual model, "expiring `:intentional`" largely collapses into "read `spec_entropy_annotation` + the existing too-tight warning." Whether the narrowed, mostly-already-inferable signal earns a new warning is a **language-team redesign question** (reverse decision 2? new label vs. annotating the existing warning? is the value worth it at all?), possibly a professor turn (the value is now as thin as the reason-string's was). Reopened, not build-ready. **No code shipped.**

---

## Restatement (Rev 0.1 — preserved; superseded by the blocking finding above)

Detect a `(spec-entropy :intentional)` annotation that has gone **stale** — i.e., the low-DP diagnostic it suppresses would no longer fire, because the spec was later tightened or Ω changed so that no trivial candidate satisfies the post anymore. The annotation is then suppressing nothing; it is dead weight that should be flagged for removal. This is the LLMLL instance of Rust's `#[expect]` (a suppression that warns when the expectation is unfulfilled) and a direct counter to the accumulation failure mode the professor review's FSE 2025 anchor documents (50.8% of suppressions affect no warning; suppression counts grow monotonically).

**Scope boundary, load-bearing.** This does **not** reopen or close F-002's laundering (weaken-the-spec-then-mark-`:intentional`). A laundered contract has a *genuinely* low DP — a trivial candidate really does satisfy its weakened post — so the annotation reads as justified and this mechanism correctly stays silent. F-002 remains settled-as-designed. What this catches is the orthogonal, automatable case: a suppression that is *provably doing nothing under the current Ω*. The value comes precisely from the DP signal being **computed, not declared** — it sidesteps the self-attestation oracle barrier (CDP proposal §10 Risk #3 Rev 2; professor Gap #5) that makes F-002 unclosable, because no agent declaration is trusted.

## Context located

1. `compiler/src/LLMLL/CDP.hs:386-403` — `buildWarnings`. Computes `identityOk`, `constOk`, `inconsistent`, `narrow` **unconditionally** (lines 387-390); `raises = raiseLowDP annotation` (line 397) gates *only* whether `WarnIdentitySatisfiesPost`/`WarnConstSatisfiesPost` are emitted (lines 399-400). The permissiveness signal an `:intentional` excuses is exactly `identityOk || constOk` — an identity or const trivial body satisfies the post — and it is already in scope at the emit site regardless of annotation.
2. `compiler/src/LLMLL/CDP.hs:412-418` — `computeScore`: `Nothing` when `|B| ≤ 1` (enumeration-too-narrow) or `satCount ≤ 0` (zero-satisfying); `Just` otherwise. This is the clean gate for "a real DP number exists" used in decision 2.
3. `compiler/src/LLMLL/Syntax.hs:362-364` — `raiseLowDP`: `:strict → True`, `:intentional`/`:unknown → False`. The suppression gate; unchanged by this proposal. The expiry predicate is definitionally the negation of the diagnostic this gate suppresses.
4. `LLMLL.md §4.4.6:661-694` — the DP score, the closed `Ω`, the `(spec-entropy …)` annotation, the zero-satisfying split (`spec-too-tight-for-omega` / `spec-inconsistent-or-unproven`, lines 667), the `basis` field recording Ω identity for auditability (line 669).
5. [`spec-entropy-reason-string-proposal.md`](spec-entropy-reason-string-proposal.md) Rev 0.2 + Appendix B — the professor review that recommended this mechanism; its W610–W613 governance block (numbering coordination, decision 4).
6. `docs/compiler-team-roadmap.md` (LT-CDP research-track row) — the tracked "contract discriminative power" concept this *anticipates*-by-extension (a governance addition to CDP, not a new axis).

**No spec/code drift found.** `LLMLL.md §4.4.6`, `CDP.hs:buildWarnings`, and `Syntax.hs:raiseLowDP` agree that `:intentional` suppresses the identity/const-satisfies-post diagnostic and nothing else. This proposal rests on that agreement.

**Freeze check.** The v0.8.1a–v0.10 freeze (`docs/compiler-team-roadmap.md:26-31`) has expired, and this introduces no construct, builtin, FFI tier, or syntax — only a governance diagnostic. Outside the freeze's ban even were it active.

## Design proposal

No surface syntax. No schema delta. The mechanism is a single governance diagnostic added to `buildWarnings`.

### Semantics — the expiry predicate

For a contracted function carrying `(spec-entropy :intentional)`, emit **W614 (`intentional-annotation-stale`)** iff:

```
annotation ≡ :intentional
  ∧  computeScore satCount totalCount ≡ Just _      -- a real DP number exists
  ∧  ¬ (identityOk ∨ constOk)                        -- no trivial candidate satisfies the post
```

In words: the annotation excuses a permissiveness (a trivial body satisfying the post) that, under the current Ω, no longer exists. The suppression suppresses nothing — it is stale. The predicate reuses `identityOk`/`constOk` (CDP.hs:387-388) and `computeScore` (CDP.hs:412-418) verbatim; nothing new is computed.

The "no-longer-low-DP floor" (the reason-string review's open question) is therefore **not a new numeric threshold** — it is the exact negation of the `raiseLowDP`-gated diagnostic condition. W614 fires precisely when `WarnIdentitySatisfiesPost`/`WarnConstSatisfiesPost` *would not* have fired even absent the annotation. This ties the expiry to `raiseLowDP`'s own semantics with zero new tunable state, which is the decisive reason to prefer it over a configurable score floor (decision 1).

### Governance surface

W614 is a **non-blocking `SevWarning`** advisory, emitted on the same CDP report path as the existing `CDPWarning` values and rendered in both text and `--json` (F-001 machine-readability parity). Optionally (decision 4), the per-function `discriminative_axis` block carries an additive boolean `intentional_stale`, so a CI consumer can gate without string-matching the diagnostic — additive, **no `trust_report_version` bump** (the `over_annotation`/`joint_pbt_witnesses` precedent).

## Decisions and recommendations

**1. Expiry floor: negation-of-diagnostic, not a numeric score threshold.** **Recommend the predicate above.** A numeric floor (`score > k`) would add a tunable an adversary games and a constant the team must justify; the negation-of-diagnostic form inherits `raiseLowDP`'s already-settled semantics and is exact ("suppresses nothing"). The DP *number* is used only through `computeScore ≡ Just _` as the existence gate (decision 2), never as a magnitude threshold.

**2. Null-score / zero-satisfying states: indeterminate — do not fire.** **Recommend W614 stays silent when `computeScore` is `Nothing`** (i.e., `inconsistent` or `narrow`, CDP.hs:413-414). Justification: when `Ω` yields no measurable DP, a "DP-staleness" verdict is not well-founded — the observation set cannot see the quantity the claim is about. Both zero-satisfying sub-states already carry their own **ungated** diagnostic (`WarnSpecTooTightForOmega` / `WarnSpecInconsistentOrUnproven`, CDP.hs:401), which fires regardless of annotation and is the appropriate signal that "the spec is tight / suspect here." Firing W614 on top would be exactly the redundant-suppression noise the FSE evidence warns against. A too-tight-for-Ω spec under an `:intentional` is thus flagged by the *existing* diagnostic, not double-flagged by W614.

**3. Ω-stability: current-run only; auditability via the existing `basis` field.** **Recommend no stored-basis comparison.** W614 is recomputed each run against the current Ω, and the `discriminative_axis.basis` field (§4.4.6:669) already records which Ω produced the verdict. Cross-version expiry ("was non-stale under last release's Ω, stale now") would require persisting prior baselines the pipeline does not keep, and would import the same-Ω-discipline hazard §4.4.6 already documents. The observational-relativity caveat carries over verbatim: a wider Ω (v0.12+ candidate widening, §4.3.1) has *more* trivial candidates, so is *less* likely to fire W614 — this is disclosed, not a defect.

**4. Governance code: W614, coordinated with the reason-string W61x block.** The spec-entropy governance family is W61x (the reason-string proposal claims W610–W613). W614 is the next free code. If the reason-string proposal does not ship (decision 5), W614 renumbers to W610 as the first spec-entropy governance code. Non-blocking, JSON-visible, distinct from the module-level `over-annotation-warning` (which is a ratio signal, not per-instance) — the two must not be conflated in output.

**5. Relationship to the reason-string proposal: supersede.** **Recommend the expiring mechanism replaces the reason-string as the primary F-002 follow-on.** It dominates on both axes:
   - *Value.* It is automatable (a computed W-code, no free-text quality problem), it is not self-attestation (the DP is computed, not declared), and it attacks the accumulation failure mode the FSE study identifies as the real cost — none of which the reason-string can do (a reason is self-attested free text that clears any non-emptiness check).
   - *Cost.* It is a **strictly smaller** change: no grammar change, no schema change, no `Contract`-record field, and therefore **none of the ~8-site positional-constructor fan-out** the reason-string's Slice-1 requires (Appendix A of that proposal). It is one predicate clause in `buildWarnings` plus one `CDPWarning` constructor.

   The reason-string's *residual* value is a human-readable justification artifact, and its worth is gated on the professor's open question 2: **is there a committed machine consumer of `spec_entropy_reason`?** There is none today — the trust report *surfaces* the string but no scorer reads it. Recommendation: **ship EXPIRING-INTENTIONAL; defer the reason-string** unless and until a machine consumer of the reason is committed. The two are not mutually exclusive (both are advisory governance and could coexist), but if only one ships, it should be this one.

## Edge cases and degenerate inputs

| # | Input shape | Expected behavior | Channel | Cite |
|---|---|---|---|---|
| 1 | `:intentional` on a genuinely permissive post (`(>= result 0)`; a const `0` body satisfies) — the F-002 laundered shape | **W614 does not fire** — `constOk` is true, the annotation is justified by the numbers. F-002 stays settled. | spec is silent (intentional) | `CDP.hs:388` `constOk`; F-002 |
| 2 | `:intentional` on a spec later tightened to be discriminative (real score, no trivial body satisfies) | **W614 fires** — stale suppression | trust (advisory) | `CDP.hs:387-388`; predicate above |
| 3 | `:intentional` on a spec so tight no candidate satisfies (`score: null`, `spec-too-tight-for-omega`) | **W614 does not fire**; `WarnSpecTooTightForOmega` fires instead (existing, ungated) | trust (existing diagnostic) | `CDP.hs:401,414`; decision 2 |
| 4 | `:unknown` on a discriminative spec | **W614 does not fire** — `:unknown` is spec-in-flux, makes no positive permissiveness claim to be stale (parallels the reason-string's `:unknown` treatment) | spec is silent (intentional) | `§4.4.6:690`; decision 5 |
| 5 | Ω widens between runs (v0.12+), a formerly-stale annotation gains a trivial satisfier | W614 stops firing under the wider Ω; verdict is Ω-relative and the `basis` field records which Ω | trust (observational-relativity) | `§4.4.6:669`; `§4.3.1`; decision 3 |

## Verification mapping

**No new proof obligation.** W614 is a governance diagnostic computed from `identityOk`/`constOk`/`computeScore` — values `buildWarnings` already produces from the completed candidate sweep. Nothing is emitted to liquid-fixpoint; the `Σ_auto` boundary (`LLMLL.md §5.3.3`) and the QF-LIA / nonlinear / Lean partition (`§5.3.5`) are untouched. Fragment classification is **N/A** — there is no obligation to classify. **Channel: trust; Fragment: none.**

## Three-channel / trust mapping

A **trust-channel advisory with zero soundness impact.** It changes nothing about *what verifies*: the diamond-lattice evidence level, the VC (contract) channel, the type channel, `raiseLowDP`'s suppression semantics, and the module over-annotation ratio are all unchanged. It adds one governance signal (W614) computed over the existing CDP observation. Strict immutability is untouched (no state, no construct). It does not reopen F-002 (edge case 1); it is orthogonal defense against suppression *staleness*, a different failure mode than laundering.

## Affected surface

*Not an implementation plan — the seam where `compiler-engineer` takes over.*

- `compiler/src/LLMLL/CDP.hs:386-403` — one clause in `buildWarnings`'s `concat` list; a new `CDPWarning` constructor (`WarnIntentionalStale`). The predicate's inputs are already bound at this site.
- `compiler/src/LLMLL/CDP.hs:173-183` — `cdpWarningLabel`, the **single** per-constructor render site (11 equations, no wildcard); add `cdpWarningLabel WarnIntentionalStale = "intentional-annotation-stale"`. `TrustReport.hs` (`:1359/:1380/:1383`) and `Main.hs:1505` render warnings opaquely via `map cdpWarningLabel`, so this one equation covers both `--json` (warnings array + headline) and text (Appendix A).
- `compiler/src/LLMLL/TrustReport.hs` — *optional* additive `intentional_stale` boolean on the `discriminative_axis` block (decision 4); no `trust_report_version` bump.
- **Doc-lead's slot (after the engineer ships):** `LLMLL.md §4.4.6` (document the expiry semantics in the `:intentional` bullet + the W614 governance code), `docs/compiler-team-roadmap.md` (LT-CDP row / CHANGELOG).
- **No change to:** `docs/llmll-ast.schema.json`, `Syntax.hs` `Contract`, `Parser.hs`, `ParserJSON.hs`, `AstEmit.hs`. This is the cost asymmetry versus the reason-string (decision 5).

## Risks and open questions

1. **The staleness verdict is Ω-relative.** Classify: verification-ergonomics / scope. Cite: `§4.4.6:661,669`. Bite: only matters when Ω changes between runs; the `basis` field discloses it, and the relativity is identical to the DP score the mechanism reads. Complicates cross-version reading, does not block.
2. **Does not catch F-002 laundering — by design.** Classify: scope. Cite: edge case 1; F-002 settled. Bite: a reader may expect an "intentional-abuse detector" to catch laundering; it does not, because a laundered spec is genuinely low-DP. This must be stated in the doc so the mechanism is not oversold (the same honesty discipline the reason-string proposal holds).
3. **`CDPWarning` constructor exhaustiveness.** Classify: build (engineer). Cite: `CDP.hs:173-183`; `package.yaml:9-16`. **Correction (Appendix A):** a missing label case is *not* compiler-caught — `-Wincomplete-patterns` is not enabled (only `-Wincomplete-uni-patterns`/`-record-updates` are), so it would be a runtime `Non-exhaustive patterns` exception, not a build failure. Bite: still low — `cdpWarningLabel` is the single match site with no wildcard, so the omission is loud (crashes the first render test), not a silent mislabel. Mitigation: add the label equation in the same commit as the constructor + a render test; optionally add `-Wincomplete-patterns` as one-line hardening (verify it surfaces no pre-existing gaps first).
4. **W61x numbering coordination.** Classify: spec-drift / DX. Cite: reason-string proposal W610–W613. Bite: minor; resolved by decision 4 (W614, or W610 if reason-string is dropped).
5. **Marginal noise if `:intentional` is used for a genuinely tight spec deliberately.** Classify: verification-ergonomics. Bite: low — a `:intentional` on a discriminative spec *is* the stale case W614 is meant to surface; the author's recourse is to drop the now-pointless annotation, which is the intended nudge. Not a false positive.

## Open questions for the professor

*(None required to adjudicate.)* The professor review (Appendix B of the reason-string proposal) already supplied the outside-PL grounding — the Rust `#[expect]` model, the FSE 2025 accumulation evidence, and the "computed-not-declared escapes the oracle barrier" argument. This proposal operationalizes that recommendation within LLMLL's existing surface; no new external question is open. If the user later reconsiders decision 5 (coexist rather than supersede), the one live empirical question — whether a machine consumer of `spec_entropy_reason` will be built — is a product decision, not a professor question.

---

**Hand-off (Rev 0 → user adjudication).** This is a fresh proposal recommending it *supersede* the reason-string as the F-002 follow-on. If the user approves the direction, the **code-track hand-off to `compiler-engineer`** is: add `WarnIntentionalStale` to the `CDPWarning` sum and one predicate clause to `buildWarnings` (`CDP.hs:386-403`) gated on `annotation ≡ :intentional ∧ computeScore ≡ Just _ ∧ ¬(identityOk ∨ constOk)`; add the one `cdpWarningLabel` equation (CDP.hs:173-183) which covers text + JSON; optionally add the additive `intentional_stale` boolean to `discriminative_axis` (`TrustReport.hs`, no version bump — recommended by the engineer so CI gates on a boolean rather than string-matching). Feasibility (answered, Appendix A): the score/`identityOk`/`constOk` triple is in scope at the single emit site (CDP.hs:386-388 ✓); `CDPWarning` is *not* compiler-enforced-exhaustive (no `-Wincomplete-patterns`), but `cdpWarningLabel` is the single wildcard-free render choke point, so the one label equation is the whole render change. No parser, schema, or `Contract`-record change. `documentation-lead` follows after the engineer ships (`LLMLL.md §4.4.6` + the W614 code).

---

## Appendix A — Compiler-engineer feasibility read

*Folded 2026-07-03. Anchors verified against source; the one correction (exhaustiveness) is also applied inline above.*

**Verdict: build-ready. The central cost claim holds.** The change is one `CDPWarning` constructor (`WarnIntentionalStale`, `CDP.hs:113-170` — a 12th on an 11-constructor sum), one `cdpWarningLabel` equation (`CDP.hs:173-183` → `"intentional-annotation-stale"`), and one guard element in `buildWarnings`'s `concat` (`CDP.hs:398-403`):

```haskell
[WarnIntentionalStale | annotation == SpecEntropyIntentional
                        && isJust (computeScore (length satisfying) distinctAll)
                        && not (identityOk || constOk)]
```

Everything the guard reads is already bound at that site. No grammar, schema, parser, `ParserJSON`, `AstEmit`, or `Contract`-record change — none of the reason-string's ~8-site fan-out. Rebuild is `CDP.hs` + its importers (`TrustReport.hs`, `Main.hs`, `Spec.hs`), a partial rebuild, not the `Syntax.hs`-wide recompile the reason-string forced.

**The render surface is free.** `TrustReport.hs:1359/1380/1383` and `Main.hs:1505` both reach CDP warnings only through `map cdpWarningLabel` — they treat warnings as opaque. So the single label equation propagates to `--json` (warnings array + headline) and text with no further edits.

**The one correction (risk 3, applied above).** The proposal assumed a new constructor forces GHC completeness errors at every consumer. It does not: `package.yaml:9-16` enables `-Wincomplete-uni-patterns` and `-Wincomplete-record-updates` but **not `-Wincomplete-patterns`**, so a missing `cdpWarningLabel` case is a runtime `Non-exhaustive patterns` exception, not a build failure. Low bite because `cdpWarningLabel` is the *only* per-constructor match site and has no wildcard — the omission crashes the first render test rather than silently mislabelling. Mitigate by updating the label in the same commit + a render test; optional one-line hardening is adding `-Wincomplete-patterns` (check for pre-existing gaps first).

**Design confirms / recommendations:**
- **Ship decision-4's additive `intentional_stale` boolean** on `discriminative_axis` (no `trust_report_version` bump — `over_annotation` precedent) — a CI consumer gating on a boolean beats string-matching the warnings array.
- **Headline capture (confirm intended):** when W614 fires it is the sole score-warning (its `computeScore≡Just ∧ ¬narrow ∧ ¬inconsistent` guard is mutually exclusive with the identity/const/tight/narrow warnings), so it becomes the trust-report `headline` (`TrustReport.hs:1383`). Arguably correct — staleness is the salient fact — but it changes the headline for an otherwise-clean function; a headline-asserting test would flag it.
- **`def-shell` / `--cdp`-absent are auto-excluded** by the `computeScore ≡ Just _` gate (both yield `Nothing`) — decision 2 is self-enforcing at the guard, no special-casing.

**Verification impact: none.** Trust channel, no fragment, no VC, no liquid-fixpoint, no `.fq` — a `Bool` conjunction over already-computed values. Non-blocking by construction (CDP warnings carry no severity/exit-code gate).

**Test plan:** +6 Haskell (clone `C23`–`C25`, `Spec.hs:8851-8879`): W614 fires (`:intentional` + discriminative post — needs one new tightened-spec fixture); quiet on the F-002 laundered/loose shape (reuse `cdp/intentional.llmll` — the test that proves F-002 isn't reopened); quiet on `:strict`, `:unknown`, null-score/too-tight, and no-annotation. +0 Python. **Baseline-count flag (raised twice now, independently):** the gate cites `README.md:7` "570 H + 37 Py" but `roadmap:226` cites **1019 H + 45 Py** — a stale-README drift to confirm with `stack test`, doc-lead's to fix.

**Effort:** trivial (~half-day incl. tests). **Rollback:** single revert; additive constructor + guard + label; no schema pin, no cache/`.fq` migration. **Professor questions:** none — buildability, not soundness.
