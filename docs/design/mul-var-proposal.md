---
name: mul-var-proposal
title: "MUL-VAR-1: state and prove a product of two variables, so that an image layout can have a contract"
status: "Rev 2, DRAFT 2026-11-07. Answers mul-var-professor-review.md. Awaits a user decision. Not settled."
date: 2026-11-07
author: language-team
rows: "MUL-VAR-1 (G7, DECIDE). Related: CLAUSE-WELLDEF-1 (shipped v0.37.0), ABSTRACTION-VERDICT-1 (shipped v0.34.0), BITWISE-WIDTH-1 (G7, PLAN), FFI-KERNEL-1 (G7, PLAN), CORE-SYNTAX-MSG-1 (G3, PLAN), LEAN-GA (parking lot). Proposes two rows, not filed: DIV-VAR-1, MUL-SLACK-1."
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# MUL-VAR-1: a product of two variables in a contract

**Status: Rev 2, DRAFT 2026-11-07.** The user has not settled this record. The compiler was not changed.

**How to read the numbers.** A number with no label comes from a run on this revision, on z3 4.15.4 and liquid-fixpoint 0.9.6.3.7. A number labelled "Rev 1" or "review" is carried from that document and was not rerun, unless the line says so. **Every VC here is built by a script. Nothing went through `llmll verify`.** z3 4.8.12 was not run (see "Not run"). The machine had a load average of 80 to 180 during these runs, so the record reports CPU seconds for `fixpoint` (with its z3 child) and treats a wall-clock time as an upper bound.

The scripts are `nf.py` and `rev2.py`, in the session scratchpad folder `mulvar`. They are not committed. The first implementation step must repeat the tables through `llmll verify`.

## Restatement

An image library states sizes and offsets as products: `w*h*channels`, `y*stride + x`. LLMLL cannot prove a product of two variables today, so no contract can say that a pixel offset is inside its buffer. This record chooses how `verify` handles `(* a b)` when neither operand is a constant, and how it reports a false claim that holds one.

## Recommendation

Three parts ship together in one release:

1. **Normal form.** A product becomes a polynomial over atoms. A monomial is a sorted multiset of atoms, printed as one uninterpreted symbol. Commutativity, associativity and distribution then hold by construction.
2. **Fixed fact set.** The emitter adds ground theorems of integer multiplication to each constraint that holds a product. The set is part of the language surface.
3. **Native recheck.** On UNSAFE, the compiler runs z3 on the same constraint with `*` interpreted. A `sat` whose model passes an exact-integer check restores `refuted`. Any other answer gives the fallback outcome. A native `unsat` never gives `verified`.

| Encoding | True proved (of 53) | False wrongly proved (of 19) | False reported `refuted` (of 19) | Can it hang? |
|---|---:|---:|---:|---|
| **Rev 2 B + recheck (recommended)** | **48** | 0 | **19** | z3: no. `fixpoint`: not on any witness, but see the expansion cap |
| Rev 1 B, measured on the 38 true witnesses it can express | 27 of 38 | 0 of 17 | 0, fallback only | Not measured on long sums |
| A, native `*` as the proof engine | 52 | 0 | not measured as a design | Yes (W23), or a false UNSAFE under a timeout |

Row A counts the native `unsat` results of the recheck query on this witness set. Rev 1 table entries for options C, C′, D and E are in "Option comparison".

**Blocking finding 1 is resolved** on this witness set: M1 to M9 and ten more false claims all give `sat` with a validated model, in at most 0.050 s wall at load 80 or higher. No true witness gives `sat`. **Blocking finding 2 is resolved** for P1 to P6: the generated form proves all six, with no hand-written equation. Five true witnesses do not prove: W14, W23, W25, Q8 and Q9. Each is listed with its cause in "What B does not prove".

## Decisions for the user

Each decision shows the professor's position as an input. The user decides.

**1. Encoding.** *Professor:* B for proofs, native z3 for `sat` only, A rejected as a proof engine, on W23's false UNSAFE (review 2.23 s; 2.13 s in this run). *Recommendation:* the same result, with a different reason. The false UNSAFE alone does not reject A, because the recheck in this record would cure it: the same direct z3 call reports `timeout` on W23. The reasons to reject A are these. A `verified` would depend on the z3 nonlinear engine and its version. One obligation can stop a whole file: W23 ran past 40 s with no per-query limit (Rev 1 measurement 4). The cost of this choice is real: A proves W14, W25, Q8 and Q9, and B does not. *Alternative that the user may prefer:* accept a native `unsat` as `verified`. That gives 52 of 53 at low cost, and it brings all the version dependence back. It is not recommended.

**2. Refutation.** *Professor:* restore `refuted` in the same release. *Recommendation:* agree. 19 of 19 false witnesses report `refuted` in this design. A separate row would ship a release in which an off-by-one offset exits 0. This rests on z3 4.15.4 only; see decision 6.

**3. `def` bodies.** *Professor:* admit, with a message condition. *Recommendation:* agree. "Messages" gives the text.

**4. Disclosure.** *Professor:* one family C ground-fact family, no new `assumed_facts` kind, no increase of `trust_report_version`. *Recommendation:* agree. `ground_fact_families` is an array of free strings (`docs/llmll-trust-report.schema.json`), and `markGroundFacts` takes any family name, so no schema change is needed. The family is named `product-facts`. The existing report text says "rides `codegen_semantics_version`", and that is correct here: the facts rest on `int-unbounded-1`.

**5. Variable divisors.** *Professor:* a separate `DIV-VAR-1`. *Recommendation:* agree. `(/ e k)` with a positive ground `k` stays an exact atom in this design. A variable divisor stays refused, with its existing `nonlinear` label. This revision measured no variable divisor.

**6. z3 4.8.12.** *Professor:* run on it, including the recheck, and record which false witnesses still report `refuted`. *Recommendation:* agree, and make it a gate before implementation starts. **NOT RUN.** It is not on this machine: `which -a z3` and the Homebrew Cellar give 4.15.4 only, a search of the home folder found no other z3, and `docker images` returned no match for z3 or llmll. The whole-disk search was stopped before it finished, so it is not a proof of absence. The run needs the user's permission to obtain that version, or a CI run of `rev2.py`. Soundness does not depend on the result: a weaker z3 can only lose a refutation or a proof.

## Change log, Rev 1 to Rev 2

| Review finding | Change |
|---|---|
| Gap 1, blocks: an offset bug exits 0 | "Verdict" adds the recheck, states what it checks, and gives a result for each z3 answer. Measurement 3 |
| Gap 2, blocks: regrouped products | "Normal form" replaces canonical nested `mul`. F6 goes away, and F9 replaces the proposed cross congruence and literal-factor equations. Measurement 1 |
| Gap 3: "stays decidable" | The option table drops that column. "Spec text" keeps `Σ_auto` unchanged and adds a separate class. "Sound and incomplete" stays |
| Gap 4: the mark needs a new scan | "The mark" specifies a scan over each emitted constraint. Measurement 5 covers each site. This pass also found a second wrong verdict, `ill-defined`; the rule closes it |
| Gap 5: name collision | The symbol is `mul##nl`. Measurement 6 |
| Gap 6: a filter is a language change | "Fact set" is normative. Measurement 2 shows that three filters each lost a realistic witness, so the set has no alignment filter. It has three stated caps, each with its measurement |
| Gap 6: slack products | Measurement row only: proposed `MUL-SLACK-1`. Not in scope |
| Gap 7: Lean worklist | "Lean worklist" selects from the fallback outcome |
| Gap 8: late `def` fallback | "Messages" |
| Gap 9: `assumed_facts` | Decision 4 |
| Gap 10: `int-unbounded-1`, F5 | "Soundness" states both. `*` is total, so it has no WD entry. `mul##nl` has no call binder, so call counts do not apply |
| Gap 11: citations | "Design-reference set" is rewritten |
| Gap 12: evidence limits | "How to read the numbers", "Not run", risks |
| Review question 1: other functions in a recheck | "What `refuted` means" |
| Review question 2: is the set normative, and cached fallbacks | "Changing the fact set" |

Three Rev 1 statements are withdrawn. "The engineer may filter" is withdrawn by gap 6. "Rests on nothing beyond `*`" is withdrawn by gap 10. The option name "`mul`" is withdrawn by gap 5.

## Context located

1. `docs/design/mul-var-professor-review.md`: the findings that this revision answers.
2. `compiler/src/LLMLL/FixpointEmit.hs`: `abstracted` and `postUnassumed` read call binders only; `exprToPredWD` and `bodyToPredM` refuse `*`.
3. `compiler/src/LLMLL/AbstractionVerdict.hs`, `applyAbstractionVerdict`: a candidate needs a body-faithful function; `hardFns` gives `aoIllDefined` with no such test.
4. `compiler/src/LLMLL/FixpointIR.hs`: `predSymbols` walks every predicate form; `sanitizeFQId` maps a name to `[A-Za-z0-9_]`.
5. `compiler/src/LLMLL/Lexer.hs`, `pWord`: a source name can hold letters, digits, `-`, `_`, `.` and `?`, so it cannot hold `#`.
6. `compiler/src/LLMLL/Feasibility.hs`, `runZ3`: the direct z3 precedent; `fqPredToSMT` abstains on a function term.
7. `compiler/src/LLMLL/VerifiedCache.hs`: `refuted` is not persisted; a sidecar with another `checker_soundness_version` is discarded.
8. `compiler/src/LLMLL/ProofArtifact.hs`: replay reruns the solver on the stored VC and fails closed on a mismatch.
9. `compiler/app/Main.hs`, `runLeanstralPipeline`: the worklist selects with `isNonLinear`.
10. `compiler/src/LLMLL/Diagnostic.hs`, `mkCoreMembershipViolation`: the caller-side text.
11. `LLMLL.md:13-14`, §5.3.3 and §13.12: `Σ_auto`, the "Outside" clause, the ground-fact families.
12. `examples/y4m/FRICTION.md` F5 and `examples/netpbm-swarm/FRICTION.md` F12, F14: the source of the row. Carried from Rev 1.

**Spec drift, carried from Rev 1 and still open.** `LLMLL.md` §5.3.3 says nonlinear terms "route to `?proof-required`"; Rev 1 measured a `W-BODY-FALLBACK` with no hole on 0.37.0. The spec should move. liquid-fixpoint reads a z3 `unknown` as UNSAFE under `--smtTimeout`; this design does not pass that flag.

**Comment drift, new.** The comment on `sanitizeFQId` says that liquid-fixpoint accepts only `[A-Za-z0-9_]` in a name. On 0.9.6.3.7, `$`, `#`, `'` and `.` are accepted after the first character; only a leading `$` failed. The comment is incorrect but the code is safe.

## What happens today (Rev 1, llmll 0.37.0; not rerun)

| Input | Result |
|---|---|
| `def area`, body and post `(* w h)` | `check` exit 1: "body contains non-core syntax" |
| `def-shell area`, the same | exit 0, post not proved: `contract-post-outside-fragment`, `Refused by: nonlinear:*` |
| `def-shell off`, post `(< result (* w h))`, body `(+ (* y w) x)` | exit 0, post not proved, `Refused by: nonlinear:*` |
| `def-shell off`, `(= n (* w h))` in the `pre` | exit 0, post not proved: `contract-pre-outside-fragment` |
| `(* 3 w)`, `(+ (* 8 y) x)` | verified, as `SIGMA-CONST-ARITH-1` specifies |

## Measurements

**Witness set.** 53 true and 19 false claims. W1 to W26 with W5b and M1 to M9 are from Rev 1. P1 to P7 and N1, N2 are from the review. R1 to R4 and N3 are the Rev 1 "fixpoint only" claims, now run under B. **Q1 to Q15 and N4 to N10 are new in this revision**, from a second pass at regrouping, aliases, padded strides and mixed theories. No witness was removed or changed.

**1. Generated facts, fixed set.** Results are the same under `fixpoint` and z3 alone for all 72 witnesses (z3 limit 10 s). "NF" means that the normal form made the goal an identity, so no query is sent.

| Group | True proved | Not proved |
|---|---:|---|
| W1 to W26 with W5b (27) | 24 | **W14, W23, W25** |
| P1 to P7 (7) | **7** | none |
| R1 to R4 (4) | 4 | none |
| Q1 to Q15 (15) | 13 | **Q8, Q9** |
| **All true (53)** | **48** | 5 |
| False, M1 to M9 and N1 to N10 (19) | 0 wrongly proved | none |

| Witness | Rev 1 B | Rev 2 | Facts | CPU s |
|---|---|---|---:|---:|
| P1 `w*(h*c) = (w*h)*c` | fail | proved, NF | 252 | no query |
| P2 regrouped value | fail | proved | 252 | 0.69 |
| P3 offset, buffer `h*(w*ch)` | fail | proved | 1241 | 3.96 |
| P4 `st=w*ch`, buffer `(w*h)*ch` | fail | proved | 1053 | 3.00 |
| P5 `ch=3` | fail | proved | 10 | 0.05 |
| P6 commuted aliases, any sign | fail | proved | 10 | 0.05 |
| W20 `3*w*h ≤ 2^63−1` | fail without F7 | proved | 12 | 0.06 |
| R3 four-plane total | fail | proved (F7b) | 355 | 0.98 |

**Which witnesses change.** Against Rev 1 B on the 38 true witnesses it can express: W20, P1 to P6 and R3 move from fail to proved. **No witness moved from proved to fail.** No false witness changes. For comparison, the review's hand-written equations gave P3 SAFE at 529 facts, 2.7 s (review). The generated form costs more, because it holds every binary split of every monomial.

W3, the crux, takes 32 facts and 0.10 CPU s. Over all 72 witnesses, the median is 0.11 CPU s and the total 115.9 CPU s. The largest is W22 at 19114 facts and 59.0 CPU s. A three-factor offset is about 1250 facts and 4 CPU s.

**2. The fixed set, against filters.** This is why the set has no alignment filter. Each row counts z3 results over the 53 true witnesses; no filter proved a false witness.

| Alignment rule | True proved | Lost against no filter | Total CPU s (`fixpoint`) | W22 CPU s |
|---|---:|---|---:|---:|
| **No filter (recommended)** | **48** | none | 119.1 | 61.1 |
| One side has equal degree | 48 | none | 95.3 | 43.1 |
| Equal degree, or one shared factor | 47 | **Q11** | not run | not run |
| Equal degree on both sides | 47 | **Q11** | not run | not run |
| Equal degree, and F5 on a shared factor | 46 | **Q10, Q11** | 21.3 on the first 64 witnesses | 5.8 |

Q10 is a row inside a wider stride, and Q11 is a padded stride with variable channels. Both are ordinary image layouts. So a filter that looks free on the original set loses real shapes, as the review said. The first two rows ran side by side, so they compare; this is why row one reads 119.1 and not the 115.9 of measurement 1. "One side has equal degree" saves 20% and loses nothing here. It is one more rule for an author to reason about, and it is not recommended. The user can choose it.

**Printing.** Each monomial printed once as an environment binder, with facts that name the binder, halves the cost against nested terms: 34.7 against 65.9 total CPU s on one filter and witness set, and 11.3 against 29.2 on W22. The cause in `fixpoint` was not located. z3 alone took 1.45 s on W22, so most of the cost is before z3.

**3. The recheck.** Native z3 on the normal-form constraint, with no facts. Three runs of each witness under `-T:2`.

| Claim | Result | Max wall s | Max `rlimit-count` |
|---|---|---:|---:|
| M1 to M9 (9) | `sat`, model validated, 9 of 9 | 0.038 | 7918 |
| N1 to N10 (10) | `sat`, model validated, 10 of 10 | 0.050 | 15074 |
| True (53) | `unsat` on 52; `timeout` on W23; **`sat` on none** | 0.162 on `unsat` | 186173 |

- **Reproduction of the review.** On the original (not normal-form) query with `:model_validate`: M1 to M9 all `sat`, at most 0.037 s (review: 0.048 s); 26 true `unsat`; W23 `timeout`; no true `sat`. W23 through `fixpoint --smtTimeout 2000` gave UNSAFE in 2.13 s (review: 2.23 s).
- **Validator controls.** Of 100 models with one value increased by 1, the check rejected 83, and 17 were still real counterexamples. On true W3, 5000 random valuations gave 0 accepted.
- **Deterministic limit.** Under `(set-option :rlimit N)` with no clock: at N = 200000 and N = 2000000, 19 of 19 false witnesses gave `sat`, and no true witness did. W23 gave `unknown` in 0.14 s and 2.02 s.
- **Noise.** M1 with 32 unrelated products in scope: `sat`, 0.034 s, validated.
- **Mixed theories.** N4 and N5 hold `bytesLen` and an array read. Both validate. No witness holds `strLen` or the two-array map encoding.

**4. Facts are true, and the generator is correct.**

- Each schema: native z3 gives `unsat` for the negation on `Int`. F5 gives `sat` on `Real`, as the review reported. Controls F5 without `b ≥ 0` and F7b without `b ≥ 0` give `sat`, so the check can fail.
- Each generated instance: 37248 facts across all witnesses, evaluated on exact integers with the product as `mul##nl`, up to `2^63`. 1301161 evaluations had a true premise. **0 failures.**
- Normal form against source: 96900 evaluations on the W, P, R, M and N witnesses without a function term, 0 differences.
- Hypotheses plus facts are satisfiable with `mul##nl` uninterpreted, for all 72 witnesses. So the facts add no contradiction on this set.

**5. Each mark site.** True claims that B cannot prove, of shape W23 or W25, one product position per row. Each is hand-built.

| Site | `fixpoint` | Marked | Recheck | Verdict | With no mark |
|---|---|---|---|---|---|
| Environment binder | UNSAFE | yes | `timeout` | fallback | false `refuted` |
| `lhs` | UNSAFE | yes | `timeout` | fallback | false `refuted` |
| `rhs` | UNSAFE | yes | `timeout` | fallback | false `refuted` |
| Callee post after substitution | UNSAFE | yes | `timeout` | fallback | false `refuted` |
| S9 definedness assumption | UNSAFE | yes | `timeout` | fallback | false `refuted` |
| Definedness goal | UNSAFE | yes | `unsat` | fallback | false `ill-defined` |
| Environment binder, W25 shape | UNSAFE | yes | `unsat` | fallback | false `refuted` |
| Control: no product, false | UNSAFE | no | `sat` | `refuted` | `refuted` |

**6. Names.** With `constant mul##nl`, a binder named `mul`, `mul_nl` or `m_0` gives a normal solver answer. Rev 1's `constant mul` beside a binder `mul` reproduced the "Multiple sorts" crash. `fixpoint-0.9.6.3.1` also accepts `mul##nl`.

**7. Scale.** The crux with K more product goals, under the fixed set.

| K | Pairs `T` | Facts | `fixpoint` result | CPU s | z3 alone, wall s |
|---:|---:|---:|---|---:|---:|
| 2 | 4 | 120 | SAFE | 0.33 | 0.03 |
| 5 | 7 | 357 | SAFE | 0.96 | 0.04 |
| 10 | 12 | 1032 | SAFE | 2.82 | 0.06 |
| 20 | 22 | 3432 | SAFE | 9.57 | 0.53 |
| 40 | 42 | 12432 | SAFE | 35.9 | 4.26 |
| 62 | 64 | 28800 | SAFE | 85.6 | 19.1 |
| 63 | 65, over the cap | 585 | UNSAFE, so fallback | 1.10 | 0.09 |

A product of more factors, or of longer sums, under the same set:

| Input | Monomials | Pairs `T` | Facts | `fixpoint` result | CPU s | z3 alone, wall s |
|---|---:|---:|---:|---|---:|---:|
| Monotone, degree 3 | 1 each side | 12 | 1080 | SAFE | 3.19 | not run |
| Monotone, degree 4 | 1 each side | 50 | 19114 | SAFE | 59.0 | not run |
| Monotone, degree 5 | 1 each side | 180, over the cap | 1620 | UNSAFE, so fallback | 2.32 | not run |
| `(a+b)*(c+d)` | 4 | 5 | 197 | SAFE | 0.88 | 0.03 |
| 3 terms × 3 terms | 9 | 9 | 621 | SAFE | 1.83 | 0.05 |
| 4 terms × 4 terms | 16 | 16 | 1968 | SAFE | 13.2 | 0.08 |
| 2 × 2 × 2 terms | 8 | 37 | 10437 | SAFE | 35.9 | 0.66 |
| 3 × 3 × 2 terms | 18 | 75, over the cap | 675 | SAFE | 30.6 | 0.05 |
| **3 × 3 × 3 terms** | **27** | 108, over the cap | 972 | **no result in 200 s wall (93.9 CPU s)** | | **0.07** |

**The last row is a hazard this revision found.** z3 alone answers in 0.07 s, and `fixpoint` gives no answer in 200 s, so the cost is before z3. It is in the long sum and not in the fact count: 3 × 3 × 2 has 675 facts and costs 30.6 CPU s, and W5b has 1241 facts and costs 3.9. **The cause was not located.** "Fact set" therefore caps expansion at 16 monomials. Before a further cap on written pairs, 3 × 3 cost 27.4 CPU s, against 1.83 with it.

The written-pair cap was added after the table in measurement 1 ran. A rerun under z3 gave the same result, `T` and fact count on all 72 witnesses, so the CPU column was not rerun.

**8. Slack products, a measurement row only (review, not rerun).** The RLT schema proved 33 of 34 in z3 alone, and gave no `fixpoint` result in 300 s at K=20, against 15.05 s for Rev 1 B on the same input. Its cause was not located. It is not in scope; see `MUL-SLACK-1`.

**9. Carried from Rev 1, not rerun.** Option A on two real files, seeds, and `--leanstral-mock`. The corpus count: of 2002 `.llmll` files on disk, 6 files hold 9 functions refused for `nonlinear:*`.

## Design proposal

### Surface

There is no new syntax. `(* a b)` already parses and type-checks as `int → int → int` (`compiler/src/LLMLL/TypeCheck.hs`), and no float form exists. JSON-AST does not change. A contract may now use it, and under decision 3 so may a `def` body.

```lisp
(def pixel-offset [w: int h: int y: int x: int] -> int
  (pre (and (>= y 0) (and (< y h) (and (>= x 0) (< x w)))))
  (post (and (>= result 0) (< result (* w h))))
  (+ (* y w) x))
```

### Semantics

Evaluation does not change. `int` lowers to Haskell `Integer`, and `*` is total on it. So `*` has no definedness entry under `CLAUSE-WELLDEF-1`, and a partial read inside a factor keeps its own obligation. No state is added, and `mul##nl` exists only in the VC, so strict immutability holds.

### Normal form

The form applies to a constraint that holds a product of two non-constant terms. Any other constraint is printed as today, so its text does not change.

1. **Atoms.** An atom is a variable, a function application, or `(/ e k)` with `k` a positive ground constant. `e` and each function argument are in normal form themselves.
2. **Polynomial.** Every integer term is expanded to a sum of `c · m`, with `c` an integer and `m` a monomial, a sorted multiset of atoms. So commutativity, associativity and distribution hold by construction. `(* w (* h c))` and `(* (* w h) c)` are one term. F6 of Rev 1 is removed, because no sum remains inside a product.
3. **Symbol.** A monomial of degree 2 or more prints as a left-nested application in ascending atom order: `mul##nl(mul##nl(a, b), c)`. The ground order is the order of the printed atom.
4. **Binder.** Each distinct monomial is one environment binder, `m##k`, with refinement `v = mul##nl(...)`. Facts and clauses name the binder.
5. **After substitution.** The form applies after callee-post substitution, so a caller's terms and a callee's terms meet.
6. **A goal that reduces to a constant.** liquid-fixpoint refuses `rhs (0 = 0)` and `rhs true` with "RHS without single conjunct" (measured on P1). If the goal reduces to true, the emitter sends no constraint for it and the clause is proved. If it reduces to false, the emitter sends `rhs false`, and the verdict rule applies (N9).
7. **A conjunct that reduces to true** in a larger goal is dropped.

**Equation resolution.** Regrouping through a name needs this, because `st` in `y*st` is an atom.

- The emitter reads each **top-level** equation of the constraint: a conjunct of a binder refinement, in `conEnv` order, then of the `lhs`.
- If one side of the equation is a single atom with coefficient 1, and that atom is not a division, the atom resolves to the other side, after earlier resolutions.
- It tries the left side first. It skips an atom that already resolved, or one that occurs in the other side. So the map has no cycle.
- An equation in a disjunct or under an implication is not read. Q9 shows the cost.

This gives `σ`, the resolved form of each monomial. `σ` does not change a clause. It only decides which facts exist, so no fact depends on a path.

### Fact set

**This set is normative. It is part of the language surface, and it decides which programs verify.** A fact is a hypothesis in the `lhs`, flat, as `FQ-FLAT-NEST-1` requires. Let `P`, the pair set of a constraint, be:

- each product `(* a b)` as written, after `σ`, where neither side is constant and the product expands to at most 4 monomials; and
- each binary split `(A, B)` of each monomial after `σ`, recursively, up to degree 6.

| Fact | Statement | Instances | Certificate |
|---|---|---|---|
| F1 sign | `a ≥ 0 ∧ b ≥ 0 ⟹ ab ≥ 0`; `a ≤ 0 ∧ b ≥ 0 ⟹ ab ≤ 0` | each pair, both orders | sign |
| F2 zero, one | `a = 0 ⟹ ab = 0`; `a = 1 ⟹ ab = b` | each pair, both orders | ring |
| F3 growth | `a ≥ 1 ∧ b ≥ 0 ⟹ ab ≥ b` | each pair, both orders | `(a−1)·b ≥ 0` |
| F4 monotone | `a ≤ c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ ab ≤ cd` | ordered pairs, 4 alignments, no filter | `(c−a)·b + c·(d−b)` |
| **F5 row** | `a < c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ ab + b ≤ cd` | ordered pairs, 4 alignments, no filter | `(c−a−1)·b + c·(d−b)`, **integers only** |
| F7 literal bound | `⋀ (0 ≤ aᵢ ≤ Aᵢ) ⟹ m ≤ ∏Aᵢ` | each monomial whose atoms all have a top-level literal upper bound, `Aᵢ ≥ 0` | F4 at constants |
| F7b literal comparand | `a ≤ K ∧ b ≥ 0 ⟹ ab ≤ K·b`; with `K ≥ 0`, `a ≥ K ∧ b ≥ 0 ⟹ ab ≥ K·b` | each pair with a single-atom side that has a top-level literal bound | `(K−a)·b ≥ 0` |
| F8 square | `aa ≥ 0` | each pair with equal sides | square |
| F9 link | `E ⟹ m = σ(m)`, where `E` is the conjunction of the equations that `σ` used | each monomial, division or application that `σ` changes | congruence |

**A fact whose premise is a true constant loses that premise. A fact with a false constant premise, or a true constant conclusion, is dropped.** There is no other filter.

**The caps.** Each is part of the set, and measurement 7 gives the cost on each side.

- **Written pairs, 4 monomials,** as above. A longer sum keeps its splits and loses only the pair as written.
- **Pairs, 64.** If `|P| > 64`, F4 and F5 are omitted for that constraint. The other facts stay. `fixpoint` reached 85.6 CPU s at 64 pairs.
- **Expansion, 16 monomials.** A single product that expands to more than 16 monomials is refused with `nonlinear:*`, as today, because 27 monomials gave no `fixpoint` result. The prototype does not apply this cap: it is the rule that measurement 7 implies, and the inputs over it were run to show why.
- **Degree, 6.** A monomial above degree 6 gets no splits. No witness reaches it.

The message names any cap that applied (see "Messages").

F6 is gone. The review's proposed cross congruence and literal factor are F9: the first resolves `a` to `d` and `b` to `c`, and the second resolves `ch` to 3.

**Termination.** `σ` has no cycle. A split makes strictly smaller monomials. F4, F5 and F9 add no new product to `P`. So generation ends.

**F5 is what the crux needs.** `y*w + x < y*w + w ≤ h*w` is linear once F5 gives the second step. Rev 1's C′ had F1 to F4 and failed W3.

**Changing the fact set.** This answers review question 2.

- A change is a language change. It needs a CHANGELOG entry, a rerun of the witness table, and `scripts/fallback_census.py`, and a test holds the family counts on W3, P3 and W22 at their stated values.
- An **added** fact can only add proofs. A **removed** fact can move a program from `verified` to fallback.
- Neither needs `checker_soundness_version`, because each fact is a theorem. A `verified` sidecar written under a larger set stays true.
- A fallback is not a positive record, and `refuted` is not persisted (`compiler/src/LLMLL/VerifiedCache.hs`). So a stale result is at worst `asserted` until the next run, which is the safe side.
- A replay runs the stored VC with its stored facts, so an older artifact replays unchanged, if its soundness stamp matches.

### The mark

`mul##nl` has no call binder, so `abstracted` and `cbAbstractable` cannot see it. A new scan is needed, and it reads the constraint as emitted, not the source:

```
productMarked c  ⟺  mul##nl ∈ ⋃ { predSymbols p | p ∈ refinements (conEnv c) ∪ {conLhs c, conRhs c} }
```

- **Every site.** After emission, a program term can only be in an environment binder, the `lhs` or the `rhs`. A callee post after substitution, an S9 assumption and a `let` are binders or `lhs` conjuncts. A definedness goal is an `rhs`. So this one walk covers each site by construction, with no per-site code. Measurement 5 holds a witness for each.
- **`predSymbols` is total** over the predicate forms, and it includes kvar arguments. No emission site in `compiler/src/LLMLL/FixpointEmit.hs` builds an `FQKVar` today, so no product can reach a constraint through a kvar solution.
- **`sanitizeFQId` must not rewrite the symbol.** `predSymbols` and `emitPred` both call it, and it would give `mul__nl`, a name that source can spell. The reserved symbols need a path past it, and `FQ-FREEVAR-GUARD-1` must treat them as declared.
- **Scan after the fact pass, over the kept constraints,** beside `abstracted` and `postUnassumed`.
- **The mark is coarse.** It reads the whole environment, as those two do. So a linear bug beside a product is marked. The recheck is what keeps that bug `refuted` (N6, N7).

**A second wrong verdict, found in this revision.** Rule 1 of `applyAbstractionVerdict` makes an id a candidate only when its function is body-faithful. `aoIllDefined` and `aoMeasureBad` come from `hardFns`, which has no such test. So a marked definedness id in a function with a fallback body would be a hard id. A true clause holding a product in a `def-shell` would then give a **false `ill-defined`, exit 1**. This reading is from the code; no run reached it. So for the product mark, **candidacy does not need a body-faithful function.** The other marks keep their rule. A test needs a `def-shell` with an untranslated body and a clause whose definedness goal has shape W25.

A marked id with no origin must not exist. A test asserts that each constraint holding `mul##nl` has an owner.

### Verdict and recheck

This is the formal form of the review's illustrative rule. For each failing id of an UNSAFE answer:

| Id | Recheck | z3 answer | Result for the id |
|---|---|---|---|
| Not product-marked | none | n/a | as today |
| Product-marked, and another mark as well | none | n/a | keeps its marks, as today |
| Product-marked only | yes | `sat`, model validated | **the product mark is removed**, so the id is complete |
| Product-marked only | yes | `sat`, model fails validation | keeps the mark, and an internal warning names z3 |
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

So the off-by-one M1 is `refuted`, and an off-by-one in a `bytes-get` call-pre reports `refuted` by the same route, because its id is in the truth partition. A wrong bound in a clause is `ill-defined`. N6 shows that a linear bug in a caller stays `refuted` when a callee post brings a product in. That is the regression the review named.

**What is checked.** The query holds the failed constraint's environment refinements, its `lhs` without the F facts and F9 links, and the negated `rhs`. `mul##nl` prints as `*`. The other ground-fact families (`measure-nonneg`, `byte-range` and others) stay, because they are part of what a program value can be. Product facts are dropped, because under `*` they are theorems and add nothing.

**What `sat` is validated against.** The compiler asks `(get-value ...)` for each variable and each function application in the constraint. It then evaluates, in its own `Integer` arithmetic:

1. every hypothesis, which must be true;
2. the goal, which must be false;
3. each product as exact multiplication, and `(/ e k)` as Haskell `div`; and
4. function consistency: two applications of one function with equal arguments must have equal results.

Any failure, or a value it cannot read, gives the mark back. This check does not use z3's `:model_validate`, so its truth does not depend on z3. A false `refuted` then needs a false VC, which is a defect today as well.

**The limit.** `(set-option :rlimit 2000000)`, plus a 5 s process guard. A clock limit makes `refuted` depend on machine load; `rlimit` does not, on one z3 version. 2000000 is 132 times the largest count on a false witness (15074). W23 reached `unknown` in 2.02 s. The rlimit unit may differ on z3 4.8.12: **not run.**

**The budget.** A function rechecks at most 8 failing ids, in id order, and stops at its first validated id, because one complete id is enough. The time counts under `--time-limit`. Beyond 8, ids keep the mark.

**What `refuted` means.** This answers review question 1. If the constraint also holds `strLen`, `bytesLen` or `Map_select`, a `sat` model interprets that function too. That is the same meaning as a QF-LIA UNSAFE over those symbols today: the VC has a countermodel, with the function free apart from its stated facts. The recheck removes the `*` abstraction and adds no other. So `refuted` keeps its meaning. Clause 1 and clause 2 marks stay separate and block the recheck, because they name an abstraction the query cannot remove. The translator must extend `fqPredToSMT` past its abstention on function terms. Where it cannot translate a term, it abstains, and the id keeps the mark.

**A `sat` varies by z3 version; a `verified` does not.** A weaker z3 can only lose a refutation. CI must not assert `refuted` on a z3 where it was not measured.

**Replay.** A function's artifact records the outcome as today, with no new enum value. A replay of a rechecked `refuted` reruns the recheck on the stored VC. If it does not reproduce, it fails closed (`classifyReplay`).

**Report the model.** `LLMLL.md:13-14` says that no counterexample input is printed. A validated model is a real one, so the `refuted` text should print it, for example `counterexample: h=25 w=21 x=21 y=24`. JSON does not change. The engineer can take this or leave it.

### Messages

**Callee, at `verify`.** `W-BODY-FALLBACK` names the term and what the recheck found:

```
W-BODY-FALLBACK f: the post is not proved. A product is in the failing constraint.
  Refused by: abstraction:nonlinear:*   at <JSON pointer>
  Product facts did not prove it. Native z3 found no counterexample (<unsat | limit | abstained>).
  The post stays a run-time check. A strict-core def that calls f will be refused.
```

Over the pair cap, the second line becomes "this constraint holds 65 product pairs; the limit is 64, so monotonicity facts were not added".

**Caller, at core admission.** Today, `check` refuses a product in a `def` at once. After decision 3, a `def` with an unprovable product passes `check`, falls back at `verify`, and then causes `core-membership-violation` at its callers. `mkCoreMembershipViolation` keeps its kind and gains a variant with the cause:

```
def 'c': callee 'f' is not body-faithful, because verify fell back on a product at <JSON pointer>
  (abstraction:nonlinear:*). Only verified functions are admissible in strict-core bodies.
Suggestion: restate f's post, supply evidence with ?proof-required, or write 'c' as a def-shell.
```

Core admission reads persisted evidence. If the sidecar does not hold the fallback construct, it must carry it for this text. The engineer confirms this.

### Disclosure

Add the family `product-facts` to `ground_fact_families`. `LLMLL.md` §13.12 goes from four families to five, with the statement of the set. No new `assumed_facts` kind and no increase of `trust_report_version`. A test checks each schema by native z3, as measurement 4 does, once and not per program. `verified` stays `verified`, with no cap.

### Lean worklist

`runLeanstralPipeline` selects a fallback function with `isNonLinear b`. `isNonLinear` stops flagging a two-variable `*`, for the same reason that it stopped flagging `(* 8 r)`. So W14, W23 and W25 would leave the list. **Select from the outcome:** a function in the fallback set whose construct is `abstraction:nonlinear:*`, or whose body holds a remaining nonlinear operator.

`nlPreH` and `nlPostH` in `compiler/src/LLMLL/HoleAnalysis.hs` then stop creating a `non-linear-contract` hole for a product. A static hole on W3 would be noise, because B proves it. The `TypeCheck` warning on an explicit `?proof-required` keeps its form, and its text must stop saying that QF-LIA cannot discharge it when the operator is `*`.

### Spec text

**`Σ_auto` does not widen.** `LLMLL.md:13-14` defines `Σ_auto` by a complete decision, and neither statement holds for a term with `mul##nl`. QF-UFLIA is decidable, but the solver then decides the abstraction and not the property. So §5.3.3 gains a separate class. Draft for the documentation-lead:

> **Abstracted products — sound, not complete.** A product of two non-constant `int` terms is normalized and reflected to an uninterpreted symbol, with a fixed set of ground theorems of integer multiplication. The solver's question is decidable, but it is a question about the abstraction. SAFE is a proof of the property, resting on `int-unbounded-1`. UNSAFE is not: the function is `refuted` only when an interpreted solver query gives a model that an exact-integer evaluation confirms, and otherwise it falls back. Nothing here is outside the trust of `verified`. No class of programs is claimed complete. The witness table is the coverage evidence. Nonlinear integer arithmetic remains undecidable (Matiyasevich 1970).

The review's answer to Rev 1's open question stands: **no fixed one-round ground set is known to be complete for a natural bilinear class.** This record claims none, and it keeps "sound and incomplete".

### What B does not prove

| Witness | Claim | Why | What the author can do |
|---|---|---|---|
| W14 | `4·cw·ch ≥ w·h` | needs `w ≤ 2·cw` scaled into a monotone fact | fallback; `?proof-required` |
| W23 | `x² ≠ 2y²` | irrationality; no local fact reaches it | fallback; Lean route. Native z3 also does not decide it |
| W25 | `(a+b)² ≥ 4ab` | needs `(a−b)² ≥ 0`, and F8 sees only written squares | fallback; restate as `(a−b)*(a−b) ≥ 0` |
| Q8 | `a≤d ∧ d≤a ∧ b≤c ∧ c≤b ⟹ ab = cd`, any sign | the equality is derived, not written, so no F9 | write `(= a d)` |
| Q9 | an equation inside a disjunct | `σ` reads top-level equations only | split the branch |

Native z3 proves W14, W25, Q8 and Q9. Each of these reports fallback, with "no counterexample". A new true fact can only add proofs, so each can be added later, under "Changing the fact set".

### Option comparison

**A. Native `*` as the proof engine.** It has no new facts, and it costs almost nothing (Rev 1: at most 0.086 s per decided witness). Its costs are version dependence, `--smtTimeout` with a false UNSAFE, and `replay-artifact` having to reproduce a nonlinear result. The recheck takes its strength as a refuter without any of those.

**Rev 1's C, C′, D and E, carried and not rerun.** C, a named product with no facts, proved 2 of 27. C′, the row's wording, proved 6 of 27 and failed every offset witness. D, the Lean path: `verify --leanstral-mock` says "not verified (fail-closed)", the real path was not run, and `LeanTranslate` rejects `/`. It stays the route for W23. E, the cursor pattern, gives no seek and no stated size.

### Design-reference set

Sources are from the review's search unless marked. Cimatti and others, incremental linearization: TOCL 19(3), 2018, and for NIA SAT 2018. That method is a refinement loop over a linear abstraction. **This design has no refinement loop.** It is related in that it adds true lemmas to an abstraction, and in no stronger way. This record makes no claim about that work's lemma names, because they were not confirmed. Dafny `--disable-nonlinear-arithmetic`: its man page says more manual work and more predictable. Verus `by(nonlinear_arith)`: default mode disables nonlinear theories, and the query is separate, which is the shape of the recheck. Sherali–Adams RLT: `MUL-SLACK-1` only. Handelman 1988 (Pacific J. Math. 132(1), pp. 35-62): the review confirmed the record from secondary sources and not from the paper, so it is secondary here. It concerns compact polytopes, and `w` and `h` are unbounded.

Matiyasevich 1970, searched in this revision: *Enumerable sets are Diophantine*, Doklady Akad. Nauk SSSR 191, pp. 279-282; English in Soviet Mathematics 11(2), pp. 354-357 ([MacTutor](https://mathshistory.st-andrews.ac.uk/Biographies/Matiyasevich/), [mathnet](https://mathnet.ru/eng/im1910)). The result depends on Davis, Putnam and Robinson, and is often called MRDP.

Local fact, in this revision: `fixpoint --help` on 0.9.6.3.7 prints "`--linear`: Use uninterpreted integer multiplication and division". The review reported no description, and that is corrected here. This record makes no claim about any Liquid Haskell flag.

## Edge cases and degenerate inputs

1. **Positive witness for the recheck.** M1: `(>= y 0)`, `(< y h)`, `(>= x 0)`, `(<= x w)`, post `(< (+ (* y w) x) (* w h))`. `fixpoint` UNSAFE, marked, native `sat`, validated. `refuted`, exit 1. Channel: contract.
2. **Positive witness for the mark.** W23 at each site of measurement 5. `fixpoint` UNSAFE, marked, native not `sat`. Fallback, exit 0, not `refuted`. Channel: trust.
3. **Negative factors.** M5, `(>= (* w h) 0)` with no `pre`. F1 does not fire. Native `sat`. `refuted`, which is correct at `w=-3`. Channel: contract.
4. **Zero extents.** `w=0` in W3's `pre` has no solution, because `0 ≤ x < w` fails. F2 gives `w*h = 0`. Channel: contract.
5. **A constant factor.** `(* 3 w)` is not a product of two non-constants. The `.fq` stays byte-identical, and UNSAFE stays `refuted` with no recheck. Channel: contract. Citation: `SIGMA-CONST-ARITH-1`.
6. **A `let` constant.** `(let [(ch 3)] (* (* w h) ch))`, as P5. F9 links it. Channel: contract.
7. **A partial read in a factor.** `(* (map-get m k) w)` in a post. `mul##nl` adds no obligation, and `map-get` keeps its `wd-post`. The atom's value is an integer, so each fact holds. Channel: contract. Citation: `CLAUSE-WELLDEF-1`.
8. **A callee post with a product.** `(post (= result (* w h)))` at `(area a b)`. The caller assumes `result = mul##nl(a, b)`, after substitution. A linear bug in that caller stays `refuted` (N6). Channel: contract.
9. **A goal that is an identity.** P1. The normal form proves it, and no constraint is sent. Channel: contract.
10. **A goal that is a false constant.** N9, `(< (* w h) (* h w))`. `rhs false`, UNSAFE, native `sat`, `refuted`. Channel: contract.
11. **A product in `decreases`.** It stays refused: descent is proved over exact terms. Channel: contract. Citation: `LLMLL.md` §5.3.
12. **A parameter named `mul` or `mul_nl`.** No collision (measurement 6). A test holds it. Channel: spec is silent (intentional).
13. **Over a cap.** 65 pairs: F4 and F5 are omitted, and a claim that needs them falls back, with a message naming the cap. `(a+b+c)*(d+e+f)*(g+h+i)`: refused with `nonlinear:*`, as today. Channel: trust.
14. **Machine integers.** Under any codegen with a fixed-width `int`, F1, F3, F4, F5 and F8 are false. The stamp `codegen_semantics_version` covers this, and this family must follow it. Channel: trust.
15. **A float product.** No float `*` exists. A future one must not receive F5, which needs integrality: `a=0, c=½, b=d=1` breaks it. Channel: type.
16. **A kernel `out-len`.** `(out-len (* w h))` stays refused. A caller can now prove `(= npix (* w h))` and pass `npix`. Channel: type. Citation: `docs/design/ffi-buffer-proposal.md`.

## Verification mapping

| Obligation | Channel | Fragment | Citation |
|---|---|---|---|
| A contract or body VC that holds `mul##nl` | contract | **(b) nonlinear, with surface-form restriction: a decidable encoding (QF-UFLIA) of an undecidable class.** Not (a): it does not join `Σ_auto`, and it is not complete | `LLMLL.md` §5.3.3 |
| The truth of each fact | not an obligation | Each schema is checked once, in a test | "Soundness" |
| A failed constraint's recheck | none: it can only remove a mark | QF-NIA, used for `sat` only | "Verdict and recheck" |
| A claim that the facts cannot reach | trust | (b): falls back. (c) `?proof-required` is available, and the Lean path stays experimental | `LLMLL.md` §5.3.5 |
| Variable divisor | outside this record | (b), refused as today | `DIV-VAR-1` |

### Soundness

**SAFE.** Each fact is a theorem at every integer valuation, with `mul##nl` read as `*`. Take that standard model. If `H ∧ F ⟹ G` is valid, then `F` is true there, so `H ⟹ G` is true. So no path condition is needed for a fact, and short-circuit context does not matter. EUF congruence is true of `*`.

**The base.** The facts rest on `int-unbounded-1`: `*` is exact `Integer` multiplication. A machine-integer codegen would make F1, F3, F4, F5 and F8 false. **F5 is integer-only.** Its certificate needs `a < c ⟹ c−a−1 ≥ 0`.

**Reach.** The normal form uses ring identities only, so it does not change the value of a term. `σ` adds facts and does not rewrite a clause, and F9 carries its premises, so it is true with no hypothesis. `*` is total, so it has no WD entry. `mul##nl` has no call binder, so the call counts of `CALL-CONGRUENCE-1` and clause 2 do not apply.

**`refuted`.** The exact-integer check confirms that the valuation satisfies the VC's hypotheses and falsifies its goal. So it adds nothing to the trust base beyond the VC being faithful, which every `refuted` needs today.

**Trust.** The facts add nothing to the sealed-builtin axioms. Their family is disclosed.

## Affected surface

This is an addition to the reflected fragment. Its soundness argument is above.

- `compiler/src/LLMLL/FixpointEmit.hs`: the `*` arms of `exprToPredWD` and `bodyToPredM`; the normal form, `σ`, the fact pass and the binder pass; the `productMarked` scan; the `nonlinear:*` label stops applying to `*`.
- `compiler/src/LLMLL/FixpointIR.hs`: a way past `sanitizeFQId` for the reserved symbols, in `emitPred` and `predSymbols`; the free-variable guard.
- `compiler/src/LLMLL/AbstractionVerdict.hs`: the product mark, the candidacy rule, the recheck's removal of a mark before rule 1.
- A recheck module, or `compiler/src/LLMLL/Feasibility.hs`: the translator, the limit and the exact-integer check.
- `compiler/src/LLMLL/Syntax.hs`: `isCoreBodySyntactic`, under decision 3. `LLMLL.md` §12 `core-expr` moves with it.
- `compiler/src/LLMLL/HoleAnalysis.hs`, `compiler/src/LLMLL/TypeCheck.hs`, `compiler/app/Main.hs`: "Lean worklist".
- `compiler/src/LLMLL/Diagnostic.hs`: "Messages".
- `compiler/src/LLMLL/TrustReport.hs`: the family only.
- **Fixtures that exist to show the refusal move to a claim B cannot prove** (Rev 1 list, not rechecked): `examples/leanstral-demo/square.llmll`, `scripts/doc-claims/nonlinear-body-fallback.llmll`, `scripts/tests/fixtures/fallback-census/census-constructs.llmll`, `scripts/tests/fixtures/fallback_attrib/attrib.llmll`, with `scripts/tests/test_fallback_attrib_1.py`, `scripts/tests/test_fallback_census.py` and `compiler/test/Spec.hs`.
- `LLMLL.md` §0, §5.3.3, §5.3.4, §5.3.5, §12, §13.12; `docs/getting-started.md`; `docs/compiler-team-roadmap.md`; `docs/design/INDEX.md`. These are the documentation-lead's.
- **Versions.** A VC with no product is byte-identical, which the first step must prove with a sweep. `checker_soundness_version` keeps its value, because no recorded verdict can stop being true: this is an argument, for the engineer to confirm. `proof_artifact_version` keeps its value, because no enum value is new. `trust_report_version` keeps its value (decision 4). A caller of a callee with a product post gets a new VC, because that post was not assumed before. Its verdict can move, in a known direction, from `callee-post-unassumed` toward `verified`.

## Ship order

This row depends on nothing unshipped. Its first step is the 4.8.12 run (decision 6). Its second is the same witness table through `llmll verify`, and the Y4M and netpbm contracts restated. It should land before the library's contract surface is written against `npix`.

## Not run

| Item | What it needs |
|---|---|
| **Any witness or VC through `llmll verify`** | an implementation; first implementation step |
| **z3 4.8.12, for B, the recheck and the rlimit unit** | the user's permission to obtain that version, or a CI run of `rev2.py`. An earlier download was denied, and this revision did not try again |
| `strLen`, two-array map encoding, opaque sorts in the recheck | an implementation of the translator |
| Y4M and netpbm contracts restated | an implementation |
| The false `ill-defined` path in `applyAbstractionVerdict` | a code reading only; no run reached it |
| Real path context, `let` binders and mixed theories at scale | an implementation |
| `scripts/fallback_census.py`, the byte-identical sweep | an implementation |
| Lean path | an API key and a Lean project (Rev 1) |
| Option A's stability, seeds and real files, on this revision | carried from Rev 1 |
| CPU for the middle two filter rows in measurement 2 | not run: their z3 counts already showed a lost witness |
| The expansion cap in the prototype | it is stated from measurement 7; implement and rerun |
| A long hypothesis that no single product causes | a new witness; first implementation step |

## Risks and open questions

1. **The witness set is still written by this team.** Scope. Two independent passes each found gaps: the review's P set found regrouping, and this revision's Q10 and Q11 found padded strides and overturned the filter that looked best. Expect more from real contracts. Complicates: a miss gives a disclosed fallback, and a new fact can only add proofs. The Y4M and netpbm restatement is the next test.
2. **`fixpoint` cost on long sums.** Decidability in practice. The 3 × 3 × 3 input gave no result in 200 s, with z3 alone at 0.07 s and the cause not located. The expansion cap removes that input and no witness. A different long hypothesis, such as a sum of many separate products, could reach the same cost, and this revision did not test one. `--time-limit` stays the outer bound, and it then gives no verdict for a whole file. Complicates: the record cannot claim that B never stalls. The first implementation step must test this.
3. **Fact cost.** Verification-ergonomics. A three-factor offset is about 4 CPU s per constraint on a loaded machine, and a function holds several constraints. The default `--time-limit` is 120 s for a file. Complicates, at scale. Rev 1 had 530 facts at 0.916 s on W26; W26 here is 494 facts at 1.79 CPU s under load. z3 alone is far faster, and the cost is in `fixpoint`, for a cause not located. `MUL-SLACK-1` covers this.
4. **`refuted` varies by z3 version.** Verification-ergonomics. A weaker z3 loses refutations. Decision 6 measures this. Blocks: only if 4.8.12 loses most of them, and then decision 2 must be reopened.
5. **Equation resolution reads conjunct order.** Verification-ergonomics. `σ` is a function of the order of `conEnv`. Two orders can give different facts, and so a different verdict, on a program whose equations overlap. No witness shows a difference; none was built to look for one. Complicates: the emitter must keep the order stable, and a test should reverse the equations on the witnesses.
6. **Hand-built VCs.** Scope. The emitter's real shape was approximated. Complicates: the first step repeats the table.
7. **A native `unsat` is thrown away.** Verification-ergonomics. W14, W25, Q8 and Q9 are true, z3 says so, and the program falls back. This is the price of keeping `verified` free of the nonlinear engine. Decision 1 names the alternative.
8. **The Lean demo loses `square`.** Scope. A new example is needed, such as W23.

### Proposed rows, not filed

**`DIV-VAR-1`** (no contract can state a division or `mod` by a variable). An image library needs `(/ i w)` and `(mod i w)` to turn an offset into coordinates, and `(/ (* x sw) dw)` for nearest-neighbour resize. Haskell `div` and SMT `div` agree only for a positive divisor (`LLMLL.md` §5.3.3), so this needs a proved `divisor > 0`, a definedness entry under `CLAUSE-WELLDEF-1`, and its own facts. Rev 1 measured three witnesses SAFE and one false variant UNSAFE under Option A.

**`MUL-SLACK-1`** (measurement only, not in scope for this release). Why is `fixpoint` far slower than z3 on large arithmetic constraints? Three inputs show it: the RLT slack-product schema (review), the fact set at scale, and a long sum. The schema proved W14, W20 and W25 in z3 (review). If the cause is removed, the schema gives a statable certificate class, and risks 2 and 3 become smaller.

## Open questions for the professor

None. The review's two open questions are answered in "What `refuted` means" and "Changing the fact set". z3 4.8.12 is a measurement, not a question.
