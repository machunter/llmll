---
name: event-log-scope-proposal
title: "EVENT-LOG-2: the event log is an I/O-trace divergence oracle, and §10a describes a different mechanism"
status: "Rev 0, PROPOSED. Adjudicates a four-part drift between LLMLL.md §10a and the shipped event log. Recommends that §10a narrow to the shipped mechanism (zero in-tree cost: no program declares :deterministic true) and that the specified-but-unbuilt injection mechanism be preserved as its own unscheduled row, because EFFECT-RESP RC-1 degrades the shipped oracle and injection is its named repair. Routed from documentation-lead 2026-08-02, who declined to write a roadmap row on a premise that did not survive verification."
date: 2026-08-02
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# EVENT-LOG-2: what the event log is, and what §10a says it is

**One line.** The compiler records an I/O trace and replays it as a divergence oracle; `LLMLL.md §10a`
specifies per-call value capture with injection replay gated on `:deterministic true`; the two are
different mechanisms with different guarantees, and only the spec is describing something that does
not run.

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
