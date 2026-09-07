---
name: capture-pipe-1-engineer-plan
title: "CAPTURE-PIPE-1: the console step machine captures stdout through a file, not a pipe"
status: "Plan approved and executed 2026-09-06 on branch capture-pipe-1/temp-file-capture, awaiting the user's review and commit: 1865 → 1870 hspec examples, 180 → 181 pytest; the widened build-smoke fixture failed against the v0.20.0 binary with the CAPTURE-PIPE-1 diagnosis and passes against the patched one; doc-claims cover cell 11 passes on macOS. Filed from the roadmap row CAPTURE-PIPE-1 (measured the same day)."
date: 2026-09-06
author: compiler-engineer
consumers: [user, documentation-lead, llmll-patch-implementer]
style: "ASD-STE100 Simplified Technical English. Haskell identifiers, compiler messages and test names keep their exact bytes."
---

# CAPTURE-PIPE-1: the console step machine captures stdout through a file, not a pipe

## Restatement

Replace the sink of the per-step stdout capture in the emitted console harness. `captureStdout` writes into a `createPipe` pipe and reads it back on the same thread after the step. A temporary file replaces the pipe. The redirect, the two codec pins, the echo and the descriptor close all stay. A run-the-program regression lands in the build-smoke gate by widening a fixture both sides already run.

## Context located

1. `compiler/src/LLMLL/CodegenHs.hs:1793-1868`: `captureStdout`. `hDuplicate stdout`, `createPipe`, `fdToHandle`, the utf8 pin before `hDuplicateTo`, the restore, `hClose oldStdout`, `hClose writeEnd`, `hGetContents readEnd` forced by `length`, `putStrLn output`.
2. `compiler/src/LLMLL/CodegenHs.hs:1871-1878`: `performStep` wraps every command in `captureStdout`.
3. `compiler/src/LLMLL/CodegenHs.hs:1903-1921`: the Main.hs import block. Line 1909 says the generated project ships no ghc-options, so the RTS is non-threaded. A `sample` of the hung gate showed two OS threads, the main one in `__select`.
4. `compiler/src/LLMLL/CodegenHs.hs:530-531`: `wasi_io_stdout s = putStr s`, so a report is one write in one step.
5. `compiler/src/LLMLL/CodegenHs.hs:2244` and `:2267-2272`: `directory` is already a dependency of every generated project. `unix` is added only for Main.hs. The only `System.Posix` import site in emitted code is line 1920.
6. `docs/compiler-team-roadmap.md` row `CAPTURE-PIPE-1`: the measurement and the two candidate fixes. This plan is the implementation track of that row.
7. `docs/compiler-team-roadmap.md` row `FD-CAPTURE-1` (closed table): the close after the restore. The row says a regression test pins the source.
8. `compiler/test/Spec.hs:4798-4816`, `:5557-5560`, `:14463-14476`, `:14494-14503`, `:15377-15382`, `:14510-14532`: every pin that touches `captureStdout`. They pin `captureStdout` presence, the `length`/`seq` force, `hDuplicateTo` and its import line, the `putStrLn` echo, `NoBuffering` after the restore, the locale note, and the `unix` dependency.
9. `compiler/test/Spec.hs` and `ModuleSpec.hs`: no hspec test contains `hClose oldStdout`, `hSetEncoding writeEnd` or `hSetEncoding readEnd` (rg, 2026-09-06). **Corrected during execution:** the pins live in the Python suite, `scripts/tests/test_codegen_capture_fd.py`, four tests that read `captureStdout` out of `CodegenHs.hs`. The FD-CAPTURE-1 row's claim holds; this plan's Rev 0 searched only `compiler/test/`. That file greps for `fdToHandle` binders, so it failed on the new sink with its own "needs rewriting rather than deleting" message, and it was rewritten to track `openTempFile` and `openFile` binders.
10. `scripts/build_smoke.sh:525-583`: the capture-encoding stage. It builds and runs `capture_encoding.llmll`, hexes the whole stream with `od`, and asks for `CENC_WANT` as a substring. Line 558 runs the program with no bound.
11. `scripts/build-smoke/capture_encoding.llmll`: two steps, and the RC-4 note on `ce-done?`: the step that trips `done?` has its command discarded.
12. `tools/build-smoke/buildsmoke.llmll:1006` and `:1781-1806`: the port feeds six stdin lines, runs the fixture under a 300 s `wasi.proc.run` bound, and checks `string-contains hex (c-want)`. Its pass line is byte-identical to the reference's.
13. `scripts/build_smoke_cover.py:120-134`: the stage set comes from the reference's verdict lines. Marker `captureStdout as UTF-8` keys the stage. No cell (`:588-812`) mutates `capture_encoding.llmll`.
14. `scripts/doc_claims_cover.py` cell 11: the macOS witness, bounded at 300 s since commit `92559c5`.
15. `docs/design/INDEX.md` and `LLMLL.md`: no design doc and no spec sentence names the capture sink (rg `captureStdout`, `pipe`: none). No spec text moves.
16. Measured 2026-09-06: 28 failing fixtures print 15,893 bytes and pass; 29 hang; 31 print 18,316 bytes. `/usr/bin/false` and a printing subject both hang. Stdout to a file still hangs. Baseline: 1865 hspec examples, 180 pytest passed and 10 skipped.

## Plan summary

`captureStdout` opens a temporary file with `openTempFile` under `getTemporaryDirectory`, pins it to utf8, and redirects `stdout` onto it with the existing `hDuplicateTo`. After the step it restores `stdout`, closes both handles, reads the file back through a fresh utf8 handle, forces the string, and removes the file. A regular file has no buffer bound, so a step of any size completes. The pipe drain on a forked thread is rejected: under the non-threaded RTS a blocking `write` on descriptor 1 stops every green thread, so the reader could still starve (`GHC.IO.FD.writeRawBufferPtr` takes the blocking branch for a handle whose `fdIsNonBlocking` is false). The temp file goes under `TMPDIR`, not the working directory, because a step that lists its working directory must not see the capture. The cost is three extra syscalls per step, estimated under 0.3 ms.

## Affected surface

- `compiler/src/LLMLL/CodegenHs.hs:1793-1868`: `captureStdout` body. `createPipe`/`fdToHandle` become `getTemporaryDirectory` and `openTempFile dir "llmll-capture.txt"`. `hSetEncoding writeEnd utf8` stays before `hDuplicateTo writeEnd stdout`. The restore, `hSetBuffering stdout NoBuffering`, `hClose oldStdout` and `hClose writeEnd` stay in that order. `readEnd <- openFile path ReadMode`, `hSetEncoding readEnd utf8`, `hGetContents`, the `length` force, then `removeFile path`, then the `putStrLn` echo. The comment block gains a CAPTURE-PIPE-1 paragraph and loses the createPipe rationale; the FD-CAPTURE-1, CAPTURE-ENCODING-1 and BUG-1 notes stay with "pipe" reworded to "file" where they name the sink.
- `compiler/src/LLMLL/CodegenHs.hs:1912`: add `openTempFile` to the `System.IO` import. New line: `import System.Directory (getTemporaryDirectory, removeFile)`.
- `compiler/src/LLMLL/CodegenHs.hs:1920`: remove `import System.Posix.IO (createPipe, fdToHandle)`.
- `compiler/src/LLMLL/CodegenHs.hs:2016-2030` and `:2267-2272`: reword the two comments that name the pipe pair; remove the `unix` conditional from `emitPackageYaml`, because no emitted line imports `System.Posix` after this change.
- `compiler/test/Spec.hs:14510-14532`: the two `unix` examples become "package.yaml declares no `unix` with a def-main" and "declares no `unix` without one". Two examples stay two.
- `compiler/test/Spec.hs:15377-15382`: comment reword only; the assertion on `setLocaleEncoding` is unchanged.
- `compiler/test/Spec.hs`: new `describe "CodegenHs captureStdout CAPTURE-PIPE-1"`, five examples (test plan).
- `scripts/build-smoke/capture_encoding.llmll`: step 1 emits `BIG=` plus a 131,072-character block plus `|BLEN=131072`; step 2 emits the BMP line; `ce-done?` becomes `(>= s 3)`. The block is a 16-character literal doubled 13 times through `let`, not a literal. The header comment gains the CAPTURE-PIPE-1 paragraph and the RC-4 note moves with the count.
- `scripts/build_smoke.sh:558`: the run becomes `perl -e 'alarm 120; exec @ARGV' "$CENC_EXE"`, behind `command -v perl || fail`. A third diagnosis branch prints `diagnosis : the 131072-byte step did not complete (CAPTURE-PIPE-1)` when the hex lacks the BMP run and the output file is under 131,072 bytes. The verdict lines are byte-identical, so `build_smoke_cover.py:129` and `buildsmoke.llmll:1800-1806` need no change. The port's 300 s bound, six-line feed and substring check already cover the widened fixture.
- `tools/doc-claims/docclaims.llmll`: no change. Cell 11 of `doc_claims_cover.py` flips from `HANG` to `ok` on macOS once the gate is rebuilt with the patched compiler.
- `docs/llmll-ast.schema.json`: no version change.
- `docs/compiler-team-roadmap.md` row `CAPTURE-PIPE-1`: documentation-lead moves it on ship. This plan narrows the row's Next Action: the test is a widened fixture plus a bounded reference run, not a new stage.

## Verification impact

None. The change is emitted runtime text in the console harness and a `def-shell` fixture. No `.fq` file, obligation, trust closure, weakness suppression or verification fragment changes. No function newly falls back from a body-faithful VC.

## Performance budget

- GHC build: `CodegenHs.hs` and `Spec.hs` recompile; `compiler/app/Main.hs` relinks. Estimate two minutes locally.
- Test suite: five string-pin examples add under one second.
- Per step at run time: one `openTempFile`, one `openFile` and one `removeFile` replace one `createPipe` and one `fdToHandle`. Estimate 0.1 to 0.3 ms per step. The refute-crux port runs about 4,000 steps, so at most 1.2 s on a CI step that takes 4 min 25 s (run 34069949780, step 20). The doc-claims gate runs 95 steps, so under 30 ms.
- The widened build-smoke fixture: a 131,072-character `String` costs about 5 MB of heap for one step, a 131 KB event-log line, and `od` over 131 KB. Estimate under 0.5 s. Measure the stage before and after and report both in the hand-off.
- Binary, `.fq` size, ProofCache and VerifiedCache: unchanged.

## Contract plan

Nothing lands in the provable fragment. The patch changes emitted Haskell runtime text and a `def-shell` fixture, and `def-shell` bodies sit outside verification by construction (`LLMLL.md` §9).

## Test plan

- New hspec examples, `compiler/test/Spec.hs`, five: (1) the preamble contains `openTempFile` and `getTemporaryDirectory` and does not contain `createPipe`; (2) `hSetEncoding writeEnd utf8` precedes `hDuplicateTo writeEnd stdout`; (3) `hSetEncoding readEnd utf8` precedes `hGetContents readEnd`; (4) `removeFile` follows the `length output` force; (5) `hClose oldStdout` follows `hDuplicateTo oldStdout stdout`. Examples 2, 3 and 5 mirror in hspec the pins the Python suite already holds in `scripts/tests/test_codegen_capture_fd.py`.
- Rewritten hspec examples: the two `unix` examples at `Spec.hs:14510-14532`.
- Test-count target: 1865 measured on `main` at v0.20.0 to 1870. Python: `scripts/tests/test_codegen_capture_fd.py` is rewritten for the file sink (binders `openTempFile` and `openFile` tracked, `readEnd` no longer an exception) and gains one test, the file removal after the forced read: 180 passed to 181, 10 skipped unchanged.
- Run-the-program test, negative half first: run `scripts/build_smoke.sh` against the v0.20.0 binary before building the patched compiler. On Linux and macOS the 131,072-byte step must deadlock, perl must kill it at 120 s, and the stage must fail with the CAPTURE-PIPE-1 diagnosis. Record that failure in the hand-off. Then build the patched compiler and run the gate again: the stage passes with the unchanged verdict line.
- macOS witness: rebuild `docclaims` with the patched compiler and run `scripts/doc_claims_cover.py`. Cell 11 must report `ok`, exit 1, about 0.1 s.
- Cover parity: run `scripts/build_smoke_cover.py` against the rebuilt `buildsmoke` port. Cell 1 must pass and report no unkeyed verdict.
- Golden or snapshot regen: none.
- End-to-end CLI path: `llmll build` of any console program, then a run.

## Rollback

One commit, one revert. No flag. No schema version. No `.verified.json` or `.fq` file changes, so no cached artifact in a user environment needs migration. A generated project rebuilds from source on the next `llmll build`. The worst case is the revert itself, which restores the pipe and the macOS hang.

## Risks and unknowns

1. **An unwritable `TMPDIR`.** DX. `getTemporaryDirectory` falls back to `/tmp`; the doc-claims cover's `ENV` sets no `TMPDIR` and CI sets one. If the directory is unwritable, `openTempFile` throws inside `performStep` and the program dies with the path in the `IOError`. That is a loud failure where the pipe hung. Complicates the plan only on an exotic host.
2. **A program that lists `TMPDIR` sees the capture file mid-step.** DX. No in-tree program lists it; the five ports list fixture directories and their own work directories. Matters only at scale.
3. **The `unix` removal.** Build. rg shows line 1920 as the only `System.Posix` import in emitted code, so no generated program loses a module. The two tests flip. Bite: none.
4. **`perl` in the reference gate.** Build. Present on `ubuntu-latest` and on macOS at `/usr/bin/perl`. A host without it fails the new guard by name. Matters only on an exotic host.
5. **RC-4 in the widened fixture.** DX. If `ce-done?` stays at `(>= s 2)`, the BMP step becomes the discarded step and the stage fails with an empty hex that no diagnosis names. The plan moves `done?` to 3 with the step; the negative run above catches a miss.
6. **The hex substring over 262 KB in a bash `case`.** Performance. Not measured; estimate well under a second. Measured in the gate run.
7. **Spec drift.** None found. `LLMLL.md` is silent on the capture sink. Rev 0 of this plan said the FD-CAPTURE-1 row claimed a pin the suite lacks; that was wrong (item 9), and the row needs no correction.

## Execution record, 2026-09-06

- Negative half, direct: the widened fixture built with the v0.20.0 binary deadlocked; `perl` ended it at 60 s with exit 142; the output file held 0 bytes and no BMP run.
- Negative half, full gate: `build_smoke.sh` with the v0.20.0 binary failed at the capture-encoding stage with `diagnosis : the 131072-byte step did not complete (CAPTURE-PIPE-1)`; the four stages before it passed.
- Positive half: `build_smoke.sh` with the patched binary passed every stage in 200 s; `build_smoke_cover.py --no-slow` passed 9 of 9 cells in 497 s against a `buildsmoke` port rebuilt with the patched compiler.
- macOS witness: `docclaims` rebuilt with the patched compiler; `doc_claims_cover.py` passed 17 of 17 cells, cell 11 `ok` with 189 lines and exit 1.
- hspec: 1870 examples, 0 failures. One existing pin needed retargeting: `the pins precede the first handle use and the event-log openFile` located the first `<- openFile` in the harness, which the capture's read handle now is; it names `logHandle <- openFile` instead, and the reason is written at the test.
- pytest: 181 passed, 10 skipped. `scripts/tests/test_codegen_capture_fd.py` failed on the new sink with its own "needs rewriting rather than deleting" message and was rewritten to track `openTempFile` and `openFile` binders; it gains one test.
- Build warnings: the same four pre-existing `CodegenHs.hs` warnings as the v0.20.0 baseline build, none new.
- `DRIFT-DOC-4`: 1256 citations in 179 living files, all resolve. `DRIFT-CT-3` and `version_gate.sh` pass.
- Not measured: the per-step cost of the file sink. The CI timing of the refute-crux step on the next `main` run is the measurement.

## Hand-off to documentation-lead, on ship

Ticket `CAPTURE-PIPE-1`. User-visible change: none at the CLI. Every generated `console` program now captures a step's stdout through a temporary file under `TMPDIR` instead of a pipe, so a step of any size completes; the generated `package.yaml` no longer lists `unix`. `LLMLL.md` candidate text: none, the spec is silent on the capture sink and §10a is unchanged. Schema delta: none. Test delta: hspec 1865 to 1870, pytest 180 to 181 passed with 10 skipped. CHANGELOG `## Latest` candidate: "CAPTURE-PIPE-1: a console step that printed more than the OS pipe buffer (16 KiB on macOS, 64 KiB on Linux) deadlocked the generated program; the step machine now captures stdout through a temporary file, `scripts/build-smoke/capture_encoding.llmll` prints 131,072 bytes in one bounded step to pin it, and the doc-claims cover's cell 11 passes on macOS." Roadmap: move `CAPTURE-PIPE-1` to the closed `[CT]` table with the measurement in the execution record above; the `FD-CAPTURE-1` row needs no correction (Rev 0 of this plan said otherwise and was wrong). INDEX: this file. Spec drift: none found.
