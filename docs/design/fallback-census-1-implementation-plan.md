---
name: fallback-census-1-implementation-plan
title: "FALLBACK-CENSUS-1: implementation plan and running record"
status: "IMPLEMENTED and SHIPPED at `0c331e5` (compiler and schema) and `cdb5968` (instrument, ratchet, CI gate), released as **v0.22.0** on 2026-09-08. Gates: hspec 1908 of 1908 (was 1891), pytest 241 collected / 218 passed / 23 skipped (was 220 / 200 / 20), census 250 files at ratio 0.984. Four divergences from the plan and two findings are recorded in §12. SHELL-FALLBACK-SILENT-1 stays DECIDE and receives its decision packet in §10."
date: 2026-09-08
author: compiler-engineer
consumers: [compiler-engineer, language-team, documentation-lead, user]
---

# FALLBACK-CENSUS-1: implementation plan and running record

The G0 row's step (2) is `FALLBACK-CENSUS-1` then `SHELL-FALLBACK-SILENT-1`
([`../compiler-team-roadmap.md`](../compiler-team-roadmap.md), row `DRIVER-LL`,
Next Action item (2)). The first row carries the **PLAN** marker and is this
plan. The second carries the **DECIDE** marker: it waits on the language-team,
and §10 gives that decision the code facts it needs. This record is the plan
and, below §11, the running record of what landed.

## 1. Restatement

Build the instrument the G1 row asks for: after every CI run, the body-faithful
ratio and the fallback-cause histogram over every LLMLL file the gates touch,
computed from the compiler's own JSON, recorded where a later run can diff it,
with the three items the 2026-09-07 triage added: a bucket for unfilled holes,
contract-post causes split by predicate construct, and a ratchet on the set of
files that pass `--strict-verified-core`.

## 2. Context located

1. `docs/compiler-team-roadmap.md` row `FALLBACK-CENSUS-1` (G1 rank 1): the
   denominator rule, the sidecar dead end, the three triage items.
2. `docs/compiler-team-roadmap.md` row `SHELL-FALLBACK-SILENT-1`: DECIDE, two
   triggers, severity is the open question.
3. [`critique-2026-09-05-triage.md`](critique-2026-09-05-triage.md) §5: the B2
   count at v0.20.1 (80 pass, 52 refuted, 36 scaffolds, 17 genuine fallbacks,
   51 of 61 entries contract-post) and the hole mislabel.
4. `compiler/src/LLMLL/FixpointEmit.hs:169-192`: the closed `FallbackCause`
   set, six values, wire form `renderFallbackCause`.
5. `compiler/src/LLMLL/FixpointEmit.hs:985-1027`: the contract refusal chain
   and its two `addBodyFallback` sites; `:1271` the body site; `:1202`,
   `:1278`, `:1305` the cap and mixed-tail sites.
6. `compiler/src/LLMLL/FixpointEmit.hs:2905-3021`: `exprToPred`, the QF-LIA
   reflection; its refusals are the nonlinear operators, `map-has`/`map-get`
   on `map-empty`, and the final catch-all.
7. `compiler/src/LLMLL/ObligationAssembly.hs:700-711`: `hasHole`, the
   existing hole walker; `:321-327` labels a hole body `hole_bearing` in the
   obligation report, so the hole is already distinguishable there.
8. `compiler/app/Main.hs:1318-1349`: the `--strict-verified-core` report and
   its JSON (`strict_errors`, `fallback_causes`), printed before the solver
   runs; `:1484-1495` the `verify --json` keys `body_faithful`,
   `body_fallback`, `body_fallback_causes`.
9. `compiler/src/LLMLL/ProofArtifact.hs:276-284` and
   `docs/proof-artifact.schema.json:76`: `fallback_reason` and its enum;
   `4731579` (v0.19.0) edited the schema in the engineer's commit.
10. `compiler/test/Spec.hs:17715-17787`: the FALLBACK-REASON-CONST-1 block,
    the `emitFR` helper and the injectivity test over `[minBound .. maxBound]`.
11. `.github/workflows/version-gate.yml:454-458` (a Python gate and its
    cover run in the C1-C4 job), `:262-266` (a `LLMLL_BIN` pytest file run in
    the toolchain job), `:631` (the refute-crux gate, the last verify-bearing
    step). No step uploads an artifact today.
12. `scripts/norm_claims_gate.py:330-334`: the committed-bound ratchet
    precedent (`assumed_bound` plus `bound_reason`).
13. `scripts/check-examples.sh:22-25` enumerates with `-maxdepth 3` (166
    files today); §5's "190 files" came from the same `find` without the
    depth cap. The census pins its own rule (§4).
14. No design doc exists for this row (`rg FALLBACK-CENSUS-1 docs/design`
    finds only the triage and the regroup proposal).

**Measured on this tree (2026-09-08, `llmll 0.21.2`, solver present).**
A contract-less `def` is recorded as `body-fallback` with cause
`contract-post-outside-fragment` (probe: `(def f [n: int] -> int n)`). That
is a mislabel: no post left the fragment, there is no post. The §5 figure "51
of 61 entries are the post leaving the fragment" therefore includes an unknown
number of absent posts. A hole body, bare or nested under `if`, reports
`body-outside-fragment`, as §5 says. A strict verify costs 0.04 s to 0.30 s
per example file, including the heartbleed set; 190 files fit in about one
minute. `llmll verify` rewrites the tracked sidecar of any tracked example it
touches, so the census runs in a scratch copy by default.

## 3. Plan summary

Two label-only changes in the emitter give the census its buckets with no
`.fq` change, on the v0.19.0 precedent: `FallbackHole` (`unfilled-hole`) and
`FallbackNoPost` (`no-post`) join the closed set, decided ahead of the existing
causes at the three sites a hole or an absent post can reach. A construct
walker over the refused clause labels each contract-side fallback with the
minimal sub-terms `exprToPred` refuses, or with the guard that refused the
whole clause. `verify --json` and the strict-core JSON both gain
`body_fallback_constructs` and `fn_kinds`, and the strict-core JSON also gains
the three body-faithful keys, so one reader shape serves both exit paths. A
Python instrument, `scripts/fallback_census.py`, enumerates the population,
runs one strict verify per file in a scratch copy, aggregates, prints a
one-line summary, writes a JSON record, and ratchets the strict-pass set
against a committed baseline. CI runs it in the toolchain job, uploads the
record as a workflow artifact, and appends the table to the step summary.
Cost: one minute of CI, four Haskell modules touched, one schema enum widened.

## 4. Affected surface

Compiler, entry to output:

- `compiler/src/LLMLL/FixpointEmit.hs:177-192`: two constructors and their
  renderings; the comment names both as census buckets.
- `compiler/src/LLMLL/FixpointEmit.hs:968-1027`: `holeBody = hasHole body`
  computed once at the body-VC entry; site `:1026` picks
  hole > no-post > guard cause > `FallbackContractPost`; site `:1027` picks
  hole > `FallbackContractPre`; each site also records the clause constructs.
- `compiler/src/LLMLL/FixpointEmit.hs:1271`: hole > `FallbackBody`.
- `compiler/src/LLMLL/FixpointEmit.hs` (new): `hasHole` moves here from
  `ObligationAssembly.hs:700-711` and is exported; `refusedConstructs ::
  Expr -> [Text]` and its label table; `addBodyFallback` gains a `[Text]`
  argument at all six call sites; `EmitResult` gains
  `erFallbackConstructs :: [(Text, [Text])]`.
- `compiler/src/LLMLL/ObligationAssembly.hs:700-711`: the local `hasHole`
  is deleted; the module already imports `LLMLL.FixpointEmit` whole (`:76`).
- `compiler/app/Main.hs:1318-1349`: the strict JSON gains `body_faithful`,
  `body_fallback`, `body_fallback_causes`, `body_fallback_constructs`,
  `fn_kinds`; `fallback_causes` stays for compatibility.
- `compiler/app/Main.hs:1484-1495`: `verify --json` gains
  `body_fallback_constructs` and `fn_kinds`.
- `docs/proof-artifact.schema.json:76`: enum gains `unfilled-hole` and
  `no-post`; no `$id` change, the v0.19.0 precedent.
- `compiler/test/Spec.hs`: a `FALLBACK-CENSUS-1` block after
  `FALLBACK-REASON-CONST-1` (§7).

Instrument and gate:

- `scripts/fallback_census.py` (new): the instrument and ratchet.
- `scripts/fallback-census/BASELINE.json` (new): the committed record and
  ratchet floor, written by `--write-baseline` on this tree.
- `scripts/fallback-census/README.md` (new): the population rule, the
  ratchet rule, how to refresh.
- `scripts/tests/test_fallback_census.py` (new) and
  `scripts/tests/fixtures/fallback-census/` (three files).
- `.github/workflows/version-gate.yml`: one census step and one
  upload-artifact step after the refute-crux gate; one `LLMLL_BIN` pytest
  line beside the HTTP-GET-1 line.

Documentation (documentation-lead, on the hand-off): `LLMLL.md §14` for the
new JSON keys and the two cause strings; `docs/getting-started.md`'s
`verify --json` snippet; `docs/compiler-team-roadmap.md` rows
`FALLBACK-CENSUS-1` and `DRIVER-LL` item (2); CHANGELOG.

**Population rule.** Every `*.llmll` and `*.ast.json` under `examples/`,
`tools/` and `scripts/build-smoke/`, any depth, sorted by path, sidecars
excluded by suffix. Every root is a tree the gates build or verify
(`version-gate.yml:369-373`, `:554`, `:731`, `:631`, `:698`). The
`-maxdepth 3` of `check-examples.sh` is not adopted: it would drop the
generated scaffold trees §5 counted.

**Denominator rule.** Functions reaching body-faithful over functions with a
post, where a post is what `augmentContractPost`
(`FixpointEmit.hs:4666-4673`) leaves in the contract. `unfilled-hole` and
`no-post` entries leave the denominator and are counted beside it. A pre-only
function has nothing for a body VC to prove and lands in `no-post`.

## 5. Verification impact

- Solver-time delta: zero. Both new causes are decided at sites that already
  refused the body VC; no constraint is added or removed. The test gate
  includes a `cmp` of the `.fq` for `examples/leanstral-demo/square.llmll`
  and for a hole-bearing scaffold before and after.
- New obligations: none.
- Trust model: `--strict-verified-core` refuses the same functions; only the
  cause text after the name changes for contract-less functions and hole
  bodies. The proof artifact's `fallback_reason` carries the new strings on
  non-positive tiers only, so the kernel invariant
  (`ProofArtifact.hs:112`) is unchanged.
- Fragment: unchanged.
- Strict-verified-core: no function newly falls back or newly passes.

## 6. Performance budget

- GHC build: `FixpointEmit.hs` and `Main.hs` recompile; `ObligationAssembly`,
  `TrustReport`, `Spec.hs` follow through the import fan-out. About the cost
  of the v0.19.0 change, measured below at §12.
- `stack test`: about twelve new examples, each an in-process emit; under one
  second added.
- Compiler runtime: `refusedConstructs` runs once per contract-side fallback
  and re-invokes `exprToPred` on sub-terms of one clause; negligible.
- CI: one census step, about 190 strict verifies at 0.04 s to 0.30 s each
  plus the scratch copy; about one minute. Per-file timeout 120 s, reported
  as an outcome, never silent.
- Cache effects: none; sidecars are written in the scratch copy.

## 7. Contract plan

Nothing lands in the provable fragment. The change is a report label in the
emitter, a JSON projection in the driver, and a Python instrument; no LLMLL
function is written. The three pytest fixtures are LLMLL files, but their job
is to be classified, not proved: one QF-LIA `def` that passes strict, one
scaffold with a hole body, one file with a nonlinear post beside a
contract-less `def`.

## 8. Test plan

hspec, `compiler/test/Spec.hs`, block `FALLBACK-CENSUS-1` (12 examples):

1. A bare hole body with a QF-LIA post reports `unfilled-hole`.
2. A hole under `if` reports `unfilled-hole`.
3. A hole body with a nonlinear post reports `unfilled-hole` (hole wins).
4. A contract-less `def` reports `no-post`.
5. A pre-only `def` reports `no-post`.
6. A `def` with no post but a refinement-aliased return type does not
   report `no-post` (DEF-RET folds the refinement into the post).
7. `renderFallbackCause` stays injective over eight values (the existing
   test is kept; this one pins the count at eight).
8. A `(* n 2)` post yields constructs `["nonlinear:*"]`.
9. A `string-concat` post yields `["app:string-concat"]`; an `if` post
   yields `["if"]`.
10. A whole-map `=` post yields `["guard:whole-structure-eq"]`; a
    recursive-type pair component yields `["guard:signature"]`.
11. An untranslatable pre yields the pre's constructs and cause
    `contract-pre-outside-fragment`.
12. `erFallbackConstructs` names are a subset of `erBodyFallback`, and a
    body-cause entry carries no constructs.

pytest, `scripts/tests/test_fallback_census.py` (15 tests): thirteen
no-toolchain cells over a stub compiler that prints canned JSON per file
(aggregation and ratio; hole and no-post exclusion; kind split; construct
counts once per function; the six file outcomes; timeout; solver-missing
fails closed with exit 2; missing baseline fails, never skips;
`--write-baseline` round trip; ratchet shrink exits 1 naming the file; a named
removal passes; population rule; the source tree is untouched;
`GITHUB_STEP_SUMMARY` receives the table) and two `LLMLL_BIN` cells over the
three fixtures against the real compiler.

Baselines, measured on `72452cf`: hspec 1891 examples; pytest 220 collected
(200 passed, 20 skipped). Targets: hspec 1903, pytest 235 collected.

End to end: `python3 scripts/fallback_census.py --llmll <bin> --repo .`
on this tree, whose record becomes `BASELINE.json`.

## 9. Rollback

One revert. No flag. The schema enum widening is additive; artifacts written
with the new strings parse under the old reader (`FromJSON` accepts any
string, `ProofArtifact.hs:295`). Sidecars are untouched. The baseline file
and the CI steps revert with the same commit. Worst case: delete the two
steps and the three new files, and the compiler change stands alone.

## 10. SHELL-FALLBACK-SILENT-1: the decision packet (DECIDE, language-team)

The row asks for a severity. These are the code facts.

- **Both triggers reproduce, and the witness is built, not traced.** Measured
  2026-09-08 at `llmll 0.21.2`:

  ```
  (type Tree (| Node Tree) (| Leaf))
  (type Box2 (| Holds Tree) (| Nothing2))
  (def-shell named [b: Box2] -> int
    (post (>= result 0))
    (match b ((Holds t) 1) ((Nothing2) 0)))
  ```

  reports `named: body-outside-fragment` and nothing else. Replacing the bound
  payload with `_` on a two-arm sum reports the same cause. Both fall back
  silently: the run prints no warning naming the arm.

- **The row's first trigger is narrower than its wording.** The row says
  "naming a match arm whose payload sort is outside the fragment". A `string`
  payload does NOT trigger it: the same shape over `(| Full string)` reaches
  **body-faithful**. A recursive user type does trigger it. So the trigger is a
  payload the fragment cannot admit at all, not any non-integer carrier sort.
  The language-team should correct the row's wording with the decision.

- The `_` trigger's asymmetry is what makes the row worth closing. As a `def`
  the same body is a loud `check` error, `def 'wild': body contains non-core
  syntax`, naming the function and suggesting `def-shell`
  (`TypeCheck.hs:1685-1688`, `Syntax.hs:800-815`). As a `def-shell` nothing is
  said at all.
- A `def` never gets there. `checkStatement (SDef ...)` refuses the body at
  check when `isCoreBodySyntactic` fails (`TypeCheck.hs:1685-1688`,
  `Syntax.hs:800-815`); a `def-shell` has no such check by design.
- The soundness position is unchanged: contract-only verification of a
  `def-shell` is sound (`LLMLL.md:296`, `:358`). What is missing is the
  disclosure that body-faithfulness was lost, and which arm lost it.
- The existing carrier is `addDiag` with `mkWarning`, already used at
  `:1203` for the path cap; EMIT-DIAG-JSON folds emitter warnings into
  `verify --json` (`Main.hs:1454-1462`), so a warning reaches agents.
- Recommendation for the decision: a warning, keyed `W-SHELL-FALLBACK`,
  naming the function, the arm and the trigger, emitted at `:1271` when the
  statement is a `def-shell` and the body contains a match. Not an error: an
  error would refuse programs the spec admits. After the census ships, the
  same information can also ride `body_fallback_constructs` for body causes,
  which is one more walker over the body-VC refusal, not planned here.

## 11. Risks and unknowns

1. **`no-post` changes a strict-core message.** DX. `Main.hs:1324`. A
   reader of an existing log sees `f (no-post)` where it saw
   `f (contract-post-outside-fragment)`. Complicates nothing; the hand-off
   names it.
2. **`actions/upload-artifact` is new to this workflow.** Scope. No step
   uses it today. If the action is unavailable the step fails visibly; the
   step summary carries the same table, so the record survives.
3. **The scratch copy changes the run directory.** Verification. A file
   whose imports reach outside the three roots would fail to resolve in the
   copy. The census reports such a file as `check-failed`, never as a pass,
   and the first run on this tree measures whether any exists.
4. **§5's histogram is not reproducible as published.** Spec-drift. The
   `no-post` split means the first census will report fewer
   `contract-post-outside-fragment` entries than 51. This is a correction,
   recorded in the baseline, not a regression.

## 12. Running record

Applied to review-ready on 2026-09-08, branch
`fallback-census-1/census-and-ratchet`, base `72452cf` (v0.21.2). Not committed.

### 12.1 Gates measured

| Gate | Before | After |
|---|---|---|
| hspec examples | 1891 | 1908 |
| hspec failures | 0 | 0 |
| pytest collected | 220 | 241 |
| pytest passed / skipped | 200 / 20 | 218 / 23 |
| `stack build` | clean | clean, no new warning on the new code |
| census population | not measured | 250 files |
| census wall clock | not measured | 6 min 4 s at `--jobs 4` |
| census CPU | not measured | 11 min 14 s |

The `.fq` for `examples/leanstral-demo/square.llmll` is 335 bytes, the figure
the v0.19.0 CHANGELOG records for the same file. That is the byte-identity
evidence available without the pre-change binary, and it is what the plan's
`cmp` was for.

### 12.2 The census, first recorded run

Over the 250 tracked files, 695 of 706 functions with a post reach
body-faithful: a ratio of **0.984**. Another **490** functions carry no proof
goal. Files: 97 pass, 83 fall back, 32 are scaffolds, 31 have no goal, 4 fail
`check`, 2 are refuted as intended, 1 verdict is unstable.

Fallback entries by cause, whole tree:

| Cause | Entries |
|---|---|
| `unfilled-hole` | 257 |
| `no-post` | 246 |
| `body-outside-fragment` | 9 |
| `contract-post-outside-fragment` | 2 |

### 12.3 Finding 1: §5's largest bucket was misread again

The triage's §5 reported, over its 17 hole-free example files, 61 fallback
entries of which **51 were `contract-post-outside-fragment`**, and concluded
that "among real programs the width limit is the contract vocabulary (posts
over lists, strings, rendered data), not bodies".

Measured over `examples/` alone with the new labels: 241 `unfilled-hole`, **54
`no-post`**, 7 `body-outside-fragment`, **2 `contract-post-outside-fragment`**.
The 7 body entries match §5 exactly, so the population is the same one. The 51
were almost entirely functions with **no post at all**, which the old label
reported as a post that left a fragment it never entered.

Checked directly rather than inferred: `examples/life_sexp/world.llmll`
declares 15 functions and contains zero `(post ` clauses, and every game example
(hangman, tictactoe, Conway, life) reports `no-post` and nothing else.

**The conclusion inverts.** The limit on the real example corpus is not the
contract vocabulary. It is that most of those functions were never given a
contract. That is a different roadmap move: widening `Σ_auto` for list and
string posts would not change these files, because they have no post to widen
for. Lever B's first data point was this figure, so this correction belongs to
the language-team before that lever is planned.

### 12.4 Finding 2: one verify verdict is not stable

`examples/secure-channel-emergent/work/spine.ast.json` reported `refuted`
during a loaded census run and `pass` on the confirmation run. Probed:
five sequential isolated runs all pass, and eight concurrent runs of that one
file all pass. The flip has been seen twice across census runs, and does not
reproduce on demand.

No claim is made about the mechanism. It is not the instrument: each worker
verifies inside its own copy of the tree, and each run deletes the sidecar it
writes, so runs cannot see one another. **Route to the compiler team as a new
row**: a `verify` verdict that flips to UNSAFE under load is a false refutation,
and the trust surface treats a refutation as evidence. The census reports the
file as `unstable`, names it, and does not fail the build on it.

### 12.5 Four divergences from the plan

1. **The population comes from `git ls-files`, not a filesystem walk.**
   `tools/llmll-driver/generated` is 107 MB of gitignored `llmll build` output
   and contributes zero files to the population; a filesystem walk copied it.
   Enumerating from the index also matches what the ratchet is about, which is
   the committed tree. Population: 250 tracked files, not the ~190 the plan
   projected from `examples/`.
2. **Cost is 6 minutes, not one, and three files are most of it.** The plan
   extrapolated 0.04-0.30 s per file from `examples/`. Measured:
   `examples/heartbleed/secure-channel/sc-channel.llmll` takes **130 s with the
   machine to itself** and 253 s under four workers, its agent-filled twin 288 s,
   and `examples/secure-channel-emergent/work/spine.ast.json` 173 s. The other
   247 files together take about four minutes. Two rounds of work brought the
   number down: per-worker parallelism from 6 min 25 s sequential, then taking
   the biggest files first from 8 min 17 s to 6 min 4 s. The workflow runs on
   pushes to main and on pull requests, so the cost is paid per PR. **This is
   the one decision in the change set worth the user's attention**; moving the
   step to a schedule needs no change to the instrument.
3. **Three mechanisms the plan did not have, all forced by measurement.** The
   first parallel version raced: two runs over one tree disagreed on 34 files.
   The fix is three parts, and all three are needed. Each worker gets its own
   copy of the tracked tree. Each run deletes the sidecar it creates. Every
   negative verdict is re-run alone before it is believed. With those, the
   record is byte-identical at `--jobs 3` and `--jobs 8`, except for the one
   file whose own verdict is unstable. Three later runs at `--jobs 4` agree on
   every number: ratio 0.984, 695 of 706, 98 files passing strict.
4. **A fourth file outcome, `no-goal`.** The plan had `scaffold` and `fallback`.
   A file whose every refusal is `no-post` is neither, and 31 files are exactly
   that. Folding them into `fallback` is the error §5 made at function level.

Also outside the plan's affected surface: `.gitignore` gains
`scripts/tests/fixtures/**/*.verified.json`, because the `LLMLL_BIN` cells
verify the fixtures in place and `llmll verify` writes a sidecar beside each
file it reads.

### 12.6 Hand-off to documentation-lead

Ticket tag `FALLBACK-CENSUS-1` (G1 rank 1), with `SHELL-FALLBACK-SILENT-1`
still open at **DECIDE** and unblocked by §10.

**User-visible behaviour.** `llmll verify --json` and
`llmll verify --json --strict-verified-core` each gain two keys:
`body_fallback_constructs` (per function, the constructs that refused its
contract clause) and `fn_kinds` (per function, its definition form). The strict
path additionally gains `body_faithful`, `body_fallback` and
`body_fallback_causes`, which it did not carry before, so one reader shape
serves both exit paths. Two new `fallback_reason` values appear on all three
report surfaces: `unfilled-hole`, for a body that is or contains an unfilled
hole, and `no-post`, for a function with no post clause after the return
refinement is folded in. Both replace `body-outside-fragment` and
`contract-post-outside-fragment` respectively for those shapes, so a
`--strict-verified-core` message that used to read
`f (contract-post-outside-fragment)` now reads `f (no-post)`.

**Schema delta.** `docs/proof-artifact.schema.json`, `fallback_reason` enum
gains `unfilled-hole` and `no-post`. Additive, no `$id` change, the v0.19.0
precedent. Older artifacts still parse and still replay.

**New gate.** `scripts/fallback_census.py` plus
`scripts/fallback-census/BASELINE.json` and its README, run in the
version-gate toolchain job with the record uploaded as a workflow artifact.

**Test delta.** hspec 1891 to 1908. pytest 220 collected to 241; 200 passed and
20 skipped to 218 passed and 23 skipped.

**CHANGELOG `## Latest` candidate.** "The body-faithful ratio is measured every
CI run instead of by hand: two label-only fallback causes separate an unfilled
scaffold and a function with no post from a body that left the fragment, each
refused contract clause names the constructs that refused it, and a ratchet
holds the strict-verified-core pass set."

**Spec drift to flag, not to fix here.** `LLMLL.md` §14 documents the
`verify --json` surface and does not yet name any of the five new keys; the
`--strict-verified-core` message text is also unversioned there. Both are
documentation-lead's call, and neither side of the compiler is wrong.

**Roadmap.** Row `FALLBACK-CENSUS-1` is complete on all three triage items, so
it moves out of G1. Row `DRIVER-LL`'s Next Action item (2) keeps
`SHELL-FALLBACK-SILENT-1` and loses `FALLBACK-CENSUS-1`. Two new rows are owed
and are described in §12.3 and §12.4.

### 12.7 What the four `check`-failing files are

None is a defect this change introduced, and each is a different thing:

- `examples/heartbleed/secure-channel/agent-fill/modules/sc-m7-spine.llmll`
  is one module of a multi-module tree and does not resolve `mac-verified`
  when verified alone.
- `examples/totp_rfc6238/totp_filled.ast.json` is the `TOTP-CHECK-1` row,
  already open: a committed sidecar for a program that fails `check`.
- `tools/llmll-driver/crux-gate-coverage-threshold.llmll` and
  `crux-shell-undeclared-authority.llmll` are cruxes whose refutation channel
  is `check` rather than `verify` (non-core body, missing capability import).
