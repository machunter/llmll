---
name: mul-var-rev2-professor-review
title: "Professor review of MUL-VAR-1 Rev 2"
status: "Review of Rev 2 DRAFT at commit 14cc57f9. Standalone. Not folded. Settles nothing."
date: 2026-11-07
author: professor
reviews: docs/design/mul-var-proposal.md
---

# Professor review of MUL-VAR-1 Rev 2

**Verdict: settle with listed amendments.** All six decisions can settle. The normative parts (normal form, fact set, caps, validator) can settle only in the amended form A1 to A5 below. I found no false proof and no false `refuted` that the design causes.

**Four findings block the text as written:**

1. The verdict changes when an author swaps two conjuncts or renames a variable.
2. The record did not locate the `fixpoint` stall, and its 16-monomial cap has the wrong shape. The cause is the `fixpoint` parser. A kernel of 25 separate products passes the cap and stalls.
3. Equation resolution has no size limit, and the solver guard does not cover it.
4. The atom list and the validator do not cover terms that the emitter really prints.

**Separate from this record, and more urgent:** v0.37.0 proves a false program today, because `a-b` and `a_b` print as one symbol (S1).

## How to read the evidence

- **RAN (solver):** my scripts, which import the team's `nf.py` unchanged. They use hand-built VCs, z3 4.15.4 and liquid-fixpoint 0.9.6.3.7. Load average was 8 to 100.
- **RAN (released):** programs through `llmll` 0.37.0, a copy of the main checkout's build. None of these programs reaches a two-variable product proof, because 0.37.0 refuses that product.
- **READ:** a code reading, with no run.
- **CI REPORT:** the z3 4.8.12 file from the coordinator. I checked it as a report and did not reproduce it.

**Nothing in this review with a two-variable product went through `llmll verify`.** The scripts are `prof2_*` in the session scratchpad folder `mulvar`, and they are not committed.

## Restatement

Rev 2 prints a product as a polynomial over atoms, with one uninterpreted symbol for each monomial. It adds a fixed set of ground theorems to each constraint that holds a product. On UNSAFE, it asks native z3 for a model, checks that model in exact integers, and reports `refuted` only if the check passes. A native `unsat` never gives `verified`.

## Context located

1. `docs/design/mul-var-proposal.md` Rev 2 and `docs/design/mul-var-professor-review.md`: the artifact and my earlier review.
2. `compiler/src/LLMLL/AbstractionVerdict.hs:197-226`: candidacy and `hardFns`. `aoRefuted` has a faithful filter at `:199`, and `aoIllDefined` has none at `:197`.
3. `compiler/src/LLMLL/FixpointEmit.hs:1669-1671`: a refused pre emits no definedness constraint.
4. `compiler/src/LLMLL/FixpointEmit.hs:1703`: `wdPreHyps` holds parameter facts only.
5. `compiler/src/LLMLL/FixpointIR.hs:339-349`: `FQAnd` prints flat under `FQ-FLAT-NEST-1`, and `FQBinArith` still prints nested.
6. `compiler/src/LLMLL/FixpointIR.hs:292-293,312`: `sanitizeFQId` and its "deliberately accepted" collision comment.
7. `compiler/app/Main.hs:1654,2453,3031`: the three callers of the pure `applyAbstractionVerdict`.
8. `docs/llmll-verify.schema.json:56`: `abstraction_fallback` has the pattern `^abstraction:app:`.
9. `compiler/src/LLMLL/PatchApply.hs:723`: the message for this cause says "two calls".
10. `compiler/src/LLMLL/DiagnosticFQ.hs:366-371`, `compiler/src/LLMLL/SolverGuard.hs:66`: a resource stop fails the whole file; the default limit is 120 s.
11. `compiler/src/LLMLL/Feasibility.hs:1-30`: the refine gate fails open, and it uses `fqPredToSMT`.
12. `examples/y4m/raster.llmll`, `examples/netpbm-swarm/kernel.llmll:44`: the source of the new witnesses.
13. `LLMLL.md:13-14`: the meaning of `refuted`.

## Answers to the seven questions

### Q1. Soundness of the normal form: no false proof found

Differential fuzz (RAN, solver, `prof2_fuzz.py`, `prof2_fuzz_b.py`). Each random VC has division by 1, 2, 3 or 7, negative values, and equations at the top level, in a disjunct or under an implication. A proof is compared with an exhaustive integer search over `[-6,6]^4` and with native z3.

| Cases | Proved by facts or normal form | Proved with an integer counterexample | Proved while native gives `sat` | Native `sat`, validated | Validated model that an independent evaluator rejects |
|---:|---:|---:|---:|---:|---:|
| 900 | 180 | **0** | **0** | 700 of 700 | **0** |

The cases come from 2 finished runs of two generators. The second generator is biased toward provable goals. The search box is small, so this shows no failure and proves nothing general. A separate evaluator, not the prototype's, checked each model.

- **Division.** `fixpoint` gives `(-3 / 2) = -2` and `(-3 mod 2) = 1`, equal to Haskell `div` and `mod` (RAN, `prof2_cap/d.fq`). `(/ x -2)` is refused on 0.37.0 (RAN, `t11`), so a negative divisor does not reach the normal form.
- **Shadowing.** `let [(w (+ w 1))]` emits `_bv_w_0`, so the names stay apart (RAN, released). Shadowing does not reach `σ`.
- **Name capture.** A file with `m` at two sorts beside a binder `m##1` gave a normal answer (RAN, one file). This does not prove that no capture exists, because I did not read the renaming code in liquid-fixpoint.
- **Reasoning.** My argument for facts and F9 is the same as the record's. Each fact is true in the standard model, and each F9 carries its premises.

**One order rule is missing (READ).** A cancellation can delete a refused term: `(* 0 (/ x y))` and `(- (/ x y) (/ x y))` both reduce to 0. So the refusal scan must run on the source term before expansion. Otherwise a post can verify with a term that stops at run time when `y = 0`. The prototype cannot express this input, so this is not run.

**S1, an existing false proof, not caused by this record (RAN, released):**

```lisp
(def collide [a-b: int a_b: int] -> int (pre (>= a-b 1)) (post (>= a_b 1)) 0)
```

`llmll verify` on 0.37.0 gives exit 0, `all_proved: true`. `(collide 1 0)` satisfies the pre and violates the post. The emitted VC has `bind 0 a_b`, `bind 1 a_b`, `lhs (a_b >= 1)`, `rhs (a_b >= 1)`. The comment at `compiler/src/LLMLL/FixpointIR.hs:312` says that the collision fails closed. This witness shows that it does not. File this as a G1 soundness row, and ship it first. It also affects the atoms of this design, because an atom key is a printed name.

### Q2. Soundness of the refuter: no false `refuted` beyond today's meaning

**The dropped-hypothesis route is closed (RAN, released; READ).** A pre with a refused conjunct emits no definedness constraint and no body VC (`compiler/src/LLMLL/FixpointEmit.hs:1669-1671`). `guard.llmll`, `guard2.llmll` and `guard3.llmll` each gave `contract-pre-outside-fragment`, exit 0, and no `ill_defined`. A refused body gives no body VC. A dropped callee post has its own mark, and that mark blocks the recheck. So a model cannot violate a clause that the query dropped on these routes.

**Unsupported builtins do not stay free (RAN, released).** `range`, `string-concat`, `int-to-string`, and `string-length` on a literal each gave `body-outside-fragment`, not `refuted`. So I could not build a true program that a free `strLen` refutes.

**Ground facts are necessary.** The record keeps them, and that is correct. `v = (select b i)` with goal `v*v ≤ 65025` is true. Without `byte-range`, native z3 gives `sat` at `v = -256` (RAN). With it, `unsat`. Add this as a test, because dropping that family gives a false `refuted`.

**Two statements are too strong.**

- "A validated model is a real one" (record, "Report the model") is incorrect. `refuted` is modular. On 0.37.0, a file with `(def g [x: int] -> int (post (>= result 0)) 5)` and `(def-shell lin [x: int w: int] -> int (pre (>= w 0)) (post (= result 5)) (g x))` gives exit 1, `refuted` (RAN, released), and `lin` is true. A printed `counterexample:` would show a value of `g` that no run gives. Print "VC counterexample", or print the inputs and name the callee results as assumed.
- "This check does not use z3's `:model_validate`, so its truth does not depend on z3" is correct only for terms that the checker evaluates itself. See Q7 and A4 for arrays and `Str`.

**Stop-at-first loses a qualification (READ).** `test_e3_ill_defined_and_refuted_qualified` holds a function that is ill-defined and refuted, with the refutation qualified. If the budget stops at a validated truth id, a false definedness id stays marked, so the function is `refuted` with no qualification. Stop per partition.

### Q3. Conjunct order: the verdict depends on it, and on names

RAN, solver, `prof2_order.py`, z3 on generated facts:

| Witness, all true | First order | Reversed order | Native z3 |
|---|---|---|---|
| O1: `x=y+1 ∧ x=2z ⟹ x*w = 2*(z*w)` | not proved | **proved** | `unsat` both |
| O2: `st=w+pad ∧ st=2*cw ⟹ y*st = 2*(y*cw)` | not proved | **proved** | `unsat` both |

On the 71 witnesses other than W22, four shuffles each and one flip of equation sides changed no verdict. So the team's set hides this, and the fault needs two definitions of one atom.

**Renaming also changes the verdict, and the record does not say so.** Four random renamings changed Q8 and Q9 from not proved to proved. Explicit form (RAN): Q8 as written is `sat`. `a≤b ∧ b≤a ∧ c≤d ∧ d≤c ⟹ a*c = d*b`, which is Q8 with `d→b, b→c, c→d`, is `unsat`. The cause is the sorted atom order, because UF congruence aligns arguments by position. So the record's table entry "Q8 does not prove" is true of those names only.

**Candidate repair (RAN, z3 only, `prof2_fix.py`).** Add a link for each top-level single-atom equation, not only the first. Add `a=c ∧ b=d ⟹ ab=cd` for each alignment of each two splits. Result:

- O1 and O2 prove in both orders.
- Three combined shuffles, flips and renamings of each of 71 witnesses changed no verdict.
- Q8 and Q9 now prove. W14, W23 and W25 still do not.
- No false witness proves.
- Fact count: 18551 against 18134, an increase of 2.3%.

This is illustrative. The language-team must state it, and `fixpoint` was not run on it.

### Q4. The stall: cause located, and the cap has the wrong shape

**The cause is paren depth in the `fixpoint` input, with no product and no fact in the file (RAN, `prof2_nest.py`, `prof2_nest2.py`).** CPU is `fixpoint` with its z3 child.

| Input, one goal, `n` or depth | 14 | 16 | 18 | 20 |
|---|---:|---:|---:|---:|
| Left-nested sum of `n` variables | 0.93 | 3.66 | not run | no result in 40 s wall |
| Right-nested sum | 0.98 | 3.72 | no result in 30 s wall | not run |
| **Redundant parens round one variable** | 2.03 | 6.08 | 20.57 | no result in 30 s wall |
| Flat `a + b + c`, `n` up to 80 | 0.04 | 0.05 | not run | 0.04 |

The cost doubles with each level, and redundant parens carry no structure. So the cost is before any logic, and that points at the parser. I did not read the liquid-fixpoint source. `FQ-FLAT-NEST-1` fixed the same effect for `&&` and `||` (`compiler/src/LLMLL/FixpointIR.hs:340-349`). `FQBinArith` at `:339` still nests.

**It is a released defect too (RAN, released).**

| `llmll verify` on 0.37.0, a linear sum in a body and post | Result |
|---|---|
| 12 terms | SAFE, 0.82 s wall |
| 16 terms | SAFE, 10.45 s wall |
| 20 terms, plus an unrelated good function, `--time-limit 15` | **exit 5, `resource-limit`, "Nothing was proved"**, 14.74 s user |

So the failure is clear, and it is not a hang. It costs the whole file: the good function loses its proof too (`compiler/src/LLMLL/DiagnosticFQ.hs:366-371`).

**Flat printing removes the stall (RAN, `prof2_flat.py`).** Same facts, same VC. The last two columns are CPU seconds.

| Input | Monomials in one sum | Nested | Flat |
|---|---:|---:|---:|
| 4 × 4 sums | 16 | 8.81 | 3.66 |
| **3 × 3 × 3 sums** (record: stall; CI: 280 CPU s) | 27 | none in 70 s wall | **1.33** |
| 4 × 4 × 4 sums | 64 | none in 70 s wall | 2.37 |
| **Kernel of 25 separate products** | 25 | none in 70 s wall | **11.71** |
| Kernel of 81 separate products | 81 | none in 70 s wall | 0.77 (over the pair cap) |

**So the 16-monomial cap is incorrect on both sides.** It refuses 3 × 3 × 3, which costs 1.33 CPU s once printed flat. It does not catch a 5 × 5 convolution with variable weights: each product there has one monomial, so the rule "a single product that expands to more than 16" does not apply, and `fixpoint` stalls. That is the "long hypothesis" of record risk 2, and it is an ordinary image kernel. Rev 2's measurement "Printing" (34.7 against 65.9) and its written-pair cap (27.4 against 1.83) probably show the same effect. I did not rerun those two.

**The remaining cost is different.** Flat printing does not change crux K=62 (50.8 against 52.0 CPU s), P3 (2.24 against 2.15) or W22 (33.0 against 51.3, under shared load). That cost grows with size. Removing the parens round each comparison in a fact halves it: K=20 goes from 8.94 to 4.08, and P3 from 3.69 to 1.66 (`prof2_minparen.py`). So `MUL-SLACK-1` probably has this cause too. I did not run the slack schema.

**The 64-pair cap is not local (RAN, `prof2_cap.py`).** It reads the whole constraint, so an unrelated `let` can remove a proof of the crux W3:

| Unrelated products in the same environment | Crux W3 |
|---|---|
| 62 of degree 2 | proved |
| 63 of degree 2 | **not proved** |
| 10 of degree 3 | proved |
| 11 of degree 3 | **not proved** |
| 2 of degree 4 | proved |
| 3 of degree 4 | **not proved** |

A disclosed fallback is the outcome, so this is not unsound. A realistic plane-copy path with 12 `let` lines reached `T = 18` and proved all four goals, at about 15 CPU s per constraint (load about 15). So the image domain is below the pair cap on that path. At that loaded rate, about eight such constraints would reach the 120 s default.

**`σ` has no limit (RAN, `prof2_sigma.py`).** The chain `x₁ = x₀*x₀ + 1`, `x₂ = x₁*x₁ + 1`, and so on has one monomial in each written product, so no cap applies. The resolved degree doubles at each step.

| Chain length | Monomials in `σ` | Degree | Generator CPU s |
|---:|---:|---:|---:|
| 6 | 33 | 64 | 0.04 |
| 8 | 129 | 256 | 1.08 |
| 10 | not reached | not reached | **no result in 40 s wall** |

This runs in the compiler, before the solver, so `--time-limit` does not stop it (READ: `runSolverGuarded` in `compiler/src/LLMLL/SolverGuard.hs:155` wraps the solver call). This hang has no exit code. Also, the fact count is not monotone in the chain: a chain of 2 has `T=63`, chains of 3 and 4 go over the cap, and a chain of 5 is under it again, because a monomial above degree 6 gets no splits.

### Q5. The second wrong verdict: real by reading, and not reachable on a released binary

- **Real by reading.** `candidate` needs a faithful function (`compiler/src/LLMLL/AbstractionVerdict.hs:216-219`). `hardFns` counts each non-candidate id (`:226`), and `aoIllDefined = hardFns PWd` has no faithful filter (`:197`). `aoRefuted` has one (`:199`). So a marked `wd-pre` in a function with a fallback body would be hard, exit 1. The record is correct.
- **Not reachable on 0.37.0 (RAN, released).** `wdprod.llmll`, a `def-shell` with `(* a b)` in the guard and a body outside the fragment, gives `contract-pre-outside-fragment`, exit 0, no `ill_defined`. The refusal happens before `compiler/src/LLMLL/FixpointEmit.hs:1671`. E20 reaches the hard path with a linear goal only. So the defect arrives with the product mark.
- **The fix in the record is correct for the verdict.** A validated `sat` on a `wd-pre` is a true `ill-defined`, because its hypotheses are parameter facts and earlier conjuncts (`:1703`), and it reads no body.
- **The fix has two omissions (READ).** First, `reclassifyEmit` appends to `erBodyFallback` and `erBodyFallbackCauses`, so a function that is already a fallback gets a second cause, and `test_e20_ill_defined_keeps_fallback_cause` expects a function to keep its first cause on the linear path. Second, `welldefWarning` says "Its truth was proved", which is false for a `def-shell` with no body VC. Both need a branch.

### Q6. The six decisions

| # | Decision | My position |
|---:|---|---|
| 1 | B for proofs, native for `sat` only | **Agree.** My witnesses add two costs, Y5 and K1. K1 is reachable with a small fact (A2). Do not accept a native `unsat` |
| 2 | `refuted` in the same release | **Agree.** On 4.8.12, 19 of 19 (CI REPORT). On 4.15.4, my 6 further false witnesses all validate, under the limit of A4 |
| 3 | Admit `def` bodies, with the message | **Agree** |
| 4 | Family `product-facts`, no `trust_report_version` increase | **Agree on the family** (`docs/llmll-trust-report.schema.json:233` is free strings; `compiler/src/LLMLL/TrustReport.hs:1915`). **Correct one statement:** the construct `abstraction:nonlinear:*` violates `docs/llmll-verify.schema.json:56`. So the verify schema changes (A5) |
| 5 | Separate `DIV-VAR-1` | **Agree.** The atom list must add `mod` with a positive ground divisor, and the refusal must run before cancellation |
| 6 | z3 4.8.12 gate | **The gate passes on the CI report, with corrections below** |

**Decision 6, the CI report, checked.** `gh run view 42404692268` gives `success` on `ci/mul-var-z3-4812`, commit `748d0462`, and the file header reads z3 4.8.12. I compared it with `r_final.txt`, line by line, ignoring times.

- The same on both: 48 of 53, the same five misses, 0 false proved, `z3/fixpoint disagree []`, 37248 facts with 0 failures, 19 of 19 `sat` validated, no true `sat`, and W23 `timeout`.
- **Rlimit unit.** On `sat` the counts are close: 14707 against 15074. On true `unsat` they are not: 1368835 against 186173. The record's "unit may differ" can close for `sat` only.
- **The coordinator's note 3 does not bear on `refuted`.** At rlimit 200000, 20 true witnesses read `unknown` on 4.8.12, and false witnesses stay 19 of 19. In the record's verdict table `unsat` and `unknown` give one outcome. So only `sat` decides the limit. The message text `<unsat | limit | abstained>` would vary by version, so it should say only "no counterexample found".
- **The limit.** 200000 gives every result the design uses, on both versions, at about 0.14 s per hard id. 2000000 gives about 2.18 s per hard id on an unloaded runner, so 8 ids cost about 17 s per function, for no change in outcome on these witnesses. All my false witnesses, including two plane-copy functions, finished under 8872 on 4.15.4 (`prof2_rl.py`). This check did not validate those two models. Keep 2000000 until the table runs through `llmll verify`, and then choose again from real counts.
- **The record's CPU numbers are upper bounds by a large factor.** W22 is 58.96 against 21.46, and K=62 is 85.6 against 30.8 CPU s, loaded against unloaded. This mixes load and z3 version, so I do not attribute it. The unloaded runner still gave no 3 × 3 × 3 result in 280 CPU s, so load is not the cause of that stall.
- **Note 1.** My run on the final `nf.py` gives T=108, facts=972 for a 3 × 3 × 3 input with other names, which supports the attribution. I did not rerun the old code.
- **Note 2 is ordering only.** Over all 72 witnesses and 6 hash seeds, `T`, the fact count and a hash of the sorted lines are equal, and the raw text hash differs (RAN, `prof2_seed.py`). So an emitter must fix its print order, for byte-identical artifacts. This does not touch the fact set.
- **A small correction.** The record says at most 0.050 s wall on false witnesses. `r_final.txt` says 0.079 s. It is load noise, but the number should match its source.
- **Not covered by CI:** my witnesses, flat printing and the repair in Q3 did not run on 4.8.12.

**Is it settleable?** Yes, as stated in the verdict. No finding reverses a decision, and each amendment is small. The direction is correct. The fact set is normative, so the text must carry A1 to A5 before the user settles it.

### Q7. The witness set: strong on image contracts, with one real gap

RAN, solver, `prof2_battery.py`, using generated facts. Nothing through `llmll verify`. Sources are `examples/y4m/raster.llmll` and `examples/netpbm-swarm/kernel.llmll`.

| Witness, all true | Facts prove | Native | Facts `T` | CPU s |
|---|---|---|---:|---:|
| Y1 chroma plane ≤ luma plane | yes | `unsat` | 2 | 0.32 |
| Y2 U offset inside frame | yes | `unsat` | 3 | 0.69 |
| Y3 V offset inside frame | yes | `unsat` | 3 | 0.70 |
| Y4 frame ≥ luma + 2 | yes | `unsat` | 2 | 0.34 |
| **Y5 frame ≥ 3/2 luma** | **no** (W14 class) | `unsat` | 2 | 0.33 |
| Y6 frame ≤ 3 luma | yes | `unsat` | 2 | 0.32 |
| Y7 chroma inline, `(/ (+ w 1) 2)` | yes | `unsat` | 2 | 0.32 |
| Y8 cursor from `plane-w`, `plane-h` posts with cases | yes | `unsat` | 2 | 0.07 |
| Y9 to Y12 plane area, cases under `=>` | yes, 4 of 4 | `unsat` | 2 to 3 | ≤ 0.56 |
| YF2, see the note below | yes | `unsat` | 3 | 0.67 |
| **K1 channel 1 or 3, `kernel.llmll:44` shape** | **no** | `unsat` | 1 | 0.04 |
| K2 the same with `c = 3` on the path | yes | `unsat` | 0 | 0.03 |
| K3 row offset, variable channels | yes | `unsat` | 11 | 1.64 |
| K4 sample count under a header limit | yes | `unsat` | 6 | 0.46 |
| K5 row above in a blur | yes | `unsat` | 2 | 0.06 |
| K6 crop window, padded buffer | yes | `unsat` | 8 | 1.24 |
| K7 half-scale of a product | yes | `unsat` | 2 | 0.08 |
| K8 last channel, `bytesLen` | yes | `unsat` | 13 | 2.66 |
| K9 `mod` as a factor, written through `/` | yes | `unsat` | 3 | 0.43 |
| K10, K11 quotient of a row index | yes | `unsat` | ≤ 1 | ≤ 0.05 |
| K12 padded stride, two names | yes | `unsat` | 10 | 1.87 |
| K13 3 × 3 kernel | yes | `unsat` | 9 | 1.27 |

**Total: 24 of 26 true prove, against 48 of 53 for the team's set.** This is the best evidence for the design that this review found. Y8 to Y12 matter most, because they use the post shape that Y4M really has.

**A correction to my own set.** I wrote YF2 (`x ≤ cw` in a U offset) as a false claim, and it proved. I checked by hand: `y*cw + x ≤ (ch-1)*cw + cw = ch*cw < 2*cw*ch`, because `cw*ch ≥ 1`. So it is true, native z3 agrees, and my label was wrong. It is not a soundness failure. I count it as true.

**False witnesses:** YF3, YF4, KF1, KF2, KF3, KF4 all give `sat` with a validated model, and none proves.

**K1 is the real gap.** `(or (= c 1) (= c 3))` with `(=> (= c 3) (< i (* 3 w)))` and goal `(< i (* c w))` is how netpbm writes channels. Adding one literal-factor fact `c = 3 ⟹ c*w = 3*w` proves it (RAN). My Rev 1 review proposed this fact, and Rev 2 replaced it with F9, which reads top-level equations only (A2).

**Emitter shapes that the witnesses miss (RAN, released).**

- `abs` and `max` print as `(if (x < 0) then (0 - x) else x)`, an `FQIte` term (`t7`, `t10`).
- `(mod x 3)` prints as `(x mod 3)` (`t8`).
- A `bytes-set` prints `_bv_call_bytes_set_1 = (Map_store b 0 7)` in the `lhs`, with `Str` and `Map_t` binders (`bytes.fq`).

So `(* (abs dx) stride)` and `(* (mod i 3) w)` are ordinary image terms that the record's atom list does not define.

**Real envelope (RAN, one file).** The crux with `bytesLen`, in the emitter's own header and `fixpoint -q --json`: `Safe`, 33 facts.

## Gaps and hazards

### Blocking the text as written

**G1. The fact set depends on conjunct order and on names.** Classify: ergonomic, language surface. Cite: record "Equation resolution", "Normal form" item 3, risk 5; `prof2_order.py`. Bite: blocks, because the record makes the set normative. A swap inside `and` changes `verified` to fallback, and so does a rename.

**G2. The stall is misdiagnosed, and the cap has the wrong shape.** Classify: decidability in practice, spec-drift. Cite: record "The caps", risk 2; `compiler/src/LLMLL/FixpointIR.hs:339`; Q4. Bite: blocks, because the cap is normative, refuses cheap programs, and misses a 5 × 5 kernel, which costs the whole file at exit 5.

**G3. `σ` has no limit.** Classify: totality of the compiler. Cite: record "Termination"; `prof2_sigma.py`. Bite: blocks, because it is an unguarded compiler hang. The record's termination argument is true and does not bound the size.

**G4. The atom list and the validator do not cover emitted terms.** Classify: spec-drift, and soundness of the verdict path. Cite: record "Atoms", "What `sat` is validated against"; Q7.

- The list omits `FQIte` and `mod`.
- The validator asks for "each variable", and "a value it cannot read gives the mark back". z3 returns `Str!val!0` and `(store ((as const (Array Int Int)) 2) 0 7)` (RAN, `prof2_arr.smt2`).
- `nf.py` skips `bytes` variables and treats `select` as a free value. So N4, N5 and my KF4 validate only because the prototype does not do what the record states.
- A hypothesis `c = Map_store b 0 7` cannot be evaluated in integer arithmetic.

Read literally, every function with a `string` or `bytes` parameter loses `refuted`. An offset bug at a `bytes-get` is the row's main use. The record discloses that the encodings did not run, but its headline says finding 1 is resolved. On byte buffers, that is not yet shown.

### Not blocking

**G5. S1, the name collision.** Soundness, released defect, outside this record. File it and ship it first.

**G6. `applyAbstractionVerdict` is pure, and it has three callers.** Spec-drift, READ. The recheck needs IO. `compiler/app/Main.hs:2453` (CDP) and `:3031` (diverge) count an UNSAFE as a kill or a refutation. If they do not recheck, a mutant of a product contract is never killed, and `--cdp` scores move. The record's "Affected surface" names neither site. State the choice.

**G7. The verify schema and two texts.** Spec-drift. `docs/llmll-verify.schema.json:56` rejects `abstraction:nonlinear:*`. `abstractionRepair` and `compiler/src/LLMLL/PatchApply.hs:723` say "two calls", which is false here. The record says "JSON does not change".

**G8. `fqPredToSMT` is shared.** Scope, READ. The record extends it for the recheck, and `compiler/src/LLMLL/Feasibility.hs` uses it for the refine gate, which fails open today on a function term. Extending it changes that gate. Use a separate translator, or state the change.

**G9. The pair cap is not local.** Ergonomic. See the table in Q4. Keep it, because the cost is real, but disclose it in the spec and reread it after A1's printing.

**G10. The overclaims in Q2, the stop rule, and the two omissions in Q5.** Spec-drift, small.

## Recommendation

Keep B, the recheck and the six decisions. Fold these five amendments. Each is illustrative, for the language-team to formalize.

**A1. Print flat, and rebuild the caps from that (G2).** Print a sum as one flat chain, as `FQ-FLAT-NEST-1` does for `&&`, and drop the parens round a comparison in a fact. Remove the 16-monomial and written-pair caps unless a rerun gives a new reason. File the printing fix as its own row and ship it first, because it repairs the released 20-term failure with no language change. A VC with no product then does change its text, so the byte-identical claim in the record must move to "identical before this row".

**A2. Make the fact set invariant (G1).** State as a language property: the fact set is unchanged by conjunct order, by equation side, and by renaming. Add a link per equation, and congruence at each alignment (`prof2_fix.py`, +2.3% facts). Add the literal factor `a = k ⟹ ab = k·b` for each literal `k` in the constraint, for K1. A test shuffles and renames every witness. Sorting the equations is not enough, because a sort by printed name still depends on names.

**A3. Bound `σ` (G3).** Stop expansion at a stated size and degree, counted after resolution, and give `nonlinear:*` for that constraint. This makes the emitter total in practice. Choose the bound after A1.

**A4. Complete the atoms and the validator (G4).**

- Add `FQIte` and `(mod e k)` with a positive ground `k` to the atoms, or state that they refuse.
- Run the refusal scan on the source before cancellation.
- Validate arrays as a finite map with a default, evaluating `Map_store` and `Map_select`.
- Treat an opaque `Str` value as a token with equality only.
- Rerun N4, N5 and KF4 on that validator, with `bytes-set`, `strLen` and the two-array map.

**A5. Name the surface that moves (G6, G7, G8).** Widen the verify schema pattern, with its version rule. Change the two "two calls" texts. Say what CDP and diverge do. Give the recheck its own translator.

**Do not** replace the design with Option A, RLT or a Lean-first path. Nothing here supports that. This remains a scope difference from Verus and Dafny, which give the author the nonlinear step, and it is not a soundness disagreement.

## Not run

| Item | Why |
|---|---|
| **Any two-variable product through `llmll verify`** | No implementation exists. All product results are hand-built VCs |
| z3 4.8.12 on my witnesses, flat printing or the repair | Not permitted on this machine; a CI run of the `prof2_*` scripts can do it |
| `fixpoint` on the Q3 repair and the literal factor | z3 only |
| Fact table rerun under flat printing, beyond the rows in Q4 | Budget |
| The validator of A4 on real array models | One `get-value` output only |
| Replay of a rechecked `refuted` | Needs an implementation |
| `(* 0 (/ x y))` cancellation | Reading only; the prototype cannot express it |
| `(* (abs x) w)` and `(* (mod i 3) w)` as atoms | Reading only, plus K9 written through `/` |
| Slack schema under flat printing | Not run; the link to `MUL-SLACK-1` is an inference |
| liquid-fixpoint parser source | Not read. "Parser" is an inference from redundant parens |
| Lean path, Docker image, `scripts/fallback_census.py` | Not relevant to the findings, not run |

**Citations.** I added no external citation in this review, so none needs confirming. Rev 1's table stands.

**Rule breaks.** Table cells and the "Not run" list use fragments. The verdict lists are short fragments for skimming. Some sentences that state a condition keep it at a cost in length. No other rule was broken knowingly.

## Open questions for the language-team

1. State the invariance of A2 as a property of the fact set, and give the test that holds it.
2. State whether CDP and diverge run the recheck, and what happens to existing `--cdp` scores on a product contract.
