# `--sketch` Inference Algorithm Architecture

> **Phase:** 2c  
> **Date:** 2026-03-27  
> **Decision (Professor, 2026-03-27):** `inferredType` is a pure type field. `null` for all indeterminate cases. Conflicts go in `errors` only.

---

## `HoleStatus` ADT and Output Contract

```haskell
data HoleStatus
  = HoleTyped    Type        -- constraint resolved from context
  | HoleAmbiguous Type Type  -- conflicting constraints from two peers
  | HoleUnknown              -- no constraint reached this hole

data SketchHole = SketchHole
  { shName    :: Name       -- "?my_hole"
  , shStatus  :: HoleStatus
  , shPointer :: Text       -- RFC 6901 JSON Pointer
  }
```

**Output contract:**

| `HoleStatus` | `inferredType` in JSON | `errors` entry? |
|---|---|---|
| `HoleTyped t` | valid LLMLL type string | No |
| `HoleUnknown` | `null` | No |
| `HoleAmbiguous t1 t2` | `null` | Yes — `"kind": "ambiguous-hole"` with both types |

`inferredType` is **never** a diagnostic string. Conflicts surface in `errors` only.

---

## Synthesis vs. Checking Mode

The current type checker runs in **synthesis mode** only:

```haskell
inferExpr :: Expr -> TC Type
```

`--sketch` needs a parallel **checking mode** entry point:

```haskell
checkExpr :: Expr -> Type -> TC ()
checkExpr (EHole name kind) expected = recordHole name kind (HoleTyped expected)
checkExpr e                 expected = inferExpr e >>= unify expected
```

For unconstrained holes (no peer provides a type), record `HoleUnknown`:
```haskell
recordHoleUnknown name kind = recordHole name kind HoleUnknown
```

`inferExpr` is **unchanged for non-sketch runs**. Both functions are no-ops when
`tcSketch = False`.

---

## Propagation Site 1 — `EIf`

All arms must return the same type, so a known arm constrains a hole arm.

```
inferExpr (EIf cond thenE elseE):

1. infer cond → assert bool (unchanged)

2. Attempt inferExpr thenE → thenT
     Success:
       if elseE is EHole → checkExpr elseE thenT       ← NEW
       else              → inferExpr elseE → elseT
                           unify thenT elseT            ← unchanged
     thenE is itself a hole (no inferred type from context):
       Attempt inferExpr elseE → elseT
         Success → checkExpr thenE elseT               ← NEW
         elseE also a hole → recordHoleUnknown for both  ← HoleUnknown

3. Return unified type
```

---

## Propagation Site 2 — `EMatch` (two-pass)

All arm bodies must return the same type. A hole arm should receive that type.

```
inferExpr (EMatch scrutinee arms):

Pass 1 — synthesise non-hole arm bodies only:
  armTypes ← [ (inferExpr body, body) | (pat, body) ← arms, not (isHole body) ]
  unification result:
    Success → T (all arm types agree)
    Failure → record (t1, t2) for Pass 2           ← HoleAmbiguous, not a sentinel type
    All arms are holes → T = Nothing

Pass 2 — record hole arm statuses:
  Unification succeeded (T = Just t):
    for each hole arm → recordHole name kind (HoleTyped t)
  Unification failed (t1, t2 conflict):
    for each hole arm → recordHole name kind (HoleAmbiguous t1 t2)
                     → also emit "ambiguous-hole" error entry
  No non-hole arms (T = Nothing):
    for each hole arm → recordHoleUnknown name kind
```

The conflict is carried in `HoleAmbiguous` — no `TConflict` type sentinel needed.

---

## Propagation Site 3 — `EApp` arguments (already handled)

Function signatures already provide the expected type for each argument position
via `unify`. Convert the argument loop to use `checkExpr` to get `recordHole`
called automatically for hole arguments — no logic change, same outcome for
non-hole arguments:

```haskell
-- before
zipWithM_ (\e t -> inferExpr e >>= unify t) args paramTypes

-- after
zipWithM_ (\e t -> checkExpr e t) args paramTypes
```

---

## Complete-set summary

| Site | How constraint arrives | Change needed |
|------|----------------------|---------------|
| `EIf` then/else | sibling branch | ✏️ try-and-fallback |
| `EMatch` arms | sibling arms unified | ✏️ two-pass loop |
| `EApp` arguments | function signature | ✏️ 1-line swap to `checkExpr` |
| `ELet` binding RHS | annotation (if typed) | ✅ unchanged |
| `fn` / lambda body | outer checking context | ✅ unchanged |

---

## D3 — Error Reporting on Partial Programs (`holeSensitive`)

> **Decision (Professor + language team, 2026-03-27):** Option C.  
> Emit all detectable errors. Annotate each with `"holeSensitive": bool` to let agents triage.

### Background

`--sketch` runs on programs with holes. A type error in a partial program falls into one of three categories:

| Category | Definition |
|----------|------------|
| **Certain** | Error holds regardless of how any hole resolves — no hole in the causal chain |
| **Conditional** | Error would disappear if a `HoleUnknown` resolved to the right type |
| **Spurious** | False positive caused by `HoleUnknown` propagating into a type position |

Options A (emit certain only) and C (emit all + flag) have the same detection cost — you compute both causal sets either way. Option C is chosen because agents benefit from full information with mechanical triage metadata, rather than silence that forces multiple round-trips.

### Output field

```json
{ "kind": "type-mismatch", "expected": "string", "got": "int",
  "pointer": "/statements/2/body/args/0", "holeSensitive": false }

{ "kind": "type-mismatch", "expected": "Command", "got": "?handler",
  "pointer": "/statements/4/body/else",   "holeSensitive": true  }
```

`holeSensitive: true` means: *this error may disappear when holes are filled.* Agents should fill holes first, re-query, then address only persistent `holeSensitive: false` errors.

### Implementation — `isHoleVar` in `unify`

An error is `holeSensitive: true` if and only if at least one type in the failing `unify` call is a hole type variable at the moment of emission:

```haskell
isHoleSensitive :: Type -> Type -> Bool
isHoleSensitive expected actual =
  isHoleVar expected || isHoleVar actual

isHoleVar :: Type -> Bool
isHoleVar (TVar n) = "?" `T.isPrefixOf` n
isHoleVar _        = False
```

Add `holeSensitive` to the error emitted at the `tcError` site in `unify`. One addition — no structural change to the error-reporting path.

### Canonical hole type variable — required invariant

`isHoleVar` works only if `inferExpr (EHole ...)` returns a `TVar` with a `?`-prefixed name when the hole appears in synthesis position (no checking context):

```haskell
inferExpr (EHole name kind) = do
  when tcSketch $ recordHoleUnknown name kind
  pure (TVar ("?" <> name))   -- ← must use this form; plain TVar "_hole" breaks isHoleVar
```

**This is a required invariant.** A hole returning `TVar "_hole"` or any non-`?`-prefixed variable will silently misclassify downstream errors as `holeSensitive: false`.

### D3 acceptance criteria

- A `unify` failure between two concrete types (no holes) emits `holeSensitive: false`.
- A `unify` failure where one side is `TVar "?foo"` emits `holeSensitive: true`.
- `inferExpr (EHole name _)` returns `TVar ("?" <> name)` in synthesis mode.
- Agents re-querying after hole resolution see `holeSensitive: false` errors persist and `holeSensitive: true` errors resolve or change.

---

## D4 — JSON Pointer Tracking

> **Decision (Professor, 2026-03-28):** Option C — fold `tcPointerStack :: [Text]` into `TCState`.  
> ReaderT layer (Option A) rejected: `TC` is `type TC a = State TCState a` — a 2-layer transformer stack would require `lift` at ~40 call sites. Explicit argument (Option B) rejected: high risk of stale pointer at manual call sites.

### Why Option C

`withSegment` is structurally identical to the existing `withEnv` pattern. Any compiler team member who understands `withEnv` understands `withSegment` immediately. Zero monad stack change. Zero lift surface. The stack is empty when `tcSketch = False` — no overhead on the normal `llmll check` path.

### `TCState` addition

```haskell
data TCState = TCState
  { tcEnv          :: TypeEnv
  , tcAliasMap     :: Map Name Type
  , tcCurrentFn    :: Maybe Name
  , tcIsLetrec     :: Bool
  , tcSketch       :: Bool
  , tcHoles        :: [SketchHole]
  , tcPointerStack :: [Text]         -- NEW: empty in check mode
  }
```

### `withSegment` and `currentPointer`

```haskell
withSegment :: Text -> TC a -> TC a
withSegment seg action = do
  modify $ \s -> s { tcPointerStack = tcPointerStack s ++ [seg] }
  result <- action
  modify $ \s -> s { tcPointerStack = init (tcPointerStack s) }
  pure result

currentPointer :: TC Text
currentPointer = do
  stack <- gets tcPointerStack
  pure $ "/" <> T.intercalate "/" stack
```

`recordHole` reads `currentPointer` internally — callers pass nothing extra.

### Call-site wrapping

Wrap each named descent in `inferExpr` and `checkStatement` with `withSegment`. Segment names must match JSON-AST field names to produce valid RFC 6901 pointers:

```haskell
-- EIf
inferExpr (EIf cond thenE elseE) = do
  inferExpr cond
  thenT <- withSegment "then" $ inferExpr thenE
  elseT <- withSegment "else" $ inferExpr elseE
  ...

-- EMatch arm i
forM_ (zip [0..] arms) $ \(i, (pat, body)) ->
  withSegment ("arms/" <> T.pack (show i) <> "/body") $ inferExpr body

-- EApp arg i
forM_ (zip [0..] args) $ \(i, arg) ->
  withSegment ("args/" <> T.pack (show i)) $ checkExpr arg paramType
```

The top-level descent into each `Statement` seeds the stack with `"statements/N"` before any nested `withSegment` calls.

### D4 acceptance criteria

- A hole at `/statements/2/body/else` is reported with `"pointer": "/statements/2/body/else"`.
- A hole at `/statements/0/body/arms/1/body` is reported with the correct nested path.
- `tcPointerStack` is `[]` at the start of every top-level check in non-sketch mode.
- No existing `llmll check` test is affected — pointer stack is inert when `tcSketch = False`.
