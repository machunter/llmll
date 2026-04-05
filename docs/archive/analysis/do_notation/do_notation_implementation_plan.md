# Do-Notation + Pair Destructuring: Implementation Plan

> **Design authority:** `docs/do-notation-design.md` r9 (Approved)
> **Target version:** LLMLL v0.3
> **Compiler source root:** `compiler/src/LLMLL/`

This plan implements the four-PR sequence defined by `do-notation-design.md`. PRs are strictly ordered: each gates the next. PRs 2 and 4 may be folded if the implementer opts for speed; the ordering constraint between them is lifted because they touch non-overlapping AST nodes (`DoStep` vs `ELet`). PRs 1 and 3 must ship first and last in their respective positions.

---

## Baseline Snapshot (confirmed by code inspection)

| Fact | Location | State |
|------|----------|-------|
| `EPair` returns `TResult ta tb` | `TypeCheck.hs:651` | Must change → `TPair` |
| `TPair` constructor does not exist | `Syntax.hs:98–115` | Must add |
| `compatibleWith` has no `TPair` case | `TypeCheck.hs:817–836` | Falls through to `a == b` — regression |
| `typeToJson` has no `TPair` case | `AstEmit.hs:153–180` | GHC `-Wincomplete-patterns` + runtime error |
| `emitDo` emits Haskell `do`-notation | `CodegenHs.hs:552–557` | Unsound in pure context |
| `DoStep` has two constructors | `Syntax.hs:182–185` | `DoBind Name Expr \| DoExpr Expr` |
| `ELet` binding head is `Name` | `Syntax.hs:169` | `[(Name, Maybe Type, Expr)] Expr` |
| `"pair-type"` schema `$def` | `docs/llmll-ast.schema.json:388–398` | Already correct — `fst`/`snd` fields present |
| `DoStep` schema | `docs/llmll-ast.schema.json:710–734` | Old `"bind-step"` / `"expr-step"` form |
| `seq_commands` preamble | `CodegenHs.hs:319–320` | `IO () -> IO () -> IO ()` — coherent with PR 3 output |

---

## PR 1 — `TPair` Introduction *(Gate for all other PRs)*

**Files:** `compiler/src/LLMLL/Syntax.hs`, `compiler/src/LLMLL/TypeCheck.hs`, `compiler/src/LLMLL/CodegenHs.hs`, `compiler/src/LLMLL/AstEmit.hs`

> [!IMPORTANT]
> PRs 2, 3, and 4 cannot begin until PR 1 passes all acceptance criteria. No do-notation TC enforcement is sound against `TResult`.

### [MODIFY] Syntax.hs

Add `TPair Type Type` to the `Type` ADT between `TResult` and `TPromise`:

```haskell
-- After TResult line 107:
| TPair Type Type               -- ^ Product type: (a, b)
```

Add `typeLabel` case (after existing `TResult` case):
```haskell
typeLabel (TPair a b) = "(" <> typeLabel a <> ", " <> typeLabel b <> ")"
```

### [MODIFY] TypeCheck.hs — four sites

**Site 1 — `inferExpr (EPair a b)` (line 651):**
```haskell
-- BEFORE:
pure (TResult ta tb)  -- Pair used as (state, command) — approximate as Result
-- AFTER:
pure (TPair ta tb)
```

**Site 2 — `compatibleWith` (after line 827):**
```haskell
-- Add before the TPromise case:
compatibleWith (TPair a b) (TPair c d) = compatibleWith a c && compatibleWith b d
```

**Site 3 — `toHsType` (add case in CodegenHs.hs, not TypeCheck.hs — see below)**

**Site 4 — verify `checkExhaustive`:** No code change needed. `TPair` falls through to `_ -> pure ()`. Document confirms this. Add a comment at the `TResult _ _` arm (line 741) noting `TPair` is handled by fallthrough.

### [MODIFY] CodegenHs.hs — one site

Add `toHsType` case (currently `toHsType` ends at `TSumType` on line 629):
```haskell
toHsType (TPair a b) = "(" <> toHsType a <> ", " <> toHsType b <> ")"
```

### [MODIFY] AstEmit.hs — one site

Add `typeToJson` case (currently missing, after `TResult` case on line 162):
```haskell
typeToJson (TPair a b) = object
  [ "kind" .= ("pair-type" :: Text)
  , "fst"  .= typeToJson a
  , "snd"  .= typeToJson b
  ]
```

**Schema:** No change required — `TypePair` `$def` with `"fst"` and `"snd"` is already present at lines 388–398.

### PR 1 Acceptance Criteria (all must pass before merge)

1. `stack build` — zero `-Wincomplete-patterns` warnings, especially for `typeToJson` in `AstEmit.hs`
2. `llmll check examples/*` — zero new diagnostics on any existing example
3. `def-main :init` returning `EPair` passes `llmll check` — no false `type-mismatch`
4. `match` on a pair-typed scrutinee does NOT produce `"non-exhaustive-match"` citing `Success`/`Error`
5. `llmll build --emit json-ast` on any `EPair`-containing program produces `{"kind":"pair-type","fst":...,"snd":...}` that round-trips through `ParserJSON.hs`

---

## PR 2 — `DoStep` Collapse + TC Enforcement

**Depends on:** PR 1 merged and acceptance criteria passing.

**Files:** `Syntax.hs`, `Parser.hs`, `ParserJSON.hs`, `TypeCheck.hs`, `PBT.hs`, `AstEmit.hs`, `docs/llmll-ast.schema.json`

> [!IMPORTANT]
> The `DoStep` ADT change touches every file that pattern-matches on `DoBind` or `DoExpr`. All sites must be updated in this single PR — partial migration will not compile.

### DoStep ADT — affected pattern-match sites

| File | Current pattern | After |
|------|----------------|-------|
| `TypeCheck.hs:709–718` | `inferDoSteps` matches `DoBind`/`DoExpr` | Rewrite (see below) |
| `Parser.hs` | `pDoStep` parses into `DoBind`/`DoExpr` | Emit `DoStep (Just n) e` / `DoStep Nothing e` |
| `ParserJSON.hs` | `"bind-step"` → `DoBind`, `"expr-step"` → `DoExpr` | Route both to `DoStep`; emit `"schema-migration-required"` warning for old kinds |
| `PBT.hs` | Any `DoStep` generators or pattern matches | Update to new ADT |
| `AstEmit.hs` | `exprToJson (EDo steps)` step serialization | Emit `"do-step"` with optional `"name"` |
| `CodegenHs.hs:556–557` | `emitStep (DoBind n e)` / `emitStep (DoExpr e)` | Update to `emitStep (DoStep (Just n) e)` / `emitStep (DoStep Nothing e)` — **PR 2 only updates this dispatch; PR 3 replaces the full `emitDo` body** |

### [MODIFY] Syntax.hs

```haskell
-- BEFORE:
data DoStep
  = DoBind Name Expr     -- ^ name <- expr
  | DoExpr Expr          -- ^ bare expression (final)

-- AFTER:
data DoStep = DoStep (Maybe Name) Expr
  -- Nothing   → anonymous step (former DoExpr)
  -- Just "x"  → named step     (former DoBind)
```

### [MODIFY] TypeCheck.hs — `inferDoSteps` complete rewrite

Replace lines 707–718 with the new pair-thread enforcement logic:

```haskell
inferDoSteps :: [DoStep] -> TC Type
inferDoSteps [] = pure TUnit
inferDoSteps steps = do
  -- Infer first step to establish S
  let (DoStep mName0 e0) = head steps
  t0 <- withSegment "steps" $ withSegment "0" $ inferExpr e0
  -- Unify: t0 must be TPair S Command
  (s0, _) <- expectPairType "do-block step 0" t0
  -- Bind state variable
  let binding0 = case mName0 of
        Just n  -> [(n, s0)]
        Nothing -> [("_s_0", s0)]
  -- Process remaining steps, threading state type S
  withEnv binding0 $ go s0 1 (tail steps)
  where
    go sType _ [] = pure (TPair sType (TCustom "Command"))
    go sType i (DoStep mName e : rest) = do
      t <- withSegment "steps" $ withSegment (tshow i) $ inferExpr e
      (si, _) <- expectPairType ("do-block step " <> tshow i) t
      -- Unify S: all steps must thread the same state type
      unify ("do-block step " <> tshow i) sType si
      let bindName = case mName of
            Just n  -> n
            Nothing -> "_s_" <> tshow i
      withEnv [(bindName, si)] $ go sType (i + 1) rest

-- Helper: expect TPair, emit "do-step-type-error" if not
expectPairType :: Text -> Type -> TC (Type, Type)
expectPairType ctx (TPair a b) = pure (a, b)
expectPairType ctx t = do
  modify $ \s -> s { tcErrors = tcErrors s ++
    [(mkError Nothing ("do-step-type-error in " <> ctx <>
      ": step must return (S, Command), got " <> typeLabel t))
      { diagKind = Just "do-step-type-error" }] }
  pure (TVar "?", TCustom "Command")  -- continue with wildcards; don't cascade
```

> [!NOTE]
> `expectPairType` uses error-recovery wildcards so a bad step doesn't suppress subsequent step diagnostics — consistent with the existing `inferHole` recovery pattern.

### [MODIFY] docs/llmll-ast.schema.json — `DoStep`

Replace the `"DoStep"` `oneOf` at lines 710–734 with:

```json
"DoStep": {
  "description": "A single step in a do-block. Named steps bind the state component; anonymous steps discard it (state-loss hazard if non-terminal).",
  "type": "object",
  "required": ["kind", "expr"],
  "additionalProperties": false,
  "properties": {
    "kind":       { "type": "string", "const": "do-step" },
    "expr":       { "$ref": "#/$defs/Expr" },
    "name":       { "type": "string", "description": "If present, bound to the state component of expr's result." },
    "state_type": { "$ref": "#/$defs/Type", "description": "Optional hint: the state type S. Required only when expr itself is a hole." }
  }
}
```

`ParserJSON.hs` must emit `"schema-migration-required"` diagnostic (warning, not error) when it encounters `"bind-step"` or `"expr-step"` — then parse them as `DoStep` anyway for backward compatibility.

### PR 2 Acceptance Criteria

1. A step expression returning `Command` (not `(S, Command)`) produces a `"do-step-type-error"` diagnostic
2. State type mismatch between steps produces `"type-mismatch"` with type labels in the message
3. `llmll typecheck --sketch` on `[s1 <- (fn state ?hole)]` reports `inferredType` for `?hole` with pointer form `/statements/N/body/steps/K/args/J`
4. Old `"bind-step"` / `"expr-step"` JSON-AST emits `"schema-migration-required"` warning but parses successfully
5. `stack test` passes all existing examples

---

## PR 3 — `emitDo` Rewrite *(Soundness fix)*

**Depends on:** PR 2 merged (ADT is now `DoStep (Maybe Name) Expr`).

**Files:** `compiler/src/LLMLL/CodegenHs.hs`

> [!CAUTION]
> The current `emitDo` emits Haskell `do`-notation inside pure `def-logic` bodies. This is unsound and will cause GHC type errors on any real `do`-block. PR 3 is not optional polish.

### [MODIFY] CodegenHs.hs — replace `emitDo` entirely

```haskell
-- REMOVE (lines 552–557):
emitDo :: [DoStep] -> Text
emitDo steps =
  "(do { " <> T.intercalate "; " (map emitStep steps) <> " })"
  where
    emitStep (DoBind n e) = toHsIdent n <> " <- " <> emitExpr e
    emitStep (DoExpr e)   = emitExpr e

-- REPLACE WITH pure let-chain emitter:
emitDo :: [DoStep] -> Text
emitDo [] = "()"
emitDo steps =
  let indexed  = zip [0 :: Int ..] steps
      bindings = concatMap emitBinding indexed
      finalIdx = length steps - 1
      finalS   = "_s_" <> tshow finalIdx
      finalCmd = buildSeq (map (\i -> "_cmd_" <> tshow i) [0..finalIdx])
  in "(let { " <> T.intercalate "; " bindings
     <> " } in (" <> finalS <> ", " <> finalCmd <> "))"
  where
    emitBinding (i, DoStep mName e) =
      let sName = case mName of { Just n -> toHsIdent n; Nothing -> "_s_" <> tshow i }
          cName = "_cmd_" <> tshow i
      in [ "(" <> sName <> ", " <> cName <> ") = " <> emitExpr e ]

    -- Right-associative seq_commands fold:
    -- seq_commands c0 (seq_commands c1 c2)
    buildSeq []     = "seq_commands () ()"  -- degenerate; blocked by parse
    buildSeq [c]    = c
    buildSeq (c:cs) = "seq_commands " <> c <> " (" <> buildSeq cs <> ")"
```

**Regression examples to add** (in `compiler/examples/` as `.llmll` and `.ast.json`):
- `do_two_step.llmll` — two named steps
- `do_three_step.llmll` — three steps, middle anonymous
- `do_two_step.ast.json` / `do_three_step.ast.json` — JSON-AST equivalents

### PR 3 Acceptance Criteria

1. Generated Haskell for a `do`-block is a pure `let ... in (sN, _finalCmd)` expression — **no `do` keyword**, no `<-` in generated output
2. A `do`-block inside a `def-logic` compiles with GHC without `-XMonadComprehensions` or `IO` context
3. Two-step and three-step regression examples pass `stack test`
4. `stack test` passes all existing examples

---

## PR 4 — Pair Destructuring in `let` *(Option A: `Name → Pattern`)*

**Depends on:** PR 1 merged (`TPair` in scope). May be developed in parallel with PRs 2 and 3 but must not merge before PR 1.

**Files:** `Syntax.hs`, `Parser.hs`, `ParserJSON.hs`, `TypeCheck.hs`, `CodegenHs.hs`, `AstEmit.hs`, `PBT.hs`, `docs/llmll-ast.schema.json`, `LLMLL.md`

> [!IMPORTANT]
> This is a mechanical `Name → Pattern` promotion in `ELet`. Every site that deconstructs an `ELet` binding tuple `(n, mAnnot, e)` must become `(pat, mAnnot, e)`. The payload for simple bindings is `PVar n` — identical semantics.

### [MODIFY] Syntax.hs

```haskell
-- BEFORE (line 169):
| ELet [(Name, Maybe Type, Expr)] Expr

-- AFTER:
| ELet [(Pattern, Maybe Type, Expr)] Expr
```

### [MODIFY] Parser.hs

Two changes:

1. In `pLetBinding`, replace `IDENT` parse with `pPattern` call:
   ```
   -- "[" pattern expr "]"  (unified form per r6 BNF)
   ```

2. Add `(pair x y)` alternative to `pPattern`:
   ```
   -- IDENT IDENT form inside parens, keyword "pair"
   ```

> [!NOTE]
> Add a regression test for `(let [(x (some-expr))] ...)` where `some-expr` starts with `(` — verify `pPattern` stops at `x` and doesn't consume the following expression as a sub-pattern.

### [MODIFY] ParserJSON.hs

In the `let`-binding object parser: check for `"name"` key (produce `PVar name` — backward compat) or `"pattern"` key (dispatch to pattern parser). Both paths converge on `(Pattern, Maybe Type, Expr)`.

### [MODIFY] TypeCheck.hs — `inferExpr (ELet ...)`

Extend binding loop (currently lines 510–524) to dispatch on pattern head:

```haskell
-- Existing: n is Name → becomes PVar n (same semantics)
-- New case:
(PConstructor "pair" [PVar s, PVar c], Nothing, e) -> do
  inferredTy <- inferExpr e
  (ta, tb)   <- expectPairType "let pair destructuring" inferredTy
  tcInsert s ta
  tcInsert c tb
  pure ((PConstructor "pair" [PVar s, PVar c], Nothing) :)
-- General pattern fallback (for future extension):
(pat, mAnnot, e) -> do
  inferredTy <- inferExpr e
  bindings   <- checkPattern pat inferredTy
  mapM_ (uncurry tcInsert) bindings
  pure ...
```

> [!NOTE]
> The general `checkPattern` dispatch handles nested destructuring `(pair word (pair g rest))` for free — no special casing needed.

### [MODIFY] CodegenHs.hs — `emitLet`

```haskell
-- BEFORE (line 487):
T.intercalate "; " (map (\(n,_,e) -> toHsIdent n <> " = " <> emitExpr e) bs)

-- AFTER:
T.intercalate "; " (map (\(pat,_,e) -> emitPat pat <> " = " <> emitExpr e) bs)
```

Add `emitPat` case for pair constructor (if not already covered by existing `PConstructor` path):
```haskell
emitPat (PConstructor "pair" [p1, p2]) = "(" <> emitPat p1 <> ", " <> emitPat p2 <> ")"
```

This emits valid Haskell: `let { (s, cmd) = expr } in body`.

### [MODIFY] AstEmit.hs — `exprToJson (ELet ...)`

Emit `"name"` key for `PVar`-headed bindings (backward compat); emit `"pattern"` key for other patterns.

### [MODIFY] docs/llmll-ast.schema.json — `LetBinding`

Add optional `"pattern"` field alongside existing `"name"` (mutually exclusive; existing `"name"` files valid without migration):

```json
"LetBinding": {
  "type": "object",
  "required": ["expr"],
  "additionalProperties": false,
  "properties": {
    "name":    { "type": "string", "description": "Simple binding: name <- expr" },
    "pattern": { "$ref": "#/$defs/Pattern", "description": "Destructuring binding: (pair x y) <- expr" },
    "expr":    { "$ref": "#/$defs/Expr" }
  }
}
```

### [MODIFY] LLMLL.md

- Update BNF `let` and `pattern` rules to match §5b in `do-notation-design.md`
- Replace §13.4 pair/record operations table with the new §13.4 text from §5b
- `do` keyword: confirm it is in the keyword list (believed present)

### PR 4 Acceptance Criteria

1. `(let [(pair s cmd) (authenticate state cred)] ...)` type-checks with `s : AppState`, `cmd : Command`
2. `(match ... [(pair s cmd) ...])` type-checks identically
3. All existing simple `(let [(x expr)] body)` programs compile — zero regressions
4. Nested: `(let [(pair word (pair g rest)) state] ...)` type-checks, binding `word`, `g`, `rest` with correct component types
5. JSON-AST files with `"name"` binding keys parse correctly via backward-compat path
6. `stack build` — no `-Wincomplete-patterns` for `emitPat` or `inferExpr (ELet ...)`
7. `stack test` regression suite passes

---

## PR Ordering Summary

```
PR 1 (TPair)  ──► PR 2 (DoStep + TC)  ──► PR 3 (emitDo rewrite)
     │
     └──────────────────────────────────► PR 4 (ELet Pattern, parallel with 2/3)
```

| PR | Blocks | Parallel-safe with |
|----|--------|--------------------|
| PR 1 | PR 2, PR 3 (must precede) | Nothing — do first |
| PR 2 | PR 3 (ADT dependency) | PR 4 (different AST node) |
| PR 3 | nothing | PR 4 |
| PR 4 | must not merge before PR 1 | PR 2, PR 3 |

---

## Verification Plan

### After PR 1
```bash
cd compiler
stack build 2>&1 | grep -i "incomplete\|warning\|error"
llmll check examples/hangman_json/hangman.ast.json
llmll check examples/tictactoe_json/tictactoe.ast.json
llmll build --emit json-ast examples/hangman_sexp/hangman.llmll
```

### After PR 2
```bash
# Expect "do-step-type-error" on bad step:
echo '{"kind":"do","steps":[{"kind":"do-step","expr":{"kind":"app","fn":"wasi.io.stdout","args":[{"kind":"lit-string","value":"hi"}]}}]}' | llmll check --stdin

# Expect sketch pointer with step index:
llmll typecheck --sketch examples/do_sketch_test.ast.json | jq '.sketchHoles[0].pointer'
# Must match: "/statements/0/body/steps/0/args/1"
```

### After PR 3
```bash
llmll build examples/do_two_step.llmll
# Inspect generated src/Lib.hs — must contain "let {" not "do {"
grep -c "do {" compiler/generated/do_two_step/src/Lib.hs  # must be 0
stack test  # all examples pass
```

### After PR 4
```bash
llmll check examples/pair_destructure_let.llmll
llmll check examples/pair_destructure_match.llmll
llmll check examples/pair_destructure_nested.llmll
# Existing files must still pass:
llmll check examples/hangman_sexp/hangman.llmll
stack test
```
