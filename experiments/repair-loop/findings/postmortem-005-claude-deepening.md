# postmortem-005 — Phase-3 Claude deepening (n=3 → n=18 within Claude)

## Headline

Claude-only deepening probe of 27 cells (3 problems × 3 targets × 3 attempts, Claude × {LLMLL, Python, Go} × {001-hangman, 002-bank-ledger, 003-rate-limiter}) added to the Phase-3 sample brings within-Claude observations to n=18 per (language) and n=6 per (problem × language) cell. All three load-bearing claims from `findings/postmortem-004-phase3-launch.md` hold at higher n; one (H1-Correctness LLMLL-cost magnitude) revises **downward** from a small-n overestimate. One new procedural finding cluster (F-042) on harness operator-affordances surfaces for compiler-engineer. Predicted-vs-observed wall and spend tracked the run plan (4-7h wall, ~$0 on max-subscription). No spec-level findings new in this probe.

## Sample composition

- Manifest: `experiments/repair-loop/manifest.phase3-claude-deepen.json`
- Batch dirs (split by F-042a): `runs/20260520T173939Z-matrix/` (slices 1 + 3, 18 cells); `runs/20260520T173939Z-matrix-matrix/` (slice 2, 9 cells)
- Compiler: `llmll 0.10.6` (Phase-3 pin preserved)
- Harness HEAD at launch: `d29d352` (post F-040 path 1 fix at `4078b76`)
- Audit pin: `4078b76` carried verbatim from Phase-3
- Agent: `claude-default` — Claude Code CLI 2.1.141, default model (same cmd-string as `manifest.phase3.json`)
- Cells executed: 27 / 27. Status: 22 target-reached, 4 budget-exhausted, 1 infrastructure-fail.
- Per-cell wall (deepening only): LLMLL ~48 min, Python ~6 min, Go ~7 min. Total run wall ~9.3h (slice 1 dominated by LLMLL k=5 budget-exhausted cells × 1800s per turn).

## Combined n=18 per language (Phase-3 + deepening)

| Language | Phase-3 | Deepening | **Combined** | Wall (avg/cell) |
|---|---|---|---|---|
| Claude × LLMLL | 4/9 (44%) | 1/9 (11%) | **5/18 (28%)** | ~48 min |
| Claude × Python | 9/9 (100%) | 9/9 (100%) | **18/18 (100%)** | ~10-15 min |
| Claude × Go | 6/9 (67%, 3-cell F-037 hole) | 9/9 (incl. fill) | **15/18 (83%)** | ~5-10 min |

## Verified findings

### F-V1 (confirms-and-tightens): within-Claude H1-Correctness — LLMLL is the costly slot

**Priority:** High
**Consumer:** language-team

#### Evidence

Combined-n table above. At n=18 per language, Claude pays **~72pp** on target-reached for LLMLL vs Python and **~55pp** vs Go. Phase-3's standalone Claude × LLMLL rate of 44% (4/9) was a small-n overestimate; the n=18 read at **28% (5/18)** is the more defensible point estimate. The deepening did not surface a new mechanism — the gap traces to the same predicate-bar mismatch postmortem-004 identified (R6d Cred predicate for LLMLL vs all-pass on Python/Go).

#### Why we saw what we saw

LLMLL terminal predicate Cred(R) requires `(|R| > 0) ∧ (n_asserted = 0) ∧ (n_no_contract = 0)` per `experiments/repair-loop/scripts/run_repair_loop.py:_count_bad_trust_tiers`. Python/Go terminal predicate is all-verifier-commands-pass. The two are not equally hard; the LLMLL gap is a difficulty-of-bar gap, not (only) a language-suitability gap.

#### Implication for language-team

Confirms the Phase-3 H1-Correctness gap is real, not n=3 noise. The "matched-difficulty H2-revised-A" or "per-tier-of-trust H2-revised-B" reframings noted in postmortem-004 are harder to defer at higher n — Phase-3 was not a sample-size artefact.

#### Acceptance

A next probe that matches predicate bars (e.g., relaxes LLMLL Cred to all-pass equivalent, OR tightens Python/Go to a property-based bar) would isolate the language-effect from the bar-effect. Not in scope for this probe; documented for language-team adjudication.

### F-V2 (tightens): strategy-variance signal — verified-into-tier dominance

**Priority:** Medium
**Consumer:** language-team

#### Evidence

Of 5 combined Claude × LLMLL successes (Phase-3: 4; deepening: 1), at least 3 are high-verified tier_profile shape — postmortem-004 cited Phase-3 cells 12 (verified=9) and 20 (verified=8) explicitly; deepening cell 8 (`runs/20260520T173939Z-matrix/cells/cell_08/run_dir/evaluation.json`) carries `locally_verified_obligations: 6, outstanding_trust_acknowledgments: 0, compositionally_verified_module_rate: 1.0, pbt_sample_pass_rate: 1.0`. n=3/5 high-verified is small but consistent across two problems (002-bank-ledger ×1, 003-rate-limiter ×2).

#### Why we saw what we saw

When Claude reaches the Cred(R) terminal on LLMLL, it tends to do so by producing contracts that the body-faithful VC chain verifies, not by producing contracts that pass only the PBT layer. The path of least resistance to "0 asserted, 0 no_contract" is to commit to verified obligations rather than to asserted ones — once the contract is asserted, no number of tests can clear `n_asserted = 0`.

#### Implication for language-team

The strategy-variance finding from postmortem-004 has tightened (n went from 2/4 to 3/5) but not changed shape. n=3/5 supports the directional claim but doesn't confirm it; a wider sample (Codex × LLMLL would add 6 more LLMLL successes at the Phase-3 6/9 rate) would be the natural deepening. Falls into the Phase-4 codex-generalizability slot already named in postmortem-004.

### F-V3 (confirms-and-extends): within-Claude H2 is bimodal, not gradient

**Priority:** High
**Consumer:** language-team

#### Evidence

Deepening LLMLL turn-count distribution (per-cell `evaluation.json:turns_completed`):

| Cell | Problem | Attempt | State | Turns |
|---|---|---|---|---|
| 1-4, 6, 7, 9 | 001, 002, 003 | various | budget-exhausted | **5** (all) |
| 5 | 002-bank-ledger | 2 | infrastructure-fail | 1 (rc=124) |
| 8 | 003-rate-limiter | 2 | target-reached | **1** |

No deepening LLMLL cell terminated at turns 2, 3, or 4. Phase-3 high-verified cells (postmortem-004 cells 12, 20) succeeded at turn ≤2 by the postmortem-004 record. Deepening Python: all 9 cells at turn 1. Deepening Go: 7 at turn 3, 2 at turn 1.

#### Why we saw what we saw

When Claude has the right contract shape on turn 1, the per-obligation VC chain produces a Cred(R)-satisfying solution immediately. When it doesn't, the repair-loop budget k=5 doesn't sample the space between "wrong shape" and "right shape" — it samples two modes (1-turn success, 5-turn failure). The cliff is in contract-shape decision space, not on a smooth refinement gradient. Go's 3-turn typical reflects a different mechanism: unused-imports / type-mismatch fixups that the agent makes locally and re-emits, not contract-shape pivots.

#### Implication for language-team

H2 refutation from postmortem-004 holds and tightens. The "convergence differential" framing of H2 is structurally wrong for LLMLL on Claude — k=5 doesn't sample a curve, it samples two modes. Any H2 reframing must account for bimodality: a matched-difficulty re-formulation should ask whether LLMLL's success-mode is faster on the cells that *do* succeed, not whether mean turns-to-success differs.

## F-042 cluster (procedural, NEW)

**Priority:** Defence-in-depth
**Consumer:** compiler-engineer (harness scripts)

### F-042a: `--batch-id` double-suffix on resume

**Evidence.** `experiments/repair-loop/scripts/run_matrix.py:249-253` (`resolve_batch_dir`) computes `name = f"{batch_id}-{label}"` where `label = manifest.get("batch_label") or "matrix"`. An operator who passes `--batch-id 20260520T173939Z-matrix` (the directory name observed under `runs/`) gets a sibling batch directory `runs/20260520T173939Z-matrix-matrix/` on resume. In this run, slice 2 (Python, 9 cells) wrote to the sibling directory because the resume from cell 10 was launched with the directory-name form of the batch-id.

**Fix proposed (prose, not patch).** Two candidates: (a) strip a trailing `-{label}` from `batch_id` if present before constructing `name`, with a one-line stderr note ("interpreted batch-id `20260520T173939Z-matrix` as raw stamp `20260520T173939Z`"); (b) document `--batch-id` in `--help` and the README as "bare stamp only" and emit a hard error if the user passes a suffixed form. Option (b) is safer (no silent rewriting of operator input).

**Acceptance.** A follow-on probe resumed via the directory-name form does not produce a sibling — either a clear error message OR a documented rewrite.

### F-042b: end-of-matrix `rc=1` on prior-cell failure

**Evidence.** `run_matrix.py:203` returns `1 if any_failed else 0` at end-of-matrix. `any_failed` is set True at the first infra-fail or harness-error cell and persists. In this run, slice 3 (Go, cells 19-27) finished 9/9 target-reached but the matrix returned `rc=1` because cell 5 had earlier infra-failed in slice 1. The task notification surfaced "failed with exit code 1" despite a clean slice 3.

**Fix proposed (prose).** Split the end-of-matrix exit-code semantic. Keep `rc=0` for fully clean; introduce a new code (e.g., `rc=4` "completed with prior failures") to distinguish from `rc=1` (currently overloaded). Document in `--help`. An operator triaging task notifications should be able to tell "matrix complete, some cells infra-failed" from "matrix aborted."

**Acceptance.** End-of-matrix exit code disambiguates "complete with prior failures" from "aborted."

## F-035 ghost (single re-observation)

**Priority:** Defence-in-depth
**Consumer:** user

**Evidence.** Cell 5 (002-bank-ledger try 2) infra-fail with `agent rc=124 at turn 1` (SIGTERM after 1800s per-turn timeout). 1 of 27 cells = ~3.7% rate. Phase-3 had no rc=124 timeouts at 1800s. Single occurrence, not blocking; circuit breaker did not trip (isolated, not 3-consecutive).

**Implication.** Per-turn timeout 1800s is sufficient at >96% rate on Claude × LLMLL but not 100% on `002-bank-ledger`. If rc=124 recurs at >5% rate in future probes, F-035 reopens; for now it stays closed.

## Withdrawn items

None.

## Null results

- **Slice-1 LLMLL rate-drop confound search.** The slice-1 LLMLL rate of 1/9 (11%) crossed the run-plan's "surprise" threshold (>20pp shift from Phase-3's 44%). Investigation: no service-degradation signal on `status.claude.com` for the run window; same compiler pin; same harness HEAD; same cmd-string; same per-turn timeout. Null result: Phase-3's 44% was a small-n overestimate at n=9; combined-n at 28% is consistent with both samples within their wide CIs. No model drift, no harness drift, no procedural confound.

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---|---|---|---|
| F-V1 | LLMLL H1-Correctness gap holds, point estimate revises down | language-team | High | (reframing decision) |
| F-V2 | Strategy-variance verified-into-tier dominance tightens to n=3/5 | language-team | Medium | (await Codex deepening) |
| F-V3 | Within-Claude H2 is bimodal not gradient | language-team | High | (H2 reframing must account) |
| F-042a | `--batch-id` double-suffix on resume | compiler-engineer | Defence-in-depth | small (help-text + validation) |
| F-042b | End-of-matrix `rc=1` semantics overloaded | compiler-engineer | Defence-in-depth | small (new exit code + help) |
| F-035 ghost | rc=124 timeout single re-observation | user | Defence-in-depth | (monitor) |

## Per-consumer scoped files

This postmortem does not write to per-consumer scoped files (`compiler-team.md`, `language-team.md`, `documentation-team.md`); postmortem-004 captured the load-bearing Phase-3 findings and the language-team has already turned on them. The F-V1/V2/V3 findings here are *confirmations* of postmortem-004 at higher n, not new findings — the same hand-off is in effect. F-042a/b are new and would go to `compiler-team.md` if compiler-engineer accepts the harness-side fixes; gating on that acceptance.

## Notes for postmortem-006 (Phase-4 candidate)

If the Codex × Python/Go fill-in runs after Jun 12 (per postmortem-004 deferred-experiment registry), it will deliver:

- Codex × LLMLL at n=18 (combining Phase-3 n=9 with a Phase-4 deepening of n=9)
- Codex × Python at n=9 (new — Phase-3 hole)
- Codex × Go at n=9 (new — Phase-3 hole)

That would resolve the agent-generalizability question postmortem-004 raised and that this deepening intentionally did not address. It would also surface 6 more Codex × LLMLL successes (at the Phase-3 6/9 rate), which would lift the strategy-variance n from 5 to ~11 and let F-V2 cross from "directional" to "confidence-tightening."

---

## Addendum 1 (2026-05-22) — per-consumer routing closed; F-042a/b landed

The §"Per-consumer scoped files" gating note above (:140-142, "F-042a/b are new and would go to `compiler-team.md` if compiler-engineer accepts the harness-side fixes; gating on that acceptance") is **satisfied**. Compiler-engineer accepted both items in `findings/compiler-engineer.md` §CE-E (CE-E-1 for F-042a, CE-E-2 for F-042b); the Python patch landed at commit `8990779` on branch `harness/f-042-batch-id-and-exit-codes` — `resolve_batch_dir` suffix guard + `EXIT_COMPLETED_WITH_PRIOR_FAILURES = 4` end-of-matrix split + argparse epilog documenting the 0/1/2/3/4 exit-code table + two new unit tests in `scripts/test_run_matrix.py` (both green: `test_rejects_suffixed_batch_id`, `test_returns_4_when_matrix_completes_with_prior_failure`).

F-V1/V2/V3 mining surface also landed in the same window: `findings/language-team.md` §LT-D-1..5 (commit `dd5fdc1`, 2026-05-21) adjudicates the load-bearing items across postmortem-004 + postmortem-005, with §LT-D-2 carrying the R-H2-W formal withdrawal and §LT-D-4 the R-S-N strategy-variance adjudication. The ":141 same hand-off is in effect" line was correct as written 2026-05-21; the hand-off has now been executed.

No gating items from this postmortem remain open at apparatus or per-consumer surface.
