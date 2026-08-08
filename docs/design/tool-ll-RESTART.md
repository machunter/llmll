---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, 2026-08-08. Green and fully released. The authority on WHERE THE WORK IS. The authority on WHAT THE STANDARD SAYS is llmll-tooling-campaign.md; when they disagree about the standard the campaign wins, when they disagree about state re-measure. DRIVER-LL Phase 4 sub-phase 4e is COMPLETE and its record (driver-ll-phase4-RESTART.md) is closed history. The active campaign is TOOL-LL: two ports of six landed as oracles, all three prerequisites cleared. THE MERGE IS DONE, main is green at 2d27c0d (v0.14.90), and all three tags are pushed with all three images published (:latest == v0.14.90's digest). Getting the merge green took three fix-forward commits for three defects it exposed and macOS could not: no solver in CI (finding 12), `stack exec` outside a stack project (§7), and a version cover that pinned the version it exists to unpin (finding 13). CAPTURE-ENCODING-1 is then SHIPPED in v0.14.90 and both of its workarounds are gone. Next is the two [CT][SPEC] shape calls, which are language-team's and NOT the porter's, then 003 RFC-first."
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

**`main` IS GREEN, at `2d27c0d` (v0.14.90), and getting the merge itself green
took three fix-forward commits.** The merge's first CI run failed, and so did
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
`92f501d4`, `v0.14.90` `0720f75d`, and `latest` resolving to `0720f75d` — the
same digest as `v0.14.90`, which is what says the ordering rule below worked.

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
4. **`JSON-SCALAR-1` and `PROC-MERGE-1` behind a language-team shape call**,
   per finding 9.
5. **Then 003, RFC-first.**

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
| **002** refute-crux gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-002](tool-rfc-002-refute-crux.md). 80/80 verdicts, agrees with the reference. Found `FD-CAPTURE-1` (BLOCKS, fixed), `JSON-SCALAR-1`, `PROC-MERGE-1` |
| **003** doc-claims, **004** doc-archive | not started; **next** |
| **005** doc-path-lint | blocked on `REGEX-LOWER-1` |
| **006** build-smoke | last; it runs the others |
| **P1** tag debt | **DONE**, §3: four tags pushed, four images published |
| **P2** file the gaps | **DONE**: `MODE-CLI-1`, `SPLIT-EMPTY-1`, `FS-WALK-1` |
| **P3** wire refute-crux into CI | **DONE**, §3 |

## 5. Gates, measured at `268df95`

**Re-measure, do not assume.** Every figure below was taken at `268df95` with a
clean tree. **All of it is macOS/aarch64 and none of it has run on Linux**,
which matters more than usual right now: see finding 10.

| Gate | Figure |
|---|---|
| `stack test` | 1656 examples, 0 failures |
| `pytest scripts/tests/` | 196 passed, 1 skipped |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 80 passed, 0 failed **on macOS, with a solver on `PATH`**. On Linux CI it scored **2 passed / 78 failed** until the job learned to build one: finding 12 |
| [`refutecrux.llmll`](../../tools/refute-crux/refutecrux.llmll) (the port) | 80 passed, 0 failed, 71s. **Has never run on Linux at all**: its CI step sits after the shell gate, which failed first |
| [`refute_crux_cover.py`](../../scripts/refute_crux_cover.py) | 16 cells, 3 negative controls, ~7 min; needs `--gate` and `--llmll` |
| [`doc_path_lint.py`](../../scripts/doc_path_lint.py) | 916 citations, all resolve |
| [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | 39 passed, needs a rebuilt sequencer via `--driver` |
| [`wave_cover.py`](../../scripts/wave_cover.py) | 7 passed, needs `--wave` |
| [`version_gate_cover.py`](../../scripts/version_gate_cover.py) | 14 passed, needs `--gate`. **The "14 passed" this table used to carry at `268df95` was NOT true at `268df95`**: the cover pinned `v0.14.87` and had been failing 5 cells since `d6e9f01`. Finding 13 |
| [`version_gate.sh`](../../scripts/version_gate.sh) | PASS at 0.14.90 |
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

11. **The workarounds for two gaps were pre-marked for removal, and half of them
    are now removed.** `CAPTURE-ENCODING-1`'s pair went with v0.14.90: the port
    writes a real `→` and `refute_crux_cover.py`'s normalisation line is gone, so
    the two implementations' labels are COMPARED rather than reconciled. **The
    pre-marking paid off exactly as intended** — closing the row was a two-line
    edit at sites that named themselves, not an audit. Still outstanding:
    `json-string-value` in the port disappears when `JSON-SCALAR-1` closes. 001
    is untouched by this round, its scanner being
    `REGEX-LOWER-1`/`SPLIT-EMPTY-1`.

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

## 8. Debt, deferred and unrelated

- **A CI toolchain image is proposed and NOT built.** The user asked whether one
  image could carry the tooling instead of the job rebuilding it. Measured at
  run `31239115894`: `Build liquid-fixpoint` 6.0 min, the port step 5.2, `Build
  llmll` 1.3, z3 0.2, jq under 5s, job total 16.2. So **jq and z3 are not the
  cost and fixpoint is already solved by the cache** — it only kept rebuilding
  because `actions/cache` does not save on a failed job and no job had yet
  succeeded. **CONFIRMED once one did**: the next two runs show
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
- **The port has no solver preflight and the reference now does.** Finding 12's
  fix went into `refute-crux-gate.sh` only, so on a host without `fixpoint` or
  z3 the shell gate refuses by name while `refutecrux.llmll` would still grade
  80 undecidable cases and report them diverged. That is a real divergence
  between two implementations declared `oracle`, and it is recorded rather than
  quietly introduced: it does not fire in CI, because the job now has a solver
  before either step runs. Close it when the port is next touched — the
  preflight is `wasi.proc.run` on `which`, not new language surface.
- **No parse gate over design-doc frontmatter.**
- `HDelegate`, `HDelegateAsync`, `HDelegatePending`, `HConflictResolution` reach
  the HOLE-STATUS-SIBLING catch-all unpinned by any test.
- DRIVER-LL 4d is parked; 4f, program unification and stage A stay deferred.
  Five of the eight remaining callerless rows are 4d's.
