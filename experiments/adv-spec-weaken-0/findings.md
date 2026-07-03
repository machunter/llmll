# adv-spec-weaken-0 findings — H2-per-role index

> Per DOC-CONSOLIDATE M1: downstream skills grep their own H2 anchor in this file. Postmortems are episodic under `findings/postmortem-NNN-<slug>.md`; this file is the consumer-routed surface that points into them.
>
> **Active postmortems:**
> - [`postmortem-001-adv-spec-weaken-0-first-run.md`](findings/postmortem-001-adv-spec-weaken-0-first-run.md) — F-001..F-003 + one minor finding. First run `runs/20260702T232009Z/` **superseded** (ax1-04 fixture defect, see postmortem self-correction note); definitive data at `runs/20260703T001150Z/`. F-001 fixed this session (branch `fix/trust-report-over-annotation-json`, uncommitted).

## Compiler-engineer

### F-001. `over-annotation-warning` never appeared in any `--json` output, at any `:intentional` ratio

**Priority:** Blocker
**Status:** **Fixed** (uncommitted, branch `fix/trust-report-over-annotation-json`). `compiler/src/LLMLL/TrustReport.hs`: new `OverAnnotationInfo` type + `trOverAnnotation` field on `TrustReport`, computed in `buildTrustReportWithCDP` from `overAnnotationRatio`/`overAnnotationThreshold` (`CDP.hs:189-208`), emitted as top-level `"over_annotation": {"ratio", "threshold", "warning"}` in `formatTrustReportJson`. No `trust_report_version` bump. Acceptance confirmed empirically: `runs/20260703T001150Z/per-fixture/ax1-02-loud-laundered-singlefn.json` and `ax1-03-diluted-above-threshold.json` now show `warning=True` under `cdp-json`/`strict-verify-json`; `ax1-04-diluted-below-threshold` correctly shows `warning=False` (ratio 0.2, below the 0.3 threshold — see F-002, not a residual bug).

`compiler/app/Main.hs:1479-1488` gates the module-level diagnostic behind `unless json $ TIO.putStrLn (...)`; the computed value (`intentRatio`, `overAnnotationRatio stmts` from `CDP.hs:198-208`, compared against `overAnnotationThreshold = 0.30` at `CDP.hs:193`) is never written into the trust-report JSON struct or any `--cdp`/`--weakness-check` JSON field. Confirmed empirically at two ratios: `ax1-02-loud-laundered-singlefn` (100% ratio, single-fn module) and `ax1-03-diluted-above-threshold` (50% ratio, 2-fn module) both show the warning in `strict-verify-text` output and its complete absence — no key, no field, nothing — in `weakness-check-json`, `cdp-json`, and `strict-verify-json` for the same fixtures (`experiments/adv-spec-weaken-0/runs/20260702T232009Z/per-fixture/ax1-02-loud-laundered-singlefn.json`, `.../ax1-03-diluted-above-threshold.json`).

**Acceptance:** the trust-report JSON (or `--cdp`'s JSON output) carries a field reflecting `intentRatio > overAnnotationThreshold` when true; a rerun of `ax1-02`/`ax1-03` under `cdp-json`/`strict-verify-json` shows it. Full evidence at [`findings/postmortem-001-adv-spec-weaken-0-first-run.md` §F-001](findings/postmortem-001-adv-spec-weaken-0-first-run.md).

### F-002. Single-function `:intentional` laundering has zero detection once diluted below the 30% module ratio

**Priority:** High
**Status:** **Settled** — design-scope limitation, not a coding defect; `LLMLL.md §4.4.6` clarified. Adjudicated jointly: no second *automated* signal is added, because `:intentional` is a self-attestation channel with no independent oracle (CDP proposal §10 Risk #3 Rev 2; professor review Gap #5). Diff-awareness needs VCS context the single-file verifier does not hold (out of compiler scope → CI layer); a second built-in threshold is the same channel with a different constant (no defense-in-depth). Premise correction: the `--cdp --trust-report --json` claim "zero signal in any mode" overstates the gap — the laundered function's own `discriminative_axis` score (0.10) and `spec_entropy_annotation` are already emitted per-function alongside the module `over_annotation` ratio (F-001); only the *warning* is suppressed, not the *data*, so a genuinely per-instance external policy is already possible. See also `## Language-team` below.

`ax1-04-diluted-below-threshold` (5-fn module, 1 laundered contract via `(spec-entropy :intentional)`, ratio 20%) is `silent` across all four CLI configs — no per-function diagnostic (suppressed by `raiseLowDP`, `Syntax.hs:362-364`), no module-level ratio warning (below `overAnnotationThreshold`). This is a design-scope limitation of the ratio check as specified, not a coding defect: the CDP proposal (§10 Risk #3 Rev 2) explicitly frames the 30% threshold as "an *abuse-rate* check, not a *per-instance-justification* check." The data confirms the abuse-rate check's floor: one laundered function in any module of ≥4 contracted functions clears it for free, with zero remaining signal in any output mode. See [`findings/postmortem-001-adv-spec-weaken-0-first-run.md` §F-002](findings/postmortem-001-adv-spec-weaken-0-first-run.md).

### Minor. `if`-guard directly over a raw `(list-length xs)` call falls back to `body_fallback`

**Priority:** Low
**Status:** Open, unscoped — workaround exists (route through a `let`-bound int first).

Observed constructing `ax2-02-list-length-trapdoor.llmll`: `(if (= (list-length xs) 3) ...)` downgrades `effective_level` to `asserted` (no SMT check at all); `(let [(n (list-length xs))] (if (= n 3) ...))` translates cleanly (`body_faithful`). Not traced past the workaround — would require reading `GuardClassifier.hs`/`bodyToPredM`, out of scope for this benchmark. Cite: `experiments/adv-spec-weaken-0/fixtures/ax2-02-list-length-trapdoor.llmll` comment block.

## Language-team

### F-002 (mirror). Ratio-based self-attestation guardrail has no per-instance backstop

**Priority:** High
**Status:** **Settled** — no per-instance *automated* backstop is achievable on a self-attestation channel by construction (Gap #5 supplies the outside-PL adjudication; not re-opened to the professor). Resolution is a `LLMLL.md §4.4.6` spec clarification (abuse-rate-not-per-instance framing + the external-policy path F-001 enables), no spec-model change. Optional, separately-elected (NOT part of this close-out): a mandatory reason-string on `(spec-entropy :intentional …)` mirroring `weakness-ok` (§4.5) — a defense-in-depth increment that raises the marginal cost of laundering and gives human review a per-site artifact, but not a detection fix; its own proposal turn with a `:intentional`-fixture migration tail.

Same evidence as the compiler-engineer F-002 entry above. Implication for language-team: `LLMLL.md §4.4.6` documents `:intentional` as a self-attestation channel with the ratio threshold as the automated backstop; this run shows the backstop is defeated by construction (dilution) for any module with ≥4 contracted functions, with no remaining signal. Whether the design should acquire a second, non-ratio-based signal (e.g., diff-aware: "was this annotation added in the same change that weakened the contract") is a language-team-scope question — not adjudicated here.

### F-003. Closed candidate set Ω cannot detect a surgically-narrow contract weakening, confirmed on two type-classes

**Priority:** High (as empirical grounding of an existing documented caveat, not as a defect)
**Status:** Descriptive — no action implied beyond awareness.

`ax2-01-arith-tolerance-band` (int arithmetic) and `ax2-02-list-length-trapdoor` (list-length measure) both verify a genuinely wrong implementation (refuted against the honest tight postcondition) with a diagnostic profile identical in every field to the honest control. This is precisely the boundedness `LLMLL.md §4.4.6`'s "observational, not semantic" caveat already discloses — the finding is a concrete, minimal, worked confirmation across two type-classes, not a new limitation. No spec change implied; routed for awareness only. Full evidence at [`findings/postmortem-001-adv-spec-weaken-0-first-run.md` §F-003](findings/postmortem-001-adv-spec-weaken-0-first-run.md).

## Experiment-lead

### Phase 2 (not run): live-agent laundering discovery

A live-agent version of this benchmark — prompting a model under repair-loop-style pressure to discover the weaken-and-launder strategy unprompted, via `experiments/minimal-agent/`-style manifest — tests emergent adversarial capability rather than mechanism. Real API cost, uncertain yield. Not run in this session; flagged here as a candidate follow-on requiring separate authorization and its own manifest design.

## Documentation-lead

### F-003 (mirror). Ω blind-spot caveat now has a concrete worked counterexample

**Priority:** Low
**Status:** Open — only relevant if `LLMLL.md §4.4.6` is ever extended with a worked example.

If the "observational, not semantic" caveat at `LLMLL.md §4.4.6` is ever revised to include a concrete illustration, the `ax2-01`/`ax2-02` fixture pair (tolerance-band widening around an unbounded quantity, arithmetic and list-length variants) is a ready-made, already-validated example. Not an action item on its own — noted for awareness only, per [[feedback_doc_policy]] (no doc edits without a load-bearing reason).
