---
name: event-log-scope-proposal
title: "EVENT-LOG-2: the event log is an I/O-trace divergence oracle, and §10a describes a different mechanism"
status: "Rev 2, SETTLED; mixed-track (spec, plus two diagnostic messages). Rev 2 re-measures every claim at `llmll 0.28.1` / `653ed1b8`. The adjudication does not change: §10a narrows and the code does not move. Three premises moved. `:deterministic` now has two consumers: TypeCheck refuses it on `wasi.env` (ENV-READ-1) and on `wasi.fs` (FS-STAT-1), so the flag is reserved, not inert. Rev 1 items 7 and 8 (line framing, the `none` result kind) shipped, so §10a states them as fact. The EFFECT-RESP degradation is now measured: an unchanged clock program replays at 2/4 events matched. Rev 2 adds two disclosures (world-dependent responses; unlogged, unframed `:init` output) and one strike (the §10a `get-bytes` parse note, which the §7 verb note contradicts). The section \"Rev 2: the §10a resolution\" supersedes the Rev 1 \"Proposed §10a text shape\". One small compiler change rides the doc pass: the two refusal diagnostics (`mkEnvDeterministicRefused`, `mkFsDeterministicRefused`) state capture in the present tense and cite §10a, so their message text moves to the conditional reason. W-REPLAY-INERT and the ReplayStatus retirement stay with REPLAY-INJECT. Rev 1, PARTIALLY DISCHARGED. Rev 1 folds what the DRIVER-LL Phase 3 port measured and what shipped in response, adding two items to the proposed §10a resolution: the LINE-FRAMING CONTRACT (a turn's wire bytes are `output ++ \"\\n\"`, so an event is `count('\\n')+1` lines and not one, which `Replay.replayOne` had assumed since the log existed) and the SETTLE ENTRY'S `none` RESULT KIND (RC-4 performs no command, so the prior `stdout` entry claimed an output that was never produced). Both landed unreleased on `driver-ll/phase-3-stage-j`. The framing defect is the one worth the spec text: an output ending in a newline matched at its own event, then desynchronized and reported the divergence against the FOLLOWING event, so the oracle could blame the wrong turn. Rev 1 also records the A2 limit as a disclosure `§10a` owes: `:on-done`'s output is outside the capture, so a green replay is not evidence it ran. Rev 0, PARTIALLY DISCHARGED. Adjudicates a four-part drift between LLMLL.md §10a and the shipped event log. Recommends that §10a narrow to the shipped mechanism (zero in-tree cost: no program declares :deterministic true) and that the specified-but-unbuilt injection mechanism be preserved as its own unscheduled row, because EFFECT-RESP RC-1 degrades the shipped oracle and injection is its named repair. Routed from documentation-lead 2026-08-02, who declined to write a roadmap row on a premise that did not survive verification. DISCHARGED 2026-08-02: Affected-surface items 2 and 3 are applied. The roadmap carries EVENT-LOG-2 [SPEC] and REPLAY-INJECT [CT] as separate rows in the Open work (v0.12+) table, and the v0.8.0-versus-v0.3.1 attribution is corrected by an appended note in Shipped Releases rather than by editing the shipped rows, that section being append-only. STILL OPEN BY DESIGN: item 1, the six-point §10a narrowing (doc-lead, spec-track, the action EVENT-LOG-2 closes on) and item 4, retiring ReplayStatus (compiler, rides REPLAY-INJECT or standalone cleanup). Item 5 stands: no schema delta."
date: 2026-08-02
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# EVENT-LOG-2: what the event log is, and what §10a says it is

**One line.** The compiler records an I/O trace and replays it as a divergence oracle; `LLMLL.md §10a`
specifies per-call value capture with injection replay gated on `:deterministic true`; the two are
different mechanisms with different guarantees, and only the spec is describing something that does
not run.

## Rev 2: re-measured at `llmll 0.28.1` / `653ed1b8` (2026-10-11)

Rev 2 does not change the adjudication. The roadmap row `EVENT-LOG-2` records it as "§10a narrows,
the code does not move", and `EVENT-CAPTURE-1` fork (b) is absorbed into it. Rev 2 re-measures each
premise of Rev 1 after fourteen minor releases. This section and "Rev 2: the §10a resolution" are
the current record. Where the Rev 0 and Rev 1 sections below disagree with them, these sections
apply. The line numbers in the Rev 0 and Rev 1 sections are from `65a08c7` and are not refreshed.

### What moved since Rev 1

1. **`:deterministic` now has two consumers.** The `SImport` clause in `TypeCheck.hs` refuses
   `:deterministic true` on a `wasi.env` import (ENV-READ-1, `mkEnvDeterministicRefused`) and on a
   `wasi.fs` import (FS-STAT-1, `mkFsDeterministicRefused`). The Rev 0 statement "consulted by
   nothing" is therefore incorrect. Both refusals take their reason from the present-tense capture
   sentence in §10a. The source comment above `mkEnvDeterministicRefused` says the message "states a
   forward condition and not a live leak". The message text does not: both messages say "A
   deterministic capability opts into event-log capture of a command's return value (LLMLL.md 10a)".
   That is the same present-tense claim, and after the narrowing it cites a §10a that no longer
   makes it.
2. **Rev 1 items 7 and 8 shipped.** `Replay.expectedLineCount` reads `count('\n') + 1` lines per
   event (REPLAY-FRAME-1). The settle entry writes `"kind":"none"` (`emitMainBody` for
   `ModeConsole` in `CodegenHs.hs`). §10a can state both as shipped behavior.
3. **Census.** No tracked program declares an accepted `:deterministic true`. The one match is
   `compiler/test/fixtures/resp-fact/fs-deterministic.llmll`, a negative fixture that expects the
   FS-STAT-1 type error. Two comment lines also match. 146 declarations write `false`.
4. **The mode restriction holds.** Only `emitMainBody ModeConsole` opens the log handle.
5. **Rev 0 affected-surface item 3 is done.** The roadmap carries the v0.8.0 attribution note under
   Shipped Releases.
6. **New drift.** §10a says "`get-bytes` currently fails to parse (fix in progress)". The §7 note
   "The verbs the parser names" says `get-bytes` parses and checks clean. The §10a note is
   incorrect.
7. **New drift.** The §13 rows for `wasi.fs.stat` and `wasi.env.get` say the refusal is a type error
   "(§10)". The refusal note is in §7.

### Witnesses, built and run on `llmll 0.28.1`

**Clock witness.** It falsifies §10 item 8 and is the first measurement of "The EFFECT-RESP
interaction" below.

```lisp
(import wasi.io    (capability stdout :deterministic false))
(import wasi.clock (capability read :deterministic true))

;; Odd turns read the clock; even turns print the reading the previous turn produced.
(def-shell clock-step [s: int input: string r: Response]
  (match r
    ((RCode n) (pair (+ s 1) (wasi.io.stdout (int-to-string n))))
    (_         (pair (+ s 1) wasi.clock.monotonic))))

(def-main :mode console
  :init (pair 0 wasi.clock.monotonic)
  :step clock-step)
```

Input `a b c d`. `llmll check` passes. All four events log `"captures":[]`. `llmll replay` of the
**unchanged** program reports `2/4 events matched`, with divergence at `seq 0` and `seq 2`, the two
events that print a clock reading. The flag is accepted and has no effect.

**`:init` witness.** It shows a gap that Rev 1 did not name.

```lisp
(import wasi.io (capability stdout :deterministic false))

(def-shell echo-step [s: int input: string r: Response]
  (pair (+ s 1) (wasi.io.stdout input)))

(def-main :mode console
  :init (pair 0 (wasi.io.stdout "welcome"))
  :step echo-step)
```

Input `a b`. Live stdout is `welcomea` then `b`. The log records `"a"` at `seq 0`. `llmll replay`
of the **unchanged** program reports `1/2 events matched`, `DIVERGE seq 0: expected="a"
actual="welcomea"`. The output of the `:init` command is not logged. It also has no newline
framing, so it joins the output of the first turn.

## Rev 2: the §10a resolution

This list supersedes the Rev 1 "Proposed §10a text shape". It is the resolution that the spec must
state. The prose belongs to documentation-lead.

1. **Mechanism.** In `:mode console`, the runtime writes `<module>.event-log.jsonl`. The file has a
   header line and one event for each loop turn. Each event records `(input, result)`.
   `llmll replay FILE LOG` rebuilds the program, runs it again on the recorded inputs, and reports
   match or divergence for each event.
2. **Guarantee.** Replay is a divergence oracle over the observable I/O trace. It detects a change
   in observable behavior. It does not reproduce a run, because each command runs again for real
   on replay.
3. **What replay cannot separate (now measured).** Under the response channel (§9.7), the output
   of a turn can depend on the `Response` of a command. A clock read, a file read, an environment
   read, a process run, or an HTTP call can change the output while the program stays the same.
   Replay reports this as divergence. State it as a general rule about commands whose response
   depends on the world. Do not list the sources: Rev 0 listed three, and the list became
   incorrect when `wasi.env.get` shipped. Use the clock witness as the example.
4. **Mode restriction.** "Only the console harness writes a log." This wording stays true for each
   possible result of MODE-CLI-1 and MODE-HTTP-1.
5. **`:deterministic` is reserved (changed from Rev 1 "inert").** The flag is parsed and carried
   through the JSON-AST. It causes no capture and no injection. It is a type error on a `wasi.env`
   import and on a `wasi.fs` import. These refusals stay. Their reason becomes conditional: if
   capture is built (REPLAY-INJECT), the flag on `wasi.env` would write a secret to the log, and on
   `wasi.fs` it would claim determinism for `stat`, which reads the clock. The §7 refusal note
   changes from "§10a captures" to this conditional reason, and gains the `wasi.fs` reason. The §7
   flag paragraph stops calling the flag an opt-in to capture. The two refusal diagnostics change in
   the same way (compiler, see "Rev 2 affected surface").
6. **§10 item 8 is rewritten.** The clock witness falsifies its claim of bitwise-deterministic
   replay. It becomes one sentence that points to items 1 to 3.
7. **The Sources of Non-Determinism table is relabelled.** The "Runtime Fix" column becomes "known,
   not addressed". The clock and PRNG rows describe the REPLAY-INJECT design, not shipped behavior.
8. **The Replayability Status table is withdrawn** (as in Rev 1). Nothing computes it.
9. **The event format example is replaced** with the real JSONL shape: a `header` line, then
   `event` lines with `seq`, `input`, `result`, and `captures`. `captures` is always `[]`. It stays
   in the format so that REPLAY-INJECT can fill it without a format change. The sentence
   "`:result` and `:captures` are injected directly" is removed.
10. **Line framing (Rev 1 item 7, shipped).** The wire bytes of a turn are `output ++ "\n"`. An
    event therefore occupies `count('\n', output) + 1` lines.
11. **The settle entry has result kind `none`** (Rev 1 item 8, shipped).
12. **Two disclosures.**
    - The output of `:on-done` is outside the log (Rev 1). A passing replay is not evidence that
      `:on-done` ran.
    - The output of the `:init` command is not logged and has no newline framing (Rev 2). It joins
      the output of the first turn. Thus a program whose `:init` prints fails replay at `seq 0`
      when the program is unchanged.

    The repair for each changes the stdout bytes of shipped programs. Both repairs stay with
    REPLAY-INJECT.
13. **Remove the §10a `get-bytes` parse note.** The §7 verb note contradicts it.

No schema delta. `"deterministic"` stays in the schema.

### Rev 2 edge cases

1. **Positive witness for item 3: the clock witness.** The unchanged program gives `2/4 events
   matched`. The narrowed text predicts this. The current §10 item 8 denies it. Channel: none.
   Replay is a runtime oracle, not a verification channel. The spec is silent today (gap, closed
   by item 3).
2. **`:deterministic true` on `wasi.clock`.** Accepted, with no effect. The narrowed text calls it
   reserved. The clock witness is also the firing witness for `W-REPLAY-INERT`. The in-tree
   population is zero, so the warning stays with REPLAY-INJECT.
3. **`:deterministic true` on `wasi.env` or `wasi.fs`.** Type error, unchanged. Channel: type. The
   text must keep the refusal and replace its reason (item 5). If the reason is removed and not
   replaced, the refusal looks arbitrary.
4. **A program whose `:init` prints: the `:init` witness.** It fails replay at `seq 0` when
   unchanged. Disclosed by item 12, not repaired. The spec is silent today (gap).
5. **`:mode cli` or `:mode http`.** No log file. `llmll replay` has no input. The spec is silent
   today (gap, closed by item 4).

### Rev 2 verification mapping

No proof obligations. This is a spec-only narrowing. Replay is a runtime divergence oracle outside
the three verification channels. `LLMLL.md §5.3.3` and `§5.3.5` do not cite it, and nothing in the
trust closure depends on it.

### Rev 2 affected surface

1. **`LLMLL.md`** (documentation-lead):
   - §7: the `:deterministic` flag paragraph and the refusal note (item 5).
   - §13: the `wasi.fs.stat` and `wasi.env.get` rows cite "(§10)" for the refusal; change to §7.
   - §8.1: the example with `stdin :deterministic true` still checks clean and is not false under
     the narrowing. Leave it; doc-lead does not edit examples.
   - §10 item 8 (item 6).
   - §10a in full (items 1 to 13).
2. **`docs/compiler-team-roadmap.md`:**
   - Close `EVENT-LOG-2` on the doc pass.
   - `REPLAY-INJECT`: replace "still unmeasured" with the clock witness result. Add the `:init`
     framing gap beside the `:on-done` gap.
   - File a new G3 `[CT]` row for the incidental finding below (suggested tag `INIT-SHAPE-1`).
3. **One small compiler change (compiler-engineer).** `mkEnvDeterministicRefused` and
   `mkFsDeterministicRefused` in `Diagnostic.hs`: the message text states the reason as a forward
   condition ("if a capture mechanism is built, ...") and stops claiming that the flag opts into
   capture. `diagKind` does not change. ER-7 in `Spec.hs` asserts "separate proposal", so the
   environment message keeps that phrase. The `ReplayStatus` retirement (`Syntax.hs`) stays a
   REPLAY-INJECT sub-item.
4. No standalone review file exists for this proposal, so there is no fold or archive.

### Rev 2 risks

1. **Incidental finding, outside this row: `check` accepts a `:init` that is not a pair.**
   Classification: spec drift, G3 shape. `:init 0` passes `llmll check`. LLMLL.md §9.5 requires
   `:init` to return a `(State, Command)` pair, and GHC rejects the generated `Main.hs`
   (`Couldn't match expected type 'Integer' with actual type '(a, b)'`). No roadmap row covers it.
   It does not block this row.
2. **The refusals lose their present-tense reason.** Classification: spec drift. If the conditional
   reason in item 5 is weak, a reader can conclude that the refusals can be removed. Keep them as
   forward guards, as `Diagnostic.hs` already says.
3. **A smaller claim can read as a regression.** Classification: scope. No shipped behavior
   changes.

No professor question. The Rev 1 question (input logging against value logging) does not change
what gets written, and the measurement now gives the guarantee.

### Hand-off to documentation-lead (spec-track)

(a) `docs/design/event-log-scope-proposal.md`. (b) Settled revision: Rev 2. (c) No standalone
review file exists, so M2 does not apply. (d) Mixed-track. Engineer summary: reword the two
refusal messages, with no `diagKind` change. Doc-lead summary: apply "Rev 2: the §10a resolution"
to `LLMLL.md` §7, §10 item 8, §10a, and the two §13 cross-references. Close `EVENT-LOG-2`. Update `REPLAY-INJECT` with the clock
measurement and the `:init` gap. File `INIT-SHAPE-1` in G3. Change the INDEX label to Rev 2,
SETTLED.

## Background

This is not a from-scratch design question. It is an adjudication of a drift, and it reached
language-team by an indirect route worth recording, because the route is the reason the drift went
unnoticed for a long time.

While settling EFFECT-RESP Rev 4, language-team measured that `capDeterministic` has no codegen
consumer (`grep -c 'capability' CodegenHs.hs` returns 0) and that `ReplayStatus` is never
constructed, and routed a roadmap row to documentation-lead describing the event log as an
unimplemented promise: declared surface with no runtime, a third instance of the pattern WASI-RT and
`:read` established. Doc-lead verified before writing and refused the row. The event log is
implemented and has been since v0.3.1. The two supporting measurements were individually true and did
not support the conclusion drawn from them.

What is actually wrong is narrower, and in one respect worse: the mechanism that ships is coherent
and complete, and the spec section describing it describes a different mechanism in the present
indicative.

## What ships, measured at `llmll 0.14.78` / `65a08c7`

The generated console harness opens `<module>.event-log.jsonl` unconditionally
(`CodegenHs.hs:922`), writes a JSONL header, and appends one event per loop iteration recording the
stdin line and the captured stdout (`CodegenHs.hs:949`, `emitEventLogPreamble` at `:844`). Only the
`ModeConsole` clause does this; `ModeCli` (`:970`) and `ModeHttp` (`:980`) write no log.

`llmll replay <source> <log>` (`Main.hs:204-205`, `doReplay` at `:2547`) rebuilds the program, spawns
it as a fresh subprocess, and for each recorded event writes the recorded input to its stdin, reads
one line of stdout, and compares against the recorded result (`Replay.hs:120-153`). It reports
matched and diverged counts.

The guarantee is a **divergence oracle over an observable I/O trace**. It detects that the program's
observable behavior changed. It does not make a program's behavior reproducible in the presence of a
non-deterministic effect, because it re-executes every effect for real.

`examples/replay-demo/replay-demo.llmll:1-12` documents exactly this and is accurate as written:
"feeds the logged inputs back, and confirms the outputs match (determinism verification)."

## The drift, in four parts

Each part is a claim in `LLMLL.md §10a` that the compiler does not implement.

**D-1. Capture is not gated on `:deterministic`.** `§10a:1652` states that capture happens "when
`:deterministic true` is set." Capture is unconditional for every `:mode console` program
(`CodegenHs.hs:922`). `capDeterministic`'s only consumer anywhere is the JSON round-trip at
`AstEmit.hs:433`; codegen never reads it.

**D-2. The `:captures` array is always empty.** `§10a:1657-1663` gives an event format carrying
`:captures [(wasi.clock.monotonic 1741823200000) (wasi.random.bytes #x4f2a...)]`. The emitted
`eventJsonL` writes `"captures":[]` as a hardcoded literal (`CodegenHs.hs:855`), and `EventLogEntry`
(`Replay.hs:24-30`) has five fields and no captures field, so the reader could not consume a
populated one.

**D-3. Replay compares; it does not inject.** `§10a:1665` states that "`:result` and `:captures` are
injected directly, bypassing real system calls." `replayOne` (`Replay.hs:141-153`) writes the
recorded input and compares the resulting output. No recorded value is substituted for a system call.
Consequently the "Runtime Fix" column of the Sources of Non-Determinism table (`§10a:1637-1641`),
which prescribes virtualizing the clock and re-seeding the PRNG from the log, has no implementation.

**D-4. The Replayability Status table has nothing behind it.** `§10a:1669-1672` splits `replayable`
from `best-effort replay` on whether all non-deterministic capabilities carry `:deterministic true`.
Neither the spec nor the compiler classifies which capabilities are non-deterministic, and
`ReplayStatus` (`Syntax.hs:871-873`, exported at `:74`) is never constructed anywhere in
`compiler/src/` or `compiler/app/`.

D-4 also fails on its own terms in-tree. All twenty `:deterministic` declarations in the repository
write `false`, every one of them on `wasi.io` stdout, so under the table every in-tree program is
`best-effort replay`. Yet `replay-demo` reports every event matched, because stdout is not a source
of non-determinism. The table's predicate treats every capability as non-deterministic unless
flagged, while the actual sources are the three in the `:1637-1641` table.

## Adjudication: §10a narrows

Three reasons, in order of weight.

**The compiler is the coherent artifact.** It implements one mechanism completely, with a CLI
surface, a module, and a worked example whose prose already matches the code. `LLMLL.md §10a` is the
only artifact in the repository describing the other mechanism.

**Narrowing costs nothing in-tree.** Census at `65a08c7`: **zero** `:deterministic true` declarations
across all `.llmll` and `.ast.json` files; twenty `:deterministic false`. No program loses a behavior
it relied on, because none relied on one, and the twenty `false` declarations stay accurate under the
narrowed reading.

**Building injection is out of proportion to what it buys today.** It requires per-call interception
at the codegen boundary for every `wasi.*` builtin, a populated `captures` array, a `captures` field
on `EventLogEntry`, and a replay mode that swaps effect implementations for log reads. That is a
larger surface than EFFECT-RESP, and no DRIVER-LL phase is blocked on it.

## Proposed §10a text shape

**Superseded by "Rev 2: the §10a resolution" above.** Kept as the Rev 0 and Rev 1 record.

Not verbatim spec prose, which is documentation-lead's slot. This is the resolution the narrowed
section must state.

1. **The mechanism.** The runtime records a sequenced JSONL log of `(input, result)` pairs at
   console-loop granularity for `:mode console` programs. `llmll replay` re-executes the program
   against the recorded inputs and reports per-event match or divergence.
2. **The guarantee, named.** A divergence oracle over an observable I/O trace. Replay detects that
   observable behavior changed. It does not reproduce a run in the presence of a non-deterministic
   effect, because every effect is re-executed for real.
3. **The mode restriction.** `:mode cli` and `:mode http` write no log. §10a today does not mention
   mode and reads as though every program logs.
4. **`:deterministic` is reserved and inert.** Parsed, carried through the JSON-AST, consulted by
   nothing. `§10:1122` stops calling it an opt-in to capture, because capture is not conditional on
   it.
5. **The Sources of Non-Determinism table is relabelled.** Its "Runtime Fix" column becomes known,
   unaddressed sources; the clock and PRNG rows describe the unbuilt mechanism's design.
6. **The Replayability Status table is withdrawn, not narrowed.** Its predicate is undefined and its
   computation does not exist. A table with neither is not a weaker true claim; it is a claim with
   nothing behind it. Restoring a status is the injection row's work, since a status needs a
   definition of which capabilities are non-deterministic.
7. **The line-framing contract, stated because replay read it wrong for as long as it existed
   (Rev 1).** A turn's wire bytes are `output ++ "\n"` (`CodegenHs.hs:1461`), so an event occupies
   `count('\n', output) + 1` lines, **not one**. `§10a` never said this, and `Replay.replayOne`
   assumed one line per event, which made any event whose recorded output was not exactly one line
   misalign. The failure mode worth naming in the spec is not the plain one: an output ending in a
   newline **matched** at its own event, because the reader stripped the discrepancy, and then
   desynchronized and reported the divergence against the following event. A divergence oracle that
   can blame the wrong turn is worse than one that fails, so the framing rule belongs in the
   normative text and not only in the emitter.
8. **The settle entry's result kind is `none`, not `stdout` (Rev 1).** The terminating step performs
   no command (RC-4, `LLMLL.md:1561`), so the program writes no line, and the entry previously
   claimed a `stdout` result of `""` that was never produced. `none` says what is true, keeps the
   entry so the input count still matches the recorded run, and lets the reader skip the read rather
   than guess. This adds a value to `result.kind`, which is the one surface addition this narrowing
   makes rather than removes.

   **The limit it leaves, which a passing replay will not state.** `:on-done`'s command runs outside
   the capture, so its output reaches real stdout and is recorded nowhere; the settle entry can match
   while carrying no information about it. **A green `llmll replay` is not evidence that `:on-done`
   ran, or ran correctly.** Bringing it inside the oracle requires newline-framing its output like
   every other turn's, which changes the stdout bytes of every shipped program declaring `:done?`.
   That trade was adjudicated to REPLAY-INJECT rather than taken here, and `§10a` should disclose the
   limit rather than let a green count imply coverage it does not have.

## The EFFECT-RESP interaction

This is why the injection design is preserved as a row rather than deleted, and it is the part with a
consequence for the DRIVER-LL campaign.

The divergence oracle works today because a console program's observable output is largely a function
of its stdin. Under EFFECT-RESP RC-1, `:step` consumes a `Response` produced by performing the
previous command, and for `wasi.fs.read` that response is a function of the filesystem. On replay,
`replayOne` re-executes the program, the read runs against whatever the file holds at replay time,
and the output can differ for a reason that has nothing to do with the program changing.

**After EFFECT-RESP, `llmll replay` conflates "the program changed" with "the world changed" and
reports both as divergence.** Injection is precisely the repair: a recorded `captures` entry replayed
in place of the read makes the trace self-contained again.

So `§10a`'s unbuilt mechanism is not speculative future work. It is the repair for a degradation that
Phase 1 introduces. DRIVER-LL is still not blocked on it, because the driver's audit need is served
by the trace itself, but the coupling belongs on the record before Phase 1 ships rather than after
someone files a replay bug against it.

This prediction is derived from the mechanism, not observed. The first real measurement is the
driver's own replay after Phase 3.

## `W-REPLAY-INERT`, proposed with its firing witness and its empty population

A declaration-site warning on `(capability … :deterministic true)`: "`:deterministic` is reserved and
currently inert; the event log captures unconditionally and replay does not inject recorded values."

The in-tree firing population is **zero**, stated plainly because a guard nothing exercises is how
dead-code guards ship (`docs/UPDATE-PROTOCOL.md` D2, precedent EXPIRING-INTENTIONAL). The first
firing site would be DRIVER-LL, which would reasonably write the flag on its `wasi.fs` and
`wasi.http` capabilities expecting capture. That is simultaneously the argument for the warning and
the argument that it is not urgent. Recommendation: specify it here, schedule it with the injection
row, not with the doc pass.

## Edge cases and degenerate inputs

1. **Positive witness for `W-REPLAY-INERT`.**
   ```lisp
   (import wasi.fs (capability read :deterministic true))

   (def-main :mode console :step handle)
   ```
   Today: accepted silently; `AstEmit.hs:433` writes `"deterministic": true`; capture happens anyway
   because it is ungated; no injection occurs on replay. Under the proposal: `check` emits
   `W-REPLAY-INERT`. Channel: **type** (declaration-site, no solver involvement). Citation:
   `Syntax.hs:836`, `AstEmit.hs:433`. Population today: zero.

2. **A console program with no non-deterministic effect** (`examples/replay-demo`, importing only
   `wasi.io` stdout at `:deterministic false`). Its replay report is exactly as strong after the
   narrowing as before: every event matches, and that is a real determinism check on the program's
   logic. Nothing is lost. Channel: spec is silent, intentionally; there is no obligation here.
   Citation: `examples/replay-demo/replay-demo.llmll:1-12`.

3. **A `:mode cli` or `:mode http` program.** No log is written at all. §10a today reads as though
   every program logs. Channel: spec is silent (**gap, flagged**). Citation: `CodegenHs.hs:917`
   against `:970` and `:980`.

4. **A post-EFFECT-RESP program whose read target changed between record and replay.** The divergence
   report is correct as documented (observable behavior differs) and useless as a regression signal
   (the program did not change). The narrowed §10a must state this, because it is the boundary users
   hit first. Channel: spec is silent (**gap, and the injection row is its named remedy**). Citation:
   `Replay.hs:141-153` against `effect-response-channel-proposal.md` RC-1.

5. **A program declaring `:deterministic false` on every capability, which is every in-tree program.**
   Under the withdrawn table it was `best-effort replay`; under the narrowing it carries no status at
   all, and its replay behavior is unchanged. Included because it is the case the withdrawal touches,
   and the answer is that nothing observable changes. Channel: spec is silent (intentional).

## Verification mapping

**No proof obligation is introduced by any part of this proposal.** Nothing here produces a predicate
over program values, so the `LLMLL.md §5.3.3 / §5.3.5` fragment boundary is not approached and
liquid-fixpoint is not reached. Stated rather than omitted, because a proposal that introduces no
solver obligation should say so.

| Item | Channel | Fragment |
|---|---|---|
| §10a narrowing | none (documentation) | none |
| `:deterministic` reserved-and-inert | none today, by construction | none |
| `W-REPLAY-INERT` | type | none; a syntactic test on a declaration form, not even QF-LIA |
| Injection replay, when built | trust (a replayed run's results came from a log, not the world) | none |

The last row is recorded now so the future row is not mis-scoped as a verification feature. Injection
adds a disclosure obligation, not a proof obligation.

## Affected surface

1. `LLMLL.md §10a:1637-1672` (narrowed per the six points above) and `§10:1122` (the "opt into
   event-log capture" sentence). Documentation-lead's slot, spec-track, no compiler work.
2. `docs/compiler-team-roadmap.md`: **two rows, not one.** Collapsing them makes a documentation fix
   look like it closes a compiler gap.
   - **EVENT-LOG-2** `[SPEC]`: the §10a narrowing. Closes on the doc pass.
   - **REPLAY-INJECT** `[CT]`: the specified-but-unbuilt mechanism, unscheduled, carrying the
     EFFECT-RESP interaction as its rationale and `W-REPLAY-INERT` as a sub-item.
3. `docs/compiler-team-roadmap.md` version attribution: `:362` and `:392` record EVENT-LOG as shipped
   at v0.8.0 while `:374` records the event log and replay shipping at **v0.3.1**, which the code's
   own labels agree with (`CodegenHs.hs:846`, `Replay.hs` header). `EVENT-LOG` appears nowhere in
   `CHANGELOG.md`. Minor; routed with the rest.
4. `compiler/src/LLMLL/Syntax.hs:74`, `:871-873`: `ReplayStatus` becomes dead surface once its table
   is withdrawn. Retire with REPLAY-INJECT or as standalone cleanup. Not a doc-pass action.
5. **No JSON-AST schema delta.** `"deterministic"` stays in the schema; the field is reserved, not
   removed.

## Risks and open questions

1. **Narrowing a spec section is a claim reduction and may read as a regression.** Classification:
   scope. Bite: complicates the doc pass only. The text mitigates it: the mechanism shipped at v0.3.1
   and has not changed; what changes is the description, and nothing that worked stops working.
2. **The EFFECT-RESP interaction is predicted, not measured.** Classification:
   verification-ergonomics. Cite: `Replay.hs:141-153`, RC-1. Bite: does not block Phase 1. Recorded
   now so it is not discovered as a bug later.
3. **`W-REPLAY-INERT` has an empty firing population.** Classification: scope. Bite: only matters if
   it ships before a program writes `:deterministic true`, in which case it is a guard nothing
   exercises. Schedule with REPLAY-INJECT.
4. **Withdrawing the Replayability Status table removes a user-facing concept with no replacement.**
   Classification: spec-drift. Bite: complicates. Keeping a status requires defining which
   capabilities are non-deterministic and computing it, which is REPLAY-INJECT's work.
5. **This drift survived from v0.3.1 to v0.14.78 undetected.** Classification: spec-drift. Bite: only
   matters at scale, and it is the reason to prefer the narrowing over a promise to build: a spec
   claim with no gate on it drifts silently for eleven minor versions. `§10a` had no doc-claim
   fixture and no test pinning any of D-1 through D-4.

## Open question for the professor

Record-and-replay has a developed literature carrying a distinction that maps onto this exactly:
**input logging** (record the program's external inputs, re-execute, rely on the program being a
function of them) versus **value logging** (record each non-deterministic call's return and inject it
on replay). LLMLL shipped the first and specified the second. Is there an established
characterization of the guarantee gap between them precise enough for the narrowed §10a to state its
guarantee rather than describe it, and does the literature name the failure mode in edge case 4,
where an input-logged replay reports divergence for a world change rather than a program change?

## Provenance

Routed to language-team by documentation-lead on 2026-08-02, who was asked to write a roadmap row on
a premise supplied by language-team, verified it first, and refused. The original premise ("no event
log is emitted anywhere; a third instance of declared-surface-with-no-runtime") was wrong. The
supporting measurements were true and did not support it. Recorded because the failure mode is
reusable: two true measurements about an absent consumer do not establish that a feature is absent,
and the check that caught it was reading the module rather than grepping for the identifier.
