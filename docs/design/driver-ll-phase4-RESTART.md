---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE, and its NEXT POINTER HAS NOW BEEN CORRECTED FOUR TIMES. The defect is the same every time: a refresh corrects the body and leaves this field, and a restarting session reads this field first. The defect has an owner. It is filed as RECORD-FRESH-1 in roadmap group G8, drafted at `record-fresh-1-proposal.md`, and this correction is that row's fourth data point. 2026-08-18 corrected a pointer that still named the CI-gate port after that port had closed at v0.16.1 (`196969a`; recorded in docs/design/tool-ll-RESTART.md). 2026-09-10 corrected a field that called 4d parked and stage A a filed STOP after both had shipped (`ea41731`); the refresh that day (b7ccee4) corrected sections 2, 6, 8 and 10 and LEFT THIS FIELD. 2026-09-10, later the same day, corrected it a third time after sub-phase 4f shipped, which this field still called not started (`ce6c830`). 2026-09-11 corrects it a fourth time, and this instance is the sharpest measurement the defect has produced. MEASURED: 25 non-merge commits landed after `ce6c830`, 8 of them INSIDE docs/design/ and 7 inside tools/llmll-driver/, and NOT ONE touched this file. A co-edit rule narrowed to this folder would not have fired either, which is the second refutation RECORD-FRESH-1 now carries. BOTH HALVES OF THE OLD WHAT IS OPEN SENTENCE WERE FALSE. It read: program unification, and NOTHING SCOPES IT. Program unification IS scoped, by two design proposals. `driver-ll-program-unification-proposal.md` at Rev 6 defines the phrase and splits job (a) into (a1) one binary and (a2) retire the stub table. `driver-ll-stage-m-fanout-proposal.md` at Rev 2 answers the stage-M multiplicity question that (a2) blocked on and that the unification proposal deliberately did not write. And half of it has SHIPPED and is TAGGED: job (a) released as v0.23.2 on 2026-09-11. The campaign was adjudicated LIVE on 2026-09-07; the sequence to Phase 5 is in the roadmap G0 row. MEASURED FROM GIT at each correction: 4d SHIPPED v0.21.1 (4eedf8b, stages H, K and N over oracle.llmll); stage A PORTED v0.21.2 (3e1c1af), once HTTP-GET-1 shipped v0.21.0 (dc2c9cf) and lifted its STOP; 4f SHIPPED v0.23.1 (e49e968, merged ecaf418), landing stage O, report.llmll and the driver-spec section 13 validator, with cover cells O1 to O4 passing on CI run 34524333081 and the cover going 58 to 62 cells; (a1) SHIPPED v0.23.2 (merged a3df712), taking three driver programs to two, making spine.llmll a LIBRARY and collapsing every name collision between the three modules; (a2) SHIPPED v0.23.2 (merged b9be306), folding stage M into the sequencer stage loop over a new `stage-fanout` kind tag, deleting the `def-main` in wave.llmll, and making `_programs()` return ONE name. WHAT IS OPEN AT v0.23.2. Unification completion-test clauses 1, 2, 4 and 5 CLOSE. CLAUSE 3 STAYS OPEN: it requires `stage-ported?` DELETED and not corrected, and that needs stages E, G2, J and L, which are still a seventeen-arm counter in spine.llmll with no caller. Job (b), the section 5.3 plumbing port and therefore the retirement of scripts/rfc_to_implementation.py, has no plan and gates on clause 3. DO NOT COUNT FALSE ROWS IN `registry.stage-ported?`. That table answers false five times and THE DRIVER STUBS FOUR STAGES, not five: `started-step` consults `stage-fanout` BEFORE the table, so the stage M row is dead and never read. The comment above the table says so. THE WAVE COVER IS NINE CELLS, not the seven this field and sections 1, 3, 7 and 8 used to state. W8 and W9 were added when the wave began writing its declared output 12-wave/wave.json, and scripts/build_smoke.sh stage 9 states nine. PHASE 4 IS NOT CLOSED, and that is a judgement this correction makes rather than an assumption it carries. Sub-phase 4f acceptance in `driver-ll-phase4-proposal.md` section 9 requires clauses 1a, 1b AND 2, plus the phase close and the gap inventory. Clause 2 was EXECUTED on 2026-09-11 (`1c4d208`, comparator fix `8db8255`) and it is a CLAUSE-2 PASS over 11 of 16 stages, disclosed as NOT a full clause 2 result: five stages read stubs at run time, the run halted at stage O, and the stage M stub four stages upstream is the cause. (a2) unblocks a full run and NOBODY HAS RE-RUN IT. No commit and no document records a Phase 4 close or a gap inventory; a grep over docs/ and CHANGELOG.md finds neither. SO THIS FILE IS CORRECTED AND NOT RETIRED. The last line below still says to delete it when Phase 4 closes and that is still right. Retirement and the archive move are the documentation-lead slot under DOC-CONSOLIDATE, not this file's slot and not a restarting session's. The Phase 5 conformance claim follows program unification, bounded by SPEC-TIER-1, FS-ISOLATION-1 and PROC-TIMEOUT-1. The last commit that touches tools/llmll-driver/ is 4f74e84. Delete this file when Phase 4 closes."
date: 2026-08-18
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# DRIVER-LL Phase 4: restart record

**This file is written to be the first thing a restarting session reads, and it
has failed at that once.** The 2026-08-06 revision went stale inside a day and
the session that opened on it had to be told, in its own prompt, that the
restart record was wrong. So: everything below is dated, every figure names how
it was measured, and anything this file cannot keep current is marked as such
rather than stated flat.

The authority on Phase 4 *design* is
[`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) at **Rev 15**.
This file is the authority on *where the work is*. When they disagree about
design, the proposal wins; when they disagree about state, re-measure.

---

## 1. Where the work is

> **This section is the 4e-era snapshot and NONE OF IT IS CURRENT STATE,
> re-measured 2026-09-11.** Everything it calls uncommitted has shipped.
> `7fcd9d3` and the seven commits under it are in `main`, `dd1220c` is an
> ancestor of `main`, and every file below that this section calls untracked or
> modified-not-committed is tracked and committed. The cover it calls seven-cell
> is **nine** cells (section 7). The section is kept because sections 4 and 9
> were measured against exactly this tree. Read it as history, never as state.

Branch `hole-status-sibling/brief-unfilled-status`, **eight commits ahead of
main** (main at `dd1220c`), **nothing pushed**:

```
7fcd9d3 refactor(driver-ll): rename the sequencer's Phase to Ctl
40ae096 docs(driver-ll): the whole-wave closure is not a trace induction
7a48283 test(checkout): pin the three HoleKind constructors nothing covered
4a0ab51 docs(design): Q-005, provisional assume-guarantee acceptance
ea1f655 docs(driver-ll): Rev 15, the 4e harness leg's two refutations
895f75a fix(docs): the design-doc frontmatter that has never parsed
fb706cd docs(design): Q-003 and Q-004, the HOLE-STATUS-SIBLING deferrals
6547de4 feat(checkout): the sibling holes the brief advertised as filled
```

**Nothing below is committed.** New, untracked:

- [`tools/llmll-driver/wave.llmll`](../../tools/llmll-driver/wave.llmll), 102
  statements. The decision layer, the state machine and the seal. Checks clean
  (3 warnings, two of them trust gaps on `fill`'s preconditioned defs and the
  third the `:done?` non-bool warning `sequencer` also raises), verifies SAFE,
  **builds through GHC**, and runs.
- [`tools/llmll-driver/fixtures/wave-roots.llmll`](../../tools/llmll-driver/fixtures/wave-roots.llmll),
  two holes.
- [`scripts/wave_cover.py`](../../scripts/wave_cover.py), the acceptance
  cover: **seven cells then, nine now** (section 7).
- [`scripts/tests/test_driver_ll_4e.py`](../../scripts/tests/test_driver_ll_4e.py),
  the 20-test no-toolchain tier.

Modified, not committed:

- this file;
- [`scripts/tests/test_driver_ll_callers.py`](../../scripts/tests/test_driver_ll_callers.py),
  the census taken from twelve to eight (section 3);
- [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh), stage 9;
- [`tools/llmll-driver/EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json),
  the wave's frozen verdict.

The stray `roots.ast.json` copy and the `generated/` tree under `fixtures/`
are **deleted**. `generated/` is already covered by `.gitignore:10` and
`tools/llmll-driver/**/*.verified.json` by `.gitignore:41`, so a rebuild under
`fixtures/` leaves nothing to clean but the emitted `.ast.json`, which belongs
in a scratch directory and not in the tree.

## 2. The goal, and the plan it changed

**The goal is to prove LLMLL writes practical programs.** Measured against
that, the expressiveness question is already answered affirmatively and buried.
3,938 driver lines across nine releases produced exactly **two** genuine
expressiveness complaints: no records, so state is a nested pair chain where a
wrong projection typechecks; and no concurrency, so the wave is serial. Every
other cost was OS access (subprocess, sha256, mkdir, listdir, argv, exit
status, HTTP, stat, env, regex lowering), and eight of those became releases.
That answers "can LLMLL reach the OS", not "can LLMLL express a practical
program".

What is **unproven** is that LLMLL programs *run* in practical settings. Every
CI step in this repository is bash or python3, the repo's own tooling is 5,195
lines of Python and shell with **zero** lines of LLMLL, and all 13 LLMLL
programs with entry points execute only to test LLMLL. No LLMLL program does
work anyone needs done.

**The plan, as agreed on 2026-08-18.** 4d stays parked. Finish 4e against a
hand-authored fixture tree. Then port the CI gates, which is the actual
dogfooding. 4f, program unification and stage A stay deferred. This
deliberately does not make the swarm run, and that was accepted consciously.

> **Overtaken by shipped work, measured 2026-09-10.** Three of the four items
> above are done. The CI-gate port is TOOL-LL, complete and closed at v0.16.1.
> 4d shipped at v0.21.1 (`4eedf8b`). Stage A shipped at v0.21.2 (`3e1c1af`),
> once `HTTP-GET-1` closed at v0.21.0 (`dc2c9cf`) and lifted its STOP. 4f then shipped
> at v0.23.1 (`e49e968`, merged `ecaf418`), so **only program unification remains
> deferred**, and it has not started. The plan
> text above is kept because it records what was agreed and why. It is not a
> statement of current state.

**4e is now done, so the next thing is the CI-gate port.** (That port closed at
v0.16.1, and 4d, stage A and 4f have shipped since. The next thing is now program unification.) Section 7 records
what it turned into. The caveat below has only strengthened: the harness leg
discharged the contention justification from outside LLMLL, and 4e's cover then
produced contention from inside a program without a stub, so what 4e uniquely
demonstrated is the protocol and the linear token discipline.

**The CI-gate port has started, and DRIFT-CI-1 is the first one.**
[`tools/version-gate/versiongate.llmll`](../../tools/version-gate/versiongate.llmll)
ports [`scripts/version_gate.sh`](../../scripts/version_gate.sh) criteria C1 to
C4: same order, same messages, same exit codes, checked against the shell
version over fourteen trees by
[`scripts/version_gate_cover.py`](../../scripts/version_gate_cover.py) and run
from [`build_smoke.sh`](../../scripts/build_smoke.sh) stage 10. It is the first
LLMLL program in this repository that is infrastructure rather than a test
subject, so the sentence above about zero lines of LLMLL in the repo's own
tooling stops being true with it.

**It does not replace the shell script and the reason is structural.**
`version-gate.yml` runs the shell version in a job with no Stack and no GHC,
deliberately; a compiled binary there would trade a fast gate for a slow one.
Two implementations, two jobs, both deciding. Retiring the shell one is a
separate decision that costs the no-toolchain property.

**Why 4e before the CI gates.** Twelve proved defs have no reachable caller,
asserted by name in
[`scripts/tests/test_driver_ll_callers.py`](../../scripts/tests/test_driver_ll_callers.py).
4e is the only thing that will ever land callers on `fill.*` and
`token.token-during`. Five proved decisions with four refute cruxes behind them
currently decide nothing, which is the defect stage H exists to catch turned on
our own artifacts: a proof about an uncalled function is still valid, so no gate
can tell you.

**One caveat the 4e harness leg introduced.** That leg answered the contention
question from *outside* LLMLL, so one of 4e's three original justifications is
discharged. What remains uniquely 4e's is whether LLMLL can express the
checkout/patch/release protocol from inside a program, and whether it can hold
a linear discipline over mutable external state. The case for 4e is therefore
narrower than when the plan was set, and the case for starting the CI-gate port
is correspondingly closer.

## 3. The state machine, which has landed

`wave.llmll` now holds the decision layer **and** a twelve-arm `:mode console`
state machine over a `(Wv, WCtl)` nested-pair state, with `:init` `:step`
`:done?` `:on-done` `:status`. Per hole it drives

```
checkout -> release before the agent call -> agent -> fresh checkout ->
patch -> verify -> accept or revert
```

with a per-`(hole, attempt)` directory, the two budgets kept apart by
`next-error-budget`, the finding-versus-protocol-failure split decided by
`is-finding`, and a per-attempt backup restored on any rejection. After the
last hole it seals the tree; section 7 says what that is and why the run does
not end at the last hole.

Exit codes: **0** every hole accepted and the tree sealed, **1** at least one
finding, **2** a usage stop before any hole exists, **3** at least one protocol
failure, **5** every hole accepted and the tree not sealed. The cover has a
cell on each.

**It runs**, against
[`tools/llmll-driver/fixtures/wave-roots.llmll`](../../tools/llmll-driver/fixtures/wave-roots.llmll)
emitted to `.ast.json`, and section 7's cover is the version of the two runs
that first showed it: **seven cells then, nine now**.

**The census moved by four assertions, not one.** The previous session's
prediction was that
`test_the_orphaned_modules_are_exactly_the_five` would go green when the
`def-main` landed. It did not: `wave` stopped being an orphan and `fill` and
`token` stopped being orphans *with* it, so the assertion moved rather than
passing. Everything in that file derives from `_programs()`, so a third
`def-main` moves the program set, the orphan set and the register together.
**Program unification job (a2) then deleted that `def-main` on 2026-09-11, and
the register moved a second time: `_programs()` now returns one name,
`sequencer`, and the wave state machine is reached as `sequencer wave ...`.**
The four `4e-owes-caller` rows are **deleted**, not widened; the remaining
eight are `oracle.*` (four), `shape.probe-rows-conform?`, `liveness.advancing`,
`gate.remedy-for` and `shell.status-line`.

The fourth assertion moved for an unrelated reason worth keeping:
`test_the_llmll_command_accessor_is_read_nowhere` reads a **repo-wide, bare
name** count, so `wave` defining its own `cfg-llmll` made sequencer's dead
accessor read as called four times. `wave`'s is named `cfg-compiler`, and the
test now asserts the name is defined once so the next collision is loud.

## 4. Measured facts the state machine needs

Measured against compiler v0.14.87 by the 4e harness leg, then extended by the
session that wrote the state machine. Do not re-derive.

- **`checkout` and `patch` take a `.ast.json`, not a `.llmll`.** A `.llmll`
  path answers `checkout requires .ast.json input; run 'llmll build --emit
  json-ast' first` and exits 1. The tree comes from `llmll build FILE --emit`,
  which writes `generated/<name>/<name>.ast.json`. **`--emit` is a bare flag**;
  the message's own `--emit json-ast` is a usage error. This cost the state
  machine's first hour and is the fact the earlier revisions of section 4 were
  missing.
- `llmll holes FILE --json` puts a JSON array on **stdout** and warnings on
  **stderr**, cleanly separated. Each entry carries `pointer` and
  `module-path` (the latter as `def add-one`, so the function name `verify`
  will report is its last space-separated field). It accepts either a `.llmll`
  or a `.ast.json`, unlike `checkout`.
- **The brief's token field is `token`.** It also carries `source_hash`, `ttl`
  and `pointer`. `brief_version` is 0.12.3.
- **A patch of one bare `replace` op is accepted**: `PatchSuccess`, no `test`
  op needed. `parsePatchOp` supports `test` and the reference sends one, but
  the CAS that produces contention is over the brief's `source_hash`, so
  dropping it costs no contention detection and saves the port an RFC 6901
  pointer walk it has no builtin for.
- **`patch` rewrites the tree in place**, so a rejected fill needs an undo. The
  wave backs the tree up per attempt, immediately before patching.
- **A refused patch leaves the lock HELD.** After `PatchAuthError` the hole
  answers `hole at ... is already checked out` until the stale token is
  released. That is the `crux-token-held-across-call` wedge reached by a second
  route, and it is why the wave releases before it retries.
- **A successful patch clears the lock itself**, so a release afterwards
  answers `token not found in lock file (may have expired)` on stderr. The wave
  issues it anyway rather than depending on that side effect.
- **The console harness reads one line of stdin per step**; on EOF it exits
  **70**. `scripts/driver_ll_cover.py:231` feeds `"x\n" * BUDGET`, and a run
  with no stdin redirect hangs rather than failing.
- `llmll checkout FILE POINTER` puts the brief as JSON on **stdout**; failures
  go to **stderr** as prose with exit 1 (`hole at ... is already checked out`).
  Release with `llmll checkout FILE --release TOKEN`, which answers
  `{"released":true}`. **A skipped release wedges the hole.**
- `llmll patch FILE REQ.json` puts JSON on **stdout** with a five-way `result`
  discriminator; stderr was **empty** on every invocation measured. The two
  commands share no convention, so do not assume one.
- The brief has **no `hole_node` field**. The reference injects it itself after
  reading the node out of the tree
  ([`scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py),
  in `_checkout`). Not a defect.
- The patch request shape is
  `{"token": T, "patch":[{"op":"test","path":PTR,"value":HOLE_NODE},{"op":"replace","path":PTR,"value":BODY}]}`.
- `llmll verify` prints `body-faithful: <comma-list>` and
  `body-fallback: <comma-list>`.
- `string-contains : string -> string -> bool` exists and is what the
  abstraction functions use.

## 5. What is done, so it is not re-derived

- **The two corrections owed with 4e are paid** (`40ae096`).
  [`tools/llmll-driver/token.llmll`](../../tools/llmll-driver/token.llmll)'s
  header and
  [`tools/llmll-driver/README.md`](../../tools/llmll-driver/README.md) both
  claimed the whole-wave closure is a trace induction. Both now state that
  `token-during` proves a **phase-indexed invariant and not an ordering**, that
  the whole-wave property follows **pointwise** once the labelling is granted,
  that what is unproved is the **labelling** (a refinement mapping over the
  port rather than a theorem about the module, and not Lean-dischargeable), and
  both are strengthened to **per step and single-threaded**, because the
  labelling is a function only while at most one hole is live. The README's
  wording was "an induction over an unbounded sequence of fills", so a grep for
  "trace induction" finds nothing there; the claim was nearly dismissed as
  absent on the strength of that grep.
- **The sequencer's `Phase` is renamed to `Ctl`** (`7fcd9d3`), 51 code sites.
  The two genuine prose uses ("Phase 4", "Phase 3") are left alone.
- **HOLE-STATUS-SIBLING shipped** (`6547de4`): a sibling function whose body
  still contains a hole now reads `status: "unfilled"` rather than `"filled"`
  in the checkout brief. `brief_version` 0.12.2 to 0.12.3, no AST schema
  change. The predicate is a positive match on `HoleKind`,
  `HProofRequired{} -> False` and `_ -> True`, and is deliberately **not**
  phrased as a negation of `holeStatus'`, whose catch-all collapses `HNamed`
  into the same bucket and would make the patch a no-op.
- **Proposal Rev 15 landed** (`ea1f655`), folding the 4e harness leg.
- **Four design-doc frontmatter blocks fixed** (`895f75a`); 60 of 60 now parse.

## 6. Findings that must not be rediscovered

1. **The type checker conflates same-named sum types across modules.** New
   compiler finding, **not fixed**, and **ROUTED on 2026-09-10 as
   `TYPE-SHADOW-1`** (`8f27271`, roadmap group G3) after three weeks unrouted.
   Measured at v0.14.87: with two modules opened, each declaring a different
   type named `Phase`, a payload-carrying value of one satisfies an annotation
   resolved to the other.
   Only an `open-shadow-warning` fires. The control proves the annotation is
   real: an `int` in the same position **is** rejected, naming the other type's
   arms. This **inverts** Rev 14's reasoning, which assumed the collision would
   surface at 4e's call site. It would not have. The rename in `7fcd9d3` is the
   only thing preventing it.

2. **The per-fill bar accepts a fill whose body calls an unfilled hole.**
   Constructed end to end: the brief advertises sibling `beta`, an agent writes
   `(beta n)` into `def-shell alpha`, `patch` returns `PatchSuccess`, `verify`
   returns SAFE with `body-faithful: alpha`, and the sidecar persists
   `body_faithful: true` with a `verified_hash` while `beta`'s body is still a
   hole node. This is **sound** assume-guarantee and the trust report is
   correct. What is wrong is the abstraction function: `[S9-FAITHFUL]`
   ([`tools/llmll-driver/fill.llmll`](../../tools/llmll-driver/fill.llmll))
   says "proved against its own body rather than assumed", and the
   `body-faithful:` line means the VC was *emitted* body-faithfully.
   `crux-fill-accepts-assumed` does **not** catch it, a refute crux perturbing
   the proved decision and not the mapping into it. So **per-fill acceptance is
   provisional** and the end-of-wave whole-tree `--strict-verified-core` is the
   closing check. Q-005 in
   [`theory-questions.md`](theory-questions.md) records the residue.

   **4e closed this**: the seal is written, and cover cell W7 makes the gap
   observable, every hole accepted and the tree not proved, exit 5. The
   converse also got measured and was not expected: because `patch` verifies
   for itself, the per-fill bar looked redundant, and it is not. A body of
   `(+ n (string-length "x"))` satisfies the postcondition, answers
   **PatchSuccess**, verifies **SAFE**, and lands in `body-fallback`.
   [S9-FAITHFUL] is the only thing that rejects it (cell W3).

3. **`termination-proved` has no producer.** The reference's `_verify_fn`
   computes safe, body_faithful and refuted and nothing for termination,
   despite its own docstring naming `termination_unverified` in the bar. Do not
   pass a literal `true` (it makes `[S9-ACCEPT]`'s fourth conjunct vacuous) or
   `false` (it rejects every fill) without saying so at the site.

4. **Contention needs two outstanding briefs, not a stub** (Rev 15, F-27). The
   CAS is per-**file** against the brief's `source_hash`, so any brief
   outstanding across a successful patch is stale. Check out two holes *before*
   patching either: patch A gives `PatchSuccess`, patch B gives
   `PatchAuthError` with `obligation context is stale`. The old premise
   conflated "the wave is serial" with "`_apply` re-checkouts under the lock
   before patching"; unreachability follows from the **second alone**. **A
   one-hole fixture makes 4e's acceptance clause vacuous**, which is that
   clause being lost for a third time by a third mechanism.

5. **`PatchAuthError` is not synonymous with contention.** `invalid or expired
   checkout token` carries the same constructor
   ([`compiler/src/LLMLL/PatchApply.hs`](../../compiler/src/LLMLL/PatchApply.hs)).
   Only the three `obligation context is stale ...` messages are contention,
   and that message carries **U+2014 EM DASH** immediately after the ASCII
   lexeme `stale`, so key on `stale` and never on the fuller phrase. The
   reference's predicate retries on either and the port must not inherit it.

6. **Stages H and N invert the artifact flow** (4d, SHIPPED v0.21.1): the agent's
   artifact is an **input** to the stage's own computation and the **driver**
   writes the declared output. Needs a stage-agent-out table and Phase arms,
   not just registry rows.

7. **Section 9.3 settlement 2**: stage H holds the reference's **only**
   `require_written`, and 4d completes **all four** `Outcome` arms. Section
   3.5.1's rule is "cite the condition, never the line, **and count all three
   raising forms**".

## 7. 4e is complete

Every item the plan owed is done. What each one turned into:

**The whole-tree seal.** The run no longer ends at the last hole. `enter`
hands off to a `Sealing` arm that runs `verify --strict-verified-core` over the
whole tree and reports SEALED or NOT SEALED. Exit **5** is reserved for the
case the per-fill bar cannot see: every hole accepted and the tree still not
proved from its own bodies. A tally that already reported a finding keeps its
own code, because the seal was always going to fail on a tree with holes left
in it and counting that twice would report one defect as two.

**The cover**, [`scripts/wave_cover.py`](../../scripts/wave_cover.py), **nine
cells** (seven at 4e; W8 and W9 were added on 2026-09-11, when the wave began
writing its declared output 12-wave/wave.json), **no stub compiler anywhere**:
every cell runs real `checkout`, real `patch` and real `verify`, because those
three commands are the decisions under test.

| Cell | What it pins |
|---|---|
| W1 | both holes accepted, tree filled, seal held; the agent's whole input is (brief, out) and there is no third channel |
| W2 | a refused patch spends the ERROR budget, the protocol budget holds, exhaustion is a FINDING, the tree is reverted |
| W3 | a fill that **patches cleanly** and is not body-faithful is rejected |
| W4 | **two briefs outstanding**: contention spends the PROTOCOL budget and leaves the error budget at 2 |
| W5 | a missing required flag stops before any hole exists |
| W6 | a `.llmll` tree is refused at parse |
| W7 | every hole accepted and the tree **still not sealed**, exit 5 |
| W8 | the declared output `wave.json` records **one row per hole**, each row carrying the fields the clause 2 comparator reads, and `attempts` **one-based** |
| W9 | a finding reaches `wave.json` as a row with its budget and its cause, which is what makes W8's `status` field discriminating |

**W3 answers a question the plan did not know it had.** `patch` verifies for
itself, so most wrong bodies never reach the per-fill bar; the obvious reading
is that `fill-accepted`'s verify conjuncts are redundant. They are not.
Measured: a body of `(+ n (string-length "x"))` satisfies the postcondition,
answers **PatchSuccess**, and `verify` answers **SAFE** with `add-one` in
`body-fallback`. `patch` accepts it and the [S9-FAITHFUL] conjunct is the only
thing that rejects it. That is the per-fill bar catching what the compiler's
own patch gate does not.

**W4 is Rev 15 F-27's construction with the wave on the losing side.** The
cover takes the brief on hole 1 and holds it, the wave takes its own on hole 0,
both at one `source_hash`; the cover patches, and the wave's patch comes back
`PatchAuthError / stale`. The window is the single console step between the
fresh checkout (`working-step`) and the patch (`fresh-step`), and the cover
finds it by watching for the `agent token=released` line rather than counting
steps. The wave then releases, re-briefs and accepts on the next attempt; hole
1 is no longer a hole, so its checkout fails and it closes as a
PROTOCOL-FAILURE and **not** a finding, which is [S9-NOT-FINDING] observed
rather than argued.

**W6 was written to a false claim of mine and corrected by running it.** The
module said a `.llmll` path "reads as zero holes". It does not: `holes` answers
the real list for source too, and what actually happened was two protocol
failures and exit 3 after both budgets were spent on checkouts that could never
succeed. `missing-flags` now refuses a tree without `.ast.json` in its name.

**The test tier**, [`scripts/tests/test_driver_ll_4e.py`](../../scripts/tests/test_driver_ll_4e.py),
20 tests, no toolchain needed. It pins the unproved seam as a set (identified
by a conjunction: takes `out: string` **and** reads it, because each half alone
misclassified a def), that all four proved cores are still called and reached,
that the token guard still admits the agent call, that `contention?` keys on
the ASCII lexeme, that the three `WCtl` matches agree, and that the cover is
wired into the build gate and its banner counts the cells it runs.

**Wired in**: [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) stage 9
builds the driver and runs the cover (it built the separate wave binary until
job (a2) folded it in). 4c shipped a cover nothing invoked; this
one does not.

**Frozen**: `wave.llmll` is in
[`EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json)
(safe, no flags, cross-module). It has no `def` at all, so what the verdict
protects is the import surface: a module that reimplemented `fill-accepted`'s
conjunction inline would type-check, pass every cover cell, and quietly return
the census to twelve.

**The census deletion is done** (section 3).

## 8. Gates

All measured on the working tree with the state machine in place, at
`7fcd9d3` plus the uncommitted changes. **Re-measure, do not assume**; figures
in this repository's docs have been stale by hundreds.

> **The figures below are the 4e-era measurement and are NOT current at v0.23.0.
> Two of the reference paths no longer exist**, and that was found by resolving
> them on 2026-09-10 rather than by reading them. `TOOL-LL` ported all six CI
> gates and closed at v0.16.1, which retired the Python and shell references in
> favour of LLMLL ports under `tools/`. The rows are corrected to the live paths
> and their recorded figures are left as measured at the time.

| Gate | Figure |
|---|---|
| `stack test` | 1656 examples, 0 failures (no Haskell changed) |
| `pytest scripts/tests/` | 170 passed, 1 skipped, 0 failed (was 150; +20 from the 4e tier) |
| [`tools/refute-crux/refutecrux.llmll`](../../tools/refute-crux/refutecrux.llmll) (was `scripts/refute-crux-gate.sh`, retired by `TOOL-LL`) | 80 passed, 0 failed (was 79; `wave.llmll`'s frozen verdict is the 80th) |
| [`tools/doc-path-lint/pathlint.llmll`](../../tools/doc-path-lint/pathlint.llmll) (was `scripts/doc_path_lint.py`, retired at v0.14.99) | 886 citations, all resolve |
| [`scripts/driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | 39 passed, 0 failed, needs a **rebuilt** sequencer via `--driver` |
| [`scripts/wave_cover.py`](../../scripts/wave_cover.py) | 7 passed, 0 failed, needs `--wave` **and** `--llmll`. **NINE cells since 2026-09-11**, and `--wave` now takes the ONE driver binary |
| [`scripts/version_gate.sh`](../../scripts/version_gate.sh) | PASS at 0.14.87 |
| [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) | PASS, stages 1 to 9 |
| frontmatter parse | 60 of 60. **No general gate protects it**; see section 10, where this is now recorded as partially discharged by [`tools/doc-archive/docarchive.llmll`](../../tools/doc-archive/docarchive.llmll) |

## 9. Gotchas that cost real time

- **The repo-root binary is stale.** Always
  `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH`
  and confirm `llmll version` first.
- `python` is not on PATH; use `python3`. `timeout` is not installed.
- **zsh globs unquoted `?` and `*`**, so `for d in foo?` and
  `grep --include=*.py` both die with "no matches found". Quote them.
- **The Bash tool's working directory persists between calls.**
- Run the prose path lint **on its own line**; piping to `tail` takes `tail`'s
  exit status and a red lint sails through. The Python reference was retired at
  TOOL-RFC-005 and the gate is now
  [`tools/doc-path-lint/pathlint.llmll`](../../tools/doc-path-lint/pathlint.llmll),
  which CI builds and runs in `spec-roundtrip`.
- `--strict-verified-core` on a `def-shell` module **hard-errors by design**
  (the strict-sibling wall).
  [`tools/llmll-driver/EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json)
  is authoritative on which module takes which flag.
- **`fn` is a reserved word** (lambda). Do not name a parameter `fn`.
- Building a driver binary: `llmll build sequencer.llmll -o DIR` from inside
  `tools/llmll-driver`, then find the executable under `DIR/.stack-work/install`.
- **A console program with no stdin hangs.** It blocks on `hIsEOF stdin` before
  doing anything, so it looks like the first subprocess wedged. Pipe it
  `"x\n" * N`, as `driver_ll_cover.py` does.
- The state machine's paren balance broke once in `parse-cfg`, an eight-field
  pair chain. A depth counter over the source that reports the first line where
  depth reaches zero finds it in one pass; the parser's own error points at the
  last line of the file.

## 10. Debt, deferred and unrelated to 4e

**Re-measured 2026-09-10 at v0.23.0, bullet by bullet. A debt list that carries
a discharged item is worse than no list, so each entry below states what was
measured and when.**

- ~~**Four shipped releases have no git tag**~~ **DISCHARGED.** The bullet named
  v0.14.84 to v0.14.87 as untagged, with the newest tag on origin at `v0.14.83`.
  **All four are tagged.** The repository carries 145 tags and they run to
  `v0.23.0`. The underlying observation about the gate still holds and is not
  discharged with it: [`scripts/version_gate.sh`](../../scripts/version_gate.sh)
  compares the five banner sites to each other and to **no git tag**, which is
  why nothing caught the gap at the time.
- **No parse gate over design-doc frontmatter**, recorded in `895f75a`.
  **PARTIALLY DISCHARGED.** A frontmatter parser now exists and runs in CI:
  [`tools/doc-archive/docarchive.llmll`](../../tools/doc-archive/docarchive.llmll)
  is built and executed by `.github/workflows/version-gate.yml`. It is **not** a
  general frontmatter parse gate: it reads the archive-disposition field and its
  population is `docs/archive/`. So a malformed or missing frontmatter block in
  `docs/design/` is still ungated. The bullet as written is now too strong; what
  remains open is the general case.
- `HDelegate`, `HDelegateAsync`, `HDelegatePending` and `HConflictResolution`
  reach the HOLE-STATUS-SIBLING catch-all unpinned by any test, recorded in
  `7a48283`. **PARTIALLY DISCHARGED, and the remaining half is exact.**
  `HDelegate` and `HDelegateAsync` now appear in
  [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs). **`HDelegatePending`
  and `HConflictResolution` appear in no test in the repository**, measured over
  `compiler/test/` and `scripts/tests/`, while both are live constructors across
  seven modules under `compiler/src/LLMLL/`. Two of four, not four of four.
  **The remaining half now has an owner**: filed 2026-09-10 as
  `HOLE-KIND-PIN-1` (`eaa613c`) into roadmap group G8, as a regression pin and
  not as a live defect. The predicate is correct and its catch-all fails safe,
  so what is missing is the test that pins the exception set.
- ~~**Finding 1 in section 6 is unrouted**~~ **ROUTED 2026-09-10 as
  `TYPE-SHADOW-1`** (`8f27271`), into roadmap group G3. This bullet read "STILL
  TRUE, and it is the only entry here that has not moved at all" until that
  filing. **The re-verification at v0.23.0 found more than section 6 states**,
  over a four-file reproduction. The control is REJECTED: an `int` in the same
  position gives `type mismatch in 'take-p2': expected P2, got int`. The witness
  is ACCEPTED, with `open-shadow-warning` as the only warning. **The build then
  FAILS at code generation**, `Multiple declarations of 'Phase'` in `Lib.hs`, so
  no program carrying the conflation can be built and the defect is not
  latent. It is a gap in `DUP-DEF-1`'s fix (v0.20.0), which made `check` and GHC
  agree for same-module duplicates and left the cross-module case.

## 11. Method discipline this phase keeps relearning

Agreement and absence-of-failure are not evidence; report detection yield, not
concordance. Verify a boolean guard by **constructing its firing witness**, not
by confirming its inputs are in scope. Settle instrument design by measurement
over real committed data, not by argument. A gate can fail open: the
refute-crux gate read `.localized` while five driver cases spelled it
`localizes`, so the localization branch was skipped since 4b and the claims
were right but unchecked.

Both a subagent's report and a document's claim get checked against the
artifact. This session a plan written in this repository specified a predicate
that was a no-op on its own reproduction case, and predicted a test flip from a
premise that was false; both were caught by an implementing agent that stopped
and reported rather than repairing them, which is the behaviour to keep.

Non-blocking theory questions go straight into
[`theory-questions.md`](theory-questions.md) as `Q-NNN` and are **not** surfaced
in the reply. A question reaches the reply only when the answer changes what
gets built.
