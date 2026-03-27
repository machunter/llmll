# `--sketch` Inference Algorithm Architecture

> **Phase:** 2c — for discussion with language team before full implementation guide  
> **Date:** 2026-03-27

---

## Synthesis vs. Checking Mode

The current type checker runs in **synthesis mode** only:

```haskell
inferExpr :: Expr -> TC Type
```

`--sketch` needs a parallel **checking mode** entry point. When the expected type is
known from context, use it to constrain holes instead of synthesising an unknown:

```haskell
checkExpr :: Expr -> Type -> TC ()
checkExpr (EHole name kind) expected = recordHole name kind expected
checkExpr e                 expected = inferExpr e >>= unify expected
```

`checkExpr` on a non-hole is identical to the existing behaviour (infer, then unify).
The only new behaviour is at `EHole`: instead of synthesising `TVar "_hole"`, it
records the expected type directly.

`inferExpr` is **unchanged for non-sketch runs**. `checkExpr` is called only at the
three propagation sites below.

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
         elseE also a hole → both recorded as TVar "_hole"

3. Return unified type
```

---

## Propagation Site 2 — `EMatch` (two-pass)

All arm bodies must return the same type. A hole arm should receive that type.

```
inferExpr (EMatch scrutinee arms):

Pass 1 — synthesise non-hole arm bodies only:
  armTypes ← [ inferExpr body | (pat, body) ← arms, not (isHole body) ]
  T ← foldM unify (head armTypes) (tail armTypes)
        -- type-mismatch errors emitted here as today
        -- all arms are holes → T = TVar "_hole"
        -- unification fails  → T = TConflict           ← NEW sentinel

Pass 2 — check hole arm bodies against T:
  for each (pat, EHole name kind) in arms:
    checkExpr (EHole name kind) T
    -- records T in sketch output; "<conflict>" if T = TConflict
```

`TConflict` is an internal sentinel used only during sketch inference. It never
appears in `llmll check` output and is not exposed in the surface language.

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
