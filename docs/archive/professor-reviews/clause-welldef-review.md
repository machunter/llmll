---
title: "Professor review: CLAUSE-WELLDEF-1 Rev 1, prove that each partial operation in a clause is defined where it is evaluated"
status: "Review of Rev 1 DRAFT. Archived 2026-11-04 at the settlement of Rev 3; folded into the proposal's Appendix."
author: professor
date: 2026-11-03
reviews: "docs/design/clause-welldef-proposal.md (Rev 1, DRAFT 2026-11-03)"
verdict: "Accept with changes. Option (a) is correct and the reversal of the 2026-07-12 disposition holds, but on a different witness. Fix the false `ill-defined` sources (W1) and the verdict combination (W2) before settlement."
---

# Professor review: CLAUSE-WELLDEF-1 Rev 1

## Restatement

The draft adds a well-definedness obligation for each admitted application of `map-get`, `bytes-get` and `bytes-set` in a `pre` or `post`. The obligation is the builtin's body-side precondition. It holds under a short-circuit context `C` and a hypothesis set `H` that depends on the clause kind. A complete failure is a new hard verdict, `ill-defined`. A failure over marked hypotheses is a fallback with cause `clause-welldef-unproved`. The run-time clause check reports an undefined clause as a violation of that clause. The draft increases `checker_soundness_version` to `"7"`, and it reverses the decline of option (b) in `docs/design/contract-position-reads-disposition.md`.

## Context located

1. `docs/design/contract-position-reads-disposition.md` (settled 2026-07-12): the soundness argument rests on "the generated program's contract assertion **fail-stops** before any value flows". It does not mention `--contracts=unproven`.
2. `LLMLL.md:22` (anchor `nc-004`): "a verified contract holds for all well-typed inputs" under the call-by-value semantics of §4.7. This statement decides the reversal (W3).
3. `compiler/src/LLMLL/CodegenHs.hs:3893-3900` (EVAL-STRICT-1, `esLazyOps = ["and", "or", "=>"]`), `:2425-2431` (`emitOp`): only `and`, `or` and `=>` are lazy in their right operand. `<=>` emits `==` on `Bool`, which forces both operands.
4. `compiler/src/LLMLL/Contracts.hs:323-348` (`wrapPre`, `wrapPost`), and the generated code for xm2 (`Lib.hs:1019-1020`, measured): the order is pre, then the body forced to WHNF by `!result`, then the post.
5. `Contracts.hs:182-190` (`instrumentClosure`): the status map is built from the imported environments only. This confirms D1.
6. `Contracts.hs:232-243` (`filterContracts`): a pre is never stripped; a post is stripped when it is verified and body-faithful.
7. `compiler/src/LLMLL/FixpointEmit.hs:3820-3848` (`exprToPred`, bytes and map arms): `bytes-set` reflects as `Map_store` with no length fact. The body arm at `:4854-4876` carries the lemma `bytesLen(r) = bytesLen(b)`. The clause side does not (W1).
8. `FixpointEmit.hs:4829-4844`, `:4854-4864`: the body arms fire only on `(bytes-get (EVar b) i)` and `(bytes-set (EVar b) i v)`. A clause admits any bytes term in the first argument.
9. `compiler/app/Main.hs:1644-1676`: `applyAbstractionVerdict` runs before `refutedSet` and `measureNotDecreasingSet`. The draft adds a third partition there (W2).
10. The CALLEE-POST-UNASSUMED-1 implementation plan (session scratchpad, not committed), §"The verdict rule": rule 2, "one non-candidate id blocks the function".
11. `compiler/src/LLMLL/VerifiedCache.hs:398-399` (`checkerSoundnessVersion = "6"`) and `docs/proof-artifact.schema.json:8-23`: the proof artifact has no soundness stamp (W6).
12. `docs/design/post-conj-split-proposal.md` Rev 2 §4.3, §4.5, E13; `docs/design/post-conj-split-professor-review.md` P3, P8.
13. `LLMLL.md:3343` (§13.12 `bytes-set` row), `LLMLL.md:776` and `:1134`: the value range `0..255` is stated in two places and missing from the table. This confirms D2.

External: Leino, "Dafny: An Automatic Program Verifier for Functional Correctness" (LPAR 2010), and the Dafny reference manual on the well-formedness of specifications; Chalin, "A Sound Assertion Semantics for the Dependable Systems Evolution Verifying Compiler" (ICSE 2007), the "strong validity" reading.

## Measurements (llmll 0.35.1, one file at a time under `watch.py 2000 300`)

Copies were kept in the drafting session's scratchpad (`profrev/`). They are not committed.

| File | What it tests | Result |
|---|---|---|
| `xm2/` (rerun) | the draft's §2.3 witness | `mklib` and `app` SAFE. The run stops with the `map-get` message under `--contracts=unproven` **and** under `--contracts=full`. The program fail-stops in both modes. |
| `xm3/` (new) | `mklib.llmll` from xm2; `app.llmll` prints `(if (map-has (mk n) 3) …)` | Both SAFE; `mk`'s post `(= (map-get result 3) 0)` is `verified`. Under `--contracts=unproven` the post is stripped, the program prints `key 3 absent` and exits 0. |
| `bl.llmll` (new) | `b: bytes[4]`, `(post (< 0 (bytes-length (bytes-set b 0 7))))`, body `0` | **refuted**, exit 1. At run time the post is true (`bytes_set` preserves length, `CodegenHs.hs:550-554`). |
| `bl2.llmll` (control) | `(post (< 0 (bytes-length b)))` | verified. |
| `br.llmll` | `(post (<= (bytes-get b 1) 255))` | verified. The byte-range fact reaches clause selects. |
| `rb.llmll` | parameter `i: Idx`, where `Idx`'s refinement is outside the fragment | `h` falls back, `contract-pre-outside-fragment`. The alias fact is not a hypothesis. |
| `rp2.llmll` | a pre outside the fragment | the function falls back, `contract-pre-outside-fragment`. |
| generated `Lib.hs` for xm2 | evaluation order | `g m = case (if not pre then error … else 1) of !result -> if not post …`. Pre, body, post, all strict. |

## Gaps and hazards

### W1. Two sources of a false `ill-defined`. (soundness of verdicts; blocks)

The draft calls a failure "complete" when it carries none of four marks (§4.3). That list is not the list of dropped hypotheses. The P8 rule from the POST-CONJ-SPLIT-1 review applies: a failure is a disproof only when every hypothesis of the failing constraint is the authored one. Two cases break the rule.

**(a) The clause logic has no length lemma for `bytes-set`.** `exprToPred` reflects `(bytes-set b i v)` as `Map_store(b, i, v)` (`FixpointEmit.hs:3825-3826`). The body arm assumes `bytesLen(r) = bytesLen(b)` as a lemma part (`:4865-4876`). The clause has no such fact. `bl.llmll` shows the effect today: a true post is `refuted`. Under the draft, `(bytes-get (bytes-set b 0 7) 1)` on `bytes[4]` gives the outer obligation `1 < bytesLen(Map_store(b,0,7))`. It is not provable, so the clause is reported `ill-defined` although every run evaluates it. Fix: emit the sealed-builtin length lemma for each `Map_store` term that a clause reflects from `bytes-set`. This also removes the false `refuted` of `bl.llmll`. That is an existing defect, and it needs its own row.

**(b) A refused parameter refinement removes a `wd-pre` hypothesis.** §4.2 gives `wd-pre` the parameter facts, including refinement aliases. §4.3 then says a `wd-pre` failure is `ill-defined` "for any function". `rb.llmll` shows that an alias whose refinement is outside the fragment contributes no fact. So `(pre (> (bytes-get b i) 0))` with `i: Idx` fails its obligation, and the draft reports `ill-defined`. The author's alias makes the read safe. Fix: add a mark, "parameter fact refused", to `wd-pre` and `wd-post` constraints of such functions.

The general fix is a rule, not two patches. The language-team must list every site where the emitter drops a hypothesis that the author wrote or that a sealed builtin guarantees. Each site sets a mark. The draft's §9 risk 2 names this failure mode but does not do the inventory.

### W2. The verdict combination with truth constraints is not specified. (soundness of verdicts; blocks)

The draft gives a verdict table for the `wd-*` constraints alone (§4.3). The shared path does not work per clause. `applyAbstractionVerdict` decides per function, and its rule 2 says one non-candidate failing id blocks reclassification. The CALLEE-POST-UNASSUMED-1 plan keeps that rule. So the result depends on which ids fail together:

- A complete failing `wd-post` id and a marked failing truth id. Rule 2 blocks the fallback. `refutedSet` (`Main.hs:1672-1676`) then reads the origins. The draft must say that the function is `ill-defined` and not `refuted`.
- A marked failing `wd-post` id and a complete failing truth id. The function is `refuted`. The draft must say whether `welldef_unproved` is also listed.
- Both ids marked. The function falls back. The draft must give one cause. Candidates are `clause-welldef-unproved`, `callee-post-unassumed` and `abstraction-unsafe`.

Fix: partition the failing ids by clause tag first (`wd-*`, `descent`/`decreases`, truth). Apply the mark rule inside each partition. Then combine the partitions by a stated precedence: `ill-defined` before `measure-not-decreasing` before `refuted` before each fallback cause. Write that table in §4.3, and add one acceptance test for each row.

### W3. The reversal holds, but §2.3 rests on the weaker witness. (spec-drift; complicates)

xm2 still fail-stops in both `--contracts` modes (measured). It shows a false call-site discharge and a misattributed failure. It does not show a value that flows past a false claim, and that was the disposition's test. On its own, xm2 does not refute the disposition's soundness paragraph.

The deciding facts are these:

1. `LLMLL.md:22` (`nc-004`) says that a verified contract holds for all well-typed inputs under call-by-value. A clause whose evaluation calls `error` does not hold under that semantics. Chalin calls this reading "strong validity", and JML adopted it. So `mapdef.llmll` contradicts the language's own soundness statement today, in every mode.
2. `--contracts=unproven` strips exactly the verified posts (`Contracts.hs:240-242`). The xm3 witness shows the effect: `mk`'s `verified` post is stripped, and the program exits 0 with a map that has no key 3.
3. Stripping shipped in v0.8.1b, before 2026-07-12. So the disposition's premise was false on the day that it was written. The reversal corrects an error. It does not respond to a new fact.

Fix: lead §2.3 with `nc-004` and the xm3 shape. Keep xm2 as the call-site case, and state that it fail-stops. Change "the reversal rests on correctness" to "the disposition's soundness paragraph contradicts `nc-004` and ignores stripping".

### W4. The Dafny citation for `wd-post` hypotheses is wrong. (spec-drift; complicates)

§4.2 says that Dafny's well-formedness check of an `ensures` clause uses the body's state. It does not. Dafny checks the well-formedness of a method's specification in a separate procedure. That procedure assumes the precondition, havocs the outputs and does not read the body. In Dafny, `ensures m[3] == 0` on a method whose body builds `map[3 := 0]` fails with "element might not be in domain". The author must write `3 in m && m[3] == 0`.

The draft's rule is the run-time-error reading: the post must be defined in each state where the program evaluates it. The generated code confirms the premise: the order is pre, body forced to WHNF, post (measured; EVAL-STRICT-1). So the rule is sound for LLMLL. It is a different rule from Dafny's, and the draft must say so. The choice has a real cost on each side:

- The spec-local rule (Dafny) gives a self-framing post. A caller can read presence from it, and a body edit cannot make a fixed post ill-defined. It also makes every `wd-post` constraint complete, so the body-fallback mark and the callee-post marks on `wd-post` disappear.
- The body-context rule (the draft) accepts the agent-written RFC 826 posts. Examples: `experiments/rfc-swarm/runs/rfc826-llmll-2026-09-11/07-feasibility/spoof-binding.llmll:4` and `table-frame.llmll:13` read `(map-get result …)` with presence only from the body.

I recommend the body-context rule, because `nc-001` makes the generated program the semantics of record and because the corpus relies on it. Record the divergence and its cost in §4.2 and §4.8. Do not cite Dafny for it.

One consequence follows. A `wd-post` constraint of a body-fallback function can never be complete, so it never changes a verdict. It gives that function a second fallback cause (E8). Drop `wd-post` emission for body-fallback functions. The run-time guard of §4.5 covers them.

### W5. The per-conjunct stripping proof is incomplete. (soundness; complicates)

§4.6 item 4 says: "a stripped conjunct is true in every state that reaches the post". That is false when its `C` uses an earlier conjunct that is kept. Example: `(and (map-has result 3) (= (map-get result 3) 0))` with body `(map-empty)`. Conjunct 2 is true in the logic (`Map_default 0`), and its obligation holds under `C`. So it is stripped. In a state that reaches the post, conjunct 2 is undefined. The program is still safe, because conjunct 1 is kept and fails first.

The correct argument is an induction over source order. Let conjuncts `1..j-1` be true or checked in a state that reaches the post. Then `C_j` holds, so conjunct `j` is defined there. Its truth proof makes it true. A stripped conjunct is evaluated in no run, and the kept conjuncts are evaluated in the same states as before. Fix: replace the sentence with this induction. Also state that a conjunct whose obligation used an unverified earlier conjunct is "defined given conjunct k", and record that dependency.

### W6. The proof artifact has no soundness epoch. (scope; complicates)

`docs/proof-artifact.schema.json` records `proof_artifact_version`, `composed_versions` and the solver pins. It has no `checker_soundness_version`. An artifact written by 0.35.1 replays its stored `.fq` as SAFE, and that `.fq` has no `wd-*` constraints. A consumer cannot tell that the artifact is from the earlier epoch. Fix: add `checker_soundness_version` to the artifact and to `composed_versions`. A replay that finds an older value reports the epoch. §4.7 must list this change.

### W7. The `WD` walk must share the `exprToPred` traversal. (spec-drift; complicates)

`exprToPred` has special arms that a separate walk can miss: the bool bridge for `map-get` against a bool literal (`FixpointEmit.hs:3762-3770`), the `intBuiltinTag` arm for `min` and `max` (`:3758-3759`), `EOp` delegation, the `=>` and `<=>` desugaring and the `match` arm. The draft already requires one π table (§4.1). Apply the same rule to the traversal. One function returns the term and its obligations under `C`. Then a new admitted form cannot get a term and no obligation.

### W8. The run-time context rules are correct. (no change)

I checked each rule of §4.1 against the generated code. `and`, `or` and `=>` are the only lazy operators (`esLazyOps`), and `=>` emits `not a || b`. `<=>` emits `==` on `Bool`, which forces both operands, so it must give no context. `match` evaluates only the selected arm. Every other admitted form is strict through `esForceArgs`, including pair construction, constructor arguments and the value of `map-put`. So the strict `WD` rules over-approximate nothing: each operand that `WD` visits is evaluated. The rule for `and` also uses `WD(C, a)` before it assumes `⟦a⟧`. This is the standard order (Leino 2010), and it makes `⟦a⟧` independent of junk where it is assumed.

The `wd-pre` hypotheses are correct and agree with Dafny's rule for `requires`: parameter facts and earlier conjuncts only. A `wd-pre` constraint has no call binders and no abstraction, so after W1(b) it is always complete. Say that in §4.3; it removes a case from the verdict table.

### W9. The soundness lemma needs one more step. (soundness; minor)

§4.4 says that a model and a run differ only at points that no run evaluates. State the step that makes this work. If `WD(C, e)` holds and `C` holds, `⟦e⟧` has the same value in every model that agrees with the run on defined reads. Prove it by induction on `e`, with the `and`, `or`, `=>` and `match` cases using the context rule. Then a truth proof over all models applies to the run. A consequence follows, and the draft can claim it: with `WD` proved, a truth counter-model no longer reads junk. That closes the disposition's second wart ("refutation localization degrades").

### W10. Smaller points. (scope; minor)

1. **Corpus claim.** The emulation ran on 23 of the 41 files. The other 18 hold only syntactically guarded reads, and scan2's context model makes those obligations true. Say so. The 11 mutant files are `refuted` before and after, so the emulation cannot show whether they also gain the `ill-defined` marker. Write "one change of exit status; the marker on mutants is not measured".
2. **Both markers.** When a clause is `ill-defined` and `refuted`, the counter-model can read an undefined term. Keep both markers, and make the `refuted` text say that the counter-model may be at an undefined point.
3. **The guard and `codegen_semantics_version`.** I agree with no change. The guard changes a message and no value that a solver axiom relies on. A division by zero raises `ArithException`, not `error`. The exit status is 1 in both cases, so §4.5 is right in effect but wrong in wording.
4. **Schema and stamp.** I accept the change of `checker_soundness_version` to `"7"`. A `"6"` sidecar can record `verified` on a clause that contradicts `nc-004`. The minor increases of `verify_json_version` and `trust_report_version` are correct.
5. **D1 and D2.** Both are confirmed. D1: `instrumentClosure` (`Contracts.hs:182-190`) never puts the entry module's status into the map, and `w9_strip.llmll`'s generated code keeps `inc`'s post. The order "this row first, then CONTRACTS-ENTRY-STRIP-1" is correct, because D1 is the only thing that keeps `mapdef.llmll` failing at run time today. D2: the drift is internal to `LLMLL.md`. The §13.12 table row (`:3343`) omits the value range, and `:776` and `:1134` state it.

## Recommendation

Accept option (a), with the run-time guard and with the hard verdict `ill-defined` outside `refutedSet`. The separate verdict is correct for the same reason that `measure-not-decreasing` is separate: the failure is a disproof of a different claim. The reversal of the 2026-07-12 disposition holds. Rest it on `nc-004` and on stripping, not on xm2.

Required changes, by severity:

1. **W1.** Add the `bytes-set` length lemma to clause reflection, and file the false `refuted` of `bl.llmll` as its own row. Add a mark for refused parameter refinements. List every hypothesis-drop site, and give each one a mark.
2. **W2.** Write the verdict combination table across `wd-*`, measure and truth partitions, with cause precedence, inside `applyAbstractionVerdict`'s per-function rule.
3. **W3.** Rewrite §2.3 around `nc-004`, stripping and the xm3 witness. State that xm2 fail-stops.
4. **W4.** Remove the Dafny citation from §4.2. Record the body-context rule as a deliberate divergence, with its cost. Drop `wd-post` for body-fallback functions.
5. **W5.** Replace the stripping proof with the induction over source order, and record a conjunct's dependency on an unverified earlier conjunct.
6. **W6.** Add `checker_soundness_version` to the proof artifact.
7. **W7.** Generate `WD` from the `exprToPred` traversal.
8. **W9, W10.** Add the junk-independence step, correct the corpus wording and the §4.5 exit wording, and qualify the `refuted` text when both markers are set.

## Open questions for the language-team

1. After W4, does any agent-written post in the corpus become `ill-defined` under the spec-local rule but not under the body-context rule? Count them, so that the user can see what the choice in W4 costs in each direction.


---

# Round 2 (appended at settlement, 2026-11-04)

The second professor review, of Rev 2. Appended unchanged, except that its headings are one level lower. Its frontmatter:

- title: "Professor review (second pass): CLAUSE-WELLDEF-1 Rev 2"
- status: "Standalone review of Rev 2 DRAFT. Not folded into the proposal."
- author: professor
- date: 2026-11-04
- reviews: "docs/design/clause-welldef-proposal.md (Rev 2, DRAFT 2026-11-03), against docs/design/clause-welldef-professor-review.md (Rev 1 review)"
- tree: "main at a339fbb8 (v0.36.0). BYTES-SET-CLAUSE-LEN-1 and CALLEE-POST-UNASSUMED-1 have shipped since Rev 2 was written."
- verdict: "Settle with named small edits. No Rev 3. Four edits must land before settlement (N1-N4). The others can land in the settlement fold."

## Professor review, second pass: CLAUSE-WELLDEF-1 Rev 2

### Restatement

Rev 2 keeps option (a): a well-definedness obligation `WD(C, e)` for each admitted `map-get`, `bytes-get` and `bytes-set` in a clause. The obligation uses the run-time short-circuit context. A complete failure is a new hard verdict, `ill-defined`. A marked failure is a fallback with cause `clause-welldef-unproved`. Rev 2 adds an inventory of eight hypothesis-drop sites (S1-S8), a per-function partition rule with a 13-row table, the body-context rule for `wd-post` as a recorded divergence from Dafny, a soundness lemma, and a soundness epoch in the proof artifact.

### Context located

1. `docs/design/clause-welldef-proposal.md` Rev 2, §4.1-§4.8, §7.2: the draft under review.
2. `docs/design/clause-welldef-professor-review.md`: the Rev 1 findings W1-W10.
3. `compiler/src/LLMLL/AbstractionVerdict.hs:117-170` (`applyAbstractionVerdict`, `decide`): the shipped per-function rule, after CALLEE-POST-UNASSUMED-1.
4. `compiler/app/Main.hs:1654-1680`: `refutedSet` counts every failing id of a blocked function, marked or not.
5. `compiler/src/LLMLL/FixpointEmit.hs:4550-4570` (`bytesSetSpec`), `:6293-6320` (`storeLenFacts`): S1 is closed on main by commit 6adae19e, as a guarded lemma.
6. `FixpointEmit.hs:1600-1660`: a pre that `exprToPred` translates can still be refused by a contract-level guard.
7. `FixpointEmit.hs:3846-3989` (`exprToPred`): the arms. Every line number in the draft's §4.1.1 is now about 110 lines low.
8. `FixpointEmit.hs:6485-6660` (`resolveAllRefinements`, `paramRefinementPre`, `augmentContractPre`): the user pre comes before the folded parameter facts.
9. `compiler/src/LLMLL/ProofArtifact.hs:209-224`, `:270-292`, `:319-321`: `composed_versions` is informational, parsed strictly, and not read by `classifyReplay`.
10. `docs/proof-artifact.schema.json:36-39`: says replay fails closed on a `codegen_semantics_version` mismatch. `classifyReplay` does not compare that field (drift, D7 below).
11. `compiler/src/LLMLL/VerifiedCache.hs:351`, `:398-399`: the sidecar compares the soundness stamp with `/=`.
12. `LLMLL.md §3.4.4` (W-Catalog, `Σ_ref`): a refinement predicate cannot name `map-get`, `bytes-get` or `bytes-set`.
13. `compiler/src/LLMLL/CodegenHs.hs:2431`, `:3899-3900`: `<=>` is strict; only `and`, `or` and `=>` are lazy. No change since Rev 1.

External: Leino, LPAR 2010, and the Dafny reference manual (well-formedness of specifications); Chalin, ICSE 2007 ("strong validity"); the SPARK 2014 / GNATprove treatment of run-time checks in `Post` aspects, which GNATprove verifies at the subprogram's return points.

### Rev 1 findings: closure

| Finding | Status | Rev 2 section | Note |
|---|---|---|---|
| W1. False `ill-defined` from dropped hypotheses | **closed** | §4.3, S1-S8, parity rule | S1 has shipped (6adae19e). The emission gate for fallback functions has a new defect: N1. |
| W2. Verdict combination not specified | **partly** | §4.4, V1-V13 | The rule is right. The cause choice has a gap (N2). The "no output change" claim is false (N3). The qualified text is missing on two rows (N5). |
| W3. Reversal rests on the weaker witness | **closed** | §2.3 | Leads with `nc-004`, stripping and xm3. States that xm2 fail-stops. |
| W4. Wrong Dafny citation | **closed** | §4.2, §4.9, §7.2 | The count needs one wording fix (N6). |
| W5. Stripping proof incomplete | **closed** | §4.7 items 4-5 | The induction is correct. The dependency record is specified. |
| W6. No soundness epoch in the artifact | **partly** | §4.8 | The field is added. The parse and the compare are not specified, and `classifyReplay` does not read `composed_versions` (N4). |
| W7. One traversal | **closed** | §4.1.1 | The `<=>` exception is correct. The line numbers are now incorrect (N8). |
| W8. Context rules correct | **closed** | §4.3 last paragraph | `wd-pre` is always complete after S1 and S4. I agree. |
| W9. Junk-independence step | **closed** | §4.5 | The canonical model needs two stated conditions (N7). |
| W10. Smaller points | **closed** | §4.4, §4.6, §7.1 | All five items are addressed. |
| Open question (cost of each rule) | **closed** | §7.2 | Measured. |

### Gaps and hazards

#### N1. The `wd-pre` emission gate admits pres that a contract guard refused. (soundness of the run; blocks settlement, small edit)

§4.3 S4 and §8 say: emit `wd-pre` when the effective pre "translates in full". E20 extends emission to body-fallback functions. But `exprToPred` returning `Just` is not the condition under which the emitter binds and sorts a pre. Three contract-level guards refuse a contract after a successful translation (`FixpointEmit.hs:1605-1626`): `contractSigGuardsBlock`, `wholeArrEqClause` on the pre, and `mapClauseBlocked`. The comment at `:1613-1618` states the reason for the third guard: the clause "would reflect against binders that don't exist (or at the wrong element sort) — free-var/ill-sort crash". FQ-FREEVAR-GUARD-1 (S8) catches a free symbol. It does not catch an ill-sorted term. An ill-sorted `wd-pre` constraint is a solver error, which is `FQError` for the whole file. So a file that passes today can fail for every function.

The same applies to functions that fall back on a refused post (`FallbackContractPost`) or a hole. Those functions leave at the first case of `case (mPostPred, mPrePred)` (`:1645-1652`), before any parameter binder is emitted.

Fix: state the gate as "the function reaches the branch where both clauses translate and no contract-level guard fires" (the `(Just postPred, Just mPre)` arm at `:1653`). That arm already holds body-faithful and body-fallback (`FallbackBody`, `FallbackPathCap`) functions with bound parameters. Every other function emits no `WD` constraint, and the run-time guard (§4.6) covers it. This removes no hard verdict that the draft relies on: E20 is inside that arm.

#### N2. The cause choice has no case for a marked set without `post-unassumed`. (soundness of the verdict text; blocks settlement, small edit)

§4.4 rule 2 chooses: all failing ids in WD, then all ids `abstraction`-marked, then `callee-post-unassumed`. With `dropped-context` added, a function can fail with WD ids marked `dropped-context` and a TRUTH or MEAS id marked `abstraction`. No id carries `post-unassumed`. The draft's step 3 then names `callee-post-unassumed`, which is false. The shipped `decide` (`AbstractionVerdict.hs:149-156`) falls through to `FallbackAbstraction` in that case, with a callee from the abstraction ids. So the draft and the code disagree.

Fix: make step 3 "some failing id carries `post-unassumed`: `callee-post-unassumed`". Add step 4: "otherwise `abstraction-unsafe`, named by the first abstraction-marked id". A `dropped-context` id contributes its construct to the list. It never chooses the cause when a non-WD id also fails. The case cannot occur until POST-CONJ-SPLIT-1 ships, so it needs a sentence and no test now.

#### N3. Rule 1 changes an output of CALLEE-POST-UNASSUMED-1, and §4.4 says it does not. (spec-drift; blocks settlement, small edit)

Rule 1 sets `refuted` only when TRUTH holds a **complete** failing id. Today `refutedSet` (`Main.hs:1676-1680`) counts every failing id of a blocked function. A blocked function keeps its marked ids (`AbstractionVerdict.hs:142-145`, rule 2). Take a function with a complete `descent` id and a marked `body-post` id. Today it is `measure-not-decreasing` and `refuted`. Under rule 1 it is `measure-not-decreasing` only. That function has no `wd-*` id. So the sentence "Neither changes an output of CALLEE-POST-UNASSUMED-1 for a function with no `wd-*` id" is false.

Rule 1 is the better rule. It applies the P8 rule to the marker as well as to the fallback: a marked failure is not a disproof. Fix: keep rule 1, delete the false sentence, and state the change. Add one test (complete MEAS, marked TRUTH: `measure-not-decreasing` only). §8 must say that `refutedSet` changes to count complete TRUTH ids only.

#### N4. The artifact epoch needs a parse rule, a compare rule and a reader. (scope; blocks settlement, small edit)

§4.8 puts `checker_soundness_version` in `composed_versions` as a required member. It says that a replay with no value or a lower value reports `ReplayFailClosed`. Three facts on main make that sentence unimplementable as written:

1. `ComposedVersions` parses with `.:` (`ProofArtifact.hs:319-321`). An old artifact without the member fails to parse. It does not reach `classifyReplay`, so the reason text never prints.
2. `liveComposedVersions` (`:215-224`) is documented as "informational: 'classifyReplay' does not read it".
3. The sidecar compares with `/=` (`VerifiedCache.hs:351`), not "below". A version string has no order in the code today.

Fix: parse the member with `.:?`. Compare with `/=`, so a newer-epoch artifact also fails closed under an older binary. Make `classifyReplay` read it, before the hash check. Change the `liveComposedVersions` comment. An alternative is a top-level field beside `codegen_semantics_version`. Either placement is acceptable if `classifyReplay` reads it and a test covers an absent member, an equal member and an unequal member.

D7 (drift, new): the schema says that replay fails closed on a `codegen_semantics_version` mismatch (`docs/proof-artifact.schema.json:36-39`). `classifyReplay` (`ProofArtifact.hs:280-292`) does not compare it. This row should not copy that pattern. File the drift as its own row.

#### N5. The qualified counter-model text is missing on two rows. (ergonomic; settlement fold)

The precedence is `ill-defined`, then `measure-not-decreasing`, then `refuted`. The reason is that a counter-model can sit at an undefined point. That reason also applies to:

- **V9** (WD complete, MEAS complete). A `descent` constraint assumes the pre. If the pre is ill-defined, the counter-model can choose junk that makes the pre true in a state where the run stops in the pre. The run then never reaches the recursive call. So `measure-not-decreasing` can be spurious, and its text needs the same qualification.
- **V5** (WD marked, TRUTH complete). The WD obligation is unproved, so the truth goal can read junk. The `refuted` text needs the qualification here too.

Fix: qualify the `refuted` and `measure-not-decreasing` text whenever any WD id of the function fails, complete or marked.

#### N6. The 6-to-1 count compares a check with no check. (spec-drift; settlement fold)

§7.2 counts `use-mk` among the 6 spec-local `ill-defined` posts. Under the chosen rule, `use-mk` emits no `wd-post` (S5). It is not shown to be defined. It is unchecked, and the run-time guard covers it. Fix: write "5 under the spec-local rule versus 1 under the body-context rule, on functions that both rules check; `use-mk` is checked only by the spec-local rule".

#### N7. The canonical model needs two stated conditions. (soundness of the argument; settlement fold)

The theorem (§4.5) says that the canonical model satisfies `H` on a body-faithful path. That holds under two conditions that the text does not state:

1. **Assumed callee posts.** `H` holds each assumed callee post. The canonical model satisfies a callee post only if that post is true in the run at defined positions and reads no undefined position. That is true when the callee's truth and `WD` are both proved. Otherwise the caller is `asserted` through the trust closure. State the theorem relative to the trust closure, as `LLMLL.md §3.4.3` does for truth.
2. **Junk choice.** The junk values must satisfy the injected ground facts: the byte range `0..255` on every select of a bytes-rooted array, the `{0,1}` range of a bool-valued map, and the guarded `bytes-set` length lemma. Each range contains the encoding default `0`, and each lemma is guarded by `π_bytes-set`. So the choice exists. Two run values must also stay distinct arrays when their `bytesLen` differ. Free junk positions allow this. Say so in two sentences.

Neither condition changes the design.

#### N8. Citations and status are out of date on main. (spec-drift; settlement fold)

- Every `exprToPred` line in §3.1 and §4.1.1 is about 110 lines low. `exprToPred` now starts at `FixpointEmit.hs:3846`. The body arms and `injectRangeFacts` moved by the same amount.
- `AbstractionVerdict.hs:77` is now `:117`.
- S1 is shipped (6adae19e, v0.36.0) as a **guarded** lemma, `π_bytes-set ⟹ bytesLen(store) = bytesLen(b)` (`:6305-6320`). E17 still holds. The outer obligation and the inner obligation share `H` and `C`, so the guard is provable wherever the inner obligation is. State that sentence in E17.
- CALLEE-POST-UNASSUMED-1 is shipped (v0.36.0). The frontmatter and §4.7 still call it "in build".
- The parity test (§4.3) has a natural anchor now: `bytesSetSpec` is the single source for both sides. The test reads its `lemma` parts.

#### N9. V13 cannot have a test in this row. (scope; settlement fold)

V13 needs per-conjunct verdicts, which POST-CONJ-SPLIT-1 adds. The per-function rule of this row cannot produce "the conjunct falls back". Mark V13 as deferred to POST-CONJ-SPLIT-1, and move its test there. The acceptance list in §8 then has 12 tests.

### The drop-site inventory (S1-S8)

The inventory is sound. I checked it against the fact sources on main.

- **S1** is closed on main, as noted in N8.
- **S2 and S3** reuse the shipped marks. A `wd-post` constraint shares the environment of its truth constraint, so `erPostUnassumed` and `erAbstracted` apply unchanged.
- **S4** is correct. A refused effective pre sends the function to `FallbackContractPre` at `:1659`, so no truth constraint exists either.
- **S5** is correct.
- **S6** is correct, and it cannot occur before POST-CONJ-SPLIT-1.
- **S7** is a correct call. The verdict is relative to the facts that a run enforces. `LLMLL.md §3.4.5` says that refinement aliases are verify-or-trust with no run-time residue. So `(pair 9 n)` reaches the read, and `ill-defined` is true of the program. The parity sentence covers the future fix of D6.
- **S8** is correct for free symbols. It does not cover ill-sorted terms. N1 closes that case at the gate, not at the guard.

One site is absent and closed by the spec. A refinement predicate could carry a partial read into `H` through `paramRefinementPre`. `LLMLL.md §3.4.4` (W-Catalog) excludes the three builtins from `Σ_ref`. Add one sentence to §4.3 that cites W-Catalog. Then a future extension of `Σ_ref` must add a site.

### The 13-row table and the precedence

The rule in §4.4 is total over the three partitions and the two failure kinds, after N2. The table is a set of examples and not an enumeration. That is acceptable, because the rule decides every case. Rows I checked against the shipped code:

- V1-V3, V6-V8, V10-V11: consistent with `applyAbstractionVerdict` once WD ids are candidates on the same terms as TRUTH ids.
- V4: correct. It needs the N3 change to `refutedSet`, because today the marked TRUTH id of a blocked function counts.
- V5: correct, with the N5 text.
- V9: correct, with the N5 text.
- V12: correct. The `ill-defined` set must not require body-faithfulness, as stated. This matches `measureNotDecreasingSet`, which does not require it either (`Main.hs:1674-1675`).
- V13: deferred (N9).

The precedence `ill-defined` > `measure-not-decreasing` > `refuted` is sound. A WD failure can make the counter-model of either other partition spurious (N5). The converse does not hold: a truth or measure failure never makes a WD counter-model spurious, because a WD constraint's goal is a precondition over reflected arguments whose own WD obligations are in the same set. The order is the right one.

### The divergence from Dafny

The divergence is justified. Rev 2 now states it correctly for Dafny methods: the specification is checked in a separate procedure that assumes the pre, makes the outputs arbitrary and does not read the body. LLMLL functions are pure, so the text should say that it compares against the method case.

Rev 2 omits the strongest argument for the body-context rule. Callers do not need a self-framing post. A `wd-post` proof quantifies over every run that reaches the post. Every call is such a run. So at a caller, the assumed callee post reads only positions that the run makes defined. By the lemma, the assumption has its run value. A caller cannot use a non-self-framing post to read junk, because the caller's own reads carry `call-pre` or `WD` obligations. Self-framing protects a modular reasoner that does not see the body. LLMLL's verifier always sees the body of a body-faithful function. Add this paragraph to §4.2.

External precedent agrees with the chosen rule. SPARK 2014 checks run-time errors in a `Post` aspect at the subprogram's return points, in the context of the body. The cost that Rev 2 names is real: a body edit can make a fixed post ill-defined. The verifier reports that edit as `ill-defined` on the next run. So the cost is a re-verification, not a silent defect.

### `checker_soundness_version` in the artifact

The epoch belongs in the artifact. Without it, an artifact from 0.35.1 replays its stored `.fq` as SAFE, and that `.fq` has no `wd-*` constraints. The increase from `"6"` to `"7"` is correct. A `"6"` sidecar can hold `verified` on a clause that contradicts `nc-004`. N4 lists what the text must add for the check to work.

### The `rb` choice: no emission or a mark

**Recommendation: no emission, as Rev 2 proposes.** I withdraw the Rev 1 mark proposal (W1(b)). Four reasons:

1. **A mark changes no verdict.** A refused effective pre sends the whole function to `FallbackContractPre` (`FixpointEmit.hs:1659`). The function has no truth constraint. A marked `wd-pre` failure would also be a fallback. The only output change is a second cause on a function that already falls back.
2. **A mark needs new machinery.** To emit `wd-pre` there, the emitter must split the effective pre into translatable and refused conjuncts, and bind the parameters outside the arm where they are bound today. That is the partial-reflection path that `FixpointEmit.hs:1613-1618` refuses on purpose ("never a partial reflection").
3. **A success would be weak evidence.** A `wd-pre` proved without the alias fact proves definedness from fewer hypotheses. The trust report has no field to show it. The clause stays `asserted` in every case.
4. **The run time covers it.** The §4.6 guard reports an undefined pre as a violation of that pre. The `ill-defined` verdict is a static claim about every run. It is not needed where the function makes no static claim at all.

The cost of no emission: an `rb`-style function whose user pre is ill-defined for reasons unrelated to the refused alias gets no `ill-defined` verdict. It falls back with `contract-pre-outside-fragment` and the guard runs. That is the same outcome as a mark, minus one cause. The cost is acceptable.

N1 generalizes this choice. "No emission outside the arm where both clauses translate" is the same rule applied to every contract-level refusal.

### Recommendation

Settle Rev 2 after four small edits. Rev 3 is not needed. The design, the context rules, the drop-site inventory, the precedence, the divergence from Dafny and the stripping induction are correct.

Before settlement:

1. **N1.** Restate the `wd-*` emission gate as the `(Just postPred, Just mPre)` arm of `FixpointEmit.hs:1653`. No `WD` constraint for any other function.
2. **N2.** Add the fourth cause step: `callee-post-unassumed` only when some id carries that mark, otherwise `abstraction-unsafe`.
3. **N3.** Delete the "no output change" sentence. State that `refutedSet` counts complete TRUTH ids only, and add the MEAS-complete, TRUTH-marked test.
4. **N4.** Specify `.:?`, `/=` and the `classifyReplay` read for the artifact epoch. File D7.

In the settlement fold: N5 (qualified text on V5 and V9), N6 (count wording), N7 (two conditions of the canonical model), N8 (line numbers, S1 shipped, CALLEE-POST-UNASSUMED-1 shipped), N9 (defer V13), the W-Catalog sentence in §4.3, and the self-framing paragraph in §4.2.

Decision 10.3 (body-context rule): yes. Decision 10.5 (stamp and artifact): yes, with N4. The `rb` choice: no emission.
