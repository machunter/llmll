---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE. Current as of 2026-08-05 end of session. Sub-phases 4a and 4b are SHIPPED, the proposal stands at Rev 9, three releases went out (v0.14.85, v0.14.86, v0.14.87), and the phase runs at 4c. The last three commits are unpushed. Delete when Phase 4 closes."
date: 2026-08-05
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# DRIVER-LL Phase 4 — restart record

Read this first, then [`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) (**Rev 9**,
SETTLED). Everything else is downstream of those two.

**Thirty-second version.** **Sub-phases 4a and 4b are SHIPPED** (`2b82464` v0.14.85, `ba2f93d`
v0.14.87) and the phase now runs at **4c**, stages D, F and G. The proposal stands at **Rev 9**. The
2026-08-05 session took it from Rev 5 to Rev 9, ran the harness leg, found 4a blocked at the process
boundary, specified and shipped the capability that unblocked it (`PROC-BOUNDARY-1`, v0.14.85),
ported 4a against it **with no shim**, re-measured §3.5, and ported 4b. Three releases shipped:
v0.14.85, v0.14.86 and v0.14.87. Everything is committed; the last three commits are **unpushed**
(§1).

**The one thing not to re-derive.** Closing the capability before porting is what bought the no-shim
result. A shim would have sat between the rig and the thing under test and mediated every 4a
acceptance result, which is the one property 4a exists to establish. The same instinct is why §9.1
settles what 4b may and may not invent.

## 1. Where the work is

**`main` is at `1bc2965`, working tree clean.** `origin` is at `ba2f93d`, so **the last three commits
are unpushed**: the v0.14.87 pins, the v0.14.87 release docs, and this record. CI was green at
`ba2f93d`.

**Push early.** The one thing this session proved the hard way is that local gates are not the gates.
`main` sat red for two days on a defect no macOS run could reach, because `build_smoke.sh` stage 5b
is a structural no-op here: GHC on this platform returns UTF-8 from `getLocaleEncoding` under every
locale. The stage now prints **NOT EXERCISED** on Darwin instead of a PASS it has not earned, so a
green local run no longer implies the encoding claim was tested.

**The installed binary is STALE.** Pins say 0.14.87; the binary was built at 0.14.86. Rebuild before
trusting any CLI result.

```
(cd compiler && stack build)
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
llmll version                          # expect 0.14.87 AFTER the rebuild
python3 -m pytest scripts/tests/ -q    # expect 131 passed, 1 skipped
python3 scripts/doc_path_lint.py       # expect 865 citations, all resolve
bash scripts/version_gate.sh           # expect PASS at v0.14.87
```

Heavier gates, all green at `ba2f93d` and unaffected by the docs commits since: Haskell **1651
examples**, `build_smoke.sh` **6 stages** (the `LC_ALL=C` half NOT EXERCISED on macOS, which is not a
failure), `refute-crux-gate.sh` **71 passed**.

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
| **5c** | **Sub-phase 4c: stages D, F, G** | **compiler-engineer** | **PENDING, UNBLOCKED. This is next** |
| 6b | Doc-lead pass at each sub-phase | documentation-lead | pending, runs after each |

## 4. The next action

**Sub-phase 4c: stages D, F and G.** 4a and 4b are shipped and their plans are in the design folder.
§9 of the proposal gives 4c's row; its acceptance is that stage E's Phase 3 pins reproduce over D's
own output.

**Stage G is on the critical path and was omitted from the campaign's original list** (§2). It
produces the input to G2 and to both of gate J's disposition conditions, so it is not optional and
its absence is why the stage enumeration was corrected in the first place.

**Four things 4b settled that 4c inherits, so do not re-derive them:**

1. **The shared validation facility exists**, in `validate.llmll`. `verdict-of` takes **no string**,
   which is the property that keeps a subject's conventions out of the validator, and
   `[V7-NO-HARDCODE]` refutes a validator fitted to one run's sizes. 4c extends it rather than
   writing a second one.
2. **Cite §3.5's halt sites by CONDITION, never by line number** (§3.5.1). Two of the nine
   spec-defined line numbers now point at sites with the **opposite** disposition, so a reader keying
   on the number lands on a plausible-looking site and nothing signals the miss.
3. **A validator where the reference has none is new behaviour and does not ride in on a port.**
   Stages I and O both have none; both are disclosed and both land at 4f.
4. **`PROC-TIMEOUT-1` is open** (§9). `wasi.proc.run`'s timeout does not fire, so any budget-overrun
   path 4c writes is unreachable through the timeout the same way 4b's is.

**The method that has paid every time, six for six.** Every refuted mechanism claim in this phase was
a grep over the name a design document uses, where the code enforces the same obligation under a
different name one call frame away. The most recent was this proposal's own Rev 8 stamp, which used a
grep to correct a stale count and produced a wrong one. If a claim rests on a grep, execute it. If
the port disagrees with the proposal, execute the disagreement before writing the correction.

**Run experiment-lead before compiler-engineer.** Harness work generates the engineer's queue rather
than following it: it produced §3.5, then §3.6, then refuted Rev 6, then refuted Rev 8 and settled
what 4b needed. Four times, four findings the port would otherwise have hit mid-build.

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
  `llmll version` reports **0.14.87**, which needs a rebuild: the pins moved and the binary did not.
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
  the 4a plan; it wants a roadmap row and has none yet.

## 9. The release that was owed is DONE

v0.14.87 shipped (`5a4832c` pins, `1bc2965` docs). It carried the two builtin fixes, sub-phase 4b,
three doc repairs, and two roadmap rows. This section is kept only to record what it closed and what
it deliberately did not:

- **`PROC-TIMEOUT-1` is filed and NOT fixed.** `wasi.proc.run`'s timeout does not fire in a built
  program: `--timeout 1` against a 30-second agent exits 0 with `seconds: 30`, and the binary reports
  `RTS way: rts_v`. **Adding `ghc-options: -threaded` to the generated package did NOT move the RTS
  way**, so the one-line fix measures identically to no change. The roadmap row says so in bold.
  Consequence: 4b's budget-overrun halt is written and unreachable through the timeout path.
- **A closure note is owed to compiler-engineer.** `PROC-TIMEOUT-1` originates in a finding inside
  `driver-ll-phase4b-implementation-plan.md`, which doc-lead does not edit. The row is its
  destination.
- **The v0.14.85 shipped row records 120 Python where the figure was 123.** Left alone deliberately:
  shipped rows are append-only, and silently correcting one is how a release record stops being a
  record. Its own pass if wanted.

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
