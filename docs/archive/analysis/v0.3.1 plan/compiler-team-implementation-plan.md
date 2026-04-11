# v0.3.1 Implementation Plan — Compiler Team

> **Source:** Professor's plan at `professor-implementation-plan.md` (this directory)  
> **Baseline:** v0.3 tagged (`a96f2ce`), 145 tests, clean build  
> **Branch:** `feature/v0.3.1-event-log`  
> **Language team review:** Issues #1–#3 resolved below  
> **Professor review:** Approved. Two implementation flags noted below.

---

## Design Decisions (Resolved)

| Question | Decision | Rationale |
|---|---|---|
| Event Log format | **True JSONL** (one object per line, no envelope) | Crash-safe without tolerant parser. Fixes language team issue #2. |
| Output capture | **Redirect stdout → capture → echo + log** | Fixes language team issue #1: `result` field is no longer empty. |
| Leanstral testing | **Mocks only** (`--leanstral-mock`) | Real `lean-lsp-mcp` integration deferred |
| Proof cache location | **Per-file sidecar** (`.proof-cache.json`) | Follows `.verified.json` pattern |
| MCP transport | **stdio** (subprocess) | Simplest; HTTP deferred |

---

## Language Team Review — Resolutions

### Issue #1: `result` field is always empty (Substantive)

**Problem:** The console loop's `cmd :: IO ()` writes directly to stdout. There's no return value to log.

**Resolution:** Capture stdout during `cmd` execution using `hDuplicate`/`hDupTo`:

```haskell
-- Generated code pattern:
import GHC.IO.Handle (hDuplicate, hDupTo)

captureStdout :: IO () -> IO String
captureStdout action = do
  (readEnd, writeEnd) <- createPipe
  oldStdout <- hDuplicate stdout
  hDupTo writeEnd stdout        -- redirect stdout → pipe
  action                        -- cmd writes to pipe
  hDupTo oldStdout stdout       -- restore stdout
  hClose writeEnd
  output <- hGetContents readEnd
  length output `seq` pure ()   -- force read
  hClose readEnd
  putStr output                 -- echo to real stdout
  pure output
```

The loop becomes:
```haskell
  let (s', cmd) = step s line
  output <- captureStdout cmd
  hPutStrLn logHandle (eventJsonL seq "stdin" line "stdout" output)
```

Now the `result` field has actual content for replay comparison.

> [!NOTE]
> This adds `GHC.IO.Handle` and `System.Posix.IO` (for `createPipe`) to generated imports. Both are available on macOS/Linux. For Windows, `System.IO` `hSetBinaryMode` + temp file is the fallback — but LLMLL's target is Docker/WASM, not Windows.

### Issue #2: JSONL vs JSON envelope contradiction (Minor)

**Resolution:** Switch to true JSONL. No envelope, no footer, no tolerant parser needed.

```
{"type":"header","version":"0.3.1","module":"hangman"}
{"type":"event","seq":0,"input":{"kind":"stdin","value":"hello"},"result":{"kind":"stdout","value":"H_llo"},"captures":[]}
{"type":"event","seq":1,"input":{"kind":"stdin","value":"e"},"result":{"kind":"stdout","value":"Hello"},"captures":[]}
```

Each line is independently parseable. Crash → partial log → valid up to last flushed line. Replay reads line by line.

### Issue #3: `mockProofResult` naming (Minor)

**Resolution:** Already addressed. `mockProofResult` is exported only from `MCPClient` and gated behind `--leanstral-mock`. Docs: `-- | Test-only: returns ProofFound "by sorry" for any obligation.`

---

## Phase A: Event Log (Deterministic Replay)

### A1. Generated Code Changes

#### [MODIFY] [CodegenHs.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs)

**`emitMainBody` (L686–728):**

Current `loopBody` (L703–709):
```haskell
loopBody ind =
  [ ind <> "eof <- hIsEOF stdin"
  , ind <> "if eof then return () else do"
  , ind <> "  line <- getLine"
  , ind <> "  let (s', cmd) = " <> stepCall step <> " s line"
  , ind <> "  cmd"
  , ind <> "  loop s'"
  ]
```

Modified:
```haskell
loopBody ind =
  [ ind <> "eof <- hIsEOF stdin"
  , ind <> "if eof then return () else do"
  , ind <> "  line <- getLine"
  , ind <> "  seq <- readIORef seqRef"
  , ind <> "  let (s', cmd) = " <> stepCall step <> " s line"
  , ind <> "  output <- captureStdout cmd"
  , ind <> "  hPutStrLn logHandle (eventJsonL seq \"stdin\" line \"stdout\" output)"
  , ind <> "  hFlush logHandle"
  , ind <> "  modifyIORef' seqRef (+1)"
  , ind <> "  loop s'"
  ]
```

**`main` preamble** gains log handle + seqRef initialization:
```haskell
main = do
  hSetBuffering stdout NoBuffering
  logHandle <- openFile "<module>.event-log.jsonl" WriteMode
  hPutStrLn logHandle (headerJsonL "<module>")
  seqRef <- newIORef (0 :: Int)
  -- ... existing init ...
  loop state0 logHandle seqRef
  hClose logHandle
```

**`loop` signature** changes from `loop s` to `loop s logHandle seqRef`.

> [!WARNING]
> **Professor flag #2:** The `doneLines` block (L718–727 in CodegenHs.hs) generates `loop s'` calls in three branches (`no-done`, `done-only`, `done+onDone`). ALL of these must be updated to `loop s' logHandle seqRef`. Missing any one will produce a GHC compile error in the generated code. Verify during implementation that every `loop` call site in the generated output carries the extra arguments.

#### [NEW] `emitEventLogPreamble` in CodegenHs.hs

Emits three helpers into generated `Main.hs`:

```haskell
-- 1. JSONL header
headerJsonL :: String -> String
headerJsonL mod = "{\"type\":\"header\",\"version\":\"0.3.1\",\"module\":\"" ++ mod ++ "\"}"

-- 2. JSONL event
eventJsonL :: Int -> String -> String -> String -> String -> String
eventJsonL seq ik iv rk rv =
  "{\"type\":\"event\",\"seq\":" ++ show seq
  ++ ",\"input\":{\"kind\":\"" ++ ik ++ "\",\"value\":\"" ++ esc iv
  ++ "\"},\"result\":{\"kind\":\"" ++ rk ++ "\",\"value\":\"" ++ esc rv
  ++ "\"},\"captures\":[]}"
  where esc = concatMap (\c -> if c == '"' then "\\\"" else if c == '\n' then "\\n" else [c])

-- 3. Stdout capture
captureStdout :: IO () -> IO String
captureStdout action = do
  oldStdout <- hDuplicate stdout
  (readEnd, writeEnd) <- createPipe
  hDupTo writeEnd stdout
  action
  hFlush stdout
  hDupTo oldStdout stdout
  hClose writeEnd
  output <- hGetContents readEnd
  length output `seq` pure ()   -- ⚠ FORCE READ (professor flag #1: lazy I/O risk)
  putStr output                 -- echo to real stdout
  pure output
```

> [!WARNING]
> **Professor flag #1:** `hGetContents` is lazy — the pipe may not be fully read before `hClose` unless forced. The `length output \`seq\` pure ()` line is mandatory.

**Generated imports addition:** `Data.IORef`, `GHC.IO.Handle (hDuplicate, hDupTo)`, `System.Posix.IO (createPipe)`.

**NaN guard:** `validateCapture` wrapper present but NOOP for v0.3.1.

### A2. Replay Subcommand

#### [MODIFY] [Main.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs)

- Add `CmdReplay FilePath FilePath` to `Command`
- Add `"replay"` subcommand
- Add `doReplay` handler

#### [NEW] [Replay.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Replay.hs)

~100 lines. Core logic:

1. Parse `.event-log.jsonl` line-by-line (skip header, parse events)
2. Build program via `doBuild` infrastructure
3. Feed each event's `input.value` to program stdin via `createProcess`
4. Capture stdout per-event, compare against `result.value`
5. Report divergences with sequence number

```haskell
module LLMLL.Replay (runReplay, ReplayResult(..)) where

data ReplayResult = ReplayResult
  { replayTotal    :: Int
  , replayMatched  :: Int
  , replayDiverged :: [(Int, Text, Text)]  -- (seq, expected, actual)
  }
```

### A3. Tests (5 new)

| # | Test | What it covers |
|---|------|----------------|
| 1 | `emitEventLogPreamble` contains `eventJsonL` and `captureStdout` | Preamble emission |
| 2 | Generated `Main.hs` with `def-main :mode console` contains `event-log.jsonl` | Codegen integration |
| 3 | `eventJsonL` output parses as valid JSON | Format correctness |
| 4 | JSONL line-by-line parse ignores partial trailing line | Crash tolerance |
| 5 | `esc` function escapes quotes and newlines | Serialization safety |

### A4. Acceptance Criteria

- [ ] `llmll run examples/hangman.llmll` produces `hangman.event-log.jsonl`
- [ ] Event log contains both `input` and `result` with actual stdout content
- [ ] `llmll replay examples/hangman.llmll hangman.event-log.jsonl` compares output and reports match/diverge
- [ ] Partial logs (kill mid-run) are parseable up to last flushed line
- [ ] NaN guard infrastructure present

---

## Phase B: Leanstral MCP (Mock-Only)

### B1. New Modules

#### [NEW] [LeanTranslate.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/LeanTranslate.hs) (~150 lines)

LLMLL contract AST → Lean 4 `theorem` text.

**Supported:** Linear arithmetic, list structural induction, `for-all` quantifiers.  
**Unsupported:** `map`, `fold`, custom ADTs → `-- UNSUPPORTED: <reason>`, hole stays `?proof-required`.

#### [NEW] [MCPClient.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/MCPClient.hs) (~120 lines)

```haskell
data MCPResult
  = ProofFound Text
  | ProofTimeout
  | ProofError Text
  | LeanstralUnavailable Text

-- | Test-only: returns ProofFound "by sorry" for any obligation.
-- Gated behind --leanstral-mock. Not used in production builds.
mockProofResult :: Text -> MCPResult
```

#### [NEW] [ProofCache.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ProofCache.hs) (~80 lines)

Per-file `.proof-cache.json` sidecar. SHA-256 hash for cache invalidation.

### B2. Modified Files

| File | What |
|------|------|
| `Main.hs` | `--leanstral-cmd`, `--leanstral-timeout`, `--leanstral-mock` on `CmdVerify`. Pipeline: liquid-fixpoint → `?proof-required` scan → cache check → Leanstral/mock → cache write. |
| `HoleAnalysis.hs` | `holeComplexity :: Maybe Text` field. Normalize → `:simple`/`:inductive`/`:unknown`. `"complexity"` in JSON output. |
| `package.yaml` | `cryptohash-sha256` dependency. |

### B3. Tests (10 new)

| # | Test | What it covers |
|---|------|----------------|
| 1 | `translateObligation` linear arithmetic → valid Lean 4 | Translation |
| 2 | `translateObligation` unsupported → `UNSUPPORTED` comment | Graceful degradation |
| 3 | `translateObligation` list induction → `∀ ... List` | List support |
| 4 | `mockProofResult` → `ProofFound` | Mock works |
| 5 | `callLeanstral` unavailable binary → `LeanstralUnavailable` | Fallback |
| 6 | `ProofCache` save → load roundtrip | Sidecar I/O |
| 7 | `ProofCache` hash mismatch detection | Cache invalidation |
| 8 | `holeComplexity` normalizes `"complex-decreases"` → `:inductive` | Classification |
| 9 | `formatHoleReportJson` includes `"complexity"` | JSON output |
| 10 | Mock pipeline: translate → mock-prove → cache → verify | End-to-end |

### B4. Acceptance Criteria

- [ ] `?proof-required :inductive` → valid Lean 4 theorem
- [ ] `--leanstral-mock`: proof resolved, certificate in `.proof-cache.json`
- [ ] Next `llmll verify`: certificate from cache, no re-call
- [ ] Without mock/binary: `?delegate-pending`, build doesn't fail
- [ ] `llmll holes --json` includes `"complexity": "inductive"`

---

## Phase C: Integration Testing

- [NEW] `examples/event_log_test/` — minimal console, generate log → replay → verify
- [NEW] `examples/proof_required_test/` — list fold with `?proof-required :inductive`, test with `--leanstral-mock`
- Regression: all 145 tests pass, `llmll verify examples/withdraw.llmll` still SAFE

---

## Delivery Schedule

```
Phase A: Event Log           ─── 1-2 days ───→ commit + 5 tests
Phase B: Leanstral MCP       ─── 3-5 days ───→ commit + 10 tests  
Phase C: Integration testing  ─── 1 day   ───→ examples + regression
                                              ─────────────────────
                              Total: ~160 tests, v0.3.1 tagged
```

## File Summary

| Phase | New Files | Modified Files |
|---|---|---|
| A | `Replay.hs` | `CodegenHs.hs`, `Main.hs`, `Spec.hs` |
| B | `LeanTranslate.hs`, `MCPClient.hs`, `ProofCache.hs` | `Main.hs`, `HoleAnalysis.hs`, `package.yaml`, `Spec.hs` |
| C | `examples/event_log_test/`, `examples/proof_required_test/` | — |
