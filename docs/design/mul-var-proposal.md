---
name: mul-var-proposal
title: "MUL-VAR-1: state and prove a product of two variables, so that an image layout can have a contract"
status: "Rev 3, DRAFT 2026-11-07. Folds amendments A1 to A5 of mul-var-rev2-professor-review.md. z3 4.8.12 run recorded. Awaits a user decision. Not settled."
date: 2026-11-07
author: language-team
rows: "MUL-VAR-1 (G7, DECIDE). Depends on FQ-ARITH-FLAT-1 and FQ-NAME-COLLIDE-1 (both PLAN, unshipped). Related: CLAUSE-WELLDEF-1 (shipped v0.37.0), ABSTRACTION-VERDICT-1 (shipped v0.34.0), CDP-FQ-RACE-1 (G1, PLAN), BITWISE-WIDTH-1 (G7, PLAN), FFI-KERNEL-1 (G7, PLAN), CORE-SYNTAX-MSG-1 (G3, PLAN), LEAN-GA (parking lot). Proposes two rows, not filed: DIV-VAR-1, MUL-SLACK-1."
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# MUL-VAR-1: a product of two variables in a contract

**Status: Rev 3, DRAFT 2026-11-07.** The user has not settled this record. The compiler was not changed. No roadmap row moved.

**How to read the numbers.** A number with no label comes from a run of `rev3.py` on this revision, on z3 4.15.4 and liquid-fixpoint 0.9.6.3.7. A number labelled "Rev 2 prototype", "review" or "Rev 1" is carried from that source and was not rerun. **Every VC here is built by a script. Nothing with a product went through `llmll verify`.** No emitter exists, so the tables show what the design does on hand-built VCs. CPU seconds count `fixpoint` with its z3 child, at a load average of 5 to 9, so read them as upper bounds. W22 cost 13.5, 13.7 and 18.0 CPU s in three places in one run, which shows the noise. **A number labelled z3 4.8.12 comes from CI run 42410952361 of this script** (see "z3 4.8.12"). That run covers the same script-built VCs and no `llmll verify`.

**The script.** `rev3.py` is one file with no imports beyond the Python standard library, no arguments and no local paths. It is in the session scratchpad folder `mulvar`, and it is not committed. Both runs in this record used the file with SHA-256 `7c0e03d0cd7a7191c889b5818dff26bc6bac87d7a660459f1087dfd45723ad50`. That file has one defect, which voids one output row: see "The void row". The corrected file has SHA-256 `14e9441d20f55f4025ae33eb5029114e0ef1fb5ac59a90efa33b884c6b4cda12`. The record copies each number that it uses, because the script and its output are temporary files. The first implementation step must repeat the tables through `llmll verify`.

## Restatement

An image library states sizes and offsets as products: `w*h*channels`, `y*stride + x`. LLMLL cannot prove a product of two variables today, so no contract can say that a pixel offset is inside its buffer. This record chooses how `verify` handles `(* a b)` when neither operand is a constant, and how it reports a false claim that holds one.

## Recommendation

Three parts ship together in one release, after two rows that ship first:

1. **Normal form.** A product becomes a polynomial over atoms. A monomial is a sorted multiset of atoms, printed as one free integer symbol. Commutativity, associativity and distribution then hold by construction.
2. **Fixed fact set.** The emitter adds ground theorems of integer multiplication to each constraint that holds a product. The set is part of the language surface. It does not change when an author reorders conjuncts, swaps the sides of an equation, or renames a variable.
3. **Native recheck.** On UNSAFE, the compiler runs z3 on the same constraint with `*` interpreted. A `sat` whose model passes an exact evaluation restores `refuted`. Any other answer gives the fallback outcome. A native `unsat` never gives `verified`.

**Rows that ship first.** `FQ-ARITH-FLAT-1` prints sums flat, and every cap here is measured on that printing. `FQ-NAME-COLLIDE-1` makes atom keys injective, because an atom key here is a printed name.

| Encoding | True proved | False wrongly proved | False reported `refuted` | Can it stop a file? |
|---|---:|---:|---:|---|
| **Rev 3 B + recheck (recommended), all witnesses** | **89 of 93** | 0 of 39 | **39 of 39** | Compiler: no, the limits stop it first. Solver: not on any witness; the largest cost is in measurement 4 |
| Rev 3 B + recheck, the 53 and 19 of Rev 2 | 50 of 53 | 0 of 19 | 19 of 19 | As above |
| Rev 2 B + recheck (Rev 2 prototype, nested printing) | 48 of 53 | 0 of 19 | 19 of 19 | Yes: 27 monomials gave no result in 280 CPU s (Rev 2 prototype, CI run) |
| A, native `*` as the proof engine | 92 of 93 | 0 | not measured as a design | Yes (W23), or a false UNSAFE under a timeout |

Row A counts the native `unsat` results of the recheck query on this witness set.

**Blocking finding 1 of the Rev 1 review is now resolved for byte buffers on this witness set, on script-built VCs, on z3 4.15.4 and z3 4.8.12.** No VC here came from the emitter, so the real emitter's shape is NOT RUN. The validator reads real `get-value` output: arrays as finite maps, `Str` as tokens. All 39 false witnesses give `sat` with a validated model, and 12 of them hold an array or a `Str` (N4, N5, KF4, BF1 to BF9). No true witness gives `sat`. Measurement 7 shows the raw output. **Finding 2 stays resolved:** P1 to P7 prove with no hand-written equation.

Four true witnesses do not prove: W14, W23, W25 and Y5. Each is listed with its cause in "What B does not prove". Q8, Q9 and K1 now prove.

## Decisions for the user

Each decision shows the professor's position as an input. The user decides. **No decision changes direction in this revision.** Two change in detail, and the design holds one change the user should look at: see "A design change beyond the amendments".

**1. Encoding.** *Professor:* B for proofs, native z3 for `sat` only. *Recommendation:* agree. A `verified` must not depend on the z3 nonlinear engine or its version. The cost is real but smaller than in Rev 2: A proves W14, W25 and Y5, and B does not. *Alternative that the user may prefer:* accept a native `unsat` as `verified`. That gives 92 of 93 at low cost, and it brings all the version dependence back. It is not recommended.

**2. Refutation.** *Professor:* restore `refuted` in the same release. *Recommendation:* agree. 39 of 39 false witnesses report `refuted` on script-built VCs, on z3 4.15.4 and z3 4.8.12. A separate row would ship a release in which an off-by-one offset exits 0.

**3. `def` bodies.** *Professor:* admit, with a message condition. *Recommendation:* agree. "Messages" gives the text.

**4. Disclosure.** *Professor:* one family C ground-fact family, no new `assumed_facts` kind, no increase of `trust_report_version`. *Recommendation:* agree on the family. The family is named `product-facts`. `ground_fact_families` is an array of free strings (`docs/llmll-trust-report.schema.json`). **Changed in detail:** the verify schema does change. Rev 2 said that JSON does not change, and that statement was incorrect. See "The verify schema".

**5. Variable divisors.** *Professor:* a separate `DIV-VAR-1`. *Recommendation:* agree. **Changed in detail:** `mod` with a positive ground divisor is now an atom, and `(/ e k)` with a positive ground `k` stays one. A variable divisor stays refused. The refusal scan runs on the written term, before expansion, so a cancellation cannot delete a refused term (measurement 6).

**6. z3 4.8.12.** *Professor:* the gate passes on the Rev 2 report, with corrections. *Recommendation:* the gate applies to Rev 3 too, because the fact set changed. **The Rev 3 run passes at the design limit of 2000000.** All 132 witnesses get the same verdict on z3 4.8.12 as on z3 4.15.4, with no true `sat` and 39 of 39 models validated. It covers script-built VCs, not `llmll verify`, and a real rlimit of 200000 on Rev 3 and z3 4.8.12 is NOT RUN. Soundness does not depend on the result: a weaker z3 can only lose a refutation or a proof.

### A design change beyond the amendments

A monomial was a nested application of one symbol, `mul##nl`, in Rev 2. In Rev 3 each monomial is **one free integer symbol**, `mul##k`, with no application. A2 asks for "the review's repair or a better one", and this is the part that goes beyond the review.

The reason is measured. A nested application keeps a congruence that aligns arguments by position, and sorted positions depend on names. Over the pair cap, F10 is omitted, so that congruence is the only congruence left. There the verdict depends on names.

| Printing, 72 pairs, F10 omitted | Goal `a*b = c*d` | The same constraint, with its names permuted so that the goal reads `a*c = d*b` |
|---|---|---|
| Nested `mul##nl` | `sat`, UNSAFE | **`unsat`, SAFE** |
| One free symbol | `sat`, UNSAFE | `sat`, UNSAFE |

The free symbol loses no witness: the two printings give the same verdict on every witness in the table. The two table runs were made on an earlier state of this script, and every z3 and `fixpoint` answer matched on all 132 witnesses. The cost was 48.0 CPU s for the free symbol and 71.1 for the nested form, measured once with the nested run sharing the machine, so that comparison is weak. The cost of this choice is that an equality the facts do not state cannot be derived through congruence, over the cap. That gives a fallback, and it reads no name.

## Change log, Rev 2 to Rev 3

| Finding in the Rev 2 review | Change |
|---|---|
| **A1 (G2), blocks:** the stall was misdiagnosed and the cap had the wrong shape | "Printing" states that sums print flat and that a comparison in a fact has no parens. "Limits" removes the 16-monomial cap and the written-pair cap, on measurement 4. The cause is read from the source, in "Printing". `FQ-ARITH-FLAT-1` ships first |
| **A2 (G1), blocks:** the verdict changes with conjunct order and names | "Rules" replaces `σ`. "Invariance" states the property. F10 and F11 are new. Measurement 3 runs both solvers. The review's repair kept `σ` under the new facts, so its fact set still read order; this one does not |
| **A3 (G3), blocks:** `σ` has no limit | "Limits" bounds degree and size after resolution. Measurement 5 shows that the chains stop with no solver call |
| **A4 (G4), blocks:** atoms and validator miss emitted terms | "Normal form" adds `FQIte` and `mod`. "Refusal scan" runs first. "What `sat` is validated against" reads arrays and `Str`. Measurement 7 uses real `get-value` output. `byte-range` stays in the query, and a test holds it |
| **A5 (G6, G7, G8):** the surface that moves | "The verify schema", "Four callers", "The recheck's translator", "Messages". **The review named three callers, and `compiler/src/LLMLL/PatchApply.hs` is a fourth** |
| G9: the 64-pair cap is not local | "Limits" states it, measurement 4 reruns the table on flat printing, and the spec text discloses it |
| Q2: "a validated model is a real one" is incorrect | Withdrawn. "What `refuted` means" says VC counterexample, and the message says so |
| Q2: truth "does not depend on z3" is too strong | Corrected in "What `sat` is validated against": it holds for each term that the checker evaluates. A free function's value is read from z3 and checked for consistency only |
| Q2: stop-at-first loses a qualification | "The budget" stops per partition |
| Q5: two omissions in the candidacy fix | "The mark" adds a branch for a function already in fallback, and a text for `welldefWarning` |
| Q6: the message text varies by z3 version | "Messages" says only "no counterexample found" |
| Q6: print order differs by hash seed | "Printing" fixes the order. Measurement 3 holds it |
| Q6: "at most 0.050 s" did not match its source | Dropped. This record uses its own run, and the Rev 2 prototype numbers are labelled |
| Q1: cancellation can delete a refused term | "Refusal scan". Measurement 6 runs what the review could not express |
| Q7: K1 is a real gap | F11 proves it. Y5 stays in the W14 class |
| G5: name collision | `FQ-NAME-COLLIDE-1` is a dependency in "Ship order" |

Withdrawn from Rev 2: the equation map `σ`; the 16-monomial and written-pair caps; "a monomial above degree 6 gets no splits"; "JSON does not change"; "`refuted` keeps a real model"; the three-way message `<unsat | limit | abstained>`; `mul##nl`.

**A convergence.** The team's "Printing" measurement in Rev 2 (34.7 against 65.9 CPU s) and the review's depth table both come from one cause, which the source now shows. The professor reached it by measurement, and this revision by reading.

## Context located

1. `docs/design/mul-var-rev2-professor-review.md`: the findings that this revision answers. Its claims were checked. One correction is above (the fourth caller).
2. `compiler/src/LLMLL/FixpointIR.hs`: `FQBinArith` prints nested, `FQAnd` prints flat, `predSymbols` walks every form, `sanitizeFQId` maps a name to `[A-Za-z0-9_]`.
3. `compiler/src/LLMLL/FixpointEmit.hs`: `abstracted` and `postUnassumed` read call binders only; `exprToPredWD` and `bodyToPredM` refuse `*`; `arrayTheorySyms`, `Map_store` and `strLen` set the array and string encoding.
4. `compiler/src/LLMLL/AbstractionVerdict.hs`, `applyAbstractionVerdict`, `reclassifyEmit`, `abstractionRepair`, `welldefWarning`: the verdict rule and its texts.
5. `compiler/app/Main.hs`, `doVerify`, `checkCDPCandidate`, the diverge classifier, `checkWeaknessCandidate`; `compiler/src/LLMLL/PatchApply.hs`, `notProvedMessage`: the callers.
6. `docs/llmll-verify.schema.json`: the pattern on `abstraction_fallback`, and `verify_json_version` as a constant.
7. `compiler/src/LLMLL/Feasibility.hs`, `fqPredToSMT`: the refine gate's translator, which fails open on a function term.
8. `compiler/src/LLMLL/Lexer.hs`, `pWord`: a source name cannot hold `#`. Carried from Rev 2.
9. `compiler/src/LLMLL/VerifiedCache.hs`, `compiler/src/LLMLL/ProofArtifact.hs`: `refuted` is not persisted; replay reruns the stored VC. Carried from Rev 2.
10. `compiler/src/LLMLL/Diagnostic.hs`, `mkCoreMembershipViolation`: the caller-side text.
11. `LLMLL.md:13-14`, §5.3.3 and §13.12: `Σ_auto`, the "Outside" clause, the ground-fact families.
12. `examples/y4m/raster.llmll`, `examples/netpbm-swarm/kernel.llmll`: the source of the Y and K witnesses.
13. liquid-fixpoint source at tag `v0.9.6.3.7`, module `Language.Fixpoint.Parse`, `appliableExprP` and `tupleP`: read for the printing cause. It is outside this tree.

**Spec drift, carried and still open.** `LLMLL.md` §5.3.3 says nonlinear terms "route to `?proof-required`"; Rev 1 measured a `W-BODY-FALLBACK` with no hole on 0.37.0. The spec should move. liquid-fixpoint reads a z3 `unknown` as UNSAFE under `--smtTimeout`; this design does not pass that flag.

**Comment drift, carried.** The comment on `sanitizeFQId` says that liquid-fixpoint accepts only `[A-Za-z0-9_]` in a name. The review's `collide` witness also shows that its "fails closed" comment is incorrect: `FQ-NAME-COLLIDE-1` owns that.

**Row drift, new.** The `FQ-ARITH-FLAT-1` row calls the parser an inference and says that the source was not read. This revision read `Parse.hs` at 0.9.6.3.7, and the engineer's plan is reported to have read it too (that plan was not read here). The documentation-lead may update that sentence when it next touches the row.

## What happens today (Rev 1, llmll 0.37.0; not rerun)

| Input | Result |
|---|---|
| `def area`, body and post `(* w h)` | `check` exit 1: "body contains non-core syntax" |
| `def-shell area`, the same | exit 0, post not proved: `contract-post-outside-fragment`, `Refused by: nonlinear:*` |
| `def-shell off`, post `(< result (* w h))`, body `(+ (* y w) x)` | exit 0, post not proved, `Refused by: nonlinear:*` |
| `def-shell off`, `(= n (* w h))` in the `pre` | exit 0, post not proved: `contract-pre-outside-fragment` |
| `(* 3 w)`, `(+ (* 8 y) x)` | verified, as `SIGMA-CONST-ARITH-1` specifies |

## Measurements

**Witness set.** 93 true and 39 false claims. W, P, R, Q, M and N are the 72 of Rev 2, unchanged. Y, K, YF, KF and PF are the professor's battery; YF2 counts as true, as the review corrected it, and PF and PF2 are the review's plane-copy false witnesses. O1, O2 and O3 are the review's order witnesses. **A1 to A7, AF1 to AF3, B1 to B4 and BF1 to BF9 are new in this revision**, for `FQIte`, `mod`, arrays and `Str`. A witness with `bytes` or `string` carries the ground facts that the emitter adds, as seen in the review's `bytes.fq`.

**1. The witness table, under flat printing, through z3 and `fixpoint`.** This is the run that the review did not do. z3 and `fixpoint` agree on every witness. "Verdict" applies "Verdict and recheck".

| Group | Source | True proved | False `refuted` | Not as expected |
|---|---|---:|---:|---|
| W (27) | Rev 1 | 24 of 27 | | **W14, W23, W25** |
| P, R (11) | Rev 1 review, Rev 1 | 11 of 11 | | none |
| Q (15) | Rev 2 | 15 of 15 | | none |
| M, N (19) | Rev 1, Rev 2 | | 19 of 19 | none |
| **Y4M: Y1 to Y12, YF2 (13)** | review, `examples/y4m/raster.llmll` | **12 of 13** | | **Y5** |
| **netpbm: K1 to K13 (13)** | review, `examples/netpbm-swarm/kernel.llmll` | **13 of 13** | | none |
| YF3, YF4, KF1 to KF4, PF, PF2 (8) | review | | 8 of 8 | none |
| O1 to O3 (3) | review | 3 of 3 | | none |
| A1 to A7 (7), AF1 to AF3 (3) | new | 7 of 7 | 3 of 3 | none |
| B1 to B4 (4), BF1 to BF9 (9) | new | 4 of 4 | 9 of 9 | none |
| **All (132)** | | **89 of 93** | **39 of 39** | **W14, W23, W25, Y5** |

No false witness proved. No true witness gave a native `sat`. Against Rev 2 on its 72 witnesses, Q8 and Q9 move from fail to proved, and no witness moves from proved to fail. Against the review's battery, K1 moves to proved.

| Witness | Rev 2 facts, CPU s (Rev 2 prototype, loaded) | Rev 3 facts | Rev 3 CPU s |
|---|---:|---:|---:|
| W3 crux | 32, 0.10 | 34 | 0.039 |
| P3 offset, buffer `h*(w*ch)` | 1241, 3.96 | 1383 | 0.859 |
| W20 `3*w*h ≤ 2^63−1` | 12, 0.06 | 18 | 0.028 |
| W22 monotone, degree 4 | 19114, 59.0 | 21432 | 13.5 |
| Q13 pad variable | not listed | 2146 | 1.47 |
| PF plane copy | not run | 2791 | 2.63 |
| K8 last channel, `bytesLen` | review: T 13, 2.66 | 1384 | 0.77 |

Over all witnesses, the median is 0.044 CPU s and the total is 40.3. The largest is W22. On Rev 2's 72 witnesses the facts total 42008, against 37248 in Rev 2, an increase of 13%. F4 and F5 are most of the set: 46897 of 58487 together.

**2. The recheck.** Native z3 on the normal-form constraint with its ground facts, and no product facts.

| Claim | Result | Max wall s | Max `rlimit-count` |
|---|---|---:|---:|
| False (39) | `sat`, model validated, 39 of 39 | 0.036, over three runs at 2000000 | 15070 |
| True (93) | `unsat` on 92; `unknown` on W23; **`sat` on none** | | 186173 on `unsat` |

W23 reaches `unknown` at the limit, in 0.72 s and 0.55 s. The first of those comes from the output row labelled 200000, which really ran at 2000000: see "The void row". M1 with 32 unrelated products in scope gives `sat`, validated, at rlimit 8302. Two controls hold from Rev 2 in new form: see measurement 7.

**3. Invariance.** The property is in "Invariance". The test compares fact sets as sets, with no names in the comparison except through the renaming.

| Test | Result |
|---|---|
| Fact set under conjunct reversal, shuffle, equation flip, rename, and all combined; 8 variants of each of 132 witnesses | 1056 comparisons, **0 differ** |
| Control: one rule per atom in conjunct order, which is Rev 2's reading, on the same test | differs on 9 variants, so the test can fail |
| Fact block text under shuffle and flip | 132 of 132 byte-identical |
| Whole `.fq` text of every witness under six Python hash seeds | one digest |

Both solvers on the named witnesses, with 9 forms of each: as written, reversed, two shuffles, flipped, two renamed, two combined. The review ran z3 only.

| Witness | z3 with facts | `fixpoint` | Rev 2 reading (review, z3 only) |
|---|---|---|---|
| O1 | `unsat` on 9 of 9 | SAFE on 9 of 9 | as written not proved; reversed proved |
| O2 | `unsat` on 9 of 9 | SAFE on 9 of 9 | as written not proved; reversed proved |
| O3 | `unsat` on 9 of 9 | SAFE on 9 of 9 | proved |
| Q8 | `unsat` on 9 of 9 | SAFE on 9 of 9 | as written not proved; renamings proved |
| Q9 | `unsat` on 9 of 9 | SAFE on 9 of 9 | as written not proved; renamings proved |
| K1 | `unsat` on 9 of 9 | SAFE on 9 of 9 | not proved |

Every witness, one combined variant, through both solvers: 132 run, **no verdict changed, and the solvers never disagreed.**

**A limit of the property.** An equation whose terms an author moved, so that neither side is one atom, gives no rule. `(= (- x y) 1)` with `(= (- x (* 2 z)) 0)` and the O1 goal gives 46 facts, `sat` with those facts, UNSAFE, and a native `unsat`, so fallback. O1 as written gives 130 facts and SAFE. The property does not cover this. The review did not ask for it, and "Risks" names the cost.

**4. Scale, under flat printing.** This rebuilds the caps.

*No product, one linear goal.*

| Terms | Nested | Flat |
|---:|---|---|
| 12 | 0.143 | 0.023 |
| 16 | 2.148 | 0.025 |
| 20 | 33.197 | 0.026 |
| 80 | not run | 0.034 |

| Redundant parens round one variable | Depth 12 | 14 | 16 | 18 |
|---|---:|---:|---:|---:|
| CPU s | 0.17 | 0.61 | 2.43 | 9.75 |

*The same generator, nested against flat.*

| Input | Facts | Nested, CPU s | Flat, CPU s |
|---|---:|---|---|
| W22 | 21432 | 33.7 | 13.7 |
| P3 | 1383 | 2.09 | 0.87 |
| Crux, K=20 | 3894 | 4.87 | 2.10 |
| 3 × 3 × 3 sums | 990 | no result in 70 s | 0.54 |
| Kernel of 25 products | 5625 | no result in 70 s | 4.44 |

*A pair cap: the crux with K more product goals, and monotone by degree.*

| Input | Pairs `T` | Facts | `.fq` bytes | Result | CPU s | z3 alone, wall s |
|---|---:|---:|---:|---|---:|---:|
| Crux K=2 | 4 | 132 | 7351 | SAFE | 0.116 | 0.019 |
| K=5 | 7 | 399 | 22546 | SAFE | 0.251 | 0.028 |
| K=10 | 12 | 1164 | 66955 | SAFE | 0.682 | 0.049 |
| K=20 | 22 | 3894 | 234090 | SAFE | 2.311 | 0.155 |
| K=40 | 42 | 14154 | 872860 | SAFE | 8.347 | 0.558 |
| K=62 | 64 | 32832 | 2044499 | SAFE | 20.329 | 1.7 |
| K=63 | 65, over the cap | 585 | 29973 | UNSAFE | 0.331 | 0.073 |
| K=100 | 102, over the cap | 918 | 47337 | UNSAFE | 0.521 | 0.066 |
| Monotone, degree 3 | 12 | 1200 | 83569 | SAFE | 0.946 | 0.051 |
| Degree 4 | 50 | 21432 | 1711158 | SAFE | 18.035 | 0.651 |
| Degree 5 | 180, over the cap | 1620 | 70831 | UNSAFE | 0.733 | 0.047 |
| Degree 6 | 602, over the cap | 5418 | 241886 | UNSAFE | 2.482 | not run |
| Degree 7 | | | | refused, degree 7 over 6 | no solver | no solver |

*Long sums and kernels. The written-pair column shows why that cap is removed.*

| Input | Monomials | `T` | Facts | Result | CPU s, no written cap | CPU s, written cap 4 |
|---|---:|---:|---:|---|---:|---:|
| 2 × 2 | 4 | 5 | 217 | SAFE | 0.179 | not run |
| 3 × 3 | 9 | 10 | 864 | SAFE | 0.675 | 0.551 |
| 4 × 4 | 16 | 17 | 2505 | SAFE | 2.119 | 1.608 |
| 5 × 5 | 25 | 26 | 5884 | SAFE | 4.958 | 3.985 |
| 8 × 8 | 64 | 65, over the cap | 585 | SAFE | 0.352 | not run |
| 2 × 2 × 2 | 8 | 38 | 12396 | SAFE | 10.034 | not run |
| 3 × 3 × 2 | 18 | 77, over the cap | 693 | SAFE | 0.33 | not run |
| 3 × 3 × 3 | 27 | 110, over the cap | 990 | SAFE | 0.443 | 0.412 |
| 4 × 4 × 4 | 64 | 242, over the cap | 2178 | SAFE | 1.06 | 0.858 |
| 5 × 5 × 5 | 125 | 452, over the cap | 4068 | SAFE | 1.965 | 1.666 |
| 7 × 7 × 7 | 343 | | | refused, expansion over 256 | no solver | |
| Kernel, 9 products | 9 | 9 | 729 | SAFE | 0.518 | |
| 25 products | 25 | 25 | 5625 | SAFE | 3.946 | |
| 49 products | 49 | 49 | 21609 | SAFE | 13.092 | |
| 81 products | 81 | 81, over the cap | 729 | SAFE | 0.348 | |
| 121 products | 121 | 121, over the cap | 1089 | SAFE | 0.487 | |

Rev 2's 3 × 3 × 3 input gave no result in 200 s (Rev 2 prototype) and 280 CPU s (Rev 2 prototype, CI). It now costs 0.44 CPU s. A kernel of 25 separate products costs 3.95, where nested printing gave no result in 70 s wall (review).

*The pair cap is not local (G9).* The cap reads the whole constraint, so an unrelated product can remove a proof of the crux W3. This is the review's table, rerun under flat printing.

| Unrelated products | Crux W3 | `T` | CPU s |
|---|---|---:|---:|
| 10 of degree 2 | SAFE | 12 | 0.863 |
| 62 of degree 2 | SAFE | 64 | 25.035 |
| 63 of degree 2 | **UNSAFE** | 65 | 0.238 |
| 4 of degree 3 | SAFE | 26 | 3.773 |
| 10 of degree 3 | SAFE | 62 | 23.424 |
| 11 of degree 3 | **UNSAFE** | 68 | 0.249 |
| 2 of degree 4 | SAFE | 52 | 15.888 |
| 3 of degree 4 | **UNSAFE** | 77 | 0.352 |

**5. The limits stop the chain, before any solver call (A3).** A chain `x₁ = x₀*x₀ + 1`, `x₂ = x₁*x₁ + 1`, and so on, with goal `x_n*x_n ≥ 0`. A second chain `x₁ = x₀*y + z` is the review's other shape. CPU is the Python generator.

| Chain length `n` | Square chain | CPU s | Mixed chain | CPU s |
|---:|---|---:|---|---:|
| 1 | ok, T 5, 103 facts | 0.005 | ok, T 18, 1979 facts | 0.071 |
| 2 | refused, degree over 6 | 0.000 | ok, T 64, 30517 facts | 1.160 |
| 3 | refused | 0.000 | refused, degree over 6 | 0.000 |
| 4 | refused | 0.000 | refused | 0.000 |
| 6 | refused | 0.000 | refused | 0.000 |
| 8 | refused | 0.000 | refused | 0.000 |
| 10 | refused | 0.000 | refused | 0.000 |
| 12 | refused | 0.000 | refused | 0.001 |
| 20 | refused | 0.001 | refused | 0.002 |
| 40 | refused | 0.001 | refused | 0.002 |
| 100 | refused | 0.003 | refused | 0.004 |

**Solver calls during this measurement: 0 z3, 0 `fixpoint`.** The review saw the generator give no result in 40 s at length 10. The fact count is no longer non-monotone, because a chain over the limit refuses whole and does not lose its splits.

**6. Refusal scan, before cancellation (A4).** The review could not express these. Solver calls: 0.

| Input | Result |
|---|---|
| `(* 0 (/ x y))` | refused, `nonlinear:/` |
| `(- (/ x y) (/ x y))` | refused, `nonlinear:/` |
| `(* 0 (mod x y))` | refused, `nonlinear:mod` |
| `(/ x 0)` | refused, `nonlinear:/` |
| `(/ x -2)` | refused, `nonlinear:/` |
| `(= w (* 0 (/ x y)))` in a hypothesis | refused, `nonlinear:/` |
| Control: `(* 0 (/ x 2))` | accepted, cancels, 0 facts |
| Control: `(* (mod x (+ 1 2)) w)`, a ground divisor | accepted, 10 facts |

**7. The validator on real models (A4).** This is real `get-value` output from z3 4.15.4, as the run printed it. "z3 4.8.12" lists the models that differ on that version. Each was read and evaluated by the checker, by two evaluators: one over the normal form, one over the source term.

```
PF: (c 4) (ch 1) (chroma 1) (cw 1) (dst 1) (frame 3) (h 1) (luma 1) (pad 2) (rowb 4) (src 6) (st 6) (total 6) (v 2) (w 1) (x 0) (y 1)
PF2: (c 1) (ch 1) (chroma 1) (cw 1) (dst 0) (frame 3) (h 1) (luma 1) (pad 0) (rowb 1) (src 0) (st 1) (total 1) (v 2) (w 1) (x 0) (y 0)
N5: (b ((as const (Array Int Int)) 0)) (h 1) (v 0) (w 0) (x 0) (y 0) ((bytesLen b) 0)
KF4: (b ((as const (Array Int Int)) 8)) (ch 2) (h 1) (k 2) (w 1) (x 0) (y 0) ((bytesLen b) 2)
BF1: (b (store ((as const (Array Int Int)) 5) 0 9)) (c (store ((as const (Array Int Int)) 5) 0 7)) (h 1) (w 0) (x 0) (y 0) ((bytesLen b) 0) ((bytesLen c) 0)
BF3: (b (store ((as const (Array Int Int)) 2) 0 3)) (c (store ((as const (Array Int Int)) 2) 0 7)) (v 7) (w 1) (x 0) (y 0) ((bytesLen b) 0) ((bytesLen c) 0)
BF5: (hs (store ((as const (Array Int Int)) 2) 0 4)) (hs2 (store (store ((as const (Array Int Int)) 2) 0 4) 3 1)) (k 0) (v 0) (vl ((as const (Array Int Int)) 0)) (vl2 ((as const (Array Int Int)) 0)) (w 3) (y 1)
BF6: (h 0) (s Str!val!0) (t Str!val!0) (w 1) ((strLen s) 0) ((strLen t) 0)
BF7: (h 1) (s Str!val!0) (t Str!val!1) (w 1) ((strLen s) 1) ((strLen t) 0)
BF8: (j (- 1)) (k 1) (mv (store ((as const (Array Int Str)) Str!val!0) (- 1) Str!val!1)) (s Str!val!0) (t Str!val!1) ((strLen s) 0) ((strLen t) 0)
BF9: (b ((as const (Array Int Int)) 0)) (c 1) (h 1) (pad 0) (src 2) (st 2) (v 0) (w 2) (x 0) (y 1) ((bytesLen b) 2)
```

- **Array forms seen on 4.15.4 and 4.8.12:** `((as const (Array Int Int)) d)` and nested `store`. The token form is `Str!val!k` on both. The reader also handles `let`, `lambda` and `(_ as-array k)`, from a `get-model` definition. **None of the 11 models that each run prints holds those three. The runs do not log the other 28 models, so those paths are not shown to have run.** An unreadable value gives the mark back.
- **Tamper controls, all false witnesses.** One integer changed: 171 rejected, 34 still a counterexample. One array changed at every written index and the default: 15 tampered, 13 rejected. One `Str` token replaced: 7 tampered, 4 rejected. One function result changed: 17 tampered, 11 rejected. A tampered model that passes still satisfies the hypotheses and falsifies the goal under exact evaluation, so it is also a counterexample.
- **Function consistency.** BF6 with one `strLen` result changed gives `MODEL FAILS, function consistency`.
- **`byte-range` stays in the query (test).** B1 is `v = select b i`, goal `v*v ≤ 65025`. With `byte-range`: native `unsat`. Without it: `sat`, validated, with `b` the constant array of -256 and `v = -256`. **That is a false `refuted`, and the validator cannot catch it, because the VC without the family really has that model.** So the family must stay, and a test holds it.
- **`FQIte` and `mod` as atoms.** A1 to A7 prove. AF1 to AF3 refute, with validated models.

**8. Facts are true, and the generator is correct.**

- Each schema: native z3 gives `unsat` for the negation on `Int`, including F9, F10, F11 and the `mod` bound. F5 gives `sat` on `Real`, as before. Controls give `sat`: F5 without `b ≥ 0`, F7b without `b ≥ 0`, F11 with a wrong `k`.
- Each generated instance: 58487 facts across all witnesses, evaluated on exact values up to `2^63`, with arrays and `Str` as finite maps and tokens, and free functions as pseudo-random functions. 742801 evaluations had a true premise. **0 failures.**
- Normal form against source: 105240 evaluations, **0 differences.**
- Hypotheses plus facts are satisfiable for every witness, so the facts add no contradiction on this set.

**9. Each mark site.** True claims that B cannot prove, one product position per row.

| Site | `fixpoint` | Marked | Recheck | Verdict | With no mark |
|---|---|---|---|---|---|
| S1 environment binder | UNSAFE | yes | `unknown` | fallback | false outcome |
| S2 `lhs` | UNSAFE | yes | `unknown` | fallback | false outcome |
| S3 `rhs` | UNSAFE | yes | `unknown` | fallback | false outcome |
| S4 callee post, after substitution | UNSAFE | yes | `unknown` | fallback | false outcome |
| S5 a definedness assumption | UNSAFE | yes | `unknown` | fallback | false outcome |
| S6 definedness goal | UNSAFE | yes | `unsat` | fallback | false outcome |
| S7 environment binder, W25 shape | UNSAFE | yes | `unsat` | fallback | false outcome |
| S8 no product, false claim (control) | UNSAFE | no | `sat` | `refuted`, linear path | `refuted` |

"False outcome" means that the script's verdict rule, with no mark, gives a complete id on a true claim. At S6 that id is a definedness id, so the outcome would be a false `ill-defined`, and the script prints it as a complete id. The other rows would give a false `refuted`.

**10. Names.** With binder `mul##0` in scope, a parameter named `mul`, `mul_nl`, `m_0` or `mul_0` gives UNSAFE in each case, with no parse or binder error. A source name cannot hold `#`.

**11. Carried, not rerun.** Option A on two real files, seeds, and `--leanstral-mock` (Rev 1). Of 2002 `.llmll` files on disk, 6 files hold 9 functions refused for `nonlinear:*` (Rev 1). The 186173 slack schema (review): see `MUL-SLACK-1`. The review's released-binary results, in "Printing" and "What `refuted` means".

### z3 4.8.12

**Rev 3, measured.** From `https://github.com/machunter/llmll/actions/runs/42410952361`, conclusion `success`, head `d446321a`, file header z3 4.8.12 and fixpoint 0.9.6.3.7, 701 s wall, load about 1. The script at that head has SHA-256 `7c0e03d0cd7a7191c889b5818dff26bc6bac87d7a660459f1087dfd45723ad50`, which is the local run's file. **It covers script-built VCs only. Nothing with a product went through `llmll verify`.**

| Measure | z3 4.8.12, Rev 3 | z3 4.15.4, Rev 3 |
|---|---:|---:|
| True proved (93) | 89; misses W14, W23, W25, Y5 | 89; the same misses |
| False wrongly proved (39) | 0 | 0 |
| False `refuted`, model validated (39) | 39, 39 | 39, 39 |
| True `sat` | none | none |
| z3 and `fixpoint` disagree | none | none |
| Recheck on W14, W25, Y5 | `unsat` | `unsat` |
| Recheck on W23 | `unknown`, 2.23 s, count 2000028; no `timeout` | `unknown`, 0.55 to 0.72 s, count 2000028; no `timeout` |
| Max false `rlimit-count` | **14703** (N2) | **15070** (N2) |
| Max true `unsat` `rlimit-count` | **1368835** (W22) | **186173** (W22) |
| True `unsat` with a count above 200000 | **29** | **0** |
| Count on W14, W25, Y5 | 443397, 151215, 359075 | 1348, 46433, 3571 |
| Max recheck wall on a false witness, s | 0.029 | 0.036 |
| Max recheck wall on a true `unsat`, s | 0.724 (Y6) | not listed |
| M1 with 0, 8, 32 unrelated products, count, all validated | 2728, 3681, 7208 | 3036, 4176, 8302 |
| Fact set under the invariance test | 1056 comparisons, 0 differ; control differs on 9 | the same |
| Fact blocks byte-identical; `.fq` digests under six seeds | 132 of 132; one digest, `0a94314ed7778754` | the same |
| O1, O2, O3, Q8, Q9, K1, 9 forms each | `unsat` and SAFE on all | the same |
| All 132, one combined variant | no verdict change, no disagreement | the same |
| Tamper, integers | **163 rejected, 42 still a counterexample** | **171 rejected, 34 still a counterexample** |
| Tamper, arrays; tokens; function results, rejected | 13 of 15; 4 of 7; 11 of 17 | the same |
| Function consistency control | `MODEL FAILS` | the same |
| B1 with `byte-range`; without | `unsat`; `sat`, validated, `v = -953` | `unsat`; `sat`, validated, `v = -256` |
| Generated facts, failures; true-premise evaluations | 58487, 0; **749448** | 58487, 0; **742801** |
| Normal form evaluations, differences | 105240, 0 | the same |
| Total CPU s; median; W22 | 40.3; 0.0505; 12.7 | 40.3; 0.044; 13.5 |
| Python; load; wall s; solver calls | 3.11.18; about 1; 701; 1125 z3, 394 `fixpoint` | 3.9.6; 5 to 9; 730; the same calls |

**Every difference between the two runs.**

1. **Verdicts: none.** Over all 132 witnesses, the z3 answer, `fixpoint` answer, `T`, facts, families, closure, degree, cap state, recheck answer, model state and verdict are identical.
2. **Recheck wording: none.** W23 reads `unknown` on both, and no recheck reads `timeout`. Each mark site in measurement 9 reads the same word on both.
3. **Scale, chains, refusal, schemas, names: no result differs.** `T`, facts, bytes and solver answers match on each row. Only CPU and wall times move. For example, depth 18 costs 7.79 CPU s against 9.75, and a sum of 20 nested costs 28.9 against 33.2. A nested 3 × 3 × 3 sum and a nested kernel of 25 give no result in 70 s on both.
4. **`rlimit-count` differs on the recheck queries,** as the table shows. The largest true count is 7.4 times larger on 4.8.12. It stays under the design limit.
5. **Models differ on 4 of the 11 printed witnesses, and all still validate.** The other 7 print the same values. On 4.8.12:

```
PF: (c 1) (ch 1) (chroma 1) (cw 1) (dst 3) (frame 4) (h 1) (luma 2) (pad 0) (rowb 2) (src 3) (st 2) (total 2) (v 3) (w 2) (x 1) (y 1)
KF4: (b ((as const (Array Int Int)) 8)) (ch 2) (h 2) (k 2) (w 2) (x 1) (y 1) ((bytesLen b) 8)
BF1: (b (store ((as const (Array Int Int)) 4) 0 8)) (c (store ((as const (Array Int Int)) 4) 0 7)) (h 1) (w 0) (x 0) (y 0) ((bytesLen b) 0) ((bytesLen c) 0)
BF9: (b ((as const (Array Int Int)) 0)) (c 1) (h 1) (pad 1) (src 2) (st 2) (v 0) (w 1) (x 0) (y 1) ((bytesLen b) 2)
```

6. **The integer tamper split and the B1 model value differ.** Different models can give a different split. Both variants pass the check in the same way, and the conclusion on `byte-range` is unchanged.
7. **The true-premise count differs, 749448 against 742801.** The generator check makes no z3 call, and its failures are 0 on both. The Python versions also differ. The cause was not traced.

**What the run does not show.** Any path through `llmll verify`, the emitter's real array and `Str` shape, the model reader's `let`, `lambda` and `as-array` paths, and a real rlimit of 200000 on Rev 3.

### The void row

**The output row labelled `rlimit 200000` in section 10 of the script is void, in both Rev 3 runs.** `recheck` takes `rlimit=`, and the published file called `native_query(vs, vc, goal)` without passing it. So that row ran at 2000000. The evidence on 4.8.12: that row reports a max true `unsat` of 1368835 and W23 `unknown` at 2.23 s, the same as the 2000000 row. **No result in this record rests on that row, except where it is named as a run at 2000000.**

- **Results at 2000000 stay valid,** because every other call used that default. The query text at the default does not change with the fix.
- **The fix passes `rlimit=rlimit` at that call.** Both published runs predate it.
- **The other parameters were checked.** `recheck` is the only caller of `native_query`, and section 10 is the only caller that passes `rlimit`. `ground_facts` reaches the VC, and the `byte-range` control shows its effect. `ground` and `get` keep their defaults at the one call, and no caller needs another value. `sorts` is passed wherever a witness has one. Calls without `sorts` use integer-only inputs. So no other row is affected.
- **A real 200000 on Rev 3:** one local check of the corrected file on z3 4.15.4 gives 39 of 39 `sat` and validated, and W23 `unknown` at count 200028 in 0.04 s. **On z3 4.8.12 it is NOT RUN.** There, 29 true witnesses count above 200000 at the design limit, so their answers at 200000 are not known. They cannot change a verdict unless they read `sat`.
- **The only real 200000 on z3 4.8.12** is the Rev 2 prototype row below, on a different query.

**Rev 2 prototype results, not Rev 3, kept for comparison.** From `https://github.com/machunter/llmll/actions/runs/42404692268`, head `748d0462`, conclusion `success`, file header z3 4.8.12 and fixpoint 0.9.6.3.7. These numbers are copied here because the file does not last.

| Measure | z3 4.8.12, Rev 2 prototype | z3 4.15.4, Rev 2 prototype |
|---|---:|---:|
| True proved (53) | 48; misses W14, W23, W25, Q8, Q9 | 48; the same misses |
| False proved (19) | 0 | 0 |
| False validated (19) | 19 of 19 | 19 of 19 |
| True `sat` | none | none |
| Max false `rlimit-count` | 14707 | 15074 |
| Max true `unsat` `rlimit-count` | **1368835** | **186173** |
| Generated facts, failures | 37248, 0 | 37248, 0 |
| W22, CPU s | 21.46, load under 1 | 58.96, load 80 or more |
| K=62, CPU s | 30.8, load under 1 | 85.6, load 80 or more |
| 3 × 3 × 3, nested | no result in 280 CPU s | no result in 200 s wall |

At rlimit 200000 on 4.8.12, 20 true witnesses read `unknown` and all 19 false witnesses stay `sat` (Rev 2 prototype). At 2000000, only W23 reads `unknown`, at 2.179 s (Rev 2 prototype). In the verdict table `unsat` and `unknown` give one outcome, so only `sat` decides the limit.

## Design proposal

### Surface

There is no new syntax. `(* a b)` already parses and type-checks as `int → int → int` (`compiler/src/LLMLL/TypeCheck.hs`), and no float form exists. JSON-AST does not change. A contract may now use it, and under decision 3 so may a `def` body. The verify JSON changes, in one pattern: see "The verify schema".

```lisp
(def pixel-offset [w: int h: int y: int x: int] -> int
  (pre (and (>= y 0) (and (< y h) (and (>= x 0) (< x w)))))
  (post (and (>= result 0) (< result (* w h))))
  (+ (* y w) x))
```

### Semantics

Evaluation does not change. `int` lowers to Haskell `Integer`, and `*` is total on it. So `*` has no definedness entry under `CLAUSE-WELLDEF-1`, and a partial read inside a factor keeps its own obligation. No state is added, and `mul##k` exists only in the VC, so strict immutability holds.

### Refusal scan

The scan runs first, on the term as written, before any expansion. A division or `mod` whose divisor is not a positive ground constant refuses the constraint with `nonlinear:/` or `nonlinear:mod`, as today. So `(* 0 (/ x y))` cannot verify with a term that stops at run time when `y = 0` (measurement 6). A ground divisor may be a closed term such as `(+ 1 2)`.

### Normal form

The form applies to a constraint that holds a product of two non-constant terms. Any other constraint is printed as `FQ-ARITH-FLAT-1` prints it.

1. **Atoms.** An atom is one of these:
   - a variable;
   - a function application, including `Map_select`, `Map_store`, `bytesLen` and `strLen`;
   - `(/ e k)` or `(mod e k)`, with `k` a positive ground constant;
   - an `FQIte`, which is how `abs`, `max`, `min` and an `if` term print.

   `e`, each function argument, and each branch and comparison of an `FQIte` are in normal form themselves. An atom may have sort `int`, an array sort or `Str`, but only an `int` atom can be a factor.
2. **Polynomial.** Every integer term is expanded to a sum of `c · m`, with `c` an integer and `m` a monomial, a sorted multiset of atoms. So commutativity, associativity and distribution hold by construction. `(* w (* h c))` and `(* (* w h) c)` are one term. The sort order only prints; no decision reads it.
3. **Symbol.** A monomial of degree 2 or more prints as one environment binder, `mul##k`, with refinement `true`. Facts and clauses name the binder. `k` follows the sorted order of the monomials in the constraint.
4. **After substitution.** The form applies after callee-post substitution, so a caller's terms and a callee's terms meet.
5. **A goal that reduces to a constant.** liquid-fixpoint refuses `rhs (0 = 0)` and `rhs true` with "RHS without single conjunct" (Rev 2 measurement on P1). If the goal reduces to true, the emitter sends no constraint for it and the clause is proved. If it reduces to false, the emitter sends `rhs false`, and the verdict rule applies (N9).
6. **A conjunct that reduces to true** in a larger goal is dropped.

### Printing

**This statement is normative. Sums print flat.** A sum is one chain, `a + b + c`, with no parens inside it. A comparison inside a fact has no parens of its own: `((a >= 0 && b >= 0) => m >= 0)`. `FQ-ARITH-FLAT-1` ships the flat chain as its own row, for every constraint, and this record depends on it.

**The cause, read from the source.** At tag `v0.9.6.3.7`, `appliableExprP` in `Language.Fixpoint.Parse` tries three parsers at an open paren, each under `try`: `tupleP`, then `parens exprP`, then `parens exprCastP`. A paren that is not a tuple parses its contents once for `tupleP`, which fails at the missing comma, and again for `parens exprP`. Nesting multiplies this, so the work doubles with each level. This is a reading, with no profile run. It agrees with measurement 4: depth 12 to 18 grows by 1.9 to 2.0 per level, with no logic in the file. The fact-parens halving that the review measured is the same factor at one level.

**Print order is fixed.** The emitter sorts facts by their printed text, and it numbers `mul##k` in sorted monomial order. No output order may depend on a hash table. Measurement 3 shows byte-identical fact blocks and one digest under six hash seeds, so an artifact replays the same bytes.

**The text of a product-free VC.** Rev 2 claimed it is byte-identical. That claim now means: identical to the release that carries `FQ-ARITH-FLAT-1`. That row's gate covers the change in text.

### Rules

This replaces `σ`. Regrouping through a name needs it, because `st` in `y*st` is an atom.

- **Each top-level equation gives rules.** The emitter reads every conjunct of a binder refinement and of the `lhs`, as a set. An equation is read after normal form.
- **A rule rewrites an atom.** If one side of an equation is a single atom with coefficient 1, and that atom is a variable or a function application, it gives a rule `atom → other side`. If both sides qualify, both rules exist. An atom that occurs in the other side gives no rule from that equation.
- **Every equation counts.** An atom with two definitions has two rules. No rule reads order, and none is chosen over another.
- **An equation in a disjunct or under an implication gives no rule.** F10 and F11 cover those shapes (Q9, K1).
- **A rule does not enter an `FQIte`.** It is opaque to rules, and the solver interprets it.

**Closure.** Applying a rule to a monomial substitutes every occurrence of the atom, including inside `/`, `mod` and function arguments. The closure of a constraint is every monomial reached from its monomials by any sequence of rules. It is a least fixed point, so it does not depend on the visit order.

**Settled monomials.** A monomial is **settled** if every monomial of degree 2 or more reachable from it can reach it back. So a monomial with an alias stays settled with its alias, and one with a definition is not settled. One monomial with a rule whose results all have degree 1 or less is resolved, and it is not settled. This definition reads the graph only, and no name.

### Fact set

**This set is normative. It is part of the language surface, and it decides which programs verify.** A fact is a hypothesis in the `lhs`, flat, as `FQ-FLAT-NEST-1` requires. Let `P`, the pair set of a constraint, be:

- each product `(* a b)` as written, with each factor in each of its settled forms; and
- each binary split `(A, B)` of each settled monomial, recursively.

| Fact | Statement | Instances | Certificate |
|---|---|---|---|
| F1 sign | `a ≥ 0 ∧ b ≥ 0 ⟹ ab ≥ 0`; `a ≤ 0 ∧ b ≥ 0 ⟹ ab ≤ 0` | each pair, both orders | sign |
| F2 zero, one | `a = 0 ⟹ ab = 0`; `a = 1 ⟹ ab = b` | each pair, both orders | ring |
| F3 growth | `a ≥ 1 ∧ b ≥ 0 ⟹ ab ≥ b` | each pair, both orders | `(a−1)·b ≥ 0` |
| F4 monotone | `a ≤ c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ ab ≤ cd` | ordered pairs, 4 alignments, no filter | `(c−a)·b + c·(d−b)` |
| **F5 row** | `a < c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ ab + b ≤ cd` | ordered pairs, 4 alignments, no filter | `(c−a−1)·b + c·(d−b)`, **integers only** |
| F7 literal bound | `⋀ (0 ≤ aᵢ ≤ Aᵢ) ⟹ m ≤ ∏Aᵢ` | each monomial whose atoms all have a literal upper bound, `Aᵢ ≥ 0` | F4 at constants |
| F7b literal comparand | `a ≤ K ∧ b ≥ 0 ⟹ ab ≤ K·b`; with `K ≥ 0`, `a ≥ K ∧ b ≥ 0 ⟹ ab ≥ K·b` | each pair with a single-atom side that has a literal bound | `(K−a)·b ≥ 0` |
| F8 square | `aa ≥ 0` | each pair with equal sides | square |
| F9 link | `E ⟹ m = m[x := e]`, where `E` is the equation of the rule `x → e` | each rule at each monomial of the closure, and at each `/`, `mod` or application it changes | substitution |
| **F10 congruence** | `a = c ∧ b = d ⟹ ab = cd` | ordered pairs, 4 alignments | congruence |
| **F11 literal factor** | `a = k ⟹ ab = k·b` | each pair with a single-atom side, each integer `k` in the constraint other than 0 and 1 | substitution |

**A literal bound** comes from a top-level comparison of a single atom with a constant, including through a rule from one atom to another. A `mod` atom has the bounds `0` and `k − 1`. **"Each integer in the constraint"** means each constant and coefficient of a normal-form side, at any depth, in any conjunct.

**A fact whose premise is a true constant loses that premise. A fact with a false constant premise, or a true constant conclusion, is dropped.** There is no other filter. Measurement 2 of Rev 2 showed that three alignment filters each lost a realistic witness. That result is carried, and it was not rerun.

**F5 is what the crux needs.** `y*w + x < y*w + w ≤ h*w` is linear once F5 gives the second step.

### Invariance

**This is a language property.** Let `F(C)` be the fact set of constraint `C`, as a set of facts over normal-form polynomials. Then:

```
F(π C)  = F(C)       for each permutation π of the conjuncts of C
F(φ C)  = F(C)       for each exchange φ of the sides of equations of C
F(ρ C)  = ρ(F(C))    for each injective renaming ρ of the variables of C
```

**Why it holds.** The rule set, the closure, the settled set, `P` and the literal set are each defined over sets, and each definition reads no order and no name. A limit refuses whole and never truncates, so no visit order can change what survives. A monomial is one symbol, so the query has no argument position for a name to align.

**What follows for a verdict.** The query is in a decidable theory over free integer symbols, arrays and free functions. So two queries that differ only by `π`, `φ` or `ρ` have one answer, unless a resource limit stops the solver. Measurement 3 shows no exception.

**The test that holds it.** Answering the review's open question 1: a test builds each witness, applies each of `π`, `φ`, `ρ` and their composition, and compares fact sets with the renaming applied. It also compares the printed fact block under `π` and `φ` byte for byte. A control runs the same test on a one-rule-per-atom generator and must fail.

**What it does not cover.** Moving terms across an equation, as in measurement 3. Only a side that is one atom gives a rule.

### Limits

**Each limit is part of the set. Each is counted after resolution. Each refuses or omits whole, and none truncates.** The message names any limit that applied.

| Limit | Value | On passing it | Reason |
|---|---:|---|---|
| Degree of a monomial in the closure | 6 | the constraint refuses, `nonlinear:*` | **Totality of the compiler.** The largest degree on any witness is 4 |
| Monomials in the closure | 256 | the constraint refuses, `nonlinear:*` | Totality. The largest closure on any witness is 24 (BF3) |
| Size of a polynomial at any step of expansion | 256 | the constraint refuses, `nonlinear:*` | Totality. 125 monomials cost 1.97 CPU s; 343 refuse with no solver call |
| Settled forms of one written factor | 32 | that written product gives no pair; its monomials keep their splits | Totality. No witness reaches it |
| Pairs `|P|` in one constraint | 64 | F4, F5 and F10 are omitted; other facts stay | **Cost.** See below |

**Removed, with their reason gone.** The 16-monomial cap, because 27 monomials now cost 0.44 CPU s. The written-pair cap of 4 monomials, because measurement 4 shows it saves 7% to 24% and changes no result: 4 × 4 costs 2.119 CPU s without it and 1.608 with it, and 5 × 5 × 5 costs 1.965 and 1.666. That saving does not justify a rule that an author must learn.

**Cost is not monotone in size.** A 2 × 2 × 2 input, under the pair cap, costs 10.0 CPU s, and a 3 × 3 × 3 input, over it, costs 0.44. The larger input carries no F4, F5 or F10, and it still proves because its goal `r ≥ 0` needs only the sign facts. A goal that needs F4 or F5 falls back over the cap, as crux K=63 shows.

**The refusal runs in the compiler, before any solver call.** `--time-limit` does not cover the generator, so these limits are what makes it total. The degree and size checks run before a multiplication, so the cost stays small (measurement 5). 6, 256 and 32 are not derived from a cost curve. They are bounds that no witness comes near, and the first implementation step should reread them.

**The pair cap is not local, and the spec says so.** It reads the whole constraint, so an unrelated `let` can remove a proof (measurement 4). This is a disclosed fallback, not unsoundness. It stays for its cost: 64 pairs cost 20.3 CPU s and 2.0 MB of `.fq` text, and the default `--time-limit` is 120 s for a file. The largest `T` on a witness is 50 (W22), and the review's plane-copy path sits at 18 and costs 2.63 CPU s. Restricting pairs to the goal's connected variables would make the cap more local. It is a further rule, it was not run, and it is not proposed.

**Termination.** The closure is finite or refused. A split makes strictly smaller monomials. F4, F5, F9, F10 and F11 add no new product to `P`. So generation ends.

**Changing the fact set.** Answering Rev 1's review question 2.

- A change is a language change. It needs a CHANGELOG entry, a rerun of the witness table, the invariance test and `scripts/fallback_census.py`. A test holds the family counts on W3, P3 and W22 at their stated values.
- An **added** fact can only add proofs. A **removed** fact can move a program from `verified` to fallback.
- Neither needs `checker_soundness_version`, because each fact is a theorem. A `verified` sidecar written under a larger set stays true.
- A fallback is not a positive record, and `refuted` is not persisted (`compiler/src/LLMLL/VerifiedCache.hs`). So a stale result is at worst `asserted` until the next run, which is the safe side.
- A replay runs the stored VC with its stored facts, so an older artifact replays unchanged, if its soundness stamp matches.

### The mark

`mul##k` has no call binder, so `abstracted` and `cbAbstractable` cannot see it. A new scan is needed, and it reads the constraint as emitted, not the source:

```
productMarked c  ⟺  a symbol with the prefix mul## ∈ ⋃ { predSymbols p | p ∈ refinements (conEnv c) ∪ {conLhs c, conRhs c} }
```

- **Every site.** After emission, a program term can only be in an environment binder, the `lhs` or the `rhs`. So this one walk covers each site by construction. Measurement 9 holds a witness for each.
- **`predSymbols` is total** over the predicate forms, and it includes kvar arguments. No emission site in `compiler/src/LLMLL/FixpointEmit.hs` builds an `FQKVar` today.
- **`sanitizeFQId` must not rewrite the symbol.** It would give `mul__0`, a name that source can spell. Reserved symbols need a path past it. `FQ-FREEVAR-GUARD-1` needs no change, because `mul##k` is a real binder in the environment.
- **Scan after the fact pass, over the kept constraints,** beside `abstracted` and `postUnassumed`.
- **The mark is coarse.** It reads the whole environment, as those two do. So a linear bug beside a product is marked. The recheck is what keeps that bug `refuted` (N6, N7).
- **The emitter keeps the table** from each `mul##k` to its monomial, per constraint. The recheck reads it.

**The candidacy rule, three branches.** The review confirmed this by reading (`compiler/src/LLMLL/AbstractionVerdict.hs`), and no released binary reaches it. A marked definedness id in a function with a fallback body would be a hard id today, because `hardFns` has no body-faithful test. So:

1. For the product mark, **candidacy does not need a body-faithful function.** The other marks keep their rule.
2. **`reclassifyEmit` must branch.** A function already in fallback keeps its first cause and gets no second entry in `erBodyFallback` or `erBodyFallbackCauses`, as `test_e20_ill_defined_keeps_fallback_cause` expects on the linear path.
3. **`welldefWarning` must branch.** "Its truth was proved" is false for a `def-shell` with no body VC. That case says: "Its truth was not checked, because the body is outside the fragment."

A test needs a `def-shell` with an untranslated body and a clause whose definedness goal has shape W25. A marked id with no origin must not exist. A test asserts that each constraint holding `mul##k` has an owner.

### Verdict and recheck

For each failing id of an UNSAFE answer:

| Id | Recheck | z3 answer | Result for the id |
|---|---|---|---|
| Not product-marked | none | n/a | as today |
| Product-marked, and another mark as well | none | n/a | keeps its marks, as today |
| Product-marked only | yes | `sat`, model validated | **the product mark is removed**, so the id is complete |
| Product-marked only | yes | `sat`, model fails validation | keeps the mark, and an internal warning names z3 |
| Product-marked only | yes | `sat`, a value it cannot read | keeps the mark |
| Product-marked only | yes | `unsat` | keeps the mark. **Never `verified`** |
| Product-marked only | yes | `unknown`, limit reached, process error, z3 missing | keeps the mark |
| Product-marked only | no: the translator abstains | n/a | keeps the mark |

The existing rule then decides, with no other change:

| Function's failing ids | Outcome |
|---|---|
| A complete id, truth partition | `refuted`, exit 1 |
| A complete id, definedness partition | `ill-defined`, exit 1 |
| A complete id, `descent` or `decreases` | the existing measure failure |
| All marked, none only definedness | fallback, cause `abstraction-unsafe`, construct `abstraction:nonlinear:*`, exit 0 |
| All marked, all definedness | fallback, cause `clause-welldef-unproved`, exit 0 |

So the off-by-one M1 is `refuted`. An off-by-one in a `bytes-get` call-pre reports `refuted` by the same route, and BF1, BF4 and BF9 are that case with arrays and strings in scope.

**What is checked.** The query holds the failed constraint's environment refinements, its `lhs` without the F facts, and the negated `rhs`. `mul##k` prints as the product of its atoms. **The other ground-fact families (`measure-nonneg`, `byte-range` and others) stay.** Dropping `byte-range` gives a false `refuted`, as measurement 7 shows, and a test holds it. Product facts are dropped, because under `*` they are theorems and add nothing.

### What `sat` is validated against

The compiler asks `(get-value ...)` for each variable of any sort, and for each application of a free function. It reads the values as follows.

| z3 prints | The checker reads |
|---|---|
| an integer, `(- n)` | an exact integer |
| `((as const (Array Int T)) d)`, `(store A i v)`, `let` | a **finite map with a default** |
| `lambda`, `(_ as-array f)` with `f` from `(get-model)` | a finite map, read at the points its `ite` names |
| `Str!val!k` | a **token**, with equality only |
| anything else | unreadable: the id keeps its mark |

It then evaluates, itself:

1. every hypothesis, which must be true;
2. the goal, which must be false;
3. each product as exact multiplication; `(/ e k)` and `(mod e k)` as Haskell `div` and `mod`; an `FQIte` by its comparison;
4. `Map_select` and `Map_store` on finite maps, and equality of finite maps as equal defaults and equal exceptions;
5. **function consistency:** two applications of one free function with equal arguments must have equal results, with arguments compared as maps or tokens where they are.

Any failure gives the mark back. This check does not use z3's `:model_validate`.

**How far the check is independent of z3.** Rev 2's sentence was too strong. The checker computes each term in items 3 and 4 itself, and z3 cannot make those false. A free function such as `strLen` has only the value z3 gave, checked for consistency. That is no weaker than the VC: the VC leaves that function free apart from its stated facts. A false `refuted` then needs a false VC, which is a defect today as well.

### What `refuted` means

**`refuted` is modular, and a validated model is a VC counterexample.** It is not always an input that fails at run time. The review's run on 0.37.0 shows this with no product: a file with `(def g [x: int] -> int (post (>= result 0)) 5)` and `(def-shell lin [x: int w: int] -> int (pre (>= w 0)) (post (= result 5)) (g x))` gives exit 1, `refuted`, and `lin` is true. A model there holds a value of `g` that no run gives. Rev 2's "a validated model is a real one" is withdrawn.

If the constraint also holds `strLen`, `bytesLen` or `Map_select`, a `sat` model interprets those too. That is the same meaning as a QF-LIA UNSAFE over those symbols today. The recheck removes the `*` abstraction and adds no other. So `refuted` keeps its meaning. Clause 1 and clause 2 marks stay separate and block the recheck, because they name an abstraction the query cannot remove.

**A `sat` varies by z3 version; a `verified` does not.** A weaker z3 can only lose a refutation. CI must not assert `refuted` on a z3 where it was not measured.

**Replay.** A function's artifact records the outcome as today, with no new enum value. A replay of a rechecked `refuted` reruns the recheck on the stored VC. If it does not reproduce, it fails closed (`classifyReplay`).

### The limit and the budget

**The limit.** `(set-option :rlimit 2000000)`, plus a 5 s process guard. A clock limit makes `refuted` depend on machine load; `rlimit` does not, on one z3 version. The largest false count is 15070 on 4.15.4 and 14703 on 4.8.12. On `sat` the unit is close across the two versions. On a true `unsat` it is not, 1368835 against 186173, and only `sat` decides the outcome. W23 costs 2.23 s at this limit on an unloaded 4.8.12 runner, so 8 such ids cost about 18 s per function. Rev 3 on 4.8.12 has no measurement at a lower limit (see "The void row"). The Rev 2 prototype kept all 19 false witnesses `sat` at a real 200000, on a different query. **Keep 2000000 until the table runs through `llmll verify`, and then choose again from real counts.**

**The budget.** Within each function, **each partition (truth, definedness, measure) rechecks at most 8 failing ids, in id order, and stops at its first validated id.** One complete id is enough for a partition, and stopping per partition keeps the qualification that `test_e3_ill_defined_and_refuted_qualified` holds: a function that is ill-defined and refuted stays both. The time counts under `--time-limit`. Beyond 8, ids keep the mark.

### Four callers

`applyAbstractionVerdict` is pure, and the recheck needs IO. **The function has four production callers, and the review named three.** `compiler/src/LLMLL/PatchApply.hs` is the fourth.

**Design.** A new IO step runs the recheck and returns the set of cleared ids. `applyAbstractionVerdict` gains that set as an argument and stays pure. Existing hspec calls pass the empty set.

| Caller | Site | Runs the recheck | Why |
|---|---|---|---|
| `verify` | `doVerify` in `compiler/app/Main.hs` | yes | the main use |
| `patch` | `compiler/src/LLMLL/PatchApply.hs` | **yes** | otherwise a fill with an offset bug is written, as a not-proved fallback, when it should be rejected as refuted. This is the swarm's path |
| `--cdp` | `checkCDPCandidate` in `compiler/app/Main.hs` | **yes** | otherwise no mutant of a product contract is ever killed: a marked UNSAFE reads as `Nothing`, unvalidated |
| diverge | classifier in `compiler/app/Main.hs` | **yes** | otherwise a wrong fill reads `FSOutsideFragment` and not `FSRefuted` |
| `--weakness-check` | `checkWeaknessCandidate` | no | it does not call the function, and it acts only on SAFE |

**What `--cdp` does to a score.** A mutant is killed only by a validated `sat`. A native `unsat` or a limit gives `Nothing`, as a marked id does today. A function with no product gets the same VC and the same answer, so its score does not move. A function with a product can move, because it is refused today: 9 functions in 6 files (Rev 1 count). **This is NOT RUN.** A CDP diff across this change must use serial runs, because concurrent runs race on one `.fq` path (`CDP-FQ-RACE-1`). The recheck must not add a shared path: it sends the query on stdin or through `openTempFile`. A candidate with marked failing ids costs one more z3 call per id, under the budget.

### The recheck's translator

**The recheck gets its own translator, in its own module.** `fqPredToSMT` stays as it is. `compiler/src/LLMLL/Feasibility.hs` uses it for the refine gate, which fails open on a function term today. Extending it would change that gate, and nothing here asks for that.

The new translator handles `Map_select`, `Map_store`, `Map_default`, `bytesLen`, `strLen`, a free function, `Str` and the two-array map encoding, `FQIte`, `/` and `mod`, and it expands `mul##k` from the emitter's table. Where it cannot translate a term, it abstains, and the id keeps the mark.

### The verify schema

- **`docs/llmll-verify.schema.json`, `abstraction_fallback`.** The pattern `^abstraction:app:` rejects `abstraction:nonlinear:*`. It becomes `^abstraction:(app:|nonlinear:)`. The description gains the product case.
- **`verify_json_version`.** A new value in an existing key is an additive change, within the major version. It goes from 1.1.0 to 1.2.0, in the schema constant and in `verifyJsonVersion` (`compiler/src/LLMLL/VerifyEnvelope.hs`). This follows the precedent of 1.1.0, which added two keys.
- **`welldef_unproved`.** Its pattern `^welldef:` already accepts `welldef:abstraction:nonlinear:*`. Its description gains that form.
- **Correction.** Rev 2 said "JSON does not change". JSON-AST does not change, and the verify JSON does. No new key is added.

### Messages

**Callee, at `verify`.** `W-BODY-FALLBACK` names the term. The text does not vary by z3 version:

```
W-BODY-FALLBACK f: the post is not proved. A product is in the failing constraint.
  Refused by: abstraction:nonlinear:*   at <JSON pointer>
  Product facts did not prove it. Native z3 found no counterexample.
  The post stays a run-time check. A strict-core def that calls f will be refused.
```

Over the pair limit, the second line becomes "this constraint holds 65 product pairs, including any unrelated product in scope; the limit is 64, so monotonicity and congruence facts were not added". A refusal under "Limits" says "this constraint is over the limit for products after its equations are applied".

**Refuted.** `LLMLL.md:13-14` says that no counterexample input is printed. The `refuted` text may print a validated model, in this form only:

```
VC counterexample: h=25 w=21 x=21 y=24. Callee results in it are assumed, not computed.
```

No JSON key is added. The engineer can take this or leave it.

**The "two calls" texts.** Three places say that a failure "needs two calls", which is false for a product:

- `abstractionRepair`, through `repairOf` in `compiler/src/LLMLL/AbstractionVerdict.hs`, the hint "If two calls to ...". A product gets: "Restate the post, or supply evidence with ?proof-required."
- `notProvedMessage` in `compiler/src/LLMLL/PatchApply.hs`, which also strips the prefix `abstraction:app:`. A product gets: "'f' was not proved: a product is in the failing constraint, and native z3 found no counterexample (abstraction:nonlinear:*). Its postcondition was assumed."
- The comment at the diverge site in `compiler/app/Main.hs`.

`LLMLL.md` §5.3.4 ("Abstraction verdict") and the `abstraction_fallback` description describe the same cause, and they move with it.

**Caller, at core admission.** Today, `check` refuses a product in a `def` at once. After decision 3, a `def` with an unprovable product passes `check`, falls back at `verify`, and then causes `core-membership-violation` at its callers. `mkCoreMembershipViolation` keeps its kind and gains a variant with the cause:

```
def 'c': callee 'f' is not body-faithful, because verify fell back on a product at <JSON pointer>
  (abstraction:nonlinear:*). Only verified functions are admissible in strict-core bodies.
Suggestion: restate f's post, supply evidence with ?proof-required, or write 'c' as a def-shell.
```

Core admission reads persisted evidence. If the sidecar does not hold the fallback construct, it must carry it for this text. The engineer confirms this.

### Disclosure

Add the family `product-facts` to `ground_fact_families`. `LLMLL.md` §13.12 goes from four families to five, with the statement of the set. No new `assumed_facts` kind and no increase of `trust_report_version`. A test checks each schema by native z3, as measurement 8 does, once and not per program. `verified` stays `verified`, with no cap.

### Lean worklist

`runLeanstralPipeline` selects a fallback function with `isNonLinear b`. `isNonLinear` stops flagging a two-variable `*`, for the same reason that it stopped flagging `(* 8 r)`. So W14, W23 and W25 would leave the list. **Select from the outcome:** a function in the fallback set whose construct is `abstraction:nonlinear:*`, or whose body holds a remaining nonlinear operator.

`nlPreH` and `nlPostH` in `compiler/src/LLMLL/HoleAnalysis.hs` then stop creating a `non-linear-contract` hole for a product. A static hole on W3 would be noise, because B proves it. The `TypeCheck` warning on an explicit `?proof-required` keeps its form, and its text must stop saying that QF-LIA cannot discharge it when the operator is `*`.

### Spec text

**`Σ_auto` does not widen.** `LLMLL.md:13-14` defines `Σ_auto` by a complete decision, and neither statement holds for a term with `mul##k`. The solver's question is decidable, but it is a question about the abstraction. So §5.3.3 gains a separate class. Draft for the documentation-lead:

> **Abstracted products — sound, not complete.** A product of two non-constant `int` terms is normalized, and each monomial becomes one free symbol, with a fixed set of ground theorems of integer multiplication. The set does not change when conjuncts are reordered, when the sides of an equation are exchanged, or when a variable is renamed. SAFE is a proof of the property, resting on `int-unbounded-1`. UNSAFE is not: the function is `refuted` only when an interpreted solver query gives a model that an exact evaluation confirms, and otherwise it falls back. Such a model is a counterexample to the verification condition; a callee result in it is assumed. A constraint over a stated degree or size refuses with `nonlinear:*`. A constraint with more than 64 product pairs loses its monotonicity and congruence facts, and every product in scope counts toward that, related to the goal or not. Nothing here is outside the trust of `verified`. No class of programs is claimed complete. The witness table is the coverage evidence. Nonlinear integer arithmetic remains undecidable (Matiyasevich 1970).

The review's answer to Rev 1's open question stands: **no fixed one-round ground set is known to be complete for a natural bilinear class.** This record claims none, and it keeps "sound and incomplete".

### What B does not prove

| Witness | Claim | Why | What the author can do |
|---|---|---|---|
| W14 | `4·cw·ch ≥ w·h` | needs `w ≤ 2·cw` scaled into a monotone fact, and `2·cw` is not a pair | fallback; `?proof-required` |
| W23 | `x² ≠ 2y²` | irrationality; no local fact reaches it | fallback; Lean route. Native z3 also does not decide it |
| W25 | `(a+b)² ≥ 4ab` | needs `(a−b)² ≥ 0`, and F8 sees only written squares | fallback; restate as `(a−b)*(a−b) ≥ 0` |
| Y5 | frame `≥` 3/2 luma | the W14 class: scales the chroma plane against luma | fallback; `?proof-required` |

Native z3 proves W14, W25 and Y5. Each reports fallback, with "no counterexample found". A new true fact can only add proofs, so each can be added later, under "Changing the fact set".

### Option comparison

**A. Native `*` as the proof engine.** It has no new facts, and it costs almost nothing (Rev 1: at most 0.086 s per decided witness). Its costs are version dependence, `--smtTimeout` with a false UNSAFE, and `replay-artifact` having to reproduce a nonlinear result. The recheck takes its strength as a refuter without any of those.

**Rev 1's C, C′, D and E, carried and not rerun.** C, a named product with no facts, proved 2 of 27. C′, the row's wording, proved 6 of 27 and failed every offset witness. D, the Lean path: `verify --leanstral-mock` says "not verified (fail-closed)", the real path was not run, and `LeanTranslate` rejects `/`. It stays the route for W23. E, the cursor pattern, gives no seek and no stated size.

### Design-reference set

Carried from Rev 2, with no change and no new search. Cimatti and others, incremental linearization: TOCL 19(3), 2018, and for NIA SAT 2018. That method is a refinement loop over a linear abstraction. **This design has no refinement loop.** It is related in that it adds true lemmas to an abstraction, and in no stronger way. Dafny `--disable-nonlinear-arithmetic`: its man page says more manual work and more predictable. Verus `by(nonlinear_arith)`: default mode disables nonlinear theories, and the query is separate, which is the shape of the recheck. Verus and Dafny give the author the nonlinear step; this design does not, and that is a scope difference and not a soundness one. Sherali–Adams 186173: `MUL-SLACK-1` only. Handelman 1988 (Pacific J. Math. 132(1), pp. 35-62): secondary here; it concerns compact polytopes, and `w` and `h` are unbounded. Matiyasevich 1970: *Enumerable sets are Diophantine*, Doklady Akad. Nauk SSSR 191, pp. 279-282; English in Soviet Mathematics 11(2), pp. 354-357.

`fixpoint --help` on 0.9.6.3.7 prints "`--linear`: Use uninterpreted integer multiplication and division" (Rev 2). This record makes no claim about any Liquid Haskell flag.

## Edge cases and degenerate inputs

1. **Positive witness for the recheck.** M1: `(>= y 0)`, `(< y h)`, `(>= x 0)`, `(<= x w)`, post `(< (+ (* y w) x) (* w h))`. `fixpoint` UNSAFE, marked, native `sat`, validated. `refuted`, exit 1. Channel: contract.
2. **Positive witness for the mark.** W23 at each site of measurement 9. `fixpoint` UNSAFE, marked, native not `sat`. Fallback, exit 0, not `refuted`. Channel: trust.
3. **Positive witness for invariance.** O1 with its equations reversed, and renamed. The fact set is equal under the renaming, and SAFE in all 9 forms. Channel: contract.
4. **Positive witness for the limit.** `x₂ = x₁*x₁ + 1`, `x₁ = x₀*x₀ + 1`, goal on `x₂*x₂`. Degree 8 after resolution. Refused, `nonlinear:*`, no solver call. Channel: trust.
5. **Positive witness for byte-range.** B1. With the family, native `unsat`, so no false `refuted`. A test drops the family and sees a model at `v = -256`. Channel: contract, trust for the family.
6. **Negative factors.** M5, `(>= (* w h) 0)` with no `pre`. F1 does not fire. Native `sat`. `refuted`, which is correct at `w=-3`. Channel: contract.
7. **Zero extents.** `w=0` in W3's `pre` has no solution, because `0 ≤ x < w` fails. F2 gives `w*h = 0`. Channel: contract.
8. **A constant factor.** `(* 3 w)` is not a product of two non-constants. The `.fq` text is the `FQ-ARITH-FLAT-1` text, and UNSAFE stays `refuted` with no recheck. Channel: contract. Citation: `SIGMA-CONST-ARITH-1`.
9. **A `let` constant.** `(let [(ch 3)] (* (* w h) ch))`, as P5. F9 links it. Channel: contract.
10. **A cancelled refused term.** `(* 0 (/ x y))`. Refused before expansion. Channel: contract.
11. **A partial read in a factor.** `(* (map-get m k) w)` in a post. `mul##k` adds no obligation, and `map-get` keeps its `wd-post`. The atom's value is an integer, so each fact holds. Channel: contract. Citation: `CLAUSE-WELLDEF-1`.
12. **A callee post with a product.** `(post (= result (* w h)))` at `(area a b)`. The caller assumes `result` equals the monomial of `a` and `b`, after substitution. A linear bug in that caller stays `refuted` (N6). Channel: contract.
13. **`abs` and `mod` as factors.** A6, A7. An `FQIte` or `mod` atom is a factor, and z3 interprets it inside each fact. Channel: contract.
14. **A goal that is an identity.** P1. The normal form proves it, and no constraint is sent. Channel: contract.
15. **A goal that is a false constant.** N9, `(< (* w h) (* h w))`. `rhs false`, UNSAFE, native `sat`, `refuted`. Channel: contract.
16. **A product in `decreases`.** It stays refused: descent is proved over exact terms. Channel: contract. Citation: `LLMLL.md` §5.3.
17. **A parameter named `mul` or `mul_0`.** No collision (measurement 10). A test holds it. Channel: spec is silent (intentional).
18. **Two names that sanitize to one.** `a-b` and `a_b` are one atom today, which is the false proof in `FQ-NAME-COLLIDE-1`. That row ships first. Channel: contract.
19. **Over the pair limit.** 65 pairs: F4, F5 and F10 are omitted, and a claim that needs them falls back, with a message naming the limit. Channel: trust.
20. **Machine integers.** Under any codegen with a fixed-width `int`, F1, F3, F4, F5 and F8 are false. The stamp `codegen_semantics_version` covers this, and this family must follow it. Channel: trust.
21. **A float product.** No float `*` exists. A future one must not receive F5, which needs integrality: `a=0, c=½, b=d=1` breaks it. Channel: type.
22. **A kernel `out-len`.** `(out-len (* w h))` stays refused. A caller can now prove `(= npix (* w h))` and pass `npix`. Channel: type. Citation: `docs/design/ffi-buffer-proposal.md`.

## Verification mapping

| Obligation | Channel | Fragment | Citation |
|---|---|---|---|
| A contract or body VC that holds `mul##k` | contract | **(b) nonlinear, with surface-form restriction: a decidable encoding of an undecidable class,** over free integer symbols with the existing array and function theories. Not (a): it does not join `Σ_auto`, and it is not complete | `LLMLL.md` §5.3.3 |
| The truth of each fact | not an obligation | Each schema is checked once, in a test | "Soundness" |
| A failed constraint's recheck | none: it can only remove a mark | QF-NIA with arrays, used for `sat` only | "Verdict and recheck" |
| A claim that the facts cannot reach | trust | (b): falls back. (c) `?proof-required` is available, and the Lean path stays experimental | `LLMLL.md` §5.3.5 |
| A constraint over a limit | trust | (b): refused with `nonlinear:*`, as today | "Limits" |
| Variable divisor | outside this record | (b), refused as today | `DIV-VAR-1` |

### Soundness

**SAFE.** Each fact is a theorem at every integer valuation, with `mul##k` read as the product of its atoms. Take that standard model. If `H ∧ F ⟹ G` is valid over free symbols, it holds under that reading. `F` is true there, so `H ⟹ G` is true. So no path condition is needed for a fact, and short-circuit context does not matter.

**The base.** The facts rest on `int-unbounded-1`: `*` is exact `Integer` multiplication. A machine-integer codegen would make F1, F3, F4, F5 and F8 false. **F5 is integer-only.** Its certificate needs `a < c ⟹ c−a−1 ≥ 0`.

**Reach.** The normal form uses ring identities only, so it does not change the value of a term. A rule adds facts and does not rewrite a clause. F9, F10 and F11 carry their premises, so each is true with no hypothesis. `*` is total, so it has no WD entry. `mul##k` has no call binder, so the call counts of `CALL-CONGRUENCE-1` and clause 2 do not apply. A `(/ e k)` or `(mod e k)` atom has a positive ground `k` by the refusal scan, so it is total and agrees with Haskell `div` and `mod`. The review ran `fixpoint` on `(-3 / 2)` and `(-3 mod 2)`, which give -2 and 1 (review).

**`refuted`.** The exact evaluation confirms that the valuation satisfies the VC's hypotheses and falsifies its goal. So it adds nothing to the trust base beyond the VC being faithful, which every `refuted` needs today.

**The fuzz.** The review's differential fuzz of Rev 2, 900 cases, found no false proof and no false model (review). **It was not rerun on Rev 3.** Measurement 8 is a weaker check of the same kind.

**Trust.** The facts add nothing to the sealed-builtin axioms. Their family is disclosed.

## Affected surface

This is an addition to the reflected fragment. Its soundness argument is above.

- `compiler/src/LLMLL/FixpointEmit.hs`: the `*` arms of `exprToPredWD` and `bodyToPredM`; the refusal scan, the normal form, rules, closure, limits, the fact pass and the binder pass; the monomial table; the `productMarked` scan; the `nonlinear:*` label stops applying to `*` under the limits.
- `compiler/src/LLMLL/FixpointIR.hs`: a way past `sanitizeFQId` for reserved symbols; a fixed print order.
- `compiler/src/LLMLL/AbstractionVerdict.hs`: the product mark, a cleared-id argument, the candidacy rule, the `reclassifyEmit` and `welldefWarning` branches, the repair text.
- **A new recheck module:** the translator, the limit, the model reader and the evaluator. `compiler/src/LLMLL/Feasibility.hs` does not change.
- `compiler/app/Main.hs`: the recheck at `doVerify`, `checkCDPCandidate` and the diverge classifier; the Lean worklist.
- `compiler/src/LLMLL/PatchApply.hs`: the recheck, and `notProvedMessage`.
- `compiler/src/LLMLL/Syntax.hs`: `isCoreBodySyntactic`, under decision 3. `LLMLL.md` §12 `core-expr` moves with it.
- `compiler/src/LLMLL/HoleAnalysis.hs`, `compiler/src/LLMLL/TypeCheck.hs`: "Lean worklist".
- `compiler/src/LLMLL/Diagnostic.hs`: "Messages".
- `compiler/src/LLMLL/TrustReport.hs`: the family only.
- `compiler/src/LLMLL/VerifyEnvelope.hs`, `docs/llmll-verify.schema.json`: "The verify schema".
- **Fixtures that exist to show the refusal move to a claim B cannot prove** (Rev 1 list, not rechecked): `examples/leanstral-demo/square.llmll`, `scripts/doc-claims/nonlinear-body-fallback.llmll`, `scripts/tests/fixtures/fallback-census/census-constructs.llmll`, `scripts/tests/fixtures/fallback_attrib/attrib.llmll`, with `scripts/tests/test_fallback_attrib_1.py`, `scripts/tests/test_fallback_census.py` and `compiler/test/Spec.hs`.
- `LLMLL.md` §0, §5.3.3, §5.3.4, §5.3.5, §12, §13.12; `docs/getting-started.md`; `docs/compiler-team-roadmap.md`; `docs/design/INDEX.md`. These are the documentation-lead's.
- **Versions.** `verify_json_version` goes to 1.2.0. `checker_soundness_version` keeps its value, because no recorded verdict can stop being true: this is an argument, for the engineer to confirm. `proof_artifact_version` keeps its value, because no enum value is new. `trust_report_version` keeps its value (decision 4). A caller of a callee with a product post gets a new VC, because that post was not assumed before. Its verdict can move, in a known direction, from `callee-post-unassumed` toward `verified`.

## Ship order

1. **`FQ-NAME-COLLIDE-1`,** because an atom key is a printed name. It is a false proof on 0.37.0 and it should ship regardless (review).
2. **`FQ-ARITH-FLAT-1`,** on its own, because it repairs the cost of a long sum with no language change. A sum of 20 costs 33.2 CPU s nested and 0.026 flat. This record's limits are measured on that printing.
3. **MUL-VAR-1.** The z3 4.8.12 run of `rev3.py` (decision 6) is done. Its first implementation step is the same witness table through `llmll verify`, and the Y4M and netpbm contracts restated. It should land before the library's contract surface is written against `npix`.

## Not run

| Item | What it needs |
|---|---|
| **Any witness or VC with a product through `llmll verify`** | an implementation; first implementation step |
| **A real rlimit of 200000 on Rev 3 and z3 4.8.12** | a CI run of the corrected `rev3.py`, if the limit is to be chosen before the `llmll verify` run. The design limit does not need it |
| The model reader's `let`, `lambda` and `as-array` paths | a z3 that prints them, and a run that logs all 39 models. The 11 models printed on each of 4.15.4 and 4.8.12 do not hold them |
| The two-array map and `Str` encoding as the emitter really prints them | an implementation. B4, BF5 and BF8 are hand-built to the shape in `compiler/src/LLMLL/FixpointEmit.hs` |
| Y4M and netpbm contracts restated | an implementation |
| `--cdp`, diverge and `patch` with the recheck, and any `--cdp` score | an implementation |
| Replay of a rechecked `refuted` | an implementation |
| The false `ill-defined` path in `applyAbstractionVerdict` | code reading only (team and review); no run reached it |
| Limits 6, 256 and 32 on real contracts | an implementation |
| Real path context, `let` binders and mixed theories at scale | an implementation |
| `scripts/fallback_census.py`, the verdict sweep | an implementation |
| The review's differential fuzz on Rev 3 | not run in this revision; measurement 8 is weaker |
| Three alignment filters on Rev 3 | carried from Rev 2; not rerun, because the fixed set has no filter |
| The slack schema under flat printing | `MUL-SLACK-1` |
| A profile of `fixpoint` on deep parens | the cause is a source reading with a matching curve |
| Lean path | an API key and a Lean project (Rev 1) |
| Option A's stability, seeds and real files, on this revision | carried from Rev 1 |

## Risks and open questions

1. **`refuted` depends on what a z3 version prints.** Verification-ergonomics. The validator reads printed values. 39 of 39 validate on 4.15.4 and 4.8.12, on script-built VCs. An unread form loses `refuted` and stays safe. Complicates: the real emitter's terms are not yet measured.
2. **The witness set is still written by this team and the professor.** Scope. Each pass has found gaps: the review's P set, this team's Q10 and Q11, the review's O, K and Y sets, and this revision's fourth caller. Expect more from real contracts. Complicates: a miss gives a disclosed fallback, and a new fact can only add proofs. The Y4M and netpbm restatement is the next test.
3. **Hand-built VCs.** Scope. The emitter's real shape was approximated. A real function has several constraints, and a real environment has more binders. Complicates: the first implementation step repeats the table.
4. **Moved terms lose the rule.** Verification-ergonomics. `(= (- x y) 1)` gives no rule, where `(= x (+ y 1))` does. An author can see this only from a fallback. Complicates. A rule from any atom with coefficient 1 would remove it, and it would grow the closure on each definition, so this record does not propose it.
5. **Fact cost at the pair limit.** Verification-ergonomics. 64 pairs cost 20.3 CPU s and 2.0 MB of text, in one constraint, under a default of 120 s for a file. A function with several such constraints reaches `--time-limit`, and that costs the whole file at exit 5. The image-domain path sits far below it. Complicates, at scale. `MUL-SLACK-1` covers the remaining cost.
6. **The limits are chosen, not derived.** Scope. 6, 256 and 32 are totality bounds that no witness comes near. A real contract may reach them, and then it refuses. Only matters at scale.
7. **The non-local cap.** Verification-ergonomics. An unrelated `let` can remove a proof. Disclosed in the spec and the message. Complicates.
8. **A native `unsat` is thrown away.** Verification-ergonomics. W14, W25 and Y5 are true, z3 says so, and the program falls back. Decision 1 names the alternative.
9. **The Lean demo loses `square`.** Scope. A new example is needed, such as W23.
10. **The model reader is new parsing of z3's output.** Soundness, mitigated. A mistake reads a value wrongly, and then an evaluation fails or a false model passes only if it satisfies the VC by exact evaluation. A passed model is a real VC counterexample whatever the reader did, so a reader bug cannot give a false `refuted` beyond today's meaning. Only matters for ergonomics.

### Proposed rows, not filed

**`DIV-VAR-1`** (no contract can state a division or `mod` by a variable). An image library needs `(/ i w)` and `(mod i w)` to turn an offset into coordinates, and `(/ (* x sw) dw)` for nearest-neighbour resize. Haskell `div` and SMT `div` agree only for a positive divisor (`LLMLL.md` §5.3.3), so this needs a proved `divisor > 0`, a definedness entry under `CLAUSE-WELLDEF-1`, and its own facts. Rev 1 measured three witnesses SAFE and one false variant UNSAFE under Option A.

**`MUL-SLACK-1`** (measurement only, not in scope for this release). The stall that gave this row most of its reason is now explained by paren depth. The review reports that removing parens round each comparison in a fact halves the remaining cost, and that the same factor explains it. What remains: cost still grows with text size at the pair limit, and the 186173 schema (review) proved W14, W20 and W25 in z3. Under flat printing, that schema may be affordable. It gives a statable certificate class, and it could reach W14 and Y5.

## Open questions for the professor

None. The review's two open questions are answered in "Invariance" and "Four callers". z3 4.8.12 is a measurement, not a question.

**Rule breaks.** Table cells use fragments. Some sentences that state a condition exceed the word limit, because the condition must stay with the sentence. The verbatim messages and the spec draft keep their own register.
