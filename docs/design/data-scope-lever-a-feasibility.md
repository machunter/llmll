# Lever A Arrays — Compiler-Engineer Feasibility Read (A0/A1)

> **Status:** Rev 0 — feasibility read of [`data-scope-lever-a-arrays-proposal.md`](data-scope-lever-a-arrays-proposal.md) (Rev 1), probe-backed.
> **Author:** compiler-engineer · 2026-07-11. Probe artifacts: session scratchpad `lever-a-probe/` (p1–p9), reproducible per §2.
> **Verdicts:** **A0 GO · A1 GO · A2 GO-WITH-CHANGES** (one encoding amendment, §4, routed to language-team). A3/A4 unblocked by anything found here.

## 1. Restatement

Empirical feasibility of stages A0 (verification-inert surface) and A1 (bytes discharge) of the Rev 1 arrays design: does the pinned solver stack (`fixpoint` + `z3`, invoked as `fixpoint -q --json <file.fq>` — `app/Main.hs:1354`) accept the array theory in textual `.fq`, with both verdicts per the §6.1 exact-reflection rule; plus the Risk-5 `typeToSort` question answered from the code, a touch list with effort, and a test-plan sketch.

## 2. Probe results (the decision input)

Method: hand-authored minimal `.fq` files in the emitted dialect (reference: a real `llmll verify` emission; probe precedent `FixpointIR.hs:196`, `Lst` "probe-verified accepted bare"), run through the same binary and flags the verify pipeline shells out to. Reproduce the decisive probe:

```
printf 'bind 0 m : { v : (Map_t int int) | true }\nbind 1 k : { v : int | true }\nbind 2 x : { v : int | true }\n\nconstraint:\n  env [0; 1; 2]\n  lhs { v : int | v = (Map_select (Map_store m k x) k) }\n  rhs { v : int | v = x }\n  id 0\n  tag []\n' > /tmp/p1.fq && fixpoint -q --json /tmp/p1.fq
```

| # | Probe | Result | What it establishes |
|---|---|---|---|
| p1 | get-after-write, `(Map_t int int)`, `Map_select`/`Map_store` | **Safe** | the map theory is **native** in the pinned fixpoint's `.fq` surface — sort `(Map_t int int)` parses, the operation symbols are interpreted, **no `constant` declarations needed** |
| p2 | p1 with wrong expected value (`v = x + 1`) | **Unsafe** | refutation fidelity — the theory refutes, satisfying §6.1's both-verdicts requirement |
| p3 | `select` mixed with LIA bounds (`0 ≤ i < 64`, byte-range conjuncts) | **Safe** | the QF_AUFLIA combination works in one constraint |
| p4 | const array `(Map_default 0)`, select at symbolic key = 0 | **Safe** | **const arrays land** → `bytes-zero`/`map-empty` reflect; §7 row 5's failed-probe branch is not taken |
| p5 | two-array encoding with `m_has : (Map_t int bool)` | **Crash** | `smt_map_sto` is declared **monomorphically at `(Array Int Int) Int Int`** in the SMT preamble; a `bool`-element instantiation is an unknown constant to z3 |
| p5b | two-array encoding, presence as **int 0/1** (`Map_t int int` twice) | **Safe** | the amended encoding proves presence + get-after-put end-to-end in one constraint |
| p5c | a single `(Map_t int bool)` binder, nothing else | **Crash** | bool-element arrays are unusable regardless of coexistence — the wall is the element sort, not mixing |
| p6 | aliased symbolic keys (`store` at `k1`, `select` at `k2`, no relation) | **Unsafe** | read-over-write else-branch counterexample — the §11 third crux behaves |
| p7 | the `read-at` off-by-one crux shape (`i ≤ 64` pre vs `i < 64` obligation) | **Unsafe** | the A1 acceptance refutation discharges |
| p8 | array binder + `data Outcome` ADT constructor in one file | **Safe** | arrays coexist with the shipped `FQData` datatype emission — combination-in-practice |
| p9 | `(Map_t int Str)`, get-after-write over string values | **Safe** | **string map values work** as specced (§3 admits values in {int, bool, string}) |

Summary: every capability A0/A1 need is green, both verdicts included. The single red is the `bool` **element** sort (p5/p5c), which hits exactly the proposal's literal `m$has : FQArr σₖ FQBool` lowering — amendment in §4.

## 3. Verdicts

**A0 — GO.** No solver dependence at all (verification-inert by design). The work is `builtinEnv` + typechecker key-sort gate + codegen/runtime; all mechanisms exist (builtin contracts registered like contracted callees per proposal §3; the runtime-assertion channel is the standing §5.3.4 backstop). Nothing to probe; nothing found blocking.

**A1 — GO.** `bytes[n]` lowers to `Map_t int int` (p1–p4, p6–p8 all int-element): reflection, ground length/byte-range facts, const arrays, LIA mixing, refutation, and ADT coexistence all probe green. `emitSort (FQArr FQInt FQInt) → "(Map_t int int)"` is a one-line rendering; sanitization is a non-issue (`sanitizeFQId` maps `$` → `_`, the existing `$ok`/`$err` splitting already rides this — `FixpointIR.hs:219`, `FixpointEmit.hs:738–739`).

**A2 — GO-WITH-CHANGES.** The two-array encoding survives with one amendment (§4). The §5.1 pair-threading remains the principal mass as the proposal says; nothing probed contradicts its feasibility (p5b is the target shape working).

## 4. Design amendment routed to language-team (Rev 1 divergence)

**Bool-element arrays are not emittable on the pinned stack.** The proposal's §5 lowering `m$has : FQArr σₖ FQBool` crashes the fixpoint→SMT bridge (p5c): the preamble declares `smt_map_sto` once, monomorphically int-element; there is no polymorphic or multi-instance declaration on this pinned binary. Amendment, semantics-preserving:

- `m$has` lowers to `FQArr FQInt FQInt` with the **0/1 discipline**: presence reflects as `select(m$has, k) = 1`, absence `= 0`; `map-put` stores `1`; `map-empty`'s has-array is `Map_default 0` (p4+p5b prove the whole path).
- `bool`-**valued** maps (`map[int,bool]`, admitted by §3's value sorts) take the same 0/1 encoding at the sort layer; surface semantics unchanged.
- `string`-valued maps need no change (p9).

Consequences: the F5 strong-politeness note (the `Arr σₖ Bool` leg being the reason politeness is needed) becomes moot **at the solver layer** — every emitted array is int- or Str-element; the metatheory citation can stay as stated since the surface theory is unchanged. The exact-reflection rule (§6.1) is satisfied: 0/1 ↔ bool is a bijection on the reflected atoms (`= 1` / `= 0` are exact), not an over-approximation. This is an emitter encoding detail one level below the design's "presence-plus-value" language — Rev 1's §5 should record it so the implementation doesn't silently diverge from the written design (the D-drift discipline).

## 5. Risk-5 answered empirically (`typeToSort` today)

`typeToSort` (`FixpointEmit.hs:1183–1195`) has cases for `TInt/TBool/TString/TList/TDependent/TPair` and then `typeToSort _ = FQInt -- conservative default`; `TBytes`/`TMap` (`Syntax.hs:131,133`) both hit the default. So today every bytes/map binder in a contract is an int-sorted term: two distinct maps compared with `=` in a contract already unify as integers (benign only because no operation reflects — exactly the proposal's Risk 5). When A1 flips operated-on binders to `FQArr`, any existing contract mentioning a bytes/map binder changes sort mid-corpus; the activation gate (§5, operated-on binders only) plus the A1 acceptance verdict inventory over `examples/` (review F7; the ENUM-EQ-FALLBACK sweep procedure from v0.14.32 is the template) is the right gate and is already in the proposal. Grep evidence for scale: the only bytes-typed binders in `examples/` sit in the crypto call chains (`totp_rfc6238`, secure-channel) with no element access and no `=`-over-bytes contracts — expected inventory delta: zero flips, to be confirmed by the sweep.

## 6. Touch list with effort (A0–A3)

| Stage | Files | Effort |
|---|---|---|
| A0 | `TypeCheck.hs` (`builtinEnv` + key-sort gate + op diagnostics), `CodegenHs.hs` (+ runtime shims; `Data.Map`/`ByteString` per §2), `Contracts.hs`-adjacent builtin-contract registration, `test/Spec.hs` | 2–3 days |
| A1 | `FixpointIR.hs` (`FQArr` ctor + `emitSort` line), `FixpointEmit.hs` (`typeToSort` `TBytes` case behind the activation gate; `exprToPred` reflection for the three bytes ops; two ground-fact families; gate plumbing), sweep script reuse | 3–4 days + the `examples/` verdict inventory |
| A2 | `FixpointEmit.hs` (`TMap` lowering with §4's 0/1 amendment; binder splitting reuse of `:738–739`; **pair-threading through `exprToPred`/`bodyToPredM` — the principal mass**; `ELet` array-RHS row), `test/Spec.hs` | 4–6 days |
| A3 | `ObligationMining.hs:171` (`isQfLia` central extension + exact-reflectability decision), `ObligationAssembly.hs`/`Checkout.hs` vocabulary, `CDP.hs`/`WeaknessCheck.hs` array-sorted candidates | ~2 days |

GHC fan-out is modest (FixpointIR/FixpointEmit/TypeCheck are already the hot recompilation set). Solver-time: probes solve in milliseconds; the activation gate keeps non-array functions byte-identical, so corpus-wide verify time is unchanged except on array-mentioning functions (measurement pattern: `experiments/cdp-perf-0/`).

## 7. Test-plan sketch

Suite conventions: emission-based tests + e2e verify tests per describe-block family (the ENUM-EQ-FALLBACK/OA precedent, v0.14.32). Baseline 1181 Haskell + 45 Python; every stage adds:

- **A0**: builtin typing (8 ops), key-sort gate diagnostics (edge case 5), runtime assertion firing, `.fq` byte-identity over the existing corpus (the no-op guarantee as a test, not a hope).
- **A1**: the §11 `read-at` crux pair (refuted at `i ≤ 64` / verified at `<`) as e2e; ground-fact emission unit tests; `emitSort` rendering; verdict-inventory sweep as a release-gate artifact (script, not a Spec test).
- **A2**: get-after-put + dropped-put twin + aliased-key crux (§11); the let-bound pipeline shape (§5.1); 0/1 presence discipline unit tests; `EIf`/call-site confirmations (§5.1 rows 3–4).
- **A3**: parser-faithful classifier tests (`EOp` and `EApp` forms — the CLASSIFY-EOP lesson); constructors-route-reflected (probe landed, so the §6.1 out-routing test flips to the reflected expectation); whole-structure-`=` routes out (edge case 9).

## 8. Residual risks

1. **Pinned-binary specificity.** The monomorphic `smt_map_sto` behavior is a property of the installed fixpoint (2009–15 vintage banner); a future fixpoint upgrade may lift it (or move the goalposts). The 0/1 amendment is forward-compatible either way; pin the behavior with an A2 regression test that would detect a changed bridge. Feasibility class; complicates nothing now.
2. **`Str`-element internals unaudited.** p9 proves Str-valued get-after-write; the bridge's internal Str lowering was not inspected. Exactness for the admitted reasoning (term-level equality, no literals) is what p9 exercises, and that is all §3 admits; A2 adds a pinned test. Verification class; low.
3. **CDP/weakness-check array-sorted skolems** (proposal Risk 4) — unprobed here, deferred to A3 scoping as the proposal already records.

**Hand-off:** amendment §4 to language-team for a Rev 1.1 line in proposal §5; everything else proceeds on the proposal as written. A0 can start immediately; A1's first commit should land the `FQArr`/`emitSort`/gate plumbing with the sweep, then reflection.
