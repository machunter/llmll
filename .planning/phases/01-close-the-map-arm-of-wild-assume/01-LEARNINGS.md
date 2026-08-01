---
phase: 01
phase_name: "close-the-map-arm-of-wild-assume"
project: "LLMLL"
generated: "2026-08-01"
counts:
  decisions: 7
  lessons: 7
  patterns: 5
  surprises: 5
missing_artifacts:
  - "01-UAT.md (not created; verification passed with no human_verification items)"
  - "01-CONTEXT.md (phase went straight from research to planning)"
---

# Phase 01 Learnings: close-the-map-arm-of-wild-assume

## Decisions

### Extend `assumesFact` by pattern clause plus scoped helpers, not by inlining admissibility

The map arm was added as a `TMap kt vt` clause delegating to two new local predicates,
`assumesFactMapKey` and `assumesFactBoolValue`, which mirror `FixpointEmit.isIntLike` /
`isStrLike` / `isBoolLike` minus their `AliasMap` lookups.

**Rationale:** the checker's admission set must track the emitter's assertion set. Naming the
emitter function each helper mirrors makes the coupling reviewable instead of coincidental, and
the omission of the `AliasMap` lookup is justified by both call sites receiving already
alias-expanded types. That justification was later shown to be incomplete for `TDependent`
(see CR-01 under Lessons), which is exactly the kind of claim this structure makes checkable.
**Source:** 01-01-SUMMARY.md

### Map-arm fixtures live in a sibling `describe` block, not as an extension of the bytes-arm block

**Rationale:** the bytes-arm block's title says "bytes[n] laundering". Appending map fixtures to
it would make that title false. This closed research open question 3 as the plan specified.
**Source:** 01-01-SUMMARY.md

### `checker_soundness_version` is not bumped

**Rationale:** decided on evidence rather than caution. `doVerify`'s type-check gate runs and
exits before every sidecar-consuming render branch (`app/Main.hs`), and `Module.hs` discards the
sidecar-merged env whenever a module's own hard errors are non-empty, so a program the widened
checker newly rejects can never reach a branch that renders a cached verdict. Neither bump
condition held: no corpus verdict flipped, and no cached sidecar reaches a consumer without a
successful type check gating it. The SUMMARY records what would reopen the question, namely any
later phase that widens what the checker accepts rather than narrowing it.
**Source:** 01-03-SUMMARY.md

### `wildAssumeFactNoun`'s fallback is a neutral noun, not an absent case

**Rationale:** keeps the function total the same way `assumesFact` is total. A future
`assumesFact` arm not yet taught to the noun function degrades to a vague-but-not-wrong "a fact"
rather than a pattern-match failure.
**Source:** 01-03-SUMMARY.md

### The WILD-ASSUME-2 Active Items row was deleted, not relabelled "SHIPPED"

**Rationale:** the plan's action text said move the row to Shipped Releases. The pre-existing
SAFE-ARG row uses an in-place "SHIPPED" label, so the executor had to choose; it followed the
plan's literal instruction rather than the neighbouring convention.
**Source:** 01-04-SUMMARY.md

### The `LLMLL.md` §3.4.6 and §5.3.5 corrections were kept despite the plan prohibiting them

Plan 01-04 prohibited expanding `LLMLL.md` beyond the version banner, on the grounds that what a
bare `?` denotes is `REQ-wildcard-semantics-spec`, a deferred backlog item.

**Rationale:** the edit does not write wildcard semantics. It corrects two statements about class
membership and ship status that the release itself makes false (§3.4.6 said the class was
`bytes[n]` alone; §5.3.5 said the map arm was not yet shipped). The human's call at the blocking
checkpoint was that a normative spec asserting "not yet shipped" about something shipped in the
same commit is the worse outcome. The deviation originated in the orchestrator's briefing, not in
executor drift.
**Source:** 01-04-SUMMARY.md, Task 3 checkpoint outcome

### CR-01 was fixed inside this phase rather than deferred to a follow-up requirement

**Rationale:** the gap predated the phase and was arguably out of scope, since `REQ-wild-assume-2`
was scoped as "extend `assumesFact` to the map class", which was already done. It was fixed
anyway because the v0.14.74 notes claim the map arm closes, and shipping that claim with a
one-line evasion open would overstate in exactly the way this phase's own criterion 4 exists to
prevent. The fix was measured clean before the decision was put to the user.
**Source:** 01-REVIEW.md (Resolution section)

---

## Lessons

### A membership predicate must strip every wrapper the emitter's resolver strips

`assumesFact` matched `TBytes` / `TMap` at the outermost constructor only, so a `TDependent`
wrapper fell through to `False`, while `FixpointEmit.resolveAliasTy`, the function that decides
whether the emitter asserts the ground fact, does strip it. The checker therefore guarded a
strictly narrower set than the emitter asserts for, and a return position declared as
`(type B (where [m: map[int bool]] true))` accepted a laundered wildcard.

**Context:** this is the same checker/emitter divergence class that produced FQ-RESULT-SORT-1,
FQ-CTOR-COLLIDE-1, and SAFE-ARG itself, which PROJECT.md already names as the milestone's fragile
area. It was not map-specific: it defeated the `bytes[n]` arm shipped in v0.14.73, so the affected
range for the wrapped shape is v0.14.34 through v0.14.73. Note that the two inner helpers already
recursed through `TDependent` for the key and value components; only the outer dispatch missed it,
which is why the gap survived four plans and their liveness probes.
**Source:** 01-REVIEW.md (CR-01)

### `stack build llmll` does not settle the package; only a full `stack test` does

After any source or cabal edit, `stack build --dry-run llmll` keeps reporting `Would build:` on the
Cabal-autogenerated `Paths_llmll.hs`. `stack build --test --no-run-tests` does not clear it either.
A full `stack test` does, and the result is then stable across repeated dry-runs.

**Context:** this matters because the dry-run assertion is the project's stale-binary guard, and
plans 01-03 and 01-04 both asserted `Nothing to build.` immediately after `stack build` and before
`stack test`, an ordering that cannot pass once the plan edits source. The orchestrator corrected
the ordering in both briefings while keeping the assertion intact. A guard that fails for a reason
unrelated to what it guards invites being weakened, which is the real hazard. Now recorded in
PROJECT.md's build-hygiene constraint.
**Source:** 01-02-SUMMARY.md (Build hygiene, re-measured), 01-03-SUMMARY.md, 01-04-SUMMARY.md

### An acceptance criterion built on `grep -c '<exact sentence>'` breaks on soft line wraps

Two of the three required CHANGELOG sentences spanned an 80-column wrap in the raw file, so the
line-based grep returned 0 despite the sentences being present and correct.

**Context:** the fix was to reformat so each required sentence occupies one physical line, which
changes nothing in rendered Markdown. Worth knowing when writing any future verbatim-text
acceptance criterion against a prose file.
**Source:** 01-04-SUMMARY.md (Deviation 1)

### An acceptance criterion of "script exits 0" was never achievable against this baseline

Plan 01-04 required `scripts/check-examples.sh` to exit 0. The script exits 1 whenever any corpus
file fails, and the pre-phase baseline already carried one pre-existing failure
(`examples/totp_rfc6238/totp_filled.ast.json`), so the criterion was unsatisfiable from the start.

**Context:** the executor verified the criterion that actually matters, the one ROADMAP states
("reports no new failures"), and documented the discrepancy rather than editing the fixture or the
script to force green. That restraint is the right call; the lesson is to write acceptance criteria
against the measured baseline rather than against an assumed-clean one.
**Source:** 01-04-SUMMARY.md (Deviation 4)

### `compiler/llmll.cabal` is hpack-generated from `compiler/package.yaml`

The release ceremony edited both files' `version:` fields by hand rather than regenerating the
`.cabal` from the edited `package.yaml` via `hpack`.

**Context:** this works and `version_gate.sh` passes, but it means the two can silently drift if a
future edit touches more than the version field. Worth deciding a convention before the next
release ceremony.
**Source:** 01-04-SUMMARY.md (Issues Encountered)

### The alias-expansion reading held, so SA-11 needed no compiler change

Research open question 1 asked whether an aliased `map[k,bool]` would bypass the guard. It does not:
`expandAlias` recurses into `TMap` components and `unify` expands both sides before
`compatibleWith`, so `assumesFact` sees a resolved type.

**Context:** the plan carried a contingency for closing an alias-bypass seam. It did not fire. The
useful detail is that this was later confirmed eliminatively rather than by reading: disabling the
`TMap` clause turns SA-11 red, which shows the alias path genuinely reaches the clause, something
the code reading alone could not establish.
**Source:** 01-02-SUMMARY.md, 01-REVIEW.md (Resolution)

### `(type Name (T))` parses only for `where`-types and sum-type arms

The first SA-11 draft, `(type BoolMap (map[int bool]))`, failed to parse: `pType`'s `pPairType`
alternative commits on the leading paren, parses the inner type as a would-be pair's first
component, then requires a comma. A plain alias body is unparenthesized.

**Context:** a fixture-source bug, not a compiler bug. Worth knowing when writing type-alias
fixtures.
**Source:** 01-02-SUMMARY.md (Rule 1 deviation)

---

## Patterns

### Clause-removal probe across a whole fixture block

Disable the single clause under test, rebuild, run the entire `describe` block, and read the
partition. The phase's decisive measurement was `8 examples, 4 failures`: every rejection fixture
(SA-8, SA-9, SA-11, SA-13) went red and every acceptance control (SA-10, SA-12, SA-14, SA-15)
stayed green.

**When to use:** any time a block mixes rejection fixtures and acceptance controls. One probe
simultaneously proves no rejection fixture is dead and no control is passing merely because the
guard failed to fire, which per-fixture checking does not establish. The verifier re-ran the same
probe independently and reproduced the partition including SA-16 and SA-17.
**Source:** 01-02-SUMMARY.md (Orchestrator clause-dependence probe), 01-VERIFICATION.md

### Match the liveness probe to the kind of thing being tested

A discriminant fixture is probed by removing the discriminant clause. A diagnostic-wording fixture
is probed by reverting the wording, not the clause. SA-16's probe restored the hardcoded "a length"
message; SA-17's probe removed the `TDependent` clause.

**When to use:** whenever adding a fixture. Recording the specific failure symptom (which assertion,
expected versus actual) is what distinguishes a real probe from an assertion that it was run.
**Source:** 01-03-SUMMARY.md, 01-REVIEW.md (Resolution)

### New arm of a discriminant predicate: clause plus scoped helpers plus a cited mirror

Add the pattern clause beside the existing predicate, put admissibility in named helpers, and in
the comment cite both the emitter function the helpers mirror and the invariant that lets them
skip work the emitter does.

**When to use:** any extension to `assumesFact` or a similar checker-side membership predicate.
CR-01 shows the value: the cited invariant ("both call sites receive already alias-expanded types")
was the exact claim that turned out to be incomplete, and having it written down is what made it
checkable.
**Source:** 01-01-SUMMARY.md, 01-REVIEW.md (CR-01)

### Staging-plus-handoff under the subagent git guard

`.claude/hooks/block-git-from-subagent.sh` denies git writes from any Task-tool subagent. The
working protocol: the executor completes a task, `git add`s exactly that task's files, and records
the intended commit message in its SUMMARY; the orchestrator commits after independently verifying
the claims.

**When to use:** every plan execution in this repo. Telling the executor this up front (plans 01-02
onward) prevents it from treating the guard as a blocker and stalling, which is what happened on
01-01 before the constraint was stated in the briefing.
**Source:** 01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md

### Evidence-limit language as a machine-checkable acceptance criterion

ROADMAP criterion 4 was operationalized as three required verbatim sentences plus a region-scoped
absence check for the adjacent release entry's exploit vocabulary, backed by a blocking human read.

**When to use:** any release note for a fix with no reaching witness. The mechanical half catches
omission; the human half catches a paraphrase that reads stronger than the evidence. Both were
needed here: the automated checks passed on a draft whose framing still needed a human judgment.
**Source:** 01-04-PLAN.md, 01-04-SUMMARY.md (Task 3 checkpoint outcome)

---

## Surprises

### The code review found a Critical that four plans and their liveness probes all missed

The phase was built around proving fixtures live, ran clause-removal probes at three separate
points, and still shipped to review with a wrapper shape that evaded the guard entirely.

**Impact:** the highest-value finding of the phase came from the advisory, non-blocking gate at the
very end. It also caught a defect in the *previous* release. The generalizable point is that
liveness probes prove the fixtures you wrote are live; they say nothing about the shapes you did
not think to write. The review brief that found it was pointed explicitly at checker/emitter
admissibility divergence, which suggests directing review attention at the known-fragile seam is
worth more than breadth.
**Source:** 01-REVIEW.md (CR-01)

### A recorded "tooling noise" conclusion did not survive re-measurement

Plan 01-02 concluded that `stack build --dry-run` is inherently and non-clearably dirty on
autogenerated `Paths_llmll.hs`, describing it as deterministic across repeated runs. The
observation reproduces; the conclusion does not. The flag clears, and a full `stack test` is what
clears it.

**Impact:** the wrong conclusion, left standing, would have justified weakening the stale-binary
guard in two later plans. The likely cause is sampling only the post-`stack build` half of the
sequence, during a window when the executor had itself edited source for a liveness probe. This is
the phase's clearest instance of an agent generalizing a transient observation into a settled
finding.
**Source:** 01-02-SUMMARY.md (Build hygiene, re-measured)

### A version-field edit needed two full `stack test` cycles to settle, not one

01-02 and 01-03 measured that one cycle clears the dirty flag after a Haskell source edit. 01-04's
edit touched `package.yaml` and `llmll.cabal` instead, and needed two.

**Impact:** none on correctness; the executor repeated the settle step rather than adjusting any
fixture. Worth knowing so a future release ceremony does not read the second `Would build:` as a
failure.
**Source:** 01-04-SUMMARY.md (Deviation 3)

### SA-11 passed on first write with zero compiler change

The alias-coverage fixture was expected to require closing a bypass seam. It did not.

**Impact:** research open question 1 was answered by measurement rather than by implementation, and
the plan's contingency went unused.
**Source:** 01-02-SUMMARY.md

### An executor stalled mid-plan waiting on a background task that did not exist

The 01-03 executor completed Task 1 correctly, then returned an incoherent message about waiting
for a completion notification for a task id that was never spawned. Tasks 2 and 3 were unstarted
and no SUMMARY existed.

**Impact:** recovered without losing work by spot-checking the filesystem (Task 1's code was
present, compiled, and passing), then resuming the same agent with its context intact plus an
explicit correction that nothing was pending. Spawning a fresh agent would have discarded usable
context; treating the incoherent return as outright failure would have redone correct work. The
general handling is to verify what is actually on disk before classifying an agent return as a
failure.
**Source:** orchestrator execution record, phase 01 (not captured in 01-03-SUMMARY.md, which was
written after recovery)
