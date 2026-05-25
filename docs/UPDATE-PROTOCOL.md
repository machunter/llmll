# Documentation Update Protocol

> **Source:** `docs/design/doc-consolidation-2026-05-24-proposal.md` §3 (DOC-CONSOLIDATE, settled 2026-05-24). This file is the working contract for every documentation change in the project. Lifted verbatim from §3.1–3.3.

## Canonical sources (P1)

| Claim | Canonical location | Linked-only from |
|---|---|---|
| Current shipped version | `CHANGELOG.md` `## Latest` | README (1-line cite), LLMLL.md (no version stamp), roadmap (no version stamp) |
| Design-doc status (draft / settled / dormant / superseded) | The design doc's own frontmatter | `docs/design/INDEX.md` (label only) |
| Implementation routing (owner, ticket tag, status) | `compiler-team-roadmap.md` Active Items table | Design docs (cite by tag) |
| Verification matrix (QF-LIA / nonlinear / Lean) | `LLMLL.md §5.3.3 / §5.3.5` | README, roadmap, design docs (cite by section) |
| JSON-AST schema | `docs/llmll-ast.schema.json` | README, LLMLL.md (cite by version) |
| Per-experiment findings | `experiments/<harness>/findings.md` (H2-per-role) | Roadmap (cite by harness + finding ID) |
| Triage routing decisions | The triage doc itself | Roadmap Active Items (cite by routing tag) |

## Per-change update matrix (D1)

| When this happens | Update | Do NOT update |
|---|---|---|
| Engineer ships a release | CHANGELOG `## Latest`; roadmap "Upcoming Releases" → "Shipped"; LLMLL.md §14 if user-visible | README version (cites CHANGELOG); design-doc frontmatter |
| Language-team settles a proposal | Proposal frontmatter `Status:`; INDEX label; hand-off summary | Roadmap (only changes when ticket completes, not when proposal settles) |
| Professor reviews a proposal | New standalone `<proposal>-review.md`; nothing else | The proposal file itself (LT folds on revision) |
| Doc-lead folds a settled review | Append `## Appendix — Professor review log` to proposal; archive `<proposal>-review.md` to `docs/archive/professor-reviews/` | Proposal frontmatter (no change) |
| Engineer ships a settled proposal's ticket | Roadmap row status; CHANGELOG if user-visible; LLMLL.md §14 if user-visible; INDEX status label | Proposal frontmatter (it's done — archive when superseded, not when shipped) |
| Experiment-lead closes a run with findings | `experiments/<harness>/findings.md` H2-per-role; new `findings/postmortem-NNN-<slug>.md` if applicable | Anything else — hand off to relevant role |
| Triage routing item closes | Triage doc routing-table row + roadmap Active Items row | Anywhere else |
| Doc gets superseded | Archive to `docs/archive/<category>/`; 2-line redirect stub at old path; delete stub after one release cycle | Other docs (redirect stub absorbs links during cycle) |

When a change does not appear in the matrix, the actor pauses and asks `language-team` to extend the matrix before acting. The matrix is the working contract; gaps are bugs to surface, not gaps to improvise around.

## Archive policy

- `docs/archive/shipped-design-specs/` — proposals whose feature has shipped and is not actively referenced
- `docs/archive/professor-reviews/` *(new — M2)* — standalone review files after fold
- `docs/archive/wasm-investigations/` *(new — M4)* — `wasm-poc-report.md`, `effectful-wasm-spike.md`
- `docs/archive/roadmap-history/` *(new — only if M5 large-cut)* — shipped-version narrative
