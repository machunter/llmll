# Documentation Lead — Findings from Experiment 001

**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — split from former `documentation-team.md` (D1, D2, D3) under the new five-role pipeline. D1.1 moved to `findings/experiment-lead.md` (`prompts/agent-instructions.md` is harness scope, not doc-lead scope). D1.2 moved to `findings/compiler-engineer.md` (`Diagnostic.hs` rendering is compiler scope). The remaining items (D2 mechanical edits, D3 prose, plus the S4 schema patch surfaced in `findings/language-team.md`) bundle into one doc pass — Activity DL-A.

This file covers one work unit:

- **DL-A — Pedagogical surface doc pass**: schema patch for identifier-shape regex (S4), three-layer Result-pattern updates in `LLMLL.md §11.2 / §13.8` and `docs/getting-started.md §4` (D2), `?proof-required` pedagogical paragraph in `LLMLL.md §13.8` and `docs/getting-started.md §4` (D3). One pass, six target docs at most, sequenced after upstream events.

`documentation-lead`'s six-target-doc allowlist: `README.md`, `docs/getting-started.md`, `LLMLL.md`, `docs/llmll-ast.schema.json`, `docs/compiler-team-roadmap.md`, `CHANGELOG.md`. All edits in DL-A land within this scope. The `experiments/<harness>/` doc surface is **not** in scope (it is `experiment-lead`'s).

---

## DL-A · Pedagogical surface doc pass

### Sequencing — required upstream events

This pass runs only after all three of the following have landed:

1. **`compiler-engineer` CE-A complete.** S1 (typecheck `on_failure`) ships. Required because removing `Result.Error` from the `LLMLL.md §11.2` `on_failure` examples is contradicted by current compiler behavior; the change is consistent only after the compiler enforces the new typing rule.
2. **`language-team` LT-A approved.** The three-layer Result rule, the `?proof-required` pedagogical hook, and the identifier-shape regex are normative decisions. `documentation-lead` does not author them; LT-A confirms them. Approval evidence lives in conversation or as a `docs/design/<topic>.md` draft promoted to settled status.
3. **CHANGELOG seed available.** The compiler-engineer hand-off carries a paragraph describing what landed (S1, S3, D1.2 if bundled). DL-A uses it as the seed for the new CHANGELOG entry.

If any of the three is missing when DL-A is invoked, the doc-lead names the gap and stops. Per the doc-lead skill's input contract, doc updates without an underlying change are forbidden.

---

### Six target docs — what changes in each

Per the doc-lead update-order discipline (CHANGELOG → README → roadmap → LLMLL.md → getting-started.md → schema):

#### 1. `CHANGELOG.md` — new version entry

Append a `## v<version> — <theme> (<date>)` section above the previous one. Suggested theme: "Soundness blockers + Result-pattern docs" (subject to the engineer's actual bundling). Subsection structure follows the established voice (`### Compiler — <subtheme>`, bolded-identifier bullets):

- `### Compiler — Delegate Fallback Typechecking` (S1)
- `### Compiler — PBT Vacuity Fix` (S3)
- `### Compiler — Diagnostic Surface` (D1.2)
- `### Spec — Three-Layer Result Patterns` (D2)
- `### Spec — `?proof-required` Pedagogical Hook` (D3)
- `### Schema — Identifier-Shape Regex` (S4)

Closing `**Tests:**` line updated to the new test count from `compiler-engineer`'s test additions.

#### 2. `README.md` — version banner, command callout, test count

- Update version banner (line 1 header) and version-callout paragraph if version bumps.
- Update the command-table row for `llmll check` if D1.2 changes user-visible text-mode output (it does; warning lines now appear on success). Voice match: keep terse.
- Update the test-count line to match the CHANGELOG `**Tests:**` line.
- No structural reorganization. The 2-min-read shape is preserved.

#### 3. `docs/compiler-team-roadmap.md` — close completed rows

- Mark any `[CT]` rows that S1 / S3 / D1.2 closed with ☑ or ✅.
- Move the closed milestone block from "Upcoming Releases" to "Shipped Releases" if a milestone fully shipped (unlikely for a soundness-fix release; default expectation is row-level updates only).
- Update the "Summary: Version Plan and Critical Path" status line if the version progression advanced.

#### 4. `LLMLL.md` — spec edits per LT-A resolutions

Three edits, each anchored to the language-team's approved resolution:

- **§11.2 `?delegate` rule (S1 small touch).** Add or clarify: "`Γ ⊢ e : T` is required for `?delegate ... → T (on-failure e)` to be well-typed." Verify against the existing §11.2 prose; the rule may already be implicit and need only a one-sentence clarification rather than a new rule.
- **§11.2 / §13.8 Result-pattern examples (D2).** Replace `Result.Error` and `Result.Ok` occurrences with `(err …)` and `(ok …)` per the three-layer rule. Add (or strengthen) the pedagogical paragraph in `§13.8` distinguishing the three layers — *construct* (`ok`/`err`), *match* (`Success`/`Error`), *test* (`is-ok`).
- **§13.8 `?proof-required` paragraph (D3).** New paragraph linking Result-returning contracts to the proof-required escape: when a contract on a function is asserted but cannot be verified (delegation, non-linear arithmetic, map invariants), mark the contract clause `?proof-required` to declare the obligation rather than paper it over.
- **§12 grammar (S4).** Insert the identifier-shape regex once, normative, with cross-reference to the schema. Cite the EBNF clauses at `LLMLL.md §12:1571,1581` that the regex enforces.
- **`llmll test` output section (S3 small touch).** If the new `unknown` status is user-visible (per `compiler-engineer`'s implementation choice), add it to the test-status taxonomy alongside `pass`/`fail`/`skip`.

Voice match: reference, not tutorial. No marketing register.

#### 5. `docs/getting-started.md §4` — Known-Good Patterns additions

- **Result patterns subsection (D2).** Three-layer rule with a worked example for each layer. Length target: roughly the size of the existing Known-Good Pattern entries.
- **`?proof-required` entry (D3).** Top-level entry in §4 explaining when to use the marker, with at least one worked example showing a Result-returning function whose post-condition is asserted.
- **Warning-on-success note (D1.2).** Brief mention that `llmll check` text mode now emits accumulated warnings on success; agents should read warnings even when rc=0.

Voice match: example-led. Keep the existing entry length cadence.

#### 6. `docs/llmll-ast.schema.json` — identifier regex (S4)

- Add `"pattern"` constraint to `ExprApp.fn` and `ExprQualApp.qual_fn` per the LT-A resolution. Exact regex strings are in `findings/language-team.md` S4.
- Bump schema `version` (and `$id` if applicable) per the schema-versioning discipline.
- Update embedded `examples` blocks if any current example violates the new regex.
- Cross-check that `compiler/src/LLMLL/ParserJSON.hs:428-431` does not need paired enforcement (conditional CE-C in `findings/compiler-engineer.md`); the default assumption is schema-only enforcement.

---

### Reconciliation pass — cross-doc checks

After all six edits land, run the doc-lead reconciliation pass before signaling review-ready:

- **Version pins agree.** README header == CHANGELOG top entry == `compiler/package.yaml` version == `compiler/llmll.cabal` version == `llmll version` runtime output.
- **Test count agrees.** README test-count line == CHANGELOG closing `**Tests:**` line.
- **Internal links resolve.** Every `[…](…)` link inside the six targets points to a real file or anchor. Anchors that were renamed (e.g., new `?proof-required` subsection in `§13.8`) are updated wherever cited.
- **Command-table truth.** Every command in `README.md`'s table is present in `llmll --help`. The `llmll check` row matches the new text-mode output behavior from D1.2.
- **Schema example validity.** Every JSON example embedded in any of the six targets validates against the updated schema with the new identifier regex. The `Result.Error` examples that were valid before are now invalid; replace, do not delete-without-replace.
- **Roadmap-CHANGELOG cross-reference.** Every roadmap tag mentioned in the new CHANGELOG entry exists in the roadmap doc; every newly-shipped roadmap row has a corresponding CHANGELOG line.
- **Spec-drift residue check.** Grep `Result.Error` and `Result.Ok` across the six targets after edits — should be zero occurrences except in withdrawn/deprecated callout if one is added.

---

## Out-of-scope items surfaced — not edited

Per doc-lead's "no scope expansion" rule, the following surfaced during reconciliation and are flagged but not fixed in this pass:

- `experiments/minimal-agent/prompts/agent-instructions.md` — D1.1 belongs to `experiment-lead`. Doc-lead does not edit harness prompts.
- `compiler/src/LLMLL/Diagnostic.hs` (or wherever D1.2 lands) — compiler code is `compiler-engineer`'s scope.
- `docs/design/*` — language-team's draft surface; doc-lead does not edit in-flight design drafts.
- Any spec-drift discovered in `LLMLL.md` outside the LT-A neighborhoods (§11.2, §12, §13.8) — surface as findings for `language-team` to adjudicate, do not silently fix.

---

## Withdrawn

**"Treat `Result.Ok` ≡ `ok`, `Result.Error` ≡ `err` as accepted aliases."** Withdrawn at the language-team layer — see `findings/language-team.md`. Doc-lead does not document them as aliases.

---

## Priority

| # | Activity | Impact | Effort |
|---|---|---|---|
| **DL-A** | Pedagogical surface doc pass | High (closes spec-drift, surfaces `?proof-required`) | Medium (six-doc reconciliation pass) |

## Hand-offs

- **`compiler-engineer`** — provides the upstream commit (S1 + S3 + D1.2) and a CHANGELOG seed. DL-A consumes both.
- **`language-team`** — provides the LT-A resolution (three-layer Result rule + identifier regex + `?proof-required` hook + small spec-touch text). DL-A consumes the resolution and writes it.
- **`experiment-lead`** — no direct hand-off. The doc-lead's reconciliation pass will not touch harness files or harness prompts; if cross-doc consistency surfaces a harness-side issue (e.g., `agent-instructions.md` references a `llmll check` flag that changed in D1.2), doc-lead flags it back to experiment-lead, does not edit.
- **`professor`** — none.

## POST-PASS workflow

Per the doc-lead skill:

1. Plan, then stop. Surface this file's content as the doc-update plan and wait for user approval.
2. On approval, apply edits in the order above. Stop and re-plan if any planned change is wrong mid-edit.
3. Run the reconciliation pass.
4. Surface a one-paragraph review-ready summary (files touched, line counts, CHANGELOG entry verbatim, any reconciliation gaps that remain).
5. On user authorization, commit with a `docs:` prefix referencing the version or roadmap tags closed. Do not commit autonomously, do not bundle with code changes.
