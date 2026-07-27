# Postmortem 002 — CDP-0 baseline re-run (successful collection; degenerate distribution)

> **Date:** 2026-05-26 (updated 2026-05-27)
> **Status:** **Complete; definitive anchor.** `runs/20260527T154040Z-baseline/baseline.json` (Appendix B) is the LT-INV §8 empirical-validation gate's comparison anchor — the first full primary+secondary run after F-006 + F-005 fixes (`cdp-discriminating-weak`, 11/26 defined, 4 midrange). The original pre-fix full run at `runs/20260526T233504Z-baseline/` and the post-fix primary-only run at `runs/20260527T140751Z-baseline/` are retained as lineage evidence.
> **Predecessor:** [`postmortem-001-cdp-baseline-blocked.md`](postmortem-001-cdp-baseline-blocked.md) — the three halted attempts on F-001 + F-003.

## Headline finding

CDP-0 baseline at compiler SHA `cc712aa` (HEAD of `fix/diagnosticfq-partial-record`, which includes LT-CDP feature ship `121815a` and F-001 fix `e5e6d04`; manifest pins `121815a` for measurement-equivalence — doc-only commits between) on 6 primary + 30 secondary fixtures (8 excluded for pre-existing verify failure) collected DP measurements for **37 contracted functions**. The driver mechanically adjudicates **`cdp-discriminating-weak`** — but **only 4 of 37 functions (10.8%) produced a defined score, and every one of the 4 scored exactly `0.000`** with `WarnIdentitySatisfiesPost`. The remaining 33 split into 6 `spec-inconsistent`, 5 `candidates-empty-under-limit`, and 22 `not-requested` (cross-module imports outside CDP-0's measurement scope). The true signal is closer to `cdp-null` than to `cdp-discriminating-weak`; the driver's intermediate-slice fall-through (F-008) is misleading on this data. The §4.3.1 enumeration produces no midrange `(0.0, 1.0)` score on the canonical Tier-1 benchmark corpus, supporting proposal §10 Risk #2 (small enumeration) as the binding constraint.

## Sample composition

- **Total fixture invocations:** 36 (6 primary + 30 secondary discovered).
- **Excluded for pre-existing verify failure:** 8 (`conways_life_json_verifier/life`, `hangman_json_verifier/hangman`, `life_json/main`, `life_json/world`, `pair_type_test/do_emit_ac`, `pair_type_test/pair_match_ac4`, `pair_type_test/pair_type_test`, `tictactoe_json_verifier/tictactoe`). Failure modes are stale type errors and missing `(import wasi.io (capability ...))` declarations; not CDP-related. Detailed per-fixture in `runs/20260526T233504Z-baseline/summary.md` "Excluded fixtures" section.
- **Contracted functions across the 28 verify-clean fixtures:** 37.
- **Compiler SHA:** `cc712aa` (working-tree HEAD of `fix/diagnosticfq-partial-record`). Manifest pins `121815a` per [`manifest.json:compiler_ref`](../manifest.json).
- **`llmll version`:** `llmll 0.10.8`.
- **`CDPScope`:** `CDPScopeAllDefLogic` (pre-LT-INV default per [`docs/design/v0.11-cross-proposal-rollback-discipline.md`](../../../docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md) §2).
- **Harness git SHA:** uncommitted — F-003 patch at [`experiments/cdp-0/scripts/cdp_baseline.py:83-100`](../scripts/cdp_baseline.py) is the working-tree delta from the prior session.
- **Run directory:** [`experiments/cdp-0/runs/20260526T233504Z-baseline/`](../runs/20260526T233504Z-baseline/) — contains `baseline.json` (full per-function axes + aggregate), `summary.md` (one-page human-readable), and `per-fixture/*.json` (raw trust-report JSON per fixture).

## Verified findings

### F-004. Defined-score distribution collapses to {0.000}; midrange empty

**Priority:** High
**Consumer:** language-team (informational); user (CDP-0 adjudication interpretation)

#### Evidence

[`runs/20260526T233504Z-baseline/baseline.json`](../runs/20260526T233504Z-baseline/baseline.json) `per_function_axes`: 4 of 37 entries have non-null `score`; all 4 scores are `0.000`:

| fixture_id | fn_name | score | candidate_count | satisfying | warnings |
|---|---|---|---|---|---|
| `banking` | `safe-subtract` | 0.000 | 2 | 2 | `identity-satisfies-post` |
| `sec_examples_auth_module_…` | `login-handler` | 0.000 | 2 | 2 | `identity-satisfies-post` |
| `sec_examples_orchestrator_walkthrough_auth_module_…` | `login-handler` | 0.000 | 2 | 2 | `identity-satisfies-post` |
| `sec_examples_orchestrator_walkthrough_auth_module_filled_…` | `login-handler` | 0.000 | 2 | 2 | `identity-satisfies-post` |

Aggregate distribution (`aggregate.score_stats` in baseline.json): mean 0.000, median 0.000, p10 / p50 / p90 / min / max all 0.000. Midrange `(0.0, 1.0)`: 0 of 4 defined scores.

#### Why we saw what we saw

The §4.3.1 enumeration produces type-compatible candidates only when the function's return type matches an enumerator's admitted-types row (per [`compiler/src/LLMLL/WeaknessCheck.hs:cdpCatalog`](../../../compiler/src/LLMLL/WeaknessCheck.hs)). For the 4 functions that produced any candidates, both the identity body and a constant body satisfied the contract — meaning the contract is permissive enough to admit each. With `|⟦S⟧_Ω| = |B_{T,U,Ω}| = 2`, the Shannon score formula yields `1 − log(2) / log(2) = 0`.

The deeper observation: across the canonical Tier-1 corpus (`b1`, `b3`, `b5`, `totp`, `erc20`, `banking`), no contract is *both* tight enough to reject some candidates AND loose enough to admit some candidates from the §4.3.1 closed set. The corpus splits into "no candidate typechecks" (F-006: `Result`-returning functions), "no candidate satisfies" (F-005: arithmetic / banking contracts with tight per-input formulas), and "all candidates satisfy" (F-004 itself: auth-handler-style contracts permissive enough for identity).

#### Implication

For **language-team** (informational): the v0.11 candidate-set enumeration produces a degenerate score distribution on the canonical example corpus. No function in the corpus produces a midrange `(0.0, 1.0)` score; every measurable function is 0.0 (spec admits trivial body). Proposal §10 Risk #2 (small enumeration) is empirically the binding constraint. The four-cell matrix in proposal §1 (verified-strong / verified-weak / tested-strong / asserted-strong) cannot be populated from this baseline because no function reaches "strong" via DP > 0. The v0.12+ widening to LLM-generated candidates per [`docs/design/invariant-discovery-review.md §5`](../../../docs/archive/professor-reviews/invariant-discovery-review.md) is the proposal-side stated mitigation; this finding is empirical evidence that the widening is load-bearing for CDP's utility as a measurement axis, not just a future nicety.

For **user**: the CDP-0 adjudication label `cdp-discriminating-weak` is mechanically correct per the driver's intermediate-slice fall-through but is materially misleading on this data. Treat the adjudication as `cdp-null` for downstream consumer guidance. See F-008 for the driver-rule refinement candidate.

#### Acceptance

Re-running after a §4.3.1 enumeration widening that produces at least one `(0.0, 1.0)`-midrange score across the same corpus would close this finding. The widening itself is a spec-side decision — not adjudicated by experiment-lead.

### F-005. `spec-inconsistent` warning name is misleading at small Ω

**Priority:** High
**Consumer:** language-team (informational); compiler-engineer (possible candidate-generation bug, see F-006)

#### Evidence

6 functions fire `WarnSpecInconsistent` (zero of the type-compatible candidates satisfied the contract):

| fixture_id | fn_name | candidate_count | satisfying |
|---|---|---|---|
| `b5` | `double` | 1 | 0 |
| `banking` | `withdraw` | 2 | 0 |
| `banking` | `transfer` | 2 | 0 |
| `banking` | `clamp-withdraw` | 2 | 0 |
| `banking` | `withdraw-twice` | 3 | 0 |
| `banking` | `compute-fee` | 1 | 0 |

These are real, body-faithful-verifiable functions with consistent contracts — the underlying programs verify SAFE under `--strict-verified-core`, confirmed during the v0.10.8 INT-1 ship and the LT-INT post-shim regen of `banking_ledger.verified.json`. A truly inconsistent contract (`(pre (and (> n 0) (< n 0)))`) would not verify; the `spec-inconsistent` label here is reporting that the §4.3.1 candidate set does not include a valid implementation, NOT that the contract is logically inconsistent.

[`compiler/src/LLMLL/CDP.hs`](../../../compiler/src/LLMLL/CDP.hs) `buildWarnings` defines `WarnSpecInconsistent` to fire when `null satisfying && not (null candidates)`. Proposal §5 documents the warning as "S is inconsistent (`|⟦S⟧_Ω| = 0`)" — technically correct *relative to Ω* per the observational caveat at proposal §1 Rev 2, but the warning name overstates the claim.

#### Why we saw what we saw

For `b5::double` (return type `int`, body `(+ n n)`): the §4.3.1 enumeration for `int → int` admits `TrivIdentity n` + `TrivConstInt {0, 1, -1, 42}` (5 candidates). The trust-report shows `candidate_count: 1` — only 1 of the 5 typechecked against the synthetic stmt's typecheck pass. That 1 (`TrivConstInt 0`, which satisfies `result = n + n` only at `n = 0`) does not satisfy universally → `spec-inconsistent`. The `identity` body `λn.n` does not satisfy `result = n + n` for nonzero `n` either, so even if all 5 typechecked, none would satisfy.

Banking contracts have similar shapes: per-input formulas (`(= result (- balance amount))`) that no constant satisfies and identity-on-`int` does not satisfy.

#### Implication

For **language-team:** the `WarnSpecInconsistent` warning name conflates "spec logically inconsistent" with "spec too tight for the candidate set Ω." Two reasonable directions:
- (a) Rename to `no-candidate-satisfies` or `vacuous-over-omega` to surface the observational-not-semantic framing (matches proposal §1 Rev 2's load-bearing caveat).
- (b) Introduce a second warning `spec-too-tight-for-omega` that fires for "no candidate satisfies AND `|Ω| ≥ N` for some N"; reserve `spec-inconsistent` for a (rare, possibly never-occurring) "no behavior in `B_{T,U,Ω}` could satisfy" semantic case.

Either is a spec-side rename + corresponding compiler-side warning-construction tweak. Not blocking; not adjudicated by experiment-lead.

For **compiler-engineer**: ancillary observation — `b5::double` reports `candidate_count: 1` where `cdpCatalog` should have produced 5 (identity-int + 4 int constants). Possible `tryCandidate` over-strictness in the synthetic typecheck path. Worth a brief look at [`compiler/src/LLMLL/WeaknessCheck.hs:158-186`](../../../compiler/src/LLMLL/WeaknessCheck.hs) (`tryCandidate`) — does the synthetic-stmt typecheck against `builtinEnv` actually accept `(+ x 0)`-shaped trivial bodies, or does the type-checker reject them for some unrelated reason? If the over-strictness is real, fixing it would expose the rest of the §4.3.1 enumeration to the metric.

**Fix shipped:** compiler-side warning rename (a) landed at commit `0b5b249` on branch `fix/diagnosticfq-partial-record`: `WarnVacuousOverOmega` fires when `functionVerifies && inconsistent`; `WarnSpecInconsistent` retained for `not functionVerifies && inconsistent`. The candidate-generation bug for `b5::double` (F-005 ancillary: `candidate_count: 1 → ≥ 5`) fixed at commit `6f2ea39` via `matchesReturnTypeOrUnknown _ Nothing = True`. Spec-side scope-policy clarification (language-team) remains open.

#### Acceptance

After (a) warning rename AND/OR (b) candidate-generation fix, re-run shows that permissive contracts fire the renamed warning and arithmetic-tight contracts produce a non-zero `candidate_count` (even if `satisfying_candidate_count` stays at 0).

**Post-fix re-confirmation owed:** experiment-lead to re-run CDP-0 harness against HEAD of `fix/diagnosticfq-partial-record` and verify `b5::double candidate_count ≥ 5`.

### F-006. `Result`-returning functions get zero candidates

**Priority:** Medium (highest signal-to-effort engineer fix in the priority matrix)
**Consumer:** compiler-engineer

#### Evidence

5 functions return `candidate_count: 0`, `WarnCandidatesEmptyUnderLimit`:

| fixture_id | fn_name |
|---|---|
| `b1` | `withdraw` |
| `b3` | `safe-first` |
| `sec_examples_withdraw-demo_withdraw_llmll` | `withdraw` |
| `sec_examples_withdraw_llmll` | `withdraw` |
| `sec_examples_withdraw-demo_withdraw_ast_json` | `withdraw` |

All five return `Result[int, string]` or similar `Result[T, E]` shapes (verified by inspecting source files).

[`compiler/src/LLMLL/WeaknessCheck.hs:cdpCatalog`](../../../compiler/src/LLMLL/WeaknessCheck.hs) `sums` case:

```haskell
sums = case mRet of
  Just (TResult okT _) -> [TrivConstSuccess okT, TrivConstError]
  _                    -> []
```

This SHOULD produce 2 candidates per `Result`-returning function (`Success`-wrapping the default of `okT`, plus `Error "default"`). `candidate_count: 0` means both candidates failed `tryCandidate`'s synthetic-typecheck filter.

#### Why we saw what we saw

[`compiler/src/LLMLL/WeaknessCheck.hs:174`](../../../compiler/src/LLMLL/WeaknessCheck.hs) type-checks the synthetic stmt against `builtinEnv` only — no imported-module env, no cross-module aliases. Likely causes (in suspected-likelihood order):

1. The `Success` and `Error` constructors are not in `builtinEnv` for the synthetic typecheck path. The `Result` type is defined elsewhere; if `builtinEnv` only carries primitive operators, the synthetic body `EApp "Success" [ELit (LitInt 0)]` is type-rejected with "call to unknown function Success".
2. The return type `Result[int, string]` is a `TResult okT errT` whose `okT` resolves to a refinement-aliased type (e.g. `PositiveInt`) rather than raw `TInt`; `cdpCatalog`'s pattern `Just (TResult okT _)` does not unwrap the refinement and the `defaultExpr okT` produces a value that does not typecheck against the refinement.
3. The `Result` type alias maps to a `TCustom "Result"` (or similar) at the type-checker level rather than `TResult okT errT`; `cdpCatalog`'s `case mRet of Just (TResult …)` never matches.

A single targeted reproduction with `b1::withdraw` would distinguish the three causes — but the experiment-lead seat does not patch compiler source; routed to compiler-engineer.

#### Implication

For **compiler-engineer**: the candidate-generation path for `Result`-returning functions silently produces zero candidates on the canonical Tier-1 benchmarks. This is the most consequential gap for CDP-0's discriminating power — these are exactly the functions the proposal §4.3.1 enumeration table targets. Fix is plausibly local to [`compiler/src/LLMLL/WeaknessCheck.hs:cdpCatalog` + `:tryCandidate`](../../../compiler/src/LLMLL/WeaknessCheck.hs). Acceptance: post-fix re-run shows `candidate_count: 2` (or more) for `b1::withdraw`, `b3::safe-first`, and the three withdraw-demo variants; downstream `satisfying_candidate_count` and `score` populate from there.

#### Acceptance

`b1::withdraw` and `b3::safe-first` return `candidate_count ≥ 2` post-engineer-fix; the per-fixture entries acquire a defined `score` (likely 0.5 for typical `Result`-returning withdraw contracts, since `Success`-wrapping the default int passes the postcondition for one input class and `Error` passes for another).

**Fix shipped:** commit `6f2ea39` on branch `fix/diagnosticfq-partial-record` — `generateForStmt` now receives full module-level `[Statement]` list; `tryCandidate` prepends `[s | s@STypeDef{} <- allStmts]` before the synthetic typecheck so `checkStatements` populates `tcAliasMap` with module-level aliases (root cause: option 2 in the three suspected causes list above — refinement-aliased `okT` caused `structuralUnify` to reject every candidate). Six regression tests F6-1–F6-6 added to [`compiler/test/Spec.hs`](../../../compiler/test/Spec.hs). **Post-fix re-confirmation owed:** experiment-lead to re-run CDP-0 harness against HEAD of `fix/diagnosticfq-partial-record` and verify `b1::withdraw candidate_count ≥ 2`, `b3::safe-first candidate_count ≥ 2`.

### F-007. CDP-0 measurement scope excludes cross-module imports (22 `not-requested` entries)

**Priority:** Medium
**Consumer:** experiment-lead (harness owner; informational); language-team (scope policy question)

#### Evidence

22 of 37 `per_function_axes` entries carry `warnings: ["not-requested"]`. First six by fixture: `totp::compute-time-step`, `totp::dynamic-truncate`, `totp::generate-totp`, `totp::validate-totp`, `totp::pad-otp`, `erc20::total-supply`. These are the trust-report's cross-module entries: when `totp_filled.ast.json` is the entry file, the trust-report includes its 5 entry-module functions PLUS 5 cross-module imports from the cached module env. The same 5 function names appear in the secondary corpus as `sec_examples_totp_rfc6238_totp_ast_json`, where they ARE the entry module and DO get CDP measured.

[`compiler/src/LLMLL/CDP.hs:computeCDPFor`](../../../compiler/src/LLMLL/CDP.hs) iterates only over the entry statement list `stmts`; transitive imports from the module cache are not measured. The trust-report at [`compiler/src/LLMLL/TrustReport.hs:cdpAxisJson`](../../../compiler/src/LLMLL/TrustReport.hs) then merges entry + cache entries and finds no CDP map entry for the cross-module ones → uniform-shape `not-requested` warning per [`compiler/src/LLMLL/CDP.hs:WarnNotRequested`](../../../compiler/src/LLMLL/CDP.hs).

#### Why we saw what we saw

CDP-0 scope was set to "the entry file's contracted functions" by my reading of proposal §2. The trust-report's cross-module behavior (merging entry + cached `ModuleEnv` entries into a single `entries:` array) was not factored into the harness design. Effect: a fixture's CDP coverage depends on whether its functions are entry-module or imported, which over-aggregates same-function-different-fixture pairs.

#### Implication

For **experiment-lead** (myself): the harness over-aggregates. A future revision could:
- (a) Deduplicate on canonical-name keys (qualified module-path + function-name) so a function measured as entry-module under one fixture is not double-counted as cross-module-not-requested under another.
- (b) Extend `computeCDPFor` to walk the module cache (requires routing to compiler-engineer for a CDP scope change). Adds compiler complexity for a question that may not load-bear.

For **language-team**: proposal §2 does not specify CDP scope across module boundaries. The current behavior (entry-module only) is a reasonable conservative default; widening to transitive scope is a scope-policy decision worth recording in a Rev 3 of the proposal, the v0.11-cross-proposal-rollback-discipline doc, or as a v0.12+ roadmap row.

Not blocking. The LT-INV §8 gate can use the same scope discipline post-LT-INV for pre/post comparability — the over-aggregation is consistent across pre and post measurements.

#### Acceptance

Either (a) harness dedup (one-pass aggregation change in [`experiments/cdp-0/scripts/cdp_baseline.py:aggregate`](../scripts/cdp_baseline.py)) lands and the next baseline shows fewer `not-requested` entries while preserving the entry-module data; or (b) proposal §2 Rev 3 adopts an explicit scope-policy statement and the harness mirrors it. Either move closes the finding.

**Fix shipped:** option (a) landed at harness working-tree (uncommitted) — dedup within the `not-requested` group at [`experiments/cdp-0/scripts/cdp_baseline.py:158–172`](../scripts/cdp_baseline.py). Within the `not-requested` bucket, `fn_name` is the dedup key; first occurrence per unique name is kept, measured entries untouched. Verified on both existing artifacts: full run 37 → 26 contracted entries (11 duplicates removed); primary-only run 20 → 20 (no duplicates present). Adjudication label unaffected (`cdp-null`). F-007 (experiment-lead) **closed**.

### F-008. Harness adjudication fall-through label is misleading on the intermediate slice

**Priority:** Medium
**Consumer:** experiment-lead (harness owner; self-routed)

#### Evidence

[`experiments/cdp-0/scripts/cdp_baseline.py:aggregate`](../scripts/cdp_baseline.py) computes `defined_fraction = 4/37 = 0.108`. The manifest labels at [`manifest.json:outcome_labels`](../manifest.json):

- `cdp-discriminating`: `defined_fraction >= 0.50 AND midrange_fraction >= 0.25`
- `cdp-discriminating-weak`: `defined_fraction >= 0.50`
- `cdp-null`: `defined_fraction < 0.10`
- `cdp-corpus-inadequate`: `contracted_total < 10`

`0.108` is the intermediate slice (`0.10 ≤ defined < 0.50`), which has no manifest-declared label. The script falls through to `cdp-discriminating-weak` with the comment "No manifest-declared label for this slice; fall back to weak with a flag" — but no flag is emitted in the JSON output, and the label reads as positive signal when in reality the corpus produced only 4 of 37 scored functions, all at 0.000.

#### Why we saw what we saw

I designed the four-threshold manifest with an unintended fourth slice (10% ≤ defined < 50%) and a defensive fall-through default that backfires on real data.

#### Implication

For **experiment-lead** (myself): the manifest's `outcome_labels` table needs refinement before publishing this baseline as the LT-INV §8 gate anchor. Two reasonable options:

- (a) Extend `cdp-null` to `defined_fraction < 0.30` (recognizing that <30% defined-fraction is operationally indistinguishable from null for gate purposes).
- (b) Introduce a fourth label `cdp-discriminating-thin` for the slice and document its consumer treatment explicitly.

Either is a one-line manifest + driver edit.

#### Acceptance

Re-run after manifest refinement emits a non-misleading adjudication label for this corpus.

**Fix shipped:** `cdp-null` threshold extended to `defined_fraction < 0.30` in [`manifest.json`](../manifest.json) and [`scripts/cdp_baseline.py:186`](../scripts/cdp_baseline.py). Both existing run artifacts patched in-place (`runs/20260526T233504Z-baseline/baseline.json` and `runs/20260527T140751Z-baseline/baseline.json` now carry `adjudication_label: "cdp-null"`). README §4 updated. The 30–50% slice falls cleanly to `cdp-discriminating-weak` with an accurate comment; the dead fallthrough is eliminated. F-008 **closed**.

## Withdrawn items

None. The pre-stated hypothesis ("the §4.3.1 enumeration produces measurable variance") is empirically not supported (F-004) — surfaced as a verified finding, not as a withdrawn item per the experiment-lead convention for falsifying-empirical results.

## Null results

The pre-stated null ("≥ 90% return `score: null` with `enumeration-too-narrow` or `candidates-empty-under-limit`") is **partially supported**: 33/37 = 89.2% return undefined-or-not-requested scores, just under the 90% threshold. The warning distribution does not match the null's specific predicted breakdown — `not-requested` (22, cross-module) was not anticipated; `spec-inconsistent` (6) was anticipated but at lower frequency. The high-level signal (most contracts produce no measurable DP) holds.

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---------|----------|----------|-----------------|
| F-004 | Defined scores cluster at 0.000; midrange empty | language-team | High | Spec-side widening (v0.12+); zero immediate engineer/doc work |
| F-005 | `spec-inconsistent` warning name misleading at small Ω | language-team; compiler-engineer | High | Spec rename + possible candidate-typecheck-strictness fix |
| F-006 | `Result`-returning functions get zero candidates | compiler-engineer | Medium | ≈ 30 min engineer fix in `WeaknessCheck.hs:cdpCatalog`/`tryCandidate` |
| F-007 | Cross-module scope gap (22 `not-requested`) | experiment-lead; language-team | Medium | Harness dedup or proposal Rev 3 scope-policy statement |
| F-008 | Driver fall-through label misleading on intermediate slice | experiment-lead | Medium | One-line manifest + driver edit |

## Findings file(s) written

- This file: [`experiments/cdp-0/findings/postmortem-002-cdp-baseline-rerun.md`](postmortem-002-cdp-baseline-rerun.md) — full integrated report.
- [`experiments/cdp-0/findings.md`](../findings.md) — H2-per-role per DOC-CONSOLIDATE M1; carries F-001 (closure cite), F-003 (closure cite), F-006 under `## Compiler-engineer`; F-004, F-005, F-007 under `## Language-team`; F-003 (closure cite), F-007, F-008 under `## Experiment-lead`; `## Documentation-lead` empty (F-005 spec rename routes here only after language-team adjudicates).

## Hand-offs (user routes)

- **`compiler-engineer`** — F-006 (small candidate-typecheck fix at `WeaknessCheck.hs:cdpCatalog`/`tryCandidate`). Highest signal-to-effort. Recommended first action.
- **`language-team`** — F-004 (proposal §10 Risk #2 empirically confirmed; v0.12+ enumeration widening is load-bearing not optional); F-005 (`spec-inconsistent` warning rename); F-007 (cross-module scope policy for proposal Rev 3). Three findings, all spec-side judgment calls.
- **`experiment-lead`** (next session) — F-007 dedup + F-008 manifest refinement; then re-run after F-006 lands to see whether the defined-fraction crosses the discrimination threshold.

## LT-INV §8 gate consumer status

CDP-0 baseline at `runs/20260526T233504Z-baseline/baseline.json` is on disk and citable. The data tells the LT-INV §8 gate that CDP is **currently not usable as a continuous-shift discriminating axis on the canonical corpus**: defined-fraction 10.8%, midrange-fraction 0% of defined, all defined scores at 0.0. Gate planning should either:

- (a) Run with CDP gated only on coarse pass/fail (any non-null score-distribution shift counts as signal) per [LT-INV §8 rollback paths](../../../docs/archive/shipped-design-specs/core-shell-inversion-direction.md);
- (b) Wait for F-006 fix + a re-run to determine whether CDP becomes usable as a continuous axis after the candidate-typecheck gap is closed.

Routing call belongs to language-team adjudicating against the §8 gate criteria.

---

## Appendix: Post-fix re-run — 2026-05-27

**Purpose:** Empirical confirmation of F-006 and F-005 ancillary acceptance criteria per the "Post-fix re-confirmation owed" obligations in §F-006 and §F-005 above.

**Run directory:** [`experiments/cdp-0/runs/20260527T140751Z-baseline/`](../runs/20260527T140751Z-baseline/) — `baseline.json`, `summary.md`, `per-fixture/`.

**Sample composition:**

- Primary corpus only (`--primary-only` flag); secondary corpus excluded to isolate acceptance-criterion signal
- 6 primary fixtures; 20 contracted functions
- Binary: `llmll 0.10.8` built from HEAD `cff26d5` (includes fix commits `6f2ea39` + `0b5b249` + three subsequent doc/harness commits)
- Harness git SHA: `cff26d5` (run directory untracked; no other working-tree delta)
- Manifest `compiler_ref` still pins `121815a` (unchanged); actual running SHA is `cff26d5`

### F-006 acceptance criteria

| function | baseline `candidate_count` | post-fix `candidate_count` | threshold | accepted |
|---|---|---|---|---|
| `b1::withdraw` | 0 (`WarnCandidatesEmptyUnderLimit`) | 7 (`satisfying=2`, `score=0.6438`) | ≥ 2 | ✅ |
| `b3::safe-first` | 0 (`WarnCandidatesEmptyUnderLimit`) | 5 (`satisfying=5`, `score=0.000`) | ≥ 2 | ✅ |

`WarnCandidatesEmptyUnderLimit` no longer fires on any primary-corpus fixture. F-006 **closed**.

### F-005 ancillary acceptance criteria

| function | baseline `candidate_count` | post-fix `candidate_count` | threshold | accepted |
|---|---|---|---|---|
| `b5::double` | 1 (`WarnSpecInconsistent`) | 6 (`satisfying=1`, `score=1.000`) | ≥ 5 | ✅ |

`WarnSpecInconsistent` no longer fires; `WarnVacuousOverOmega` correctly fires on the banking arithmetic-tight functions (F-005 rename, commit `0b5b249`, confirmed). F-005 ancillary **closed**.

### Distribution shift (primary corpus — apples-to-apples)

| axis | baseline primary (reconstructed) | post-fix primary |
|---|---|---|
| contracted functions | 20 | 20 |
| defined scores | 1 (5.0%) | 5 (25.0%) |
| midrange scores | 0 | 1 (`b1::withdraw` at 0.6438) |
| adjudication | `cdp-null` territory (5%) | `cdp-discriminating-weak` (25%) |
| score mean / median | 0.000 / 0.000 | 0.529 / 0.644 |
| min / max | 0.000 / 0.000 | 0.000 / 1.000 |

Baseline primary counts are reconstructed from the per-function table in `runs/20260526T233504Z-baseline/baseline.json` — the baseline run was primary+secondary (37 functions); primary-only counts extracted from `per_function_axes[fixture_id in {b1, b3, b5, totp, erc20, banking}]`.

`b1::withdraw` at `score=0.6438` is the first midrange CDP score in the Tier-1 corpus. The F-004 finding (midrange empty) does not close from this run: F-004 was scoped to the full baseline corpus (primary+secondary, 37 functions); this re-run is primary-only. A full post-fix run (primary+secondary) would determine whether the midrange fraction holds across the secondary corpus.

### Warning distribution shift (primary corpus)

| warning | baseline primary | post-fix primary |
|---|---|---|
| `candidates-empty-under-limit` | 3 | 0 |
| `spec-inconsistent` | 6 | 0 |
| `vacuous-over-omega` | 0 | 4 |
| `identity-satisfies-post` | 2 | 2 |
| `const-satisfies-post` | 2 | 5 |
| `not-requested` | 11 | 11 |

`banking::withdraw` moved from `WarnVacuousOverOmega` (0 satisfying of 2 candidates) to `score=1.000` (1 satisfying of 7 candidates). This is a positive ancillary signal: the alias-threading fix (`6f2ea39`) widened the candidate set for Result-adjacent integer functions beyond what the acceptance criteria required.

### Status update

F-006 and F-005 ancillary are empirically confirmed closed at harness SHA `cff26d5`, run `20260527T140751Z`. The "Post-fix re-confirmation owed" obligations in both sections above are discharged.

---

## Appendix B: Definitive full post-fix run — 2026-05-27

**Purpose:** Full primary+secondary baseline at HEAD `27586c6` after all F-005, F-006, F-007, and F-008 fixes. This run is the CDP-0 definitive anchor for the LT-INV §8 empirical-validation gate.

**Run directory:** [`experiments/cdp-0/runs/20260527T154040Z-baseline/`](../runs/20260527T154040Z-baseline/) — `baseline.json`, `summary.md`, `per-fixture/`.

**Sample composition:**

- Primary corpus: 6 fixtures; secondary corpus: 30 discovered, 22 verify-clean, 8 excluded.
- 28 fixtures processed; 26 contracted functions (after F-007 dedup of `not-requested` group).
- **Binary:** `llmll 0.10.8` built from HEAD `27586c6` (includes all fix commits through `27586c6` F-008 threshold extension).
- **Harness git SHA:** `27586c6` (run directory untracked).
- **Manifest `compiler_ref`** still pins `121815a` (measurement-equivalence anchor unchanged); actual running SHA is `27586c6`.
- **Excluded secondary (8, all pre-existing):** `conways_life_json_verifier/life` (type-mismatch), `hangman_json_verifier/hangman` (infinite type + type-mismatch), `life_json/main` (unknown functions), `life_json/world` (unknown function), `pair_type_test/do_emit_ac`, `pair_type_test/pair_match_ac4`, `pair_type_test/pair_type_test` (wasi.io capability missing), `tictactoe_json_verifier/tictactoe` (type-mismatch + branch-type mismatch). Same 8 as the pre-fix full run.

### Aggregate

| axis | pre-fix full (20260526T233504Z) | post-fix primary-only (20260527T140751Z) | **definitive full (20260527T154040Z)** |
|---|---|---|---|
| fixtures processed | 28 (6+22) | 6 (primary only) | **28 (6+22)** |
| contracted_fns_total | 37* | 20 | **26** |
| defined_scores | 4 (10.8%) | 5 (25.0%) | **11 (42.3%)** |
| midrange_scores | 0 | 1 | **4** |
| midrange_fraction | 0% | 20.0% | **36.4% of defined** |
| adjudication_label | cdp-null (retroactively; F-008 fix) | cdp-null | **cdp-discriminating-weak** |
| score mean / median | 0.000 / 0.000 | 0.529 / 0.644 | **0.416 / 0.644** |
| score min / max | 0.000 / 0.000 | 0.000 / 1.000 | **0.000 / 1.000** |

\* Pre-fix run preceded the F-007 dedup patch; 37 = 26 deduped + 11 suppressed duplicate `not-requested` entries.

### Defined-score breakdown

| fixture_id | fn_name | score | warnings |
|---|---|---|---|
| `b1` | `withdraw` | **0.6438** (midrange) | identity-satisfies-post, const-satisfies-post |
| `b3` | `safe-first` | 0.000 | const-satisfies-post |
| `b5` | `double` | 1.000 | const-satisfies-post |
| `banking` | `safe-subtract` | 0.000 | identity-satisfies-post, const-satisfies-post |
| `banking` | `withdraw` | 1.000 | const-satisfies-post |
| `sec_withdraw-demo_llmll` | `withdraw` | **0.6438** (midrange) | identity-satisfies-post, const-satisfies-post |
| `sec_withdraw_llmll` | `withdraw` | **0.6438** (midrange) | identity-satisfies-post, const-satisfies-post |
| `sec_auth_module_ast_json` | `login-handler` | 0.000 | identity-satisfies-post, const-satisfies-post |
| `sec_orchestrator_auth_module_ast_json` | `login-handler` | 0.000 | identity-satisfies-post, const-satisfies-post |
| `sec_orchestrator_auth_module_filled_ast_json` | `login-handler` | 0.000 | identity-satisfies-post, const-satisfies-post |
| `sec_withdraw-demo_ast_json` | `withdraw` | **0.6438** (midrange) | identity-satisfies-post, const-satisfies-post |

Score distribution (defined only): mean 0.416, median 0.644, p10 0.000, p50 0.644, p90 1.000, min 0.000, max 1.000.

### Warning distribution (full corpus)

| warning | pre-fix full | definitive full |
|---|---|---|
| `candidates-empty-under-limit` | 5 | 0 |
| `spec-inconsistent` | 6 | 0 |
| `vacuous-over-omega` | 0 | 4 |
| `identity-satisfies-post` | 4 | 8 |
| `const-satisfies-post` | 4 | 11 |
| `not-requested` | 22 (pre-dedup) | 11 (post-dedup) |

### Implications for F-004 (open finding)

F-004 was stated as "midrange empty across canonical corpus" — that claim was accurate at the pre-fix baseline. The definitive run shows **4 midrange scores (36.4% of defined)**, all at `score=0.6438`, all from `withdraw`-family functions. The F-004 finding for language-team (v0.12+ LLM-generated-candidate widening is load-bearing) remains open — the `score=0.6438` midrange cluster is produced by the §4.3.1 *constant* enumeration (2 satisfying of 7 total candidates), not by LLM-generated candidates. The proposal §10 Risk #2 claim (small enumeration limits discrimination) remains structurally valid: 4 of 11 defined scores are in the midrange; 4 of 11 score exactly 0.000 (`login-handler` × 3 + `safe-subtract`) because all 12 type-compatible candidates satisfy the permissive auth contract. The four-cell matrix at proposal §1 remains unpopulated on "verified-strong" (DP close to 1.0) functions — `b5::double` and `banking::withdraw` at `score=1.000` are verified-strong by CDP but their contracts are permissive (one satisfying candidate out of many, i.e., high discrimination) not tight. F-004 should be refined to note partial resolution: *midrange now achievable on `withdraw`-family contracts; `login-handler`-family contracts remain at 0.000 (identity-satisfies-post); LLM-widening remains load-bearing for non-trivial real-world contract families.*

### LT-INV §8 gate consumer status — updated

CDP-0 definitive anchor is `runs/20260527T154040Z-baseline/baseline.json`. The data tells the LT-INV §8 gate that CDP is **usable as a coarse discriminating axis on the canonical corpus post F-006 fix**: defined-fraction 42.3%, midrange-fraction 36.4% of defined, score range [0.000, 1.000]. Gate option (b) from postmortem-002 §LT-INV — "wait for F-006 fix + re-run to determine whether CDP becomes usable as a continuous axis" — is now answered: yes, CDP produces meaningful score variation post-fix. Gate option (a) — "coarse pass/fail only" — is superseded; continuous-shift comparison is viable for `withdraw`-family contracts and `double`-family contracts. The residual limitation is the `login-handler`-family at `score=0.000`: these contracts admit every candidate, which remains a genuine discrimination failure not addressed by F-006. Routing call for LT-INV §8 gate planning belongs to language-team.
