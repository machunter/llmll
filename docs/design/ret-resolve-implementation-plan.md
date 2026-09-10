---
name: ret-resolve-implementation-plan
title: "RET-RESOLVE implementation plan: resolve a wildcard tau_ret transitively in a verification-facing pass"
status: "Rev 1, review-ready. Implements docs/design/ret-resolve-proposal.md (Rev 2). Part 1 re-scopes the four-channel table against HEAD at v0.23.0 and routes the correction to a Rev 3 of the proposal. Not implemented; no compiler source is changed by this document."
date: 2026-09-09
author: compiler-engineer
consumers: [user, language-team, professor, documentation-lead]
---

# RET-RESOLVE implementation plan

## Restatement

Add a verification-facing fixpoint pass over the recorded return-type map. The pass replaces a bare
`TVar "?"` return type with the type the body synthesizes in the strengthened environment. The type
channel's accept and reject set does not change. The acceptance gate is a corpus sweep that must show
an identical `.fq` and an identical verdict set.

This document is a plan. It changes no compiler source.

## Context located

- `docs/compiler-team-roadmap.md` row `RET-RESOLVE` (line 77 of the Active Items table) gives the
  ticket, the `PLAN` marker, the "128 files" claim and the re-scoping instruction.
- `docs/design/ret-resolve-proposal.md` (Rev 2, SETTLED) gives the rule, the three side conditions
  SC1 / SC2' / SC3', the four-channel table in section "What the pass changes", the gate, and the
  invariants I1 and I2.
- `docs/archive/professor-reviews/ret-resolve-proposal-review.md` gives four review rounds. Round 3
  records that the reviewer's proposed `resultLenFact` fix was refuted by measurement.
- `compiler/src/LLMLL/TypeCheck.hs`: `collectTopLevel`, `recordRetType`, `tcRetTypes`,
  `checkStatement`, `preferConcreteOnSelfCall`, `isHoleVar`, `inferHole`, `cyclicMembers`,
  `typeCheckWithCacheModeRet'`.
- `compiler/src/LLMLL/FixpointEmit.hs`: `effRet`, `emitFnConstraints`, `sortA1`, `typeToSortA`,
  `typeToSort`, `calleeRetSort`, `contractSigGuardsBlock`, `augmentContractPost`,
  `returnRefinementPost`, `bytesLenRetPost`, `wholeArrEqClause`, `injectRangeFacts`,
  `injectBoolValRangeFacts`, `seedImportedContracts`.
- `compiler/src/LLMLL/Module.hs`: `loadModule` (the import-path typecheck), `buildModuleEnv`,
  `meRetTypes`.
- `compiler/src/LLMLL/TypeAdmissibility.hs`: `admits`, `wildAssumeRejects`.
- `compiler/src/LLMLL/VerifiedCache.hs`: `checkerSoundnessVersion`, `sidecarNeedsRevalidation`.
- `compiler/src/LLMLL/TrustReport.hs`: `downgradeStaleVerifiedSidecar`.
- `compiler/app/Main.hs`: the `verify` entry path and `emitSynthetic`.
- `compiler/test/Spec.hs`: the block `FQ-RESULT-SORT-1: result binder sorts from the effective return
  type`, tests `FQRS-1` to `FQRS-8`, `EMITDIAG-1`, `RBP-1` to `RBP-3`.
- `scripts/fallback_census.py` and `scripts/fallback-census/BASELINE.json`: the live corpus
  instrument and its ratchet floor.
- `.github/workflows/version-gate.yml`: jobs `C1-C4` (banner, schema, pytest) and `C5` (toolchain,
  hspec, refute-crux, build gate, fallback census).

## Part 1: prerequisite re-scoping

The roadmap row states that channel 4 of the proposal no longer exists, and that the prerequisite
chain must be re-scoped before the row is scheduled. This section verifies that statement against the
source and gives the corrected table.

### The roadmap's account, tested

**The account holds on its own terms, and it is incomplete.**

1. **`resultLenFact` is gone.** `rg` over `compiler/src` finds no definition and no use. Five
   comments name it, in `FixpointEmit.hs` and `TypeAdmissibility.hs`, and each says it was deleted.
   `bytesLenReft`, its binder-side twin, is gone the same way. This claim is *eliminative*: the
   search covered the whole of `compiler/src` and returned zero definitions.
2. **The fact moved into the effective post.** `bytesLenRetPost` is conjoined into
   `returnRefinementPost`, which `augmentContractPost` folds into the contract. So the length is a
   goal in the body VC, not an antecedent. This is the shape the roadmap describes.
3. **`WILD-ASSUME-2` shipped at v0.14.74.** Confirmed twice. The roadmap release table carries the
   row. The source carries the mechanism: `admits am t = boolValuedMapTy am t` is the soundness set,
   and `wildAssumeRejects am t = admits am t || isJust (bytesLenOf am t)` is the diagnostic set that
   the two `TypeCheck` seams read. `WILD-ASSUME` Stage 1 (bytes) shipped at v0.14.73.
4. **The row's account is incomplete in three ways.** Channel 4 of the proposal cited **two** sites,
   not one. The second site, `wholeArrEqClause`, still exists. Two further assumption-injection sites
   that the proposal never listed are live and are fed by `tau_ret`. Section "The corrected channel
   table" gives all of them.

### Channel-by-channel verdict at HEAD (v0.23.0)

**Channel 1, sort lowering. UNCHANGED and live.** `emitFnConstraints` derives the `result` binder
sort with `sortA1`, which falls through to `typeToSortA` and then to `typeToSort`. `typeToSort` ends
with `typeToSort _ = FQInt`, so a bare `TVar "?"` and `int` lower to the same sort. `calleeRetSort`,
in the `CallVC` arm of `bodyToPredM`, sorts a call-result binder from the ContractEnv third slot,
which `effRet` overrides with `tau_ret`.

**Channel 2, admissibility gating. UNCHANGED and live.** `contractSigGuardsBlock` composes
`sigPairUnsafe` and `resultReturnUnsafe`. Both read `mRet`. A wildcard that resolves to a pair with a
non-sortable component, or to a non-admissible `Result`, moves the function to `erBodyFallback`.

**Channel 3, effective-post augmentation. WIDENED, and asymmetric.** `augmentContractPost` reads the
effective `mRet` at the definition site, inside `emitFnConstraints`. Since FACT-AG-LEN Stage 3 it
also folds `bytesLenRetPost`. So a resolved `bytes[n]` return adds a proof obligation to the body VC.

The asymmetry matters and the proposal does not record it. The ContractEnv builder applies
`augmentContractPost` **before** `effRet` replaces the third slot. Read the order in
`buildContractEnvWith`: `aug params mRet c` runs on the raw statement's `mRet`, and
`emitFixpointWithCache` then maps `effRet` over the third slot only. `seedImportedContracts` has the
same order. So a resolved return type adds an obligation at the definition site and exports no
guarantee to callers. The direction is conservative: the function owes more and promises the same.

**Channel 4a, `resultLenFact`. GONE.** See above. The proposal's "crash or `refuted` to `verified`"
direction for this site no longer exists.

**Channel 4b, post-assumption unblocking at a call site. LIVE, and sound.** The `CallVC` arm computes
`mPostPred` and drops the callee's post when `bytesOpOnResult (contractPost contract)` holds and
`calleeRetSort /= byteArraySort`. That guard is a sound weakening. Resolving `tau_ret` to `bytes[n]`
makes `calleeRetSort` the array sort, so the guard stops firing and the caller assumes a post it did
not assume before. This is the proposal's channel-4 direction at a different site. **It is sound
under FACT-AG-LEN Stage 3**, because the assumed clause is the callee's written post, and the callee
now proves its own result length as a goal. This satisfies invariant I2 by construction for the
`bytes[n]` length class.

**Channel 4c, ground range facts on the constraint LHS. LIVE, with an empty corpus population.**
`injectRangeFacts` conjoins facts into `conLhs`. For a `Map_select` whose array argument satisfies
`bytesRootedArr`, it conjoins `0 <= t` and `t <= 255`. `bytesRootedArr` is default-true on any
`FQVar` whose name lacks a `$has` or `$val` suffix, which is the open row `ARR-RANGE-NAME`.
`injectBoolValRangeFacts` conjoins `0 <= v <= 1` for each `$val` array in `boolValArrs`, and
`boolValArrs` is built from `params ++ [("result", rt) | Just rt <- [mRet]]`. Both are reachable only
when the resolved `tau_ret` is a `bytes[n]` or an admissible bool-valued map. **No corpus wildcard
resolves to either type** (see "Corpus measurement"). So the population is empty today and
`ARR-RANGE-NAME` is not a blocking prerequisite. It needs a guard test, not a queue position.

**Channel 5, whole-structure equality fallback. LIVE, and conservative.** `wholeArrEqClause` was
listed inside channel 4 of the proposal. It is not an assumption injection. It is a fallback gate:
`postCause` returns `FallbackContractPost` or `FallbackContractPre` when it fires. Its `bytesVars`
and `mapVars` sets include `"result"` when `mRet` is a bytes type or a map type. So resolving
`tau_ret` moves the function from a body-faithful VC to a contract-only fallback. The direction is
channel 2's, not channel 4's.

### The corrected channel table

**Proposed replacement text for `docs/design/ret-resolve-proposal.md` section "What the pass changes:
four channels". This edit is owed to a Rev 3 of that proposal. This plan does not apply it.** The
section heading changes from "four channels" to "five channels", and the table becomes:

| # | Channel | Site (construct) | Direction | Status at v0.23.0 |
|---|---|---|---|---|
| 1 | Sort lowering of `result` and of call binders | `sortA1` in `emitFnConstraints`; `calleeRetSort` in the `CallVC` arm of `bodyToPredM` | crash to verdict | Live and unchanged |
| 2 | Admissibility gating | `contractSigGuardsBlock`, over `sigPairUnsafe` and `resultReturnUnsafe` | verdict to `asserted` | Live and unchanged |
| 3 | Effective-post augmentation | `augmentContractPost`, at the definition site only | obligation added; `verified` to `refuted` possible | Live and **widened**: FACT-AG-LEN Stage 3 added `bytesLenRetPost`. The ContractEnv applies `aug` **before** `effRet`, so a resolved return exports no guarantee to callers |
| 4a | Assumption injection from the declared length | `resultLenFact` | was crash or `refuted` to `verified` | **Deleted at v0.14.78.** The channel does not exist |
| 4b | Post-assumption unblocking at a call site | the `bytesOpOnResult` and `calleeRetSort` guard in the `CallVC` arm | post dropped, to post assumed | Live. **Sound** under FACT-AG-LEN Stage 3: the callee proves the length it exports |
| 4c | Ground facts on the constraint LHS | `injectRangeFacts` with `bytesRootedArr`; `injectBoolValRangeFacts` over `boolValArrs` | `refuted` to `verified` | Live. Reaching population is **empty** in the corpus. Open row `ARR-RANGE-NAME` owns the name-based decision |
| 5 | Whole-structure equality fallback | `wholeArrEqClause` | body-faithful to contract-only | Live. Conservative. Listed under channel 4 in Rev 2, which mis-stated its direction |

Two further Rev 3 corrections belong with the table:

- **The proposal's affected-surface item 5 names the wrong stamp.** It asks for a
  `codegen_semantics_version` increase in `ProofArtifact.hs`. That stamp tracks int against
  machine-int codegen semantics and is `INT-3`'s re-arm discriminator. `VerifiedCache.hs` says in
  terms that spending it on a checker change would leave `INT-3` without one. The stamp for a checker
  change is `checkerSoundnessVersion` in `VerifiedCache.hs`, currently `"2"`. See "Verification
  impact" for the condition under which RET-RESOLVE needs it.
- **The proposal's affected-surface list misses a third consumer of `tau_ret`.** `Main.emitSynthetic`
  builds a CDP or weakness candidate program and calls `typeCheckWithCacheRet` for its map. So
  `--cdp` and `--weakness-check` read the resolved map too.

### The prerequisite chain today

Every ordering constraint the proposal's "Ordering" section states is discharged.

| Prerequisite | Status | Evidence |
|---|---|---|
| `SAFE-ARG` | SHIPPED v0.14.73 | roadmap Closed table row |
| `WILD-ASSUME` (bytes arm) | SHIPPED v0.14.73 | roadmap; `wildAssumeRejects` in `TypeAdmissibility` |
| `WILD-ASSUME-2` (map arm) | SHIPPED v0.14.74 | roadmap; `admits = boolValuedMapTy` |
| `FACT-AG-LEN` Stages 1 to 3 | SHIPPED v0.14.76 to v0.14.78 | roadmap; `bytesLenParamPre`, the `bodyToPredM` axiom equation, `bytesLenRetPost` |
| `ARR-RANGE-NAME` | OPEN, **not blocking** | reaching population measured empty; guard test in the test plan |

**RET-RESOLVE is unblocked.** The channel that carried the blocking argument is deleted, and the
channel that replaced it (4b) is sound for the reason FACT-AG-LEN exists.

## Corpus measurement

The row claims a byte-identical `.fq` across "all 128 files". **The corpus size does not hold. The
census predicate does hold, and it is sharper today than when it was written.**

### Corpus size

| Population | Definition | Count today |
|---|---|---|
| Rev 2 census corpus | tracked `.llmll` under `examples/`, `compiler/test/fixtures/`, `tools/` | **228** (was 151 at Rev 2) |
| The same roots, JSON-AST | tracked `.ast.json` under the same three roots | **79**, and the Rev 2 census never read them |
| `FALLBACK-CENSUS-1` population | tracked `.llmll` and `.ast.json` under `examples/`, `tools/`, `scripts/build-smoke` | **250** (175 `.llmll`, 75 `.ast.json`) |
| `FALLBACK-CENSUS-1` strict-pass floor | `scripts/fallback-census/BASELINE.json` | **98** files |
| Compiler fixture corpus | tracked under `compiler/test/fixtures/` | **68** (64 `.llmll`, 4 `.ast.json`) |

**No `.fq` file is tracked and none is on disk.** `git ls-files '*.fq'` returns nothing and a
filesystem search returns nothing. So "128 files" cannot be checked against an artifact; it was a
count of `.fq`-producing files inside a 151-file S-expression-only corpus in July. **Do not quote
it.** The number to quote is the sweep population: 250 files under the `FALLBACK-CENSUS-1` roots plus
68 fixture files, 318 in total, over two source surfaces.

### The census predicate

A syntactic reader over both surfaces reproduces the Rev 2 census and extends it. The reader models
the compiler's own rules: `collectTopLevel` seeds every unannotated head at `TVar "?"`,
`checkStatement` never refines the environment binding for a definition, so a call to an unannotated
definition synthesizes the wildcard whatever the source order; and `inferExpr (EIf ...)` returns the
then-branch type unless `preferConcreteOnSelfCall` fires.

S-expression surface, 228 files, 1120 definition heads:

- **102 unannotated heads, 30 unannotated and contracted.** Both figures are identical to the Rev 2
  census, on a corpus 51 percent larger. The wildcard population did not grow.
- **16 heads have a bare `TVar "?"` as their recorded `tau_ret`**, 13 of them contracted.
- **4 more heads carry a named hole type.** SC1 retains those.
- Kleene iteration reaches the fixpoint in **2 rounds** (one productive round, one confirming round).
- **Every contracted bare wildcard that resolves at all resolves to `int`: 12 of 12.** They are
  `examples/banking_ledger/banking.llmll` and `banking-bad.llmll` (four each),
  `examples/withdraw-demo/compose.llmll` and `compose-bad.llmll`,
  `compiler/test/fixtures/xmod-alias/use.llmll` and `compiler/test/fixtures/xmod-tier/compose.llmll`.
- One contracted wildcard, `examples/benchmarks/b3-safe-first.llmll :: safe-first`, stays a wildcard.
- The three non-contracted wildcards are the three files the Rev 2 census named as the expected
  sources of surprise: `examples/hangman_sexp/hangman.llmll :: game-won?`,
  `examples/life_sexp/world.llmll :: glider-grid` and `examples/life_sexp/world.llmll :: evolve`.

JSON-AST surface, 79 files, 276 definition heads, **139 unannotated**:

- **6 heads have a bare wildcard `tau_ret`.**
- One is contracted: `examples/totp_rfc6238/totp_filled.ast.json :: generate-totp`, and it resolves
  to **`int`**.
- One stays a wildcard: `examples/conways_life_json_verifier/life.ast.json :: neighbor-alive`.
- Four are contract-free: `examples/life_json/world.ast.json :: evolve` (resolves to a pair),
  `examples/hangman_json_verifier/hangman.ast.json :: game-won?` (resolves to **bool**),
  `examples/hangman_json/hangman.ast.json :: game-won?`, and
  `examples/life_json/world.ast.json :: glider-grid`.

**The predicate holds.** `sortA1` on `int` reaches `typeToSortA` and then `typeToSort TInt = FQInt`,
which is the same sort a bare wildcard reaches through `typeToSort _ = FQInt`. Every contracted
wildcard in the corpus resolves to `int` or stays a wildcard, on both surfaces. So the `.fq` bytes
are predicted identical.

These classification claims are **corroborative**, not eliminative. The reader is not `inferExpr`. It
must be confirmed by the sweep. The head counts and the file counts are eliminative: they come from
`git ls-files` over the whole tree.

### The gate is not complete, and this is measured

The proposal states that a byte-identical corpus `.fq` is a complete gate across all channels,
"because sorts, lhs facts, and rhs obligations are all rendered in the file". **That is false for a
contract-free function.** Measured at v0.23.0 with the installed binary:

```
$ llmll verify examples/life_sexp/world.llmll
   .fq written to /tmp/world.fq
   body-fallback: make-world, get-cell, count-neighbors, evolve-row, cell-to-char,
                  make-empty-row, set-cell-in-row, set-cell-in-grid, glider-grid
   Running liquid-fixpoint ...
   world.llmll — SAFE (liquid-fixpoint)
```

The emitted `.fq` is 32 lines. It contains the `Pair2` datatype declaration, seven qualifiers and 24
parameter binds. **It contains no constraint and no `result` binder.** `world.llmll` declares no
`pre` and no `post`, so no goal is emitted. `evolve` is not in the fallback list today.

The consequence: if `evolve`'s `tau_ret` resolves to a pair with a non-sortable component,
`sigPairUnsafe` fires, `evolve` joins the fallback list, and **the `.fq` bytes do not change**. The
same holds for the three other contract-free change candidates. **The gate must therefore compare the
emitter's fallback set and the trust tiers as well as the `.fq` bytes.** The `FALLBACK-CENSUS-1`
record is the artifact that carries both.

## Plan summary

Insert a Kleene fixpoint over the recorded return-type map at the single seam where that map leaves
the type checker, and leave every other channel alone. `typeCheckWithCacheModeRet'` is the one shared
implementation, and it is the only place that reads `tcRetTypes st`. Its report-only wrapper
`typeCheckWithCacheMode'` discards the map, so a change at that seam cannot reach the type channel's
accept or reject set. The pass re-synthesizes each bare-wildcard body in an environment that binds
every top-level function at its current resolved type, keeps concrete entries fixed (SC1), discards
every state accumulator except the map (SC2'), and uses an SCC-conditioned branch preference (SC3').
Cross-module resolution needs one extra seed from each cached module's `meRetTypes`. `FixpointEmit`
needs no change. The cost is one extra inference pass over the entry module's bodies, which is a
small multiple of the existing single pass. The gate is a two-build corpus sweep over 318 files.

## Affected surface

Grouped from the entry point to the output.

- `compiler/src/LLMLL/TypeCheck.hs`, `typeCheckWithCacheModeRet'`: the single seam. The returned
  pair's second component becomes `resolveRetTypes ... (tcRetTypes st)` instead of `tcRetTypes st`.
- `compiler/src/LLMLL/TypeCheck.hs`, new `resolveRetTypes`: the Kleene iteration. Runs a fresh
  `runState` per candidate body and reads back only the synthesized type (SC2').
- `compiler/src/LLMLL/TypeCheck.hs`, new `sccOf`: a sibling of the existing `cyclicMembers`, giving
  the component membership SC3' needs. `TypeCheck.hs` already imports `buildCallGraph` from
  `HoleAnalysis` and `stronglyConnComp` with `SCC(..)` from `Data.Graph`, so this adds no import and
  no package dependency.
- `compiler/src/LLMLL/TypeCheck.hs`, new `preferConcreteInSCC`: the SC3' variant of the join rule.
  `preferConcreteOnSelfCall` stays exactly as shipped for the type channel. Widening the shipped
  function in place would move the type channel's accept set, which SC2' forbids.
- `compiler/src/LLMLL/TypeCheck.hs`, `isHoleVar`: read, not changed. SC1's discriminant is
  `t == TVar "?"`, which is strictly narrower than `isHoleVar`, because `inferHole` produces
  `TVar ("?" <> name)`.
- `compiler/src/LLMLL/Module.hs`, `loadModule`: the import-path call to `typeCheckWithCacheRet`
  already runs one line before `buildModuleEnv`. The pass must be seeded with the cached modules'
  `meRetTypes`. The seed is available at that point in `cache1`.
- `compiler/src/LLMLL/FixpointEmit.hs`: **no code change**. `effRet` already routes the map to every
  consumer. Behaviour changes across five channels without an edit here.
- `compiler/src/LLMLL/VerifiedCache.hs`, `checkerSoundnessVersion`: changed **only if** the sweep
  shows a verdict move on a function that carries `verified` evidence. See "Verification impact".
- `docs/llmll-ast.schema.json`: no change, no version increase. No node shape moves.
- `LLMLL.md`: the `documentation-lead` owns this. Section 3.4.6's sentence naming the channels needs
  the corrected count, and section 5.3.5 needs the I2 disclosure. Not this plan's edit.
- `docs/compiler-team-roadmap.md`: the `documentation-lead` moves the row. Not this plan's edit.
- `docs/design/ret-resolve-proposal.md`: the corrected channel table above is **owed to a Rev 3**,
  which the `language-team` writes. This plan does not edit that document.

## Step sequence

Nine steps. Steps 1 and 2 are measurement and must complete before any code is written, because step
2 can refute the gate's prediction before the patch exists.

1. **Re-run the census over both surfaces and record it.** Extend the Rev 2 reader to the JSON-AST
   node kinds (`app`, `qual-app`, `op`, `if`, `let`, `do`, `match`, `pair`, `lit-*`, `var`,
   `hole-named`, `hole-delegate`). Record the bare-wildcard set, its resolution, and the Kleene round
   count for all 318 files. Expected output is the table in "Corpus measurement". Deliverable is a
   file under `docs/design/`, not a compiler change.
2. **Capture the pre-change baseline.** Build `main`, then **copy the binary aside before any later
   build overwrites the install root**. Sweep the corpus with it and store the `.fq` files, the
   stdout, and a `fallback_census.py --out` record. See "Byte-identity verification procedure".
3. **Add `sccOf` and `preferConcreteInSCC`.** Pure functions, no state. Unit-testable without the
   emitter.
4. **Add `resolveRetTypes` and wire it at the seam.** Implement SC1 and SC2' first, with SC3'
   disabled (the join falls through to `preferConcreteOnSelfCall`). Run `stack test`. The three
   `RBP-*` tests and the eight `FQRS-*` tests must pass unchanged.
5. **Enable SC3'.** Run `stack test` again. `RBP-2` is the pin that decides this step: it asserts that
   a foreign unannotated callee does **not** trigger the preference, and it asserts the emitted sort
   `result : { v : int | true }`. Under SC3' the wildcard branch's head `(g n)` is a call to `g`,
   which is not in `SCC(h)`, so the preference does not apply, the join disagrees after resolution
   (`bool` against `int`), and the wildcard is retained. `RBP-2` must pass without an edit. If it
   needs an edit, SC3' is wrong, not the test.
6. **Seed the cross-module path.** Extend `loadModule`'s call so the pass sees the cached modules'
   `meRetTypes`. Add the module tests named in the test plan.
7. **Add the new tests.** See "Test plan".
8. **Run the gate.** Build, sweep with the post-change binary, and compare against step 2.
9. **Adjudicate every non-empty diff per channel, with its direction named.** A diff that is not
   attributable to a named channel blocks the change.

## Verification impact

- **Solver-time delta: zero on the predicted path.** The `.fq` files are predicted byte-identical for
  every contracted function in the corpus, so liquid-fixpoint receives the same input.
- **New obligations: zero in the corpus.** Channel 3 adds a `bytes-length` goal only when a wildcard
  resolves to `bytes[n]`. No corpus wildcard does. Outside the corpus the new obligation is one
  postcondition conjunct per resolved `bytes[n]` return.
- **Trust-model effect.** Channel 2 and channel 5 can demote a function from body-faithful to
  `erBodyFallback`, which floors its tier at `asserted`. Invariant I1 requires each such demotion to
  be enumerated with a channel and a witness. The four contract-free change candidates named in
  "Corpus measurement" are the enumerated set, and each has **no post**, so none of them carries
  `verified` evidence to lose. They sit in the census's `excluded_no_goal` bucket.
- **Verification fragment.** No new class. `int` and a bare wildcard both lower to `FQInt`. A resolved
  pair lowers to `FQDataApp "Pair2"` through `typeToSortA`, which is the acyclic datatype theory
  already in use. Nothing becomes nonlinear. Nothing escapes to Lean.
- **Strict-verified-core.** `--strict-verified-core` hard-errors when a function falls back. A
  channel-2 demotion on a file that CI runs with that flag would fail the build. None of the four
  candidates is in the `strict_pass` floor of `BASELINE.json`, which is the set the ratchet protects.
  This is a measured claim over the 98 recorded paths.
- **Evidence hash and the soundness stamp.** `downgradeStaleVerifiedSidecar` builds its hash from
  `normalizeDefStmt`, which yields the **raw** statement's `mRet`, and `Main`'s write side does the
  same. So the hash is blind to a resolved `tau_ret`, and it **cannot** identify the affected
  population. The rule that follows: if the sweep is verdict-identical, no stamp is needed. If any
  function that carries `verified` evidence moves, `checkerSoundnessVersion` must go from `"2"` to
  `"3"`, because nothing else invalidates the stale sidecar. Do not spend
  `codegen_semantics_version`; `INT-3` needs it.

## Performance budget

- **GHC recompilation.** `TypeCheck.hs` is imported by `Module.hs`, `Main.hs` and the test suites, so
  a change there rebuilds most of the downstream graph. Measured proxy: a `TypeCheck.hs`-only edit is
  the common case in this repository and it is not the slow one; `FixpointEmit.hs`, which this plan
  does not touch, is.
- **Compiler runtime.** The pass runs one extra `inferExpr` traversal per bare-wildcard body per
  round. The corpus needs 2 rounds and has 16 candidate bodies on the S-expression surface and 6 on
  the JSON surface. So the added work is about 44 body traversals across the whole corpus, against
  1396 definition heads already traversed once. The expected delta on `llmll check` is zero, because
  `check` uses the report-only wrapper, and on `llmll verify` it is below measurement noise.
- **Worst case.** `F` is monotone on a product of flat lattices, and each entry can only move from
  wildcard to concrete once, so the iteration is bounded by the number of bare-wildcard entries plus
  one confirming round. There is no exponential path. A component with no concrete anchor stays a
  wildcard and costs one round.
- **`.fq` size delta: zero on the predicted path.**
- **`ProofCache` and `VerifiedCache` hit rate: unchanged.** The evidence hash preimage does not move.
- **Gate cost.** One `fallback_census.py` run over the 250-file population takes about 3 to 11
  minutes with four workers, as `scripts/fallback_census.py` records for 2026-09-08 and 2026-09-09.
  The two-build gate therefore costs about 20 to 25 minutes of sweep time plus two builds.

## Contract plan

**This change lands nothing in the provable fragment.** `resolveRetTypes`, `sccOf` and
`preferConcreteInSCC` are Haskell compiler internals. They are not LLMLL functions, they carry no
`pre` and no `post`, and no LLMLL contract can be written for them. The deliverable for this section
is that sentence.

The property that stands in for a contract is stated as a test, not as a clause: **the type channel's
diagnostic set is identical before and after.** SC2' makes that true by construction, because the
report comes from `typeCheckWithCacheMode'`, which discards the map. `PASS-1` in the test plan asserts
it directly rather than relying on the construction.

## Test plan

**Baseline, recorded and not measured here: 1942 hspec examples and 218 pytest tests at v0.23.0.**
The implementer must re-measure both on the merge base before the patch and after it, and report the
delta. Do not carry the recorded figure into the ship note.

### New hspec tests, in `compiler/test/Spec.hs`

They belong in the existing `describe "FQ-RESULT-SORT-1: result binder sorts from the effective
return type"` block, beside `FQRS-1` to `FQRS-8` and `RBP-1` to `RBP-3`, and they reuse that block's
`emitRet` helper, which already runs typecheck and then the emitter with the map.

| Test | Asserts |
|---|---|
| `RR-1` | A contracted unannotated caller of an unannotated `bool`-returning callee sorts `result` at `bool`. Channel 1, shape `B` |
| `RR-2` | The same shape under `let` sorts identically. Shape `C` and `D_let` |
| `RR-3` | A call nested two `if` levels deep resolves. Shape `Q_nested` |
| `RR-4` | An unannotated `string`-returning callee sorts `result` at `Str` and does not crash. Shape `E_str`, the v0.14.72 conversion |
| `RR-5` | Two mutually recursive `def-shell`s with a literal anchor resolve. Shape `M_shellmut` |
| `RR-6` | The annotated control emits byte-identical `.fq` text to the unannotated form, for each of `RR-1` to `RR-5` |
| `SC1-1` | A named-hole return type is retained, not replaced. Sketch mode is preserved |
| `SC1-2` | A concrete `tau^0` is never revised, even when re-synthesis in the strengthened environment gives a different concrete type. `L_mono` is the fixture |
| `SC2-1` (`PASS-1`) | The `DiagnosticReport` from `typeCheck` is identical with and without the pass, over a fixture set that includes a forward reference, a hole body and a branch mismatch |
| `SC2-2` | `runSketch` reports the same hole set. The pass must not append to `tcHoles` |
| `SC3-1` | Inside one SCC, the concrete branch determines the group's return type |
| `SC3-2` | Across an SCC boundary the preference does not apply and the wildcard is retained. This is `RBP-2`'s shape asserted on the resolved map instead of on the emitted sort |
| `CYC-1` | An anchorless `def-shell` cycle stays a bare wildcard, lowers to `FQInt`, and reaches a verdict. Shape `S_anchorless` |
| `CH2-1` | A wildcard resolving to a non-sortable pair moves the function into `erBodyFallback` and names the cause. Channel 2, witness `X_rectree` |
| `CH3-1` | A wildcard resolving to `bytes[n]` adds `bytes-length` to the emitted rhs, and the ContractEnv entry for the same function does **not** gain it. This pins the channel-3 asymmetry |
| `CH4B-1` | A caller of a `bytes[n]`-returning wildcard callee whose post applies a bytes op now assumes that post, and the callee's own body VC carries the matching goal. Channel 4b, and I2's antecedent |
| `CH4C-1` | Guard for `ARR-RANGE-NAME`: a wildcard resolving to `bytes[n]` puts `result` into the `injectRangeFacts` population, and the emitted LHS names the fact. Asserts the fact is present, not that it is absent |
| `CH5-1` | A wildcard resolving to a bytes type makes `wholeArrEqClause` fire and routes the contract to fallback with cause `guard:whole-structure-eq` |
| `RES-1` | Guard for `R_result`: a wildcard resolving to a `Result` sorts the definition-site `result` binder through `typeToSortA`'s `TResult` arm, while `calleeRetSort` still reaches `typeToSort`'s `FQInt` default. The asymmetry is asserted, so a later fix has a pin |
| `KLEENE-1` | The iteration terminates on a three-function chain and reports the same map from two different statement orders. Determinism |

Count: 20 new examples, target 1962 or more. Any example the implementer adds beyond this list raises
the target.

### New module tests, in `compiler/test/ModuleSpec.hs`

| Test | Asserts |
|---|---|
| `RRX-1` | An imported unannotated non-int callee resolves through `meRetTypes` and the importing module's call binder sorts correctly. Shape `xmod-B` |
| `RRX-2` | The seed is required, not optional: with an empty `meRetTypes` the same fixture keeps today's behaviour |
| `RRX-3` | `meExports` is unchanged by the pass, so an importing module's checker is not made stronger. This is `buildModuleEnv`'s stated invariant |

Count: 3 new examples.

### Python tests, in `scripts/tests/`

The pytest suite pins compiler behaviour through the real binary, so it grades this change. Two
additions:

- `scripts/tests/test_fallback_census.py`: add a cell that asserts the strict-pass set does not
  shrink for the two files that carry contracted wildcards resolving to `int`,
  `examples/banking_ledger/banking.llmll` and `examples/withdraw-demo/compose.llmll`. Both are in
  `BASELINE.json` today.
- A new cell asserting that `llmll verify` on `examples/life_sexp/world.llmll` reports the same
  `body-fallback` function list before and after. This is the channel-2 pin that the `.fq` bytes
  cannot carry.

Count: 2 new pytest cells, target 220 or more.

### Existing artifacts that grade this change, and must be re-run

Every one of these is a grading artifact. A plan that names only the compiler edit under-counts the
work by a factor of five.

| Artifact | Where it runs | What it grades |
|---|---|---|
| `compiler/test/Spec.hs`, block `FQ-RESULT-SORT-1` | `stack test`, CI job `C5` | `FQRS-1` to `FQRS-8`, `EMITDIAG-1`, `RBP-1` to `RBP-3`. `RBP-2` and `FQRS-8` are the two pins most exposed |
| `compiler/test/ModuleSpec.hs` | `stack test`, CI job `C5` | the `meRetTypes` and `seedImportedContracts` path |
| `python -m pytest scripts/tests/` | CI job `C1-C4` | 218 tests, the suite CI actually runs |
| `scripts/tests/test_fallback_census.py` | CI job `C5`, with `LLMLL_BIN` | the real compiler over the 250-file population |
| `scripts/fallback-census/BASELINE.json` | the ratchet inside that gate | the 98-file strict-pass floor; a demotion that drops a file needs a waiver naming the cause |
| refute-crux verdict gate, `scripts/refute_crux_cover.py` and `tools/refute-crux/` | CI job `C5` | 80 live cases over 11 example suites, including `examples/banking_ledger`, which holds 7 of the 12 resolving wildcards |
| `scripts/build_smoke.sh`, BUILD-GATE-1 | CI job `C5` | end-to-end build over `scripts/build-smoke` |
| `examples/*/EXPECTED_VERDICTS.json` (13 files) | the example gates | per-function expected verdicts, including `examples/banking_ledger/` |
| `docs/design/` doc-claim and norm-claim gates | CI job `C5` | any citation this change makes stale |

`scripts/check-examples.sh` exists but **is not wired into CI**; a search of `.github/workflows/`
returns no reference to it. Run it by hand, and do not count it as a gate.

## Byte-identity verification procedure

The gate has two halves. The first is deterministic and needs no solver. The second needs the
toolchain.

**Preparation.**

1. On a clean `main`, run `stack build`, then **copy the produced binary aside** as `llmll.pre`
   before doing anything else. A later `stack build` overwrites the install root, and the negative
   half of the gate then has nothing to run against.
2. Do not use `git stash` around a build in `compiler/`. `hpack` rewrites `llmll.cabal` and the pop
   conflicts. Use a second worktree or a copied tree.
3. Export the local install root onto `PATH` and confirm the version, because a stale binary reads as
   "the patch did not work":
   `export PATH="$(cd compiler && stack path --local-install-root)/bin:$PATH"` then `llmll version`.
   Confirm the binary's mtime is later than the last change to `compiler/src`.

**Half one, the `.fq` bytes.**

4. Enumerate the population the way `scripts/fallback_census.py` does, from `git ls-files` over
   `examples`, `tools`, `scripts/build-smoke` with suffixes `.llmll` and `.ast.json`, and add
   `compiler/test/fixtures`. 318 files.
5. Copy the tree to a scratch directory. `llmll verify` **writes a `.verified.json` sidecar beside the
   source**, so a sweep over the repository dirties tracked files.
6. For each file run `llmll verify FILE -o "$OUT/<slug>.fq"` and capture stdout and stderr to
   `"$OUT/<slug>.out"`. The `-o` flag exists; without it the file goes to `/tmp/<name>.fq` and
   collides across directories with the same basename.
7. Repeat with the post-change binary into a second output directory.
8. `diff -r fq-pre fq-post` must be empty. Any non-empty file is adjudicated against the five-channel
   table, with its direction named.

**Half two, the channels the bytes cannot carry.**

9. `diff -r out-pre out-post` over the captured stdout. This compares the verdict line, the
   `body-fallback:` list and every `W-BODY-FALLBACK` warning. This half is what catches a channel-2 or
   channel-5 demotion on a contract-free function, which half one is measurably blind to.
10. Run `python3 scripts/fallback_census.py --llmll <binary> --out <record> --no-ratchet` with each
    binary and diff the two records. The record is written with `sort_keys` and carries no durations,
    so it is byte-stable by design. Compare `ratio`, `causes`, `constructs`, `outcomes`,
    `strict_pass` and the per-file `body_faithful` counts.
11. Run `llmll verify --trust-report --json` on the 13 directories that carry an
    `EXPECTED_VERDICTS.json` and diff the tiers.

**Acceptance.** Half one empty, half two empty except for entries that appear in the enumerated
demotion set of "Verification impact". A verdict move on a function that carries `verified` evidence
requires the `checkerSoundnessVersion` change described above, and it also requires re-reading
invariant I1 with the language-team before the change ships.

## Rollback

- **A single revert is plausible.** The change is confined to `TypeCheck.hs` plus one seed argument in
  `Module.hs`. No schema field moves, no CLI flag is added, no on-disk format changes.
- **A flag is not needed and should not be added.** The freeze-era habit of gating a verifier change
  behind a flag would double the gate surface, because both settings would need a sweep. The pass is
  either correct at the seam or it is reverted.
- **No migration concern for `.verified.json`.** The evidence-hash preimage reads the raw statement's
  `mRet`, so no sidecar goes stale and no revalidation is forced. This holds only while the sweep is
  verdict-identical; see the conditional stamp rule.
- **No migration concern for `.fq` files.** None is tracked and none is cached in a user environment;
  each run writes a fresh file.
- **Worst-case unwind cost.** One revert commit plus one rebuild. If the change has already shipped
  and a demotion is found later, the unwind also needs the `documentation-lead` to move the roadmap
  row back, which is the same cost the `RET-BRANCH-PREF` Stage 2 withdrawal paid.

## Risks and unknowns

1. **The syntactic census is not `inferExpr`.** Classification. The reader in "Corpus measurement"
   models `collectTopLevel`, the `EIf` join and `preferConcreteOnSelfCall`, but it approximates
   builtin return types and does not expand aliases. **Effect: complicates the plan.** The prediction must be
   confirmed by the sweep in step 2 before any code is written, which is why step 2 precedes step 3.
2. **Four contract-free change candidates are invisible to the `.fq` gate.** Verification.
   `examples/life_sexp/world.llmll :: evolve`, `examples/life_json/world.ast.json :: evolve`,
   `examples/hangman_json_verifier/hangman.ast.json :: game-won?` and
   `examples/hangman_json/hangman.ast.json :: game-won?`. Measured: `world.llmll` emits a 32-line
   `.fq` with no constraint. **Effect: complicates the plan.** Half two of the procedure closes it.
3. **The JSON-AST surface carries 139 unannotated heads and was never censused.** Scope. The Rev 2
   census read S-expression syntax only. Six of those heads are bare wildcards and one resolves to
   `bool`, which does not lower to `FQInt`. **Effect: complicates the plan.** Step 1 closes it.
4. **`ARR-RANGE-NAME` is an open false-fact channel that `tau_ret` can feed.** Verification.
   `bytesRootedArr` decides a ground fact on a generated variable-name suffix, and it is default-true.
   Reaching population measured empty in the corpus. **Effect: matters only at scale**, that is, the
   first time a program's unannotated return resolves to `bytes[n]`. `CH4C-1` is the guard.
5. **The channel-3 asymmetry can surprise a reader.** DX. A resolved return adds a definition-site
   obligation and exports no caller guarantee, because `aug` runs before `effRet` in the ContractEnv
   builder. A function can therefore start failing its own post while its callers see no change.
   **Effect: complicates the plan.** `CH3-1` pins it and the Rev 3 table records it.
6. **`emitSynthetic` reads the resolved map.** Scope. `--cdp` and `--weakness-check` build a synthetic
   candidate program and typecheck it. A resolved `tau_ret` changes the candidate's emitted
   constraints, so CDP verdicts are in the gate's scope. **Effect: complicates the plan.** The `--trust-report
   --json --cdp` comparison in step 11 covers it.
7. **`RBP-2` is the tightest pin and it is close to the new rule.** Build. It asserts the emitted sort
   for exactly the shape SC3' governs. **Effect: blocks step 5** if SC3' is implemented as an
   unconditional widening of `preferConcreteOnSelfCall`. The plan keeps the shipped function untouched
   for this reason.
8. **The recorded test baseline is not a measured one.** Scope. 1942 hspec and 218 pytest come from
   the roadmap's v0.23.0 row, not from a run on the merge base. **Effect: complicates the plan.** Measure both
   before the patch.
9. **The gate costs about 20 to 25 minutes of sweep time plus two builds.** Performance. One census
   run reached 10 minutes 41 seconds on 2026-09-08. **Effect: matters only at scale**, that is, if the
   sweep has to be repeated for each adjudication round.

## Open questions for the professor

None. Every candidate question failed the negative test: each was answered by reading
`compiler/src/LLMLL/`, by `git ls-files`, or by one measurement.

- Whether channel 4's soundness precondition is still `WILD-ASSUME`: answered by reading
  `TypeAdmissibility.admits`, the `CallVC` arm's post guard and `bytesLenRetPost`. It is FACT-AG-LEN.
- Whether `ARR-RANGE-NAME` blocks this row: answered by the census. The reaching population is empty.
- Whether byte-identity is a complete gate: answered by one `llmll verify` run. It is not.
- Whether `checkerSoundnessVersion` must change: answered by reading the hash preimage. It is
  conditional on the sweep, and the condition is stated in "Verification impact".
