---
name: entry-mode-settlement-proposal
title: "Entry modes: finish `cli` as console without stdin, retire the `http` stub, and type-check `:init`"
status: "Rev 1, SETTLED 2026-10-12 (user accepted the professor review). Rev 0 settled 2026-10-11. Three decisions. (1) MODE-CLI-1: finish `:mode cli` as the console harness without the stdin loop; `:step` is `(State, Response) -> (State, Command)`, `:done?` is required and must return bool, and the unbounded loop is reported in the trust report. (2) MODE-HTTP-1: retire the `http` stub; the server use case moves to the Trigger-gated Parking Lot row HTTP-SERVE-1. (3) INIT-SHAPE-1: implemented and merged (`3b08bcd`, release v0.28.3). Code-track; (1) and (2) ship together with one schema bump."
date: 2026-10-12
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# Entry modes: `cli`, `http`, and `:init`

**One line.** `def-main` advertises three entry modes. Only `console` works. `cli` can print a pure
value and nothing else, `http` passes `check` and `build` and then crashes on start, and the
`:init` field of every mode is never type-checked.

## Rev 1: professor review (2026-10-12)

The professor accepted all three decisions and the absence of a `:fuel` field. Rev 1 folds in the
amendments below. Where this section and the Rev 0 text disagree, this section applies.

### Decision 1 amendments

1. **The unbounded loop is reported, not only specified (new item 10).** A `cli` program's loop is
   unbounded by construction, so `check`, `verify` and the trust report state it. The report gains
   a top-level, only-on-true field `unbounded_entry_loop: true` for a `:mode cli` program, and the
   text report gains one line under the headline. It is an informational marker on the model of
   `termination_unverified` (`LLMLL.md §4.2` and its trust-report entry): derived at report-build time, never persisted,
   and it does not feed `evidenceMeet`, the effective level or strict-core admission. It is a
   minor `trust_report_version` bump. **It does not reuse `partial_fns`.** That list names members
   of a call-graph cycle, and `termination_assumed_fns` derives its callers from it. The `cli` loop
   is in the harness, not in the call graph, so adding it there would give `termination_assumed`
   a false `via`. No warning fires on a `:done?` that never holds: a process that never stops on
   purpose is legitimate. Precedent: Dafny's `decreases *`, Agda's `NON_TERMINATING`.
2. **`:done?` must return bool in `cli` (amends item 3).** The `:done?` return check in the
   `SDefMain` clause of `checkStatement` is a `tcWarn`. In `cli`, `:done?` is the only exit, so a
   non-bool return is a `check` error there. It stays a warning in `console`, where stdin
   exhaustion is a second exit. A `TVar` return passes, as today.
3. **`:status` is accepted in `cli` (affected-surface correction).** `checkStatusField` warns
   `":status applies only to :mode console"` on every other mode. Its guard becomes "console or
   cli", or every correct `cli` program that declares `:status` gets a false warning. Its
   `:status without :done?` warning cannot fire in `cli`, because `:done?` is required there.
4. **The supported bound is a counter in the state (new item 11).** A program that wants a step
   limit keeps a count in its state and includes it in `:done?`. The spec documents this idiom in
   §9.5. It is the principled replacement for a `:fuel` field, because the bound is part of the
   program, visible to `check`, and a candidate measure for LOOP-MEASURE-1.
5. **No `:decreases` measure on `def-main` now.** The tools that would move to `cli` first keep
   their work queue in an untyped record, so a measure would always report "unverified". The
   professor proposes a Parking Lot row:
   **LOOP-MEASURE-1.** A `(decreases …)` clause on a `cli` `def-main`, discharged as strict descent
   of a measure over the state across `:step`, which would remove `unbounded_entry_loop`. Trigger:
   a `cli` program with a typed state and a step whose body verifies.
6. **Item 7 (no event log) is kept, with its reason (answers professor question 2).** The
   professor asked for a justification or a follow-up, and said that replay "extends to `cli`
   trivially". It does not. The shipped log records inputs, and replay feeds them back
   (`LLMLL.md §10a`). A `cli` program has no external input: its only inputs are the
   `Response`s of its own commands, and replay performs those commands again for real. Replaying a
   `cli` program is therefore running it again, and an input log has nothing to record. A `cli`
   log is meaningful only as a value log, which is REPLAY-INJECT. Doc-lead adds `cli` to the
   REPLAY-INJECT row's scope. A trace for diagnosing a spinning program is a separate question
   that no consumer has raised; it is not filed.

### Decision 2 amendment

7. **HTTP-SERVE-1 design question 2 gains a case.** A reply as data cannot depend on the
   `Response` of a command issued for the same request, for example a ledger read before the
   decision. That case needs either multi-step requests (the harness holds the request open across
   steps) or a deferred reply. Append to question 2: "Limit: a reply cannot depend on a command
   issued for the same request; that needs multi-step requests or a deferred reply."

### Decision 3: shipped, and the type-variable count

8. **Shipped.** `checkInitShape` in `TypeCheck.hs`, merged as `3b08bcd` and released as v0.28.3.
   Rev 0 item 1 said that an unbound name in `:init` is reported "as for any expression". That is
   correct, and it is a warning, not an error: LLMLL reports unbound names as warnings everywhere.
9. **Type-variable count (professor's request), measured on `3b08bcd` with a temporary trace,
   since reverted.** Of 79 tracked programs whose `def-main` declares `:init`, 69 infer a pair with
   both elements concrete, and 10 infer a bare type variable and pass the shape check unchecked.
   No program infers a pair with a type-variable element. The 10 are `examples/hangman_sexp`,
   `hangman_json`, `hangman_json_verifier`, `life_sexp`, `life_json`,
   `conways_life_json_verifier`, `tictactoe_sexp`, `tictactoe_json_verifier`, and
   `scripts/build-smoke/replay_settle.llmll` and `scripts/doc-claims/hole-abort-at-run.llmll`.
   Each calls a helper with no declared return type. GHC still checks their shape at `build`. The
   gap is 13% of the population and is disclosed in `LLMLL.md §9.5`. Closing it is the general
   problem of unannotated `def-shell` returns, not an `:init` problem, and is not filed here.

### Rev 1 affected surface (replaces the Rev 0 `TypeCheck.hs` and spec lines)

- `TypeCheck.hs`: `checkStepArity` gains a `cli` clause; `checkInitRequired` and `checkInitShape`
  stop exempting `cli`; `:done?` required for `cli`, and its return check is an error for `cli`;
  `checkStatusField` guard becomes console or cli, and the `http` wording goes.
- `TrustReport.hs`: `unbounded_entry_loop`, the text-report line, and the `trust_report_version`
  bump.
- `LLMLL.md`: §9.5 as Rev 0 says, plus the counter idiom and the unbounded-loop marker; the trust-report
  field list beside `termination_unverified`; §10a unchanged ("only the console harness writes a log" stays true).
- Roadmap: file LOOP-MEASURE-1 and HTTP-SERVE-1 in the Trigger-gated Parking Lot; add `cli` to the
  REPLAY-INJECT row's scope.

### Hand-off

(a) `docs/design/entry-mode-settlement-proposal.md`. (b) Settled revision: Rev 1. (c) No standalone
review file exists; the professor review was held in conversation and is recorded in this section,
so M2 does not apply. (d) Engineer summary: implement Decisions 1 and 2 together, as amended here,
with one schema version bump and one `trust_report_version` bump. Doc-lead: add the INDEX row with
label "Rev 1, SETTLED".

## Measured at `llmll 0.28.2` / `c47f9f2f`

### Population

No tracked `.llmll` or `.ast.json` program uses `:mode cli` or `:mode http`. The only matches are
comments in five console programs that explain why they do not use `cli`
(`tools/doc-archive/docarchive.llmll`, `tools/doc-claims/docclaims.llmll`,
`tools/doc-path-lint/pathlint.llmll`, `tools/refute-crux/refutecrux.llmll`,
`compiler/test/fixtures/resp-fact/docclaims-nullary.llmll`). 46 tracked programs use
`:mode console`.

### `:mode cli`

The `ModeCli` clause of `emitMainBody` in `CodegenHs.hs` emits `args <- getArgs` and
`print (step args)`. No command is performed.

| Witness | `check` | `build` | Run |
|---|---|---|---|
| `:step` returns `int` (`list-length args`) | OK | OK | prints `3`, exit 0 |
| `:step` returns a `Command` | OK | GHC: `No instance for 'Show (IO ())'` | — |
| The shape `LLMLL.md §9.5` gives `cli`: `(State, string) -> (State, Command)`, with `:init` | OK | GHC: `No instance for 'Show (String -> ([String], IO ()))'` | — |

The spec documents a `cli` shape that cannot build. `:init` is accepted and ignored.

### `:mode http`

`:mode http 9000` with `:init` passes `check` and `build`. The built program prints
`LLMLL HTTP server on port 9000` and exits 1 with
`http mode: wire warp in package.yaml and uncomment above`. The emitted JSON-AST writes
`"mode": "http:9000"`, which `docs/llmll-ast.schema.json` rejects. A JSON program whose mode is
misspelled `"consoel"` passes `check` and becomes an HTTP program, because `entryMode` in
`ParserJSON.hs` ends `_ -> ModeHttp 8080`. The four defects in the MODE-HTTP-1 row are all still
present.

### `:init`

The `SDefMain` clause of `checkStatement` in `TypeCheck.hs` calls `inferExpr` on `:step` and on
`:done?`. It never calls it on `:init`. `checkInitRequired` reads only whether `:init` is present.
Every witness below passes `check`:

| `:init` (step state is `int`) | `build` |
|---|---|
| `0` | GHC: `Couldn't match expected type 'Integer' with actual type '(a, b)'` |
| `(pair "zero" (wasi.io.stdout "hi"))` | GHC: `Couldn't match type '[Char]' with 'Integer'` |
| `(pair 0 42)` | GHC: `Couldn't match expected type 'IO ()' with actual type 'Integer'` |
| `(pair 0 (wasi.io.stdout no-such-name))` | `check` accepts an unbound name |
| `(mk-init)`, an unannotated `def-shell` returning a correct pair | OK (control) |
| `(pair 0 (wasi.fs.write "/tmp/x" "y"))` with **no** `wasi.fs` import | builds and runs |

The last row is the most serious. `checkWasiCapability` fires from `inferExpr`, so a `wasi.*` call
inside `:init` is never checked against the module's imports. A program can perform an effect
whose namespace it never declared, which falsifies the §7 property "module-scoped declaration of
effect namespaces" for `:init`.

### What changed since MODE-CLI-1 was filed

PROC-BOUNDARY-1 (v0.14.85) gave `console` the two things `cli` was for: argv through
`wasi.proc.args`, delivered as the first `:step`'s `Response`, and an exit status through
`:status`. What `console` still forces is the **stdin step clock**. Four tools do not read the
line's content and are driven by `printf 'x\n'`: `pathlint` gets 900 lines, and
`scripts/build_smoke.sh` sends a fixed count at five sites. Too few lines ends the program with
exit 70 and no report.

## Decision 1: MODE-CLI-1, finish `cli` as console without stdin

1. **Step shape.** `:step` takes two parameters, `(State, Response)`, and returns
   `(State, Command)`. There is no input line.
2. **Harness.** Perform `:init`'s command and keep its response. Then loop: call `:step` on the
   state and the last response. If `:done?` holds on the new state, discard the step's command
   (RC-4, as in console), call `:on-done` if declared, and exit with `:status` (exit 0 if absent).
   Otherwise perform the command, keep its response, and repeat.
3. **`:done?` is required.** A `cli` def-main without `:done?` is a `check` error. A console
   program stops when stdin runs out; a `cli` loop has no such stop. Requiring `:done?` removes the
   trivially endless case at `check` time.
4. **Non-termination is allowed and disclosed.** A `cli` program whose `:done?` never holds runs
   until it is killed. No `:fuel` field is added: a fuel count is the step clock under a new name.
   An external bound (a CI timeout) is the caller's choice.
5. **`:init` is required** under the same rule as console (`checkInitRequired` stops exempting
   `cli`).
6. **Arguments** come from `wasi.proc.args`, as in console. No entry-point parameter carries argv.
7. **No event log.** `LLMLL.md §10a` (v0.28.2) already says only the console harness writes one.
8. **No stdin.** A `cli` program does not read stdin. No `wasi.io` read command exists, so nothing
   changes for any other mode.
9. **Migration: none required.** The mode has no users, so the old meaning (a pure function of
   `list[string]`, printed) is replaced, not deprecated. Moving the four step-clock tools to `cli`
   is optional, separate work.

## Decision 2: MODE-HTTP-1, retire the stub

1. Remove `http` from `pEntryMode` (`Parser.hs`), from `entryMode` (`ParserJSON.hs`), from
   `entryModeLabel` (`AstEmit.hs`), from `EntryMode` (`Syntax.hs`), and from the `ModeHttp` clause
   of `emitMainBody`.
2. **`:mode http` becomes a parse error with a hint**: no server harness exists; outbound calls are
   `wasi.http.*`; the server design is tracked as HTTP-SERVE-1.
3. **Defect (i) is fixed.** An unknown JSON mode string is a decode error that names the accepted
   values, `console` and `cli`. It no longer becomes a different program.
4. **Schema.** `DefMain.mode` becomes the string enum `["console", "cli"]`. The http object is
   removed. This is a schema change, so the schema version is bumped.
5. **`wasi.http.response` stays.** It is the anchor of RESP-FACT-1 (`respFactTable` in
   `RespFact.hs`) and works in console mode. Whether to rename it belongs to HTTP-SERVE-1.

### HTTP-SERVE-1, for the Trigger-gated Parking Lot

**Use case.** A proved decision service: deploy a verified core (the `withdraw-demo`,
`payments-core`, `banking_ledger`, `token-revocation-emergent`, `totp_rfc6238`, `erc20_token` and
auth-walkthrough family) so that the proved function answers each request. Agent tool servers do
not need this: MCP's stdio transport is newline-delimited JSON-RPC, which `console` already serves.

**Design questions it carries.**

1. A `Request` type (method, path, query, headers, body).
2. **Reply as data:** `:step` returns `(State, Reply, Command)`, so the type gives exactly one reply
   for each request. A reply issued as a `Command` cannot be counted until CMD-A lands.
3. Serial handling: state threads from one request to the next, so requests are handled one at a
   time. Parallel handling needs a separate state-partitioning design.
4. Runtime policy owned by the harness: body-size limit, timeouts, bind address. Capability
   enforcement is still CAP-1-REAL.
5. A dependency tier: `warp`, `wai` and `http-types` in each server program's generated package.
6. Replay: requests are inputs and replies are outputs, so the divergence oracle extends; the
   v0.28.2 sentence "only the console harness writes a log" widens.
7. Proof obligations: none new. Request parsing is shell.

**Trigger.** A named consumer: a decision-service example someone wants to deploy, or a port of
`llmll serve` to LLMLL.

## Decision 3: INIT-SHAPE-1, type-check `:init`

1. `checkStatement` for `SDefMain` calls `inferExpr` on `:init` when present. An unbound name or an
   ill-typed subexpression is reported as for any expression. A `wasi.*` call with no matching
   import is reported as `missing-capability`, as it is in `:step`.
2. The inferred type must be a pair. Its first element must be compatible with `:step`'s state
   parameter (the first parameter of the step's function type). Its second must be compatible with
   `Command`. A failure is a type error of kind `def-main-init-shape` that names `:init`, the
   expected shape, and the found type.
3. A type variable passes, as it does for `:step` and `:done?`. An unannotated helper such as
   `(boot)` or `(use …)` stays accepted. This is a disclosed gap with no false positives.
   Annotating the helper makes it checked.
4. **Census first.** 74 tracked `.llmll` files and 6 tracked `.ast.json` files declare `:init`;
   41 of the S-expression sites are a literal `(pair …)`, the rest call a helper. The engineer runs `check` on every
   tracked program before and after. Each new error is a hidden defect to report, not a reason to
   weaken the rule.
5. It applies to every mode that keeps `:init`: `console` now, and `cli` after Decision 1.

## Edge cases

1. **`cli` with no `:done?`.** `check` error. Channel: type. This is the positive witness for
   Decision 1 item 3: `(def-main :mode cli :init (pair 0 (wasi.io.stdout "x")) :step s)`.
2. **`cli` whose `:done?` never holds.** Runs until killed. Spec states it (intentional).
3. **A JSON document with `"mode": "cli"` and the old one-parameter step.** None tracked. It fails
   `def-main-step-arity` with a message that gives the new shape. Channel: type.
4. **`:mode http` in source after Decision 2.** Parse error with the HTTP-SERVE-1 hint.
5. **JSON `"mode": "consoel"`.** Decode error naming `console` and `cli`. Positive witness for
   Decision 2 item 3.
6. **`:init 0` with an `int` state.** `def-main-init-shape`. Positive witness for Decision 3; its
   sibling `(pair 0 (wasi.io.stdout "x"))` must stay clean.
7. **`:init (mk-init)` with an unannotated helper.** Accepted (type variable). Disclosed gap.

## Verification mapping

No proof obligations. All three decisions are declaration-shape checks in the type channel, or
harness and parser changes. Nothing reaches the `LLMLL.md §5.3.3` / `§5.3.5` fragment boundary.

## Affected surface

1. **Code (compiler-engineer).** `Syntax.hs` (`EntryMode`), `Parser.hs` (`pEntryMode`),
   `ParserJSON.hs` (`entryMode`), `AstEmit.hs` (`entryModeLabel`), `CodegenHs.hs` (`emitMainBody`:
   `ModeCli` rewritten, `ModeHttp` removed), `TypeCheck.hs` (`checkStepArity` gains a `cli` clause,
   `checkInitRequired` stops exempting `cli`, `:done?` required for `cli`, `:init` inference and
   `def-main-init-shape`, and the `:status` warning loses its `http` case).
2. **Schema.** `docs/llmll-ast.schema.json` `DefMain.mode`, with a version bump. The test
   `test_sv3_mode_http_witness_is_rejected` in `scripts/tests/test_schema_valid_1.py` is retired
   with the mode.
3. **Spec (documentation-lead).** `LLMLL.md` §9.5 (syntax block, modes table, key semantics, the
   `cli` step sentence), §12 EBNF, and the notes that say "the `cli` and `http` harnesses perform no
   command".
4. **Roadmap (documentation-lead).** Close MODE-CLI-1, MODE-HTTP-1 and INIT-SHAPE-1 as each
   ships. File HTTP-SERVE-1 in the Trigger-gated Parking Lot.
5. **Out of scope, routed as findings.** The five tool comments that cite MODE-CLI-1 become stale
   when Decision 1 ships.

## Risks

1. **Unbounded `cli` loops.** Classification: scope. A broken `cli` program hangs instead of
   exiting 70. Accepted, and the reason is item 4 of Decision 1. This is the point a professor
   review would test.
2. **The `:init` census may find hidden defects in tracked programs.** Classification: scope. Each
   one is a real defect that GHC or a type variable hid. Bite: may enlarge the INIT-SHAPE-1 patch.
3. **Removing `http` removes a word agents may expect.** Classification: DX. The parse-error hint
   names what exists and where the design is tracked.

## Sequencing

INIT-SHAPE-1 first: it is small, has no design dependency, and its census informs the `cli` work.
Then Decisions 1 and 2 together, because both change `EntryMode` and the schema `mode` shape and
should take one schema version bump.
