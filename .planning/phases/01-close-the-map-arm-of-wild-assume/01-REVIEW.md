---
phase: 01-close-the-map-arm-of-wild-assume
reviewed: 2026-08-01T05:09:32Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - compiler/src/LLMLL/TypeCheck.hs
  - compiler/test/Spec.hs
  - compiler/package.yaml
  - compiler/llmll.cabal
  - docs/compiler-team-roadmap.md
findings:
  critical: 1
  warning: 1
  info: 1
  total: 3
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-08-01T05:09:32Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

The phase's real delta is confined to `compiler/src/LLMLL/TypeCheck.hs` (the new `TMap` arm on `assumesFact`, the two admissibility helpers, `wildAssumeFactNoun`, and the reworded `tcWildAssumeError` message) and `compiler/test/Spec.hs` (SA-8 through SA-16). `compiler/package.yaml`, `compiler/llmll.cabal`, and `docs/compiler-team-roadmap.md` are a version bump and a roadmap row, as expected.

The nine new tests correctly prove the map arm live at both seams (SA-8, SA-9), hold the over-breadth line (SA-6, SA-10, SA-12, SA-14, SA-15), and confirm alias coverage for a plain `STypeDef` alias (SA-11) with no code change. That reasoning is sound as far as it goes.

It does not go far enough. I traced `assumesFact`'s two call sites (`unify`/`compatibleWith` for the return/check seam, `structuralUnify` for the argument seam, per `FixpointEmit.isIntLike`/`isBoolLike`/`resolveAliasTy`) and found that `assumesFact` never strips a `TDependent` wrapper before dispatching on `TBytes`/`TMap`, while `FixpointEmit.resolveAliasTy` (the function that actually decides whether the emitter asserts the ground fact) does strip it. I reproduced the resulting gap against the compiled `llmll 0.14.74` binary: a refinement-style alias wrapping a `map[k,bool]` (or a `bytes[n]`) return type evades the entire WILD-ASSUME guard at the return seam, for both the pre-existing bytes arm and the new map arm this phase ships. This is the exact "helper divergence" hazard called out for this review, and none of SA-8..SA-16 exercises it. See CR-01.

A secondary diagnostic-wording defect (WR-01) and a documentation-drift nit in the new test comments (IN-01) round out the findings.

## Critical Issues

### CR-01: `assumesFact` does not strip `TDependent`, so a refinement-wrapped `bytes[n]`/`map[k,bool]` return type evades WILD-ASSUME entirely (reopens the false-SAFE gap for both arms)

**File:** `compiler/src/LLMLL/TypeCheck.hs:363-366`
**Issue:**

```haskell
assumesFact :: Type -> Bool
assumesFact (TBytes _)   = True
assumesFact (TMap kt vt) = assumesFactMapKey kt && assumesFactBoolValue vt
assumesFact _            = False
```

`assumesFact` pattern-matches `TBytes`/`TMap` only at the outermost constructor. It has no `TDependent` clause, so `assumesFact (TDependent _ (TMap TInt TBool) _)` and `assumesFact (TDependent _ (TBytes 64) _)` both fall through to `assumesFact _ = False`, even though `assumesFactMapKey`/`assumesFactBoolValue` (the two new helpers, lines 375-389) do recurse through `TDependent` when it wraps a map's *key or value component*. The gap is specifically the case where the *whole* map/bytes type is wrapped, e.g. a refinement alias `(type BoolMapDep (where [m: map[int bool]] true))`, syntactically reachable, since `pWhereType`'s base type is parsed with the unrestricted `pType` (`compiler/src/LLMLL/Parser.hs:319-324,580-596`, `1039-1044`).

Both `assumesFact` call sites are affected differently:

- **Return/check seam** (`unify`/`compatibleWith`, `TypeCheck.hs:2303-2385`): `compatibleWith`'s wildcard-guard clause (`compatibleWith t a@(TVar _) | isBareWildcard a, assumesFact t = False`, line 2309-2310) is evaluated on `expected'` from `expandAlias`, which unfolds `TCustom` aliases but explicitly **preserves** the `TDependent` wrapper (`TDependent n b c -> (\b' -> TDependent n b' c) <$> go seen b`, line 2371). When the guard's `assumesFact t` returns `False` on the still-wrapped type, GHC falls through to the next equation, `compatibleWith _ (TVar _) = True` (line 2311), which fires unconditionally. **The bare wildcard is silently accepted.**
- **Argument seam** (`structuralUnify`, via the EApp/EOp call sites at lines 1612-1624/1656-1668): this seam applies `stripDep` (one level of `TDependent`-unwrapping, line 1955-1957) immediately before calling `structuralUnify`, so it is *not* vulnerable, `assumesFact` sees the unwrapped `TMap`/`TBytes` there. I confirmed this empirically (see below); only the return/check seam is exploitable.

Meanwhile `FixpointEmit.resolveAliasTy`, the function `boolValuedMapTy`/`isIntLike`/`isBoolLike` actually use to decide whether to assert the ground fact, **does** strip `TDependent`:

```haskell
resolveAliasTy :: AliasMap -> Type -> Type
resolveAliasTy am (TCustom n)        = maybe (TCustom n) (resolveAliasTy am) (Map.lookup n am)
resolveAliasTy am (TDependent _ b _) = resolveAliasTy am b
resolveAliasTy _  t                  = t
```
(`compiler/src/LLMLL/FixpointEmit.hs:1476-1479`)

So the emitter still asserts the per-key value-range fact (or `bytesLen`) for a `TDependent`-wrapped declaration, while the checker's admission guard fails to reject the laundered wildcard that reaches it, precisely the false-SAFE pattern `docs/design/finding-arg-position-false-safe.md` documents and this phase exists to close.

**Empirically confirmed** against the compiled `llmll 0.14.74` binary (`stack build` at HEAD):

Control (bare, unwrapped, correctly rejected, matches SA-9):
```lisp
(def mkint [k: int] -> map[int int] (map-put (map-empty) k 7))
(def-shell midb [k: int] (mkint k))
(def-shell badb [k: int] -> map[int bool] (midb k))
```
```
error: type mismatch in 'badb': expected map[int,bool], got ? (an unannotated return type). ...
```

Same shape, return type wrapped in a `where` alias, **silently accepted**:
```lisp
(type BoolMapDep (where [m: map[int bool]] true))
(def mkint [k: int] -> map[int int] (map-put (map-empty) k 7))
(def-shell midb [k: int] (mkint k))
(def-shell badb [k: int] -> BoolMapDep (midb k))
```
```
✅ ..., OK (4 statements)
```

The same evasion reproduces for the pre-existing bytes arm with `(type BufDep (where [b: bytes[64]] true))` wrapping a laundered `bytes[32]`.

**Fix:** add a `TDependent` clause to `assumesFact` itself, so it strips the wrapper before dispatching, mirroring what `resolveAliasTy` already does and what `assumesFactMapKey`/`assumesFactBoolValue` already do for the inner key/value positions:

```haskell
assumesFact :: Type -> Bool
assumesFact (TBytes _)       = True
assumesFact (TMap kt vt)     = assumesFactMapKey kt && assumesFactBoolValue vt
assumesFact (TDependent _ b _) = assumesFact b
assumesFact _                = False
```

Add a regression test (return seam, both arms) using a `(where [...] ...)` alias in place of a bare or plain-`STypeDef` alias, e.g.:
```lisp
(type BoolMapDep (where [m: map[int bool]] true))
(def-shell badb [k: int] -> BoolMapDep (midb k))
```
asserting `reportSuccess report \`shouldBe\` False` and `wildAssumeFired report \`shouldBe\` True`, alongside an equivalent `bytes[n]` case.

## Warnings

### WR-01: `tcWildAssumeError` reports the generic "a fact" noun instead of the class-specific wording for an aliased map/bytes type, because it is called with the un-expanded type

**File:** `compiler/src/LLMLL/TypeCheck.hs:2382-2385`
**Issue:** in `unify`:
```haskell
unify ctx expected actual = do
  expected' <- expandAlias expected
  actual'   <- expandAlias actual
  unless (compatibleWith expected' actual') $
    if isBareWildcard actual' && assumesFact expected'
      then tcWildAssumeError ctx expected      -- <-- original, un-expanded `expected`
      else tcTypeMismatch ctx expected actual
```
The rejection decision correctly uses `expected'` (alias-expanded), but the call to `tcWildAssumeError` passes the *original* `expected` "to preserve alias names in diagnostics" (comment at line 2384, this part is intentional and fine for `typeLabel`). The problem is that `tcWildAssumeError` also calls `wildAssumeFactNoun expected` (`TypeCheck.hs:449-450`) on that same un-expanded value. For a plain `STypeDef` alias (`(type BoolMap map[int bool])`), `wildAssumeFactNoun (TCustom "BoolMap")` matches none of `wildAssumeFactNoun`'s specific clauses and falls to the catch-all `wildAssumeFactNoun _ = "a fact"`, even though the rejection is, in fact, the map arm's per-key value-range fact.

Confirmed empirically: SA-11's own fixture (`(type BoolMap map[int bool])` laundered through an unannotated hop) is correctly *rejected*, but the message reads:
```
error: type mismatch in 'badalias': expected BoolMap, got ? (an unannotated return type). A BoolMap value carries a fact that the verifier asserts from the declaration, ...
```
instead of "carries a per-key value range". SA-16 only asserts the specific wording for the two *non-aliased* fixtures (`map[int bool]` and `bytes[64]` written out literally), so this regression is untested and would not be caught by the current suite.

**Fix:** compute the noun from the expanded type, not the original:
```haskell
if isBareWildcard actual' && assumesFact expected'
  then tcWildAssumeError ctx expected expected'   -- pass both; use expected' only for the noun
  else tcTypeMismatch ctx expected actual
```
and in `tcWildAssumeError`, use the expanded argument for `wildAssumeFactNoun` while keeping the original for `typeLabel` in the rest of the message. (The other call site, `structuralUnify` at line 2237-2238, already passes the already-expanded `expected`, so only this call site needs the change.)

## Info

### IN-01: New test comments (SA-8, SA-11) cite `TypeCheck.hs` line numbers that no longer match the file after this same diff's own edits

**File:** `compiler/test/Spec.hs:147, 177-178`
**Issue:** SA-8's comment says "reaching structuralUnify's argument clause (TypeCheck.hs:2218)"; SA-11's says "expandAlias recurses into TMap components (TypeCheck.hs:2318)" and "unify expands both sides before compatibleWith (TypeCheck.hs:2331-2332)". This phase's own diff inserts 26 net lines earlier in `TypeCheck.hs` (the `@@ -343,24 +343,50 @@` hunk), shifting everything below it. In the file as it ships (current HEAD), the actual locations are: the WILD-ASSUME clause in `structuralUnify` is at line 2237 (not 2218), `expandAlias`'s `TMap` case is at line 2363 (not 2318), and `unify`'s `expandAlias`/`compatibleWith` calls are at lines 2376-2378 (not 2331-2332). A reader who jumps to the cited lines lands on unrelated code (`TPair`/`TFn` clauses in `structuralUnify`, or well past `unify` inside `TCState`'s successor definitions).
**Fix:** update the citations to the post-edit line numbers (2237, 2363, 2376-2378), or drop exact line numbers from comments describing code in the same file being edited and reference the function name only (e.g. "see `expandAlias`'s `TMap` case") so the comment does not drift on the next edit.

---

_Reviewed: 2026-08-01T05:09:32Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
