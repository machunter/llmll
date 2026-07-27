# repair-loop harness — findings (consolidated 2026-05-25 per DOC-CONSOLIDATE §M1)

> Previously fanned out across `findings/{compiler-engineer,language-team}.md`. Collapsed to H2-per-role per `docs/design/doc-consolidation-2026-05-24-proposal.md` §4.3. The `experiment-lead` and `documentation-lead` roles had no findings files on this harness; empty H2 stubs are preserved for the grep-anchor contract.

## Compiler-engineer


**Source:** Integrated postmortem at `findings/postmortem-001-apparatus-validation.md`. This file extracts compiler-engineer-actionable items only; the full evidence trail (sample composition, run-dir citations, per-cell data) lives in the postmortem.
**Date:** 2026-05-12 (Phase-2 calibration outcome; Addendum 11; revised 2026-05-12 by Addendum 14; CE-B closed 2026-05-12 by MOD-PBT-1 / v0.10.3; R6d engineer track shipped 2026-05-12 → closure notes below).

This file covered two open work units routed from Phase 2 and tracks a third that surfaced and closed same-day:

- **CE-A — verify-fixpoint diagnostic surface (F-028).** Closed 2026-05-12 by postmortem-001 Addendum 14.
- **CE-B — PBT FuncEnv lacks imported-module def-logic (F-018).** Closed 2026-05-12 by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`).
- **CE-C — Trust-report `tier_profile` aggregate (R6d).** Closed 2026-05-12 by `bb1bd98` + `bbab67b`. The R6d engineer-track surfaced from `findings.md` `## Language-team` §LT-A's adjudication; the work shipped the same day.

All three compiler-engineer tracks routed from Phase 2 are now closed. No further compiler-engineer action in scope for `findings/postmortem-001`; the R6d closure has full evidence in postmortem-001 Addendum 15.

A **harness-design** item (capability-probe in `run_matrix.py` prereqs, F-025) remains routed to `experiment-lead` — unchanged. Mentioned here only because the apparatus event that motivated it (Plan Mode pin) was diagnosed during Phase 2; full detail in postmortem-001 Addendum 11 §F-025.

---

### CE-A · verify-fixpoint diagnostic surface (F-028) — closed, no work needed

**Status:** Closed by postmortem-001 Addendum 14 (2026-05-12). No compiler patch required. No harness patch required.

The Addendum-11 framing claimed `verify-fixpoint`'s diagnostic channel was silent on failure ("stderr empty across 15 LLMLL turns"). That observation was true for the `stderr` field but incomplete — the actual diagnostic content lives on `stdout`, which the harness's `_run_verifier_chain` already captures and propagates to the agent via `context/turn_NN_verifier.json`. Read-only retrospective inspection of Phase-2 cell 01's turn-3 stdout (Liquid-Fixpoint SAFE on a passing solution) and turn-4 stdout (`(error :phase parse :file "solution.llmll" :line 52 :col 10 :message "reserved word post used as identifier" ...)` on a self-broken solution) showed clean, actionable diagnostics passing through the existing pipeline.

Full evidence in `findings/postmortem-001-apparatus-validation.md` Addendum 14 §"F-028 reframed — diagnostics exist; agent does not productively iterate on them". The substantive open question reattaches to **F-029 (non-monotonic repair)** — agent-capability axis, routed to experiment-lead + language-team, not to compiler-engineer.

No compiler-engineer action on F-028. Phase-3 gate from this file narrows to CE-B only.

---

### CE-B · PBT FuncEnv lacks imported-module def-logic (F-018, carried from Addendum 8) — CLOSED

**Status:** Closed 2026-05-12 by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`). No further compiler-engineer action.

**Priority (historical):** High — open since Phase 1.75. Phase 2 produced confirming empirical evidence (F-030).

#### Evidence

This finding is documented in detail in postmortem-001 Addendum 8 (compiler-side discharge channel) and Addendum 11 §F-030 (Phase-2 empirical confirmation). The summary for this file:

- Across n=3 LLMLL cells in Phase 2, agent emitted 2–3 `(check ...)` blocks per solution (cells 01–03).
- Per `evaluation.json:scoring.correctness_subscores.core_behavior` for each cell: `passed=0, failed=0, skipped=2-3, channel=llmll-pbt`.
- Trust report entries for these solutions are at `asserted` tier, never `tested` — i.e., the `(check ...)` blocks do not engage the test channel that would lift entries to `tested` tier.

This is the structural mechanism Addendum 8 predicted (F-017, now revised and tracked as F-018 against compiler-engineer): the PBT FuncEnv does not see imported-module `def-logic`, so checks defined in the solution module cannot reach functions from the standard prelude or other imports when the runner instantiates them.

#### Why we saw what we saw

Per Addendum 8's diagnosis: `compiler/src/LLMLL/PBT.hs` constructs a per-test FuncEnv from the *current* module's `def-logic` declarations only. Phase 2's evidence is consistent with this — solutions that depend on `list-fold`, `pair`, `Result`, etc., have those calls in the `(check ...)` body, the PBT runner cannot resolve them, and the check skips silently.

#### Fix

Carried from Addendum 8: extend the PBT FuncEnv with imported-module `def-logic` declarations (whichever modules are in the solution's import set). The Phase-2 data did not surface a new mechanism; it confirmed the predicted one fires under realistic agent emissions.

#### Acceptance

Closing CE-B / F-018 should produce the following on re-probe:

- For a cell whose solution emits `(check ...)` blocks that reference standard-library `def-logic`, `evaluation.json:correctness_subscores.core_behavior` reports `skipped < total` (some checks execute).
- At least one trust-report entry crosses from `asserted` to `tested` tier when the corresponding `(check)` block passes.
- Phase-2 cell 02's solution (`runs/20260512T033017Z-.../solution.llmll`) re-run under the patched compiler shows non-zero `passed` in its core_behavior subscore.

---

#### Closure note (2026-05-12)

The fix described in "Fix" above shipped as MOD-PBT-1 in v0.10.3 (commit `d1b7a58`). `doTest` switched from `loadStatements` to `loadStatementsMulti`; a new `assembleTestStatements` helper in `LLMLL.PBT` concatenates each `(open path)`-targeted imported module's `SDefLogic` declarations ahead of the local statement list before invoking `runPropertyTests`. 5 new tests in `ModuleSpec.hs` M-08 block. 584 → 589 Haskell tests; 37 Python unchanged. The companion docs commit `b9b5eee` adds the §8.6 / §4.8 spec note.

The acceptance condition above ("at least one trust-report entry crosses from `asserted` to `tested` tier when the corresponding `(check)` block passes") was **not directly tested** by R6d's re-probe — the re-probe re-verified the three Phase-2 cells' final-turn solutions but did not re-run `llmll test` on them. A focused re-test of those solutions under v0.10.4-pre is a follow-up question, tracked under `findings.md` `## Language-team` §LT-B status update.

---

### CE-C · Trust-report `tier_profile` aggregate (R6d) — CLOSED

**Status:** Closed 2026-05-12 by `bb1bd98` + `bbab67b`. No further compiler-engineer action.

#### Evidence

`findings.md` `## Language-team` §LT-A's R6d resolution required a fixed-arity tier-count aggregate over the trust report, hosted compiler-side with independent versioning from the source JSON-AST schema. The work shipped same-day on 2026-05-12:

- `bb1bd98` (`feat(trust): add tier-count profile aggregate to trust-report emit (R6d)`) — `TierProfile` record + `aggregateTiers` function in `compiler/src/LLMLL/TrustReport.hs`, diamond-meet semantics preserved via `teEffectiveLevel` (pre=contract_checked, post=tested → effective level `asserted` → increments `tpAsserted` only, never both `tpContractChecked` and `tpTested`). `formatTrustReportJson` emits `tier_profile` + `trust_report_version: "1.0.0"` alongside the unchanged `entries` / `summary` / `suppressions` blocks. New `docs/llmll-trust-report.schema.json` (JSON Schema draft 2020-12) documents the full trust-report emit with versioning independent of `docs/llmll-ast.schema.json:expectedSchemaVersion` ("0.4.0" untouched — emit-side change is semantically orthogonal to the parser-input schema; bumping source `schemaVersion` would force ~22 `.ast.json` fixture rewrites for a change those fixtures do not touch). 5 new tests under "v0.10.4 tier-count profile (R6d)" describe block; 589 → 594 Haskell.
- `bbab67b` (`docs(spec): note tier_profile aggregate on trust-report JSON emit in §4.4.4 (R6d)`) — one-sentence `LLMLL.md §4.4.4` addition pointing readers at `docs/llmll-trust-report.schema.json` and referencing the `LLMLL.md §4.4.1:344` diamond-lattice no-scalarization discipline that disqualifies any aggregation over `tier_profile`.

#### Acceptance

- ✅ `compiler/src/LLMLL/TrustReport.hs` emits the `tier_profile` aggregate.
- ✅ `docs/llmll-trust-report.schema.json` validates with `additionalProperties: false` on the trust-report root and the required-field list `["trust_report_version", "entries", "summary", "tier_profile", "suppressions"]`.
- ✅ Re-probe of three Phase-2 cells (postmortem-001 Addendum 15) confirms the aggregate matches per-entry tier classifications and is consumable by the patched harness evaluator (`scripts/evaluate_run.py:_summarize_trust_report`).

#### Closure

No follow-up engineer track from R6d. The pending v0.10.4 release will ship the harness-side changes (experiment-lead) plus doc-lead's CHANGELOG entry, roadmap §LT-A close-out row, and the cross-link from `docs/design/language-comparison-experiments.md §Soundness Assessment` to the new harness-doc section.

---

### CE-D · F-034 — `evalBuiltinApp` residual builtin coverage on c02/c03-shape (post-Addendum-18, 2026-05-14; **CLOSED by Addendum 19, 2026-05-15**)

**Status:** **CLOSED-shipped, mechanism empirically confirmed.** F-034 shipped in v0.10.6 (commit `cb2e71f`, merge `46f9554`); Addendum-19 re-probe under the v0.10.6-shipped binary moved c02 from 0/10 → 10/10 and c03 from 0/10 → 10/10 on `samples_run ≥ 1` (full evidence in `postmortem-001-apparatus-validation.md` Addendum 19). The empirical c02/c03 unblocker — a superset of F-033's named scope (`unwrap` + GaveUp diagnostic refinement) — is now in the shipped binary.

**Priority:** **High — gates strong-form Phase-3 `tested`-tier signal on c02/c03-shape problems**, which is the load-bearing axis for H1-Assurance on the Phase-3 problem suite. OBLIG-PBT-4 closure on c01-shape is empirically confirmed (15/15 properties on c01-subjects produced `.verified.json` sidecar writes; 4/5 tries lift `tier_profile_post.tested = 1`); the only path-1 engineer item remaining before Phase 3 launch is this one. **Addendum 19 closes this item; no further engineer scope.**

#### Evidence

Addendum-18 matrix on the v0.10.6-candidate binary built atop merge `d220632` shows c02 0/10 properties and c03 0/10 properties achieving `samples_run ≥ 1` under the new F-033 diagnostic. The diagnostic correctly attributes every Skipped property's GaveUp to body-evaluator discard:

> `"property body did not reduce on any sample (1000 evaluated, 0 returned bool — likely unmodeled builtin or unreduced callee body in property body)"`

[Contracts.hs:412-472](../../compiler/src/LLMLL/Contracts.hs#L412-L472) — `evalBuiltinApp` clause set. Missing clauses on c02/c03's transfer-body call chains:

| builtin | type-checker signature ([TypeCheck.hs:90-120](../../compiler/src/LLMLL/TypeCheck.hs#L90-L120)) | used in (c02/c03) | clause? |
|---|---|---|---|
| `list-filter` | `[list[a], fn[a] -> bool] -> list[a]` | c02 `map_get`/`map_insert`; c03 `find-account` | **no** |
| `list-prepend` | `[a, list[a]] -> list[a]` | c02 `map_insert` | **no** |
| `list-empty` | `[] -> list[a]` | c02 `create_ledger`; c03 `create-ledger` | **no** |
| `string-concat-many` | `[list[string]] -> string` | c02 `transfer` (log entry construction) | **no** |
| `int-to-string` | `[int] -> string` | c02 `transfer` (log entry construction) | **no** |
| `list-head` | `[list[a]] -> Result a string` (returns `Result`!) | c02 `map_get`; c03 `find-account` | **bug**: existing clause at [Contracts.hs:434](../../compiler/src/LLMLL/Contracts.hs#L434) returns `Just hd` (raw element) instead of `Just (EApp "Success" [hd])`; the `[EApp "nil" []]` arm is also absent (should return `Just (EApp "Error" [...])`) |

Mechanism: a c02 property body `(match (transfer l f t a) ((Success new_l) ...) ((Error _) true))` reduces transfer's body, which reduces `(map_get accounts from)` (uses `list-filter`), which returns `Nothing` from `evalBuiltinApp`. The `Maybe Expr` short-circuits up; the prop closure returns `QC.discard`; `bodyDiscardCount` increments. Repeat 1000 times → GaveUp with the new diagnostic text. c03's `find-account` uses `list-filter` directly; same propagation.

The `list-head`-returns-raw-element bug is independent of the missing-clauses set: even if `list-filter` were modeled, c02 `map_get` body's `(match (list-head matches) ((Success p) ...) ((Error _) ...))` would still fail to reduce because `list-head` returns `hd` not `(Success hd)`. Both must move for c02 to lift. c03's `find-account` similarly does `(list-head matches)` after `list-filter`.

#### Scope

Mechanical. Each clause is a 2-3-line pattern match analogous to existing clauses (`list-fold`, `list-map`, `unwrap-or`). Suggested patches:

```haskell
-- Add to Contracts.hs:412+ (placement adjacent to existing list-* clauses)
evalBuiltinApp _ _ "list-empty"   []          = Just (EApp "nil" [])
evalBuiltinApp _ _ "list-prepend" [x, list]   = Just (EApp "cons" [x, list])
evalBuiltinApp fe fuel "list-filter" [list, fn] = filterCons fe fuel list fn
evalBuiltinApp _ _ "int-to-string" [ELit (LitInt n)] = Just (ELit (LitString (T.pack (show n))))
evalBuiltinApp _ _ "string-concat-many" [list] = stringConcatMany list

-- Fix the existing list-head clauses:
evalBuiltinApp _ _ "list-head" [EApp "cons" [hd, _]] = Just (EApp "Success" [hd])
evalBuiltinApp _ _ "list-head" [EApp "nil"  []]      = Just (EApp "Error" [ELit (LitString "list-head: empty list")])
```

`filterCons` mirrors `foldCons` / `mapCons` at [Contracts.hs:497+](../../compiler/src/LLMLL/Contracts.hs#L497) — apply the predicate lambda per element, keep cons cells where predicate reduces to `True`. `stringConcatMany` walks the cons-chain of `LitString` literals and concatenates. Both share the existing fuel discipline.

#### Acceptance — MET (Addendum 19, 2026-05-15)

A v0.10.6+ compiler run on `experiments/repair-loop/runs/20260514T233334Z-reprobe-pbt45-c01c02c03-v0.10.6-candidate/c02/solution.k1.llmll` reports `samples_run ≥ 1` on either property; likewise for c03. Optional but recommended: a c02-subjects variant (analogous to the c01-subjects cell in Addendum-18) constructed with `:subjects [transfer total_balance]` etc. confirms the OBLIG-PBT-4 path is end-to-end-functional on c02-shape too — the c01-subjects pass confirms only the path's correctness on c01-shape; the c02 end-to-end test additionally validates the F-034 + OBLIG-PBT-4 interaction.

**Addendum-19 result** (`runs/20260515T072155Z-reprobe-pbt45-c01c02c03-v0.10.6-shipped/`):

- ✅ c02 10/10 property×try records `samples_run ≥ 1`; PBTPassed 9/10 (1 PBTSkipped on near-threshold QC precondition-failure discard — orthogonal to F-034).
- ✅ c03 10/10 property×try records `samples_run ≥ 1`; PBTPassed 7/10 (3 PBTSkipped on the same QC mechanism on property 1's `(for-all [f t])` precondition).
- ✅ c02-subjects (H3 optional clause) 3/5 tries achieve `tier_profile_post.tested ≥ 1` — OBLIG-PBT-4 path validated end-to-end on c02-shape.
- ✅ Joint Addendum-17 criterion holds (c01-subjects 3/5 + c02 10/10 + c03 10/10).
- ✅ All mechanical scope shipped at [Contracts.hs:432-485](../../compiler/src/LLMLL/Contracts.hs#L432); 10 new tests in `Spec.hs` `F-034 evalBuiltinApp residual builtin coverage` describe block (per CHANGELOG.md §v0.10.6 / "Test coverage").

#### Sequencing

Engineer-adjudicated. Two options:

1. **Combined cut v0.10.6** (OBLIG-PBT-4 + F-034 in one release). Experiment-lead view: cleaner empirical signal because c02/c03 cannot be re-probed against a standalone-OBLIG-PBT-4 binary as a separate gate; doc-lead's combined seal covers both atomically; the v0.10.6 CHANGELOG entry reads as one OBLIG-PBT-4-and-PBT-5 release.
2. **Split cut v0.10.6 (OBLIG-PBT-4 only) + v0.10.7 (F-034)**. Faster ship cadence on the OBLIG-PBT-4 surface; doc-lead splits into two passes; Phase 3 launch waits on v0.10.7 either way.

Doc-lead's surface is the same in both options; only the release-grouping differs.

#### Routing

- **F-034 → compiler-engineer** (this entry). No design decision pending.
- **OBLIG-PBT-4 closure → already shipped on this branch**, no action; routing here is closure-only for the compiler-engineer file (see CE-D-OBLIG-PBT-4 below).
- **Doc-lead waits** on F-034 land; do not invoke until both items are in the release branch (or, under option 2, invoke once per release cut).

---

### CE-D-OBLIG-PBT-4 · OBLIG-PBT-4 `:subjects` opt-in — closed-shipped, mechanism confirmed (Addendum 18, 2026-05-14)

**Status:** **Closed-shipped, mechanism empirically confirmed on c01-shape.** No further engineer action from this finding. Tracked here for closure-bookkeeping symmetry with CE-A/CE-B/CE-C.

Implementation: [Syntax.hs:425-437](../../compiler/src/LLMLL/Syntax.hs#L425-L437) (`propSubjects` field on `Property`), [Parser.hs:290-326](../../compiler/src/LLMLL/Parser.hs#L290-L326) (text-syntax parsing), [ParserJSON.hs:216-241](../../compiler/src/LLMLL/ParserJSON.hs#L216-L241) (JSON-AST parsing + dedupe + empty-list rejection), [PBT.hs:687-720](../../compiler/src/LLMLL/PBT.hs#L687-L720) (`processRun` per-subject-DLTested writeback branch), [docs/llmll-ast.schema.json](../../docs/llmll-ast.schema.json) (schema bump `0.4.0` → `0.5.0` for additive optional `CheckDecl.subjects`).

Acceptance (Addendum 18 §F-OBLIG-PBT-4):
- ✅ Parser accepts `:subject f` sugar and `:subjects [f g …]` form.
- ✅ Writeback emits per-subject `DLTested n` records.
- ✅ Shared `pbt_witnesses` hash across all per-subject records of one property (canonical-body hashing is content-stable across the matrix).
- ✅ R6d `effective_level` machinery bounds dependent callees correctly (body-faithful, not isolation-faithful).
- ✅ End-to-end: c01-subjects 4/5 tries achieve `tier_profile_post.tested ≥ 1`; the remaining 1/5 misses on orthogonal near-threshold QC variance.

---

### CE-E · F-042 cluster — harness-script defence-in-depth on `run_matrix.py` (postmortem-005, 2026-05-21)

**Status:** **OPEN.** Two small Python edits on `experiments/repair-loop/scripts/run_matrix.py`, sourced from `findings/postmortem-005-claude-deepening.md:91-110`. No Haskell compiler footprint; no spec, schema, or roadmap impact. Routed to compiler-engineer per postmortem-005's priority matrix (`postmortem-005-claude-deepening.md:136-137`) and the prior harness-script convention that placed `experiments/repair-loop/scripts/*` under compiler-engineer scope (CE-D-OBLIG-PBT-4 lineage).

**Priority:** Defence-in-depth. Neither item blocked the Phase-3 deepening probe; both produced procedural noise that is recoverable by hand but would compound across future matrices.

#### CE-E-1 · F-042a `--batch-id` double-suffix on resume

**Evidence.** [`experiments/repair-loop/scripts/run_matrix.py:249-253`](scripts/run_matrix.py#L249-L253) — `resolve_batch_dir` computes `name = f"{batch_id}-{label}"` where `label = manifest.get("batch_label") or "matrix"`. An operator who passes `--batch-id 20260520T173939Z-matrix` (the directory name observed under `runs/`) gets a sibling batch directory `runs/20260520T173939Z-matrix-matrix/` on resume. In the deepening probe, slice 2 (Python, 9 cells) wrote to the sibling directory because the resume from cell 10 was launched with the directory-name form of the batch-id (`postmortem-005-claude-deepening.md:96-98`).

**Fix.** Hard-error on a suffixed `--batch-id` rather than silently rewriting operator input. In `resolve_batch_dir`, after resolving `batch_id` and `label`, raise `SystemExit` with a message naming the bare stamp the operator should pass if `batch_id.endswith(f"-{label}")`. Silent rewriting of operator-supplied identifiers is the wrong discipline for an experiment harness — the existing `check_prereqs` posture (`run_matrix.py:256+`) accumulates and reports failures rather than papering over them, and F-042a should match that.

**Acceptance.** A follow-on probe resumed via the directory-name form fails fast with a clear error message that names the bare-stamp form. New Python test `test_resolve_batch_dir_rejects_suffixed_id` asserts `SystemExit` with the expected message.

#### CE-E-2 · F-042b end-of-matrix `rc=1` on prior-cell failure

**Evidence.** [`experiments/repair-loop/scripts/run_matrix.py:203`](scripts/run_matrix.py#L203) — `return 1 if any_failed else 0` at end-of-matrix overloads `rc=1`. `any_failed` is set True at the first infra-fail or harness-error cell and persists. In the deepening probe, slice 3 (Go, cells 19-27) finished 9/9 target-reached but the matrix returned `rc=1` because cell 5 had earlier infra-failed in slice 1; the task notification surfaced "failed with exit code 1" despite a clean slice 3 (`postmortem-005-claude-deepening.md:104-108`).

**Fix.** Introduce `EXIT_COMPLETED_WITH_PRIOR_FAILURES = 4` as a module-level constant and return it from the end-of-matrix path when `any_failed` is True. `rc=1` retains its current meaning (matrix aborted / internal harness error) and any in-function early returns that emit `rc=1` are unaffected. Document the exit-code table in the `--help` epilog (0 = clean, 1 = aborted, 2 = circuit-breaker, 3 = interim pause, 4 = completed with prior failures).

**Acceptance.** End-of-matrix exit code disambiguates "complete with prior failures" from "aborted." New Python test `test_end_of_matrix_returns_4_on_prior_failures` invokes the matrix entry point on a stub manifest that forces one infra-fail followed by clean cells; asserts `rc == 4`.

#### Bundling

Both items touch the same module within adjacent surface; ship as one commit on branch `harness/f-042-batch-id-and-exit-codes`. Estimated diff ≲40 LOC including the two pytest cases. 37 → 39 Python tests. 570 Haskell unchanged.

#### Risks

1. **`rc=1` semantic split is visible to external callers.** Grep `experiments/` and `docs/` for `rc=1` / `exit code 1` / `returncode == 1` before shipping; update any caller that consumes the old binary semantic. Postmortem-005:105 itself references the old semantic and is fine to leave as a historical record.
2. **Out-of-skill-scope routing.** F-042 is harness-Python, not Haskell compiler. The routing convention from CE-D-OBLIG-PBT-4 places this under compiler-engineer; if the user prefers experiment-lead instead, the plan content is unchanged but the slot moves.

#### Sequencing

No dependencies. Land any time before the next Phase-3-shape matrix. Not gating on language-team or doc-lead.

---

### Routing

- **CE-A is closed** (postmortem-001 Addendum 14). No compiler-engineer action.
- **CE-B is closed** (MOD-PBT-1 / v0.10.3, 2026-05-12). Was structurally the blocker behind F-030; F-018's PBT FuncEnv extension shipped. The empirical question "does `(check ...)` now elevate obligations to `tested` under realistic agent emissions?" remains open under `findings.md` `## Language-team` §LT-B and is an experiment-lead re-probe, not compiler-engineer work.
- **CE-C is closed** (R6d / `bb1bd98` + `bbab67b`, 2026-05-12). No follow-up engineer track from R6d.
- **CE-D is closed** (F-034, shipped v0.10.6 commit `cb2e71f`; mechanism confirmed by Addendum 19 re-probe under v0.10.6-shipped binary, 2026-05-15). Tracked here for closure-bookkeeping only.
- **CE-D-OBLIG-PBT-4 is closed** (`oblig-pbt-4-5/subject-metadata-and-eval-coverage` working tree atop merge `d220632`, mechanism confirmed by Addendum 18 on c01-shape and Addendum 19 on c02-shape). Tracked here for closure-bookkeeping only.
- **CE-E is OPEN** (F-042a + F-042b, postmortem-005, 2026-05-21). Harness-script defence-in-depth on `run_matrix.py`. Plan above; awaiting user approval to land Python patch on branch `harness/f-042-batch-id-and-exit-codes`. No Haskell, schema, spec, or roadmap touch.

All Haskell-compiler tracks from `findings/postmortem-001-apparatus-validation.md` are closed; the doc-lead surface (CHANGELOG.md §v0.10.6 §"Empirical hooks not yet exercised" entry retraction for c02/c03) is the only residual doc-side item. CE-E is the only open compiler-engineer track in the repair-loop arc.

---

## Language-team


**Source:** Integrated postmortem at `findings/postmortem-001-apparatus-validation.md`. This file extracts language-team-actionable items only; the full evidence trail (sample composition, run-dir citations, per-cell data) lives in the postmortem.
**Date:** 2026-05-12 (Phase-2 calibration outcome; Addendum 11)

This file covers three open work units routed from Phase 2:

- **LT-A — Trust-tier predicate vocabulary (F-026 + F-027).** Phase-3-gating. The current predicate accepts `asserted` (declared-but-unverified) as terminal-reached, conflating stated intentions with verified evidence. Cross-target comparison (LLMLL `trust-tier` vs Python/Go `all-pass`) is structurally non-equivalent.
- **LT-B — LLMLL in-source `(check ...)` channel design (F-030, coupled to F-018 in `compiler-engineer.md`).** Phase 2 confirmed Addendum 7's F-017 prediction empirically. The compiler-side mechanism is F-018; the language-team item is the design question of whether `(check)` is the right surface for the test channel or whether a separate form is needed.
- **LT-C — Match-arm canonical form (R5, carried from Addendum 10).** Not Phase-3-gating. Phase 2 produced empirical confirmation that the §17 wrapped-form grammar holds; the §3.3 informal-example divergence remains the open decision.

---

### LT-A · Trust-tier predicate vocabulary (F-026 + F-027)

**Priority:** High — Phase-3-gating. Without resolution, the matrix cannot evaluate H1 (the assurance differential the README hypothesis names as Phase 3's central question).

#### Evidence

Across n=3 LLMLL cells in Phase 2, the trust-report breakdown per final turn (cited from each cell's `repair_loop_log.json:turns[-1].verifier_results[name=verify].parsed_json`):

| Cell | Status | Entries | `verified` | `proved` | `contract_checked` | `tested` | `asserted` | `null` (no_contract) |
|---|---|---|---|---|---|---|---|---|
| 01 | budget-exhausted | 7 | 0 | 0 | 0 | 0 | **7** | 0 |
| 02 | target-reached | 6 | 0 | 0 | 0 | 0 | **6** | 0 |
| 03 | budget-exhausted | 6 | 0 | 0 | 0 | 0 | 3 | 3 |

**19 obligations across n=3 LLMLL cells. 0 reached `verified` / `proved` / `contract_checked` / `tested`. Every entry the verifier returned was at `asserted` tier or unset.** Cell 02 matched the trust-tier predicate (terminal-reached) because the predicate's accepted-levels set in `experiments/repair-loop/scripts/run_repair_loop.py:_count_bad_trust_tiers:538-542` includes `asserted`:

```python
accepted_levels = {
    "verified", "proved", "asserted",
    "contract-checked", "contract_checked", "checked",
    "tested",
}
```

By comparison, Python/Go cells matched their respective `all-pass` predicates by **passing 8/8 behavioral tests** in the testkit (`testkits/002-bank-ledger/{python,go}/test_solution.py` / `solution_test.go`).

LLMLL solutions in this batch did engage the verification surface — cell 02 emits 6 `(post ...)` clauses, 1 `(pre ...)` clause, 4 `(where [n: int] (...))` refinement-type predicates, and `:source "..."` annotations on most clauses. The agent is *declaring* obligations. The verifier never *discharges* them; they remain at `asserted` tier.

#### Why we saw what we saw

The trust-tier ladder in `LLMLL.md §<trust-system section>` ranks `verified > proved > contract_checked > tested > asserted > no_contract`. The current predicate treats everything at or above `asserted` as good enough. This makes the predicate satisfied by any solution whose obligations parse and survive type-check, regardless of whether any obligation has been validated by SMT, runtime check, or PBT.

The implicit Phase-3 H1 framing (LLMLL agents reach higher *assurance* at fixed *k*) assumes the predicate measures assurance. It doesn't — it measures *declaration*. Phase 3 under this predicate produces a measurable that cannot defend the claim.

#### Decision options (for `/language-team` adjudication)

**R6a — Tighten the trust-tier predicate (remove `asserted` from accepted-levels).**
Require at least one of `verified` / `contract_checked` / `tested` per entry. Pro: keeps the existing predicate shape, simple to implement (one-line set edit). Con: under R6a, all 3 Phase-2 LLMLL cells invert to budget-exhausted — Phase 2 reads as 0/3 LLMLL wins. The question becomes whether gemini-default *can* push past `asserted` under any k, on any cell composition. n=3 from Phase 2 is consistent with "no under current conditions" but not conclusive. Decisively answering requires a small re-probe under tightened predicate + F-028 diagnostics surfaced.

**R6b — Split into terminal-reached binary + numeric assurance score.**
Keep `target-reached` as "the agent stopped without an open error" (the loop-control signal) and add an *assurance score* extracted from the trust report's tier distribution (e.g., 0.5 per `tested`, 1.0 per `verified`, 0.25 per `asserted`, 0.0 per `no_contract`) as the H1 measurement. Pro: cross-target comparison happens on a continuous measurable, not a binary; H1 can be evaluated even when no LLMLL cell reaches `verified`. Con: weights are a design decision, the scoring rubric extends, and Python/Go need a parallel assurance scoring (Python type-hint density? Go error-return density? — the current per-axis scoring rubric (Addendum 8) stubs these as TODO(sub-3-v2)).

**R6c — Hybrid.** Tighten the trust-tier predicate (R6a) for terminal-reached, AND surface assurance score (R6b) alongside as an analysis-time signal. The predicate becomes a clean binary; the comparison runs on the numeric signal regardless of terminal-reached status. Heaviest implementation but most defensible H1 framing.

Empirical evidence (this Phase-2 batch) does not adjudicate among R6a / R6b / R6c — all three are coherent design moves and the choice depends on what H1 is meant to measure.

#### Recommended next moves (for the user routing this finding)

1. `/language-team` adjudicates R6a vs R6b vs R6c. The decision is a design call on what `target-reached` *means* under the assurance hypothesis.
2. The adjudicated predicate vocabulary lands in `manifest.phase2-calibration.json:terminal_target_per_target` and (if non-trivial) in `LLMLL.md`'s trust-system section.
3. A small re-probe (1–2 LLMLL cells, k≥5) confirms the predicate behaves as designed before Phase 3 is launched.

#### Acceptance

LT-A closes when:
- The predicate vocabulary decision (R6a / R6b / R6c) lands in `LLMLL.md` and is reflected in `experiments/repair-loop/scripts/run_repair_loop.py:_count_bad_trust_tiers` (or wherever the predicate dispatch lives under the new rubric).
- A re-probe cell's `evaluation.json` reflects the new measurable.
- The Phase-3 manifest's `terminal_target` block uses the updated predicate.

#### Spec touch

The decision will likely touch `LLMLL.md`'s trust-system / verification-channel section. Whether the spec patch is invasive depends on R6a (smallest — clarifies which tiers count as terminal-reached) vs R6b/R6c (larger — defines assurance score and its weights).

#### Resolution — R6d (2026-05-13)

The `/language-team` adjudication arrived at a fourth option, **R6d**, after a `/professor` pass on a tentative R6c recommendation. R6d combines:

- **Universal `Cred(R)`** (R6a's tightening, lattice-meet reading) — the predicate refuses any cell with one or more `asserted` or `no_contract` entries.
- **Six-Int `tier_profile` aggregate** emitted by the compiler in the trust-report JSON (`docs/llmll-trust-report.schema.json`, introduced 2026-05-12 in `bb1bd98`) — replaces R6b's cardinal-weighted `S(R)` with a fixed-arity profile that respects `LLMLL.md §4.4.1:344` diamond incomparability between `contract_checked` and `tested`.
- **Spec-vs-tool boundary** — the consumer predicate and the H1 split are hosted in `experiments/repair-loop/README.md` ("Credibility predicate and the H1 split (R6d)"), not in `LLMLL.md`, per professor critique of R6c's spec-side hosting.
- **H1 bifurcation** restored — H1-Correctness (cross-target testkit, LLMLL via `CodegenHs`) + H1-Assurance (per-target profile, never scalarized cross-paradigm), realigning with `docs/design/language-comparison-experiments.md:29-35`.

The R6c cardinal-weighted `S(R)` was withdrawn on professor critique: any total order over `contract_checked` vs `tested` weights collapses the §4.4.1 diamond, contradicting the load-bearing epistemic-status note at `LLMLL.md §4.4.1:346-347`. This empirical batch did not arbitrate the withdrawal — the spec contradiction did.

#### Empirical close

Re-probe of the three Phase-2 cells under the v0.10.4-pre compiler (re-verify only, no agent re-run; `findings/postmortem-001-apparatus-validation.md` Addendum 15):

| Cell | `n_entries` | `tier_profile` (non-zero) | R6d `Cred` |
|---|---|---|---|
| c01 | 7 | `asserted=7` | false |
| c02 | 6 | `asserted=6` | false |
| c03 | 6 | `asserted=3, no_contract=3` | false |

All three invert to `Cred=false`. c02's inversion (target-reached → Cred=false) is the empirical correction R6d was designed to make. c03's profile additionally surfaces the `no_contract` half-the-obligations finding that the pre-R6d predicate had flattened.

#### Status

§LT-A → **CLOSED** (2026-05-13). Phase-3 readiness on this axis restored.

---

### LT-B · LLMLL in-source `(check ...)` channel design (F-030)

**Priority:** Medium — couples F-018 (compiler-engineer side). Not Phase-3-gating in itself, but if the predicate vocabulary tightens (LT-A → R6a or R6c), the test channel needs to land to give the agent any path past `asserted` tier.

#### Evidence

All three Phase-2 LLMLL solutions emitted `(check ...)` blocks (cell 01: 3 checks; cells 02–03: 2 checks each). Per `evaluation.json:scoring.correctness_subscores.core_behavior`:

| Cell | passed | failed | skipped | channel |
|---|---|---|---|---|
| 01 | 0 | 0 | 3 | `llmll-pbt` |
| 02 | 0 | 0 | 2 | `llmll-pbt` |
| 03 | 0 | 0 | 2 | `llmll-pbt` |

Every `(check)` block was skipped, never executed. The trust report shows the same solutions' obligations at `asserted` tier, never `tested`.

Addendum 7's F-017 predicted this from structural analysis: imported-module `def-logic` is not visible to the PBT FuncEnv, so any `(check)` block that references the standard prelude or other imported functions cannot be instantiated. Phase 2 confirmed empirically.

#### Why we saw what we saw

F-018 (compiler-engineer side, see `findings.md` `## Compiler-engineer` §CE-B) is the structural cause: `compiler/src/LLMLL/PBT.hs` constructs a per-test FuncEnv from the current module only.

The language-team question is upstream of the compiler patch: **is `(check ...)` the right surface for the test channel, or should LLMLL provide a separate form for the kind of property-based test that drives the trust-tier `tested` rung?**

Two readings:

- **The `(check ...)` form is the test channel and the F-018 patch is sufficient.** F-018 lands, imported-module `def-logic` becomes visible, the existing surface works. No language change.
- **The `(check ...)` form is one channel among several and the design needs explicit articulation.** A distinct `(property ...)` form for QuickCheck-style sample-driven tests, distinct from `(check ...)` for assertion-style invariants, might better align the test channel with how the trust ladder treats them. This is a spec-design question.

#### Recommended next moves

Defer the language-team decision until F-018 lands and a re-probe under the patched compiler shows whether `(check ...)`-on-existing-surface produces `tested`-tier credit. If yes, LT-B closes with no spec change. If no, the design question reopens with empirical evidence to constrain it.

#### Acceptance

LT-B closes when one of:
- F-018 lands and a re-probe cell shows `tested`-tier entries in the trust report from `(check ...)` blocks, OR
- A spec proposal lands that defines the test-channel surface explicitly (separate `(property ...)` form, or revised `(check ...)` semantics, with the trust-tier mapping made explicit).

#### Spec touch (conditional)

If R6a/R6c (LT-A tightening) lands AND F-018 (compiler-engineer) lands AND `(check)` still doesn't elevate obligations to `tested`, the spec needs an explicit test-channel section. Conditional on those upstream landings; not a same-turn item.

#### Status update (2026-05-13)

F-018 / CE-B closed by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`, shipped 2026-05-12) — the PBT FuncEnv now honors `(open ...)` for cross-module `def-logic`, and §LT-A landed (R6d) — the trust-tier predicate now refuses `asserted`-only reports. Both upstream conditions are met. LT-B's contingent "does `(check ...)` elevate obligations to `tested` under the patched compiler" question was *not* directly tested in the R6d re-probe — that re-probe was re-verify only, not re-test. A focused LT-B re-probe (`llmll test` on the three Phase-2 cells' solutions under v0.10.4-pre, comparing whether previously-skipped `(check)` blocks now execute and lift obligations to `tested`) is the next step toward LT-B closure. LT-B stays open until that re-probe lands.

#### Status update (2026-05-14, post-Addendum-17 informed-by)

The Addendum 16 (2026-05-13) re-probe under v0.10.4 routed F-032 to `compiler-engineer` and shipped as OBLIG-PBT-3 (v0.10.5, commit `d220632`, 2026-05-14). The Addendum 17 (2026-05-14) lift-validation re-probe under v0.10.5 then exercised the threaded pipeline on the three Phase-2 sealed solutions (c01/c02/c03 on `002-bank-ledger`, k=5 each) and falsified the strong-form H1-Assurance hypothesis at Addendum 16:2088 — zero of 15 compiler runs produced any `tested`-tier lift in `tier_profile_post`. The mechanism is dual, not single:

- **c02/c03 (deep-product + `?proof-required`-in-post):** body-side static-eval discard saturation in `evalExprStaticWith` at `compiler/src/LLMLL/PBT.hs:399-403`; `quickCheckResult` returns `GaveUp { numTests = 0 }`; the `PBTSkipped` arm at `PBT.hs:678` emits no diagnostic. Routed to `compiler-engineer` as F-033 (candidate OBLIG-PBT-5).
- **c01 (shallow-product observer-of-operation):** n=12/12 PBTPassed bodies hit the multi-callee guard at `compiler/src/LLMLL/PBT.hs:660-676` (the `fs`-arm of `pbtTrustWriteback`). Every plausible "transfer-preserves-X" property mentions both `transfer` and one of `total-balance` / `balance` / `has-account?`. This empirically inverts the v0.10.5 OBLIG-PBT-3 proposal's premise at `docs/design/oblig-pbt-3-proposal.md:52` (corrected in-folder 2026-05-14): the singleton head-position fallback was framed as covering "the typical Phase-3 problem shape," but the **metamorphic-relation / observer-of-operation idiom** (Hughes 2020 *How to Specify It!* §3; distinct from state-machine command-sequence properties such as Claessen-Hughes `eqc_statem`, a surface LLMLL has not adopted) — operation and observer being distinct contracted functions — is the natural form of "operation preserves observable property" and is canonically multi-callee on this problem family.

**§LT-B priority reframing.** §LT-B's "is `(check ...)` the right surface for the test channel" question is unchanged in shape. What changes is the cost of the conservative singleton fallback that v0.10.5 OBLIG-PBT-3 ships: on the agent-authored `002-bank-ledger` family it suppresses ~100% of `PBT-Lift` candidates, not the marginal fraction the v0.10.5 cut anticipated. OBLIG-PBT-4 (`:subject f` / `:subjects [f g]` metadata, designed in `docs/archive/shipped-design-specs/oblig-pbt-3-proposal.md` §11) is therefore now **Phase-3-gating in combination with OBLIG-PBT-5 / F-033**, not a low-priority follow-on. The two are independent blockers on independent shapes; both must ship before the strong-form H1-Assurance signal is coherently reachable on the Phase-3 suite. The OBLIG-PBT-4 design surface itself is unchanged — the priority and sequencing change, not the spec content.

**Recommended sequencing.** The user has selected path 1 (sequence OBLIG-PBT-5 + OBLIG-PBT-4 before strong-form Phase 3 launch). Recommended compiler-engineer-side bundling of OBLIG-PBT-4 and OBLIG-PBT-5 in a single engineer turn: both touch `PBT.hs` adjacent surfaces (the writeback consumption point at `PBT.hs:660-676`; the runQC body-evaluator at `PBT.hs:399-403`), and amortizing the surface review is the cheaper sequencing. Engineer adjudicates the bundling; the language-team has no scope to dictate it. The doc-lead's narrow-form Phase-3 caveat (which would have applied under path 2) is *not* invoked under path 1.

**Professor consultation (2026-05-14).** Path-1 professor review (F-033 scope hypothesis + OBLIG-PBT-4 sequencing question) independently confirmed the bundling recommendation via two convergent reading paths: the **PBT-literature reading** (under LLMLL's no-state-machine surface, explicit annotation is the only available route to per-callee evidence allocation on metamorphic-relation properties — Hughes 2020 *How to Specify It!* §3 — and is therefore load-bearing, not deferrable) and the **empirical reading** (the n=12/12 c01 multi-callee fate is dominant, not edge-case). Engineer-time-pressure fallback per professor: ship OBLIG-PBT-5 first (the body-evaluator fix is the more mechanism-discriminating signal — `samples_run > 0` distinguishes "the body evaluator was the blocker" from "something deeper"), followed by OBLIG-PBT-4 immediately, with explicit drift-protection (OBLIG-PBT-4 must not slip to a later milestone, since OBLIG-PBT-5 alone leaves the strong-form question unresolved). The professor's Q2 — the spec gap at `docs/archive/shipped-design-specs/oblig-pbt-3-proposal.md` §11 where `:subjects [f g]` lift semantics were undefined — was closed by the language-team in favor of **per-subject `DLTested n` lifts under explicit-annotation opt-in, with shared `pbt_witnesses` cross-link** (pinned in §11.1, 2026-05-14). Schema impact (corrected 2026-05-14 post-engineer-implementation): AST schema bumps `expectedSchemaVersion` `"0.4.0"` → `"0.5.0"` as an additive-optional minor bump for the new `CheckDecl.subjects` field (required under the schema's strict-`additionalProperties` invariant); `trust_report_version` stays at `"1.1.0"` (per-subject lifts do not change `EvidenceRecord` shape). The original §11.1 commitment to "no schema delta" was authored on a false-tolerance assumption and is corrected in `docs/archive/shipped-design-specs/oblig-pbt-3-proposal.md` §11.1. The conjoint-record alternative (`DLJointTested [Name] n` or `subjects: [Name]` field on `DLTested`) was considered and rejected on harness-coupling grounds — a `trust_report_version` 1.2.0 bump at the v0.10.6 boundary would couple the experiment-lead's `Cred(R)` consumer with a *trust-report* schema change at Phase 3 launch (this argument is unaffected by the AST schema bump, which the harness does not consume). The framing fix (metamorphic-relation per Hughes 2020 §3; "state-machine property" reserved for `eqc_statem`-style command sequences LLMLL has not adopted) attaches to the doc-lead's post-OBLIG-PBT-4-ship surface at `docs/compiler-team-roadmap.md:166` and `LLMLL.md §4.4.5`; the language-team commits this framing into the doc-lead hand-off at that time.

**§LT-B closure criteria, updated.** LT-B remains open until one of:

- OBLIG-PBT-4 (`:subject` / `:subjects`) and OBLIG-PBT-5 (F-033) both ship, and a re-run of the Addendum 17 matrix shows at least one PBTPassed property on at least one of c01 / c02 / c03 lifts `tier_profile_post.tested ≥ 1` (the conjunction is load-bearing: c01 needs `:subjects`, c02/c03 need F-033); OR
- A spec proposal lands that redesigns the test-channel surface entirely (separate `(property ...)` form, or revised `(check ...)` semantics), making the OBLIG-PBT-4 metadata route moot. Considered low-likelihood under current sequencing.

The Spec touch (conditional) clause above remains conditional. No `LLMLL.md` change in this turn; doc-lead is downstream of the OBLIG-PBT-4 + OBLIG-PBT-5 ship.

#### Routing emitted in this update

- **Engineer-facing.** OBLIG-PBT-4 design surface is unchanged from `docs/archive/shipped-design-specs/oblig-pbt-3-proposal.md` §11; bundling recommendation with OBLIG-PBT-5 is informational, engineer-adjudicated.
- **Doc-lead-facing.** No same-turn surface; doc-lead is invoked after both compiler items ship. At that point the doc-lead's surface includes: `docs/compiler-team-roadmap.md` row 8 (OBLIG-PBT-4) close-out + cite Addendum 17 + n=12/12; `LLMLL.md §4.4.5` `PBT-Lift` rule extension with the `:subject` / `:subjects` premise; `CHANGELOG.md` v0.10.6 entry; `README.md` schema-pin where applicable.
- **Experiment-lead-facing.** The Addendum-17 acceptance re-run shape is named in F-033's acceptance criterion (`postmortem-001-apparatus-validation.md` §F-033 / Acceptance); the c01 acceptance shape adds: at least one PBTPassed body with `:subjects [transfer total-balance]` (or equivalent) lifts `tier_profile_post.tested ≥ 1` on `c01/solution.k*.llmll`. The experiment-lead reruns the matrix after the compiler turns close; this is the verification gate before Phase 3 launches.

#### Status update (2026-05-14, post-Addendum-18)

The Addendum-18 (2026-05-14) re-probe under the v0.10.6-candidate binary built from `oblig-pbt-4-5/subject-metadata-and-eval-coverage` atop merge `d220632` (35-file diff, +700/−102) ran the c01 / c02 / c03 / c01-subjects matrix (k=5 per cell, 80 compiler invocations, $0). Two-half empirical result:

- **c01-shape (OBLIG-PBT-4): closed empirically.** The c01-subjects cell — c01 augmented with `:subjects [transfer total-balance]` on property 1, `:subjects [transfer balance]` on property 2, `:subjects [transfer has-account?]` on property 3 — produced `.verified.json` sidecars on 5/5 tries with 3 per-subject `DLTested(100)` records each, sharing the canonical-body hash exactly as §11.1 prescribed. 4/5 tries lift `tier_profile_post.tested = 1` (n=1 = `total-balance`, the only callee with zero contracted dependencies); the remaining 1/5 (k=2) missed on a near-threshold QC discard of property 1 — orthogonal QC variance, not an OBLIG-PBT-4 defect. R6d's `effective_level` machinery bounds `balance.effective_level` and `transfer.effective_level` to `asserted` via still-`asserted` dependencies on `find-balance` / `update-balance` — correct body-faithful behavior.

- **c02/c03-shape (OBLIG-PBT-5 residual): re-named F-034.** c02 0/10 and c03 0/10 properties achieve `samples_run ≥ 1`. The new F-033 GaveUp diagnostic ("property body did not reduce on any sample (1000 evaluated, 0 returned bool — likely unmodeled builtin or unreduced callee body in property body)") correctly attributes every discard to the body evaluator. The proximate cause is **not** what Addendum-17 F-033 named (`unwrap` is now shipping and not the bottleneck) but a different residual surface: missing `evalBuiltinApp` clauses on `list-filter`, `list-prepend`, `list-empty`, `string-concat-many`, `int-to-string`, plus a `list-head` return-shape bug at [Contracts.hs:434](../../compiler/src/LLMLL/Contracts.hs#L434). All five missing clauses are mechanical pattern-matches analogous to existing ones; no design surface to litigate. F-034 routes to `compiler-engineer` (`findings.md` `## Compiler-engineer` §CE-D).

**§LT-B closure status.** Per the criteria at lines 166-169 above, §LT-B closes when "at least one PBTPassed property on at least one of c01 / c02 / c03 lifts `tier_profile_post.tested ≥ 1`." This is now true on c01 (via `:subjects` opt-in), so the disjunctive read of the criterion holds. The conjunctive read (the user's path-1 framing, which requires the lift on *all three* representative shapes) requires F-034 to ship before §LT-B closes empirically on the full Phase-3 problem surface. Conservative read for the language-team: §LT-B remains **partially closed** — c01-shape settled, c02/c03-shape gated on F-034.

**Joint acceptance criterion result.** The user's stated criterion ("samples_run ≥ 1 on c02/c03 + tier_profile_post.tested ≥ 1 on c01 with `:subjects` annotation") — a conjunction — **does not hold** under v0.10.6-candidate. The c01-subjects conjunct passes; the c02/c03 conjunct fails. Path-1 stages 3 (doc-lead) and 4 (Phase 3 launch) **do not proceed** per this criterion as stated.

**Sequencing recommendation (informational, engineer-adjudicated).** Combined v0.10.6 cut (OBLIG-PBT-4 + F-034 in one release) produces a cleaner empirical signal than a split v0.10.6 (OBLIG-PBT-4 only) + v0.10.7 (F-034) sequence, because c02/c03 cannot be re-probed against a standalone-OBLIG-PBT-4 binary as a separate gate; doc-lead's combined seal covers both atomically. Split cut is also valid if engineer-time-pressure favors a faster OBLIG-PBT-4 ship cadence. Phase-3 launch waits on F-034 either way.

**No new language-team scope opened.** §LT-B closure criteria at lines 166-169 unchanged in shape — only the c02/c03 conjunct's blocker is re-named from F-033 to F-034. The OBLIG-PBT-4 design surface remained correct end-to-end; the §11.1 pinned commitment (per-subject `DLTested n` lifts under explicit-annotation opt-in with shared `pbt_witnesses` cross-link) is empirically confirmed. The doc-lead surface enumerated at line 176 (roadmap row 8 close-out, `LLMLL.md §4.4.5` rule extension, `CHANGELOG.md` v0.10.6 entry, schema-pin updates) remains pending F-034 land.

#### Status update (2026-05-15, post-Addendum-19) — §LT-B CLOSED

The Addendum-19 (2026-05-15) re-probe under the v0.10.6-shipped binary (built fresh from `main` commit `46f9554`; `llmll version` reports `0.10.6`) ran the 5-cell matrix `c01 / c02 / c03 / c01-subjects / c02-subjects` (k=5 per cell, 50 compiler invocations, $0). F-034 has shipped (commit `cb2e71f` bundling OBLIG-PBT-4 + F-033 + F-034). Empirical result:

- **c02/c03-shape (F-034) closed empirically.** c02 0/10 → **10/10** property×try records `samples_run ≥ 1` (PBTPassed 9/10, 1 PBTSkipped on near-threshold QC precondition-failure discard — orthogonal to F-034); c03 0/10 → **10/10** (PBTPassed 7/10, 3 PBTSkipped on the same QC mechanism on property 1's `(for-all [f t])` precondition where `f = t` is statistically rare in the random sampler). The clean before/after switch attributable to the F-034 shipping commit closes CE-D.
- **OBLIG-PBT-4 on c02-shape (H3 / F-034 acceptance optional clause) confirmed.** c02-subjects (c02 augmented with `:subjects [transfer total_balance]` on property 1 and `:subjects [transfer balance]` on property 2) achieves `tier_profile_post.tested ≥ 1` on **3/5 tries** — same rate as c01-subjects in this run (Addendum-18 c01-subjects was 4/5; both within near-threshold QC variance). The OBLIG-PBT-4 `:subjects` path is end-to-end functional across two distinct body shapes (c01-shape with cons-list pattern matching and Result-chain plumbing; c02-shape with map-based plumbing using `list-filter` / `list-prepend` / `string-concat-many`).
- **c01-subjects reproduces Addendum-18.** 3/5 tries `tier_profile_post.tested ≥ 1` (Addendum 18: 4/5 — within QC variance). No regression.
- **c01 / c02 / c03 unannotated controls.** `tier_profile_post.tested = 0` floor reproduces exactly across all 5 tries each — the multi-callee writeback guard fires as design-intent on unannotated multi-callee properties.

**§LT-B closure status — CLOSED.** Per the criteria at lines 166-169, §LT-B closes when "at least one PBTPassed property on at least one of c01 / c02 / c03 lifts `tier_profile_post.tested ≥ 1`." The user's path-1 framing (conjunctive: all three representative shapes lift) is now empirically vindicated:
- c01-shape lifts via c01-subjects (3/5 tries, both Addendum 18 and Addendum 19).
- c02-shape lifts via c02-subjects (3/5 tries, Addendum 19).
- c03-shape's PBTPassed property 2 produces `samples_run = 100` across all 5 tries; c03 was not augmented to c03-subjects in this matrix (the F-034 acceptance criterion specified c02-subjects, not c03-subjects), but the structural mechanism is the same as c02-subjects — symmetric augmentation of c03 would lift on identical grounds, and c03's PBTPassed records are now observable under the F-034-shipped body evaluator. If conservative-conjunctive-reading is required to fully close, a c03-subjects follow-up cell is cheap (one sed pass, 10 invocations, $0) but not Phase-3-gating.

**Joint acceptance criterion result — HOLDS.** The user's stated criterion ("samples_run ≥ 1 on c02/c03 + tier_profile_post.tested ≥ 1 on c01 with `:subjects` annotation") is satisfied: c02 10/10, c03 10/10, c01-subjects 3/5. Path-1 stages 3 (doc-lead — already shipped in v0.10.6 commit `cf711d6`) and 4 (Phase 3 launch) **proceed**.

**Doc-lead residual.** v0.10.6 is already doc-sealed. The only doc-lead surface implied by Addendum 19 is a one-line CHANGELOG.md §v0.10.6 §"Empirical hooks not yet exercised" erratum/footnote retracting the c02/c03 reference at CHANGELOG.md line 38 and pointing to Addendum 19's closure evidence. This is small enough to bundle into the next normal doc pass; not a v0.10.6.1 surface, not a language-team scope.

**No new language-team scope opened.** §LT-B closure is empirical, not design-surface — no `LLMLL.md` patch implied beyond what shipped in v0.10.6 (`§4.4.5` `PBT-Lift` rule extension with `:subjects` premise). Phase-3 readiness on the predicate-vocabulary (R6d), PBT-Lift (OBLIG-PBT-3 / OBLIG-PBT-4), and body-evaluator-coverage (F-033 + F-034) axes is now empirically vindicated against the actual Phase-2 agent emissions.

---

### LT-C · Match-arm canonical form (R5, carried from Addendum 10)

**Priority:** Medium — not Phase-3-gating; tracked for closure.

#### Evidence

Phase 2 produced empirical confirmation of the §17 wrapped-form grammar's correctness:

- Gemini emitted match arms in the **wrapped form** in cell 02's solution (`runs/20260512T033017Z-.../solution.llmll`).
- The parser accepted them across all 5 turns of cell 02.
- No parse failures attributable to match-arm wrapping appeared in any of the 15 LLMLL turns in this batch.

The §3.3 informal-example divergence remains the open decision; Phase 2 did not produce new evidence relevant to that decision (the agent did not emit §3.3-style sibling-form arms in any Phase-2 cell, so the divergence's empirical impact is unmeasured).

#### Why we saw what we saw

Per Addendum 10's bisection: the §17 grammar is empirically correct (parser accepts wrapped form; shipping `examples/` use wrapped form). The §3.3 informal example uses sibling form and does not parse. The decision is which surface is canonical.

#### Status

R5a (patch §3.3 informal examples to wrapped form) remains the recommended option per Addendum 10's evidence. No Phase-2 finding changes this.

#### Recommended next moves

R5 routes through a dedicated `/language-team` + `/documentation-lead` turn at convenience. Not Phase-3-gating, not bundled with LT-A. Tracked here for closure-tracking only.

#### Status update (2026-05-15) — §LT-C CLOSED (retrospective)

R5a shipped at commit `ecdf42f` (`docs(spec): correct match-arm informal examples in LLMLL.md §3.3 / §9 / §13.5 (R5a)`) as part of v0.10.3's spec pedagogy corrections (2026-05-12; roadmap at `docs/compiler-team-roadmap.md:290`). `LLMLL.md §3.3` at HEAD uses wrapped-form throughout (e.g., `((Red) "stop")` and `((Start word) ...)` on lines 213-220); no sibling-form informal examples remain on the section. The "Status" and "Recommended next moves" entries above were not updated when R5a shipped, leaving §LT-C stale-as-of-v0.10.3 through 2026-05-15.

Closure is **retrospective**: the section is marked closed against the actual shipping commit, not against a future `/documentation-lead` patch. Discovered during a `/documentation-lead` consultation on a (now-withdrawn) S6 hand-off framed against the stale entry; the doc-lead's read of HEAD `LLMLL.md §3.3` caught the drift on the first consult. Phase-3 contamination risk on this axis is empirically vacated; the Phase-3 problem-shape audit's CC-1 prediction at `experiments/repair-loop/findings/phase3-problem-shape-audit.md` (commit `7623712`) is revised in place pre-pin under the audit's pre-launch in-place-edit window.

§LT-C → **CLOSED (retrospective)** (2026-05-15).

---

### LT-D · Phase-3 launch findings — H1/H2/H3 adjudications (postmortem-004 + postmortem-005)

**Priority:** Mixed (H2 raw refutation is the load-bearing adjudication; the other four are confirmation closures or empirical baselines). Post-launch; not Phase-3-gating in retrospect — Phase 3 has shipped — but the language-team-side adjudication on H2 conditions any Phase-4 design turn.

**Source:** `findings/postmortem-004-phase3-launch.md` §"Verified findings (hypothesis-class)" + `findings/postmortem-005-claude-deepening.md` §"Verified findings". Both postmortems flagged a pending per-consumer fragment for `findings.md` `## Language-team` (postmortem-004:490; postmortem-005:142). This section is that fragment.

#### Why this fragment was missing

Between 2026-05-17 (postmortem-004 land) and 2026-05-21 (this fragment land), `findings.md` `## Language-team` read as "all three LT items closed" while postmortem-004 carried the H2 refutation, H1-Assurance confirmation, H3 confirmed-and-extension, H1-Correctness cross-agent variance, and the verification-strategy split. A reader landing on `language-team.md` alone would have missed the entire Phase-3-launch outcome. The drift is itself a finding about the per-consumer-fragment authoring discipline: the postmortem author self-flagged the missing fragment at line 490 ("**fragment to be added** in a separate edit") but the explicit hand-off did not generate a follow-up turn until the 2026-05-21 review of all repair-loop findings. Recorded here for the discipline trail; no procedural change proposed (the postmortem self-flag is the correct mechanism; the gap is in the follow-up cadence, not the discipline).

---

#### LT-D-1 · H1-Assurance bifurcation — empirically confirmed, R6d validates

##### Evidence

`postmortem-004:42-74` records substantive within-LLMLL `tier_profile` variation across the 10 LLMLL target-reached cells: cells split between `verified`-dominant shapes (cells 4, 12, 13, 15, 19, 20 — verified ranges 2–9) and `tested`-dominant shapes (cells 1, 5, 22, 23 — tested ranges 3–15). The six-Int aggregate distinguishes assurance-by-proof from assurance-by-testing without scalarization across paradigms. Python/Go cells carry the native binary `all-pass`-style signal in parallel; the harness does not scalarize across paradigms. `postmortem-005:50-65` (F-V2) tightens the within-Claude pattern to n=3/5 high-`verified`-tier dominance among successes.

##### Why we saw what we saw

R6d's universal `Cred(R)` + six-Int `tier_profile` (closed in §LT-A 2026-05-13) is the apparatus that makes the bifurcation observable. The diamond-incomparability declaration at `LLMLL.md §4.4.1:344` and the epistemic-status note at `:346-347` are **load-bearing**, not decorative: without the diamond, the verified-vs-tested distinction collapses and the assurance-strategy delta is suppressed. The professor's 2026-05-13 critique of R6c's cardinal-weighted scalarization — which would have collapsed the diamond by the back door — was exactly what protected the empirical signal from being destroyed at design time.

##### Closure

No spec move implied. R6d is empirically validated by the Phase-3 data, and `experiments/repair-loop/README.md:267-330` (the spec-vs-tool boundary surface) reads correctly against the realized data. The closure rests on three references that already converge on the same discipline:

- `LLMLL.md §4.4.1:344-347` — diamond + epistemic-status rationale.
- `docs/design/language-comparison-experiments.md:20-35,37` — Correctness/Assurance separation with R6d operationalization footnote.
- `experiments/repair-loop/README.md:283-330` — `tier_profile` Assurance signal + no-scalarization discipline.

§LT-D-1 → **CLOSED (informational)** (2026-05-21).

---

#### LT-D-2 · H2 (convergence differential) — raw form empirically refuted; formal withdrawal recorded (R-H2-W)

##### Evidence

`experiments/repair-loop/README.md:45-47` pre-states H2 verbatim: *"On tasks whose dominant invariant class is inside LLMLL's QF-LIA fragment (`LLMLL.md §5.3.3 / §5.3.5`), LLMLL converges in fewer turns than Python."* `postmortem-004:84-97` reports the empirical outcome on the QF-LIA-dominant 002-bank-ledger problem: Claude × LLMLL mean 3.0 turns to terminal; Codex × LLMLL mean 3.2; Claude × Python 1.0 every try; Gemini × Python 1.0 every try. LLMLL converges in **more** turns than Python on the QF-LIA-dominant problem H2 was framed around, not fewer.

`postmortem-005:79-90` (F-V3) tightens the refutation with within-Claude bimodality at n=18: the LLMLL deepening turn-count distribution is `[5,5,5,5,5,5,5,5,1]` with zero cells terminating at turns 2, 3, or 4. At k=5, LLMLL successes terminate at turn ≤2 (right-shape mode) or budget-exhaust at turn 5 (wrong-shape mode); no intermediate convergence sampled. H2's "convergence" framing implicitly assumed gradient sampling of a refinement curve; the data shows two-mode selection at turn 1.

##### Why we saw what we saw

The structural cause is **predicate-bar mismatch**, named at `postmortem-004:99-108`. Python's `manifest.phase3.json:terminal_target_per_target.python.kind = "all-pass"` terminates on testkit pass — satisfiable in one turn because Python is the agents' training distribution. LLMLL's `terminal_target_per_target.llmll.kind = "trust-tier"` terminates on R6d `Cred(R)` — requires structured verification work the agent must iterate through: emit, run verifier, observe trust report, refine obligations, re-emit, repeat. **The "more turns" delta is not "LLMLL agents are slower at the problem"; it is "LLMLL agents are asked to do more per turn."** This is the experiment's *intended design*, not a defect — but H2's framing implicitly assumed comparable predicate difficulty across targets.

The bimodality compounds the refutation: even if the predicate bar were equalized, the LLMLL distribution at k=5 does not gradient-sample, so any "convergence differential" measurement on this k requires re-thinking what is being measured. A k=10 probe might surface intermediate-turn terminals; that is an empirical question, not a defense of H2's raw form.

##### Adjudication — R-H2-W (formal withdrawal)

H2 in its pre-stated form is withdrawn from the Phase-3 hypothesis set as empirically refuted. The withdrawal is the finding, not a defect to be repaired by silent successor.

R-H2-A (matched-difficulty reframing) and R-H2-B (per-tier-of-trust reframing), both surfaced at `postmortem-004:114-117`, are coherent *next* hypotheses for a Phase-4 design turn. Both are untestable in the current harness — R-H2-A requires a predicate-bar augmentation on Python/Go to produce comparable-difficulty terminals; R-H2-B requires native body-faithful equivalents on Python/Go that do not currently exist. **Neither is authored here as a silent successor to H2.** Per the pre-registration discipline at `docs/design/language-comparison-experiments.md:247-249` (Nosek, Ebersole, DeHaven & Mellor, *The preregistration revolution*, PNAS 115(11):2600–2606, 2018), successor hypotheses are new pre-registrations with their own pinned commits, not retunings of refuted ones. The successor hypothesis is *deferred* to a Phase-4 design turn; its authoring is out of scope for this LT-D fragment.

The bimodality finding (F-V3) attaches to the successor as a **shape constraint**: any H2-successor must measure something other than mean turns-to-terminal at k=5, because the LLMLL distribution is two-mode at that k. Per-cell strategy choice (LT-D-4 below), turns-to-first-success-mode, or k-sized-to-expose-modes are the candidate measurables; the design space is open.

##### Affected surface

- `experiments/repair-loop/README.md:45-47` — H2 statement requires an addendum recording the refutation + withdrawal. **This is the experiment-lead's apparatus surface**, not language-team's; routed to `experiment-lead` (see §"Routing" below).
- `experiments/repair-loop/findings/phase3-problem-shape-audit.md` — dated addendum recording the H2 raw-form refutation per the immutability protocol at `docs/design/language-comparison-experiments.md:247-249`. Authored same turn as this fragment (2026-05-21).
- `LLMLL.md`, `CHANGELOG.md`, `README.md`, `docs/llmll-ast.schema.json`, `docs/compiler-team-roadmap.md` — **untouched**. The refutation lives in apparatus and audit surfaces, not in the spec, in accordance with the spec-vs-tool boundary established by R6d's professor critique (`findings/language-team.md:79-86`).

##### Closure

§LT-D-2 → **CLOSED (R-H2-W formal withdrawal)** (2026-05-21). Successor hypothesis pre-registration is a future-turn item, not gated on this closure.

##### Closure addendum 1 (2026-05-22) — methodological warrant refined (professor turn)

Routed from a professor turn (2026-05-22). The adjudication R-H2-W and the successor-deferral position are unchanged; the citation supporting *why* the successor is deferred is refined to clear an over-claim.

The §LT-D-2:305 invocation of Nosek, Ebersole, DeHaven & Mellor, *The preregistration revolution*, PNAS 115(11):2600–2606, 2018, is correct for the **immutability protocol** at `docs/design/language-comparison-experiments.md:247-249` — i.e., for the prohibition on silently retuning H2 into an H2′ post-hoc. It is over-claimed when carried into the **successor-deferral** position. Deferral rests on two convergent methodological constraints that do not reduce to immutability:

**(a) Testability (Popperian).** R-H2-A requires predicate-bar augmentation on Python / Go to produce comparable-difficulty terminals; R-H2-B requires native body-faithful equivalents on Python / Go that do not currently exist (`postmortem-004:114-117`; §LT-D-2:305). Pre-registration's epistemic function — lock predictions before data — presupposes an apparatus capable of producing the data. With the apparatus absent at HEAD, registration would be paperwork, not falsifiable prediction.

**(b) Stage-1 Registered Reports criterion.** Stage-1 registration of a Registered Report requires methods to be specifiable in advance (Chambers & Tzavella, *The past, present and future of Registered Reports*, Nature Human Behaviour 6(1):29–42, 2022). R-H2-A / R-H2-B fail Stage-1 specifiability until the Phase-4 harness extension is itself designed. The Phase-4 design turn is therefore the correct authoring slot for the successor pre-registration, against an apparatus design produced in the same turn.

The Nosek immutability protocol is retained as the warrant for refusing in-place retuning of withdrawn hypotheses; it is no longer cited as the warrant for *when* the successor is authored. Testability + Stage-1 is.

The absence of a PL-empirical refutation-recovery precedent is itself a finding: the field has not yet settled what successor authorship after empirical refutation should look like in language-comparison studies (Kaijanaho, *Evidence-Based Programming Language Design: A Philosophical and Methodological Exploration*, Jyväskylä Studies in Computing 222, 2015). LLMLL is, in this respect, building methodology slightly ahead of the field, in line with the project's existing posture on the verification-empirical seam.

§LT-D-2 remains **CLOSED (R-H2-W formal withdrawal)**. This addendum refines paper-trail citation only; it does not reopen the adjudication.

---

#### LT-D-3 · H3 (boundary-of-value, null-watcher) — confirmed-and-extended

##### Evidence

`postmortem-004:131-170` reports cross-target rates on the H3 null-watcher problem 001-hangman (state-machine, non-QF-LIA-dominant per `experiments/repair-loop/README.md:58`): LLMLL 3/9 target-reached vs Python 6/6 and Go 6/6. The H3 pre-statement (`experiments/repair-loop/README.md:49-50`: "On tasks whose dominant invariant class is outside QF-LIA, LLMLL produces no measurable advantage. Confirmation bounds the value claim; refutation extends it.") is confirmed in the bounded-value form and empirically extended: LLMLL produces a measurable *terminal-reaching disadvantage* on this problem class at k=5 with the per-target predicates, not just no advantage. H1-Correctness on cells that *do* reach terminal is comparable across paradigms (Claude × LLMLL 1.000 pass rate on hangman; Codex × LLMLL 0.722; Python/Go 1.000) — meaning the disadvantage is in *getting to* terminal under R6d's per-obligation bar, not in solution quality once there.

##### Why we saw what we saw

001-hangman's state machine has non-QF-LIA invariants (guess-letter not in previous-guesses, game-state transitions on hit-vs-miss). R6d `Cred(R)` requires every obligation above `asserted`; for non-QF-LIA invariants this means liquid-fixpoint cannot discharge them (so they fall to `asserted`), the agent must explicitly route to `weakness-ok`, or emit `(check ...)` blocks (with `:subjects` annotation when multi-callee per `LLMLL.md §4.4.5`) to promote them to `tested`. All three paths take iteration; first-turn solutions rarely cover all expected obligations above-asserted. Python/Go on the same problem face `all-pass` only.

##### Closure

No language-team spec move. The confirmation aligns with the audit's per-problem prediction at `docs/design/phase3-problem-shape-audit.md:185` ("LLMLL-disadvantaged or neutral on 003-rate-limiter" + "roughly comparable on 001-hangman"); the empirical 001-hangman disadvantage is slightly stronger than the audit's "roughly comparable" prediction, but inside the variance band the audit declared at `:194-197` (predicted `match` rate 60-85%, `divergence` rate 10-30%, `unaudited` rate 5-15%). Post-hoc whether 001-hangman cells should be marked `match` or `divergence` is the `prediction_match`-field author's call (human judgment per `docs/design/language-comparison-experiments.md:579`); the question is empirical-aggregation, not language-team scope.

The optional narrative-update implication noted at `postmortem-004:163-166` ("Language-team might consider whether the project's value-claim narrative should be updated to lead with 'rich verification surface' rather than 'faster development'") is **out of language-team scope** — `docs/one-pager.md`, `README.md`, and the project's positioning copy are documentation-lead's surface, not language-team's. Routing flagged in §"Routing" below; no action this turn.

§LT-D-3 → **CLOSED (confirmed-and-extended; no spec move)** (2026-05-21).

##### Closure addendum 1 (2026-05-22) — narrative routing resolved as already-satisfied

Doc-lead value-claim narrative review against LT-D-3 + LT-D-5 closed with zero in-scope edits recommended. Empirical check of `docs/one-pager.md` at HEAD: the verification-surface lede the `postmortem-004:163-166` implication proposed is already in place across title:1 ("A Verification System for AI Agent Teams"), subtitle:3 (verification-led), The Problem:9-17 (coordination + verification + hallucination, no velocity lede), The Approach:25 ("verification is not a post-hoc filter — it is the coordination protocol itself"), and Stratified Verification:55-57 (trust-level propagation). No "faster development" lede exists in `docs/one-pager.md` to dethrone; the routing language at `:335` and `:392` paraphrased `postmortem-004:166`'s conditional ("might consider whether… should be updated") into a more declarative form than the source warranted. The conditional collapses against the HEAD state.

The lone velocity-adjacent sentence at `docs/one-pager.md:97` ("the verify-on-merge loop lets agents iterate quickly") sits inside the "No Training Data Question" section and is a per-turn feedback-loop tightness claim (JSON-Pointer-localized errors + structurally-constrained patches), not a cross-cell terminal-reaching claim. LT-D-5's n=18 target-reached-rate data (Claude × LLMLL 5/18; Claude × Python 18/18; Claude × Go 15/18) is a cross-cell terminal-reaching metric over a k=5 turn budget — a different scale of claim. A fast inner loop is compatible with low cross-cell terminal-reaching; the n=18 data refutes neither. No re-anchoring of `:97` is warranted on LT-D-5 grounds.

`README.md` at HEAD carries no value-claim narrative copy — it is the reference document for the command surface, examples, and repo layout. The only narrative line (`:3`, "prioritises contract clarity, token efficiency, and ambiguity elimination over human readability") is a design-priority claim, not addressed by either LT-D-3 or LT-D-5. No n=18 citation fits without rewriting the document's voice.

LT-D-5's n=18 baseline stays in this file (`findings/language-team.md:371-385`) and `postmortem-005:28-47` (F-V1) — those are its load-bearing homes. None of the doc-lead's six target docs (`LLMLL.md`, `CHANGELOG.md`, `README.md`, `docs/llmll-ast.schema.json`, `docs/compiler-team-roadmap.md`, `docs/getting-started.md`) is a category fit for an n=18 agent-LLMLL target-reaching-rate finding; promoting it into any of them would be a category transfer (empirical-pattern → spec-or-engineering surface), not a documentation completion.

Routing dead-zone on `docs/one-pager.md` flagged for the record: §LT-D-3 above (`:335`) adjudicated this file as out of language-team scope, and the doc-lead skill's hard constraint excludes it from its six target docs. No pipeline skill natively owns `docs/one-pager.md` edits; future narrative moves there fall to direct user authorship. Not actionable this turn; recorded so the dead-zone is visible to future re-readers.

§LT-D-3 narrative routing → **CLOSED-AS-ALREADY-SATISFIED** (2026-05-22). No edits to the six doc-lead target docs warranted from LT-D-3 or LT-D-5; LT-D-5 n=18 baseline stays here.

---

#### LT-D-4 · Verification-strategy split — observed pattern; spec-guidance adjudication R-S-N (no spec change)

##### Evidence

`postmortem-004:256-282` documents within-agent strategy variance: Codex on 001-hangman produces cell 4 with `{verified: 2}` (verified-into-tier) and cell 5 with `{tested: 15}` (tested-into-tier) — same agent, same model, same reasoning effort, same problem-shape, different try. Across the n=10 LLMLL target-reached cells: Claude reaches terminal 3-of-4 times via verified-into-tier (cells 12 `verified=9`, 19 `verified=4`, 20 `verified=8`) and once via tested-into-tier (cell 1 `tested=13`); Codex mixes (3 via verified, 3 via tested). `postmortem-005:50-65` (F-V2) tightens the within-Claude verified-into-tier dominance to n=3/5 among combined Phase-3 + deepening successes — directional but small.

##### Why we saw what we saw

Both strategies satisfy R6d `Cred(R)`: `asserted=0 AND no_contract=0`. The agent satisfies the predicate by either (a) promoting all obligations to body-faithful-verified (liquid-fixpoint discharges QF-LIA-decidable arithmetic) or (b) adding PBT-Lift `(check ...)` blocks that cover all obligations and promote them to `tested` (with `:subjects` for multi-callee per `LLMLL.md §4.4.5`'s PBT-Lift-Annotated branch shipped in v0.10.6). The diamond incomparability at `LLMLL.md §4.4.1:344` is the spec's principled position on the question: it admits both strategies as legitimate, with neither implying the other.

##### Adjudication — R-S-N (no spec change)

The spec's existing position is consistent with the empirical pattern. Agents adapt their strategy to the obligation shape and to whatever signal they read from the verifier feedback loop; the diamond incomparability is what makes that adaptation legitimate. The observation that "Claude tends toward verified-into-tier; Codex mixes" is an empirical finding about agents, not a spec-design question about LLMLL.

The two alternatives are rejected:

- **R-S-G (non-normative guidance in `LLMLL.md §4.4.1`).** Adding a paragraph telling agents to prefer body-faithful when obligation is in-fragment, PBT-Lift otherwise, documents what the existing spec already implies. The cost is words; the benefit is small. Deferred — if a future empirical pattern shows agents systematically choosing the wrong strategy for the obligation shape (e.g., tested-into-tier on QF-LIA-trivial obligations), R-S-G reopens. Not the current pattern.
- **R-S-P (normative ordering — prefer `verified` over `tested` when both available).** Hard-rejected. Collapses the diamond by the back door; contradicts `LLMLL.md §4.4.1:347` (logical vs statistical evidence as categorically different kinds of trust signal); contradicts `LLMLL.md §4.4.1:350` (the deliberate design divergence from Liquid Haskell that admits the `tested` channel into the partial order).

R-S-N stands on n=5–10 Phase-3 LLMLL successes plus the F-V2 n=3/5 deepening signal. The sample is small; the recommendation is appropriately tentative and reopens if Phase-4 codex generalization (Jun-12 quota reset per `postmortem-004:344-348`) surfaces a contradicting pattern.

##### Affected surface

- `LLMLL.md` — **untouched**.
- `docs/design/language-comparison-experiments.md` — optional one-line empirical-baseline footnote at the §"Soundness Assessment" tail (Phase-3 observation: strategy choice is non-deterministic task-time within the diamond incomparability). Low-priority; defer to next doc-lead pass or absorb into the §LT-D-4 paper trail here. Not authored this turn.

§LT-D-4 → **CLOSED (R-S-N no spec change)** (2026-05-21). Reopens conditionally on Phase-4 codex generalization data.

##### Closure addendum 1 (2026-05-22) — professor adjudication absorbed; meta/object boundary; reference-class rehoming

Professor team's R-S-N adjudication (2026-05-22) confirms R-S-N stands and sharpens the R-S-P hard-rejection. The narrow open question routed back — whether `LLMLL.md §4.4.1:346-350`'s existing NOTE pair does the meta-level / object-level work explicitly or implicitly — resolves as **implicit**. A future maintainer reading §4.4.1 alone, without this paper trail, has access to the diamond lattice (`:330-335`), the epistemic-kind distinction (`:347`: logical vs statistical evidence), and the channel-admission rationale (`:350`: design divergence from Liquid Haskell). All three are *object-level* statements describing what the trust report records and how the recorded categories relate; none names *strategy selection* — the agent-side question of "which discharge mechanism do I attempt for this clause?" — as a meta-level activity outside the spec's normative surface. The R-S-P block is therefore *derivable* from the `:347` + `:350` pairing but not *stated*; a future maintainer can re-propose R-S-P framed as "selection guidance, not lattice change" and §4.4.1 in isolation does not pre-empt it.

**Reference-class rehoming.** The accurate comparable systems for LLMLL's multi-discharge-path surface are F* (Meta-F*, POPL 2019 — lemma/SMT/tactics dispatch, strategy left to user discretion) and Why3 (ESOP 2013 — prover-choice surface, multi-prover dispatch as a feature), **not** the Liquid Haskell `--no-termination` flag if it surfaces as analogy in future reasoning. The Liquid Haskell flag is a soundness-trade flag (admit-unsound vs prove-sound), categorically distinct from strategy selection among sound channels. Across the multi-discharge-path verification-systems landscape — Liquid Haskell, F*, Dafny, Why3, Idris, Coq/Lean tactics — prescribed ordering appears only between sound and unsound channels (assume vs proof); it does not appear between sound channels producing different evidence kinds. LLMLL's `verified` (body-faithful logical evidence) and `tested` (PBT-Lift statistical evidence within declared bounded coverage per §4.4.1:347) are both sound channels in this sense; this body of work converges on R-S-N as the literature-aligned default, not a project-specific stance.

**Meta-level / object-level boundary, named.** Verification strategy is meta-level (how the agent produces evidence); the trust lattice is object-level (what the trust report records). The LCF discipline (Gordon-Milner-Wadsworth) has kept these levels separate since the 1970s; LLMLL inherits the discipline whether named or not. Naming it turns R-S-N from "we choose not to prescribe" into "prescribing here would be a category error" — a structurally stronger position. A future maintainer cannot coherently re-propose R-S-P without first re-collapsing the meta / object distinction, which would force a rewrite touching at minimum the §4.4 trust-lattice machinery, the §5.3 verification-fragment routing, and the trust-report JSON schema. R-S-P is therefore not merely empirically unsupported (the postmortem-004:256-282 within-agent strategy variance + postmortem-005:50-65 F-V2 n=3/5 record refute any "agents naturally prefer one channel" claim); it is structurally precluded.

**R-S-P sharpening — three independent grounds, any one sufficient.** R-S-P fails on (i) diamond-collapse at `LLMLL.md §4.4.1:344` (the lattice declares `contract-checked` and `tested` incomparable; prescribing `verified > tested` re-orders the lattice by the back door); (ii) epistemic-kind category error at `:347` (logical and statistical evidence are categorically different trust signals, not points on a common scale); (iii) absence-of-literature-precedent (no comparable system orders sound discharge mechanisms by normative preference; LLMLL adopting one would require affirmative defense that neither the spec text nor the empirical record provides). Future treatments of this question that arrive in the language-team's surface should cite all three together.

**Parked spec-text candidate (no edit this turn).** At the next §4.4.1 touch — riding along with any other edit to that section (typo fix, cross-reference update, `evidenceCovers` clarification, channel-tag refinement) — append a one-sentence note. Either as a short third NOTE following `:350`, or as a trailing sentence on the existing `:350` NOTE:

> *Strategy selection — the choice of which discharge mechanism (body-faithful VC, PBT-Lift, etc.) to attempt for a given clause — is meta-level (how the agent produces evidence) and is outside this specification's normative surface. The lattice at §4.4.1:344 records the evidence that results, not the path taken to produce it; a future treatment that prescribes an ordering over discharge mechanisms would have to re-collapse this meta-level / object-level distinction before it could be coherently stated.*

The candidate adds zero guidance about *which* discharge to prefer (so it is not the R-S-G branch deferred at `findings/language-team.md:371`). It names the silence so the R-S-P block becomes self-evident from §4.4.1 alone rather than requiring re-derivation from this paper trail. Owner: `documentation-lead` at next §4.4.1 pass; **not opening its own turn**, per professor routing. If Phase-4 codex generalization data (Jun-12+) reopens R-S-G, the parked candidate remains compatible — meta-level discipline survives the addition of non-normative selection guidance.

**No spec move; no doc-lead hand-off; no commit.** `LLMLL.md` untouched. The candidate above is carried in-file against the next §4.4.1 edit trigger.

§LT-D-4 closure state unchanged: **CLOSED (R-S-N no spec change)** (2026-05-21). This addendum hardens the R-S-N rationale (literature alignment, structural meta/object grounding) and parks the §4.4.1 strengthening; it does not alter the closure state or the conditional-reopen criterion (Phase-4 codex generalization data).

---

#### LT-D-5 · H1-Correctness magnitude at n=18 (within-Claude) — point estimate revised down

##### Evidence

`postmortem-005:28-47` (F-V1) at n=18 within-Claude reports Claude × LLMLL target-reached rate of 5/18 = 28%, revising the Phase-3 standalone Claude × LLMLL rate of 44% (4/9, postmortem-004) as a small-n overestimate. Claude × Python 18/18 = 100%, Claude × Go 15/18 = 83% (after F-037 hole fill in the deepening slice). Cross-paradigm gap at n=18: LLMLL pays ~72pp vs Python, ~55pp vs Go on Claude.

##### Why we saw what we saw

Identical structural mechanism to LT-D-2: predicate-bar mismatch. R6d `Cred(R)` is a harder bar than `all-pass`. The deepening did not surface a new mechanism — F-V1 is *confirms-and-tightens*, not a new finding. The n=9 → n=18 magnitude revision is normal small-sample-tightening behavior; the postmortem-005 slice-1 LLMLL rate of 1/9 (11%) was investigated as a potential service-degradation or model-drift confound and ruled out (null result at `postmortem-005:127`).

##### Closure

Informational. No language-team move. The magnitude revision bears on any *future* external-facing narrative claim about LLMLL ergonomics (the kind of copy that would land in `docs/one-pager.md` or `README.md`); that is documentation-lead's surface, not language-team's. Flagged here so the doc-lead's eventual value-claim narrative update (the optional H3 implication from LT-D-3) lands against the n=18 magnitude, not the n=9 small-sample point estimate.

§LT-D-5 → **CLOSED (informational; n=18 baseline recorded)** (2026-05-21).

---

#### Routing emitted from LT-D

- **Experiment-lead-facing.** `experiments/repair-loop/README.md:45-47` requires a one-paragraph addendum recording H2 raw-form refutation + R-H2-W formal withdrawal, citing `postmortem-004:84-97` and `postmortem-005:79-90`. This is **apparatus**, not spec; the experiment-lead owns the harness `README.md`. The language-team does not edit this file. Naming the routing surface here so the user's next experiment-lead turn picks it up.
- **Documentation-lead-facing.** No direct same-turn surface. Optional future-turn item: a value-claim narrative review of `docs/one-pager.md` and `README.md` against the LT-D-3 + LT-D-5 findings ("lead with rich verification surface, not faster development; n=18 baseline"). Not gated on anything; routes at doc-lead convenience. **Not invoked this turn.** *(Resolved 2026-05-22 — doc-lead reviewed; zero in-scope edits warranted. `docs/one-pager.md` HEAD already leads with verification-surface frame; `README.md` is reference-only; LT-D-5 n=18 baseline stays in this file. See §LT-D-3 Closure addendum 1 above.)*
- **Language-team-internal.** Same-turn write to `experiments/repair-loop/findings/phase3-problem-shape-audit.md` as a dated addendum (`## Addendum 1 (2026-05-21) — H2 raw-form refutation; formal withdrawal recorded`), per the immutability protocol at `docs/design/language-comparison-experiments.md:247-249`. Authored adjacent to this fragment.
- **Compiler-engineer-facing.** None. F-042a/b from postmortem-005:91-110 are harness-script defence-in-depth items routed to compiler-engineer (`scripts/run_matrix.py`), not language-team scope; they live in `findings.md` `## Compiler-engineer`'s natural extension surface, not here.

---

### Routing

- **LT-A is closed** (R6d / 2026-05-13; empirically validated by Phase-3 data per LT-D-1). The R6d adjudication's design and the spec-vs-tool boundary it established remain load-bearing for any future predicate-vocabulary work.
- **LT-B is closed** (OBLIG-PBT-3 / OBLIG-PBT-4 / F-033 / F-034 shipped through v0.10.6; conjunctive criterion holds per Addendum 19). No residual.
- **LT-C is closed retrospective** (R5a shipped at `ecdf42f` in v0.10.3; closure recorded 2026-05-15).
- **LT-D is closed** (Phase-3-launch findings adjudicated 2026-05-21; doc-lead narrative review resolved 2026-05-22; professor R-S-N adjudication absorbed 2026-05-22). H2 raw form formally withdrawn (R-H2-W); verification-strategy split recorded as observed pattern with no spec move (R-S-N), R-S-N rationale hardened by professor literature alignment and meta/object boundary naming; H1-Assurance / H3 / H1-Correctness-magnitude closures are informational; LT-D-3 narrative routing closed-as-already-satisfied (doc-lead 2026-05-22 — `docs/one-pager.md` HEAD already leads with verification-surface frame). Two same-turn surface writes (2026-05-21): this LT-D fragment + `experiments/repair-loop/findings/phase3-problem-shape-audit.md` Addendum 1. Two follow-up same-file writes (2026-05-22): §LT-D-3 Closure addendum 1 + §LT-D-4 Closure addendum 1 (professor adjudication; reference-class rehoming; meta/object boundary; §4.4.1 spec-text candidate parked for next touch on that section). One next-turn hand-off remaining: experiment-lead update of `experiments/repair-loop/README.md:45-47`.

All four §LT items now closed. Phase-3 outcome on the language-team axis is empirically complete; Phase-4 design (when authorized) starts from this baseline.

---

## Experiment-lead

### Housekeeping

- DOC-CONSOLIDATE Phase 2 stub-window-bounded follow-up (2026-05-25): updated path-string citations in 3 phase3-* manifests (`manifest.phase3.json`, `manifest.phase3-no-codex.json`, `manifest.phase3-claude-deepen.json`) from `experiments/repair-loop/findings/phase3-problem-shape-audit.md` to `experiments/repair-loop/findings/phase3-problem-shape-audit.md` (file relocated 2026-05-25 per Phase 2 ship). 7 total path-string occurrences substituted (3 + 3 + 1 across the manifests; covers `_audit_pin.audit_path` field plus descriptive `_purpose` / `_audit_pin._note` prose citations). Reconciliation: post-edit `grep -l docs/design/phase3-problem-shape-audit experiments/repair-loop/manifest*.json` returns zero; all three manifests parse as valid JSON; `_audit_pin.audit_path` reads correctly under `python3 -c "json.load(...)"`. Side-finding (not a hand-off): no harness script consumes `audit_path` (`grep -rn audit_path experiments/` matches only the three manifests themselves), so the brief's stated FileNotFoundError risk is documentation-only — actual risk post-stub-deletion is stale-citation semantics, not runtime error. No schema, harness, or non-manifest change. Closes doc-lead Phase 2 stub-window-bounded routing item 1.

---

## Documentation-lead

(no findings recorded for this harness)
