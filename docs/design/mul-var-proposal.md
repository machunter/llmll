---
name: mul-var-proposal
title: "MUL-VAR-1: state and prove a product of two variables, so that an image layout can have a contract"
status: "Rev 1, DRAFT 2026-11-07. Awaits a user decision. Not settled. No professor pass yet."
date: 2026-11-07
author: language-team
rows: "MUL-VAR-1 (G7, DECIDE). Related: CLAUSE-WELLDEF-1 (shipped v0.37.0), ABSTRACTION-VERDICT-1 (shipped v0.34.0), BITWISE-WIDTH-1 (G7, PLAN), FFI-KERNEL-1 (G7, PLAN), CORE-SYNTAX-MSG-1 (G3, PLAN), LEAN-GA (parking lot). Proposes one row, not filed: DIV-VAR-1."
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# MUL-VAR-1: a product of two variables in a contract

**Status: Rev 1, DRAFT 2026-11-07.** The user has not settled this record. Every number below was measured on 2026-11-07 unless a line says otherwise. The compiler was not changed. Each encoding was tested on a verification condition (VC) built by hand, in the shape the emitter writes.

## Restatement

An image library states sizes and offsets as products: `w*h*channels`, `y*stride + x`. LLMLL cannot prove a product of two variables today, so no contract can say that a pixel offset is inside its buffer. This record chooses how `verify` handles `(* a b)` when neither operand is a constant.

## Recommendation

**Reflect `(* a b)` as one uninterpreted function `mul`, with ground facts that are theorems of integer multiplication.** This is Option B below. The facts include one that the row did not name, the *row fact*: `a < c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ a·b + b ≤ c·d`. Without it, the central obligation `y*w + x < w*h` fails.

| Option | True witnesses proved (of 27) | False witnesses wrongly proved (of 9) | Can it hang? | Stays decidable? | New trust |
|---|---:|---:|---|---|---|
| **B. `mul` + ground facts (recommended)** | 24 | 0 | No | Yes, QF-UFLIA | None beyond `*` being integer multiplication |
| A. Native `*` to z3 | 26 | 0 | Yes; needs a per-query timeout | No, QF-NIA | The z3 nonlinear engine |
| C. Named product, no facts | 2 | 0 | No | Yes | None |
| C′. The row's wording: monotonicity and bound facts only | 6 | 0 | No | Yes | None |
| D. Lean path | Not measured | Not measured | n/a | n/a | Not in the default verdict |
| E. Cursor pattern, no change | 0 | 0 | No | Yes | None |

Option A proves more and costs less on this set. It is the serious alternative. Option B is recommended for two reasons. Its verdict does not depend on the nonlinear heuristics of a z3 version, and CI and Docker run a z3 (4.8.12) that this measurement could not reach. It also keeps `Σ_auto` decidable, so one hard obligation cannot stop a whole file.

## Decisions for the user

1. **Encoding.** Option B (recommended) or Option A.
2. **Refutation.** Under either option, a failing constraint that holds a product cannot report `refuted` from the solver's answer alone (see "Verdict"). Accept the fallback outcome in the first release (recommended), or also file a recheck row that restores `refuted`.
3. **`def` bodies.** Admit a two-variable `*` in the strict core (recommended), or keep it for `def-shell` bodies only.
4. **Disclosure.** Add one per-function `assumed_facts` line for `mul` facts, with no effect on the trust level (recommended), or add none, because the facts are theorems.
5. **Variable divisors.** File `DIV-VAR-1` as a separate row (recommended), or widen this row. Resize and offset-to-coordinates need it.
6. **z3 4.8.12.** Run the witnesses on the CI z3 before settlement. The classifier refused the download in this session. It is required if decision 1 goes to Option A, and a check otherwise.

## Context located

1. `examples/y4m/FRICTION.md` F5: `frame-bytes` cannot be stated; the cursor workaround gives up seek.
2. `examples/netpbm-swarm/FRICTION.md` F12, F14: nonlinear gates differ; whole-image facts cannot be stated.
3. `compiler/src/LLMLL/FixpointEmit.hs`: `exprToPredWD` and `bodyToPredM` refuse `*` after `constArithTerm`; the label comes from the `nonlinearOps` list.
4. `compiler/src/LLMLL/Syntax.hs`: `isCoreBodySyntactic` and `constArithAdmitted` gate `def` bodies.
5. `compiler/src/LLMLL/HoleAnalysis.hs`: `isNonLinear` shares `constArithAdmitted`; the Lean worklist reads it.
6. `compiler/src/LLMLL/LeanTranslate.hs`: admits `*`, rejects `/` and `mod`.
7. `compiler/src/LLMLL/AbstractionVerdict.hs`, `docs/design/byte-io-proposal.md` Part 0: an abstracted term turns UNSAFE into the fallback outcome.
8. `docs/design/byte-io-proposal.md` "Part 6": `band` is an uninterpreted function with ground facts. This record uses the same form.
9. `docs/design/ffi-buffer-proposal.md` Part 3 and edge case 13: `(out-len (* w h))` is refused, so the worked example passes `npix`.
10. `LLMLL.md` §5.3.3: the fragment classes, the path-(a) ground-fact discipline, and the "Outside" clause.
11. `.github/workflows/version-gate.yml`: CI proves with apt z3 4.8.12, the same as the Docker image.

No draft existed on this topic.

**Spec drift, two findings.** First, `LLMLL.md` §5.3.3 says nonlinear terms "route to `?proof-required`". Measured on 0.37.0, a `def-shell` with `(post (< result (* w h)))` falls back with `W-BODY-FALLBACK`, `Refused by: nonlinear:*`, and no hole. The spec text should move to match. Second, liquid-fixpoint reads a z3 `unknown` as UNSAFE under `--smtTimeout` (measurement 5). The spec's account of `refuted` does not consider this, because no emitted VC is expected to reach `unknown` today.

## What happens today (llmll 0.37.0, liquid-fixpoint 0.9.6.3.7, z3 4.15.4)

| Input | Result |
|---|---|
| `def area`, body and post `(* w h)` | `check` exit 1: "body contains non-core syntax" |
| `def-shell area`, the same | exit 0, post not proved: `contract-post-outside-fragment`, `Refused by: nonlinear:*` |
| `def-shell off`, post `(< result (* w h))`, body `(+ (* y w) x)` | exit 0, post not proved, `Refused by: nonlinear:*` |
| `def-shell off`, `(= n (* w h))` in the `pre` | exit 0, post not proved: `contract-pre-outside-fragment` |
| The same post as `?proof-required` | exit 0, post not proved, `Refused by: hole`; two warnings |
| `def off`, products passed as `n` and `r`, with `(<= (+ r w) n)` in the `pre` | **verified.** The row fact became a `pre` that no caller can prove |
| `(* 3 w)`, `(+ (* 8 y) x)` | verified, as `SIGMA-CONST-ARITH-1` specifies |

## Measurements

The witnesses are 27 true claims and 9 false claims. The true claims cover buffer length, row offset, stride, variable channels, crop size and offset, chroma planes, a whole Y4M frame, frame `i` of `k`, a 3-D offset, a two-image blit, and three claims chosen to be hard. A random search over small integers found a counterexample for each false claim and none for any true claim.

**1. Results.** Each cell is the z3 result in a 10 s limit. "fail" means z3 found a model of the encoded negation. For A, that is a real counterexample. For C, C′ and B, it may not be. `fixpoint` gave the same answer as z3 on A, C′ and B for all 36 witnesses, except W23 under A, which `fixpoint` did not finish in 30 s.

| Witness | A native | C named | C′ bound | B ground facts |
|---|---|---|---|---|
| W1 `w*h = h*w` | proved | proved | proved | proved |
| W2 buffer `w*h*3` | proved | fail | proved | proved |
| **W3 `0 ≤ y*w+x < w*h`** | **proved** | **fail** | **fail** | **proved** |
| W4 stride `y*st + 3x + c < h*st` | proved | fail | fail | proved |
| W5 variable channels, named offset | proved | fail | fail | proved |
| W5b variable channels, unnamed | proved | fail | fail | proved |
| W6 crop size `cw*ch ≤ w*h` | proved | fail | proved | proved |
| W7 crop offset | proved | fail | fail | proved |
| W8 chroma offset | proved | fail | fail | proved |
| W9 V plane inside a frame | proved | fail | fail | proved |
| W10 frame `i` of `k` | proved | fail | fail | proved |
| W11 distribution | proved | fail | fail | proved |
| W12 next row | proved | fail | fail | proved |
| W13 byte index against a length | proved | fail | fail | proved |
| W14 `4*cw*ch ≥ w*h` | proved | fail | fail | **fail** |
| W15 half width times half height `≤ w*h` | proved | fail | proved | proved |
| W16 horizontal flip offset | proved | fail | fail | proved |
| W17 transpose offset | proved | fail | fail | proved |
| W18 factor reached through an alias | proved | fail | fail | proved |
| W19 3-D offset | proved | fail | fail | proved |
| W20 `w,h ≤ 65535 ⟹ 3*w*h ≤ 2^63−1` | proved | fail | fail | proved with the F7 fact (below); fail without |
| W21 frame inside a file | proved | fail | fail | proved |
| W22 four-factor monotonicity | proved | fail | proved | proved |
| W23 `x*x ≠ 2*y*y` | **timeout** | fail | fail | **fail** |
| W24 Pythagorean parity | proved | proved | proved | proved |
| W25 `(a+b)^2 ≥ 4ab` | proved | fail | fail | **fail** |
| W26 two-image blit | proved | fail | fail | proved |
| M1 to M9, nine false claims | none proved | none proved | none proved | none proved |

Option A also proved four more true claims through `fixpoint`, and refused one false claim: rotate-90 offset, BMP row stride, a four-plane total, a bound from a product in the `pre`, and a rotate-90 with the wrong stride. These were not run under B.

**2. Time.** Through `fixpoint`, A took at most 0.086 s on each decided witness. B took at most 0.916 s (W26, 8 product terms and 530 facts). The cost of B is in the fact count. It is about `10T + 8T(T−1)` facts for `T` product terms in one constraint, plus any distribution equations.

| Product terms in one constraint | Facts (B) | `fixpoint`, B | `fixpoint`, A | z3 alone, B |
|---:|---:|---:|---:|---:|
| 4 | 136 | 0.5 s | 0.11 s | 0.02 s |
| 7 | 406 | 1.0 s | 0.09 s | 0.03 s |
| 12 | 1176 | 2.9 s | 0.07 s | 0.04 s |
| 22 | 3916 | 9.8 s | 0.18 s | 0.23 s |
| 42 | 14196 | 39.8 s | 0.16 s | 1.17 s |

z3 alone takes a small part of `fixpoint`'s time on B. So a smaller fact set, or a filter on which pairs get facts, should recover most of the cost. The engineer may filter, because a missing fact can only lose a proof.

**3. Stability of A.** Six witnesses gave the same result under five random seeds. The crux stayed proved in about 0.01 s with up to 16 unrelated product facts in scope. Two real files, `examples/netpbm-swarm/lex.llmll` and `examples/y4m/raster.llmll`, were re-solved with the crux appended, and each stayed SAFE (6.4 s and 7.1 s, against 6.5 s and 6.8 s). A product beside `bytesLen` and an array sort also decided correctly. This was all on one z3 version. **z3 4.8.12 was not measured.**

**4. Option A can hang.** W23 is true, and z3 does not decide it. With no per-query limit, `fixpoint` was still running when killed at 40 s, on W23 alone and when appended to each real file. Under `llmll` this stops at `--time-limit` (default 120 s), with no verdict for any function in the file.

**5. A per-query timeout gives a false UNSAFE.** With `--smtTimeout 2000`, W23 returns **UNSAFE in about 2 s, although it is true.** liquid-fixpoint does not separate `unknown` from `sat`. Appended to the real files, the run ended UNSAFE in 11.2 s and 10.7 s. So Option A must also treat UNSAFE as the fallback outcome.

**6. The facts are true.** Each fact was checked on Haskell `Integer`, exhaustively on `-7..7` and on 18 boundary values up to `2^127`, with 0 failures. z3 also proved each inequality under native multiplication. A control, the row fact without `b ≥ 0`, failed in both, so the check can fail. The facts together with each witness's hypotheses were satisfiable on the three largest witnesses.

**7. Corpus.** Of 2002 `.llmll` files on disk, including untracked run output, 6 files hold 9 functions refused for `nonlinear:*`. Each verdict below follows from the rule; it was not built and run: `square` (`examples/leanstral-demo/square.llmll`), `g` (`scripts/doc-claims/nonlinear-body-fallback.llmll`), `nonneg` (one experiment run), `nonlinear_post` (the census fixture), `pick` (`scripts/tests/fixtures/fn_shadow_1/pk.llmll`), and `sq-pos`, `sq-let`, `prod`, `pre-sq` (`scripts/tests/fixtures/fallback_attrib/attrib.llmll`).

## Design proposal (Option B)

### Surface

There is no new syntax. `(* a b)` already parses and type-checks as `int → int → int`. JSON-AST does not change. A contract may now use it, and if decision 3 is accepted, so may a `def` body:

```lisp
(def pixel-offset [w: int h: int y: int x: int] -> int
  (pre (and (>= y 0) (and (< y h) (and (>= x 0) (< x w)))))
  (post (and (>= result 0) (< result (* w h))))
  (+ (* y w) x))
```

### Semantics

Evaluation does not change. `int` lowers to Haskell `Integer` (`LLMLL.md` §3), and `*` is total on it. So `*` adds no definedness obligation under `CLAUSE-WELLDEF-1`, and a partial read inside a factor keeps its own obligation.

**Reflection.** A product whose operands are not ground is normalized and reflected:

- A constant factor moves out: `(* (* 3 x) w)` is `3·mul(x, w)`. A form with a ground operand stays exact linear arithmetic, and its `.fq` does not change.
- Arguments are in one canonical order, so `mul(w, h)` and `mul(h, w)` are one term.
- A factor may itself hold a `mul` term, as `mul(mul(w, h), ch)`.

`constant mul : (func(0, [int; int; int]))` is declared only in a file that uses it.

**Facts.** The emitter adds these ground facts to each constraint, over the product terms of that constraint, after substitution. Each is a hypothesis, flat in the `lhs`, as `FQ-FLAT-NEST-1` requires.

| Fact | Statement | Instances | Why it holds |
|---|---|---|---:|
| F1 sign | `a ≥ 0 ∧ b ≥ 0 ⟹ ab ≥ 0`; `a ≤ 0 ∧ b ≥ 0 ⟹ ab ≤ 0` | each term, both orders | Sign of a product |
| F2 zero, one | `a = 0 ⟹ ab = 0`; `a = 1 ⟹ ab = b` | each term, both orders | Ring identities |
| F3 growth | `a ≥ 1 ∧ b ≥ 0 ⟹ ab ≥ b` | each term, both orders | `(a−1)·b ≥ 0` |
| F4 monotone | `a ≤ c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ ab ≤ cd` | ordered pairs, 4 alignments | `ab ≤ cb ≤ cd` |
| **F5 row** | `a < c ∧ b ≤ d ∧ b ≥ 0 ∧ c ≥ 0 ⟹ ab + b ≤ cd` | ordered pairs, 4 alignments | `(a+1)·b ≤ cb ≤ cd` |
| F6 distribution | `mul(s + t, b) = mul(s, b) + mul(t, b)`, and a constant in a factor expands | each term with a sum as a factor | Ring identity |
| F7 literal bound | `0 ≤ a ≤ A ∧ 0 ≤ b ≤ B ⟹ ab ≤ A·B` | each term, per literal pair in the hypotheses | F4 at constants |
| F8 square | `mul(n, n) ≥ 0` | each term with equal factors | `n² ≥ 0` |

**F5 is what the crux needs.** `y*w + x < y*w + w ≤ h*w` is linear once F5 gives its second step. C′ has F1 to F4 and fails W3. All pairs are used, with no syntactic match on a shared factor, so an alias such as `(= s w)` still works (W18).

F7 and F8 were each measured alone: F7 moves W20 from fail to proved, and F8 proves `n*n ≥ 0`. The 24 in the table counts W20 under F7. The other measurements use F1 to F6.

**Termination.** F6 adds terms, and each added term has fewer atoms in the factor it expands. No other fact adds a term. So the closure is finite.

### Verdict

`mul` joins clause 1 of the abstracted-term rule in `docs/design/byte-io-proposal.md` Part 0, as `band` does. The facts are true but incomplete, so UNSAFE means only that the abstraction admits a counterexample.

| Solver | Constraint holds no `mul` | Constraint holds `mul` |
|---|---|---|
| SAFE | `verified` | `verified` |
| UNSAFE | `refuted` | fallback, cause `abstraction-unsafe`, construct `abstraction:nonlinear:*` |

**The cost is real.** All nine false witnesses would report the fallback outcome, with exit 0, not `refuted`. The disclosure stays: `W-BODY-FALLBACK` prints, the post stays a run-time check, and `--strict-verified-core` and `patch --require-proof` refuse the function. An agent that fills holes with `--require-proof` still gets a refusal. Option A has the same cost, by measurement 5.

**Restoring `refuted` (decision 2).** Native z3 found a model for all nine false witnesses in under 0.02 s. A later row could run z3 directly on a failed constraint, and evaluate the model on `Integer`. A model that evaluates to a counterexample is a real disproof. A concrete search is weaker: 200000 samples missed M8 on one range, and M4 and M5 on the other. This is not needed for the first release.

### Option comparison

**A. Native `*`.** The emitter passes `(w * h)` to liquid-fixpoint, which hands it to z3. It needs no new facts and adds almost no time. It also proves W14 and W25, and it handles variable divisors (measured: `(/ i w)` and `(mod i w)` under `w > 0`, and `(/ (* x sw) dw)` for nearest-neighbour resize, each SAFE). Its costs:

- A `verified` result depends on the z3 nonlinear engine, and on its version. CI and the published image use 4.8.12; this session used 4.15.4.
- It needs `--smtTimeout`, which measurement 5 shows can report a true obligation as UNSAFE, and which makes the result depend on machine load.
- `Σ_auto` is no longer a decidable class, which `LLMLL.md` §5.3.3 states as its defining property.
- `replay-artifact` must then reproduce a nonlinear result, and `FIXPOINT-VERSION-1` shows that an artifact does not yet name its solver version.

If the 4.8.12 run also proves all 26, and the user accepts the timeout rule, Option A is defensible. It should then be scoped with the timeout passed only for a file that holds a product, so that every other `.fq` run is unchanged.

**C. Named product.** A product named once and reasoned about linearly proves almost nothing (2 of 27), because no fact relates `n` to `r`. The measured `def off` shows what happens: the author moves the row fact into a `pre`, where no caller can prove it. This is the `npix` shape in `docs/design/ffi-buffer-proposal.md`, which checks `npix = w*h` at run time.

**C′. Monotonicity and bound facts.** This is the row's first example. It proves crop size, down-scale and monotonicity, and fails every offset witness. It is not enough on its own.

**D. Lean.** `verify --leanstral-mock` on the crux reports "not verified (fail-closed): degenerate proof term". The real path needs an API key and a Lean project, so it was not run. `LeanTranslate` rejects `/`, so W8, W9, W14 and W15 cannot translate as written. The production path is parked under `LEAN-GA`, and the result is not part of the default verdict. Routing every layout contract there is the wrong default. It stays the route for what B misses, such as W23.

**E. Cursor.** `examples/y4m/raster.llmll` proves each byte step. It gives no seek, no stated size, and no check of a byte count against a proved size (F5). It stays a valid pattern, and it does not serve random access, blit or crop by offset.

### What B does not prove

W14 and W25 are true and fail. W23 is true and fails. Each falls back with disclosure, and an author can use `?proof-required`, or `check` evidence. W14 needs a fact with scaled factors; adding it is possible later, since a new true fact can only add proofs.

### Design-reference set

These are named from general knowledge and were not checked in this session. Dafny offers `--disable-nonlinear-arithmetic` and a lemma library, because native nonlinear proofs are unstable. Verus isolates them in `by(nonlinear_arith)`. Liquid Haskell has `--linear`, which makes `*` uninterpreted. Cimatti and others use the same sign, monotonicity and tangent facts in incremental linearization, for SMT over nonlinear arithmetic. Option B is a fixed, one-round form of that method. The professor should check this paragraph.

## Edge cases and degenerate inputs

1. **Positive witness for the abstraction mark.** M1: `(>= y 0)`, `(< y h)`, `(>= x 0)`, `(<= x w)`, post `(< (+ (* y w) x) (* w h))`. It is false at `h=25, w=21, x=21, y=24`. Behaviour: UNSAFE, the constraint holds `mul`, so the fallback outcome and exit 0. Channel: trust. Citation: Verdict.
2. **Negative factors.** M5: `(>= (* w h) 0)` with no `pre`. F1 does not fire, so it is not proved, which is correct at `w=-3`. M4 is the same with `y=-1`. Channel: contract.
3. **Zero extents.** `w=0` or `h=0`. W3's `pre` then has no solution, because `x < w` or `y < h` fails with `x, y ≥ 0`. F2 gives `w*h = 0`, so a zero-size buffer is sound. Channel: contract.
4. **A square.** `(* n n)` with `n` negative. F8 gives `≥ 0`. The control `n*n ≥ 1` is false at `n=0` and stays unproved. Channel: contract.
5. **A constant factor.** `(* 3 w)`. It stays exact, the `.fq` is byte-identical, and UNSAFE stays `refuted`. Channel: contract. Citation: `SIGMA-CONST-ARITH-1`.
6. **A partial read in a factor.** `(* (map-get m k) w)` in a post. `mul` adds no obligation, and `map-get` keeps its `wd-post`. Channel: contract. Citation: `CLAUSE-WELLDEF-1`.
7. **A callee post with a product.** `(post (= result (* w h)))` at a call `(area a b)`. The caller assumes `result = mul(a, b)`. Facts are generated after substitution, so the caller's terms get them. Channel: contract.
8. **A product in `decreases`.** `(decreases (* w h))`. It stays refused in this record: descent is proved over exact terms, and a fallback there has separate rules. Channel: contract. Citation: `LLMLL.md` §5.3.
9. **An undecidable claim.** W23. No hang under B: z3 returned a model of the encoded negation inside the 10 s limit, then the rule gives the fallback outcome. Channel: trust.
10. **A large value at the FFI boundary.** A product passed to a kernel `int` can pass `2^63−1`. `int` is `Integer`, so the product is right, and the `int64` range obligation of `docs/design/ffi-buffer-proposal.md` Part 4 stays a hard obligation. W20 shows that a range `pre` can prove it. Channel: contract.
11. **Many product terms.** 42 terms in one constraint gave 14196 facts and 39.8 s. Facts grow as `8T²`. The `--time-limit` still bounds the run. The engineer may filter pairs. Spec is silent (intentional).
12. **A kernel `out-len`.** `(out-len (* w h))` stays refused (`ffi-kernel-term-unsupported`). A caller can now prove `(= npix (* w h))` and pass `npix`, which removes the run-time-only check that the FFI record's worked example describes. Lifting the refusal is a later change to that record. Channel: type.

## Verification mapping

| Obligation | Channel | Fragment | Citation |
|---|---|---|---|
| A contract or body VC that holds `mul` | contract | **(a) QF-UFLIA, auto-discharged.** Ground facts over one uninterpreted function: the measure-class discipline, path-(a), without a claim of completeness against QF-NIA | `LLMLL.md` §5.3.3; `FixpointEmit.hs` |
| The truth of each fact F1 to F8 | not an obligation | Proved once, by the arguments in the table, and checked as in measurement 6. Not a per-program obligation | this record |
| A claim that the facts cannot reach (W14, W23, W25) | trust | (b) nonlinear: falls back. (c) `?proof-required` is available, and the Lean path stays experimental | `LLMLL.md` §5.3.5 |
| Variable divisor | outside this record | (b), refused as today. Proposed row `DIV-VAR-1` | `FixpointEmit.hs` |

**Strict immutability.** No state is added. `mul` exists only in the VC.

**Soundness argument.** Each fact is a theorem of integer multiplication, the run-time semantics of `*` is exact `Integer` multiplication, and `mul` is functional, so EUF congruence is true of it. So a VC proved with the facts is true of the program. No fact restricts a value that the program can produce.

**Trust.** The facts rest on no assumption about a sealed builtin or a codegen choice beyond `*` itself. This differs from the `TRUST-AXIOM` population, which depends on what codegen emits. Decision 4 still proposes one disclosure line, because a reader of the VC meets `mul` and its facts. `verified` stays `verified`, with no cap.

## Affected surface

This is an addition to the reflected fragment. Its soundness argument is above.

- `compiler/src/LLMLL/FixpointEmit.hs`: the `*` arms of `exprToPredWD` and `bodyToPredM`; the normalization; a ground-fact pass per constraint; the `nonlinear:*` label, which now applies to `/`, `mod` and the rest, not to `*`.
- `compiler/src/LLMLL/AbstractionVerdict.hs`: `mul` as an abstracted term.
- `compiler/src/LLMLL/Syntax.hs`: `isCoreBodySyntactic`, under decision 3. `LLMLL.md` §12 `core-expr` excludes "non-linear ops" and must move with it.
- `compiler/src/LLMLL/HoleAnalysis.hs`: `isNonLinear` stops flagging a two-variable `*`, as `SIGMA-CONST-ARITH-1` did for a constant one. This also narrows the Lean worklist in `compiler/app/Main.hs`.
- `compiler/src/LLMLL/TrustReport.hs` and `docs/llmll-trust-report.schema.json`: one `assumed_facts` kind, under decision 4, with a minor increase of `trust_report_version`.
- **Fixtures that exist to show the refusal must move to a claim B cannot prove:** `examples/leanstral-demo/square.llmll` (the Lean demo loses its example), `scripts/doc-claims/nonlinear-body-fallback.llmll`, `scripts/tests/fixtures/fallback-census/census-constructs.llmll`, `scripts/tests/fixtures/fallback_attrib/attrib.llmll`, with `scripts/tests/test_fallback_attrib_1.py`, `scripts/tests/test_fallback_census.py` and `compiler/test/Spec.hs`.
- `LLMLL.md` §5.3.3 and §5.3.5; `docs/getting-started.md`; `docs/compiler-team-roadmap.md` (`MUL-VAR-1`, new `DIV-VAR-1`); `docs/design/INDEX.md`. These are the documentation-lead's.
- **Versions.** Clauses that did not translate now translate, and every clause that translated before emits the same term. So the `LLMLL.md` §4 rule for `checker_soundness_version` keeps the stamp, and it requires a byte-identical `.fq` sweep over the corpus as evidence. `proof_artifact_version` does not change, because no enum value is new: the construct is free text under the existing `abstraction-unsafe` cause. The engineer confirms both.
- **No conflict with `docs/design/byte-io-proposal.md`.** `BITWISE-1` keeps exact QF-LIA forms, and `band` keeps its own facts. `mul` adds a second symbol of the same kind. A shift by a variable stays refused.

## Ship order

This row depends on nothing unshipped. `CLAUSE-WELLDEF-1` and `ABSTRACTION-VERDICT-1` have shipped. It should land before the library's contract surface is written against `npix`, and before `FFI-KERNEL-1` if the kernel vocabulary is to change.

## Risks and open questions

1. **False witnesses lose `refuted`.** Verification-ergonomics. Cite: Verdict. Complicates: agents get a fallback, not a refusal, unless they use `--require-proof`. The cost is a loss of information, not of soundness.
2. **The witness set was written by the author of this record.** Scope. It covers the operations this library is expected to need, and a real library will meet more. Complicates: a miss gives a disclosed fallback. The Y4M and netpbm contracts should be re-stated as a first test.
3. **Fact volume.** Verification-ergonomics. Cite: measurement 2. Matters at scale: 22 terms cost 9.8 s, while the largest witness has 8. No real function was measured, because no real function can state a product today.
4. **The whole measurement used hand-built VCs.** Scope. The emitter's real path context, `let` binders and mixed theories were approximated, not run. Complicates: the first implementation step must repeat the table through `llmll verify`.
5. **The z3 version is unmeasured.** Soundness is not affected, since SAFE from a correct solver is a proof. Decisive for Option A. B stays in QF-UFLIA, which the existing emitter already uses, so less change is expected. That expectation is not measured.
6. **Trust in z3's nonlinear engine, under Option A only.** Soundness. Not measured, and not measurable here. Matters if decision 1 goes to A.
7. **The Lean demo loses `square`.** Scope. Cite: Affected surface. A new example is needed, such as W23.

### Proposed row, not filed

**`DIV-VAR-1`** (no contract can state a division or `mod` by a variable). An image library needs `(/ i w)` and `(mod i w)` to turn an offset into coordinates, and `(/ (* x sw) dw)` for nearest-neighbour resize. Haskell `div` and SMT `div` agree only for a positive divisor (`LLMLL.md` §5.3.3), so this needs a proved `divisor > 0`, a definedness entry under `CLAUSE-WELLDEF-1`, and its own facts. Measured under Option A: the three witnesses are SAFE, and one false variant is UNSAFE. It was not measured under Option B.

## Open questions for the professor

1. Is a one-round ground set of sign, monotonicity and row facts a known complete procedure for some useful class of bilinear integer constraints? If it is, the record can state that class in place of a witness count, and `LLMLL.md` §5.3.3 can claim it. If not, the claim stays "sound and incomplete". This changes the spec text that this record promotes.
