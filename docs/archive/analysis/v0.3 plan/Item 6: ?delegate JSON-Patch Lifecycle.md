# Item 6: `?delegate` JSON-Patch Lifecycle

## Goal

Deliver the v0.3 headline agent-coordination feature: an agent checks out a hole, submits an RFC 6902 JSON-Patch against the program's JSON-AST, and the compiler applies the patch, re-verifies, and reports results targeting the patch's own pointers.

Item 4 (Async codegen swap) is absorbed as Phase 1.

---

## Phase 1 — Async Codegen Swap (absorbs Item 4)

The opening commit. Mechanically trivial, untestable in isolation, but required before `?delegate-async` can produce real `Async` values.

### Changes

#### [MODIFY] [CodegenHs.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs)

| Line | Current | Target |
|------|---------|--------|
| 640 | `toHsType (TPromise t) = "(IO " <> ...` | `"(Async " <> ...)` |
| 480 | `emitExpr (EAwait e) = emitExpr e` (no-op) | Exception-safe `Result`-wrapped `Async.wait` (see §3.2 below) |
| `runtimePreamble` (~L182) | — | add `import Control.Concurrent.Async qualified as Async` + `import Control.Exception (try, SomeException)` to the **generated** Lib.hs preamble |
| `emitPackageYaml` | — | add `async >= 2.2` to the **generated** package.yaml dependencies (alongside QuickCheck, containers, etc.) |

> [!IMPORTANT]
> The `async` dependency belongs in the **generated** Haskell project, not the compiler's own `package.yaml`. The compiler never imports `Control.Concurrent.Async` — it only emits code that references it. Same pattern as `QuickCheck` in the generated test harness.

#### [MODIFY] [TypeCheck.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs) (Language Team R2 §2)

The type checker must agree with codegen on `EAwait`'s return type. Currently ([L662–668](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L662-L668)):

```haskell
inferExpr (EAwait expr) = do
  innerType <- inferExpr expr
  case innerType of
    TPromise t -> pure t          -- ← returns bare t (WRONG after §3.2)
    other -> ...
```

Must become:

```haskell
inferExpr (EAwait expr) = do
  innerType <- inferExpr expr
  case innerType of
    TPromise t -> pure (TResult t TDelegationError)  -- §3.2: exception-safe wrapping
    other -> ...
```

Without this, any program that `await`s a delegate and pattern-matches the result (`match result (Success v) ... (Error e) ...`) gets a false type-mismatch: the type checker infers bare `t` but codegen produces `Result[t, DelegationError]`.

> [!NOTE]
> `inferHole (HDelegateAsync spec)` at [L703](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L703) correctly returns `TPromise t` — no change needed there. The `Result` wrapping only occurs at the `await` point, which is where the exception can arise. An un-`await`ed `Promise[t]` remains `Promise[t]`.

#### `EAwait` Codegen — Exception-Safe Result Wrapping (§3.2)

The generated `await` must **not** produce a bare `Async.wait` call. `Async.wait` re-throws child thread exceptions, which would crash the calling logic function — violating the LLMLL principle that logic functions cannot crash from IO.

The generated code must wrap in exception handling and return `Result[t, DelegationError]`:

```haskell
-- emitExpr (EAwait e) generates:
(do result <- try (Async.wait <inner>)
    case result of
      Left (e :: SomeException) -> pure (Left (AgentCrash ()))
      Right v                   -> pure (Right v))
```

This ensures `await` always returns `Result[t, DelegationError]` as the spec (§11.2) requires for async delegation. The type of `EAwait e` is `Result[t, DelegationError]`, not bare `t`.

### Acceptance

- `stack build` succeeds with no new warnings
- `stack test` — 69/69 pass (no code uses Promise/Async yet, so no behavior change)
- Inspect generated `Lib.hs` for a program with `Promise[t]`: confirm `Async t` type and exception-safe `await` wrapper appear in output

---

## Phase 2 — `llmll checkout <file> <pointer>`

An agent calls `llmll checkout program.ast.json /statements/2/body` to lock a hole. The compiler validates the pointer resolves to an actual hole node in the JSON-AST, records the lock, and returns a checkout token.

### Design Decisions (from professor + language team review)

- **Top-level CLI command.** `llmll checkout` and `llmll patch` are both mutations — they get their own verbs, separate from `llmll holes` (inspection).
- **Pointer resolution on JSON `Value` (Strategy 1).** Load the `.ast.json`, resolve the RFC 6901 pointer on the raw `Data.Aeson.Value` tree, check if the node has `"kind": "hole-*"`. ~30 lines, reuses in Phase 3.
- **S-expression sources rejected.** `llmll checkout program.llmll` → error: `"checkout requires .ast.json input; run 'llmll build --emit json-ast' first"`.
- **Lock TTL with auto-expiry.** Default 1 hour. Stale locks auto-expired on any `checkoutHole` or `applyPatch` call.
- **Per-file lock scope.** `.llmll-lock.json` alongside the source.
- **Lock release command.** `llmll checkout --release <file> <token>` for explicit abandonment (§2.4).
- **Lock status query.** `llmll checkout --status <file> <token>` returns remaining TTL (§4.4).
- **Pointer must terminate at a hole node.** If the agent provides a pointer to a *containing* node (e.g., `/statements/2` when the hole is at `/statements/2/body`), return a hint: `"did you mean /statements/2/body?"` (§4.2).

### Changes

#### [NEW] [JsonPointer.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/JsonPointer.hs) (§2.1)

Dedicated ~60-line module for RFC 6901 operations on `Data.Aeson.Value`. Cleanly separated from domain logic. Both `Checkout.hs` and `PatchApply.hs` import this — no circular dependency.

```haskell
module LLMLL.JsonPointer
  ( resolvePointer
  , setAtPointer
  , removeAtPointer
  , parsePointer
  , isHoleNode
  , findDescendantHoles
  ) where

-- | Parse an RFC 6901 pointer string into path segments.
-- "/statements/2/body" → ["statements", "2", "body"]
parsePointer :: Text -> [Text]

-- | Resolve a pointer against a JSON Value.
-- Returns Nothing if any segment fails to resolve.
resolvePointer :: Text -> Value -> Maybe Value

-- | Set a value at a pointer location. Returns Left on invalid path.
setAtPointer :: Text -> Value -> Value -> Either Text Value

-- | Remove the node at a pointer location.
removeAtPointer :: Text -> Value -> Either Text Value

-- | Check if a JSON node represents a hole (kind starts with "hole-").
isHoleNode :: Value -> Bool

-- | Find all hole-node pointers that are descendants of the given pointer.
-- Used by checkout to provide hints when pointer doesn't target a hole directly.
findDescendantHoles :: Text -> Value -> [Text]
```

#### [NEW] [Checkout.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Checkout.hs)

```haskell
import LLMLL.JsonPointer (resolvePointer, isHoleNode, findDescendantHoles)

data CheckoutToken = CheckoutToken
  { ctPointer   :: Text
  , ctHoleKind  :: Text
  , ctExpected  :: Maybe Text
  , ctTimestamp :: UTCTime
  , ctToken     :: Text              -- 32-char hex random bearer token
  , ctTTL       :: NominalDiffTime   -- default: 3600s
  } deriving (Show, Eq, Generic)

data CheckoutLock = CheckoutLock
  { lockFile    :: FilePath
  , lockTokens  :: [CheckoutToken]
  } deriving (Show, Eq, Generic)

-- | Validate pointer targets a hole node, create lock, return token.
-- Auto-expires stale locks. Uses advisory file lock (flock) for atomicity.
checkoutHole :: FilePath -> Value -> Text -> IO (Either Diagnostic CheckoutToken)

-- | Release a lock explicitly. Agent calls this to abandon a checkout.
releaseHole :: FilePath -> Text -> IO (Either Diagnostic ())

-- | Query remaining TTL for a token.
checkoutStatus :: FilePath -> Text -> IO (Either Diagnostic NominalDiffTime)

-- | Load/save lock file (.llmll-lock.json).
loadLock  :: FilePath -> IO (Maybe CheckoutLock)
saveLock  :: FilePath -> CheckoutLock -> IO ()

-- | Remove expired tokens from a lock.
expireStale :: UTCTime -> CheckoutLock -> CheckoutLock
```

`checkoutHole` validation logic:

1. Resolve pointer against JSON `Value`
2. If node is not a hole → check `findDescendantHoles` for hint: `"did you mean /statements/2/body?"`
3. If node is a hole → check lock file for active (non-expired) lock on this pointer
4. If locked → reject: `"hole at <pointer> is already checked out"`
5. If unlocked → generate token, append to lock file under advisory `flock`, return token

#### [MODIFY] [Main.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs)

- Add `CmdCheckout FilePath Text` and `CmdCheckoutRelease FilePath Text` and `CmdCheckoutStatus FilePath Text` to `Command` ADT
- Add top-level `"checkout"` subcommand with `--release` and `--status` flags
- Guard: reject non-`.ast.json` / non-`.json` file extensions

#### [MODIFY] [package.yaml](file:///Users/burcsahinoglu/Documents/llmll/compiler/package.yaml)

- Add `LLMLL.JsonPointer` and `LLMLL.Checkout` to `exposed-modules`
- Add `time >= 1.12` and `filelock >= 0.1` dependencies

### Acceptance

- `llmll checkout program.ast.json /statements/0/body` → token JSON + `.llmll-lock.json`
- Non-hole pointer → error with hint: `"did you mean /statements/0/body?"`
- Already-locked pointer → error: `"hole already checked out"`
- Expired lock → auto-expired, new checkout succeeds
- `.llmll` source → error: `"checkout requires .ast.json input"`
- `llmll checkout --release program.ast.json <token>` → clears lock entry
- `llmll checkout --status program.ast.json <token>` → remaining TTL

---

## Phase 3 — Patch Apply + Re-Verify

The core feature. Agent submits an RFC 6902 JSON-Patch in an LLMLL envelope. Compiler applies, re-parses, re-typechecks, reports.

### Design Decisions (from professor + language team review)

- **LLMLL envelope format** with embedded token (self-contained for agents).
- **`parseJSONASTValue :: Value -> Either [Diagnostic] [Statement]`** exposed in `ParserJSON.hs` (§3.3). Multi-diagnostic return so agents can fix all structural errors in one round-trip.
- **4 RFC 6902 ops:** `replace`, `add`, `remove`, `test`. Explicit rejection of `move`/`copy` with clear error (§3.1).
- **Token scope containment** (§2.2): every patch op's path must be a descendant-or-self of the checkout pointer. Prevents lateral hole theft.
- **File atomicity** (§2.3): advisory `flock` held for the entire read→verify→write cycle.
- **Patches restricted to hole-filling in v0.3** (§4.1): the checked-out node must be a hole. General AST mutation is v0.4.
- **`add` restricted to within checked-out subtree** (§4.3): no statement-level array additions via patch.
- **Serve.hs routes** with auth parity (§3.5): `POST /checkout` and `POST /patch` governed by the same `withAuth` middleware as existing routes. File paths must be absolute.

### Changes

#### [MODIFY] [ParserJSON.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ParserJSON.hs)

Refactor: extract `parseJSONASTValue :: Value -> Either [Diagnostic] [Statement]`. The existing `parseJSONAST` becomes a thin wrapper: decode `ByteString` → `Value`, delegate to `parseJSONASTValue`, collapse `[Diagnostic]` to the first one for backward compat.

#### [NEW] [PatchApply.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/PatchApply.hs)

```haskell
import LLMLL.JsonPointer (resolvePointer, setAtPointer, removeAtPointer)
import LLMLL.Checkout (loadLock, saveLock, expireStale, CheckoutToken(..))
import LLMLL.ParserJSON (parseJSONASTValue)

data PatchRequest = PatchRequest
  { prToken      :: Text
  , prPatch      :: [PatchOp]
  } deriving (Show, Eq, Generic)

data PatchOp
  = PatchReplace Text Value        -- "replace" pointer value
  | PatchAdd     Text Value        -- "add" pointer value
  | PatchRemove  Text              -- "remove" pointer
  | PatchTest    Text Value        -- "test" pointer expected-value
  deriving (Show, Eq, Generic)

data PatchResult
  = PatchSuccess [Statement]
  | PatchTypeError DiagnosticReport
  | PatchApplyError Text           -- incl. test failure, move/copy rejection
  | PatchAuthError Text            -- invalid/expired/scope-violation
  deriving (Show)

-- | Apply a single patch op to a JSON Value.
applyOp :: PatchOp -> Value -> Either Text Value

-- | Apply all ops in sequence; short-circuit on first failure.
applyOps :: [PatchOp] -> Value -> Either Text Value

-- | Full lifecycle:
-- 1. Validate token against lock file (auto-expire stale)
-- 2. Scope check: all op paths are descendant-or-self of checkout pointer (§2.2)
-- 3. Load source .ast.json as Value
-- 4. Apply RFC 6902 ops (replace/add/remove/test)
-- 5. Re-parse Value → [Statement] via parseJSONASTValue
-- 6. Re-typecheck
-- 7. On success: write updated .ast.json under advisory flock, clear lock entry
applyPatch :: FilePath -> PatchRequest -> IO PatchResult

-- | Scope containment check (§2.2, Safety Invariant §5.4).
-- Returns Left with error if any op path is outside the checkout subtree.
-- NOTE: test ops are also scope-checked in v0.3. Cross-scope test (e.g.,
-- asserting a sibling function's signature) is deferred to v0.4.
-- Agents can read the JSON-AST independently to assert pre-conditions
-- outside the checkout subtree.
validateScope :: Text -> [PatchOp] -> Either Text ()
validateScope checkoutPtr ops = ...
  -- ∀ op ∈ ops: op.path is prefix of checkoutPtr ∨ checkoutPtr is prefix of op.path

-- | Reject unsupported RFC 6902 ops (§3.1).
-- If op == "move" or "copy", return clear error with workaround.
parsePatchOp :: Value -> Either Text PatchOp
```

#### [MODIFY] [Main.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs)

- Add `CmdPatch FilePath FilePath` to `Command`
- Add top-level `"patch"` subcommand: `llmll patch <source.ast.json> <patch-request.json>`

#### [MODIFY] [Serve.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Serve.hs)

Add routes governed by existing `withAuth` middleware:

- `POST /checkout` — body: `{ "file": "<absolute-path>", "pointer": "..." }` → token JSON
- `POST /checkout/release` — body: `{ "file": "<absolute-path>", "token": "..." }` → OK
- `POST /patch` — body: `PatchRequest` JSON with `"file"` field added → result JSON

File paths must be **absolute** (§3.5) — resolves working directory ambiguity.

#### [MODIFY] [package.yaml](file:///Users/burcsahinoglu/Documents/llmll/compiler/package.yaml)

- Add `LLMLL.PatchApply` to `exposed-modules`

### LLMLL Patch Envelope Format

```json
{
  "token": "a1b2c3d4...",
  "patch": [
    { "op": "test",    "path": "/statements/2/body", "value": { "kind": "hole-delegate", ... } },
    { "op": "replace", "path": "/statements/2/body", "value": { "kind": "lit-int", "value": 42 } }
  ]
}
```

Unsupported ops produce a clear error:

```json
{ "op": "move", ... }
→ "RFC 6902 'move' op is not supported in v0.3; use 'remove' + 'add' instead"
```

### Acceptance

- Valid patch with scope-contained ops → `PatchSuccess`, updated `.ast.json`, lock cleared
- Type-incorrect patch → `PatchTypeError` with diagnostic report
- Stale patch (`test` fails) → `PatchApplyError "test failed at /statements/2/body"`
- Scope violation (op targets different hole) → `PatchAuthError "op path /statements/0/body is outside checkout scope /statements/2/body"`
- `move`/`copy` op → `PatchApplyError "RFC 6902 'move' op not supported in v0.3"`
- Concurrent patches → second writer gets `PatchApplyError` due to `flock` contention or stale-read detection
- HTTP `POST /checkout` and `POST /patch` work identically to CLI

---

## Phase 4 — Diagnostics Targeting Patch Nodes

When a patch fails type-checking, error pointers reference the patch's own operations.

### Changes

#### [MODIFY] [Diagnostic.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Diagnostic.hs)

Refined signature (§3.4):

```haskell
data PatchOpInfo = PatchOpInfo
  { poiIndex :: Int
  , poiPath  :: Text   -- RFC 6901 pointer targeted by this op
  , poiKind  :: Text   -- "replace" | "add" | "remove"
  } deriving (Show, Eq, Generic)

-- | Rebase diagnostic pointers relative to patch operations.
-- Only mutation ops (replace/add/remove) can introduce type errors; test cannot.
-- Algorithm:
--   for each op in ops (reverse precedence):
--     if diag.pointer starts with op.path:
--       suffix = diag.pointer - op.path
--       diag.pointer = "patch-op/" <> show op.index <> suffix
--       return diag
--   return diag unchanged
rebaseToPatch :: [PatchOpInfo] -> Diagnostic -> Diagnostic
```

#### [MODIFY] [PatchApply.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/PatchApply.hs)

After re-typecheck, build `[PatchOpInfo]` from the patch ops and pipe diagnostics through `rebaseToPatch`.

### Acceptance

- Multi-op patch, op #2 introduces type error → `patch-op/2/body`
- Single-op patch error → `patch-op/0/...`
- `test` op (non-mutation) never appears in rebased pointers

---

## Safety Invariants (from Language Team §5)

These properties **must hold** and will be tested:

### §5.1 Progress (Patch Application)
>
> If `applyOps ops ast = Right ast'`, then `parseJSONASTValue ast'` must return `Right stmts`.

A successfully applied patch always produces structurally valid JSON-AST.

### §5.2 Preservation (Type Safety Through Patch)
>
> If `applyPatch` returns `PatchSuccess stmts`, then `typeCheck emptyEnv stmts` returns `reportSuccess = True`.

`PatchSuccess` is only reachable after a passing `typeCheck`. No code path skips re-verification.

### §5.3 Lock Exclusivity
>
> For all time T, file F, pointer P: at most one active (non-expired) token exists.

Enforced by `checkoutHole` under advisory `flock`.

### §5.4 Token Scope Containment
>
> `applyPatch` with token for pointer P must reject any `PatchOp` whose path is not descendant-or-self of P.

Enforced by `validateScope` before any ops are applied.

---

## Resolved Design Questions

| Question | Decision | Rationale |
|----------|----------|-----------|
| CLI shape | Both `checkout` and `patch` are **top-level** subcommands | Mutations get own verbs |
| Lock scope | **Per-file** `.llmll-lock.json` | No project root convention yet |
| Patch format | **LLMLL envelope** with embedded token | Agent-first; self-contained JSON |
| Pointer resolution | **On JSON `Value`** (Strategy 1) | Reuses in Phase 3; 30 lines |
| S-expression sources | **Reject** with clear message | Agents work in JSON-AST |
| Lock expiry | **1-hour TTL**, auto-expired | Prevents permanent blocking |
| Lock release | `llmll checkout --release` + `POST /checkout/release` | Don't force wait for TTL |
| Lock status | `llmll checkout --status` | Agent can check before expensive work |
| `parseJSONASTValue` | `Either [Diagnostic] [Statement]` | Multi-error for fewer agent round-trips |
| RFC 6902 `test` op | **Included** | Guards against stale patches |
| RFC 6902 `move`/`copy` | **Rejected** with clear error | Defer to v0.4 |
| `EAwait` semantics | Exception-safe → `Result[t, DelegationError]` | Spec §11.2 safety |
| Patch scope | Hole-filling only in v0.3 | General AST mutation is v0.4 |
| `add` on arrays | Restricted to checked-out subtree | No statement-level adds via patch |
| File atomicity | Advisory `flock` for read→verify→write | Prevents concurrent patch races |
| Serve.hs routes | `POST /checkout`, `/checkout/release`, `/patch` | Auth parity; absolute paths |

---

## Verification Plan

### Automated Tests

- **Phase 1:** No new tests (existing 69 pass)
- **Phase 2:** `describe "JsonPointer"` — resolve, set, remove on nested JSON; `describe "Checkout"` — successful checkout, non-hole rejection with hint, double-lock, expired auto-cleanup, `.llmll` rejection, release, status
- **Phase 3:** `describe "PatchApply"` — successful replace, type-error, scope violation, `test` pass/fail, `move`/`copy` rejection, `parseJSONASTValue` multi-error, flock atomicity
- **Phase 4:** `describe "PatchDiagnostics"` — single-op and multi-op rebasing, `test` op excluded

### Integration Test

Two-agent demo fixture:

1. `examples/delegate_demo/program.ast.json` — program with `?delegate` hole
2. `examples/delegate_demo/patch-request.json` — `test` + `replace`
3. Script: `llmll checkout ... && llmll patch ...` → success

### Regression

- `stack test` passes at each phase boundary
- All existing `llmll check` examples pass

---

## File Change Summary

| Phase | New Files | Modified Files |
|-------|-----------|----------------|
| 1 | — | `CodegenHs.hs`, `TypeCheck.hs`, `CHANGELOG.md` |
| 2 | `JsonPointer.hs`, `Checkout.hs` | `Main.hs`, `package.yaml` |
| 3 | `PatchApply.hs` | `Main.hs`, `ParserJSON.hs`, `Serve.hs`, `package.yaml` |
| 4 | — | `Diagnostic.hs`, `PatchApply.hs` |

---

## Language Team Spec Artifacts — Status

The language team is delivering D1–D3 on branch `feature/delegate-lifecycle-spec`. Current status:

| # | Artifact | Status | Compiler Team Dependency |
|---|----------|--------|--------------------------|
| D1 | `LLMLL.md §11.2`: `await` returns `Result[t, DelegationError]` | ✅ **Landed** | Phase 1 `TypeCheck.hs` + `CodegenHs.hs` must match spec |
| D2 | `LLMLL.md §11.2`: checkout/patch workflow | ✅ **Landed** | Phase 2/3 CLI + Serve.hs must match spec |
| D3 | `llmll-ast.schema.json`: `PatchEnvelope`, `PatchOp`, `CheckoutToken`, `ExprAwait` desc | 🔄 **In progress** | Phase 3 `PatchApply.hs` must conform to schema |
| D4 | Formal inference rules | ⏳ Deferred | — |
| D5 | Z3 encoding of Lock Exclusivity (§5.3) | ⏳ Deferred | — |

### Implementation Contracts (from D3 schema)

Our implementation **must** conform to these schema definitions:

**`CheckoutToken` response** (returned by `doCheckout` and `POST /checkout`):

```json
{ "pointer": "/statements/2/body", "hole_kind": "delegate", "token": "a1b2c3d4...", "ttl": 3600 }
```

Required fields: `pointer`, `token`, `ttl`. Optional: `hole_kind`.

**`PatchOp` validation** (in `parsePatchOp`):

- `op` must be one of `["replace", "add", "remove", "test"]`
- `value` is **required** for `replace`, `add`, `test`; must be **absent** for `remove`
- Any other `op` (e.g., `"move"`, `"copy"`) → clear rejection error

**Schema version bump:** Deferred. The schema version (`0.2.0`) gates the *parser*, not the type checker. Bump to `0.3.0` coordinated with Phase 3's `ParserJSON.hs` changes if new AST node kinds are added.

### Phase 1 Documentation Additions

Phase 1 must also update:

- **[CHANGELOG.md](file:///Users/burcsahinoglu/Documents/llmll/CHANGELOG.md)** — add v0.3 breaking change entry: `"await now returns Result[t, DelegationError] instead of bare t. Programs that use await must pattern-match on Success/Error."`
