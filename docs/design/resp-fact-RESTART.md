---
name: resp-fact-restart
title: "RESP-FACT-1: session restart record"
status: "RESTART RECORD, 2026-09-05. RESP-FACT-1 is SHIPPED as v0.17.0 on the branch resp-fact-1/control-tag-facts, three commits off 213fceb, NOT pushed and NOT merged when this record was written. Section 0 measures that claim. Section 2 lists what is owed."
date: 2026-09-05
author: compiler-engineer
consumers: [user, compiler-engineer, language-team, documentation-lead, professor]
style: "ASD-STE100 Simplified Technical English. See docs/design/tool-ll-RESTART.md section 0 for the rules."
---

# RESP-FACT-1: restart record

## 0. Measure the state before you use it

This file states where the work stopped. A record of that kind became incorrect
at a handoff three times in this repository. Do these steps first.

1. Run `git rev-parse --abbrev-ref HEAD`. It must print `resp-fact-1/control-tag-facts`, or `main` after a merge.
2. Run `git log --oneline main..resp-fact-1/control-tag-facts`. It gives the unmerged commits. Section 1 names three.
3. Run `git status --short`. It must print nothing.
4. Run `head -1 LLMLL.md`. It gives the version banner. Section 1 says `v0.17.0`.
5. Run `bash scripts/version_gate.sh`. It must pass.
6. Run `gh run list --branch resp-fact-1/control-tag-facts --limit 3`. It gives the CI result, if the branch was pushed.
7. Run the roadmap census command in `docs/design/tool-ll-RESTART.md` section 0.

If a result disagrees with section 1, section 1 is incorrect. Correct it before other work.

The compiler binary can be older than the tree. Run this before any `llmll` command:

```sh
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH && llmll version
```

It must print `llmll 0.17.0`. If it does not, run `stack build` in `compiler/`.

## 1. What the branch holds

Three commits off `213fceb`, written 2026-09-04:

- `6052919`: proposal Rev 6, professor round 5, engineer plan revision 2. Documents only.
- `d5dd5a8`: the compiler change. New module `compiler/src/LLMLL/RespFact.hs`. Seams in `TypeCheck.hs`, `FixpointEmit.hs`, `TrustReport.hs`, `VerifiedCache.hs`. Twenty-five fixtures under `compiler/test/fixtures/resp-fact/`. Fifty-seven Spec examples. `stack test` measured 1831 examples, 0 failures, twice.
- `51a428a`: the v0.17.0 release records. CHANGELOG, README, `LLMLL.md` §9.7, §13.9, §5.3.5, §4.4.4, the roadmap, getting-started §4.27, INDEX rows 94 and 95, the version pins.

The design is `docs/design/resp-fact-proposal.md` Rev 6. The plan is
`docs/design/resp-fact-implementation-plan.md` revision 2. The CHANGELOG entry
`## v0.17.0` states what shipped and lists five deviations from the plan.

## 2. What is owed

**Updated 2026-09-05.** Items 3 to 6 are DONE. Items 1, 2 and 7 remain.

1. **Push the branch and read CI.** NOT DONE. The `version-gate` workflow re-runs the doc-claims
   gate and the path lint. Every tracked `.verified.json` re-verifies once under
   `checker_soundness_version` `"2"`.
2. **Merge to `main`** after CI passes. NOT DONE. Tag `v0.17.0` after the merge. A tag push starts
   `docker-publish`.
3. **Fix four citations in the plan.** DONE. The two fixture lines now carry the
   `compiler/test/fixtures/resp-fact/` prefix. The plan's own §16 item 6 instruction named targets
   that had themselves drifted; it now says to name the construct.
4. **Write the §16 closure notes.** DONE. All eleven items carry a state. Items 1, 4, 6 and 7 are
   closed; items 2, 3, 5, 8, 9 and 10 are open; item 11 is deferred to `MOD-PROGLIB-1`. The
   proposal frontmatter is settled to `Rev 6, SETTLED and SHIPPED as v0.17.0`, and §11
   prerequisite 3 is marked discharged.

   **Item 6 was wider than the finding said, and this is the reusable part.** `d5dd5a8` repaired one
   comment and left `CodegenHs.hs:582-586` incorrect inside that same comment. A sweep of every
   cross-file citation in `compiler/src` found **nine** incorrect ones, because `d5dd5a8` moved
   `TypeCheck.hs` by one line at the import and by twelve more at `checkStatements`. All nine are
   repaired by NAMING THE CONSTRUCT, never the line. Roadmap row `SRC-CITE-DRIFT-1` records that no
   gate catches this class.
5. **File the roadmap rows.** DONE, and there were **eight**, not three. `PAIR-PROJ-LET-1`,
   `CALL-PRE-ARGCALL-1`, `XMOD-QUAL-CTOR-1` (which §16 named), plus `SHELL-FALLBACK-SILENT-1`,
   `CLAUSE-CTOR-PAREN-1`, `XMOD-CTOR-SEVERITY-1` (§16 items 2, 3, 5, which were routed "as a new
   row" with no tag), plus `SRC-CITE-DRIFT-1` and the deferred `MOD-PROGLIB-1`.
6. **Fold the review.** DONE. `resp-fact-review.md` is folded into the proposal as
   `## Appendix — Professor review log` and moved to
   `docs/archive/professor-reviews/resp-fact-proposal-review.md`. Nine inbound citations were
   repointed across four files. There is no "protocol row 45"; the rule is the **Archive policy**
   section of `docs/UPDATE-PROTOCOL.md`, and `professor-reviews/` takes no `archive-disposition`
   field. That directory is outside the two governed directories, so the move does not affect the
   DRIFT-DOC-3 ungated bound of 58.
7. **`FS-STAT-1` is unblocked.** NOT STARTED. Its clamp's discharge claim can be a fact request
   under `LLMLL.md` §9.7.

**One defect found and NOT fixed.** The Active Items census note claimed 39 `OPEN` rows. The row
total (55) reproduced exactly; the `OPEN` split did not, under either a substring rule (44) or a
leading-word rule (42). The note now records the reproducible rule and the measured figures (63
rows, 50 `OPEN`, after the eight new rows), and says the older sub-count is unexplained. Whoever
touches it next should settle which rule the 39 counted rather than copy it forward.

## 3. What not to trust

- Do not trust a count in a memory file. Measure it with section 0.
- Do not run `git stash`, then `stack build`, then `git stash pop` in this repository. `hpack` rewrites `compiler/llmll.cabal` during the build and the pop is refused. Use a worktree.
- Do not read the engineer plan as the record of what shipped. The CHANGELOG entry and `d5dd5a8` are. Five deviations are listed in both.
- `verify` prints `W-RESP-FACT-UNBOUND` twice on a refuted run. That is cosmetic and recorded.
