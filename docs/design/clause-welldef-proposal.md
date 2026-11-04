---
name: clause-welldef-proposal
title: "CLAUSE-WELLDEF-1: prove that each partial operation in a pre or post is defined where the program evaluates it"
status: "Rev 2, DRAFT 2026-11-03; folds the professor review (W1-W10); awaiting user settlement. NOT SETTLED."
date: 2026-11-03
author: language-team
rows: "CLAUSE-WELLDEF-1 (G1, DECIDE). Prerequisite: BYTES-SET-CLAUSE-LEN-1 (G1, PLAN, filed), ships first. Shares the verdict path with CALLEE-POST-UNASSUMED-1 (in build), which ships first. Ships before CONTRACTS-ENTRY-STRIP-1 (G3, PLAN, filed). Its run-time guard depends on PRE-FAIL-EXIT-1 (G2, DECIDE, filed). Referenced by POST-CONJ-SPLIT-1 (§4.3, §4.5, E13). Supersedes the decline of option (b) in docs/design/contract-position-reads-disposition.md."
consumers: [user, professor, compiler-engineer, documentation-lead]
reviews: "docs/design/clause-welldef-professor-review.md (Rev 1, accept with changes; W1 and W2 blocking). Folded in Rev 2."
---

# CLAUSE-WELLDEF-1: prove that each partial operation in a pre or post is defined where the program evaluates it

**Status: Rev 2, DRAFT 2026-11-03. Not settled.** All measurements are on `llmll 0.35.1` (the main checkout build, liquid-fixpoint 0.9.6.3.7). Each file ran alone under the memory and time watchdog `watch.py`. The Rev 1 witnesses are in /private/tmp/claude-501/-Users-burcsahinoglu-Documents-llmll/0b4801a1-2e16-4efa-838b-2282560e27b9/scratchpad/cwd1/. The professor's witnesses (xm3, `bl.llmll`, `rb.llmll`) are in /private/tmp/claude-501/-Users-burcsahinoglu-Documents-llmll/0b4801a1-2e16-4efa-838b-2282560e27b9/scratchpad/profrev/. The Rev 2 witnesses and the spec-local emulation (§7.2) are in /private/tmp/claude-501/-Users-burcsahinoglu-Documents-llmll/0b4801a1-2e16-4efa-838b-2282560e27b9/scratchpad/cwd2/.

## Rev 2 changes

| Finding | Severity | What Rev 2 does | Section |
|---|---|---|---|
| W1. False `ill-defined` from dropped hypotheses | blocking | Lists every site where a `wd-*` constraint can lack a fact that a run guarantees. Each site gets one of three treatments: a prerequisite row, no emission, or a mark. States the parity rule that keeps the list complete. | §4.3, E17-E19 |
| W2. Verdict combination not specified | blocking | Partitions failing ids by clause tag. States the per-function rule and the precedence. Gives a 13-row table with one named test per row. | §4.4 |
| W3. Reversal rests on the weaker witness | complicates | §2.3 now leads with `nc-004` (`LLMLL.md:22`) and the xm3 witness. It states that stripping shipped in v0.8.1b, before the disposition. xm2 stays as the call-site case, and the text says that it fail-stops. | §2.3 |
| W4. Wrong Dafny citation | complicates | Removes the citation. Records the body-context rule as a deliberate divergence from Dafny, with the cost in each direction. Drops `wd-post` for body-fallback functions. Answers the review's open question by measurement. | §4.2, §4.9, §7.2 |
| W5. Stripping proof incomplete | complicates | Replaces it with an induction over source order. Records a conjunct's dependency on an earlier unverified conjunct. | §4.7 item 4 |
| W6. Proof artifact has no soundness epoch | complicates | Adds `checker_soundness_version` to the proof artifact and to `composed_versions`. | §4.8 |
| W7. `WD` walk must share the `exprToPred` traversal | complicates | Defines one function that returns the term and its obligations. Lists each `exprToPred` arm and its `WD` rule, with line numbers. Names the `<=>` arm as the one place where the shared traversal must not reuse the desugaring. | §4.1.1 |
| W8. Context rules correct | no change | States that `wd-pre` is always complete after W1, and removes that case from the verdict table. | §4.3, §4.4 |
| W9. Lemma needs the junk-independence step | minor | Adds the step and its induction. Claims the consequence for refutation localization. | §4.5 |
| W10. Smaller points | minor | "23 of 41 files emulated", and why. "Marker on mutants not measured". Division by zero raises `ArithException`. The `refuted` text says that the counter-model may be at an undefined point. | §7.1, §4.6, §4.4 |
| Coordinator: CALLEE-POST-UNASSUMED-1 | — | Positions `ill-defined` and `clause-welldef-unproved` against the new cause `callee-post-unassumed`. | §4.4, §4.7 |

The professor and this proposal converge on option (a), on the context rules and on the separate hard verdict. Rev 2 diverges from the review in one place. The review asks for a mark on a refused parameter refinement (W1(b)). Rev 2 emits no `wd-*` constraint for such a function instead. The function already falls back whole, so a mark would only add a second fallback cause (§4.3, site S4).

## Summary

1. **Recommendation: option (a), a well-definedness obligation for each admitted partial operation in a clause.** Three builtins need it: `map-get`, `bytes-get` and `bytes-set`. The obligation is the builtin's own precondition, the same term that the body emits as a `call-pre:<builtin>` obligation today.
2. **The obligation assumes the run-time evaluation context.** An earlier operand of `and` is assumed true. An earlier operand of `or` is assumed false. The antecedent of `=>` is assumed true. A `match` arm assumes its constructor test. This matches the generated Haskell (`CodegenHs.hs:2426-2431`, `esLazyOps` at `:3899-3900`).
3. **A `post` obligation may assume the body's path facts.** This is a deliberate divergence from Dafny, which checks a specification without the body. The RFC 826 swarm posts depend on it (§4.2, §7.2).
4. **A clause is `verified` only when its truth and its well-definedness are both proved.**
5. **A failed obligation over complete hypotheses is a new hard verdict, `ill-defined`.** It is not `refuted`. `verify` exits 1.
6. **A failed obligation over marked hypotheses is a fallback,** with cause `clause-welldef-unproved` when only `wd-*` ids fail. §4.4 gives the full rule beside `abstraction-unsafe` and `callee-post-unassumed`.
7. **The run-time clause check is guarded.** A partial operation outside its precondition inside a clause reports a violation that names the clause.
8. **`checker_soundness_version` changes from `"6"` to `"7"`, and the proof artifact records it.**
9. **Corpus impact is one change of exit status.** It is `f` in `scripts/doc-claims/contract-read-oob.llmll`, which exists to show this defect.
10. **The 2026-07-12 disposition is reversed.** Its soundness paragraph contradicts `nc-004` and ignores `--contracts=unproven` stripping (§2.3).

---

## 1. Restatement

`exprToPred` reflects `map-get`, `bytes-get` and `bytes-set` as total array terms (`Map_select`, `Map_store`). At run time the same operations call `error` outside their precondition. So `verify` can prove a clause that the built program cannot evaluate. The question is whether `verify` proves clause well-definedness as an obligation of its own, or refuses such terms in clauses. The proposal must also say what a failed obligation reports, how it combines with the other verdicts, how the run-time check of a clause behaves, and what changes in the records.

## 2. Context located

### 2.1 Artifacts

1. `docs/compiler-team-roadmap.md`, row CLAUSE-WELLDEF-1 (G1): the DECIDE cell this proposal answers.
2. `docs/compiler-team-roadmap.md`, rows BYTES-SET-CLAUSE-LEN-1, CALLEE-POST-UNASSUMED-1, CONTRACTS-ENTRY-STRIP-1, PRE-FAIL-EXIT-1, CTOR-FIELD-SORT-1: filed rows that this proposal orders against (§4.7).
3. `docs/design/clause-welldef-professor-review.md`: the review that Rev 2 folds.
4. /private/tmp/claude-501/-Users-burcsahinoglu-Documents-llmll/0b4801a1-2e16-4efa-838b-2282560e27b9/scratchpad/callee-post-unassumed-plan.md, "The verdict rule": the shared per-function rule.
5. `docs/design/post-conj-split-professor-review.md` P3, P8: truth and well-definedness are separate obligations; a failure is a disproof only over authored hypotheses.
6. `docs/design/post-conj-split-proposal.md` Rev 2 §4.3, §4.5, E13: no per-conjunct stripping until this row ships.
7. **`docs/design/contract-position-reads-disposition.md` (settled 2026-07-12): the prior decision on this topic.** This proposal reverses it (§2.3).
8. `LLMLL.md:22` (`nc-003`, `nc-004`): a verified contract holds for all well-typed inputs under the call-by-value semantics of §4.7.
9. `docs/design/byte-io-proposal.md` line 414: "No pure operation is partial without a `pre` or a `Result`."
10. `compiler/src/LLMLL/FixpointEmit.hs:3736-3908` (`exprToPred`): the clause vocabulary.
11. `FixpointEmit.hs:4829-4847`, `:4854-4876`, `:4944-4957`: the body arms of `bytes-get`, `bytes-set` and `map-get`. Each emits its precondition as a PROVE obligation. The `bytes-set` arm also assumes a `lemma` part, `bytesLen(r) = bytesLen(b)`.
12. `FixpointEmit.hs:6107-6181` (`injectRangeFacts`), `:6194-6216` (`injectBoolValRangeFacts`): per-occurrence ground facts over LHS and RHS terms.
13. `FixpointEmit.hs:6381-6416` (`bytesLenParamPre`, `paramRefinementPre`, `augmentContractPre`), `:6441-6476` (`returnRefinementPost`, `augmentContractPost`): parameter and return facts enter the effective pre and post.
14. `FixpointEmit.hs:1015-1060`: FQ-FREEVAR-GUARD-1 routes a function whole when one of its constraints names a free symbol.
15. `compiler/src/LLMLL/AbstractionVerdict.hs:77-112` (`applyAbstractionVerdict`, rules 1-3); `compiler/app/Main.hs:1654-1676` (`avOut`, `measureNotDecreasingSet`, `refutedSet`).
16. `compiler/src/LLMLL/Contracts.hs:180-190` (`instrumentClosure`), `:232-243` (`filterContracts`), `:314-348` (`wrapPre`, `wrapPost`).
17. `compiler/src/LLMLL/CodegenHs.hs:543-554`, `:578-581`, `:896-898`, `:2423-2437`, `:3899-3900`: the run-time builtins, `emitOp` and the lazy operators.
18. `compiler/src/LLMLL/VerifiedCache.hs:398-399` (`checkerSoundnessVersion = "6"`); `docs/proof-artifact.schema.json:7-31` (`composed_versions` has no soundness stamp).
19. `CHANGELOG.md` §v0.8.1b (2026-05-01): the body-faithful stripping rule under `--contracts=unproven`.

### 2.2 Drift found while reading

- **D1. `--contracts=unproven` does not strip a verified post in the entry module.** Filed as CONTRACTS-ENTRY-STRIP-1 (G3, PLAN). It ships after this row (§4.7).
- **D2. `LLMLL.md §13.12` states the `bytes-set` precondition as `0 ≤ i < n`.** The run time and the body obligation also require `0 ≤ v ≤ 255` (`CodegenHs.hs:553`, `FixpointEmit.hs:4861-4864`). `LLMLL.md:776` and `:1134` state the range. The table row (`:3343`) should move to match.
- **D3. The disposition's soundness paragraph is false under `--contracts=unproven`, and it was false when written.** §2.3.
- **D4. The run-time message misleads in a clause.** `map-get` on an absent key prints "map-has is the required pre" (`CodegenHs.hs:581`). In a clause, the defect is in the clause.
- **D5 (new). The clause side has less sealed-builtin knowledge than the body side.** The body `bytes-set` arm assumes length preservation (`FixpointEmit.hs:4865-4870`). The clause arm (`:3825-3826`) does not. Filed as BYTES-SET-CLAUSE-LEN-1. Today it causes a false `refuted` (`bl.llmll`). Under this proposal it would also cause a false `ill-defined`. So it is a prerequisite (§4.3, site S1).
- **D6 (new; filed 2026-11-03 as `PAIR-REFINE-ENTRY-1`). A refinement alias at a pair component is neither assumed nor proved.** Witness cwd2/pc3.llmll: `h [p: (Idx, int)]`, where `Idx` is `0 ≤ i < 4`, and a caller `c` with body `(h (pair 9 n))`. `check` and `verify` pass, exit 0. cwd2/pc2.llmll: a post `(< (first p) 4)` on the same `h` is `refuted`. So the component refinement has no effect in the verifier. `resolveAllRefinements` (`FixpointEmit.hs:6313-6317`) returns nothing for a `TPair`. §3.4.1 introduces a refinement at "concrete introduction sites", and the spec does not say whether a pair component is one. This is a candidate row for the coordinator. It is not a dropped hypothesis for this proposal (§4.3, site S7).

### 2.3 Why the 2026-07-12 disposition is reversed

The disposition makes two claims. First, a `verified` post cannot be silently false, because "the generated program's contract assertion fail-stops before any value flows". Second, a `refuted` verdict cannot contradict a satisfiable contract. It calls the residual defect a matter of quality.

**The deciding fact is the language's own soundness statement.** `LLMLL.md:22` (`nc-004`) says that a verified contract holds for all well-typed inputs under the call-by-value semantics of §4.7. A clause whose evaluation calls `error` does not hold under that semantics. Chalin calls this reading "strong validity" (ICSE 2007), and JML adopted it. So a `verified` record on `mapdef.llmll` contradicts `nc-004` today, in every `--contracts` mode.

**Stripping removes the fail-stop.** `--contracts=unproven` strips exactly the posts that are verified and body-faithful (`Contracts.hs:240-242`). Witness xm3 (profrev/xm3/): `mklib.llmll` holds `mk`, with post `(= (map-get result 3) 0)` and body `(map-empty)`. `verify` reports the post `verified`. `app.llmll` prints `(if (map-has (mk n) 3) "key 3 present" "key 3 absent")`. Built with `--contracts=unproven`, the program prints `key 3 absent` and exits 0. The program continues with a value that the verified post excludes. Confirmed on v0.35.1.

**The premise was false on the day it was written.** The body-faithful stripping rule shipped in v0.8.1b (`CHANGELOG.md` §v0.8.1b, 2026-05-01), ten weeks before the disposition. The disposition did not mention `--contracts=unproven`. So the reversal corrects an error. It does not respond to a new fact. The disposition's own revisit trigger (frequency in agent corpora) has not fired, and the reversal does not rest on it.

**The call-site case (xm2) is a second, weaker defect.** `app.llmll` holds `c`, with body `(g (mk n))`, where `g` has pre `(>= (map-get m 3) 0)`. `verify` discharges `g`'s pre at the call from `mk`'s post. The run stops in `g`'s pre with the `map-get` message, under both `--contracts=unproven` and `--contracts=full`. So xm2 fail-stops. It shows a false call-site discharge and a misattributed failure. It does not show a value that flows past a false claim.

**POST-CONJ-SPLIT-1 increases the exposure.** A conjunct gets its own `verified` record, and per-conjunct stripping needs this obligation (§4.7 item 4).

## 3. Inventory

### 3.1 Every clause-admissible term, by run-time behaviour

"Admitted" means `exprToPred` returns a term, so the clause can be `verified`. A refused term makes the whole clause `asserted`. That clause still runs at run time.

| Term | Admitted in a clause? | Run time | Logic | Exposure | Witness |
|---|---|---|---|---|---|
| `map-get m k` | Yes (`FixpointEmit.hs:3845-3848`). Not on a literal `(map-empty)` (`:3840`). | `error` when `k` is absent (`CodegenHs.hs:578-581`) | `Map_select(m$val, k)`, total. On `map-empty`, the value array is `Map_default 0`. | pre, post | `w1_mappost`, `w3_mappre`, xm2, xm3 |
| `bytes-get b i` | Yes (`:3823-3824`) | `error` unless `0 ≤ i < len` (`CodegenHs.hs:545-548`) | `Map_select(b, i)`, total | pre, post | `w2_bytespost` |
| `bytes-set b i v` | Yes (`:3825-3826`) | `error` unless `0 ≤ i < len` and `0 ≤ v ≤ 255` (`CodegenHs.hs:550-554`) | `Map_store(b, i, v)`, total, no length fact (D5) | pre, post | `w12_bytesset`, `bl.llmll` |
| `/`, `mod` | Only with a numeral divisor above 0, or a ground divisor that folds above 0 (`:3788`, `GuardClassifier.hs:342-352`) | Haskell `div`, `mod` (`CodegenHs.hs:2434-2437`) | SMT `div`, `mod`; agrees for a positive divisor | none in the logic | — |
| `/`, `mod` with another divisor; `rem`, `^`, `**` | No (`:3790`) | `ArithException` (`divide by zero`) for a zero divisor | — | run time only | `w5_divclause` |
| `unwrap` | No (no case) | `error` on `Error` (`CodegenHs.hs:896-898`) | — | run time only | `w6_unwrap` |
| `map-get` or `map-has` on a literal `(map-empty)` | No (`:3839-3840`) | `map-get` calls `error` | — | run time only | — |
| `list-head`, `list-tail`, `list-nth`, `string-to-int` | No | Total: they return `Result` | — | none | — |
| `string-char-at`, `string-slice` | No | Total: they clamp | — | none | — |
| `first`, `second`, pair construction | Yes (`:3812-3814`) | Total | Total selectors | none | — |
| `match` on a variable | Yes (`:3879-3907`) | `case`; `check` rejects a non-exhaustive match | Selectors under constructor tests | none | `w13_match` |
| `min`, `max`, `abs` (marked), `compare`; the three lengths; `map-has`, `map-put`; `ok`, `err`, `is-ok`, constructors; literals | Yes | Total | Total | none | — |
| A user function call | No (POST-CALL-XMOD-1 is open) | The callee's own pre check runs inside the clause | — | run time only | — |
| `if`, `let`, `lambda` | No (`:3908`) | — | — | none | — |

So exactly three admitted builtins are partial at run time and total in the logic: `map-get`, `bytes-get` and `bytes-set`. The n-ary `and` cannot occur: `check` rejects `(and a b c)` (`w8_nary`).

### 3.2 Pre, post and body

- **Body: already covered.** A partial builtin in a body emits its precondition as a PROVE obligation, tagged `call-pre:<builtin>` (`FixpointEmit.hs:4944-4957` for `map-get`). A failure is `refuted` (`w7_bodyget`). Every body read must first prove presence or bounds, so a body term never reads a junk value.
- **Post: exposed.** `mapdef.llmll`, `w1_mappost`, `w2_bytespost` and `w12_bytesset` are `verified` and write a sidecar. Each built program stops when it evaluates the post. xm3 shows the stripped case, where the program does not stop.
- **Pre: exposed, in two ways.** First, evaluating the pre can stop the program before the check reports (`w3_mappre` prints the `map-get` message, not `Precondition violated in g`). Second, a caller can discharge an ill-defined pre from an encoding artefact (xm2).
- **The guarded idiom works at run time.** `w14_shortcircuit`: `(pre (and (map-has m 3) (> (map-get m 3) 0)))` on `(map-empty)` reports `Precondition violated in g2`. The `=>` form passes.

## 4. Design proposal

### 4.1 The obligation

Each partial builtin `f` has one precondition `π_f`, over the reflected arguments:

```
π_map-get(m, k)      =  Map_select(m$has, k) = 1
π_bytes-get(b, i)    =  0 ≤ i  ∧  i < bytesLen(b)
π_bytes-set(b, i, v) =  0 ≤ i  ∧  i < bytesLen(b)  ∧  0 ≤ v  ∧  v ≤ 255
```

These are exactly the `pre` terms of the three body arms (`FixpointEmit.hs:4836-4844`, `:4861-4864`, `:4952`). **Rule: the body arm and the clause obligation read `π_f` from one table.** A second copy can drift, and that has happened before (`sealedAxiomBuiltins`, `FixpointEmit.hs:352-362`).

`WD(C, e)` is the set of obligations of a clause expression `e` under a context `C`. `C` is a list of formulas that are true when the program evaluates `e`:

```
WD(C, (and a b))   = WD(C, a) ∪ WD(C ∧ ⟦a⟧, b)
WD(C, (or a b))    = WD(C, a) ∪ WD(C ∧ ¬⟦a⟧, b)
WD(C, (=> a b))    = WD(C, a) ∪ WD(C ∧ ⟦a⟧, b)
WD(C, (not a))     = WD(C, a)
WD(C, (<=> a b))   = WD(C, a) ∪ WD(C, b)
WD(C, (match x ((K_i ps_i) e_i)…))
                   = ⋃_i WD(C ∧ test_i ∧ ⋀_{j<i} ¬test_j, e_i[sel/ps])
WD(C, (f a_1 … a_n)), f partial
                   = ⋃_j WD(C, a_j) ∪ { C ⟹ π_f(⟦a_1⟧, …, ⟦a_n⟧) }
WD(C, (g a_1 … a_n)), g total
                   = ⋃_j WD(C, a_j)
WD(C, x) = WD(C, literal) = ∅
```

`⟦·⟧` is `exprToPred`. A multi-clause post is the left-nested `and` of its clauses in source order, as SRC-CONJ-1 folds it. So an earlier `post` form is context for a later one. `<=>` gives no context, because the generated `==` on `Bool` evaluates both operands (`CodegenHs.hs:2431`).

The folded refinements are not part of `e`. The DEF-RET return refinement and the `bytes[n]` return length are appended to the effective post (`FixpointEmit.hs:6468-6476`). The run-time check does not evaluate them. So `WD` walks the authored clause only, and the folded conjuncts enter neither `C` nor `H`.

#### 4.1.1 One traversal for the term and its obligations (W7)

**Rule: one function returns both the term and the obligations.** Its shape is `exprToPredWD :: Ctx -> Expr -> Maybe (FQPred, [Obligation])`. `exprToPred` becomes `fmap fst . exprToPredWD []`. A new admitted form then cannot get a term without an obligation. The table maps each arm of `exprToPred` to its `WD` rule.

| `exprToPred` arm | Lines | `WD` rule |
|---|---|---|
| `EVar`, literals, string literal | `:3741-3752` | none |
| Marked `min`, `max`, `abs` (`intBuiltinTag`) | `:3756-3757` | total: union over the arguments |
| Bool bridge: `map-get` against a bool literal, either order | `:3768-3772` | the `map-get` rule applies to the inner `map-get`. The bridge changes the comparison term only. |
| Comparisons, `+`, `-` | `:3776-3784` | total: union over both operands |
| `constArithTerm` (`*`, `/`, `mod` with a numeral or folded divisor above 0) | `:3788` | total: the arm admits a positive divisor only |
| `and`, `or` | `:3791-3792` | the context rules. The arm maps a list (`mapM`), so the walk folds left to right. `check` admits two operands only. |
| `not` | `:3793` | union over the operand |
| `=>` | `:3797` | desugars to `(or (not p) q)`. The `or` rule then gives `C ∧ ¬¬⟦p⟧` for `q`, which is the `=>` rule. Reuse is correct here. |
| `<=>` | `:3798-3799` | **must not reuse the desugaring.** The desugared form `(and (or (not p) q) (or (not q) p))` would give `q` the context `⟦p⟧`. The run time evaluates both operands with no context. The walk takes this arm on the source form, before the desugaring. |
| `string-length`, `list-length`, `bytes-length` | `:3804-3805`, `:3822` | total: union over the operand |
| `first`, `second`, `EPair` | `:3812-3814` | total: union over the operands |
| `bytes-get`, `bytes-set` | `:3823-3826` | partial: `π_f`, plus the operands |
| `map-has`, `map-get` on a literal `map-empty` | `:3839-3840` | refused, so no obligation; the run-time guard applies (E15) |
| `map-has` | `:3841-3844` | total. The map argument goes through `mapPairTermsC`. Each key and value of a `map-put` chain is walked, because `map-put` is strict. |
| `map-get` | `:3845-3848` | partial: `π_map-get` over the has-array of the same `mapPairTermsC` pair, plus the map argument and the key |
| `EOp` | `:3850` | delegates to the `EApp` arm, as `exprToPred` does |
| `ok`, `err`, a constructor | `:3854-3860` | total: union over the arguments |
| `is-ok` on a variable | `:3864-3865` | none |
| `match` on a variable | `:3879-3907` | arm `i` under `C ∧ test_i ∧ ⋀_{j<i} ¬test_j`, with the same selector substitution. The arm's `prior` list already holds the earlier tests. |
| everything else | `:3908` | refused |

### 4.2 Hypotheses

Each obligation in `WD` becomes one Horn constraint. Its hypotheses `H` depend on the clause:

- **`pre`.** `H` = the parameter facts only: the translated `paramRefinementPre` (refinement aliases and `bytesLen(b) = n`), the binder facts (`enumTagDomain`) and the per-occurrence ground facts. The pre itself is not assumed. Its earlier conjuncts enter through `C`. One constraint set per function. Tag: `wd-pre`.
- **`post`, body-faithful function.** `H` = the environment of the truth constraint on each path: the pre, the path guards, the binder facts, the assumed callee posts and the ground facts. One constraint per path, as for truth. Tag: `wd-post`.
- **`post`, body-fallback function: no constraint (W4).** Without the body, `result` is free, so the constraint can never be complete. It would only add a second fallback cause. The run-time guard (§4.6) covers these clauses.

The constraint is `H ∧ C ⟹ π_f(…)`. It sits in the same `.fq` file and the same solver run as the truth constraints.

**Why a post may assume the body's facts. This is a deliberate divergence from Dafny.** Dafny checks the well-formedness of a method's specification in a separate procedure. That procedure assumes the precondition, makes the outputs arbitrary and does not read the body. In Dafny, `ensures m[3] == 0` on a body that builds `map[3 := 0]` fails with "element might not be in domain". LLMLL uses the run-time-error reading instead: the post must be defined in each state where the program evaluates it. The generated code evaluates the pre, then forces the body to WHNF with `!result`, then evaluates the post (measured on xm2's `Lib.hs`). So each path fact holds when the post runs. `nc-001` makes the generated program the semantics of record. Rev 1 cited Dafny for this rule. That citation was wrong, and Rev 2 removes it.

The cost of each rule, measured in §7.2:

- **Spec-local rule (Dafny).** A post is self-framing: a caller can read presence from it, and a body edit cannot make a fixed post ill-defined. Every `wd-post` constraint is complete, so no mark applies to it. Cost: 4 agent-written posts in the 2026-09-11 RFC 826 run become `ill-defined`. They hold today and hold under the body-context rule.
- **Body-context rule (chosen).** It accepts those 4 posts. Cost: a `wd-post` constraint shares its environment with the truth constraint, so it inherits the callee marks (§4.3). A post's definedness can depend on the body, so a body edit can change it.

**Why the pre may not assume itself.** The program evaluates the pre to decide whether the pre holds. Assuming it would make `(pre (> (map-get m 3) 0))` prove its own definedness. This agrees with Dafny's rule for `requires`.

**The hypotheses rest on assume-guarantee.** `H` for `wd-pre` holds the parameter refinements. A caller proves them at each call (`LLMLL.md §5.3.4`). An unverified caller lowers the trust level through the trust closure, as for every truth constraint.

### 4.3 Dropped hypotheses (W1)

A failing `wd-*` constraint is a disproof only when its `H` holds every fact that a run guarantees at that point. This is the P8 rule of the POST-CONJ-SPLIT-1 review. A site where the emitter omits such a fact is a **drop site**. Each drop site gets one of three treatments. **Prerequisite**: a row ships first and closes the site. **No emission**: the proposal emits no `wd-*` constraint there. **Mark**: the constraint carries a mark, and a failure is a fallback, never `ill-defined`.

The inventory comes from reading the clause translation (`exprToPred`), the fact injections (`injectRangeFacts`, `injectBoolValRangeFacts`, `injectStrLitDistinct`), the parameter and return folds and the call arms.

| Site | What is missing | Witness | Treatment |
|---|---|---|---|
| **S1. Sealed-builtin lemma in a clause.** | `bytesLen(Map_store(b,i,v)) = bytesLen(b)`. The body arm assumes it as a `lemma` part (`:4865-4870`). The clause arm (`:3825-3826`) does not. | profrev/bl.llmll: a true post is `refuted` today. `(bytes-get (bytes-set b 0 7) 1)` on `bytes[4]` would be `ill-defined`. | **Prerequisite: BYTES-SET-CLAUSE-LEN-1.** |
| **S2. Callee post not assumed.** | The callee's post, when it does not translate at the call (`FixpointEmit.hs:4709`). | the CALLEE-POST-UNASSUMED-1 witnesses | **Mark** `post-unassumed`, the same field that row adds. |
| **S3. Two calls to one callee.** | Congruence between two results (partly closed by CALL-CONGRUENCE-1). Also the facts of a builtin in `abstractedBuiltins` (empty today). | the ABSTRACTION-VERDICT-1 witnesses | **Mark** `abstraction`, unchanged. |
| **S4. Parameter refinement outside the fragment.** | The alias fact. The effective pre is the user pre conjoined with `paramRefinementPre` (`:6399-6416`). One refused conjunct refuses the whole effective pre. | profrev/rb.llmll: `h` falls back with `contract-pre-outside-fragment` | **No emission.** Rule: emit `wd-pre` and `wd-post` only when the effective pre translates in full. Such a function already falls back whole, so a mark would only add a second cause. |
| **S5. Body fallback.** | Every path fact. | `use-mk` (E8) | **No emission** of `wd-post` (§4.2). `wd-pre` is still emitted when the effective pre translates (E20). |
| **S6. Earlier conjunct refused (POST-CONJ-SPLIT-1 only).** | The earlier conjunct, which has no FQ form and cannot enter `C`. | the split's E13 | **Mark** `dropped-context`. |
| **S7. Pair component refinement.** | `0 ≤ first p < 4` for `p : (Idx, int)`. | cwd2/pc2.llmll, cwd2/pc3.llmll | **Not a drop.** No caller proves the fact and no run checks it (D6), so a run can reach the undefined point. `ill-defined` is then correct. If D6 is fixed by enforcing the fact at callers, the fix must also assume it here (parity rule). |
| **S8. Free symbol in a `wd-*` constraint.** | — (the constraint is ill-scoped) | none built | **No verdict.** FQ-FREEVAR-GUARD-1 (`:1015-1060`) routes the function whole, with cause `constraint-symbols-unbound`. For a function that is already body-fallback, the guard drops its `wd-pre` constraints only. |

**Sites checked and found complete.** The byte-range fact `0 ≤ select ≤ 255` reaches a clause select, including a select of a `Map_store` chain over a bytes root (`:6136-6149`; profrev/br.llmll verifies). The `{0,1}` fact of a bool-valued map reaches a clause select over a parameter or `result`, and over a `map-put` chain on one (`:6206-6212`). The three length measures get `t ≥ 0` (`:6181`). String literals get pairwise distinctness. Each injection reads LHS and RHS terms, so it covers the new `π_f` terms. A `bytes[n]` return length is a goal, not a hypothesis (`:6441-6445`). On a body-faithful path, the facts that prove that goal are in `H` too. A solver crash (CTOR-FIELD-SORT-1) is `FQError`, not UNSAFE, so it cannot produce `ill-defined`.

**The parity rule keeps the inventory complete.** A change that adds a fact on the body side, or a lemma part to a sealed-builtin arm, must add the same fact on the clause side or add a mark. One hspec test lists every `lemma` part of every clause-admissible sealed builtin and checks that the clause reflection carries it. This is the `sealedAxiomBuiltins` single-site discipline applied to lemmas.

**Consequence (W8).** A `wd-pre` constraint has no call binders and no abstraction. After S1 and S4, it is always complete. So a `wd-pre` failure is always `ill-defined`.

### 4.4 Verdicts and their combination (W2)

The verdict is decided per function, on the path that `applyAbstractionVerdict` already owns (`AbstractionVerdict.hs:77`), as extended by CALLEE-POST-UNASSUMED-1. Each failing id of a function belongs to one **partition** by clause tag:

- **WD**: `wd-pre`, `wd-post`.
- **MEAS**: `descent`, `decreases`.
- **TRUTH**: every other tag (`body-post`, `call-pre:*` and the rest).

Each failing id is **complete** or **marked** (marks: `post-unassumed`, `abstraction`, `dropped-context`).

**The rule, per function.**

1. **A complete failing id in any partition makes the verdict hard.** The function gets each hard marker whose partition holds a complete id: `ill_defined` for WD, `measure-not-decreasing` for MEAS, `refuted` for TRUTH (body-faithful functions only, as `refutedSet` requires today). The marked ids of that function do not change the outcome. This is rule 2 of ABSTRACTION-VERDICT-1: one non-candidate id blocks the fallback. `verify` exits 1.
2. **Otherwise, a marked failing id makes the function fall back, with one cause.** The cause is chosen in this order:
   1. every failing id is in WD: `clause-welldef-unproved`;
   2. every failing id carries the `abstraction` mark: `abstraction-unsafe`;
   3. otherwise: `callee-post-unassumed`.
   `verify` exits 0 with the warning for that cause.
3. **No failing id: no change.** Truth decides the verdict.

**Precedence of the hard markers in text and in `--strict-verified-core` messages:** `ill-defined`, then `measure-not-decreasing`, then `refuted`. All three can be set together. The well-definedness failure comes first because a truth counter-model may read a term at an undefined point. When `ill_defined` and `refuted` are both set, the `refuted` text says: "the counter-example may sit at a point where the clause is undefined; fix the `ill-defined` clause first".

**Why `clause-welldef-unproved` comes first among the causes.** It says that the clause's truth was proved and only its definedness was not. A truth failure in the same function is the larger fact, so causes 2 and 3 apply whenever a TRUTH or MEAS id also fails. The cause names the reason as a construct: `welldef:post-unassumed:app:<g>`, `welldef:abstraction:app:<g>` or `welldef:dropped-context`.

**Positioning against CALLEE-POST-UNASSUMED-1.** That row makes `callee-post-unassumed` the cause when a marked TRUTH id fails. This row adds no mark of its own to TRUTH ids. It reuses the `post-unassumed` and `abstraction` marks on WD ids. It adds one mark, `dropped-context`, which only POST-CONJ-SPLIT-1 can produce. So `clause-welldef-unproved` is a fallback cause beside the other two, and `ill-defined` is a hard verdict beside `refuted`. Neither changes an output of CALLEE-POST-UNASSUMED-1 for a function with no `wd-*` id.

| # | Failing ids of the function | Outcome | Exit | Test |
|---|---|---|---|---|
| V1 | none | unchanged | as today | `wd-safe-guarded` (E2) |
| V2 | WD complete only | `ill-defined` | 1 | `wd-ill-post-mapdef` (E1) |
| V3 | WD complete, TRUTH complete | `ill-defined` and `refuted`; `refuted` text qualified | 1 | `wd-ill-and-refuted` (E3, empty body, post `(= (map-get result 3) 1)`) |
| V4 | WD complete, TRUTH marked | `ill-defined` only | 1 | `wd-ill-pre-truth-marked` (a `wd-pre` failure, and a body call to a callee with a refused post that makes the post fail) |
| V5 | WD marked, TRUTH complete | `refuted` only; no `welldef_unproved` entry | 1 | `wd-marked-refuted` (two branches: a marked `wd-post` failure on one, a complete truth failure on the other) |
| V6 | WD marked only | fallback, `clause-welldef-unproved` | 0 | `wd-unproved-post-unassumed` (E13) |
| V7 | WD marked, TRUTH marked, `post-unassumed` on some | fallback, `callee-post-unassumed` | 0 | `wd-and-truth-unassumed` |
| V8 | WD marked, TRUTH marked, `abstraction` on all | fallback, `abstraction-unsafe` | 0 | `wd-and-truth-abstraction` |
| V9 | WD complete, MEAS complete | `ill-defined` and `measure-not-decreasing` | 1 | `wd-ill-measure-bad` |
| V10 | WD marked, MEAS complete | `measure-not-decreasing` only | 1 | `wd-marked-measure-bad` |
| V11 | WD marked, MEAS marked | fallback, cause by step 2 (`callee-post-unassumed` or `abstraction-unsafe`), with `W-DECREASES-UNDISCHARGED` | 0 | `wd-marked-measure-marked` |
| V12 | `wd-pre` complete in a body-fallback function | `ill-defined`; the function keeps its fallback cause too | 1 | `wd-ill-pre-fallback-body` (E20) |
| V13 | WD marked `dropped-context` only (after POST-CONJ-SPLIT-1) | the conjunct falls back, `clause-welldef-unproved` | 0 | `wd-dropped-context` (E14) |

`FQError` and `FQResourceLimit` are whole-run answers and are unchanged. `--strict-verified-core` fails on each hard marker and on each fallback cause, as on any non-verified clause.

**`ill-defined` is not `refuted`.** `refuted` means the clause is false in a reachable state. `ill-defined` means the program cannot evaluate the clause in a reachable state. The REC-DESCENT precedent applies: `measure-not-decreasing` is kept out of `refutedSet` "so a pure measure failure is never mislabeled refuted" (`Main.hs:1664-1676`). `ill-defined` is an orthogonal marker, like `refuted` (`LLMLL.md:633`). It is not a `DisplayLevel` element. Unlike `refutedSet`, the `ill-defined` set does not require a body-faithful function, because a `wd-pre` constraint does not read the body (V12).

**Callers.** A caller assumes an `ill-defined` or `clause-welldef-unproved` post as it assumes an `asserted` post. The caller's level meets `asserted`. Neither post is stripped, so the callee's run-time check stops the program before a caller sees a value that violates the post. This argument depends on the fail-stop of a contract violation. PRE-FAIL-EXIT-1 records two handlers that catch `error` and turn it into a value (§4.7).

### 4.5 Soundness argument (W9)

**Setting.** A run state `ρ` gives each variable a value. A partial operation applied in `ρ` is *defined* when its precondition holds in `ρ`. A model `M` of the encoding *agrees with `ρ` on defined reads* when each select at a defined position has the run's value in `M`. The canonical model takes the run's values at defined positions and the encoding's values elsewhere (for example `Map_default 0` for `map-empty`). It satisfies every reflection equation in `H` on a body-faithful path, because each body read is defined (its `call-pre:<builtin>` obligation holds).

**Lemma (junk independence).** Let `C` hold in `ρ`, and let every obligation in `WD(C, e)` be valid. Then the program evaluates `e` in `ρ` without an error, and `⟦e⟧` has the run's value in every model `M` that agrees with `ρ` on defined reads.

Proof by induction on `e`.
- Variable or literal: immediate.
- Total operation: by the induction hypothesis on each argument. Each argument is evaluated (`esForceArgs`), and the operation is a function of the argument values.
- Partial operation `f`: by the induction hypothesis, each argument has its run value in `M`. The obligation `C ⟹ π_f` is valid and `C` holds, so `π_f` holds in `ρ`. The read is defined, so `M` gives it the run's value.
- `(and a b)`: the hypothesis on `a` (context `C`) gives `⟦a⟧ = eval_ρ(a)`. If `a` is false, both sides are false and the run does not evaluate `b`. If `a` is true, `C ∧ ⟦a⟧` holds in `ρ`, and the hypothesis on `b` applies.
- `(or a b)`, `(=> a b)`: the same argument with `¬⟦a⟧` and `⟦a⟧`.
- `(<=> a b)`: both operands under `C`, as the run evaluates both.
- `(match x …)`: exactly one arm `i` has its test true and every earlier test false in `ρ`. The reflected conjunction holds each other arm vacuously: an arm `j < i` has a false test, and an arm `j > i` has the true test `test_i` in its `prior` list (`FixpointEmit.hs:3897`). So `⟦e⟧` equals arm `i`'s term. The hypothesis on arm `i` under `C ∧ test_i ∧ ⋀_{j<i} ¬test_j` gives its value.

**Theorem.** If the truth constraint of a clause is valid, and every `WD` obligation of the clause is valid, then the clause holds in every run that reaches it. Proof: take the canonical model of the run state. It satisfies `H`. Validity gives `⟦e⟧` true in it. The lemma gives `eval_ρ(e) = ⟦e⟧`.

So, after this row, a solver model and a run differ only at points that no run evaluates. Each truth proof over the total encoding then holds for the generated program. This includes the proof of a callee's pre at a call site (xm2) and the stripping of a verified clause (xm3). A clause that relies on the default value, such as `mapdef.llmll`, fails its obligation.

**Consequence: refutation localization.** When `WD` is proved, the lemma applies to a truth counter-model too: the clause's value in that model depends only on reads that the model's own state makes defined. So the counter-model names no junk read. This closes the disposition's second defect ("refutation localization degrades").

The lemma does not need an underspecified encoding. It needs only that no evaluated term reads an undefined position.

### 4.6 Run-time side: guard the clause check

**Rule: inside a clause, a partial operation outside its precondition is a violation of that clause.** The check raises `Precondition of <fn> is undefined: <op> <reason>` or `Postcondition of <fn> is undefined: <op> <reason>`. It does not raise the builtin's own error.

- **Scope.** The rule applies to the expression that `wrapPre` and `wrapPost` wrap (`Contracts.hs:314-348`). It covers `map-get`, `bytes-get`, `bytes-set`, `unwrap`, `/`, `mod` and `rem`. A body is unchanged.
- **A user call in a clause is not rewritten.** The callee's own pre check names the callee.
- **The exit status is unchanged in effect.** A clause violation and a builtin error both raise `error` today. A division by zero raises `ArithException` (`divide by zero`), not `error`. The process exits with status 1 in each case. The guard tests the divisor before the division, so a clause division by zero becomes a clause violation through `error`.
- **The guard inherits PRE-FAIL-EXIT-1.** The guard raises through the same path as a failed pre. Two handlers catch that path today (`llmll_rxTotal`, and the `EAwait` code). Whatever PRE-FAIL-EXIT-1 decides for a failed pre applies to the guard unchanged.
- **Codegen does not read verification results for this.** The guard is dead code where `WD` is proved. Its cost is one presence test or one bound test per read.
- **Reference.** JML adopted the same rule for run-time assertion checking (Chalin, "strong validity", ICSE 2007).

The guard matters most where `WD` does not apply: a refused clause with `unwrap` or a variable divisor, a `post` of a body-fallback function (S5), a function whose effective pre is refused (S4), and a clause that is `clause-welldef-unproved`.

### 4.7 Interactions and order

**Ship order.** BYTES-SET-CLAUSE-LEN-1, then CALLEE-POST-UNASSUMED-1, then this row, then CONTRACTS-ENTRY-STRIP-1. BYTES-SET-CLAUSE-LEN-1 closes site S1. CALLEE-POST-UNASSUMED-1 adds the `post-unassumed` field that site S2 reuses, and the cause that §4.4 orders against. CONTRACTS-ENTRY-STRIP-1 comes last: today D1 keeps the run-time check of an entry-module post, so `mapdef.llmll` at least stops. D1 fixed alone would strip that post silently.

**PRE-FAIL-EXIT-1.** Independent in order. The "Callers" argument (§4.4) and the guard (§4.6) assume that a contract violation stops the program. That row decides whether the two catching handlers keep converting one into a value.

**POST-CONJ-SPLIT-1.**

1. *Truth assumes no other conjunct; well-definedness assumes the earlier ones.* This is the split's §4.3 rule plus §4.1 here. The two rules do not conflict.
2. *A conjunct is `verified` only when its truth and its well-definedness are both proved.*
3. *The dropped-context mark (site S6).* A failure gives `clause-welldef-unproved`, never `ill-defined`. In `(and (refused-guard r k) (= (map-get r k) 0))`, conjunct 2 is `asserted` with that cause (E14).
4. *Per-conjunct stripping reopens (W5).* **Rule: under `--contracts=unproven`, strip conjunct `j` when its truth and its well-definedness are both verified. Keep every other conjunct, in source order.** Proof, by induction over source order. Fix a state that reaches the post, and let conjuncts `1 … j-1` each be true there or kept and checked. If a kept earlier conjunct is false, its check stops the program, and conjunct `j` is not evaluated. Otherwise every earlier conjunct is true, so `C_j` holds. `C_j` holds, so the `WD` obligation makes conjunct `j` defined there. Its truth proof makes it true. So a stripped conjunct is never the first to fail, and each kept conjunct is evaluated in the same states as before. Its definedness in those states is either proved or guarded at run time (§4.6). The Rev 1 sentence "a stripped conjunct is true in every state that reaches the post" was false. With `(and (map-has result 3) (= (map-get result 3) 0))` on `(map-empty)`, conjunct 2 is true in the logic and is stripped. In a run, conjunct 2 is undefined. The program is still safe, because conjunct 1 is kept and fails first. The induction covers this case.
5. *Record the dependency.* A conjunct whose `WD` obligation used an earlier conjunct `k` that is not verified is recorded as "defined given conjunct k". The record holds the index `k`. A reader then knows that stripping conjunct `k` later would need a new proof.
6. *Record wording.* The split's "proved as part of the post" becomes "proved, and defined where evaluated" for a conjunct whose obligation holds.

**CONTRACT-READ-LINT.** Keep the `contract-read-oob` warning (`Diagnostic.hs:255-260`). It is a `check`-time signal with no solver. Its slice, a literal index against a literal `bytes[n]`, is a subset of the `ill-defined` verdicts.

**ABSTRACTION-VERDICT-1.** Its mark applies to `wd-*` constraints unchanged (site S3).

**`decreases`.** Not covered. The run time does not evaluate a `decreases` measure (`CodegenHs.hs:2068-2070` emits it as a comment). See E9.

### 4.8 Schema and version delta

- **`checker_soundness_version`: `"6"` to `"7"`.** A sidecar written under `"6"` can record `verified` on a clause that contradicts `nc-004` (`mapdef.llmll`, `w2_bytespost`, `w12_bytesset`, `contract-read-oob.llmll`). Every sidecar reader then fails closed and asks for a new `verify`. AND-GUARD-PRE-1 set the precedent for `"6"`.
- **Proof artifact (W6).** `docs/proof-artifact.schema.json` gains `checker_soundness_version` as a required member of `composed_versions`. An artifact written by 0.35.1 has no `wd-*` constraints in its stored `.fq`, so it replays SAFE, and today a consumer cannot see its epoch. A replay that finds no value, or a value below the current one, reports `ReplayFailClosed` with the reason "written under an earlier soundness epoch; re-verify". It does not report a verdict. `proof_artifact_version` takes a minor increase, because a required member is added. The artifact also gains the `ill-defined` verdict and the new cause.
- **`verify --json`**: two new keys, `ill_defined` (a list of function names) and `welldef_unproved` (a list of function names with constructs), beside `abstraction_fallback`. Minor increase of `verify_json_version`. `solver_verdict` follows the `measure-not-decreasing` precedent; the engineer confirms its value.
- **Trust report**: marker `ill_defined` on the clause entry; the new fallback cause `clause-welldef-unproved`. Minor increase of `trust_report_version`; `docs/llmll-trust-report.schema.json` gains both.
- **Constraint origins**: two new clause tags, `wd-pre` and `wd-post` (`DiagnosticFQ.hs:60`).
- **Diagnostics**: `clause-ill-defined` (error), with text such as `the post of 'mk' is not defined where it is evaluated: (map-get result 3) needs (map-has result 3)`; `W-CLAUSE-WELLDEF-UNPROVED` (warning).
- **`.fq`**: byte-identical for every function with no admitted partial operation in a translated clause. Other functions gain `wd-*` constraints. A body-fallback function gains `wd-pre` constraints only.
- **JSON-AST schema**: no change. **Surface syntax**: no change. No new builtin, construct, FFI tier or capability.
- **`codegen_semantics_version`**: no change. The guard changes a message and no value that a solver axiom relies on.

### 4.9 Options not chosen

- **(b) Refuse partial operations in clauses.** 90 clauses in 41 files use them (§7), nearly all in the guarded idiom. The RFC 826 swarm specifications and the netpbm swarm posts would fall back. A syntactic refusal also cannot accept a read that body facts make safe.
- **(c) Obligations in posts, refusal in pres.** Nothing makes a pre harder than a post. The pre obligation has fewer hypotheses.
- **(a) with the spec-local (Dafny) hypotheses for `wd-post`.** Every `wd-post` constraint would be complete, and posts would be self-framing. Rejected: 4 agent-written RFC 826 posts become `ill-defined` (§7.2), and `nc-001` makes the run-time order the semantics of record. Section 4.2 records the trade.
- **(a) with "assume all conjuncts" instead of short-circuit context.** It would accept `(and (= (map-get m k) 0) (map-has m k))`, which stops at run time when `k` is absent.
- **A mark for a refused parameter refinement (review W1(b)).** Replaced by "no emission" (site S4). The function already falls back whole.
- **A run-time guard alone, with no obligation.** It fixes the message, not the false `verified` record, the stripped post of xm3 or the call-site discharge of xm2.

## 5. Edge cases and degenerate inputs

**E1. `mapdef.llmll` (positive witness for `ill-defined`).** Input: `(def-shell mk [n: int] -> map[int,int] (post (= (map-get result 3) 0)) (map-empty))`. Behaviour: `wd-post` gives `Map_select(Map_default 0, 3) = 1` under the body facts. It is false, and the constraint is complete. Row V2: `ill-defined`, exit 1, no `verified` record. Channel: contract. Today `verified` (measured).

**E2. Guarded post.** Input: `w4_guarded.llmll`, `(post (and (map-has result 3) (= (map-get result 3) 7)))`. Behaviour: `C` gives the presence. SAFE. Row V1. Channel: contract.

**E3. Wrong conjunct order.** Input: `(post (and (= (map-get result 3) 7) (map-has result 3)))` with body `(map-empty)`. Behaviour: the `map-get` obligation has an empty `C` and fails. The truth fails too (`0 ≠ 7`). Row V3: `ill-defined` and `refuted`, with the qualified `refuted` text. With body `(map-put (map-empty) 3 7)`, both hold from body facts, and the function is `verified`. Channel: contract.

**E4. Pre that reads an absent key.** Input: `w3_mappre.llmll`, `(pre (> (map-get m 3) 0))`. Behaviour: `wd-pre` fails over the parameter facts. Row V2: `ill-defined`, exit 1. At run time, a call on `(map-empty)` reports `Precondition of g is undefined: map-get key 3 not present`. Channel: contract and run time.

**E5. The call-site discharge (xm2).** Behaviour: `mk` and `g` are `ill-defined`, so `mklib.llmll` exits 1. `c` assumes `mk`'s post and proves `g`'s pre as today, at level `asserted` through the trust closure. Neither post is stripped. Channel: contract and trust.

**E6. Bytes read past the length.** Input: `scripts/doc-claims/contract-read-oob.llmll`, `(post (>= (bytes-get b 9) 0))` on `bytes[8]`. Behaviour: `9 < 8` fails. `ill-defined`, exit 1. The `check`-time warning stays. Channel: type (lint) and contract.

**E7. `bytes-set` value out of range.** Input: `w12_bytesset.llmll`. Behaviour: two failing obligations, `9 < 4` and `300 ≤ 255`. `ill-defined`. Today `verified`. Channel: contract.

**E8. Post of a body-fallback function.** Input: `compiler/test/fixtures/map-ret-post/use.llmll`, `use-mk`, `(post (>= (map-get result k) 0))`, body `(mk k)`. Behaviour: no `wd-post` is emitted (site S5). The verdict stays the existing fallback, with its one cause. At run time, the guard reports an undefined post. Channel: trust and run time. Rev 1 gave this function a second cause; Rev 2 does not.

**E9. A partial operation in `decreases`.** Behaviour: no obligation. The run time does not evaluate the measure. Its descent proof stays sound: the junk entries of the initial map are fixed once, and every later map is a `Map_store` chain over it. Channel: spec is silent (intentional).

**E10. A refused clause with a partial operation.** Input: `w5_divclause.llmll` (divides by the parameter `d`); `w6_unwrap.llmll`. Behaviour: no obligation; the clause is `asserted` as today. At run time, `(dv 0)` reports "Postcondition of dv is undefined: division by zero", where today it prints the `ArithException` text `divide by zero`. Channel: run time.

**E11. Short-circuit through `or` and `=>`.** Input: `(pre (=> (map-has m 3) (> (map-get m 3) 0)))` and the `or` form. Behaviour: both obligations hold from `C`. `w14_shortcircuit` shows that the run time agrees. Channel: contract.

**E12. `<=>` gives no context.** Input: `(post (<=> (map-has m k) (> (map-get m k) 0)))`. Behaviour: `C` is empty for `map-get`, so the obligation fails unless `H` gives presence. A walk that reused the `<=>` desugaring would wrongly accept it (§4.1.1). Channel: contract.

**E13. Callee post not assumed.** Input: a caller whose post reads `(map-get (callee x) k)` through a `let`-free path, guarded only by a fact that the callee's refused post would give, with the truth proved. Behaviour: the `wd-post` id carries `post-unassumed`. Row V6: fallback, `clause-welldef-unproved`, construct `welldef:post-unassumed:app:callee`. Channel: trust.

**E14. Split with a refused guard (POST-CONJ-SPLIT-1 E13).** Input: `(and (refused-guard r k) (= (map-get r k) 0))`. Behaviour: conjunct 2's id carries `dropped-context`. Row V13. Conjunct 2 is `asserted` and is not stripped. Channel: trust.

**E15. Map read on a literal `map-empty`.** Input: `(post (= (map-get (map-empty) 3) 0))`. Behaviour: refused today (`FixpointEmit.hs:3840`), so no obligation. The run-time guard reports `Postcondition of f is undefined`. Channel: run time.

**E16. Nested partial reads.** Input: `(map-get m (map-get m2 k))`. Behaviour: two obligations, the inner `Map_select(m2$has,k)=1` and the outer `Map_select(m$has, Map_select(m2$val,k))=1`. The outer one is meaningful only because the inner one holds; the lemma's partial-operation case covers this. Channel: contract.

**E17. Read through a `bytes-set` (site S1).** Input: `(post (= (bytes-get (bytes-set b 0 7) 1) (bytes-get b 1)))` on `b: bytes[4]`, after BYTES-SET-CLAUSE-LEN-1. Behaviour: the outer obligation `1 < bytesLen(Map_store(b,0,7))` holds from the length fact that row adds. SAFE. Without that row, it is a false `ill-defined`. That is why the row is a prerequisite. Channel: contract.

**E18. Parameter refinement outside the fragment (site S4).** Input: profrev/rb.llmll with an added `(pre (> (bytes-get b i) 0))`, `i: Idx`. Behaviour: the effective pre does not translate. No `wd-*` constraint is emitted. The function falls back with `contract-pre-outside-fragment`, as today. At run time the guard covers the pre. Channel: trust and run time.

**E19. Pair component refinement (site S7).** Input: cwd2/e19.llmll, `h [b: bytes[4] p: (Idx, int)]` with post `(>= (bytes-get b (first p)) 0)`. Today `h` is body-faithful and `verified` (measured). Behaviour: the obligation `first p < 4` fails, and the constraint is complete. `ill-defined`. This is correct, because a caller can pass an out-of-range component: `c` in cwd2/pc3.llmll passes `(pair 9 n)` with no obligation, and that run reaches the undefined read. Channel: contract. Cite: D6.

**E20. `wd-pre` in a body-fallback function.** Input: cwd2/e20.llmll, `(def-shell g [m: map[int,int] s: string] -> int (pre (> (map-get m 3) 0)) (post (>= result 0)) (string-length (string-concat s s)))`, a body outside the fragment. Behaviour: the effective pre translates, so `wd-pre` is emitted. It fails and is complete. Row V12: `ill-defined`, exit 1. The function keeps `body-outside-fragment` as its fallback cause. Today `g` falls back with that cause and exits 0 (measured). Channel: contract.

## 6. Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| `wd-pre`: `facts(params) ∧ C ⟹ π_f(…)` | contract (PROVE) | (a) QF-LIA plus the array theory and the `bytesLen` measure; auto-discharged by liquid-fixpoint. The same class as today's `call-pre:<builtin>` body obligations. | `LLMLL.md §5.3.3` array class; `FixpointEmit.hs:4829-4957` |
| `wd-post`: `P ∧ path ∧ Γ ∧ C ⟹ π_f(…)` (body-faithful only) | contract (PROVE) | (a), as above; the same environment as the truth constraint | `LLMLL.md §5.3.3`, `§5.3.4` |
| Clause truth | contract | unchanged | `LLMLL.md §5.3.4` |
| Run-time guard of a clause | run time (trust backstop) | not an obligation | `LLMLL.md §5.3.4` backstop |

No obligation is nonlinear or quantified. No obligation goes to Lean. Each `C` is a conjunction of admitted clause sub-terms, so it is in the fragment by construction.

## 7. Corpus impact

### 7.1 The body-context rule (chosen)

Measured on the tracked tree at `491d96b1`, with `scan.py`, `scan2.py`, `wdgen.py` and `probe_run.py` in cwd1/.

- **595 tracked `.llmll` files, 2820 `pre` and `post` clauses.** 90 clauses in 41 files hold `map-get`, `bytes-get` or `bytes-set`. 17 of the 41 files are under `examples/`.
- **Syntactic read.** 299 `map-get` occurrences have a `map-has` on the same arguments in their short-circuit context. 40, in 18 files, do not. 8 `bytes-get` occurrences, in 5 files. 1 `pre` holds `map-get`, guarded. No clause has a non-literal divisor.
- **Emulation: 23 of the 41 files.** The other 18 files hold only syntactically guarded reads. `scan2.py`'s context model makes each of their obligations true, so they were not run. For each of the 23 files, `wdgen.py` appends each obligation as an extra `post` clause, `(post (=> C π_f))`, and runs `verify` on the copy and the original.
- **Result: one change of exit status, `f` in `scripts/doc-claims/contract-read-oob.llmll`.** The 11 mutant files are `refuted` before and after. So the emulation cannot show whether they also gain the `ill-defined` marker; that is not measured. The other 11 files are unchanged.
- **Limits.** The emulation cannot test a body-fallback function, because the extra post is only assumed. Under Rev 2 those functions emit no `wd-post` (S5), so this limit no longer affects a verdict. It also assumes the pre when it emulates a `wd-pre` obligation. The one pre in the corpus is guarded, so this does not change the count.
- **`.fq` changes** are limited to functions in the 41 files. The census baseline must be measured again.

### 7.2 The spec-local rule (the review's open question)

Method. cwd2/wdspec.py adds, for each function with a `WD` obligation in its post, a sibling `def-shell <name>__spec`. The sibling has the same parameters plus `rr__` of the return type, the same pre, the post `C ⟹ π_f` with `result` renamed to `rr__`, and the body `0`. The body is a literal, so the post is proved from the pre and the parameter facts only. That is Dafny's well-formedness hypothesis set. cwd2/spec_run.py runs `verify` on each of the 23 files and reports the sibling functions that fail. Results are in cwd2/spec.jsonl.

| Rule | New `ill-defined` in non-mutant files | Which |
|---|---|---|
| Body-context (chosen) | 1 | `f` in `contract-read-oob.llmll` |
| Spec-local (Dafny) | 6 | the same `f` (by reading: `9 < 8` fails under any hypotheses; the script skips it because it has no `->`), `use-mk` (fixture, body-fallback), and 4 agent-written posts in the 2026-09-11 RFC 826 run: `recv-merge` (`merge-before-opcode.llmll`), `recv-table` (`recv-table.llmll`), `merge-binding` (`spoof-binding.llmll`), `recv-table-framed` (`table-frame.llmll`) |

The four RFC 826 posts read `(map-get result k)` or `(map-has result k)` with presence given only by the body's `map-put`. Their mutant twins also fail the spec-local sibling, but they are `refuted` already. The 2026-09-12 run's four files and `roots.llmll` are unaffected under both rules. The other direction is empty by construction: the spec-local hypotheses are a subset of the body-context hypotheses on each path. The one exception is a body-fallback function, where the body-context rule emits no `wd-post` and the spec-local rule decides (`use-mk`). The 18 files that were not run hold syntactically guarded reads, so `C` alone discharges them under both rules.

## 8. Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: `exprToPredWD`, with `exprToPred` derived from it (§4.1.1); a single `π_f` table read by the body arms and by `exprToPredWD`; emission of `wd-pre` once per function when the effective pre translates in full, and `wd-post` on each path of a body-faithful function; the `dropped-context` mark (after POST-CONJ-SPLIT-1); `ConstraintOrigin` tags; the FQ-FREEVAR-GUARD-1 case for a `wd-pre` constraint of a function that is already body-fallback.
- `compiler/src/LLMLL/AbstractionVerdict.hs` and `compiler/app/Main.hs` (`:1654-1676`): the partition rule of §4.4; an `illDefinedSet` that does not require body-faithfulness; the cause order; the exit law; the `--json` keys.
- `compiler/src/LLMLL/DiagnosticFQ.hs`: the two clause tags and their text.
- `compiler/src/LLMLL/Diagnostic.hs`: `clause-ill-defined`, `W-CLAUSE-WELLDEF-UNPROVED`, the qualified `refuted` text.
- `compiler/src/LLMLL/TrustReport.hs`, `ProofArtifact.hs`, `VerifiedCache.hs`: marker, cause, stamp `"7"`, the artifact's soundness epoch and its replay check.
- `compiler/src/LLMLL/Contracts.hs` (`wrapPre`, `wrapPost`) and `CodegenHs.hs`: clause-context forms of the seven partial operations (§4.6).
- `docs/llmll-trust-report.schema.json`, `docs/proof-artifact.schema.json`, `docs/llmll-verify.schema.json`.
- `LLMLL.md` §4.4.1 (the new verdict), §4.4.4 (`--json` keys), §5.3.3 and §5.3.4 (the obligation, the body-context rule and its divergence from Dafny, the stripping rule), §13.12 (π also governs clauses; D2). Doc-lead's slot.
- `docs/design/contract-position-reads-disposition.md`: superseded on settlement. Doc-lead's slot.
- `docs/design/post-conj-split-proposal.md` §4.3, §4.5, E13: the reopened stripping rule and its induction (§4.7 item 4), at the next revision of that proposal.
- `scripts/fallback_census.py`: the new cause in its own bucket.
- **Acceptance tests.** The 13 rows of §4.4, one test each. E4 and E10 run-time messages. A two-module test from xm2, and one from xm3 that checks the post is no longer stripped. The lemma-parity test (§4.3). The `.fq` byte-identity sweep over the files with no partial operation in a clause.

## 9. Risks and open questions

1. **New hard failures.** Classify: verification-ergonomics. A file that passes today can exit 1. Cite: §4.4. Bite: complicates. The corpus count is one, a fixture made for this defect (§7.1). Agent-written code outside the repository can hold more. The diagnostic names the missing `map-has` or bound.
2. **An unlisted drop site.** Classify: soundness of the verdict. A drop site missing from §4.3 gives a false `ill-defined` on a correct clause. Cite: §4.3. Bite: complicates. The parity rule and its test cover sealed-builtin lemmas. A new fact family on the body side is caught only by review of that row.
3. **Stamp change cost.** Classify: scope. Every sidecar and every proof artifact fails closed once. Cite: §4.8. Bite: matters at scale only. BYTES-LEN-RANGE-1 and AND-GUARD-PRE-1 paid the same cost.
4. **Two copies of π or of the traversal.** Classify: spec-drift. Cite: §4.1, §4.1.1. Bite: complicates. One table, one traversal, and one test that lists every `CallVC` builtin with a `pre`.
5. **Fail-stop is not guaranteed today.** Classify: soundness. The "Callers" argument and the guard assume that a contract violation stops the program. PRE-FAIL-EXIT-1 records two handlers that catch it. Cite: §4.4, §4.6. Bite: complicates that row, not the verdicts of this one.
6. **Future partial builtins.** Classify: scope. `docs/design/byte-io-proposal.md` adds `bytes-slice`, `string-code-at` and five `bit-*` operations, each with a QF-LIA pre. Each enters the π table and the parity test when it becomes clause-admissible. Bite: matters at scale only.
7. **POST-CALL-XMOD-1.** Classify: soundness. If a user function becomes admissible in a clause, its pre is a well-definedness obligation by the same rule. Bite: complicates that row, not this one.

## 10. Decisions for the user

1. Option (a), with the run-time guard of §4.6. Recommendation: yes.
2. `ill-defined` as a hard verdict with exit 1. Recommendation: yes.
3. The body-context hypotheses for `wd-post`, as a recorded divergence from Dafny (§4.2, §7.2). Recommendation: yes.
4. The verdict combination of §4.4, with `clause-welldef-unproved` first among the fallback causes when only `wd-*` ids fail. Recommendation: yes.
5. Increase `checker_soundness_version` to `"7"`, and add it to the proof artifact. Recommendation: yes (§4.8).
6. Ship order: BYTES-SET-CLAUSE-LEN-1, CALLEE-POST-UNASSUMED-1, this row, CONTRACTS-ENTRY-STRIP-1 (§4.7).
7. Reopen per-conjunct stripping in POST-CONJ-SPLIT-1 with the rule and induction of §4.7 item 4, after this row ships.
8. D6 (pair component refinement is not enforced) is filed as `PAIR-REFINE-ENTRY-1`. Correct the §13.12 `bytes-set` precondition (D2).
9. Mark `docs/design/contract-position-reads-disposition.md` superseded on settlement.

No open question blocks this proposal, so this draft has no section for the professor.
