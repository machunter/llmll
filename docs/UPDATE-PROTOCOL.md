# Documentation Update Protocol

> **Source:** `docs/design/doc-consolidation-2026-05-24-proposal.md` §3 (DOC-CONSOLIDATE, settled 2026-05-24). This file is the working contract for every documentation change in the project. Lifted verbatim from §3.1–3.3.

## Canonical sources (P1)

| Claim | Canonical location | Linked-only from |
|---|---|---|
| Current shipped version (release narrative) | `CHANGELOG.md` `## Latest` | README §current-version cite line, roadmap (cite by tag) |
| Version banner (the `vX.Y.Z` number) | `compiler/package.yaml` `version:` (build source of truth) | **Must equal it — enforced by DRIFT-CI-1 C1, [`scripts/version_gate.sh`](../scripts/version_gate.sh):** `compiler/llmll.cabal` `version:`, `README.md` line 1, `LLMLL.md` line 1, `CHANGELOG.md` top `## vX.Y.Z` heading |
| Design-doc status (draft / settled / dormant / superseded) | The design doc's own frontmatter | `docs/design/INDEX.md` (label only) |
| Implementation routing (owner, ticket tag, status) | `compiler-team-roadmap.md` Active Items table | Design docs (cite by tag) |
| Verification matrix (QF-LIA / nonlinear / Lean) | `LLMLL.md §5.3.3 / §5.3.5` | README, roadmap, design docs (cite by section) |
| JSON-AST schema | `docs/llmll-ast.schema.json` | README, LLMLL.md (cite by version) |
| Per-experiment findings | `experiments/<harness>/findings.md` (H2-per-role) | Roadmap (cite by harness + finding ID) |
| Triage routing decisions | The triage doc itself | Roadmap Active Items (cite by routing tag) |

## Per-change update matrix (D1)

| When this happens | Update | Do NOT update |
|---|---|---|
| Engineer ships a release | **Version banner `vX.Y.Z` in all five DRIFT-CI-1 files: `compiler/package.yaml`, `compiler/llmll.cabal`, `README.md` line 1, `LLMLL.md` (line-1 banner **+** "Current version" paragraph **+** new release-history row), `CHANGELOG.md` top `## vX.Y.Z` heading**; CHANGELOG `## Latest` anchor; roadmap "Upcoming Releases" → "Shipped"; LLMLL.md §14 if user-visible. **Before push: run [`scripts/version_gate.sh`](../scripts/version_gate.sh) (DRIFT-CI-1 C1–C4) — it must pass.** | `README.md` §current-version cite line (points to CHANGELOG, not bumped); design-doc frontmatter |
| Language-team settles a proposal | Proposal frontmatter `Status:`; INDEX label; hand-off summary | Roadmap (only changes when ticket completes, not when proposal settles) |
| A role (or co-authoring pair, e.g. LT + EL) produces a settled prose amendment to a freeform roadmap section (milestone narrative, gate-criterion paragraph, empirical-gate pass-criteria text — not a table-row cell) and the user approves | `docs/compiler-team-roadmap.md` — doc-lead applies the settled text verbatim; no rewording without the originating role's re-authorization | `CHANGELOG.md` (not a release); `LLMLL.md`; `README.md`; table-row acceptance-criteria cells; design-doc frontmatter |
| Professor reviews a proposal | New standalone `<proposal>-review.md`; nothing else | The proposal file itself (LT folds on revision) |
| Doc-lead folds a settled review | Append `## Appendix — Professor review log` to proposal; archive `<proposal>-review.md` to `docs/archive/professor-reviews/` | Proposal frontmatter (no change) |
| Engineer ships a settled proposal's ticket | Roadmap row status; CHANGELOG if user-visible; LLMLL.md §14 if user-visible; INDEX status label | Proposal frontmatter (it's done — archive when superseded, not when shipped) |
| Experiment-lead closes a run with findings | `experiments/<harness>/findings.md` H2-per-role; new `findings/postmortem-NNN-<slug>.md` if applicable | Anything else — hand off to relevant role |
| Triage routing item closes | Triage doc routing-table row + roadmap Active Items row | Anywhere else |
| Doc gets superseded | Archive to `docs/archive/<category>/`; 2-line redirect stub at old path; delete stub after one release cycle | Other docs (redirect stub absorbs links during cycle) |

When a change does not appear in the matrix, the actor pauses and asks `language-team` to extend the matrix before acting. The matrix is the working contract; gaps are bugs to surface, not gaps to improvise around.

> **Banner-pin authority (reconciled 2026-06-12).** The "Version banner" row (P1) and the banner detail in the "Engineer ships a release" row (D1) were reconciled to the **DRIFT-CI-1** gate ([`scripts/version_gate.sh`](../scripts/version_gate.sh), C1–C4), which post-dates the DOC-CONSOLIDATE §3 verbatim lift and is executable ground truth. The gate enforces `vX.Y.Z` equality across `compiler/package.yaml`, `compiler/llmll.cabal`, `README.md` line 1, `LLMLL.md` line 1, and the `CHANGELOG.md` `## vX.Y.Z` top heading; a release that bumps any one without the others fails CI. (Origin: the v0.11.2 release `22c6aa8` bumped the README banner but not LLMLL.md's, tripping C1; `6bf3f89` reconciled LLMLL.md and this protocol now records the full pin set so the gap cannot recur.)

## Archive policy

- `docs/archive/shipped-design-specs/` — proposals whose feature has shipped and is not actively referenced
- `docs/archive/professor-reviews/` *(new — M2)* — standalone review files after fold
- `docs/archive/wasm-investigations/` *(new — M4)* — `wasm-poc-report.md`, `effectful-wasm-spike.md`
- `docs/archive/roadmap-shipped-history.md` *(M5 large-cut — DONE 2026-06-21)* — detailed per-version shipped history split out of `compiler-team-roadmap.md`; the live roadmap keeps a compact one-line-per-version `## Shipped Releases` summary that links into this file

When `docs/archive/shipped-design-specs/` crosses ~20 entries (currently 35 — past threshold since the v0.11/v0.12/v0.13 ship cadence; sub-categorization below is now due, not just forward-looking), sub-categorize by version-shipped (`v0.6/`, `v0.8/`, `v0.9/`, `v0.10/`, `v0.11/`) and add `docs/archive/dormant-explorations/` for docs judged stale-but-not-shipped (distinguishes "shipped-and-archived" from "explored-and-dropped" semantics).

### 3.4 Pre-planned archive moves (gated by ticket-ship or condition)

The following docs are on a natural-archive trajectory. The trigger column states the gate that fires archival (not a ship-date commitment — the underlying ticket schedule is in [`compiler-team-roadmap.md`](compiler-team-roadmap.md)). On each release pass, doc-lead checks which gates fired and applies the listed move mechanically.

| Document | Archive trigger | Destination |
|---|---|---|
| `docs/design/oblig-pbt-3-proposal.md` | OBLIG-PBT-3 ships | **DONE** — OBLIG-PBT-3 shipped v0.10.5; moved to [`shipped-design-specs/`](archive/shipped-design-specs/oblig-pbt-3-proposal.md) |
| `docs/design/int-2-boundary-shims.md` | INT-2 ships | **DONE** — moved to [`shipped-design-specs/`](archive/shipped-design-specs/int-2-boundary-shims.md) |
| `docs/design/core-shell-inversion-proposal.md` | LT-INV ships | **DONE** — moved to [`shipped-design-specs/`](archive/shipped-design-specs/core-shell-inversion-proposal.md) |
| `docs/design/contract-discriminative-power-proposal.md` | CDP-0 ships | **DONE** — moved to [`shipped-design-specs/`](archive/shipped-design-specs/contract-discriminative-power-proposal.md) |
| `docs/design/proof-required-predicate-carrier-proposal.md` | LT-PPR ships | **DONE** — moved to [`shipped-design-specs/`](archive/shipped-design-specs/proof-required-predicate-carrier-proposal.md) |
| `docs/design/refinement-metatheory-of-record-proposal.md` | REF-META-1 ships | **DONE** — moved to [`shipped-design-specs/`](archive/shipped-design-specs/refinement-metatheory-of-record-proposal.md) |
| `docs/design/core-shell-inversion-direction.md` | All of LT-INV + LT-CDP + LT-PPR ship | ~~Fold into lead proposal's `## Background` (per M2 case 3), then archive~~ **DONE (2026-06-12)** — folded into [`core-shell-inversion-proposal.md`](archive/shipped-design-specs/core-shell-inversion-proposal.md) `## Background`; archived to `shipped-design-specs/` |
| `docs/design/int-3-machine-int-sketch.md` | INT-PRE escalates → promote; or INT-PRE no-regression → resolve | `shipped-design-specs/` (promotion path) or `dormant-explorations/` (resolution path; see §3.3 sub-categorization note) — **not yet triggered**: INT-3 remains roadmap status "P3 — open" (dormant-but-still-open, not resolved) |
| `docs/design/critique-2026-05-23-triage.md` | All 17 routing items closed | `docs/archive/triages/` (new subdir on first triage archive) — **not yet triggered**: OBLIG-PBT-5b (one of the 17 routed items) is still open per the roadmap's Active Items table |
| `docs/design/doc-consolidation-2026-05-24-proposal.md` | Next release sweep (shipped at `1a8733f`; audit close-out at `e6eb4b6`; fully closed) | **DONE** — moved to [`shipped-design-specs/`](archive/shipped-design-specs/doc-consolidation-2026-05-24-proposal.md) |

Updates to this list happen alongside any milestone-rename or scope-change commit. If a row's trigger becomes ambiguous, route to language-team to re-adjudicate before archiving.
