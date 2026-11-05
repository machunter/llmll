---
name: clause-welldef-proposal
title: "CLAUSE-WELLDEF-1: prove that each partial operation in a pre or post is defined where the program evaluates it"
status: "Rev 3, SETTLED 2026-11-04 (user-approved). Rev 3 makes the four blocking edits of the second professor pass (N1-N4) and every fold item (N5-N9 and three paragraphs). It aligns with POST-CONJ-SPLIT-1 on the review's C1 and C2, and it updates site S7 for the settled PAIR-REFINE-ENTRY-1."
date: 2026-11-04
author: language-team
rows: "CLAUSE-WELLDEF-1 (G1, PLAN; was DECIDE). Prerequisites shipped in v0.36.0: BYTES-SET-CLAUSE-LEN-1 (site S1) and CALLEE-POST-UNASSUMED-1 (the shared verdict path). Ships before POST-CONJ-SPLIT-1 and before CONTRACTS-ENTRY-STRIP-1 (G3, PLAN). Its run-time guard depends on PRE-FAIL-EXIT-1 (G2, DECIDE). Changes site S7 with PAIR-REFINE-ENTRY-1 (G1, decided 2026-11-04). Related rows filed at settlement: REPLAY-CODEGEN-VERSION-1 (drift D7), LIST-REFINE-ENTRY-1. Supersedes the decline of option (b) in docs/design/contract-position-reads-disposition.md."
consumers: [user, professor, compiler-engineer, documentation-lead]
review: "Two professor passes, folded below as the Appendix: the review of Rev 1 (2026-11-03, accept with changes, W1-W10; archived at docs/archive/professor-reviews/clause-welldef-review.md) and the second pass of Rev 2 (2026-11-04, settle after N1-N4; never committed as a standalone file)."
---

# CLAUSE-WELLDEF-1: prove that each partial operation in a pre or post is defined where the program evaluates it

**Status: Rev 3, SETTLED 2026-11-04.** The language-team wrote Rev 1 on 2026-11-03. The professor reviewed it the same day with the verdict "accept with changes" (W1-W10). Rev 2 folded that review. The professor's second pass of Rev 2 (2026-11-04) said "settle after four small edits" (N1-N4). The professor's second pass of POST-CONJ-SPLIT-1 Rev 2 added two cross-draft findings (C1, C2). The user accepted every recommendation on 2026-11-04. Rev 3 makes every change. Both reviews are folded below as the [Appendix](#appendix--professor-review-log).

The Rev 1 and Rev 2 measurements are on `llmll 0.35.1` (liquid-fixpoint 0.9.6.3.7). Each file ran alone under the memory and time watchdog `watch.py`. The witnesses are named by their scratch directory: `cwd1/` (Rev 1), `profrev/` (the first review: xm3, `bl.llmll`, `rb.llmll`) and `cwd2/` (Rev 2, and the spec-local emulation of §7.2). These directories are in the drafting session's scratchpad and are not committed. Source line numbers in Rev 3 are on main at `a339fbb8` (v0.36.0).

## Decisions (settled by the user, 2026-11-04)

1. **Option (a), with the run-time guard of §4.6.** Each admitted partial operation in a clause gets a well-definedness obligation.
2. **`ill-defined` is a hard verdict.** `verify` exits 1.
3. **`wd-post` uses the body-context hypotheses.** This is a recorded divergence from Dafny's rule for methods (§4.2, §7.2).
4. **The verdict combination of §4.4,** with the four-step cause order (N2) and `refuted` counted on complete TRUTH ids only (N3).
5. **`checker_soundness_version` goes from `"6"` to `"7"`.** The proof artifact records it, and replay reads it (N4, §4.8).
6. **The emission gate (N1 and C1).** A function emits `wd-*` constraints only when it reaches the arm where both its pre and its post translate and no contract-level guard fires. Inside that arm, `wd-pre` is emitted for every function, and `wd-post` is emitted on each path of every function with a body VC. Both rules hold together (§4.2).
7. **`rb`-style functions get no emission.** The professor withdrew the mark of W1(b). A function whose effective pre is refused emits no `wd-*` constraint (site S4).
8. **Fallback is per function in v1 (C2).** A failed `clause-welldef-unproved` check makes the whole function fall back, not one conjunct. Row V13 and its test move to POST-CONJ-SPLIT-1.
9. **The refuted rule agrees with POST-CONJ-SPLIT-1 (C2).** `refuted` needs a complete TRUTH id in a function with a body VC. Before the split ships, that set is the body-faithful functions. After it ships, it is the body-faithful or partly proved functions.
10. **Ship order: CLAUSE-WELLDEF-1 ships before POST-CONJ-SPLIT-1.** Both ship before CONTRACTS-ENTRY-STRIP-1 can strip an entry-module post (§4.7).
11. **Proof-artifact version rule.** From now on, a new enum value in the proof artifact raises `proof_artifact_version`, because an old validator rejects it. v0.36.0 added the `fallback_reason` value `callee-post-unassumed` without a raise. That release stays as shipped, and this record lists it as a known exception. CLAUSE-WELLDEF-1 ships first, so it takes `0.2.0`. POST-CONJ-SPLIT-1 takes the next raise.
12. **PAIR-REFINE-ENTRY-1 is settled as option A.** A refinement on a pair component is checked like a scalar parameter's refinement, at any depth. Callers prove it, and the callee assumes it. Site S7 and E19 change to match (§4.3).
13. **Two rows are filed.** REPLAY-CODEGEN-VERSION-1: `classifyReplay` never compares `codegen_semantics_version`, although the schema says that replay fails closed on it (drift D7). LIST-REFINE-ENTRY-1: a list element or map value refinement is neither proved nor assumed.
14. **Docs.** Correct the §13.12 `bytes-set` precondition (D2). Mark `docs/design/contract-position-reads-disposition.md` superseded. Both are the documentation-lead's slot.

## Rev 3 changes

| Finding | Source | What Rev 3 does | Section |
|---|---|---|---|
| N1. The `wd-pre` gate admits pres that a contract guard refused | second pass, blocking | The gate is the `(Just postPred, Just mPre)` arm of `FixpointEmit.hs:1661`. No other function emits a `wd-*` constraint. | §4.2, §4.3 S4, S8, §8 |
| N2. No cause for a marked set without `post-unassumed` | second pass, blocking | Four cause steps. `callee-post-unassumed` only when some id carries that mark. Otherwise `abstraction-unsafe`. | §4.4 |
| N3. Rule 1 changes an output of CALLEE-POST-UNASSUMED-1 | second pass, blocking | The false "no output change" sentence is deleted. `refutedSet` counts complete TRUTH ids only. New row V14 and its test. | §4.4, §8 |
| N4. The artifact epoch has no parse rule, compare rule or reader | second pass, blocking | `.:?`, `/=`, and a read in `classifyReplay` before the hash check. Three tests. Drift D7 filed as REPLAY-CODEGEN-VERSION-1. | §4.8, §2.2 |
| N5. Qualified text missing on V5 and V9 | second pass, fold | The `refuted` and `measure-not-decreasing` texts are qualified whenever any WD id of the function fails. | §4.4 |
| N6. "6 against 1" compares a check with no check | second pass, fold | "5 against 1, on functions that both rules check". | §7.2, §4.2 |
| N7. The canonical model needs two conditions | second pass, fold | The theorem is relative to the trust closure. The junk choice satisfies the ground facts. | §4.5 |
| N8. Stale references | second pass, fold | `exprToPred` lines, S1 shipped as a guarded lemma, CALLEE-POST-UNASSUMED-1 shipped in v0.36.0, the parity test reads `bytesSetSpec`. | §2.1, §3.1, §4.1.1, §4.3, E17 |
| N9. V13 cannot have a test in this row | second pass, fold | V13 and its test move to POST-CONJ-SPLIT-1. | §4.4, §8 |
| W-Catalog sentence | second pass, fold | `Σ_ref` excludes the three builtins, so a parameter refinement cannot carry a partial read into `H`. | §4.3 |
| Self-framing paragraph | second pass, fold | Why callers need no self-contained post. | §4.2 |
| Dafny methods | second pass, fold | The comparison is against Dafny methods. | §4.2 |
| C1. `wd-post` for every function with a body VC | POST-CONJ-SPLIT-1 second pass | The `wd-post` set is "has a body VC", not "body-faithful". | §4.2, §4.7 |
| C2. Two rules agree with POST-CONJ-SPLIT-1 | POST-CONJ-SPLIT-1 second pass | The refuted rule uses the body-VC set. The fallback is per function in v1. Ship order. | §4.4, §4.7, E14 |
| PAIR-REFINE-ENTRY-1 settled | user decision | S7 becomes a fact in `H`. E19 becomes `verified`. | §2.2 D6, §4.3 S7, E19 |
| Proof-artifact version rule | user decision | `0.1.0` to `0.2.0`; v0.36.0 recorded as the exception. | §4.8 |

## Rev 2 changes (from the review of Rev 1)

| Finding | Severity | What Rev 2 did | Section |
|---|---|---|---|
| W1. False `ill-defined` from dropped hypotheses | blocking | Listed every drop site (S1-S8), each with a treatment. Stated the parity rule. | §4.3, E17-E19 |
| W2. Verdict combination not specified | blocking | Partitioned failing ids by clause tag. Stated the per-function rule, the precedence and a table with one test per row. | §4.4 |
| W3. Reversal rests on the weaker witness | complicates | §2.3 leads with `nc-004` and xm3. xm2 stays as the call-site case. | §2.3 |
| W4. Wrong Dafny citation | complicates | Removed the citation. Recorded the body-context rule as a divergence. Dropped `wd-post` for body-fallback functions. Measured the cost of each rule. | §4.2, §4.9, §7.2 |
| W5. Stripping proof incomplete | complicates | An induction over source order, and a dependency record. | §4.7 item 4 |
| W6. No soundness epoch in the artifact | complicates | Added `checker_soundness_version` to the artifact. | §4.8 |
| W7. One traversal | complicates | One function returns the term and its obligations. The `<=>` arm does not reuse the desugaring. | §4.1.1 |
| W8. Context rules correct | no change | `wd-pre` is always complete after S1 and S4. | §4.3 |
| W9. Junk-independence step | minor | Added the lemma and its induction. | §4.5 |
| W10. Smaller points | minor | Corpus wording, `ArithException`, qualified `refuted` text. | §7.1, §4.6, §4.4 |

## Summary

1. **Option (a): a well-definedness obligation for each admitted partial operation in a clause.** Three builtins need it: `map-get`, `bytes-get` and `bytes-set`. The obligation is the builtin's own precondition, the same term that the body emits as a `call-pre:<builtin>` obligation today.
2. **The obligation assumes the run-time evaluation context.** An earlier operand of `and` is assumed true. An earlier operand of `or` is assumed false. The antecedent of `=>` is assumed true. A `match` arm assumes its constructor test. This matches the generated Haskell (`CodegenHs.hs:2426-2431`, `esLazyOps` at `:3899-3900`).
3. **The obligation is emitted only where its hypotheses are complete.** The function must reach the arm where both clauses translate and no contract-level guard fires. `wd-post` also needs a body VC.
4. **A `post` obligation may assume the body's path facts.** This is a deliberate divergence from Dafny, which checks a method's specification without the body. The RFC 826 swarm posts depend on it (§4.2, §7.2).
5. **A clause is `verified` only when its truth and its well-definedness are both proved.**
6. **A failed obligation over complete hypotheses is a new hard verdict, `ill-defined`.** It is not `refuted`. `verify` exits 1.
7. **A failed obligation over marked hypotheses is a fallback of the whole function.** The cause is `clause-welldef-unproved` when only `wd-*` ids fail. §4.4 gives the full rule beside `abstraction-unsafe` and `callee-post-unassumed`.
8. **The run-time clause check is guarded.** A partial operation outside its precondition inside a clause reports a violation that names the clause.
9. **`checker_soundness_version` changes from `"6"` to `"7"`.** The proof artifact records it, replay reads it, and `proof_artifact_version` goes to `0.2.0`.
10. **Corpus impact is one change of exit status.** It is `f` in `scripts/doc-claims/contract-read-oob.llmll`, which exists to show this defect.
11. **The 2026-07-12 disposition is reversed.** Its soundness paragraph contradicts `nc-004` and ignores `--contracts=unproven` stripping (§2.3).

---

## 1. Restatement

`exprToPred` reflects `map-get`, `bytes-get` and `bytes-set` as total array terms (`Map_select`, `Map_store`). At run time the same operations call `error` outside their precondition. So `verify` can prove a clause that the built program cannot evaluate. The question is whether `verify` proves clause well-definedness as an obligation of its own, or refuses such terms in clauses. The proposal must also say what a failed obligation reports, how it combines with the other verdicts, how the run-time check of a clause behaves, and what changes in the records.

## 2. Context located

### 2.1 Artifacts

Line numbers are on main at `a339fbb8` (v0.36.0).

1. `docs/compiler-team-roadmap.md`, row CLAUSE-WELLDEF-1 (G1): the DECIDE cell this proposal answered.
2. `docs/compiler-team-roadmap.md`, rows CONTRACTS-ENTRY-STRIP-1, PRE-FAIL-EXIT-1, PAIR-REFINE-ENTRY-1, POST-CONJ-SPLIT-1: rows that this proposal orders against (§4.7).
3. The two professor reviews, folded in the Appendix. The first is archived at `docs/archive/professor-reviews/clause-welldef-review.md`.
4. CALLEE-POST-UNASSUMED-1, shipped in v0.36.0: `LLMLL.md:1160` (§5.3.4, the refutation rule), `compiler/src/LLMLL/AbstractionVerdict.hs:117-170` (`applyAbstractionVerdict`, `decide`).
5. `docs/archive/professor-reviews/post-conj-split-review.md` P3, P8: truth and well-definedness are separate obligations; a failure is a disproof only over authored hypotheses.
6. `docs/design/post-conj-split-proposal.md`: no per-conjunct stripping until this row ships. Its second professor pass gives C1 and C2.
7. **`docs/design/contract-position-reads-disposition.md` (settled 2026-07-12): the prior decision on this topic.** This proposal reverses it (§2.3).
8. `LLMLL.md:22` (`nc-003`, `nc-004`): a verified contract holds for all well-typed inputs under the call-by-value semantics of §4.7.
9. `docs/design/byte-io-proposal.md` line 414: "No pure operation is partial without a `pre` or a `Result`."
10. `compiler/src/LLMLL/FixpointEmit.hs:3846-4021` (`exprToPred`): the clause vocabulary.
11. `FixpointEmit.hs:4969-4986`, `:4994-5005`, `:5077-5090`: the body arms of `bytes-get`, `bytes-set` and `map-get`. Each emits its precondition as a PROVE obligation. The `bytes-set` arm reads its pre and its `lemma` part from `bytesSetSpec` (`:4563`).
12. `FixpointEmit.hs:6263` (`injectRangeFacts`), `:6366` (`injectBoolValRangeFacts`), `:6301-6320` (`storeLenFacts`): per-occurrence ground facts over LHS and RHS terms.
13. `FixpointEmit.hs:6553-6648` (`bytesLenParamPre`, `paramRefinementPre`, `augmentContractPre`, `returnRefinementPost`, `augmentContractPost`): parameter and return facts enter the effective pre and post.
14. `FixpointEmit.hs:1605-1626`: three contract-level guards (`contractSigGuardsBlock`, `wholeArrEqClause`, `mapClauseBlocked`) refuse a contract after a successful translation. `:1649-1661`: the `case (mPostPred, mPrePred)` arms; the `(Just postPred, Just mPre)` arm is at `:1661`.
15. `FixpointEmit.hs:1054` and following: FQ-FREEVAR-GUARD-1 routes a function whole when one of its constraints names a free symbol.
16. `compiler/app/Main.hs:1664-1690`: `bodyFaithfulSet`, `measureNotDecreasingSet`, `refutedSet`, `descentDischargedFns`.
17. `compiler/src/LLMLL/Contracts.hs:180-190` (`instrumentClosure`), `:232-243` (`filterContracts`), `:314-348` (`wrapPre`, `wrapPost`).
18. `compiler/src/LLMLL/CodegenHs.hs:543-554`, `:578-581`, `:896-898`, `:2423-2437`, `:3899-3900`: the run-time builtins, `emitOp` and the lazy operators.
19. `compiler/src/LLMLL/VerifiedCache.hs:351`, `:398-399` (`checkerSoundnessVersion = "6"`, compared with `/=`).
20. `compiler/src/LLMLL/ProofArtifact.hs:209-224` (`ComposedVersions`, `liveComposedVersions`), `:243` (`proofArtifactVersion = "0.1.0"`), `:277-292` (`classifyReplay`), `:319-321` (`ComposedVersions` parse with `.:`); `docs/proof-artifact.schema.json`.
21. `CHANGELOG.md` §v0.8.1b (2026-05-01): the body-faithful stripping rule under `--contracts=unproven`.
22. `LLMLL.md §3.4.4` (W-Catalog, `Σ_ref`): a refinement predicate cannot name `map-get`, `bytes-get` or `bytes-set`.

### 2.2 Drift found while reading

- **D1. `--contracts=unproven` does not strip a verified post in the entry module.** Filed as CONTRACTS-ENTRY-STRIP-1 (G3, PLAN). It ships after this row (§4.7).
- **D2. `LLMLL.md §13.12` states the `bytes-set` precondition as `0 ≤ i < n`.** The run time and the body obligation also require `0 ≤ v ≤ 255` (`CodegenHs.hs:553`, `bytesSetSpec`). `LLMLL.md:776` and `:1134` state the range. The table row (`:3343`) should move to match.
- **D3. The disposition's soundness paragraph is false under `--contracts=unproven`, and it was false when written.** §2.3.
- **D4. The run-time message misleads in a clause.** `map-get` on an absent key prints "map-has is the required pre" (`CodegenHs.hs:581`). In a clause, the defect is in the clause.
- **D5. The clause side had less sealed-builtin knowledge than the body side.** Closed in v0.36.0 by BYTES-SET-CLAUSE-LEN-1 (commit 6adae19e). The clause side now carries the guarded lemma `π_bytes-set ⟹ bytesLen(Map_store(b,i,v)) = bytesLen(b)` (`storeLenFacts`, `FixpointEmit.hs:6316-6320`). Both sides read it from `bytesSetSpec`.
- **D6. A refinement alias at a pair component was neither assumed nor proved.** Witness cwd2/pc3.llmll: `h [p: (Idx, int)]`, where `Idx` is `0 ≤ i < 4`, and a caller `c` with body `(h (pair 9 n))`. `check` and `verify` pass, exit 0. cwd2/pc2.llmll: a post `(< (first p) 4)` on the same `h` is `refuted`. `resolveAllRefinements` (`FixpointEmit.hs:6485-6489`) returns nothing for a `TPair`. **Settled 2026-11-04 as PAIR-REFINE-ENTRY-1, option A:** a pair component is an introduction site at any depth. Callers prove the component predicate, and the callee assumes it. Site S7 changes to match (§4.3).
- **D7 (new, second pass). Replay does not compare `codegen_semantics_version`.** `docs/proof-artifact.schema.json:36-39` says that replay fails closed on a mismatch. `classifyReplay` (`ProofArtifact.hs:277-292`) does not read the field. Filed as REPLAY-CODEGEN-VERSION-1. The epoch check of this row must not copy that pattern (§4.8).

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
| `map-get m k` | Yes (`FixpointEmit.hs:3955-3958`). Not on a literal `(map-empty)` (`:3950`). | `error` when `k` is absent (`CodegenHs.hs:578-581`) | `Map_select(m$val, k)`, total. On `map-empty`, the value array is `Map_default 0`. | pre, post | `w1_mappost`, `w3_mappre`, xm2, xm3 |
| `bytes-get b i` | Yes (`:3933-3934`) | `error` unless `0 ≤ i < len` (`CodegenHs.hs:545-548`) | `Map_select(b, i)`, total | pre, post | `w2_bytespost` |
| `bytes-set b i v` | Yes (`:3935-3936`) | `error` unless `0 ≤ i < len` and `0 ≤ v ≤ 255` (`CodegenHs.hs:550-554`) | `Map_store(b, i, v)`, total, with the guarded length lemma (D5, closed) | pre, post | `w12_bytesset`, `bl.llmll` |
| `/`, `mod` | Only with a numeral divisor above 0, or a ground divisor that folds above 0 (`:3898`, `GuardClassifier.hs:342-352`) | Haskell `div`, `mod` (`CodegenHs.hs:2434-2437`) | SMT `div`, `mod`; agrees for a positive divisor | none in the logic | — |
| `/`, `mod` with another divisor; `rem`, `^`, `**` | No (`:3900`) | `ArithException` (`divide by zero`) for a zero divisor | — | run time only | `w5_divclause` |
| `unwrap` | No (no case) | `error` on `Error` (`CodegenHs.hs:896-898`) | — | run time only | `w6_unwrap` |
| `map-get` or `map-has` on a literal `(map-empty)` | No (`:3949-3950`) | `map-get` calls `error` | — | run time only | — |
| `list-head`, `list-tail`, `list-nth`, `string-to-int` | No | Total: they return `Result` | — | none | — |
| `string-char-at`, `string-slice` | No | Total: they clamp | — | none | — |
| `first`, `second`, pair construction | Yes (`:3922-3924`) | Total | Total selectors | none | — |
| `match` on a variable | Yes (`:3992-4020`) | `case`; `check` rejects a non-exhaustive match | Selectors under constructor tests | none | `w13_match` |
| `min`, `max`, `abs` (marked), `compare`; the three lengths; `map-has`, `map-put`; `ok`, `err`, `is-ok`, constructors; literals | Yes | Total | Total | none | — |
| A user function call | No (POST-CALL-XMOD-1 is open) | The callee's own pre check runs inside the clause | — | run time only | — |
| `if`, `let`, `lambda` | No (`:4021`) | — | — | none | — |

So exactly three admitted builtins are partial at run time and total in the logic: `map-get`, `bytes-get` and `bytes-set`. The n-ary `and` cannot occur: `check` rejects `(and a b c)` (`w8_nary`).

### 3.2 Pre, post and body

- **Body: already covered.** A partial builtin in a body emits its precondition as a PROVE obligation, tagged `call-pre:<builtin>` (`FixpointEmit.hs:5077-5090` for `map-get`). A failure is `refuted` (`w7_bodyget`). Every body read must first prove presence or bounds, so a body term never reads a junk value.
- **Post: exposed.** `mapdef.llmll`, `w1_mappost`, `w2_bytespost` and `w12_bytesset` are `verified` and write a sidecar. Each built program stops when it evaluates the post. xm3 shows the stripped case, where the program does not stop.
- **Pre: exposed, in two ways.** First, evaluating the pre can stop the program before the check reports (`w3_mappre` prints the `map-get` message, not `Precondition violated in g`). Second, a caller can discharge an ill-defined pre from an encoding artefact (xm2).
- **The guarded idiom works at run time.** `w14_shortcircuit`: `(pre (and (map-has m 3) (> (map-get m 3) 0)))` on `(map-empty)` reports `Precondition violated in g2`. The `=>` form passes.

## 4. Design

### 4.1 The obligation

Each partial builtin `f` has one precondition `π_f`, over the reflected arguments:

```
π_map-get(m, k)      =  Map_select(m$has, k) = 1
π_bytes-get(b, i)    =  0 ≤ i  ∧  i < bytesLen(b)
π_bytes-set(b, i, v) =  0 ≤ i  ∧  i < bytesLen(b)  ∧  0 ≤ v  ∧  v ≤ 255
```

These are exactly the `pre` terms of the three body arms (`FixpointEmit.hs:4969-4986`, `bytesSetSpec` at `:4563`, `:5077-5090`). **Rule: the body arm and the clause obligation read `π_f` from one table.** A second copy can drift, and that has happened before (`sealedAxiomBuiltins`, `FixpointEmit.hs:381-382`). `bytesSetSpec` already is that single source for `bytes-set`. The table extends the same pattern to the other two builtins.

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

The folded refinements are not part of `e`. The DEF-RET return refinement and the `bytes[n]` return length are appended to the effective post (`augmentContractPost`). The run-time check does not evaluate them. So `WD` walks the authored clause only, and the folded conjuncts enter neither `C` nor `H`.

#### 4.1.1 One traversal for the term and its obligations (W7)

**Rule: one function returns both the term and the obligations.** Its shape is `exprToPredWD :: Ctx -> Expr -> Maybe (FQPred, [Obligation])`. `exprToPred` becomes `fmap fst . exprToPredWD []`. A new admitted form then cannot get a term without an obligation. The table maps each arm of `exprToPred` to its `WD` rule. Lines are `FixpointEmit.hs` at `a339fbb8`.

| `exprToPred` arm | Lines | `WD` rule |
|---|---|---|
| `EVar`, literals, string literal | `:3851-3862` | none |
| Marked `min`, `max`, `abs` (`intBuiltinTag`) | `:3866-3867` | total: union over the arguments |
| Bool bridge: `map-get` against a bool literal, either order | `:3878-3884` | the `map-get` rule applies to the inner `map-get`. The bridge changes the comparison term only. |
| Comparisons, `+`, `-` | `:3886-3894` | total: union over both operands |
| `constArithTerm` (`*`, `/`, `mod` with a numeral or folded divisor above 0) | `:3898` | total: the arm admits a positive divisor only |
| `and`, `or` | `:3901-3902` | the context rules. The arm maps a list (`mapM`), so the walk folds left to right. `check` admits two operands only. |
| `not` | `:3903` | union over the operand |
| `=>` | `:3907` | desugars to `(or (not p) q)`. The `or` rule then gives `C ∧ ¬¬⟦p⟧` for `q`, which is the `=>` rule. Reuse is correct here. |
| `<=>` | `:3908-3909` | **must not reuse the desugaring.** The desugared form `(and (or (not p) q) (or (not q) p))` would give `q` the context `⟦p⟧`. The run time evaluates both operands with no context. The walk takes this arm on the source form, before the desugaring. |
| `string-length`, `list-length`, `bytes-length` | `:3914-3915`, `:3932` | total: union over the operand |
| `first`, `second`, `EPair` | `:3922-3924` | total: union over the operands |
| `bytes-get`, `bytes-set` | `:3933-3936` | partial: `π_f`, plus the operands |
| `map-has`, `map-get` on a literal `map-empty` | `:3949-3950` | refused, so no obligation; the run-time guard applies (E15) |
| `map-has` | `:3951-3954` | total. The map argument goes through `mapPairTermsC`. Each key and value of a `map-put` chain is walked, because `map-put` is strict. |
| `map-get` | `:3955-3958` | partial: `π_map-get` over the has-array of the same `mapPairTermsC` pair, plus the map argument and the key |
| `EOp` | `:3960` | delegates to the `EApp` arm, as `exprToPred` does |
| `ok`, `err`, a constructor | `:3964-3970` | total: union over the arguments |
| `is-ok` on a variable | `:3974-3975` | none |
| `match` on a variable | `:3992-4020` | arm `i` under `C ∧ test_i ∧ ⋀_{j<i} ¬test_j`, with the same selector substitution. The arm's `prior` list already holds the earlier tests (`:4010`). |
| everything else | `:4021` | refused |

### 4.2 Emission gate and hypotheses

**The emission gate (N1, C1).** A function emits `wd-*` constraints only when it reaches the `(Just postPred, Just mPre)` arm of `FixpointEmit.hs:1661`. A function reaches that arm only when both its effective pre and its effective post translate and no contract-level guard fires (`contractSigGuardsBlock`, `wholeArrEqClause`, `mapClauseBlocked`, `:1605-1626`). Inside the arm:

- **`wd-pre`** is emitted for every function. The arm binds and sorts the parameters, so the constraint is well-scoped and well-sorted.
- **`wd-post`** is emitted on each path of every function **with a body VC**. Before POST-CONJ-SPLIT-1, that set is `erBodyFaithfulFns`. After it, the set is the union of `erBodyFaithfulFns` and `erPartlyProvedFns`. A partly proved function then gets `wd-post` constraints for its admitted conjuncts.
- A function in the arm with no body VC (`FallbackBody`, `FallbackPathCap`) gets `wd-pre` only (site S5, E20).

Every other function emits no `WD` constraint: a refused post, a refused pre (site S4), a hole, a function with no post, and a contract that a guard refused. The run-time guard (§4.6) covers each of them. The two rules hold together: N1 says where a `wd-*` constraint may exist at all, and C1 says which functions in that arm get `wd-post`.

A contract-level guard can refuse a pre that `exprToPred` translates. The third guard exists because such a clause "would reflect against binders that don't exist (or at the wrong element sort)". FQ-FREEVAR-GUARD-1 catches a free symbol, but not an ill-sorted term. An ill-sorted constraint is `FQError` for the whole file. So "the pre translates" is not a safe gate, and the arm is.

**Hypotheses.** Each obligation in `WD` becomes one Horn constraint. Its hypotheses `H` depend on the clause:

- **`pre`.** `H` = the parameter facts only: the translated `paramRefinementPre` (refinement aliases, pair-component refinements after PAIR-REFINE-ENTRY-1, and `bytesLen(b) = n`), the binder facts (`enumTagDomain`) and the per-occurrence ground facts. The pre itself is not assumed. Its earlier conjuncts enter through `C`. One constraint set per function. Tag: `wd-pre`.
- **`post`, function with a body VC.** `H` = the environment of the truth constraint on each path: the pre, the path guards, the binder facts, the assumed callee posts and the ground facts. One constraint per path, as for truth. Tag: `wd-post`.
- **`post`, function with no body VC: no constraint (W4).** Without the body, `result` is free, so the constraint can never be complete. It would only add a second fallback cause.

The constraint is `H ∧ C ⟹ π_f(…)`. It sits in the same `.fq` file and the same solver run as the truth constraints.

**Why a post may assume the body's facts. This is a deliberate divergence from Dafny.** The comparison is against Dafny **methods**. LLMLL functions are pure, but their posts are checked against a body as a method's are. Dafny checks the well-formedness of a method's specification in a separate procedure. That procedure assumes the precondition, makes the outputs arbitrary and does not read the body. In Dafny, `ensures m[3] == 0` on a method whose body builds `map[3 := 0]` fails with "element might not be in domain". LLMLL uses the run-time-error reading instead: the post must be defined in each state where the program evaluates it. The generated code evaluates the pre, then forces the body to WHNF with `!result`, then evaluates the post (measured on xm2's `Lib.hs`). So each path fact holds when the post runs. `nc-001` makes the generated program the semantics of record. Rev 1 cited Dafny for this rule. That citation was wrong, and Rev 2 removed it. SPARK 2014 agrees with the chosen rule: GNATprove checks run-time errors in a `Post` aspect at the subprogram's return points, in the context of the body.

**Why callers need no self-framing post.** Self-framing protects a modular reasoner that does not see the body. LLMLL's verifier always sees the body of a function with a body VC. A `wd-post` proof quantifies over every run that reaches the post, and every call is such a run. So at a caller, the assumed callee post reads only positions that the run makes defined. By the lemma of §4.5, the assumption has its run value. A caller cannot use a post that is not self-framing to read junk, because the caller's own reads carry `call-pre` or `WD` obligations.

The cost of each rule, measured in §7.2:

- **Spec-local rule (Dafny).** A post is self-framing: a caller can read presence from it, and a body edit cannot make a fixed post ill-defined. Every `wd-post` constraint is complete, so no mark applies to it. Cost: 4 agent-written posts in the 2026-09-11 RFC 826 run become `ill-defined`. They hold today and hold under the body-context rule.
- **Body-context rule (chosen).** It accepts those 4 posts. Cost: a `wd-post` constraint shares its environment with the truth constraint, so it inherits the callee marks (§4.3). A body edit can make a fixed post ill-defined. The verifier reports that edit as `ill-defined` on the next run, so the cost is a re-verification, not a silent defect.

**Why the pre may not assume itself.** The program evaluates the pre to decide whether the pre holds. Assuming it would make `(pre (> (map-get m 3) 0))` prove its own definedness. This agrees with Dafny's rule for `requires`.

**The hypotheses rest on assume-guarantee.** `H` for `wd-pre` holds the parameter refinements. A caller proves them at each call (`LLMLL.md §5.3.4`). An unverified caller lowers the trust level through the trust closure, as for every truth constraint.

### 4.3 Dropped hypotheses (W1)

A failing `wd-*` constraint is a disproof only when its `H` holds every fact that a run guarantees at that point. This is the P8 rule of the POST-CONJ-SPLIT-1 review, now `LLMLL.md:1160`. A site where the emitter omits such a fact is a **drop site**. Each drop site gets one of three treatments. **Prerequisite**: a row ships first and closes the site. **No emission**: the proposal emits no `wd-*` constraint there. **Mark**: the constraint carries a mark, and a failure is a fallback, never `ill-defined`.

The inventory comes from reading the clause translation (`exprToPred`), the fact injections (`injectRangeFacts`, `injectBoolValRangeFacts`, `injectStrLitDistinct`), the parameter and return folds and the call arms.

| Site | What is missing | Witness | Treatment |
|---|---|---|---|
| **S1. Sealed-builtin lemma in a clause.** | `bytesLen(Map_store(b,i,v)) = bytesLen(b)`. | profrev/bl.llmll: a true post was `refuted` before v0.36.0. | **Closed by a prerequisite.** BYTES-SET-CLAUSE-LEN-1 shipped in v0.36.0 (6adae19e) as the guarded lemma `π_bytes-set ⟹ bytesLen(store) = bytesLen(b)` (`storeLenFacts`). |
| **S2. Callee post not assumed.** | The callee's post, when it does not translate at the call (`cvPostUnassumed`). | the CALLEE-POST-UNASSUMED-1 witnesses | **Mark** `post-unassumed`, the field that row shipped. |
| **S3. Two calls to one callee.** | Congruence between two results (partly closed by CALL-CONGRUENCE-1). Also the facts of a builtin in `abstractedBuiltins` (empty today). | the ABSTRACTION-VERDICT-1 witnesses | **Mark** `abstraction`, unchanged. |
| **S4. Contract refused (N1).** | The alias fact of a parameter refinement outside the fragment, or any fact of a clause that a contract-level guard refused. One refused conjunct refuses the whole effective pre. | profrev/rb.llmll: `h` falls back with `contract-pre-outside-fragment` | **No emission.** The function does not reach the arm of `:1661` (§4.2). It already falls back whole, so a mark would only add a second cause. |
| **S5. No body VC.** | Every path fact. | `use-mk` (E8) | **No emission** of `wd-post` (§4.2). `wd-pre` is still emitted inside the arm (E20). |
| **S6. Earlier conjunct refused (POST-CONJ-SPLIT-1 only).** | The earlier conjunct, which has no FQ form and cannot enter `C`. | the split's E13 | **Mark** `dropped-context`. POST-CONJ-SPLIT-1 adds it. |
| **S7. Pair component refinement.** | Before PAIR-REFINE-ENTRY-1: `0 ≤ first p < 4` for `p : (Idx, int)`. | cwd2/pc2.llmll, cwd2/pc3.llmll, cwd2/e19.llmll | **Not a drop.** See below. |
| **S8. Free symbol in a `wd-*` constraint.** | — (the constraint is ill-scoped) | none built | **No verdict.** FQ-FREEVAR-GUARD-1 routes the function whole, with cause `constraint-symbols-unbound`. An ill-sorted term is not caught there. The gate of §4.2 (N1) keeps such a term out of every `wd-*` constraint. |

**Site S7 after PAIR-REFINE-ENTRY-1.** PAIR-REFINE-ENTRY-1 (settled 2026-11-04, option A) makes each pair component an introduction site, at any depth. The predicate of each component is instantiated at its selector path and joins the effective pre at a parameter and the effective post at a return. Callers prove it, and the callee assumes it. So the fact `0 ≤ first p < 4` is in `H` for `wd-pre` and `wd-post`, through `paramRefinementPre`. S7 is then not a drop site and not an `ill-defined` site. E19 is `verified`. The parity rule holds, because one function produces the conjunct for both sides. Until PAIR-REFINE-ENTRY-1 ships, no caller proves the fact and no run checks it, so a run can reach the undefined read, and `ill-defined` is the correct verdict. A list element or map value refinement stays outside `H` and is not proved at callers. `ill-defined` is then correct for a read that depends on it, by the same argument. LIST-REFINE-ENTRY-1 decides that case.

**A refinement predicate cannot carry a partial read into `H`.** `LLMLL.md §3.4.4` (W-Catalog) excludes `map-get`, `bytes-get` and `bytes-set` from `Σ_ref`. So `paramRefinementPre` adds no partial read to `H`. A future extension of `Σ_ref` must add a drop site here.

**Sites checked and found complete.** The byte-range fact `0 ≤ select ≤ 255` reaches a clause select, including a select of a `Map_store` chain over a bytes root (`injectRangeFacts`; profrev/br.llmll verifies). The `{0,1}` fact of a bool-valued map reaches a clause select over a parameter or `result`, and over a `map-put` chain on one (`injectBoolValRangeFacts`). The three length measures get `t ≥ 0`. String literals get pairwise distinctness. Each injection reads LHS and RHS terms, so it covers the new `π_f` terms. A `bytes[n]` return length is a goal, not a hypothesis. On a path with a body VC, the facts that prove that goal are in `H` too. A solver crash (CTOR-FIELD-SORT-1) is `FQError`, not UNSAFE, so it cannot produce `ill-defined`.

**The parity rule keeps the inventory complete.** A change that adds a fact on the body side, or a lemma part to a sealed-builtin arm, must add the same fact on the clause side or add a mark. One hspec test reads the `lemma` parts of `bytesSetSpec` and of every other clause-admissible sealed builtin, and checks that the clause reflection carries each one. This is the `sealedAxiomBuiltins` single-site discipline applied to lemmas.

**Consequence (W8).** A `wd-pre` constraint has no call binders and no abstraction. After S1 and S4, it is always complete. So a `wd-pre` failure is always `ill-defined`.

### 4.4 Verdicts and their combination (W2)

The verdict is decided per function, on the path that `applyAbstractionVerdict` owns (`AbstractionVerdict.hs:117-170`), as shipped by CALLEE-POST-UNASSUMED-1. Each failing id of a function belongs to one **partition** by clause tag:

- **WD**: `wd-pre`, `wd-post`.
- **MEAS**: `descent`, `decreases`.
- **TRUTH**: every other tag (`body-post`, `call-pre:*` and the rest).

Each failing id is **complete** or **marked** (marks: `post-unassumed`, `abstraction`, and `dropped-context` after POST-CONJ-SPLIT-1).

**The rule, per function.**

1. **A complete failing id in any partition makes the verdict hard.** The function gets each hard marker whose partition holds a complete id: `ill_defined` for WD, `measure-not-decreasing` for MEAS, `refuted` for TRUTH. `refuted` also needs a function with a body VC: body-faithful today, body-faithful or partly proved after POST-CONJ-SPLIT-1. A marked failing id never sets a hard marker. This is rule 2 of ABSTRACTION-VERDICT-1: one complete id blocks the fallback. `verify` exits 1.
2. **Otherwise, a marked failing id makes the whole function fall back, with one cause.** The cause is chosen in this order:
   1. every failing id is in WD: `clause-welldef-unproved`;
   2. every failing id carries the `abstraction` mark: `abstraction-unsafe`;
   3. some failing id carries the `post-unassumed` mark: `callee-post-unassumed`;
   4. otherwise: `abstraction-unsafe`, named by the first `abstraction`-marked id.
   `verify` exits 0 with the warning for that cause.
3. **No failing id: no change.** Truth decides the verdict.

A `dropped-context` id contributes its construct to the list. It never chooses the cause when a non-WD id also fails. Step 4 is reachable only through such an id, so it cannot occur before POST-CONJ-SPLIT-1, and it needs no test in this row. Step 4 matches the shipped `decide` (`AbstractionVerdict.hs:149-156`).

**Rule 1 changes an output of CALLEE-POST-UNASSUMED-1 (N3).** Today `refutedSet` (`Main.hs:1676-1680`) counts every failing id of a blocked function, marked or not. Under rule 1 it counts complete TRUTH ids only. Example: a function with a complete `descent` id and a marked `body-post` id. Today it is `measure-not-decreasing` and `refuted`. After this row it is `measure-not-decreasing` only (row V14). The change applies the P8 rule to the marker as well as to the fallback: a marked failure is not a disproof.

**Precedence of the hard markers in text and in `--strict-verified-core` messages:** `ill-defined`, then `measure-not-decreasing`, then `refuted`. All three can be set together. A well-definedness failure comes first because a counter-model of the other partitions may read a term at an undefined point. The converse does not hold. A WD constraint's goal is a precondition over reflected arguments whose own WD obligations are in the same set.

**Qualified text (N5).** When any WD id of the function fails, complete or marked, the `refuted` and `measure-not-decreasing` texts are qualified. With a complete WD id the text says: "the counter-example may sit at a point where the clause is undefined; fix the `ill-defined` clause first". With a marked WD id only it says: "the counter-example may sit at a point where the clause is not proved defined". A `descent` constraint assumes the pre. If the pre is ill-defined, the counter-model can choose junk that makes the pre true in a state where the run stops in the pre. So `measure-not-decreasing` can be spurious too.

**Why `clause-welldef-unproved` comes first among the causes.** It says that the clause's truth was proved and only its definedness was not. A truth failure in the same function is the larger fact, so steps 2-4 apply whenever a TRUTH or MEAS id also fails. The cause names the reason as a construct: `welldef:post-unassumed:app:<g>`, `welldef:abstraction:app:<g>` or `welldef:dropped-context`.

**Positioning against CALLEE-POST-UNASSUMED-1.** That row made `callee-post-unassumed` the cause when a marked TRUTH id fails. This row adds no mark of its own to TRUTH ids. It reuses the `post-unassumed` and `abstraction` marks on WD ids. So `clause-welldef-unproved` is a fallback cause beside the other two, and `ill-defined` is a hard verdict beside `refuted`. The one change for a function with no `wd-*` id is the `refutedSet` change above.

| # | Failing ids of the function | Outcome | Exit | Test |
|---|---|---|---|---|
| V1 | none | unchanged | as today | `wd-safe-guarded` (E2) |
| V2 | WD complete only | `ill-defined` | 1 | `wd-ill-post-mapdef` (E1) |
| V3 | WD complete, TRUTH complete | `ill-defined` and `refuted`; `refuted` text qualified | 1 | `wd-ill-and-refuted` (E3, empty body, post `(= (map-get result 3) 1)`) |
| V4 | WD complete, TRUTH marked | `ill-defined` only; the marked TRUTH id is not counted | 1 | `wd-ill-pre-truth-marked` (a `wd-pre` failure, and a body call to a callee with a refused post that makes the post fail) |
| V5 | WD marked, TRUTH complete | `refuted` only, text qualified; no `welldef_unproved` entry | 1 | `wd-marked-refuted` (two branches: a marked `wd-post` failure on one, a complete truth failure on the other) |
| V6 | WD marked only | fallback, `clause-welldef-unproved` | 0 | `wd-unproved-post-unassumed` (E13) |
| V7 | WD marked, TRUTH marked, `post-unassumed` on some | fallback, `callee-post-unassumed` | 0 | `wd-and-truth-unassumed` |
| V8 | WD marked, TRUTH marked, `abstraction` on all | fallback, `abstraction-unsafe` | 0 | `wd-and-truth-abstraction` |
| V9 | WD complete, MEAS complete | `ill-defined` and `measure-not-decreasing`; `measure-not-decreasing` text qualified | 1 | `wd-ill-measure-bad` |
| V10 | WD marked, MEAS complete | `measure-not-decreasing` only, text qualified | 1 | `wd-marked-measure-bad` |
| V11 | WD marked, MEAS marked | fallback, cause by steps 2-4, with `W-DECREASES-UNDISCHARGED` | 0 | `wd-marked-measure-marked` |
| V12 | `wd-pre` complete in a function with no body VC | `ill-defined`; the function keeps its fallback cause too | 1 | `wd-ill-pre-fallback-body` (E20) |
| V13 | WD marked `dropped-context` only | **deferred to POST-CONJ-SPLIT-1.** The whole function falls back with `clause-welldef-unproved`, and every conjunct is `asserted` | 0 | moves to POST-CONJ-SPLIT-1 (E14) |
| V14 | MEAS complete, TRUTH marked, no WD | `measure-not-decreasing` only (today also `refuted`) | 1 | `meas-complete-truth-marked` |

`FQError` and `FQResourceLimit` are whole-run answers and are unchanged. `--strict-verified-core` fails on each hard marker and on each fallback cause, as on any non-verified clause.

**`ill-defined` is not `refuted`.** `refuted` means the clause is false in a reachable state. `ill-defined` means the program cannot evaluate the clause in a reachable state. The REC-DESCENT precedent applies: `measure-not-decreasing` is kept out of `refutedSet` "so a pure measure failure is never mislabeled refuted" (`Main.hs:1672-1676`). `ill-defined` is an orthogonal marker, like `refuted` (`LLMLL.md:633`). It is not a `DisplayLevel` element. Unlike `refutedSet`, the `ill-defined` set does not require a body VC, because a `wd-pre` constraint does not read the body (V12). `measureNotDecreasingSet` does not require it either (`Main.hs:1674-1675`).

**Callers.** A caller assumes an `ill-defined` or `clause-welldef-unproved` post as it assumes an `asserted` post. The caller's level meets `asserted`. Neither post is stripped, so the callee's run-time check stops the program before a caller sees a value that violates the post. This argument depends on the fail-stop of a contract violation. PRE-FAIL-EXIT-1 records two handlers that catch `error` and turn it into a value (§4.7).

### 4.5 Soundness argument (W9, N7)

**Setting.** A run state `ρ` gives each variable a value. A partial operation applied in `ρ` is *defined* when its precondition holds in `ρ`. A model `M` of the encoding *agrees with `ρ` on defined reads* when each select at a defined position has the run's value in `M`. The canonical model takes the run's values at defined positions and junk values elsewhere.

**Two conditions on the canonical model (N7).** The canonical model satisfies `H` on a path with a body VC under two conditions.

1. **Assumed callee posts.** `H` holds each assumed callee post. The canonical model satisfies a callee post only if that post is true in the run at defined positions and reads no undefined position. That is true when the callee's truth and `WD` are both proved. Otherwise the caller is `asserted` through the trust closure. So the theorem below holds relative to the trust closure, as `LLMLL.md §3.4.3` states for truth.
2. **Junk choice.** The junk values must satisfy the injected ground facts: the byte range `0..255` on every select of a bytes-rooted array, the `{0,1}` range of a bool-valued map, and the guarded `bytes-set` length lemma. Each range contains the encoding default `0`, and each lemma is guarded by `π_bytes-set`, so such a choice exists. Two run values with different `bytesLen` must stay distinct arrays. Free junk positions allow this.

Each reflection equation in `H` then holds, because each body read is defined (its `call-pre:<builtin>` obligation holds).

**Lemma (junk independence).** Let `C` hold in `ρ`, and let every obligation in `WD(C, e)` be valid. Then the program evaluates `e` in `ρ` without an error, and `⟦e⟧` has the run's value in every model `M` that agrees with `ρ` on defined reads.

Proof by induction on `e`.
- Variable or literal: immediate.
- Total operation: by the induction hypothesis on each argument. Each argument is evaluated (`esForceArgs`), and the operation is a function of the argument values.
- Partial operation `f`: by the induction hypothesis, each argument has its run value in `M`. The obligation `C ⟹ π_f` is valid and `C` holds, so `π_f` holds in `ρ`. The read is defined, so `M` gives it the run's value.
- `(and a b)`: the hypothesis on `a` (context `C`) gives `⟦a⟧ = eval_ρ(a)`. If `a` is false, both sides are false and the run does not evaluate `b`. If `a` is true, `C ∧ ⟦a⟧` holds in `ρ`, and the hypothesis on `b` applies.
- `(or a b)`, `(=> a b)`: the same argument with `¬⟦a⟧` and `⟦a⟧`.
- `(<=> a b)`: both operands under `C`, as the run evaluates both.
- `(match x …)`: exactly one arm `i` has its test true and every earlier test false in `ρ`. The reflected conjunction holds each other arm vacuously: an arm `j < i` has a false test, and an arm `j > i` has the true test `test_i` in its `prior` list (`FixpointEmit.hs:4010`). So `⟦e⟧` equals arm `i`'s term. The hypothesis on arm `i` under `C ∧ test_i ∧ ⋀_{j<i} ¬test_j` gives its value.

**Theorem.** Relative to the trust closure: if the truth constraint of a clause is valid, and every `WD` obligation of the clause is valid, then the clause holds in every run that reaches it. Proof: take the canonical model of the run state. Under the two conditions it satisfies `H`. Validity gives `⟦e⟧` true in it. The lemma gives `eval_ρ(e) = ⟦e⟧`.

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

The guard matters most where `WD` does not apply: a refused clause with `unwrap` or a variable divisor, a `post` of a function with no body VC (S5), a function outside the arm of §4.2 (S4), and a clause that is `clause-welldef-unproved`.

### 4.7 Interactions and order

**Ship order.** BYTES-SET-CLAUSE-LEN-1 and CALLEE-POST-UNASSUMED-1 shipped in v0.36.0. This row ships next. POST-CONJ-SPLIT-1 ships after this row. CONTRACTS-ENTRY-STRIP-1 ships after this row too: today D1 keeps the run-time check of an entry-module post, so `mapdef.llmll` at least stops. D1 fixed alone would strip that post silently.

**PRE-FAIL-EXIT-1.** Independent in order. The "Callers" argument (§4.4) and the guard (§4.6) assume that a contract violation stops the program. That row decides whether the two catching handlers keep converting one into a value.

**POST-CONJ-SPLIT-1.** This row ships first, so the split carries the items below.

1. *Truth assumes no other conjunct; well-definedness assumes the earlier ones.* This is the split's §4.3 rule plus §4.1 here. The two rules do not conflict.
2. *A conjunct is `verified` only when its truth and its well-definedness are both proved.*
3. *`wd-post` for a partly proved function (C1).* `wd-post` is emitted on each path of every function with a body VC, which after the split is the union of `erBodyFaithfulFns` and `erPartlyProvedFns` (§4.2). The split adds this as a row of its reader table.
4. *The refuted rule (C2).* Rule 1 of §4.4 reads "body-faithful or partly proved" after the split.
5. *The `dropped-context` mark (site S6, C2).* The split adds it: a `wd-post` obligation whose context omits a refused earlier conjunct carries the mark. A failure gives `clause-welldef-unproved`, never `ill-defined`. The fallback is per function in v1: in `(and (refused-guard r k) (= (map-get r k) 0))`, the whole function falls back, and every conjunct is `asserted` (E14). A per-conjunct fallback would need a sidecar `conjuncts` record on a run that is not SAFE, which no record defines.
6. *Per-conjunct stripping reopens (W5).* **Rule: under `--contracts=unproven`, strip conjunct `j` when its truth and its well-definedness are both verified. Keep every other conjunct, in source order.** Proof, by induction over source order. Fix a state that reaches the post, and let conjuncts `1 … j-1` each be true there or kept and checked. If a kept earlier conjunct is false, its check stops the program, and conjunct `j` is not evaluated. Otherwise every earlier conjunct is true, so `C_j` holds. `C_j` holds, so the `WD` obligation makes conjunct `j` defined there. Its truth proof makes it true. So a stripped conjunct is never the first to fail, and each kept conjunct is evaluated in the same states as before. Its definedness in those states is either proved or guarded at run time (§4.6). The Rev 1 sentence "a stripped conjunct is true in every state that reaches the post" was false. With `(and (map-has result 3) (= (map-get result 3) 0))` on `(map-empty)`, conjunct 2 is true in the logic and is stripped. In a run, conjunct 2 is undefined. The program is still safe, because conjunct 1 is kept and fails first. The induction covers this case.
7. *Record the dependency.* A conjunct whose `WD` obligation used an earlier conjunct `k` that is not verified is recorded as "defined given conjunct k". The record holds the index `k`. A reader then knows that stripping conjunct `k` later would need a new proof.
8. *Record wording.* The split's "proved as part of the post" becomes "proved, and defined where evaluated" for a conjunct whose obligation holds.
9. *Row V13 and its test* move to the split (§4.4).
10. *Versions.* The split takes the `proof_artifact_version` raise after `0.2.0`. `checker_soundness_version` is already `"7"` when the split ships. The split's byte-identical `.fq` sweep then compares files that already hold `wd-*` constraints.

**PAIR-REFINE-ENTRY-1.** Independent in order. Before it ships, a read guarded only by a pair-component refinement is `ill-defined`, which is correct (site S7). After it ships, the fact is in `H`, and the read is `verified`. Each order gives correct verdicts.

**CONTRACT-READ-LINT.** Keep the `contract-read-oob` warning (`Diagnostic.hs:255-260`). It is a `check`-time signal with no solver. Its slice, a literal index against a literal `bytes[n]`, is a subset of the `ill-defined` verdicts.

**ABSTRACTION-VERDICT-1.** Its mark applies to `wd-*` constraints unchanged (site S3).

**`decreases`.** Not covered. The run time does not evaluate a `decreases` measure (`CodegenHs.hs:2068-2070` emits it as a comment). See E9.

### 4.8 Schema and version delta

- **`checker_soundness_version`: `"6"` to `"7"`.** A sidecar written under `"6"` can record `verified` on a clause that contradicts `nc-004` (`mapdef.llmll`, `w2_bytespost`, `w12_bytesset`, `contract-read-oob.llmll`). Every sidecar reader then fails closed and asks for a new `verify`. AND-GUARD-PRE-1 set the precedent for `"6"`.
- **Proof artifact: the soundness epoch (W6, N4).** `ComposedVersions` gains `checker_soundness_version`. Without it, an artifact written by 0.35.1 replays its stored `.fq` as SAFE, and that `.fq` has no `wd-*` constraints. Four rules make the check work:
  1. **Parse.** The member parses with `.:?`. An artifact without it still parses, so it reaches `classifyReplay` and gets the reason text.
  2. **Compare.** `/=`, as the sidecar does (`VerifiedCache.hs:351`). A version string has no order in the code. So an artifact from a newer epoch also fails closed under an older binary.
  3. **Reader.** `classifyReplay` reads the member before the hash check. An absent or unequal value gives `ReplayFailClosed` with the reason "written under a different soundness epoch; re-verify". It never gives a verdict.
  4. **Comment.** The `liveComposedVersions` comment ("informational: `classifyReplay` does not read it") changes to say that `classifyReplay` reads the soundness member.
  Three tests: an absent member, an equal member and an unequal member. The writer always emits the member. A top-level field beside `codegen_semantics_version` is an acceptable alternative placement under the same four rules. Drift D7 is a separate row (REPLAY-CODEGEN-VERSION-1). This check must not copy it.
- **`proof_artifact_version`: `"0.1.0"` to `"0.2.0"`.** The rule from 2026-11-04: a new enum value in the proof artifact raises `proof_artifact_version`, because an old validator rejects it. This row adds the `fallback_reason` value `clause-welldef-unproved`, the `ill-defined` function marker and the epoch member. **Known exception:** v0.36.0 added `callee-post-unassumed` to the same enum and kept `0.1.0`. That release stays as shipped. So `0.1.0` admits `callee-post-unassumed` since v0.36.0. POST-CONJ-SPLIT-1 takes the next raise.
- **`verify --json`**: two new keys, `ill_defined` (a list of function names) and `welldef_unproved` (a list of function names with constructs), beside `abstraction_fallback`. Minor increase of `verify_json_version`. `solver_verdict` follows the `measure-not-decreasing` precedent; the engineer confirms its value.
- **`refutedSet`**: counts complete TRUTH ids of functions with a body VC only (N3, §4.4). This changes the `refuted` marker of a function with a complete MEAS id and a marked TRUTH id (V14).
- **Trust report**: marker `ill_defined` on the clause entry; the new fallback cause `clause-welldef-unproved`. Minor increase of `trust_report_version`; `docs/llmll-trust-report.schema.json` gains both. POST-CONJ-SPLIT-1 takes the next increase.
- **Constraint origins**: two new clause tags, `wd-pre` and `wd-post` (`DiagnosticFQ.hs:60`).
- **Diagnostics**: `clause-ill-defined` (error), with text such as `the post of 'mk' is not defined where it is evaluated: (map-get result 3) needs (map-has result 3)`; `W-CLAUSE-WELLDEF-UNPROVED` (warning).
- **`.fq`**: byte-identical for every function with no admitted partial operation in a translated clause. Other functions in the arm of §4.2 gain `wd-*` constraints. A function with no body VC gains `wd-pre` constraints only.
- **JSON-AST schema**: no change. **Surface syntax**: no change. No new builtin, construct, FFI tier or capability.
- **`codegen_semantics_version`**: no change. The guard changes a message and no value that a solver axiom relies on.

### 4.9 Options not chosen

- **(b) Refuse partial operations in clauses.** 90 clauses in 41 files use them (§7), nearly all in the guarded idiom. The RFC 826 swarm specifications and the netpbm swarm posts would fall back. A syntactic refusal also cannot accept a read that body facts make safe.
- **(c) Obligations in posts, refusal in pres.** Nothing makes a pre harder than a post. The pre obligation has fewer hypotheses.
- **(a) with the spec-local (Dafny) hypotheses for `wd-post`.** Every `wd-post` constraint would be complete, and posts would be self-framing. Rejected: 4 agent-written RFC 826 posts become `ill-defined` (§7.2), `nc-001` makes the run-time order the semantics of record, and callers do not need self-framing (§4.2).
- **(a) with "assume all conjuncts" instead of short-circuit context.** It would accept `(and (= (map-get m k) 0) (map-has m k))`, which stops at run time when `k` is absent.
- **A mark for a refused parameter refinement (review W1(b)).** Replaced by "no emission" (site S4). The professor withdrew the mark in the second pass: it changes no verdict, it needs a partial reflection that `FixpointEmit.hs:1613-1618` refuses on purpose, and the run-time guard covers the case.
- **Emission gated on "the pre translates".** Rejected (N1). A contract-level guard can refuse a translated pre, and an ill-sorted `wd-pre` constraint would be `FQError` for the whole file.
- **A per-conjunct fallback for `clause-welldef-unproved`.** Rejected for v1 (C2). It needs a sidecar `conjuncts` record on a run that is not SAFE.
- **A run-time guard alone, with no obligation.** It fixes the message, not the false `verified` record, the stripped post of xm3 or the call-site discharge of xm2.

## 5. Edge cases and degenerate inputs

**E1. `mapdef.llmll` (positive witness for `ill-defined`).** Input: `(def-shell mk [n: int] -> map[int,int] (post (= (map-get result 3) 0)) (map-empty))`. Behaviour: `wd-post` gives `Map_select(Map_default 0, 3) = 1` under the body facts. It is false, and the constraint is complete. Row V2: `ill-defined`, exit 1, no `verified` record. Channel: contract. Today `verified` (measured).

**E2. Guarded post.** Input: `w4_guarded.llmll`, `(post (and (map-has result 3) (= (map-get result 3) 7)))`. Behaviour: `C` gives the presence. SAFE. Row V1. Channel: contract.

**E3. Wrong conjunct order.** Input: `(post (and (= (map-get result 3) 7) (map-has result 3)))` with body `(map-empty)`. Behaviour: the `map-get` obligation has an empty `C` and fails. The truth fails too (`0 ≠ 7`). Row V3: `ill-defined` and `refuted`, with the qualified `refuted` text. With body `(map-put (map-empty) 3 7)`, both hold from body facts, and the function is `verified`. Channel: contract.

**E4. Pre that reads an absent key.** Input: `w3_mappre.llmll`, `(pre (> (map-get m 3) 0))`. Behaviour: `wd-pre` fails over the parameter facts. Row V2: `ill-defined`, exit 1. At run time, a call on `(map-empty)` reports `Precondition of g is undefined: map-get key 3 not present`. Channel: contract and run time.

**E5. The call-site discharge (xm2).** Behaviour: `mk` and `g` are `ill-defined`, so `mklib.llmll` exits 1. `c` assumes `mk`'s post and proves `g`'s pre as today, at level `asserted` through the trust closure. Neither post is stripped. Channel: contract and trust.

**E6. Bytes read past the length.** Input: `scripts/doc-claims/contract-read-oob.llmll`, `(post (>= (bytes-get b 9) 0))` on `bytes[8]`. Behaviour: `9 < 8` fails. `ill-defined`, exit 1. The `check`-time warning stays. Channel: type (lint) and contract.

**E7. `bytes-set` value out of range.** Input: `w12_bytesset.llmll`. Behaviour: two failing obligations, `9 < 4` and `300 ≤ 255`. `ill-defined`. Today `verified`. Channel: contract.

**E8. Post of a body-fallback function.** Input: `compiler/test/fixtures/map-ret-post/use.llmll`, `use-mk`, `(post (>= (map-get result k) 0))`, body `(mk k)`. Behaviour: the function has no body VC, so no `wd-post` is emitted (site S5). The verdict stays the existing fallback, with its one cause. At run time, the guard reports an undefined post. Channel: trust and run time.

**E9. A partial operation in `decreases`.** Behaviour: no obligation. The run time does not evaluate the measure. Its descent proof stays sound: the junk entries of the initial map are fixed once, and every later map is a `Map_store` chain over it. Channel: spec is silent (intentional).

**E10. A refused clause with a partial operation.** Input: `w5_divclause.llmll` (divides by the parameter `d`); `w6_unwrap.llmll`. Behaviour: no obligation; the clause is `asserted` as today. At run time, `(dv 0)` reports "Postcondition of dv is undefined: division by zero", where today it prints the `ArithException` text `divide by zero`. Channel: run time.

**E11. Short-circuit through `or` and `=>`.** Input: `(pre (=> (map-has m 3) (> (map-get m 3) 0)))` and the `or` form. Behaviour: both obligations hold from `C`. `w14_shortcircuit` shows that the run time agrees. Channel: contract.

**E12. `<=>` gives no context.** Input: `(post (<=> (map-has m k) (> (map-get m k) 0)))`. Behaviour: `C` is empty for `map-get`, so the obligation fails unless `H` gives presence. A walk that reused the `<=>` desugaring would wrongly accept it (§4.1.1). Channel: contract.

**E13. Callee post not assumed.** Input: a caller whose post reads `(map-get (callee x) k)` through a `let`-free path, guarded only by a fact that the callee's refused post would give, with the truth proved. Behaviour: the `wd-post` id carries `post-unassumed`. Row V6: fallback, `clause-welldef-unproved`, construct `welldef:post-unassumed:app:callee`. Channel: trust.

**E14. Split with a refused guard (POST-CONJ-SPLIT-1 E13).** Input: `(and (refused-guard r k) (= (map-get r k) 0))`. Behaviour after POST-CONJ-SPLIT-1: conjunct 2's id carries `dropped-context`. Row V13: the whole function falls back with `clause-welldef-unproved`, and every conjunct is `asserted`. No conjunct is stripped. The test belongs to POST-CONJ-SPLIT-1. Channel: trust.

**E15. Map read on a literal `map-empty`.** Input: `(post (= (map-get (map-empty) 3) 0))`. Behaviour: refused today (`FixpointEmit.hs:3950`), so no obligation. The run-time guard reports `Postcondition of f is undefined`. Channel: run time.

**E16. Nested partial reads.** Input: `(map-get m (map-get m2 k))`. Behaviour: two obligations, the inner `Map_select(m2$has,k)=1` and the outer `Map_select(m$has, Map_select(m2$val,k))=1`. The outer one is meaningful only because the inner one holds; the lemma's partial-operation case covers this. Channel: contract.

**E17. Read through a `bytes-set` (site S1).** Input: `(post (= (bytes-get (bytes-set b 0 7) 1) (bytes-get b 1)))` on `b: bytes[4]`. Behaviour: the outer obligation `1 < bytesLen(Map_store(b,0,7))` holds from the guarded length lemma that BYTES-SET-CLAUSE-LEN-1 shipped. The guard `π_bytes-set(b,0,7)` is provable wherever the inner obligation is, because the outer and the inner obligation share `H` and `C`. SAFE. Without that row, it would be a false `ill-defined`. Channel: contract.

**E18. Parameter refinement outside the fragment (site S4).** Input: profrev/rb.llmll with an added `(pre (> (bytes-get b i) 0))`, `i: Idx`. Behaviour: the effective pre does not translate, so the function does not reach the arm of §4.2. No `wd-*` constraint is emitted. The function falls back with `contract-pre-outside-fragment`, as today. At run time the guard covers the pre. Channel: trust and run time.

**E19. Pair component refinement (site S7).** Input: cwd2/e19.llmll, `h [b: bytes[4] p: (Idx, int)]` with post `(>= (bytes-get b (first p)) 0)`. Today `h` is body-faithful and `verified` (measured), with no definedness check. Behaviour after PAIR-REFINE-ENTRY-1: the fact `0 ≤ first p < 4` is in `H`, so the obligation `first p < 4` holds. `verified`. The call `(h (pair 9 n))` in cwd2/pc3.llmll is then refuted at its call-pre. If this row ships before PAIR-REFINE-ENTRY-1, `h` is `ill-defined` in the interval, which is correct then: a caller can pass `(pair 9 n)` with no obligation, and that run reaches the undefined read. Channel: contract. Cite: D6.

**E20. `wd-pre` in a body-fallback function.** Input: cwd2/e20.llmll, `(def-shell g [m: map[int,int] s: string] -> int (pre (> (map-get m 3) 0)) (post (>= result 0)) (string-length (string-concat s s)))`, a body outside the fragment. Behaviour: both clauses translate and no guard fires, so `g` reaches the arm of §4.2 and `wd-pre` is emitted. It fails and is complete. Row V12: `ill-defined`, exit 1. The function keeps `body-outside-fragment` as its fallback cause. Today `g` falls back with that cause and exits 0 (measured). Channel: contract.

## 6. Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| `wd-pre`: `facts(params) ∧ C ⟹ π_f(…)` | contract (PROVE) | (a) QF-LIA plus the array theory and the `bytesLen` measure; auto-discharged by liquid-fixpoint. The same class as today's `call-pre:<builtin>` body obligations. | `LLMLL.md §5.3.3` array class; `FixpointEmit.hs:4969-5090` |
| `wd-post`: `P ∧ path ∧ Γ ∧ C ⟹ π_f(…)` (functions with a body VC only) | contract (PROVE) | (a), as above; the same environment as the truth constraint | `LLMLL.md §5.3.3`, `§5.3.4` |
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
- **Limits.** The emulation cannot test a body-fallback function, because the extra post is only assumed. Those functions emit no `wd-post` (S5), so this limit does not affect a verdict. It also assumes the pre when it emulates a `wd-pre` obligation. The one pre in the corpus is guarded, so this does not change the count.
- **`.fq` changes** are limited to functions in the 41 files. The census baseline must be measured again.

### 7.2 The spec-local rule (the first review's open question)

Method. cwd2/wdspec.py adds, for each function with a `WD` obligation in its post, a sibling `def-shell <name>__spec`. The sibling has the same parameters plus `rr__` of the return type, the same pre, the post `C ⟹ π_f` with `result` renamed to `rr__`, and the body `0`. The body is a literal, so the post is proved from the pre and the parameter facts only. That is Dafny's well-formedness hypothesis set for a method. cwd2/spec_run.py runs `verify` on each of the 23 files and reports the sibling functions that fail. Results are in cwd2/spec.jsonl.

**The count is 5 under the spec-local rule against 1 under the body-context rule, on functions that both rules check.** `use-mk` is checked only by the spec-local rule. Under the chosen rule it has no body VC, so it emits no `wd-post` (S5) and the run-time guard covers it. It is unchecked, not shown to be defined.

| Rule | New `ill-defined` in non-mutant files, on functions both rules check | Which |
|---|---|---|
| Body-context (chosen) | 1 | `f` in `contract-read-oob.llmll` |
| Spec-local (Dafny) | 5 | the same `f` (by reading: `9 < 8` fails under any hypotheses; the script skips it because it has no `->`), and 4 agent-written posts in the 2026-09-11 RFC 826 run: `recv-merge` (`merge-before-opcode.llmll`), `recv-table` (`recv-table.llmll`), `merge-binding` (`spoof-binding.llmll`), `recv-table-framed` (`table-frame.llmll`) |
| Spec-local only | +1 | `use-mk` (fixture, body-fallback), which the body-context rule does not check |

The four RFC 826 posts read `(map-get result k)` or `(map-has result k)` with presence given only by the body's `map-put`. Their mutant twins also fail the spec-local sibling, but they are `refuted` already. The 2026-09-12 run's four files and `roots.llmll` are unaffected under both rules. The other direction is empty by construction: on each path, the spec-local hypotheses are a subset of the body-context hypotheses. The 18 files that were not run hold syntactically guarded reads, so `C` alone discharges them under both rules.

## 8. Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: `exprToPredWD`, with `exprToPred` derived from it (§4.1.1); a single `π_f` table read by the body arms and by `exprToPredWD`, on the `bytesSetSpec` pattern; emission inside the `(Just postPred, Just mPre)` arm only (`:1661`): `wd-pre` once per function, and `wd-post` on each path of every function with a body VC; `ConstraintOrigin` tags. POST-CONJ-SPLIT-1 adds the `dropped-context` mark and the `erPartlyProvedFns` union.
- `compiler/src/LLMLL/AbstractionVerdict.hs` and `compiler/app/Main.hs` (`:1664-1690`): the partition rule of §4.4; the four cause steps; `refutedSet` restricted to complete TRUTH ids; an `illDefinedSet` that does not require a body VC; the exit law; the `--json` keys.
- `compiler/src/LLMLL/DiagnosticFQ.hs`: the two clause tags and their text.
- `compiler/src/LLMLL/Diagnostic.hs`: `clause-ill-defined`, `W-CLAUSE-WELLDEF-UNPROVED`, the qualified `refuted` and `measure-not-decreasing` texts.
- `compiler/src/LLMLL/TrustReport.hs`, `VerifiedCache.hs`: marker, cause, stamp `"7"`.
- `compiler/src/LLMLL/ProofArtifact.hs`: `proofArtifactVersion = "0.2.0"`; the `checker_soundness_version` member, parsed with `.:?`; the `/=` read in `classifyReplay` before the hash check; the `liveComposedVersions` comment.
- `compiler/src/LLMLL/Contracts.hs` (`wrapPre`, `wrapPost`) and `CodegenHs.hs`: clause-context forms of the seven partial operations (§4.6).
- `docs/llmll-trust-report.schema.json`, `docs/proof-artifact.schema.json` (version `0.2.0`, the epoch member, the new enum value, and a note that `0.1.0` admits `callee-post-unassumed` since v0.36.0), `docs/llmll-verify.schema.json`.
- `LLMLL.md` §4.4.1 (the new verdict), §4.4.4 (`--json` keys), §5.3.3 and §5.3.4 (the obligation, the body-context rule and its divergence from Dafny methods, the stripping rule), §13.12 (π also governs clauses; D2). Doc-lead's slot.
- `docs/design/contract-position-reads-disposition.md`: superseded on settlement. Doc-lead's slot.
- `docs/design/post-conj-split-proposal.md`: the items of §4.7 under POST-CONJ-SPLIT-1, at that proposal's settlement.
- `scripts/fallback_census.py`: the new cause in its own bucket.
- **Acceptance tests.** 13 rows of §4.4, one test each: V1-V12 and V14. V13 moves to POST-CONJ-SPLIT-1. The three epoch tests of §4.8. E4 and E10 run-time messages. A two-module test from xm2, and one from xm3 that checks the post is no longer stripped. The lemma-parity test (§4.3), reading `bytesSetSpec`. A gate test: a function whose pre a contract-level guard refuses emits no `wd-*` constraint. The `.fq` byte-identity sweep over the files with no partial operation in a clause.

## 9. Risks and open questions

1. **New hard failures.** Classify: verification-ergonomics. A file that passes today can exit 1. Cite: §4.4. Bite: complicates. The corpus count is one, a fixture made for this defect (§7.1). Agent-written code outside the repository can hold more. The diagnostic names the missing `map-has` or bound.
2. **An unlisted drop site.** Classify: soundness of the verdict. A drop site missing from §4.3 gives a false `ill-defined` on a correct clause. Cite: §4.3. Bite: complicates. The parity rule and its test cover sealed-builtin lemmas. A new fact family on the body side is caught only by review of that row.
3. **Stamp change cost.** Classify: scope. Every sidecar and every proof artifact fails closed once. Cite: §4.8. Bite: matters at scale only. BYTES-LEN-RANGE-1 and AND-GUARD-PRE-1 paid the same cost.
4. **Two copies of π or of the traversal.** Classify: spec-drift. Cite: §4.1, §4.1.1. Bite: complicates. One table, one traversal, and one test that lists every `CallVC` builtin with a `pre`.
5. **Fail-stop is not guaranteed today.** Classify: soundness. The "Callers" argument and the guard assume that a contract violation stops the program. PRE-FAIL-EXIT-1 records two handlers that catch it. Cite: §4.4, §4.6. Bite: complicates that row, not the verdicts of this one.
6. **Future partial builtins.** Classify: scope. `docs/design/byte-io-proposal.md` adds `bytes-slice`, `string-code-at` and five `bit-*` operations, each with a QF-LIA pre. Each enters the π table and the parity test when it becomes clause-admissible. Bite: matters at scale only.
7. **POST-CALL-XMOD-1.** Classify: soundness. If a user function becomes admissible in a clause, its pre is a well-definedness obligation by the same rule. Bite: complicates that row, not this one.

## 10. Rev 2 decision list

Rev 2 listed nine decisions for the user. The user settled all of them on 2026-11-04, with the second-pass edits. See [Decisions](#decisions-settled-by-the-user-2026-11-04). No open question remains.

---

## Appendix — Professor review log

Folded 2026-11-04 at the settlement of Rev 3. Two passes, condensed below with their finding ids and verdicts. The first review is archived unchanged at [`../archive/professor-reviews/clause-welldef-review.md`](../archive/professor-reviews/clause-welldef-review.md). The second pass was never committed as a standalone file, so it has no archive copy. Two findings of the second pass of POST-CONJ-SPLIT-1 (C1, C2) also apply to this record. They are listed last.

### Review of Rev 1 (2026-11-03)

**Verdict: accept with changes.** Option (a) is correct, and the reversal of the 2026-07-12 disposition holds, but on a different witness. W1 and W2 block settlement.

Measurements (llmll 0.35.1, one file at a time): xm2 fail-stops under `--contracts=unproven` and `--contracts=full`. xm3: `mk`'s `verified` post is stripped under `--contracts=unproven`, and the program prints `key 3 absent` and exits 0. `bl.llmll`: a true post about `bytes-set` length is `refuted`. `br.llmll`: the byte-range fact reaches clause selects. `rb.llmll`: a parameter alias outside the fragment gives `contract-pre-outside-fragment`. The generated `Lib.hs` evaluates pre, then body to WHNF, then post, all strict.

| Id | Class; bite | Finding | Disposition |
|---|---|---|---|
| W1 | soundness of verdicts; blocks | Two sources of a false `ill-defined`: (a) the clause side has no `bytes-set` length lemma; (b) a refused parameter refinement removes a `wd-pre` hypothesis. List every drop site and mark each. | Rev 2: S1-S8 and the parity rule. (a) became BYTES-SET-CLAUSE-LEN-1, shipped v0.36.0. (b) became "no emission"; the professor withdrew the mark in the second pass. |
| W2 | soundness of verdicts; blocks | The combination with truth constraints is per function and unspecified. Partition by tag, mark inside each partition, combine by precedence, one test per row. | Rev 2: §4.4 and the table. Rev 3 adds N2, N3, N5. |
| W3 | spec-drift; complicates | xm2 fail-stops. The reversal rests on `nc-004`, stripping and xm3. Stripping shipped in v0.8.1b, before the disposition. | Rev 2: §2.3. |
| W4 | spec-drift; complicates | Dafny checks a method's specification without the body. The body-context rule is a divergence; record its cost. Drop `wd-post` for body-fallback functions. | Rev 2: §4.2, §7.2. Rev 3 says "methods". |
| W5 | soundness; complicates | The per-conjunct stripping proof is false as stated. Use an induction over source order and record the dependency. | Rev 2: §4.7. |
| W6 | scope; complicates | The proof artifact has no soundness epoch. | Rev 2 added the field. Rev 3 adds the parse, compare and reader rules (N4). |
| W7 | spec-drift; complicates | `WD` must share the `exprToPred` traversal. | Rev 2: §4.1.1. |
| W8 | no change | The context rules are correct. `<=>` is strict. `wd-pre` is complete after W1(b). | Rev 2: §4.3 last paragraph. |
| W9 | soundness; minor | The lemma needs the junk-independence step. Claim refutation localization. | Rev 2: §4.5. |
| W10 | scope; minor | 23 of 41 files emulated; marker on mutants not measured; `ArithException`; qualified `refuted` text; stamp and versions accepted; D1 and D2 confirmed. | Rev 2: §7.1, §4.6, §4.4. |
| Open question 1 | — | Count the posts that each Dafny rule makes `ill-defined`. | Rev 2: §7.2. Rev 3 corrects the count (N6). |

### Second pass, review of Rev 2 (2026-11-04)

**Verdict: settle with named small edits; no Rev 3 needed in design.** Four edits before settlement (N1-N4); the others in the settlement fold. The design, the context rules, the drop-site inventory, the precedence, the divergence from Dafny and the stripping induction are correct. Rev 1 findings: W1, W3, W4, W5, W7, W8, W9, W10 closed; W2 and W6 partly closed (N2, N3, N5; N4).

| Id | Class; bite | Finding | Disposition in Rev 3 |
|---|---|---|---|
| N1 | soundness of the run; blocks | "The effective pre translates" admits pres that a contract-level guard refused (`FixpointEmit.hs:1605-1626`). An ill-sorted `wd-pre` constraint is `FQError` for the whole file. Gate on the `(Just postPred, Just mPre)` arm. | §4.2, S4, S8, §8, decision 6. |
| N2 | soundness of the verdict text; blocks | The cause choice names `callee-post-unassumed` when no id carries that mark. Add a fourth step. | §4.4 rule 2. |
| N3 | spec-drift; blocks | Rule 1 changes `refutedSet` for a function with no `wd-*` id. Keep rule 1, delete the false sentence, add a test. | §4.4, V14, §4.8, §8. |
| N4 | scope; blocks | The artifact epoch needs `.:?`, `/=` and a reader in `classifyReplay`. File D7. | §4.8, D7 (REPLAY-CODEGEN-VERSION-1). |
| N5 | ergonomic; fold | Qualify the counter-model text on V5 and V9 too. | §4.4. |
| N6 | spec-drift; fold | "6 against 1" counts `use-mk`, which the chosen rule does not check. | §7.2. |
| N7 | soundness of the argument; fold | The canonical model needs two conditions: assumed callee posts (relative to the trust closure) and a junk choice that meets the ground facts. | §4.5. |
| N8 | spec-drift; fold | `exprToPred` lines about 110 low; S1 shipped as a guarded lemma; CALLEE-POST-UNASSUMED-1 shipped; parity test anchored on `bytesSetSpec`. | §2.1, §3.1, §4.1.1, §4.3, E17. |
| N9 | scope; fold | V13 needs per-conjunct verdicts. Defer it to POST-CONJ-SPLIT-1. | §4.4, §8. |
| Drop sites | — | S1-S8 sound. Add a W-Catalog sentence: `Σ_ref` excludes the three builtins. | §4.3. |
| Dafny | — | The divergence is justified. Say "methods". Add the argument that callers need no self-framing post. SPARK 2014 agrees. | §4.2. |
| `rb` | — | No emission. The professor withdraws the W1(b) mark: it changes no verdict, needs a partial reflection, and the guard covers the case. | S4, §4.9, decision 7. |

The second pass also answered Rev 2's decision 10.3 (body-context rule: yes) and 10.5 (stamp and artifact: yes, with N4).

### Cross-draft findings from the second pass of POST-CONJ-SPLIT-1 (2026-11-04)

| Id | Finding | Disposition in Rev 3 |
|---|---|---|
| C1 | Rev 2 emits `wd-post` only for body-faithful functions. A partly proved function is not body-faithful, so its admitted conjuncts could be `verified` with no well-definedness proof. Emit `wd-post` for every function with a body VC. | §4.2, §4.7 item 3, decision 6. Reconciled with N1: N1 gates on the arm, C1 picks the functions in it. |
| C2 | Four points of agreement: the refuted rule uses the body-VC union; fallback per function in v1; the split adds the `dropped-context` mark; ship CLAUSE-WELLDEF-1 first. | §4.4 rule 1, §4.7 items 4-5, E14, decisions 8-10. |
| C4 (versions) | One rule for `proof_artifact_version`; v0.36.0 added `callee-post-unassumed` with no raise. | §4.8, decision 11. |
