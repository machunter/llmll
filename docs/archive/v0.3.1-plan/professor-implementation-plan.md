# v0.3.1 Implementation Plan

> **Features:** Leanstral MCP Integration + Event Log Spec  
> **Prerequisite:** v0.3 shipped (12/12), clean build, 69+ tests passing  
> **Estimated effort:** ~2 weeks

---

## Scope

Two features, ordered by dependency:

| Phase | Feature | Why this order |
|---|---|---|
| **A** | Event Log | No external dependencies. Pure codegen + runtime change. Simpler to verify. |
| **B** | Leanstral MCP | Depends on external `lean-lsp-mcp` service. Can develop against mocks while Phase A ships. |
| **C** | Integration testing | Both features verified against acceptance criteria |

---

## Phase A: Event Log (Deterministic Replay)

The Event Log records every `(Input, CommandResult, captures)` triple during execution. Replay reads the log and re-injects inputs, producing identical output.

### A1. Event Log Format

> [!IMPORTANT]
> The spec (LLMLL.md §10a) defines an S-expression format. The implementation uses JSON for machine consumption — the S-expression rendering is a display concern.

**Format: `.event-log.json`**

```json
{
  "version": "0.3.1",
  "module": "hangman",
  "events": [
    {
      "seq": 0,
      "input": { "kind": "stdin", "value": "hello" },
      "result": { "kind": "stdout", "value": "H_llo" },
      "captures": []
    },
    {
      "seq": 1,
      "input": { "kind": "stdin", "value": "e" },
      "result": { "kind": "stdout", "value": "Hello" },
      "captures": [
        { "source": "wasi.clock.monotonic", "value": 1741823200000 },
        { "source": "wasi.random.bytes", "value": "4f2a..." }
      ]
    }
  ]
}
```

### A2. Implementation: Generated Code Changes

#### [MODIFY] [CodegenHs.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs)

The console and CLI loops in `emitMainBody` (L682–757) currently read stdin and execute commands directly. The event log wraps this loop:

**Console mode (L682–727):**

Current:
```
loop s = do
  eof <- hIsEOF stdin
  if eof then return () else do
    line <- getLine
    let (s', cmd) = step s line
    cmd
    loop s'
```

Modified:
```
loop s logHandle seqRef = do
  eof <- hIsEOF stdin
  if eof then return () else do
    line <- getLine
    seq <- readIORef seqRef
    let (s', cmd) = step s line
    cmd
    hPutStrLn logHandle (eventJson seq "stdin" line)
    modifyIORef' seqRef (+1)
    loop s' logHandle seqRef
```

The `main` function opens the log file, creates the sequence counter, and passes them into the loop. The log file path is `<module>.event-log.json`.

**Imports to add to generated Main.hs:**
```haskell
import Data.IORef (newIORef, readIORef, modifyIORef')
```

**NaN guard:** Add a validation wrapper around any float-returning capture. For v0.3.1, the scope is limited to `wasi.clock.monotonic` and `wasi.random.bytes` — neither returns floats. The NaN guard is a NOOP but the infrastructure exists for v0.4 WASM.

#### [NEW] `emitEventLogPreamble` function in CodegenHs.hs

A helper that emits the `eventJson` function into the generated `Main.hs` preamble:

```haskell
emitEventLogPreamble :: [Text]
emitEventLogPreamble =
  [ "-- Event Log (§10a)"
  , "eventJson :: Int -> String -> String -> String"
  , "eventJson seq kind value ="
  , "  \"{\\\"seq\\\":\" ++ show seq ++ \",\\\"input\\\":{\\\"kind\\\":\\\"\" ++ kind ++ \"\\\",\\\"value\\\":\\\"\" ++ escape value ++ \"\\\"},\\\"result\\\":{}}\""
  , "  where escape = concatMap (\\c -> if c == '\"' then \"\\\\\\\"\" else [c])"
  ]
```

> [!NOTE]
> This is deliberately simple — hand-rolled JSON serialization in the generated code. Adding an `aeson` dependency to the generated package just for event logging would be excessive. The format is a flat JSON object per line (JSONL), wrapped in the envelope by the `main` function on exit.

### A3. Implementation: Replay Subcommand

#### [MODIFY] [Main.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs)

Add `CmdReplay FilePath FilePath` to the `Command` ADT (L70–87). Source file + event log file.

Add `"replay"` to the subparser (L104–131):

```haskell
<> command "replay" (info replayCmd
    (progDesc "v0.3.1: Replay an event log against a compiled program"))
```

#### [NEW] [Replay.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Replay.hs)

New module. ~80 lines. Core logic:

1. Parse the `.event-log.json` file
2. Build the program as normal (reuse `doBuild` infrastructure)
3. Feed each event's `input.value` to the program's stdin via `createProcess` with piped handles
4. Capture stdout and compare against `result.value`
5. Report any divergence with the event sequence number

```haskell
module LLMLL.Replay (runReplay, ReplayResult(..)) where

data ReplayResult = ReplayResult
  { replayTotal      :: Int
  , replayMatched    :: Int
  , replayDiverged   :: [(Int, Text, Text)]  -- (seq, expected, actual)
  }
```

### A4. Acceptance Criteria

- [ ] `llmll run examples/hangman.llmll` produces `hangman.event-log.json` alongside program output
- [ ] `llmll replay examples/hangman.llmll hangman.event-log.json` produces identical output
- [ ] NaN values in captured results are rejected at serialization time (guard present, not triggered by current capture sources)
- [ ] Event log format matches the JSON schema defined in A1

### A5. Dependencies

None new. `Data.IORef` and `System.IO` are already in scope.

---

## Phase B: Leanstral MCP Integration

Resolve `?proof-required :inductive` and `:unknown` holes by translating the proof obligation to a Lean 4 theorem, calling Leanstral via MCP, and caching the result.

### B1. Architecture

```
  ?proof-required :inductive
        │
        ▼
  ┌─────────────────┐
  │ LeanTranslate.hs│  LLMLL TypeWhere AST → Lean 4 theorem text
  └────────┬────────┘
           │ Lean 4 source (Text)
           ▼
  ┌─────────────────┐
  │ MCPClient.hs    │  MCP JSON-RPC call to lean-lsp-mcp
  └────────┬────────┘
           │ Proof term (Text) or error
           ▼
  ┌─────────────────┐
  │ ProofCache.hs   │  Write/read .proof-cache.json sidecar
  └─────────────────┘
```

### B2. Implementation: Lean Translation

#### [NEW] [LeanTranslate.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/LeanTranslate.hs)

Translates LLMLL proof obligations to Lean 4 theorem statements.

**Input:** A `HProofRequired` hole with its context — the contract expression, the function signature, and the surrounding type environment.

**Output:** A Lean 4 `theorem` declaration as `Text`.

**Translation strategy:**

| LLMLL | Lean 4 |
|---|---|
| `int` | `Int` |
| `bool` | `Bool` |
| `string` | `String` |
| `list[t]` | `List t` |
| `Result[t, e]` | `Except e t` (or custom `Result` in Lean) |
| `(pre (> x 0))` | hypothesis `(hx : x > 0)` |
| `(post (= result ...))` | goal `: result = ...` |
| `(for-all [x: int] ...)` | `∀ (x : Int), ...` |

**Example:**

```lisp
;; LLMLL
(def-logic sum-list [xs: list[int]]
  (post (>= result 0))
  (letrec sum-helper [acc: int remaining: list[int]]
    :decreases remaining
    ...))
```

→

```lean
-- Lean 4
theorem sum_list_nonneg : ∀ (xs : List Int), sum_list xs ≥ 0 := by
  sorry -- Leanstral fills this
```

The `sorry` placeholder is what Leanstral replaces with an actual proof tactic sequence.

**Scope limitation:** v0.3.1 supports translating:
- Linear arithmetic predicates (`>`, `>=`, `<`, `<=`, `=`, `+`, `-`)
- List structural induction (`list-length`, `list-head`, `list-tail`)
- Quantified variables from `for-all` bindings

Complex predicates (e.g., involving `map`, `fold`, custom ADTs) produce a `-- UNSUPPORTED: <reason>` comment in the Lean output and the hole remains `?proof-required`.

### B3. Implementation: MCP Client

#### [NEW] [MCPClient.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/MCPClient.hs)

Minimal MCP client. ~120 lines. Communicates with `lean-lsp-mcp` via JSON-RPC over stdio (process spawn) or HTTP.

**MCP call flow:**

1. Spawn `lean-lsp-mcp` as a child process (or connect to HTTP endpoint from config)
2. Send `initialize` → receive `InitializeResult`
3. Send `tools/call` with tool name `"prove"` and the Lean 4 theorem text as argument
4. Receive the proof term (or error)
5. Send `shutdown` + `exit`

```haskell
module LLMLL.MCPClient
  ( MCPConfig(..)
  , MCPResult(..)
  , callLeanstral
  , defaultMCPConfig
  ) where

data MCPConfig = MCPConfig
  { mcpCommand  :: FilePath        -- "lean-lsp-mcp" or custom path
  , mcpArgs     :: [String]        -- extra args
  , mcpTimeout  :: Int             -- seconds (default: 120)
  }

data MCPResult
  = ProofFound Text               -- the proof tactic text
  | ProofTimeout                  -- Leanstral didn't respond in time
  | ProofError Text               -- Leanstral returned an error
  | LeanstralUnavailable Text     -- binary not found / connection refused
```

**Fallback behavior (from roadmap):** If Leanstral is unreachable, the hole becomes `?delegate-pending` — blocks execution, does not fail the build. This is already implemented in `HoleAnalysis.hs` via `HDelegatePending`.

### B4. Implementation: Proof Cache

#### [NEW] [ProofCache.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ProofCache.hs)

Stores verified proof certificates as a sidecar file (`.proof-cache.json`), following the same pattern as `VerifiedCache.hs`.

```json
{
  "version": "0.3.1",
  "proofs": {
    "/statements/3/post": {
      "obligation": "theorem sum_list_nonneg : ...",
      "proof": "by induction xs with ...",
      "prover": "leanstral",
      "verified_at": "2026-04-15T10:30:00Z",
      "lean_version": "4.8.0"
    }
  }
}
```

**Cache invalidation:** A proof is invalidated when the contract expression at the same JSON pointer changes (hash comparison). The cache stores a SHA-256 hash of the original `pre`/`post` expression text.

**Verification without Leanstral:** On subsequent builds, `llmll verify` checks proofs in the cache by:
1. Verifying the obligation hash matches the current contract
2. If match → report `VLProven "leanstral"` (no re-call needed)
3. If mismatch → re-call Leanstral (or mark as `?proof-required` if unavailable)

### B5. Integration Points

#### [MODIFY] [Main.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs)

- `doVerify` (the `llmll verify` handler) is extended: after liquid-fixpoint runs, check for `?proof-required` holes in the AST. For each, check the proof cache. If cache miss → call Leanstral. If proof found → write to cache + report `VLProven "leanstral"`. If unavailable → report `?delegate-pending`.

- Add `--leanstral-cmd` and `--leanstral-timeout` options to `CmdVerify`.

#### [MODIFY] [HoleAnalysis.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/HoleAnalysis.hs)

- Add `holeComplexity :: HoleEntry -> Maybe Text` field extracting the `:simple`/`:inductive`/`:unknown` hint from `HProofRequired`. Currently the reason text is free-form ("non-linear-contract", "complex-decreases"). Normalize these to the three spec-defined tiers:
  - `"non-linear-contract"` → `:unknown` (might be solvable by Leanstral, might not)
  - `"complex-decreases"` → `:inductive` (structural induction — Leanstral's strength)
  - `"manual"` → `:unknown`

#### [MODIFY] [formatHoleReportJson](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/HoleAnalysis.hs#L372-L398) in HoleAnalysis.hs

Add `"complexity"` field to JSON output for `proof-required` holes:

```json
{ "kind": "proof-required", "complexity": "inductive", ... }
```

### B6. Acceptance Criteria

- [ ] A `?proof-required :inductive` hole for a structural list property (e.g., `sum_list >= 0`) is translated to a valid Lean 4 theorem
- [ ] When `lean-lsp-mcp` is available: proof is resolved, certificate stored in `.proof-cache.json`
- [ ] On next `llmll verify`: certificate is read from cache, no Leanstral call made
- [ ] When `lean-lsp-mcp` is unavailable: hole becomes `?delegate-pending`, build does not fail
- [ ] `llmll holes --json` includes `"complexity": "inductive"` for the hole

### B7. Dependencies

#### [MODIFY] [package.yaml](file:///Users/burcsahinoglu/Documents/llmll/compiler/package.yaml)

```yaml
dependencies:
  - process >= 1.6      # already present (for liquid-fixpoint)
  - cryptohash-sha256   # for cache invalidation hashing
```

> [!NOTE]
> `cryptohash-sha256` is a small, pure Haskell package with no C dependencies. Alternative: use `hashable` which is already a transitive dependency — but the hash is not stable across GHC versions.

---

## Phase C: Integration Testing

### C1. Event Log Tests

#### [NEW] `examples/event_log_test/`

A minimal console program that reads two lines of input and echoes them. Run it once to generate the event log, then replay to verify determinism.

```lisp
(def-main
  :mode console
  :init (pair "" (wasi.io.stdout "Enter two words:\n"))
  :step (fn [state: string input: string]
    (pair (string-concat state input)
          (wasi.io.stdout (string-concat "Got: " input "\n"))))
  :done? (fn [state: string] (>= (string-length state) 2)))
```

### C2. Leanstral Tests

#### [NEW] `examples/proof_required_test/`

A program with a `?proof-required :inductive` contract on a list fold. Tests the end-to-end flow when Leanstral is available and when it's mocked as unavailable.

```lisp
(def-logic safe-sum [xs: list[int]]
  (pre (>= (list-length xs) 0))
  (post (>= result 0))
  (letrec helper [acc: int remaining: list[int]]
    :decreases remaining
    (if (= (list-length remaining) 0)
        acc
        (helper (+ acc (abs (list-head remaining)))
                (list-tail remaining)))))
```

### C3. Regression

- All existing 69+ tests must pass
- `stack test` green
- `llmll verify examples/withdraw.llmll` still reports SAFE

---

## File Summary

| Phase | New Files | Modified Files |
|---|---|---|
| A | `Replay.hs` | `CodegenHs.hs`, `Main.hs` |
| B | `LeanTranslate.hs`, `MCPClient.hs`, `ProofCache.hs` | `Main.hs`, `HoleAnalysis.hs`, `package.yaml` |
| C | `examples/event_log_test/`, `examples/proof_required_test/` | — |

---

## Open Questions

> **Q1: Event Log — write during execution or at exit?**
>
> Option (a): append each event as a JSONL line during execution (crash-safe, partial logs useful for debugging).
> Option (b): accumulate in memory, write full JSON file at exit (cleaner format, atomic write).
>
> Leaning toward: (a) — JSONL during execution, with a wrapping `main` that writes the envelope header/footer. Crash-safe is important for debugging agent programs.

> **Q2: Leanstral — MCP over stdio or HTTP?**
>
> `lean-lsp-mcp` can run as a stdio subprocess (MCP standard) or as an HTTP server.
> Stdio is simpler (no port management). HTTP allows a shared Leanstral instance across multiple compiler invocations.
>
> Leaning toward: stdio for v0.3.1 (simplest). HTTP as a `--leanstral-endpoint` flag for later.

> **Q3: Should the proof cache be per-file or per-project?**
>
> Per-file (`.proof-cache.json` next to the source) is simpler and follows the `.verified.json` sidecar pattern.
> Per-project (`~/.llmll/proof-cache/`) allows sharing proofs across files.
>
> Leaning toward: per-file, following the existing `.verified.json` pattern. Consistency trumps optimization.
