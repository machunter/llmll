---
name: post-conj-split-proposal
title: "POST-CONJ-SPLIT-1: prove the admitted conjuncts of a post, and record a partly proved post"
status: "Rev 2, DRAFT 2026-11-02, professor review folded; awaiting user settlement"
date: 2026-11-02
author: language-team
rows: "POST-CONJ-SPLIT-1 (G1, DECIDE). Depends on CALLEE-POST-UNASSUMED-1 (ships first). References CLAUSE-WELLDEF-1. Proposes two follow-up rows, not filed (PRE-CONJ-DROP-1, POST-CONJ-DIAG-1)."
consumers: [user, professor, compiler-engineer, documentation-lead]
reviews: "docs/design/post-conj-split-professor-review.md (professor, against Rev 1); folded in the appendix. The review file stays in place until settlement."
---

# POST-CONJ-SPLIT-1: prove the admitted conjuncts of a post, and record a partly proved post

**Status: Rev 2, DRAFT 2026-11-02, professor review folded; awaiting user settlement.** Rev 1 measurements are on `llmll 0.35.1` (the main checkout build, liquid-fixpoint 0.9.6.3.7), run one file at a time under a memory and time watchdog. The review added three witnesses (`whole.llmll`, `rneed.llmll`, `mapdef.llmll`) on the same build. Rev 2 adds one check: the type checker rejects `(and)` and `(and a)` (§4.1).

**What changed from Rev 1.** The appendix maps each review item to the section that answers it. In short:

- The false refutation of a correct caller is not this row's defect. CALLEE-POST-UNASSUMED-1 fixes it, and it ships first (§3).
- The refutation rule is stated once: a refutation needs complete hypotheses on every failing constraint (§4.2).
- The totality argument of Rev 1 §4.3 reason 1 is removed. Clause well-definedness is a separate row, CLAUSE-WELLDEF-1. Per-conjunct stripping is forbidden (§4.3, §4.5).
- Option B is chosen and fully specified (§4.4).
- Each reader of `erBodyFaithfulFns` has a decision (§4.6).
- The motivation uses the measured witnesses and the Y4M probe, not the netpbm "header half" claim (§2).

## Summary

1. **Recommendation: split, after CALLEE-POST-UNASSUMED-1.** `verify` flattens the top-level `and` of a function's effective `post` into conjuncts. It proves the conjuncts that translate. It records each other conjunct `asserted`.
2. **One body VC per path, as today.** The right side of each path constraint is the conjunction of the admitted conjuncts. When every conjunct translates, the `.fq` is byte-identical to today, at the definition and at every call site.
3. **A refutation needs complete hypotheses.** A function is refuted only when every hypothesis of every failing constraint is the authored one. A callee post that is not assumed in full makes the hypotheses incomplete. That case falls back (the CALLEE-POST-UNASSUMED-1 rule).
4. **Truth and well-definedness are separate obligations.** The split proves the truth of each admitted conjunct, without assuming any other conjunct. It does not prove that a conjunct is defined at run time. CLAUSE-WELLDEF-1 owns that obligation.
5. **Callers assume the admitted conjuncts (Option B).** A caller's level meets the level of the conjuncts it actually assumed, edge by edge and through the transitive closure.
6. **The clause stays `asserted`.** A partly proved post keeps `display_level: asserted` and `body_faithful: false`. Clause `body_faithful` now means "a body VC proved the whole clause". A new `partly_proved: true` marker names the other state.
7. **No per-conjunct stripping.** `--contracts=unproven` keeps the whole post as a run-time assertion. `--strict-verified-core` still fails on a partly proved function.

---

## 1. Restatement

A `post` is translated into the `Σ_auto` fragment as one unit. If any sub-term does not translate, the emitter withdraws the whole post. The function then falls back with cause `contract-post-outside-fragment`, and callers assume nothing from the post. The question is whether `verify` should treat a top-level `and` as a list of separate proof goals. The proposal must also say how each consumer records and reads a partly proved post. The consumers are the trust report, the `.verified.json` sidecar, the proof artifact, `--strict-verified-core`, call sites, the patch outcome, weakness checks and CDP.

## 2. Motivation, measured

### 2.1 The netpbm F6 claim is wrong

The roadmap row says the split "would have verified the header half of 8 transforms" (`examples/netpbm/FRICTION.md` F6). That is false on 0.35.1. I verified the netpbm modules in the order of `examples/netpbm/build.sh`, and then removed the refusals one at a time:

| Variant of the transform contract | Result on 0.35.1 |
|---|---|
| As written: `pre (image-ok? img)`, `post (and (image-ok? result) (= (img-header result) (img-header img)))` | fallback, `contract-post-outside-fragment; app:image-ok?, app:img-header` |
| `post (= (img-header result) (img-header img))` (the "header half" alone) | fallback, `contract-post-outside-fragment; app:img-header` |
| `post (= (first result) (first img))`, pre kept | fallback, `contract-pre-outside-fragment; app:image-ok?` |
| `post (= (first result) (first img))`, no pre | fallback, `body-outside-fragment; app:list-map, lambda` (`vflip`: `app:list-reverse`; `blur`: seven constructs) |

Four refusals stack on each transform:

1. The out-of-fragment conjunct `image-ok?`. This row addresses it.
2. A user call (`img-header`) in a clause. `exprToPred` has no case for a user call (`compiler/src/LLMLL/FixpointEmit.hs:3736-3934`). That is `POST-CALL-XMOD-1`, and it applies within one module too.
3. The pre `(image-ok? img)`. A def-site pre that does not translate withdraws the body VC (`FixpointEmit.hs:1587-1597`). PRE-CONJ-DROP-1 (§4.8) is the follow-up.
4. The body. `list-map`, `lambda` and `list-reverse` are outside `Σ_auto`. No open row admits a list-transforming body as an opaque term.

Refusal 4 alone blocks every conjunct, because no conjunct is proved without a body VC. So netpbm is not a motivation for this row.

Three smaller findings on the row text:

- **F6 sub-claim.** F6 says the label "names a verified callee (`img-header`) as refused". The label is correct. A user call in a clause is refused whatever the callee's evidence (refusal 2).
- **Citation drift.** The row cites `examples/netpbm-swarm/FRICTION.md` for "netpbm F6". Swarm F6 is about verify cost. The conjunct problem is only in `examples/netpbm/FRICTION.md` F6. Swarm F10 (no failing-conjunct diagnostic) is related; see POST-CONJ-DIAG-1.
- **Hidden body causes.** F6 also says the body's own causes are not reported. The emitter decides the post before it tries the body (`FixpointEmit.hs:1586-1597`). A refused post therefore hides every body cause. With the split, a partly admitted post reaches the body, so its causes become visible.

### 2.2 The Y4M probe, F4: one conjunct withdrew a whole post

`examples/y4m/FRICTION.md` F4 is the real motivation. The first contract of `raster.next-p` had four conjuncts. One of them was `(= result (if (= p 2) 0 (+ p 1)))`. An `if` is admitted in a body but not in a post. So the emitter withdrew all four conjuncts, and the three conjuncts in the fragment were lost with the `if` conjunct.

`check` accepted the file and gave no warning. `check` does not run the emitter, so it cannot see a fragment refusal. The first sign was `PatchNotProved` on the body patch, with cause `contract-post-outside-fragment`. `marker-step` had the same shape (seven `if` conjuncts). The author rewrote each `if` conjunct as two implications. The contract change then restarted the hole protocol for the module (Y4M F6).

Under this proposal, `next-p` as first written gives three `verified` conjuncts and one `asserted` conjunct, refused by `if`. The patch outcome names the refused conjunct (§4.6, `PatchApply.hs`). This is a prediction, not a measurement. The engineer's acceptance test is the original `next-p` contract.

The missing `check`-time warning is outside this row. It is a finding for the user to route.

### 2.3 Minimal witnesses

All files are in the session scratchpad: Rev 1 files in the lead's directory, review files in `pcsrev/`. A shell function `all-pos?` makes a conjunct out of the fragment:

```lisp
(def-shell all-pos? [xs: list[int]] -> bool
  (list-fold xs true (fn [acc: bool x: int] (and acc (> x 0)))))

(def-shell pos-or-one [n: int] -> int
  (post (and (>= result 1) (all-pos? [result])))
  (if (> n 0) n 1))

(def-shell use-it [n: int] -> int
  (post (>= result 2))
  (+ (pos-or-one n) 1))
```

| File | Callee post | Today (0.35.1) | After CALLEE-POST-UNASSUMED-1 | After the split as well |
|---|---|---|---|---|
| `split.llmll` (above) | `(and (>= result 1) (all-pos? [result]))` | callee asserted; `use-it` **refuted** (false); exit 1 | `use-it` falls back, own cause; exit 0 | callee conjunct 0 verified, 1 asserted; `use-it` SAFE, `verified` (Option B) |
| `bad.llmll` | `(and (>= result 5) (all-pos? [result]))`, body is wrong | callee asserted; `use-it` **refuted** (wrong blame); exit 1 | callee asserted; `use-it` falls back; exit 0 | callee **refuted** on conjunct 0; `use-it` depends-on-refuted; exit 1 |
| `whole.llmll` | `(all-pos? [result])` | `use-it` refuted; exit 1 | `use-it` falls back | no change: no conjunct is admitted |
| `rneed.llmll` | `(and (>= result 0) (all-pos? [result]))` | `use-it` refuted; exit 1 | `use-it` falls back | callee partly proved; `use-it` still needs `result ≥ 1` from the refused conjunct, so it falls back |
| `only.llmll` | `(>= result 1)` | both verified; exit 0 | no change | no change |
| `badonly.llmll` | `(>= result 5)` | callee refuted; `use-it` depends-on-refuted | no change | no change |
| `mapdef.llmll` | `mk` returns `(map-empty)`, post `(= (map-get result 3) 0)` | `mk` verified, sidecar written; the built program calls `error` on `map-get` | no change | no change; CLAUSE-WELLDEF-1 |

The columns separate the two rows. CALLEE-POST-UNASSUMED-1 removes the false refutations in `split`, `whole` and `rneed`. The split adds proof: it turns `split.llmll` into a proved caller, and it turns `bad.llmll` into a refutation of the correct function. Without the split, `bad.llmll` passes with exit 0 and an `asserted` wrong callee.

## 3. Dependencies

**CALLEE-POST-UNASSUMED-1 ships first.** Today `refutedSet` (`compiler/app/Main.hs:1672-1676`) accepts an UNSAFE answer from a VC whose hypotheses are incomplete. A call whose callee post did not translate gets a free result binder (`FixpointEmit.hs:4648-4690`, `cvPostAssumption = Nothing`). In the terms of Godefroid et al. (POPL 2010), that UNSAFE answer is a *may* counterexample. A refutation needs a *must* counterexample. CALLEE-POST-UNASSUMED-1 marks each constraint whose environment holds a call result whose callee post exists and was not assumed in full. A function whose every failing constraint carries the mark falls back with its own cause, as `applyAbstractionVerdict` does. That row also changes the W-BODY-FALLBACK text by cause (`compiler/src/LLMLL/Diagnostic.hs:300-312`) and the refutation wording at `LLMLL.md:633` (§4.4.1).

The split depends on that mark in two ways:

1. A partly proved callee is, by definition, not assumed in full. Its callers' failing constraints carry the mark.
2. A call-site sort guard that drops one conjunct (E11) also sets the mark.

So the split needs no new verdict mechanism. It needs one change to the input of the mark: "assumed in full" means every conjunct of the callee's effective post was assumed at that call site.

**CLAUSE-WELLDEF-1 is independent, and it blocks one later change.** It checks that a clause is defined at run time where it is evaluated. The `mapdef.llmll` shape exists today without the split. This proposal does not depend on it. Per-conjunct stripping under `--contracts=unproven` waits for it (§4.5).

## 4. Design proposal

### 4.1 Conjunct list

**Definition.** The conjunct list of a function is the flattening of the top-level `and` nodes of its effective post. The effective post is the post after the SRC-CONJ-1 clause fold (`compiler/src/LLMLL/Parser.hs:592`) and the DEF-RET return-refinement fold (`augmentContractPost`, `FixpointEmit.hs:6469-6476`). Flattening goes through `and` only.

```
conj(and(a_1, …, a_n)) = conj(a_1) ++ … ++ conj(a_n)     -- n ≥ 0
conj(e)                = [e]                              -- e is not an `and` node
```

The list is in author order. The return-refinement conjunct, when present, is last. Each conjunct has an index `k` (0-based) and an origin: `author` or `return-refinement`.

Flattening does not go through `let`, `if`, `match`, `=>`, `<=>`, `or` or `not`. A conjunct with one of these at its head is one conjunct. See §5 E7 and E8.

**Degenerate `and`.** `and` is typed binary (`compiler/src/LLMLL/TypeCheck.hs:129`, `TFn [TBool, TBool] TBool`). On 0.35.1, `(post (and))` and `(post (and (>= result 0)))` fail `check` and `verify` with `operator 'and' expects 2 args, got 0` (or `got 1`), exit 1. A nested `(and)` fails the same way. So no authored post reaches the emitter with a nullary or unary `and`. The definition above still covers every arity, because internal folds build `and` nodes. For `n = 0` the list is empty. For `n = 1` the list is `conj(a_1)`. An empty list has no refused conjunct, so it takes the "every conjunct admitted" row of §4.2, which emits today's term.

**Surface.** No change. `(post (and a b))`, `(post (and a (and b c)))`, and repeated `(post a) (post b)` clauses all give a flat list. The JSON-AST is unchanged, so `schema_version` does not change.

### 4.2 Definition-site obligation and the refutation rule

Let `A` be the admitted conjuncts: those `c_k` where `exprToPred c_k` is `Just q_k`. Let `R` be the refused conjuncts.

| `A` | `R` | Behaviour |
|---|---|---|
| all | empty | As today. One body VC per path, right side `FQAnd [q_0 … q_n]`. The `.fq` is byte-identical (FQ-FLAT-NEST-1, `compiler/src/LLMLL/FixpointIR.hs:340-381`, prints the same flat chain). |
| empty | all | As today. Fallback, cause `contract-post-outside-fragment`. |
| non-empty | non-empty | **New.** One body VC per path, right side `FQAnd [q_k | k ∈ A]`. The function is *partly proved*. |

The rule for the new case:

```
  P  ∧  path  ∧  Γ_calls  ∧  result = ⟦B⟧   ⟹   ⋀_{k ∈ A} q_k          (one constraint per path)
```

`P` is the full translated pre. If the pre does not translate, the function falls back as today (`contract-pre-outside-fragment`); PRE-CONJ-DROP-1 is the follow-up. `Γ_calls` is the set of callee-post assumptions at the calls on the path (§4.4).

**Guards stay whole.** The whole-contract guards in `postCause` (`FixpointEmit.hs:1544-1568`: signature guard, whole-structure equality, map-clause guard) still refuse the whole contract. Only the `exprToPred` refusal is split. This keeps the sort-crash firewall of `LLMLL.md §5.3.3` unchanged (§5 E9).

**The refutation rule.** A function is refuted only when every hypothesis of every failing constraint is the authored one. For a body VC, the hypotheses are the pre, the path, the body and `Γ_calls`. So the rule needs:

1. the pre translated whole (true in this row, because a refused pre falls back);
2. the full body (true for every body VC);
3. at every call in the environment of the failing constraint, the callee post assumed in full.

Condition 3 is the CALLEE-POST-UNASSUMED-1 mark. The split does not change the rule. It only adds a new way to fail condition 3 (a partly proved callee).

The refused conjuncts `R` of the function's *own* post are goals, not hypotheses. Leaving them out of the goal does not weaken the hypotheses. A model where an admitted conjunct is false is a model where the post is false, whatever `R` evaluates to. So an UNSAFE answer that meets the rule disproves the authored post, in the modular sense of `LLMLL.md §4.4.1`.

**Verdicts.**

- SAFE: every `k ∈ A` gets `verified (liquid-fixpoint)`. Every `k ∈ R` gets `asserted`, with its refusing constructs from `refusedConstructs c_k` (`FixpointEmit.hs:3936-3960`).
- UNSAFE, and the refutation rule holds: the function is **refuted**.
- UNSAFE, and every failing constraint carries the CALLEE-POST-UNASSUMED-1 mark: the function falls back with that row's cause. All conjuncts are `asserted`.
- UNSAFE that ABSTRACTION-VERDICT-1 reclassifies: the function falls back with cause `abstraction-unsafe`, as today. All conjuncts are `asserted`. This needs the partly proved list in `applyAbstractionVerdict` (§4.6).

### 4.3 Truth and well-definedness

A clause has two obligations, and Rev 1 mixed them.

- **Truth.** In every state that the hypotheses admit, the conjunct is true. Each admitted conjunct denotes an SMT term, so the truth obligation of each conjunct is independent of the others.
- **Well-definedness.** Where the program evaluates the clause at run time, each partial operation in it is inside its precondition. Dafny checks this in a separate well-formedness pass. It assumes the earlier conjunct of `&&` only in that pass, never in the truth proof. SPARK checks run-time errors in contracts the same way.

**Rule: each admitted conjunct is proved true without assuming any other conjunct.** One constraint with a conjunctive right side is valid exactly when each conjunct is valid under the same hypotheses. So §4.2 already gives independent truth obligations. Two reasons support the rule:

1. **Assuming an admitted earlier conjunct adds nothing.** If `c_0 ∈ A` is proved, then `P ∧ B ⟹ c_0`, so `P ∧ B ∧ c_0` and `P ∧ B` have the same models. If `c_0` is refuted, the function is refuted anyway.
2. **Assuming a refused earlier conjunct is not available, and would be wrong.** A refused conjunct has no FQ form, so it cannot be assumed. If a later revision admitted a conjunct only in part, assuming it would make a `verified` record depend on an `asserted` fact.

Rev 1 gave a third reason: "every admitted term is total, and the partial operations that need a guard are refused". **Rev 2 removes it.** It is false. `exprToPred` admits `map-get` and `bytes-get` as `Map_select` (`FixpointEmit.hs:3736-3934`). Both have run-time preconditions (`LLMLL.md §13.12`: `map-get` needs `(map-has m k)`, `bytes-get` needs `0 ≤ i < n`). `Map_select` is total in the logic. Outside the precondition, its logic value is an artefact of the encoding. Run-time `map-get` on an absent key calls `error` (`compiler/src/LLMLL/CodegenHs.hs:581`). `mapdef.llmll` shows the result today: a `verified` post whose run-time evaluation fails.

Division and `mod` are not counterexamples. They are admitted only with a numeral divisor greater than zero (`constArithTerm`). Codegen emits `div` (`CodegenHs.hs:2434`), floor division, and SMT-LIB `div` with a positive divisor is also floor division. Pair selectors are total. MATCH-POST selectors sit under constructor tests inside one `exprToPred` result, so the split never separates them.

**What the split does to the well-definedness gap.** It increases exposure. Today `(and (refused-guard r k) (= (map-get r k) 0))` is `asserted` in whole. After the split, the second conjunct gets its own `verified` record. That record is sound as part of the conjunction: it was proved over more states than the guard admits. It is not sound as a standalone run-time claim. Three rules follow:

1. **No per-conjunct stripping.** `--contracts=unproven` keeps the whole post of a partly proved function. This holds until CLAUSE-WELLDEF-1 ships, and that row reopens the question.
2. **No standalone wording.** The per-conjunct record and text say "proved as part of the post". They never present a conjunct as a run-time assertion that holds alone (§4.7).
3. **The well-definedness obligation belongs to CLAUSE-WELLDEF-1.** That row covers every clause, split or not.

**Run time is unchanged.** The built program still evaluates the whole post with short-circuit `and` (`LLMLL.md §4.7`, `§13.3`). A refused conjunct that needs an earlier guard keeps that guard at run time, because the post is not stripped.

**The example from the brief.** `(and (> (list-length xs) 0) (= (list-nth xs 0) (ok result)))`: conjunct 0 is admitted (`listLen`), conjunct 1 is refused (`app:list-nth`). Conjunct 0 is proved alone. `list-nth` answers `Error` out of range (`LLMLL.md §13.5`), so conjunct 1 is defined at run time without the guard.

### 4.4 Call sites and the caller tier (Option B)

**Rule: a caller assumes the admitted conjuncts of the callee post, and only those.** At a call, `cvPostAssumption` becomes `FQAnd [q_k[args, r/result] | k ∈ A_callee]`. The three existing call-site sort guards (`FixpointEmit.hs:4648-4666`) apply to each conjunct. A guarded conjunct is dropped. Dropping a hypothesis is a sound weakening. The call site records the set `S ⊆ A_callee` of indices it assumed. If `S` is not every conjunct of the callee's effective post, the call is "not assumed in full", and the CALLEE-POST-UNASSUMED-1 mark applies.

**CALL-CONGRUENCE-1.** No change. The congruence fact reads the call key (callee, argument sorts), not the post (`FixpointEmit.hs:5693-5745`).

**Cross-module.** The imported `ContractEnv` is rebuilt from `meStatements` (`seedImportedContracts`, `FixpointEmit.hs:581`). So the importer computes the same conjunct list and the same `A`. The importer reads the per-conjunct levels from the callee's sidecar (§4.7). A missing or unreadable record reads `asserted` (fail closed).

**Decision: Option B.** The caller's level meets the level of the callee conjuncts it actually assumed. Option A (meet the callee's clause level, `asserted`) is rejected. The caller's proof does not use `Q_R`, so the caller's guarantee holds even when `Q_R` is false or is not checked at run time. The appendix (P4) gives the reviewer's three arguments: hybrid type checking, gradual verification, and blame.

**Specification of Option B.**

1. **Per call site, after the sort guards.** The assumed level of a call site is the meet of the per-conjunct levels over `S`, the indices assumed at that site. It is not the meet over `A_callee`. If `S` is empty, the site assumed nothing, and the edge keeps today's rule (meet with the callee's clause level). This fails closed.
2. **Per edge.** The assumed level of an edge `C → P` is the meet over every call site of `P` in `C`'s body.
3. **Edge by edge in the `enrichEntry` fold.** Today `calleeMinLevel` (`compiler/src/LLMLL/TrustReport.hs:1595-1599`) is a fold of `csPost` over the flattened transitive callee set. That fold is wrong for a partly proved callee. A grand-caller `G` would meet `P`'s clause level `asserted` through a caller `C` whose proof used only `Q_A`. The new fold gives each transitive callee `X` the meet, over every edge `Y → X` with `Y` in `G`'s closure or `Y = G`, of that edge's assumed level. For a callee that is not partly proved, every edge level equals the clause level, so the fold equals today's fold.
4. **A callee whose body falls back.** A callee can have a partly admitted post and a body outside the fragment (cause `body-outside-fragment`). It has no body VC, so it writes no `conjuncts` record (§4.7). Its callers still assume `Q_A`, because the call site translates each conjunct whatever the callee's evidence. Each assumed conjunct then reads the clause level, `asserted`. So the caller is `asserted` through that edge. This is the fail-closed default, stated here so the engineer does not have to infer it.
5. **Record the assumed indices.** The caller's trust entry gains `assumed_callee_conjuncts`: one object per edge into a callee with a refused conjunct, `{callee, indices, level}`. `indices` is the union of `S` over the edge's call sites. `level` is the edge's assumed level. An auditor can then recompute the meet.
6. **`--strict-verified-core`.** A caller labelled `verified` under Option B still fails the strict core through its callee. In the same module, the partly proved callee is in `body_fallback`, so the gate fails the run (`Main.hs:1520-1535`). Across modules, `importAssumedOf` (STRICT-XMOD-1, `Main.hs:1531`) names the imported callee as not proved. This is consistent: a strict core needs every function in the core proved in full.

`ObligationAssembly`'s `callee_tier` reads the same value through `teEffectiveLevel`, so it follows Option B with no separate change.

The downstream trust warning (`LLMLL.md §4.4.3`) still fires for a partly proved imported callee, because its clause is `asserted`. Its text names the state: `post partly proved (1 of 2 conjuncts verified)`.

### 4.5 Clause-level records

**Definition: clause `body_faithful`.** `body_faithful: true` on a post clause means "a body VC proved the whole clause". A partly proved post has `body_faithful: false` and `display_level: asserted`. Every reader that keys on the clause therefore fails closed, as it does today.

**Definition: `partly_proved`.** `partly_proved: true` on a function means "a body VC was emitted for the admitted conjuncts of the post, and at least one conjunct was refused". It is present only when true, as `refuted` is. It separates the two states that `body_faithful: false` now covers: no body VC, and a body VC for part of the post. A refuted partly proved function carries both `refuted: true` and `partly_proved: true`.

**New fallback cause.** `FallbackContractPostPartial`, rendered `contract-post-partly-outside-fragment`. The closed set (`FixpointEmit.hs:200-264`) grows by one. With CALLEE-POST-UNASSUMED-1 it grows by two in all; the census counts each cause in its own bucket (`scripts/fallback_census.py`). A partly proved function is in `body_fallback` with this cause. It is in a new emitter list, `erPartlyProvedFns`. It is not in `erBodyFaithfulFns`.

| Consumer | Behaviour for a partly proved function |
|---|---|
| `--contracts=unproven` (`compiler/src/LLMLL/Contracts.hs:229-254`) | Keeps the whole post as a run-time assertion. Per-conjunct stripping is forbidden until CLAUSE-WELLDEF-1 (§4.3). |
| Strict-core callee admission (`checkCalleeAdmissibility`) | Not admissible (no body-faithful clause record). |
| `--strict-verified-core` | Fails. The function is in `body_fallback` with the new cause. |
| `--weakness-check`, `--cdp` (`Main.hs:2390`, `:2420`) | Unchanged: the candidate is in `body_fallback`, so it is reported unvalidated. Running candidates against `A` is a follow-up (§9). |
| Leanstral route (`Main.hs:2133`) | Unchanged: the function is in `body_fallback`. |

### 4.6 Every reader of `erBodyFaithfulFns`

The review listed five readers besides `refutedSet`. A grep of this worktree finds those and five more in `Main.hs`. The rule for each decision: a reader that asks "did a body VC run over this function?" takes the union of the two lists. A reader that asks "is the whole post proved?" takes `erBodyFaithfulFns` alone.

| Reader | What it asks | Decision |
|---|---|---|
| `compiler/src/LLMLL/AbstractionVerdict.hs:87` (`faithful`, rule 1 candidates) | Can this UNSAFE id be reclassified? | **Union.** Otherwise a partly proved function whose UNSAFE answer runs through two calls of one callee is reported refuted, the false refutation ABSTRACTION-VERDICT-1 stops. |
| `AbstractionVerdict.hs:119` (`reclassifyEmit`) | Move a reclassified function to fallback | **Also remove it from `erPartlyProvedFns`.** Its cause becomes `abstraction-unsafe`; all conjuncts are `asserted`. |
| `compiler/app/Main.hs:1660`, `:1672-1676` (`refutedSet`) | Is this UNSAFE origin a disproof? | **Union**, under the refutation rule of §4.2 (CALLEE-POST-UNASSUMED-1 mark). Without it a false admitted conjunct is silently `asserted` (`bad.llmll`). |
| `compiler/src/LLMLL/ObligationAssembly.hs:1199` (`faithful`, feeds `ccBodyFaithful` `:1367`, `:1445`; `classifyBodyFragment` `:1365`, `:1443`; `mkTrustChannel` `:1371`) | Clause-level flag in the obligation report | **`erBodyFaithfulFns` alone**, so `body_faithful` agrees with the trust report. Constraint obligations of a partly proved function still come from the constraint table. They carry `partly_proved: true`. |
| `compiler/src/LLMLL/PatchApply.hs:738` (`patchedOutcomes`) | Did the patch prove the function? | **`erBodyFaithfulFns` alone.** A partly proved function is not proved, with the new cause. `notProvedMessage` (`PatchApply.hs:716-732`) changes by cause. For this cause it says "N of M post conjuncts were proved; conjunct k is outside the fragment (constructs)". The current tail "Rewrite the body without those constructs" is wrong for a post refusal; it applies only to `body-outside-fragment`. |
| `Main.hs:1907` (sidecar writer, `bodyFaithfulSet`) | Write the post as `verified`? | **`erBodyFaithfulFns` alone.** The clause stays `asserted`. On SAFE, the writer adds `conjuncts` for each function in `erPartlyProvedFns` (§4.7). |
| `Main.hs:3610` (proof artifact, `entryToInputs`) | Tier of the function record | **`erBodyFaithfulFns` alone.** The tier is `asserted` from the clause; `fallback_reason` is the new value. A refuted partly proved function has `refuted: true` and a non-null `fallback_reason`. `mkFnRecord` (`compiler/src/LLMLL/ProofArtifact.hs:159-163`) accepts it, because the tier is not positive. Add a test for that record. |
| `Main.hs:1492-1493` (text line `body-faithful:`) | Display | **`erBodyFaithfulFns` alone.** Add a `partly proved:` line. |
| `Main.hs:1508` (`uncheckedCallPres`, `TrustReport.hs:1307-1319`) | Did a body VC check the call-site pres? | **Union.** A partly proved function has a body VC, so its call-site pres are proved obligations. Without the union, the report says "call-pre unchecked" for them, which is false. |
| `Main.hs:1531` (`importAssumedOf`, strict core) | Proved imports under a body-faithful function | **`erBodyFaithfulFns` alone.** A partly proved function already fails the strict core. |
| `Main.hs:1571`, `:1761` (`body_faithful` key in `--json`) | Census and verdict object | **`erBodyFaithfulFns` alone.** Add a `partly_proved` key with `erPartlyProvedFns`, on both exit paths (the census reads one shape, FALLBACK-CENSUS-1). |
| `Main.hs:1747-1749` (`headlineCounts`) | The proved count in the headline | **`erBodyFaithfulFns` alone.** The footer adds a partly proved count (§4.7). |

### 4.7 Schema delta

**Sidecar (`.verified.json`).** The post record of a partly proved function gains `conjuncts`. Each entry carries its own evidence, so the existing read rules apply to each entry:

```json
"pos-or-one": {
  "post": {
    "display_level": {"level": "asserted"},
    "body_faithful": false,
    "partly_proved": true,
    "conjuncts": [
      {"index": 0, "origin": "author", "text": "(>= result 1)",
       "display_level": {"level": "verified", "prover": "liquid-fixpoint"},
       "body_faithful": true, "verified_hash": "sha256:…"},
      {"index": 1, "origin": "author", "text": "(all-pos? [result])",
       "display_level": {"level": "asserted"},
       "refused_by": ["app:list-empty"]}
    ]
  }
}
```

- Written only for a partly proved post that was SAFE. A fully proved post, a fully refused post, and a partly admitted post whose body falls back keep today's shape (§4.4 item 4).
- On a conjunct entry, `body_faithful: true` means "a body VC proved this conjunct as part of the post". It does not claim run-time well-definedness (§4.3).
- `verified_hash` is the function's existing hash. It covers the effective post, so the index is stable while the hash matches.
- Read rule: the `LLMLL.md §4.4.1` downgrade (verified without `body_faithful`, absent hash, hash drift, no live definition) applies to each entry.
- An old binary ignores `conjuncts` (unknown keys are ignored, `compiler/src/LLMLL/VerifiedCache.hs:150-260`) and reads the clause as `asserted`. A new binary that reads an old sidecar finds no `conjuncts` and reads the whole clause.

**`checker_soundness_version` stays `"6"`.** Every post that translated before emits the same term. The change makes clauses translate that did not, and adds caller hypotheses at call sites that assumed nothing. Adding a hypothesis cannot turn a recorded SAFE into UNSAFE. This is the "keeps the stamp" case of `LLMLL.md §4.4.1`. **Condition: the byte-identical `.fq` sweep covers definitions and call sites.** For every corpus file with no partly admitted post, the `.fq` is byte-identical. In particular, a caller of a callee whose post is unchanged and fully admitted emits the same `cvPostAssumption` bytes. A caller of a fully refused callee emits no assumption, as today.

**Trust report.** `trust_report_version` goes from `1.10.0` to `1.11.0` (`TrustReport.hs:466-467`). The version increases although the keys are additive, because Option B changes what a caller's level means. The precedent is `1.9.0` (MODE-CLI-1). New keys, each with a row in `docs/llmll-trust-report.schema.json` in the same release:

| Key | Where | Schema note |
|---|---|---|
| `partly_proved_fns` | top level | The top-level object is closed (`additionalProperties: false`, line 9). The row is required. |
| `partly_proved` | `TrustEntry` | `{"type": "boolean", "const": true}`, omitted when false, like `refuted`. `TrustEntry` is open (line 150), but the project documents each key. |
| `post_conjuncts` | `TrustEntry` | Array of closed objects: `index`, `origin`, `text`, `display_level`, `body_faithful`, `refused_by`. Same objects as the sidecar, without the hash. |
| `assumed_callee_conjuncts` | `TrustEntry` | Array of closed objects: `callee`, `indices` (array of integers), `level` (`LevelLabel`). |

Text form:

```
  pos-or-one:
    pre:  —  |  post: asserted, partly proved, 1 of 2 conjuncts verified   [body_fallback: contract-post-partly-outside-fragment; app:list-empty]
      post[0] verified (liquid-fixpoint), proved as part of the post   (>= result 1)
      post[1] asserted                                                   (all-pos? [result])   refused by app:list-empty
  use-it:
    post: verified   assumes pos-or-one post[0] (verified)
```

**Footer.** `SAFE (liquid-fixpoint), partial: 3 of 33 contracted functions proved; 1 partly proved; 29 assumed, not proved: …`.

**`verify --json`.** `body_fallback_causes` can carry the new value, and the verdict object gains `partly_proved`. The verdict object is open (`docs/llmll-verify.schema.json`), so `verify_json_version` stays `1.0.0`. `docs/getting-started.md:567` says "one of eleven fixed" values. The count changes with this row and with CALLEE-POST-UNASSUMED-1.

**Proof artifact.** `docs/proof-artifact.schema.json:76` enumerates `fallback_reason`. Adding a value breaks a validator of the old schema, so `proof_artifact_version` goes from `0.1.0` to `0.2.0`. The description "Null iff body-faithful" (same line) becomes "Null iff a body VC proved the whole post clause". The function record gains `partly_proved`. The §4.1 invariant (`ProofArtifact.hs:159-163`) does not change.

**Compiler version.** A minor release (`0.36.0`). A function that was silently `asserted` can now be refuted (E4), so `verify` exit codes change on some programs.

### 4.8 Follow-up rows (proposed, not filed)

- **PRE-CONJ-DROP-1.** At the definition site, drop the pre conjuncts that do not translate, and prove the post under the admitted pre. A weaker hypothesis is sound. An UNSAFE answer under a dropped pre conjunct is a may counterexample. It falls back, with cause `contract-pre-partly-outside-fragment`, never `refuted`. This is the same rule as §4.2 and CALLEE-POST-UNASSUMED-1: refuted only when every hypothesis of every failing constraint is the authored one. **Measure first.** A dropped pre conjunct can be the guard of a partial body operation, such as a `bytes-get` index bound. The VC then fails on the call precondition and falls back, so the row gains nothing. The row states a gain only after a corpus count: functions with a partly admitted pre, an admitted post and an in-fragment body, and among them how many SAFE results the dropped guard prevents. The call-site pre stays whole: it is a PROVE obligation, and the call is withdrawn when it does not translate (`FixpointEmit.hs:4641-4642`).
- **POST-CONJ-DIAG-1.** Name the failing conjunct, and name the outer refusing call.
  - *Failing conjunct, on UNSAFE only.* After an UNSAFE answer, re-solve each failing constraint once for each admitted conjunct, and name the first conjunct that fails. A SAFE run costs nothing extra. Rev 1 proposed one constraint per conjunct on every run. That multiplies the cost of every run by `|A|`, so Rev 2 drops it. This is the on-demand pattern that CALL-CONGRUENCE-1 planned.
  - *Outer refusing call.* `refusedConstructs` stops at the deepest refusing node. For `split.llmll` the label is `app:list-empty`, and the list literal hides the user call `all-pos?`. The per-conjunct label also reports the outermost refusing user call: `app:all-pos? (app:list-empty)`. Authors read this label more after the split.

## 5. Edge cases and degenerate inputs

**E1. Positive witness: a partly proved post.**
Input: `pos-or-one` in `split.llmll` (§2.3). Behaviour: conjunct 0 `verified`, conjunct 1 `asserted`, cause `contract-post-partly-outside-fragment`, `partly_proved: true`. `use-it` is SAFE and `verified` under Option B, with `assumed_callee_conjuncts: [{callee: pos-or-one, indices: [0], level: verified}]`. Channel: contract (conjunct 0), trust (conjunct 1). Cite: §4.2, §4.4.

**E2. Every conjunct admitted.**
Input: `(post (and (>= result 0) (<= result 10)))`. Behaviour: as today; byte-identical `.fq` at the definition and at every call site. Channel: contract. Cite: §4.2 row 1; §4.7 sweep condition.

**E3. Every conjunct refused, or no `and`.**
Input: `(post (image-ok? result))`, or `whole.llmll`. Behaviour: as today, `contract-post-outside-fragment`. A caller's UNSAFE answer falls back under CALLEE-POST-UNASSUMED-1. Channel: trust. Cite: §4.2 row 2; §3.

**E4. An admitted conjunct is false (a new refutation).**
Input: `bad.llmll`, or `(post (and false (image-ok? result)))`. Behaviour: the function is refuted; callers are depends-on-refuted; exit 1. Today the function is silently `asserted` and the exit status blames a caller. Channel: contract. Cite: §4.2 verdicts; §4.6 `refutedSet` row.

**E5. A guard conjunct before a refused conjunct.**
Input: `(and (> (list-length xs) 0) (= (list-head xs) (ok result)))`. Behaviour: conjunct 0 proved alone; conjunct 1 `asserted`; the run-time post keeps the short-circuit order. Channel: contract and trust. Cite: §4.3.

**E6. A refused guard before an admitted conjunct that needs it for truth.**
Input: `(and (image-ok? result) (>= (first (first result)) 1))`, where the second conjunct holds only when the first does. Behaviour: the solver may answer UNSAFE on conjunct 1. If the refutation rule holds, that is a genuine refutation: in the model, either `image-ok?` is false or conjunct 1 is false, so the post is false. The author must strengthen the body, or move the fact into the refused conjunct. Channel: contract. Cite: §4.3 reason 2. Spec is silent on a warning (intentional; the refutation names the function, and POST-CONJ-DIAG-1 names the conjunct).

**E7. `and` under `let`, `if` or `match`.**
Input: `(let [(h (img-header result))] (and … …))`, `(if c (and a b) d)`, or `(match result ((Success out) (and …)) ((Error e) true))`. Behaviour: one conjunct; refused whole if any part is refused, as today. Strict immutability makes `let`-distribution a valid rewrite, and `if` and `match` arms can be split as implications. Spec is silent (intentional, Rev 2 scope).

**E8. `=>` with a conjunctive consequent, and `not` or `or`.**
Input: `(=> p (and a b))`, `(not (or a b))`. Behaviour: one conjunct each. `(=> p (and a b))` to `(and (=> p a) (=> p b))` is sound and is a natural later widening. Spec is silent (intentional).

**E9. A guard refusal on one conjunct.**
Input: a post with a whole-structure `=` on a `bytes` operand in one conjunct and a scalar fact in another. Behaviour: the whole contract is refused, cause `contract-post-outside-fragment`, label `guard:whole-structure-eq`, as today. Spec is silent (intentional: the guards protect against solver sort crashes, and a per-conjunct guard needs its own review).

**E10. A refused return-refinement conjunct.**
Input: a return alias whose predicate is outside `Σ_auto`, and an author post that translates. Behaviour: author conjuncts proved; the refinement conjunct is `asserted` with origin `return-refinement`. Channel: trust. **Gap (flag):** an alias predicate has no run-time residue (`LLMLL.md §3`, "Channel distinction"), so this `asserted` conjunct has no run-time assertion behind it. The same gap exists today for a whole-post fallback with a folded refinement. The report says `asserted (no run-time check)` for this origin.

**E11. A call-site sort guard drops one conjunct.**
Input: a callee post with a datatype term in one conjunct, called where the result binder is not datatype-sorted. Behaviour: that conjunct is not assumed; the others are. The call is not assumed in full, so the CALLEE-POST-UNASSUMED-1 mark applies to the caller's failing constraints. The edge's assumed level is the meet over the conjuncts assumed. Channel: contract. Cite: `FixpointEmit.hs:4655-4664`; §4.4 items 1 and 2.

**E12. A stale per-conjunct record.**
Input: the body changes after a partly proved SAFE run. Behaviour: the hash drifts, and every `verified` conjunct entry reads `asserted`. Channel: trust. Cite: `LLMLL.md §4.4.1` read rules, applied per entry.

**E13. A partial operation after a refused guard (well-definedness).**
Input: `(and (refused-guard r k) (= (map-get r k) 0))`. Behaviour: conjunct 1 can be proved true over all states, including states where `k` is absent. Its record says "proved as part of the post". The post is not stripped, so the run-time short-circuit still guards `map-get`. Channel: contract (truth); well-definedness is not checked. Cite: §4.3; CLAUSE-WELLDEF-1. A single-conjunct `mapdef.llmll` shows the same gap without the split.

**E14. Degenerate `and`.**
Input: `(post (and))`, `(post (and (>= result 0)))`, or `(post (and (>= result 0) (and)))`. Behaviour: `check` and `verify` reject each with `operator 'and' expects 2 args`, exit 1 (measured on 0.35.1). No split runs. If an internal fold ever builds such a node, `conj` gives `[]` or `conj(a)` (§4.1). Channel: type. Cite: `TypeCheck.hs:129`.

**E15. A partly admitted callee whose body falls back.**
Input: `pos-or-one` with a body outside `Σ_auto`. Behaviour: the callee falls back with cause `body-outside-fragment`, writes no `conjuncts` record, and is `asserted`. Callers assume `Q_A` at level `asserted`, so a SAFE caller is `asserted` through that edge. A caller's UNSAFE answer falls back (the call is not assumed in full). Channel: trust. Cite: §4.4 item 4.

**E16. A caller that needs a refused conjunct.**
Input: `rneed.llmll`. Behaviour: the callee is partly proved. `use-it` assumes `result ≥ 0` and needs `result ≥ 1`, so its VC is UNSAFE. The failing constraint carries the mark, so `use-it` falls back. It is not refuted. Neither Option A nor Option B makes it `verified`. Channel: trust. Cite: §3; §4.2 verdicts.

**E17. Two calls of one callee in a partly proved function.**
Input: a partly proved function whose admitted conjunct fails only through two unrelated calls to one callee. Behaviour: `applyAbstractionVerdict` reclassifies it to `abstraction-unsafe`, all conjuncts `asserted`, not refuted. Channel: trust. Cite: `AbstractionVerdict.hs:87`, `:119`; §4.6.

## 6. Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| `P ∧ path ∧ Γ_calls ∧ result = ⟦B⟧ ⟹ ⋀_{k∈A} q_k` | contract | QF-LIA within `Σ_auto`, auto-discharged by liquid-fixpoint. Same class as today's body VC: each `q_k` passed `exprToPred`. | `LLMLL.md §5.3.3`, `§5.3.4`; `FixpointEmit.hs:1845`, `:2017` |
| Caller assumes `⋀_{k∈S} q_k[args, r]` | contract (ASSUME polarity) | QF-LIA within `Σ_auto` | `LLMLL.md §5.3.4` compositional chain; `FixpointEmit.hs:4714` |
| Each `c_k`, `k ∈ R` | trust (run-time assertion under `--contracts=full` and `unproven`) | Outside `Σ_auto`; not routed to Lean in this row. A later row could route each refused conjunct as its own `?proof-required` obligation. | `LLMLL.md §5.3.5` |
| Well-definedness of each clause | not checked by this row | Owned by CLAUSE-WELLDEF-1 | §4.3 |

No obligation leaves its current fragment. No nonlinear or quantified obligation is introduced.

## 7. Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: conjunct flattening; the partial case in the body-VC entry (`:1586-1600`); `FallbackContractPostPartial` (`:200-264`); per-conjunct `cvPostAssumption` with the assumed index set `S` (`:4648-4690`); the "assumed in full" input to the CALLEE-POST-UNASSUMED-1 mark; `erPartlyProvedFns` and per-conjunct verdict inputs in `EmitResult` (`:292`, `:1104`).
- `compiler/src/LLMLL/AbstractionVerdict.hs`: the union at `:87`; `reclassifyEmit` at `:119`.
- `compiler/app/Main.hs`: every reader in §4.6; the SAFE path that writes `conjuncts`; the footer; the `--json` keys.
- `compiler/src/LLMLL/ObligationAssembly.hs`: the `partly_proved` marker on constraint obligations.
- `compiler/src/LLMLL/PatchApply.hs`: `notProvedMessage` by cause.
- `compiler/src/LLMLL/VerifiedCache.hs`: `conjuncts` codec; per-entry read rules.
- `compiler/src/LLMLL/Syntax.hs`: a per-conjunct evidence type beside `EvidenceRecord`.
- `compiler/src/LLMLL/TrustReport.hs`: `post_conjuncts`, `partly_proved`, `assumed_callee_conjuncts`, `partly_proved_fns`; the per-edge fold in `enrichEntry`; text rendering; `trustReportEmitVersion`.
- `compiler/src/LLMLL/ProofArtifact.hs`, `docs/proof-artifact.schema.json`: the new `fallback_reason` value, its description, `partly_proved`, `proof_artifact_version`; a test that `mkFnRecord` accepts `refuted` with the new cause.
- `docs/llmll-trust-report.schema.json`: the four rows of §4.7.
- `scripts/fallback_census.py`: the new cause in its own bucket.
- `LLMLL.md §4.4.1`, `§4.4.3`, `§4.4.4`, `§5.3.4` (body VC, contract stripping, strict core); `docs/getting-started.md:567`. Doc-lead's slot after the engineer ships.
- `docs/compiler-team-roadmap.md` row text for POST-CONJ-SPLIT-1 (§2.1 findings). Doc-lead's slot.
- No new builtin, construct, FFI tier or capability.

**Acceptance tests.** `split.llmll` (E1), `bad.llmll` (E4), `rneed.llmll` (E16), the original Y4M `next-p` contract (§2.2), an abstraction case (E17), and the byte-identical `.fq` sweep (§4.7).

## 8. Risks and open questions

1. **New refutations in existing programs.** Classify: verification-ergonomics. A function that was silently `asserted` can become refuted (E4, E6), and its file then exits 1. Cite: §4.2. Bite: complicates. The census lists every file whose verdict changes before the release.
2. **A missed reader of `erBodyFaithfulFns`.** Classify: soundness. If `refutedSet` or `applyAbstractionVerdict` misses the partly proved list, a false conjunct is silently `asserted`, or a may counterexample is reported refuted. Cite: §4.6. Bite: blocks, if missed. The acceptance tests `bad.llmll` and E17 close it.
3. **The release order.** Classify: soundness. If the split ships before CALLEE-POST-UNASSUMED-1, every caller of a partly proved callee can be falsely refuted (`rneed.llmll`). Cite: §3. Bite: blocks. The split's plan names the dependency.
4. **Option B changes what a caller's level means.** Classify: spec-drift. The `enrichEntry` fold changes from a flat fold to a per-edge fold. Cite: `TrustReport.hs:1563-1604`. Bite: complicates. For a callee that is not partly proved the result is unchanged, and a unit test asserts this.
5. **Unknown scale.** Classify: scope. Nobody has measured how many corpus functions have a partly admitted post and an in-fragment body. The census cannot tell today, because a refused post hides the body decision (§2.1). Bite: matters at scale only. The engineer's first step is that count.
6. **Well-definedness exposure.** Classify: soundness of run-time claims. A `verified` conjunct can hold an undefined partial operation (E13). Cite: §4.3. Bite: complicates; contained by the no-stripping rule and the record wording until CLAUSE-WELLDEF-1.
7. **E10 asserted conjunct with no run-time check.** Classify: spec-drift. Pre-existing for whole-post fallback. Bite: report wording only.

## 9. Decisions for the user

1. Split, after CALLEE-POST-UNASSUMED-1. Recommendation: yes (§3, §4.1 to §4.3).
2. Option A or Option B for the caller tier. Recommendation: B, with the specification of §4.4. The reviewer agrees.
3. Keep weakness and CDP unvalidated on partly proved functions, or run the candidates against `A`. Recommendation: keep them unvalidated. A trivial body that satisfies `A` says `A` is weak. That is useful, but it is a separate report surface.
4. File PRE-CONJ-DROP-1 (measurement first) and POST-CONJ-DIAG-1 (re-solve on UNSAFE only, outer refusing call) as rows.
5. Correct the POST-CONJ-SPLIT-1 row text (§2.1) and add the Y4M F4 citation.
6. Route the missing `check`-time warning for a refused clause (§2.2). No row is proposed here.

---

## Appendix — Professor review log

The standalone professor review of Rev 1 is folded here. The source file stays at `docs/design/post-conj-split-professor-review.md` until the user settles this proposal. At settlement, the documentation-lead archives it under DOC-CONSOLIDATE §M2.

**Source:** `docs/design/post-conj-split-professor-review.md` (reviewed 2026-11-02, against Rev 1; reviewer: Lead Consultant for Formal Language Design). One round. Verdict: "Accept with changes. Fix the false refutation (P1) first, as its own row." The reviewer measured `whole.llmll`, `rneed.llmll` and `mapdef.llmll` on 0.35.1.

### P1. The false refutation is a separate defect (blocks)

**Finding.** `split.llmll` is a false refutation today. The cause is not the conjunct structure. `refutedSet` accepts an UNSAFE answer over a dropped callee post, which is a may counterexample (Godefroid et al., POPL 2010). The split does not remove it: `whole.llmll`, `rneed.llmll` and a sort-guard drop remain. The W-BODY-FALLBACK text "its post is assumed" is false for `contract-post-outside-fragment`.

**Outcome.** Accepted. The user files CALLEE-POST-UNASSUMED-1 as its own row, and it ships first. That row owns the mark, the fallback cause, the W-BODY-FALLBACK text by cause, and the `LLMLL.md:633` wording. Rev 2 §3 states the dependency, and §2.3 separates the effect of each row on each witness.

### P2. The hypotheses are not complete (blocks)

**Finding.** Rev 1 §4.2 said the hypotheses are complete. They also include callee posts, which can be dropped. `applyAbstractionVerdict` reads only `erBodyFaithfulFns`. Five other readers take that list.

**Outcome.** Accepted. §4.2 states the rule: refuted only when every hypothesis of every failing constraint is the authored one. §4.6 gives a decision for each reader. A grep of this worktree found five more readers in `Main.hs` than the review listed (`:1492`, `:1508`, `:1531`, `:1571`, `:1747-1749`, `:1761`). `uncheckedCallPres` (`:1508`) takes the union.

### P3. The totality argument is false (complicates)

**Finding.** `map-get` and `bytes-get` are admitted and have run-time preconditions. `mapdef.llmll` is `verified`, but its post calls `error` at run time. Truth and well-definedness are different obligations (Dafny, SPARK). The split increases exposure.

**Outcome.** Accepted. §4.3 removes Rev 1 reason 1 and keeps the two obligations apart. Per-conjunct stripping is forbidden until CLAUSE-WELLDEF-1, which the user files now. The per-conjunct wording is "proved as part of the post". E13 is the new edge case.

### P4. Option B is correct but under-specified (complicates)

**Finding.** Option B, by three arguments. Hybrid type checking (Flanagan, POPL 2006; Knowles and Flanagan, TOPLAS 2010): the run-time check of `Q_R` sits in the callee's post, so the caller needs no cast. Gradual verification (Bader, Aldrich and Tanter, VMCAI 2018; Wise et al., OOPSLA 2020): a caller that uses only the precise part needs no inserted check. Blame (Findler and Felleisen, ICFP 2002; Wadler and Findler, ESOP 2009): a failure of `Q_R` blames the callee. Five gaps: the meet per call site after sort guards; the per-edge fold; a callee whose body falls back; recorded indices; the `--strict-verified-core` interaction.

**Outcome.** Accepted. §4.4 chooses Option B and specifies each of the five items. An edge with an empty assumed set keeps today's clause-level rule, which fails closed. E15 covers the body-fallback callee. `post_assumed_level` from Rev 1 is replaced by the per-edge `assumed_callee_conjuncts`.

### P5. `body_faithful: false` covers two states (complicates)

**Finding.** A partly proved function had a body VC, can be refuted, and is not body-faithful. A refuted partly proved function carries `refuted: true` and a non-null `fallback_reason`, a combination that does not exist today.

**Outcome.** Accepted. §4.5 defines clause `body_faithful` as "a body VC proved the whole clause" and adds the `partly_proved: true` marker. §4.6 and §4.7 add a `mkFnRecord` test and change the proof-artifact description. Citation correction: "Null iff body-faithful" is at `docs/proof-artifact.schema.json:76`, not `:17`.

### P6. Flattening only through `and` (accept)

**Finding.** Accept for this revision. Specify `(and)` and `(and a)`. The label for `split.llmll` is `app:list-empty`, which hides `all-pos?`. POST-CONJ-DIAG-1 should report the outermost refusing user call.

**Outcome.** Accepted. §4.1 and E14: the type checker rejects both forms on 0.35.1 (`operator 'and' expects 2 args`), and `conj` is defined for every arity. §4.8 adds the outer refusing call to POST-CONJ-DIAG-1.

### P7. Schema and version plan (accept with one condition)

**Finding.** The versions are correct, and `checker_soundness_version` stays `"6"`. Condition: the byte-identical `.fq` sweep covers call sites. The trust-report schema needs rows for the new keys.

**Outcome.** Accepted. §4.7 states the call-site condition and lists four schema rows. Citation correction: `docs/llmll-trust-report.schema.json:103` is `over_annotation`. `TrustEntry` is open (`additionalProperties: true`, line 150), and the top-level object is closed (line 9). So the top-level `partly_proved_fns` row is required, and the nested arrays use closed item objects.

### P8. PRE-CONJ-DROP-1 (accept with the P1 rule)

**Finding.** Correct, on the same may/must rule. A dropped pre conjunct can guard a partial body operation. Measure before claiming a gain.

**Outcome.** Accepted. §4.8 writes the row on the stated rule and makes a corpus count its first step.

### P9. POST-CONJ-DIAG-1 (revise the plan)

**Finding.** One constraint per conjunct multiplies the cost of every run. Re-solve only on UNSAFE.

**Outcome.** Accepted. §4.8 re-solves each failing constraint per admitted conjunct after UNSAFE only.

### Open questions from the review

1. *Justify or remove the totality claim of Rev 1 §4.3.* Removed (§4.3).
2. *State the refutation rule with the callee-hypothesis condition, and decide each reader.* Stated (§4.2); decided (§4.6).

### Convergence and divergence

The language-team and the reviewer reached Option B by different paths. The language-team argued from nc-005/nc-006 (a caller's proof rests only on the facts it assumed). The reviewer argued from hybrid checking, gradual verification and blame. No divergence remains.
