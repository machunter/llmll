---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, written 2026-08-07. The authority on WHERE THE WORK IS. The authority on WHAT THE STANDARD SAYS is llmll-tooling-campaign.md; when they disagree about the standard the campaign wins, when they disagree about state re-measure. DRIVER-LL Phase 4 sub-phase 4e is COMPLETE and its record (driver-ll-phase4-RESTART.md) is closed history. The active campaign is TOOL-LL, one port of six landed, blocked at P1 on a decision only the user can take."
date: 2026-08-07
author: language-team
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

Branch `hole-status-sibling/brief-unfilled-status`, **15 commits ahead of local
`main`**, local `main` **7 commits ahead of `origin/main`**, **nothing pushed at
all**, working tree clean.

**The branch name is wrong and this is the first thing to fix.** It was cut for
one compiler fix (`6547de4`, HOLE-STATUS-SIBLING) and now carries four unrelated
bodies of work: theory-question records, a doc-frontmatter fix, all of DRIVER-LL
sub-phase 4e, and the TOOL-LL campaign. Verify this section before trusting it.

**A shipped compiler behaviour change is sitting unreleased on it.** `6547de4`
changes `Checkout.hs` and `HoleAnalysis.hs` so a sibling whose body still holds
a hole reads `status: "unfilled"`, and moves `brief_version` to 0.12.3. The
CHANGELOG still reads 0.14.87. So the branch changes compiler behaviour with no
version bump, and the gate that would catch that cannot, because the five banner
sites still agree with each other at the old version.

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

## 3. The next action, and it needs the user

**P1, clear the tag debt, is blocked on a decision only the user can take.**
Newest tag on origin is `v0.14.83`; banners read `0.14.87`. The chosen
distribution mechanism is a published image, and no image exists for the last
four releases, so every port's distribution step is blocked behind this.

Targets **verified 2026-08-07**: each is the release-doc commit, each has all
five banner sites consistent at its own version, and each is already an ancestor
of `origin/main`, so tagging needs no branch push.

| Tag | Commit |
|---|---|
| v0.14.84 | `a182638` |
| v0.14.85 | `1428fe3` |
| v0.14.86 | `6e92dd0` |
| v0.14.87 | `1bc2965` |

**Three things stand in front of it:**

1. **Pushing a `v*` tag publishes.** It triggers `docker-publish.yml`'s
   `publish` job, which runs `version_gate.sh` at the tag and pushes an image to
   ghcr.io. This is outward-facing and needs explicit authorization.
2. **An unverifiable mechanism.** `on.push` carries both `paths:` filters and
   `tags: ['v*']`. Whether a tag on an already-pushed commit satisfies the path
   filter cannot be settled by reading. If it does not fire, the tags land with
   no images, which is worse than the present state because it looks released.
   **Mitigation: push `v0.14.84` alone, observe, then decide.**
3. **`origin/main`'s most recent CI run did not complete.** 2026-08-06 20:42,
   `cancelled` after 15m, as was one earlier that evening, with a 2-minute
   success between them. The workflow has no `timeout-minutes` and no
   `concurrency` group, so its own config does not explain it. **Unresolved.**

**P3 needs no authorization and is available now.**
`refute-crux-gate.sh` is **not invoked by any workflow**; it is a `make` target
only, despite its own header calling itself a CI gate, and it freezes 80 verify
verdicts including every driver refute crux. Wiring it into `version-gate.yml`
is a few lines of shell, and it must precede TOOL-RFC-002 or that port ports
something CI does not run.

## 4. State of the campaign

| | |
|---|---|
| **001** DRIFT-CI-1 version gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-001](tool-rfc-001-version-gate.md) |
| **002** refute-crux gate | next, after P3; first port written RFC-first |
| **003** doc-claims, **004** doc-archive | not started |
| **005** doc-path-lint | blocked on `REGEX-LOWER-1` |
| **006** build-smoke | last; it runs the others |
| **P1** tag debt | **BLOCKED on the user**, §3 |
| **P2** file the gaps | **DONE**: `MODE-CLI-1`, `SPLIT-EMPTY-1`, `FS-WALK-1` |
| **P3** wire refute-crux into CI | available now |

## 5. Gates, measured on this tree at `1c515ca`

**Re-measure, do not assume.**

| Gate | Figure |
|---|---|
| `stack test` | 1656 examples, 0 failures (no Haskell changed this session) |
| `pytest scripts/tests/` | 188 passed, 1 skipped |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 80 passed, 0 failed |
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
   invoked; `refute-crux-gate.sh` is in that state today. The standard's §1
   exists to catch it before code is written.

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

- The branch (§1), and the release ceremony its compiler change owes.
- **No parse gate over design-doc frontmatter.**
- `HDelegate`, `HDelegateAsync`, `HDelegatePending`, `HConflictResolution` reach
  the HOLE-STATUS-SIBLING catch-all unpinned by any test.
- DRIVER-LL 4d is parked; 4f, program unification and stage A stay deferred.
  Five of the eight remaining callerless rows are 4d's.
