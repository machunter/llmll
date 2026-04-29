# BODY-VC-0 — Design Specification

> **Version:** Final Rev 4 — **APPROVED** (all 5 agents signed off)  
> **Date:** 2026-04-29  
> **Implements:** compiler-team-roadmap.md § v0.8.0 BODY-VC-0  
> **Soundness:** ✅ Signed off — structural induction confirmed coherent  
> **Feasibility:** ✅ Signed off (Agent 2) — all claims verified against codebase  
> **Solver:** ✅ Signed off (Agent 3) — QF-LIA closure, path completeness, conservative fallback  
> **Testability:** ✅ Signed off (Agent 4) — all 32 golden tests deterministic and unambiguous  
> **Extensibility:** ✅ Signed off (Agent 1) — no future extension path blocked

---

## 1. Motivation and Current Faithfulness Gap

[emitFnConstraints](../../compiler/src/LLMLL/FixpointEmit.hs#L108-L114) never passes the function body to the constraint generator. The body is silently dropped. The emitter checks that pre/post predicates are self-consistent in QF-LIA, but never encodes the function body:

```lisp
(def-logic withdraw [balance: int amount: int]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  42)  ;; WRONG — but verifier says SAFE
```

`VLProvenSMT "liquid-fixpoint"` (SMT proof evidence from liquid-fixpoint) means "the contract is satisfiable" — NOT "the body satisfies the contract." [isBodyFaithful](../../compiler/src/LLMLL/Contracts.hs#L191-L192) returns `False` unconditionally (BUG-6, v0.6.3), so runtime assertions are never stripped. The system is conservatively correct but verification is vacuous.

**What BODY-VC-0 Must Prove:** For `def-logic f [params] (pre P) (post Q) body`:

> **VC:** `P ∧ (result = ⟦body⟧) ⟹ Q`

Body-VCs are only emitted when a postcondition exists. Functions with only preconditions (or no contracts) produce no body constraints — there is nothing to prove.

**Operational Semantics Anchor:** Per [verification-debate-action-items.md:47](../../docs/design/verification-debate-action-items.md#L47): LLMLL's operational semantics are defined by the generated Haskell program.

---

## 2. Supported Fragment

```bnf
body  ::=  lit | var | binop(body, body) | unop(body)
         | let x = body in body | if body then body else body
lit   ::=  integer | bool
var   ::=  <int-typed identifier>
binop ::=  + | - | = | < | <= | >= | > | /= | and | or
unop  ::=  not
```

**Scope:** Non-recursive `def-logic` only. Any sub-expression outside this grammar → entire function falls back. No partial translation.

**Sort restriction for BODY-VC-0:** Variables (parameters and let-bindings used as values) are **int-typed only**. Boolean expressions appear as predicates (guards, comparisons) but not as first-class values bound to variables. Bool-typed variable support is deferred to BODY-VC-1 (requires sort environment — see §9).

**Guard restriction:** `EIf` guards must be leaf predicates — no `ELet` or nested `EIf` in guard position. Guards go through `exprToPred`, which does not handle `ELet`/`EIf`. Compound guards use `and`/`or`/`not` combinators.

---

## 3. Formal VC Rules

### 3.1 Core Types

```haskell
data BodyVC
  = SimpleVC [LetBinding] FQPred
  | BranchVC FQPred BodyVC BodyVC       -- guard, then-VC, else-VC

data LetBinding = LetBinding Text FQSort FQPred  -- renamed name, sort, rhs pred
```

### 3.2 Signature and Alpha-Renaming Strategy

```haskell
-- Public entry point (pure wrapper over stateful core)
bodyToPred :: Expr -> Maybe BodyVC
bodyToPred expr = evalState (bodyToPredM Map.empty expr) 0

-- Internal: carries renaming env + fresh-name counter
bodyToPredM :: Map Name Name -> Expr -> State Int (Maybe BodyVC)
```

Alpha-renaming is implemented via a `Map Name Name` renaming environment threaded through `bodyToPredM`. At each `ELet`, the bound variable `x` is mapped to a fresh name `_bv_x_N` (where N is a monotonic counter). `EVar x` consults the environment: `FQVar (fromMaybe x (Map.lookup x env))`. This is a single-pass approach — no AST modification.

**Counter scope:** The fresh-name counter in `State Int` is **global** across all functions in a single `emitFixpoint` invocation. Two functions that both shadow a parameter `x` produce `_bv_x_0` and `_bv_x_1` (not both `_bv_x_0`). This avoids name collisions in the shared `.fq` file. The counter is initialized to 0 at the start of `emitFixpoint` and threaded through all function emissions.

### 3.3 Translation Rules

**Entry normalization:**
```
⟦EOp name args⟧ = ⟦EApp name args⟧
```

**Leaves:**
```
⟦ELit (LitInt n)⟧  = SimpleVC [] (FQLit n)
⟦ELit (LitBool b)⟧ = SimpleVC [] (if b then FQTrue else FQFalse)
⟦EVar x⟧           = SimpleVC [] (FQVar (lookupRename env x))
⟦EApp op [l,r]⟧    = SimpleVC [] <$> exprToPred(EApp op [l,r])  -- delegates
⟦EApp "not" [a]⟧   = SimpleVC [] <$> exprToPred(EApp "not" [a])
⟦ELit _⟧           = Nothing
```

**Multi-binding ELet desugaring:**
```
⟦ELet [(p1,t1,e1),(p2,t2,e2),...] body⟧ =
  ⟦ELet [(p1,t1,e1)] (ELet [(p2,t2,e2),...] body)⟧
```

**ELet (single PVar binding):**
```
⟦ELet [(PVar x, _, rhs)] body⟧ =
  x' ← freshName(x)                      -- "_bv_x_N", counter++
  env' = Map.insert x x' env             -- extend renaming env
  case ⟦rhs⟧ of                          -- rhs uses OUTER env (x not yet renamed)
    Just (SimpleVC bs rhsPred) →
      let lb = LetBinding x' (predSort rhsPred) rhsPred
      in case ⟦body⟧_env' of             -- body uses EXTENDED env
           Just (SimpleVC bs' p)  → SimpleVC (bs++[lb]++bs') p
           Just (BranchVC g t e)  → BranchVC g (prepend (bs++[lb]) t) (prepend (bs++[lb]) e)
           Nothing                → Nothing
    Just (BranchVC g tVC eVC) →           -- EIf-in-ELet RHS: hoist
      hoistBranch x' g tVC eVC body env'
    Nothing → Nothing

⟦ELet [(nonPVar, _, _)] _⟧ = Nothing
```

**`hoistBranch` (hoisting helper for EIf-in-ELet RHS):**
```
hoistBranch x' guard thenVC elseVC body env' =
  case (leafOf thenVC, leafOf elseVC) of
    (Just (tBs, tPred), Just (eBs, ePred)) →
      let tLB = LetBinding x' FQInt tPred
          eLB = LetBinding x' FQInt ePred
          contVC = ⟦body⟧_env'
      in case contVC of
           Just vc → Just (BranchVC guard (prepend (tBs++[tLB]) vc) (prepend (eBs++[eLB]) vc))
           Nothing → Nothing
    _ → Nothing   -- nested branching in branch leaf — fallback

leafOf :: BodyVC -> Maybe ([LetBinding], FQPred)
leafOf (SimpleVC bs p) = Just (bs, p)
leafOf (BranchVC _ _ _) = Nothing   -- recursive hoisting not supported in BODY-VC-0
```

**EIf — guard-in-LHS split:**
```
⟦EIf guard thenE elseE⟧ =
  case (exprToPred guard, ⟦thenE⟧, ⟦elseE⟧) of
    (Just gPred, Just tVC, Just eVC) → BranchVC gPred tVC eVC
    _ → Nothing
```

Guard goes through `exprToPred` (predicate-position). Branches go through `bodyToPredM` (value-position). If any sub-expression fails, the entire `EIf` returns `Nothing`.

**Unsupported → `Nothing`:** `EMatch`, `EApp` (user-defined), `ELambda`, `EDo`, `EHole`, `EAwait`, `EPair`, non-linear ops (`*`,`/`,`mod`).

### 3.4 Flattening and Helpers

```haskell
type FlatPath = (FQPred, [LetBinding], FQPred)  -- guard, binders, resultPred

flattenBodyVC :: BodyVC -> [FlatPath]
flattenBodyVC (SimpleVC bs p)      = [(FQTrue, bs, p)]
flattenBodyVC (BranchVC g tVC eVC) =
  [(conjoin g gT, bsT, pT)         | (gT, bsT, pT) <- flattenBodyVC tVC] ++
  [(conjoin (FQNot g) gE, bsE, pE) | (gE, bsE, pE) <- flattenBodyVC eVC]

conjoin :: FQPred -> FQPred -> FQPred
conjoin FQTrue p = p
conjoin p FQTrue = p
conjoin p q      = FQAnd [p, q]

conjoinAll :: [FQPred] -> FQPred
conjoinAll = foldr conjoin FQTrue

predSort :: FQPred -> FQSort
predSort (FQLit _)          = FQInt
predSort (FQBinArith _ _ _) = FQInt    -- FQAdd/FQSub only
predSort FQTrue             = FQBool
predSort FQFalse            = FQBool
predSort (FQBinPred _ _ _)  = FQBool   -- comparison ops only
predSort (FQAnd _)          = FQBool
predSort (FQOr _)           = FQBool
predSort (FQNot _)          = FQBool
predSort (FQVar _)          = FQInt    -- BODY-VC-0: int-only vars
predSort _                  = FQInt
```

**Path limit:** Warn at 256 paths, error at 4096. Counts emitted paths (leaves of `BodyVC` tree).

### 3.5 Constraint Emission

**Precondition:** Body VCs require `contractPost` to be `Just`. If no postcondition exists, no body constraint is emitted (the body VC proves `body ⊢ post` — without `post`, nothing to prove).

For each `FlatPath (guard, binders, resultPred)`:

```
-- Emit let-binders with fresh IDs
for each LetBinding in binders:
  bid <- freshBid
  addBind (FQBind bid name (FQReft "v" sort (FQBinPred FQEq (FQVar "v") pred)))

-- Emit result binder
rbid <- freshBid
-- retSort derivation: use mRet annotation if present, else infer from body
retSort = case mRet of
  Just t  -> typeToSort t
  Nothing -> predSort resultPred   -- infer from body translation
addBind (FQBind rbid "result" (FQReft "v" retSort FQTrue))

-- Build LHS: guard ∧ pre ∧ (result = resultPred)
-- Omit pre if absent (no true placeholder). Omit guard if FQTrue.
lhsPred = conjoinAll (filter (/= FQTrue) [guard, pre, FQBinPred FQEq (FQVar "result") resultPred])

-- Emit constraint
constraint env=(paramIds ++ letIds ++ [rbid])
  lhs { result : retSort | lhsPred }
  rhs { result : retSort | postPred }
  tag [fnName; "body-post" / "body-post-then" / "body-post-else"]
  jsonPtr = "/statements/" <> show stmtIdx <> "/body"
```

**Additive:** Body VCs supplement existing pre/post/decreases constraints. Never replace them. Diagnostics must distinguish body-faithful failures from contract self-consistency failures (see below).

**`emitBodyVCs` gate:** A `Bool` field in the emitter's config record (threaded through `emitFixpoint`), set to `True` by BODY-VC-2. No CLI flag — purely internal, controlled by compiler version.

**Diagnostic format for body-post tags:** BODY-VC-2 must update `toDiag` in [DiagnosticFQ.hs](../../compiler/src/LLMLL/DiagnosticFQ.hs) to handle body-post tags with a distinct message format. The current `coClause <> "-condition"` pattern produces awkward output for body tags. Required messages:
- `"body-post"` → `"body verification of '" <> fn <> "' failed"`
- `"body-post-then"` → `"body verification of '" <> fn <> "' failed (then-branch)"`
- `"body-post-else"` → `"body verification of '" <> fn <> "' failed (else-branch)"`

**JSON Pointer for body constraints:** `coJsonPtr` should be `/statements/N/body`. Note: the JSON-AST schema may need a `"body"` key added (currently the body is the last positional element of `def-logic`).

**Pre-existing note:** The early-exit guard at [FixpointEmit.hs:158-160](../../compiler/src/LLMLL/FixpointEmit.hs#L158-L160) is dead code (`when ... return ()` doesn't short-circuit in `IO`). BODY-VC-1 should remove or fix it.

**Solver note:** Let-binder refinements (e.g., `_bv_s_0 = a + b`) are available as axioms in the constraint environment. The solver uses them to propagate equalities into the result predicate. Constraint IDs in examples are illustrative — actual IDs depend on emission order.

---

## 4. `.fq` Examples

### 4.1 Arithmetic with Pre (T03)

```lisp
(def-logic inc [n: int] (pre (>= n 0)) (post (= result (+ n 1))) (+ n 1))
```
```
bind 0 n      : { v : int | true }
bind 1 result : { v : int | true }

constraint:
  tag [inc; body-post]  env [0; 1]
  lhs { result : int | (n >= 0) && (result = (n + 1)) }
  rhs { result : int | (result = (n + 1)) }
```

### 4.2 ELet (T04)

```lisp
(def-logic add3 [a: int b: int c: int]
  (post (= result (+ (+ a b) c)))
  (let [[s (+ a b)]] (+ s c)))
```
```
bind 0 a        : { v : int | true }
bind 1 b        : { v : int | true }
bind 2 c        : { v : int | true }
bind 3 _bv_s_0  : { v : int | (v = (a + b)) }
bind 4 result   : { v : int | true }

constraint:
  tag [add3; body-post]  env [0;1;2;3;4]
  lhs { result : int | (result = (_bv_s_0 + c)) }
  rhs { result : int | (result = ((a + b) + c)) }
```

### 4.3 EIf — Guard-in-LHS (T05)

```lisp
(def-logic abs [x: int] (post (>= result 0)) (if (>= x 0) x (- 0 x)))
```
```
bind 0 x      : { v : int | true }
bind 1 result : { v : int | true }

constraint:  tag [abs; body-post-then]  env [0;1]
  lhs { result : int | (x >= 0) && (result = x) }
  rhs { result : int | (result >= 0) }

constraint:  tag [abs; body-post-else]  env [0;1]
  lhs { result : int | (not (x >= 0)) && (result = (0 - x)) }
  rhs { result : int | (result >= 0) }
```

### 4.4 EIf-in-ELet — Hoisting (T11)

```lisp
(def-logic abs-plus-one [x: int] (post (> result 0))
  (let [[y (if (> x 0) x (- 0 x))]] (+ y 1)))
```
```
bind 0 x        : { v : int | true }
bind 1 _bv_y_0  : { v : int | true }
bind 2 result   : { v : int | true }

constraint:  tag [abs-plus-one; body-post-then]  env [0;1;2]
  lhs { result : int | (x > 0) && (_bv_y_0 = x) && (result = (_bv_y_0 + 1)) }
  rhs { result : int | (result > 0) }

constraint:  tag [abs-plus-one; body-post-else]  env [0;1;2]
  lhs { result : int | (not (x > 0)) && (_bv_y_0 = (0 - x)) && (result = (_bv_y_0 + 1)) }
  rhs { result : int | (result > 0) }
```

### 4.5 Shadowing — Alpha-Renamed (T09)

```lisp
(def-logic f [x: int] (post (= result (+ x 1))) (let [[x (+ x 1)]] x))
```
```
bind 0 x        : { v : int | true }
bind 1 _bv_x_0  : { v : int | (v = (x + 1)) }
bind 2 result   : { v : int | true }

constraint:  tag [f; body-post]  env [0;1;2]
  lhs { result : int | (result = _bv_x_0) }
  rhs { result : int | (result = (x + 1)) }
```

> `x` in RHS (postcondition) unambiguously refers to `bind 0` (param). SAFE.

---

## 5. Fallback Behavior

When `bodyToPred` encounters any untranslatable sub-expression, the **entire function** falls back:

1. `bodyToPred` returns `Nothing`
2. No body constraint emitted
3. Existing contract-only constraints emitted unchanged
4. Function recorded in `erBodyFallback`
5. `isBodyFaithful` remains `False` — runtime assertions preserved

**Triggers:** non-int parameter, `*`/`/`/`mod`, user-defined call, `EMatch`, `ELambda`, `EDo`, `EHole`, `EAwait`, `EPair`, string/float/unit literals, non-`PVar` pattern in `ELet`, `ELet`/`EIf` in guard position, no postcondition.

**No silent weakening.** Only two valid outcomes: full body-faithful VC or unchanged contract-only VC.

---

## 6. Soundness Claim

> For a non-recursive `def-logic` function with body `e`, pre `P`, post `Q`: if `bodyToPred(e) = Just vc` and the solver reports SAFE for all flattened constraints, then for every well-typed input satisfying `P`, the generated Haskell's runtime evaluation of `e` satisfies `Q`.

**Qualifications:** Body-faithful for supported QF-LIA fragment only. Modulo TCB. Partial correctness (termination trivial: no recursion). Lazy/strict equivalence holds (no divergence in fragment).

**Argument:** Structural induction on 6 constructors. `ELit`/`EVar` trivial; `+`/`-` exact; `ELet` exact equality; `EIf` exhaustive split. Pen-and-paper suffices.

---

## 7. Proof Obligations

| # | Obligation | Verification |
|---|-----------|-------------|
| PO-1 | `bodyToPred` conservative | Structural induction; N01–N04 |
| PO-2 | Fallback no worse than today | By construction; F01–F05 |
| PO-3 | `ELet` binder exact | T04,T07,T09,T10 |
| PO-4 | Guard-split exhaustive | T05,N03 |
| PO-5 | Hoisting preserves semantics | T11 |
| PO-6 | `result` bound correctly | All T-tests |
| PO-7 | Lazy/strict equivalence | Fragment grammar |
| PO-8 | Multi-let sequential | E06 |
| PO-9 | Alpha-renaming prevents shadowing | T09,T10 |

**TCB:** `CodegenHs.hs` · `bodyToPred` · `exprToPred` · `liquid-fixpoint` · Z3 · GHC

---

## 8. Test Matrix

### Positive (SAFE) — 11 tests

| ID | Rule | Paths |
|----|------|-------|
| T01 | Literal | 1 |
| T02 | Variable | 1 |
| T03 | Arithmetic + pre | 1 |
| T04 | Single let | 1 |
| T05 | If-then-else | 2 |
| T06 | Boolean guard in if | 1 |
| T07 | Nested let | 1 |
| T08 | Let + If | 2 |
| T09 | Shadowing (alpha-rename) | 1 |
| T10 | Double shadow | 1 |
| T11 | If-in-let (hoisting) | 2 |

### Negative (UNSAFE) — 4 tests

| ID | Description |
|----|-------------|
| N01 | Wrong constant |
| N02 | Off-by-one |
| N03 | Bad else branch |
| N04 | Let body wrong |

### Fallback — 5 tests

| ID | Trigger |
|----|---------|
| F01 | `match` in body |
| F02 | User-defined call |
| F03 | `letrec` |
| F04 | Multiplication |
| F05 | Nested unsupported |

### Edge — 9 tests

| ID | Case |
|----|------|
| E01 | No pre, no post → no body VC, not in either tracking set |
| E02 | Pre only → no body VC (no postcondition to verify against) |
| E03 | Post only, no pre → body VC, LHS has no pre term |
| E04 | 256 paths (warn) |
| E05 | 4097 paths (error) |
| E06 | Multi-binding let desugared to nested |
| E07 | Body + contract VCs coexist; diagnostic messages distinct |
| E08 | Multi-function file: two functions both shadow `x` → `_bv_x_0` and `_bv_x_1` (global counter) |
| E09 | Nested if-in-if-in-let: `(let [[y (if a (if b 1 2) 3)]] y)` → fallback (`leafOf` returns `Nothing` for nested `BranchVC`) |

### Regression — 3 tests (R01–R03)

**Total: 32 tests.** Layout: `compiler/test/golden/body-vc/{positive,negative,fallback,edge,regression}/`

---

## 9. Deferred Constructs

| Construct | Phase | Reason |
|-----------|-------|--------|
| `FQIte` constructor | Later | Guard-in-LHS avoids IR change |
| Bool-typed variables | BODY-VC-1 | Requires sort environment (`Map Text FQSort`) for `predSort` on `FQVar` |
| `letrec` / recursion | Phase 2+ | Needs inductive hypothesis (Lean) |
| `EApp` user calls | Phase 2 | Needs function summaries |
| `EMatch` | Phase 2 | ADT case analysis |
| `ELambda`, `EDo` | Out of scope | Higher-order / effectful |
| Non-linear arithmetic | Out of scope | Outside QF-LIA |
| `TDependent` in VCs | Out of scope | Two-layer architecture |
| Lean mechanization | Future | Pen-and-paper suffices |
| `ELet`/`EIf` in guards | Future | `exprToPred` doesn't handle them |
| `FQOr`-in-`FQAnd` parens | BODY-VC-1 | Pre-existing serialization gap in `emitPred` |

---

## Appendix: Implementation Sequence

```
BODY-VC-0 (this document)
    ▼
BODY-VC-1: bodyToPredM + BodyVC + flattenBodyVC + alpha-renaming env
           + predSort + retSort derivation + emitBodyConstraint
           + hoistBranch/leafOf + global fresh-name counter
           + path-count limit (warn@256, error@4096)
           + gated by emitBodyVCs config field (default False)
           + fix dead early-exit at FixpointEmit.hs:158-160
    ▼
BODY-VC-2: Wire body into emitFnConstraints, set emitBodyVCs=True
           + erBodyFaithful/erBodyFallback
           + DiagnosticFQ: body-post message format + coJsonPtr
    ▼
BODY-VC-3: csBodyFaithful + isBodyFaithful per-function update
    ▼
BODY-VC-T: Golden tests (30 tests, parallel with BODY-VC-2)
```

### Modules Affected

| Module | Change | Phase |
|--------|--------|-------|
| [FixpointEmit.hs](../../compiler/src/LLMLL/FixpointEmit.hs) | `bodyToPredM`, `BodyVC`, `flattenBodyVC`, `predSort`, `hoistBranch`, `leafOf`, renaming env, `emitBodyVCs` gate, `erBodyFaithful`/`erBodyFallback` | 1/2 |
| [FixpointIR.hs](../../compiler/src/LLMLL/FixpointIR.hs) | No changes | — |
| [Contracts.hs](../../compiler/src/LLMLL/Contracts.hs) | `csBodyFaithful`, `isBodyFaithful` | 3 |
| [DiagnosticFQ.hs](../../compiler/src/LLMLL/DiagnosticFQ.hs) | `body-post*` tags | 2 |

### Key Design Decisions

| Decision | Resolution |
|----------|-----------|
| Forward symbolic eval (not WP) | Accepted — equivalent for total QF-LIA |
| Guard-in-LHS for `EIf` | Accepted — avoids IR change |
| `bodyToPredM` with `State Int` + renaming `Map` | Accepted — single-pass, no AST mutation |
| `BranchVC` for hoisting | Accepted — sound, compositional |
| Alpha-renaming via threaded env | Accepted — prevents shadowing bugs |
| Additive body constraints | Accepted — never replace contract VCs |
| Int-only vars for BODY-VC-0 | Accepted — avoids `predSort`/`FQVar` sort bug |
| Body VCs require postcondition | Accepted — nothing to prove without post |
| Path-count limits (256/4096) | Accepted — counts emitted paths |
| Per-function `isBodyFaithful` | Accepted — via `csBodyFaithful` |
