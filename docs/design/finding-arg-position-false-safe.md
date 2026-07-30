---
name: finding-arg-position-false-safe
title: "SAFE-ARG: a `bytes[n]` length fact is asserted from an unvalidated declaration, and the wildcard launders the declaration"
status: "Rev 2 — FIXED and RELEASED in v0.14.73 (`0e1327a` fix, `cc15e7c` release). Stage 1 is bytes-only; the map[k,bool] arm is roadmap row WILD-ASSUME-2. Rev 2 corrects the discriminant, which implementation proved dead as specified"
severity: "FALSE SAFE — a `verified` verdict on a memory-safety obligation that does not hold; not fail-closed"
found_by: professor review of ret-resolve-proposal, 2026-07-29; chain measured jointly with language-team over four review rounds
consumers: [compiler-engineer, documentation-lead, language-team, user]
---

# SAFE-ARG: a `bytes[n]` length fact is asserted from an unvalidated declaration

**One line.** The type channel lets a `bytes[32]` value satisfy a `bytes[64]` parameter when it
passes through one unannotated function, and the verifier then asserts `bytesLen(b) = 64` as a
ground fact from that parameter's declared type, discharging the index-in-bounds obligation
against a premise that is false.

This is the first defect on this line that is **not** fail-closed. Every prior member of the
FQ-RESULT-SORT-1 family exits 1 with a solver crash. This one reports `SAFE`, writes a
`.verified.json`, and records `display_level.level = "verified"` with `body_faithful: true` and a
`verified_hash`.

## Reproduction

Eight lines. `llmll check` passes; `llmll verify` reports SAFE.

```lisp
(def mk32 [] -> bytes[32] (bytes-zero))
(def-shell mid2 [] (mk32))                       ;; unannotated: the laundering hop
(def-shell consume [b: bytes[64] i: int] -> int
  (pre (and (>= i 0) (< i 64)))
  (post (>= result 0))
  (bytes-get b i))
(def-shell caller [i: int] -> int (pre (and (>= i 0) (< i 64))) (consume (mid2) i))
```

`consume` is certified for every `i` in `[0,64)` on a buffer that is 32 bytes long. The emitted
constraint set shows both halves:

```
bind 1 b : { v : (Map_t int int) | ((bytesLen v) = 64) }        ;; the false fact
...
lhs { v : int | ((bytesLen b) >= 0) && ((i >= 0) && (i < 64)) }
rhs { v : int | (0 <= i) && (i < (bytesLen b)) }               ;; discharged from it
```

## The chain, with a witness per step

| Step | Claim | Witness |
|---|---|---|
| 1 | A declared `bytes[n]` return over a body of another length is **rejected** | `P1_direct`, `P5_noncall`: "type mismatch in 'bad': expected bytes[64], got bytes[32]" |
| 2 | One unannotated hop launders the same mismatch past the type channel | `P2_wildcard`, `P3_declared_lie`, `Q1_argpos`: all `check` clean |
| 3 | The binder's declared type is turned into a ground fact | `bytesLenReft` ([`FixpointEmit.hs:1598-1600`](../../compiler/src/LLMLL/FixpointEmit.hs)), applied at `:1467`; `LLMLL.md:956` |
| 4 | The index obligation is discharged from that fact | `Q1_argpos` constraint above |
| 5 | The verdict is `SAFE` and is persisted | `Q1_argpos.llmll.verified.json`: `consume.post.display_level.level = "verified"`, `body_faithful: true`, `verified_hash` present |

Root of step 2 is `compatibleWith (TVar _) _ = True`
([`TypeCheck.hs:2185`](../../compiler/src/LLMLL/TypeCheck.hs)) together with `collectTopLevel`
registering an unannotated return as `TVar "?"` (`:919-936`).

**The argument position is what makes it live.** At a *return* position the same laundering also
injects a false fact, but the enclosing VC additionally equates `result` with a call binder that
`typeToSort` collapses to `FQInt` (no `TBytes` case, `FixpointEmit.hs:2429-2441`, consumed at
`:3165-3168`), so the constraint is ill-sorted and liquid-fixpoint refuses it. At an argument
position the false fact lands on a **parameter** of a function that is verified independently,
whose VC contains no call binder for it, so nothing crashes. `P5_noncall` is the witness that this
is structural rather than incidental: no call-free laundered lie exists, because any non-call
bytes-producing body synthesizes a concrete length that is compared against the declaration.

## Consequence, stated precisely

Codegen emits a dynamic bounds check: `bytes_get` is generated with
`| i < 0 || i >= length b = error ("bytes-get: pre-condition failed: index … out of bounds …")`
([`CodegenHs.hs:275`](../../compiler/src/LLMLL/CodegenHs.hs)). So the generated program **traps at
runtime**; it does not read out of bounds. What is falsely certified is the index-in-bounds
obligation itself. The user-visible failure is a runtime error in a program the verifier certified
free of exactly that error.

Severity is unchanged by this: a `verified` verdict on a memory-safety obligation that does not hold
is the most severe class this project recognizes, and `LLMLL.md:956` describes the obligation as
"real memory-safety, not a length proxy". The advisory must not say "certifies an out-of-bounds
read", because that overstates what the generated program does.

**The anti-laundering kernel cannot catch it.** `LLMLL.md:1060` makes a positive-tier record
ill-formed unless its qualifying fields cohere, enforced LCF-style on emit and on deserialization.
Here every field coheres: not `refuted`, empty `fallback_reason`, hash present. The invariant's scope
is field coherence, not antecedent truth, and this is the witness that the unguarded surface is the
one that matters.

## Affected version range

The binder fact `bytesLen(v) = n` enters with `bytesLenOf` at
**`c4ad7b6` (`feat(LEVER-A1): bytes[n] obligations discharge statically — the array class enters
Sigma_auto`, 2026-07-11)**, `compiler/package.yaml` at `0.14.33`, first release tag containing it
**`v0.14.34`**. Measured SAFE at v0.14.71 and v0.14.72. The bisect endpoints are recorded in
"Bisect" below; the intervening releases changed the compiler only where `compiler/src/` moved, so
treat the range as **v0.14.34 through v0.14.72 inclusive** unless a per-release run says otherwise.

## `assumes(τ)`: which types assert facts nothing discharges

Derived from the emitter's fact-injection sites rather than from probes, which is what the rule below
must be keyed on.

| Site | Fact injected | Derived from | Class |
|---|---|---|---|
| `bytesLenReft` `:1598-1600`, applied `:1467` | `bytesLen(v) = n` on a param or result binder | the binder's **declared type** | **`bytes[n]`** |
| `resultLenFact` `:1212-1213` | `bytesLen(result) = n` | `τ_ret` | **`bytes[n]`** |
| `injectRangeFacts` `:4156` | `0 ≤ select(arr,i) ≤ 255` | bytes-rootedness decided by binder **name** (`bytesRootedArr`, `:4161-4163`) | **`bytes[n]`** |
| `injectRangeFacts` `:4184` | `0 ≤ select(m$val,k) ≤ 1` | the declared **map value type** (`boolValRooted`) | **`map[k,bool]`** |
| `bytesVars` / `mapVars` `:1713-1716` | membership in the whole-array-eq gate | declared types | gate, not a fact |
| `:3355`, `:3373-3377` | index-in-bounds, value-range | PROVE-polarity **obligations** | not assumptions |
| `:2194`, `:2869`, `:3400`, `:3416` | map presence `select(h,k) = 1` | program text (a `map-has`/`map-get` occurred) or a PROVE obligation | not type-derived |
| `:3730` | `tag = 1` | program text (a match arm) | not type-derived |

Two families qualify: `bytes[n]` and `map[k,v]` where the value type constrains the encoding
(`bool` today). The third fact in the table adds harm rather than a new family: because
`bytesRootedArr` discriminates on binder *name*, a non-byte array laundered into a `bytes[n]`
parameter also receives false `0 ≤ … ≤ 255` value-range facts, not only a false length.

Measured non-members, each with a witness, so the rule is not written more broadly than the defect:

- **Refinement aliases are safe.** `Q2_alias`: `badp` declared `-> PositiveInt` over a laundered
  negative value is **REFUTED**, because the `§3.4.1` introduction obligation (`LLMLL.md:447`)
  makes the producer prove the predicate rather than assuming it.
- **Nullary enums are safe.** `R1_enum`: `badc` declared `-> ColorA` over a laundered `ColorB` is
  **REFUTED**; the lhs carries no tag-range fact and `result ∈ {0,1,2}` is left to prove.
- **Pairs, `Result`, payload sums** contribute sorts only; a mismatch is a sort disagreement and
  fails loudly (`P6b_map` crash pattern). Reasoned from the emitter, not probed.
- **`map[k,bool]` is a member with no reaching-SAFE witness.** `R2_mapbool` shows the false
  `0 ≤ … ≤ 1` asserted from the declaration with the obligation trivially implied by it; both the
  return shape (`R2_mapbool`) and the argument shape (`R3_maparg`) crash before a verdict. Fix it
  with the `bytes` arm; do not describe it as exploitable and do not describe it as safe.

## The rule: WILD-ASSUME

State the restriction on the absorbing clause itself, not on checking positions. Keying it on
checking positions misses argument passing, which is the position that is live.

```
    isHoleVar τ'      assumes(τ)
    ─────────────────────────────────────  (Absorb-Reject)
    compatibleWith τ' τ   =   False
```

`assumes(τ)` holds when `τ` contributes a fact to a VC antecedent that no obligation discharges: by
the table above, `bytes[n]` and `map[k,v]` with an encoding-constraining value type, and nothing
else today. The discriminant on the left is the **bare** `TVar "?"` of `collectTopLevel`, not
`isHoleVar` in general, so a named hole (`TVar ("?" <> h)`, `TypeCheck.hs:1600`) is untouched and
sketch mode is preserved.

**Two seams, not one (corrected from Rev 0 by engineer measurement).** Rev 0 cited
`compatibleWith:2185` alone. That is the *return* path, reached via `unify` (`:2248-2253`, called at
`:984, 1019, 1065, 1099`) and `checkExpr` (`:1289-1290`). The **live argument path does not go
through it**: `inferExpr (EApp …)` expands aliases and calls `structuralUnify` (`:1503-1515`), which
absorbs at `(_, TVar _) -> pure subst` (`:2122`, a line whose own comment already flags it as
soundness-adjacent). The guard must land in **both** functions, and the argument seam is the one that
closes `Q1_argpos`.

**Direction: guard the actual side only.** `compatibleWith` is symmetric (`:2185-2186`), but only the
configuration *expected = assuming type, actual = bare wildcard* launders. The reverse is inert: a
bare wildcard in expected position is the absence of a declaration, so there is no assertion for the
emitter to believe and no fact to falsify. Guard clause two (`compatibleWith _ (TVar _)`) with
`assumes` applied to the first argument; leave clause one alone. Polarity is preserved at every call
site (`unify:2251`, the `structuralUnify` fallback `:2159`, and `:1787`).

**Discriminant: the bare wildcard *and its freshened instances*, `?` or `?$N`.** Three TVar
populations reach these clauses, and the guard must fire on exactly one:

| Population | Source | Guard fires? |
|---|---|---|
| `TVar "?"`, `TVar "?$0"`, `TVar "?$17"` | `collectTopLevel:919-936` (and `inferHole (HChoose _)`, `:1602-1604`), then alpha-renamed per call site | **yes** |
| `TVar ("?" <> name)` | `inferHole:1600`, named holes | no, sketch mode is preserved |
| `TVar "a"`, `TVar "bs"`, `TVar "k"`, `TVar "v"` (and `bs$3`, …) | `builtinEnv:134-168` polymorphic signatures | no |

**Corrected by implementation, Rev 2.** Rev 1 of this finding specified *exact equality* with
`TVar "?"`, and both professor reviews endorsed it. That is wrong, and it made the rule **completely
dead**: `freshenFnType` (BUG-3, v0.14.3, `TypeCheck.hs:1935-1960`) alpha-renames every TVar in a
callee's signature at each call site as `v <> "$" <> counter` (`:2117`), so an unannotated return
reaches the use site as `TVar "?$0"` and never as `TVar "?"`. Measured: with the exact-equality guard
all five laundering probes still type-checked clean; relaxing the name check reported
`got ?$0`, which is how the encoding was identified. The correct predicate is
`n == "?" || "?$" isPrefixOf n`, which still excludes named holes (`?body_impl` does not start with
`?$`) and polymorphic variables (none start with `?`). This is the reason the rule is stated over a
named predicate rather than an inline pattern: the encoding of "bare inference wildcard" is not
self-evident from the constructor.

Writing the guard as `isHoleVar actual` or as a catch-all `TVar _` pattern would fire on population
three. Measured consequences, which differ by arm and are worth stating because the obvious witness
is not the reachable one:

- **Stage 1 (`bytes`): no reachable over-breadth witness.** `bytes-zero` returns `TVar "bs"`
  (`builtinEnv:164`) but is rejected in argument position by the LEVER-A0 determining-context rule
  (`:1934-1936`; measured: "(bytes-zero) requires a context that determines bytes[n]"), so it cannot
  reach a `bytes[n]` parameter. `bytes-set` also returns `TVar "bs"` (`:163`) but `applySubst`
  resolves it to the concrete buffer type from its first argument, so what arrives is `TBytes n`, not
  a TVar. The corpus typecheck-acceptance diff is therefore the stage-1 guard, not a fixture.
- **Stage 2 (`map`): the witness is reachable and it is `map-empty`.** `("map-empty", TFn []
  (TMap (TVar "k") (TVar "v")))` (`:168`) delivers polymorphic component TVars that `structuralUnify`
  absorbs componentwise via the `(TMap k1 v1, TMap k2 v2)` case into `(_, TVar _)`. That absorption is
  *legitimate*: it is how the context determines `k` and `v`. A loose discriminant breaks every
  `(map-empty)` at a typed map position. This fixture is required before the map arm ships.

**Ship in two stages.** Stage 1 (SAFE-ARG) restricts `assumes(τ)` to `bytes[n]`, which closes the
one live class and is the advisory release. Stage 2 adds the `map` arm and states the criterion in
the spec.

**FACT-AG, the general fix, is a research row and not this patch.** The principled form is that no
fact derived from a type enters a VC antecedent unless the function that declared the type has
discharged it, which means routing type-derived facts through the assume-guarantee channel that
already carries contract guarantees (`consumed_guarantees`, the `§5.3.4` meet). WILD-ASSUME
**approximates** FACT-AG; the two are one design with two implementations. The design-reference
precedent is F\*'s length-indexed buffers, where the length equality is discharged at the call site,
and Dafny's term-level `a.Length`, where no type-level lie is expressible.

## Edge cases and degenerate inputs

1. **Primary fixture, the live case.** `Q1_argpos` above. After the rule: type error at the
   argument. Channel: type. Cite `TypeCheck.hs:2185`.
2. **Return-position siblings.** `P2_wildcard`, `P3_declared_lie`: type errors after the rule, so no
   VC is emitted and the false fact has no site. Channel: type.
3. **Map arm.** `R2_mapbool`: rejected under stage 2. Channel: type.
4. **Over-breadth guard, refinement alias.** `Q2_alias` must keep type-checking and keep reporting
   `badp` REFUTED. Rejecting it means `assumes(τ)` was implemented over "carries type-level data"
   instead of over "asserts an undischarged fact". Channel: contract, `§3.4.1`.
5. **Over-breadth guard, enum.** `R1_enum` must keep type-checking, keep reporting `badc` REFUTED,
   and keep its lhs free of a tag-range fact. Channel: contract.
6. **Scope boundary, scalars.** All 102 unannotated corpus definition heads keep type-checking;
   `assumes(TInt)` is false. This holds the blast radius at zero and distinguishes WILD-ASSUME from
   the general wildcard narrowing the project has twice declined. Channel: type.
7. **Hole at an assuming position.** `(def-shell f [] -> bytes[64] ?body)` must not be rejected: a
   hole is a checking target, not a laundering path. Channel: type; the name discriminant is the
   answer, and the spec should say so rather than leave it derivable.
8. **Over-breadth witness for the map arm, required before stage 2.** `(map-empty)` passed where a
   `map[int,bool]` is expected must keep type-checking. `map-empty : TFn [] (TMap (TVar "k")
   (TVar "v"))` (`builtinEnv:168`) relies on the componentwise absorption that `structuralUnify`
   performs through its `(TMap k1 v1, TMap k2 v2)` case into `(_, TVar _)`, and that absorption is
   how the context determines `k` and `v`. Channel: type. A discriminant written as `isHoleVar` or
   `TVar _` rather than exact `TVar "?"` breaks this.
9. **The obvious bytes over-breadth witness does not exist.** `(consume (bytes-zero) i)` with
   `consume : bytes[64] -> …` is **already** an error today: "(bytes-zero) requires a context that
   determines bytes[n]" (LEVER-A0 determining-context rule, `TypeCheck.hs:1934-1936`). Recorded so a
   later reader does not add it as a stage-1 fixture and conclude the guard is over-broad when the
   rejection came from elsewhere. Channel: type; the stage-1 over-breadth guard is the corpus
   typecheck-acceptance diff, not a fixture.

## Verification mapping

WILD-ASSUME introduces **no proof obligation**. It is a decidable syntactic admissibility rule, the
same status as the `§3.4.4` predicate well-formedness rule and the strict-core whitelist.

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| `bytesLen(b) = n`, once earned rather than assumed | contract | QF theory of arrays + QF-LIA, polite-combined, decidable | `LLMLL.md §5.3.3` array class at `:956` |
| map value range `0 ≤ select ≤ 1`, same | contract | QF arrays + QF-LIA | `:956` |
| FACT-AG's call-site length/sort obligation | contract | QF-LIA, PROVE polarity, same shape as index-in-bounds | `:956`; research row, not this patch |
| the laundering, post-rule | type | not an SMT obligation; rejected at check time | the rule above |

Nothing nonlinear, nothing quantified, nothing escapes to Lean.

## Affected surface

1. `compiler/src/LLMLL/TypeCheck.hs:2122` (`structuralUnify`, the live argument seam) **and**
   `:2185-2186` (`compatibleWith`, the return and `checkExpr` seam): both gain the `assumes(τ)` side
   condition, guarding the actual side only, keyed on exact `TVar "?"`. No emitter change.
2. `compiler/src/LLMLL/VerifiedCache.hs:283-284, 287-308`: sidecars written by affected versions must
   be invalidated. Two corrections to Rev 0, both measured. `sidecarNeedsRevalidation` is
   **`_top = False`, a stub**, not a field-absence trigger; the comment block at `:227-232` describes
   the historically disarmed INT-1 trigger, not the body. And the stamp is **not in the sidecar** at
   all: `codegenSemanticsVersion` (`ProofArtifact.hs:214-215`) reaches only the proof artifact
   (`Main.hs:2668`), so the change is writer plus reader plus constant.

   **Use a new key, `checker_soundness_version`, not `codegen_semantics_version`.** The latter is
   specified for a different axis, `int` versus `machine-int` codegen semantics
   (`ProofArtifact.hs:201`; `LLMLL.md:1050`, where INT-3's re-arm depends on it), and one string
   cannot say which axis moved. Emit `checker_soundness_version` as a reserved top-level key in
   `saveVerifiedWith` (`:303-308`, alongside `reservedCallerObligationsKey`), and invalidate on
   absent-or-mismatched in `sidecarNeedsRevalidation`.

   **SAFE-ARG introduces the field; it bumps nothing.** No sidecar in the affected range carries the
   key, so absence alone is the affected-range signal and the initial value can be `"1"`. This is
   safe in exactly the way the INT-1 field-absence trigger was not: that trigger over-invalidated
   because the writer *legitimately omitted* `overflow_tainted` on every verified entry
   (`VerifiedCache.hs:227-232`), whereas the writer here emits `checker_soundness_version`
   unconditionally, so absence is a sound "written by an older compiler" signal rather than a
   normal state.
3. Fixtures: the seven cases above, with `Q2_alias` and `R1_enum` as over-breadth guards and the
   unannotated-int corpus as the scope guard.
4. Gates: corpus typecheck-acceptance diff (expected empty); corpus `.fq` byte-identity (expected
   empty); a sidecar test showing an affected-stamp sidecar is refused.
5. **Spec drift, narrowed on the doc pass — and it is `§3.4.6`, not `§3.4.5`.** The first statement
   of this item claimed the erasure section was inaccurate for the array class. That overstates it.
   `§3.4.5`'s Theorem A quantifies over **refinement-alias predicates** (`A ≜ (where [x: τ] p)`) and
   says those carry no runtime residue; the `bytes_get` bounds check at `CodegenHs.hs:275` is a
   builtin's own guard, not an erased predicate's residue, so the theorem stands untouched. What the
   guard actually complicates is the **unscoped parenthetical at `§3.4.6`**, "Because LLMLL erases and
   inserts no casts (§3.4.5)", which is used there to justify why `?`-admission carries no runtime
   guard. **Route to language-team, not documentation-lead**: doc-lead correctly declined it on the
   v0.14.73 pass, because deciding which side moves is a spec adjudication rather than a doc edit.
   Whether other builtins carry runtime guards is still unmeasured; a sweep over `CodegenHs.hs` is
   owed either way.
6. **Roadmap severity correction.** `docs/compiler-team-roadmap.md:53` carries "Fails closed (exit 1,
   a crash, never a false SAFE), so no prior verdict is affected". That is accurate for
   FQ-RESULT-SORT-1's own shapes and false at HEAD for the array class. The line must be scoped.
7. `CHANGELOG.md`: a correctness advisory naming the version range, the eight-line shape, the
   consequence (a runtime trap on an obligation certified discharged, not memory unsafety), and the
   fact that affected sidecars carry a coherent `verified` record.
8. Freeze policy: not applicable, lifted at v0.11 (`docs/compiler-team-roadmap.md:234`). No new
   builtin, syntax construct, FFI tier, or orchestration surface; no JSON-AST or schema change.

## Bisect

Closed. Endpoints measured against purpose-built binaries; the lower bound is settled from source
because the obligation and the fact were introduced by the same commit.

| Commit / version | `Q1_argpos` | Basis |
|---|---|---|
| v0.14.72 (`c43654b`, HEAD) | **SAFE**, sidecar written | measured |
| v0.14.71 (`a623e46` = `d97d388^`) | **SAFE**, identical `bind`/`lhs`/`rhs` | measured, `--fast` build at that commit |
| `c4ad7b6` (LEVER-A1; `package.yaml` 0.14.33, first release tag **v0.14.34**) | **SAFE**, `check` clean | measured, `--fast` build at that commit; binary reports `llmll 0.14.33` |
| `c4ad7b6^` | **not applicable** | `bytesLen` occurs **0** times in `FixpointEmit.hs` at `c4ad7b6^` and **25** times at `c4ad7b6`; neither the length fact nor the index-in-bounds obligation existed, so there is no obligation to discharge falsely |

**Affected released range: v0.14.34 through v0.14.72 inclusive.** The fact
(`bytesLenReft`) and the obligation it discharges (index-in-bounds) entered together at
`c4ad7b6`, so the defect is coeval with the array class rather than introduced by any later
change. Nothing in the FQ-RESULT-SORT-1 line caused it; stage (a) (`d97d388`) widened the *return*
position variant, which is masked, and left this one untouched.

## Appendix: probe sources

Recorded so the finding is reproducible without the session that produced it. Each was run against
`llmll 0.14.72` and, where noted above, against purpose-built binaries at v0.14.71 and `c4ad7b6`.

```lisp
;; P1_direct — declared length mismatch, no hop. REJECTED (the check that works).
(def mk32 [] -> bytes[32] (bytes-zero))
(def-shell bad [] -> bytes[64] (mk32))

;; P2_wildcard — the same mismatch through one unannotated hop. check CLEAN.
(def mk32 [] -> bytes[32] (bytes-zero))
(def-shell mid2 [] (mk32))
(def-shell bad [] -> bytes[64] (mid2))
(def-shell top2 [] (post (= (bytes-length result) 64)) (bad))

;; P3_declared_lie — the lie is in the declaration. False fact injected at BOTH versions.
(def mk32 [] -> bytes[32] (bytes-zero))
(def-shell mid2 [] (mk32))
(def-shell bad2 [] -> bytes[64] (post (= (bytes-length result) 64)) (mid2))

;; P4_truthful — control: same VC shape, no call binder, truthful. SAFE (correctly).
(def-shell good [] -> bytes[64] (post (= (bytes-length result) 64)) (bytes-zero))

;; P5_noncall — a lie whose body needs no call binder. REJECTED, which is why the
;; return-position variant is structurally masked.
(def-shell bad3 [b: bytes[32]] -> bytes[64] (post (= (bytes-length result) 64)) (bytes-set b 0 1))

;; Q1_argpos — THE LIVE CASE. check clean, verify SAFE, sidecar written.
(def mk32 [] -> bytes[32] (bytes-zero))
(def-shell mid2 [] (mk32))
(def-shell consume [b: bytes[64] i: int] -> int
  (pre (and (>= i 0) (< i 64)))
  (post (>= result 0))
  (bytes-get b i))
(def-shell caller [i: int] -> int (pre (and (>= i 0) (< i 64))) (consume (mid2) i))

;; Q2_alias — over-breadth guard. check clean, badp REFUTED: aliases carry an obligation.
(type PositiveInt (where [x: int] (> x 0)))
(def mkneg [] -> int (- 0 5))
(def-shell midp [] (mkneg))
(def-shell badp [] -> PositiveInt (midp))
(def-shell userp [] (post (> result 0)) (badp))

;; R1_enum — over-breadth guard. check clean, badc REFUTED, no tag-range fact in the lhs.
(type ColorA (| Red) (| Green) (| Blue))
(type ColorB (| A) (| B) (| C) (| D) (| E))
(def mkD [] -> ColorB (D))
(def-shell midc [] (mkD))
(def-shell badc [] -> ColorA
  (post (or (= result Red) (or (= result Green) (= result Blue))))
  (midc))

;; R2_mapbool — the map arm: false 0..1 range asserted from the declaration, obligation
;; trivially implied by it. Crashes before a verdict.
(def mkint [k: int] -> map[int int] (map-put (map-empty) k 7))
(def-shell midb [k: int] (mkint k))
(def-shell badb [k: int] -> map[int bool]
  (post (or (= (map-get result k) true) (= (map-get result k) false)))
  (midb k))

;; P6b_map — the map laundering, type channel only. check CLEAN.
(def mkstr [k: int] -> map[int string] (map-put (map-empty) k "x"))
(def-shell midm [k: int] (mkstr k))
(def-shell badm [k: int] -> map[int int] (post (>= (map-get result k) 0)) (midm k))
```

## Provenance

Found in review round 4 of `ret-resolve-proposal.md`, by testing whether the fix proposed in round 3
was complete over positions rather than by arguing about the design. The two highest-value findings
in that thread both came from testing a claim in the previous turn's own text. Recorded here because
the process point is reusable: the channel count for `τ_ret` moved 1 → 2 → 4 → 4-plus-parameters
across four rounds, each increment found by reading rather than by deriving the consumer set from
the emitter. The table in "`assumes(τ)`" above is the derived version, and it is the artifact that
should have existed in round 1.
