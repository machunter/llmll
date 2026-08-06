---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE. Current as of 2026-08-06, third session. Sub-phases 4a and 4b are SHIPPED and SUB-PHASE 4c IS IMPLEMENTED AND MERGED to main: stages D, F and G ported, arriving as four commits on driver-ll-4c/stages-d-f-g and fast-forwarded onto main from 0d3242b. 4c HAD NEVER BEEN THROUGH CI at the branch tip, zero runs, and pushing a branch runs nothing: version-gate.yml fires only on push to main and on pull requests targeting main. THE PR WAS DECLINED and 4c merged to main directly, AND NO ACTIONS RUN FIRED: 4c IS ON MAIN AND HAS NEVER BEEN THROUGH CI, because GitHub Actions is in a MAJOR OUTAGE measured at 2026-08-06 ~18:50Z. That is external and nothing in this repository is implicated, but the outage does not make the merge safe, it makes it unverified. THE RELEASE CEREMONY IS HELD until a run lands, since its tag push feeds docker-publish and that cannot run either. Section 1 gives the measurement. The proposal stands at Rev 12: Rev 10, plus the two amendments the port earned (section 9.2: 4c constructs ConditionUnmet, and F-20's tolerance is not at two sites), plus Rev 12 correcting the second of those to FOUR sites after the new test tier computed it. No revision changed what 4c does. A RELEASE CEREMONY IS NOW DUE: nothing was owed while 4c sat on a branch and the merge is what makes it owed. Of the four items open at session start, THREE ARE CLOSED: REGEX-LOWER-1 has a roadmap row (86b39db, and the row is wider than the finding was, the affected population being EIGHT names of which only one is executed), section 9.2 item 1 is amended at Rev 11, and the driver README is current at 3f229d8. The fourth, the v0.14.85 shipped row's uncorrected 120, is still deliberately uncorrected. NEW AND OPEN: task 28, widening stage-tag-count when K, L or M lands, which a test now asserts rather than a note. Still untouched: 4d through 4f, and the largest owed item in the phase is still a fresh census for proposal §3.6's table, whose keys are knowingly stale. Delete when Phase 4 closes."
date: 2026-08-06
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# DRIVER-LL Phase 4 — restart record

Read this first, then [`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) (**Rev 12**,
SETTLED), and for 4c specifically
[`driver-ll-phase4c-implementation-plan.md`](driver-ll-phase4c-implementation-plan.md), **whose
frontmatter is accurate and whose body is the running record of what actually landed**. Everything
else is downstream of those three.

**Thirty-second version.** **Sub-phases 4a and 4b are SHIPPED** (`2b82464` v0.14.85, `ba2f93d`
v0.14.87) and **sub-phase 4c is IMPLEMENTED and MERGED to `main`, with its release ceremony still
owed**: stages D, F and G are ported, and they arrived as four commits on
`driver-ll-4c/stages-d-f-g`. The proposal stands at
**Rev 12**: Rev 10 plus the two amendments the port earned, plus Rev 12's correction of one of
them. No revision changed what 4c does.
The first 2026-08-05 session took it from Rev 5 to Rev 9, ran the
harness leg, found 4a blocked at the process boundary, specified and shipped the capability that
unblocked it (`PROC-BOUNDARY-1`, v0.14.85), ported 4a against it **with no shim**, re-measured §3.5,
and ported 4b. Three releases shipped: v0.14.85, v0.14.86 and v0.14.87. The second session pushed the
backlog, ran the 4c harness leg, and folded Rev 10. The third session built 4c and merged it.

**The number that matters at restart: 4c is on `main` and has zero CI runs.** Not zero green runs,
zero runs. The merge was a clean fast-forward of `main` from `0d3242b` onto `6ecd68e` and **GitHub
Actions never evaluated it.**

**The measurement, because this is the second time in one phase that a gate was assumed rather than
observed.** For `6ecd68e`, `actions/runs?head_sha=` returns `total_count: 0`. The only check suites
on the commit are the Cursor app's and GitHub Pages', both created at 18:24:34Z, and **there is no
GitHub Actions suite at all**. Actions is enabled on the repository with `allowed_actions: all`,
[`version-gate.yml`](../../.github/workflows/version-gate.yml) is `active`, its trigger at `:34-38`
is `push` to `main`, it declares no `workflow_dispatch`, and the head commit message carries no
`[skip ci]`-family token. Every precondition for a run holds and no run exists.

**The cause is a GitHub Actions outage, and the first hypothesis was refuted by its own test.** The
guess was that the same SHA having been pushed to `driver-ll-4c/stages-d-f-g` ninety seconds earlier
left Actions unwilling to re-evaluate it on the `main` push. **That is wrong.** `a474e26`, a fresh
SHA that had never been a branch head, was pushed to `main` alone and produced **zero runs across two
minutes of polling**, which eliminates the push shape entirely. `githubstatus.com` then gives the
actual cause: at 2026-08-06 ~18:50Z, **`Actions` and `Pages` are both in `major_outage`**. Nothing
about this repository, this branch or this merge is implicated.

**The operational consequence stands regardless of the cause.** `main` carries an unexercised 4c and
will keep carrying it until Actions recovers and a fresh SHA is pushed. **The outage does not make
the merge safe; it makes it unverified**, and those are different claims.

**What this cost, and it is a method point rather than an incident.** The record asserted "4c's first
CI run is the push that merged it" one commit before this one. That was an inference from a trigger
declaration, not an observation of a run, and it was wrong within ten minutes. A declared trigger is
not a run, in the same way `build_smoke.sh` stage 5b printing PASS was not an encoding test.

**When a run does land, `build_smoke.sh` stage 8 is the one to read**: it builds the sequencer and
drives the acceptance cover against the **built binary**, 4c moved its banner and its cover count
(`b9904a6`), and no CI run has ever seen that stage in that state.

**Rev 10 replaced 4c's acceptance clause, and a restarting session must not re-derive the old one.**
The clause "stage E's Phase 3 pins reproduce over D's own output" was **measured unsatisfiable under
both readings**: 7 for 7 over the committed pair, **0 for 7 over stub-D**, and unpinnable in principle
over live output, the pins being agreement statistics between two stochastic extractions. §9's table
now carries the replacement, which inverts the direction of the check: the already-ported downstream
stages **run** over 4c's output rather than pinned values reproducing over it. §9.2 item 3 gives the
measurement.

**The one thing not to re-derive.** Closing the capability before porting is what bought the no-shim
result. A shim would have sat between the rig and the thing under test and mediated every 4a
acceptance result, which is the one property 4a exists to establish. The same instinct is why §9.1
settles what 4b may and may not invent.

## 1. Where the work is

**Sub-phase 4c is merged to `main`**, having arrived as four commits on
`driver-ll-4c/stages-d-f-g` and fast-forwarded from `0d3242b`. In landing order: `36f6476`
(`shape.llmll`, the proved channel, four body-faithful defs), `3dc0162` (the registry tables,
behaviour-preserving), `40d5958` (the 4c plan and running record), `b9904a6` (the sequencer bodies,
the cover extension and the stage-8 banner), and this record's own reconciliation commit on top.

**`main`'s own history is unchanged from the second session's close.** The four commits outstanding
then (`ba2f93d..d15b2ff`) were pushed and **CI came back green on both `version-gate` and
`docker-publish` at `d15b2ff`**; `43ddb95` (Rev 10 plus the new rig cell) and `8cd05ee` (doc-lead
reconciliation of `INDEX.md` and two roadmap rows) landed after; `0d3242b` is the restart record's own
Rev 10 commit.

**The pre-merge CI question was put and answered: no PR, merge. The consequence arrived immediately
and is worse than the one that was weighed.** The risk discussed was a red `main`; what happened is
an **unexercised** `main`, which is the same failure wearing the costume of success. `main` sat red
for two days earlier in this phase on a defect no macOS run could
reach, because `build_smoke.sh` stage 5b is a structural no-op here, GHC on this platform returning
UTF-8 from `getLocaleEncoding` under every locale; the stage now prints **NOT EXERCISED** on Darwin
instead of a PASS it has not earned. And the 4c port then produced two defects that no static gate
could reach either, only a run of the built driver (§5). Local gates are not the gates, twice over,
and 4c's first real gate ran with the code already on `main`.

**The installed binary must be at 0.14.87 and there is no bump in 4c.** The block below is a
**verification step rather than a pending action**, and it is still worth running first: the failure
it guards against recurs whenever the pins move and the binary does not.

```
(cd compiler && stack build)
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
llmll version                          # expect 0.14.87
python3 -m pytest scripts/tests/ -q    # expect 132 passed, 1 skipped
python3 scripts/doc_path_lint.py       # expect ~860 citations, all resolve
bash scripts/version_gate.sh           # expect PASS at v0.14.87
```

The pytest figure moved 131 → 132 at `43ddb95` (the new stage-D cell, §7) and 4c did not move it
again. **The citation count in this block was wrong before Rev 10 and is approximate on purpose**: it
read 865, measured 859 at the second session's start, 860 after Rev 10, 863 at the branch tip and
**865 once this record's own edits land**. Treat "all resolve" as the gate and the count as
informational, since any prose edit anywhere moves it, this one included and demonstrably so.

Gates measured at the branch tip: the acceptance cover **39 passed, 0 failed** (31 before), Haskell
**1651 examples**, `refute-crux-gate.sh` **75 passed** (71 before), and every driver module SAFE.
`build_smoke.sh` runs **eight numbered stages** (plus 2a and 5b; the earlier "6 stages" in this
section was stale), the `LC_ALL=C` half NOT EXERCISED on macOS, which is not a failure. **All of these
are local measurements. None of them is a CI run.**

## 2. What Phase 4 is, in four sentences

Port the eleven agent-delegated stages (B, C, D, F, **G**, H, I, K, M, N, O) and the serial wave
into `tools/llmll-driver/` as `def-shell` orchestration; **six are ported, B, C and I at 4b and D, F
and G at 4c, and five remain: H, K, M, N and O.** Stage G was omitted from the campaign's
original list and is on the critical path, since it produces the input to G2 and to both of gate J's
disposition conditions. Acceptance is three clauses (proposal §2), not artifact reproduction, which
was measured unsatisfiable. The phase activates `fill.*` and `token.token-during`, which have had no
caller since v0.14.70.

## 3. Task queue

| # | Task | Role | State |
|---|---|---|---|
| 1 | Campaign doc §Phase 4 → Rev 5 | language-team | **done** |
| 2 | Harness items (a)(b)(c) | experiment-lead | **done** |
| 7 | Adjudicate F-1/F-2/F-3 | language-team | **done**, landed as proposal §3.5 |
| 8 | Python-side §3.5/§3.6 repair | experiment-lead | **done**, v0.14.84 (`aa08051`) |
| 3 | `FS-ENCODING-1` + `wasi.fs.copy` | compiler-engineer | **done**, v0.14.84 (`82a0772`, `0f2c22f`) |
| 6a | Release ceremony v0.14.84 | documentation-lead | **done** (`a182638`) |
| 9 | Harness leg for 4a: T7 test, the guarded manifest read, §10 cases 16–18 | experiment-lead | **done** (`c10081d`). 115 → 120 Python tests; findings F-9/F-10/F-11 |
| 10 | Two roadmap rows (`FS-STAT-1` re-scoped, `MATCH-CATCHALL-1`), `CLAUSE-INDEP-1` under the layer-3 row, two DRIVER-LL notes additions, one stale internal cross-reference | documentation-lead | **done** 2026-08-05, `docs/compiler-team-roadmap.md` + `INDEX.md` |
| 11 | Sub-phase 4a **plan**: module decomposition, acceptance instrumentation, eight measured findings | compiler-engineer | **done**, `driver-ll-phase4a-implementation-plan.md`. It found #4 blocked |
| 12 | `PROC-BOUNDARY-1`: `wasi.proc.args` + `def-main :status`. Proposal, row, ship, release | language-team → compiler-engineer → documentation-lead | **done, SHIPPED v0.14.85**. Proposal at Rev 3; no breaking change |
| 4 | **Sub-phase 4a: sequencer, manifest, resume gate, two halt channels. No stage bodies** | compiler-engineer | **done, SHIPPED** (`2b82464`). No shim. 15/15 cover, 6 refute-crux perturbations |
| 13 | Does the Python T7 mask like the port's did? | experiment-lead | **done**, answered NO by mutation. F-12/F-13. Cover is separable |
| 14 | Rev 8: settle the four held findings | language-team | **done**, all three predictions confirmed |
| 15 | Re-measure §3.5 at HEAD; it generated 4b's queue | experiment-lead | **done**, F-14–F-17. Refuted Rev 8's own stamp. Landed as Rev 9 |
| 5b | **Sub-phase 4b: stages B, C, I and the shared validation facility** | compiler-engineer | **done, SHIPPED** (`ba2f93d`). Cover 15 → 31 cells; `validate.llmll` SAFE |
| 16 | Release v0.14.87 + three doc repairs + two roadmap rows | documentation-lead | **done** (`5a4832c`, `1bc2965`). `PROC-TIMEOUT-1` filed, not fixed (§9) |
| 17 | **4c harness leg: three measurements** | experiment-lead | **done**. F-18/F-19/F-20. F-18 **refuted the brief that commissioned it**; F-19 eliminated §3.6's artifact-state reading; new rig cell, 131 → 132 |
| 18 | **Rev 10**: fold F-18/F-19/F-20, new §3.6.1 and §9.2, replace 4c's acceptance clause | language-team | **done** (`43ddb95`) |
| 19 | Reconcile `INDEX.md:74` and two roadmap rows to Rev 10 | documentation-lead | **done** (`8cd05ee`). `PROC-TIMEOUT-1`'s closure note discharged; it was half-discharged already |
| **5c** | **Sub-phase 4c: stages D, F, G** | compiler-engineer | **done, IMPLEMENTED ON A BRANCH, NOT MERGED** (`36f6476`, `3dc0162`, `40d5958`, `b9904a6`). Cover 31 → 39 cells; `shape.llmll` SAFE first attempt; four findings, three of which corrected the plan or its predecessor |
| **21** | **CI on 4c** | user | **STILL PENDING and BLOCKED EXTERNALLY.** The PR was declined, the merge push produced **no Actions run at all**, and the cause is a **GitHub Actions major outage** measured at 2026-08-06 ~18:50Z, not the push shape (§1). 4c is on `main` unexercised. Re-check `githubstatus.com`, then push a fresh SHA to `main` |
| **22** | **The release ceremony 4c owes**: version bump, CHANGELOG entry, DRIVER-LL roadmap row | documentation-lead | **PENDING and now DUE, 4c being merged** (§9). No compiler change in it, so it records a driver sub-phase and not a language movement |
| **23** | **`REGEX-LOWER-1` roadmap row** | documentation-lead | **done** (`86b39db`), and the row is wider than the brief was: `emitOp`'s fallback breaks **eight** names in `isOperator`, not one, and only `regex-match` has been executed. All eight have a zero in-tree firing population. Census before fix, on the `RESERVED-NAME-1` precedent |
| **24** | **§9.2 item 1 amendment** (4c constructs `ConditionUnmet`) plus the F-20 three-site amendment | language-team | **done, proposal at Rev 11.** Neither changes 4c's code. The F-20 amendment sharpened on execution: `:482`'s tolerance is over the **dispositions document**, not `core.json`, so the generalization is the shape and the n=0 null result covers two sites of three |
| **26** | Reconcile `INDEX.md` and the DRIVER-LL roadmap row to **Rev 11** | documentation-lead | **done** (`86b39db`). The 4c plan had no INDEX row at all and now has one; 4c's narrative and its version still ride with task 22 |
| **25** | [`tools/llmll-driver/README.md`](../../tools/llmll-driver/README.md) for D, F and G | compiler-engineer | **done** (`3f229d8`). Two of its counts were wrong and are measured now: the frozen verdict set is **31**, not 27, and the cover is **39**, not 31 |
| **27** | **A no-toolchain test tier for 4c** | compiler-engineer | **done** (`1973b80`), nine tests, pytest **132 → 141**. It found two things by being written: **the tolerance census is FOUR sites, not three** (Rev 11 was short by one), and **`stage-tag-count` is D-only while K, L and M are multi-invocation and unported** |
| **28** | **Widen `stage-tag-count` when K, L or M lands** | compiler-engineer | **PENDING, and asserted rather than remembered.** `test_driver_ll_4c.py` fails the moment one of the three is marked ported without the table moving (§6) |
| 20 | **Re-census proposal §3.6's table** | experiment-lead | **PENDING. The largest owed item in the phase** (§4) |
| 6b | Doc-lead pass at each sub-phase | documentation-lead | pending, runs after each |

## 4. The next action

**Wait out the Actions outage, get a run on `main`, read stage 8, then do the release ceremony.** 4c
merged with no PR in front of it, the merge push produced no run, and the cause is external (§1), so
`main` currently carries an unexercised sub-phase and every statement about 4c's correctness rests on
local gates alone.

**The ceremony is held on purpose and not merely deferred.** Its last step is a `vX.Y.Z` tag push,
which is what `docker-publish`'s publish job triggers on, and during the outage that job cannot run
either. Tagging a release into an outage produces a tag with no published image and no gate behind
it, which is a worse record than a release that waited. Order when Actions returns: fresh SHA to
`main`, read the run, **then** ceremony.

**The ceremony.** 4c is a feature and the pins are still 0.14.87 with no compiler change in them, so
it owes a version bump, a CHANGELOG entry and the DRIVER-LL roadmap row. One fact about it, checked
rather than assumed: `version_gate.sh` compares the five banner sites **to each other and to no git
tag**, so `main` at 0.14.87 with 4c in it is green and the ceremony is a **discipline obligation
rather than a gate**. That is exactly the condition under which a release quietly does not happen, so
it is queued as task 22 rather than left to the next green run to remind anyone.

**What 4c does not owe.** No change to what it does: the Rev 11 and Rev 12 amendments reconcile the
document to the port and move no code. No
compiler change: `json-array`, `json-get{,-string,-int,-bool}`, `list-{filter,fold,map,length,nth}`,
`range`, `string-char-at`, `string-to-int` and `wasi.fs.copy` all exist, checked and not assumed. The
one compiler item 4c produced, **`REGEX-LOWER-1`**, is a disclosure and a roadmap row rather than a
blocker: the port hand-rolls both pattern checks and says so at the site.

**Stage G is ported, so that hole is closed.** G was omitted from the campaign's original list (§2)
and produces the input to G2 and to both of gate J's disposition conditions, which is why the stage
enumeration was corrected. It landed in 4c with D and F.

**What proposal §9.2 settled, and the one place the port disagrees.** Rev 10 settles 4c in five
items and the port was built against them: D's iteration-`b` halt is `failed` (measured, §3.6.1);
`[V7-NO-PARTIAL]` and `[V7-ONLY-TWO]` are **sound for 4c unchanged** and were not widened, because
`verdict-of` takes no artifact set so the sibling-state question belongs at the call site; the
acceptance clause is replaced; the guarded-read population is **five, not two**; and the B-side
extraction has no downstream consumer, which the port reproduces rather than repairs. **Item 1 is
silent on one thing the port does**: `check_dispositioned:493` is `require_spec` rather than
`require`, so its halt is spec-defined and records `stopped`, and **4c therefore builds three of
`Outcome`'s four arms where 4b built two**. Item 1 records only that 4c constructs no
`PartialThenHalt`, which holds. `[V7-ONLY-TWO]` stays true as stated, being a property of
`verdict-outcome`'s codomain rather than an invariant of the port, so the shipped proved module's
prose was **left alone**: a later sub-phase's arithmetic does not go into a module that already
shipped. The barrier halt routes through the sequencer's `halt-with … ConditionUnmet` channel
instead, which is why `[V7-NO-STOP]` is not violated.

**Four things 4b settled that 4c inherited and 4d inherits in turn, so do not re-derive them:**

1. **The proved validation surface is two modules now, not one, and that is a divergence worth
   knowing.** `validate.llmll` holds 4b's presence-and-floor facility, whose `verdict-of` takes **no
   string**; 4c added `shape.llmll` for content shape, whose four defs take **only bools and ints**.
   Both earn subject-neutrality structurally rather than by review. §9.2 item 2's requirement held in
   the half that carries weight: **no proved post was changed and `validate.llmll` was not touched at
   all.** Its forecast did not: `validate.llmll:56-63` predicted "a second channel into this module"
   and the channel landed in a sibling module instead, which is strictly the more conservative of the
   two. That note is epoch-labelled "AT 4b" so it is not false, but a reader at 4d who looks there
   for the shape channel will not find it. `[V7-NO-HARDCODE]` refutes a validator fitted to one run's
   sizes and `[D7-NO-HARDCODE]` is its content-side counterpart, measured by
   `crux-shape-row-count-fitted`.
2. **Cite §3.5's halt sites by CONDITION, never by line number** (§3.5.1). Two of the nine
   spec-defined line numbers now point at sites with the **opposite** disposition, so a reader keying
   on the number lands on a plausible-looking site and nothing signals the miss.
3. **A validator where the reference has none is new behaviour and does not ride in on a port.**
   Stages I and O both have none; both are disclosed and both land at 4f.
4. **`PROC-TIMEOUT-1` is open** (§9). `wasi.proc.run`'s timeout does not fire, so a budget-overrun
   path is unreachable through the timeout. Rev 10 named the population and 4c has now written it:
   **D, F and G each invoke an agent**, so three more overrun halts exist and none of them is
   reachable. The roadmap row records it, and **no cover cell may claim to exercise them.**

**The largest owed item in the phase is a census, not a port.** Proposal **§3.6's table is knowingly
stale and is filed rather than broken**: its keys are line numbers, `:809` is now a `for` statement
inside `_pinned_sources`, and two conditions it files as post-write fire **before** their stage writes
anything. Rev 10 did not renumber it, because renumbering by inspection is exactly what produced the
bad Rev 8 stamp. Re-deriving it needs a fresh census over the write-before-halt ordering of every
stage. **This is owed work and not a trap**: a restarting session should read the table's argument (two
orthogonal axes that disagree somewhere) and distrust every line number in it.

**The method that has paid every time, six for six.** Every refuted mechanism claim in this phase was
a grep over the name a design document uses, where the code enforces the same obligation under a
different name one call frame away. The most recent was this proposal's own Rev 8 stamp, which used a
grep to correct a stale count and produced a wrong one. If a claim rests on a grep, execute it. If
the port disagrees with the proposal, execute the disagreement before writing the correction.

**Run experiment-lead before compiler-engineer.** Harness work generates the engineer's queue rather
than following it: it produced §3.5, then §3.6, then refuted Rev 6, then refuted Rev 8 and settled
what 4b needed, and then refuted the 4c acceptance clause. **Five times, five findings the port would
otherwise have hit mid-build.**

**The fifth was the strongest form, and it is a new failure shape for §5.** F-18 did not refute a claim
inside a document; **it refuted the brief that commissioned it.** The leg was sent out to decide
*which* of two readings of 4c's acceptance clause was satisfiable, and the answer was **neither**, so
the question presupposed a false dichotomy. A brief can be wrong in the same checkable way a design
claim can, and the same remedy applies: state the alternatives as measurable and let a null on all of
them be a permitted outcome. Recorded in proposal §15 rather than quietly replaced.

**A channel the earlier lessons do not cover: run the built thing.** Both defects the 4c port
produced were invisible to `llmll check`, to `llmll verify` and to the acceptance cover as it stood,
and only a run of the built driver found them. The provisioning `mkdir` was **described in a comment
and never issued**, so the copies and the rubric write targeted a directory `delegate-cmd` created
afterwards, and nothing halted because both writes are unchecked exactly as `shutil.copy2` is: both
extractor directories held only `PROMPT.md` and the logs. And the second invocation **re-entered
`Tmpl` rather than provisioning**, so extractor B got an empty working directory, which is the
blindness stage D exists to make structural, defeated by a phase transition. Both are cover cells C1
and C2 now. The general form is worth carrying into 4d: a proved module and a green cover establish
exactly what they quantify over, and **a phase graph that has never run is quantified over by
neither.** This is the same rule as "execute the grep", one level further out.

## 5. Sequencing lesson, paid for three times now

Experiment-lead work **generates** the compiler-engineer's queue rather than following it. Running
the harness leg first is what produced §3.5; running it a second time, to execute the repair, is
what produced §3.6 and caught a regression no test covered; running it a third time, on 2026-08-05,
refuted a claim Rev 6 had just made and found a corrupt-manifest shape Rev 6's enumeration missed.
The pattern is consistent: **the design document has been wrong in a checkable way at every
revision, and the thing that caught it was executing something.**

**The specific failure shape, now named and tracked as proposal risk 3c.** Four mechanism claims in
this phase have been refuted the same way: a grep over the name the *design document* uses for a
thing, where the code enforces the same obligation under a *different name one call frame away*.
Rev 6's §2.3 finding 3 grepped `stage.outputs` and missed `AgentRunner.run`'s check on `out_name`
(`rfc_to_implementation.py:331-334`). §3.3 records two more, and `FS-ENCODING-1`'s mechanism was the
fourth. All four were caught by running something, four out of four. If a future revision's claim
rests on a grep, execute it.

## 6. Open work Phase 4 has filed and not closed

Rev 6 routed the first block of these. The table was also short by two, `FS-ISOLATION-1` and
`STATE-PROD-1` being filed in proposal §14 and absent here. **The last five rows are 4c's own and are
the four open items plus one, all of them filed at the branch tip and none of them blocking the
merge.**

| Tag | What | Routed to |
|---|---|---|
| `FS-STAT-1` | `liveness.advancing` has no callable data source. **An mtime does not close it**: `advancing` takes an age in seconds and monotonic reports nanoseconds since an unspecified epoch. Re-scoped to a clamped-age builtin | **Roadmap row**, `[CT][SPEC]`, on the `HTTP-GET-1` precedent. Doc-lead |
| `MATCH-CATCHALL-1` | `emitMatch` suppresses its catch-all on a mixed constructor/literal match. Tagged in Rev 6; the row text must carry the ships-past-a-`tcWarn` precondition | **Roadmap row**, `[CT]`. Doc-lead |
| `CLAUSE-INDEP-1` | A `post` clause entailed by its siblings occupies a §15.1 tier and eliminates nothing. Confirmed at `[S5-PRESENCE]` | **Third item under the layer-3 contract-quality row** (`roadmap:210`), extending CDP. Doc-lead |
| `PROC-ENV-1` | `wasi.proc.run` has no env parameter; blocks nothing | **R-14 in `driver-ll-open-work.md`**, no roadmap row. Done |
| `STATE-PROD-1` | At most one payload per constructor; §4 gives the worked encoding and its cost | **R-15 in `driver-ll-open-work.md`**, no roadmap row. Done |
| `SPEC-TIER-1` | driver-spec §15.1's tiering clause cannot classify its own §13. Target-spec defect; the source is pinned so it is recorded, not repaired | **Named in the DRIVER-LL row's notes as a Phase 5 constraint.** Doc-lead |
| `FS-ISOLATION-1` | `audit_blindness` implements driver-spec §8:330-332 and the port defers it | **Same**, plus the phase-close disclosure under §15.1:504-505 |
| `F-7` | Stage O is the only delegated stage with no validator; driver-spec §13 is its specification | Lands at sub-phase 4f. Unchanged |
| `F-4` | Stage G2's citation check scores every stub citation below threshold | Experiment-lead. Unchanged, still open |
| **§3.6 census** | **New at Rev 10, and the largest owed item in the phase.** Proposal §3.6's table is line-keyed and its keys are stale at HEAD: `:809` is a `for` statement inside `_pinned_sources`, and the two G2 conditions the first row files as post-write fire before G2 writes anything. Needs a fresh census over the write-before-halt ordering of every stage, **not** a renumbering, renumbering by inspection being what produced the bad Rev 8 stamp | **Experiment-lead.** Does not block 4c: §9.2 settles what 4c needs, and §3.6.1 carries the one site 4c touches |
| **F-20 live half** | Whether a live agent can emit a bare-list `core.json`. Dead in-tree at n=0 live runs, so the port's narrowing to the dict shape is measured over every observed producer and unmeasured against a live one | Experiment-lead, and only when a live run happens for another reason. The port rejects rather than tolerates, so a surprise is loud |
| **`REGEX-LOWER-1`** | **ROW FILED at `86b39db`, and it is wider than 4c thought.** `emitOp` ([`CodegenHs.hs:1346-1362`](../../compiler/src/LLMLL/CodegenHs.hs)) has named lowerings for ten operators and then a fallback that intercalates the operator name literally, which is correct exactly for names that are already valid Haskell infix operators. `isOperator` holds **two that are not** (`regex-match`, `is-valid?`) plus **six Unicode aliases**, with no normalization between parser and codegen. **Only `regex-match` is executed; the other seven are read off the source.** All eight have a zero in-tree firing population, measured over every committed `.llmll` file, so no fixture would notice either way. Original finding: **`regex-match` typechecks and verifies and then DOES NOT BUILD.** It is in the type environment (`TypeCheck.hs:143`), documented at `LLMLL.md:326`, and its preamble implementation is emitted (`CodegenHs.hs:395-396`), yet a program calling it dies in GHC with `Variable not in scope: regex`, because `Parser.hs:943` lists it among the **operators** beside `and`/`or`/`=>` so codegen emits it infix with its hyphen unmangled, and unlike `and`/`or` it has no infix lowering. **Its in-tree firing population was zero**, which is how a typed, documented, preamble-backed builtin was never code-generated once | **Compiler-engineer, and it has NO ROADMAP ROW: it exists in the 4c plan and one `sequencer.llmll` comment and nowhere else.** 4c hand-rolls both pattern checks, exactly equivalent on their domains and Σ_auto-safe, and does not work around it silently |
| **§9.2 item 1 was silent on `ConditionUnmet`** | `check_dispositioned:493` is `require_spec` rather than `require`, so §3.5's rule makes its halt spec-defined and it records `stopped`. **4c therefore builds three of `Outcome`'s four arms where 4b built two.** Item 1 records only that 4c constructs no `PartialThenHalt`, which holds. The rig asserts the `stopped` in `test_exclusion_outside_the_barrier_list_halts_the_run`, mode `bad-barrier` | **CLOSED at Rev 11.** `[V7-ONLY-TWO]` stays true as stated, being about `verdict-outcome`'s codomain rather than the port, so **the shipped proved module's prose was left alone on purpose** |
| **F-20's tolerance is at FOUR sites** | F-20 named two (`:713`, `:732`, both `core_ids` on `core.json`), the 4c plan found a third (`:482`, the dispositions document's `rows`), and writing the 4c test tier found a **fourth**: `:456` in `check_audit`, over the audit document's `audited`, which belongs to **stage G2** and sits outside 4c entirely | **CORRECTED at Rev 12** after Rev 11 stated it as three. **Three readers running have stated this count short, each enumerating the artifact they were porting**, so it is now **computed** by `test_driver_ll_4c.py` and fails on a fifth. A count wrong three times is not a fact to re-check, it is a fact to derive |
| **`stage-tag-count` is D-only** | K, L and M are all multi-invocation in the reference and all three unported, so the table's `(if (= i 3) 2 1)` is correct today and wrong for whichever lands first. Two readings of what the table counts were **both refuted**: D declares two outputs and holds **one** `agent.run` executed twice by a loop, while K holds two call sites and declares one output | **Task 28, and asserted rather than noted.** The test passes while the hazard is only a hazard and fails the moment one of the three is marked ported without the table moving |
| **A docstring cited as an assertion** | The 4c plan cited the barrier assertion as `test_rfc_pipeline_integration.py:334`, which is a docstring line. §3.5.1's rule, cite the condition or the test name and never the line, was written one sub-phase earlier and ignored here | **Recorded at Rev 11, not repaired in the plan**, which is a running record. The amendments cite the test by name |
| **Driver README unupdated for D, F and G** | **CLOSED at `3f229d8`.** Writing it found two stale counts in the file (frozen verdicts 27 → **31**, cover 31 → **39**) and one real gap, now task 27: **4c added nothing to the no-toolchain tier**, so every check it added needs a built binary | Closed. The gap it found is open |
| **`validate.llmll:56-63`'s forecast** | It predicted the content-shape validators would land as "a second channel into this module"; they landed in the sibling `shape.llmll` instead. The note is epoch-labelled "AT 4b" so it is not false, and rewriting a shipped proved module for a comment is not worth a re-verify on its own | **Compiler-engineer, to ride with the next change that touches `validate.llmll`**, which is 4f where the two programs unify |

## 7. Gotchas

- **Stale binary.** `stack exec` from the repo root runs the wrong compiler. Before any compiler
  work: `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH` and check
  `llmll version` reports **0.14.87**. The rebuild this gotcha called for **has been done**; the
  gotcha stays because the condition recurs every time the pins move and the binary does not, and it
  bit once already in this phase.
- **A rig cell exists now for stage D's second extractor.** Mode `bad-extraction-b` plus
  `test_stage_D_records_failed_when_the_valid_sibling_is_already_written`. **Nothing reached that halt
  before it**: `bad-extraction` corrupts whichever tag runs first and tag `a` always runs first, so
  every prior run halted with no sibling artifact on disk. The cell is the only one that exercises
  §4:146 being satisfied by a valid **sibling**, and stage D is the only agent-delegated stage where
  that state is reachable at all, being the only one declaring two outputs.
- **The doc path lint gates CI.** `scripts/tests/test_doc_path_lint.py::test_clean_on_live_repo`
  runs in `version-gate.yml`, so an unresolved prose citation leaves `main` red. Only citations
  **containing a slash** are checked (`doc_path_lint.py:150-151`), so a bare filename is safe and a
  workdir-relative path with a directory in it is not. Writing the bad example out in backticks is
  itself enough to trip it, which is how this file broke the lint once.
- **Stage G2 still cannot run under the stub.** Its citation check scores every stub citation below
  `CITATION_RESOLVES_AT` because the rows quote `"q"` against SPEC lines that do not contain it.
  Fixing it needs stub rows whose quotes are drawn from the pinned bytes. Filed as harness finding
  F-4, still open.
- **Do not read `driver-spec.txt`'s structure from `grep -nE "^[0-9]*\.  [A-Z]"`.** It truncates at
  section 9 because sections 10 and up use a single space. §10 through §15.4 exist and carry
  conditions this proposal originally missed; the Rev 5 sweep read them, and §6.2 through §6.5 are
  the result.
- **macOS cannot reproduce the FS-ENCODING-1 condition, and the confirming CI run FAILED.** GHC here
  returns UTF-8 from `getLocaleEncoding` under every locale, so stage 5b was a structural no-op
  locally while reporting PASS. Its first real execution, on `main` after the 2026-08-05 push, failed
  on four assertions from **one** defect: `FS-ENCODING-1` pinned the filesystem handles and left the
  generated program's **standard** handles on the ambient locale, so a program wrote non-ASCII to
  disk correctly and then died printing it. Fixed at v0.14.86, verified red-to-green in a Linux
  container. **Stage 5b now prints NOT EXERCISED on Darwin** rather than a PASS it has not earned, so
  a green local run no longer implies the encoding claim was tested.
- **The doc lint bit twice on 2026-08-05**, both times in exactly the way the bullet above predicts,
  and the second time was *while writing this bullet*. A findings file named a workdir-relative
  artifact by joining its stage directory and filename with a slash inside backticks, so the lint
  tried to resolve it as a repo path. The fix is to name the two parts separately: "`scope.md` under
  its stage directory". Do not write the offending form out as an example, in this file or any other,
  because the example is itself a citation. Run `python3 scripts/doc_path_lint.py` after any prose
  that names a runtime path.
- **Line-bearing citations are unlintable and drift silently.** `doc_path_lint` exempts a backticked
  path that appears as a link label whose target exists (`doc_path_lint.py:146-147`) and skips
  anything without a slash (`:150-151`), so the line numbers inside `` `Foo.hs:120-145` `` are never
  checked. Seven were stale in the proposal at Rev 5, five of them into `compiler/src/LLMLL/`, and
  all four of §10 case 6's. Rev 6 repaired them and proposes citing the top-level binding instead,
  since a rename is grep-detectable where a line shift is not. **The roadmap had the same defect
  internally**, and it was worse than drift: its layer-3 row cross-referenced CDP at `:224`, and
  `:224` was **already a table header at `0b27ee0`, the commit that introduced the reference**. It
  never resolved once. Doc-lead repaired it name-based on 2026-08-05, to the `#active-items` anchor,
  so a line shift cannot re-break it.
- **The driver's stage-selection flag is `--only`, not `--stages`.** The rig's fixture takes a
  `stages=` keyword and maps it (`test_rfc_pipeline_integration.py:275`). A hand-rolled invocation
  using `--stages` dies in argparse with exit 2, which reads exactly like a deliberate `Halt` and
  cost a debugging cycle on 2026-08-05.
- **`pytest tmp_path` lives under `/var/folders`, which the driver refuses as a run directory.** Pass
  `--allow-volatile-workdir`; the rig already does.
- **An LLMLL binding named `show` passes `llmll check` and fails GHC** with `Ambiguous occurrence
  'show'` against generated prelude code. Same family as the reserved `check`. Found incidentally by
  the 4a plan. **It has a roadmap row now, `RESERVED-NAME-1`, OPEN**; this bullet said it had none,
  which was true when written and is not true at HEAD.
- **A push to `main` is not a CI run, and the gap is checkable in one call.** Two pushes on
  2026-08-06 produced zero runs while Actions was enabled, the workflow active, the trigger matching
  and no skip token present; the cause was a GitHub Actions **major outage**, not anything in the
  repository (§1). **Check that a run exists after any push to `main`** rather than assuming the
  trigger fired: `total_count` from `actions/runs?head_sha=<sha>` is the reading that cannot be
  misinterpreted, and githubstatus.com's `components.json` endpoint distinguishes an outage from a
  repository-side cause. The first hypothesis here, that pushing a SHA to a branch and then
  fast-forwarding `main` onto it suppresses the run, was **refuted**: a fresh SHA pushed to `main`
  alone behaved identically. Do not re-derive it.
- **Running the driver drops `sequencer.event-log.jsonl` in the working directory.** It is untracked
  debris, not an artifact, and nothing reads it back. Delete it; do not commit it and do not reason
  from it.
- **`regex-match` compiles nothing.** It typechecks and verifies and then fails GHC, per
  `REGEX-LOWER-1` in §6. Until that row ships, any pattern check in driver code is hand-rolled from
  `string-char-at` and friends, which is what 4c did, and the reason belongs at the site rather than
  in a commit message.

## 9. Releases: v0.14.87 is DONE, and 4c owes a NEW ceremony NOW

**4c is merged, so all of it is now due**: the version bump, the CHANGELOG entry and the DRIVER-LL
roadmap row. Nothing was owed while it sat on a branch; the merge is what makes it owed. The pins are still 0.14.87 and **no compiler change is in 4c**,
so what ships is a driver sub-phase and not a language movement. Three things to carry into it.
`REGEX-LOWER-1` wants its own roadmap row (§6) and the release should name it even though 4c does not
fix it. The roadmap row's 4c text owes a **disclosure of `shape.llmll` as new proved surface**, on
the precedent `validate.llmll` set at 4b. And the cover figure moved 31 → 39 cells, which is the
number a release note should carry rather than "the cover passes".

v0.14.87 shipped (`5a4832c` pins, `1bc2965` docs). It carried the two builtin fixes, sub-phase 4b,
three doc repairs, and two roadmap rows. This section is kept only to record what it closed and what
it deliberately did not:

- **`PROC-TIMEOUT-1` is filed and NOT fixed.** `wasi.proc.run`'s timeout does not fire in a built
  program: `--timeout 1` against a 30-second agent exits 0 with `seconds: 30`, and the binary reports
  `RTS way: rts_v`. **Adding `ghc-options: -threaded` to the generated package did NOT move the RTS
  way**, so the one-line fix measures identically to no change. The roadmap row says so in bold.
  Consequence: 4b's budget-overrun halt is written and unreachable through the timeout path.
- **The closure note owed to compiler-engineer is DISCHARGED** (`8cd05ee`), and it turned out to have
  been **half-discharged already**: the roadmap row has cited its originating plan since v0.14.87, so
  what was actually owed was only the new population. The row now names `AgentRunner.run` as the
  reference's own overrun path and D, F and G as the three stages 4c adds. Do not file it a third time.
- **The v0.14.85 shipped row records 120 Python where the figure was 123.** Left alone deliberately:
  shipped rows are append-only, and silently correcting one is how a release record stops being a
  record. **Still open.** Its own pass if wanted. Note the same principle already applies once more:
  the v0.14.87 row records 131 Python and the 132nd test landed after that release, which is correct
  and must not be "fixed."

## 8. Rev 8: SETTLED, and what it cost to wait

Rev 8 was **shut on purpose** until 4a ran, on the ground that every revision of this proposal which
predicted was wrong in a checkable way. The wait paid. All three predictions were confirmed by
execution, **and holding them produced two findings a predicted Rev 8 would have missed**: the
cover's cells are separable, not merely present, and a perturbation that crashes is not a
perturbation that refutes. Both came out of mutating the cover rather than reasoning about it.

The table below is kept as the record of what was held and why. **All four are now settled in Rev 8
§15.** Two items remain open and are NOT Rev 8's:

- **`PROC-BOUNDARY-1`'s range refinement is body-faithful only for a scalar state.** A `def`
  projecting a pair falls back, measured on `[s: (int,int)]` as much as on the driver's state, so
  `:status`'s range post is contract-checked rather than proved for any real driver. The 4a port
  puts the weight on a body-faithful `exit-code` and clamps at the boundary. **Language-team.**
- **`sha256_file` is partial.** It opens its path with no existence check and is correct today only
  because the presence guard runs first. Any refactor computing digests independently of the
  presence sweep turns a deleted artifact from a clean re-run into a traceback. Defence-in-depth,
  no defect reachable at HEAD. **Compiler-engineer.**

| # | Finding | Where it lands | Status |
|---|---|---|---|
| 1 | **§3.5 states a measurement with no epoch.** "46 `require()` sites plus three raises" was correct against `aa08051~1` and is **39 and ten** at HEAD. Nothing drifted: Task #8 landed the second raising form (`require_spec`, `:358`) that §3.5 itself ordered, so the counts moved because the repair shipped. §3.5's partition ("of the 46: 9 spec-defined, 26 …") is now over an encoding the repair replaced | §3.5 gains a measurement epoch and a re-measured partition | **Confirmed by measurement.** No bite for 4a; hits 4b's framing |
| 2 | **`wasi.fs.sha256` collapses presence and digest into one command** (`RErr` absent / `RText` hex). Conservative in the safe direction | A third §7 disclosure, which the proposal does not list | Predicted. Confirm against the port |
| 3 | **§4's sum encoding makes `:on-done` usable**, retiring the RC-4 workaround `spine.llmll:673-679` documents | §4, plus the workaround's own note | Predicted. Confirm against the port |
| 4 | **The port decides all three corrupt-manifest shapes with one total predicate** over what the reader indexes, where the reference discriminates by Python exception site. The port is **better than the thing clause 1b checks it against** | Clause 1b, conformance-where-they-differ | Predicted, and it is the interesting one: 1b assumes the reference is the standard |

The first is a document defect an engineer already tripped on, and it is recorded here rather than
repaired so that the repair and its re-measurement land together.
