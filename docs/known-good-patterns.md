# LLMLL v0.1.3.1 — Known-Good Patterns

> **Purpose:** A single-page reference for AI agents targeting the **current compiler** (v0.1.3.1).
> Each pattern shows what works today, what the old workaround was, and when it was fixed.
> If you ever see contradictory guidance elsewhere in the spec, this page takes precedence for v0.1.3.1.

---

## 1. Pair / State Accessor Functions

**Pattern — state accessors with explicit type annotations on the state parameter:**

```json
{ "kind": "def-logic", "name": "state-word",
  "params": [{ "name": "s", "param_type": { "kind": "primitive", "name": "string" } }],
  "body": { "kind": "app", "fn": "first", "args": [{ "kind": "var", "name": "s" }] } }
```

✅ **Works in v0.1.3.1.** `first` and `second` accept any pair-like value regardless of how the parameter was annotated.

> [!NOTE]
> **Old workaround (v0.1.1–v0.1.3):** Required `"untyped": true` on the state parameter because the type checker incorrectly rejected `first(s: string)` with `expected Result[a,b], got string`. **Remove this workaround.** Fixed in v0.1.3.1 (commit `ef6f41c`).

---

## 2. Type Aliases (where-clauses) at Call Sites

**Pattern — passing a literal where a named alias is expected:**

```json
{ "kind": "app", "fn": "use-nonneg",
  "args": [{ "kind": "lit-int", "value": 5 }] }
```

where `use-nonneg` declares `[x: NonNeg]` and `NonNeg = (where [n: int] (>= n 0))`.

✅ **Works in v0.1.3.1.** The type checker expands aliases before unification — `5 :: int` is compatible with `NonNeg` whose base type is `int`.

> [!NOTE]
> **Old workaround (v0.1.1–v0.1.3):** Required passing the value as an untyped variable or removing the `where` constraint from the type definition. Fixed in v0.1.3 (commit `9931a77`).

---

## 3. List Literals in JSON-AST

**Pattern — constructing a fixed list:**

```json
{ "kind": "lit-list", "items": [
    { "kind": "lit-string", "value": " " },
    { "kind": "lit-string", "value": " " },
    { "kind": "lit-string", "value": " " }
]}
```

✅ **Works in v0.1.3.1.** The `lit-list` node is desugared by the parser to a `foldr list-prepend (list-empty)` chain.

> [!NOTE]
> **Old workaround:** Chaining 9 `list-append` calls to build a 9-element board. `lit-list` was added in v0.1.3.1 (commit `7a190a9`).

---

## 4. Multi-Segment String Construction

**Pattern — building a display string from multiple segments:**

```json
{ "kind": "app", "fn": "string-concat-many",
  "args": [{ "kind": "lit-list", "items": [
      { "kind": "var", "name": "c0" },
      { "kind": "lit-string", "value": " | " },
      { "kind": "var", "name": "c1" },
      { "kind": "lit-string", "value": " | " },
      { "kind": "var", "name": "c2" }
  ]}]}
```

✅ **Works in v0.1.3.1.** `string-concat-many :: list[string] -> string` concatenates without separator.

> [!NOTE]
> **Old workaround:** Five nested `string-concat` calls. Added in v0.1.3.1 (commit `7a190a9`).

---

## 5. New Built-ins Available Since v0.1.3.1

| Function | Signature | Notes |
|----------|-----------|-------|
| `string-trim` | `string → string` | Strip leading/trailing whitespace, `\t`, `\n`, `\r` |
| `string-concat-many` | `list[string] → string` | Concat list of strings |
| `list-nth` | `list[a] int → Result[a, string]` | Safe indexed access |

---

## 6. Still Restricted in v0.1.x (Fixed in v0.2)

| Feature | Status | Workaround |
|---------|--------|------------|
| `[acc: (int, string)]` in `typed-param` | ❌ Parse error in v0.1.x | Use bare `[acc]` — fixed in v0.2 |
| Multi-file imports | ❌ Not yet | Single file only |
| LiquidHaskell `pre`/`post` verification | ⚠️ Runtime assert only | Correct at runtime; proof deferred |

---

## 7. JSON-AST `def-main` Initialisation

```json
{ "kind": "def-main", "mode": "console",
  "init":  { "kind": "app", "fn": "start-game", "args": [] },
  "step":  { "kind": "var", "name": "game-loop" } }
```

> [!IMPORTANT]
> **`:init` must be a zero-arg function call**, not a bare `var`. Use `{ "kind": "app", "fn": "start-game", "args": [] }`, not `{ "kind": "var", "name": "start-game" }`.
