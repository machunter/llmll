# Deferred Design: `ContractClause` Type Refactor

> **Status:** Deferred — captured for future reference  
> **Origin:** Language Team v0.6.0 review (2026-04-22)  
> **Decision:** Option A (sibling fields) chosen for v0.6 to minimize invasiveness. Option B documented here for when the contract representation needs richer structure.

---

## Context

v0.6 adds per-clause `:source` annotations to `pre`/`post` contracts. Two designs were considered:

### Option A (chosen for v0.6): Sibling Fields

Add per-clause source refs as flat fields alongside existing `Maybe Expr`:

```haskell
data Contract = Contract
  { contractPre        :: Maybe Expr
  , contractPreSource  :: Maybe Text    -- :source for pre
  , contractPost       :: Maybe Expr
  , contractPostSource :: Maybe Text    -- :source for post
  }
```

**Pros:** Additive — existing pattern matches on `contractPre`/`contractPost` are unchanged.  
**Cons:** Every future per-clause metadata field (`severity`, `confidence`, `owner`, `timestamp`, etc.) adds two more flat fields. The `Contract` record becomes unwieldy.

### Option B (deferred): `ContractClause` Type

Introduce a structured clause type and refactor `Contract` to use it:

```haskell
data ContractClause = ContractClause
  { clauseExpr      :: Expr
  , clauseSource    :: Maybe Text      -- :source "RFC 8446 §7.1"
  -- Future fields go here:
  -- , clauseSeverity  :: Maybe Severity
  -- , clauseOwner     :: Maybe AgentName
  -- , clauseTimestamp :: Maybe UTCTime
  }

data Contract = Contract
  { contractPre  :: Maybe ContractClause
  , contractPost :: Maybe ContractClause
  }
```

**Pros:**
- Clean, extensible — new per-clause metadata is one field addition to `ContractClause` instead of two fields on `Contract`
- Self-documenting — `ContractClause` is a named type, not a bag of `Maybe` fields
- Enables future features naturally: clause-level verification status, clause ownership for multi-agent auditing, clause timestamps for drift detection

**Cons:**
- Every pattern match on `contractPre`/`contractPost` in the codebase changes from `Maybe Expr` to `Maybe ContractClause`
- Affected modules (at time of writing):
  - `WeaknessCheck.hs` — `hasContracts`, `tryCandidate`
  - `FixpointEmit.hs` — constraint generation from pre/post expressions
  - `Contracts.hs` — runtime assertion generation
  - `TrustReport.hs` — `collectAllContractStatus`, `mkCS`
  - `PBT.hs` — property checking (indirect, via statement walk)
  - `CodegenHs.hs` — Haskell code emission for contract assertions
  - `Parser.hs` — `pPreClause`, `pPostClause` return types
  - `ParserJSON.hs` — contract node parsing
  - `AstEmit.hs` — JSON-AST round-trip emission

---

## When to Revisit

Consider migrating to Option B when **any** of these triggers occur:

1. A second per-clause metadata field is needed (beyond `:source`)
2. Multi-agent auditing requires per-clause ownership tracking
3. Clause-level verification status (distinct from function-level `ContractStatus`) is needed
4. The `Contract` record exceeds 6 flat fields
5. Multiple `pre` clauses with different `:source` annotations lose provenance — the and-desugaring (`foldl1 (\a b -> EApp "and" [a, b])`) merges N clauses into one expression, so N distinct source references cannot be preserved. With `[ContractClause]`, each clause retains its own `:source`. (Discovered Sprint 2, 2026-04-22)

## Migration Path

1. Introduce `ContractClause` alongside existing `Contract` (additive)
2. Add a compatibility shim: `clauseExpr :: ContractClause -> Expr`
3. Migrate modules one at a time, using the shim to avoid a big-bang refactor
4. Remove shim once all consumers use `ContractClause` directly

---

## Related

- [Language Team v0.6.0 review](../../LLMLL.md) §1.3
- `Syntax.hs` — current `Contract` definition (L234–L238)
- `compiler-team-roadmap.md` — v0.6 PROV-1..4 (clause-level provenance)
