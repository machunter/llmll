# Item 7b: Stratified Verification — Compiler Team Brief

**Origin:** Professor-team debate on Principle 4 (Runtime Contract Verification)  
**Date:** 2026-04-11  
**Depends on:** Item 7a (language team spec changes)  
**Status:** Awaiting review  

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
  deriving (Show, Eq, Ord)
```

> [!NOTE]
> `VLTested` carries a sample count to leave room for future trust granularity. For v0.3, `llmll test` writes the actual sample count from QuickCheck. The language spec says `tested` without a count — the count is compiler-internal metadata, not surface syntax.

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
instrumentStatement ContractsFull _ stmt@(SDefLogic name params mRet contract body) =
  -- current behavior: wrap all
  let newBody = wrapWithContracts name contract body
  in SDefLogic name params mRet noContract newBody
instrumentStatement ContractsUnproven cs stmt@(SDefLogic name params mRet contract body) =
  let pre'  = case csPreLevel cs of
                Just (VLProven _) -> Nothing    -- strip proven pre
                _                 -> contractPre contract
      post' = case csPostLevel cs of
                Just (VLProven _) -> Nothing    -- strip proven post
                _                 -> contractPost contract
      stripped = Contract pre' post'
      newBody  = wrapWithContracts name stripped body
  in SDefLogic name params mRet noContract newBody
instrumentStatement _ _ stmt = stmt
```

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

### Location: `compiler/src/LLMLL/Module.hs` + `compiler/src/LLMLL/TypeCheck.hs`

When resolving a cross-module function call:

1. Look up the callee's `ContractStatus` from its `ModuleEnv`.
2. If any clause is `VLAsserted` or `VLTested`, emit a `WARNING` diagnostic:

```haskell
data DiagnosticKind = ... | TrustGapWarning

-- Example diagnostic:
Diagnostic
  { dKind    = TrustGapWarning
  , dPointer = "/statements/3/body/args/0"  -- call site in caller
  , dMessage = "Function crypto.hash.pbkdf2 has an unproven postcondition (level: asserted). "
            <> "Your module inherits this trust gap. "
            <> "Silence with: (trust crypto.hash.pbkdf2 :level asserted)"
  }
```

### `(trust ...)` declaration

Parser support for the new form (language team provides grammar rule):

```lisp
(trust crypto.hash.pbkdf2 :level asserted)
```

Parsed into:

```haskell
data Statement = ...
  | STrust QualIdent VerificationLevel  -- trust acknowledgment
```

The type checker records acknowledged trusts. When a `TrustGapWarning` would fire for a function that has been `(trust ...)`-ed, the diagnostic is suppressed.

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
