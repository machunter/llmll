---
title: "Professor review: POST-CONJ-SPLIT-1 Rev 1, prove the admitted conjuncts of a post"
status: "Standalone review of Rev 1 DRAFT. Not folded into the proposal."
author: professor
date: 2026-11-02
reviews: "docs/design/post-conj-split-proposal.md (Rev 1, DRAFT 2026-11-02)"
verdict: "Accept with changes. Fix the false refutation (P1) first, as its own row."
---

# Professor review: POST-CONJ-SPLIT-1 Rev 1

## Restatement

The draft flattens the top-level `and` of the effective post into conjuncts. It
proves the conjuncts that `exprToPred` admits in one body VC per path, and it
records the refused conjuncts `asserted`. A caller assumes only the admitted
conjuncts. The clause stays `asserted` and not body-faithful, and a new
per-conjunct field carries the partial evidence. An UNSAFE answer on the
admitted conjuncts refutes the whole post.

## Context located

1. `compiler/src/LLMLL/FixpointEmit.hs:1514-1600`: `postCause`, `mPostPred`, `mPrePred`. The post is translated as one unit. The draft reads this correctly.
2. `FixpointEmit.hs:3736-3934` (`exprToPred`): admits `map-get` (`Map_select` on the value array) and `bytes-get` (`Map_select`). Both have run-time preconditions (`LLMLL.md` §13.12 table, `map-get` pre `(map-has m k)`, `bytes-get` pre `0 ≤ i < n`).
3. `compiler/src/LLMLL/CodegenHs.hs:581`: run-time `map-get` on an absent key calls `error`.
4. `FixpointEmit.hs:4633-4720`: call site. An untranslatable callee post sets `cvPostAssumption = Nothing`. The call result is then a free binder. The caller VC is still emitted.
5. `compiler/app/Main.hs:1646-1676`: `applyAbstractionVerdict` runs first. Then `refutedSet` = UNSAFE origins ∩ `erBodyFaithfulFns`. No test asks whether a callee post was dropped.
6. `compiler/src/LLMLL/AbstractionVerdict.hs:87,119`: reclassification considers only `erBodyFaithfulFns`.
7. Other readers of `erBodyFaithfulFns`: `ObligationAssembly.hs:1199`, `PatchApply.hs:738`, `Main.hs:1907`, `Main.hs:3610`.
8. `compiler/src/LLMLL/Diagnostic.hs:300-312`: `mkBodyFallbackWarning` says "so its post is assumed and not proved" for every cause.
9. `compiler/src/LLMLL/Contracts.hs:229-254`: `filterContracts` strips a post only when verified and body-faithful. The draft reads this correctly.
10. `compiler/src/LLMLL/TrustReport.hs:1563-1604`: `enrichEntry` folds `csPost` levels of every transitive callee into `calleeMinLevel`.
11. `compiler/src/LLMLL/ProofArtifact.hs:159-163`, `docs/proof-artifact.schema.json:17`: `fallback_reason` enum; "Null iff body-faithful".
12. `LLMLL.md:633` (§4.4.1): `refuted` is a modular disproof against "the callee contracts the verifier assumes".
13. `docs/compiler-team-roadmap.md:713` (ABSTRACTION-VERDICT-1): the precedent that an UNSAFE answer over incomplete hypotheses falls back. The user put wrong verdicts first.
14. External: Flanagan, *Hybrid Type Checking*, POPL 2006; Knowles and Flanagan, TOPLAS 2010. Bader, Aldrich and Tanter, *Gradual Program Verification*, VMCAI 2018; Wise et al., *Gradual Verification of Recursive Heap Data Structures*, OOPSLA 2020. Findler and Felleisen, *Contracts for Higher-Order Functions*, ICFP 2002. Wadler and Findler, *Well-Typed Programs Can't Be Blamed*, ESOP 2009. Godefroid, Nori, Rajamani and Tetali, *Compositional May-Must Program Analysis*, POPL 2010. Leino, *Dafny*, LPAR 2010 (well-formedness of specifications). SPARK 2014 reference manual (run-time checks in assertions and contracts).
15. `docs/design/`: no other draft on this topic. `docs/archive/professor-reviews/shell-call-pre-1-review.md` already uses the hybrid-checking reading for call sites.

## Measurements (llmll 0.35.1, one file at a time under `watch.py 2000 300`)

Scratch directory: the session scratchpad, `pcsrev/` (not committed).

| File | Callee post | Caller `use-it` (post `(>= result 2)`, body `(+ (callee n) 1)`) | exit |
|---|---|---|---|
| `whole.llmll` | `(all-pos? [result])`, refused whole | refuted | 1 |
| `rneed.llmll` | `(and (>= result 0) (all-pos? [result]))` | refuted | 1 |
| `mapdef.llmll` | `mk` returns `(map-empty)`, post `(= (map-get result 3) 0)` | (no caller) `mk` is `verified`, body-faithful, sidecar written | 0 |

`whole.llmll` has no admitted conjunct, so the split cannot change it. In
`rneed.llmll` the caller needs `result ≥ 1`, and only the refused conjunct
gives that fact. The split assumes `result ≥ 0` only, so `use-it` stays
refuted after the split. `mapdef.llmll` shows a `verified` post that the
built program cannot evaluate: `map-get` on key 3 calls `error`.

## Gaps and hazards

### P1. The false refutation is a separate defect. Fix it first. (soundness of verdicts; blocks)

The lead's witness `split.llmll` is a false refutation today. The cause is
not the conjunct structure. The cause is that `refutedSet` (`Main.hs:1672-1676`)
accepts an UNSAFE answer from a VC whose hypotheses are incomplete. A call
whose callee post did not translate gets a free result binder
(`FixpointEmit.hs:4648-4690`, `cvPostAssumption = Nothing`). The caller's VC
then lacks a hypothesis that the authored program supplies.

In the terms of Godefroid et al. (POPL 2010), an UNSAFE answer over a dropped
hypothesis is a *may* counterexample, not a *must* counterexample. A
refutation needs a must counterexample. ABSTRACTION-VERDICT-1 applied the same
rule to two calls of one callee. This case is the next member of the same
class.

`LLMLL.md:633` defines a refutation against "the callee contracts the verifier
assumes". Under that wording the verdict is conformant. But the same paragraph
says a correct program is refuted only "when a callee's `post` is weaker than
its body". Here the authored post is not weaker. The verifier dropped it. So
the spec wording and the behaviour both need a change.

The W-BODY-FALLBACK text adds a second error. For cause
`contract-post-outside-fragment`, "its post is assumed" is false: no caller
assumes it (`Diagnostic.hs:307`). The text is correct only for causes where
the post translates, such as `body-outside-fragment`.

The split does not remove this defect. Three cases stay after the split:

1. A callee post with no admitted conjunct (`whole.llmll`).
2. A caller that needs a fact from a refused conjunct (`rneed.llmll`).
3. A conjunct that a call-site sort guard drops (draft E11, `FixpointEmit.hs:4655-4664`).

Recommendation: file a separate row, for example `CALLEE-POST-UNASSUMED-1`,
and ship it before the split. Mark each constraint whose environment holds a
call result whose callee post exists and was not assumed in full. After the
solver, a function whose every failing constraint carries the mark falls
back, as `applyAbstractionVerdict` does. Use its own cause, so the census can
count it. Change the W-BODY-FALLBACK text by cause. For a refused post, say
"its post is not proved, and callers do not assume it". The stated cost is
the ABSTRACTION-VERDICT-1 cost: a wrong caller of such a callee also falls
back. That is acceptable, because the callee is already `asserted`.

### P2. §4.2 says the hypotheses are complete. They are not. (soundness of verdicts; blocks)

§4.2 justifies "refuted" with "the hypotheses are complete (full P, full
body)". The hypotheses of a body VC also include the callee posts at each
call. A partly proved function can call a callee whose post was dropped in
whole or in part. Its UNSAFE answer is then not a disproof. The draft must
state the condition: a refutation needs complete callee hypotheses on every
failing constraint. With P1 in place, the split inherits this rule with no
new mechanism.

A second gap is in the same paragraph. `applyAbstractionVerdict` reads only
`erBodyFaithfulFns` (`AbstractionVerdict.hs:87`). The draft adds the partly
proved list to `refutedSet` but not to the abstraction pass. A partly proved
function whose UNSAFE answer holds two calls of one callee would then be
reported refuted. That is a false refutation that ABSTRACTION-VERDICT-1 was
built to stop.

The draft names only `Main.hs:1672-1676`. Five other readers take
`erBodyFaithfulFns` (Context items 6 and 7). The engineer must decide, for
each one, whether a partly proved function belongs in it. Make this list part
of the plan, not a later discovery.

### P3. The totality argument in §4.3 is false as written. (spec-drift; complicates)

§4.3 reason 1 says the partial operations that need a guard are refused.
`map-get` and `bytes-get` are admitted (`FixpointEmit.hs`, the `map-get` and
`bytes-get` cases of `exprToPred`). Both have run-time preconditions
(`LLMLL.md` §13.12). In the logic they are total, because `Map_select` is
total. Outside the precondition, their logic value is an artefact of the
encoding. `mapdef.llmll` shows the result: a post is `verified` although its
run-time evaluation calls `error` (`CodegenHs.hs:581`).

Division and `mod` are not counterexamples. They are admitted only with a
numeral divisor greater than zero. Codegen emits `div` (`CodegenHs.hs:2434`),
which is floor division. SMT-LIB `div` with a positive divisor is also floor
division, so the two agree. Pair selectors are total, as the draft says.
MATCH-POST selectors sit under constructor tests inside one `exprToPred`
result, so the split never separates them.

The draft's conclusion survives in a narrower form. The *truth* obligation of
each conjunct is independent, because each SMT term denotes. The draft mixes
this with *well-definedness*, which is a different obligation. In Dafny the
earlier conjunct of `&&` is assumed only in the well-formedness check of the
later one, never in its truth proof. SPARK checks run-time errors in contracts
in the same way. So the question "may proving `c_1` assume `c_0`" has the
answer "no", but for a reason the draft does not give.

The split increases the exposure of this gap. Today
`(and (refused-guard r k) (= (map-get r k) 0))` is `asserted` in whole. After
the split, the second conjunct gets its own `verified` record. That record
claims a fact that has no run-time meaning without the guard. It is sound for
the conjunction, because it is proved over more states than the guard admits.
It is not sound as a standalone run-time claim.

Recommendation: rewrite §4.3 reason 1 with the two obligations kept apart.
Forbid per-conjunct stripping under `--contracts=unproven` until clause
well-definedness is checked. File a row for clause well-definedness (the
`mapdef.llmll` shape exists today, without the split). In the per-conjunct
record and text, do not present a conjunct as a run-time assertion that holds
alone.

### P4. Option B is correct, but the draft under-specifies it. (soundness; complicates)

The answer to the author's question is in the Recommendation. The
specification gaps are these:

1. The assumed level must be the meet over the conjuncts *actually assumed at that call site*, after the sort guards drop some (E11). It is not the meet over `A`.
2. The fold in `enrichEntry` is over transitive callees. Each hop must use the assumed level of that edge, not the clause level. Otherwise a grand-caller inherits `asserted` through a caller that did not assume `Q_R`.
3. A callee whose post is partly admitted but whose *body* falls back writes no `conjuncts` record (§4.6 writes it only for a partly proved post). The caller still assumes `Q_A` at that callee's level, which is `asserted`. State this case. The fail-closed default gives the right answer, but the spec must say it.
4. Record, in the caller's trust entry, which callee conjunct indices the caller assumed. Without them an auditor cannot check the meet.
5. State that a caller labelled `verified` under Option B is still refused by `--strict-verified-core` through its callee. That is consistent, because strict core requires every function in the core to be proved in full, but a reader will ask.

### P5. `body_faithful: false` now covers two states. (spec-drift; complicates)

Keeping the clause `asserted` is the correct conservative choice. Every reader
that keys on the clause then fails closed. But a partly proved function had a
body VC, can be refuted, and is not in `erBodyFaithfulFns`. Today
`body_faithful: false` means "no body VC was emitted". After the split it
also means "a body VC proved part of the post". The proof artifact schema says
`fallback_reason` is "Null iff body-faithful" (`proof-artifact.schema.json:17`).
A refuted partly proved function will carry `refuted: true` together with a
non-null `fallback_reason`. That combination does not exist today.

Recommendation: define clause `body_faithful` as "the whole clause is proved
by a body VC". Add a marker such as `partly_proved: true` on the entry. Add a
test that `mkFnRecord` accepts `refuted` with the new fallback reason.

### P6. Flattening only through `and`. (scope; accept)

Accept for Rev 1. The `=>` and `let` rewrites in E7 and E8 are sound under
strict immutability. They belong in a later revision. Specify two degenerate
inputs: `(and)` with no operand, and `(and a)` with one operand. Both are
legal surface forms.

The refusal label for `split.llmll` is `app:list-empty`, not
`app:all-pos?`. `refusedConstructs` stops at the deepest refusing node, so the
list literal hides the user call. After the split, the label is per conjunct
and authors will read it more. POST-CONJ-DIAG-1 should report the outermost
refusing user call as well.

### P7. Schema and version plan. (scope; accept with one condition)

`trust_report_version` 1.11.0 is correct. The new key changes what a caller
level means, and the 1.9.0 precedent applies. `proof_artifact_version` 0.2.0
is correct, because an old validator rejects the new enum value. Compiler
0.36.0 is correct, because exit codes change.

`checker_soundness_version` can stay `"6"`. The split only adds hypotheses at
call sites and adds goals where none were emitted. No recorded SAFE becomes
UNSAFE. The condition: the byte-identical `.fq` sweep must cover the call-site
change too. A caller of a callee with an unchanged, fully admitted post must
emit the same `cvPostAssumption` bytes.

The trust report schema has `additionalProperties: false` on its entry
objects (`docs/llmll-trust-report.schema.json:103` and nearby). The new keys
need schema rows in the same release.

### P8. PRE-CONJ-DROP-1. (soundness; accept with the P1 rule)

The rule "UNSAFE under a dropped pre conjunct falls back" is correct. It is
the same may/must rule as P1. Write both rows against one stated rule:
**refuted only when every hypothesis of every failing constraint is the
authored one.** A dropped pre conjunct can be the guard of a partial body
operation, such as a `bytes-get` index bound. The VC then fails on the call
precondition and falls back. Measure how often this happens before the row
claims a gain.

### P9. POST-CONJ-DIAG-1. (ergonomic; revise the plan)

One constraint per conjunct multiplies the cost of every run. A cheaper
design pays only on failure. On UNSAFE, re-solve the failing constraint once
for each admitted conjunct, and name the first conjunct that fails. A SAFE run
then costs nothing extra. This is the on-demand pattern that CALL-CONGRUENCE-1
planned and did not need.

## Recommendation

**Verdict: accept with changes.** The split is the smallest principled change.
It does not leave QF-LIA within `Σ_auto`, and it keeps every existing reader
fail-closed.

**Order.** Ship P1 as its own row first. It is a present false refutation, the
project ranks wrong verdicts first, and the split does not fix it
(`whole.llmll`, `rneed.llmll`). The split then depends on it for P2.

**Required changes, by severity.**

1. P1: separate row for UNSAFE over an unassumed callee post (fall back, own cause), plus the W-BODY-FALLBACK text by cause and the `LLMLL.md:633` wording. Ship first.
2. P2: state the complete-hypotheses condition for refutation; put the partly proved list into `applyAbstractionVerdict`; list every `erBodyFaithfulFns` reader with a decision for each.
3. P3: rewrite §4.3 reason 1 with truth and well-definedness kept apart; no per-conjunct stripping; file a clause well-definedness row (`mapdef.llmll`).
4. P4: specify Option B per call site and per edge, with the body-fallback case, the recorded conjunct indices and the strict-core interaction.
5. P5: define clause `body_faithful`, add a `partly_proved` marker, test `mkFnRecord` with `refuted` and the new cause.
6. P7: extend the byte-identical sweep to call sites; add trust-report schema rows.
7. P9: change POST-CONJ-DIAG-1 to re-solve on UNSAFE only.
8. P6: specify `(and)` and `(and a)`; report the outer refusing user call.

**Answer to the Option A/B question: Option B.**

The callee post is `Q = Q_A ∧ Q_R`. The caller's VC uses only `Q_A`, and
`Q_A` is proved against the callee body. So the caller's proof does not use
`Q_R` at all. The caller's guarantee holds even if `Q_R` is false, and even
if `--contracts=none` removes the run-time check of `Q_R`. Option A would make
the caller's label depend on a fact its proof does not use.

Hybrid type checking supports this reading. Flanagan inserts a cast only where
the static check cannot decide the subtyping. A site with no cast is checked
statically. Here the cast, the run-time check of `Q_R`, sits in the callee's
post. The caller needs no cast.

Gradual verification gives the same answer, but for a narrower reason. In
Bader, Aldrich and Tanter, an imprecise post `? ∧ φ` lets a caller assume more
than `φ` *optimistically*. A run-time check is then inserted *at the caller*,
and that caller is not statically verified. A caller that uses only the
precise part `φ` needs no inserted check. The LLMLL caller is the second kind:
it assumes `Q_A` only. Note that `Q_R` is precise but undecidable for the
prover, not an imprecise `?`. So the hybrid reading is the closer analogy.

Blame gives the third argument. Under Findler and Felleisen, a failure of
`Q_R` at run time blames the callee, the party that supplies the post. Wadler
and Findler show that the more precisely checked side cannot be blamed. The
caller cannot be blamed for `Q_R`.

Option B is correct only with the P4 specification. The caller's level must be
the meet over the conjuncts it actually assumed, edge by edge and transitively.
Option B also does not repair the case where the caller *needs* `Q_R`
(`rneed.llmll`). That caller is not verified under either option. P1 decides
what it reports.

## Open questions for the language-team

1. Justify, or remove, the claim in §4.3 that "the partial operations that need a guard are refused", given the `map-get` and `bytes-get` cases of `exprToPred` and the `mapdef.llmll` result.
2. State the refutation rule of §4.2 with the callee-hypothesis condition, and say which `erBodyFaithfulFns` readers (Context items 6 and 7) admit a partly proved function.

---

# Round 2 (appended at settlement, 2026-11-04)

The second professor review, of Rev 2. Appended unchanged, except that its headings are one level lower and an absolute scratchpad path is shortened. Its frontmatter:

- title: "Professor review, round 2: POST-CONJ-SPLIT-1, prove the admitted conjuncts of a post"
- author: professor
- date: 2026-11-04
- reviews: "docs/design/post-conj-split-proposal.md (Rev 2, DRAFT 2026-11-02, not settled)"
- prior: "docs/design/post-conj-split-professor-review.md (Rev 1, accept with changes)"
- also_read: "docs/design/clause-welldef-proposal.md (Rev 2, DRAFT 2026-11-03); CHANGELOG.md v0.36.0; LLMLL.md §4.4.1 (:633), §5.3.4 (:1160)"
- verdict: "Settle with named small edits (C1-C6). C1 must be fixed in this draft or in CLAUSE-WELLDEF-1 before both settle."

## POST-CONJ-SPLIT-1: professor review of Rev 2

### Restatement

Rev 2 flattens the top-level `and` of the effective post. It proves the admitted conjuncts in one body VC per path and records the refused conjuncts `asserted`. A function is refuted only when every hypothesis of every failing constraint is authored. A caller assumes only the admitted conjuncts and meets their levels per edge (Option B). The clause stays `asserted`, a `partly_proved` marker names the new state, and no conjunct is stripped. CALLEE-POST-UNASSUMED-1 supplies the verdict for an incomplete hypothesis.

**Verdict: settle with small edits.** Rev 2 answers every round-1 finding. It adds no new false `verified` and no new false `refuted`. CALLEE-POST-UNASSUMED-1 shipped in v0.36.0 with the rule this draft assumes, so the dependency is met. The open items are three cross-draft gaps with CLAUSE-WELLDEF-1 (C1, C2), stale text after v0.36.0 (C3, C4), one sweep condition (C5) and one missed reader (C6).

### Context located

1. `docs/design/post-conj-split-proposal.md` Rev 2: the object of this review.
2. `docs/design/post-conj-split-professor-review.md`: round 1, P1-P9.
3. `CHANGELOG.md` v0.36.0, CALLEE-POST-UNASSUMED-1: cause `callee-post-unassumed`, construct `post-unassumed:app:<callee>`, the cause-dependent `W-BODY-FALLBACK` text, and `proof-artifact.schema.json` gains the enum value with **no** `proof_artifact_version` change.
4. `LLMLL.md:633` (§4.4.1) and `:1160` (§5.3.4): the shipped refutation rule, "refuted only when every hypothesis of every failing constraint is the authored one". It is word for word the rule of Rev 2 §4.2.
5. `compiler/src/LLMLL/FixpointEmit.hs:4784-4801`: the three call-site guards (`syntacticUnsafePairRet`, `bytesOpOnResult`, `predHasDataTerm`). Each one drops the **whole** post today.
6. `FixpointEmit.hs:4857-4862`: `cvPostUnassumed = isJust (contractPost contract) && isNothing mPostSubst`. The shipped mark is all-or-nothing.
7. `compiler/src/LLMLL/AbstractionVerdict.hs:118-160`: one candidate set, keyed on `erBodyFaithfulFns` (`:128`), decides both `abstraction-unsafe` and `callee-post-unassumed`.
8. `compiler/app/Main.hs:1664-1690`: `bodyFaithfulSet` feeds `refutedSet` (`:1676`) and `descentDischargedFns` (`:1688`).
9. `compiler/src/LLMLL/TrustReport.hs:1595-1604`: `calleeMinLevel`, the flat fold that Option B replaces. The draft reads it correctly.
10. `docs/getting-started.md:567`: now "one of twelve fixed strings", with `callee-post-unassumed`. It says that "a call-site sort guard drops a conjunct".
11. `docs/design/clause-welldef-proposal.md` Rev 2 §4.2, §4.3 site S6, §4.4 (rule 1, row V13), §4.7 items 1-6, E14, Affected surface: the obligations that the split interacts with.
12. Measurement, this review: the local build `llmll 0.36.0` (`stack path --local-install-root`, contains the `post-unassumed` strings). Witnesses `split`, `bad`, `rneed`, `whole` copied to the session scratchpad (`decide/m/`). In each, the callee falls back with `contract-post-outside-fragment`, `use-it` falls back with `callee-post-unassumed` (`post-unassumed:app:<callee>`), and `verify` exits 0. This confirms the "After CALLEE-POST-UNASSUMED-1" column of §2.3.

### Disposition of round-1 findings

| Item | Status | Rev 2 section | Note |
|---|---|---|---|
| P1. False refutation is a separate defect; fix first | **Closed** | §3; §2.3 table | Shipped as CALLEE-POST-UNASSUMED-1 in v0.36.0. Measured (Context 12). §3 still describes it in the future tense (C3). |
| P2. Hypotheses are not complete; `applyAbstractionVerdict`; other readers | **Closed, one reader missed** | §4.2 refutation rule; §4.6 reader table; E17 | `descentDischargedFns` is not listed (C6). The `AbstractionVerdict` row should say that the union now also gates `callee-post-unassumed` (C6). |
| P3. Totality argument false; truth vs well-definedness | **Closed** | §4.3; §4.5; E13; §6 | CLAUSE-WELLDEF-1 is filed and drafted. The cross-draft gaps are C1 and C2. |
| P4. Option B under-specified | **Closed** | §4.4 items 1-6; E11; E15 | Per site after guards, per edge, body-fallback callee, recorded indices, strict core. |
| P5. `body_faithful: false` covers two states | **Closed** | §4.5 definitions; §4.6 `Main.hs:3610` row; §4.7 proof artifact | `partly_proved` marker; `mkFnRecord` test. |
| P6. Flatten through `and` only; degenerate `and`; outer label | **Closed** | §4.1; E14; §4.8 POST-CONJ-DIAG-1 | `(and)` and `(and a)` are `check` errors (measured on 0.35.1). |
| P7. Version plan; call-site sweep; schema rows | **Closed in content, stale in numbers** | §4.7 | See C4 and C5. |
| P8. PRE-CONJ-DROP-1 on the may/must rule | **Closed** | §4.8 | Measure first. |
| P9. POST-CONJ-DIAG-1 re-solve on UNSAFE only | **Closed** | §4.8 | |
| Open question 1 (totality claim) | **Answered** | §4.3 | Removed. |
| Open question 2 (refutation rule, readers) | **Answered** | §4.2; §4.6 | |

### Does v0.36.0 change the draft?

The shipped rule is the rule the draft assumes, so the design does not change. Three details of the shipped code matter.

1. **The shipped mark is all-or-nothing** (`FixpointEmit.hs:4862`). It fires when the whole post is not assumed. The split assumes a subset `S`. The draft already says that the mark input must become "`S` is not every conjunct" (§3, last paragraph). Keep that sentence, and cite `cvPostUnassumed` by name.
2. **Today each guard drops the whole post** (`FixpointEmit.hs:4784-4801`). `LLMLL.md:1160` and `getting-started.md:567` say "a call-site sort guard drops a conjunct". That wording is drift on the shipped tree. The split makes it true, because §4.4 applies each guard per conjunct. Route the wording to documentation-lead at the split ship, or correct it now to "drops the post".
3. **The shipped `W-BODY-FALLBACK` text says "A callee post is assumed only when all of it is inside the decidable fragment."** After the split, that sentence is false. A partly admitted post is partly assumed. See C3.

### Gaps and hazards in Rev 2

#### C1. CLAUSE-WELLDEF-1 emits `wd-post` only for body-faithful functions. A partly proved function is not body-faithful. (soundness of the pair; must fix before both settle)

**Classification:** soundness, in combination. **Bite:** blocks the pair, not this draft alone. The fix is one sentence.

CLAUSE-WELLDEF-1 Rev 2 emits `wd-post` "on each path of a body-faithful function" (§4.2; Affected surface). It emits nothing for a body-fallback function (site S5). A partly proved function is in `body_fallback` with the new cause and is not in `erBodyFaithfulFns` (split §4.5). If the engineer reads "body-faithful" as `erBodyFaithfulFns`, a partly proved function gets no `wd-post` constraint. Its admitted conjuncts are then `verified` with no well-definedness proof. That contradicts CLAUSE-WELLDEF-1 §4.7 item 2 ("verified only when its truth and its well-definedness are both proved"). It also leaves the `mapdef.llmll` exposure open in exactly the place where the split increases it (split §4.3).

**Required edit.** State in both drafts that `wd-post` is emitted on each path of every function **with a body VC**, which is the union of `erBodyFaithfulFns` and `erPartlyProvedFns`. This is the split's own rule for a reader that asks "did a body VC run?" (§4.6). Add the CLAUSE-WELLDEF-1 emission decision as a row of the split's §4.6 table.

#### C2. Two more points of disagreement with CLAUSE-WELLDEF-1. (spec drift; small edits; one user choice)

1. **The refuted rule.** CLAUSE-WELLDEF-1 §4.4 rule 1 gives `refuted` "for TRUTH (body-faithful functions only, as `refutedSet` requires today)". The split changes `refutedSet` to the union (§4.6). Whichever draft ships second must say "body-faithful or partly proved".
2. **Per-conjunct or per-function fallback.** CLAUSE-WELLDEF-1 row V13 and E14 say "the conjunct falls back" and "conjunct 2 is `asserted`". The split's verdicts (§4.2) are per function: a marked UNSAFE makes every conjunct `asserted`. The verdict path (`applyAbstractionVerdict`) is per function too. These two texts conflict. **Recommendation:** per function in v1, as the split says. A per-conjunct fallback needs a sidecar `conjuncts` record on a non-SAFE run, which §4.7 does not define. This is the user's choice. Per conjunct keeps more evidence, at the cost of a new record state.
3. **The `dropped-context` mark (site S6).** Only the split can produce it, and the split does not mention it. Add to split §4.3 and Affected surface: "if CLAUSE-WELLDEF-1 has shipped, a `wd-post` obligation whose context omits a refused earlier conjunct carries the `dropped-context` mark".
4. **Ship order.** Neither draft orders the split against CLAUSE-WELLDEF-1. Both orders are sound. The split contains the exposure by "no stripping" and by its wording. CLAUSE-WELLDEF-1 repairs a present defect (`mapdef.llmll`, xm3). **Recommendation:** CLAUSE-WELLDEF-1 first. Then the split carries items 1 and 3 and the C1 sentence, and its per-conjunct wording becomes "proved, and defined where evaluated" from the start (CLAUSE-WELLDEF-1 §4.7 item 6). This is the user's choice.

#### C3. Rev 2 text predates v0.36.0. (spec drift; small edits)

1. §3 describes CALLEE-POST-UNASSUMED-1 as future work ("ships first", "marks", "That row also changes …"). Rewrite it as shipped: cite `LLMLL.md:1160`, v0.36.0, and `cvPostUnassumed`.
2. §2.3: the "After CALLEE-POST-UNASSUMED-1" column is now measured, not predicted. Context 12 confirms it for `split`, `bad`, `rneed` and `whole`.
3. The shipped `W-BODY-FALLBACK` text for `callee-post-unassumed` ends "A callee post is assumed only when all of it is inside the decidable fragment." After the split, change it to name the assumed subset, for example: "The verifier assumed conjuncts 0 of the post of 'pos-or-one'; conjunct 1 is outside the fragment." The construct `post-unassumed:app:<callee>` should carry the unassumed indices, for example `post-unassumed:app:pos-or-one[1]`. Add both to §4.5 and §7.
4. The new cause `contract-post-partly-outside-fragment` needs its own `W-BODY-FALLBACK` ending. v0.36.0 made the ending depend on the cause. Proposed: "so N of M post conjuncts are proved, and callers assume only those."

#### C4. The version plan is stale and conflicts with the v0.36.0 precedent. (spec drift; one user choice)

1. §4.7 "Compiler version: a minor release (`0.36.0`)". v0.36.0 has shipped. The split is the next minor release, `0.37.0` or later.
2. §4.5 "With CALLEE-POST-UNASSUMED-1 it grows by two in all." It has already grown by one. The split adds one. §4.7 "one of eleven fixed": `getting-started.md:567` now says twelve. The split makes it thirteen.
3. **`proof_artifact_version`.** The split says that a new `fallback_reason` value breaks an old validator, so the version goes to `0.2.0`. v0.36.0 added `callee-post-unassumed` to the same enum with no version change. Both cannot be the rule. The split's reasoning is correct: the enum is closed, so an old validator rejects the new value. **Recommendation:** the split takes `0.2.0`, and its note says that `0.1.0` already admits `callee-post-unassumed` since v0.36.0. CLAUSE-WELLDEF-1 also takes a minor increase (W6). The second of the two to ship takes `0.3.0`. This is the user's choice of rule.
4. **`checker_soundness_version`.** CLAUSE-WELLDEF-1 changes it to `"7"`. If that row ships first, the split's sentence becomes "stays at its current value". The byte-identical sweep then compares `.fq` files that already hold `wd-*` constraints.
5. **`trust_report_version`.** Both drafts take a minor increase. The second to ship takes the next one.

#### C5. The byte-identical sweep condition is too strong. (precision; small edit)

§4.7 requires a byte-identical `.fq` "for every corpus file with no partly admitted post". The split also applies each guard per conjunct (§4.4). A callee whose post translates in full, and one of whose conjuncts trips `bytesOpOnResult` or `predHasDataTerm`, loses its whole post at the call today. After the split, the caller assumes the other conjuncts. The `.fq` bytes change at that call site, although no post is partly admitted. The change is sound: it adds a hypothesis, and no recorded SAFE becomes UNSAFE. But the sweep as written fails on such a file, or the engineer weakens the guard to pass it.

**Required edit.** Exempt a call site where a guard fires on some conjunct but not all. List such sites in the census output. The professor's P7 condition (unchanged `cvPostAssumption` bytes for an unchanged, fully admitted callee post) still holds for every other call site.

#### C6. Two reader details. (spec precision; small edits)

1. **`descentDischargedFns` (`Main.hs:1688`) reads `bodyFaithfulSet`.** The §4.6 table omits it. Decision: `erBodyFaithfulFns` alone. A partly proved recursive function then keeps `termination_unverified`, which fails closed. Also state whether the emitter emits descent obligations for a partly proved function. A failure of one is `measure-not-decreasing`, which does not need body-faithfulness (`Main.hs:1674-1675`).
2. **The `AbstractionVerdict` row.** In v0.36.0 the candidate set at `AbstractionVerdict.hs:128` decides both causes. So the union also makes `callee-post-unassumed` reachable for a partly proved function. Without the union, a partly proved caller of a partly proved callee is falsely refuted, which is risk 3 of the draft. Say so in the row. The cited line `:87` is now `aoFallbackFns`; the set is at `:128`.

#### C7. The Y4M gain is narrower than §2.2 suggests. (scope; note only)

§4.6 keeps `PatchApply` on `erBodyFaithfulFns` alone. So `patch --require-proof` still answers `PatchNotProved` for the original `next-p` contract. The gain is the message (it names the refused conjunct), the three `verified` conjunct records and Option B for callers. The author still rewrites the `if` conjunct to get the fill accepted. State this in §2.2, so that the user does not expect F4 to disappear.

### No new soundness issue in a verdict

I checked the places where Rev 2 adds a hypothesis or a goal.

1. **A partly proved function's refutation.** The refused conjuncts are goals. Leaving a goal out does not weaken the hypotheses. A model in which an admitted conjunct is false is a model in which the post is false. Combined with the shipped rule (complete hypotheses), an UNSAFE answer is a modular disproof, as §4.2 says.
2. **Option B.** The caller's proof uses only `Q_A`, and `Q_A` was proved against the callee body. The per-edge meet over `S` makes the caller's level depend only on what it assumed. An empty `S` keeps today's clause-level meet. A body-fallback callee gives `asserted` through the edge (E15). A refuted callee still gives `depends-on-refuted`. No level is higher than the evidence it rests on.
3. **Per-conjunct guards.** A guard still drops every conjunct that it would have crashed on. Dropping a hypothesis is a sound weakening. The shipped mark then routes the UNSAFE answer to a fallback.
4. **Self-recursion.** A recursive call assumes `Q_A` while the body proves `Q_A`. That is ordinary partial correctness, and the call is marked, so an UNSAFE answer falls back.
5. **Well-definedness.** The split does not add a run-time claim. The whole post stays checked. A `verified` conjunct over a junk read is exposed only through its record wording until CLAUSE-WELLDEF-1, and C1 closes the gap after it.

### Recommendation

Settle Rev 2 after these edits.

1. **C1 (must fix before both settle).** `wd-post` is emitted for every function with a body VC (the union). Add that decision to §4.6, and the same sentence to CLAUSE-WELLDEF-1.
2. **C2.** Align the refuted rule (union). Choose per-function fallback for `clause-welldef-unproved` in v1. Add the `dropped-context` mark to the split. Choose the ship order; CLAUSE-WELLDEF-1 first is recommended.
3. **C3.** Rewrite §3 as shipped. Record the §2.3 measurements. Change the shipped `W-BODY-FALLBACK` sentence and the construct to name indices. Add an ending for the new cause.
4. **C4.** Compiler `0.37.0`. Cause counts. One rule for `proof_artifact_version`, and coordinate the three version numbers with CLAUSE-WELLDEF-1.
5. **C5.** Exempt call sites where a guard fires on some conjuncts from the byte-identical sweep.
6. **C6.** Add `descentDischargedFns` to §4.6, and state the `AbstractionVerdict` union's second effect.
7. **C7.** State in §2.2 that `patch --require-proof` still refuses the original `next-p`.

### Open questions for the language-team

1. Under C2 item 2, state whether a `clause-welldef-unproved` failure on one conjunct of a partly proved function makes every conjunct `asserted`, or only that conjunct. Align CLAUSE-WELLDEF-1 row V13 and E14 with the answer.
