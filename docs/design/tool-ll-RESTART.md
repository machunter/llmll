---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, written 2026-08-07. The authority on WHERE THE WORK IS. The authority on WHAT THE STANDARD SAYS is llmll-tooling-campaign.md; when they disagree about the standard the campaign wins, when they disagree about state re-measure. DRIVER-LL Phase 4 sub-phase 4e is COMPLETE and its record (driver-ll-phase4-RESTART.md) is closed history. The active campaign is TOOL-LL: two ports of six landed as oracles, all three prerequisites cleared, nothing blocked on a decision. Next is 003/004."
date: 2026-08-07
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, experiment-lead, user]
---

# TOOL-LL: restart record

**Read this first, then
[`llmll-tooling-campaign.md`](llmll-tooling-campaign.md).** This file is where
the work is; that one is what the standard says. Everything below is dated and
every figure names how it was measured, because a restart record in this
repository has gone stale inside a day before.

---

## 1. Where the work is

Branch `tool-ll/campaign-4e-hole-status`. At `d6e9f01`: **21 commits ahead of
local `main`**, local `main` **7 commits ahead of `origin/main`**, **the branch
has never been pushed**, working tree clean.

The count is stamped with the commit because this file's first version said 15
and was stale within the hour. If `HEAD` is not `d6e9f01`, re-measure rather
than reading on:
`git rev-list --count main..HEAD` and `git rev-list --count origin/main..main`.

**Tags are a separate matter and four of them ARE pushed** (§3). Tags on
commits already in `origin/main` need no branch push, which is why P1 could
close while the branch stayed local.

**The branch was renamed 2026-08-07**, from `hole-status-sibling/brief-unfilled-status`.
It was cut for one compiler fix (`6547de4`, HOLE-STATUS-SIBLING) and carries four
unrelated bodies of work: theory-question records, a doc-frontmatter fix, all of
DRIVER-LL sub-phase 4e, and the TOOL-LL campaign. The name now says so.

**The compiler behaviour change it carried is released, 2026-08-07: v0.14.88.**
`6547de4` changes `Checkout.hs` and `HoleAnalysis.hs` so a sibling whose body
still holds a hole reads `status: "unfilled"`, and moves `brief_version` to
0.12.3. That shipped with no version bump, and the gate that would catch it
could not, because the five banner sites still agreed with each other at the old
version. All five now read 0.14.88 and `version_gate.sh` passes. **The tag is
not pushed**: it is owed at merge, and this branch has not merged.

## 2. What is settled, and must not be re-litigated

User adjudications, 2026-08-07:

- **Scope**: the six CI gates, and nothing else. The covers,
  `rfc_to_implementation.py` and `scripts/tests/` are out, each for a reason
  recorded in campaign §2.
- **Distribution**: jobs pull a published release image.
- **Retirement**: the original stays one release as a differential oracle, then
  is deleted in the same commit that flips the RFC's `tool_state` to `retired`.
- **The gap discipline**: every gap takes exactly one of BLOCKS, SHAPES or
  COSMETIC, and a SHAPES row must state what the design would have been and cite
  a roadmap tag.

## 3. The prerequisites, all three now cleared

**The next action is writing TOOL-RFC-002's port.** P1, P2 and P3 are done, and
nothing in the campaign is now blocked on a decision.

**P1 is DONE, 2026-08-07. The tag debt is cleared and all four images are
published**, each verified at its `Build + push (amd64)` step rather than at the
run's green check. The user authorized it; it was not taken unilaterally.
`:latest` points at `v0.14.87`, which is why `v0.14.87` was pushed last and
alone: concurrent publish runs race, and `:latest` lands on whichever finishes
last rather than on the highest version.

Each target was re-verified before its push: banner matching its own tag,
`version_gate.sh` exit 0 at that commit in a detached worktree, and already an
ancestor of `origin/main`, so no branch push was needed. All four tags are
annotated and each says in its message that it was backfilled after the fact.

| Tag | Commit |
|---|---|
| v0.14.84 | `a182638` |
| v0.14.85 | `1428fe3` |
| v0.14.86 | `6e92dd0` |
| v0.14.87 | `1bc2965` |

**The three hazards, and how each was discharged:**

1. **Pushing a `v*` tag publishes.** It triggers `docker-publish.yml`'s
   `publish` job, which runs `version_gate.sh` at the tag and pushes an image to
   ghcr.io. Outward-facing, so it needed explicit authorization. **Given.**
2. **The mechanism was called unverifiable, and it was verifiable after all,
   from history rather than from the file.** `on.push` carries both `paths:`
   filters and `tags: ['v*']`, and whether a tag satisfies the path filter
   cannot be settled by reading the YAML. It can be settled by looking at what
   already happened: the run list shows `headBranch=v0.14.82` and `v0.14.83`,
   both `push`, both `success`, with `build-test` skipped and `publish` run.
   **Tag pushes have been firing this workflow all along.**

   The mitigation was followed anyway: `v0.14.84` alone, observed to green
   (run `31222612126`, `Build + push (amd64)` success, 17m59s), then the rest.
   The doubt was correct to record; the wrong tool was reached for to answer it.
   A question about what a workflow does is answered by what it did, and that
   evidence was three commands away the whole time.
3. **`origin/main`'s most recent CI run did not complete. RESOLVED 2026-08-07,
   and it is not the workflow.** Both runs (2026-08-06 19:21 and 20:42) are
   `failure` at the run level and `cancelled` at the job level, at 15:02 and
   15:03. **Both jobs in each run executed ZERO steps** and share start and end
   timestamps to the second, so they never received a runner: they sat queued
   and were cancelled at 15 minutes.

   That rules out the workflow's own config, and it also rules out the fix that
   looks obvious. **Adding `timeout-minutes` would not have prevented it**, since
   a job that never starts has no step for a timeout to bound. It is not quota
   or billing either: the repository is public, so Actions minutes are free, and
   a 2m05s success at 19:56 sits between the two failures, which no persistent
   account-level block would allow.

   What remains is a transient runner-assignment problem upstream on that
   evening. Nothing in this repository is actionable; the response to a
   recurrence is to re-run, not to edit the workflow. Recorded so the next
   reader does not spend the time again, and so nobody "fixes" it with a
   `timeout-minutes` that cannot fire.

**P3 is DONE, 2026-08-07, and needed no authorization.**
`refute-crux-gate.sh` now runs in `version-gate.yml`'s `spec-roundtrip` job:
that is the Stack-bearing job, and the gate shells out to `stack exec llmll --`,
so the deliberately toolchain-free job could not host it. It sits after the
cheap doc-claims gate and before `build_smoke.sh`, keeping the job ordered cheap
to expensive, and a jq guard was added because the script hard-requires jq and
the job had never asserted it. Measured 80 passed / 0 failed, ~3 min, at
`f555070`. TOOL-RFC-002 now has a wired gate to port.

## 4. State of the campaign

| | |
|---|---|
| **001** DRIFT-CI-1 version gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-001](tool-rfc-001-version-gate.md) |
| **002** refute-crux gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-002](tool-rfc-002-refute-crux.md). 80/80 verdicts, agrees with the reference. Found `FD-CAPTURE-1` (BLOCKS, fixed), `JSON-SCALAR-1`, `PROC-MERGE-1` |
| **003** doc-claims, **004** doc-archive | not started; **next** |
| **005** doc-path-lint | blocked on `REGEX-LOWER-1` |
| **006** build-smoke | last; it runs the others |
| **P1** tag debt | **DONE**, §3: four tags pushed, four images published |
| **P2** file the gaps | **DONE**: `MODE-CLI-1`, `SPLIT-EMPTY-1`, `FS-WALK-1` |
| **P3** wire refute-crux into CI | **DONE**, §3 |

## 5. Gates, measured at `1c515ca`

**Re-measure, do not assume.** Only documentation changed between `1c515ca` and
`0299a41`, so these hold at `HEAD`; `pytest` was re-run after each and stayed at
188.

| Gate | Figure |
|---|---|
| `stack test` | 1656 examples, 0 failures (no Haskell changed this session) |
| `pytest scripts/tests/` | 188 passed, 1 skipped |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 80 passed, 0 failed; re-measured at `f555070`, ~3 min warm |
| [`doc_path_lint.py`](../../scripts/doc_path_lint.py) | 910 citations, all resolve |
| [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | 39 passed, needs a rebuilt sequencer via `--driver` |
| [`wave_cover.py`](../../scripts/wave_cover.py) | 7 passed, needs `--wave` |
| [`version_gate_cover.py`](../../scripts/version_gate_cover.py) | 14 passed, needs `--gate` and `--llmll` |
| [`version_gate.sh`](../../scripts/version_gate.sh) | PASS at 0.14.87 |
| [`build_smoke.sh`](../../scripts/build_smoke.sh) | PASS, stages 1 to 10 |

## 6. Findings not to rediscover

1. **`MODE-CLI-1` is the reason the ports are large.** `:mode cli` emits
   `print (step args)`: a pure step, no `Command` performed, no exit status,
   zero in-tree users. `console` is the only usable entry mode, so every LLMLL
   tool is a stdin-driven step machine that exits **70** on EOF. 58 code lines
   of shell became 278 of LLMLL, and this is the single largest contributor.

2. **`SPLIT-EMPTY-1`: `string-split ""` does not terminate**, typechecks, and
   *verifies*. There is no character decomposition at all, so a scan must be a
   fold over a literal index list with a hand-written bound.

3. **`CAP-NULLARY-1`: nullary `wasi.*` builtins bypass capability enforcement.**
   `checkWasiCapability` is called only from `inferExpr (EApp ...)`, so argv and
   the wall clock are reachable with no capability import naming them.

4. **The per-fill bar is not redundant with `patch`.** A body of
   `(+ n (string-length "x"))` satisfies its postcondition, answers
   `PatchSuccess`, verifies SAFE, and lands in `body-fallback`. `[S9-FAITHFUL]`
   is the only thing that rejects it.

5. **`checkout` and `patch` take a `.ast.json`, not a `.llmll`**, and `--emit`
   is a bare flag. A refused patch leaves the lock HELD; a successful one clears
   it. Full list in
   [`driver-ll-phase4-RESTART.md`](driver-ll-phase4-RESTART.md) §4.

6. **A gate that is not wired in decides nothing.** 4c shipped a cover nothing
   invoked; `refute-crux-gate.sh` was in that state until P3 wired it
   (2026-08-07, §3). The standard's §1 exists to catch it before code is
   written, and here it did: the finding came from applying §1 to the port,
   before any of the port was designed.

## 7. Gotchas that cost real time this session

- **zsh does not word-split unquoted parameters.** `set -- $pair` inside a loop
  puts the whole string in `$1`, so `git show "$sha:F"` became
  `git show ":F"`, which reads the **index** and silently answers about the
  working tree. It cost two false conclusions in one turn. Use Python for
  anything with quoting in it.
- **zsh eats `^` and `{}`.** `git cat-file -e $sha^{commit}` unquoted reports
  every commit as missing.
- **`yes x | head -n N | prog` reports 141 under `set -o pipefail`**, because
  `yes` is designed to die of SIGPIPE. It failed a build stage while the program
  under test printed PASS.
- **A console program with no stdin hangs**, and writes
  `<module>.event-log.jsonl` into its **working directory**. Run tools from a
  scratch dir with an absolute `--root`.
- **The repo-root binary is stale.** Always
  `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH`.
- **Run `doc_path_lint.py` on its own line**; piping to `tail` takes `tail`'s
  exit status.

## 8. Debt, deferred and unrelated

- The branch is renamed and its compiler change is released as v0.14.88 (§1).
  **The `v0.14.88` tag is not pushed and should not be until this branch merges**,
  since the tag's own gate compares it to the banner on `main`.
- **No parse gate over design-doc frontmatter.**
- `HDelegate`, `HDelegateAsync`, `HDelegatePending`, `HConflictResolution` reach
  the HOLE-STATUS-SIBLING catch-all unpinned by any test.
- DRIVER-LL 4d is parked; 4f, program unification and stage A stay deferred.
  Five of the eight remaining callerless rows are 4d's.
