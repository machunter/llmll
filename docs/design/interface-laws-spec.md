# `def-interface :laws` — Formal Specification

> **Status:** Proposed (v0.6.2)  
> **Date:** 2026-04-24  
> **Authors:** Language Team  
> **Implements:** compiler-team-roadmap.md § v0.6.2 "Algebraic Laws"  
> **Prerequisite:** v0.6.1 shipped (TOTP benchmark, crypto builtins, hub query)

---

## 1. Motivation

LLMLL can currently verify **per-function** contracts: preconditions and postconditions on individual `def-logic` / `letrec` functions. What it cannot express are **cross-function algebraic relationships** — properties that hold between two or more functions in an interface.

Examples of algebraic laws:

| Law | Property |
|-----|----------|
| **Round-trip** | `decode(encode(x)) = Ok(x)` |
| **Idempotency** | `normalize(normalize(x)) = normalize(x)` |
| **Commutativity** | `merge(a, b) = merge(b, a)` |
| **Associativity** | `combine(combine(a, b), c) = combine(a, combine(b, c))` |
| **Identity** | `combine(x, empty) = x` |
| **Conservation** | `total-supply(transfer(s, from, to, amt)) = total-supply(s)` |

These laws cannot be expressed as `pre`/`post` contracts because they span multiple function signatures. They require a **quantified property over the interface's method set**.

### 1.1 Design Principle

`:laws` clauses are **first-class algebraic properties attached to an interface**. They compile to QuickCheck properties for testing and generate proof obligations for Leanstral. They are the interface-level analog of function-level `pre`/`post` contracts.

---

## 2. Surface Syntax

### 2.1 S-Expression Form

```lisp
(def-interface Codec
  [encode (fn [x: a] → string)]
  [decode (fn [s: string] → Result[a, string])]
  :laws
  [(for-all [x: int]
     (= (match (decode (encode x))
          ((Success v) (= v x))
          ((Error _) false))
        true))])
```

**Grammar extension** (EBNF, extends §13):

```ebnf
(* Current *)
def-interface = "(" "def-interface" IDENT { iface-fn } ")" ;

(* Proposed *)
def-interface = "(" "def-interface" IDENT { iface-fn } [ ":laws" "[" { law-clause } "]" ] ")" ;

law-clause    = "(" "for-all" "[" { typed-param } "]" expr ")" ;
```

**Key design decisions:**

1. **`:laws` is a keyword, not positional.** It always appears after all `iface-fn` declarations.
2. **Each law is a `for-all` block.** This reuses the existing `Property` infrastructure from `check` blocks — the law body must be a boolean expression.
3. **Laws can reference all interface methods** by name. The interface method signatures are in scope within each law body.
4. **Type variables** (e.g., `a` in `Codec`) are universally quantified at the interface level. Within `:laws`, concrete test types are instantiated by the test generator (see §5.2).

### 2.2 JSON-AST Form

```json
{
  "kind": "def-interface",
  "name": "Codec",
  "methods": [
    {"name": "encode", "fn_type": {"kind": "fn-type", "params": [...], "return_type": ...}},
    {"name": "decode", "fn_type": {"kind": "fn-type", "params": [...], "return_type": ...}}
  ],
  "laws": [
    {
      "kind": "for-all",
      "bindings": [{"name": "x", "param_type": {"kind": "primitive", "name": "int"}}],
      "body": { ... }
    }
  ]
}
```

This is already the schema produced by `AstEmit.hs` — the `"laws"` field is emitted when non-empty (line 83 of current `AstEmit.hs`).  The `ParserJSON.hs` already parses `"laws"` as `o .:? "laws" .!= [] >>= mapM parseExpr` (line 145).

**Change required:** Each law in the JSON-AST `"laws"` array should be a `for-all` object (with `"kind": "for-all"`, `"bindings"`, `"body"`), not a bare expression. This matches the `check` block schema. The parser must accept the `for-all` wrapper. 

### 2.3 Worked Examples

#### Example 1: Codec round-trip

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

#### Example 2: Monoid laws

```lisp
(def-interface Monoid
  [empty  (fn [] → a)]
  [combine (fn [x: a y: a] → a)]
  :laws
  [(for-all [x: int]
     (= (combine x (empty)) x))
   (for-all [x: int]
     (= (combine (empty) x) x))
   (for-all [x: int y: int z: int]
     (= (combine (combine x y) z)
        (combine x (combine y z))))])
```

#### Example 3: Idempotent normalizer

```lisp
(def-interface Normalizer
  [normalize (fn [x: string] → string)]
  :laws
  [(for-all [x: string]
     (= (normalize (normalize x))
        (normalize x)))])
```

---

## 3. Typing Rules

### 3.1 Well-Formedness (LAWS-WF)

A `:laws` clause is well-formed iff:

```
Γ = { f₁ : τ₁, f₂ : τ₂, ..., fₙ : τₙ }    (interface method signatures)
Δ = { x₁ : σ₁, ..., xₖ : σₖ }              (for-all bindings)

Γ, Δ ⊢ body : bool
────────────────────────────────────────────
⊢ (for-all [x₁:σ₁ ... xₖ:σₖ] body) : Law
```

**Informally:** The law body must type-check to `bool` when the interface methods and the for-all bindings are in scope.

### 3.2 Implementation in `TypeCheck.hs`

The current implementation (line 512–526) already does this:

```haskell
checkStatement (SDefInterface name fns _laws) = do
  -- Register interface function signatures
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $ "interface '" <> name <> "' function '" <> fname
        <> "' must have fn type, got " <> typeLabel other
  -- v0.6: type-check :laws expressions (must be Bool under interface context)
  forM_ _laws $ \lawExpr -> do
    let ifaceBindings = fns  -- interface method signatures as env
    lawType <- withEnv ifaceBindings (inferExpr lawExpr)
    unless (compatibleWith lawType TBool) $
      tcError $ "interface '" <> name <> "' :laws clause must be bool, got " <> typeLabel lawType
```

**What must change for v0.6.2:**

1. **Each law is a `Property`, not a bare `Expr`.** The parser must produce `[Property]` (not `[Expr]`), and the type-checker must bring the `for-all` bindings into scope alongside the interface methods.

2. **Type variable instantiation.** When a law references a type variable `a` from the interface, and the `for-all` binding uses a concrete type (`int`), the substitution must flow through. The existing U-Lite per-call-site substitution already handles this.

**Proposed `checkStatement` update:**

```haskell
checkStatement (SDefInterface name fns laws) = do
  -- Register interface function signatures
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $ "..."
  -- v0.6.2: type-check :laws as Properties (for-all bindings + bool body)
  forM_ laws $ \(Property desc bindings body) -> do
    let ifaceBindings = fns  -- interface method signatures
    withEnv ifaceBindings $ withEnv bindings $ do
      bodyType <- inferExpr body
      unless (compatibleWith bodyType TBool) $
        tcError $ "interface '" <> name <> "' law '" <> desc
          <> "' must be bool, got " <> typeLabel bodyType
```

### 3.3 Scoping Rules

| Name | In scope? | Source |
|------|-----------|--------|
| Interface methods (`encode`, `decode`) | ✅ | `defInterfaceFns` |
| For-all bindings (`x`, `y`, `z`) | ✅ | `propBindings` of each law |
| Top-level `def-logic` functions | ✅ | Already in `tcEnv` from `checkStatements` first pass |
| Built-in functions (`=`, `list-length`, etc.) | ✅ | `builtinEnv` |
| `result` keyword | ❌ | Only available in `post` clauses |

### 3.4 Error Diagnostics

| Condition | Diagnostic | Code |
|-----------|-----------|------|
| Law body does not type-check to `bool` | `interface 'Codec' law 'round-trip' must be bool, got int` | `E020` |
| Law references an undefined name | `unbound variable 'encodee' (may be in scope at runtime)` | existing `W001` |
| For-all binding uses a type not supported by QuickCheck | `law 'round-trip': no Arbitrary instance for type Codec` | `W620` (new) |
| `:laws` without any `for-all` blocks | `interface 'Codec' :laws requires at least one (for-all ...) clause` | `E021` |

---

## 4. AST Representation

### 4.1 Change to `Syntax.hs`

```haskell
-- Current:
| SDefInterface
    { defInterfaceName :: Name
    , defInterfaceFns  :: [(Name, Type)]
    , defInterfaceLaws :: [Expr]          -- v0.6: optional :laws clauses
    }

-- Proposed:
| SDefInterface
    { defInterfaceName :: Name
    , defInterfaceFns  :: [(Name, Type)]
    , defInterfaceLaws :: [Property]      -- v0.6.2: laws are Properties (for-all + body)
    }
```

This is a **breaking AST change** — all pattern matches on `SDefInterface` must be updated. The `Property` type already exists and captures exactly the right structure: a description, a list of typed bindings, and a boolean body.

### 4.2 Affected Modules (exhaustive)

| Module | Current pattern | Update |
|--------|----------------|--------|
| `Syntax.hs` | `defInterfaceLaws :: [Expr]` | → `[Property]` |
| `Parser.hs` | `pure $ SDefInterface name fns []` | Parse `:laws` with `for-all` |
| `ParserJSON.hs` | `laws <- o .:? "laws" .!= [] >>= mapM parseExpr` | `mapM parseForAll` |
| `AstEmit.hs` | `"laws" .= map exprToJson laws` | `"laws" .= map propertyToJson laws` |
| `TypeCheck.hs` | `forM_ _laws $ \lawExpr -> ...` | Bring for-all bindings into scope |
| `CodegenHs.hs` | `emitStmt (SDefInterface name fns _laws) = emitInterface name fns` | Emit QuickCheck properties |
| `HoleAnalysis.hs` | `collectHolesStmtIdx _idx (SDefInterface _ _ _) = []` | No change (laws don't contain holes) |
| `Module.hs` | `toExport (SDefInterface name _ _) = ...` | No change |
| `SpecCoverage.hs` | Does not reference laws | Laws count toward interface contract coverage |

---

## 5. Code Generation

### 5.1 QuickCheck Property Emission

Each law compiles to a standalone QuickCheck property in the generated `Lib.hs`:

**Input:**
```lisp
(def-interface Normalizer
  [normalize (fn [x: string] → string)]
  :laws
  [(for-all [x: string]
     (= (normalize (normalize x))
        (normalize x)))])
```

**Generated Haskell:**
```haskell
-- def-interface Normalizer: law 1 (idempotency)
prop_Normalizer_law_1 :: String -> Bool
prop_Normalizer_law_1 x =
  (normalize (normalize x)) == (normalize x)
```

### 5.2 Type Variable Instantiation

When an interface has type variables (`a` in `Codec`), and a law uses a concrete type in its `for-all` bindings (`x: int`), codegen emits the property with the concrete type:

```lisp
(def-interface Codec
  [encode (fn [x: a] → string)]
  [decode (fn [s: string] → Result[a, string])]
  :laws
  [(for-all [x: int]
     ...)])
```

Generates:
```haskell
prop_Codec_law_1 :: Int -> Bool
prop_Codec_law_1 x = ...
```

**Design decision:** The concrete type in the `for-all` binding determines the test instantiation. If the user wants to test with multiple types, they write multiple laws:

```lisp
:laws
[(for-all [x: int]    (= (decode (encode x)) (ok x)))
 (for-all [x: string] (= (decode (encode x)) (ok x)))]
```

This is explicit, auditable, and avoids the complexity of a multi-instance type class dispatch.

### 5.3 `emitInterface` Update

```haskell
-- Current:
emitInterface :: Name -> [(Name, Type)] -> Text

-- Proposed:
emitInterface :: Name -> [(Name, Type)] -> [Property] -> Text
```

The function emits the typeclass declaration (unchanged) followed by one `prop_` function per law.

---

## 6. Verification Integration

### 6.1 Verification Level for Laws

Laws follow the same stratified verification model as function contracts:

| Level | When assigned | Mechanism |
|-------|--------------|-----------|
| `tested` | Default | QuickCheck (100+ samples per law) |
| `proven` | After Leanstral | Lean 4 proof of the universally-quantified statement |
| `asserted` | Fallback | Runtime only (if test infrastructure is not invoked) |

### 6.2 `--spec-coverage` Interaction

Laws **do not count** toward the function-level `effective_coverage` metric. They are a separate dimension:

```
Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     4 / 7   (57%)
    Proven:                     2
    Tested:                     1
    Asserted:                   1
  Interface laws:               3 / 3 tested
    Normalizer:                 1 law (tested, 100 samples)
    Codec:                      2 laws (tested, 100 samples each)
  Effective coverage: 71% (5/7)
```

**Rationale:** Laws are interface-level properties, not function-level. Including them in `effective_coverage` would inflate the metric for modules that declare many interfaces but few function implementations.

### 6.3 Proof Obligations for Leanstral

Each law generates a Lean 4 theorem statement:

```lisp
;; LLMLL law
(for-all [x: int]
  (= (normalize (normalize x)) (normalize x)))
```

```lean
-- Generated Lean 4 theorem (mock / future)
theorem Normalizer_law_1 (x : Int) :
  normalize (normalize x) = normalize x := by
  sorry  -- proof obligation
```

This is handled by the existing `LeanTranslate.hs` pipeline (currently mock-only). No changes needed until Leanstral goes live.

---

## 7. Parser Changes

### 7.1 S-Expression Parser (`Parser.hs`)

The current `pDefInterface` (line 204–210) must be extended:

```haskell
-- Current:
pDefInterface :: Parser Statement
pDefInterface = do
  _ <- try (symbol "(" *> symbol "def-interface")
  name <- pIdent
  fns <- many (try pInterfaceFn)
  _ <- symbol ")"
  pure $ SDefInterface name fns []

-- Proposed:
pDefInterface :: Parser Statement
pDefInterface = do
  _ <- try (symbol "(" *> symbol "def-interface")
  name <- pIdent
  fns <- many (try pInterfaceFn)
  laws <- option [] pLawsClause
  _ <- symbol ")"
  pure $ SDefInterface name fns laws

pLawsClause :: Parser [Property]
pLawsClause = do
  _ <- symbol ":laws"
  brackets (many pLawForAll)

pLawForAll :: Parser Property
pLawForAll = parens $ do
  _ <- try (symbol "for-all") <|> (T.singleton <$> char '\x2200' <* sc)
  bindings <- brackets (many pTypedParam)
  body <- pExpr
  pure $ Property "" bindings body
```

### 7.2 JSON-AST Parser (`ParserJSON.hs`)

The current `parseDefInterface` (line 141–146) must change:

```haskell
-- Current:
parseDefInterface o = do
  name    <- o .: "name"
  methods <- o .: "methods" >>= mapM parseIfaceMethod
  laws    <- o .:? "laws" .!= [] >>= mapM parseExpr
  pure $ SDefInterface name methods laws

-- Proposed:
parseDefInterface o = do
  name    <- o .: "name"
  methods <- o .: "methods" >>= mapM parseIfaceMethod
  laws    <- o .:? "laws" .!= [] >>= mapM parseLawProperty
  pure $ SDefInterface name methods laws

parseLawProperty :: Value -> Parser Property
parseLawProperty = withObject "LawProperty" $ \o -> do
  bindings <- o .: "bindings" >>= mapM parseTypedParam
  body     <- o .: "body"     >>= parseExpr
  desc     <- o .:? "description" .!= ""
  pure $ Property desc bindings body
```

### 7.3 JSON-AST Emitter (`AstEmit.hs`)

The current law emission (line 77–86) must be updated:

```haskell
-- Current:
stmtToJson (SDefInterface name fns laws) =
  object $
    [ ... ]
    ++ if null laws then [] else ["laws" .= map exprToJson laws]

-- Proposed:
stmtToJson (SDefInterface name fns laws) =
  object $
    [ ... ]
    ++ if null laws then [] else ["laws" .= map lawToJson laws]
  where
    lawToJson (Property desc bindings body) = object $
      [ "kind"     .= ("for-all" :: Text)
      , "bindings" .= map typedParamToJson bindings
      , "body"     .= exprToJson body
      ] ++ if T.null desc then [] else ["description" .= desc]
```

---

## 8. Backward Compatibility

### 8.1 AST Change

The `defInterfaceLaws :: [Expr] → [Property]` change is **AST-breaking**. All existing code that pattern-matches on `SDefInterface` must be updated. However:

- No existing LLMLL program uses `:laws` (the field is always `[]` in current code).
- The S-expression parser currently produces `SDefInterface name fns []`.
- The JSON-AST parser accepts `"laws": []` and produces `[]`.

**Migration:** Replace `[Expr]` with `[Property]` in `Syntax.hs`. All pattern match sites already ignore laws (using `_laws`), so the update is mechanical.

### 8.2 JSON-AST Schema

The `"laws"` field changes from `[Expr]` to `[ForAllObject]`. Since no existing JSON-AST uses laws, this is non-breaking in practice. The schema version should remain `"0.3.0"` (no schema bump needed — laws were always defined in the schema, just unused).

### 8.3 Test Impact

All 279 existing Haskell tests pass unchanged. The `_laws` pattern variable absorbs both `[Expr]` and `[Property]` at the match site.

---

## 9. Open Questions for Compiler Team

> **Q1: Should law descriptions be auto-generated or user-provided?**
>
> The `Property` type has a `propDescription :: Text` field. For `check` blocks, users write the description (`"Addition is commutative"`). For laws, we could:
> - (A) Require explicit descriptions: `(for-all "round-trip" [x: int] ...)`
> - (B) Auto-number: `"Codec_law_1"`, `"Codec_law_2"`
> - (C) Accept optional descriptions: `(for-all [x: int] ...)` auto-numbers, `(for-all "name" [x: int] ...)` uses the name
>
> **Language Team recommendation:** Option (C). Auto-numbering is low-friction for early adoption; explicit names are better for documentation.

> **Q2: Should laws be run by `llmll test` or `llmll verify`?**
>
> Laws are QuickCheck properties — they belong to the testing phase. But they are *interface-level* properties, not function-level. Options:
> - (A) `llmll test` runs all laws alongside `check` blocks
> - (B) `llmll verify --laws` runs laws separately
> - (C) Both: `llmll test` runs laws; `llmll verify --spec-coverage` reports their status
>
> **Language Team recommendation:** Option (C). Laws are testable properties; they should run with `test`. Coverage reporting is a `verify` concern.

> **Q3: What happens when an interface has laws but no implementation?**
>
> An interface with `:laws` but no implementing `def-logic` functions in the module is valid — the laws are structural declarations. They become testable only when an implementation exists in a module that uses the interface.
>
> This is analogous to Haskell typeclasses: the class declares laws, instances implement them, and QuickCheck tests the instances.

> **Q4: Where-clause constraints in law bindings?**
>
> Can a law's `for-all` binding use a dependent type?
> ```lisp
> (for-all [x: PositiveInt] ...)
> ```
> **Yes** — this reuses the existing `gen` infrastructure. If `PositiveInt` has a registered `gen`, it is used. Otherwise, rejection sampling applies. No special handling needed.

---

## 10. Acceptance Criteria

### 10.1 Parser

- [ ] S-expression parser accepts `(def-interface Name [fn-sigs] :laws [(for-all ...)])` and produces `SDefInterface` with `[Property]` laws
- [ ] S-expression parser accepts `(def-interface Name [fn-sigs])` (no `:laws`) and produces `SDefInterface` with `[]` laws (backward compat)
- [ ] JSON-AST parser accepts `"laws": [{"kind": "for-all", ...}]` and produces matching `[Property]`
- [ ] JSON-AST emitter round-trips: `parseJSONAST(emitJsonAST(stmts)) == stmts` for programs with laws

### 10.2 Type Checker

- [ ] Law body is type-checked to `bool` with interface methods + for-all bindings in scope
- [ ] Type error emitted if law body is non-bool
- [ ] Interface methods callable within law body (substitution works)
- [ ] Unbound variable in law body produces existing warning

### 10.3 Code Generation

- [ ] Each law emits a `prop_InterfaceName_law_N` QuickCheck property
- [ ] Generated property compiles and runs with `stack test`
- [ ] Type variable instantiation works (concrete types in for-all → concrete property)

### 10.4 Spec Coverage

- [ ] `--spec-coverage` reports interface laws as a separate section
- [ ] Laws do not inflate `effective_coverage`

### 10.5 Regression

- [ ] All 279 existing tests pass
- [ ] All 3 verifier examples (`hangman`, `tictactoe`, `conways_life`) build with 0 errors
- [ ] ERC-20 and TOTP benchmarks build with 0 errors

---

## 11. Test Plan

### 11.1 New Test Cases

| Test | Input | Expected |
|------|-------|----------|
| `laws_parse_basic` | `(def-interface M [f (fn [x: int] → int)] :laws [(for-all [x: int] (= (f x) (f x)))])` | Parses to `SDefInterface "M" [("f", TFn [TInt] TInt)] [Property "" [("x", TInt)] ...]` |
| `laws_parse_empty` | `(def-interface M [f (fn [x: int] → int)])` | Parses to `SDefInterface "M" [...] []` |
| `laws_parse_multiple` | Three laws | All three parsed |
| `laws_typecheck_ok` | Round-trip law referencing interface methods | 0 errors |
| `laws_typecheck_nonbool` | Law body returns `int` | Error `E020` |
| `laws_typecheck_unbound` | Law references undefined name | Warning |
| `laws_json_roundtrip` | Emit → parse → compare | Exact match |
| `laws_codegen_prop` | Single law | Generated `prop_` function compiles |
| `laws_codegen_multi` | Three laws | Three `prop_` functions |
| `laws_coverage_separate` | Module with laws + functions | Laws in separate report section |

### 11.2 Effort Estimate

| Component | Est. hours |
|-----------|-----------|
| `Syntax.hs` (`[Expr]` → `[Property]`) + mechanical fixes | 1 |
| `Parser.hs` (`:laws` clause) | 2 |
| `ParserJSON.hs` (for-all object) | 1 |
| `AstEmit.hs` (property round-trip) | 1 |
| `TypeCheck.hs` (for-all scoping) | 2 |
| `CodegenHs.hs` (QuickCheck emission) | 3 |
| `SpecCoverage.hs` (law reporting) | 2 |
| Tests (11 new) | 3 |
| **Total** | **~15 hours** |

---

## 12. Future Work (Not In Scope)

- **Law inheritance across modules:** When module B imports an interface from module A, B's implementations should satisfy A's laws. This requires cross-module law propagation — deferred to v0.7.
- **Law-driven type-class deriving:** Auto-generating implementation strategies from law shapes (e.g., recognizing monoidal structure). Research track.
- **Negative laws (counter-examples):** `(for-all [x: int] (not (= (encode x) "")))` — currently expressible, but counter-example reporting could be improved. Future tooling.
