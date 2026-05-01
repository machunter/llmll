# EVID-0 — Design Specification

> **Version:** Rev 2 — Professor's review incorporated  
> **Date:** 2026-04-30  
> **Implements:** compiler-team-roadmap.md § v0.8.1b (Evidence Model Refactor)  
> **Source:** Professor's five-round review (2026-04-30)  
> **Reviewed:** Professor (2026-04-30) — conditional approve, 4 issues resolved  
> **Status:** APPROVED — ready for implementation

---

## 1. Motivation and Current Trust-Model Gap

The current `VerificationLevel` ADT in [Syntax.hs:252–257](../../compiler/src/LLMLL/Syntax.hs#L252-L257) imposes a **total order** on verification evidence:

```haskell
data VerificationLevel
  = VLAsserted                        -- tier 0
  | VLTested   { vlSamples :: Int }   -- tier 1
  | VLProven   { vlProver  :: Text }  -- tier 2
  | VLProvenSMT { vlSMTSolver :: Text }  -- tier 2
```

`vlTier` maps these to integers, and `trustMin` takes the minimum. This works when evidence is comparable, but **`contract-checked` and `tested` are fundamentally incomparable**:

- `contract-checked` = "the solver proved the contract predicates are internally consistent" (specification evidence)
- `tested` = "QuickCheck ran 100 samples without falsification" (empirical evidence)

Neither subsumes the other. The total order forces a ranking that misrepresents the epistemic status. Users see `tested > asserted` and `proven > tested`, concluding a linear progression. In reality, evidence forms a **partial order** (diamond lattice).

**Second gap:** The trust report does not distinguish between functions whose dependencies are **runtime primitives** (trusted by definition), **compiler builtins** (implemented in the preamble), and **external opaque stubs** (correctness assumed, not verified). A function calling `sha1` and a function calling `+` both show zero drift warnings. The `sha1` dependency is an unverified assumption that should be surfaced.

---

## 2. New ADT Definitions

### 2.1 `DisplayLevel` — replaces `VerificationLevel`

```haskell
-- | Evidence tier for a contract clause. Partial order, not total.
data DisplayLevel
  = DLAsserted                         -- ^ Runtime assertion only; no evidence
  | DLTested   { dlSamples :: Int }    -- ^ QuickCheck passed N samples
  | DLContractChecked { dlProver :: Text }  -- ^ SMT proved contract consistency (not body)
  | DLVerified { dlProver :: Text }    -- ^ SMT proved body satisfies contract
  deriving (Show, Eq, Generic)
```

**Lattice structure:**
```
         DLVerified
        /          \
DLContractChecked  DLTested
        \          /
         DLAsserted
```

`DLContractChecked` and `DLTested` are **incomparable**. There is no `Ord` instance.

### 2.2 `evidenceMeet` — replaces `trustMin`

```haskell
-- | Greatest lower bound (meet) of two display levels.
-- Exhaustive pattern matching — no numeric tier dispatch.
-- Incomparable elements (DLContractChecked ⊓ DLTested) meet at DLAsserted.
evidenceMeet :: DisplayLevel -> DisplayLevel -> DisplayLevel
-- Bottom absorbs
evidenceMeet DLAsserted _            = DLAsserted
evidenceMeet _ DLAsserted            = DLAsserted
-- Same constructor, different metadata: conservative choice
evidenceMeet (DLVerified p1) (DLVerified _)               = DLVerified p1
evidenceMeet (DLContractChecked p1) (DLContractChecked _)  = DLContractChecked p1
evidenceMeet (DLTested n1) (DLTested n2)                   = DLTested (min n1 n2)
-- Verified is top
evidenceMeet (DLVerified _) b        = b
evidenceMeet a (DLVerified _)        = a
-- Incomparable: contract-checked ⊓ tested = asserted
evidenceMeet DLContractChecked{} DLTested{} = DLAsserted
evidenceMeet DLTested{} DLContractChecked{} = DLAsserted
```

> [!NOTE]
> **No `dlTier` helper.** Previous draft used a numeric tier function that imposed an implicit total order — exactly what this refactor eliminates. Exhaustive pattern matching is required. (Professor review Issue 3.)

**Key properties:**
- `evidenceMeet (DLContractChecked "lf") (DLTested 100) = DLAsserted` — incomparable meet at bottom
- `evidenceMeet (DLTested 100) (DLTested 200) = DLTested 100` — same constructor, conservative (min samples)
- `evidenceMeet (DLContractChecked "lf") (DLContractChecked "z3") = DLContractChecked "lf"` — same constructor, first-argument preference (arbitrary but deterministic)
- `evidenceMeet (DLVerified "lf") (DLTested 50) = DLTested 50` — top identity

### 2.3 Lattice Laws (Proof Obligations)

| # | Law | Formula | Test cases |
|---|-----|---------|-----------|
| PO-1a | Commutativity | `meet(a,b) = meet(b,a)` | 16 pairs (4×4) + 8 parameterized variants |
| PO-1b | Associativity | `meet(meet(a,b),c) = meet(a,meet(b,c))` | 64 triples (4×4×4) |
| PO-2 | Idempotency | `meet(a,a) = a` | 4 cases |
| PO-3 | Bottom absorbs | `meet(a, DLAsserted) = DLAsserted` | 4 cases |
| PO-4 | Top identity | `meet(a, DLVerified) = a` | 4 cases |
| PO-5 | Same-constructor metadata | `meet(DLTested 100, DLTested 200) = DLTested 100` | 4 cases |

**Total: 100 unit test cases.**

### 2.4 `AssumptionKind`

```haskell
-- | Classification of unverified dependencies.
data AssumptionKind
  = AKRuntimePrimitive   -- ^ Trusted runtime semantics: +, -, string-length, etc.
  | AKCompilerBuiltin    -- ^ Implemented in LLMLL preamble: string-char-at, regex-match
  | AKExternalOpaque     -- ^ Stub or FFI binding: sha1, hmac-sha1, Aeson
  deriving (Show, Eq, Ord, Generic)
```

### 2.5 `EvidenceRecord` — replaces direct `VerificationLevel` fields in `ContractStatus`

```haskell
-- | Structured evidence record for a single contract clause.
data EvidenceRecord = EvidenceRecord
  { erDisplayLevel :: DisplayLevel   -- ^ What kind of evidence backs this clause
  , erBodyFaithful :: Bool           -- ^ True when body VC was generated and passed
  , erSource       :: Maybe Text     -- ^ :source provenance annotation
  } deriving (Show, Eq, Generic)

-- | Per-function contract verification status (v0.8.1b).
data ContractStatus = ContractStatus
  { csPre         :: Maybe EvidenceRecord  -- ^ Nothing if no pre clause
  , csPost        :: Maybe EvidenceRecord  -- ^ Nothing if no post clause
  , csAssumptions :: [AssumptionKind]      -- ^ Function-level unverified dependencies
  } deriving (Show, Eq, Generic)
```

> [!NOTE]
> **Assumptions are function-level, not clause-level.** A function's precondition and postcondition share the same call graph. Placing `[AssumptionKind]` on `ContractStatus` avoids redundancy and prevents the semantic confusion of implying a precondition "assumes" an FFI dependency. (Professor review Issue 2.)

**Migration from current `ContractStatus`:**
```haskell
-- Current (v0.8.0):
data ContractStatus = ContractStatus
  { csPreLevel         :: Maybe VerificationLevel
  , csPostLevel        :: Maybe VerificationLevel
  , csPreSource        :: Maybe Text
  , csPostSource       :: Maybe Text
  , csPostBodyFaithful :: Bool
  }

-- New (v0.8.1b): flattened into EvidenceRecord + function-level assumptions
-- csPreLevel + csPreSource → csPre :: Maybe EvidenceRecord
-- csPostLevel + csPostSource + csPostBodyFaithful → csPost :: Maybe EvidenceRecord
-- (new) csAssumptions :: [AssumptionKind] — computed from call graph
```

### 2.6 Helper Functions — replace `vlTier`, `trustCovers`, `isProvenLevel`, `vlProverName`

```haskell
-- | Does evidence level `a` cover requirement `b`?
-- a covers b iff meet(a,b) = b (b is below or equal to a in the lattice).
evidenceCovers :: DisplayLevel -> DisplayLevel -> Bool
evidenceCovers a b = evidenceMeet a b == b

-- | Is this verified-level evidence (body-faithful SMT proof)?
isVerifiedLevel :: DisplayLevel -> Bool
isVerifiedLevel DLVerified{} = True
isVerifiedLevel _            = False

-- | True when evidence includes a solver-backed proof (contract or body).
-- Does NOT imply a total ordering — DLTested is incomparable, not "below".
isSolverBacked :: DisplayLevel -> Bool
isSolverBacked DLVerified{}        = True
isSolverBacked DLContractChecked{} = True
isSolverBacked _                   = False

-- | Extract prover name, if any.
dlProverName :: DisplayLevel -> Maybe Text
dlProverName (DLVerified p)        = Just p
dlProverName (DLContractChecked p) = Just p
dlProverName _                     = Nothing

-- | Human display label for a display level.
dlLabel :: DisplayLevel -> Text
dlLabel DLAsserted            = "asserted"
dlLabel (DLTested n)          = "tested (" <> tshow n <> " samples)"
dlLabel (DLContractChecked p) = "contract-checked (" <> p <> ")"
dlLabel (DLVerified p)        = "verified (" <> p <> ")"

-- | Human display label for an assumption kind.
akLabel :: AssumptionKind -> Text
akLabel AKRuntimePrimitive = "runtime-primitive"
akLabel AKCompilerBuiltin  = "compiler-builtin"
akLabel AKExternalOpaque   = "external-opaque"
```

> [!NOTE]
> **No `dlTier` or `isContractCheckedOrAbove`.** `dlTier` imposed an implicit total order; deleted. `isContractCheckedOrAbove` implied a linear ranking; renamed to `isSolverBacked` which describes what is checked (solver involvement) without ordering implication. (Professor review Issues 3 & 4.)

---

## 3. Constructor Mapping

### 3.1 `VerificationLevel` → `DisplayLevel`

| Old constructor | New constructor | Rationale |
|---|---|---|
| `VLAsserted` | `DLAsserted` | Unchanged semantics |
| `VLTested n` | `DLTested n` | Unchanged semantics |
| `VLProven prover` | `DLContractChecked prover` | Legacy Lean proofs proved contract consistency, not body faithfulness |
| `VLProvenSMT solver` (no body VC) | `DLContractChecked solver` | Contract-only solver evidence |
| `VLProvenSMT solver` (with body VC) | `DLVerified solver` | Body-faithful solver evidence |

> [!IMPORTANT]
> The split of `VLProvenSMT` into `DLContractChecked` vs `DLVerified` depends on `csPostBodyFaithful`. This is the critical mapping: same constructor, different evidence tier based on body-faithfulness. The migration reader must check this field.

### 3.2 Assumption Classification (New)

Assumptions are **not** derived from `VerificationLevel`. They are computed by inspecting the function's call graph:

| Callee pattern | `AssumptionKind` |
|---|---|
| `+`, `-`, `*`, `/`, `mod`, `=`, `<`, `<=`, `>=`, `>`, `string-length`, `string-concat` | `AKRuntimePrimitive` |
| `string-char-at`, `regex-match`, `index-safe` | `AKCompilerBuiltin` |
| `sha1`, `hmac-sha1`, any FFI stub, `(trust ...)` callee | `AKExternalOpaque` |

The classification is static — derived from a lookup table, not from runtime behavior.

---

## 4. JSON Schema

### 4.1 New `.verified.json` Format

```json
{
  "schema_version": "0.8.1b",
  "withdraw": {
    "pre": {
      "display_level": "verified",
      "prover": "liquid-fixpoint",
      "body_faithful": false,
      "source": null
    },
    "post": {
      "display_level": "verified",
      "prover": "liquid-fixpoint",
      "body_faithful": true,
      "source": "withdraw-spec"
    },
    "assumptions": ["runtime-primitive"]
  }
}
```

> Assumptions are at the function level (sibling of `pre`/`post`), not inside each clause.

**`display_level` values:** `"asserted"`, `"tested"`, `"contract-checked"`, `"verified"`.

### 4.2 Backward-Compatible Reader

Old `.verified.json` files (no `schema_version` key) are parsed using the existing `csFromJSON` logic, then mapped:

```haskell
migrateOldCS :: OldContractStatus -> ContractStatus
migrateOldCS old = ContractStatus
  { csPre         = migrateClause (oldCsPreLevel old) (oldCsPreSource old) False
  , csPost        = migrateClause (oldCsPostLevel old) (oldCsPostSource old) (oldCsPostBodyFaithful old)
  , csAssumptions = []  -- old format had no assumption data; see Observation B
  }

migrateClause :: Maybe VerificationLevel -> Maybe Text -> Bool -> Maybe EvidenceRecord
migrateClause Nothing _ _ = Nothing
migrateClause (Just vl) src bodyF = Just EvidenceRecord
  { erDisplayLevel = migrateVL vl bodyF
  , erBodyFaithful = bodyF
  , erSource       = src
  }

migrateVL :: VerificationLevel -> Bool -> DisplayLevel
migrateVL VLAsserted      _     = DLAsserted
migrateVL (VLTested n)    _     = DLTested n
migrateVL (VLProven p)    _     = DLContractChecked p
migrateVL (VLProvenSMT s) True  = DLVerified s
migrateVL (VLProvenSMT s) False = DLContractChecked s
```

**Detection:** If the top-level JSON object has no `"schema_version"` key, use the old reader.

---

## 5. Consumer File Changes (12 files)

| # | File | Current usage | Required change |
|---|------|------|--------|
| 1 | `Syntax.hs` | Defines `VerificationLevel`, `ContractStatus`, `vlTier`, `trustMin`, `trustCovers`, `isProvenLevel`, `vlProverName` | Replace with `DisplayLevel`, `EvidenceRecord`, `AssumptionKind`, `ContractStatus` (new), `evidenceMeet`, `evidenceCovers`, `isVerifiedLevel`, `dlProverName`, `dlLabel`, `akLabel` |
| 2 | `VerifiedCache.hs` | `vlToJSON`/`vlFromJSON`, `csToJSON`/`csFromJSON` | New serializers for `DisplayLevel`, `EvidenceRecord`. Migration reader for old format. Schema version detection. |
| 3 | `TrustReport.hs` | `vlLabel`, `effectiveLevel`, `trustMin` in `enrichEntry`, `computeDrifts`, `computeSummary` | `dlLabel`, `effectiveLevel` returns `Maybe DisplayLevel`, `enrichEntry` uses `evidenceMeet`. Add assumption display. `⚠` for `external-opaque`. |
| 4 | `SpecCoverage.hs` | `vlLabel` (duplicate def), classification by `isProvenLevel`/`VLTested`/`VLAsserted` | Replace with `dlLabel`, classify by `isVerifiedLevel`/`isSolverBacked`/`DLTested`/`DLAsserted`. JSON field names updated. |
| 5 | `Contracts.hs` | `filterContracts` matches `VLProvenSMT` + `csPostBodyFaithful` for stripping | Match `DLVerified` + `erBodyFaithful` from `csPost` |
| 6 | `Module.hs` | `mergeCS` uses `trustMin`. `extractContractStatus` constructs `ContractStatus`. | `mergeCS` uses `evidenceMeet` on `EvidenceRecord`. Constructor updated. |
| 7 | `Main.hs` | Constructs `VLProvenSMT "liquid-fixpoint"` in verify pipeline. Reads `ContractStatus` for trust/coverage. | Construct `DLVerified`/`DLContractChecked` based on `isBodyFaithful`. Updated `ContractStatus` constructor. |
| 8 | `ProofCache.hs` | `proofToLevel` returns `VLProvenSMT`/`VLProven`/`VLAsserted`. `isTaintedProof` caps to `VLAsserted`. | Return `DLVerified`/`DLContractChecked`/`DLAsserted`. Tainted → `DLAsserted`. |
| 9 | `AstEmit.hs` | `vlLabel` for JSON-AST round-trip | `dlLabel` |
| 10 | `TypeCheck.hs` | `tcContractStatus :: Map Name ContractStatus` for trust-gap warnings | Type update only — the `ContractStatus` shape changes but usage patterns are the same |
| 11 | `Parser.hs` | Parses `(trust ...)` → `VerificationLevel` | Parse → `DisplayLevel` constructor. `(trust asserted)` → `DLAsserted`, etc. |
| 12 | `ObligationMining.hs` | Reads `VerificationLevel` for obligation classification | Pattern update for new constructors |

---

## 6. Trust Report Changes

### 6.1 Current Output

```
  withdraw:
    pre:  proven-smt (liquid-fixpoint)  |  post: proven-smt (liquid-fixpoint)
```

### 6.2 New Output

```
  withdraw:
    pre:  contract-checked (liquid-fixpoint)  |  post: verified (liquid-fixpoint)
    ↳ calls string-length (runtime-primitive)
    ↳ calls sha1 (⚠ external-opaque)
```

**Changes:**
1. `proven-smt` split into `contract-checked` or `verified` based on body-faithfulness
2. Assumption kinds displayed per callee
3. `⚠` prefix for `external-opaque` dependencies
4. Summary section adds `contract-checked` count alongside `verified`

### 6.3 `TrustEntry` Update

```haskell
data TrustEntry = TrustEntry
  { teName           :: Name
  , tePre            :: Maybe EvidenceRecord     -- was tePreLevel + tePreSource
  , tePost           :: Maybe EvidenceRecord     -- was tePostLevel + tePostSource
  , teDeps           :: [TrustDependency]
  , teDrifts         :: [Text]
  , teEffectiveLevel :: Maybe DisplayLevel        -- was Maybe VerificationLevel
  }
  -- Assumptions accessed via ContractStatus.csAssumptions, not duplicated here.

data TrustSummary = TrustSummary
  { tsVerified        :: Int     -- was tsProven
  , tsContractChecked :: Int     -- NEW
  , tsTested          :: Int
  , tsAsserted        :: Int
  , tsNone            :: Int
  , tsDrifts          :: Int
  }
```

### 6.4 `effectiveLevel` Update

```haskell
effectiveLevel :: ContractStatus -> Maybe DisplayLevel
effectiveLevel cs =
  case (csPre cs >>= Just . erDisplayLevel, csPost cs >>= Just . erDisplayLevel) of
    (Nothing, Nothing) -> Nothing
    (Just a, Nothing)  -> Just a
    (Nothing, Just b)  -> Just b
    (Just a, Just b)   -> Just (evidenceMeet a b)
```

---

## 7. `(trust ...)` Surface Syntax

### 7.1 Current

```lisp
(trust asserted)
(trust tested 100)
(trust proven "leanstral")
```

### 7.2 New (v0.8.1b)

```lisp
(trust asserted)              ;; → DLAsserted
(trust tested 100)            ;; → DLTested 100
(trust contract-checked "liquid-fixpoint")  ;; → DLContractChecked "liquid-fixpoint"
(trust verified "liquid-fixpoint")          ;; → DLVerified "liquid-fixpoint"
```

**Backward compatibility:** `(trust proven "x")` is accepted and mapped to `DLContractChecked "x"` with a deprecation warning.

---

## 8. Stripping Logic Update

Current in [Contracts.hs:186](../../compiler/src/LLMLL/Contracts.hs#L186):

```haskell
Just (VLProvenSMT _) | csPostBodyFaithful cs -> Nothing  -- strip post
```

New:
```haskell
case csPost cs of
  Just er | isVerifiedLevel (erDisplayLevel er) && erBodyFaithful er -> Nothing
  _ -> -- keep assertion
```

**Preconditions are never stripped.** This invariant is unchanged.

---

## 9. Fallback Behavior

When the evidence model cannot determine a `DisplayLevel` for a clause (e.g., missing sidecar, corrupted JSON):

1. Default to `DLAsserted`
2. Log a diagnostic warning
3. Runtime assertions preserved

This is consistent with the current behavior where missing `ContractStatus` defaults to `Nothing` → assertions kept.

---

## 10. Test Matrix

### Lattice Properties — 100 unit tests

| ID | Category | Cases |
|----|----------|-------|
| L-COM | Commutativity: `meet(a,b) = meet(b,a)` | 24 (16 base + 8 parameterized) |
| L-ASC | Associativity: `meet(meet(a,b),c) = meet(a,meet(b,c))` | 64 |
| L-IDP | Idempotency: `meet(a,a) = a` | 4 |
| L-BOT | Bottom absorbs: `meet(a, DLAsserted) = DLAsserted` | 4 |
| L-TOP | Top identity: `meet(a, DLVerified) = a` | 4 |

### Incomparable Pair — 2 golden tests

| ID | Test |
|----|------|
| I-01 | `evidenceMeet (DLContractChecked "lf") (DLTested 100) = DLAsserted` |
| I-02 | `evidenceMeet (DLTested 100) (DLContractChecked "lf") = DLAsserted` |

### Serialization — 6 golden tests

| ID | Test |
|----|------|
| S-01 | New `EvidenceRecord` round-trips through JSON |
| S-02 | Old `.verified.json` (no `schema_version`) parsed correctly |
| S-03 | Old `VLProvenSMT` + `bodyFaithful=true` → `DLVerified` |
| S-04 | Old `VLProvenSMT` + `bodyFaithful=false` → `DLContractChecked` |
| S-05 | Old `VLProven` → `DLContractChecked` |
| S-06 | Old `VLTested 50` → `DLTested 50` |

### Trust Report — 5 golden tests

| ID | Test |
|----|------|
| T-01 | Body-faithful function shows `verified (liquid-fixpoint)` |
| T-02 | Contract-only function shows `contract-checked (liquid-fixpoint)` |
| T-03 | Function calling `sha1` shows `⚠ external-opaque` |
| T-04 | Transitive degradation: verified → contract-checked callee → effective `contract-checked` |
| T-05 | Incomparable chain: verified → tested callee → effective `asserted` |

### Assumption Display — 3 golden tests

| ID | Test |
|----|------|
| A-01 | `+` callee → no warning (runtime-primitive, silent) |
| A-02 | `sha1` callee → `⚠ assumes external-opaque: sha1` |
| A-03 | `string-char-at` callee → `compiler-builtin` (informational, no `⚠`) |

### Coverage/CLI — 4 golden tests

| ID | Test |
|----|------|
| C-01 | `--spec-coverage` JSON uses `"verified"` / `"contract-checked"` labels |
| C-02 | `--trust-report` human output matches new format |
| C-03 | `--trust-report --json` output matches new schema |
| C-04 | `--emit json-ast` round-trip with new `DisplayLevel` labels |

### Stripping — 2 golden tests

| ID | Test |
|----|------|
| X-01 | `--contracts=unproven` strips post for `DLVerified` + `bodyFaithful=true` |
| X-02 | `--contracts=unproven` keeps post for `DLContractChecked` (not body-faithful) |

### Backward Compatibility — 2 golden tests

| ID | Test |
|----|------|
| B-01 | `(trust proven "x")` parsed → `DLContractChecked "x"` + deprecation warning |
| B-02 | Old sidecar + new compiler → build succeeds, correct levels |

**Total: 124 tests** (100 lattice + 2 incomparable + 6 serialization + 5 trust report + 3 assumption + 4 coverage/CLI + 2 stripping + 2 backward compat)

---

## 11. Deferred Constructs

| Construct | Phase | Reason |
|-----------|-------|--------|
| `DLVerifiedLean` | LEAN-GA | Blocked on `lean-lsp-mcp`. When shipped, adds `prover: "lean"` to evidence. |
| Assumption auto-classification | COMP-0 | Requires call graph analysis; deferred to v0.9 |
| `TDependent` rename to `TRefined` | Optional in v0.8.1b | Source-level rename; no semantic change |
| Suppression debt integration | Future | `suppression_debt` field unchanged; classification uses new tiers |

---

## Appendix: Implementation Sequence

```
EVID-0 (this document)
    ▼
EVID-1:  DisplayLevel + EvidenceRecord + AssumptionKind + ContractStatus (new)
         + evidenceMeet (exhaustive) + evidenceCovers + isVerifiedLevel
         + isSolverBacked + dlLabel + akLabel. No dlTier.
         in Syntax.hs. Update all 12 consumer files (EVID-1a..1e).
    ▼
EVID-2:  VerifiedCache.hs — new JSON format + backward-compatible reader
    ▼
EVID-3:  TrustReport.hs — effectiveLevel, enrichEntry, display
    ▼
EVID-4:  SpecCoverage.hs — classification + JSON field names
    ▼
EVID-5:  Contracts.hs — stripping logic
    ▼
EVID-6:  Module.hs — mergeCS
    ▼
EVID-7:  Main.hs — CLI output + ContractStatus construction
    ▼
EVID-8:  LLMLL.md — spec updates (§4.4.1, §5.3.3, §5.3.4)
    ▼
EVID-T:  124 tests (parallel with EVID-2 onward)
```

### Modules Affected

| Module | Change | Phase |
|--------|--------|-------|
| [Syntax.hs](../../compiler/src/LLMLL/Syntax.hs) | New ADTs, helpers, `ContractStatus` restructure | EVID-1 |
| [VerifiedCache.hs](../../compiler/src/LLMLL/VerifiedCache.hs) | JSON schema, migration reader | EVID-2 |
| [TrustReport.hs](../../compiler/src/LLMLL/TrustReport.hs) | Display, propagation, `TrustEntry`/`TrustSummary` | EVID-3 |
| [SpecCoverage.hs](../../compiler/src/LLMLL/SpecCoverage.hs) | Classification, JSON | EVID-4 |
| [Contracts.hs](../../compiler/src/LLMLL/Contracts.hs) | Stripping logic | EVID-5 |
| [Module.hs](../../compiler/src/LLMLL/Module.hs) | `mergeCS`, `extractContractStatus` | EVID-6 |
| [Main.hs](../../compiler/src/Main.hs) | CLI, `ContractStatus` construction | EVID-7 |
| [ProofCache.hs](../../compiler/src/LLMLL/ProofCache.hs) | `proofToLevel` | EVID-1a |
| [AstEmit.hs](../../compiler/src/LLMLL/AstEmit.hs) | `vlLabel` → `dlLabel` | EVID-1b |
| [TypeCheck.hs](../../compiler/src/LLMLL/TypeCheck.hs) | Type update | EVID-1c |
| [Parser.hs](../../compiler/src/LLMLL/Parser.hs) | `(trust ...)` syntax | EVID-1d |
| [ObligationMining.hs](../../compiler/src/LLMLL/ObligationMining.hs) | Pattern update | EVID-1e |

### Key Design Decisions

| Decision | Resolution |
|----------|-----------|
| Partial order, not total | `DLContractChecked` ∦ `DLTested` — meet produces `DLAsserted` |
| No `Ord` instance on `DisplayLevel` | Prevents accidental `min`/`max` usage |
| Exhaustive pattern matching in `evidenceMeet` | No `dlTier` helper — avoids implicit total order (Professor Issue 3) |
| `DLTested` meet uses `min` on samples | `meet(DLTested 100, DLTested 200) = DLTested 100` (Professor Issue 1) |
| Assumptions on `ContractStatus`, not `EvidenceRecord` | Function-level, not clause-level (Professor Issue 2) |
| `isSolverBacked` not `isContractCheckedOrAbove` | Name describes what is checked, not ordering (Professor Issue 4) |
| Evidence record flattens `ContractStatus` | `csPreLevel` + `csPreSource` → `csPre :: Maybe EvidenceRecord` |
| Backward-compatible sidecar reader | Old files parsed via `schema_version` detection |
| `VLProvenSMT` split by `csPostBodyFaithful` | Same old constructor, two new tiers |
| Assumption classification is static | Lookup table, not runtime analysis. Computed during verification, stored in `ContractStatus`. |
| `(trust proven ...)` deprecated | Accepted with warning in v0.8.1b, mapped to `DLContractChecked`. Hard error in v0.10+. |
| `external-opaque` gets `⚠` | Visually prominent in trust report |
| `runtime-primitive` is silent | No warning — these are part of the TCB |
| Migrated old sidecars: `csAssumptions = []` | Assumptions unknown for pre-v0.8.1b data; trust report omits assumption section rather than displaying "no assumptions" |

---

## Appendix B: Professor Review Issues (Resolved)

| # | Issue | Severity | Resolution |
|---|-------|----------|------------|
| 1 | `evidenceMeet` equality check fails for parameterized constructors (`DLTested 100 ≠ DLTested 200`) | Correctness | Exhaustive pattern matching; `min` for `DLTested`; first-arg preference for same-prover |
| 2 | `erAssumptions` on clause-level is redundant and semantically wrong | Architecture | Moved to `ContractStatus.csAssumptions` (function-level) |
| 3 | `dlTier` creates implicit total order | Design | Deleted; exhaustive matching in `evidenceMeet` |
| 4 | `isContractCheckedOrAbove` name implies linear ordering | API design | Renamed to `isSolverBacked` |
