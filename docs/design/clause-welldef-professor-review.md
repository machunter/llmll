---
title: "Professor review: CLAUSE-WELLDEF-1 Rev 1, prove that each partial operation in a clause is defined where it is evaluated"
status: "Standalone review of Rev 1 DRAFT. Not folded into the proposal."
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
10. /private/tmp/claude-501/-Users-burcsahinoglu-Documents-llmll/0b4801a1-2e16-4efa-838b-2282560e27b9/scratchpad/callee-post-unassumed-plan.md §"The verdict rule": rule 2, "one non-candidate id blocks the function".
11. `compiler/src/LLMLL/VerifiedCache.hs:398-399` (`checkerSoundnessVersion = "6"`) and `docs/proof-artifact.schema.json:8-23`: the proof artifact has no soundness stamp (W6).
12. `docs/design/post-conj-split-proposal.md` Rev 2 §4.3, §4.5, E13; `docs/design/post-conj-split-professor-review.md` P3, P8.
13. `LLMLL.md:3343` (§13.12 `bytes-set` row), `LLMLL.md:776` and `:1134`: the value range `0..255` is stated in two places and missing from the table. This confirms D2.

External: Leino, "Dafny: An Automatic Program Verifier for Functional Correctness" (LPAR 2010), and the Dafny reference manual on the well-formedness of specifications; Chalin, "A Sound Assertion Semantics for the Dependable Systems Evolution Verifying Compiler" (ICSE 2007), the "strong validity" reading.

## Measurements (llmll 0.35.1, one file at a time under `watch.py 2000 300`)

Copies are in /private/tmp/claude-501/-Users-burcsahinoglu-Documents-llmll/0b4801a1-2e16-4efa-838b-2282560e27b9/scratchpad/profrev/.

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
