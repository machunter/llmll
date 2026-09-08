---
name: driver-ll-phase4d-implementation-plan
title: "DRIVER-LL sub-phase 4d: implementation plan and running record"
status: "APPLIED TO REVIEW-READY on 2026-09-08 on branch driver-ll-4d/stages-h-k-n, NOT COMMITTED. Stages H, K and N are ported and the acceptance cover runs them against the real compiler: 52 passed, 0 failed (39 before). The census prerequisite the roadmap named was found already done at 3a4046b (2026-08-06); one residue test closes it. Update this field at commit and again at release."
date: 2026-09-08
author: compiler-engineer
consumers: [compiler-engineer, language-team, experiment-lead, documentation-lead, user]
---

# DRIVER-LL sub-phase 4d: implementation plan and running record

Port stages H, K and N into `tools/llmll-driver/` as `def-shell` orchestration
around the proved cores that shipped ahead of them at v0.14.88:
[`oracle.llmll`](../../tools/llmll-driver/oracle.llmll) (four defs) and
`shape.probe-rows-conform?`. Read proposal §9.3 and the restart record's §6 items
6 and 7 first.

## The prerequisite was already done

The roadmap's G0 row says "Next: the 4d census prerequisite, then sub-phase
4d". Commit `3a4046b` (2026-08-06, first tagged v0.14.88) did the prerequisite:
[`scripts/tests/test_driver_ll_4c.py`](../../scripts/tests/test_driver_ll_4c.py)
splits the multi-invocation census by receiver (`_is_agent_run`) and asserts
the runner is never aliased. The 2026-09-07 regroup carried the proposal's
§9.3 item 1 forward without a `git log` check.

One residue survived, and it is one test. The census walks each stage
handler's own body, so a `ctx.agent.run` inside a top-level helper would be
qualified, unaliased and invisible. Measured by AST: all nine delegations sit
in `stage_*` handlers. `test_every_agent_delegation_sits_in_a_stage_handler`
pins the placement, not the count.

## What landed

**Registry** ([`registry.llmll`](../../tools/llmll-driver/registry.llmll)).
`stage-ported?` claims nine (H is 8, K is 11, N is 14). Rows for the three
stages in `stage-prompt`, `stage-agent-label`, `stage-pre-count`,
`stage-pre-path`, `stage-pre-mode`, `stage-pre-key`, `stage-needs-src?` (K
only). One new precondition mode, **3 FILTER**: parse, project `rows`, keep
the rows whose `stage-pre-filter-key` equals `stage-pre-filter-val`, the
reference's `r["disposition"] == "Encoded"`, as two stage-contract constants.
Four new tables: `stage-needs-llmll?` (H, K), `stage-provision-ref?` (H, K,
N), `stage-oracle` (H 1, K 2, N 3) and **`stage-agent-out`**, the file the
agent writes, which for H and N is not the declared output. `stage-shape`
gives H tag 4.

**Sequencer** ([`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll),
1785 to 2450 lines, 271 statements, still SAFE with no flags). `Cfg` widens
at the tail with `--reference-dir`; `--llmll-cmd` joins `missing-flags`, so
the `parse-cfg` comment that said REQUIRED since `4c0014f` is now true.
`render` substitutes `{{llmll}}`. `delegate-cmd` copies `LLMLL.md` and
`docs/llmll-ast.schema.json` into the agent directory (`_provision_reference`)
when `--reference-dir` is given; the copies are unchecked, as `shutil.copy2`
is. `shape-verdict` reaches `probe-rows-conform?` as tag 4. A `Loop` payload
type and ten `Ctl` arms: `HGood`, `HMut`, `HOutG`, `HOutM`, `HWrote`,
`KCheck`, `NRow`, `NSkip`, `NOut`, `NWrote`. `outp-pass` dispatches on
`stage-oracle`; the 4b/4c path is `outp-next`. Each proved def is forwarded
once (`probe-ok?`, `feasible?`, `as-expected?`, `complete-matrix?`), the 4e
pattern. The header gains a section 7 statement for the `oracle` abstraction.

**Cover** ([`scripts/driver_ll_cover.py`](../../scripts/driver_ll_cover.py)).
A required `--llmll`; `drive()` passes `--llmll-cmd` and `--reference-dir`;
stub modes that write real LLMLL probe, mutant and root files; thirteen cells
(H1 to H5, K1 to K3, N1 to N4, F0). Every cell runs the real compiler. T4,
the injector's PartialThenHalt cell, becomes `@local4a`: its rig mirror moved
to H1, the real site. `build_smoke.sh` stage 8 passes `--llmll`.

**Tests.** [`test_driver_ll_4d.py`](../../scripts/tests/test_driver_ll_4d.py),
thirteen tests, no toolchain. The 4c tier's `PORTED` is nine plus the residue
test. The callers census loses its five `4d-parked` rows, its orphan set is
`{liveness, shell}`, and the `cfg-llmll` guard inverts to "read, defined
once". The mirror count stays seventeen.

## Divergences from the reference, disclosed

1. **The exit status of `llmll verify` is not read.** The port folds run and
   read into one command (the wave's idiom); `safe` keys on the SAFE line.
   Measured at v0.21.0: a SAFE run exits 0, a refuted or fallen-back strict
   run prints no SAFE line and exits 1. No transcript decides differently.
2. **The file stem is not compared.** The reference's `body_faithful` compares
   a FILE stem against FUNCTION names in the `body-fallback:` list. The port
   asks for a `body-faithful:` line and no `body-fallback:` line. Stronger,
   and subsumed by the SAFE conjunct under `--strict-verified-core`.
3. **K's detail names the transcript** (`10-roots/check.stdout.log`) rather
   than embedding 3000 bytes, as `delegate-step` names `agent.stderr.log`.
4. **K's reads land before its sources.** The Pre loop reads the inventory and
   the scope, then lists `00-source`; the reference reads the sources between
   them. Only the detail string on a doubly broken workdir differs.
5. **H's row omits `returncode` and the 4000-byte `output` tail**; the whole
   transcript is `verify-<idx>-<half>.stdout.log` in the agent directory.
6. **N's `reason` is `""` where the reference carries null**, and a catalogue
   that is not an array records `failed` where the reference tracebacks.
7. **`matrix-complete?` decides before the write.** Its false branch is
   unreachable by construction and is written down as such at the site.

## What a run found that no static check could

The first cover run handed the agent the DECLARED output path
(`feasibility.json`) where the reference's `ctx.agent.run` asks for
`probes.json`. The stub wrote a placeholder under the declared name, the
shape check rejected the driver's own placeholder, and five cells failed with
"expected a list of probes". Restart record §6 item 6 had named this exact
inversion and said it needed a table, not just registry rows; the plan read
it and still conflated the two names. `stage-agent-out` is the table, and
`test_stage_agent_out_names_the_two_catalogues` pins it against the
reference's `out_name` arguments.

## Gates at the checkpoint

| Gate | Figure |
|---|---|
| `stack test` | 1891 examples, 0 failures (no Haskell touched; measured before the branch) |
| `pytest scripts/tests/` | 195 passed, 20 skipped (was 181; +1 residue, +13 4d tier; the skips need `LLMLL_BIN`) |
| `scripts/driver_ll_cover.py` | 52 passed, 0 failed (was 39), about 7 s wall-clock with the real compiler |
| `llmll verify sequencer.llmll`, `registry.llmll` | SAFE, no flags, as frozen; sidecars unchanged |
| `llmll check sequencer.llmll` | OK, 271 statements, 20 warnings (trust gaps of imported asserted defs and the `:done?` warning, as before) |
| refute-crux gate | not re-run in full; the two changed modules re-verified by hand to their frozen verdicts |

## Routing

- **documentation-lead**: the G0 row's "Next" pointer and the restart
  record's status field are stale (prerequisite done at `3a4046b`; stage A's
  STOP lifted at v0.21.0); 4d needs a CHANGELOG entry and a version, which
  4a and 4c never got; this file needs its INDEX row.
- **language-team**: proposal §9's 4d row says "Proved cores activated: none
  new" while `oracle.llmll` and `probe-rows-conform?` shipped for 4d; the rig
  has no stage N mode, so N's cells have no reference mirror by construction.
- **compiler-engineer**: `PROC-TIMEOUT-1` now reaches the compiler runs; no
  cell claims the overrun. Next is the stage A port on its own branch.
