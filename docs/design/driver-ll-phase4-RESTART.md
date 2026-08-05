---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE. Rewritten 2026-08-04 after the phase's first three tasks merged as v0.14.84. Delete when Phase 4 closes."
date: 2026-08-04
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# DRIVER-LL Phase 4 — restart record

Read this first, then [`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) (Rev 5,
SETTLED). Everything else is downstream of those two.

## 1. Where the work is

**Merged to `main` at `092943a`, released as v0.14.84.** The `driver-ll/phase-4` branch is merged
and can be deleted. **Nothing is pushed**; `origin` is still at v0.14.83.

Verified on the merged tree: `llmll version` → 0.14.84, `scripts/version_gate.sh` DRIFT-CI-1 PASS
across all five pins, **1616** Haskell examples, **115** Python, `doc_path_lint` 759 citations all
resolve, `build_smoke.sh` four stages green.

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
| **4** | **Sub-phase 4a: sequencer, manifest, resume gate, two halt channels. No stage bodies.** | **compiler-engineer** | **PENDING, UNBLOCKED — this is next** |
| 5 | Sub-phases 4b–4f | compiler-engineer | pending, blocked by #4 |
| 6b | Doc-lead pass at each sub-phase | documentation-lead | pending, runs after each |

## 4. The next action

**Task #4, sub-phase 4a**, and it is the only unblocked item. Proposal §9 gives the row:

> Lands: sequencer, manifest, resume gate, **two halt channels**. No stage bodies.
> Proved cores activated: `skip.may-skip`, `stage.record-outcome` (all four `Outcome` arms).
> Acceptance: the transition cover of §2.3 passes.

Three things the last session settled that 4a depends on, so do not re-derive them:

1. **The halt model is three-way, not two-way.** `stage.record-outcome` proves four `Outcome`
   constructors; §3.5's clause-source rule and §3.6's artifact-state axis together decide which one
   a site constructs. The Python reference now encodes this and its manifest rows carry an
   `outcome` field naming the constructor, so the port has a worked example to check against rather
   than a rule to re-interpret.
2. **The transition cover is nine, not eight.** §2.3 records the ninth (artifacts present, no
   completion record) and the measurement that corrected the count.
3. **`:866` is held at `stopped` deliberately.** Two derivations point opposite ways; §3.6 records
   both and takes the conservative one. If 4a's port disagrees, that is a finding, not a bug.

## 5. Sequencing lesson, paid for twice now

Experiment-lead work **generates** the compiler-engineer's queue rather than following it. Running
the harness leg first is what produced §3.5; running it a second time, to execute the repair, is
what produced §3.6 and caught a regression no test covered. Two of the six harness findings
corrected this proposal's own claims, and the compiler leg corrected two more of its claims after
that. The pattern is consistent: **the design document has been wrong in a checkable way at every
revision, and the thing that caught it was executing something.**

## 6. Open work Phase 4 has filed and not closed

| Tag | What | Where |
|---|---|---|
| `FS-STAT-1` | No file mtime, so `liveness.advancing` has no callable data source. Blocks driver-spec §12:405-428 via a §15.2 capability gap; the §15.1:511 proof obligation is already discharged | proposal §14 |
| `PROC-ENV-1` | `wasi.proc.run` has no env parameter; named-not-scheduled | proposal §14 |
| `SPEC-TIER-1` | driver-spec §15.1's tiering clause cannot classify its own §13. Target-spec defect; the source is pinned so it is recorded, not repaired | proposal §14, harness findings F-8 |
| `F-7` | Stage O is the only delegated stage with no validator; driver-spec §13 is its specification. Lands at sub-phase 4f | harness findings F-7 |
| (unnamed) | `emitMatch` suppresses its catch-all on a mixed constructor/literal match | proposal §10 case 6 |

**Neither `FS-STAT-1` nor `PROC-ENV-1` has a roadmap row**, unlike the two that shipped. Routing
that is language-team's call, not doc-lead's.

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
  `LC_ALL`, so `build_smoke.sh` stage 5b is honest on Linux and a no-op locally. The first CI run on
  `main` at v0.14.84 is the confirming test, and it has not happened.
