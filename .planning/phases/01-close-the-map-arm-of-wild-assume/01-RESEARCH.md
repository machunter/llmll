# Phase 1: Close the map arm of WILD-ASSUME - Research

**Researched:** 2026-07-31
**Domain:** Haskell compiler internals — type-checker soundness guard (`compiler/src/LLMLL/TypeCheck.hs`), verification-fact emitter (`compiler/src/LLMLL/FixpointEmit.hs`)
**Confidence:** HIGH (all claims below verified by reading the current tree at HEAD, `planning/onboard-v015-milestone` branch, unless tagged otherwise)

## Summary

This phase extends `assumesFact` (currently `bytes[n]`-only, `TypeCheck.hs:361-363`) to cover
`map[k,bool]`, so a `map[k,bool]` value that reaches a binder through a bare inference wildcard is
rejected at the type seam instead of letting `FixpointEmit.injectBoolValRangeFacts` assert
`0 <= select(m$val,k) <= 1` from an unvalidated declaration. This is stage 2 of a two-stage design
(`docs/design/finding-arg-position-false-safe.md`, Rev 2); stage 1 (`bytes[n]`) shipped v0.14.73 as
SAFE-ARG. The design doc, the roadmap row (`WILD-ASSUME-2`), and `.planning/REQUIREMENTS.md` all
point to the same fix: a one-line change to `assumesFact`'s pattern match, landing at the two seams
SAFE-ARG already instrumented (`structuralUnify` for arguments, `compatibleWith`/`unify`/`checkExpr`
for returns). No new seam, no new emitter logic, no new external package.

**The single most important finding for the planner:** the hard prerequisite this phase names —
the `(map-empty)` over-breadth fixture `SA-6` — **already exists** and is already green
(`compiler/test/Spec.hs:2089-2096`). It was written and committed as part of the SAFE-ARG stage-1
work, ahead of need, specifically so stage 2 would not have to write it under time pressure. This
does not remove SA-6 from the plan's verification checklist (it is still success criterion 1 and
must still pass after the discriminant widens — that's the actual test), but it means "commit the
SA-6 fixture" is not a task; "confirm SA-6 still passes after the change" is.

**Primary recommendation:** change `assumesFact` from `assumesFact (TBytes _) = True; assumesFact _
= False` to also match `TMap kt TBool` (after alias resolution — see Open Questions on whether
`assumesFact` itself needs alias expansion or whether the two call sites already expand first), add
new fixtures SA-8/SA-9 (argument-position and return-position map[int,bool] laundering, mirroring
SA-1/SA-2's shape but with `mkint`/`badb`-style bodies from the design doc's `R2_mapbool` probe),
verify SA-1..SA-7 and the corpus gate stay green, ship under the release ceremony.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Reject a laundered `map[k,bool]` argument | Type Checker — `structuralUnify` (`TypeCheck.hs`) | — | The live seam; `EApp` inference calls `structuralUnify`, which owns argument-position admissibility |
| Reject a laundered `map[k,bool]` return / checked expression | Type Checker — `compatibleWith` via `unify` / `checkExpr` (`TypeCheck.hs`) | — | Owns return-position and `checkExpr`-mediated admissibility; structurally masked in practice (see Pitfalls) but must still carry the guard for `checkExpr`-only positions |
| Discriminate "bare wildcard" from named holes / polymorphic builtins | Type Checker — `isBareWildcard`, `freshenFnType` (`TypeCheck.hs`) | — | Pure syntactic classification, no I/O, belongs entirely in the type-checking module |
| Assert `0 <= select(m$val,k) <= 1` from a declared bool-map type | Verification Emitter — `injectBoolValRangeFacts`, `boolValRooted` (`FixpointEmit.hs`) | — | Downstream of the type checker; this phase does not change this function, it prevents an unvalidated declaration from ever reaching it via a wildcard |
| Fixture / regression proof of the rejection | Test Suite — `compiler/test/Spec.hs` | — | Existing SAFE-ARG `describe` block is the home for the new map-arm cases |
| Version/release ceremony | Docs / Release tier — `README.md`, `LLMLL.md`, `CHANGELOG.md`, `compiler/package.yaml`, `compiler/llmll.cabal`, `scripts/version_gate.sh` | — | Orthogonal to the code change; gates on file-content agreement only |

## Standard Stack

**Not applicable in the conventional sense.** This phase adds no new library, no new dependency, no
new file. It is a single-clause pattern-match extension in an existing module
(`compiler/src/LLMLL/TypeCheck.hs`) plus test additions in the existing test module
(`compiler/test/Spec.hs`). The "stack" is the existing Haskell toolchain already pinned in
`compiler/package.yaml` / `compiler/llmll.cabal` (GHC 9.6.6 via Stack 3.7.1, confirmed installed —
see Environment Availability). No `npm install` / `pip install` / `cargo add` equivalent exists for
this phase. **Package Legitimacy Audit is skipped**: no external packages are installed.

## Package Legitimacy Audit

Not applicable — this phase installs no packages. Skipped per the gate's own scope (packages only).

## Architecture Patterns

### System Architecture Diagram

```
source program (.llmll)
        |
        v
   Parser (Parser.hs) --> AST (Syntax.hs)
        |
        v
   TypeCheck.hs :: checkStatements
        |
        +-- collectTopLevel: unannotated `def`/`def-shell` return registered as TVar "?"
        |
        +-- inferExpr (EApp f args):
        |     mFuncTy <- freshenFnType (looked-up signature)   <-- alpha-renames every TVar,
        |                                                          incl. "?" -> "?$N", per call site
        |     structuralUnify func subst (expected param type) (actual arg type)
        |         |
        |         +-- (_, TVar _) | isBareWildcard actual, assumesFact expected
        |         |       -> tcWildAssumeError  [THIS PHASE: widen assumesFact]
        |         |
        |         +-- (TMap k1 v1, TMap k2 v2) -> recurse componentwise
        |               (this is how (map-empty)'s TVar "k"/"v" absorb legitimately —
        |                must stay untouched; SA-6 fixture protects this)
        |
        +-- checkExpr e expected = inferExpr e >>= unify "<check>" expected
        |     unify calls compatibleWith after expandAlias on both sides
        |         |
        |         +-- compatibleWith t a@(TVar _) | isBareWildcard a, assumesFact t = False
        |               [THIS PHASE: same widen, second call site]
        |
        v
   type-checked AST, if accepted  ---(REJECTED here, this phase's goal)---> stop, diagnostic emitted
        |
        v
   FixpointEmit.hs :: emitFnConstraints
        |
        +-- boolValArrs = { n$val | (n,t) <- params++[result], boolValuedMapTy aliases t }
        |         (built ONLY from declared types — this is the fact-assertion site
        |          this phase prevents an unvalidated declaration from reaching)
        |
        +-- injectBoolValRangeFacts boolValArrs c
        |         asserts 0 <= select(m$val,k) <= 1 as a VC antecedent hypothesis
        |
        v
   liquid-fixpoint / Z3 solver --> verified / asserted / refuted / CRASH (sort mismatch,
                                     the R2_mapbool / R3_maparg current behavior pre-fix)
```

### Recommended Change Location

No new files. Two edits in `compiler/src/LLMLL/TypeCheck.hs`:
1. `assumesFact` (`:361-363`) — widen the pattern match.
2. `compiler/test/Spec.hs` — add SA-8/SA-9 fixtures inside the existing `describe "SAFE-ARG
   (WILD-ASSUME): bytes[n] laundering through an unannotated hop"` block (`:2020`), or a sibling
   `describe` block for the map arm — the planner's call, but the existing block's helpers
   (`tcOf`, `wildAssumeFired`) are directly reusable.

### Pattern 1: The `assumesFact` discriminant, verified `[VERIFIED: TypeCheck.hs:346-363]`

**What:** `assumesFact` classifies a `Type` as "asserts a ground fact into a VC antecedent that no
obligation discharges." Currently:

```haskell
-- compiler/src/LLMLL/TypeCheck.hs:361-363
assumesFact :: Type -> Bool
assumesFact (TBytes _) = True
assumesFact _          = False
```

The type this needs to also match is `TMap Type Type` (`Syntax.hs:134`) where the value type is
`TBool` — i.e. `map[k,bool]` for any admissible key `k` (int or string per
`FixpointEmit.boolValuedMapTy`, `:1780-1785`, which is key-agnostic: `(isIntLike am kt ||
isStrLike am kt) && isBoolLike am vt`). The design doc's own derivation table
(`finding-arg-position-false-safe.md:107`) names the class as `map[k,bool]`, matching
`boolValuedMapTy`'s exact admissibility, not a broader "any map" or "any bool-valued container."

**When to use:** This is the single change site for the map arm. Do not add a second discriminant
function — `assumesFact` is called from exactly three sites (`:2192`, `:2265`, `:2337`), all of
which already carry the `isBareWildcard` co-guard from the bytes arm; widening `assumesFact` alone
propagates to all three automatically.

**Open question the planner must resolve — alias expansion.** `assumesFact` receives its argument
directly from `structuralUnify`'s `expected` parameter and from `compatibleWith`'s `t` parameter.
Both call sites are reached AFTER `expandAlias` in the `unify`/`compatibleExpanded` paths
(`TypeCheck.hs:2290-2294`, `:2330-2332`), but `structuralUnify` itself is invoked at `EApp`
inference sites that the SAFE-ARG design doc says "expand aliases before calling" (comment at
`:2137-2139`, "PRECONDITION: inputs must be pre-expanded via expandAlias"). If the phase introduces
a `type BoolMap (map[int bool])`-style alias in a fixture, confirm `assumesFact` is applied to the
already-resolved `TMap _ TBool`, not to a residual `TCustom "BoolMap"` — otherwise the guard silently
does not fire on an aliased map type. `[ASSUMED — not measured in this session; recommend a fixture
that launders via a type alias as a corpus/regression check, not a required success criterion]`.

### Pattern 2: The two seams, verified `[VERIFIED: TypeCheck.hs:2140-2237, :2258-2340]`

**Seam 1 — arguments, `structuralUnify` (`TypeCheck.hs:2140-2237`).** The live path per the SAFE-ARG
design doc (line 152: "The live argument path does not go through [`compatibleWith`]"). Guard clause:

```haskell
-- compiler/src/LLMLL/TypeCheck.hs:2192-2194
(_, TVar _) | isBareWildcard actual, assumesFact expected -> do
  tcWildAssumeError func expected
  pure subst
```

This sits inside the `(TVar a, _)` / actual-is-`TVar` case dispatch, immediately before the
catch-all wildcard absorption at `:2196` (`(_, TVar _) -> pure subst`). Reached from `inferExpr
(EApp ...)` at `:1556-1580` (`structuralUnify func subst (stripDep expected') (stripDep actual')`,
line 1578) and from the builtin-operator path at `:1621`. A `map[k,bool]`-typed argument position
whose actual value is a bare wildcard (`?` or `?$N`) is the shape this seam must reject.

**Seam 2 — returns and `checkExpr`, `compatibleWith` via `unify` (`TypeCheck.hs:2258-2340`).**

```haskell
-- compiler/src/LLMLL/TypeCheck.hs:2264-2266
compatibleWith t a@(TVar _)
  | isBareWildcard a, assumesFact t  = False
compatibleWith _ (TVar _)            = True
```

`compatibleWith` is a pure `Type -> Type -> Bool` (no `TC` monad, no diagnostic side effect).
`unify` (`:2329-2340`) is what actually emits the diagnostic, and routes specifically to
`tcWildAssumeError` when the wildcard-assume condition holds (`:2337-2338`), falling back to
`tcTypeMismatch` otherwise. `checkExpr e expected = inferExpr e >>= unify "<check>" expected`
(`:1354`) is the sole consumer for checked expressions; the direct `unify` call sites feeding
top-level return-type checks are at `TypeCheck.hs` (per the design doc's citation, originally
`:984, 1019, 1065, 1099` — re-verify exact line numbers at execution time since the file has since
grown; `unify`'s definition itself is confirmed at `:2329`).

**Both seams must gain the widened `assumesFact` for free — no separate edit to either seam's
guard clause is needed.** The guard clauses already call `assumesFact`; only `assumesFact`'s body
changes. This is the same mechanism SAFE-ARG's own diff used for stage 1 and is why the design doc
frames stage 2 as "add the `map` arm" (`finding-arg-position-false-safe.md:203`) rather than as new
seam work.

### Pattern 3: `isBareWildcard` and `freshenFnType` — the SAFE-ARG dead-guard precedent `[VERIFIED: TypeCheck.hs:365-387, 2118-2126]`

This is the single most load-bearing prior-art item for this phase's fixture design (see success
criterion 2 and the roadmap's explicit callout).

```haskell
-- compiler/src/LLMLL/TypeCheck.hs:385-387
isBareWildcard :: Type -> Bool
isBareWildcard (TVar n) = n == "?" || "?$" `T.isPrefixOf` n
isBareWildcard _        = False
```

```haskell
-- compiler/src/LLMLL/TypeCheck.hs:2118-2126
freshenFnType :: Type -> TC Type
freshenFnType t =
  case Set.toList (freeTVarNames t) of
    []  -> pure t
    vs -> do
      n <- gets tcTVarCounter
      modify $ \s -> s { tcTVarCounter = n + 1 }
      let rename = Map.fromList [ (v, TVar (v <> "$" <> tshow n)) | v <- vs ]
      pure (applySubst rename t)
```

**What went dead, and why (verified from `TypeCheck.hs:378-384` and
`finding-arg-position-false-safe.md:174-184`).** The design's Rev 1 (and both professor reviews of
it) specified the discriminant as **exact equality**, `n == "?"`. That is wrong, and it made the
rule **completely dead** in practice: `freshenFnType` alpha-renames every free `TVar` in a callee's
signature — including the bare wildcard registered by `collectTopLevel` for an unannotated return —
at **every call site**, as `v <> "$" <> counter`. So an unannotated callee's return type never
arrives at a use site as `TVar "?"`; it arrives as `TVar "?$0"`, `TVar "?$17"`, etc. Measured
directly: "with an exact-equality guard the rule was completely dead, and `bad4` reported `got
?$0`" — i.e. every one of the five original laundering probes still type-checked clean under the
exact-equality guard, and the freshened name only surfaced in the diagnostic once the check was
relaxed to a prefix test. The corrected predicate, shipped, is `n == "?" || "?$" isPrefixOf n`.

**What the fixture must do to prove liveness (this phase's obligation, criterion 2).** A fixture
that only exercises `TVar "?"` directly (e.g. calling an unannotated `def` with no intervening hop)
proves nothing about the freshened form, because in real programs a wildcard almost never survives
to a use site un-freshened — `freshenFnType` runs at every `EApp`. The bytes-arm precedent, SA-1
(`Spec.hs:2033-2044`), proves liveness the right way: it launders through **one unannotated hop**
(`mk32` -> `mid2` -> `consume(mid2 arg)`), which forces at least one `freshenFnType` application
before the guard is reached, so the value the guard actually sees is `TVar "?$N"`, not `TVar "?"`.
**The map-arm fixtures (SA-8/SA-9, not yet written) must copy this exact shape**: an unannotated
intermediate function (like `midb` in the design doc's `R2_mapbool` probe,
`finding-arg-position-false-safe.md:380-386`) between the map-producing function and the
consuming/declaring function, so the guard is proven live against `?$N`, not merely against `?`.

### Anti-Patterns to Avoid

- **Writing `assumesFact` as `TMap _ _ = True` (any map).** Breaks `(map-empty)` absorption
  identically to how a catch-all `TVar _` broke SA-6 in edge case 8 of the design doc — `map-empty :
  TFn [] (TMap (TVar "k") (TVar "v"))` relies on `structuralUnify`'s `(TMap k1 v1, TMap k2 v2)` case
  recursing into `(_, TVar _) -> pure subst` for **both** components. `assumesFact` must match on
  the value type specifically being `TBool` (or, if the planner decides to also expand aliases
  inline, the alias-resolved `TBool`), not merely on the outer constructor being `TMap`.
- **Writing the discriminant as `isHoleVar` or a bare `TVar _` pattern anywhere in the new code.**
  This is the exact mistake the design doc calls out for both the return-position guard history and
  the map-empty hazard — `isHoleVar` (`:342-344`, `"?" isPrefixOf n`) matches named holes too
  (`?body_impl`), which would break sketch mode.
- **Testing only the un-freshened `TVar "?"` form.** See Pattern 3 above — this is exactly how the
  first SAFE-ARG implementation shipped dead.
- **Treating "check clean, verify crashes" as evidence of safety.** The requirement's evidence-limit
  clause (criterion 4) exists precisely because a solver crash is not a verdict; it must not be
  reported as "this arm was safe until now."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Classifying "is this type map[k,bool]" | A fresh predicate in `TypeCheck.hs` | Extend `assumesFact`'s existing pattern match with a case mirroring `FixpointEmit.boolValuedMapTy`'s admissibility (`isIntLike \|\| isStrLike` key, `isBoolLike` value) | Two independently-written "is this a bool map" predicates in two modules is exactly the kind of drift the design doc's `assumes(τ)` derivation table (line 107) is trying to prevent — FACT-AG (Phase 3) explicitly targets deriving this set from the emitter rather than hand-enumerating it twice |
| Detecting a bare wildcard | A new name-pattern check | `isBareWildcard` (`TypeCheck.hs:385-387`), already covers `?` and `?$N` | Already correct and already the shipped, measured-live discriminant; re-deriving it risks reintroducing the Rev-1 exact-equality bug |
| Proving the guard fires on `?$N` | A synthetic test that manually constructs a `TVar "?$5"` AST node | A source-level fixture with an unannotated intermediate hop (SA-1's shape) | A hand-constructed AST bypasses `freshenFnType`'s actual renaming path and would pass even if the guard were reverted to exact-equality — it would not have caught the Rev-1 regression |

**Key insight:** every piece of machinery this phase needs already exists and is already exercised
by the bytes arm. The work is a one-clause widen plus fixtures shaped like the existing SA-1/SA-2
pair, not new design.

## Runtime State Inventory

Not applicable — this is not a rename/refactor/migration phase. No stored data, live service
config, OS-registered state, secrets, or build artifacts carry a name this phase changes. Skipped
per the trigger condition.

## Common Pitfalls

### Pitfall 1: Believing SA-6 is a task rather than a passing precondition

**What goes wrong:** A plan that includes a task "write and commit the SA-6 fixture" duplicates
work and risks a merge conflict or a confusing diff against `compiler/test/Spec.hs:2089-2096`,
which already contains it, already passing (since `assumesFact` does not yet cover `TMap`, nothing
currently rejects `(map-empty)`).

**Why it happens:** The requirement and roadmap text both describe SA-6 as a "prerequisite... must
be committed before the restriction widens," phrased as future work because that is how the design
doc originally scoped stage 2. The SAFE-ARG stage-1 implementation got ahead of that framing and
committed it early.

**How to avoid:** The plan's task list should read "confirm SA-6 (`Spec.hs:2093-2096`) still passes
after `assumesFact` widens" as a verification step, not a construction step. Re-run `stack test
--test-arguments '--match "SA-6"'` (or the project's equivalent) after the `assumesFact` edit, before
declaring success criterion 1 met.

**Warning signs:** A diff that re-adds an `it "SA-6 ..."` block, or a diff that touches
`Spec.hs:2089-2096` at all in a way that isn't purely contextual (e.g. moving it into a new describe
block).

### Pitfall 2: Treating "crashes before a verdict" as something this phase must fix at the solver layer

**What goes wrong:** Attempting to make `injectBoolValRangeFacts` or the FixpointEmit sort-encoding
"handle" the mismatched-sort case gracefully (e.g. catch the crash, degrade to `asserted`) instead
of preventing the laundered program from ever reaching the emitter.

**Why it happens:** "crash on a sort mismatch" sounds like an emitter bug to fix. It is not — it is
the CONSEQUENCE of the laundering the type checker should have rejected. Requirement criterion 3 is
explicit: after this phase, the laundered program is "refused at the seam instead of injecting
[the fact]," i.e. the crash disappears because the type checker now rejects the program before
FixpointEmit ever runs, not because FixpointEmit learns to cope.

**How to avoid:** Scope the diff to `TypeCheck.hs` (plus tests). Do not touch
`FixpointEmit.hs:4177-4191` (`injectBoolValRangeFacts`) or `:1780-1785` (`boolValuedMapTy`) — they
are correct as declared-type-driven fact assertions; the defect is that an undischarged declaration
reaches them, not that they compute the wrong fact from a valid one.

**Warning signs:** A diff touching `FixpointEmit.hs` for this phase at all should prompt a second
look — the only correct diff site is `TypeCheck.hs` and `Spec.hs`.

### Pitfall 3: Overclaiming in the release notes

**What goes wrong:** Writing a CHANGELOG entry that says this phase "fixes a false SAFE in the map
arm," mirroring the v0.14.73 SAFE-ARG entry's framing ("this one did not fail closed").

**Why it happens:** Copy-paste from the adjacent, structurally similar SAFE-ARG changelog entry
(`CHANGELOG.md` v0.14.73 heading, read this session) is a natural drafting shortcut, but the map arm
has a **materially different evidence status**: `[VERIFIED via docs/design/finding-arg-position-false-safe.md:128-131, roadmap.md:50, REQUIREMENTS.md:37-40]` both the return shape (`R2_mapbool`)
and the argument shape (`R3_maparg`) crash on a sort mismatch before reaching a verdict at HEAD.
There is no reaching-SAFE witness for the map arm the way `Q1_argpos` was a reaching-SAFE witness for
bytes. This phase closes a class member found by the emitter-derivation table, not a demonstrated
exploit.

**How to avoid:** The documentation-lead (or whoever drafts the CHANGELOG entry) should quote
success criterion 4 verbatim as the governing language: "a measured member of the SAFE-ARG class
with no reaching-SAFE witness... The phase closes a class member; it does not refute a demonstrated
exploit." A corpus run with zero new failures is a regression check, explicitly not evidence the fix
works (there is no known-exploitable case for it to have fixed).

**Warning signs:** Any CHANGELOG draft using the words "false SAFE," "certified," "reads past the
end," or similar exploit-narrative language for this phase specifically.

## Code Examples

### Existing bytes-arm fixture shape to copy (verified pattern, `Spec.hs:2020-2044`)

```haskell
-- Source: compiler/test/Spec.hs:2020-2044 (existing, verified)
describe "SAFE-ARG (WILD-ASSUME): bytes[n] laundering through an unannotated hop" $ do
  let launderPrefix =
        [ "(def mk32 [] -> bytes[32] (bytes-zero))"
        , "(def-shell mid2 [] (mk32))"
        ]
      tcOf srcLines = case parseStatements GrammarCoreInversion "<safe-arg>" (T.pack (unlines srcLines)) of
        Left err    -> Left (show err)
        Right stmts -> Right (typeCheck GrammarCoreInversion emptyEnv stmts)
      wildAssumeFired report =
        any (T.isInfixOf "unannotated return type" . diagMessage) (reportDiagnostics report)

  it "SA-1 rejects a laundered bytes[32] at a bytes[64] ARGUMENT position" $ do
    case tcOf (launderPrefix ++
          [ "(def-shell consume [b: bytes[64] i: int] -> int"
          , "  (pre (and (>= i 0) (< i 64)))"
          , "  (post (>= result 0))"
          , "  (bytes-get b i))"
          , "(def-shell caller [i: int] -> int (pre (and (>= i 0) (< i 64))) (consume (mid2) i))"
          ]) of
      Left e -> expectationFailure e
      Right report -> do
        reportSuccess report `shouldBe` False
        wildAssumeFired report `shouldBe` True
```

### Design-doc probe source for the map-arm fixture shape (not yet a Spec.hs test; source to adapt)

```lisp
;; Source: docs/design/finding-arg-position-false-safe.md:380-391 (R2_mapbool, P6b_map)
;; R2_mapbool — the map arm: false 0..1 range asserted from the declaration, obligation
;; trivially implied by it. Crashes before a verdict AT HEAD (pre-fix).
(def mkint [k: int] -> map[int int] (map-put (map-empty) k 7))
(def-shell midb [k: int] (mkint k))
(def-shell badb [k: int] -> map[int bool]
  (post (or (= (map-get result k) true) (= (map-get result k) false)))
  (midb k))
```

**Note for the planner:** the design doc gives R2_mapbool (return-position launder) and names but
does not give source for R3_maparg (argument-position launder, the `structuralUnify` seam analog of
`Q1_argpos`). The planner must construct R3_maparg's fixture by analogy to `Q1_argpos`
(`Spec.hs`/design-doc `:355-362`): an unannotated function returning `map[int,int]`, passed as an
argument to a function whose parameter is declared `map[int,bool]`. After the fix, `assumesFact`
widening covers both `structuralUnify` (this new argument-position fixture) and `compatibleWith`
(the `R2_mapbool`-shaped fixture above) — both should transition from "check clean" to "type error,
`wildAssumeFired`."

### The `assumesFact` widen itself (not yet made; this session's primary recommendation)

```haskell
-- compiler/src/LLMLL/TypeCheck.hs:361-363, proposed shape (verify against
-- FixpointEmit.boolValuedMapTy's exact admissibility before finalizing —
-- key-agnostic: int OR string key, TBool value)
assumesFact :: Type -> Bool
assumesFact (TBytes _)       = True
assumesFact (TMap _ TBool)   = True
assumesFact _                = False
```

`[ASSUMED — this exact clause shape, not verified by compiling it this session; the planner/executor
must confirm it type-checks in context and reconcile with the alias-expansion open question above]`.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `assumesFact` covers only `bytes[n]` | `assumesFact` covers `bytes[n]` and `map[k,bool]` | This phase (target v0.14.74) | Closes the second (of two known) `assumes(τ)` class members; `map[k,bool]` value-range facts can no longer be laundered through a bare wildcard |
| Discriminant `n == "?"` (exact equality) | Discriminant `n == "?" \|\| "?$" isPrefixOf n` | SAFE-ARG Rev 2, shipped v0.14.73, `0e1327a` | The exact-equality form was completely dead against real laundering (all probes type-checked clean); this is already fixed and unchanged by this phase — reuse it, do not re-derive it |

**Deprecated/outdated:** SAFE-ARG Rev 0 and Rev 1 of the design (superseded by Rev 2, currently the
only live revision — see `docs/design/finding-arg-position-false-safe.md:4`, status line).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `assumesFact` receives an already-alias-expanded `Type` at all three call sites, so `(TMap _ TBool)` will match even when the source uses a type alias for the map or the bool | Pattern 1 (Open question) | If false, an aliased `map[k,bool]` type (e.g. `type BoolMap (map[int bool])`) would silently bypass the new guard — a gap not covered by success criterion 3 as stated, but a corpus program using such an alias would still launder |
| A2 | The proposed `assumesFact (TMap _ TBool) = True` clause is the correct scope, matching `FixpointEmit.boolValuedMapTy`'s admissibility (int-or-string key, bool value) rather than a narrower `TMap TInt TBool` or broader `TMap _ _` | Code Examples | Too narrow (e.g. requiring `TInt` key) silently fails to close the string-keyed bool-map sub-case; too broad breaks `(map-empty)` per the SA-6 hazard |
| A3 | R3_maparg's fixture (argument-position map launder) can be constructed by direct analogy to `Q1_argpos`/R2_mapbool without hitting some other type-checker rejection first (the way `(consume (bytes-zero) i)` was already rejected for an unrelated reason per edge case 9) | Code Examples | If some other check already rejects the naive R3_maparg construction, the fixture would not actually exercise the new `assumesFact` guard, and criterion 2/3's "fixture exercises `?$N` directly" would go unverified for the argument seam |

## Open Questions (ALL RESOLVED 2026-07-31, during planning)

> **RESOLVED, Q1 — alias expansion.** Answered by reading rather than by fixture-and-hope.
> `expandAlias` recurses into `TMap k v` (`compiler/src/LLMLL/TypeCheck.hs:2318`); `unify` expands
> both sides before `compatibleWith` (`:2331-2332`); the `EApp` site expands before
> `structuralUnify` (`:1576-1577`). Both `assumesFact` call sites therefore receive fully resolved
> value types, and the new helpers need no `AliasMap` parameter. Verified independently by the
> orchestrator against HEAD. Plan `01-02` commits this as fixture **SA-11** rather than leaving it an
> assumption, with a stated contingency that closes the seam if the measurement disagrees.
>
> **RESOLVED, Q2 — stale line numbers.** Confirmed stale: the design doc's cited `unify` call sites
> (`:984, 1019, 1065, 1099`) do not hold at HEAD. The plans re-cite current line numbers rather than
> trusting the design doc, and every citation in them was checked against the live source by both the
> orchestrator and the plan-checker.
>
> **RESOLVED, Q3 — fixture placement.** Decided in favor of a new sibling `describe` block rather
> than extending the bytes-arm block, whose own description string says "bytes[n] laundering".
> Recorded in `01-01-PLAN.md`.
>
> The three questions are kept below as written for the record. Nothing under this heading is an
> open item for execution.

1. **Does `assumesFact` need alias expansion inline, or is it always called post-`expandAlias`?**
   - What we know: the two production call sites (`structuralUnify`'s precondition comment,
     `unify`'s explicit `expandAlias` calls) suggest yes, aliases are resolved before `assumesFact`
     runs.
   - What's unclear: whether every call path (including any test-harness path that calls
     `structuralUnify` or `compatibleWith` directly, bypassing `unify`) also expands first.
   - Recommendation: add one regression fixture using a type alias over `map[int bool]` as a
     corpus/regression check (not necessarily a named success-criterion fixture), and cite the
     `expandAlias` precondition comment (`TypeCheck.hs:2137-2139`) in the plan's verification step.

2. **Exact line numbers for the top-level `unify` call sites feeding return-type checking.**
   - What we know: the design doc cites `:984, 1019, 1065, 1099` for these call sites (as of the
     SAFE-ARG Rev 2 draft, prior to any subsequent edits).
   - What's unclear: whether those exact line numbers still hold at current HEAD — the file has
     grown (current `unify` definition is at `:2329`, `compatibleWith` at `:2258`, both later than
     the design doc's own citations for other content, indicating insertions since Rev 2 was
     written).
   - Recommendation: the plan should re-grep `unify "<...>" ` call sites at execution time rather
     than trust the design doc's line numbers verbatim; `checkExpr`'s definition (verified this
     session at `TypeCheck.hs:1348-1354`) is the single sure entry point for return-type checking
     via `unify`.

3. **Should SA-8/SA-9 live in the existing `describe "SAFE-ARG (WILD-ASSUME)..."` block or a new
   sibling block?**
   - What we know: SA-1..SA-7 are all bytes-arm-focused in naming and comments; the block's own
     `describe` string says "bytes[n] laundering."
   - What's unclear: whether the project's convention favors extending the existing description
     text to cover both arms, or opening a new `describe "SAFE-ARG (WILD-ASSUME): map[k,bool]
     laundering..."` block reusing `tcOf`/`wildAssumeFired`.
   - Recommendation: a new sibling `describe` block is cleaner (keeps the bytes-arm block's title
     accurate) and avoids touching working SA-1..SA-7 test code; this is a planner/executor style
     call, not a functional one.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Stack | Build/test | Yes | 3.7.1 (aarch64-osx) | — |
| GHC | Build/test | Yes | 9.6.6 (via Stack) | — |
| jq | `scripts/version_gate.sh` (C3/C4 checks) | Yes | jq-1.7.1 | — |
| git | version bisect / commit citations | Yes | (system) | — |

**Missing dependencies with no fallback:** none identified.

**Missing dependencies with fallback:** none identified.

**Build hygiene finding — reported honestly, not resolved this session.** Per the roadmap's
mandatory precondition, `(cd compiler && stack build --dry-run llmll)` was run this session. It did
**not** report "Nothing to build." Actual output:

```
Would unregister locally:
* llmll-0.14.73 (local file changes:
  .stack-work/dist/aarch64-osx/ghc-9.6.6/build/autogen/Paths_llmll.hs
  .stack-work/dist/aarch64-osx/...)

Would build:
* llmll-0.14.73: database=local, source=/Users/burcsahinoglu/Documents/llmll/compiler/

No executables to be installed.
```

This flags only `.stack-work`'s generated `autogen/Paths_llmll.hs` as changed (a Cabal-generated
file embedding build paths, commonly regenerated after a branch switch or worktree move with no
source edits) — plausibly benign, but **not verified benign this session**, and the roadmap's own
rule is explicit that `stack build --dry-run` reporting anything other than "Nothing to build."
means the binary is not to be trusted for measurement. **The plan's first task should be running a
real `stack build llmll`, then re-running the dry-run check and confirming it reports "Nothing to
build." before any `llmll check`/`verify` output in this phase is trusted** — do not skip this on
the assumption that the flagged file is harmless.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hspec (`compiler/test/Spec.hs`), invoked via `stack test` |
| Config file | `compiler/package.yaml` (test-suite stanza) / `compiler/llmll.cabal` |
| Quick run command | `cd compiler && stack test --test-arguments '--match "SAFE-ARG"'` |
| Full suite command | `cd compiler && stack test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REQ-wild-assume-2 (criterion 1) | `(map-empty)` still type-checks at a typed map position after the widen | unit (Hspec) | `stack test --test-arguments '--match "SA-6"'` | Yes — `Spec.hs:2093-2096` |
| REQ-wild-assume-2 (criterion 2) | `assumesFact` covers the map class; guard fires on `?$N`, not only bare `?` | unit (Hspec) | `stack test --test-arguments '--match "SAFE-ARG"'` (new SA-8/SA-9 needed) | Partial — bytes-arm SA-1..7 exist (`Spec.hs:2020-2103`); map-arm cases do not exist yet, ❌ Wave 0 |
| REQ-wild-assume-2 (criterion 3) | Laundered `map[k,bool]` argument AND return are refused at the type seam, not injected into a VC | unit (Hspec) | Same new SA-8 (argument)/SA-9 (return) tests | ❌ Wave 0 — needs authoring per Code Examples above |
| REQ-wild-assume-2 (criterion 4) | Release notes state the evidence limit correctly | manual-only (documentation review) | n/a — human/doc-lead review against this file's Pitfall 3 | n/a |
| REQ-wild-assume-2 (criterion 5) | Ships per Definition of Done | scripted gate | `scripts/version_gate.sh`; `stack test`; `scripts/check-examples.sh` | Yes, all three scripts exist |

### Sampling Rate

- **Per task commit:** `cd compiler && stack test --test-arguments '--match "SAFE-ARG"'`
- **Per wave merge:** `cd compiler && stack test` (full suite) plus `scripts/check-examples.sh`
  (corpus regression check named in criterion 4)
- **Phase gate:** Full suite green, `scripts/version_gate.sh` exits 0, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] New Hspec tests SA-8 (argument-position map[int,bool] launder, `structuralUnify` seam) and
      SA-9 (return-position map[int,bool] launder, `compatibleWith`/`checkExpr` seam) —
      `compiler/test/Spec.hs`, adjacent to the existing SAFE-ARG block. Both must launder through
      an unannotated hop (see Pitfall/Pattern 3) so they exercise `?$N`, not bare `?`.
- [ ] Confirm existing SA-1..SA-7 stay green after the `assumesFact` widen (regression, not a new
      file).
- [ ] Confirm the corpus gate (`scripts/check-examples.sh`) reports no new failures — this is the
      regression check named in criterion 4, explicitly not evidence of correctness on its own.

## Security Domain

This phase is a compiler-internal soundness fix, not an application with a network-facing surface,
authentication, session state, or user input in the ASVS sense. ASVS categories (V2 Authentication,
V3 Session Management, V4 Access Control, V6 Cryptography) do not apply. The relevant "threat" is
soundness regression in the type checker, which the existing SAFE-ARG sidecar-invalidation mechanism
(`checker_soundness_version`, `VerifiedCache.hs`) already covers — this phase does not need a new
invalidation stamp because it only *narrows* what type-checks (never widens acceptance), so no
previously-`verified` sidecar becomes newly-false as a result of this change. `[ASSUMED — reasoned
from the shape of the change (narrowing, not widening, acceptance); not independently verified by
inspecting `VerifiedCache.hs`'s revalidation trigger logic this session]`. The planner should confirm
this reasoning holds (i.e. that no program which was `verified` under stage-1-only `assumesFact`
now needs sidecar invalidation) rather than assume it silently.

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| False `SAFE`/`verified` from an unvalidated type-level declaration (the SAFE-ARG/WILD-ASSUME class generally) | Tampering (of the trust artifact, not of a running system) | The WILD-ASSUME admissibility rule itself — reject the laundering at the type seam before a fact is asserted |
| A solver crash on ill-sorted input being mistaken for (or reported as) a verdict | Repudiation (of what was actually checked) | Criterion 4's evidence-limit discipline: a crash is not a verdict and must not be described as either SAFE or exploitable |

## Project Constraints (from CLAUDE.md)

No project-local `./CLAUDE.md` exists in this repository. The compiler-engineer skill's conventions
(citation-dense, cite `compiler/src/LLMLL/<Module>.hs:<lines>`) were followed throughout this
document. The user's global CLAUDE.md prose-style rules (no em dashes, no "load-bearing"/"honest(ly)")
were applied to this document's own prose.

## Sources

### Primary (HIGH confidence — read directly this session)
- `compiler/src/LLMLL/TypeCheck.hs` — `assumesFact` (:346-363), `isBareWildcard`/`tcWildAssumeError`
  (:365-408), `freshenFnType` (:2118-2126), `structuralUnify` (:2140-2237), `compatibleWith`
  (:2258-2285), `compatibleExpanded`/`expandAlias`/`unify` (:2287-2340), `checkExpr` (:1348-1354),
  `builtinEnv` map-empty entry (:168)
- `compiler/src/LLMLL/FixpointEmit.hs` — `boolValArrs` construction (:735-746),
  `injectRangeFacts`/`injectBoolValRangeFacts` (:4125-4191), `mapArrEncodableTy`/`boolValuedMapTy`
  (:1739-1785)
- `compiler/test/Spec.hs` — SAFE-ARG `describe` block, SA-1..SA-7 (:2016-2103)
- `docs/design/finding-arg-position-false-safe.md` — the governing design doc, Rev 2 (full read:
  `assumes(τ)` table :99-131, the WILD-ASSUME rule :133-243, edge cases :214-243, probe sources
  :327-392)
- `docs/compiler-team-roadmap.md` — WILD-ASSUME-2 active-item row (:50)
- `CHANGELOG.md` — v0.14.73 SAFE-ARG entry (head of file)
- `scripts/version_gate.sh` — full read, all four checks (C1-C4)
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` — phase scope,
  acceptance criteria, prior decisions
- Direct tool verification this session: `stack build --dry-run llmll`, `stack --version`, `jq
  --version`, `git log --oneline --grep="SAFE-ARG"` (commits `0e1327a`, `cc15e7c`, `f90dd39`,
  `85426da`, `ad1f820`)

### Secondary (MEDIUM confidence)
- None used — this phase required no external web research; all needed information was in-tree.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — no external dependencies introduced
- Architecture: HIGH — every cited line was read directly from the current tree this session
- Pitfalls: HIGH — sourced directly from the design doc's own measured history (the Rev-1 dead-guard
  finding) and from the requirement's own stated evidence-limit language

**Research date:** 2026-07-31
**Valid until:** Tied to the current HEAD of `compiler/src/LLMLL/TypeCheck.hs` and
`FixpointEmit.hs`. Re-verify line citations if this phase is not executed promptly, or if Phase 2
(RET-RESOLVE) or any other WILD-ASSUME-adjacent work lands first — both touch the same seams
(`structuralUnify`/`compatibleWith`) this phase modifies.
