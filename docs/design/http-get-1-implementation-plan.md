---
name: http-get-1-implementation-plan
title: "HTTP-GET-1: engineer plan and measurements for wasi.http.get"
status: "Rev 1, APPLIED and SHIPPED v0.21.0 (commit dc2c9cf, 2026-09-07). The plan was approved by the user on 2026-09-07 and executed as written, with one change the budget measurement forced (the System.Timeout wrapper, section 9); section 9 records every measurement taken while applying it and on the first main run (cold build about two minutes on the runner; the Stack cache saved under the new key). Still owed: the exact-key cache hit on the run after this record's push."
date: 2026-09-07
author: compiler-engineer
consumers: [user, documentation-lead, language-team]
---

# HTTP-GET-1: engineer plan and measurements for `wasi.http.get`

**One line.** The design is [`http-get-1-proposal.md`](http-get-1-proposal.md) Rev 1, settled on
realization A: `http-client` and `http-client-tls` compiled into the generated program, with the
body, its imports and its dependencies emitted only for a program that calls `wasi.http.get`. This
file is the implementation track of that design and the record of what applying it measured.

---

## 1. Restatement

Add one `Command` constructor, `wasi.http.get : string -> string -> Command`, across five compiler
modules. Confine the generated-program cost (41 new packages) to programs that call it. Do not
reopen the contract; the proposal's section 4 is the contract, clause by clause.

## 2. Context that shaped the plan

- `generateHaskell` in `compiler/src/LLMLL/CodegenHs.hs` computes `warnings` with `stmtWarnings`
  and hands the statement list to `emitLibHs` and a `Bool` to `emitPackageYaml`; one more predicate
  threads the same way. `generateHaskellMulti` concatenates every module's statements first, so the
  predicate sees imported modules.
- `runtimePreamble` is a top-level CAF and the comments above `import qualified System.Process as P`
  and above `jsonPreamble` say why: the WASI-RT completeness fold in `compiler/test/Spec.hs` folds
  over one list. A conditional block breaks that invariant, so the fold now reads two lists.
- `llmll_publish_io` catches `IOException` only. `http-client` throws `HttpException`. The body must
  catch it itself or a refused connection is an uncaught exception.
- The `wasi.env.get` literal rule in `inferExpr` and `mkEnvNameMalformed` in
  `compiler/src/LLMLL/Diagnostic.hs` give the shape of a literal-argument rule and its diagnostic.
- `harnessAssumptions` in `compiler/src/LLMLL/TrustReport.hs` is a guard chain on the console
  harness; `hasHole` in the same module is the precedent for a local expression walker.
- The two hand-maintained preamble-name lists, in `scripts/build_smoke.sh` and
  `tools/build-smoke/buildsmoke.llmll`, are edited together by their own rule. A list entry adds no
  verdict line, so the BUILD-GATE-1 differential cover is unaffected.
- The `version-gate` CI job runs pytest with no toolchain; the `spec-roundtrip` job runs
  `scripts/tests/test_source_encoding.py` with `LLMLL_BIN` set. Runtime cells follow that precedent.
- The Stack cache key in `.github/workflows/version-gate.yml` hashes the compiler's three files
  only; the "Cache fixpoint binary" step documents that an exact key hit skips the save.
- Precedent footprints: ENV-READ-1 (`cd9cb42`) and FS-STAT-1 (`61c9d3e`, which committed its plan
  file beside the patch).

## 3. What changed

### 3.1 Compiler

| Module | Change |
|---|---|
| `TypeCheck.hs` | `builtinEnv` row `wasi.http.get : TFn [TString, TString] (TCustom "Command")`. In `inferExpr`, beside the `wasi.env.get` rule: a literal first argument not beginning `http://` or `https://` records `mkHttpUrlMalformed`. |
| `Diagnostic.hs` | `mkHttpUrlMalformed`, kind `http-url-malformed`, with a suggestion naming the argument order. |
| `ObligationAssembly.hs` | `primEffect "wasi.http.get" = Just (Caps {ENetHttp, EFsWrite})`, above the `wasi.` fallthrough, with the soundness comment. |
| `CodegenHs.hs` | `usesHttpGet` (one predicate over `stmtExprs` with `callsName`), computed once in `generateHaskell` and threaded to `emitLibHs` (a `Bool` parameter, conditional `httpGetImports`), the preamble splice (`runtimePreamble ++ httpGetPreamble` when the predicate holds) and `emitPackageYaml` (a `Bool` parameter, conditional `httpGetDeps`). Four new exports. The stale dependency comment reworded. |
| `TrustReport.hs` | `harnessAssumptions` returns `consoleEntries ++ httpGetEntries`; the second is the proposal's section 7 text, conditioned on a call, found by a local total walker. |

The preamble body follows the proposal's clauses in order: prefix check (4.1), `parseRequest` with
`method = methodGet`, `redirectCount = 10`, `responseTimeoutMicro 60000000` (4.8, 4.2, 4.6),
`openBinaryTempFile` in `takeDirectory dest` and a `brRead` loop (4.3), rename only when the loop
returned without an exception and the status is 2xx (4.4), `removeFile` and `RErr` otherwise (4.5),
`tlsManagerSettings` (4.7). `methodGet` from `Network.HTTP.Types.Method` because the generated
module has no `OverloadedStrings`. `try` at `HttpException` wraps the fetch; `onException` removes
the temporary on every other path.

### 3.2 Tests and fixtures

- `compiler/test/Spec.hs`: describe "HTTP-GET-1", HG-1 to HG-20. The completeness fold's
  `preambleText` and its per-name binding check read `runtimePreamble ++ httpGetPreamble`. Counts:
  nineteen `wasi.*` names, `builtinEnv` at 104, `needsBinding` at 73.
- `scripts/tests/test_http_get_1.py` and `scripts/tests/fixtures/http_get.llmll`: ten runtime
  cells over local listeners, `LLMLL_BIN`-gated. The fixture prints the fetch's arm on its second
  turn and exits 0 regardless, so the arm, the bytes at `dest` and the exit status are three
  separate observations.
- `scripts/build-smoke/smoke.llmll`: `smoke-get` calls the builtin once, so that fixture pays and
  exercises the conditional group. `wasi_http_get` added to both hand-maintained lists.

### 3.3 CI and pins

- `compiler/generated-deps.txt`: every name `emitPackageYaml` can emit. HG-16 asserts the emitted
  set across both variants equals the file. The Stack cache key hashes it.
- `.github/workflows/version-gate.yml`: the key gains the pin; a new step runs the runtime cells in
  the `spec-roundtrip` job after the source-encoding gate.
- `Dockerfile`: unchanged; the runtime stage has no GHC and `ca-certificates` is present.
- `docs/llmll-ast.schema.json`: unchanged.

## 4. Verification impact

Zero SMT obligations, zero contract clauses, no `RespFact` row. `effect_summary` for a caller gains
`net.http` and `fs.write`, bounded. One additive `harness_assumptions` entry, conditioned on a call.
Programs that do not call the builtin produce byte-identical Haskell (measured, section 9), so no
`.verified.json`, `.fq` or `codegen_semantics_version` movement. Nothing widens `Σ_auto`.

## 5. Performance budget

Compiler: five modules touched, one near-full recompile because `Diagnostic.hs` is imported widely.
Generated programs that fetch: 33 to 75 packages, 41 new; 40 s cold on Apple silicon, minutes on a
runner, once per cache key. Programs that do not fetch: unchanged. BUILD-GATE-1's `smoke.llmll`
now pays the group once per key. `llmll check` and `verify`: one `when` clause per `EApp`.

## 6. Contract plan

Nothing lands in the provable fragment: a sealed builtin realized in codegen, a type rule over a
literal, an effect-catalog entry and a report entry. The fixture is `def-shell` and one literal
`def`. The proposal's section 9 records "contract channel: none".

## 7. Rollback

One commit to revert. No schema version, no cache migration. HG-12 and HG-14 pin that a non-calling
program's output does not change. The cache pin file reverts with the commit and the previous key's
cache is still present.

## 8. Risks, as planned

1. An uncaught `HttpException` crashes the program: the body's own `try`, pinned by HG-11 and run by
   the refused-connection cell.
2. The preamble is no longer one CAF: the fold reads both lists; HG-16 and HG-20 guard the split.
3. The cache key never learns the delta: the pin file in `hashFiles`; two consecutive CI runs are
   the proof, the second showing no package builds.
4. The budget under the non-threaded RTS: the two hung-server cells (section 9).
5. Two hand-maintained lists: edited together in this change.

## 9. Measurements taken while applying the plan

| Measurement | Result |
|---|---|
| hspec baseline at `cd00566` | 1870 examples, 0 failures |
| hspec after the patch | 1891 examples, 0 failures (+21: HG-1 to HG-20, and the one the completeness fold generates for the new name). One pre-existing pin, CP-4 "wasi.http.get is NOT declared", was retargeted to assert the declared shape rather than deleted |
| pytest baseline (no `LLMLL_BIN`) | 181 passed, 10 skipped |
| pytest after, no `LLMLL_BIN` | 181 passed, 20 skipped (the ten new cells skip without a toolchain) |
| pytest after, `LLMLL_BIN` set, `test_http_get_1.py` | 10 passed in 132 s, of which about 120 s are the two budget cells waiting their 60 s out |
| **Budget, measurement 2 of the proposal's section 11** | **Positive for both offline targets, in two runs.** Run one carried `http-client`'s `responseTimeout` alone (60 s): a listener that never answers and one that stalls after one body byte both held the built program past 130 s, so the library's budget covered neither shape here (reason not established). Run two added a `System.Timeout` wrapper around the whole transfer in the preamble: both shapes answer `RErr` at about 60 s. `System.Timeout` interrupts a blocked socket read in the generated program's RTS; `PROC-TIMEOUT-1`'s site is a blocking foreign call, which it cannot. The wrapper is the layer that delivers clause 4.6 |
| Byte identity for a non-fetching program | `examples/replay-demo` built with `--emit-only` by the pre-patch and the patched compiler: `diff -r` empty |
| Negative half, pre-patch binary | `llmll check` on the fixture: `warning: call to unknown function 'wasi.http.get'` |
| Fixture and `smoke.llmll` under the patched compiler | `llmll check` OK, the pre-existing `:done?` warning only |
| Closure delta, `lts-22.43`, this machine | 33 to 75 packages, 41 new, 40 s wall clock cold |
| New compiler warnings in the five edited modules | none; every warning the rebuild printed for them blames to an earlier commit |
| Path-citation lint over the new and edited docs | every citation resolves; the one unresolved citation the gate reports predates this branch (`critique-2026-09-05-triage.md`, a gitignored `generated/` path) |

The owed measurements from the proposal's section 11, as they stand after the merge to `main`
(`version-gate` run 34180880222, 2026-09-08, success in 27m00s against 19m37s for the previous
`main` run):

1. **Cold build on the runner: taken.** The 41-package group was first built inside the new
   "Run HTTP-GET-1 runtime cells" step, 240 s in total, of which about 120 s are the two budget
   cells waiting their 60 s out; so the fixture build with the cold group cost about two minutes on
   the runner, against 40 s on Apple silicon. BUILD-GATE-1 then compiled `smoke.llmll` against the
   already-built group in 129 s.
2. **The budget: taken, positive**, recorded above, with the one change to the realization that it
   forced (the `System.Timeout` wrapper). The resolver target stays a hand measurement.
3. **The cache key: first half taken.** The run missed the exact key, restored the previous cache
   through the restore-key prefix (`stack-Linux-7248…`), and saved under the new key
   (`stack-Linux-452a…`) at the end, which is the designed path: the pin file moved the key, so the
   save was not skipped. The second half, an exact hit that rebuilds nothing, is the run after
   this record's own push.

**Consequence of measurement 2 for the spec text: none.** Clause 4.6 stands as written. What the
measurement changed is the realization note: the budget is delivered by a `System.Timeout` wrapper
around the whole transfer, not by `http-client`'s `responseTimeout`, which is kept for the header
phase but did not fire for either shape in the built program. Two observations for the roadmap,
routed to documentation-lead: `PROC-TIMEOUT-1`'s row can record that its mechanism is specific to a
blocking foreign call, since a socket read was interrupted here under the same RTS; and the
proposal's section 2.4, which listed the budget as the one property realization B kept over A, is
settled in A's favour by this run.

## 10. Hand-off to documentation-lead

Held for the review-ready signal. Ticket `HTTP-GET-1`. User-visible: a new §13.9 row,
`wasi.http.get | string string -> Command | (import wasi.http (capability get URL)) | Fetch url and
write the body to dest as bytes, never decoded; RNone on a 2xx with the complete body renamed onto
dest, RErr (naming the status, or the transport failure) otherwise with dest unchanged; follows
redirects (10), 60-second budget, certificate validation on; a literal url not beginning http:// or
https:// is a type error`; the delivery-notes paragraph gains `wasi.http.get` among the `RNone`
deliveries; §7 names the `get` verb. Schema delta: none. Roadmap: `HTTP-GET-1` DECIDE to SHIPPED;
`CAP-1-REAL` gains the sentence that `get` rides any `wasi.http` import; the `DRIVER-LL` row's
step (3) becomes the stage A port. Drift to record: `harness_assumptions` has no `LLMLL.md`
sentence (`REPORT-GATE-1` class); `effect-response-channel-proposal.md` carries both the `RText`
and the `RNone` reading. CHANGELOG candidate: "`wasi.http.get` fetches a URL to a file as bytes,
atomically, with `RNone` on 2xx and `RErr` otherwise; realized with `http-client-tls` and paid only
by programs that call it."
