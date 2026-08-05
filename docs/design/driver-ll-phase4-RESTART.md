---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE. Written 2026-08-04 so a cleared session can resume without re-deriving anything. Delete when Phase 4 closes."
date: 2026-08-04
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# DRIVER-LL Phase 4 — restart record

Read this first, then
[`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) (Rev 5, SETTLED). Everything else is
downstream of those two.

## 1. Where the work is

Committed to branch **`driver-ll/phase-4`** at `4423287`, one commit above `main` (`0ed395b`,
v0.14.83). **Not pushed.** `main` is untouched and clean.

| Path | State in `4423287` |
|---|---|
| `docs/design/driver-ll-phase4-proposal.md` | new, Rev 4, SETTLED, READY FOR ENGINEER |
| `docs/design/driver-in-llmll-campaign.md` | modified, §Phase 4 → Rev 5 |
| `experiments/rfc-swarm/DRIVER-LL-PHASE4-HARNESS-FINDINGS.md` | new, six findings, F-1 closed by proposal §3.5 |
| `scripts/tests/test_rfc_pipeline_integration.py` | modified, 15 → 19 tests |
| `docs/design/driver-ll-phase4-RESTART.md` | this file |

`scripts/rfc_to_implementation.py` is **unchanged** and must stay that way until the §3.5 repair is
taken deliberately: it is the live driver.

**Verification state at the time of writing:** `python3 -m pytest scripts/tests/ -q` → 111 passed.
`python3 scripts/doc_path_lint.py` → 735 citations, all resolve. No compiler build was run this
session; no Haskell was touched.

## 2. What Phase 4 is, in four sentences

Port the eleven agent-delegated stages (B, C, D, F, **G**, H, I, K, M, N, O) and the serial wave into
`tools/llmll-driver/` as `def-shell` orchestration. Stage G was omitted from the campaign's original
list and is on the critical path, since it produces the input to G2 and to both of gate J's
disposition conditions. Acceptance is three clauses (proposal §2), not artifact reproduction, which
was measured unsatisfiable. The phase activates `fill.*` and `token.token-during`, which have had no
caller since v0.14.70.

## 3. Task queue

| # | Task | Role | State |
|---|---|---|---|
| 1 | Campaign doc §Phase 4 → Rev 5 | language-team | **done** |
| 2 | Harness items (a)(b)(c) | experiment-lead | **done**; item (d) split out to #7, now unblocked |
| 7 | Adjudicate F-1/F-2/F-3 | language-team | **done**, landed as proposal §3.5 |
| 3 | `FS-ENCODING-1` + `wasi.fs.copy` | compiler-engineer | **pending, unblocked** |
| 8 | Python-side §3.5 repair (was item d) | experiment-lead | **pending, unblocked by §3.5** |
| 4 | Sub-phase 4a: sequencer, manifest, two halt channels | compiler-engineer | pending; wants #8 landed first |
| 5 | Sub-phases 4b–4f | compiler-engineer | pending, blocked by #4 |
| 6 | Doc-lead pass: INDEX, roadmap, open-work rows | documentation-lead | pending, runs last |

## 4. The next action

Either of #3 or #8; they are independent and neither blocks the other.

**#3 is the smaller.** `FS-ENCODING-1`: pin UTF-8 on `wasi.fs.read` / `wasi.fs.write`
([`CodegenHs.hs:506-508`](../../compiler/src/LLMLL/CodegenHs.hs), `:533-535`) and return `RErr` on a
decode failure rather than throwing inside a `Command`. Measure the blast radius first; the
expectation that it is zero because the corpus is ASCII is an expectation, not a measurement.
`wasi.fs.copy`: one `builtinEnv` signature, one `primEffect` clause mapping to
`Caps {EFsRead, EFsWrite}` on the `wasi.fs.sha256` precedent
([`ObligationAssembly.hs:448`](../../compiler/src/LLMLL/ObligationAssembly.hs)), one codegen case,
`RNone`, no new label and no new `Response` arm. Both are proposal §8 and §14.

**#8 is now mechanical**, which it was not before §3.5. **37** halt sites move to `failed`; nine stay
`stopped` and are listed by clause in proposal §3.5. `require()` needs a second raising form so the
disposition rides the clause rather than the validator. **Rev 5 changed the count from 38.** `:866`
(stage H) is held at `stopped` and changes constructor rather than status: it fires after its stage
wrote a declared output, which proposal §3.6 shows is a second classification axis §3.5 omitted.
Holding it is the conservative action under both readings of §4:146-147, so #8 does not wait on that
question being settled.
`test_exclusion_outside_the_barrier_list_halts_the_run` must keep asserting `stopped`: it is the
witness that the rule does not over-fire.

## 5. Sequencing lesson, already paid for once

Experiment-lead work **generates** the compiler-engineer's queue rather than following it. Running
the harness leg first is what produced §3.5; had 4a been built first it would have been built against
a four-condition halt model that does not exist. Two of the six harness findings corrected this
proposal's own claims, and one corrected an attribution that a truncated grep had put in the wrong
spec section.

## 6. Gotchas

- **Stale binary.** `stack exec` from the repo root runs the wrong compiler. Before any compiler
  work: `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH` and check
  `llmll version`.
- **The doc path lint gates CI.** `scripts/tests/test_doc_path_lint.py::test_clean_on_live_repo` runs
  in `version-gate.yml`, so an unresolved prose citation leaves `main` red. A backticked
  workdir-relative path, of the stage-directory-slash-filename shape a stage output naturally has,
  reads as a repo path and fails; name the artifact by role instead. Writing that example out in
  backticks is itself enough to trip the lint, which is how this line broke it once. Bare filenames
  are safe: `doc_path_lint.py:150-151` skips any citation with no slash in it.
- **Stage G2 still cannot run under the stub.** Its citation check scores every stub citation below
  `CITATION_RESOLVES_AT` because the rows quote `"q"` against SPEC lines that do not contain it.
  Fixing it needs stub rows whose quotes are drawn from the pinned bytes. Filed as harness finding
  F-4, not bundled into the wave work.
- **Do not read `driver-spec.txt`'s structure from `grep -nE "^[0-9]*\.  [A-Z]"`.** It truncates at
  section 9 because sections 10 and up use a single space. §10 through §15.4 exist and two of them
  carry conditions this proposal originally attributed to §7.
