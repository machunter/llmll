# Pre-v0.3 Stabilisation Sprint — Implementation Plan

> **Prepared by:** Language Team
> **Date:** 2026-04-04
> **For discussion with:** Compiler Team
> **Source audit:** `pre_v03_assessment.md`
>
> **Governing criterion:** Every item below must be resolved before a single v0.3 feature ticket is opened. Items marked **[PREREQ v0.3]** are blocking — v0.3 Leanstral integration cannot be correct without them.

---

## Open Questions for the Compiler Team

> [!IMPORTANT]
> **H3 — `do`-notation semantics** requires a design decision before any implementation. Two options are on the table. The compiler team must choose before the sprint begins.
>
> **Option A (parse-time desugar):** `(do [x <- e] body)` is expanded at parse time into `EApp "seq-commands" [e, ELet [("x", ?, e)] body]`. The `EDo` AST node is removed. TC and codegen are untouched.
>
> **Option B (keep `EDo`, enforce pair model):** `EDo` remains a first-class AST node. The type checker enforces that every `DoBind` step returns `(State, Command)` and that the final `DoExpr` also returns `(State, Command)`. Codegen emits the corresponding pair-threading code rather than Haskell `do`-notation.
>
> Option A is lower risk and implementable in one PR. Option B is semantically cleaner but non-trivial and may delay the sprint.

> [!IMPORTANT]
> **M2 — RFC 6901 pointer source** for `llmll holes --json`: two approaches exist.
>
> **Option A (reuse sketch pass):** Run `runSketch` internally from `HoleAnalysis` and extract `shPointer` from the `SketchHole` list. Eliminates duplicate traversal logic. Requires `HoleAnalysis` to depend on `TypeCheck`.
>
> **Option B (dedicated walk):** Add a `withIndex`-style wrapper to `collectHolesExpr` that tracks integer indices per child position. No new dependency. Slightly more code.
>
> Language team prefers Option A for consistency with `--sketch`.

---

## Component 1 — Type System Soundness

*These two items directly threaten the correctness of the v0.3 Leanstral proof translation layer.*

---

### 1a — `EOp` Argument Type Checking **[PREREQ v0.3]**

**Ticket:** TC-01
**Priority:** Critical
**Estimated effort:** Small (2–3 hours)

#### Problem

`inferExpr (EOp op _args)` discards all arguments. `(> "hello" 42)` passes the type checker today. This violates Progress: well-typed programs should not go wrong. Proof obligations emitted to Lean will carry ill-typed sub-expressions if this is not fixed.

#### Files Changed

| File | Change |
| ---- | ------ |
| [TypeCheck.hs](../../../compiler/src/LLMLL/TypeCheck.hs) | Replace `inferExpr (EOp op _args)` with full argument-type checking |

#### Proposed Implementation

Replace the current relaxed body:

```haskell
-- BEFORE (lines 638–646)
inferExpr (EOp op _args) = do
  case Map.lookup op builtinEnv of
    Just (TFn _paramTypes retType) -> pure retType
    _ -> tcWarn ("unknown operator '" <> op <> "'") >> pure TBool
```

With:

```haskell
-- AFTER
inferExpr (EOp op args) = do
  case Map.lookup op builtinEnv of
    Just (TFn paramTypes retType) -> do
      when (length args /= length paramTypes) $
        tcError $ "operator '" <> op <> "' expects " <> tshow (length paramTypes)
                  <> " args, got " <> tshow (length args)
      zipWithM_ (\(j, expected) arg ->
        withSegment "args" $ withSegment (tshow (j :: Int)) $ checkExpr arg expected)
        (zip [0..] paramTypes) args
      pure retType
    _ -> do
      tcWarn $ "unknown operator '" <> op <> "'"
      pure TBool
```

#### Proof Obligation

**Progress lemma for operators:** For all `Γ`, `op`, `args`:
```
Γ ⊢ (EOp op args) : τ  iff
  builtinEnv(op) = TFn [τ₁,...,τₙ] τ  ∧
  |args| = n  ∧
  ∀ i. Γ ⊢ args[i] : τᵢ
```

#### Acceptance Criteria

- `(> "hello" 42)` → type error: `type mismatch in '<check>': expected int, got string`
- `(+ 1 2)` → still type-checks to `int`
- `(= x y)` for polymorphic `x`, `y` → still type-checks (TVar matches anything)
- `stack test` passes with no regressions

---

### 1b — `?proof-required` Hint Taxonomy **[PREREQ v0.3]**

**Ticket:** TC-02
**Priority:** Critical
**Estimated effort:** Medium (4–6 hours)

#### Problem

`HProofRequired Text` stores a free-form string tag (`"non-linear-contract"`, `"complex-decreases"`, `"manual"`). The spec (`LLMLL.md §6`) and v0.3 Leanstral integration require a three-level structured hint: `:simple` (LH track), `:inductive` (Leanstral track), `:unknown`. The routing logic in v0.3 cannot function without this.

#### Files Changed

| File | Change |
| ---- | ------ |
| [Syntax.hs](../../../compiler/src/LLMLL/Syntax.hs) | Add `ProofHint` data type; change `HProofRequired Text` → `HProofRequired ProofHint Text` |
| [HoleAnalysis.hs](../../../compiler/src/LLMLL/HoleAnalysis.hs) | Update `holeKindLabel`, `holeDesc`, `holeStatus'` for new type |
| [Parser.hs](../../../compiler/src/LLMLL/Parser.hs) | Update `pProofRequiredHole` to emit structured hint |
| [ParserJSON.hs](../../../compiler/src/LLMLL/ParserJSON.hs) | Update JSON-AST `hole-proof-required` node parsing |
| [CodegenHs.hs](../../../compiler/src/LLMLL/CodegenHs.hs) | Update `emitHole (HProofRequired ...)` |
| [LLMLL.md](../../../LLMLL.md) | Update §6 to document new JSON-AST `hint` field |

#### Proposed ADT

```haskell
-- New in Syntax.hs
data ProofHint
  = PHSimple    -- ^ Within QF linear arithmetic; LiquidHaskell/fixpoint can handle it
  | PHInductive -- ^ Requires structural/inductive reasoning; route to Leanstral MCP
  | PHUnknown   -- ^ Complexity undetermined; human review required
  deriving (Show, Eq, Generic)

-- Updated HoleKind constructor
-- BEFORE:  | HProofRequired Text
-- AFTER:   | HProofRequired ProofHint Text   -- hint, reason tag
```

#### Assignment Rules

| Trigger | Assigned `ProofHint` | Reason tag |
| ------- | -------------------- | ---------- |
| Non-linear `pre`/`post` (`*`, `/`, `mod`, `^`) on scalar values | `PHSimple` | `"non-linear-contract"` |
| Non-linear `pre`/`post` involving recursive structure / list | `PHInductive` | `"non-linear-contract"` |
| `letrec :decreases` is a complex expression (not variable/literal) | `PHInductive` | `"complex-decreases"` |
| Manual `?proof-required` in source | `PHUnknown` | `"manual"` |

> [!NOTE]
> The distinction between `PHSimple` and `PHInductive` for non-linear contracts requires a lightweight structural check on the argument expressions. A heuristic: if any argument to `*`/`/`/`mod` references a list-typed sub-expression or a letrec parameter, classify as `PHInductive`; otherwise `PHSimple`.

#### JSON-AST Node Update

```json
// BEFORE
{ "kind": "hole-proof-required", "reason": "non-linear-contract" }

// AFTER
{ "kind": "hole-proof-required", "hint": "simple|inductive|unknown", "reason": "non-linear-contract" }
```

The `"hint"` field is **required** in v0.3. The parser should reject nodes missing it (emit a clear error, suggest running `llmll check` to regenerate).

#### Acceptance Criteria

- `?proof-required` in S-expression source → `HProofRequired PHUnknown "manual"`
- Non-linear contract on scalars → `HProofRequired PHSimple "non-linear-contract"`
- Complex `letrec :decreases` → `HProofRequired PHInductive "complex-decreases"`
- `llmll holes --json` output includes `"hint": "simple"|"inductive"|"unknown"` field
- `llmll typecheck --sketch` output preserves hint in hole entries
- Existing `stack test` suite passes

---

## Component 2 — Parser & Codegen Cleanup

---

### 2a — `string-concat` Variadic Desugar **[v0.3 Specified]**

**Ticket:** PC-01
**Priority:** High
**Estimated effort:** Small (1–2 hours)

#### Problem

`(string-concat "a" "b" "c")` in S-expression source produces an arity error today. The v0.3 roadmap specifies parse-time desugar to `(string-concat-many ["a" "b" "c"])` for 3+ arguments. Binary `(string-concat a b)` is unchanged.

#### Files Changed

| File | Change |
| ---- | ------ |
| [Parser.hs](../../../compiler/src/LLMLL/Parser.hs) | Modify `pSExprApp` to desugar `string-concat` with 3+ args |

#### Proposed Implementation

In `pSExprApp`, after parsing `func` and `args`:

```haskell
-- In pSExprApp, before the isOperator check:
let (func', args') = desugarStringConcat func args

desugarStringConcat :: Name -> [Expr] -> (Name, [Expr])
desugarStringConcat "string-concat" args
  | length args >= 3 = ("string-concat-many", [foldr (\a acc -> EApp "list-prepend" [a, acc])
                                                      (EApp "list-empty" []) args])
desugarStringConcat func args = (func, args)
```

#### Acceptance Criteria (from roadmap)

- `(string-concat "a" "b" "c")` compiles to same Haskell as `(string-concat-many ["a" "b" "c"])`
- `(string-concat prefix)` partial application still type-checks as `string → string`
- JSON-AST `{"fn": "string-concat", "args": [a, b, c]}` still produces a clear arity error (sugar is S-expression only)

---

### 2b — `pModule` / `pModuleFlattened` Alignment

**Ticket:** PC-02
**Priority:** Medium
**Estimated effort:** Trivial (30 min)

#### Problem

`pModuleFlattened` (main parse path) parses `open`/`export` declarations between imports and body. `pModule` (REPL/API path, exposed as `parseModule`) does not — it goes directly from imports to `many pStatement`. This means `(open ...)` declarations in the `(module ...)` block may be silently dropped when using the `parseModule` entry point.

#### Files Changed

| File | Change |
| ---- | ------ |
| [Parser.hs](../../../compiler/src/LLMLL/Parser.hs) | Add `opens <- many (try pOpenDecl <|> try pExportDecl)` to `pModule` between imports and body |

#### Acceptance Criteria

- `parseModule` on a file with `(open app.auth)` before `(def-logic ...)` correctly includes `SOpen` in the result
- Existing REPL and module-resolver paths are unaffected

---

### 2c — `sanitizeCheckLabel` Underscore Collapse Fix

**Ticket:** PC-03
**Priority:** Low
**Estimated effort:** Trivial (15 min)

#### Problem

`T.splitOn "__"` collapses double underscores but leaves single runs from multi-replacement intact. `"a___b"` → `"a__b"` (still contains double underscore on the `_b` fragment). GHC accepts the identifier but inspection tools are confused.

#### Files Changed

| File | Change |
| ---- | ------ |
| [CodegenHs.hs](../../../compiler/src/LLMLL/CodegenHs.hs) | Replace `splitOn "__"` approach with a `go`-loop that collapses any underscore run |

#### Proposed Implementation

```haskell
sanitizeCheckLabel :: Text -> Text
sanitizeCheckLabel lbl =
  let replaced = T.map (\c -> if isAsciiAlphaNum c then c else '_') lbl
      collapsed = collapseUnderscores replaced
  in T.dropWhile (== '_') . T.dropWhileEnd (== '_') $ collapsed
  where
    collapseUnderscores = T.pack . go False . T.unpack
    go _    []          = []
    go True ('_':rest)  = go True rest          -- skip consecutive underscores
    go _    ('_':rest)  = '_' : go True rest    -- emit one, enter collapse mode
    go _    (c  :rest)  = c   : go False rest
    isAsciiAlphaNum c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
```

---

### 2d — Centralise `schemaVersion` in `Version.hs`

**Ticket:** PC-04
**Priority:** Medium
**Estimated effort:** Small (1 hour)

#### Problem

`"0.2.0"` is hard-coded in `Sketch.hs` (line 43), `ParserJSON.hs` (`expectedSchemaVersion`), and the `emitLibHs` banner in `CodegenHs.hs`. When the schema bumps to `0.3.0`, each must be updated manually — one missed update silently breaks version gating.

#### Files Changed

| File | Change |
| ---- | ------ |
| [NEW] `compiler/src/LLMLL/Version.hs` | Define `currentSchemaVersion :: Text = "0.2.0"` and `compilerVersion :: Text = "0.2.0"` |
| [Sketch.hs](../../../compiler/src/LLMLL/Sketch.hs) | Import `Version` and replace literal `"0.2.0"` |
| [ParserJSON.hs](../../../compiler/src/LLMLL/ParserJSON.hs) | Import `Version` and replace `expectedSchemaVersion` literal |
| [CodegenHs.hs](../../../compiler/src/LLMLL/CodegenHs.hs) | Import `Version` and replace banner string |
| [compiler/package.yaml](../../../compiler/package.yaml) | Ensure `LLMLL.Version` is in `exposed-modules` |

---

### 2e — `do`-notation Design Decision & Fix

**Ticket:** PC-05
**Priority:** Medium (requires team decision first)
**Estimated effort:** Small if Option A; Large if Option B (see Open Questions above)

#### Problem

`EDo` codegen emits Haskell `do`-notation directly (valid only for `IO` monad). The spec states `do`-notation should desugar to the `Command/Response` pair model at the AST level.

> [!WARNING]
> **This item is blocked on the compiler team's Option A / Option B decision.** Do not begin implementation until the choice is recorded as a `[DESIGN — COMMITTED]` entry in `compiler-team-roadmap.md`.

#### If Option A chosen (recommended)

The `EDo` constructor is removed from `Syntax.hs`. The parser expands `(do ...)` at parse time. No TC or codegen changes required. The `EDo` dead-code paths in `TypeCheck.hs`, `CodegenHs.hs`, and `HoleAnalysis.hs` are deleted.

#### If Option B chosen

The type checker must enforce:
- Every `DoBind name e` step: `Γ ⊢ e : (State, Command)`
- The final `DoExpr e`: `Γ ⊢ e : (State, Command)`
- `inferDoSteps` must return `(State, Command)` not `TUnit`

Codegen must emit pair-threading Haskell instead of `do`-blocks.

---

## Component 3 — Tooling DX

---

### 3a — RFC 6901 Pointers in `llmll holes --json`

**Ticket:** DX-01
**Priority:** Medium
**Estimated effort:** Medium (3–4 hours)

#### Problem

`HoleAnalysis.formatHoleReportJson` derives the `"pointer"` field by replacing spaces with `/` in context strings. This is not a valid RFC 6901 JSON Pointer and is inconsistent with `--sketch` output. Agent tools using these pointers to locate holes in the JSON-AST will fail.

#### Files Changed

| File | Change |
| ---- | ------ |
| [HoleAnalysis.hs](../../../compiler/src/LLMLL/HoleAnalysis.hs) | Add pointer tracking to `collectHolesExpr` (see options in Open Questions) |

#### Proposed approach (Option A — reuse sketch pass)

Expose a `runSketchHoles :: TypeEnv -> [Statement] -> [SketchHole]` function from `TypeCheck` that runs the sketch pass and returns only `sketchHoles`. In `HoleAnalysis.formatHoleReportJson`, call this pass and join each `HoleEntry` with its corresponding `SketchHole` by name. The `shPointer` from the sketch result becomes the `"pointer"` in the JSON output.

#### Acceptance Criteria

- `llmll holes --json` `"pointer"` field is a valid RFC 6901 JSON Pointer
- Pointer for a hole in `def-logic game-won? body` = `/statements/N/body`
- Pointer is consistent with `--sketch` output for the same hole

---

### 3b — Gate `"unresolved named hole"` Warning in Sketch Mode

**Ticket:** DX-02
**Priority:** Low
**Estimated effort:** Trivial (15 min)

#### Problem

`inferHole (HNamed name)` emits `tcWarn "unresolved named hole"` unconditionally. In sketch mode (`tcSketchMode = True`), holes are expected — the warning is noise. It also duplicates when tools run the type checker as a sub-step.

#### Files Changed

| File | Change |
| ---- | ------ |
| [TypeCheck.hs](../../../compiler/src/LLMLL/TypeCheck.hs) | Gate `tcWarn "unresolved named hole"` on `not <$> gets tcSketchMode` |

```haskell
inferHole (HNamed name) = do
  recordHole name HoleUnknown
  sketch <- gets tcSketchMode
  unless sketch $
    tcWarn "unresolved named hole"
  pure (TVar ("?" <> name))
```

---

### 3c — `random_int` Runtime Stub

**Ticket:** DX-03
**Priority:** Low
**Estimated effort:** Small (1 hour)

#### Problem

`random_int = return 42` silently returns a constant, defeating PBT generators that use `random-int`. Programs appear to work but produce no random coverage.

#### Files Changed

| File | Change |
| ---- | ------ |
| [CodegenHs.hs](../../../compiler/src/LLMLL/CodegenHs.hs) | Wire `System.Random.randomRIO (minBound, maxBound)` in the preamble and add `System.Random` to default dependencies |
| [CodegenHs.hs](../../../compiler/src/LLMLL/CodegenHs.hs) | Add `random` to `hackagePkgNames` default list so it doesn't require an explicit `(import haskell.random)` |

---

### 3d — Version Banner in Generated Files

**Ticket:** DX-04
**Priority:** Trivial
**Estimated effort:** Trivial (5 min, done as part of PC-04)

#### Problem

`emitLibHs` emits `"-- Generated by LLMLL compiler v0.1.3 (Haskell backend)"`. Should reference the centralised version constant added in PC-04.

#### Files Changed

| File | Change |
| ---- | ------ |
| [CodegenHs.hs](../../../compiler/src/LLMLL/CodegenHs.hs) | Replace literal `v0.1.3` with `compilerVersion` from `Version.hs` |

---

## Summary Table

| Ticket | Item | Priority | Effort | PREREQ v0.3? | Decision needed? |
| ------ | ---- | -------- | ------ | ------------ | ---------------- |
| TC-01 | `EOp` argument type checking | Critical | Small | **Yes** | No |
| TC-02 | `?proof-required` hint taxonomy | Critical | Medium | **Yes** | No |
| PC-01 | `string-concat` variadic desugar | High | Small | No | No |
| PC-02 | `pModule` open/export alignment | Medium | Trivial | No | No |
| PC-03 | `sanitizeCheckLabel` underscore collapse | Low | Trivial | No | No |
| PC-04 | Centralise `schemaVersion` in `Version.hs` | Medium | Small | No | No |
| PC-05 | `do`-notation design + fix | Medium | Small–Large | No | **Yes** |
| DX-01 | RFC 6901 pointers in `holes --json` | Medium | Medium | No | **Yes (approach)** |
| DX-02 | Gate sketch-mode warning | Low | Trivial | No | No |
| DX-03 | `random_int` stub | Low | Small | No | No |
| DX-04 | Version banner | Trivial | Trivial | No | No |

---

## Verification Plan

### Automated Tests
```bash
cd compiler
stack test                         # all 47 existing tests must pass after each ticket
stack exec llmll -- check ../examples/hangman_json/hangman.ast.json
stack exec llmll -- check ../examples/hangman_sexp/hangman.llmll
stack exec llmll -- check ../examples/tictactoe_sexp/tictactoe.llmll
stack exec llmll -- typecheck --sketch ../examples/sketch/if_hole.ast.json
```

New test cases to add:
- TC-01: `ill_typed_op.llmll` — `(> "hello" 42)` must produce a type-mismatch error
- TC-02: `proof_hints.llmll` — verify `PHSimple` / `PHInductive` / `PHUnknown` emitted correctly
- PC-01: `string_concat_variadic.llmll` — verify 3-arg form compiles
- DX-01: golden file for `llmll holes --json` pointer format

### Manual Verification
- After TC-01: run `llmll check` on a program with an ill-typed operator and confirm the diagnostic JSON has `"kind": "type-mismatch"` with correct `"expected"` and `"got"` fields.
- After TC-02: run `llmll holes --json` and confirm each `?proof-required` entry has a `"hint"` field with value `"simple"`, `"inductive"`, or `"unknown"`.
- After PC-01: run `llmll check` on `(string-concat "a" "b" "c")` and confirm it compiles without error.
