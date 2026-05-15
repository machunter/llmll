# Compiler Engineer — Findings from the Repair-Loop Harness

**Source:** Integrated postmortem at `findings/postmortem-001-apparatus-validation.md`. This file extracts compiler-engineer-actionable items only; the full evidence trail (sample composition, run-dir citations, per-cell data) lives in the postmortem.
**Date:** 2026-05-12 (Phase-2 calibration outcome; Addendum 11; revised 2026-05-12 by Addendum 14; CE-B closed 2026-05-12 by MOD-PBT-1 / v0.10.3; R6d engineer track shipped 2026-05-12 → closure notes below).

This file covered two open work units routed from Phase 2 and tracks a third that surfaced and closed same-day:

- **CE-A — verify-fixpoint diagnostic surface (F-028).** Closed 2026-05-12 by postmortem-001 Addendum 14.
- **CE-B — PBT FuncEnv lacks imported-module def-logic (F-018).** Closed 2026-05-12 by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`).
- **CE-C — Trust-report `tier_profile` aggregate (R6d).** Closed 2026-05-12 by `bb1bd98` + `bbab67b`. The R6d engineer-track surfaced from `findings/language-team.md` §LT-A's adjudication; the work shipped the same day.

All three compiler-engineer tracks routed from Phase 2 are now closed. No further compiler-engineer action in scope for `findings/postmortem-001`; the R6d closure has full evidence in postmortem-001 Addendum 15.

A **harness-design** item (capability-probe in `run_matrix.py` prereqs, F-025) remains routed to `experiment-lead` — unchanged. Mentioned here only because the apparatus event that motivated it (Plan Mode pin) was diagnosed during Phase 2; full detail in postmortem-001 Addendum 11 §F-025.

---

## CE-A · verify-fixpoint diagnostic surface (F-028) — closed, no work needed

**Status:** Closed by postmortem-001 Addendum 14 (2026-05-12). No compiler patch required. No harness patch required.

The Addendum-11 framing claimed `verify-fixpoint`'s diagnostic channel was silent on failure ("stderr empty across 15 LLMLL turns"). That observation was true for the `stderr` field but incomplete — the actual diagnostic content lives on `stdout`, which the harness's `_run_verifier_chain` already captures and propagates to the agent via `context/turn_NN_verifier.json`. Read-only retrospective inspection of Phase-2 cell 01's turn-3 stdout (Liquid-Fixpoint SAFE on a passing solution) and turn-4 stdout (`(error :phase parse :file "solution.llmll" :line 52 :col 10 :message "reserved word post used as identifier" ...)` on a self-broken solution) showed clean, actionable diagnostics passing through the existing pipeline.

Full evidence in `findings/postmortem-001-apparatus-validation.md` Addendum 14 §"F-028 reframed — diagnostics exist; agent does not productively iterate on them". The substantive open question reattaches to **F-029 (non-monotonic repair)** — agent-capability axis, routed to experiment-lead + language-team, not to compiler-engineer.

No compiler-engineer action on F-028. Phase-3 gate from this file narrows to CE-B only.

---

## CE-B · PBT FuncEnv lacks imported-module def-logic (F-018, carried from Addendum 8) — CLOSED

**Status:** Closed 2026-05-12 by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`). No further compiler-engineer action.

**Priority (historical):** High — open since Phase 1.75. Phase 2 produced confirming empirical evidence (F-030).

### Evidence

This finding is documented in detail in postmortem-001 Addendum 8 (compiler-side discharge channel) and Addendum 11 §F-030 (Phase-2 empirical confirmation). The summary for this file:

- Across n=3 LLMLL cells in Phase 2, agent emitted 2–3 `(check ...)` blocks per solution (cells 01–03).
- Per `evaluation.json:scoring.correctness_subscores.core_behavior` for each cell: `passed=0, failed=0, skipped=2-3, channel=llmll-pbt`.
- Trust report entries for these solutions are at `asserted` tier, never `tested` — i.e., the `(check ...)` blocks do not engage the test channel that would lift entries to `tested` tier.

This is the structural mechanism Addendum 8 predicted (F-017, now revised and tracked as F-018 against compiler-engineer): the PBT FuncEnv does not see imported-module `def-logic`, so checks defined in the solution module cannot reach functions from the standard prelude or other imports when the runner instantiates them.

### Why we saw what we saw

Per Addendum 8's diagnosis: `compiler/src/LLMLL/PBT.hs` constructs a per-test FuncEnv from the *current* module's `def-logic` declarations only. Phase 2's evidence is consistent with this — solutions that depend on `list-fold`, `pair`, `Result`, etc., have those calls in the `(check ...)` body, the PBT runner cannot resolve them, and the check skips silently.

### Fix

Carried from Addendum 8: extend the PBT FuncEnv with imported-module `def-logic` declarations (whichever modules are in the solution's import set). The Phase-2 data did not surface a new mechanism; it confirmed the predicted one fires under realistic agent emissions.

### Acceptance

Closing CE-B / F-018 should produce the following on re-probe:

- For a cell whose solution emits `(check ...)` blocks that reference standard-library `def-logic`, `evaluation.json:correctness_subscores.core_behavior` reports `skipped < total` (some checks execute).
- At least one trust-report entry crosses from `asserted` to `tested` tier when the corresponding `(check)` block passes.
- Phase-2 cell 02's solution (`runs/20260512T033017Z-.../solution.llmll`) re-run under the patched compiler shows non-zero `passed` in its core_behavior subscore.

---

### Closure note (2026-05-12)

The fix described in "Fix" above shipped as MOD-PBT-1 in v0.10.3 (commit `d1b7a58`). `doTest` switched from `loadStatements` to `loadStatementsMulti`; a new `assembleTestStatements` helper in `LLMLL.PBT` concatenates each `(open path)`-targeted imported module's `SDefLogic` declarations ahead of the local statement list before invoking `runPropertyTests`. 5 new tests in `ModuleSpec.hs` M-08 block. 584 → 589 Haskell tests; 37 Python unchanged. The companion docs commit `b9b5eee` adds the §8.6 / §4.8 spec note.

The acceptance condition above ("at least one trust-report entry crosses from `asserted` to `tested` tier when the corresponding `(check)` block passes") was **not directly tested** by R6d's re-probe — the re-probe re-verified the three Phase-2 cells' final-turn solutions but did not re-run `llmll test` on them. A focused re-test of those solutions under v0.10.4-pre is a follow-up question, tracked under `findings/language-team.md` §LT-B status update.

---

## CE-C · Trust-report `tier_profile` aggregate (R6d) — CLOSED

**Status:** Closed 2026-05-12 by `bb1bd98` + `bbab67b`. No further compiler-engineer action.

### Evidence

`findings/language-team.md` §LT-A's R6d resolution required a fixed-arity tier-count aggregate over the trust report, hosted compiler-side with independent versioning from the source JSON-AST schema. The work shipped same-day on 2026-05-12:

- `bb1bd98` (`feat(trust): add tier-count profile aggregate to trust-report emit (R6d)`) — `TierProfile` record + `aggregateTiers` function in `compiler/src/LLMLL/TrustReport.hs`, diamond-meet semantics preserved via `teEffectiveLevel` (pre=contract_checked, post=tested → effective level `asserted` → increments `tpAsserted` only, never both `tpContractChecked` and `tpTested`). `formatTrustReportJson` emits `tier_profile` + `trust_report_version: "1.0.0"` alongside the unchanged `entries` / `summary` / `suppressions` blocks. New `docs/llmll-trust-report.schema.json` (JSON Schema draft 2020-12) documents the full trust-report emit with versioning independent of `docs/llmll-ast.schema.json:expectedSchemaVersion` ("0.4.0" untouched — emit-side change is semantically orthogonal to the parser-input schema; bumping source `schemaVersion` would force ~22 `.ast.json` fixture rewrites for a change those fixtures do not touch). 5 new tests under "v0.10.4 tier-count profile (R6d)" describe block; 589 → 594 Haskell.
- `bbab67b` (`docs(spec): note tier_profile aggregate on trust-report JSON emit in §4.4.4 (R6d)`) — one-sentence `LLMLL.md §4.4.4` addition pointing readers at `docs/llmll-trust-report.schema.json` and referencing the `LLMLL.md §4.4.1:344` diamond-lattice no-scalarization discipline that disqualifies any aggregation over `tier_profile`.

### Acceptance

- ✅ `compiler/src/LLMLL/TrustReport.hs` emits the `tier_profile` aggregate.
- ✅ `docs/llmll-trust-report.schema.json` validates with `additionalProperties: false` on the trust-report root and the required-field list `["trust_report_version", "entries", "summary", "tier_profile", "suppressions"]`.
- ✅ Re-probe of three Phase-2 cells (postmortem-001 Addendum 15) confirms the aggregate matches per-entry tier classifications and is consumable by the patched harness evaluator (`scripts/evaluate_run.py:_summarize_trust_report`).

### Closure

No follow-up engineer track from R6d. The pending v0.10.4 release will ship the harness-side changes (experiment-lead) plus doc-lead's CHANGELOG entry, roadmap §LT-A close-out row, and the cross-link from `docs/design/language-comparison-experiments.md §Soundness Assessment` to the new harness-doc section.

---

## CE-D · F-034 — `evalBuiltinApp` residual builtin coverage on c02/c03-shape (post-Addendum-18, 2026-05-14)

**Status:** **Open.** Routed from postmortem-001 Addendum 18. Re-targeting of Addendum 17's F-033 residual: F-033's named scope (`unwrap` + GaveUp diagnostic refinement) shipped on this branch and that surface is closed; the empirical c02/c03 unblocker is a **superset** of that surface.

**Priority:** **High — gates strong-form Phase-3 `tested`-tier signal on c02/c03-shape problems**, which is the load-bearing axis for H1-Assurance on the Phase-3 problem suite. OBLIG-PBT-4 closure on c01-shape is empirically confirmed (15/15 properties on c01-subjects produced `.verified.json` sidecar writes; 4/5 tries lift `tier_profile_post.tested = 1`); the only path-1 engineer item remaining before Phase 3 launch is this one.

### Evidence

Addendum-18 matrix on the v0.10.6-candidate binary built atop merge `d220632` shows c02 0/10 properties and c03 0/10 properties achieving `samples_run ≥ 1` under the new F-033 diagnostic. The diagnostic correctly attributes every Skipped property's GaveUp to body-evaluator discard:

> `"property body did not reduce on any sample (1000 evaluated, 0 returned bool — likely unmodeled builtin or unreduced callee body in property body)"`

[Contracts.hs:412-472](../../../compiler/src/LLMLL/Contracts.hs#L412-L472) — `evalBuiltinApp` clause set. Missing clauses on c02/c03's transfer-body call chains:

| builtin | type-checker signature ([TypeCheck.hs:90-120](../../../compiler/src/LLMLL/TypeCheck.hs#L90-L120)) | used in (c02/c03) | clause? |
|---|---|---|---|
| `list-filter` | `[list[a], fn[a] -> bool] -> list[a]` | c02 `map_get`/`map_insert`; c03 `find-account` | **no** |
| `list-prepend` | `[a, list[a]] -> list[a]` | c02 `map_insert` | **no** |
| `list-empty` | `[] -> list[a]` | c02 `create_ledger`; c03 `create-ledger` | **no** |
| `string-concat-many` | `[list[string]] -> string` | c02 `transfer` (log entry construction) | **no** |
| `int-to-string` | `[int] -> string` | c02 `transfer` (log entry construction) | **no** |
| `list-head` | `[list[a]] -> Result a string` (returns `Result`!) | c02 `map_get`; c03 `find-account` | **bug**: existing clause at [Contracts.hs:434](../../../compiler/src/LLMLL/Contracts.hs#L434) returns `Just hd` (raw element) instead of `Just (EApp "Success" [hd])`; the `[EApp "nil" []]` arm is also absent (should return `Just (EApp "Error" [...])`) |

Mechanism: a c02 property body `(match (transfer l f t a) ((Success new_l) ...) ((Error _) true))` reduces transfer's body, which reduces `(map_get accounts from)` (uses `list-filter`), which returns `Nothing` from `evalBuiltinApp`. The `Maybe Expr` short-circuits up; the prop closure returns `QC.discard`; `bodyDiscardCount` increments. Repeat 1000 times → GaveUp with the new diagnostic text. c03's `find-account` uses `list-filter` directly; same propagation.

The `list-head`-returns-raw-element bug is independent of the missing-clauses set: even if `list-filter` were modeled, c02 `map_get` body's `(match (list-head matches) ((Success p) ...) ((Error _) ...))` would still fail to reduce because `list-head` returns `hd` not `(Success hd)`. Both must move for c02 to lift. c03's `find-account` similarly does `(list-head matches)` after `list-filter`.

### Scope

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

`filterCons` mirrors `foldCons` / `mapCons` at [Contracts.hs:497+](../../../compiler/src/LLMLL/Contracts.hs#L497) — apply the predicate lambda per element, keep cons cells where predicate reduces to `True`. `stringConcatMany` walks the cons-chain of `LitString` literals and concatenates. Both share the existing fuel discipline.

### Acceptance

A v0.10.6+ compiler run on `experiments/repair-loop/runs/20260514T233334Z-reprobe-pbt45-c01c02c03-v0.10.6-candidate/c02/solution.k1.llmll` reports `samples_run ≥ 1` on either property; likewise for c03. Optional but recommended: a c02-subjects variant (analogous to the c01-subjects cell in Addendum-18) constructed with `:subjects [transfer total_balance]` etc. confirms the OBLIG-PBT-4 path is end-to-end-functional on c02-shape too — the c01-subjects pass confirms only the path's correctness on c01-shape; the c02 end-to-end test additionally validates the F-034 + OBLIG-PBT-4 interaction.

### Sequencing

Engineer-adjudicated. Two options:

1. **Combined cut v0.10.6** (OBLIG-PBT-4 + F-034 in one release). Experiment-lead view: cleaner empirical signal because c02/c03 cannot be re-probed against a standalone-OBLIG-PBT-4 binary as a separate gate; doc-lead's combined seal covers both atomically; the v0.10.6 CHANGELOG entry reads as one OBLIG-PBT-4-and-PBT-5 release.
2. **Split cut v0.10.6 (OBLIG-PBT-4 only) + v0.10.7 (F-034)**. Faster ship cadence on the OBLIG-PBT-4 surface; doc-lead splits into two passes; Phase 3 launch waits on v0.10.7 either way.

Doc-lead's surface is the same in both options; only the release-grouping differs.

### Routing

- **F-034 → compiler-engineer** (this entry). No design decision pending.
- **OBLIG-PBT-4 closure → already shipped on this branch**, no action; routing here is closure-only for the compiler-engineer file (see CE-D-OBLIG-PBT-4 below).
- **Doc-lead waits** on F-034 land; do not invoke until both items are in the release branch (or, under option 2, invoke once per release cut).

---

## CE-D-OBLIG-PBT-4 · OBLIG-PBT-4 `:subjects` opt-in — closed-shipped, mechanism confirmed (Addendum 18, 2026-05-14)

**Status:** **Closed-shipped, mechanism empirically confirmed on c01-shape.** No further engineer action from this finding. Tracked here for closure-bookkeeping symmetry with CE-A/CE-B/CE-C.

Implementation: [Syntax.hs:425-437](../../../compiler/src/LLMLL/Syntax.hs#L425-L437) (`propSubjects` field on `Property`), [Parser.hs:290-326](../../../compiler/src/LLMLL/Parser.hs#L290-L326) (text-syntax parsing), [ParserJSON.hs:216-241](../../../compiler/src/LLMLL/ParserJSON.hs#L216-L241) (JSON-AST parsing + dedupe + empty-list rejection), [PBT.hs:687-720](../../../compiler/src/LLMLL/PBT.hs#L687-L720) (`processRun` per-subject-DLTested writeback branch), [docs/llmll-ast.schema.json](../../../docs/llmll-ast.schema.json) (schema bump `0.4.0` → `0.5.0` for additive optional `CheckDecl.subjects`).

Acceptance (Addendum 18 §F-OBLIG-PBT-4):
- ✅ Parser accepts `:subject f` sugar and `:subjects [f g …]` form.
- ✅ Writeback emits per-subject `DLTested n` records.
- ✅ Shared `pbt_witnesses` hash across all per-subject records of one property (canonical-body hashing is content-stable across the matrix).
- ✅ R6d `effective_level` machinery bounds dependent callees correctly (body-faithful, not isolation-faithful).
- ✅ End-to-end: c01-subjects 4/5 tries achieve `tier_profile_post.tested ≥ 1`; the remaining 1/5 misses on orthogonal near-threshold QC variance.

---

## Routing

- **CE-A is closed** (postmortem-001 Addendum 14). No compiler-engineer action.
- **CE-B is closed** (MOD-PBT-1 / v0.10.3, 2026-05-12). Was structurally the blocker behind F-030; F-018's PBT FuncEnv extension shipped. The empirical question "does `(check ...)` now elevate obligations to `tested` under realistic agent emissions?" remains open under `findings/language-team.md` §LT-B and is an experiment-lead re-probe, not compiler-engineer work.
- **CE-C is closed** (R6d / `bb1bd98` + `bbab67b`, 2026-05-12). No follow-up engineer track from R6d.
- **CE-D is open** (F-034, routed 2026-05-14 from postmortem-001 Addendum 18). Mechanical scope; gates Phase-3 strong-form `tested`-tier signal on c02/c03-shape; sequencing engineer-adjudicated (combined v0.10.6 cut or split v0.10.6 + v0.10.7).
- **CE-D-OBLIG-PBT-4 is closed** (`oblig-pbt-4-5/subject-metadata-and-eval-coverage` working tree atop merge `d220632`, mechanism confirmed by Addendum 18). Tracked here for closure-bookkeeping only.
