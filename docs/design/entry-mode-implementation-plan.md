---
name: entry-mode-implementation-plan
title: "MODE-CLI-1 + MODE-HTTP-1: implementation plan"
status: "APPROVED 2026-10-12 by the user; handed to llmll-patch-implementer. Implements docs/design/entry-mode-settlement-proposal.md Rev 1 (SETTLED 2026-10-12), Decisions 1 and 2. One schema version change (0.11.0 to 0.12.0) and one trust_report_version change (1.8.0 to 1.9.0)."
date: 2026-10-12
author: compiler-engineer
consumers: [user, llmll-patch-implementer, documentation-lead]
style: "ASD-STE100 Simplified Technical English. Haskell identifiers, compiler messages and test names keep their exact bytes."
---

# MODE-CLI-1 + MODE-HTTP-1: implementation plan

## Restatement

The plan has two parts:

- **MODE-CLI-1:** `:mode cli` becomes the console harness without stdin. `:step` is `(State, Response) -> (State, Command)`, `:init` and `:done?` are required, and the trust report marks the loop as unbounded.
- **MODE-HTTP-1:** the `http` mode is removed from the AST, the two parsers, the emitter, codegen and the schema. An unknown JSON mode string becomes a decode error.

Both change `EntryMode` and `DefMain.mode`, so they ship in one patch with one schema version change. No verification condition changes.

## Context located

- `docs/design/entry-mode-settlement-proposal.md` Rev 1: the settled decisions, amendments 1 to 7, and edge cases 1 to 5. Decision 3 (INIT-SHAPE-1) shipped in v0.28.3.
- `docs/compiler-team-roadmap.md` rows `MODE-CLI-1` (line 139) and `MODE-HTTP-1` (line 140): both at DECIDE. The settlement replaces both DECIDE cells.
- `compiler/src/LLMLL/Syntax.hs:972-976` (`EntryMode`): three constructors. `ModeHttp` carries `httpPort`.
- `compiler/src/LLMLL/Parser.hs:492-497` (`pEntryMode`): `http` with an optional port.
- `compiler/src/LLMLL/ParserJSON.hs:562-566` (`parseDefMain`): `_ -> ModeHttp 8080` is defect (i).
- `compiler/src/LLMLL/ParserJSON.hs:70,90`: `expectedSchemaVersion = "0.11.0"` and `acceptedSchemaVersions`.
- `compiler/src/LLMLL/AstEmit.hs:185-188` (`entryModeLabel`): writes `"http:" <> port`, defect (iii).
- `compiler/src/LLMLL/CodegenHs.hs:2400-2539` (console clause of `emitMainBody`): the template for the new cli clause. `initBlock`, `onDoneLine`, `statusExpr` and `settleParam` are local to it.
- `compiler/src/LLMLL/CodegenHs.hs:2541-2552` (cli clause): `print (step args)`. `:2554-2577` (http clause): an `error` stub.
- `compiler/src/LLMLL/CodegenHs.hs:602-606` (`llmll_perform`): performs a command and returns its `Response` with no stdout capture. The cli loop uses it. `:2240-2245` (`performStep`) captures stdout for the event log, so the cli loop does not use it.
- `compiler/src/LLMLL/CodegenHs.hs:2281`: `emitEventLogPreamble` goes into every `Main.hs`, whatever the mode. So the cli harness has `llmll_perform` and the `Response` type available.
- `compiler/src/LLMLL/TypeCheck.hs:2185-2210` (`checkStatement (SDefMain …)`): `:done?` return check is a `tcWarn`.
- `compiler/src/LLMLL/TypeCheck.hs:2232-2262` (`checkStatusField`), `:2285-2310` (`checkStepArity`), `:2348-2364` (`checkInitRequired`), `:2390-2412` (`checkInitShape`): each has a cli or http case to change.
- `compiler/src/LLMLL/TrustReport.hs:416` (`trustReportEmitVersion = "1.8.0"`), `:428-503` (`harnessAssumptions`, console only), `:2045-2095` (`formatTrustReportJson` top level), `:1890-1920` (`formatTrustReport` text sections).
- `compiler/src/LLMLL/RespFact.hs:813` (`hasConsoleMain`): RESP-FACT-1 requires a console `def-main`. See finding F3.
- `docs/llmll-ast.schema.json` `$defs.DefMain`: `mode` is `oneOf` a string enum or an http object. The `init`, `step` and `done?` descriptions state cli and http rules that this plan makes incorrect.
- Tests that pin the old behaviour: `compiler/test/Spec.hs:17365`, `:17487-17493`, `:17677-17706`, `:18196`; trust-report version pins at `:4925`, `:5214`, `:13907`; `scripts/tests/test_schema_valid_1.py:64-175` (`test_sv3_mode_http_witness_is_rejected`); `scripts/tests/test_console_init_1.py:15,158` (cli exclusion).
- Population, from the settlement and confirmed by grep: zero tracked programs use `:mode cli` or `:mode http`. The only matches are comments in five console tools.
- Test baseline from the v0.28.3 roadmap row: 2253 Haskell, 312 Python. Step 1 measures it again on the merge base.

## Plan summary

`EntryMode` loses `ModeHttp`. GHC's incomplete-pattern warnings then list every site that matched on it, so the removal cannot miss a site. The cli harness is the console harness with three parts removed: the stdin read, the event log and the EOF exit. `:init`'s command is performed and its `Response` goes to the first `:step`. The loop calls `:step` on the state and the last response, tests `:done?`, and either settles (RC-4: discard the command, run `:on-done`, exit with `:status`) or performs the command and repeats. The type checker requires `:init` (unless the state is unit) and `:done?` for cli, checks a two-parameter step, and makes a non-bool `:done?` an error in cli. The trust report gains the only-on-true top-level field `unbounded_entry_loop` and one text line, with `trust_report_version` 1.9.0. The schema `mode` becomes a plain `["console","cli"]` enum, with schema version 0.12.0. The cost is about 250 changed lines in seven modules, and no change to the verifier.

## Affected surface

Ordered from the AST to the output.

1. `compiler/src/LLMLL/Syntax.hs:972-976`: `EntryMode = ModeConsole | ModeCli`. Change the comment on `ModeCli` to "console harness without stdin (MODE-CLI-1)".
2. `compiler/src/LLMLL/Parser.hs:492-497` (`pEntryMode`): replace the `http` alternative with `symbol "http" *> fail httpRetiredHint`. Change the `pDefMain` comment at `:470`. The hint text:
   `":mode http is not supported: no HTTP server harness exists. Outbound HTTP calls are wasi.http.* commands from a console or cli program. The server design is tracked as HTTP-SERVE-1."`
3. `compiler/src/LLMLL/ParserJSON.hs:562-566`: replace the catch-all with `other -> fail (…)`. The message names the value and the accepted values `"console"` and `"cli"`. If the value starts with `http`, the message also gives the HTTP-SERVE-1 hint. A JSON `mode` that is an object already fails at `o .: "mode" :: Parser Text`, so the decode error for the old http object needs no new code.
4. `compiler/src/LLMLL/ParserJSON.hs:70,90`: `expectedSchemaVersion = "0.12.0"`. Put `"0.12.0"` first in `acceptedSchemaVersions`. Older versions stay accepted, because no tracked older document uses http.
5. `compiler/src/LLMLL/AstEmit.hs:185-188`: remove the `ModeHttp` clause of `entryModeLabel`.
6. `compiler/src/LLMLL/TypeCheck.hs`:
   - `checkStatement (SDefMain …)` `:2185-2210`: if the mode is `ModeCli` and `:done?` is absent, report `tcErrorK "def-main-done-required"`. The message is `":mode cli requires :done?: it is the only exit of the cli loop, which does not read stdin (MODE-CLI-1)."` If `:done?` is present, the return check uses `tcErrorK "def-main-done-type"` in cli and keeps `tcWarn` in console. A `TVar` return passes in both modes, as now.
   - `checkStatusField` `:2232-2262`: delete the `":status applies only to :mode console"` warning. With `ModeHttp` removed, the guard "console or cli" is true for every mode, so the warning can never fire. Keep the `":status without :done?"` warning guarded on `ModeConsole`. In cli, `def-main-done-required` already reports that case.
   - `checkStepArity` `:2285-2310`: add a `ModeCli` clause. The step must be `TFn` with two parameters and the second must be compatible with `TCustom "Response"`. Otherwise report `def-main-step-arity` with the text `":step of a cli def-main must take two parameters (state, response: Response) and return (state, Command); found N parameter(s)…"`. This covers edge case 3 (the old one-parameter cli step). Remove the `checkStepArity _ _ = pure ()` fallback, because the two clauses are now total. Change the comment at `:2280-2284`.
   - `checkInitRequired` `:2348-2364`: delete the `ModeCli Nothing` clause. The mode parameter becomes unused, so remove it from the signature and the call site.
   - `checkInitShape` `:2390-2412`: delete the `(ModeCli, _)` arm. Remove the mode parameter. Change the comment that says MODE-CLI-1 removes the exemption.
7. `compiler/src/LLMLL/CodegenHs.hs`:
   - Move `initBlock`, `onDoneLine`, `statusExpr` and `settleParam` from the console clause's `where` block to top-level helpers that take `mInit`, `mOnDone` and `mStatus`. The console output stays byte-identical. Test T-C1 below checks this.
   - Replace the cli clause `:2541-2552` with the harness below (illustrative, not implementation). It uses the same encoding settings as console, `llmll_perform` and not `performStep`, and does not open an event log.

     ```
     main = do
       setLocaleEncoding utf8; hSetEncoding stdout utf8; hSetEncoding stderr utf8
       hSetBuffering stdout NoBuffering
       let !(state0, initCmd) = <init>      -- or state0 = (), r0 = RNone
       r0 <- llmll_perform initCmd
       status <- loop state0 r0
       llmll_terminate status
       where
         llmll_terminate :: Integer -> IO ()   -- 0 -> exitSuccess, n -> ExitFailure n
         loop s r = do
           let !(s', cmd) = <step> s r
           if <done?> s' then settle s' else do
             r' <- llmll_perform cmd
             loop s' r'
         settle s' = do <on-done> s'; return (<status> s')
     ```

     `:done?` is required, so the loop has one exit and `llmll_terminate` takes `Integer`, not `Maybe Integer`. The step-call wrapper for a non-variable step is `(\ s r -> <e> s r)`.
   - Delete the http clause `:2554-2577`. Keep the `emitMainBody _ _` fallback, because `emitMainBody` also receives statements that are not `SDefMain`.
8. `compiler/src/LLMLL/TrustReport.hs`:
   - Add the field `trUnboundedEntryLoop :: Bool` to `TrustReport`. Set it at `:628`, beside `trHarnessAssumptions`, to `any isCliMain entryStmts`. It is not persisted and does not feed `evidenceMeet`, the effective level or strict-core admission (amendment 1).
   - `formatTrustReportJson`: append `[ "unbounded_entry_loop" .= True | trUnboundedEntryLoop report ]` to the top-level object. A console report stays byte-identical except for the version string.
   - `formatTrustReport`: add one line after the header: `"Entry loop: :mode cli runs until :done? holds; its termination is not checked (unbounded_entry_loop)."`
   - `trustReportEmitVersion = "1.9.0"`. Add a version-history comment in the style of `:398-415`.
   - `harnessAssumptions`: emit the three EFFECT-RESP entries for cli too, with the prefix `cli harness` in place of `console harness`. See finding F2.
9. `docs/llmll-ast.schema.json`:
   - `DefMain.mode` becomes `{"type": "string", "enum": ["console", "cli"]}`, with a description that names MODE-HTTP-1 and HTTP-SERVE-1.
   - Correct the descriptions of `init` (the rule now applies to console and cli), `step` (cli takes `(State, Response)`; delete the http sentence) and `done?` (required for cli, and its return must be bool there).
   - Add `"0.12.0"` to the `schemaVersion` enum. Add a v0.12.0 sentence to its description.
10. Not touched by this patch. `LLMLL.md` §9.5, §12 and the trust-report field list, `docs/getting-started.md`, `CHANGELOG.md`, the roadmap rows and the five tool comments are the documentation-lead's scope. The hand-off below lists them.

## Verification impact

- Solver-time delta: zero. No `.fq` file changes, because `def-main` produces no verification condition.
- New obligations: zero.
- Trust model: one informational top-level field and three disclosure entries for cli. No change to `effective_level`, trust closure, weakness suppressions or evidence freshness.
- Fragment: no change. Nothing reaches `LLMLL.md §5.3.3` / `§5.3.5`.
- Strict verified core: no function changes its body-faithful status.

## Performance budget

- GHC build: seven modules in `compiler/src/LLMLL/` change. `Syntax.hs` changes a type, so most of the library recompiles once. That is about the same as any `Syntax.hs` change, a few minutes on a clean build.
- Test runtime: about 15 new Haskell examples. About four of them build and run a generated program, at about 10 s each, so `stack test` gets about 40 s slower. The Python cells add about 10 s.
- `llmll check`, `verify`, `typecheck --sketch`: no measurable change. The new checks are constant-time per `def-main`.
- ProofCache and VerifiedCache: no effect. The trust-report field is derived when the report is built and is not cached.

## Contract plan

This change puts nothing in the provable fragment. It changes parsers, a type-check of declaration shape, harness codegen and a report field. None of these are LLMLL functions with contracts.

## Test plan

Step 1 measures the baseline on `main` (`bcabf52`): `stack test` example count and `python -m pytest scripts/tests/`. The expected values are 2253 and 312.

New and changed Haskell tests (`compiler/test/Spec.hs`, one new `describe "MODE-CLI-1 / MODE-HTTP-1"` block):

1. **T-P1:** `(def-main :mode http 9000 …)` fails to parse, and the error contains `HTTP-SERVE-1`. Edge case 4.
2. **T-P2:** bare `:mode http` also fails to parse.
3. **T-J1:** a JSON `def-main` with `"mode": "consoel"` fails to decode, and the error names `console` and `cli`. Edge case 5 and defect (i).
4. **T-J2:** `"mode": "http:9000"` fails to decode with the HTTP-SERVE-1 hint.
5. **T-J3:** a cli program round-trips through `AstEmit` and `ParserJSON` with `"mode": "cli"` and no change.
6. **T-T1:** cli with no `:done?` reports `def-main-done-required`. Edge case 1 is the witness: `(def-main :mode cli :init (pair 0 (wasi.io.stdout "x")) :step s)`.
7. **T-T2:** cli with a one-parameter step reports `def-main-step-arity`, and the message contains `(state, response: Response)`. Edge case 3.
8. **T-T3:** cli with a three-parameter console-shaped step reports `def-main-step-arity`.
9. **T-T4:** cli whose `:done?` returns `int` reports the error `def-main-done-type`. The same `:done?` in console stays a warning (control).
10. **T-T5:** cli with no `:init` and an `int` state reports `def-main-init-required`. With a unit state, it is accepted.
11. **T-T6:** cli with `:init 0` reports `def-main-init-shape`. The sibling `:init (pair 0 (wasi.io.stdout "x"))` is clean.
12. **T-T7:** a correct cli program that declares `:status` gives no warning. This tests amendment 3.
13. **T-C1:** the generated `Main.hs` of a fixed console program is byte-identical before and after the helper refactor. The patch puts the expected text in the test before the refactor.
14. **T-C2 (end to end):** build and run a cli fixture that keeps a counter in its state (amendment 4). Its `:init` writes `start`. Each step writes the count. `:done?` holds at 3, `:on-done` writes `end`, and `:status` returns 4. Assert stdout `start\n1\n2\n3`-shaped output ending in `end`, exit code 4, stdin not read (run with stdin closed), and no `*.event-log.jsonl` file.
15. **T-C3 (end to end):** a cli step that matches `RText` on a `wasi.fs.read` response reads a temp file. This shows that the `Response` arrives.
16. **T-C4:** RC-4 in cli. The step that makes `:done?` true also returns `wasi.io.stdout "MUST-NOT-PRINT"`. Assert that stdout does not contain it.
17. **T-R1:** the trust report of a cli program has `"unbounded_entry_loop": true` and the text line. A console program's JSON has no such key.
18. **T-R2:** the cli report has the three `cli harness` entries in `harness_assumptions`. The console entries keep their exact bytes.

Changed Haskell tests:

- `:17365` and `:17487-17493`: rewrite to the new cli shape. The second test said that cli is "untouched" by the arity rule. It becomes T-T2.
- `:17677-17698` (the two http cells): delete. T-P1 replaces them.
- `:17700-17710` (cli scope guard for `checkInitRequired`): becomes T-T5.
- `:18196` comment: correct the reason. The PB-6 assertion stays.
- `:4925`, `:5214`, `:13907`: change `"1.8.0"` to `"1.9.0"`.
- Each Spec.hs site that pins schema `"0.11.0"` (8 matches): change it to `"0.12.0"` where it pins the emitted version. Keep it where it tests that the old version is still accepted.

Python (`scripts/tests/`):

- `test_schema_valid_1.py`: replace `test_sv3_mode_http_witness_is_rejected` with `test_sv3_mode_http_does_not_parse`. It asserts that `llmll check` of the §7.2 witness fails and names HTTP-SERVE-1. Add one cell that emits a cli program and validates it against the schema.
- `test_console_init_1.py:15,158`: remove the cli exclusion, so the census includes cli. The census population for cli is zero, so the result does not change.
- `test_diverge_nosolver_1.py`: change the pinned schema version if it is the emitted one.

Target: Haskell 2253 + about 15 (18 new, about 3 deleted). Python 312, unchanged or +1. The gate is that neither count decreases.

Census: run `llmll check` on every tracked program with a `def-main` (83 at v0.28.3), before and after. Expected change: none, because no tracked program uses cli or http. Any change is a finding to report, not a reason to weaken a rule.

## Rollback

One `git revert` of the patch commit is enough. There is no flag. The schema version is pinned: a 0.12.0 compiler reads 0.11.0 documents, and a 0.11.0 compiler rejects 0.12.0 documents by its enum. No `.verified.json` or `.fq` cache contains a mode, so no cache migration is necessary. The worst-case cost is a revert plus a new release. No program in the tree uses either mode.

## Risks and unknowns

1. **The console harness changes when the helpers move.** Classification: build. Source: `CodegenHs.hs:2440-2539`. Effect: every console program's `Main.hs` would change. T-C1 compares the bytes, and the build-smoke suite runs 46 console programs. Complicates the plan only if T-C1 fails.
2. **`symbol "http"` matches the prefix of a longer word.** Classification: DX. Source: `Parser.hs:492-497`. The current `console` and `cli` alternatives have the same property. `:mode httpx` gives the HTTP-SERVE-1 hint, which is acceptable. Matters only at scale.
3. **A non-bool `:done?` becomes an error in cli only.** Classification: DX. An agent that copies a console program with an `int` `:done?` to cli gets an error it did not get before. This is the settled rule (amendment 2) and affects zero programs.
4. **Output buffering in cli.** Classification: build. Without a stdin loop, nothing flushes stdout between steps. `hSetBuffering stdout NoBuffering` matches the console harness and T-C2 tests it. Matters only if omitted.

## Findings routed out of scope

- **F1, the word "check" in amendment 1.** Rev 1 says that "`check`, `verify` and the trust report state" the unbounded loop. It also says that "no warning fires". This plan reads it as: the statement is in the trust report, JSON and text, and `check` gives no diagnostic for a correct cli program. If the language team meant a `check` note, that is a one-line `tcWarn` added later.
- **F2, harness assumptions for cli.** The settlement does not name `harnessAssumptions` (`TrustReport.hs:428-503`). Its three EFFECT-RESP entries are true for cli without change: the `Response` arm is not typed against the command, arms are shape classes, and RC-4 discards the last command. If the report omitted them for cli, it would claim less than is assumed. The plan emits them with a `cli harness` prefix and keeps the console bytes. The language team should confirm this in the next INDEX pass.
- **F3, RESP-FACT-1 stays console only.** `RespFact.hs:813` requires a console `def-main`. A cli program that requests a fact gets the existing structural error, which says "no console def-main". That message is true. Extending RESP-FACT-1 to cli is a separate row, with no consumer today. It is not filed.
- **F4, `llmll replay` on a cli program.** No log file exists, so replay fails with its "log not found" error. Amendment 6 says that this is correct. Documentation-lead can state it in §10a, which already says that only the console harness writes a log.

## Documentation hand-off (held until the patch commit)

Tags: `MODE-CLI-1`, `MODE-HTTP-1`. User-visible behaviour: `:mode cli` runs `:init`, then calls `:step (State, Response) -> (State, Command)` in a loop with no stdin, until `:done?` holds; it exits with `:status` or 0. `:init` and `:done?` are required in cli, and a non-bool `:done?` is an error there. New check kinds: `def-main-done-required`, `def-main-done-type`; `def-main-step-arity` now covers cli. `:mode http` is a parse error that names HTTP-SERVE-1. An unknown JSON mode string is a decode error. Schema: 0.11.0 to 0.12.0; `DefMain.mode` is the enum `["console","cli"]`, and the http object is removed. Trust report: 1.8.0 to 1.9.0; new top-level only-on-true field `unbounded_entry_loop`, one text line, and `cli harness` entries in `harness_assumptions`. Doc-lead scope: `LLMLL.md` §9.5 (syntax, mode table, cli semantics, the counter idiom, the unbounded-loop marker), §12 EBNF, the trust-report field list, §10a (cli writes no log); roadmap: close MODE-CLI-1 and MODE-HTTP-1, file LOOP-MEASURE-1 and HTTP-SERVE-1 (with amendment 7's limit) in the Trigger-gated Parking Lot, and add cli to REPLAY-INJECT's scope; the five tool comments that cite MODE-CLI-1 become incorrect. CHANGELOG candidate: "`:mode cli` now performs commands and exits on `:done?` without reading stdin, and the `http` stub is removed."
