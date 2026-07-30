# Codebase Concerns

**Analysis Date:** 2026-07-30

## Tech Debt

### WILD-ASSUME-2: map[k,bool] value-range fact asserted from declaration (open)

**Issue:** The `map[k,bool]` arm of the WILD-ASSUME restriction is deferred. A `map[k,bool]` binder carries a ground fact `0 ≤ select(m$val,k) ≤ 1` asserted from its declared value type (`injectRangeFacts` in `compiler/src/LLMLL/FixpointEmit.hs:4184`), which is a member of the same class as SAFE-ARG: a fact no obligation discharges, believed from a declaration the type channel need not validate. Measured as a member but with no reaching-SAFE witness yet — both return and argument shapes crash on a sort mismatch before a verdict.

**Files:** 
- `compiler/src/LLMLL/FixpointEmit.hs:4184` (injectRangeFacts)
- `docs/design/finding-arg-position-false-safe.md` (edge case 8)

**Impact:** Stage 1 of WILD-ASSUME (bytes-only) shipped v0.14.73; Stage 2 blocks until `(map-empty)` over-breadth fixture is in place, because `map-empty : TFn [] (TMap (TVar "k") (TVar "v"))` relies on componentwise wildcard absorption.

**Fix approach:** Extend `assumesFact` in `TypeCheck.hs` to the map class after verifying the `(map-empty)` fixture does not break. Roadmap item WILD-ASSUME-2.

### RET-RESOLVE: Wildcard return type not resolved transitively (open)

**Issue:** An unannotated return type is registered as `TVar "?"` in `collectTopLevel` (`compiler/src/LLMLL/TypeCheck.hs:919-936`), and callers inherit it. When that wildcard reaches the verification channel, `sortA1` (`compiler/src/LLMLL/FixpointEmit.hs:2429-2441`) lowers it to `FQInt`. This closes nine measured crash shapes at the root instead of patching one shape at a time. Design settled (Rev 2) but queued behind WILD-ASSUME-2 to prevent turning crashes into false-SAFE verdicts.

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs:919-936` (collectTopLevel)
- `compiler/src/LLMLL/FixpointEmit.hs:2429-2441` (typeToSort)
- `docs/design/ret-resolve-proposal.md` (Rev 2)

**Impact:** Deferred because the `resultLenFact` assumption injection path (which this would enable) can turn a crash into `verified`, so it must not land before WILD-ASSUME is in place.

**Fix approach:** Kleene iteration over the recorded return-type map with three side conditions: wildcard-only refinement, sandboxed pass (acceptance unchanged by construction), SCC-conditioned if-join preference. Corpus census predicts byte-identical `.fq` across all 128 files.

### TODO(R5 stage 3): Relational-VC path stub in DivergenceCheck

**Issue:** Semantic equivalence is stubbed with `semanticEquivalenceStub _ _ = Nothing` and a comment `TODO(R5 stage 3): relational-VC path`.

**Files:** `compiler/src/LLMLL/DivergenceCheck.hs:385`

**Impact:** R5 (relational verification) stage 3 is incomplete. This is a research track item, not blocking shipped functionality.

**Fix approach:** Implement relational-VC path for stage 3 of R5 research track.

### TODO(sub-3-v2): SUB-3 experiment work deferred

**Issue:** The repair-loop repair evaluation scripts contain multiple stubs for `TODO(sub-3-v2)` indicating that sub-3 phase-2 work is hard-deferred.

**Files:**
- `experiments/repair-loop/scripts/evaluate_run.py:152` (main stub)
- `experiments/repair-loop/scripts/evaluate_run.py:186, 344, 353, 381, 389, 394` (subsidiary stubs)

**Impact:** Sub-3 phase-2 experiment work is not currently being pursued. The evaluation script acknowledges 5 stubs and 1 hard-defer affecting experiment staging and coverage metrics.

**Fix approach:** Requires explicit SUB-3-v2 work plan and roadmap commitment.

---

## Known Bugs (Fixed)

### SAFE-ARG (v0.14.34 through v0.14.72) — FIXED in v0.14.73

**Symptoms:** `llmll verify` reports `SAFE` and writes `.verified.json` for a program that reads past the end of a buffer. This is the first defect on the false-SAFE line that did NOT fail closed.

**Root Cause:** The type channel lets a `bytes[32]` value satisfy a `bytes[64]` parameter when it passes through one unannotated function (bare inference wildcard `TVar "?"` compatible with everything). The verifier then asserts `bytesLen(b) = 64` as a ground fact from the parameter's declared type and discharges the index-in-bounds obligation against that false premise.

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs:2122` (structuralUnify, live argument seam)
- `compiler/src/LLMLL/TypeCheck.hs:2185-2186` (compatibleWith)
- `compiler/src/LLMLL/FixpointEmit.hs:1598-1600` (bytesLenReft fact injection)
- `docs/design/finding-arg-position-false-safe.md` (comprehensive analysis)

**Affected Range:** v0.14.34 through v0.14.72 inclusive. The fact and the obligation were introduced together at commit `c4ad7b6` (LEVER-A1, 2026-07-11).

**Codegen Reality:** `bytes_get` is generated with a dynamic bounds check (`compiler/src/LLMLL/CodegenHs.hs:275`), so the generated program traps at runtime rather than reading out of bounds. The false claim is the verification obligation itself, not actual memory unsafety.

**Fix (v0.14.73):** WILD-ASSUME rule: a bare inference wildcard no longer satisfies a type that contributes a fact to a VC antecedent that no obligation discharges. Two seams fixed: `structuralUnify` (argument position, the live path) and `compatibleWith` (return and checkExpr). The discriminant is `TVar "?"` and its `freshenFnType` instances (`?$N`), not `isHoleVar` in general. `.verified.json` gains `checker_soundness_version` stamped unconditionally, so absence is a sound "written by older binary" signal.

**Residue:** The `map[k,bool]` arm deferred as WILD-ASSUME-2 pending `(map-empty)` fixture.

### FQ-RESULT-SORT-1 (v0.14.34 through v0.14.72) — FIXED in v0.14.72

**Symptoms:** `llmll verify` crashes with "The sort X is not numeric" or sort mismatch errors. Not bool-specific: strings crash with "The sort Str is not numeric"; pairs crash with "The sort (Pair2 …) is not numeric". Not literal-specific: a computed bool body crashes when the post eliminates the boolean (e.g., `(post (and result (> n 0)))`); surviving shape is `(= result e)` alone.

**Root Cause:** The type channel derives `result`'s sort from the synthesized body type (`TypeCheck.hs:992`), but the contract channel derives it from the optional `-> RetType` annotation, defaulting to `FQInt`. Where they disagree, the emitted `.fq` is ill-sorted and liquid-fixpoint crashes.

**Files:**
- `compiler/src/LLMLL/FixpointEmit.hs:1156` (retSort)
- `compiler/src/LLMLL/FixpointEmit.hs:1207, 1220-1221` (consumption)
- `docs/design/finding-fq-result-sort-default.md` (Rev 3)

**Workaround:** Annotate the return type.

**Fix (v0.14.72):** Two stages. Stage (a): The checker records `tau_ret = mRet |> tau_body` on `TCState`, and the contract channel consumes it via `effRet` at the `emitFnConstraints` boundary. This also makes `sigPairUnsafe` and `resultReturnUnsafe` stop failing open. Stage (b): `meRetTypes` on `ModuleEnv` carries it cross-module. A third stage (HOLE-RET, firing on wildcard `tau_ret`) was implemented and withdrawn: it demoted 12 corpus functions from `verified` to `asserted`, because a wildcard is idiomatic (104 unannotated def heads corpus-wide, 72 alongside another unannotated callee).

**Residue:** RET-BRANCH-PREF (v0.14.72) ships stage 1 only — prefers concrete branch over self-recursive call. Stage 2 (general preference) deferred pending corpus measurement.

### MATCH-NULLARY-1 (v0.14.34 through v0.14.66) — FIXED in v0.14.66

**Symptoms:** `llmll verify --strict-verified-core` reports `SAFE` for a function that does not satisfy its postcondition. Generated program's own assertion fires at runtime on the input the proof covered.

**Root Cause:** Bare nullary constructor in a match arm (e.g., `(A 1)` instead of `((A) 1)`) parses as a catch-all binder named `A`. The verifier reasons about that catch-all while codegen emits a real constructor pattern.

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs` (checkPatternExpanded, post-fix)
- `compiler/src/LLMLL/Parser.hs` (pattern parsing)
- `docs/design/finding-match-nullary-ctor-unsound.md`

**Severity:** Soundness defect (false SAFE under `--strict-verified-core`). Blast radius zero: 0 hits across 127 in-tree sources and 1526 committed ASTs.

**Fix (v0.14.66):** `TypeCheck.checkPatternExpanded` now hard-errors when a match-arm pattern is a bare `PVar` naming a constructor of the scrutinee's type (user sum types and `Result`), naming the correct form in the message.

### FQ-CTOR-COLLIDE-1 (v0.14.34 through v0.14.67) — FIXED in v0.14.67

**Symptoms:** `llmll verify` crashes with "Sort mismatch" or sort error when a parameter or let-binder is named like a lowercased ADT constructor (e.g., `denied` collides with `Denied` constructor lowercased).

**Root Cause:** The `.fq` emitter lowercases user ADT constructor names (e.g., `Denied` → `denied`), so a binder with the same name collides in the SMT namespace. liquid-fixpoint crashes with a sort error.

**Files:**
- `compiler/src/LLMLL/FixpointEmit.hs:539, 2729, 2837, 3056, 3621` (lowercasing sites)
- `compiler/src/LLMLL/FixpointEmit.hs:3614` (convention comment)
- `docs/design/finding-fq-ctor-name-collision.md`

**Severity:** Fail-closed crash (never a false SAFE). Usability trap for agent fill swarms: colliding names are exactly natural for protocol code (`denied`, `data`, `error`, `ack`). Error message points nowhere near the cause.

**Fix (v0.14.67):** User (uppercase-initial) constructors emit through a single new `FixpointIR.fqCtorSym` with a reserved `ctor_` prefix (`Denied` → `ctor_denied`, selectors `ctor_denied_0`); built-in lowercase symbols (`ok`, `err`, `pair2`) stay verbatim.

---

## Security Considerations

### unsafePerformIO in generated test harnesses

**Risk:** The generated test harnesses (`generated/event_log_test/src/Lib.hs`, `generated/cg/src/Lib.hs`, `generated/prog/src/Lib.hs`, and others) use `unsafePerformIO` to evaluate regex patterns in a pure context.

**Files:**
- `generated/event_log_test/src/Lib.hs:18` (import)
- `generated/event_log_test/src/Lib.hs:105-110` (usage with comment "PREAMBLE COMPROMISE (v0.7)")
- `generated/cg/src/Lib.hs` (same pattern)
- `generated/prog/src/Lib.hs` (same pattern)
- `generated/event_log_test_check/src/Lib.hs` (same pattern)

**Current Mitigation:** These are test/generated harnesses only, not shipped code. The compromise is documented as a v0.7 preamble design decision. Real regex evaluation is wrapped to isolate side effects.

**Recommendations:** 
1. Document why the preamble needed this compromise (likely pattern evaluation context inference).
2. Consider a pure pattern evaluation path for a future runtime if these harnesses become part of shipped tooling.
3. No action required for internal test use.

---

## Performance Bottlenecks

### CDP (Compositional Dependent Precondition) verification time multiplier

**Problem:** `--cdp` / `--weakness-check` / `--spec-coverage` runs roughly 2–3× verify time on modules with candidates.

**Files:** `experiments/cdp-perf-0/` (benchmark)

**Current Capacity:** Characterized and measured; impact known.

**Scaling Path:** The feature was considered for default enablement (`--strict-verify`) but deferred on cost/UX grounds (unprompted diagnostic surface on every `verify`). The `--cdp` opt-in is preferred. Revisit if concrete production need emerges.

### Liquid-fixpoint path count fallback (>4096 paths)

**Problem:** When verification paths exceed ~4096, the emitter falls back to a broader constraint, generating warning `W-DECREASES-UNUSED` or `W-DECREASES-LEX`.

**Files:** `compiler/src/LLMLL/FixpointEmit.hs` (fallback logic)

**Impact:** Warnings are non-blocking but indicate that decreasing measure uniqueness may not be guaranteed.

**Current Mitigation:** Emitter diagnostics reach `--json` (fixed v0.14.72).

---

## Fragile Areas

### Type channel vs. verification channel divergence

**Why Fragile:** The type channel (`TypeCheck.hs`) and contract/verification channel (`FixpointEmit.hs`) maintain parallel derivations of types and sort information. Divergence between them has caused multiple crashes (FQ-RESULT-SORT-1, and before RET-RESOLVE ships, others).

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs` (inference, type checking)
- `compiler/src/LLMLL/FixpointEmit.hs` (sort derivation, fact injection)
- `compiler/src/LLMLL/VerifiedCache.hs` (sidecar validation)

**Safe Modification:** Any change to type inference must be checked against the verification channel's use of that type. Measurement gates (corpus `.fq` byte-identity, typecheck-acceptance diffs) are in place on shipped features.

**Test Coverage Gaps:** WILD-ASSUME, FQ-RESULT-SORT-1, and RET-BRANCH-PREF each required extensive measurement against the corpus to catch divergence. Pre-commit gates are strong; post-commit traps (like FQ-CTOR-COLLIDE-1) indicate gaps in manual code review.

### Wildcard type handling across call sites

**Why Fragile:** Unannotated return types register as `TVar "?"`, then `freshenFnType` alpha-renames them per call site as `TVar "?$0"`, `TVar "?$1"`, etc. The actual encoding (`?$` prefix) was only discoverable by testing, not by reading code (`TypeCheck.hs:2117`). Earlier implementations specified exact equality with `TVar "?"` which made guards completely dead.

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs:919-936` (collectTopLevel, registers `?`)
- `compiler/src/LLMLL/TypeCheck.hs:1935-1960` (freshenFnType, alpha-renames to `?$N`)
- `compiler/src/LLMLL/TypeCheck.hs:2117` (naming at call site)
- `docs/design/finding-arg-position-false-safe.md` (Rev 2 corrects the discriminant)

**Safe Modification:** Any guard on `TVar` values must account for both bare `?` and `?$N` forms. Name predicates (`n == "?" || "?$" isPrefixOf n`) are more robust than pattern matching.

**Test Coverage Gap:** The naming strategy is not tested in isolation; it emerged from probe failures.

### Sidecar invalidation and version stamping

**Why Fragile:** The INT-1 field-absence trigger over-invalidated because the writer legitimately omitted `overflow_tainted` on every verified entry. SAFE-ARG (v0.14.73) introduces `checker_soundness_version` to avoid this pitfall, stamped unconditionally so absence is a sound signal.

**Files:**
- `compiler/src/LLMLL/VerifiedCache.hs:283-284, 287-308` (sidecarNeedsRevalidation)
- `compiler/src/LLMLL/VerifiedCache.hs:227-232` (historical INT-1 over-invalidation)
- `compiler/src/LLMLL/ProofArtifact.hs:214-215` (codegenSemanticsVersion, different axis)
- `compiler/src/LLMLL/Main.hs:2668` (emission)

**Safe Modification:** Every sidecar field that signals a compiler version boundary must be stamped unconditionally, not conditionally on a detection criterion. The stamp is the signal.

**Test Coverage Gap:** INT-1 over-invalidation was discovered in production; measurement gates on sidecar handling should be routine CI.

---

## Scaling Limits

### Corpus size and test cycle time

**Current Capacity:** 1439 Haskell examples in the corpus; v0.14.73 shows "1439 Haskell examples, 0 failures" + "107 Python". Gate cycle time is not published.

**Scaling Path:** 
1. Parallelize example runs where feasible.
2. Separate fast gates (syntax, type-check) from slow gates (verification).
3. Consider sampling strategies for regression suites on every commit.

### Data scope extension limits

**Current Capacity:** Lever A shipped (v0.14.33–51) covers `bytes[n]` and `map[k,v]` with `{int,string}` keys and `{int,bool,string}` values.

**Limit:** Lists and recursive data are deliberately deferred. The verification boundary (`Σ_auto`) is intentionally restricted to non-recursive types to keep the encoding decidable.

**Scaling Path:** 
1. Extend to recursive data structures via explicit measure annotations (not automatic).
2. Or move verification of recursive structures to Lean tier (LEAN-GA, external blocker).
3. Or introduce limited recursion (e.g., tail calls only) with automatic measure inference.

---

## Scaling Barriers

### Module system codegen enforcement (MOD-2 through MOD-5)

**Barrier:** The module system is compile-time correct, but codegen-level enforcement (export hiding, qualified imports, interface checks) is absent.

**Files:**
- `compiler/src/LLMLL/Module.hs` (loading, type checking)
- `compiler/src/LLMLL/CodegenHs.hs` (single concatenated output)

**Current State:** 
- MOD-2: Per-module Haskell file emission (prerequisite for all others) — not started
- MOD-3: Qualified access at codegen (depends on MOD-2) — not started
- MOD-4: `loadFromFile` strict typecheck migration — not started
- MOD-5: `checkInterfaceMismatch` wiring (also motivated by XMOD-AG cross-module assume-guarantee) — not started

**Trigger:** A production use case requiring true namespace isolation.

### WASM sandboxing (future, not in current roadmap)

**Current State:** Docker + CAP-1 provide two enforcement layers (compile-time capability gating + container isolation). WASM adds a hardware-enforced third layer.

**Files:** `docs/archive/wasm-investigations/wasm-poc-report.md` (PoC feasibility confirmed)

**Trigger:** Real users running untrusted agent code outside development environments.

---

## Missing Critical Features

### Relational verification (R5 stage 3)

**Feature Gap:** Semantic equivalence checking is stubbed. R5 research track is pursuing relational VCs (compare two implementations for equivalence).

**Blocks:** Differential verification features (compare old vs. new implementation).

**Status:** Research track, not blocking shipped functionality. Stage 1 and 2 are in progress; stage 3 (relational-VC path) is noted with `TODO(R5 stage 3)` in `DivergenceCheck.hs:385`.

### Leanstral integration (LEAN-GA)

**Feature Gap:** Verified-Lean evidence tier exists but is experimental; production three-layer rebuild (faithful translation, full nonlinear/inductive routing, retry-with-error loop) is not complete.

**Blocks:** Moving nonlinear obligations outside QF-BV scope to Lean 4 + Mathlib for real (not mock) verification.

**Status:** Externally blocked on Leanstral 1.5+ availability. Demo slice shipped v0.14.8 (examples/leanstral-demo/). Production rebuild deferred.

**Files:** `docs/design/leanstral-integration-scope.md`

---

## Test Coverage Gaps

### Sidecar handling under version drift

**Untested Area:** Specific revalidation scenarios when binaries drift versions. INT-1 over-invalidation and SAFE-ARG invalidation are known cases, but systematic handling is not regression-tested.

**Files:**
- `compiler/src/LLMLL/VerifiedCache.hs`
- `compiler/test/fixtures/` (no sidecar-version scenarios visible)

**Risk:** Silent acceptance of stale sidecars from future version transitions.

**Priority:** Medium — sidecar handling is versioning-critical; a test harness (e.g., "build with vN, verify with vN+1, expect revalidation") should be routine.

### Type channel divergence regression

**Untested Area:** Systematic regression suite for type/sort divergence. FQ-RESULT-SORT-1 and SAFE-ARG were discovered through review and measurement, not automated gates.

**Files:**
- `compiler/test/fixtures/fq-result-sort/` (post-fix, 9 examples)
- `compiler/test/fixtures/safe-arg/` (post-fix, SA-1..7, SS-1..4)
- No pre-commit gate on divergence

**Risk:** Future changes to type inference or sort derivation may silently diverge without catching it.

**Priority:** High — a suite comparing `--json` type output against verification channel assumptions should be automatic.

### Wildcard encoding stability

**Untested Area:** The `?$N` encoding from `freshenFnType` is not explicitly tested in isolation. Tests for WILD-ASSUME use full programs, not isolated type-inference probes.

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs:1935-1960` (freshenFnType)
- `compiler/test/fixtures/wild-assume/` (end-to-end only)

**Risk:** Changes to name generation (e.g., counter format) could break the discriminant in WILD-ASSUME without catching it.

**Priority:** Low (low mutation risk) but worth documenting.

### Cross-module assume-guarantee (XMOD-AG)

**Untested Area:** Full coverage of cross-module obligation flow (`consumed_guarantees` propagation) under inheritance scenarios. XMOD-AG shipped v0.14.17–20 but test coverage leans toward the happy path.

**Files:**
- `compiler/src/LLMLL/Module.hs` (loading, guarantee threading)
- `compiler/src/LLMLL/FixpointEmit.hs` (emitImportedGuarantees)
- `compiler/test/fixtures/xmod-ag/` (exists, but breadth unknown)

**Risk:** Subtle obligation-transmission bugs in deep import chains or circular scenarios.

**Priority:** Medium — currently a shipped feature with known complexity.

---

## Dependencies at Risk

### Liquid-fixpoint version mismatch

**Risk:** Compiler output schema (`.fq` format) can diverge from liquid-fixpoint input expectations. SAFE-ARG introduced `checker_soundness_version` to signal schema changes, but future divergence on any axis requires careful coordination.

**Impact:** Mismatched versions produce cryptic solver crashes ("Sort mismatch at argument #1", "The sort S is not numeric").

**Current Mitigation:** 
1. `compiler/package.yaml` pins liquid-fixpoint version.
2. Corpus `.fq` byte-identity gates catch silent divergence.
3. `LLMLL.md` §5.3 specifies the emitted theory.

**Recommendations:** 
1. CI gate on `.fq` format version compatibility (not just byte-identity).
2. Maintain a compatibility matrix if supporting multiple liquid-fixpoint versions.

### GHC / Haskell toolchain

**Risk:** The compiler is written in Haskell; compiler and generated code both depend on GHC. `ghc-wasm-meta` toolchain (for WASM target) has low bus-factor maintenance.

**Files:** `compiler/package.yaml` (GHC version pin), `scripts/setup-env.sh` (toolchain setup)

**Scaling Limit:** WASM build target (Phase 0–3) deferred on GHC-WASM availability; if `ghc-wasm-meta` falls behind GHC releases, work slips.

---

## Known Residue (Shipped, Incomplete)

### Stage G2 artifact audit shipped unrun (v0.14.71)

**What Happens:** The artifact audit stage (`scripts/doc_path_lint.py`) was implemented and integrated into the RFC-SWARM playbook at stage G2, but "has never seen a live run" as noted in v0.14.71 CHANGELOG.

**Why It Matters:** Stage G2 is meant to catch citation misresolutions before the slower feasibility probes (stage H) run. If it never runs in production, citations that fail to resolve still waste 45 minutes of probe time.

**Files:**
- `scripts/doc_path_lint.py` (linting logic)
- `docs/RFC-SWARM_PLAYBOOK.md` (stage G2 definition)
- `CHANGELOG.md` v0.14.71 (admission: "Not established: it has never seen a live run")

**Recommendation:** Gate the stage into the next RFC-SWARM run to validate the implementation against real data.

### map-empty over-breadth fixture not yet in place (prerequisite for WILD-ASSUME-2)

**What Happens:** The `(map-empty)` builtin returns `TFn [] (TMap (TVar "k") (TVar "v"))`, and the WILD-ASSUME guard must be loose enough to allow componentwise wildcard absorption during unification, else every `(map-empty)` at a typed position breaks.

**Why It Matters:** WILD-ASSUME-2 cannot ship without this fixture in place, or it will cause mass acceptance breakage.

**Files:**
- `compiler/src/LLMLL/TypeCheck.hs` (builtinEnv:168)
- `docs/design/finding-arg-position-false-safe.md` (edge case 8, fixture named SA-6)
- `docs/compiler-team-roadmap.md` (WILD-ASSUME-2 entry, prerequisite noted)

**Recommendation:** Commit the `(map-empty)` fixture before WILD-ASSUME-2 implementation begins.

---

*Concerns audit: 2026-07-30*
