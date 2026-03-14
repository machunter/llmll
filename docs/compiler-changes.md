# LLMLL Compiler Changes — v0.1 → v0.1.1

This document covers every change made to the compiler's parser (`Parser.hs`),
entry point (`Main.hs`), and code generator (`Codegen.hs`) during the v0.1.1
development cycle.  Changes are grouped by file and ordered as they were applied.

---

## Parser.hs

### 1. `pSumTypeMultiArm` — ADT sum types with multiple arms

**What changed.** The original parser had no way to parse a type definition that
contained more than one `(| Ctor Payload)` arm as direct children of a `(type ...)`
block.

**Before.** Parsing `(type GameInput (| StartGame Word) (| Guess Letter))` would
fail because the type-body parser tried to read one arm and immediately returned.

**After.** A new parser `pSumTypeMultiArm` collects `some (try pSumArm)` (one or
more arms), joins the constructor names with `" | "` and wraps the result in
`TCustom "StartGame | Guess"`.  This label is later detected in `Codegen.hs`
(see §Codegen) and emitted as a Rust `enum`.

```lisp
;; Now parses correctly:
(type GameInput
  (| StartGame Word)
  (| Guess Letter))
```

---

### 2. `pGenDecl` — custom PBT generator declarations

**What changed.** `pStatement` had no branch for `(gen TypeName expr)`.

**Before.** A `gen` declaration at the top level caused a parse error
(`unexpected token "gen"`).

**After.** `pGenDecl` is added to `pStatement`'s `choice` list.  It parses
`(gen TypeName generatorExpr)` and stores the generator expression as `SExpr`
(the `Statement` AST has no `SGenDecl` arm yet; a proper arm is deferred to v0.2).
The registered name is discarded at this stage.

```lisp
;; Now parses correctly:
(gen Word (fn [n: int] (string-repeat "a" (+ n 1))))
```

---

### 3. `pDefParam` — untyped parameters in `def-logic`

**What changed.** Parameters in `def-logic` bodies were required to be
typed (`name: type`).  Bare names like `[s]` were not accepted.

**Before.** Accessor functions such as `(def-logic state-word [s] (first s))`
caused a parse error because `s` has no `: type` annotation.

**After.** `pDefParam` now tries `pTypedParam` first; if that fails it accepts any
identifier and assigns it the wildcard type `TCustom "_"`.

```haskell
pDefParam :: Parser (Name, Type)
pDefParam = try pTypedParam <|> do
  n <- pIdent
  pure (n, TCustom "_")
```

The wildcard propagates to Codegen (where `TCustom "_"` maps to `LlmllVal`) and
acts as a deferral note for v0.2 type inference.

---

### 4. `pFnExpr` — `fn` lambda in expression position

**What changed.** `(fn [params] body)` was only parseable at the statement
level as a `pFnType` (which produces a `Type`, not an `Expr`).  It could not appear
inside a `let` binding or as an argument.

**Before.** The hangman code's inline lambdas in `list_map` calls:

```lisp
(list-map chars (fn [c: string] (if (list-contains guessed c) c "_")))
```

failed with `unexpected "fn"` because `pExpr` had no branch for it.

**After.** `pFnExpr` is added as a `try` branch in `pExpr`:

```haskell
pFnExpr :: Parser Expr
pFnExpr = parens $ do
  _ <- try (symbol "fn") <|> (T.singleton <$> char '\x03BB' <* sc)
  params <- brackets (many pDefParam)
  _ <- optional (try (pArrowSym *> pType))  -- only consume '-> T' when present
  body <- pExpr
  pure $ ELambda params body
```

The key subtlety: the optional return-type annotation is guarded by `try
(pArrowSym *> pType)`.  Without the `try`, `pType` was consuming the first
identifier of the body expression (e.g. `(if ...)` is parsed as a type name
`if`, corrupting the parse).

---

### 5. `pPattern` — constructor patterns in `match` arms

**What changed.** Match case patterns like `((StartGame word) body)` were not
parsed correctly.  The pattern parser expected bare identifiers or literals; it did
not handle parenthesised constructor patterns.

**Before.**

```lisp
(match input
  ((StartGame word) (initialize-game word))
  ((Guess l)        (handle-guess state l)))
```

failed because `pPattern` did not look for `(Ctor arg...)`.

**After.** A `try $ parens $ ...` branch is added as the first option in
`pPattern`:

```haskell
pPattern = choice
  [ PWildcard <$ symbol "_"
  , try $ parens $ do          -- (Ctor arg1 arg2 ...) constructor pattern
      name <- pIdent
      args <- many pPattern
      pure $ PConstructor name args
  , PLiteral <$> pLiteral
  , PVar     <$> pIdent
  ]
```

---

### 6. `pTypeBody` dispatch order

`pTypeBody` now tries `pWhereType` first, then `pSumTypeMultiArm`, then falls
back to `pType`.  This ordering ensures that dependent types (`(where ...)`) and
multi-arm ADTs (`(| Ctor ...)`) are both recognised before the generic type
parser grabs the input.

---

## Main.hs

### Module support — the decision

> **This is the most significant architectural decision in this cycle.**

**Background.** LLMLL files can be either:

1. **Module-wrapped** — the entire file is enclosed in `(module name ...)`,
   optionally followed by `(import ...)` lines.
2. **Bare** — a sequence of top-level statements with no module wrapper.

The old compiler accepted only module-wrapped files.  `hangman_complete.llmll`
was originally written with a module wrapper **and** capability imports:

```lisp
(module hangman
  (import wasi.io.stdout (capability write "/dev/stdout"))
  (import wasi.io.stdin  (capability read  "/dev/stdin"))
  ... rest of the file ...)
```

**Why module support was temporarily relaxed.** `parseModule` succeeds when the
`(module name ...)` form parses correctly.  However, capability-import statements
inside a module body use a form `(import wasi.io.stdout (capability write ...))`.
The parser's `pImportStmt` correctly handles this syntax; the module parser calls
`many pStatement` which includes `pImportStmt`.  So capability imports **do** parse
in isolation.

The actual problem was more subtle: the file's **`(module hangman ...)` wrapper
itself is fine**, but when the compiler then called `parseModule fp src` and got
back `Module name imports body`, the downstream commands (`doCheck`, `doBuild`,
etc.) called `parseStatements fp src` directly — ignoring the module result — which
then re-parsed the file as bare statements and failed on the `(module ...)` keyword.

**What was fixed.** A `parseSrc` helper was introduced in `Main.hs`:

```haskell
parseSrc :: FilePath -> T.Text -> Either T.Text [Statement]
parseSrc fp src =
  case parseModule fp src of
    Right (Module _ _ body) -> Right body           -- module-wrapped file
    Left _  ->
      case parseStatements fp src of
        Right stmts -> Right stmts                  -- bare file
        Left err    -> Left (T.pack (show err))
```

All four commands (`doCheck`, `doHoles`, `doTest`, `doBuild`) now route through
`parseSrc` instead of calling `parseStatements` directly.

**Why the module wrapper was also removed from `hangman_complete.llmll`.** After
`parseSrc` was added, the module wrapper no longer caused a parse error — `parseSrc`
could extract the body correctly.  However, capability-import statements in the
module body are currently **ignored by all downstream phases** (type-checker, PBT
engine, code generator).  Keeping them inside the module wrapper would generate
no-op `SImport` nodes that do nothing at build time; this is misleading.

The decision was to:
- Move the `(import ...)` lines to **comments** so the intent is preserved in the source.
- Remove the `(module hangman ...)` wrapper so the file is processed as bare statements.
- Track restoring proper `(module ...)` processing as a v0.2 task.

> **Module support is not removed from the compiler** — `parseModule` is intact,
> `parseSrc` tries it first, and files with a `(module ...)` wrapper still parse
> correctly (the body is extracted and used).  What changed is that
> **capability imports inside a module body do not yet wire up to the type-checker
> or code generator**.

---

## Codegen.hs

### 1. ADT sum types → Rust `enum`

**Before.** A type defined with `(type GameInput (| StartGame Word) (| Guess Letter))`
was emitted as:

```rust
pub type GameInput = StartGame | Guess;  // invalid Rust!
```

**After.** `emitTypeDef` detects the `" | "` separator in the `TCustom` label and
emits a proper Rust `enum` with a `use Enum::*;` glob import to bring variants
into scope for match arms:

```rust
#[derive(Debug, Clone, PartialEq)]
pub enum GameInput {
    StartGame(String),
    Guess(String),
}
use GameInput::*;
```

---

### 2. `toRustIdent` — sanitize `?`, `.`, and `-`

LLMLL identifiers can contain characters that are illegal in Rust identifiers:

| LLMLL character | Conversion | Example |
|---|---|---|
| `-` (kebab-case) | `_` | `def-logic` → `def_logic` |
| `?` (predicate suffix) | `_` | `game-won?` → `game_won_` |
| `.` (qualified names) | `_` | `wasi.io.stdout` → `wasi_io_stdout` |

```haskell
toRustIdent :: Name -> Text
toRustIdent = T.map sanitize
  where
    sanitize '-' = '_'
    sanitize '?' = '_'
    sanitize '.' = '_'
    sanitize  c  = c
```

---

### 3. Dependent type aliases — no longer re-emitted

The header pre-declares `Word`, `Letter`, `GuessCount`, and `PositiveInt` as
simple type aliases (the constraint is deferred to v0.2).  The `isTypeDef`
predicate uses a Haskell **record pattern** (required because `STypeDef` is a
record constructor) to skip these names:

```haskell
preDefinedTypeNames :: [Text]
preDefinedTypeNames = ["Word", "Letter", "GuessCount", "PositiveInt"]

isTypeDef (STypeDef { typeDefName = name }) = name `notElem` preDefinedTypeNames
isTypeDef _                                  = False
```

> **Note on the record pattern fix.** An earlier attempt used positional syntax
> `STypeDef name _` which silently failed to match (Haskell record constructors
> require field-name patterns).  This caused the pre-defined type aliases to be
> emitted twice, producing duplicate-definition errors from `rustc`.

---

### 4. `LlmllVal` — dynamic value type for untyped functions

LLMLL v0.1 does not infer return types for `def-logic` functions that lack an
explicit `-> RetType` annotation (the parser stores `Nothing` for `defLogicReturn`
in those cases).  Rust requires explicit return type annotations on free functions,
so the codegen must emit _something_.

The generated `lib.rs` header now declares a `LlmllVal` enum:

```rust
pub enum LlmllVal { Int(i64), Float(f64), Text(String), Bool(bool),
                    Unit, List(Vec<LlmllVal>), Pair(Box<LlmllVal>, Box<LlmllVal>) }
```

It implements `From<i64>`, `From<String>`, `From<bool>`, `From<Vec<String>>`,
`From<(A,B)>` (tuple → Pair), plus `Add`, `Not`, `PartialEq`, and `PartialOrd`
so that LLMLL operators (`+`, `not`, `=`, `<`, `>=`) compile without errors.

Untyped functions emit `-> LlmllVal` and wrap their body with `.into()`.  Typed
functions (those where LLMLL explicitly declares the return type) emit their
concrete Rust type unchanged.

---

### 5. Standard library stubs in the generated header

All LLMLL built-in functions that the hangman example calls are now emitted inline
at the top of every generated `lib.rs`, so the crate compiles with no external
dependency:

| LLMLL built-in | Rust signature |
|---|---|
| `string-length` | `fn string_length(s: impl AsRef<str>) -> i64` |
| `string-char-at` | `fn string_char_at(s: impl AsRef<str>, i: i64) -> String` |
| `string-contains` | `fn string_contains(h: impl AsRef<str>, n: impl AsRef<str>) -> bool` |
| `string-concat` | `fn string_concat(a: String, b: String) -> String` |
| `int-to-string` | `fn int_to_string(n: i64) -> String` |
| `range` | `fn range(from: i64, to: i64) -> Vec<i64>` |
| `list-empty` | `fn list_empty<T>() -> Vec<T>` |
| `list-append` | `fn list_append<T: Clone>(v, x) -> Vec<T>` |
| `list-map` | `fn list_map<T,U>(v, f) -> Vec<U>` |
| `list-fold` | `fn list_fold<T,U>(v, init, f) -> U` |
| `pair` | `fn pair(a, b) -> LlmllVal` (LlmllVal::Pair) |
| `first` | `fn first(p: LlmllVal) -> LlmllVal` |
| `second` | `fn second(p: LlmllVal) -> LlmllVal` |
| `wasi.io.stdout` | `fn wasi_io_stdout(s) -> Command` (String stub) |

`string_length` and friends accept `impl AsRef<str>` so they work with both
`&str` and owned `String` arguments without explicit `.as_str()` calls at every
call site.

---

### 6. `validate_X` stubs

Dependent-type validator functions (`validate_Word`, `validate_Letter`, etc.) are
emitted from the header as `todo!()` stubs rather than trying to emit the
constraint expression (which references LLMLL param names that don't exist in the
Rust scope):

```rust
pub fn validate_Word(_x: &String) -> bool { todo!("validate_Word: v0.2") }
```

Full constraint evaluation is tracked as a v0.2 task.

---

## Quick reference — what is deferred to v0.2

| Feature | Status |
|---|---|
| Module capability imports wired to type-checker | Deferred |
| Proper `SGenDecl` AST node (gen declarations) | Deferred |
| Return-type inference for unannotated `def-logic` | Deferred |
| Dependent-type constraint evaluation in Rust | Deferred |
| PBT generators for custom types in Haskell runtime | Deferred |
