# Compiler Team Brief: `def-interface :laws` (v0.6.2)

> **Date:** 2026-04-24  
> **Source:** Language Team formal specification → [`docs/design/interface-laws-spec.md`](design/interface-laws-spec.md)  
> **Ticket:** v0.6.2 `def-interface :laws` (roadmap line 54–65)  
> **Estimated effort:** ~15 hours across 8 modules  
> **Priority:** P0 for v0.6.2 — this is the headline feature

---

## What This Is

First-class algebraic law enforcement on `def-interface`. Laws are quantified boolean properties that span multiple interface methods — round-trip guarantees, idempotency, commutativity, conservation invariants. They compile to QuickCheck properties and (future) Lean 4 proof obligations.

**Before (v0.6.1):** Interfaces declare method signatures. You can verify individual functions. You cannot express "decode(encode(x)) = x" as part of the interface contract.

**After (v0.6.2):**

```lisp
(def-interface Codec
  [encode (fn [x: a] → string)]
  [decode (fn [s: string] → Result[a, string])]
  :laws
  [(for-all [x: int]
     (match (decode (encode x))
       ((Success v) (= v x))
       ((Error _) false)))])
```

Each law emits a `prop_Codec_law_1` QuickCheck property in the generated Haskell.

---

## The One AST Change

**This is the breaking change. Everything else follows from it.**

```haskell
-- Syntax.hs line 309-313
-- BEFORE:
| SDefInterface
    { defInterfaceName :: Name
    , defInterfaceFns  :: [(Name, Type)]
    , defInterfaceLaws :: [Expr]           -- v0.6: bare expressions
    }

-- AFTER:
| SDefInterface
    { defInterfaceName :: Name
    , defInterfaceFns  :: [(Name, Type)]
    , defInterfaceLaws :: [Property]       -- v0.6.2: for-all properties
    }
```

`Property` already exists in `Syntax.hs` (line 278–282) — it's the type used by `SCheck` blocks:

```haskell
data Property = Property
  { propDescription :: Text
  , propBindings    :: [(Name, Type)]
  , propBody        :: Expr
  } deriving (Show, Eq, Generic)
```

This is the right representation: a law is a for-all quantified boolean body with typed bindings — identical structure to a `check` block.

---

## Implementation Tickets

### LAWS-1: `Syntax.hs` — AST change [CT]

**Change:** `defInterfaceLaws :: [Expr]` → `defInterfaceLaws :: [Property]`

**Mechanical fallout:** Every pattern match on `SDefInterface` must be updated. All current sites use `_laws` (ignoring the field), so this is a type-signature fix, not a logic change.

| File | Line | Current | Update |
|------|------|---------|--------|
| `TypeCheck.hs` | 448 | `collectTopLevel (SDefInterface name fns _laws)` | No logic change — `_laws` absorbs `[Property]` |
| `TypeCheck.hs` | 512 | `checkStatement (SDefInterface name fns _laws)` | **Logic change** (see LAWS-4) |
| `CodegenHs.hs` | 388 | `emitStmt (SDefInterface name fns _laws)` | **Logic change** (see LAWS-5) |
| `AstEmit.hs` | 77 | `stmtToJson (SDefInterface name fns laws)` | **Logic change** (see LAWS-6) |
| `HoleAnalysis.hs` | 151 | `collectHolesStmtIdx _idx (SDefInterface _ _ _)` | No change |
| `Module.hs` | 235 | `s@SDefInterface{}` | No change |
| `Module.hs` | 257 | `toExport (SDefInterface name _ _)` | No change |
| `SpecCoverage.hs` | 139 | Does not reference `SDefInterface` | No change |
| `ParserJSON.hs` | 146 | `SDefInterface name methods laws` | **Logic change** (see LAWS-3) |
| `Parser.hs` | 210 | `SDefInterface name fns []` | **Logic change** (see LAWS-2) |

**Acceptance:** `stack build` compiles with 0 errors after all downstream modules are updated.

---

### LAWS-2: `Parser.hs` — S-expression parsing [CT]

**Current (line 204–210):**
```haskell
pDefInterface = do
  _ <- try (symbol "(" *> symbol "def-interface")
  name <- pIdent
  fns <- many (try pInterfaceFn)
  _ <- symbol ")"
  pure $ SDefInterface name fns []
```

**Proposed:**
```haskell
pDefInterface = do
  _ <- try (symbol "(" *> symbol "def-interface")
  name <- pIdent
  fns <- many (try pInterfaceFn)
  laws <- option [] pLawsClause
  _ <- symbol ")"
  pure $ SDefInterface name fns laws

-- | Parse :laws [(for-all [...] body) ...]
pLawsClause :: Parser [Property]
pLawsClause = do
  _ <- symbol ":laws"
  brackets (many pLawForAll)

-- | Parse a single law: (for-all [bindings] body) or (∀ [bindings] body)
pLawForAll :: Parser Property
pLawForAll = parens $ do
  _ <- try (symbol "for-all") <|> (T.singleton <$> char '\x2200' <* sc)
  bindings <- brackets (many pTypedParam)
  body <- pExpr
  pure $ Property "" bindings body
```

**Why `Property "" bindings body`:** The description field is empty by default (auto-numbered in codegen). Optional named laws (`(for-all "round-trip" [x: int] ...)`) are a future extension — not in scope for v0.6.2. See formal spec §9 Q1.

**Backward compat:** `option [] pLawsClause` means `(def-interface Name [fn-sigs])` without `:laws` still produces `SDefInterface name fns []`. All existing programs parse unchanged.

**Acceptance:**
- `(def-interface M [f (fn [x: int] → int)] :laws [(for-all [x: int] (= (f x) (f x)))])` parses successfully
- `(def-interface M [f (fn [x: int] → int)])` still parses (empty laws)
- Parse error on `:laws` without brackets or without `for-all`

---

### LAWS-3: `ParserJSON.hs` — JSON-AST parsing [CT]

**Current (line 141–146):**
```haskell
parseDefInterface o = do
  name    <- o .: "name"
  methods <- o .: "methods" >>= mapM parseIfaceMethod
  laws    <- o .:? "laws" .!= [] >>= mapM parseExpr
  pure $ SDefInterface name methods laws
```

**Proposed:**
```haskell
parseDefInterface o = do
  name    <- o .: "name"
  methods <- o .: "methods" >>= mapM parseIfaceMethod
  laws    <- o .:? "laws" .!= [] >>= mapM parseLawProperty
  pure $ SDefInterface name methods laws

-- | Parse a law from JSON-AST:
-- { "kind": "for-all", "bindings": [...], "body": {...} }
-- Optional "description" field for named laws.
parseLawProperty :: Value -> Parser Property
parseLawProperty = withObject "LawProperty" $ \o -> do
  bindings <- o .: "bindings" >>= mapM parseTypedParam
  body     <- o .: "body"     >>= parseExpr
  desc     <- o .:? "description" .!= ""
  pure $ Property desc bindings body
```

**Note:** The `"kind": "for-all"` field is present in the JSON but not consumed — it's there for schema self-description. This matches the existing `check`/`for_all` pattern where `parseForAll` also doesn't validate the kind.

**Acceptance:** Round-trip test — `parseJSONAST(emitJsonAST(stmts)) == stmts` for programs with laws.

---

### LAWS-4: `TypeCheck.hs` — Type checking [CT]

**Current (line 512–526):**
```haskell
checkStatement (SDefInterface name fns _laws) = do
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $ ...
  forM_ _laws $ \lawExpr -> do
    let ifaceBindings = fns
    lawType <- withEnv ifaceBindings (inferExpr lawExpr)
    unless (compatibleWith lawType TBool) $
      tcError $ "interface '" <> name <> "' :laws clause must be bool, got " <> typeLabel lawType
```

**Proposed:**
```haskell
checkStatement (SDefInterface name fns laws) = do
  -- Register interface function signatures
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $
        "interface '" <> name <> "' function '" <> fname
        <> "' must have fn type, got " <> typeLabel other
  -- v0.6.2: type-check :laws as Properties
  -- Each law's for-all bindings + interface methods are in scope
  forM_ laws $ \(Property _desc bindings body) -> do
    let ifaceBindings = fns
    withEnv ifaceBindings $ withEnv bindings $ do
      bodyType <- inferExpr body
      unless (compatibleWith bodyType TBool) $
        tcError $ "interface '" <> name <> "' :laws clause must be bool, got " <> typeLabel bodyType
```

**What changed:** The for-all bindings (`[(Name, Type)]`) are now brought into scope alongside the interface methods. Previously, laws were bare expressions — bindings were absent.

**Scoping rules (from formal spec §3.3):**
- Interface methods: ✅ in scope
- For-all bindings: ✅ in scope
- Top-level `def-logic` functions: ✅ already in `tcEnv` from `checkStatements`
- Built-ins: ✅ from `builtinEnv`
- `result` keyword: ❌ not available (only in `post` clauses)

**Acceptance:**
- Law referencing interface methods type-checks with 0 errors
- Law body returning `int` → error
- Law referencing undefined name → warning (existing behavior)

---

### LAWS-5: `CodegenHs.hs` — QuickCheck emission [CT]

**This is the largest change.**

**Current (line 388):**
```haskell
emitStmt (SDefInterface name fns _laws) = emitInterface name fns
```

**Proposed:**
```haskell
emitStmt (SDefInterface name fns laws) = emitInterface name fns laws
```

**Update `emitInterface` (line 457–464):**

```haskell
-- BEFORE:
emitInterface :: Name -> [(Name, Type)] -> Text
emitInterface name fns = T.unlines $
  [ "class " <> toHsIdent name <> " t where" ]
  ++ map emitMethod fns
  ++ [ "" ]

-- AFTER:
emitInterface :: Name -> [(Name, Type)] -> [Property] -> Text
emitInterface name fns laws = T.unlines $
  [ "class " <> toHsIdent name <> " t where" ]
  ++ map emitMethod fns
  ++ [ "" ]
  ++ concatMap (emitLaw name) (zip [1..] laws)
  where
    emitMethod (fname, ftype) =
      "  " <> toHsIdent fname <> " :: t -> " <> emitFnType ftype

-- | Emit a single interface law as a QuickCheck property.
emitLaw :: Name -> (Int, Property) -> [Text]
emitLaw ifaceName (idx, Property _desc bindings body) =
  let propName = "prop_" <> toHsIdent ifaceName <> "_law_" <> tshow idx
      paramNames = T.unwords (map (toHsIdent . fst) bindings)
      paramTypes = map (toHsType . snd) bindings
      sig = propName <> " :: " <> T.intercalate " -> " (paramTypes ++ ["Bool"])
      def = propName <> " " <> paramNames <> " = " <> emitExpr body
  in [ "-- " <> toHsIdent ifaceName <> " law " <> tshow idx
     , sig
     , def
     , ""
     ]
  where
    tshow :: Show a => a -> Text
    tshow = T.pack . show
```

**Generated output example:**

```haskell
class Normalizer t where
  normalize :: t -> String -> String

-- Normalizer law 1
prop_Normalizer_law_1 :: String -> Bool
prop_Normalizer_law_1 x = (normalize (normalize x)) == (normalize x)
```

**Edge case — type variables:** When a law uses a concrete type (`x: int`) but the interface method has a type variable (`a`), the per-call-site substitution in `emitExpr` handles this. The property is monomorphic at the concrete type. No special handling needed in codegen.

**Acceptance:**
- Single law → one `prop_` function in generated Haskell
- Three laws → three `prop_` functions
- Generated code compiles with `stack build`
- Generated properties run with `stack test`

---

### LAWS-6: `AstEmit.hs` — JSON-AST round-trip [CT]

**Current (line 77–86):**
```haskell
stmtToJson (SDefInterface name fns laws) =
  object $
    [ "kind"    .= ("def-interface" :: Text)
    , "name"    .= name
    , "methods" .= map ifaceMethodToJson fns
    ] ++
    if null laws then [] else ["laws" .= map exprToJson laws]
```

**Proposed:**
```haskell
stmtToJson (SDefInterface name fns laws) =
  object $
    [ "kind"    .= ("def-interface" :: Text)
    , "name"    .= name
    , "methods" .= map ifaceMethodToJson fns
    ] ++
    if null laws then [] else ["laws" .= map lawToJson laws]
  where
    ifaceMethodToJson (n, ty) =
      object ["name" .= n, "fn_type" .= typeToJson ty]
    lawToJson (Property desc bindings body) = object $
      [ "kind"     .= ("for-all" :: Text)
      , "bindings" .= map typedParamToJson bindings
      , "body"     .= exprToJson body
      ] ++ if T.null desc then [] else ["description" .= desc]
```

**Acceptance:** `parseJSONAST fp (emitJsonAST stmts) == Right stmts` for programs containing laws.

---

### LAWS-7: `SpecCoverage.hs` — Coverage reporting [CT]

Laws should appear in `--spec-coverage` output as a **separate section** — they do NOT count toward `effective_coverage` (which is a function-level metric).

**Change in `formatCoverageText`:** Add a section after the "Intentional Underspecification" block:

```
  Interface laws:               3 / 3 tested
    Normalizer:                 1 law (tested)
    Codec:                      2 laws (tested)
```

**Implementation:** The `runCoverage` function takes `[Statement]`. Extract `SDefInterface` nodes with non-empty laws. Count them. Report in text and JSON output.

This is additive — no existing coverage logic changes.

**Acceptance:** `--spec-coverage` output includes law counts when laws exist.

---

### LAWS-8: Tests [CT]

| # | Test | Input | Expected |
|---|------|-------|----------|
| T1 | `laws_parse_basic` | S-expr with one law | `SDefInterface` with `[Property]` |
| T2 | `laws_parse_empty` | S-expr without `:laws` | `SDefInterface` with `[]` |
| T3 | `laws_parse_multiple` | S-expr with 3 laws | 3 `Property` entries |
| T4 | `laws_typecheck_ok` | Round-trip law referencing interface methods | 0 errors |
| T5 | `laws_typecheck_nonbool` | Law body returns `int` | Error |
| T6 | `laws_typecheck_unbound` | Law references undefined name | Warning |
| T7 | `laws_json_roundtrip` | Emit → parse → compare | Exact match |
| T8 | `laws_codegen_prop` | Single law | `prop_` function compiles |
| T9 | `laws_codegen_multi` | Three laws | Three `prop_` functions |
| T10 | `laws_coverage` | Module with laws + functions | Laws in separate report section |
| T11 | `laws_regression` | All 279 existing tests | 0 failures |

---

## Implementation Order

```
LAWS-1 (Syntax.hs)           ← do this first; everything else fails to compile until this lands
  │
  ├── LAWS-2 (Parser.hs)     ← unblocks S-expression input
  ├── LAWS-3 (ParserJSON.hs) ← unblocks JSON-AST input
  ├── LAWS-6 (AstEmit.hs)    ← unblocks round-trip test (T7)
  │
  └── LAWS-4 (TypeCheck.hs)  ← unblocks type-checking tests (T4-T6)
        │
        └── LAWS-5 (CodegenHs.hs) ← unblocks codegen tests (T8-T9)
              │
              └── LAWS-7 (SpecCoverage.hs) ← unblocks coverage test (T10)

LAWS-8 (Tests) — write alongside each ticket
```

**Suggested sprint plan:**

| Day | Work |
|-----|------|
| 1 (morning) | LAWS-1 + LAWS-2 + LAWS-3 + LAWS-6 (AST + parsers + emitter — all mechanical) |
| 1 (afternoon) | LAWS-4 (TypeCheck — scoping logic) + tests T1–T7 |
| 2 (morning) | LAWS-5 (CodegenHs — QuickCheck emission) + tests T8–T9 |
| 2 (afternoon) | LAWS-7 (SpecCoverage) + T10 + T11 regression sweep |

---

## What NOT to Do

1. **Don't change `defInterfaceLaws` to a new record type.** `Property` is exactly right — it's what `SCheck` uses, and laws are semantically identical to check blocks scoped to an interface.

2. **Don't add law descriptions to the S-expression syntax yet.** Keep `Property "" bindings body` for v0.6.2. Named laws are a v0.7 extension. The JSON-AST already supports an optional `"description"` field for future use.

3. **Don't try to make laws run automatically in `llmll build`.** Laws compile to `prop_` functions. They are tested by `llmll test` (existing QuickCheck infrastructure) or by `stack test`. The compiler's job is to emit them — the test runner's job is to execute them.

4. **Don't modify `SpecCoverage.effective_coverage`.** Laws are interface-level properties. Including them in the function-level metric would inflate coverage numbers. Report them separately.

5. **Don't touch `FixpointEmit.hs` or `LeanTranslate.hs`.** Liquid-fixpoint verification and Lean proof obligations for laws are future work. Laws are tested (QuickCheck) in v0.6.2, not proven.

---

## Open Decisions (Need Compiler Team Input)

These are listed in the formal spec §9. Language team has recommendations but wants compiler team perspective:

1. **Law descriptions (Q1):** Auto-number (`"Codec_law_1"`) or require user names? We recommend option C (optional — auto-number by default, allow explicit names). For v0.6.2, auto-numbering only.

2. **Test runner integration (Q2):** Laws should run with `llmll test`. Do we emit them as part of the existing `checkAll_` runner, or as separate `prop_` functions that require manual invocation? We recommend: emit as `prop_` functions (consistent with `check` block codegen) and add them to `checkAll_` if one exists.

3. **Interface-only modules (Q3):** An interface with `:laws` but no implementing functions in scope is valid (the laws are declarative). The generated `prop_` functions will reference undefined methods → GHC compile error. This is expected and correct — laws are only testable when an implementation exists. No special compiler handling needed.

---

## Reference

- **Formal specification:** [`docs/design/interface-laws-spec.md`](design/interface-laws-spec.md) — full typing rules, grammar, examples, and proof obligations
- **Roadmap entry:** [`docs/compiler-team-roadmap.md`](compiler-team-roadmap.md) line 54–65
- **Property type:** `Syntax.hs` line 278–282
- **Current interface type-checking:** `TypeCheck.hs` line 512–526
- **Current interface codegen:** `CodegenHs.hs` line 456–464
- **Check block pattern (reference implementation):** `Parser.hs` line 278–304 (`pCheckBlock` + `pForAll`)
