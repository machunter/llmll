---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE. Rewritten 2026-08-04 after the phase's first three tasks merged as v0.14.84; updated 2026-08-05 for proposal Rev 7; the harness leg ran and sub-phase 4a is unblocked. Delete when Phase 4 closes."
date: 2026-08-05
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# DRIVER-LL Phase 4 — restart record

Read this first, then [`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) (Rev 7,
SETTLED). Everything else is downstream of those two.

**Thirty-second version.** Phase 4's first three tasks shipped as v0.14.84 and are merged. The
2026-08-05 session took the proposal from Rev 5 to Rev 7 and ran the harness leg that Rev 6 had put
in front of sub-phase 4a. **Sub-phase 4a is now unblocked and is the next action** (§4). Six files
are modified and uncommitted (§1). Two roadmap edits and three routing rows are waiting on doc-lead
and block nothing (§3 row 10, §6). The one thing not to re-derive: the acceptance criterion for 4a
is Rev 7 text and the transition count moved twice, from eight to nine to **eleven**, all eleven of
which now have a test.

## 1. Where the work is

**Committed and merged:** `main` at `c4c07f5`, released as v0.14.84. The `driver-ll/phase-4` branch
is merged and can be deleted. **Nothing is pushed**; `origin` is still at v0.14.83, so `main` is ten
commits ahead.

**UNCOMMITTED, and this is the part a fresh session will not otherwise know about.** Six files are
modified in the working tree from the 2026-08-05 session (proposal Rev 6 and Rev 7, plus Task #9's
harness leg). Nothing is staged. No commit was authorized.

| File | What changed | Role that wrote it |
|---|---|---|
| `docs/design/driver-ll-phase4-proposal.md` | Rev 5 → **Rev 7**. The big one, roughly 460 lines | language-team |
| `docs/design/driver-ll-phase4-RESTART.md` | this file | language-team |
| `docs/design/driver-ll-open-work.md` | R-14 (`PROC-ENV-1`) and R-15 (`STATE-PROD-1`) | language-team |
| `experiments/rfc-swarm/DRIVER-LL-PHASE4-HARNESS-FINDINGS.md` | new session block, findings F-9/F-10/F-11 | experiment-lead |
| `scripts/rfc_to_implementation.py` | `read_manifest()` at `:212`, called at the resume read | experiment-lead |
| `scripts/tests/test_rfc_pipeline_integration.py` | one `STUB_MODE` (`silent-scope`) and five tests | experiment-lead |

**Verify the tree before trusting any of it:**

```
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
llmll version                      # expect 0.14.84
python3 -m pytest scripts/tests/ -q   # expect 120 passed (was 115)
python3 scripts/doc_path_lint.py      # expect 764 citations, all resolve
python3 scripts/rfc_to_implementation.py --self-test   # expect PASS
```

The Haskell suite (1616 examples) and `build_smoke.sh` were **not** re-run this session and did not
need to be: no compiler source changed. Re-run them before any commit that touches `compiler/`.

**If the uncommitted work is to be committed**, it splits cleanly in two and should: the three
`docs/design/` files are one commit (the Rev 6 and Rev 7 specification work), and the three
`scripts/` plus `experiments/` files are another (Task #9's harness leg, which has its own positive
witness recorded in the findings). No version bump is owed, because no compiler source changed and
the pins are already at 0.14.84.

## 2. What Phase 4 is, in four sentences

Port the eleven agent-delegated stages (B, C, D, F, **G**, H, I, K, M, N, O) and the serial wave
into `tools/llmll-driver/` as `def-shell` orchestration. Stage G was omitted from the campaign's
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
| 9 | Harness leg for 4a: T7 test, the guarded manifest read, §10 cases 16–18 | experiment-lead | **done**, uncommitted. 115 → 120 Python tests; findings F-9/F-10/F-11 |
| **4** | **Sub-phase 4a: sequencer, manifest, resume gate, two halt channels. No stage bodies.** | **compiler-engineer** | **PENDING, UNBLOCKED. This is next** |
| 5 | Sub-phases 4b–4f | compiler-engineer | pending, blocked by #4 |
| 6b | Doc-lead pass at each sub-phase | documentation-lead | pending, runs after each |
| 10 | Two roadmap rows (`FS-STAT-1` re-scoped, `MATCH-CATCHALL-1`), `CLAUSE-INDEP-1` under the layer-3 row, two DRIVER-LL notes additions, one stale internal cross-reference | documentation-lead | pending, parallel, blocks nothing |

## 4. The next action

**Task #4, sub-phase 4a.** The harness leg ran and unblocked it. 4a now has a red/green target rather
than a description: **eleven of eleven cover cells and all three corrupt-manifest shapes have a
Python-side test**, where at Rev 6 the count was ten of eleven and zero of three.

Proposal §9 gives the row. Its acceptance cell is Rev 7 text, not Rev 5 text; the count moved twice.

What the harness leg changed for the port, beyond the tests:

1. **`read_manifest`** (`rfc_to_implementation.py:212`) guards three corrupt-manifest shapes and
   raises `StageFailure`, which the top-level `except Halt` renders as exit 2. The port needs a
   defined transition for all three, not two: the third is a well-formed object with a list at
   `stages`, and it dies at the resume gate's own indexing expression rather than at the read.
2. **`AgentRunner.run:331-334` already enforces §7:279.** Rev 6 said the reference could record
   `complete` over a missing declared output and it cannot, for the eleven agent-delegated stages.
   The port is matching behaviour here, not correcting it.
3. **T7 is measured**: the stage re-runs and prints no reason line. The test asserts the decision,
   not the silence, and the port is free to report or not.

Five things Rev 5, Rev 6 and Rev 7 settled that 4a depends on, so do not re-derive them:

1. **The halt model is three-way, not two-way.** `stage.record-outcome` proves four `Outcome`
   constructors; §3.5's clause-source rule and §3.6's artifact-state axis together decide which one
   a site constructs. The Python reference now encodes this and its manifest rows carry an
   `outcome` field naming the constructor, so the port has a worked example to check against rather
   than a rule to re-interpret.
2. **The transition cover is eleven, and all eleven now have a test.** Rev 6 derives it as a product
   over three axes instead of enumerating it, because the count moved at every revision. T4 (a halt
   after writing output) and T7 (complete record, declared artifact absent) were both missing.
3. **Clause 1a needs the abstraction function α of §2.1 and is unsatisfiable without it.** A complete
   row carries a wall-clock `seconds`; the halt rows carry Python exception text as `detail`. α
   discards the first and weakens the second to a non-emptiness predicate.
4. **`:866` is held at `stopped` deliberately.** Two derivations point opposite ways; §3.6 records
   both and takes the conservative one. If 4a's port disagrees, that is a finding, not a bug.
5. **A grep over a design document's vocabulary is not a code audit.** Four mechanism claims in this
   phase have been refuted the same way, most recently Rev 6's, and all four were caught by running
   something. Proposal risk 3c. If 4a's port disagrees with the proposal, execute the disagreement
   before writing the correction.

**Do not emit `"outcome": "Finished"` on a complete manifest row.** The reference emits no `outcome`
field there (`:1950-1956`), α retains `outcome`, and the uniform port breaks clause 1a on the most
frequent transition in any run. §4 states it as a specified decision.

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

Rev 6 routed all of these. The table was also short by two, `FS-ISOLATION-1` and `STATE-PROD-1`
being filed in proposal §14 and absent here.

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

## 7. Gotchas

- **Stale binary.** `stack exec` from the repo root runs the wrong compiler. Before any compiler
  work: `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH` and check
  `llmll version` reports **0.14.84**.
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
- **macOS cannot reproduce the FS-ENCODING-1 condition.** GHC on macOS uses UTF-8 regardless of
  `LC_ALL`, so `build_smoke.sh` stage 5b is truthful on Linux and a no-op locally. The first CI run
  on `main` at v0.14.84 is the confirming test, and it has not happened.
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
  since a rename is grep-detectable where a line shift is not. **The roadmap has the same defect
  internally**: its layer-3 row at `:210` cross-references CDP at `:224`, which is now a table header.
- **The driver's stage-selection flag is `--only`, not `--stages`.** The rig's fixture takes a
  `stages=` keyword and maps it (`test_rfc_pipeline_integration.py:275`). A hand-rolled invocation
  using `--stages` dies in argparse with exit 2, which reads exactly like a deliberate `Halt` and
  cost a debugging cycle on 2026-08-05.
- **`pytest tmp_path` lives under `/var/folders`, which the driver refuses as a run directory.** Pass
  `--allow-volatile-workdir`; the rig already does.
