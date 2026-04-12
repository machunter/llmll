# Item 7b: Stratified Verification — Compiler Team Brief

**Origin:** Professor-team debate on Principle 4 (Runtime Contract Verification)  
**Date:** 2026-04-11  
**Depends on:** Item 7a (language team spec changes)  
**Status:** Awaiting review  
**Resolved decisions (2026-04-11):** `(trust ...)` uses per-function multiple declarations (like `import`); `tested(N)` sample counts are compiler-internal only for v0.3.  
**Corrections applied (2026-04-11):** Three compiler-team corrections integrated — see §Errata at end.

---

## Context

The language team is renaming Principle 4 to "Design by Contract with Stratified Verification" and introducing three concepts the compiler must support:

1. **Verification levels** (`proven`, `tested`, `asserted`) — metadata per contract, per function.
2. **`--contracts` flag** — controls which runtime assertions survive into generated Haskell.
3. **Trust-level propagation** — downstream modules see warnings when depending on unproven contracts.

This brief covers the implementation plan for each.

---

## Deliverable 1: `VerificationLevel` Data Type

### Location: `compiler/src/LLMLL/Syntax.hs`

Add to the existing contract-related types:

```haskell
-- | How a contract clause (pre or post) has been verified.
data VerificationLevel
  = VLAsserted                -- ^ Runtime assertion only; no evidence
  | VLTested   { vlSamples :: Int }  -- ^ QuickCheck passed N samples without falsification
  | VLProven   { vlProver  :: Text } -- ^ Formally verified by named prover ("liquid-fixpoint", "leanstral")
  deriving (Show, Eq)

-- | Trust-tier ordering: Asserted < Tested < Proven.
-- Internal metadata (samples, prover name) is NOT compared.
-- This ensures (trust foo :level tested) silences VLAsserted and VLTested(any N),
-- and --contracts=unproven strips only VLProven regardless of prover name.
vlTier :: VerificationLevel -> Int
vlTier VLAsserted  = 0
vlTier VLTested{}  = 1
vlTier VLProven{}  = 2

instance Ord VerificationLevel where
  compare a b = compare (vlTier a) (vlTier b)
```

> [!NOTE]
> `VLTested` carries a sample count internally. This is **compiler-internal metadata, not surface syntax** (resolved decision). The parser maps `(trust foo :level tested)` to `VLTested 0` as a sentinel meaning "any count accepted." The actual sample count is written by `llmll test` and persisted in the sidecar `.verified.json` file and `llmll verify --json` output, but never appears in `.llmll` source.

### Where it attaches

Extend `Contract` or create a parallel structure:

```haskell
data ContractStatus = ContractStatus
  { csPreLevel  :: Maybe VerificationLevel  -- Nothing if no pre clause
  , csPostLevel :: Maybe VerificationLevel  -- Nothing if no post clause
  } deriving (Show, Eq)
```

This is stored in `ModuleEnv` alongside the exported function signatures. Default for a freshly parsed module: `VLAsserted` for every clause.

### Writers

| Command | What it writes |
|---------|---------------|
| `llmll verify` | Sets `VLProven "liquid-fixpoint"` for each contract that `.fq` solver reports SAFE. Skipped contracts remain `VLAsserted`. |
| `llmll test` | Sets `VLTested N` for each function whose `check`/`for-all` blocks pass with N samples. |
| Future: Leanstral | Sets `VLProven "leanstral"` for contracts resolved via Lean proof certificates. |

### Persistence

Verification levels should be cached alongside the module. Two options:

- **(a)** Sidecar file: `foo.llmll.verified.json` — a JSON map from function name to `ContractStatus`. Written by `llmll verify` and `llmll test`. Read by `llmll build` and module imports.
- **(b)** Embedded in JSON-AST: add `"verificationLevel"` fields to `def-logic` and `letrec` nodes.

**Recommendation:** Option (a) for v0.3. The sidecar file is independent of the source format (works for both `.llmll` and `.ast.json`), does not require schema changes, and can be `.gitignore`d for CI reproducibility. Option (b) is cleaner long-term but requires a schema version bump.

---

## Deliverable 2: `--contracts` Flag

### Location: `compiler/src/LLMLL/Contracts.hs` + CLI parser

Add a `ContractsMode` type:

```haskell
data ContractsMode
  = ContractsFull      -- ^ All contracts remain as runtime assertions
  | ContractsUnproven  -- ^ Strip assertions for VLProven contracts
  | ContractsNone      -- ^ Strip all runtime assertions
  deriving (Show, Eq)
```

### Changes to `instrumentStatement`

Current behavior (line 121–126 of `Contracts.hs`): unconditionally wraps every `SDefLogic` with pre/post assertions.

New behavior: take `ContractsMode` and the function's `ContractStatus` as inputs.

```haskell
instrumentStatement :: ContractsMode -> ContractStatus -> Statement -> Statement
instrumentStatement ContractsNone _ stmt = stmt  -- strip everything

-- SDefLogic: full mode
instrumentStatement ContractsFull _ stmt@(SDefLogic name params mRet contract body) =
  let newBody = wrapWithContracts name contract body
  in SDefLogic name params mRet noContract newBody

-- SLetrec: full mode (CORRECTION: was missing — SLetrec fell through the catch-all)
instrumentStatement ContractsFull _ stmt@(SLetrec name params mRet contract dec body) =
  let newBody = wrapWithContracts name contract body
  in SLetrec name params mRet noContract dec newBody

-- SDefLogic: unproven mode
instrumentStatement ContractsUnproven cs stmt@(SDefLogic name params mRet contract body) =
  let stripped = filterContracts cs contract
      newBody  = wrapWithContracts name stripped body
  in SDefLogic name params mRet noContract newBody

-- SLetrec: unproven mode (CORRECTION: must handle SLetrec identically)
instrumentStatement ContractsUnproven cs stmt@(SLetrec name params mRet contract dec body) =
  let stripped = filterContracts cs contract
      newBody  = wrapWithContracts name stripped body
  in SLetrec name params mRet noContract dec newBody

instrumentStatement _ _ stmt = stmt

-- | Strip proven contract clauses, keep unproven ones.
filterContracts :: ContractStatus -> Contract -> Contract
filterContracts cs contract = Contract
  { contractPre = case csPreLevel cs of
      Just (VLProven _) -> Nothing
      _                 -> contractPre contract
  , contractPost = case csPostLevel cs of
      Just (VLProven _) -> Nothing
      _                 -> contractPost contract
  }
```

> [!WARNING]
> **Existing bug:** The current `instrumentStatement` catch-all (line 126) passes `SLetrec` through unchanged — its `pre`/`post` contracts are never instrumented as runtime assertions. This is independent of stratified verification but must be fixed as part of this deliverable.

### CLI integration

```
llmll build <file> [--contracts=full|unproven|none]
```

Default logic:
1. If `--contracts` is explicitly set, use that.
2. Else if a sidecar `.verified.json` exists for the file, use `ContractsUnproven`.
3. Else use `ContractsFull`.

### `llmll test` override

`llmll test` always uses `ContractsFull`, ignoring the flag. Tests must exercise all assertions regardless of proof status — this catches regressions in the prover pipeline.

---

## Deliverable 3: Trust-Level Propagation

### Location: `compiler/src/LLMLL/TypeCheck.hs` (CORRECTED — was Module.hs + TypeCheck.hs)

Trust-gap warnings fire **at call sites** during type inference. The relevant code path is `inferExpr (EApp func args)` (TypeCheck.hs line 612). `Module.hs` handles file-system resolution and `ModuleEnv` construction — it does not reason about call sites.

**Implementation path:**

1. `ModuleEnv` gains a new field: `meContractStatus :: Map Name ContractStatus` (in `Syntax.hs`).
2. `typeCheckWithCache` (TypeCheck.hs line 302) seeds the `TypeEnv` and **also** threads a parallel `Map Name ContractStatus` for all qualified names from the cache.
3. In `inferExpr (EApp func args)`, after resolving `func` against the `TypeEnv`, look up its `ContractStatus`. If any clause is below `VLProven`, and no `STrust` declaration matches, emit `TrustGapWarning`.

When resolving a cross-module function call:

1. Look up the callee's `ContractStatus` from the seeded map.
2. If any clause is `VLAsserted` or `VLTested`, emit a `WARNING` diagnostic:

```haskell
-- New diagnostic kind (add to Diagnostic.hs)
-- Example diagnostic:
Diagnostic
  { dKind    = Just "trust-gap-warning"
  , dPointer = "/statements/3/body/args/0"  -- call site in caller
  , dMessage = "Function crypto.hash.pbkdf2 has an unproven postcondition (level: asserted). "
            <> "Your module inherits this trust gap. "
            <> "Silence with: (trust crypto.hash.pbkdf2 :level asserted)"
  }
```

### `(trust ...)` declaration

Parser support for the new form (language team provides grammar rule). **Per-function, multiple declarations** — follows the `import` model, not the `export` model:

```lisp
;; Each trust gap is acknowledged individually
(trust crypto.hash.pbkdf2 :level asserted)
(trust auth.verify-token  :level tested)
```

Parsed into (CORRECTED — uses flat `Name`, not a structured `QualIdent` type):

```haskell
data Statement = ...
  | STrust
      { trustTarget :: Name              -- ^ flat dotted text, e.g. "crypto.hash.pbkdf2"
      , trustLevel  :: VerificationLevel -- ^ acknowledged trust level
      }
```

> [!NOTE]
> **Why flat `Name`?** There is no `QualIdent` type in `Syntax.hs`. Import paths are `Name` (flat `Text`), split only at point of use via `splitDotted` (Module.hs line 69). `STrust` follows the same convention. The suppression logic compares the flat qualified key that `typeCheckWithCache` seeded — no decomposition needed.

**Parser mapping for `:level tested`:** Since `tested(N)` is compiler-internal, the parser maps bare `tested` to `VLTested 0` (sentinel). The suppression logic uses the custom `Ord` instance (compares `vlTier` only), so `VLTested 0` compares equal to `VLTested 1000` — exactly the right behavior for trust acknowledgment.

**Idempotency:** Multiple `(trust ...)` declarations for the same function are silently deduplicated. The type checker collects trusts into a `Set Name` — duplicates are a no-op, not an error. This prevents merge conflicts when multiple agents acknowledge the same trust gap.

The type checker records acknowledged trusts. When a `TrustGapWarning` would fire for a function that has been `(trust ...)`-ed at the declared level or lower (using `Ord VerificationLevel`), the diagnostic is suppressed.

### Ordering

`(trust ...)` follows the same ordering rule as `import`, `open`, `export` — must appear before any `def-logic`.

---

## Deliverable 4: `.fq` Emitter Faithfulness Invariant

### The contract

> If `llmll verify` reports SAFE for a contract, then removing the runtime assertion does not change the observable behavior of any well-typed program.

### Current gap

`FixpointEmit.exprToPred` (line 265) returns `Nothing` for `lambda`, `let`, `match`, and all non-trivial expression forms. This means:

- A `post` clause containing a `let` binding will be **skipped** by the verifier (emitted as `?proof-required`).
- The runtime assertion for the same `post` clause **will** fire, because `Contracts.wrapPost` does not simplify — it embeds the `post` expression verbatim.

This is **currently safe**: if the verifier skips a contract, it stays `VLAsserted`, and `ContractsUnproven` will keep the runtime assertion. The invariant only breaks if `exprToPred` reports a false SAFE — i.e., translates a contract to a weaker `.fq` constraint that the solver accepts trivially.

### Action items

1. **Audit `exprToPred`** for false-positive SAFE paths. Currently the function is conservative (returns `Nothing` for anything it cannot translate). Ensure no future extension (e.g., adding `let` support) introduces unsound simplification.
2. **Add a regression test**: for each contract that `llmll verify` reports SAFE, run `llmll test` with `--contracts=full` and confirm no `post` violation. If a verified contract fails at runtime, the emitter is unsound.
3. **Document the coverage boundary** in a comment at the top of `FixpointEmit.hs`: "This module's output is trusted by `--contracts=unproven`. Any extension to `exprToPred` must preserve the faithfulness invariant: if SAFE is reported, the runtime assertion must be semantically redundant."

---

## Priority and Scheduling

| Deliverable | Priority | Blocks |
|-------------|----------|--------|
| D1: `VerificationLevel` type + `ModuleEnv` storage | P1 | D2, D3 |
| D2: `--contracts` flag | P2 | Nothing (additive) |
| D3: Trust-level propagation + `(trust ...)` | P2 | Nothing (additive) |
| D4: Faithfulness audit + regression test | P1 | D2 (must prove emitter is correct before stripping assertions) |

D1 and D4 are the critical path. D2 and D3 can be parallelized after D1 lands.

> [!WARNING]
> **D4 before D2.** Do not ship `--contracts=unproven` until the faithfulness audit is complete. Stripping proven assertions without confirming emitter correctness violates the invariant.

---

## Relationship to Other Items

| Item | Relationship |
|------|-------------|
| Item 6 (`?delegate` lifecycle) | Checkout metadata should include the `ContractStatus` of contracts in the checked-out subtree, so the filling agent knows which contracts are proven vs. asserted. |
| Item 7a (language team brief) | Spec counterpart. All surface syntax (`(trust ...)`, `--contracts` flag, verification level taxonomy) is defined there. |

---

## Prerequisite Patches

Two existing bugs must be fixed before (or alongside) the stratified verification work:

### P0a: `SLetrec` contracts never instrumented

**File:** `Contracts.hs` line 126  
**Bug:** The catch-all `instrumentStatement stmt = stmt` passes `SLetrec` through unchanged. Its `pre`/`post` contracts are never wrapped as runtime assertions.  
**Fix:** Add explicit `SLetrec` clauses to `instrumentStatement` (see D2 above).  
**Risk:** Low — isolated to `Contracts.hs`.

### P0b: `SLetrec` functions never exported

**File:** `Module.hs` line 240–246  
**Bug:** `toExport` handles `SDefLogic`, `SDefInterface`, and `STypeDef`, but the catch-all `toExport _ = Nothing` drops `SLetrec`. Recursive functions defined with `letrec` are invisible to importing modules.  
**Fix:**
```haskell
toExport (SLetrec name params mRet _ _ _) =
  let retType = fromMaybe (TVar "?") mRet
  in Just (name, TFn (map snd params) retType)
```
**Risk:** Low — additive, no existing behavior changes (currently those functions are simply invisible; making them visible cannot break callers that could never see them).

> [!IMPORTANT]
> Both P0 patches should land before D1. `ContractStatus` in `ModuleEnv` must cover both `SDefLogic` and `SLetrec` from the start, and the runtime assertion instrumentation must handle both forms before the `--contracts` mode logic is layered on top.

---

## Errata (Compiler Team Review)

Three corrections from compiler team code review, applied 2026-04-11:

| # | Original claim | Correction | Section updated |
|---|----------------|-----------|----------------|
| 1 | "D3 goes in `Module.hs`" | `Module.hs` handles file resolution and `ModuleEnv` construction. Trust warnings fire at call sites in `TypeCheck.hs` (`inferExpr (EApp ...)`, line 612). | D3 |
| 2 | `instrumentStatement` sketch only handles `SDefLogic` | `SLetrec` (Syntax.hs line 263) also carries contracts. The existing catch-all passes it through uninstrumented. Both must be handled. | D2 |
| 3 | `deriving (Show, Eq, Ord)` on `VerificationLevel` | Derived `Ord` compares `vlSamples` inside `VLTested`, making `VLTested 100 > VLTested 50`. Custom `Ord` via `vlTier` compares only the trust tier. | D1 |

Two open questions resolved:

| # | Question | Resolution | Rationale |
|---|----------|-----------|----------|
| 1 | Should `STrust` use `QualIdent` or flat `Name`? | **Flat `Name`** (like `importPath`) | No `QualIdent` type exists. `splitDotted` decomposes at point of use. Consistency with `Import`. |
| 2 | Can `SLetrec` be exported cross-module? | **Yes, but it's currently a bug** (P0b) | `toExport` catch-all drops `SLetrec`. Fix as prerequisite patch. `ContractStatus` must cover both forms. |
