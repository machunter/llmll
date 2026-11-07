---
name: mul-var-professor-review
title: "Professor review of MUL-VAR-1 Rev 1"
status: "Review of Rev 1 DRAFT at commit 8baaa121. Standalone. Not folded."
date: 2026-11-07
author: professor
reviews: docs/design/mul-var-proposal.md
---

# Professor review of MUL-VAR-1 Rev 1

**Verdict: accept the direction, and do not settle Rev 1.** Keep Option B for proofs. Each fact is sound. Two gaps block settlement: an offset bug no longer reports `refuted`, and the normal form misses regrouped products.

## Restatement

The draft abstracts `(* a b)` to an uninterpreted function `mul` in QF-UFLIA. It adds ground instances of ordered-ring theorems to each constraint, and it reads UNSAFE on a constraint that holds `mul` as a fallback. The draft asks whether this abstraction is the right default, against native QF-NIA.

## Context located

1. `docs/design/mul-var-proposal.md` Rev 1: the artifact. No other draft exists on this topic.
2. `LLMLL.md:13-14`: says that the decision is complete inside `Σ_auto`, and that UNSAFE is `refuted`.
3. `LLMLL.md:3360`: four ground-fact families have an existing disclosure.
4. `compiler/src/LLMLL/TypeCheck.hs:118`: `*` has the type `int → int → int`, and no float form exists.
5. `compiler/src/LLMLL/TypeCheck.hs:3441`, `compiler/src/LLMLL/HoleAnalysis.hs:154,157,204,207`: the readers of `isNonLinear`.
6. `compiler/src/LLMLL/FixpointEmit.hs:1137-1149`: `abstracted` scans call binders only (`cbAbstractable`).
7. `compiler/src/LLMLL/FixpointEmit.hs:392,402`: `sealedAxiomBuiltins` and `abstractedBuiltins`.
8. `compiler/src/LLMLL/AbstractionVerdict.hs:195-225`: rule 2, and the `WdMarkedOnly` route for a definedness id.
9. `compiler/src/LLMLL/Feasibility.hs:262-272`: the compiler already runs `z3 -in` directly.
10. `compiler/src/LLMLL/FixpointIR.hs:292-293,327`: a variable keeps its name after `sanitizeFQId`.
11. `compiler/src/LLMLL/TrustReport.hs:168,1914,1996-2004,2270,2494`: family C ground facts in the trust report.
12. `compiler/src/LLMLL/ProofArtifact.hs:267-268`: `codegenSemanticsVersion = "int-unbounded-1"`.
13. External sources: see the citation table in gap 11.

## Measurements added by this review

All runs used z3 4.15.4 and liquid-fixpoint 0.9.6.3.7. All VCs were hand-built, as in the draft. **Nothing ran through `llmll verify`, and z3 4.8.12 was not run.** The scripts are in the session scratchpad under `mulvar/`, in `prof_*.py`, and are not committed. I added seven true witnesses (P1 to P7) and two false witnesses (N1, N2).

| Encoding | True proved, of 34 | False proved, of 11 | Note |
|---|---:|---:|---|
| A, native `*` | 33 | 0 | Misses W23 (timeout) |
| B, draft facts F1 to F6 | 24 | 0 | With F7, 25. Misses W14, W20 (without F7), W23, W25, P1 to P6 |
| Slack products, z3 alone | 33 | 0 | Misses W23. See gap 6 for the fixpoint cost |

| New witness, true | Claim | Draft B | With the added equation (F-table, `fixpoint`) |
|---|---|---|---|
| P1 | `w*(h*c) = (w*h)*c` | fail | Not run. Normal form makes the two sides one term |
| P2 | a value regrouped from `(y*w)*c` to `y*(w*c)` | fail | Not run. Normal form makes the two sides one term |
| P3 | `(y*w+x)*ch+c < h*(w*ch)` | fail | SAFE, 2.7 s, 529 facts |
| P4 | `st=w*ch`, offset below `(w*h)*ch` | fail | SAFE, 0.98 s, 300 facts |
| P5 | `ch=3 ⟹ (w*h)*ch = 3*(w*h)` | fail | SAFE, 0.2 s |
| P6 | `a=d ∧ b=c ⟹ a*b = c*d`, any sign | fail | SAFE, 0.13 s |

I wrote each added equation by hand, for that one witness. This shows that the facts reach these claims once the equation is present. It does not measure an emitter that generates the equations.

## Gaps and hazards

No soundness gap exists in the facts. The severity order below starts with the gaps that block settlement.

### 1. An offset bug exits 0: ergonomic, blocks

**Cite:** draft "Verdict" and edge case 1; `compiler/src/LLMLL/AbstractionVerdict.hs:195-225`; `LLMLL.md:13-14`.

The false claim M1 is the off-by-one offset, which is the bug that this feature exists to catch. Under the draft, it gives fallback, exit 0, and a run-time stop. A `bytes-get` call-pre with the same wrong bound takes the same route. A marked definedness id in a clause gives `clause-welldef-unproved`, not `ill-defined`.

The draft says that `--require-proof` still refuses, but default `verify` is the path that most users run. The draft calls this a loss of information. For a contract language at the image-buffer boundary, a verdict of "not known" on a checkable bug is a product failure.

The mark also reaches callers. A callee post with a product now enters the caller's environment after substitution. So a linear bug in that caller, which reports `refuted` today, can become a fallback. That is a regression for an existing program, although the corpus affected is small (draft measurement 7).

The fix is cheap. The native query with model validation gave `sat` on all nine false witnesses M1 to M9, in at most 0.048 s under a 2 s limit (`prof_checks.py`). In an earlier run under a 5 s limit, N1 and N2 also gave `sat`, in at most 0.043 s. It gave `unsat` on 26 true witnesses, `timeout` on W23, and `sat` on no true witness.

### 2. The normal form misses regrouped products: ergonomic, blocks

**Cite:** draft "Reflection", lines 151-155; P1 to P6 above.

The draft keeps nested `mul(mul(w, h), ch)` and has no associativity. A library that writes `w*(h*ch)` in one module and `(w*h)*ch` in another cannot connect them. The Y4M and netpbm shapes have three factors, so this occurs in normal use. The draft's witness set did not include a second grouping, so its 24 of 27 overstates coverage.

Canonical argument order has a second effect on UF congruence. After sorting, `a*b` and `c*d` with `a=d, b=c` are aligned as `mul(a,b)` and `mul(c,d)`. Congruence then needs `a=c` and `b=d`, which the hypotheses do not give. So the canonical order loses the commuted case when the alias is not syntactic. W18 passes only because F4 gives both bounds on nonnegative values. P6 at any sign fails.

A `let` constant has the same gap. `ch=3` is a hypothesis and not a ground operand, so `mul(mul(w,h),ch)` stays unrelated to `3·mul(w,h)` (P5).

### 3. "Stays decidable" is true of the encoding only: spec-drift, complicates

**Cite:** draft table, "Stays decidable? Yes, QF-UFLIA"; `LLMLL.md:13-14`.

QF-UFLIA is decidable, but the solver then decides the abstraction and not the property. `LLMLL.md:13-14` defines `Σ_auto` by completeness, and it reads UNSAFE as `refuted`. Neither statement holds for a term with `mul`. So the record must not widen `Σ_auto`. It needs a separate class in `LLMLL.md` §5.3.3: "decidable abstraction, sound for SAFE, incomplete".

### 4. The mark needs a new scan: soundness of `refuted`, complicates

**Cite:** `compiler/src/LLMLL/FixpointEmit.hs:1137-1149`; draft "Affected surface".

`abstracted` reads call binders through `cbAbstractable`. A `mul` term has no call binder: it appears inside a predicate. The draft says "`mul` as an abstracted term", and names `AbstractionVerdict.hs`, but the change is in the emitter. If the scan misses one site, a true program with a product can report a false `refuted`. That is the one wrong verdict that this design can cause.

The scan must cover environment binders, the `lhs`, the `rhs`, callee posts after substitution, S9 definedness assumptions, and definedness goals. A negative test needs a true claim that B cannot prove, at each of those sites. W23 and W25 are suitable.

### 5. The name `mul` can collide with a parameter: ergonomic, complicates

**Cite:** `compiler/src/LLMLL/FixpointIR.hs:292-293,327`; draft "`constant mul`".

A `.fq` file that holds `constant mul` and a binder named `mul` crashes liquid-fixpoint with "Multiple sorts" (`prof_checks.py`, hand-written `.fq`). `sanitizeFQId` keeps the name of a variable, so a parameter named `mul` looks likely to reach this. I did not run this through `llmll verify`. Use a name that source cannot produce, and add a test with a parameter named `mul`.

### 6. The fact set defines what verifies, and the draft leaves it open: scope, matters at scale

**Cite:** draft measurement 2 and edge case 11, "Spec is silent (intentional)".

The draft lets the engineer filter pairs, because a missing fact can only lose a proof. That is correct for soundness. But the facts now decide which programs verify, so a filter is a language change. My own goal-directed filter lost W4, W7 and W26 at two rounds, and it lost 17 true witnesses at one round, not counting W23, while z3 stayed fast. So do not assume that a filter is free. Hold each filter change to `scripts/fallback_census.py` and the witness table.

**Slack products are not ready.** The schema "a product of two nonnegative hypothesis slacks is nonnegative" is Sherali–Adams level 2 (RLT). It replaces F1, F3, F4, F5, F7 and F8 with one theorem, and in z3 it proved 33 of 34. It is also better at scale in z3 alone. Through `fixpoint`, it is much worse.

| Extra product goals (K) | Draft B facts, `fixpoint` | Slack facts, `fixpoint` | Slack, z3 alone |
|---:|---:|---:|---:|
| 2 | 136, 0.64 s | 57, 1.6 s | 0.017 s |
| 5 | 406, 1.54 s | 150, 4.82 s | 0.036 s |
| 10 | 1176, 4.62 s | 405, 33.37 s | 0.076 s |
| 20 | 3916, 15.05 s | 1290, no result in 300 s | 0.089 s |

W5 also gave no result in 60 s through `fixpoint` under this schema. The fact count is not the cause: 34 facts at K=10 still took 21.58 s. Environment binders are not the cause either: global constants took 26.73 s at K=10. **I did not locate the cause.** So this review does not recommend the schema for the first release.

### 7. The Lean worklist loses claims that B cannot prove: scope, complicates

**Cite:** draft "Affected surface", `isNonLinear`; `compiler/src/LLMLL/HoleAnalysis.hs:154,157,204,207`; `compiler/src/LLMLL/TypeCheck.hs:3441`.

The draft makes `isNonLinear` stop flagging a two-variable `*`. W14, W23 and W25 then have no route to the worklist and no warning. The draft's own "What B does not prove" section sends these claims to Lean. Select the worklist from the outcome (a function fell back with construct `abstraction:nonlinear:*`), not from syntax.

### 8. A `def` fallback appears later and at the caller: ergonomic, complicates

**Cite:** draft decision 3; `examples/y4m/FRICTION.md` (the `chroma-dim` case); `compiler/src/LLMLL/Syntax.hs` (`isCoreBodySyntactic`).

Today `check` refuses a product in a `def` at once. After decision 3, a `def` with an unprovable product passes `check`. It then falls back at `verify`, and that causes `core-membership-violation` at its callers. The message must name the product and the fallback in the callee.

### 9. `assumed_facts` is the wrong field: spec-drift, complicates

**Cite:** draft decision 4; `LLMLL.md:3360`; `compiler/src/LLMLL/TrustReport.hs:1996-2004,2270`.

The facts are theorems, so "assumed" is incorrect. A new kind also increases `trust_report_version` for no benefit. Family C already reports ground-fact families in one line. Add one family. Check the schema of each fact in a test, by native z3 or Lean, and not per program.

### 10. The facts rest on `int-unbounded-1`, and F5 is integer-only: soundness, no failure today

**Cite:** `compiler/src/LLMLL/ProofArtifact.hs:267-268`; `compiler/src/LLMLL/TypeCheck.hs:118`.

I checked each fact. On `Int`, z3 reports `unsat` for each negation. A Python grid of 26 values in each of four positions, with values up to `2^127` in magnitude, gave 0 failures (F7 is excepted from the grid because it uses fixed literals in this check). Two controls show that the check can fail: F5 without `b ≥ 0` gave 26702 failures, and F5 without `c ≥ 0` gave 3773.

F5 has this certificate: `cd − ab − b = (c−a−1)·b + c·(d−b)`. Each term is a product of nonnegative values. `a < c ⟹ c−a−1 ≥ 0` holds on integers only. On `Real`, z3 gives `sat` for its negation, for example at `a=0, c=½, b=d=1`. No float `*` exists today, so this causes no failure. A future float `*` must not receive F5.

**The facts stay sound under the verdict rule.** Each ground instance is true at every integer valuation. Take the standard model with `mul` as `*`. If `H ∧ F ⟹ G` is valid, then `F` is true there, so `H ⟹ G` is true. So SAFE stays sound. No path condition is needed for a fact, and short-circuit context does not matter. A factor that is a total-logic value of `Map_select` is still an integer, so the fact holds for it.

The draft says that the facts rest on nothing "beyond `*` itself". The correct statement is that they rest on `int-unbounded-1`. A machine-integer codegen would make F1, F3, F4, F5 and F8 false, and those facts must follow `codegen_semantics_version`.

**`*` is total, so no definedness entry is correct.** The draft's edge case 6 is correct: a partial read in a factor keeps its own obligation. `mul` has no call binder, so the call counts of `CALL-CONGRUENCE-1` and clause 2 do not apply. UF congruence holds, with the limit in gap 2. Canonicalize after substitution, or one product splits into two terms and a proof is lost.

### 11. The citations are partly incorrect: spec-drift, complicates

**Cite:** draft "Design-reference set".

The draft's phrase "a fixed, one-round form of that method" overstates the relation to incremental linearization. That method is a refinement loop, and its tangent lemmas need a point from a model. F1 to F8 hold no tangent, and F5 uses integrality. Use: "shares the sign and monotonicity lemma families, and has no refinement loop".

| Claim | Status | Source |
|---|---|---|
| Cimatti et al., incremental linearization for NRA and NTA | Confirmed. TOCL 19(3), 2018 | [IRIS record](https://iris.unitn.it/handle/11572/210160), [PDF](https://iris.unitn.it/retrieve/e3835195-298b-72ef-e053-3705fe0ad821/main.pdf) |
| The same authors on NIA | Confirmed. SAT 2018, LNCS 10929, pp. 383-398 | Same search |
| The lemma names sign, monotonicity and tangent | Not confirmed by search. From memory | None |
| Dafny `--disable-nonlinear-arithmetic`, older `/noNLarith` | Confirmed. The man page says more manual work and more predictable. "Unstable" is the draft's word | [man page](https://manpages.ubuntu.com/manpages/jammy/man1/dafny.1.html), [issue 4703](https://github.com/dafny-lang/dafny/issues/4703) |
| Verus `by(nonlinear_arith)` | Confirmed. Default mode disables nonlinear theories. The query is separate and sees only `requires` | [guide](https://verus-lang.github.io/verus/guide/nonlinear.html), [reference](https://verus-lang.github.io/verus/guide/reference-assert-by-nonlinear.html) |
| Liquid Haskell `--linear` makes `*` uninterpreted | Not confirmed. `fixpoint --help` lists `--linear` with no description | Local help |
| Sherali–Adams RLT, products of constraints | Confirmed in outline | [Liberti slides](https://sea2012.labri.fr/uploads/Main/liberti-rrlt-slides-sea12.pdf), [Optimization Online](https://optimization-online.org/2001/12/412/) |
| Handelman 1988 | Confirmed from the record and secondary sources, not from the full paper. Pacific J. Math. 132(1), pp. 35-62 | [MSP](https://msp.org/pjm/1988/132-1/pjm-v132-n1-p04-s.pdf), [MaRDI](https://portal.mardi4nfdi.de/wiki/Item:Q1112337) |
| Matiyasevich 1970, undecidability of NIA | Not searched. Standard result, from general knowledge | None |

### 12. The evidence has known limits: scope, complicates

**Cite:** draft risks 2, 4 and 5.

All numbers here and in the draft come from hand-built VCs. My P set shows that the witness set was incomplete after one independent pass, so expect more gaps from real contracts. The first implementation step must repeat the table through `llmll verify`, and must restate the Y4M and netpbm contracts. z3 4.8.12 cannot affect the soundness of B or of the recheck, but it can change which false claims report `refuted`.

## Recommendation

**Rank 1: Option B for proofs, native z3 only for `sat`, in one release.** B wins on SAFE. Option A's timeout turns a true claim into UNSAFE: I reproduced W23 as UNSAFE in 2.23 s. Under A, a `verified` verdict depends on the z3 version and on machine load. The native engine is still the best refuter available, and a one-sided use of it adds no trust to `verified`.

Illustrative rule, for the language-team to formalize:

```
SAFE from fixpoint                         → verified
UNSAFE, marked, and mul is the only mark:
   native z3 with mul ↦ *, short limit, sat, model validates → refuted
   unsat, unknown, timeout, process error                    → fallback
UNSAFE, marked with another abstraction    → as today
```

Run z3 directly, because liquid-fixpoint reads `unknown` as UNSAFE (draft measurement 5). `compiler/src/LLMLL/Feasibility.hs:262-272` is the precedent, and it needs a limit added. A weaker z3 can only lose a refutation. So `refuted` varies by z3 version, while `verified` does not. This one-sided use follows the same idea as Verus's separate nonlinear query: the nonlinear engine stays out of the default proof. A native `unsat` in this path must not count as `verified`.

**Rank 2: close the grouping gap with the smallest change.** Keep F1 to F8. Add these to the normal form and facts:

- Normalize a product to a sorted flat multiset of atoms, so comm and assoc are syntactic. An emitter that keeps nested terms must add ground regrouping equations instead.
- Add cross congruence: `a=d ∧ b=c ⟹ mul(a,b) = mul(c,d)`, at any sign.
- Add the literal factor: `a=k ⟹ mul(a,b) = k·b`, for each literal `k` in the hypotheses. F2 is the case of 0 and 1.

The hand-supplied equations proved P3 to P6 through `fixpoint`. I did not measure the generated form, and the fact count can increase: P3 went from 301 to 529 facts.

**Rank 3: state the class honestly.** The draft's open question has a negative answer. I know of no fixed-degree one-round ground set that is complete for a natural bilinear class, and NIA is undecidable. Handelman's theorem gives a certificate of unbounded degree, for a strictly positive polynomial on a compact polytope. The image domain has unbounded `w` and `h`, so that theorem does not apply to it directly. The spec text stays "sound and incomplete". Do not claim a class in §5.3.3, and keep the witness table as the coverage evidence.

**Rank 4: file a measurement row for slack products.** The row asks why `fixpoint` is slow on this schema while z3 is fast. If the cause is removed, this schema gives a statable certificate class: "linear in monomials over products of hypothesis slacks up to degree d". It also proved W14, W20 and W25. It does not belong in the first release.

**Decisions in the draft:**

| # | Decision | Change? | Result |
|---:|---|---|---|
| 1 | Encoding | **Refine** | B for proofs. Native z3 for `sat` only. Reject A as the proof engine |
| 2 | Refutation | **Change** | Restore `refuted` in the same release. Do not defer the recheck |
| 3 | `def` bodies | Keep | Admit, with the message in gap 8 |
| 4 | Disclosure | **Change** | Use a family C ground-fact family. No new `assumed_facts` kind, and no increase of `trust_report_version` |
| 5 | Variable divisors | Keep | Separate `DIV-VAR-1` |
| 6 | z3 4.8.12 | Keep, widen | Also run the recheck on it, and record which false witnesses still report `refuted` |

**Rule breaks in this review.** The table cells and the citation list use fragments. Two sentences in gap 10 and in the rank-3 text state a theorem with its conditions, and I kept each condition. No other rule was broken knowingly.

## Open questions for the language-team

1. Specify the recheck when a failed constraint also holds another uninterpreted function, such as `strLen` or `Map_select`. A `sat` then gives a model for that function too. State if `refuted` has the same meaning as a QF-LIA UNSAFE over the same symbols today.
2. State if the fact set is normative. If it is, a change to the facts needs a stated process, including how `compiler/src/LLMLL/VerifiedCache.hs:406` treats a cached fallback. I did not check that behaviour.
