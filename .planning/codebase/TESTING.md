# Testing Patterns

**Analysis Date:** 2026-07-30

## Test Framework

**Runner:**
- Hspec 2.11+ (`hspec >=2.11`)
- Config: `compiler/llmll.cabal` (test-suite section)
- Entry point: `compiler/test/Spec.hs` (main suite), `compiler/test/ModuleSpec.hs` (module system tests)

**Assertion Library:**
- Hspec built-in assertions (`shouldBe`, `shouldSatisfy`, `shouldReturn`, etc.)
- No separate assertion library needed

**Parser Testing:**
- `hspec-megaparsec` 2.2+ for parser-specific assertions
- Validates parsing errors and success cases

**Property Testing:**
- QuickCheck 2.14+ for property-based testing
- Custom wrappers via `LLMLL.PBT` module (`runPropertyTests`, `PBTResult`, `PBTRun`, `PBTStatus`)

**Run Commands:**
```bash
# Run all tests (from compiler directory)
stack test

# Watch mode (requires ghcid)
ghcid --command "stack ghci"

# Coverage (requires hpc)
stack test --coverage

# Specific test suite
stack test llmll:llmll-test
```

## Test File Organization

**Location:**
- Tests are co-located with test fixtures
- Main test file: `compiler/test/Spec.hs` (largest file, ~788KB)
- Module system tests: `compiler/test/ModuleSpec.hs`
- Test fixtures: `compiler/test/fixtures/` (organized by feature)

**Naming:**
- Test file naming: `*Spec.hs` (Hspec convention)
- Fixture files: feature-name directories with `.llmll`, `.ast.json`, `.json` files
- Examples: `compiler/test/fixtures/pair_type_test/`, `compiler/test/fixtures/xmod-ag/`, `compiler/test/fixtures/cdp/`

**Structure:**
```
compiler/
├── test/
│   ├── Spec.hs          # Main test suite
│   ├── ModuleSpec.hs    # Module system tests
│   └── fixtures/
│       ├── pair_type_test/
│       │   ├── pair_type_test.llmll
│       │   ├── pair_type_test.ast.json
│       │   ├── pair_destruct_let.llmll
│       │   └── ...
│       ├── xmod-ag/
│       │   ├── lib.llmll
│       │   ├── use.llmll
│       │   └── ...
│       └── ...
└── src/
    └── LLMLL/
```

## Test Structure

**Suite Organization:**
From `compiler/test/ModuleSpec.hs`:
```haskell
describe "Module System" $ do
  describe "M-01: import + open + bare call" $ do
    it "succeeds under strict typecheck when open is present" $ do
      let entryStmts = [...]
          cache = mkCache [modA_env]
          report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
      reportSuccess report `shouldBe` True

  describe "M-02: import without open fails strict" $ do
    it "bare call to imported function fails without open" $ do
      let entryStmts = [...]
          cache = mkCache [modA_env]
          report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
      reportSuccess report `shouldBe` False
      let errs = filter ((== SevError) . diagSeverity) (reportDiagnostics report)
      length errs `shouldSatisfy` (>= 1)
```

**Key Patterns:**
1. Organize tests with `describe` blocks (logical grouping)
2. Each test case in `it` block with clear description
3. Setup in `let` bindings (no mutable state)
4. Assertions using Hspec matchers: `shouldBe`, `shouldSatisfy`, `shouldBe True`, `shouldBe False`
5. Diagnostic assertion: `filter ((== SevError) . diagSeverity) (reportDiagnostics report)`
6. Fixture loading: `loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["modC_cycle"]`

## Setup and Teardown

**Setup Pattern:**
- No global setup; use `beforeAll`, `before`, or `beforeWith` from Hspec
- Fixtures built fresh for each test via helper functions

**Helpers for Setup:**
From `ModuleSpec.hs`:
```haskell
-- | Build a simple ModuleEnv from a module path and statements, with no
-- imported modules (empty base env).
mkEnv :: ModulePath -> [Statement] -> ModuleEnv
mkEnv path stmts = buildModuleEnv path stmts Map.empty emptyEnv

-- | A simple def-logic that returns its parameter.
defLogic :: T.Text -> [(T.Text, Type)] -> Maybe Type -> Expr -> Statement
defLogic name params mRet body =
  SDefLogic name params mRet (Contract Nothing Nothing Nothing Nothing Nothing [] []) body

-- | Module A: defines f and g, no export restriction.
modA_stmts :: [Statement]
modA_stmts =
  [ defLogic "f" [("x", TInt)] (Just TInt) (EOp "+" [EVar "x", ELit (LitInt 1)])
  , defLogic "g" [("x", TInt)] (Just TInt) (EOp "+" [EVar "x", ELit (LitInt 2)])
  ]
```

**Teardown Pattern:**
- Use `finally` from `Control.Exception` for cleanup
- Example from `Spec.hs`:
  ```haskell
  result <- loadVerified sidecarPath `finally` removeFile sidecarPath
  ```
- Cleanup temporary files, clear environment variables set during test

**File Management:**
- Temporary directories: use `getTemporaryDirectory` from `System.Directory`
- File existence checks: `doesFileExist`, `doesDirectoryExist`
- Removal: `removeFile`, `removeDirectoryRecursive`
- Create as needed: `createDirectoryIfMissing`

## Mocking

**Framework:** QuickCheck + custom fixtures (no mocking library)

**Patterns:**
- No external mocks; tests use real implementations
- Fixtures for complex objects: `mkEnv`, `defLogic`, `mkCache` functions
- Property-based testing via QuickCheck:
  ```haskell
  import LLMLL.PBT (runPropertyTests, PBTResult(..), PBTRun(..), PBTStatus(..))
  ```

**What to Mock:**
- File I/O: Use `withTemporaryDirectory` or temp file helpers instead
- Network: MCP client has mock: `mockProofResult` in `LLMLL.MCPClient`
- Process execution: `callProcess` or `readProcessWithExitCode` (real process, needed for integration tests)
- External services: Lean proof checking uses `LLMLL.MCPClient` with configurable `MCPConfig`

**What NOT to Mock:**
- Parser (test with real examples)
- Type checker (test with real types and constraints)
- Compiler phases (test the actual transformations)

## Fixtures and Factories

**Test Data:**
From `compiler/test/ModuleSpec.hs` - helper functions create test objects:
```haskell
-- Fixture definition
modA_env :: ModuleEnv
modA_env = mkEnv ["modA"] modA_stmts

-- Usage in test
let cache = mkCache [modA_env]
```

**Location:**
- Haskell helpers: `compiler/test/Spec.hs` and `compiler/test/ModuleSpec.hs` (inline helpers)
- LLMLL fixtures: `compiler/test/fixtures/*/` (subdirectories by feature)
- JSON AST fixtures: `*.ast.json` files for parser testing
- LLMLL source fixtures: `*.llmll` files for end-to-end testing

**Factory Functions:**
```haskell
-- From ModuleSpec.hs
mkEnv :: ModulePath -> [Statement] -> ModuleEnv
mkEnv path stmts = buildModuleEnv path stmts Map.empty emptyEnv

defLogic :: T.Text -> [(T.Text, Type)] -> Maybe Type -> Expr -> Statement
defLogic name params mRet body =
  SDefLogic name params mRet (Contract Nothing Nothing Nothing Nothing Nothing [] []) body

mkCache :: [ModuleEnv] -> ModuleCache
mkCache envs = Map.fromList [(mePath e, e) | e <- envs]
```

## Coverage

**Requirements:** Not enforced; optional via `stack test --coverage`

**View Coverage:**
```bash
# Generate coverage report
stack test --coverage

# View detailed report
open .stack-work/install/.../hpc/index.html
```

**Coverage Tools:**
- HPC (Haskell Program Coverage) built into GHC
- `hpc report` and `hpc markup` for detailed analysis
- No coverage thresholds enforced in CI

## Test Types

**Unit Tests:**
- Scope: Individual functions and small units
- Approach: Test single responsibility - parser, type checker phase, diagnostic generation
- Example: `M-01: import + open + bare call succeeds strict typecheck` tests the typecheck function with module imports
- Files: `compiler/test/Spec.hs` (majority), `compiler/test/ModuleSpec.hs` (module-specific)

**Integration Tests:**
- Scope: Multiple compiler phases working together
- Approach: End-to-end tests from AST to fixpoint generation or proof output
- Examples: 
  - Fixture loading + typecheck + obligation assembly
  - Module loading with circular import detection
  - Cross-module composition with alias tracking
- Files: `compiler/test/Spec.hs` (mixed with unit tests)

**Property-Based Tests:**
- Scope: Invariant properties across many inputs
- Framework: QuickCheck via `LLMLL.PBT` module
- Run via: `runPropertyTests :: [Statement] -> [Capability] -> IO PBTResult`
- Files: `compiler/test/Spec.hs` (integration with other tests)
- Properties verified: 
  - Soundness of verification verdicts (SAFE implies no counterexample)
  - Completeness (refute cases are correctly identified)

**E2E Tests:**
- Framework: Not used in unit test suite
- Approach: Manual verification or CI integration tests
- Manual E2E: `stack exec llmll -- verify examples/*/...` runs compiler end-to-end
- Examples stored in `examples/` directory (showcase and regression)

## Common Patterns

**Async Testing:**
```haskell
-- From Spec.hs: use hspec's async support
it "loads verified cache" $ do
  result <- loadVerified sidecarPath
  result `shouldSatisfy` isJust
```

**Error Testing:**
Pattern: Assert on diagnostic presence and content
```haskell
-- From ModuleSpec.hs
it "bare call to imported function fails without open" $ do
  let entryStmts = [SImport (Import "modA" Nothing Nothing), ...]
      report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
  reportSuccess report `shouldBe` False
  let errs = filter ((== SevError) . diagSeverity) (reportDiagnostics report)
  length errs `shouldSatisfy` (>= 1)
```

**Diagnostic Verification:**
```haskell
-- Assert on error kind
let shadowWarns = filter
      (\d -> diagSeverity d == SevWarning
          && T.isInfixOf "open-shadow-warning" (diagMessage d))
      (reportDiagnostics report)
length shadowWarns `shouldSatisfy` (>= 1)

-- Assert on specific field
diagKind (head diags) `shouldBe` Just "circular-import"

-- Assert on message content
let msg = diagMessage cycleDiag
msg `shouldSatisfy` T.isInfixOf "modC_cycle"
msg `shouldSatisfy` T.isInfixOf "modD_cycle"
```

**File-Based Fixtures:**
```haskell
-- Load fixture from disk
let srcRoot = "test/fixtures/modules"
result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["modC_cycle"]
case result of
  Left diags -> do
    length diags `shouldSatisfy` (>= 1)
    diagKind (head diags) `shouldBe` Just "circular-import"
  Right _ -> expectationFailure "Expected error, got success"
```

**Map-Based Comparison:**
```haskell
-- Assert on record field
Map.member "f" (meExports modA_export_env) `shouldBe` True
Map.member "g" (meExports modA_export_env) `shouldBe` False
```

**Multiple Setup Variants:**
```haskell
-- Test success and failure paths with shared setup
it "(open modA (f)) makes f available but not g" $ do
  -- Success variant
  let entryStmts_ok = [...SOpen ["modA"] (Just ["f"])...]
      report_ok = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts_ok
  reportSuccess report_ok `shouldBe` True

  -- Failure variant  
  let entryStmts_fail = [...SOpen ["modA"] (Just ["f"]), ...EApp "g"...]
      report_fail = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts_fail
  reportSuccess report_fail `shouldBe` False
```

---

*Testing analysis: 2026-07-30*
