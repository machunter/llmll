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
