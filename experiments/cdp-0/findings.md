# CDP-0 findings — H2-per-role index

> Per DOC-CONSOLIDATE M1 (settled 2026-05-24): downstream skills grep their own H2 anchor in this file. Postmortems are episodic under `findings/postmortem-NNN-<slug>.md`; this file is the consumer-routed surface that points into them.
>
> **Active postmortems:**
> - [`postmortem-001-cdp-baseline-blocked.md`](findings/postmortem-001-cdp-baseline-blocked.md) — three halted attempts on F-001 (compiler partial-record) + F-003 (harness flag placement). Both closed.
> - [`postmortem-002-cdp-baseline-rerun.md`](findings/postmortem-002-cdp-baseline-rerun.md) — successful baseline; load-bearing artifact for LT-INV §8 empirical-validation gate. F-004..F-008 surfaced.

## Compiler-engineer

### F-001. `fqResultToReport` partial-record crash on `--json verify` SAFE results

**Status:** **Closed by commit `e5e6d04`** (`fix: DiagnosticFQ — initialize reportPhase to "lh-fixpoint" (F-001)`) on branch `fix/diagnosticfq-partial-record`. CHANGELOG entry at commit `cc712aa` under `### Compiler — fix: DiagnosticFQ partial-record crash on \`--json verify\` SAFE (F-001)`. Four regression tests `DF-1`..`DF-4` in [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs) close the test gap. Full evidence preserved at [`findings/postmortem-001-cdp-baseline-blocked.md` §F-001](findings/postmortem-001-cdp-baseline-blocked.md).

### F-006. `Result`-returning functions get zero candidates from §4.3.1 enumeration

**Priority:** Medium (highest signal-to-effort in the priority matrix)
**Status:** **Closed by commit `6f2ea39`** (`fix: WeaknessCheck — thread STypeDef aliases into synthetic type-check (F-006)`). Root cause was confirmed as refinement-aliased `okT`: `tryCandidate` called `typeCheck builtinEnv [syntheticStmt]` with an empty `tcAliasMap`, so `expandAlias (TCustom "PositiveInt")` returned the opaque node unchanged and `structuralUnify` rejected every candidate. Fix: `generateForStmt` now receives the full module-level `[Statement]` list and prepends `[s | s@STypeDef{} <- allStmts]` before the synthetic typecheck so `checkStatements` populates `tcAliasMap` with module-level aliases. Six regression tests F6-1–F6-6 in [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs) close the test gap. CHANGELOG entry at commit `cc712aa` (amended in staged docs pass) under `### Compiler — fix: WeaknessCheck zero-candidate generation (F-006 / F-005 ancillary)`. **Empirical re-confirmation** of `b1::withdraw candidate_count ≥ 2` and `b3::safe-first candidate_count ≥ 2` post-fix is owed to experiment-lead (CDP-0 re-run against HEAD of `fix/diagnosticfq-partial-record`).

Across 5 canonical Tier-1 benchmarks (`b1::withdraw`, `b3::safe-first`, plus three `withdraw-demo` variants), all returning `Result[T, E]`, [`compiler/src/LLMLL/CDP.hs:computeCDPFor`](../../compiler/src/LLMLL/CDP.hs) records `candidate_count: 0` with `WarnCandidatesEmptyUnderLimit`. [`compiler/src/LLMLL/WeaknessCheck.hs:cdpCatalog`](../../compiler/src/LLMLL/WeaknessCheck.hs) is wired to produce `[TrivConstSuccess okT, TrivConstError]` for `TResult okT _`, so both candidates failed the synthetic typecheck at [`compiler/src/LLMLL/WeaknessCheck.hs:174`](../../compiler/src/LLMLL/WeaknessCheck.hs) (`typeCheck builtinEnv [syntheticStmt]`). Three suspected causes — `Success`/`Error` constructors absent from `builtinEnv`, refinement-aliased `okT` rejecting `defaultExpr okT`, or `Result` type-alias resolving to `TCustom "Result"` rather than `TResult okT errT`. Targeted reproduction with `b1::withdraw` would distinguish.

**Acceptance:** `b1::withdraw` and `b3::safe-first` return `candidate_count ≥ 2` post-fix; downstream `score` populates. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-006](findings/postmortem-002-cdp-baseline-rerun.md).

### F-005 ancillary. Possible `tryCandidate` over-strictness on `int → int` constants

**Priority:** Low (ancillary observation; F-005 main is a spec-side rename, routed to language-team)
**Status:** **Closed by commit `6f2ea39`** (F-005 ancillary: `cdpCatalog` constants for unannotated sexp returns). Root cause: `matchesReturnType _ Nothing = False` suppressed all constant generation for sexp-parsed functions with no return-type annotation; only identity candidates passed. Fix: new private helper `matchesReturnTypeOrUnknown :: Type -> Maybe Type -> Bool` (`_ Nothing = True`) used in the `ints`, `bools`, `strings` arms of `cdpCatalog`; `Nothing` arms added to `lists` and `sums` cases. **Empirical re-confirmation** of `b5::double candidate_count ≥ 5` post-fix is owed to experiment-lead (CDP-0 re-run against HEAD of `fix/diagnosticfq-partial-record`).

[`runs/20260526T233504Z-baseline/baseline.json`](runs/20260526T233504Z-baseline/baseline.json) shows `b5::double` (signature `int → int`, contract `result = n + n`) at `candidate_count: 1` where the §4.3.1 enumeration should produce 5 (`TrivIdentity n` + `TrivConstInt {0, 1, -1, 42}`). The four typed-int constants apparently failed [`compiler/src/LLMLL/WeaknessCheck.hs:158-186`](../../compiler/src/LLMLL/WeaknessCheck.hs) (`tryCandidate`)'s synthetic typecheck. Worth a brief look during the F-006 engineer turn — same module, possibly same root cause.

## Language-team

### F-004. Defined-score distribution collapses to {0.000}; midrange empty across canonical corpus

**Priority:** High
**Status:** Open. Routed to language-team for spec-side judgment.

Across 37 contracted functions in the verify-clean CDP-0 corpus, only 4 produced a defined score, and all 4 scored exactly `0.000` with `WarnIdentitySatisfiesPost`. Aggregate mean / median / p10 / p50 / p90 / min / max all `0.000`; midrange `(0.0, 1.0)` empty. The §4.3.1 enumeration produces no midrange score on the canonical Tier-1 benchmark corpus — empirical confirmation of proposal §10 Risk #2 (small enumeration) as the binding constraint, not just a future-work caveat. The four-cell matrix at [`docs/design/contract-discriminative-power-proposal.md`](../../docs/design/contract-discriminative-power-proposal.md) §1 (verified-strong / verified-weak / tested-strong / asserted-strong) cannot be populated from this baseline. The v0.12+ widening to LLM-generated candidates per [`docs/design/invariant-discovery-review.md §5`](../../docs/design/invariant-discovery-review.md) is load-bearing for CDP's utility as a measurement axis. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-004](findings/postmortem-002-cdp-baseline-rerun.md).

### F-005. `spec-inconsistent` warning name is misleading at small Ω

**Priority:** High
**Status:** Compiler-side rename **closed by commit `0b5b249`** (`fix: CDP WarnVacuousOverOmega disambiguation for tight-but-verified contracts (F-005)`). `WarnVacuousOverOmega` fires when `functionVerifies && inconsistent` (body-faithful-verified function whose contract admits no §4.3.1 candidate); `WarnSpecInconsistent` retained for `not functionVerifies && inconsistent`. Spec-side scope-policy clarification (**language-team**) remains open — see postmortem-002 §F-005 for the two spec options.

`WarnSpecInconsistent` fires on 6 functions (`b5::double`, `banking::{withdraw, transfer, clamp-withdraw, withdraw-twice, compute-fee}`) — all real, body-faithful-verifiable contracts. The warning name reads as a semantic-inconsistency claim, but the underlying condition is `|⟦S⟧_Ω| = 0` over a small `Ω` — observational, not semantic, per the proposal §1 Rev 2 caveat. Two spec-side options: (a) rename to `no-candidate-satisfies` / `vacuous-over-omega`; (b) introduce a distinct `spec-too-tight-for-omega` and reserve `spec-inconsistent` for a (rare) semantic-inconsistency case. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-005](findings/postmortem-002-cdp-baseline-rerun.md).

### F-007. CDP-0 measurement scope excludes cross-module imports (proposal §2 silent on cross-module scope)

**Priority:** Medium
**Status:** Open. Routed to language-team for scope-policy clarification.

22 of 37 trust-report entries are cross-module imports that CDP-0 does not measure — they appear with `WarnNotRequested` because [`compiler/src/LLMLL/CDP.hs:computeCDPFor`](../../compiler/src/LLMLL/CDP.hs) iterates only over the entry-module `stmts`. Proposal §2 does not specify CDP scope across module boundaries. Routing options: (a) add an explicit scope-policy statement to proposal §2 Rev 3 ("entry-module only" as conservative default; "transitive" as future widening); (b) add to [`docs/design/v0.11-cross-proposal-rollback-discipline.md`](../../docs/design/v0.11-cross-proposal-rollback-discipline.md) as a Rev 2 footnote. Current entry-module-only behavior is a reasonable conservative default — not blocking; documenting the policy improves pre/post comparability for the LT-INV §8 gate. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-007](findings/postmortem-002-cdp-baseline-rerun.md).

## Experiment-lead

### F-003. CDP-0 harness placed `--json` after the subcommand; absolute-path resolution missing

**Status:** **Closed in-session** by patch at [`experiments/cdp-0/scripts/cdp_baseline.py:83-100`](scripts/cdp_baseline.py) (uncommitted; lands with this findings ship). Two-line fix: `--json` moved to top-level position per `llmll --help` (`Usage: llmll [--version] COMMAND [--json]`); fixture path passed as absolute (`REPO_ROOT / rel_path`) so `cwd=compiler/` resolution works. Full evidence preserved at [`findings/postmortem-001-cdp-baseline-blocked.md` §F-003](findings/postmortem-001-cdp-baseline-blocked.md).

### F-007. CDP-0 harness over-aggregates cross-module entries (harness-side mirror of language-team F-007)

**Priority:** Medium
**Status:** Open. Self-routed to experiment-lead.

22 of 37 trust-report entries fire `WarnNotRequested` (cross-module imports). The harness over-aggregates: the same function appears once as entry-module (measured) under one fixture and again as cross-module-not-requested under another. Two reasonable harness-side fixes: (a) deduplicate on canonical qualified-name keys in [`experiments/cdp-0/scripts/cdp_baseline.py:aggregate`](scripts/cdp_baseline.py); (b) extend `computeCDPFor` to walk the module cache (requires routing compiler-engineer for a CDP scope change). Option (a) is local to the harness and one-pass-change; recommended pending language-team's adjudication on F-007 (language-team H2) since the scope policy bounds what dedup means. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-007](findings/postmortem-002-cdp-baseline-rerun.md).

### F-008. Driver fall-through adjudication label misleading on intermediate slice

**Priority:** Medium
**Status:** Open. Self-routed.

[`manifest.json:outcome_labels`](manifest.json) defines four thresholds with an unintended fourth slice (`0.10 ≤ defined < 0.50`) that falls through to `cdp-discriminating-weak` with a defensive comment but no JSON-emit flag. On the load-bearing baseline run, the corpus produced `defined_fraction = 0.108`, landing in this slice and emitting a positive-sounding label when the underlying data is closer to `cdp-null`. Two options: (a) extend `cdp-null` to `defined_fraction < 0.30`; (b) introduce a fourth label `cdp-discriminating-thin`. One-line manifest + driver edit. Should land before publishing this baseline as the LT-INV §8 gate's adjudicated comparison anchor. See [`findings/postmortem-002-cdp-baseline-rerun.md` §F-008](findings/postmortem-002-cdp-baseline-rerun.md).

## Documentation-lead

*(No findings routed to doc-lead at this time. F-005 spec rename and F-007 scope-policy statement would route here only after language-team adjudicates the proposal-side changes.)*
