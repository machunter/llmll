# EXPIRING-INTENTIONAL — Staleness detection for `(spec-entropy :intentional)` via the computed CDP diagnostic

> **Version:** Rev 0 — initial proposal.
> **Date:** 2026-07-03
> **Implements:** Successor to [`spec-entropy-reason-string-proposal.md`](spec-entropy-reason-string-proposal.md) (Rev 0.2), per the professor review folded there as Appendix B. Descends from settled `experiments/adv-spec-weaken-0` **F-002**.
> **Origin:** Professor-recommended reallocation of the reason-string's Slice-2 budget. Models Rust `#[expect]` (an *expiring* suppression) on LLMLL's existing CDP machinery.
> **Prerequisites:** None. No new surface syntax, no schema change, no `Contract`-record change — purely a governance diagnostic computed from values `buildWarnings` already produces.
> **Status:** Proposed (Rev 0) — awaiting user adjudication. Recommended to **supersede** the reason-string as the primary F-002 follow-on (dominates on value *and* cost; see decision 5).

---

## Restatement

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
- The `CDPWarning` → text/JSON render path (wherever the existing constructors are rendered) — add the W614 rendering; **exhaustiveness check is the engineer's feasibility question** (risk 4).
- `compiler/src/LLMLL/TrustReport.hs` — *optional* additive `intentional_stale` boolean on the `discriminative_axis` block (decision 4); no `trust_report_version` bump.
- **Doc-lead's slot (after the engineer ships):** `LLMLL.md §4.4.6` (document the expiry semantics in the `:intentional` bullet + the W614 governance code), `docs/compiler-team-roadmap.md` (LT-CDP row / CHANGELOG).
- **No change to:** `docs/llmll-ast.schema.json`, `Syntax.hs` `Contract`, `Parser.hs`, `ParserJSON.hs`, `AstEmit.hs`. This is the cost asymmetry versus the reason-string (decision 5).

## Risks and open questions

1. **The staleness verdict is Ω-relative.** Classify: verification-ergonomics / scope. Cite: `§4.4.6:661,669`. Bite: only matters when Ω changes between runs; the `basis` field discloses it, and the relativity is identical to the DP score the mechanism reads. Complicates cross-version reading, does not block.
2. **Does not catch F-002 laundering — by design.** Classify: scope. Cite: edge case 1; F-002 settled. Bite: a reader may expect an "intentional-abuse detector" to catch laundering; it does not, because a laundered spec is genuinely low-DP. This must be stated in the doc so the mechanism is not oversold (the same honesty discipline the reason-string proposal holds).
3. **`CDPWarning` constructor exhaustiveness.** Classify: scope (engineer). Cite: `CDP.hs:386` + render sites. Bite: small, mechanical — adding a constructor forces GHC pattern-completeness errors at every consumer, which is discoverable and safe; route to engineer.
4. **W61x numbering coordination.** Classify: spec-drift / DX. Cite: reason-string proposal W610–W613. Bite: minor; resolved by decision 4 (W614, or W610 if reason-string is dropped).
5. **Marginal noise if `:intentional` is used for a genuinely tight spec deliberately.** Classify: verification-ergonomics. Bite: low — a `:intentional` on a discriminative spec *is* the stale case W614 is meant to surface; the author's recourse is to drop the now-pointless annotation, which is the intended nudge. Not a false positive.

## Open questions for the professor

*(None required to adjudicate.)* The professor review (Appendix B of the reason-string proposal) already supplied the outside-PL grounding — the Rust `#[expect]` model, the FSE 2025 accumulation evidence, and the "computed-not-declared escapes the oracle barrier" argument. This proposal operationalizes that recommendation within LLMLL's existing surface; no new external question is open. If the user later reconsiders decision 5 (coexist rather than supersede), the one live empirical question — whether a machine consumer of `spec_entropy_reason` will be built — is a product decision, not a professor question.

---

**Hand-off (Rev 0 → user adjudication).** This is a fresh proposal recommending it *supersede* the reason-string as the F-002 follow-on. If the user approves the direction, the **code-track hand-off to `compiler-engineer`** is: add `WarnIntentionalStale` to the `CDPWarning` sum and one predicate clause to `buildWarnings` (`CDP.hs:386-403`) gated on `annotation ≡ :intentional ∧ computeScore ≡ Just _ ∧ ¬(identityOk ∨ constOk)`; render W614 on the existing CDP text/JSON path; optionally add the additive `intentional_stale` boolean to `discriminative_axis` (`TrustReport.hs`, no version bump). Feasibility question for the engineer: is `CDPWarning` consumed exhaustively so the new constructor is compiler-caught at every render site, and is the score/`identityOk`/`constOk` triple in scope at the single emit site (CDP.hs:386-388 says yes)? No parser, schema, or `Contract`-record change. `documentation-lead` follows after the engineer ships (`LLMLL.md §4.4.6` + the W614 code).
