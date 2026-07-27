# CDP-0 findings — H2-per-role index

> Per DOC-CONSOLIDATE M1 (settled 2026-05-24): downstream skills grep their own H2 anchor in this file. Postmortems are episodic under `findings/postmortem-NNN-<slug>.md`; this file is the consumer-routed surface that points into them.
>
> **Active postmortems:**
> - [`postmortem-001-cdp-baseline-blocked.md`](findings/postmortem-001-cdp-baseline-blocked.md) — three halted attempts on F-001 (compiler partial-record) + F-003 (harness flag placement). Both closed.
> - [`postmortem-002-cdp-baseline-rerun.md`](findings/postmortem-002-cdp-baseline-rerun.md) — F-004..F-008 surfaced; **Appendix B** (`runs/20260527T154040Z-baseline/`) is the definitive CDP-0 anchor for LT-INV §8: `cdp-discriminating-weak`, 11/26 defined (42.3%), 4 midrange (36.4% of defined), harness SHA `27586c6`.

## Compiler-engineer

### F-001. `fqResultToReport` partial-record crash on `--json verify` SAFE results

**Status:** **Closed by commit `e5e6d04`** (`fix: DiagnosticFQ — initialize reportPhase to "lh-fixpoint" (F-001)`) on branch `fix/diagnosticfq-partial-record`. CHANGELOG entry at commit `cc712aa` under `### Compiler — fix: DiagnosticFQ partial-record crash on \`--json verify\` SAFE (F-001)`. Four regression tests `DF-1`..`DF-4` in [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs) close the test gap. Full evidence preserved at [`findings/postmortem-001-cdp-baseline-blocked.md` §F-001](findings/postmortem-001-cdp-baseline-blocked.md).

### F-006. `Result`-returning functions get zero candidates from §4.3.1 enumeration

**Priority:** Medium (highest signal-to-effort in the priority matrix)
**Status:** **Closed by commit `6f2ea39`** (`fix: WeaknessCheck — thread STypeDef aliases into synthetic type-check (F-006)`). Root cause was confirmed as refinement-aliased `okT`: `tryCandidate` called `typeCheck builtinEnv [syntheticStmt]` with an empty `tcAliasMap`, so `expandAlias (TCustom "PositiveInt")` returned the opaque node unchanged and `structuralUnify` rejected every candidate. Fix: `generateForStmt` now receives the full module-level `[Statement]` list and prepends `[s | s@STypeDef{} <- allStmts]` before the synthetic typecheck so `checkStatements` populates `tcAliasMap` with module-level aliases. Six regression tests F6-1–F6-6 in [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs) close the test gap. CHANGELOG entry at commit `cc712aa` (amended in staged docs pass) under `### Compiler — fix: WeaknessCheck zero-candidate generation (F-006 / F-005 ancillary)`. **Empirical re-confirmation** of `b1::withdraw candidate_count ≥ 2` and `b3::safe-first candidate_count ≥ 2` post-fix is owed to experiment-lead (CDP-0 re-run against HEAD of `fix/diagnosticfq-partial-record`).

Across 5 canonical Tier-1 benchmarks (`b1::withdraw`, `b3::safe-first`, plus three `withdraw-demo` variants), all returning `Result[T, E]`, [`compiler/src/LLMLL/CDP.hs:computeCDPFor`](../../compiler/src/LLMLL/CDP.hs) records `candidate_count: 0` with `WarnCandidatesEmptyUnderLimit`. [`compiler/src/LLMLL/WeaknessCheck.hs:cdpCatalog`](../../compiler/src/LLMLL/WeaknessCheck.hs) is wired to produce `[TrivConstSuccess okT, TrivConstError]` for `TResult okT _`, so both candidates failed the synthetic typecheck at [`compiler/src/LLMLL/WeaknessCheck.hs:174`](../../compiler/src/LLMLL/WeaknessCheck.hs) (`typeCheck builtinEnv [syntheticStmt]`). Three suspected causes — `Success`/`Error` constructors absent from `builtinEnv`, refinement-aliased `okT` rejecting `defaultExpr okT`, or `Result` type-alias resolving to `TCustom "Result"` rather than `TResult okT errT`. Targeted reproduction with `b1::withdraw` would distinguish.

**Acceptance:** `b1::withdraw` and `b3::safe-first` return `candidate_count ≥ 2` post-fix; downstream `score` populates. **Empirically confirmed at run `20260527T140751Z`**: `b1::withdraw candidate_count=7` (satisfying=2, score=0.6438), `b3::safe-first candidate_count=5` (satisfying=5, score=0.000). See [`findings/postmortem-002-cdp-baseline-rerun.md` §Appendix](findings/postmortem-002-cdp-baseline-rerun.md).

### F-005 ancillary. Possible `tryCandidate` over-strictness on `int → int` constants

**Priority:** Low (ancillary observation; F-005 main is a spec-side rename, routed to language-team)
**Status:** **Closed by commit `6f2ea39`** (F-005 ancillary: `cdpCatalog` constants for unannotated sexp returns). Root cause: `matchesReturnType _ Nothing = False` suppressed all constant generation for sexp-parsed functions with no return-type annotation; only identity candidates passed. Fix: new private helper `matchesReturnTypeOrUnknown :: Type -> Maybe Type -> Bool` (`_ Nothing = True`) used in the `ints`, `bools`, `strings` arms of `cdpCatalog`; `Nothing` arms added to `lists` and `sums` cases. **Empirically confirmed at run `20260527T140751Z`**: `b5::double candidate_count=6` (satisfying=1, score=1.000). See [`findings/postmortem-002-cdp-baseline-rerun.md` §Appendix](findings/postmortem-002-cdp-baseline-rerun.md).

[`runs/20260526T233504Z-baseline/baseline.json`](runs/20260526T233504Z-baseline/baseline.json) shows `b5::double` (signature `int → int`, contract `result = n + n`) at `candidate_count: 1` where the §4.3.1 enumeration should produce 5 (`TrivIdentity n` + `TrivConstInt {0, 1, -1, 42}`). The four typed-int constants apparently failed [`compiler/src/LLMLL/WeaknessCheck.hs:158-186`](../../compiler/src/LLMLL/WeaknessCheck.hs) (`tryCandidate`)'s synthetic typecheck. Worth a brief look during the F-006 engineer turn — same module, possibly same root cause.

## Language-team

### F-004. Defined-score distribution collapses to {0.000}; midrange empty at pre-fix baseline — partially resolved post F-006

**Priority:** High
**Status:** **Closed** by language-team gate adjudication (2026-05-27). Gate outcome: **Outcome 1** (`cdp-discriminating-weak`; coarse pass/fail). See [`docs/design/contract-discriminative-power-proposal.md §2 Rev 3`](../../docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) for the F-007 scope-policy resolution that is part of this closure.

**Pre-fix state (run `20260526T233504Z`):** Across 37 contracted functions (pre-dedup), 4 produced a defined score and all 4 scored exactly `0.000`; midrange `(0.0, 1.0)` empty. Empirical confirmation of proposal §10 Risk #2 (small enumeration) as binding constraint.

**Post-fix state (definitive run `20260527T154040Z`):** After F-006 fix (alias threading for `Result`-returning functions), 11 of 26 contracted functions produce a defined score (42.3%); 4 are midrange (36.4% of defined), all `withdraw`-family contracts at `score=0.6438`. Score range [0.000, 1.000]. Adjudication upgraded from `cdp-null` to `cdp-discriminating-weak`.

The F-004 claim that "midrange is empty" no longer holds post-fix. What remains open for language-team: (a) `login-handler`-family contracts (3 of 11 defined scores) score `0.000` because all 12 type-compatible candidates satisfy the permissive auth postcondition — identity-and-const always passing a trivial contract is the proposal §10 Risk #2 pattern surviving in the auth domain; (b) the four-cell matrix at proposal §1 remains unpopulated on "verified-strong tight contracts" — `b5::double` and `banking::withdraw` at `score=1.000` are high-discrimination but their §4.3.1 enumeration still relies on small constant sets; (c) the v0.12+ LLM-generated-candidate widening per [`docs/design/invariant-discovery-review.md §5`](../../docs/archive/professor-reviews/invariant-discovery-review.md) remains load-bearing for `login-handler`-family and other permissive-postcondition contracts. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-004 and §Appendix B](findings/postmortem-002-cdp-baseline-rerun.md).

### F-005. `spec-inconsistent` warning name is misleading at small Ω

**Priority:** High
**Status:** **Closed** (2026-05-27; CE follow-up complete 2026-05-29). Compiler-side disambiguation closed by commit `0b5b249` (`fix: CDP WarnVacuousOverOmega disambiguation for tight-but-verified contracts (F-005)`). `WarnVacuousOverOmega` fires when `functionVerifies && inconsistent` (body-faithful-verified function whose contract admits no §4.3.1 candidate); `WarnSpecInconsistent` retained for `not functionVerifies && inconsistent`. Spec-side scope-policy clarification closed by language-team adjudication (2026-05-27): **Option B adopted** — user-facing label `"spec-too-tight-for-omega"` adopted for the `WarnVacuousOverOmega` condition; `"spec-inconsistent"` reserved for the semantic-UNSAT case. **CE follow-up complete (commit `3af3c06`, 2026-05-29):** `WarnVacuousOverOmega` → `WarnSpecTooTightForOmega` renamed in [`compiler/src/LLMLL/CDP.hs:115-116,146,298`](../../compiler/src/LLMLL/CDP.hs) (constructor declaration, wire-line label, `buildWarnings` usage); wire-line label `"vacuous-over-omega"` → `"spec-too-tight-for-omega"` active in all future `--cdp` output. **Historical baseline artifacts** (`experiments/cdp-0/runs/20260527T154040Z-baseline/` and `runs/20260527T140751Z-baseline/`) contain `"vacuous-over-omega"` — frozen pre-rename records; the divergence from the renamed label is expected and not a defect. See [`docs/design/contract-discriminative-power-proposal.md §5 Rev 5`](../../docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md).

`WarnSpecInconsistent` fires on 6 functions (`b5::double`, `banking::{withdraw, transfer, clamp-withdraw, withdraw-twice, compute-fee}`) — all real, body-faithful-verifiable contracts. The warning name reads as a semantic-inconsistency claim, but the underlying condition is `|⟦S⟧_Ω| = 0` over a small `Ω` — observational, not semantic, per the proposal §1 Rev 2 caveat. Two spec-side options: (a) rename to `no-candidate-satisfies` / `vacuous-over-omega`; (b) introduce a distinct `spec-too-tight-for-omega` and reserve `spec-inconsistent` for a (rare) semantic-inconsistency case. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-005](findings/postmortem-002-cdp-baseline-rerun.md).

### F-007. CDP-0 measurement scope excludes cross-module imports (proposal §2 silent on cross-module scope)

**Priority:** Medium
**Status:** **Closed** by language-team scope-policy adjudication (2026-05-27). Entry-module-only is the explicit conservative default; transitive scope deferred to v0.12+. Policy statement added to [`docs/design/contract-discriminative-power-proposal.md §2 Rev 3`](../../docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) ("Out of scope (deferred)" — Transitive CDP scope bullet; "Out of scope under v0.11 surface — sequencing" — denominator bullet extended with pre/post §8 comparability constraint). Location ruling: proposal §2, not `v0.11-cross-proposal-rollback-discipline.md` — module-boundary scope is a CDP-internal implementation policy, not a cross-proposal gate-outcome condition.

22 of 37 trust-report entries are cross-module imports that CDP-0 does not measure — they appear with `WarnNotRequested` because [`compiler/src/LLMLL/CDP.hs:computeCDPFor`](../../compiler/src/LLMLL/CDP.hs) iterates only over the entry-module `stmts`. Proposal §2 does not specify CDP scope across module boundaries. Routing options: (a) add an explicit scope-policy statement to proposal §2 Rev 3 ("entry-module only" as conservative default; "transitive" as future widening); (b) add to [`docs/design/v0.11-cross-proposal-rollback-discipline.md`](../../docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md) as a Rev 2 footnote. Current entry-module-only behavior is a reasonable conservative default — not blocking; documenting the policy improves pre/post comparability for the LT-INV §8 gate. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-007](findings/postmortem-002-cdp-baseline-rerun.md).

## Experiment-lead

### F-003. CDP-0 harness placed `--json` after the subcommand; absolute-path resolution missing

**Status:** **Closed in-session** by patch at [`experiments/cdp-0/scripts/cdp_baseline.py:83-100`](scripts/cdp_baseline.py) (uncommitted; lands with this findings ship). Two-line fix: `--json` moved to top-level position per `llmll --help` (`Usage: llmll [--version] COMMAND [--json]`); fixture path passed as absolute (`REPO_ROOT / rel_path`) so `cwd=compiler/` resolution works. Full evidence preserved at [`findings/postmortem-001-cdp-baseline-blocked.md` §F-003](findings/postmortem-001-cdp-baseline-blocked.md).

### F-007. CDP-0 harness over-aggregates cross-module entries (harness-side mirror of language-team F-007)

**Priority:** Medium
**Status:** **Closed in-session** by dedup patch at [`experiments/cdp-0/scripts/cdp_baseline.py:aggregate`](scripts/cdp_baseline.py) (lines 158–172). Within the `not-requested` bucket, `fn_name` is used as a dedup key; first occurrence per unique name is kept. Measured entries are untouched — `transfer` collision between banking (measured) and erc20 (not-requested) confirmed and correctly treated as distinct functions. Full run: 37 → 26 contracted entries; 11 duplicate cross-module entries removed. Primary-only run: 20 → 20 (no duplicates present). Adjudication label unaffected (`cdp-null` in both cases). See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-007](findings/postmortem-002-cdp-baseline-rerun.md).

### F-008. Driver fall-through adjudication label misleading on intermediate slice

**Priority:** Medium
**Status:** **Closed.** `cdp-null` threshold extended from `< 0.10` to `< 0.30` in [`manifest.json`](manifest.json) and [`scripts/cdp_baseline.py:186`](scripts/cdp_baseline.py). Both run artifacts patched in-place: `runs/20260526T233504Z-baseline/baseline.json` and `runs/20260527T140751Z-baseline/baseline.json` both now carry `adjudication_label: "cdp-null"`. The 30–50% slice falls cleanly to `cdp-discriminating-weak` (partial signal, no dead fallthrough). README §4 outcome-labels table updated. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-008](findings/postmortem-002-cdp-baseline-rerun.md).

## Documentation-lead

*(No findings routed to doc-lead at this time. F-005 spec rename and F-007 scope-policy statement would route here only after language-team adjudicates the proposal-side changes.)*
