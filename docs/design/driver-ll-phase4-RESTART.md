---
name: driver-ll-phase4-restart
title: "DRIVER-LL Phase 4: session restart record"
status: "LIVE. Rewritten 2026-08-07, fifth session; rewritten again the same day by the sixth, which landed the state machine and then CLOSED THE SUB-PHASE. SUB-PHASE 4e IS COMPLETE: wave.llmll runs end to end, fills the two-hole fixture through a real agent process, seals the tree with a whole-tree --strict-verified-core, and carries a seven-cell cover (including the two-brief contention cell Rev 15 mandates, driven against the real compiler with no stub) wired into build_smoke.sh stage 9, a 20-test no-toolchain tier, and a frozen verdict. The callerless census is down from twelve to eight. All gates green. THE NEXT THING IS THE CI-GATE PORT, which is the actual dogfooding; 4d is PARKED by an agreed pivot and 4f, program unification and stage A stay deferred."
date: 2026-08-07
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
- [`scripts/wave_cover.py`](../../scripts/wave_cover.py), the seven-cell
  acceptance cover.
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

**The plan, agreed and unchanged.** 4d stays parked. Finish 4e against a
hand-authored fixture tree. Then port the CI gates, which is the actual
dogfooding. 4f, program unification and stage A stay deferred. This
deliberately does not make the swarm run, and that was accepted consciously.

**4e is now done, so the next thing is the CI-gate port.** Section 7 records
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
emitted to `.ast.json`, and section 7's cover is the seven-cell version of the
two runs that first showed it.

**The census moved by four assertions, not one.** The previous session's
prediction was that
`test_the_orphaned_modules_are_exactly_the_five` would go green when the
`def-main` landed. It did not: `wave` stopped being an orphan and `fill` and
`token` stopped being orphans *with* it, so the assertion moved rather than
passing. Everything in that file derives from `_programs()`, so a third
`def-main` moves the program set, the orphan set and the register together.
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
   compiler finding, **not fixed**, unrouted. Measured at v0.14.87: with two
   modules opened, each declaring a different type named `Phase`, a
   payload-carrying value of one satisfies an annotation resolved to the other.
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

6. **Stages H and N invert the artifact flow** (4d, parked): the agent's
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

**The cover**, [`scripts/wave_cover.py`](../../scripts/wave_cover.py), seven
cells, **no stub compiler anywhere**: every cell runs real `checkout`, real
`patch` and real `verify`, because those three commands are the decisions under
test.

| Cell | What it pins |
|---|---|
| W1 | both holes accepted, tree filled, seal held; the agent's whole input is (brief, out) and there is no third channel |
| W2 | a refused patch spends the ERROR budget, the protocol budget holds, exhaustion is a FINDING, the tree is reverted |
| W3 | a fill that **patches cleanly** and is not body-faithful is rejected |
| W4 | **two briefs outstanding**: contention spends the PROTOCOL budget and leaves the error budget at 2 |
| W5 | a missing required flag stops before any hole exists |
| W6 | a `.llmll` tree is refused at parse |
| W7 | every hole accepted and the tree **still not sealed**, exit 5 |

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
builds the wave and runs the cover. 4c shipped a cover nothing invoked; this
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

| Gate | Figure |
|---|---|
| `stack test` | 1656 examples, 0 failures (no Haskell changed) |
| `pytest scripts/tests/` | 170 passed, 1 skipped, 0 failed (was 150; +20 from the 4e tier) |
| [`scripts/refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 80 passed, 0 failed (was 79; `wave.llmll`'s frozen verdict is the 80th) |
| [`scripts/doc_path_lint.py`](../../scripts/doc_path_lint.py) | 886 citations, all resolve |
| [`scripts/driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | 39 passed, 0 failed, needs a **rebuilt** sequencer via `--driver` |
| [`scripts/wave_cover.py`](../../scripts/wave_cover.py) | 7 passed, 0 failed, needs `--wave` **and** `--llmll` |
| [`scripts/version_gate.sh`](../../scripts/version_gate.sh) | PASS at 0.14.87 |
| [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) | PASS, stages 1 to 9 |
| frontmatter parse | 60 of 60, and **no gate protects it** |

## 9. Gotchas that cost real time

- **The repo-root binary is stale.** Always
  `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH`
  and confirm `llmll version` first.
- `python` is not on PATH; use `python3`. `timeout` is not installed.
- **zsh globs unquoted `?` and `*`**, so `for d in foo?` and
  `grep --include=*.py` both die with "no matches found". Quote them.
- **The Bash tool's working directory persists between calls.**
- Run [`scripts/doc_path_lint.py`](../../scripts/doc_path_lint.py) **on its own
  line**; piping to `tail` takes `tail`'s exit status and a red lint sails
  through.
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

- **Four shipped releases have no git tag** and therefore no ghcr image. Newest
  tag on origin is `v0.14.83` while the five banner sites read `v0.14.87`.
  Targets: v0.14.84 to `a182638`, v0.14.85 to `1428fe3`, v0.14.86 to `6e92dd0`,
  v0.14.87 to `1bc2965`.
  [`scripts/version_gate.sh`](../../scripts/version_gate.sh) compares banners to
  each other and to no tag, which is why nothing caught it. Deferred while
  Actions drains.
- **No parse gate over design-doc frontmatter**, recorded in `895f75a`.
- `HDelegate`, `HDelegateAsync`, `HDelegatePending` and `HConflictResolution`
  reach the HOLE-STATUS-SIBLING catch-all unpinned by any test, recorded in
  `7a48283`.
- Finding 1 in section 6 is unrouted.

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
