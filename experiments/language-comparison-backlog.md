# Experiment-Lead Backlog — Cross-Language Harness (pre-bootstrap)

**Status:** Pre-Phase-3-launch. The cross-language harness is implemented at `experiments/repair-loop/` (the historical directory name; the harness matured from repair-loop apparatus validation into the cross-language harness over Phase 1 / Phase 2). This file is the experiment-lead's tracking surface for items routed to the role but blocked on trigger conditions that have not yet fired. Phase-3 launch readiness is addressed by in-place extension of `experiments/repair-loop/`, not by greenfield bootstrap of a new directory.
**Date opened:** 2026-05-15.
**Locus rationale:** Single file at the `experiments/` root. The cross-language harness at `experiments/repair-loop/` is the launch home; this backlog file is the experiment-lead's pre-Phase-3 tracking surface and lives at the root rather than inside `experiments/repair-loop/` to keep it visible as cross-cutting work (it lists items that span the harness, the design doc, and the methodology surface). It can later move into `experiments/repair-loop/BACKLOG.md` via `git mv` if cross-cutting visibility ceases to matter; the cost of the move is small and decoupled from Phase-3 launch.
**Source for both entries:** Language-team adjudication 2026-05-15, routed from professor's three assignments. Methodology-discipline bundle (A1 immutability extension + A2-spec `prediction_match` field + A3 documentation-scope footnote) landed in the same turn at `docs/design/language-comparison-experiments.md` §"Experimental Controls" #7a, §"Target Adapter Shape", §"Reporting Output", §"Open Design Questions" #3.

---

## B-1 · `prediction_match` field emission + aggregator-side separation (A2-harness)

**Status:** Registered, blocked on trigger.
**Routed from:** Professor's Assignment 2 split — spec-side landed 2026-05-15; harness-side deferred to this backlog per the assignment's "register as an experiment-lead backlog item now, do not hold it in the language-team's queue" instruction.

### Trigger

The cross-language harness at `experiments/repair-loop/` gains per-cell `prediction_match`-aware result aggregation. The harness currently emits `matrix_report.json` (top-level) plus `cells/cell_NN/manifest.json` (per-cell) and per-attempt turn-by-turn artifacts (`solution.kN.llmll`, `verify.kN.json`, etc.); it does not currently emit a per-cell `evaluation.json` in the schema sketched at `docs/design/language-comparison-experiments.md:549-580`. B-1's substantive work is the schema extension — either growing a per-cell `evaluation.json` analog or threading `prediction_match` into the existing `matrix_report.json:cells[]` entries — whichever the experiment-lead adjudicates at implementation time as the smaller change.

### Deliverable when triggered

Three sub-items, all harness-side, all experiment-lead-owned:

1. **Per-cell field emission.** `evaluation.json` schema (per `docs/design/language-comparison-experiments.md` §"Reporting Output") gains `prediction_match: enum["match", "divergence", "unaudited"]`, default `"unaudited"` on every cell. Emitted unconditionally by the evaluator, regardless of target.
2. **Aggregator-side separation.** Cross-language `matrix_report.json` / `matrix_summary.md` generation logic excludes cells with `prediction_match == "divergence"` from the primary H1-Assurance aggregation and routes them to a separately-labelled report section. Cells with `prediction_match == "match"` or `"unaudited"` flow into the primary aggregation per the launch matrix's standard logic.
3. **Comparison logic discipline.** The `match` / `divergence` / `unaudited` value is assigned by **human post-hoc judgment** against the pinned-commit-hash audit at `experiments/repair-loop/findings/phase3-problem-shape-audit.md` (per `docs/design/language-comparison-experiments.md` §"Experimental Controls" #7a immutability extension). The harness does not parse the audit content or automate the comparison in B-1's scope. Automation of the comparison is registered as a separate, deferred sub-item below.

### Acceptance

A reviewer reading a Phase-3 `matrix_report.json` can locate the `prediction_match` field on every cell row, and `divergence` cells appear in the separately-labelled report section rather than the primary H1-Assurance aggregate. The "flagged for separate discussion" clause in `docs/design/language-comparison-experiments.md` Control #7a acquires its syntactic referent at this point.

### Out of scope

- **Per-problem prediction content.** The audit's substantive content (which verification paths each problem is expected to engage) is the language-team's S7 obligation at `experiments/repair-loop/findings/phase3-problem-shape-audit.md`, distinct from B-1.
- **Automated audit-vs-observed comparison.** A future sub-item; not in B-1's deliverable. Registered here so future planning is on notice that the field-emission and the comparison-automation are separable.
- **Per-language toolchain pins** (Python / Node / Go / rustc versions) needed for cross-language reproducibility. Lands when the cross-language harness is bootstrapped; not bundled into B-1.

---

## B-2 · symmetric-documentation dose-response side-arm (A3-followon)

**Status:** Registered, blocked on conjunctive trigger.
**Routed from:** Professor's Assignment 3 with the Hanenberg 2010 (*An experiment about static and dynamic type systems*, OOPSLA) and Endrikat, Hanenberg, Robbes & Stefik 2014 (*How do API documentation and static typing affect API usability?*, ICSE) anchors landed in the same turn at `docs/design/language-comparison-experiments.md` §"Open Design Questions" #3 resolution.

### Trigger (conjunctive)

All three conjuncts must hold:

1. **Launch matrix completes.** The Phase-3 cross-language matrix has run to terminal state (all cells either reached terminal-target or hit budget/timeout) and the `matrix_report.json` is on disk.
2. **H1-Assurance read is on record.** A postmortem entry has documented the launch's H1-Assurance read with sample composition (`n` attempts × agents × problems × targets) and the per-target `tier_profile_post` analog tuple emitted per `docs/design/language-comparison-experiments.md` §"Reporting Output" 3-tuple shape.
3. **Discipline-guide design exists for Python / Go.** A non-trivial design artifact — *not* "`LLMLL.md` verbatim handed to a Python agent" but a symmetric-in-shape document at matched token weight and matched verification-discipline density. Per the language-team's adjudication 2026-05-15, this sharpens the professor's two-conjunct trigger; experiment-lead may relax to the two-conjunct form when the time comes (the discipline-guide design itself remains a non-trivial authoring task either way).

### Deliverable when triggered

A side-arm matrix run with the following shape:

- **Problem set:** One problem from the launch matrix, selected post-launch on H1-Assurance signal (typically the problem where the launch's LLMLL-vs-Python/Go gap was widest, but the choice depends on launch outcomes).
- **Budget:** ~⅓ per-cell budget relative to the launch matrix's per-cell budget (the professor's proposed ratio; tune at side-arm planning time on cost-envelope evidence).
- **Documentation surface:** Python / Go cells receive the discipline guide from trigger conjunct 3 in place of the short target-specific instructions used in the launch matrix. LLMLL cells continue to receive full `LLMLL.md` as in the launch matrix (the asymmetry being tested is on the Python / Go side, not on LLMLL).
- **Reporting:** Standard 3-tuple per `docs/design/language-comparison-experiments.md` §"Reporting Output", plus the `prediction_match` field per B-1 (assuming B-1 has shipped by the time B-2 fires).

The side-arm's purpose is to test whether the launch matrix's asymmetric-documentation framing was **load-bearing** for the observed H1-Assurance differential — i.e., whether Python / Go would have narrowed the gap, held the gap, or surprisingly inverted it under symmetric documentation.

### Acceptance

A side-arm postmortem produces a per-target signal comparable in shape to the launch matrix's primary cells, with the documentation-surface variable explicitly varied. The analysis prose states whether the launch's H1-Assurance gap (a) narrows under symmetric documentation (the rival hypothesis "Python/Go would have won at matched documentation surface" gains support), (b) persists (the launch's joint-as-subject framing is empirically defensible against the rival), or (c) inverts (a third, currently-unhypothesized regime; documents the surprise).

### Out of scope (now)

- **Discipline-guide authoring.** The trigger's third conjunct — a non-trivial design task that must land before the side-arm runs. The authoring is itself the experiment-lead's scope when the time comes; B-2 registers the side-arm shape, not the guide's content.
- **Problem selection.** Depends on launch outcomes; cannot be pre-pinned.
- **Cost envelope and agent rotation.** Side-arm-planning-time decisions; depend on launch cost record and post-launch budget availability.

---

## What is not in this backlog

- **S7 audit substantive content** (`experiments/repair-loop/findings/phase3-problem-shape-audit.md` per-problem predicted verification-path engagement) — language-team-owned; the upstream artifact B-1's comparison logic binds to.
- **`manifest.phase3.json` authoring** — blocked on user adjudication of S1–S8 from the 2026-05-15 language-team Phase-3 scope-decision turn (S1 per-target predicate shape, S2 `:subjects` discipline, S3 cross-paradigm Assurance tuple, S4 `--strict-verified-core` policy, S5 spec-coverage role in `Cred`, S6 R5a doc-lead hand-off, S7 audit, S8 documentation depth at run-prep). Manifest authoring is experiment-lead-owned downstream of those adjudications.
- **R5a match-arm canonical-form patch** (`LLMLL.md §3.3` informal examples) — documentation-lead-owned via the S6 hand-off.
- **In-place Phase-3 extension of `experiments/repair-loop/`** — authoring the `001-hangman` and `003-rate-limiter` problem statements and Python + Go testkits, plus `manifest.phase3.json`, plus toolchain pins (Python / Go versions in the manifest preamble). This is the experiment-lead's substantive pre-launch work and is not a backlog item — it is a same-session bootstrap directly downstream of S1–S5 / S8 adjudication. Once it lands, B-1's "harness emits the field" precondition is unblocked.

## Closure protocol

When a backlog item's trigger fires, the experiment-lead produces a run plan or harness-change plan per the experiment-lead skill's output template, surfaces it for user approval, and on approval moves the work into an active experiment campaign. The corresponding backlog entry's status is updated to "Triggered" with the date and a pointer to the active campaign. On completion of the work, the entry's status is updated to "Closed" with a pointer to the postmortem or harness commit that closed it. Closed entries are retained in this file for historical record, not deleted.
