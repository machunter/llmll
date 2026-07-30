# Coding Conventions

**Analysis Date:** 2026-07-30

## Naming Patterns

**Files:**
- PascalCase with `.hs` extension
- Example: `Syntax.hs`, `TypeCheck.hs`, `Contracts.hs`, `Diagnostic.hs`
- Located in `compiler/src/LLMLL/` for library modules
- Located in `compiler/app/` for executable entry points
- Located in `compiler/test/` for test modules

**Functions:**
- camelCase for all function names
- Verb-prefix pattern: `parse*`, `emit*`, `check*`, `build*`, `analyze*`, `collect*`, `validate*`
  - Examples: `parseStatements`, `emitFixpoint`, `typeCheck`, `buildModuleEnv`, `analyzeHoles`, `collectHoleGuards`
- Smart constructors use `mk*` prefix for creating values
  - Examples: `mkError`, `mkWarning`, `mkInfo`, `mkErrorAt`, `mkCircularImport`, `mkModuleNotFound`, `mkInterfaceMismatch`
- Predicate/test functions use `is*` or `has*` prefix
  - Examples: `isVerifiedLevel`, `isCoreBodySyntactic`, `isSolverBacked`, `hasContracts`
- Partial functions use `Unsafe` suffix when they can fail
  - Example: `resultReturnUnsafe`
- Monadic operations: no special prefix, just follow verb pattern
  - Examples: `runSketch`, `runTC`, `runReplay`, `runPropertyTests`

**Variables:**
- lowercase for bindings and parameters in function definitions
- camelCase for multi-word local variables
- Temporary/intermediate variables: `x`, `y`, `z`, `a`, `b`, `t`, `e`, `s`, `m`, `n` (single letters acceptable for very small scopes)
- Plural forms for collections: `stmts`, `diags`, `errs`, `msgs`, `envs`, `defs`, `funcs`, `params`
- Single letters for type parameters: `a`, `b`, `t`, `e` (error), `m` (monad)

**Types:**
- PascalCase for all data types and type aliases
- Constructor names: PascalCase, follow semantic meaning
  - Examples: `Type(..)` has `TInt`, `TString`, `TBool`, `TList`, `TMap`, `TResult`, `TPair`, `TFn`, `TPromise`, `TDependent`, `TDelegationError`, `TVar`, `TCustom`, `TSumType`
  - Prefix with letter indicating category: `T` for types, `S` for statements, `E` for expressions, `L` for literals, `P` for patterns
- Record fields: lowercase with module prefix when needed
  - Examples: `diagSeverity`, `diagSpan`, `diagMessage`, `diagKind`, `meExports`, `mePath`, `poiIndex`, `poiPath`

**Modules:**
- Module names: `LLMLL.ModuleName` pattern
- All exposed in explicit export list in module header
- Organized by responsibility (Syntax, Parser, TypeCheck, etc.)

## Code Style

**Formatting:**
- No automated formatter (eslint/prettier equivalent)
- Haddock documentation for public functions and types
- Line length: pragmatic, typically 80-100 chars but not strictly enforced
- Indentation: consistent 2-space or 4-space, follow existing file style

**Linting:**
- GHC compiler flags: `-Wall -Wcompat -Widentities -Wincomplete-record-updates -Wincomplete-uni-patterns -Wpartial-fields -Wredundant-constraints`
- These flags are configured in `compiler/llmll.cabal` for both library and executable
- Additional flag for executable: `-optP-Wno-nonportable-include-path -optc-Wno-nonportable-include-path`

**Language Extensions:**
```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TupleSections #-}
```

These are declared as `default-extensions` in the cabal file and applied to all modules.

**Additional extensions used in specific files:**
- `{-# LANGUAGE StrictData #-}` in `Syntax.hs` - forces strict evaluation of all data constructor fields
- `{-# LANGUAGE OverloadedStrings #-}` is the most important for this codebase - enables string literals to be `Text` instead of `String`

## Import Organization

**Order:**
1. Prelude + standard library imports (`Data.Text`, `Data.Map.Strict`, etc.)
2. Third-party library imports (`Test.Hspec`, `Text.Megaparsec`, etc.)
3. Local module imports (other LLMLL modules)

**Example from `compiler/test/ModuleSpec.hs`:**
```haskell
import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import LLMLL.Syntax
import LLMLL.Parser (parseTopLevel)
import LLMLL.TypeCheck (...)
```

**Pattern:**
- `qualified` for common modules to avoid name collisions: `qualified Data.Map.Strict as Map`, `qualified Data.Text as T`
- Explicit imports for LLMLL modules, listing only needed functions to document dependencies
- Comments on import groups separated by blank lines

## Error Handling

**Patterns:**
- Primary: `Either`-based error handling where operations return `Either DiagnosticReport a` or `DiagnosticReport`
- Structured error type: `Diagnostic` with `diagSeverity`, `diagMessage`, `diagKind`, `diagCode`, `diagPointer`, `diagSpan`
- Error classification via `diagKind` field - strings like `"type-mismatch"`, `"undefined-name"`, `"circular-import"`, `"module-not-found"`, `"interface-mismatch"`
- Parser errors converted to `Diagnostic` via `megaparsecToDiagnostic` function

**Smart constructors (all in `LLMLL.Diagnostic`):**
- `mkError :: Maybe Span -> Text -> Diagnostic` - basic error
- `mkWarning :: Maybe Span -> Text -> Diagnostic` - basic warning
- `mkInfo :: Maybe Span -> Text -> Diagnostic` - informational message
- `mkErrorAt :: Text -> Text -> Text -> Diagnostic` - error with kind and JSON Pointer (kind, pointer, message)
- Domain-specific: `mkCircularImport`, `mkModuleNotFound`, `mkInterfaceMismatch`, `mkExportConflict`, `mkOpenShadowWarning`, `mkNonExhaustiveMatch`, `mkTrustGapWarning`, `mkSpecWeakness`, `mkCandidateUnvalidated`, `mkMissingCapability`, `mkCoreGrammarViolation`, `mkCoreMembershipViolation`, `mkReuseWarning`, `mkContractReadOOBWarning`

**Error handling in parsers:**
- Use `fail` for parse errors (megaparsec will convert to proper error)
- Use `try` combinator to backtrack on parse failure
- Example from `LLMLL.Parser`:
  ```haskell
  pDefLogicRemoved :: Parser Statement
  pDefLogicRemoved = do
    _ <- try (symbol "(" *> symbol "def-logic")
    fail $ "removed-construct: 'def-logic' was removed in v0.12.1 and is "
        ++ "rejected under all grammar modes (no auto-rewrite); use 'def' for "
        ++ "strict-core or 'def-shell' for permissive"
  ```

**Error handling in type checking:**
- Accumulate diagnostics in `DiagnosticReport` type
- Use `reportSuccess :: DiagnosticReport -> Bool` to check if phase succeeded
- Use `reportDiagnostics :: DiagnosticReport -> [Diagnostic]` to extract error list
- Filter by severity: `filter ((== SevError) . diagSeverity) diags`

## Logging

**Framework:** None standardized - uses plain `putStrLn` and `hPutStrLn` for CLI output

**Patterns:**
- CLI output via `putStrLn :: String -> IO ()`
- Error output via `hPutStrLn stderr`
- Debug output commented out or removed (no debug framework)
- No log levels enforced

## Comments

**When to Comment:**
- Module header: Always document with Haddock (three dashes `-- |`)
- Type definitions: Always include Haddock comment explaining purpose
- Complex algorithms: Inline comments explaining approach or invariants
- Workarounds: Always document why a workaround is needed, reference issues
- Examples: Include example in Haddock when non-obvious

**Haddock/JSDoc:**
- All public functions MUST have Haddock comments
- Format: `-- | Description text` or `-- ^ field doc` for records
- Example from `Syntax.hs`:
  ```haskell
  -- | The LLMLL type representation.
  --
  -- In v0.1, dependent types ('TDependent') store the constraint as a raw
  -- expression AST — parsed but not evaluated at compile time.
  data Type
    = TInt                          -- ^ 64-bit integer
    | TFloat                        -- ^ 64-bit float
  ```

## Function Design

**Size:** 
- Prefer small functions (10-30 lines)
- Complex logic broken into named helper functions
- Large functions (100+ lines) should be documented as to why they can't be split

**Parameters:**
- Use pattern matching to destructure in function arguments when possible
- Example: `functionName (Constructor a b) = ...` rather than `functionName x = let (a, b) = destructure x`
- Prefer explicit type signatures on top-level functions

**Return Values:**
- Use `Maybe a` for optional results (no value is not an error)
- Use `Either error a` for fallible operations (from Either or DiagnosticReport)
- Use data types (`ContractViolation`, `HoleEntry`, etc.) for complex return values
- Consistency: a function always returns the same type

## Module Design

**Exports:**
- Explicit export list in module header (no `(..)` unless documenting all)
- Example from `LLMLL.Syntax`:
  ```haskell
  module LLMLL.Syntax
    ( -- * Names and Source Locations
      Name
    , Span(..)
    , Located(..)

      -- * Types
    , Type(..)
    , typeLabel
    , typeConstructorName
    )
  ```
- Section comments in export list for logical grouping (e.g., `-- * Names`, `-- * Types`)

**Barrel Files:**
- No barrel files used in this codebase
- Each module responsible for its own API

**Internal functions:**
- Not exported, only used within module
- Prefixed with `_` if intentionally unused or
- Simply not listed in export list (preferred pattern)

---

*Convention analysis: 2026-07-30*
