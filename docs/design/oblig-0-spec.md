# OBLIG-0 — Design Specification

> **Version:** Rev 8 — Seventh review incorporated  
> **Date:** 2026-05-02  
> **Implements:** compiler-team-roadmap.md § v0.10 (Obligation-Guided Agent Coding)  
> **Prerequisites:** v0.9.0 (COMP-0) shipped, v0.9.1 (module hardening) shipped  
> **Reviewed:** Professor — Rev 2 (6), Rev 3 (6), Rev 4 (6), Rev 5 (4), Rev 6 (5), Rev 7 (4), Rev 8 (3)  
> **Status:** APPROVED — OBLIG-1/MOD-1 unblocked; OBLIG-2 gates on §4.2.3/§4.2.4

---

## 1. Motivation

LLMLL's compiler already computes rich information about every `?hole`, contract clause, and call-site precondition, spread across four separate commands. An agent filling a hole must invoke multiple commands and correlate their outputs — a fragile, token-expensive process.

**What OBLIG-0 defines:** A single structured JSON obligation report merging type, contract, and trust information for every actionable site.

**Design principle:** v0.10 **primarily** re-exports existing analysis. One component — the candidate-expression search (§7) — is **net-new analysis** scoped to `ObligationMining.hs`, with bounded search and explicit "unverified" labeling. It does not expand the TCB.

---

## 2. Obligation Report JSON Schema

### 2.1 Top-Level Structure

```json
{
  "schema_version": "0.10.0",
  "source_file": "withdraw.llmll",
  "cross_module": "unsupported",
  "obligations": [ ... ],
  "summary": { "total": 5, "open": 3, "discharged": 1, "deferred": 1, "asserted": 0 }
}
```

### 2.2 Single Obligation Object

```json
{
  "id": "oblig:withdraw:body:?h3:a1b2c3d4e5f6",
  "origin": "/statements/1/body",
  "kind": "hole-obligation",
  "backing": "guidance",
  "status": "open",
  "function": "withdraw",

  "type_channel": {
    "expected_type": "int",
    "polymorphic": false,
    "in_scope": [
      { "name": "balance", "type": "int", "source": "param" },
      { "name": "amount",  "type": "int", "source": "param" }
    ]
  },

  "contract_channel": {
    "preconditions": ["(>= balance amount)"],
    "postcondition_goal": "(>= result 0)",
    "path_condition": [
      { "guard": "(>= balance amount)", "kind": "qf_lia" }
    ],
    "path_truncated": false,
    "contract_fragment": "qf_lia",
    "body_fragment": "hole_bearing",
    "body_faithful_possible": false
  },

  "trust_channel": {
    "assumptions": [{ "name": "int-minus", "kind": "runtime-primitive" }],
    "effective_level": "asserted",
    "body_faithful": false
  },

  "contracted_functions": [
    { "name": "safe-subtract", "params": [["a","int"],["b","int"]],
      "returns": "int", "status": "verified" }
  ],
  "available_functions": [
    { "name": "list-head", "params": [["xs","list[a]"]],
      "returns": "Result[a, string]", "status": "builtin" }
  ],

  "suggestions": [
    { "expression": "(- balance amount)",
      "reason": "satisfies (>= result 0) under precondition (>= balance amount)",
      "verified": false, "kind": "candidate-expression" }
  ]
}
```

### 2.3 Obligation Kinds

| `kind` | Trigger |
|---|---|
| `hole-obligation` | Type checker finds `?hole` |
| `contract-obligation` | Verifier UNSAFE on contract clause |
| `precondition-obligation` | Verifier UNSAFE on `call-pre:` |
| `termination-obligation` | Verifier UNSAFE on `decreases` constraint |
| `branch-obligation` | Per-branch sub-goal from `EMatch` |

**Termination obligation payload (v0.10):** v0.10 reports only `origin`, `backing`, and `status` for `termination-obligation`. The proof goal is always `decreases_measure >= 0` ([FixpointEmit.hs:402](../../compiler/src/LLMLL/FixpointEmit.hs#L402)). A future extension may add a `"termination_goal"` field carrying the measure expression.

### 2.4 Obligation Backing (Rev 8 — Finding 1)

> [!IMPORTANT]
> **Rev 8:** `"backing": "smt"` is derived from actual entries in the `ConstraintTable` ([DiagnosticFQ.hs:36](../../compiler/src/LLMLL/DiagnosticFQ.hs#L36)), which records `ConstraintOrigin` with fields `(coFunction, coClause, coJsonPtr, coSourceFile)`. The current `ConstraintOrigin` identifies the **enclosing function and clause type**, not individual branches, paths, or call sites within a function. Granularity is therefore **per-function per-clause-type**, not per-obligation-site.

> [!NOTE]
> **All-or-nothing body VCs (Rev 8 — Finding 2):** The current emitter translates `EIf` and `EMatch` bodies as all-or-nothing: if any branch fails translation, the entire body VC is abandoned ([FixpointEmit.hs:789](../../compiler/src/LLMLL/FixpointEmit.hs#L789), [FixpointEmit.hs:914](../../compiler/src/LLMLL/FixpointEmit.hs#L914)). There is no partial-path emission. If a function has a `body-post` constraint in the table, **all** body-level obligations for that function are SMT-backed. If the body fell back, **none** are.

```haskell
deriveBacking :: ConstraintTable -> Name -> ObligationKind -> Text
deriveBacking table fnName kind
  -- Body-level obligations: SMT-backed iff body VCs emitted for this function.
  -- Under all-or-nothing emission, this is a per-function check.
  | kind `elem` [HoleObligation, BranchObligation]
  = if hasClausePrefix table fnName "body-post" then "smt" else "guidance"
  -- Contract obligations: SMT-backed iff pre/post/body-post emitted
  | kind == ContractObligation
  = if hasClausePrefix table fnName "pre"
    || hasClausePrefix table fnName "post"
    || hasClausePrefix table fnName "body-post"
    then "smt" else "guidance"
  -- Call-pre obligations: SMT-backed iff call-pre constraint emitted
  | kind == PreconditionObligation
  = if hasClausePrefix table fnName "call-pre" then "smt" else "guidance"
  -- Termination obligations: SMT-backed iff decreases constraint emitted
  | kind == TerminationObligation
  = if hasClausePrefix table fnName "decreases" then "smt" else "guidance"
  | otherwise = "guidance"

hasClausePrefix :: ConstraintTable -> Name -> Text -> Bool
hasClausePrefix table fn prefix =
  any (\origin -> coFunction origin == fn && prefix `T.isPrefixOf` coClause origin)
      (Map.elems table)
```

This accurately reflects the emitter's granularity: per-function, per-clause-type, with all-or-nothing body VC emission. If future work introduces partial-path emission (emitting constraints for successful branches while falling back on others), this function should be refined to per-path granularity using an extended `ConstraintOrigin` that carries a path/branch index.

### 2.5 Obligation Status

| Status | Meaning |
|---|---|
| `open` | No evidence — agent must act |
| `discharged` | Verified by solver/tests/evidence |
| `deferred` | Suppressed via `(weakness-ok)` |
| `asserted` | Runtime assertion only |

---

## 3. Obligation ID Design (Rev 4 — Finding 2)

### 3.1 ID Format

```
oblig:<function>:<channel>:<site>:<fingerprint>
```

### 3.2 Fingerprint Input — Alpha-Normalization (Rev 6 — Finding 4)

The fingerprint hashes an **alpha-normalized** representation. Binder classes actively normalized in v0.10:

| Binder class | Canonical prefix | Status |
|---|---|---|
| Function parameters | `$p` | **Active** — postconditions reference params |
| Type variables | `$t` | **Active** — prevents skolem instability |
| Let-bound variables | `$l` | **Deferred** — v0.10 postconditions are first-order over params and `result`; `$l` normalization adds complexity with no current benefit |
| Match payload variables | `$m` | **Deferred** — same rationale as `$l` |

> [!NOTE]
> **Rev 6 (Finding 4):** The Rev 4 table listed `$l` and `$m` as active, but the implementation only threaded `paramSubst`. v0.10 postconditions are restricted to first-order predicates over parameters and `result`, so let-bound and match-payload variables do not appear in postcondition expressions. The table is narrowed to match. If postconditions are later permitted to mention let-bound or match-arm names, `alphaCanonExpr` must be extended to maintain a growing binder-rename map across `ELet`/`EMatch`.

**Normalization applied to:**
- `expected_type` — TVar names canonicalized
- `postcondition_goal` — parameter references canonicalized via `paramSubst`
- `normalized_binding_names` — sorted, types included, parameter names replaced

```haskell
normalizeForFingerprint :: Name -> [(Name, Type)] -> Maybe Expr -> HoleStatus -> Text
normalizeForFingerprint fnName params mPost holeStatus =
  let paramSubst = Map.fromList $ zip (map fst params) ["$p" <> tshow i | i <- [0::Int ..]]
      normPost = fmap (alphaCanonExpr paramSubst) mPost
      normType = alphaCanonTVars (holeStatusType holeStatus)
  in T.intercalate ":" [fnName, typeLabel normType, maybe "" exprToSExpr normPost]
```

12-hex-char SHA-256 hash. `"origin"` (JSON Pointer) is separate mutable metadata.

### 3.3 Stability Properties

- **Rename-stable:** Parameter renames don't change ID (parameter binders are canonicalized via `$p` prefix). Let-bound and match-payload renames are **not** currently normalized (`$l`/`$m` are deferred — see §3.2); renaming those binders inside a postcondition expression would change the ID. This is benign under v0.10's restriction that postconditions are first-order over parameters and `result`.
- **Skolem-stable:** `TVar "a"` and `TVar "b"` produce the same ID after canonical renaming.
- **Edit-stable:** No positional component.
- **Postcondition-sensitive:** Different proof goals produce different IDs (desirable).

---

## 4. Three Obligation Channels

### 4.1 Type Channel

| Field | Type | Source |
|---|---|---|
| `expected_type` | `Text` | `shStatus` → `typeLabel` (alpha-canonical for polymorphic) |
| `polymorphic` | `Bool` | `true` when type is `TVar` |
| `in_scope` | `[ScopeEntry]` | `shEnv` → `buildScopeEntries` |

Polymorphic holes always get `"backing": "guidance"`.

### 4.2 Contract Channel

| Field | Type | Description |
|---|---|---|
| `preconditions` | `[Text]` | `contractPre` S-expression |
| `postcondition_goal` | `Maybe Text` | `contractPost` S-expression |
| `path_condition` | `[PathEntry]` | Typed path condition entries |
| `path_truncated` | `Bool` | `true` when capped at 16 clauses |
| `contract_fragment` | `Text` | Fragment of pre/post expressions only |
| `body_fragment` | `Text` | Fragment of body translation |
| `body_faithful_possible` | `Bool` | Whether body VC exists |

#### 4.2.1 Path Condition Entries

Each entry is typed to prevent consumers from ingesting structural markers as predicates:

```json
{ "guard": "(>= balance amount)", "kind": "qf_lia" }
{ "guard": "(match-success _call_g_0)", "kind": "structural" }
```

| `kind` | Consumable as predicate? |
|---|---|
| `"qf_lia"` | Yes — guard from `EIf`, translatable via sort-aware classifier |
| `"structural"` | No — synthetic label from `EMatch` / `CallVC` |

#### 4.2.2 Dual Fragment Classification

| Field | Values | Determines |
|---|---|---|
| `contract_fragment` | `"qf_lia"` / `"non_qf_lia"` / `"absent"` | Whether pre/post are in decidable fragment |
| `body_fragment` | `"qf_lia"` / `"hole_bearing"` / `"unsupported"` / `"recursive"` | Why the body did or didn't produce a VC |

> [!NOTE]
> **Rev 4 (Finding 6):** `"non_qf_lia"` replaces `"non_linear"`. The latter was too narrow — unsupported contracts include strings, lists, general matches, regex, and constructor-dependent postconditions, not just non-linear arithmetic.

Optional `"non_qf_lia_reason"` field provides detail when present:

```json
{ "contract_fragment": "non_qf_lia", "non_qf_lia_reason": "postcondition contains EMatch on result" }
```

#### 4.2.3 Path Condition Sourcing for Hole-Bearing Functions

`bodyToPredM` ([FixpointEmit.hs:917](../../compiler/src/LLMLL/FixpointEmit.hs#L917)) returns `Nothing` for `EHole`. OBLIG-2 uses a **separate guard-walker** in `ObligationAssembly.hs`:

```haskell
collectHoleGuards :: SortEnv -> [(Name, Type)] -> Expr -> [(Name, [PathEntry])]
collectHoleGuards sortEnv params = go Map.empty sortEnv []
  where
    go env se acc (EHole (HNamed n)) = [(n, acc)]
    go env se acc (EHole _)          = [("_anon", acc)]
    go env se acc (EIf guard thenE elseE) =
      let classified = classifyGuard env se guard
          negclassified = negateEntry classified
      in go env se (acc ++ [classified]) thenE
         ++ go env se (acc ++ [negclassified]) elseE
    -- Rev 6 (Finding 1): update env/SortEnv across ELet bindings.
    -- Unannotated bindings are NOT added to SortEnv (sort-unknown).
    -- Guards referencing sort-unknown variables will be classified
    -- as "structural" by guardToPredPresentation (which checks SortEnv).
    go env se acc (ELet binds body) =
      let (env', se') = foldl' (\(e, s) (PVar v, mTy, _rhs) ->
            let renamed = v
            in case mTy of
                 Just ty -> (Map.insert v renamed e, Map.insert renamed (typeToSort ty) s)
                 Nothing -> (Map.insert v renamed e, s)  -- sort-unknown: omit from SortEnv
            ) (env, se) binds
      in concatMap (\(_, _, e) -> go env se acc e) binds  -- RHS uses outer scope
         ++ go env' se' acc body                           -- body uses extended scope
    -- Match payloads: extend scope with constructor bindings
    go env se acc (EMatch _ arms) =
      concatMap (\(i, (pat, body)) ->
        let (env', se') = extendScopeWithPat env se pat
        in go env' se' (acc ++ [PathEntry ("(match-" <> patLabel pat <> ")") "structural"]) body
      ) (zip [0..] arms)
    -- Lambda params: extend scope (same sort-unknown rule as ELet)
    go env se acc (ELambda params b) =
      let (env', se') = foldl' (\(e, s) (pn, mTy) ->
            case mTy of
              Just ty -> (Map.insert pn pn e, Map.insert pn (typeToSort ty) s)
              Nothing -> (Map.insert pn pn e, s)  -- sort-unknown
            ) (env, se) params
      in go env' se' acc b
    go env se acc (EApp _ args) = concatMap (go env se acc) args
    go env se acc (EOp _ args)  = concatMap (go env se acc) args
    go env se acc (EPair a b)   = go env se acc a ++ go env se acc b
    go env se acc (EAwait e)    = go env se acc e
    go env se acc (EDo steps)   = concatMap (\(DoStep _ e) -> go env se acc e) steps
    go _   _  _   _             = []
```

> [!IMPORTANT]
> **Rev 4 (Finding 3):** Guard classification uses a **sort-aware classifier** mirroring `guardToPredM` ([FixpointEmit.hs:927](../../compiler/src/LLMLL/FixpointEmit.hs#L927)), not `exprToPred`. The presentation-only classifier checks variable sorts against `SortEnv` (built from `buildSortEnv aliases params`) before labeling a guard `"qf_lia"`. Without sort checking, `exprToPred` would incorrectly label guards involving bool/string variables as QF-LIA.

```haskell
classifyGuard :: Map Name Name -> SortEnv -> Expr -> PathEntry
classifyGuard env se guard =
  -- Mirror guardToPredM's sort-aware check (presentation-only, not TCB).
  -- Rev 5 (Finding 3): if env/SortEnv is incomplete (local binding not
  -- reconstructed), guardToPredPresentation returns Nothing and the
  -- guard is safely classified as "structural".
  let mPred = evalState (guardToPredPresentation env se guard) 0
  in case mPred of
       Just _  -> PathEntry (exprToSExpr guard) "qf_lia"
       Nothing -> PathEntry (exprToSExpr guard) "structural"

-- | Presentation-only guard classifier. Mirrors guardToPredM's structure
-- (checks SortEnv for variable sorts) but does NOT produce verification
-- conditions.
guardToPredPresentation :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
-- ... mirrors guardToPredM cases from FixpointEmit.hs:927-972 ...
```

### 4.2.4 Drift Mitigation: `guardToPredM` ↔ `guardToPredPresentation` (Rev 6 — Finding 2)

> [!WARNING]
> Two implementations of the same predicate semantics in different modules will drift. A future change to `guardToPredM` (e.g., adding a new operator, changing sort treatment) that isn't mirrored produces silently inconsistent reports.

**Mitigation (two-pronged):**

1. **Shared sort-checking core (preferred).** Extract a `GuardClassifier` module from `FixpointEmit.hs` that exposes the sort-aware predicate classification logic. Both `guardToPredM` (verification) and `guardToPredPresentation` (presentation) call this shared core. The duplication is bounded to the tail: `guardToPredM` produces `FQPred` for the solver; `guardToPredPresentation` produces `Just ()` / `Nothing` for the classifier. The shared core handles variable lookup, operator dispatch, and recursive structure.

2. **OBLIG-2 acceptance regression test (mandatory regardless).** A golden test that fuzzes guard expressions over a corpus and asserts:
   ```
   ∀ guard ∈ corpus: isJust (guardToPredM env se guard) == isJust (guardToPredPresentation env se guard)
   ```
   This test is added to `compiler/test/golden/oblig/` and gates OBLIG-2 merge. If the shared-core refactor is deferred, this test is the minimum viable drift detection.

**Properties:** Read-only AST walker, not TCB. Cap at 16 entries → `path_truncated: true`.

### 4.3 Trust Channel

Unchanged. Sources `csAssumptions`, `teEffectiveLevel`, `erBodyFaithful`.

---

## 5. Enriched Typed Holes (OBLIG-1 Spec)

### 5.1 Extension to `CheckoutToken`

Five new fields: `ctContractPre`, `ctPostconditionGoal`, `ctPathCondition`, `ctAssumptions`, `ctObligationId`.

### 5.2 Checkout CLI Activation (Rev 5 — Finding 1)

The new fields are emitted **unconditionally** — no `--obligations` flag on `checkout`. Rationale: the fields are `Maybe`-wrapped and JSON-encoded as `null` when absent. Adding them to every checkout response has zero cost when unused and avoids requiring agents to know about an extra flag.

```
llmll checkout <file> <pointer>
```

The existing `--obligations` flag on `llmll verify` is unrelated to checkout behavior. The roadmap reference to `llmll checkout --obligations` is superseded — see §9 and the roadmap update.

### 5.3 Staleness Rule (Rev 4 — Finding 5, Rev 5 — Finding 2)

> [!WARNING]
> Obligation context fields in `CheckoutToken` are **snapshots** captured at checkout time. They may go stale if source or `.verified.json` changes while the token is live.

Mitigation:

1. **`ctSourceHash`** — SHA-256 of the source file at checkout time.
2. **`ctVerifiedHash`** — SHA-256 of the **local** `.verified.json` sidecar at checkout time (or `null` if no sidecar exists). Covers staleness of `ctAssumptions` and trust-channel fields that depend on evidence records.
3. **Refresh-before-patch:** `llmll patch` validates both hashes against current files. If either mismatches, the patch is rejected: `"obligation context is stale — re-checkout required"`.
4. **No silent staleness:** Agents that skip re-checkout get a hard error, not silently stale data.

> [!NOTE]
> **Rev 6 (Finding 3):** `ctVerifiedHash` covers only the local `.verified.json` under v0.10 (single-module scope). After MOD-1 ships, `ctAssumptions` will legitimately depend on imported modules' contract verification (via `meContracts`), and those evidence records live in other modules' sidecar files. **MOD-1 must extend the staleness guard** to hash all imported `.verified.json` files (or a Merkle digest thereof). This is a MOD-1 implementation requirement, not a v0.10 design change.

```haskell
data CheckoutToken = CheckoutToken
  { -- ... existing fields ...
  , ctContractPre       :: Maybe Text
  , ctPostconditionGoal :: Maybe Text
  , ctPathCondition     :: Maybe [Text]
  , ctAssumptions       :: Maybe [Text]
  , ctObligationId      :: Maybe Text
  , ctSourceHash        :: Maybe Text    -- Rev 4: source staleness guard
  , ctVerifiedHash      :: Maybe Text    -- Rev 5: local .verified.json staleness guard
  }
```

### 5.4 OBLIG-1 Scope

Single-module only. `ctPathCondition` sources from contract pre (not body guards). Does not depend on §4.2.3 guard-walker or MOD-1.

---

## 6. `EMatch` Branch Obligations (OBLIG-3)

### 6.1 Backing Derived from Emitter Results (Rev 8)

Branch obligation backing is **not** assigned by match form alone. It uses `deriveBacking` (§2.4), which checks whether any `body-post`-prefixed constraint exists in the `ConstraintTable` for the enclosing function.

A `Result` 2-arm match that falls back (due to untranslatable scrutinee, unsupported branch body, constructor-dependent postcondition per [FixpointEmit.hs:856-864](../../compiler/src/LLMLL/FixpointEmit.hs#L856-L864), or missing return type) produces no `body-post` constraints and correctly gets `"backing": "guidance"`.

### 6.2 Branch Obligation Object

```json
{
  "kind": "branch-obligation",
  "backing": "guidance",
  "parent_id": "oblig:process:body:?impl:a1b2c3d4e5f6",
  "branch_index": 0,
  "constructor": "Success",
  "bindings": [{ "name": "val", "type": "int", "source": "match-arm" }],
  "path_condition": [{ "guard": "(match-success _call_g_0)", "kind": "structural" }],
  "postcondition_goal": "(>= result 0)"
}
```

---

## 7. Repair Suggestion Generation (OBLIG-4)

Net-new analysis in `ObligationMining.hs`. O(n²) bounded arithmetic search (variables + binary ops). No `EIf` synthesis (deferred to Tier 2). Suggestions carry mandatory `"verified": false`. Does not expand TCB.

---

## 8. Function Lists (Rev 4 — Finding 4)

### 8.1 Two Lists

> [!NOTE]
> **Rev 4:** Split into `contracted_functions` (assume-guarantee candidates) and `available_functions` (type-guided construction including builtins).

| Field | Selection predicate | Use case |
|---|---|---|
| `contracted_functions` | Has contract, return type compatible, in scope | Assume-guarantee call sites |
| `available_functions` | Type-compatible, in scope, includes non-`wasi.*` builtins | General expression construction (e.g., `list-head`) |

### 8.2 Cardinality and Ordering (Rev 6 — Finding 5)

- **Hard cap:** 8 entries each (16 total max, ~2.4KB).
- **Truncation signal:** When the cap excludes candidates, the list carries `"truncated": true` (analogous to `scope_truncated` in checkout and `path_truncated` in path conditions). Absent or `false` when all candidates fit.
- **Priority (Rev 6):** structural-equality match (post-zonking) > unification-only match > alphabetical. "Post-zonking" means type variables are resolved to their inferred concrete types before comparison; a polymorphic builtin like `list-head : list[a] -> Result[a, string]` that unifies with `Result[int, string]` ranks below a monomorphic function returning `Result[int, string]` directly.
- **Trust label:** each entry carries `"status"`: `"verified"` / `"contract-checked"` / `"asserted"` / `"builtin"`.

### 8.3 Cross-Module

Before MOD-1: same-module only. After MOD-1: imported module exports matching filter.

---

## 9. CLI Integration

New `--obligation-report` flag. Existing `--obligations` unchanged in v0.10; deprecated v0.11; removed v0.12. JSON versioning via `"schema_version": "0.10.0"`.

---

## 10. Benchmark Suite

### Tier 1 — Arithmetic (gates OBLIG-4 initial)

| # | Program | Expected |
|---|---|---|
| B1 | `withdraw(balance, amount)` | `(- balance amount)` |
| B5 | `double(n)` | `(+ n n)` |

### Tier 1 — Branch Obligations (gates OBLIG-3)

| # | Program | Expected |
|---|---|---|
| B3 | `safe-first(xs)` — match on `(list-head xs)` | 2-arm obligations; `list-head` appears in `available_functions` as `"builtin"` |

### Tier 2 — Conditional Synthesis (deferred)

| # | Program | Expected |
|---|---|---|
| B2 | `clamp(value, lo, hi)` | `(if (< value lo) lo ...)` |
| B4 | `abs(n)` | `(if (< n 0) (- 0 n) n)` |

Quality criteria: completeness, minimality (<2KB), grounding, actionability (Tier 1), stability (skolem+rename stable).

---

## 11. Dependency Discipline

```
OBLIG-0 (this document)
    ▼
OBLIG-1: Enriched typed holes (single-module, NO MOD-1 dep)
    ▼ (parallel)
MOD-1:  meContracts in ModuleEnv
    ▼
OBLIG-2: Full obligation report (BLOCKS on MOD-1)
          + guard-walker (§4.2.3)
    ▼
OBLIG-3: EMatch branch obligations (BLOCKS on MOD-1)
    ▼
OBLIG-4: Repair suggestions (Tier 1)
    ▼
OBLIG-4-ext: Conditional synthesis (Tier 2, deferred)
    ▼
OBLIG-5: Repair loop integration
    ▼
OBLIG-B: Benchmark suite (tiered gating)
```

---

## 12. Modules Affected

| Module | Change | Phase |
|---|---|---|
| **[NEW] `ObligationAssembly.hs`** | Report assembly, guard-walker, `guardToPredPresentation`, JSON encoding | OBLIG-2 |
| `Checkout.hs` | 5 new `CheckoutToken` fields + `ctSourceHash` + `ctVerifiedHash` staleness guards | OBLIG-1 |
| `Main.hs` | `--obligation-report` flag | OBLIG-2 |
| `ObligationMining.hs` | Export `isQfLia`; candidate search | OBLIG-4 |
| `Syntax.hs` | `meContracts` in `ModuleEnv` | MOD-1 |

---

## 13. Soundness

- Reports are informational — no verification semantics change.
- Guard-walker and candidate search are not TCB.
- `deriveBacking` consults actual emitter results, not structural heuristics.
- TCB unchanged: `CodegenHs.hs` · `bodyToPred` · `exprToPred` · `applySubst` · `liquid-fixpoint` · Z3 · GHC.

---

## 14. All Review Issues

### Rev 2 (6 issues)

| # | Issue | Resolution |
|---|---|---|
| 1 | N-ary EMatch overstates verifier | Two-tier backing (§6) |
| 2 | Cross-module conflicts with roadmap | OBLIG-1 single-module; OBLIG-2/3 block MOD-1 (§11) |
| 3 | Obligation IDs too weak | Structural fingerprint, 12-hex hash, origin separated (§3) |
| 4 | Decidability underspecified | Dual fragment classification (§4.2.2) |
| 5 | `--obligations` already shipped | `--obligation-report` with migration (§9) |
| 6 | Benchmarks exceed initial search | Tiered; B3 uses `list-head` (§10) |

### Rev 3 (6 hazards)

| # | Hazard | Resolution |
|---|---|---|
| 1 | Path conditions unavailable for holes | Guard-walker in `ObligationAssembly.hs` (§4.2.3) |
| 2 | "No new analysis" contradicts §7 | Corrected framing (§1) |
| 3 | Skolem instability | Alpha-canonical TVars (§3.2) |
| 4 | `(match-success)` not FQPred | Typed `PathEntry` with `kind` discriminator (§4.2.1) |
| 5 | `logic_fragment` conflates body/contract | Dual `contract_fragment` + `body_fragment` (§4.2.2) |
| 6 | `available_functions` unspecified | Type-compat filter, cap of 8 (§8) |

### Rev 4 (6 findings)

| # | Finding | Resolution |
|---|---|---|
| 1 | Result-match backing too coarse | `deriveBacking` checks emitter results, not form (§2.4) |
| 2 | ID rename stability incomplete | Full alpha-normalization: params, lets, match payloads (§3.2) |
| 3 | Guard walker uses wrong predicate test | Sort-aware `guardToPredPresentation` mirrors `guardToPredM` (§4.2.3) |
| 4 | `available_functions` excludes builtins | Split: `contracted_functions` + `available_functions` (§8) |
| 5 | Checkout fields need staleness rule | `ctSourceHash` + refresh-before-patch validation (§5.3) |
| 6 | `"non_linear"` too narrow | `"non_qf_lia"` + optional `reason` field (§4.2.2) |

### Rev 5 (4 clarifications)

| # | Finding | Resolution |
|---|---|---|
| 1 | Checkout activation underspecified | New fields emitted unconditionally (no checkout flag). §5.2 |
| 2 | Staleness guard misses evidence changes | Added `ctVerifiedHash` for `.verified.json` sidecar. §5.3 |
| 3 | Guard-walker scope threading incomplete | `ELet`/match/lambda extend env/SortEnv; unresolvable → `"structural"`. §4.2.3 |
| 4 | Roadmap names old flag in OBLIG-5 | Roadmap updated: `--obligation-report` replaces `--obligations`. External fix |

### Rev 6 (5 findings)

| # | Finding | Resolution |
|---|---|---|
| 1 | ELet sort fallback to FQInt misclassifies guards | Unannotated bindings omitted from SortEnv (sort-unknown → `"structural"`). §4.2.3 |
| 2 | `guardToPredPresentation` will drift from `guardToPredM` | Shared sort-checking core + OBLIG-2 regression test. §4.2.4 |
| 3 | `ctVerifiedHash` is single-module; MOD-1 uncovered | Documented as local-only; MOD-1 must extend to imported sidecars. §5.3 |
| 4 | ID normalization table overstates `$l`/`$m` coverage | Narrowed to `$p`/`$t` (active); `$l`/`$m` deferred. §3.2 |
| 5 | Ordering vocabulary ambiguous under polymorphism | Specified as post-zonking structural > unification-only > alphabetical. §8.2 |

### Rev 7 (4 findings)

| # | Finding | Resolution |
|---|---|---|
| 1 | `deriveBacking` used function-level membership lists | Per-clause-type lookup via `ConstraintTable`. §2.4 |
| 2 | ID stability overclaims local rename coverage | Narrowed to "parameter renames"; local binder caveat documented. §3.3 |
| 3 | Modules table omits `ctVerifiedHash` | Added to `Checkout.hs` row. §12 |
| 4 | Roadmap benchmark section stale | Updated to tiered benchmarks with `safe-first` via `list-head`. External fix |

### Rev 8 (3 findings)

| # | Finding | Resolution |
|---|---|---|
| 1 | `deriveBacking` not truly per-site; `ConstraintOrigin` lacks sub-function identity | Weakened claim to per-function per-clause-type; documented `ConstraintOrigin` fields. §2.4 |
| 2 | Partial-path claim false; `EIf`/`EMatch` are all-or-nothing | Corrected prose: all-or-nothing with forward pointer for future partial-path work. §2.4 |
| 3 | Termination obligations omitted | Added `termination-obligation` kind for `decreases` constraints. §2.3 |

---

## Appendix: Prior Spec Relationships

| Spec | Relationship |
|---|---|
| BODY-VC-0 | Re-exports `FlatPath` guards as typed `path_condition` entries |
| EVID-0 | Re-exports `EvidenceRecord` and `AssumptionKind` as trust channel |
| COMP-0 | Re-exports call-pre diagnostics as `precondition-obligation` |
