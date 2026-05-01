# COMP-0 — Design Specification

> **Version:** Rev 2 — Professor's review incorporated  
> **Date:** 2026-05-01  
> **Implements:** compiler-team-roadmap.md § v0.9 (Compositional Verification)  
> **Prerequisites:** v0.8.0 (BODY-VC) shipped, v0.8.1b (EVID-0) approved  
> **Reviewed:** Professor (2026-05-01) — conditional approve, 5 issues resolved  
> **Status:** APPROVED — ready for COMP-1

---

## 1. Motivation and Current Compositionality Gap

[bodyToPredM](../../compiler/src/LLMLL/FixpointEmit.hs#L571) falls back to `Nothing` for all `EApp` calls to user-defined functions (line 698–699: `bodyToPredM _ _ _ = return Nothing`). This means:

```lisp
(def-logic safe-subtract [a: int b: int]
  (pre  (>= a b))
  (post (= result (- a b)))
  (- a b))

(def-logic withdraw [balance: int amount: int]
  (pre  (>= balance amount))
  (post (>= result 0))
  (safe-subtract balance amount))  ;; body falls back — NOT body-faithful
```

`withdraw` calls `safe-subtract`, which is itself body-faithful. But `bodyToPredM` returns `Nothing` for the `EApp "safe-subtract" [...]` node, so `withdraw` falls back to contract-only verification. The postcondition `result >= 0` is never proven against the body.

**What COMP-0 must enable:** Compositional verification — when function `f` calls function `g`, the verifier should:
1. **Prove** that `f` satisfies `g`'s precondition at the call site (obligation)
2. **Assume** `g`'s postcondition holds for the result (hypothesis)
3. Use the assumed postcondition to prove `f`'s own postcondition

**Soundness anchor:** This is standard assume-guarantee reasoning. The callee's contract is the interface boundary. If both sides are independently verified, the composition is sound.

---

## 2. Assume-Guarantee Encoding for `EApp`

### 2.1 Encoding Rules

Given caller `f` with path condition Γ, encountering call `(g e₁ ... eₙ)`:

**Step 1 — Argument translation:** Translate each argument `eᵢ` via `bodyToPredM`. If any argument fails, the entire `EApp` falls back.

**Step 2 — Precondition obligation (PROVE polarity):**
```
Γ ⟹ pre_g[p₁ ↦ ⟦e₁⟧, ..., pₙ ↦ ⟦eₙ⟧]
```
This is a **constraint** the solver must discharge. The caller must satisfy the callee's precondition.

> [!CAUTION]
> **Polarity is critical.** The precondition is emitted as a constraint (RHS of an implication), NOT as a hypothesis (LHS). Emitting it as a hypothesis would allow the solver to assume it freely — a soundness hole.

**Step 3 — Postcondition hypothesis (ASSUME polarity):**
```
post_g[p₁ ↦ ⟦e₁⟧, ..., pₙ ↦ ⟦eₙ⟧, result ↦ result_g_fresh]
```
This is added to the **environment** (LHS of subsequent implications). The caller may use the callee's postcondition.

**Step 4 — Result binding:**
```
result_call = result_g_fresh
```
A fresh symbolic variable `_call_g_N` (global counter) represents the call result.

### 2.2 Contract Variable Renaming

Callee contracts reference parameter names `p₁...pₙ` and `result`. These must be alpha-renamed to avoid collision with the caller's namespace:

```haskell
-- Callee: (def-logic g [x: int y: int] (pre (>= x y)) (post (= result (- x y))) ...)
-- Call site in f: (g balance amount)
-- Substitution: x ↦ balance, y ↦ amount, result ↦ _call_g_0
```

The substitution map is built from the callee's parameter list and the translated argument predicates. `result` is always mapped to the fresh call-result variable.

### 2.3 BodyVC Extension: `CallVC` Constructor

```haskell
data BodyVC
  = SimpleVC [LetBinding] FQPred
  | BranchVC FQPred BodyVC BodyVC
  | CallVC                              -- NEW (v0.9)
    { cvCallee      :: Name             -- callee function name
    , cvArgs        :: [FQPred]         -- translated argument predicates
    , cvPreObligation :: Maybe FQPred   -- callee pre after substitution (PROVE)
    , cvPostAssumption :: Maybe FQPred  -- callee post after substitution (ASSUME)
    , cvResultVar   :: Name             -- fresh result variable (_call_g_N)
    , cvResultSort  :: FQSort           -- sort of the result
    , cvContinuation :: BodyVC          -- rest of the body after the call
    }
  deriving (Show, Eq)
```

**Why a new constructor instead of emission-level handling:** The compiler team raised this in the implementation plan review. A `CallVC` constructor is preferred because:
1. `flattenBodyVC` needs to thread the obligation and assumption through path splitting
2. The obligation must appear as a **separate** constraint from the body-post constraint
3. The assumption must be added to the LHS of all subsequent constraints on the same path

### 2.4 Flattening `CallVC`

```haskell
flattenBodyVC (CallVC callee args mPre mPost resultVar sort cont) =
  -- Flatten the continuation
  let contPaths = flattenBodyVC cont
  -- For each continuation path, prepend:
  --   1. A let-binding for the result variable (unconstrained — sort only)
  --   2. The postcondition assumption as an additional guard
  in [ ( conjoinAll [guard, fromMaybe FQTrue mPost]
       , LetBinding resultVar sort (FQVar resultVar) : lbs
       , resultPred )
     | (guard, lbs, resultPred) <- contPaths
     ]
  -- The precondition obligation is emitted as a SEPARATE constraint
  -- during emitFnConstraints, not folded into the body-post constraint.
```

### 2.5 Precondition Obligation Emission

For each `CallVC` encountered during constraint emission:

```
Constraint tag: [fnName, "call-pre", calleeName]
LHS: guard ∧ pre_caller ∧ accumulated_bindings
RHS: pre_callee[substituted]
```

This is emitted as an independent constraint with its own constraint ID and origin entry in the `ConstraintTable`. If the solver reports UNSAFE on this constraint, `ObligationMining.hs` can produce a structured diagnostic (COMP-5).

---

## 3. Contract Lookup Architecture

### 3.1 `ContractEnv` — Statement-Level Contract Map

`bodyToPredM` currently has no access to other functions' contracts. A new parameter is needed:

```haskell
type ContractEnv = Map Name ([(Name, Type)], Contract, Maybe Type)
-- Maps function name → (parameter list, contract, return type annotation)
-- Return type needed for EMatch sort derivation (§5.3, Issue 5)

buildContractEnv :: [Statement] -> ContractEnv
buildContractEnv stmts = Map.fromList $ mapMaybe go stmts
  where
    go (SDefLogic name params mRet contract _) = Just (name, (params, contract, mRet))
    go (SLetrec name params mRet contract _ _) = Just (name, (params, contract, mRet))
    go _ = Nothing
```

### 3.2 Updated `bodyToPredM` Signature

```haskell
bodyToPredM :: Map Name Name   -- renaming env
            -> SortEnv         -- sort env
            -> ContractEnv     -- NEW: contract lookup
            -> Set Name        -- NEW: recursive SCC set (§4)
            -> Expr
            -> State Int (Maybe BodyVC)
```

### 3.3 `EApp` Case in `bodyToPredM`

```haskell
-- User-defined function call with contract
-- Issue 4 resolution: SCC guard REMOVED. Callers of recursive functions
-- may use assume-guarantee against the recursive function's contract.
-- The recursive function's own body VC remains excluded (§4.1).
-- Trust degrades via evidenceMeet — see §4.4.
bodyToPredM env se cenv sccSet (EApp fname args)
  | fname `Map.member` cenv
  = do
    -- Translate arguments
    mArgVCs <- mapM (bodyToPredM env se cenv sccSet) args
    let mArgPreds = sequence [p | Just (SimpleVC [] p) <- mArgVCs]
    case mArgPreds of
      Nothing -> return Nothing  -- argument translation failed
      Just argPreds -> do
        let (params, contract, mRetType) = cenv Map.! fname
            paramNames = map fst params
        -- Build substitution: callee params → translated args
        let subst = Map.fromList (zip paramNames argPreds)
        -- Issue 1 resolution: three-way pre distinction (soundness-critical)
        --   callee has no pre        → no obligation, assumption valid
        --   callee has pre, translates → obligation emitted
        --   callee has pre, fails     → ENTIRE CALL FALLS BACK
        let mPreResult = case contractPre contract of
              Nothing  -> Just Nothing
              Just pre -> case exprToPred pre of
                            Nothing -> Nothing       -- untranslatable pre → fallback
                            Just p  -> Just (Just (applySubst subst p))
        case mPreResult of
          Nothing -> return Nothing  -- soundness: cannot assume post without verifying pre
          Just mPrePred -> do
            -- Translate post (Nothing = no post → no assumption)
            let mPostPred = contractPost contract >>= exprToPred
            -- Fresh result variable
            resultVar <- freshName ("call_" <> fname)
            let mPostSubst = fmap (\p -> applySubst (Map.insert "result" (FQVar resultVar) subst) p) mPostPred
                retSort = maybe FQInt typeToSort mRetType
            -- Issue 3 resolution: return CallVC directly (Option A)
            -- The enclosing ELet case fills the real continuation.
            return $ Just $ CallVC
              { cvCallee         = fname
              , cvArgs           = argPreds
              , cvPreObligation  = mPrePred
              , cvPostAssumption = mPostSubst
              , cvResultVar      = resultVar
              , cvResultSort     = retSort
              , cvContinuation   = SimpleVC [] (FQVar resultVar)
              }
```

**Practical pattern:** Most call sites appear as `(let [[r (g x y)]] body)`. The `ELet` case recognizes when its RHS is a `CallVC` and threads the continuation:

```haskell
-- ELet with CallVC RHS: thread the body as the continuation
bodyToPredM env se cenv sccSet (ELet [(PVar v, _, rhs)] body)
  -- ... (existing SimpleVC and BranchVC cases unchanged) ...
  -- NEW: CallVC in let RHS
  Just (CallVC cal args mPre mPost rVar rSort _cont) -> do
    renamed <- freshName v
    let env' = Map.insert v renamed env
        se'  = Map.insert renamed rSort se
    mBodyVC <- bodyToPredM env' se' cenv sccSet body
    case mBodyVC of
      Nothing -> return Nothing
      Just bvc -> return $ Just $ CallVC cal args mPre mPost rVar rSort bvc
```

### 3.4 `applySubst` — Predicate Substitution

```haskell
applySubst :: Map Name FQPred -> FQPred -> FQPred
applySubst subst (FQVar v) = Map.findWithDefault (FQVar v) v subst
applySubst subst (FQBinPred op l r) = FQBinPred op (applySubst subst l) (applySubst subst r)
applySubst subst (FQBinArith op l r) = FQBinArith op (applySubst subst l) (applySubst subst r)
applySubst subst (FQAnd ps) = FQAnd (map (applySubst subst) ps)
applySubst subst (FQOr ps) = FQOr (map (applySubst subst) ps)
applySubst subst (FQNot p) = FQNot (applySubst subst p)
applySubst _ p = p  -- FQLit, FQTrue, FQFalse unchanged
```

---

## 4. SCC Detection for Recursive Functions

### 4.1 Motivation

Recursive call cycles cannot use assume-guarantee reasoning **for the recursive function's own body VC** without inductive hypotheses (deferred to Lean integration). Functions in recursive SCCs are **excluded from body-faithful verification of their own bodies**. However, **callers of recursive functions** may use assume-guarantee reasoning against the recursive function's contract, treating it as an opaque interface (see §4.4).

### 4.2 Reuse Existing Infrastructure

[HoleAnalysis.hs](../../compiler/src/LLMLL/HoleAnalysis.hs#L538-L544) already has `buildCallGraph` and uses `Data.Graph.stronglyConnComp` for hole dependency analysis. The same `extractCalls` function exists in both [HoleAnalysis.hs:524](../../compiler/src/LLMLL/HoleAnalysis.hs#L524) and [TrustReport.hs:178](../../compiler/src/LLMLL/TrustReport.hs#L178).

**Refactoring plan:** Extract `buildCallGraph` and `extractCalls` into a shared utility (or reuse from `HoleAnalysis`), then compute SCCs at the top level in `emitFixpointWith`:

```haskell
-- In emitFixpointWith, before processing statements:
let callGraph = buildCallGraph stmts
    sccs = stronglyConnComp
      [(name, name, deps) | (name, deps) <- Map.toList callGraph]
    recursiveNames = Set.fromList $ concatMap getRecursive sccs
      where
        getRecursive (AcyclicSCC _) = []
        getRecursive (CyclicSCC ns) = ns
```

`recursiveNames` is passed to `bodyToPredM` as the SCC set. For the function's **own** body VC, membership in `recursiveNames` causes fallback (letrec already excluded). For **callers**, the SCC set is used to degrade trust level but not to prevent assume-guarantee encoding (see §3.3, §4.4).

### 4.3 Self-Recursion

A function that calls itself (direct recursion) forms a trivial SCC of size 1. `letrec` functions are already excluded from body VCs (line 352: `Nothing -> pure ()`). Non-letrec `def-logic` functions that somehow call themselves should also fall back — the SCC set handles this uniformly.

### 4.4 Callers of Recursive Functions (Issue 4 Resolution)

> [!NOTE]
> **Professor Review Issue 4 — resolved by relaxation.**

A call to a recursive function with a valid contract uses assume-guarantee reasoning (§2). The caller's effective display level degrades via `evidenceMeet`:

- Recursive callee is `DLContractChecked` → caller effective level ≤ `DLContractChecked`
- Recursive callee is `DLAsserted` → caller effective level ≤ `DLAsserted`

The recursive function's own body VC remains excluded (§4.1). This relaxation is sound because assume-guarantee against a contract is independent of whether the callee's body is verified — it depends only on whether the contract holds, which is the callee's own verification responsibility.

**Effective display level cap:** A function that uses compositional reasoning against a recursive callee can be at most `DLContractChecked`, never `DLVerified`, because the callee's body VC is not available to justify `DLVerified`.

---

## 5. `EMatch` on `Result a e` — Two-Path Encoding

### 5.1 Motivation

`EMatch` is currently unsupported in `bodyToPredM` (line 698–699: catch-all `Nothing`). The most common and valuable case is matching on `Result`:

```lisp
(def-logic process-withdrawal [balance: int amount: int]
  (pre  (> balance 0))
  (post (>= result 0))
  (match (safe-subtract balance amount)
    ((Success val) val)
    ((Error _) balance)))
```

### 5.2 Supported Fragment

**COMP-0 scope:** `EMatch` on `Result a e` only (two constructors: `Success` and `Error`). General ADT matching is deferred.

**Detection:** The scrutinee's type must resolve to `TResult ok_type err_type`. In practice, this means the scrutinee is a call to a function whose return type is `Result`. Type information is available via the `SortEnv` or parameter annotations.

### 5.3 Encoding Rule

> [!IMPORTANT]
> **Constructor-independent postcondition requirement (Issue 2 resolution).** The callee's postcondition expression must not itself contain `EMatch` on `result`. If `contractPost` contains an `EMatch` on `result`, the `EMatch` encoding falls back to `Nothing`. This prevents unsound assumptions when the postcondition assigns different guarantees per constructor. Full constructor-decomposed postconditions are deferred (§13).

```haskell
-- | Does the postcondition use constructor-dependent reasoning?
isConstructorDependent :: Expr -> Bool
isConstructorDependent (EMatch (EVar "result") _) = True
isConstructorDependent (EMatch _ _)                = False
isConstructorDependent (EApp _ args) = any isConstructorDependent args
isConstructorDependent (ELet _ body) = isConstructorDependent body
isConstructorDependent (EIf _ t e)   = isConstructorDependent t || isConstructorDependent e
isConstructorDependent _             = False
```

```
⟦EMatch scrutinee [(PConstructor "Success" [PVar s], bodyS),
                    (PConstructor "Error"   [PVar e], bodyE)]⟧ =
  -- Issue 2: reject constructor-dependent postconditions
  case contractPost contract of
    Just post | isConstructorDependent post -> Nothing  -- fallback
    _ ->
  -- Issue 5: resolve Success/Error sorts from callee return type (ContractEnv)
  let (_, _, mRetType) = cenv Map.! fname
  in case mRetType of
    Just (TResult okType errType) ->
      let okSort  = typeToSort okType
          errSort = typeToSort errType
          scrutVC = ⟦scrutinee⟧
      in case scrutVC of
        Just svc ->
          -- Success branch: bind s to scrutinee result, translate bodyS
          let envS = Map.insert s resultVar env
              seS  = Map.insert resultVar okSort se
              bodyS_VC = ⟦bodyS⟧_envS
          -- Error branch: bind e, translate bodyE
              envE = Map.insert e resultVar env
              seE  = Map.insert resultVar errSort se
              bodyE_VC = ⟦bodyE⟧_envE
          in BranchVC
               (FQVar "_match_success")  -- synthetic guard
               bodyS_VC
               bodyE_VC
        Nothing -> Nothing
    _ -> Nothing  -- non-Result or unannotated return type → fallback
```

**Guard encoding:** The success/error distinction is modeled as a synthetic boolean guard. The solver treats each branch independently — the success branch assumes success, the error branch assumes error. Path conditions are conjunctive, so the two branches are disjoint. The guard carries no semantic content for constructor-independent postconditions (this is correct — both branches get the same postcondition assumption). Constructor-dependent postconditions are rejected by the `isConstructorDependent` check above.

### 5.4 Interaction with `CallVC`

The common pattern `(match (g x y) ...)` combines `EApp` (§2) and `EMatch` (§5):
1. `g x y` produces a `CallVC` with the call's postcondition
2. The match destructures the result into success/error branches
3. Each branch gets the relevant portion of the postcondition

This interaction is handled by the `ELet` desugaring: `(match (g x y) ...)` is equivalent to `(let [[_r (g x y)]] (match _r ...))` after the parser normalizes the AST.

---

## 6. Transitive Trust Degradation

### 6.1 Integration with v0.8.1b Evidence Model

[TrustReport.hs:226–260](../../compiler/src/LLMLL/TrustReport.hs#L226-L260) already computes transitive effective levels via `enrichEntry` using `evidenceMeet` from the diamond lattice. COMP-4 extends this to use the new `DisplayLevel` tiers:

**Rule:** A function's effective display level is `evidenceMeet` of its own level and all transitively reachable callees' levels.

```
effectiveLevel(f) = evidenceMeet(ownLevel(f), ⊓{ effectiveLevel(g) | g ∈ transitiveDeps(f) })
```

**Already implemented in v0.8.1b:** The `enrichEntry` function does exactly this. COMP-4's work is:
1. Ensure the call graph used by `enrichEntry` matches the call graph used by SCC detection (§4)
2. Add test coverage for degradation chains: `verified → contract-checked → tested → asserted`

### 6.2 Degradation Examples

| Scenario | f's own level | callee chain | f's effective level |
|---|---|---|---|
| Verified chain | `DLVerified` | all `DLVerified` | `DLVerified` |
| One contract-checked | `DLVerified` | one `DLContractChecked` | `DLContractChecked` |
| Mixed incomparable | `DLVerified` | `DLContractChecked` + `DLTested` | `DLAsserted` |
| Recursive fallback | `DLContractChecked` | self-recursive | `DLContractChecked` (no body VC) |

---

## 7. Call-Site Precondition Failure Diagnostics (COMP-5)

### 7.1 Integration with `ObligationMining.hs`

[ObligationMining.hs](../../compiler/src/LLMLL/ObligationMining.hs) already handles UNSAFE constraint analysis. COMP-5 extends it for call-site precondition failures:

When a `call-pre` constraint (§2.5) is UNSAFE:

```
✗ Call-site precondition failure
  Caller: withdraw
  Callee: safe-subtract
  Required: (>= a b)  [callee pre, substituted: (>= balance amount)]
  Path condition: (> balance 0)
  Gap: path condition does not imply callee precondition
  Suggested repair: strengthen caller precondition to (>= balance amount)
```

### 7.2 Constraint Origin Extension

```haskell
-- New ConstraintOrigin tag for call-site preconditions:
ConstraintOrigin
  { coFunction = "withdraw"
  , coClause   = "call-pre"       -- NEW tag
  , coJsonPtr  = "/statements/1/body/..."
  , coSrcFile  = "example.llmll"
  }
```

The `coClause = "call-pre"` tag allows `ObligationMining.hs` to distinguish call-site failures from contract failures and produce targeted suggestions.

---

## 8. `--strict-verified-core` Build Mode (COMP-6)

### 8.1 Semantics

`llmll build --strict-verified-core` is a build mode that **hard-errors** on:
1. Any function with unproven call-site preconditions
2. Any function that falls back to contract-only (not body-faithful)
3. Any function in a recursive SCC (cannot be body-faithful)

This is distinct from `--strict` (which hard-errors on typecheck warnings). It targets the verification pipeline specifically.

### 8.2 Implementation

Add a flag to `EmitOptions`:

```haskell
data EmitOptions = EmitOptions
  { emitBodyVCs        :: Bool
  , emitStrictVerified :: Bool   -- NEW: hard-error on fallback/unproven
  } deriving (Show, Eq)
```

After verification, if `emitStrictVerified` is `True`:
- Any function in `erBodyFallback` → hard error
- Any UNSAFE `call-pre` constraint → hard error

---

## 9. Soundness Argument

### 9.1 Per-Function Soundness (from BODY-VC-0)

For each non-recursive `def-logic f [params] (pre P) (post Q) body`:

> **VC:** `P ∧ (result = ⟦body⟧) ⟹ Q`

If the solver reports SAFE, then for all well-typed inputs satisfying P, the body produces a result satisfying Q. This is unchanged from [body-vc-0-spec.md §7](body-vc-0-spec.md#7-soundness-argument).

### 9.2 Compositional Soundness (new in COMP-0)

For caller `f` calling callee `g`:

**Obligation:** `Γ_f ⟹ pre_g[args]` (solver MUST discharge)  
**Assumption:** `post_g[args, result_g]` (solver MAY use)

**Argument:** If `g` is independently verified (its own body VC is SAFE), then `post_g` holds for all inputs satisfying `pre_g`. The obligation proves that `f` provides such inputs. Therefore, the assumption is justified.

**Recursive case:** Recursive functions' **own** body VCs are excluded (§4.1). **Callers** of recursive functions may use assume-guarantee against the recursive function's contract (§4.4). Trust degrades via `evidenceMeet` — the caller's effective display level is at most `DLContractChecked`. This is the same reasoning used for any callee whose body VC is unavailable.

### 9.3 Proof Obligations Summary

| ID | Property | Verified by |
|-----|----------|------------|
| PO-1 | Callee pre is an obligation (RHS), not a hypothesis | Constraint polarity in §2.5 |
| PO-2 | Callee post is justified by callee's own body VC | Independent verification |
| PO-3 | Recursive functions excluded from own body VC | SCC detection (§4); callers may use assume-guarantee (§4.4) |
| PO-4 | Contract variable substitution is capture-free | Alpha-renaming with fresh names (§2.2) |
| PO-5 | Path conditions are conjunctive and disjoint | Inherited from BODY-VC-0 flattening |
| PO-6 | Trust degradation is monotonic (meet is ≤ both inputs) | `evidenceMeet` lattice laws (EVID-0) |
| PO-7 | Untranslatable callee pre → entire call falls back | Three-way distinction in §3.3 (Issue 1) |
| PO-8 | Constructor-dependent postconditions rejected in EMatch | `isConstructorDependent` check in §5.3 (Issue 2) |

**TCB:** `CodegenHs.hs` · `bodyToPred` · `exprToPred` · `applySubst` · `isConstructorDependent` · `liquid-fixpoint` · Z3 · GHC

---

## 10. Test Matrix (COMP-T)

### Positive (SAFE) — 9 tests

| ID | Description | Paths |
|----|-------------|-------|
| C01 | Simple call: `f` calls verified `g`, postcondition proven | 1 |
| C02 | Call chain: `f` → `g` → `h`, all verified | 1 |
| C03 | Call with let-binding: `(let [[r (g x)]] (+ r 1))` | 1 |
| C04 | Call in if-branch: `(if cond (g x) (h x))` | 2 |
| C05 | Multiple calls: `(+ (g x) (h y))` | 1 |
| C06 | `EMatch` on `Result`: success + error branches | 2 |
| C07 | Call with precondition satisfied by caller's pre | 1 |
| C08 | Degraded chain: `DLVerified` calling `DLContractChecked` → effective `DLContractChecked` | 1 |
| C09 | Non-recursive caller calls recursive callee with contract → assume-guarantee, effective `DLContractChecked` | 1 |

### Negative (UNSAFE) — 4 tests

| ID | Description |
|----|-------------|
| N01 | Call-site precondition not satisfied (caller pre too weak) |
| N02 | Call result used without postcondition match |
| N03 | Wrong argument order: `(g amount balance)` vs `(g balance amount)` |
| N04 | Missing guard before call in conditional branch |

### Fallback — 7 tests

| ID | Trigger |
|----|---------|
| F01 | Call to function without contracts (no pre/post) |
| F02 | Call to recursive function **without** contract → fallback |
| F03 | Call to function with non-QF-LIA contract |
| F04 | Call with non-translatable argument |
| F05 | `EMatch` on non-`Result` type |
| F06 | Call to function with non-QF-LIA precondition (e.g., `(pre (* x x))`) → entire call falls back (Issue 1) |
| F07 | Callee has constructor-dependent postcondition (`match result` in post) → `EMatch` encoding falls back (Issue 2) |

### Edge — 5 tests

| ID | Case |
|----|------|
| E01 | Callee has pre but no post → obligation emitted, no assumption |
| E02 | Callee has post but no pre → assumption used, no obligation |
| E03 | Self-recursive `def-logic` (not `letrec`) → SCC fallback |
| E04 | Mutual recursion A↔B → both fall back |
| E05 | Call in nested let: `(let [[a (g x)]] (let [[b (h a)]] b))` |

### Stripping Regression — 4 tests

| ID | Description |
|----|-------------|
| S01 | Verified chain: all postconditions strippable |
| S02 | Degraded chain: callee contract-only → caller not strippable |
| S03 | Mixed chain with `--strict-verified-core` → hard error |
| S04 | `--contracts=unproven` with compositional body-faithful |

### Trust Report — 2 tests

| ID | Description |
|----|-------------|
| R01 | Trust report shows transitive degradation |
| R02 | Trust report distinguishes call-site obligation from body-post |

**Total: 31 tests.** Layout: `compiler/test/golden/comp/{positive,negative,fallback,edge,stripping,trust}/`

---

## 11. Modules Affected

| Module | Change | Phase |
|--------|--------|-------|
| [FixpointEmit.hs](../../compiler/src/LLMLL/FixpointEmit.hs) | `CallVC` constructor, `bodyToPredM` EApp case, `applySubst`, `ContractEnv`, SCC set parameter, `flattenBodyVC` extension, call-pre constraint emission | COMP-1 |
| [FixpointIR.hs](../../compiler/src/LLMLL/FixpointIR.hs) | No changes expected | — |
| [HoleAnalysis.hs](../../compiler/src/LLMLL/HoleAnalysis.hs) | Extract `buildCallGraph`/`extractCalls` for reuse (or import) | COMP-2 |
| [TrustReport.hs](../../compiler/src/LLMLL/TrustReport.hs) | Ensure call graph consistency with SCC detection; test degradation chains | COMP-4 |
| [ObligationMining.hs](../../compiler/src/LLMLL/ObligationMining.hs) | `call-pre` clause handling, structured call-site diagnostics | COMP-5 |
| [DiagnosticFQ.hs](../../compiler/src/LLMLL/DiagnosticFQ.hs) | `call-pre` tag in `ConstraintOrigin` | COMP-1 |
| [Contracts.hs](../../compiler/src/LLMLL/Contracts.hs) | No changes expected (body-faithful flag already per-function) | — |
| [Main.hs](../../compiler/src/LLMLL/Main.hs) | `--strict-verified-core` flag | COMP-6 |

---

## 12. Implementation Sequence

```
COMP-0 (this document — design review)
    ▼
COMP-1: bodyToPredM EApp case + CallVC + ContractEnv + applySubst
         + call-pre constraint emission + flattenBodyVC extension
         + fresh call-result counter
    ▼
COMP-2: SCC detection (reuse Data.Graph.stronglyConnComp)
         + recursive set passed to bodyToPredM
         + extractCalls shared utility
    ▼
COMP-3: bodyToPredM EMatch on Result (two-path encoding)
         + synthetic success/error guard
    ▼
COMP-4: Transitive trust degradation test coverage
         + call graph consistency with SCC detection
    ▼
COMP-5: ObligationMining.hs call-pre diagnostics
         + structured repair suggestions
    ▼
COMP-6: --strict-verified-core flag + hard-error on fallback
    ▼
COMP-T: 31 golden tests (parallel with COMP-2+)
```

---

## 13. Deferred Constructs

| Construct | Phase | Reason |
|-----------|-------|--------|
| `EMatch` on general ADTs | v0.10+ | Requires constructor-refined sort env |
| Constructor-dependent postcondition decomposition | v0.10+ | Requires per-constructor sub-postcondition extraction (Issue 2) |
| `EMatch` on `Result` with inferred (unannotated) return type | v0.10+ | Requires type-checker output threaded into `bodyToPredM` (Issue 5) |
| Recursive function induction | LEAN-GA | Needs inductive hypothesis (Lean) |
| Higher-order calls (`ELambda` args) | Out of scope | Requires function summaries for lambdas |
| Cross-module calls | Future | Requires module-level `ContractEnv` |
| Non-QF-LIA callee contracts | Out of scope | Outside decidable fragment |
| `EDo` / effectful calls | Out of scope | Monadic reasoning not in fragment |

---

## 14. Key Design Decisions

| Decision | Resolution |
|----------|-----------|
| `CallVC` constructor vs emission-level handling | `CallVC` as intermediate node — Option A (Issue 3). Consistent with `BranchVC` pattern. |
| Precondition as constraint (PROVE) not hypothesis | Accepted — soundness-critical polarity |
| Untranslatable callee pre → entire call falls back | Three-way distinction mirrors BODY-VC-0 fallback policy (Issue 1) |
| Constructor-dependent postconditions rejected in EMatch | `isConstructorDependent` guard (Issue 2). Full decomposition deferred. |
| Callers of recursive functions may use assume-guarantee | Relaxation accepted (Issue 4). Trust degrades via `evidenceMeet`. |
| `ContractEnv` includes return type | `Maybe Type` needed for EMatch sort derivation (Issue 5) |
| SCC detection via `Data.Graph.stronglyConnComp` | Accepted — reuse existing infrastructure from `HoleAnalysis.hs` |
| `EMatch` limited to `Result` | Accepted — highest-value case, avoids general ADT sort env |
| Contract variable substitution via `applySubst` | Accepted — simple, capture-free with fresh names |
| `--strict-verified-core` as separate flag from `--strict` | Accepted — orthogonal concerns (typecheck vs verification) |
| Trust degradation reuses `evidenceMeet` | Accepted — lattice laws proven in EVID-0 |
| 31-test matrix | Accepted — covers all encoding rules, polarities, edge cases, and review issues |

---

## Appendix: Professor Review Issues (Resolved)

| # | Issue | Severity | Resolution |
|---|-------|----------|------------|
| 1 | Untranslatable precondition → free pass on obligation | Correctness | Three-way pre distinction in §3.3; test F06 |
| 2 | `EMatch` guard semantically vacuous for constructor-dependent postconditions | Correctness | `isConstructorDependent` guard in §5.3; test F07 |
| 3 | `bodyToPredM` returns `SimpleVC` but spec describes `CallVC` flattening | Architecture | Option A: `CallVC` as intermediate node in §3.3 |
| 4 | Recursive callee → entire caller falls back | Ergonomics | Relaxation: allow assume-guarantee against recursive contracts (§4.4); test C09 |
| 5 | `EMatch` binding sort derivation not specified | Completeness | `ContractEnv` extended with `Maybe Type` (§3.1); sort resolved from `TResult` in §5.3 |
