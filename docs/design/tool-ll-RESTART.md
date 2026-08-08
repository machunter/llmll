---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, 2026-08-08. The authority on WHERE THE WORK IS. The authority on WHAT THE STANDARD SAYS is llmll-tooling-campaign.md; when they disagree about the standard the campaign wins, when they disagree about state re-measure. DRIVER-LL Phase 4 sub-phase 4e is COMPLETE and its record (driver-ll-phase4-RESTART.md) is closed history. The active campaign is TOOL-LL: two ports of six landed as oracles, all three prerequisites cleared. **FULLY RELEASED AT v0.14.91**, `main` green at `5b88bc9`, tag pushed and image published with `:latest` on its digest (`b9a0dcec`), verified at the REGISTRY. **BOTH [CT][SPEC] SHAPE CALLS ARE NOW SETTLED AND SHIPPED IN v0.14.91**: JSON-SCALAR-1 as a FOUR-name projection family (the field family minus the key), PROC-MERGE-1 as equal-path-strings-mean-merge with ordering explicitly NOT in the contract, that last decided by measurement rather than argument. Both shipped with EXECUTED fixtures, and both fixtures were mutation-checked rather than assumed to work. The port's last workaround is gone, so finding 11 is fully closed. **003 IS COMMITTED AND CUT AS v0.14.92**: port, differential cover (17 cells + 3 controls), CI wiring and RFC at `tool_state: oracle`, three ports of six now landed as oracles. The cover caught TWO real defects in the port before either shipped, neither reachable from the live corpus. **THE CEREMONY IS NOT FINISHED**: v0.14.92 is committed but NOT tagged and NOT published, because the ordering rule in §1 tags only after `version-gate` is green on `main`. Everything in §5 is macOS/aarch64 and none of v0.14.92 has run on Linux."
date: 2026-08-08
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

**THE MERGE IS DONE.** `tool-ll/campaign-4e-hole-status` fast-forwarded into
local `main` at `8bf4ece` (33 commits, 48 files, 7,741 insertions) and pushed
`b9cbf00..8bf4ece` on 2026-08-07. The branch still exists and is now identical
to `main`. The counts this section used to carry are retired: they were a
property of an unmerged branch and there is no longer one.

**v0.14.92 IS COMMITTED AND IS NEITHER TAGGED NOR PUBLISHED YET**, four commits
past `5b88bc9`: the 003 port with its RFC and cover and CI wiring, the release,
this record, and one fix-forward. **THE FIRST CI RUN WAS RED and the ordering
rule is what stopped a broken tree being published** (run `31282452612`). It was
not the port: the cover's scrubbed environment gave the compiler no locale, and
on Linux `TOOL-ENCODING-1` then made it unable to read any of the 15 fixtures.
Finding 15. Everything below about v0.14.91 remains true and is the state this
one is built on. **The next reader's first job is to check whether that
sentence is still current**, because the ordering rule below is the whole reason
it is written this way: `gh run list --branch main --limit 3`, and if
`version-gate` is green at the tip then the tag and the image are what is owed,
tagged ALONE and verified at the REGISTRY.

**`main` WAS GREEN at `5b88bc9` (v0.14.91), tagged and published.** v0.14.91
fast-forwarded `1745a69..5b88bc9` on 2026-08-08 and went green on Linux first
time, which is worth recording because the previous merge needed three
fix-forward commits. **Both new fixtures are confirmed to have BUILT AND RUN on
Linux**, not skipped: `proc_merge.llmll` passing there is the one that mattered,
since it spawns `/bin/sh` and its control depends on the child's buffering.

**The tag run finished in 27 SECONDS and that is not a red flag, but it looks
exactly like one.** v0.14.90's took 23m50s. The difference is a Docker layer
cache hit: the same commit had been built by the `main` push twenty minutes
earlier, so only the push happened. `Build + push (amd64)` succeeded and the
registry confirms it. **This is the case §1 keeps warning about from the other
direction**: a fast green is as much in need of registry verification as a slow
one.

**The earlier merge, kept because its lesson stands.** Getting v0.14.90's merge green
took three fix-forward commits. The merge's first CI run failed, and so did
the two after it. **Every one of the three was a defect the merge exposed and
none was visible from macOS**, which is the case for having merged before doing
the bug work:

| Run | Failed at | Cause | Fixed by |
|---|---|---|---|
| 1 | refute-crux gate, 2 passed / 78 failed | the job had never had a solver | `6fda261` |
| 2 | the port step | `stack exec` outside a stack project | `f5e1cd3` |
| 3 | `build_smoke.sh` | the version cover pinned `v0.14.87` | `235da63` |

Findings 12, 13 and §7 carry them. **Three of the three are finding 6's class**:
wired but never run, written but never executed, or measured somewhere it could
not fail.

**All owed tags are PUSHED and all images are published**, each verified at the
REGISTRY and not at a run's green check: `v0.14.88` `5c1194d4`, `v0.14.89`
`92f501d4`, `v0.14.90` `0720f75d`, `v0.14.91` `b9a0dcec`, and `latest`
resolving to `b9a0dcec` — the same digest as `v0.14.91`, which is what says the
ordering rule below worked. v0.14.91 was tagged ALONE, after `version-gate` was
green on `main` and after that commit's image had passed the container
acceptance gate in the `main` run: v0.14.90's pattern, repeated deliberately.

**Re-measure, do not read on.** If `git rev-list --count origin/main..main` is
not 0, or the newest `version-gate` run on `main` is not green, this section is
describing a world that has moved:
`gh run list --branch main --limit 3`.

**The branch was renamed 2026-08-07**, from `hole-status-sibling/brief-unfilled-status`.
It was cut for one compiler fix (`6547de4`, HOLE-STATUS-SIBLING) and carries four
unrelated bodies of work: theory-question records, a doc-frontmatter fix, all of
DRIVER-LL sub-phase 4e, and the TOOL-LL campaign. The name now says so.

**THREE releases came out of this branch and all three are tagged and
published.** v0.14.88 (`d6e9f01`) releases `6547de4`, which changes
`Checkout.hs` and `HoleAnalysis.hs` so a sibling whose body still holds a hole
reads `status: "unfilled"` and moves `brief_version` to 0.12.3. v0.14.89
(`c7c057a`) releases `FD-CAPTURE-1` plus TOOL-RFC-002. v0.14.90 (`2d27c0d`)
releases `CAPTURE-ENCODING-1`.

**THE ORDERING RULE THAT PRODUCED THAT, KEPT BECAUSE IT STILL BINDS.**
`docker-publish.yml`'s publish job runs `version_gate.sh` AT THE TAG and pushes
an image to ghcr.io, so tagging a red `main` publishes from a broken tree, and
the campaign's settled distribution is jobs pulling exactly those images (§2).
Tag only after `version-gate` is green on `main`. Push tags SEPARATELY, lowest
first, each observed green at its `Build + push (amd64)` step before the next:
concurrent runs race and `:latest` follows whichever finishes last, not the
highest version.

**v0.14.88 and v0.14.89 were BACKFILLED; v0.14.90 was not.** The first two sat
untagged across a merge and three red runs. The third was tagged the same day,
on a commit already green on Linux and whose image had already passed the
container acceptance gate in the `main` run. That is the shape to repeat.

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

## 3. The agreed plan, and the one gate inside it

**Agreed with the user 2026-08-07, after 002 landed. Do not re-derive it:**

1. ~~**Merge this branch to `main` and push.**~~ **DONE**, 2026-08-07 (§1).
   Merging before the bug work was right, and the first run is the evidence: it
   found a defect that only exists on Linux (finding 12) and that no amount of
   local work would have surfaced.
2. ~~**Watch that CI run. Tags only after it is green.**~~ **DONE.** Three runs
   were red and each named a real defect (§1's table). `main` is green at
   `235da63`, both tags are pushed and both images are published, `:latest`
   resolving to the same digest as `v0.14.89`.
3. ~~**`CAPTURE-ENCODING-1` next.**~~ **SHIPPED v0.14.90**, tagged and published
   the same day. Cause: `System.Posix.IO.fdToHandle` returns a handle in BINARY
   mode, which is the ABSENCE of a codec rather than a wrong one, so
   `setLocaleEncoding` had nothing to inform — `hGetEncoding` answers `Nothing`
   on both pipe ends while the locale reads UTF-8. Fixed by pinning `utf8` on
   both ends, write end BEFORE the redirect; all four configurations ablated.
   **Both workarounds are gone** (finding 11), so the port writes a real `→` and
   the cover compares labels instead of normalising them — which is also how the
   Linux datapoint arrived, since that comparison cannot pass on Linux unless the
   fix works there.
4. ~~**`JSON-SCALAR-1` and `PROC-MERGE-1` behind a language-team shape call**,
   per finding 9.~~ **BOTH SHIPPED v0.14.91**, the shapes put to the user rather
   than settled at the keyboard.

   **`JSON-SCALAR-1` took the WIDER shape: four names**, `json-as-string` /
   `-int` / `-bool` / `-number`, each `Json -> Result[T,string]`. The argument
   that decided it is that `json-array` was ALREADY a projection of exactly that
   shape, so the family had one member and the question was whether to finish it,
   not whether to invent a kind of operation. The five now partition `Json`.

   **`PROC-MERGE-1`'s prior question was the one that mattered, and measurement
   settled it: ordering is NOT part of the contract and cannot be.** A merged
   stream's interleaving is the order the CHILD flushes, not the order it writes.
   Probed directly against GHC's `process`: a child writing stdout first and
   stderr second lands **stderr first**, stdout being block-buffered when its fd
   is a file. So the "byte for byte" reproduction TOOL-RFC-002 §5 imagined was
   never available to promise. Mechanism: equal path STRINGS mean merge, one
   handle on both, no signature change. Syntactic equality, so `"log"` and
   `"./log"` do not merge.

   **One correction the closure forced.** It was recorded in three places that
   `(json-get-string x "")` on a scalar *answers* `""`. It does not: `json-get`
   on a non-object is `err`. The `""` came from the PORT, whose `jstr` wraps
   every field read in `(unwrap-or ... "")`. The defect was a missing operation
   whose absence every call site papered over locally, which is why no gate
   could see it, and it is the argument for the `Result` shape.
5. **003, RFC-first.** ~~NEXT~~ **DONE AND COMMITTED**, released as v0.14.92.
   RFC written before any code with both §8 questions put to the user; port at
   [`tools/doc-claims/docclaims.llmll`](../../tools/doc-claims/docclaims.llmll);
   cover at [`doc_claims_cover.py`](../../scripts/doc_claims_cover.py), 17 cells
   and 3 negative controls, all ok; wired into `spec-roundtrip` adjacent to its
   reference; `tool_state: oracle`.

   **"BYTE-IDENTICAL" WAS TOO STRONG AND IS CORRECTED HERE BEFORE IT PROPAGATES.**
   The live run is identical to the reference **line for line with blank lines
   stripped from BOTH sides**, exit codes agreeing (0 and 0). Stripping is not
   optional and is not symmetric in what it costs: the port's `console` harness
   emits a blank line per step, 47 of them in a live run, so its output cannot be
   compared without removing them, and removing them also removes the ONE blank
   line the reference prints deliberately between its last tick and its summary.
   [`doc_claims_cover.py`](../../scripts/doc_claims_cover.py)'s `normalise()`
   already said exactly this and the prose above it did not. The weakening is
   small, it is stated rather than glossed, and this is 002's discipline
   (decisions and exit codes compared, not bytes) applied to its own record.

   **THE COVER EARNED ITS PLACE ON ITS FIRST RUN, twice.** Cell 5: the port
   promoted a `warn` observation on the presence of `warning:` alone, where the
   reference promotes it only when the warning AND the pinned substring match.
   Cell 11: the port probed its subject unconditionally and SKIPPED where the
   reference FAILS, because `LLMLL_BIN` set to a nonexistent path is used AS
   GIVEN and never second-guessed. **Neither was reachable from the live
   corpus**, which always names a working subject and always passes.

   **Two cover bugs of my own, both worth not repeating.** A cell anchored on a
   fixture that lacked the header it wanted (the anchor guard firing as
   designed), and — the instructive one — **the two implementations were given
   DIFFERENT ENVIRONMENTS**, so the port found an `llmll` on `PATH` the
   reference could not see. A differential cover that varies the environment
   between its two sides is comparing two worlds, not two implementations.

   **Settled by the user 2026-08-08, do not re-litigate:** the port reproduces
   the reference's two SKIP paths faithfully and the silent success is filed as
   `SKIP-SILENT-1` rather than fixed inside a port commit; the `@expect` grammar
   is implemented in FULL, which the retirement rule forces rather than taste.
6. ~~**Commit and release 003.**~~ **DONE**, three commits: the port with its
   RFC, cover, CI wiring and the `SKIP-SILENT-1` row; the v0.14.92 release; this
   record. **THE CEREMONY IS NOT FINISHED AT THAT POINT AND THIS STEP IS NOT
   EITHER**: v0.14.92 is not tagged and no image is published until
   `version-gate` is green on `main`, which is the ordering rule in §1 and the
   only thing standing between a red tree and a published release image.
7. **NEXT: 004 (doc-archive), RFC-first.** 005 stays blocked on `REGEX-LOWER-1`
   and 006 stays last, since it runs the others.

**003 is NOT blocked by any of the three open gaps**; that was measured, not
assumed. So step 3 and 4 before step 5 is a choice to stop accumulating
workarounds across four remaining ports, not a dependency.

P1, P2 and P3 are all done and nothing in the campaign is blocked on a
decision.

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
| **002** refute-crux gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-002](tool-rfc-002-refute-crux.md). 80/80 verdicts, agrees with the reference. Found `FD-CAPTURE-1` (BLOCKS, fixed v0.14.89), `CAPTURE-ENCODING-1` (fixed v0.14.90), `JSON-SCALAR-1` and `PROC-MERGE-1` (both **fixed v0.14.91**). **All four of its findings are now closed and every workaround it carried is deleted** |
| **003** doc-claims | **PORTED**, `tool_state: oracle`, [TOOL-RFC-003](tool-rfc-003-doc-claims.md). Released v0.14.92. 15 fixtures, agrees with the reference. Filed `SKIP-SILENT-1` (COSMETIC in the RFC, its own roadmap row), and found **no new language gap**: the first port in the campaign that did not, which is a datapoint about the gaps 002 closed rather than about how hard 003 was |
| **004** doc-archive | not started; **004 is NEXT** |
| **005** doc-path-lint | blocked on `REGEX-LOWER-1` |
| **006** build-smoke | last; it runs the others |
| **P1** tag debt | **DONE**, §3: four tags pushed, four images published |
| **P2** file the gaps | **DONE**: `MODE-CLI-1`, `SPLIT-EMPTY-1`, `FS-WALK-1` |
| **P3** wire refute-crux into CI | **DONE**, §3 |

## 5. Gates, measured at v0.14.92 (the tip of this session's work)

**Re-measure, do not assume, and re-measure THIS SECTION and not only §1.**
Finding 13 is that these rows are independent claims that rot on their own
schedule: two of them were false for two days while §1 was accurate. Every
figure below was taken at v0.14.92 **except the one that says otherwise in its
own row**, which is `stack test`: nothing under `compiler/` changed in v0.14.92,
so it was deliberately not re-run and its row now says so rather than carrying a
figure forward under a new version's heading. Carrying figures forward under a
heading that implies they were re-taken is precisely finding 13.

**All of it is macOS/aarch64 and none of the v0.14.92 work has run on Linux
yet**, which is finding 10's caveat and finding 12's: every measurement needing a
proof, and every measurement of an encoding, is macOS-only until CI says
otherwise. `proc_merge.llmll` is the newest thing with a platform-shaped risk in
it, since it spawns `/bin/sh` and depends on the child's buffering, and the
buffering is the one thing the fixture deliberately does not assert.

| Gate | Figure |
|---|---|
| `stack test` | **NOT RE-RUN at v0.14.92 and it does not need to be**: nothing under `compiler/` changed, only the two version strings the banner gate compares. Last measured at v0.14.91: **1666 examples, 0 failures**, from 1656, the +10 being JSON-SCALAR-1 and PROC-MERGE-1's tests and the delta matching exactly what says none of them silently skipped |
| `pytest scripts/tests/` | 196 passed, 1 skipped |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 80 passed, 0 failed **on macOS, with a solver on `PATH`**. On Linux CI it scored **2 passed / 78 failed** until the job learned to build one: finding 12 |
| [`refutecrux.llmll`](../../tools/refute-crux/refutecrux.llmll) (the port) | 80 passed, 0 failed, 71s. **Has never run on Linux at all**: its CI step sits after the shell gate, which failed first |
| [`refute_crux_cover.py`](../../scripts/refute_crux_cover.py) | **16 cells + 3 negative controls, all ok at v0.14.91.** Cell 11, "bogus flag injected", is the one that grades the `c-flags` path JSON-SCALAR-1 rewrote, so the port's agreement with the reference is checked where the change actually landed rather than only in aggregate. **`--gate` is the PORT BINARY and `--llmll` is the COMPILER**, not the other way round; the shell reference is not an argument at all. See §7. **The "~7 min" was right and the "~80 min" that briefly replaced it was WRONG, from a contaminated measurement.** The ~80 min figure was taken from a run competing with four stalled probe processes, which was not noticed until later. A clean run on the same host took **~8 min**, and CI runs the same 16 cells in **324s** (run 31275114285). Roughly 6-10 min is the figure; the per-cell arithmetic that produced 80 was extrapolation from a poisoned sample |
| [`json_scalar.llmll`](../../scripts/build-smoke/json_scalar.llmll) | executed by `build_smoke.sh`; one line, 7 cells, of which the two `err` cells are the assertion. Mutation-checked (finding 14) |
| [`proc_merge.llmll`](../../scripts/build-smoke/proc_merge.llmll) | executed by `build_smoke.sh`; 2 lines, merged plus a split control. Mutation-checked (finding 14) |
| [`doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh) | 15 doc-claim(s) match, exit 0. **NEEDS NO SOLVER, and the row that first stood here said it did.** One fixture carries `@cmd: verify {file}`, which is where the claim came from, but its expectation is `check-error:call to unknown function`: a name-resolution failure reached before any VC is built. Measured at 15/15 under a PATH holding neither `fixpoint` nor z3, and CI agrees without being asked, running both doc-claims steps three steps before `fixpoint` reaches `PATH`. So this stays one of the gates finding 12 calls "decides without a proof" |
| [`docclaims.llmll`](../../tools/doc-claims/docclaims.llmll) (the port) | 15 match, exit 0, ~40s. Identical to the reference line for line with blank lines stripped from BOTH sides; see §3 step 5 for why that phrasing and not "byte-identical". **Has never run on Linux** |
| [`doc_claims_cover.py`](../../scripts/doc_claims_cover.py) | **17 cells + 3 negative controls, all ok at v0.14.92**, ~2 min on macOS/aarch64. **`--gate` is the PORT BINARY and `--llmll` is the COMPILER**, the same trap as `refute_crux_cover.py` and the same answer: §7. Cell 11 compares the DECISION only, deliberately, the reference's captured output there being bash's own diagnostic text. **It went RED on its first Linux run and the defect was in the COMPILER**, not in either implementation: finding 15 |
| [`doc_path_lint.py`](../../scripts/doc_path_lint.py) | **935 citations in 170 living files, all resolve** (916 at v0.14.91). **The figure moved twice while this row was being written and the second move is the instructive one**: it read 929 until `rfc-genre-and-naming.md` was committed, because the lint's file list is `git ls-files '*.md'` and an UNTRACKED document is invisible to it. So a doc-quality gate cannot see the document you are currently writing, which is exactly when you want it to. It also counts **prose** citations only, stripping markdown link targets first, so adding four `[label](path)` links to this file moved the count by zero |
| [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | 39 passed, needs a rebuilt sequencer via `--driver` |
| [`wave_cover.py`](../../scripts/wave_cover.py) | 7 passed, needs `--wave` |
| [`version_gate_cover.py`](../../scripts/version_gate_cover.py) | 14 passed, needs `--gate`. **The "14 passed" this table used to carry at `268df95` was NOT true at `268df95`**: the cover pinned `v0.14.87` and had been failing 5 cells since `d6e9f01`. Finding 13 |
| [`version_gate.sh`](../../scripts/version_gate.sh) | PASS at 0.14.92 |
| [`build_smoke.sh`](../../scripts/build_smoke.sh) | PASS, all stages including the new capture-encoding one. **Also not true at `268df95`** — its last stage runs the cover above, so it had been failing since `d6e9f01` too. Finding 13 |

**Rebuilding the port**, which several of these need:

```
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
cd tools/refute-crux && llmll build refutecrux.llmll -o <outdir>
```

Then run it from a scratch directory with an absolute `--root`, because a
console program writes `<module>.event-log.jsonl` into its working directory:

```
python3 -c "import sys; sys.stdout.write('x\n'*4000)" \
  | <outdir>/.../refutecrux --root <repo> --subject <llmll binary> --work <scratch>
```

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

7. **TOOL-RFC-002's feasibility read was WRONG, and that is the campaign's
   most useful result so far.** Rev 0 concluded "nothing here is BLOCKS" and "no
   new gap was discovered". Building it found four defects. **A feasibility
   table enumerates what the language HAS; the defects are in what it DOES.**
   Treat any future RFC's §4 as a list of things to go and try, not as a
   clearance. RFC §5 keeps the wrong conclusion quoted above the correction.

8. **Two of the four fail SILENTLY, and that is what cost the time.**
   `JSON-SCALAR-1`: `(json-get-string x "")` on a scalar answers `""`, so the
   port ran its whole corpus with the flags dropped and reported 30 passed / 50
   failed, where 50 is exactly the count of flagged cases. It type-checks, it
   verifies, no gate sees it. `CAPTURE-ENCODING-1` is silent in the other
   direction: output looks present but is wrong bytes.

9. **`bug` vs `language gap` has a repository convention: the roadmap's `[CT]`
   and `[SPEC]` tags** (legend at roadmap `:13-14`). `[SPEC]` means closing it
   changes what the language IS. `FD-CAPTURE-1` and `CAPTURE-ENCODING-1` are
   `[CT]` bugs; `JSON-SCALAR-1` and `PROC-MERGE-1` are `[CT][SPEC]` gaps and
   campaign §9 makes their SHAPE language-team's call, not the porter's.
   **Do not settle those two at the keyboard.**

10. **Every encoding measurement in this record is macOS-only.** v0.14.86's
    history is that macOS GHC resolves UTF-8 under every `LC_ALL`, which is why
    a gate "could not fail where it ran" and `main` was red for two days. So
    `CAPTURE-ENCODING-1`'s `codepoint mod 256` finding has no Linux datapoint,
    and getting one is an argument for merging BEFORE fixing it.

11. **The workarounds for two gaps were pre-marked for removal, and they are ALL
    now removed.** `CAPTURE-ENCODING-1`'s pair went with v0.14.90: the port
    writes a real `→` and `refute_crux_cover.py`'s normalisation line is gone, so
    the two implementations' labels are COMPARED rather than reconciled.
    `json-string-value` went with v0.14.91. **The pre-marking paid off exactly as
    intended**: closing each row was a small edit at sites that named themselves,
    not an audit. 001 is untouched by all of this, its scanner being
    `REGEX-LOWER-1`/`SPLIT-EMPTY-1`.

    **The deleted helper was also WRONG, which nobody had noticed and which the
    removal turned up.** It stripped the outer quotes off `json-serialize`, and
    the emitted `jsonQuote` escapes every character above `~` as `\uXXXX`. So a
    flag carrying a non-ASCII character came back as six literal characters:
    the port would have mangled exactly the class of character v0.14.90 was cut
    to fix. A workaround is not a smaller version of the fix, and this one had a
    second defect hiding inside the first.

12. **The `spec-roundtrip` job had no solver, and nothing noticed because no
    gate in it had ever needed one.** `llmll verify` proves nothing by itself:
    it shells out to `fixpoint`, which shells out to z3, and absent either it
    exits **3** — "solver unavailable (proof did not run)",
    [`Main.hs:1386`](../../compiler/app/Main.hs). The job set up Stack and
    nothing else from the day it was written and ran green in ~2 minutes the
    whole time, because `doc_claims_gate.sh`, `build_smoke.sh` and
    `spec_roundtrip.py` all decide without a proof. The refute-crux gate P3
    wired in is the first that cannot, and its first Linux run scored **2 passed
    / 78 failed**, every failure exit 3.

    **The two that passed are what identify the cause rather than leaving it
    inferred**: they are the only two whose verdict is reached BEFORE the solver
    (a capability refusal and a coverage threshold). So this was an absent
    toolchain, not a verification regression, and not the encoding failure
    finding 10 predicted.

    **Sibling of finding 6, one turn further on.** A gate that is not wired in
    decides nothing; **a gate wired into a job that cannot run it decides
    nothing either, and says it did.** The script had a `jq` preflight and no
    `fixpoint`/`z3` one, so it printed `78 frozen verdict(s) diverged` when zero
    had diverged — the same silent-wrong-answer class as finding 8, in a gate's
    own summary line. Fixed three ways: the job apt-installs z3 and builds
    `fixpoint` from [`scripts/fixpoint.stack.yaml`](../../scripts/fixpoint.stack.yaml)
    (the Dockerfile's pin, cached on that file's hash), and the gate now refuses
    to grade verdicts it cannot decide.

    **Generalise finding 10 while you are here.** It says every ENCODING
    measurement in this record is macOS-only. So is every measurement that
    needed a proof, for the same reason, and this is what that costs.

13. **A cover that pins a literal version rots at the next release, and §5's
    own figures rotted with it.** `version_gate_cover.py` hardcoded `v0.14.87`
    in five cells. The banner moved at `d6e9f01` (v0.14.88) and again at
    `c7c057a` (v0.14.89), the cover was added at `7d1de03` and never touched
    since, so from `d6e9f01` onward those cells could not find their anchor —
    and `build_smoke.sh`, whose LAST stage is that cover, failed with them.

    **§5 claimed both were passing at `268df95` and neither was.** Those figures
    were carried forward from an earlier measurement rather than taken at the
    commit they were stamped with, which is the exact failure this record warns
    about in its own §1 and had already committed twice. **Re-measuring §1 is
    not enough; §5 is a table of claims and each one rots independently.**

    **The irony is worth keeping.** V13 is the cover's negative control and its
    comment reads: "A gate that failed here would be pinning a literal version
    rather than checking that the sites agree, which is the anti-hardcoding
    property `crux-validate-subject-hardcoded` exists for one directory over."
    The cover asserting that the gate does not pin a version pinned one itself.

    **The one thing that worked is the thing to keep.** The cells did not go
    vacuously green: `edit`'s `want` reports "this cell would test nothing" and
    FAILS. A mutation harness that cannot find its anchor must fail, never skip,
    or a rotted cover reads as a healthy one. `BANNER` now comes from
    `LLMLL.md` line 1, the same place `version_gate.sh` reads it.

14. **A new gate is a claim, and the claim is that it can FAIL. Both v0.14.91
    fixtures were mutation-checked, and one of the two checks changed what the
    fixture asserts.** The cheap way to do it is to mutate the GENERATED Haskell
    in an already-built fixture project and rebuild that project alone, rather
    than mutating the compiler and paying a full rebuild per probe.

    `proc_merge.llmll`: making the merge unconditional (`errH <- return outH`)
    flips the split control to `OUT=n|ERR=n`, so the gate rejects it. Note the
    flip is not the one predicted: the expectation was `OUT=y`, but under an
    unconditional merge the split *stderr* file is never opened at all, so the
    read errs and BOTH markers go missing. The gate still fails, which is what
    was being tested, and the predicted-versus-actual gap is the reason to run
    the probe rather than reason about it.

    `json_scalar.llmll`: making `json-as-string` answer `Right ""` on a
    non-string and dropping `json-as-int`'s lexeme guard flips **exactly the two
    refusal cells**, `X-AS-INT` and `N-AS-STR`, while all three value cells stay
    correct. **So the three value cells alone would have caught neither
    mutation.** That is measured support for the fixture's own claim that its
    refusals are the assertion, and it is the kind of statement usually made on
    intuition and left unchecked.

15. **`TOOL-ENCODING-1` BITES, IT BITES TOTALLY, AND THE NEGATIVE CONTROLS ARE
    WHAT CAUGHT IT.** 003's cover went red on its first Linux run. The defect is
    in the SUBJECT: `llmll` decodes `.llmll` source through `TIO.readFile`, which
    takes the ambient locale, and the cover scrubs the environment so its two
    sides are asked the same question, which hands the compiler **no locale at
    all**. On Linux that is POSIX, and all 15 fixtures failed with
    `hGetContents: invalid argument (cannot decode byte sequence starting from
    194)` — `0xC2`, a UTF-8 lead byte.

    **The census that roadmap row has been asking for is now taken, and the
    answer is worse than "non-empty": 15 of 15**, `§` and `—` in the `@doc` and
    `@claim` headers. For that directory the firing population is total.

    **Cells 1-13 all reported `ok`.** Both implementations failed and failed
    identically, so every mutation cell still AGREED. What reddened was the three
    negative controls, which require both sides to PASS an unmutated tree. **A
    battery of mutation cells alone would have gone green while the compiler
    could not read a single fixture**, which is the strongest argument this
    campaign has produced for negative controls, and it is worth more than the
    controls' usual framing as a sanity check on the harness.

    Worked around by pinning `LC_ALL=C.UTF-8` on both sides, pre-marked for
    removal when the row closes. **The repair NOT to make is dropping the
    scrubbing**: that trades a measured compiler defect for an unmeasurable
    comparison, and re-introduces the two-different-worlds bug the cover already
    fixed once.

    **Finding 10 generalises again.** It said every encoding measurement here is
    macOS-only; finding 12 added every measurement needing a proof. This is the
    first time the macOS blindness hid a defect in the COMPILER rather than in a
    gate, and it stayed hidden through a full local green run: 17/17 with no
    locale set, because macOS GHC resolves UTF-8 under every `LC_ALL`.

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
- **`stack exec` outside a stack project silently retargets the GLOBAL one.**
  `tools/refute-crux` has no `stack.yaml`, so `stack exec llmll --` there
  resolves against `~/.stack/global-project`, whose resolver is not the
  compiler's. On Linux CI that meant installing **GHC 9.10.3** before answering
  `Executable named llmll not found on path`. The `ghc-toolchain` toolchain-diff
  warning printed during that install is NOT the failure and says so itself
  ("Don't worry! This won't affect your ghc in any way") — it is the symptom of
  a GHC install that should never have started. The repo-root-binary hazard one
  step further on: not the wrong compiler, no compiler. Use the absolute
  `$(cd compiler && stack path --local-install-root)/bin/llmll`, which is what §5
  already prescribes.
- **Run `doc_path_lint.py` on its own line**; piping to `tail` takes `tail`'s
  exit status.
- **`fd 1 == PIPE` on a generated console program is NORMAL and is not evidence
  of anything.** It was read here as proof that a stalled probe was blocked on
  the launching harness's plumbing, and a wrong conclusion was written down on
  that basis. Every `console` program redirects its own stdout into a
  `captureStdout` pipe and hands the saved original to a later fd: `lsof` on a
  healthy run shows `0r` the stdin file, **`1` a PIPE**, `2w` and `4w` the real
  output file, `5` and `6` the capture pipe's ends. **Read the whole fd table,
  not one row.** What actually distinguishes a hang is CPU TIME that stops
  accumulating: `ps -o time=` frozen across a 90-second sample is the signal,
  and `%cpu` alone is not, since it decays toward 0 on a merely idle process.
- **`pgrep -f` returning nothing is not proof of absence, and a 0-byte log is
  not proof of death.** A check for the running cover returned zero while `ps`
  showed it alive: the process had not spawned yet, the wrapper still being
  inside `stack path`. Python also block-buffers stdout to a file and writes
  nothing until it exits, which was already known this same session and applied
  anyway. Two absent signals were read as "the job died" when it was starting
  normally. **Wait, then use `ps`.**
- **EVERY COVER IN THIS CAMPAIGN TAKES `--gate` AS THE PORT AND `--llmll` AS THE
  COMPILER**, and `doc_claims_cover.py` is the second to do it. The convention is
  now consistent across the covers, which makes it easier to get wrong once and
  then twice, not harder: the names read as the opposite assignment in both.
  The bullet below is the incident that named it and it applies unchanged.
- **`refute_crux_cover.py`'s two arguments are not what their names suggest, and
  §5 used to say only "needs `--gate` and `--llmll`", which is exactly enough
  rope.** `--gate` is the **refutecrux PORT BINARY**, executed directly as
  `[gate, "--root", ...]`; `--llmll` is the **compiler**, passed on as
  `--subject`. The shell reference is not an argument at all: `run_shell` invokes
  the copy inside the scratch tree it builds. Passing
  `--gate scripts/refute-crux-gate.sh --llmll <port>` reads as the obvious
  assignment, type-checks as far as the filesystem is concerned, and hangs;
  it cost a ten-minute timeout before the workflow file settled it
  ([`version-gate.yml:273`](../../.github/workflows/version-gate.yml)). §5 now
  names the roles. Same lesson as the tag-mechanism doubt in §3: the question was
  answered by what CI already does, not by reading the script's argparse.

## 8. Debt, deferred and unrelated

- **A CI toolchain image is proposed and NOT built.** The user asked whether one
  image could carry the tooling instead of the job rebuilding it. Measured at
  run `31239115894`: `Build liquid-fixpoint` 6.0 min, the port step 5.2, `Build
  llmll` 1.3, z3 0.2, jq under 5s, job total 16.2. So **jq and z3 are not the
  cost and fixpoint is already solved by the cache** — it only kept rebuilding
  because `actions/cache` does not save on a failed job and no job had yet
  succeeded.

  **THE PORT STEP'S COST IS MISATTRIBUTED IN THIS BULLET AND THE CORRECTION
  MATTERS FOR WHAT AN IMAGE WOULD BUY.** It says the step's ~5 min is
  GENERATED-project builds (`async`, `regex-tdfa`, which the compiler does not
  depend on). Measured from step log timestamps at run 31275114285, the 411s
  splits **10s generate-and-build / 324s `refute_crux_cover.py` / 78s the live
  80-case corpus**. Those deps sit in the restored `~/.stack` snapshot db and
  cost ~10s. **So the port step is solver time, not build time, and baking a
  snapshot db into an image would not touch it.** The image's remaining case is
  determinism, not speed. **CONFIRMED once one did**: the next two runs show
  `Build liquid-fixpoint: skipped` and the job at **10.9 min against 16.2**, so
  the image's remaining SPEED case is roughly fifteen seconds (jq plus z3) and
  should not be argued on that basis. The real arguments for an image are
  determinism (cache entries
  evict at 7 days, and the Stack key is `hashFiles(compiler/stack.yaml)`, so a
  resolver bump silently restores the 6-minute tail) and baking the lts-22.43
  snapshot db, which would bite into the port step's 5.2 min of
  GENERATED-project builds (`async`, `regex-tdfa`, which the compiler does not
  depend on). **It cannot be the published release image**: RFC §8 decision 2
  requires the subject be built from source, or the 41 refuted cases go
  vacuously green. It would be a second, CI-only image.
- ~~**The port has no solver preflight and the reference now does.**~~ **CLOSED
  in v0.14.91**, authorized by the user. `refutecrux.llmll` now probes `which
  fixpoint` and `which z3` as two states between `Boot` and the first manifest
  read, and refuses by name with the reference's message and exit 1. Verified
  both ways round: hiding `fixpoint` alone reports `missing: fixpoint`, hiding
  z3 alone reports `missing: z3`, and the full corpus still scores 80 passed /
  0 failed with the two extra steps in the budget.

  **The mechanism is the exit code and nothing else**, which is what makes it
  robust: 0 is found, 1 is `which` running and not finding it, and 127 is
  `code-in`'s score for an `RErr`, which is what a spawn failure publishes if
  `which` itself is absent. Every non-zero case refuses, so an unusual
  environment fails safe rather than grading verdicts it cannot decide. Output
  goes to `/dev/null` twice: a path that always exists, so the probe cannot fail
  for a reason unrelated to the solver, and the repetition exercises
  PROC-MERGE-1's merge where the bytes are discarded anyway.

  **THIS ENTRY DESCRIBED THE PRE-FIX BEHAVIOUR WRONGLY, AND THE TRUTH IS WORSE
  THAN EITHER GUESS. Measured: the pre-fix port DEADLOCKS.** The entry predicted
  it "would still grade 80 undecidable cases and report them diverged". Run
  against the actual pre-fix binary with `fixpoint` and z3 hidden and nothing
  else changed, it instead stops dead:

  | | pre-fix, no solver | with solver |
  |---|---|---|
  | output | **1882 bytes, frozen** | 7432 bytes, 99 report lines |
  | CPU accumulated | **1.11s, not moving over 90s** | completes |
  | state | sleeping, 0% | exit 0, 80 passed / 0 failed |

  **Reproduced five times, all at exactly 1882 bytes**, with stdin from a FILE
  and stdout to a FILE and the process detached, so it is not the launching
  harness. A 300-step run completes normally (exit 70), which locates the
  deadlock near step ~1882 of the ~1997 a full run takes: it dies just before
  finishing, having emitted no report, because the report only flushes at the
  end.

  So the two `oracle` implementations did not merely disagree about a number.
  One refused by name in under a second; the other **hung indefinitely**. The
  preflight is what stops that being reachable, and this is the strongest
  argument for it, not the one originally recorded. The deadlock itself is left
  unexplained and unfixed: it is now unreachable through the gate, and chasing
  it belongs with whoever next has reason to run a console program of that
  length against a deliberately broken toolchain.
- **No parse gate over design-doc frontmatter.**
- `HDelegate`, `HDelegateAsync`, `HDelegatePending`, `HConflictResolution` reach
  the HOLE-STATUS-SIBLING catch-all unpinned by any test.
- DRIVER-LL 4d is parked; 4f, program unification and stage A stay deferred.
  Five of the eight remaining callerless rows are 4d's.
