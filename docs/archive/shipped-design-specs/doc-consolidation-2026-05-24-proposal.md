# DOC-CONSOLIDATE — Project Documentation Consolidation and SOP

> **Version:** Rev 1 — initial settled draft
> **Date:** 2026-05-24
> **Implements:** New cross-cutting concern under `docs/compiler-team-roadmap.md` (Active Items addition pending); no language-surface change, no schema bump, no compiler change
> **Prerequisites:** None — pure documentation-architecture move, executable under feature freeze and outside it equally
> **Origin:** User reported friction from accumulated documents outside source code (language doc, design docs, experiment docs, findings docs); language-team scan of the active doc surface (2026-05-24) confirmed 4× per-experiment role-file fan-out, three-source status drift for settled proposals, and pillar-doc version drift (README v0.10.8 vs roadmap v0.10.7)
> **Companion:** None — this is a self-contained doc-architecture move with no upstream design memo
> **Reviewed:** Adjudicated and approved by user in conversation (2026-05-24); no professor review required (inward-only doc-architecture proposal, no PL-literature reach load-bearing)
> **Status:** Settled (Rev 1) — **shipped at commit `1a8733f`** (2026-05-25, single-sweep PR per §11). Two follow-ups closed: **M6 INDEX demote** landed by language-team subsequently (INDEX entries demoted to one-liners; archived files removed); **R1–R7 overlap audit** settled at `e6eb4b6` (no subsumption; **four** cross-references applied to roadmap research-track section — R1↔[`type-driven-development.md`](../../design/type-driven-development.md), R2↔[`agent-orchestration.md`](../../design/agent-orchestration.md), R5↔[`experiments/repair-loop/`](../../experiments/repair-loop/) as sibling-not-overlap, R7↔TERM-1 as complementary-not-overlapping; R3 partial-criterion flagged with TOTP-as-worked-example cite). **DOC-CONSOLIDATE fully closed.**

---

## 1. Motivation

The active documentation surface outside `compiler/src/` has grown to 60+ files across `docs/`, `docs/design/`, `experiments/<harness>/`, and the project pillars (`README.md`, `LLMLL.md`, `CHANGELOG.md`). The growth pattern is not random; it follows three structural fan-outs that compound:

1. **Proposal-then-review pairs that never collapse.** Every settled design proposal carries a standalone `<proposal>-review.md` alongside it forever, even after the review's findings have been folded into the proposal's revised text. Active examples: [`oblig-pbt-3-proposal.md`](oblig-pbt-3-proposal.md) + [`oblig-pbt-3-review.md`](../professor-reviews/oblig-pbt-3-review.md); [`invariant-discovery-proposal.md`](../../design/invariant-discovery-proposal.md) + [`invariant-discovery-review.md`](../professor-reviews/invariant-discovery-review.md). The standalone review's value at settlement is provenance, not active reading.

2. **Per-role per-experiment findings fan-out.** Each experiment harness (`minimal-agent/`, `int-pre/`, `repair-loop/`) carries 4 role-files in `findings/` — `compiler-engineer.md`, `language-team.md`, `experiment-lead.md`, `documentation-lead.md` — for a 4 × 3 = 12-file surface across three harnesses. Cross-cutting reads (e.g., "what did all three harnesses find about the obligation channel?") force fanned-out reading; experiment closure forces a 4× update.

3. **Multi-authoritative-source status claims.** A single piece of state — e.g., "OBLIG-PBT-3 is settled at Rev 2, awaiting engineer hand-off" — currently lives in three places: the proposal's own frontmatter, the [`docs/design/INDEX.md:21`](../../design/INDEX.md) paraphrased entry, and the Active Items routing in [`compiler-team-roadmap.md`](../../compiler-team-roadmap.md). When the engineer ships it, three locations must move; in practice they drift.

The cost is bidirectional: cost-of-reading on re-orientation (too many files to scan), and cost-of-writing on update (too many files to keep in sync). The user-reported friction is the surface of both.

Observed drift, surfaced during the inventory scan (2026-05-24):

- [`README.md:7`](../../../README.md) announces v0.10.8 shipped; [`compiler-team-roadmap.md:3`](../../compiler-team-roadmap.md) header still says "v0.10.7 shipped." Two pillar docs disagree on the current version. README also embeds a ~2KB CHANGELOG-shaped release-notes paragraph for v0.10.8 — verbatim duplication of CHANGELOG content.
- [`README.md:188-194`](../../../README.md) describes the docs/ layout with stale callouts (e.g., `agent-prompt-semantics-gap.md` listed under `docs/design/` but actually archived under `docs/archive/shipped-design-specs/`); `LLMLL.md` line-1 annotated "v0.10.1" against an actual v0.10.8 spec.
- [`docs/research-track.md`](../research-track.md) (216 lines) overlaps with the roadmap's research-track entries; [`contract-discriminative-power-proposal.md:26`](contract-discriminative-power-proposal.md) already manually papers over a case-by-case drift ("supersedes [research-track.md] §6 (already retired in catch-up Pass 3 with cross-reference)").
- [`docs/design/proof-required-predicate-carrier.md`](proof-required-predicate-carrier.md) (deferred-exploration seed) has been content-superseded by [`proof-required-predicate-carrier-proposal.md`](proof-required-predicate-carrier-proposal.md) per [`INDEX.md:27`](../../design/INDEX.md) but the seed file still sits in `docs/design/`, not in `docs/archive/`.
- [`docs/design/INDEX.md`](../../design/INDEX.md) entries (lines 21, 23–29) have grown from one-line summaries into multi-paragraph status reports — the index is duplicating proposal frontmatter content, which guarantees lockstep-update failure.
- [`docs/effectful-wasm-spike.md`](../wasm-investigations/effectful-wasm-spike.md) (Apr 20, 81 lines) and [`docs/wasm-poc-report.md`](../wasm-investigations/wasm-poc-report.md) (Apr 16, 157 lines) are pre-roadmap-reorganization spike notes; their conclusions have landed in the roadmap.

The project already practices local consolidation moves: [`docs/archive/shipped-design-specs/`](../archive/shipped-design-specs/) exists; [`INDEX.md`](../../design/INDEX.md) tracks supersession; [`critique-2026-05-23-triage.md`](../../design/critique-2026-05-23-triage.md) is itself a consolidation pattern collapsing four conversation turns into one durable artifact. This proposal systematizes those local moves into a documented protocol with per-role obligations, rather than inventing new mechanisms.

---

## 2. Design proposal

Six consolidation moves (**M1**–**M6**), one structural principle (**P1**), one operational discipline (**D1**). Each move is local, reversible, and does not touch language semantics, the verification matrix, the JSON-AST schema, or any compiler module.

### P1 — One authoritative source per claim; everywhere else links

The structural cause of "lots to update" is multi-authoritative-source claims. Under P1, every claim-class has a single canonical location; all other mentions are 1-line *pointers*, not paraphrased copies. Three canonical-location bindings:

- **Current shipped version:** [`CHANGELOG.md`](../../../CHANGELOG.md) `## Latest` is canonical. [`README.md:1`](../../../README.md) cites it; [`LLMLL.md`](../../../LLMLL.md) does not version-stamp; [`compiler-team-roadmap.md`](../../compiler-team-roadmap.md) header does not version-stamp. Eliminates the v0.10.7-vs-v0.10.8 drift class.
- **Design-doc status (settled / draft / dormant / superseded):** the design doc's own frontmatter is canonical. [`INDEX.md`](../../design/INDEX.md) carries title + status label + 8–12-word hook only, no paraphrased summary.
- **Implementation routing (owner, ticket tag, status):** [`compiler-team-roadmap.md`](../../compiler-team-roadmap.md) Active Items table is canonical. Design docs cite back to roadmap tickets by tag (`OBLIG-PBT-3`, `INT-2`, `DRIFT-CI-1`, …); roadmap is the only place a routing status moves on ticket completion.

### M1 — Collapse per-role experiment findings into single `findings.md` per experiment

Per experiment, collapse the 4 role-files into one `experiments/<harness>/findings.md` with H2 sections `## Compiler-engineer`, `## Language-team`, `## Experiment-lead`, `## Documentation-lead`. Postmortems stay as separate dated files under `experiments/<harness>/findings/postmortem-NNN-<slug>.md` — they are episodic, not role-structured. The H2-per-role split preserves skill-routing (each skill greps for its own H2 anchor); the single-file shape eliminates the cross-role read cost and the 4× update fan-out on experiment closure.

12 role-files → 3 files. Postmortem groups (3 in `minimal-agent/`, 1 in `int-pre/`, 5 in `repair-loop/`) unchanged.

### M2 — After-settlement supersession discipline

Three sub-patterns generate near-duplicate doc pairs and accumulate without consolidation:

1. **Proposal-then-review pair after settlement.** Once a proposal reaches Rev N "settled" with the professor's review folded in, the standalone review is provenance, not active reading. Move: when a proposal settles, fold the review's findings list into an `## Appendix — Professor review log` section of the proposal (one line per finding, with cite to the original review hash), then move the standalone review to `docs/archive/professor-reviews/`. Loss of content: zero. Loss of discovery: zero (INDEX still links the proposal). Active-reading surface: −1 file per settled pair. Worked example: [`oblig-pbt-3-proposal.md`](oblig-pbt-3-proposal.md) + [`oblig-pbt-3-review.md`](../professor-reviews/oblig-pbt-3-review.md).

2. **Seed exploration superseded by full proposal.** Example: [`proof-required-predicate-carrier.md`](proof-required-predicate-carrier.md) (deferred-exploration seed) superseded by [`proof-required-predicate-carrier-proposal.md`](proof-required-predicate-carrier-proposal.md) (Rev 1 settled). The seed has been promoted; the seed file is stale. Move: archive the seed to `docs/archive/shipped-design-specs/` with a one-line redirect note.

3. **Direction memo + LT proposal(s) that implement it.** Example: [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) (Rev 2 direction memo) + [`core-shell-inversion-proposal.md`](core-shell-inversion-proposal.md) (Rev 1 settled LT-INV) + future `core-shell-inversion-review.md`. When all spawned proposals settle, fold the direction memo into the lead proposal's `## Background` section and archive the memo. Direction memos are scaffolding for the LT-proposal turn; they age out once the proposals settle.

### M3 — Strip CHANGELOG-shaped content from README; README cites CHANGELOG

[`README.md:5-7`](../../../README.md) currently carries a ~70-line v0.10.8 release-notes paragraph that duplicates CHANGELOG.md verbatim or near-verbatim. Move: replace lines 5–7 with the existing one-line "See CHANGELOG.md for full release notes" plus a 1-sentence "current version: see CHANGELOG `## Latest`" pointer. The README's "Repository layout," "Documentation," "Examples," and "Verification Boundary" tables stay — those are README-canonical content. Cuts ~70 lines and eliminates the README-vs-CHANGELOG drift class entirely.

Also: refresh [`README.md:128, 184, 188-194, 211`](../../../README.md) stale callouts (archived design docs listed under `docs/design/`, stale spec-version annotation, stale schema-version annotation).

### M4 — Archive standalone docs/ files that are pre-reorganization or single-purpose-and-shipped

Three candidates inside `docs/`:

- [`effectful-wasm-spike.md`](../wasm-investigations/effectful-wasm-spike.md) (Apr 20, 81 lines) — pre-roadmap-reorganization spike note → `docs/archive/wasm-investigations/`.
- [`wasm-poc-report.md`](../wasm-investigations/wasm-poc-report.md) (Apr 16, 157 lines) — README cites it as "feasibility confirmed"; conclusion has landed in the roadmap → `docs/archive/wasm-investigations/`.
- [`docs/research-track.md`](../research-track.md) (216 lines) — overlaps with the roadmap's research-track entries. P1 says pick one canonical location. Recommend keeping the roadmap canonical (Active Items table already lives there) and deleting `docs/research-track.md` after migrating remaining unique entries into the roadmap's research-track section.

### M5 — Decompose `compiler-team-roadmap.md` (1656 lines) along its conflated concerns

The roadmap is currently six documents in one file: (a) version-milestone definitions, (b) shipped-version narrative history, (c) Active Items routing table, (d) Feature Freeze Policy text, (e) cross-cutting concerns, (f) research-track entries. Concerns (a) + (c) are tight-loop update surfaces. (b) is append-only history. (d) is stable policy. (e)–(f) drift slowly.

Smallest viable cut: keep one `compiler-team-roadmap.md` but introduce five top-of-file H2 anchors with stable IDs and an explicit table of contents that skills can deep-link into:

- `## Upcoming Releases` (high-churn)
- `## Active Items` (high-churn)
- `## Shipped (historical)` (append-only)
- `## Feature Freeze Policy` (low-churn)
- `## Cross-cutting concerns` (low-churn)

Larger cut (deferred to a future iteration): move "Shipped (historical)" into `docs/archive/roadmap-history.md` (~300+ lines extracted), shrinking the active roadmap to high-churn parts only. Recommended threshold for the larger cut: when "Shipped (historical)" crosses 500 in-file lines. Currently ~300; small cut is sufficient.

### M6 — Demote `docs/design/INDEX.md` entries from prose summaries to one-liners

Current state: [`INDEX.md`](../../design/INDEX.md) entries (lines 21, 23–29) are multi-paragraph status reports duplicating the proposals' own frontmatter. As proposals settle and revise, INDEX entries must be updated in lockstep — and they are not.

Move: enforce one-line-per-entry. Format:

```
| [filename.md](filename.md) | 8–12-word hook | **Status label** |
```

Status label comes from the design doc's own frontmatter; the proposal's full description, supersession links, and revision history stay in the proposal. Brings INDEX from 69 lines to ~50 with no information loss for the reader (one click to the proposal yields the rest).

Mechanization (`make index` regenerating INDEX from frontmatter) is a research-track follow-up, not part of this proposal.

### D1 — Operational discipline: `docs/UPDATE-PROTOCOL.md` (new file, ≤ 80 lines)

One new file at `docs/UPDATE-PROTOCOL.md`. Lives at docs/ root. Every skill cites it. Three tables: canonical sources (P1 instantiation), per-change update matrix, archive policy. Verbatim content in §3 below.

---

## 3. `docs/UPDATE-PROTOCOL.md` content (lift-and-drop)

### 3.1 Canonical sources (P1)

| Claim | Canonical location | Linked-only from |
|---|---|---|
| Current shipped version | `CHANGELOG.md` `## Latest` | README (1-line cite), LLMLL.md (no version stamp), roadmap (no version stamp) |
| Design-doc status (draft / settled / dormant / superseded) | The design doc's own frontmatter | `docs/design/INDEX.md` (label only) |
| Implementation routing (owner, ticket tag, status) | `compiler-team-roadmap.md` Active Items table | Design docs (cite by tag) |
| Verification matrix (QF-LIA / nonlinear / Lean) | `LLMLL.md §5.3.3 / §5.3.5` | README, roadmap, design docs (cite by section) |
| JSON-AST schema | `docs/llmll-ast.schema.json` | README, LLMLL.md (cite by version) |
| Per-experiment findings | `experiments/<harness>/findings.md` (H2-per-role) | Roadmap (cite by harness + finding ID) |
| Triage routing decisions | The triage doc itself | Roadmap Active Items (cite by routing tag) |

### 3.2 Per-change update matrix (D1)

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

When a change does not appear in the matrix, the actor pauses and asks language-team to extend the matrix before acting. The matrix is the working contract; gaps are bugs to surface, not gaps to improvise around.

### 3.3 Archive policy

- `docs/archive/shipped-design-specs/` — proposals whose feature has shipped and is not actively referenced
- `docs/archive/professor-reviews/` *(new — M2)* — standalone review files after fold
- `docs/archive/wasm-investigations/` *(new — M4)* — `wasm-poc-report.md`, `effectful-wasm-spike.md`
- `docs/archive/roadmap-history/` *(new — only if M5 large-cut)* — shipped-version narrative

---

## 4. Per-skill `## Documentation discipline` blocks

Each block is the verbatim insertion text for the corresponding `.claude/skills/<role>/SKILL.md`. Doc-lead authors the actual file edits.

### 4.1 `compiler-engineer`

> **Touches:** compiler source under `compiler/src/LLMLL/`, tests, fixtures, `docs/llmll-ast.schema.json` *only when shipping a schema bump tied to your patch*.
>
> **Never touches:** `README.md`, `LLMLL.md`, `CHANGELOG.md`, `docs/design/INDEX.md`, design-doc frontmatter, `docs/getting-started.md`, `docs/compiler-team-roadmap.md` Active Items row (doc-lead moves the row on your ship confirmation).
>
> **After shipping a feature**, produce a one-paragraph hand-off to `documentation-lead`: ticket tag (e.g. `OBLIG-PBT-3`), user-visible CLI / behavior change (verbatim `LLMLL.md §14` candidate text), schema delta if any (version bump, new fields, deprecated fields), test count delta, one-sentence CHANGELOG `## Latest` candidate. Stop after the hand-off.
>
> **On spec drift discovered** (`LLMLL.md` and the compiler disagree on something your patch touches): flag it explicitly in the hand-off — do not silently fix one side.
>
> See [`docs/UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) for the canonical-sources table and per-change matrix.

### 4.2 `language-team`

> **Touches:** design proposals in conversation, then on user request as drafts in `docs/design/<topic>.md`. Proposal frontmatter is the canonical source for proposal status (P1) — keep `Status:` accurate on every revision.
>
> **Never touches:** `LLMLL.md`, `CHANGELOG.md`, `README.md`, `docs/compiler-team-roadmap.md` (doc-lead's slot). No commits.
>
> **On settlement**, emit a hand-off paragraph naming: (a) the proposal file, (b) the settled revision (`Rev N`), (c) whether a standalone `<proposal>-review.md` exists ready for fold-and-archive (triggers M2), (d) the engineer hand-off summary if code-track, the doc-lead summary if spec-track. Doc-lead handles INDEX label update and archive; you do not.
>
> **INDEX.md entries for your proposals are one-liners** — title, 8–12-word hook, status label. The full description lives in the proposal. If you want to write more in INDEX, that content belongs in the proposal's own `## Background` or `## Summary` section.
>
> See [`docs/UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) for the canonical-sources table and per-change matrix.

### 4.3 `experiment-lead`

> **Touches:** `experiments/<harness>/` — manifests, scripts, the single `experiments/<harness>/findings.md` (H2-per-role), and dated `experiments/<harness>/findings/postmortem-NNN-<slug>.md`.
>
> **Never touches:** any doc outside `experiments/` (route to doc-lead). Findings reach the rest of the project via hand-off paragraphs, not direct edits to other docs.
>
> **`findings.md` structure:** `## Compiler-engineer`, `## Language-team`, `## Experiment-lead`, `## Documentation-lead` — H2 sections, one per consuming role. Downstream skills grep for their own H2 anchor. A new role → add an H2 section in the same file; never fan back out to per-role files.
>
> **Postmortems are episodic, not role-structured** — separate dated files under `findings/`. Experiment specs stay separate per the existing harness convention.
>
> **On findings publication**, hand off to the relevant role: compiler bugs → engineer; spec implications → language-team; doc-surface gaps → doc-lead. Authority ends at pattern surfacing.
>
> **When a finding's claim about a target doc's state is the basis for a hand-off**, open the target doc at HEAD and verify before handing off — findings drift faster than the docs they describe.
>
> See [`docs/UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) for the canonical-sources table and per-change matrix.

### 4.4 `documentation-lead`

> **Owns the six target docs plus new structural surface added by the doc-consolidation:**
>
> Target docs (unchanged):
> - `README.md`, `docs/getting-started.md`, `LLMLL.md`, `docs/llmll-ast.schema.json`, `docs/compiler-team-roadmap.md`, `CHANGELOG.md`
>
> New surface:
> - `docs/design/INDEX.md` (one-line discipline per M6)
> - `docs/UPDATE-PROTOCOL.md` (the canonical-sources table + per-change matrix; authored by you from the doc-consolidation proposal §3)
> - Supersession / archive moves (M2, M4) — every settled-and-folded proposal triggers an archive sweep
> - Roadmap H2 anchor maintenance (M5)
>
> Refuse scope expansion beyond this surface, same as before.
>
> **On each inbound hand-off:**
> - *From engineer:* apply CHANGELOG `## Latest` candidate, roadmap row status flip, LLMLL.md §14 user-visible feature line, INDEX status label if proposal settled-and-shipped, schema-version README cite.
> - *From language-team (settlement):* apply INDEX status label; if standalone review exists, fold as `## Appendix — Professor review log` into the proposal and move the review to `docs/archive/professor-reviews/`; leave a 2-line redirect stub at the old path for one release cycle.
> - *From experiment-lead (findings):* doc-surface gaps named in the `## Documentation-lead` section of `findings.md` get triaged into roadmap Active Items if non-trivial, or fixed in-place if a single-doc edit.
>
> **Never edits:** `compiler/src/LLMLL/`; design-doc bodies (only INDEX labels and review-fold appendices); experiment findings (only the `## Documentation-lead` content via experiment-lead hand-off).
>
> Per-change-type matrix at [`docs/UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) is your working tool.

### 4.5 `professor`

> **Touches:** review files in `docs/design/<topic>-review.md` during critique turns.
>
> **Never touches:** the proposal you are reviewing (language-team folds your findings on revision); `LLMLL.md`, `CHANGELOG.md`, `README.md`, roadmap (doc-lead's slot).
>
> **When critiquing**, your output stays standalone — do not pre-fold into the proposal. The fold-after-settlement pattern keeps your critique reviewable as an independent artifact during back-and-forth.
>
> **Once a proposal settles and your standalone review gets folded** into `## Appendix — Professor review log` by doc-lead, your review file is archived to `docs/archive/professor-reviews/`. You do not initiate the fold or the archive — that is the after-settlement protocol owned by doc-lead.
>
> See [`docs/UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) for the canonical-sources table and per-change matrix.

---

## 5. Cross-role hand-off contracts

Three hand-offs benefit from a fixed shape; all three are one-paragraph.

- **engineer → doc-lead** *(release or ticket ship)*: ticket tag · user-visible CLI/behavior change (verbatim §14 candidate) · schema delta if any · test count delta · CHANGELOG `## Latest` candidate.

- **language-team → doc-lead** *(spec-track settlement, no compiler work)*: proposal file · settled `Rev N` · six-target-doc impact (which docs, which sections, verbatim text candidates where applicable) · INDEX label update · standalone review-fold flag.

- **language-team → engineer** *(code-track settlement)*: settled surface · settled semantics · settled verification mapping (channel + fragment per `LLMLL.md §5.3.3 / §5.3.5`) · affected `compiler/src/LLMLL/` modules · settled JSON-AST delta.

---

## 6. Edge cases and degenerate inputs

1. **A doc the user is mid-read gets moved.** Risk: broken bookmarks. Mitigation: every archive move leaves a 2-line stub at the old path pointing to the new path, deleted after one full release cycle. Cost: ≤ 12 stub files for ≤ 60 days. **Channel: documentation-process** (not verification). **Cite:** `docs/archive/` already exists; the redirect-stub pattern is the obvious extension.

2. **A new external critique arrives mid-2026.** Does the triage pattern still scale? Under the proposal, the second triage forces a `docs/design/triages/` sibling dir; currently one is fine in `docs/design/` root. **Channel: documentation-process.** **Status: spec is silent (intentional)** — defer until the second triage forces the question.

3. **A future role joins** (e.g., a "security-lead" persona). Per-experiment `findings.md` works unchanged — add an H2 section. The collapse to one file is more extensible than the fan-out, not less. **Channel: documentation-process.**

4. **A proposal is partially settled** — some sections settled, others open. Does M2's after-settlement folding rule fire? No: M2 fires only on whole-proposal settlement signaled by `Status: Settled (Rev N)` in frontmatter. Partial-settle proposals retain their separate review file until full settlement. **Channel: documentation-process.** **Cite:** [`oblig-pbt-3-proposal.md`](oblig-pbt-3-proposal.md) is the worked example of a fully-settled proposal currently ready for the fold.

5. **CHANGELOG-as-version-canon creates a single point of failure if CHANGELOG itself is wrong.** P1 reduces drift but does not eliminate it; it relocates the verification burden to one file. CHANGELOG's `## Latest` is touched on every release; it's the lowest-error-rate location available. **Channel: documentation-process.** **Cite:** P1 trades 3-source drift for 1-source error, which is a strict improvement.

6. **The roadmap's history H2 (M5 small-cut) still grows unboundedly.** True. The larger M5 cut is the answer once the in-file history crosses ~500 lines. Currently ~300; small cut is sufficient for now. **Channel: documentation-process / scope.**

---

## 7. Verification mapping

**This proposal introduces no proof obligations.** It is a documentation-architecture move; the spec (`LLMLL.md`), the verification fragment (QF-LIA / nonlinear / Lean partition per `LLMLL.md §5.3.3 / §5.3.5`), the JSON-AST schema, the trust model, and the obligation channels are untouched. No QF-LIA constraint, no nonlinear obligation, no `?proof-required` candidate.

Verification-mapping is **N/A by construction** for this proposal. Stated explicitly rather than omitted: the absence is not punted to the engineer.

---

## 8. Affected surface

The single-sweep PR (per user adjudication 2026-05-24) touches the following files. Grouped by concern.

### 8.1 New files

- `docs/UPDATE-PROTOCOL.md` — content per §3 above
- `experiments/minimal-agent/findings.md` — H2-per-role consolidation of the 4 existing role files
- `experiments/int-pre/findings.md` — H2-per-role consolidation of the 4 existing role files
- `experiments/repair-loop/findings.md` — H2-per-role consolidation of the 4 existing role files
- `docs/archive/professor-reviews/` — new archive subdir (M2)
- `docs/archive/wasm-investigations/` — new archive subdir (M4)

### 8.2 Files moved to archive (with 2-line redirect stub at old path)

- `experiments/minimal-agent/findings/{compiler-engineer,language-team,experiment-lead,documentation-lead}.md` — 4 files → folded into `findings.md`, originals deleted (no redirect needed; same-dir fold)
- `experiments/int-pre/findings/{compiler-engineer,language-team,documentation-team}.md` — 3 files → folded into `findings.md`
- `experiments/repair-loop/findings/{compiler-engineer,language-team}.md` — 2 files → folded into `findings.md`
- `docs/design/proof-required-predicate-carrier.md` → `docs/archive/shipped-design-specs/` (M2 case 2; superseded seed)
- `docs/effectful-wasm-spike.md` → `docs/archive/wasm-investigations/` (M4)
- `docs/wasm-poc-report.md` → `docs/archive/wasm-investigations/` (M4)
- `docs/design/invariant-discovery-review.md` → `docs/archive/professor-reviews/` (M2 case 1; proposal already settled, fold-and-archive)
- `docs/design/oblig-pbt-3-review.md` → `docs/archive/professor-reviews/` (M2 case 1; proposal already settled, fold-and-archive)
- `docs/research-track.md` → migrate unique entries into `compiler-team-roadmap.md` research-track section, then archive to `docs/archive/` (M4)

### 8.3 Files edited

- `README.md` — strip CHANGELOG-shaped paragraph (M3); refresh stale callouts (M3); update Documentation table for archive moves (M4)
- `docs/design/INDEX.md` — demote entries to one-liners (M6); remove archived files; update post-M2 fold-and-archive entries
- `docs/compiler-team-roadmap.md` — H2 anchor reorg (M5 small-cut); absorb unique research-track entries from migrated `docs/research-track.md` (M4)
- `docs/design/invariant-discovery-proposal.md` — append `## Appendix — Professor review log` (M2 fold)
- `docs/design/oblig-pbt-3-proposal.md` — append `## Appendix — Professor review log` (M2 fold)
- `.claude/skills/compiler-engineer/SKILL.md` — insert `## Documentation discipline` block per §4.1
- `.claude/skills/language-team/SKILL.md` — insert `## Documentation discipline` block per §4.2
- `.claude/skills/experiment-lead/SKILL.md` — insert `## Documentation discipline` block per §4.3
- `.claude/skills/documentation-lead/SKILL.md` — insert `## Documentation discipline` block per §4.4
- `.claude/skills/professor/SKILL.md` — insert `## Documentation discipline` block per §4.5

### 8.4 Files not touched

- `compiler/src/LLMLL/` — no change. No CodegenHs, FixpointEmit, TypeCheck, ObligationAssembly, schema-emitter, or any source touch.
- `LLMLL.md` — no change. The spec is not edited.
- `docs/llmll-ast.schema.json` — no change. No schema bump.
- `CHANGELOG.md` — add one Unreleased entry under "Infra" noting the doc-consolidation; no version-bump entry.
- Out-of-scope-under-freeze flags: none triggered. Freeze policy applies to language surface, not documentation architecture.

### 8.5 PR scope summary

Approximate line-count deltas: README −70; INDEX −30; roadmap +20 (H2 anchors) − ~10 (research-track migration may net out); new `UPDATE-PROTOCOL.md` +80; 3 new `findings.md` ≈ +400 (sum of existing 12 role files); 5 SKILL.md edits ≈ +50 each; archive moves zero net.

Net file count: +6 new files (UPDATE-PROTOCOL, 3 findings.md, 2 new archive subdirs), −15 active doc files (12 role files folded, `proof-required-predicate-carrier.md` seed, `effectful-wasm-spike.md`, `wasm-poc-report.md`, plus `research-track.md` archived after migration, plus invariant-discovery-review and oblig-pbt-3-review moved to archive). Net: **−9 active files; −1 authoritative-source class drift surface (P1 cuts the three-source status pattern to one).**

---

## 9. Risks and open questions

Severity-ordered.

1. **Scope creep into content rewrites** — *classification: scope.* A consolidation pass invites "while we're here, let's also rewrite getting-started.md / regroup orchestrator-walkthrough.md / split LLMLL.md by chapter." All such asks are refused within this proposal's scope. M1–M6 + P1 + D1 are structural moves on file count and authoritative location, not editorial content. **Bite: blocks the proposal** if not held — content rewrites are 10× the work and would defer the structural payoff indefinitely. **Cite:** user framing ("less to scan or discover, less documents to update") is structural, not editorial.

2. **Tooling gap for INDEX.md demotion** — *classification: documentation-process.* M6 reduces INDEX entries to one-liners, but without a `make index` script the manual sync from proposal frontmatter to INDEX label still requires doc-lead attention on every status flip. **Bite: complicates** M6 — does not block it; manual sync is the current state. A `make index` script is a research-track follow-up. **Cite:** documentation-lead skill execution time.

3. **The 12-file `findings/<role>.md` collapse under M1 changes the filename pattern that downstream skills currently grep for.** Skills grep for `compiler-engineer.md`-shaped filenames; under M1 they grep for `## Compiler-engineer` headings inside `findings.md`. Trivial rewrite at the skill level, but it must land in the same PR as M1. **Bite: only matters at integration time** — coordinate the M1 move with skill-file updates in the same PR. **Cite:** experiment-lead and the four role-skills SKILL.md files.

4. **P1 enforcement is a discipline, not a mechanism** — *classification: documentation-process.* Even with D1's update protocol, the project relies on doc-lead and skill instructions to enforce single-authoritative-source. There is no compiler check on doc structure. **Bite: only matters at scale** — over a 6-month horizon, doc-lead discipline plus periodic audits is sufficient; a mechanical check is a research-track item. **Cite:** the project has no doc-lint tooling currently.

5. **Roadmap M5 small-cut is reversible; large-cut is not (cheaply)** — *classification: scope.* Small cut now; defer large cut to when in-file history crosses ~500 lines. **Bite: complicates** the timing decision; does not block. **Cite:** current shipped-history section ~300 lines.

6. **The triage doc is a meta-coordination pattern that doesn't fit cleanly into "design proposal" or "spec" categories.** *Classification: spec-drift in the doc-architecture sense.* Current home is `docs/design/`. If triages become routine, `docs/design/triages/` becomes the right sibling dir. **Bite: only matters at scale.** **Cite:** memory entry `Triage routing pattern` notes the pattern is established but does not commit to a directory.

---

## 10. Open questions for the professor

None. This is an inward-only proposal — the questions are all about LLMLL's own doc structure, the project's own coordination patterns (triage, supersession, archive), and the skills' own update discipline. No external-PL literature reach would clarify a decision. The closest outward question would be "how do GHC and Liquid Haskell organize their design-document folders," but neither maintains a single-repo design-doc folder at this scale, so the comparison would not load-bear. Skip.

---

## 11. Hand-off summary for `documentation-lead`

Per the user's adjudication (single-sweep PR, 2026-05-24), the execution plan is one PR with the file-by-file change list in §8. Recommended sub-commits within the PR for review hygiene:

1. **Protocol commit** — create `docs/UPDATE-PROTOCOL.md`; insert per-skill `## Documentation discipline` blocks into the 5 SKILL.md files. The rules become enforceable.
2. **Findings collapse commit** — create the 3 new `findings.md` files; delete the 12 role files. Update any skill that greps for role filenames to grep for H2 anchors instead.
3. **Archive sweep commit** — create `docs/archive/professor-reviews/` and `docs/archive/wasm-investigations/`; move the 7 files listed in §8.2; append `## Appendix — Professor review log` to the two settled proposals (invariant-discovery, oblig-pbt-3).
4. **Roadmap and INDEX commit** — H2 anchor reorg of `compiler-team-roadmap.md`; migrate `docs/research-track.md` entries into the roadmap and archive the source; demote `docs/design/INDEX.md` entries to one-liners.
5. **README commit** — strip CHANGELOG-shaped paragraph; refresh stale callouts; update Documentation table.

CHANGELOG `Unreleased / Infra` entry candidate:

> **DOC-CONSOLIDATE — Project documentation consolidation and SOP.** Introduces `docs/UPDATE-PROTOCOL.md` codifying canonical-source bindings and per-change update matrix; collapses per-experiment per-role findings to single `experiments/<harness>/findings.md` with H2-per-role; archives post-fold professor reviews and pre-reorganization wasm spike docs; demotes `docs/design/INDEX.md` entries to one-liners; H2-anchor reorg of `compiler-team-roadmap.md`. No language-surface change, no schema bump, no compiler change. Net active doc count −9 files; eliminates three-source status-drift pattern by routing through P1 canonical sources.

No `LLMLL.md §14` update (no user-visible feature). No schema version bump. No test count delta.
