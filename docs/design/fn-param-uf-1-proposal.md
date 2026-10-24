---
title: FN-PARAM-UF-1 — a call through a function-typed parameter is an opaque call, as a call to an uncontracted named function is
status: Rev 0, SETTLED 2026-10-24. The user asked for this decision before GENERICS-1 (generics-proposal.md decision 3). The answer is yes, with the encoding the compiler already uses for an uncontracted named callee (a fresh result binder per call site, not an uninterpreted function symbol). The homework found a soundness defect in name resolution that must ship first (FN-SHADOW-1, new).
rows: FN-PARAM-UF-1 (G1, DECIDE to PLAN); FN-SHADOW-1 (new, G1, PLAN, soundness); PBT-FN-PARAM-1 (G1, PLAN, unchanged, lands in the same release); CALL-CONGRUENCE-1 (new, Trigger-gated Parking Lot)
review: none
date: 2026-10-24
author: language-team
consumers: [compiler-engineer, documentation-lead, user]
related: "generics-proposal.md (Rev 1, decision 3 and the key idiom); shell-call-pre-1-proposal.md (the call-pre unchecked report); roadmap rows FFI-UNINTERP-1, LIST-LEN-AXIOM-1, FALLBACK-ATTRIB-1, MINMAX-FRAG-1"
---

# FN-PARAM-UF-1: calls through a function-typed parameter

## Decision

1. **Yes.** In a body VC, a call `(p e₁ … eₙ)` where `p` is a function-typed parameter of the function being verified is translated as a call to an uncontracted named function with the signature of `p`. The call gets a fresh result binder with no assumption on it. No pre obligation is emitted for it.
2. **The encoding is a fresh binder per call site, not an uninterpreted function symbol.** This is what the compiler does today for an uncontracted named callee. Two calls with equal arguments get two unrelated binders. Congruence is not adopted (see "Congruence").
3. **A caller may pass a lambda in a function-typed argument position.** The argument is not translated, and the callee's contract cannot mention that parameter.
4. **Name resolution is fixed first (FN-SHADOW-1).** A parameter or local binder shadows a top-level function of the same name. Today the verifier, the PBT evaluator and the strict-core admission check resolve the name to the top-level function. That gives a false `SAFE` (witness S1).
5. **The `call-pre unchecked` report counts edges, not callers.** Without this change, decision 3 hides an unchecked pre (witness W9).
6. **`def` stays as it is.** A `def` that calls a function-typed parameter is still refused by `check`. Admission is a question for GENERICS-2.
7. **PBT-FN-PARAM-1 lands in the same release.** It does not block this row. It shares one evaluator clause with FN-SHADOW-1.

## Restatement

`(def-shell min2-by [le: (fn [int int] -> bool) a: int b: int] -> int (post (or (= result a) (= result b))) (if (le a b) a b))` falls back, and so does every caller that passes a lambda. The same body that calls a named uncontracted `int-le` is body-faithful and proved. The post does not depend on what `le` returns. The question is whether the verifier should treat the parameter call as it treats the named call, and whether that is sound.

The measurement set is the type-classes value probe of 2026-10-24 (P1 queue, P3 log analyser). The design-reference set is Liquid Haskell, F\* and Dafny. In each of those, a function-typed argument without a refinement is an opaque value, and a call through it yields an unconstrained result of the declared type. This proposal brings LLMLL to that baseline. It does not add refinements on function types, which Liquid Haskell has and LLMLL does not.

## Context located

1. **`compiler/src/LLMLL/FixpointEmit.hs`, `bodyToPredM`, the `EApp` clause guarded by ``fname `Map.member` cenv``.** A named callee in the contract environment becomes a `CallVC` with a fresh `_bv_call_<f>_N` binder. With no pre and no post, nothing constrains that binder. The `.fq` for `min2-named` holds `bind 12 _bv_call_int_le_1 : { v : bool | (v = _bv_call_int_le_1) }` and no function symbol.
2. **`buildContractEnvWith`.** Every `def`, `def-shell`, `letrec` and `def-invariant` enters the contract environment, contracted or not. A parameter never does.
3. **`aNormalizeBody` in `bodyToPredFromRS`.** It hoists a call out of an `if` condition only when the callee is a contract-environment key. `(le a b)` is not hoisted. `guardToPredM` has no case for it, so the `EIf` clause returns `Nothing`.
4. **`bodyRefusalLabels` and `constructLabel`.** After a refusal, the label is the outermost construct, here `if`. The label approximates the refusing term by design. FALLBACK-ATTRIB-1 tracks this.
5. **`translateCallArg` inside the same `EApp` clause.** A variable argument becomes `FQVar` whatever its sort. Any other argument goes through `bodyToPredM`, which has no `ELambda` clause. A lambda argument therefore makes the whole call fall back, labelled `app:min2-by`.
6. **`exprToPred`.** It has no case for an application of a parameter, so a contract clause that calls `le` is outside the fragment. `check` rejects `=` on function values. A function-typed parameter therefore never appears in a translated clause.
7. **`calleeRetSort` and `typeToSort`.** A call binder takes its sort from the callee's declared return type. Types without an exact sort (`Command`, `Promise`, function types) fall to `int`, and nothing constrains such a binder.
8. **`compiler/src/LLMLL/Contracts.hs`, `evalC` for `EApp`.** It looks up the program functions first and never looks at the environment. A call through a parameter that shadows a program function runs that function (witness S3). A non-shadowing parameter call does not reduce (PBT-FN-PARAM-1).
9. **`compiler/src/LLMLL/TrustReport.hs`, `uncheckedCallPres`.** It reports `(caller, callee)` edges only for callers that are not body-faithful. A body-faithful caller that passes a pre-carrying function as a value is never reported (witness W9).
10. **`compiler/src/LLMLL/CallGraph.hs`, `extractRefs`.** The termination graph already honours shadowing for value uses. `LLMLL.md` §4.4.4 states it, in the `termination_unverified` paragraph: a function used as a value is an edge "unless a binder in scope shadows its name". The VC emitter, the evaluator and the admission check do not follow that rule.
11. **`compiler/src/LLMLL/VerifiedCache.hs`, `checkerSoundnessVersion`.** It is `"3"`. It increases when a checker defect invalidates verdicts from older binaries.
12. **`compiler/src/LLMLL/ObligationAssembly.hs`.** It reads the body-fallback causes for the obligation report and lists candidate callees for the checkout brief. It needs no change. The `if` and `app:` causes disappear from its output when this lands.
13. **`docs/design/generics-proposal.md` Rev 1.** Decision 3 orders FN-PARAM-UF-1 before GENERICS-1. The second idiom calls `(key x)` through a parameter. Verification specializes each instance and then verifies the copy.
14. **Test suite, MINMAX-FRAG-1 block.** MMF-6 pins `compiler/test/fixtures/minmax-frag/shadow-param.llmll` as "falls back, never proves". This proposal changes it to body-faithful and refuted.

**Corpus.** Of 501 tracked `.llmll` files, one declares a function-typed parameter: the MMF-6 fixture. The test suite holds a few inline sources with such parameters (`twice`, `hof2`, `use-res`), and none of them has a post.

### Drift found

- **D1. `LLMLL.md` §5.3.5, row "`EApp` (uncontracted callee)", says body-faithful ❌, contract-only.** The code is body-faithful with an opaque result binder (`min2-named` proves). The spec should move.
- **D2. The roadmap row says "uninterpreted function application".** The code mints a fresh binder per call site. It does not emit an uninterpreted function. This record keeps the row name and corrects the wording.
- **D3. `LLMLL.md` §4.4.4 promises binder shadowing for the termination graph only.** The verifier, the evaluator and admission resolve a shadowed call head to the top-level function. This is FN-SHADOW-1.

## Design

There is no surface change and no schema change. The rules below are spec text for `LLMLL.md` §5.3.3 to §5.3.5.

### R1. Name resolution (FN-SHADOW-1, prerequisite)

In the body of a function, a call head `f` resolves to the innermost binder named `f`. The binders are a parameter, a `let`, a `match` payload, a lambda parameter and a `do` step. A top-level or opened function is used only when no binder of that name is in scope. This holds in three places:

- **Verifier:** `bodyToPredM` does not assume the contract of a top-level `f` at a call whose head is a binder. The ANF hoist set follows the same rule.
- **Evaluator:** `evalC` consults the environment before the program functions.
- **Admission:** the strict-core callee check does not admit a binder as a verified callee. The refusal names it as a parameter.

R1 is the rule Haskell codegen already follows. The built program calls the binder (witness S1).

### R2. A call through a function-typed parameter

Let `p : (fn [τ₁ … τₙ] -> σ)` be a parameter of the function `g` under verification. A call `(p e₁ … eₙ)` in `g`'s body is translated exactly as a call to a named callee with parameters `τ₁ … τₙ`, return type `σ`, and an empty contract:

```
Γ ⊢ eᵢ ⇝ tᵢ  (each argument is translated as a call argument today)
r fresh,  sort(r) = sortA(σ)
──────────────────────────────────────────────────────────────
Γ ⊢ (p e₁ … eₙ) ⇝ CallVC{ callee = p, pre = ⊤ (none), post = none, result = r }
```

- `sortA` is the alias-aware return sort a named callee gets (`typeToSortA`). An unfixed generic instance is already `int` by generics-proposal.md.
- The ANF hoist set includes `g`'s function-typed parameters, so a call in an `if` condition, an argument or a scrutinee is hoisted into a `let`.
- The refinement in `σ` or in `τᵢ` is not assumed and not obligated. `check` does not enforce it at the point where a function value is passed (witness W6).
- A payload-subtyping obligation is emitted for a sum-typed `τᵢ` with a refined payload, as it is for any callee. It is declaration-driven, so the parameter's declared type is enough.
- Only parameters are in scope of R2. A `let`-bound, `match`-bound or lambda-bound function value stays outside the fragment. Its call still falls back, and R1 still resolves its name.

### R3. A function-typed argument at a call to a named callee

At a call `(h … a …)` where `h`'s parameter `q` at that position has a function type, the argument `a` is not translated. The substitution has no entry for `q`. A variable, a named function and a lambda are all accepted.

This is safe because no translated clause of `h` mentions `q`. An application of `q` is outside `exprToPred`, and `=` on functions is a `check` error. If a later change makes such a clause translatable, the existing leftover discipline applies: a pre that mentions `q` makes the whole call fall back, and a post that mentions `q` is not assumed. The engineer adds `q` to the uncovered-name check, so that this holds by construction and not by accident.

### R4. Contracts do not change

A `pre` or `post` that applies a function-typed parameter stays outside the fragment. The contract-only fallback is unchanged (test MMF-C6 keeps passing).

### R5. The `call-pre unchecked` report counts edges

`uncheckedCallPres` reports a `(caller, callee)` pair for every edge to a pre-carrying callee that the caller's body VC does not prove. A body-faithful caller proves only its direct call sites. Its other edges are reported:

- a pre-carrying function passed as a value (witness W9, `via-value`, missed today);
- a call inside a lambda body (witness W9, `via-lambda`; reported today only because the caller falls back).

Without R5, R3 makes `via-lambda` body-faithful and its unchecked pre disappears from the output.

### R6. `def` admission does not change

A `def` that calls a function-typed parameter stays a `core-membership-violation`. After R1 the message says that the callee is a parameter, and the suggestion is `def-shell`. GENERICS v1 is `def-shell` only, so GENERICS-1 does not need more. Generic `def` (GENERICS-2) owns this question.

## Soundness argument

**Claim.** If the body VC built by R2 and R3 is valid, then every run of `g` that returns satisfies `g`'s post. This holds for every function value bound to `p`, and for every caller.

1. **R2 assumes nothing about `p`.** The binder `r` is universally quantified in the constraint, like a parameter. The VC is valid only if the post holds for every value of sort `sortA(σ)` at every call. The real call returns one such value, by type safety of the checked program.
2. **No purity, determinism or totality is assumed.** Two calls get two binders, so the VC holds even if the calls return different values. If a call diverges or aborts (`error`, a failed runtime assertion), the run does not return. Partial correctness, the standing semantics of `LLMLL.md` §0.1 and §4.2, then makes the post vacuous.
3. **Effects.** A call that returns `Command` or `Promise` builds a value and performs nothing (`LLMLL.md` §9). Its binder has the `int` default sort and no constraint, so nothing reads it.
4. **The sort agrees with the value.** `sortA(σ)` is the rule a named callee uses. Where `σ` has no exact sort, the binder is unconstrained and is never equated with a term of a different sort. This is the case today for a named callee that returns `Command` (twin T8).
5. **Callers.** R3 drops only arguments that no translated clause mentions, so the assumed post and the proved pre are the same formulas as today. The callee's post was proved for every function value, so the caller may assume it whatever it passes.
6. **Termination accounting is unchanged and stays correct.** `g` is proved at partial correctness relative to calls through `p`. A caller that passes a named recursive function already gets a call-graph edge for the value use (`LLMLL.md` §4.4.4), so the termination flag lands on the caller that supplied the function. A lambda cannot recurse.
7. **Name resolution.** Points 1 to 5 are about the binder `p`. They are sound only if the verifier, the evaluator and the built program call the same function. R1 makes that true. Today it is false (witnesses S1 to S4).

## Congruence

An uninterpreted function symbol `p` per parameter would add one fact: equal arguments give equal results within one body. That fact is true in LLMLL for calls that return, because functions are pure and evaluation is call-by-value (`LLMLL.md` §4.7). It is not adopted in this row, for four reasons:

1. **Uniformity.** A named uncontracted callee has no congruence today (witness W5). Giving it to parameters only would make two calls with the same meaning prove differently.
2. **Sorts.** A function symbol needs an exact sort for every argument. The key idiom passes `Task` values, which may have no exact sort. The fresh binder never puts arguments in the `.fq`, so the argument sort does not matter (twin T6).
3. **New vocabulary.** A per-function symbol is a new kind of declaration in the `.fq`, with namespacing across functions in one file. The fresh binder adds none.
4. **No measured demand.** No probe program wrote a post that needs two equal calls to agree.

**What this costs.** A post that holds only because two equal calls agree is refuted, not proved. `verify` then exits 1 on a true post. Named callees have this incompleteness today (W5). It is filed as CALL-CONGRUENCE-1 in the Trigger-gated Parking Lot. The trigger is a real program whose post is refuted for this reason. The cheap form would be common-subexpression sharing in `aNormalizeBody`, for named and parameter callees together.

## Interactions

- **Higher-order builtins (`list-map`, `list-fold`, `list-sort-by`).** Not changed. They are builtins, not contract-environment keys, and a body that calls them falls back with `app:<builtin>`. A lambda passed to them stays opaque. LIST-LEN-AXIOM-1 owns the builtin side. An opaque binder for an unmodelled builtin is sound by the same argument as R2, but it is a different decision and no row is filed.
- **GENERICS-1 key idiom.** After specialization, `key : (fn [T] -> k)` has a concrete `k`, or `int` for an unfixed instance. A call `(key x)` is an R2 call whatever `T` is. The key call stops being a refusal cause. Other causes stay: the P1 copies still fall back on the `match` on `list-head` (generics-proposal.md, "Verification"). A post cannot mention `(key x)` (R4), so "sorted by key" is not expressible. A post such as `(or (= result a) (= result b))` proves (twin T6).
- **FFI-UNINTERP-1.** That row asks to admit a pure Tier 1 function as an uninterpreted symbol under a totality assumption. R2 shows that the VC half needs no symbol and no totality assumption at partial correctness. The admission half stays open. This record anticipates that row and does not settle it.
- **PBT-FN-PARAM-1.** It is the test-side twin. It changes the `evalC` `EApp` clause that FN-SHADOW-1 also changes, so the two edits belong in one commit series. It is not a soundness prerequisite of R2. Land it in the same release, for two reasons. A function-parameter function that still falls back for another cause has PBT as its only evidence. GENERICS-1 runs PBT per instance.

## Edge cases and positive witnesses

Each witness was run alone on a scratchpad build of `c61486f7` (`llmll 0.31.0`). A twin is the same body with the parameter replaced by a named uncontracted function. By R2, its result today is the predicted result after this lands.

| # | Input | Today | After | Channel |
|---|---|---|---|---|
| S1 | `(def pick [x: int y: int] -> int (post (= result x)) x)` and `(def-shell g [pick: (fn [int int] -> int) a: int b: int] -> int (post (= result a)) (pick a b))`, called as `(g (fn [x: int y: int] y) 1 2)` | `g` body-faithful, **SAFE**, sidecar `verified`. The built program stops with `Postcondition violated in g`. | R1: `g` is an R2 call, and it is refuted. | contract (soundness) |
| S2 | The same `pick`, and `(def-shell g2 [a: int b: int] -> int (post (= result a)) (let [(pick (mk 0))] (pick a b)))` where `mk` returns `(fn [x: int y: int] y)` | **SAFE**. The built program stops with `Postcondition violated in g2`. | R1: falls back (let-bound value). | contract (soundness) |
| S3 | S1's `g` with `(check … (= (g (fn [x: int y: int] y) a b) b))`, true at run time, and the same property with `a`, false at run time | The true property **fails** (counterexample `a = 0, b = 1`). The false property **passes**. | R1 and PBT-FN-PARAM-1: the true property passes, and the false one fails. | trust (PBT evidence) |
| S4 | `pick` in its own verified module, then `(import pk) (open pk)` and S1's `g` written as `def` | `check` OK; `--strict-verified-core` **SAFE**. | R1 and R6: `core-membership-violation`, callee is a parameter. | type (admission) |
| W1 | `min2-by` from the restatement (twin `min2-named`) | fallback, `Refused by: if` | proved | contract |
| W2 | `(def-shell pick-lambda [a: int b: int] -> int (post (or (= result a) (= result b))) (min2-by (fn [x: int y: int] (<= x y)) a b))` (twin: pass `int-le`) | fallback, `app:min2-by`. The twin is proved today. | R3: proved | contract |
| W3 | `(def-shell g [min: (fn [int int] -> int) a: int b: int] -> int (post (<= result a)) (min a b))`, the MMF-6 fixture (twin returns `b`) | fallback | body-faithful, **refuted**. This is correct: the post is false for a parameter that returns `b`. MMF-6 changes. | contract |
| W4 | `(f (f x))` with `f: (fn [int] -> int)` (twin `inc`, T9) | fallback | hoisted, two binders; SAFE | contract |
| W5 | `(if (le a b) (if (le a b) 0 1) 0)` with post `(= result 0)` (twin with `int-le`) | twin **refuted**, a true post (no congruence) | refuted, exit 1. This is the stated cost; see CALL-CONGRUENCE-1. | contract (incompleteness) |
| W6 | `(type PositiveInt (where [x: int] (> x 0)))`, `(def-shell use-pos [f: (fn [int] -> PositiveInt) a: int] -> int (post (> result 0)) (f a))`, and a caller passing `(fn [x: int] (- 0 5))`, which `check` accepts | fallback, `app:f` | **refuted**. This is correct: the call returns -5. The return refinement is not assumed. | contract |
| W7 | Twin T6: `key: (fn [Task] -> int)` with `(type Task (| Task int))`; T7: `(fn [Job] -> string)`; post `(or (= result a) (= result b))` | twins SAFE | SAFE | contract |
| W8 | Twin T8: `(fn [int] -> Command)` called in a `let`, post on another value | twin SAFE, binder at `int`, unconstrained | SAFE | contract |
| W9 | `(def pos-le [x: int y: int] -> bool (pre (> x 0)) …)`; `via-value` passes `pos-le` to `min2-by`; `via-lambda` passes `(fn [x: int y: int] (pos-le x y))` | `via-value` body-faithful, **not reported**; `via-lambda` reported `call-pre unchecked: via-lambda -> pos-le` | R5: both reported | trust (disclosure) |
| W10 | `(def min2-by [le: (fn [int int] -> bool) …] …)` written as `def` | `core-membership-violation` | unchanged (R6), message names a parameter | type |
| W11 | A pre or post that applies `le` (MMF-C6) | contract-only fallback | unchanged (R4) | contract |

S1 to S4 are the positive witnesses for R1: each is a minimal firing input. W9 is the positive witness for R5. W3, W5 and W6 show that the change can turn a fallback into a refutation, and `verify` then exits 1. W3 and W6 are true refutations. W5 is incomplete.

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Body VC with R2 binders | contract | (a) QF-LIA with Bool and the existing datatype sorts. R2 adds a declared variable and no symbol (`LLMLL.md` §5.3.3, `Σ_auto`). |
| Call-pre at a caller with an R3 argument | contract | (a). The formula is the one emitted today. |
| Payload-subtyping at an R2 call | contract | (a). This is the existing obligation shape. |
| R1 | none new | It removes wrongly assumed posts, so it emits fewer facts. |

Nothing is class (b) or (c). Nothing goes to Lean.

## Stamp effect

- **FN-SHADOW-1 (R1) increases `checker_soundness_version` from `"3"` to `"4"`.** A sidecar from an older binary can hold a false `verified` (S1, S2, S4). This is the SAFE-ARG precedent: one re-verify per tree.
- **FN-PARAM-UF-1 (R2, R3, R5) needs no increase.** Every verdict it changes moves from `asserted` (fallback) to `verified` or `refuted`. An older sidecar holds no `verified` record for those functions, so nothing in it is false.
- **`.fq` content.** R2 and R3 change the `.fq` only of a file with a call through a function-typed parameter, or with a lambda argument to a user callee. In the tracked tree that is the MMF-6 fixture and the inline test sources named above. The refute-crux gate (96 frozen verdicts) holds no such file. Every other `.fq` is byte-identical, because each new clause fires only on occurrence.

## Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: `bodyToPredM` (the contract-environment `EApp` clause: binder shadowing, and the function-typed parameter case); `bodyToPredFromRS` and `aNormalizeBody` (hoist set); `translateCallArg` (R3); the uncovered-name check (R3); the per-function contract environment (R1 and R2).
- `compiler/src/LLMLL/Contracts.hs`: `evalC` for `EApp` (R1; PBT-FN-PARAM-1).
- `compiler/src/LLMLL/TypeCheck.hs` and `compiler/src/LLMLL/Diagnostic.hs`: strict-core callee admission and the parameter wording (R1, R6).
- `compiler/src/LLMLL/TrustReport.hs`: `uncheckedCallPres` (R5).
- `compiler/src/LLMLL/VerifiedCache.hs`: `checkerSoundnessVersion` to `"4"` (FN-SHADOW-1).
- Tests: MMF-6 changes; new regressions for S1 to S4 and W1 to W11.
- `LLMLL.md`: §5.3.3 (R2 as the opaque-call rule), §5.3.4 (`call-pre unchecked` by edge), §5.3.5 (fix the uncontracted-callee row, D1; add a row for a call through a function-typed parameter), and the binder-shadowing sentence in §4.4.4 extended to the verifier, the evaluator and admission.

There is no addition: no builtin, construct, FFI tier or capability.

## Risks

1. **New refutations change exit codes.** Class: verification-ergonomics. Source: W3, W5, W6. A file that passes `verify` today can exit 1. In the tracked tree only the MMF-6 fixture is affected. It complicates the change note and does not block.
2. **Wrong sort for an R2 binder crashes the solver.** Class: soundness of the run (a crash, not a false SAFE). Source: CALLEE-DATA-SORT-1 history. Use the named-callee sort rule unchanged. A battery over the return types in W7 and W8 covers it.
3. **R3 depends on no clause mentioning a function-typed parameter.** Class: soundness. Source: `exprToPred`, the `=` check. The uncovered-name check makes this hold by construction.
4. **Shadowing reaches further than measured.** Class: soundness. Source: S1 to S4. Other readers of the contract environment by bare name may exist; the engineer should search for every lookup of a call head.

## Hand-off

**Proposal file:** `docs/design/fn-param-uf-1-proposal.md`, Rev 0, settled. No review file exists.

**Engineer (code-track).** Do the work in two steps, in this order.

1. **FN-SHADOW-1 first.** Apply R1 in `bodyToPredM` and the ANF hoist set, in `evalC`, and in strict-core admission. Increase `checkerSoundnessVersion` to `"4"`. Add regressions S1 to S4: the build-and-run of S1 must agree with `verify`.
2. **Then FN-PARAM-UF-1 and PBT-FN-PARAM-1 together.** Apply R2 (parameter calls as uncontracted `CallVC`, with the alias-aware return sort, hoisted by ANF, and with payload-subtyping as for any callee). Apply R3 (do not translate a function-typed argument, and add the parameter to the uncovered-name check). Apply R5 (report by edge in `uncheckedCallPres`). Change MMF-6 to "body-faithful, no `(if `, Unsafe". Add W1 to W11 as tests. Then apply the PBT-FN-PARAM-1 closure in `evalC`. There is no JSON-AST change and no schema change. GENERICS-1 starts after this ships.

**Documentation lead.**

- In `docs/compiler-team-roadmap.md`, move FN-PARAM-UF-1 from DECIDE to PLAN and cite this record. Correct "uninterpreted function application" to "opaque call (fresh result binder)" (D2).
- File FN-SHADOW-1 in G1 as PLAN: "a parameter or local binder that shadows a top-level function is resolved to the top-level function by the verifier, the PBT evaluator and strict-core admission; false SAFE (S1, S2, S4) and false PBT evidence (S3)". It increases `checker_soundness_version`.
- File CALL-CONGRUENCE-1 in the Trigger-gated Parking Lot, with the trigger stated under "Congruence".
- Add a note to PBT-FN-PARAM-1 that it lands with FN-PARAM-UF-1 and shares the `evalC` edit with FN-SHADOW-1.
- Add one INDEX row for this record.
- At release, promote R1 to R6 into `LLMLL.md` §5.3.3 to §5.3.5 and fix the D1 row.
