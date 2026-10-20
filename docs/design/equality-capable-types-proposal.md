---
title: CTOR-FN-FIELD-1 — equality-capable types
status: Rev 0, SETTLED 2026-10-20 (user-approved)
rows: CTOR-FN-FIELD-1 (G3)
review: none (no professor pass)
---

# CTOR-FN-FIELD-1: equality-capable types

**Status: Rev 0, SETTLED 2026-10-20.** The language-team wrote this decision on 2026-10-20, together with the FFI-CONV-1 split, which belongs to [`ffi-tier1-proposal.md`](ffi-tier1-proposal.md) and is not repeated here. The user approved it the same day. No professor pass was made.

## Restatement

A type that holds a function or a `Command` passes `check` and fails `build`. Every generated sum type derives `(Eq, Show)`, and GHC cannot derive either class for a function type or for `IO ()`. The same failure occurs with no user type: `=` on two functions, or on two `Command` values, passes `check` and fails `build`. This record settles which types have equality, what codegen derives, and what `check` refuses.

## Context located

- `compiler/src/LLMLL/CodegenHs.hs` `emitTypeDef`: every sum type derives `(Eq, Show)`.
- `compiler/src/LLMLL/CodegenHs.hs` `emitStmtRenamed`: after a constructor rename, a type derives `Eq` and gets `emitShowInstance`.
- `compiler/src/LLMLL/CodegenHs.hs` `emitOp`: `=`, `!=` and `<=>` are emitted as Haskell `==`. The runtime declares `list_contains :: Eq a =>` and `map_get :: (Ord k, Show k) =>`.
- `compiler/src/LLMLL/TypeCheck.hs` `checkJsonNoEq` and `jsonEqConsumers` (JSON-NOEQ): the precedent. `=`, `!=` and `list-contains` are already refused at `check`, with kind `json-equality-denied`, when the substituted type mentions `Json`.
- `compiler/src/LLMLL/TypeCheck.hs` `isAdmissibleConstructor`: decides whether a body that builds a datatype value keeps its body VC.
- `compiler/src/LLMLL/PBT.hs`: `llmll test` evaluates properties in the compiler's own interpreter. It does not use generated `Eq` or `Show` instances.
- `compiler/src/LLMLL/Syntax.hs` `STypeDef`: a user type has a name and a body, and no type parameters.
- `LLMLL.md` does not state the domain of `=`. That is a spec gap, which this record closes on ship.

### Witnesses (llmll 0.30.8, GHC 9.6.6)

Each program passes `check`, and `build` fails:

| Program | `build` error |
|---|---|
| `(type Ops (\| Ops list[(fn [int] -> int)]))` | `No instance for ‘Eq (Integer -> Integer)’`, and the same for `Show`, at `deriving (Eq, Show)` |
| `(def-shell same [f: (fn [int] -> int) g: (fn [int] -> int)] -> bool (= f g))` | `No instance for ‘Eq (Integer -> Integer)’` |
| `(def-shell same [a: Command b: Command] -> bool (= a b))` | `No instance for ‘Eq (IO ())’` |

The second and third witnesses involve no user type, so the defect is wider than the row's first title.

## Design proposal

### The rule

Define **equality-capable** on types:

- **Not capable:** a function type, `Command`, `Promise[T]`, and `Json`. `Json` keeps its JSON-NOEQ rule unchanged.
- **Capable:** every other builtin type whose components are capable. For example, `list[T]` is capable when `T` is.
- **A user type** is capable when every constructor field is capable. Compute this as a greatest fixpoint over the alias map, so a recursive type with no incapable component stays capable.

### Codegen

- A capable user type derives `(Eq, Show)`, as today.
- An incapable user type derives nothing.
- After a rename (`emitStmtRenamed`), an incapable type gets neither `deriving (Eq)` nor `emitShowInstance`.
- **Exception for `Json` (user-approved 2026-10-20, from the engineer's plan):** codegen treats a `Json`-holding type as capable and keeps `deriving (Eq, Show)`, because the generated Haskell `Json` type already derives both and such a type builds today. `check` still refuses equality on it with `json-equality-denied` (E9), so what a program may write is as stated above.
- **`=` on `Promise` (user-approved 2026-10-20):** it builds today as `Async` thread-identity equality, which is not the structural equality `LLMLL.md` §13.2 defines, so it becomes an `equality-undefined` error. This is the one program shape that builds today and stops building.

### Check

- `=`, `!=` and `list-contains` are refused when the substituted type at the call site is not equality-capable.
- The new error kind is `equality-undefined`. Its message names the type and the incapable component.
- This generalizes `checkJsonNoEq`. A type that mentions `Json` still gets `json-equality-denied`, so existing messages and tests do not change.
- `<=>` takes `bool` only, so it cannot reach an incapable type.

### Why derive nothing and refuse at `check`

| Option | Effect | Verdict |
|---|---|---|
| Refuse such types at `check` | Dispatch tables, handler records and strategy values become inexpressible. | Rejected: a common design pattern is lost. |
| An `Eq` instance that calls `error` | `check` and `build` pass, and `=` crashes at run time. | Rejected: it breaks crash-freedom of built programs (roadmap G2) and one-shot correctness. |
| An `Eq` that compares by `StableName` or always returns `False` | `=` gets a nondeterministic or false meaning. | Rejected: `=` stops being sound as a contract predicate. |
| **Derive nothing, refuse equality at `check`** | The type builds. The only failing use is caught at `check`, with a message. | **Settled.** |

### Uses of the derived instances

Every use of a derived instance in generated code was read:

- **`Eq`:** `emitOp` for `=`, `!=` and `<=>` (Haskell `==`), and `list_contains`. The `check` rule above covers each one.
- **`Show`:**
  - An enclosing type's derived `Show`: the fixpoint makes the enclosing type incapable too, so it derives nothing.
  - `map_get`'s `Show k`: a user type derives no `Ord`, so it cannot be a map key and cannot reach this.
  - `emitShowInstance` after a rename: it is not emitted for an incapable type.
- **Elsewhere:** `llmll test` runs in the `PBT.hs` interpreter, not in generated code. The runtime event log records `Command` and `Response` text, not user values.

So once the `check` rule holds, no generated code needs `Eq` or `Show` of an incapable type.

## Edge cases and degenerate inputs

| # | Input | Expected | Channel |
|---|---|---|---|
| E1 (positive witness) | `(type Ops (\| Ops list[(fn [int] -> int)]))`, then `(def-shell same [a: Ops b: Ops] -> bool (= a b))` | A `check` error, `equality-undefined`, naming `Ops` and its function field. Today `check` passes and `build` fails. | type |
| E2 | The same `Ops` type, used in a `match`, with no `=` on it | Builds. `Ops` derives nothing. | — |
| E3 | `(= f g)` on two `(fn [int] -> int)` values | `equality-undefined`. Today `build` fails (measured). | type |
| E4 | `(= a b)` on two `Command` values | `equality-undefined`. Today `build` fails with `No instance for ‘Eq (IO ())’` (measured). | type |
| E5 | `(type Wrap (\| Wrap Ops))` | `Wrap` is incapable by the fixpoint, and derives nothing. | type |
| E6 | `(type Tree (\| Leaf int \| Node Tree Tree))` | Capable by the greatest fixpoint. It derives `(Eq, Show)`, as today. | — |
| E7 | `(list-contains handlers h)` with `handlers: list[(fn [int] -> int)]` | `equality-undefined` | type |
| E8 | `=` on two `Result[(fn [int] -> int), string]` values | `equality-undefined`: the substituted type contains a function. | type |
| E9 | `=` on a type that holds `Json` | `json-equality-denied`, unchanged. | type |

User types have no type parameters, so a polymorphic `Box[a]` instantiated at a function type cannot arise.

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| The equality-capable check | type | None. It is a syntactic check at `check`. |

The record adds no VC. Refusing `=` at an incapable type removes VCs and adds none, so `Σ_auto` is unchanged. A body that builds an `Ops` value is unaffected: whether its body VC is faithful is still decided by `isAdmissibleConstructor`.

## Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: the equality-capable predicate (a greatest fixpoint over the alias map), and the `equality-undefined` check beside `checkJsonNoEq`.
- `compiler/src/LLMLL/CodegenHs.hs`: conditional deriving in `emitTypeDef` and `emitStmtRenamed`.
- `LLMLL.md`: state the domain of `=`, `!=` and `list-contains`, and the new error kind. This lands on ship.
- `docs/llmll-ast.schema.json`: no change. No node shape changes.
- **No addition.** The record adds no builtin, construct or capability. It narrows what `check` accepts, so that `check` agrees with `build`.

## Risks

1. **Two error kinds for one idea.** (Spec drift.) `json-equality-denied` and `equality-undefined` both mean that equality is undefined at a type. Merging them would change a shipped message, so both are kept, and the code comment notes the relation. This only complicates the plan.
2. **A program that compared functions now fails earlier.** (Scope.) No such program can build today, so no working program changes behaviour. Only `check` output changes, from OK to an error.

## Hand-off

- **File:** `docs/design/equality-capable-types-proposal.md`, Rev 0, settled 2026-10-20.
- **Review:** none, so there is no review file to fold or archive.
- **Engineer:** implement the rule, the codegen change and the `check` rule above. Acceptance: E1, E3, E4, E7 and E8 give `equality-undefined`; E2 and E5 build; E6 and E9 are unchanged.
- **Doc-lead:** add the INDEX row, and move CTOR-FN-FIELD-1 from DECIDE to PLAN with a link to this file. The `LLMLL.md` text lands on ship.
