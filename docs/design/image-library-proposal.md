---
name: image-library-proposal
title: "IMAGE-LIB-1: an image library whose functions verify, with bytes-tabulate and variable divisors"
status: "Rev 3. Parts A, B and D SETTLED 2026-11-20 (user accepted decisions 1 to 5). Part C DRAFT, awaiting its witness table. Folds the security review of Rev 1 and the professor review of Rev 2 (image-library-review.md); dispositions in the appendix. No compiler code exists for Part B or Part C."
date: 2026-11-20
author: language-team
rows: "Proposes IMAGE-LIB-1 and BYTES-TABULATE-1 (not filed). Gives DIV-VAR-1 (G7, DECIDE) its encoding record. Related: MUL-VAR-1 (shipped v0.39.0), CLAUSE-WELLDEF-1 (shipped v0.37.0), CALL-RESULT-MARK-1 and ABSTRACTION-LEN-EXACT-1 (shipped v0.41.0), BYTES-MAKE-ALIAS-1 (shipped v0.40.1), INT-INDEX-WRAP-1 (shipped), CALLEE-POST-UNASSUMED-1 (shipped v0.36.0), ABSTRACTION-RESULT-LEN-1 (G1, DECIDE), CONE-DEF-DIRECTION-1 (DECIDE), POST-CALL-XMOD-1 (G1, DECIDE), SIG-SCALAR-ARM-1 (G1, DECIDE), PAIR-NEST-PROJ-1 (G1, PLAN), POST-CONJ-SPLIT-1 (G1, PLAN), FFI-KERNEL-1 (G7, PLAN), WEAKNESS-MUTANT-1 (G1), PERF-TEXT-1 (G8, MEASURE)."
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# IMAGE-LIB-1: an image library whose functions verify

**Settlement (2026-11-20).** The user accepted decisions 1 to 5 as recommended. Parts A, B and D are settled at Rev 3, and BYTES-TABULATE-1 goes to the compiler-engineer. Part C stays a draft until its witness table runs; decision 2 (the `d ≥ 1` rule) is settled independently of the fact set.

**Status: Rev 3.** The governing criterion is verified function coverage. A core function is covered when the trust report gives it the effective level `verified` and its post is proved to determine the result (Part D). Parts B and C are language additions, each with its soundness argument here.

**Changes from Rev 2,** after the professor review (findings P1 to P9, `image-library-review.md`):

- **Part B drops the content fact C.** No function in the plan reads a tabulate result, so C added a trusted axiom with no use (P2). `bytes-tabulate` now carries a length lemma only, in the class of `bytes-make`. Content export is deferred to a later design based on abstract refinements.
- **Part C replaces D1 to D3** with one two-way schema G, the Galois connection of floor division, plus D0 and a congruence fact D4. Each instance set is defined over the MUL-VAR-1 rule closure. Pass order, invariance and limits are stated. Rev 3 shows by hand that the plan's three hard witnesses are covered (P1).
- **The `geom` posts carry range conjuncts,** so callers see linear facts only (P7).
- **Part D defines "exact" by a determinacy check** (P4), splits the measure into a covered set and a refutation rate (P3), and adds three mutation operators (P5).
- Smaller items: `sigmaAutoPred` refuses variable divisors (P6); `checker_soundness_version` does not change (P8); codegen forces the arguments (P9).

Rev 2's changes after the security review of Rev 1 (findings H1 to H5, M1 to M4, L1 to L5) are kept; the appendix maps both reviews.

## Summary

The library holds an image as a `bytes` buffer with its width, height and channel count passed as separate `int` arguments. No core signature carries a pair, a list or a `Result`. This is the shape of the y4m core, which verifies all 29 of its core functions today.

Two additions:

- **Part B, `bytes-tabulate`.** A sealed builtin that builds an n-byte buffer from a named, verified generator in O(n), with run-time guards. The solver learns its length. The per-pixel guarantee is proved in the generator, not reflected through the buffer.
- **Part C, DIV-VAR-1.** Division and `mod` by a variable with a proved `d ≥ 1`. Coordinate arithmetic, the generators' exact posts and nearest-neighbour resize need it.

Part D defines coverage from the trust report and a determinacy check, with two CI ratchets.

## Background: the measurement

Measured on llmll 0.41.1 (2026-11-19), liquid-fixpoint 0.9.6.3.7. Every module of `examples/netpbm`, `examples/netpbm-swarm` and `examples/y4m` was verified with `--json verify` in dependency order, in a copy of the tree. The per-function tally is a session file and is not committed.

| Example | Representation | Pure core verified | All functions verified |
|---|---|---|---|
| y4m | `bytes` plus `int` offsets, one core level per module | 29 / 29 (`hdr`, `raster`, `xform`, `ybuf`) | 39 / 85 |
| netpbm-swarm | lists and maps, small modules | 48 / 48 in the leaf modules | 59 / 105 |
| netpbm | lists and nested pairs, one large module | 3 / 43 in `netpbm.llmll` | 34 / 87 |

In total, 132 of 277 functions verify. `body_faithful` in `--json verify` lists a function even when its post is refuted (security finding H4), so the count was redone from `--json trust-report`, restricted to each module's own functions. All 25 module runs report `success: true`. The trust report gives `verified (liquid-fixpoint)` for exactly the 132 body-faithful functions. The 145 others are `asserted` (71) or carry no level (74, the functions with no contract). The baseline stands.

| Cause of the 145 (`body_fallback_causes`, `Refused by`) | Functions | Remedy |
|---|---|---|
| No contract, or a `pre` with no `post` | 74 | Write contracts. Not a compiler change. |
| `post` calls `image-ok?`, a fold over a list | about 16 | A `bytes` representation, where well-formedness is a length equation (MUL-VAR-1) |
| `guard:signature`: a `Result` or pair that carries a list or an image | 22 | SIG-SCALAR-ARM-1, or a representation without such signatures |
| List folds, lambdas, `list-nth`, `unwrap-or` in a body | about 13 | A `bytes` representation |
| Nested pair accessors and their dependants | about 10 | PAIR-NEST-PROJ-1, or no pairs in the core |
| Text parsing (`regex-match`, `string-to-int`) | about 6 | Keep in the shell |

**Two facts decide the design.**

1. `bytes-set` copies the whole buffer. `llmll_bytesSet` in `compiler/src/LLMLL/CodegenHs.hs` returns `BS.concat [BS.take k b, BS.singleton v, BS.drop (k + 1) b]`. A pixel loop over `bytes-set` is O(n²): about 10¹² byte copies for one megapixel.
2. The O(n) builders tell the solver only a length. `LLMLL.md` §5.3.3, "The byte type of any length": `bytes-make`, `bytes-slice`, `bytes-concat` and `bytes-concat-many` give a fresh term with a length fact and no content fact.

So no operation today builds an output image fast from verified per-pixel code. FFI-KERNEL-1 makes it fast, but a C kernel is trusted, not verified, so it lowers coverage.

## Restatement

Design an image library that maximizes verified coverage, and the two language additions it needs. The library parses untrusted files, and a false `verified` is treated as a security failure, not only a defect. The measurement set is the three examples above. The design-reference set is Liquid Haskell, Dafny, Verus and F\*, which state "every output pixel equals f of the input" as a quantified invariant or an index-dependent refinement. LLMLL has no quantifiers in the fragment, so this design proves the per-pixel statement once per generator, at a symbolic index, and builds the buffer from verified generators.

## Context located

1. `examples/y4m/ybuf.llmll`, `examples/y4m/raster.llmll`: the pattern that verifies. `bytes` plus `int` parameters, sentinel `-1` returns, one level per module, `def-shell` with `decreases` for loops.
2. `LLMLL.md` §5.3.3, array class and "The byte type of any length": `bytes-get`/`bytes-set` exact; the builders give length only.
3. `LLMLL.md` §13.12, "The sealed-builtin axiom set": closed at thirteen; `bytes-make` carries a length lemma only, on a fresh term. A content reflection is sound only on a term that cannot appear twice with different lengths (BYTES-MAKE-ALIAS-1).
4. `compiler/src/LLMLL/FixpointEmit.hs`: `sealedAxiomBuiltins`, `abstractedBuiltins`, `exactSealedBuiltins` (where `bytes-tabulate` joins `bytes-make`); `nonlinearOps`; `extractQualifiers`, whose comment states that body VCs are path-enumerated with no kvars.
5. `compiler/src/LLMLL/CodegenHs.hs`: `bytes_make` checks length, value and `maxBound` before it narrows (INT-INDEX-WRAP-1); `/` lowers to Haskell `div` and `mod` to `mod`. `int` lowers to `Integer`.
6. `compiler/src/LLMLL/GuardClassifier.hs`, `constArithTerm`: only a numeral divisor greater than zero is admitted today.
7. `compiler/src/LLMLL/ObligationMining.hs`, `isSigmaAuto` and `sigmaAutoPred`: the Σ_auto test that MUL-VAR-1 Amendment 1 narrowed for products.
8. [`mul-var-proposal.md`](mul-var-proposal.md) Rev 3b: "Rules", "Fact set", "Invariance", "Limits". Part C extends each of them. Decision 5 filed DIV-VAR-1.
9. `LLMLL.md` §4.4: the record key counts a function passed as a value; the termination graph treats it as an edge. §4.4.6: the evidence axis and the discriminative axis are kept apart. §4.7: call-by-value.
10. [`clause-welldef-proposal.md`](clause-welldef-proposal.md): the definedness entry `π` and the `ill-defined` status that Part C extends.
11. [`tier-route-1-proposal.md`](tier-route-1-proposal.md) (Rev 1, DRAFT): `bytes-tabulate` adds a sealed-builtin entry, so it takes the full track.
12. `scripts/fallback_census.py`: measures fragment width. It copies `body_faithful` whatever the verdict, so it is not a coverage source.
13. [`image-library-review.md`](image-library-review.md): the professor review of Rev 2.

## Part A: the library

### Representation

The verified core never holds an image as one value. A raster is four arguments: `buf: bytes`, `w: int`, `h: int`, `c: int`. Its invariant is a `pre`, with a sample cap:

```lisp
(and (>= w 1) (and (>= h 1) (and (or (= c 1) (= c 3))
     (and (<= (* (* w h) c) 268435456)
          (= (bytes-length buf) (* (* w h) c))))))
```

The cap is 2²⁸ samples (256 MiB, about 89 megapixels at `c = 3`). It is a literal in the `pre`, so every core entry proves it, and every `bytes-tabulate` length in the core is bounded by it. The row stride is `(* w c)`. Samples are 8-bit, so maxval is 255. A file with another maxval gets a sentinel error at decode. Parsers return an `int`, with a negative code for an error, as `find-lf` in the y4m core does. This shape avoids SIG-SCALAR-ARM-1 and PAIR-NEST-PROJ-1 in the core.

### Untrusted input

The decoders follow four rules:

1. **Digit cap.** A header number has at most 9 digits. The scan returns a sentinel at the tenth digit. This bounds the work per number and stops the quadratic `Integer` growth that the current y4m digit loop allows (`examples/y4m/hdr.llmll`, the digit accumulator).
2. **Size check first.** The decoder compares the declared `w·h·c` with the cap and with the remaining payload bytes before any other step. A mismatch is a sentinel.
3. **No allocation by header.** Decode slices the input. It never calls `bytes-make` or `bytes-tabulate` with a length taken from a header before rule 2 passes.
4. **Errors are values.** Every header or payload mismatch gives a sentinel, so a hostile file yields an error message. The raster `pre` at the shell-to-core call is then a backstop. The shell is a `def-shell` that does I/O, so that `pre` is enforced by the run-time check, which `--contracts` never strips. It fails closed with exit 1.

`ops.resize` bounds its targets by the same cap in its `pre`.

### Module layout

Leaf first. No `def` calls a `def` in its own module; each level calls only lower levels, which are verified first. The table is normative for Part D: a module's level decides whether its functions are core, not the `def` or `def-shell` keyword.

| Level | Module | Contents |
|---|---|---|
| L0 | `px` | Point kernels: `invert-v`, `threshold-v`, `gray-v`, `clamp-v`. Pure `int → int`. |
| L0 | `geom` | Index arithmetic: `offset`, `row-of`, `col-of`, `chan-of`, `hflip-x`, `vflip-y`, `clamp-idx`, `scale-src`. Each post is an equation plus a range. |
| L1 | `at` | Per-index generators `*-at [buf w h c … i] -> int`. Each body calls `geom` and `px` and reads with `bytes-get`. Each post states the result exactly, with the source index written out in-line. |
| L2 | `ops` | Whole-image operations. Each body is one `bytes-tabulate` over an `at` generator. Shape-verified (Part D). |
| L1 | `pnm-hdr`, `y4m-hdr` | Byte-level header scans with `decreases` and the digit cap. `y4m-hdr` reuses the y4m core. |
| L2 | `pnm`, `y4m` | Encode and decode as offsets and slices, with sentinel errors and the size check first. |
| shell | `main` | `def-shell` only: argv, `wasi.fs`, dispatch. Counted apart (Part D). |

The library starts in a new `examples/image` directory. It moves to the hub when the API settles.

### Contract plan

Each clause is written before its body. A post may not call an imported `def` until POST-CALL-XMOD-1 is decided, so each `*-at` post restates its source index as arithmetic. The decomposition of an index `i` with stride `s = w·c` is `y = i / s`, `x = (i mod s) / c`, `k = i mod c`.

**Ranges live in `geom` (P7).** Each `geom` post carries its range as a conjunct. A `*-at` body that calls `geom` then receives linear facts, `0 ≤ y < h` and so on, and does not repeat the nonlinear proof. The `*-at` post still contains division, so its well-definedness under CLAUSE-WELLDEF-1 uses Part C; the hand derivation for `hflip-at` is in Part C.

| Function | `pre` | `post` | Example mutant |
|---|---|---|---|
| `geom.offset [w h c y x k]` | `0≤y<h`, `0≤x<w`, `0≤k<c`, `w,h,c ≥ 1` | `(and (= result (+ (* (+ (* y w) x) c) k)) (and (>= result 0) (< result (* (* w h) c))))` | swapped `x` and `y` with `w` and `h`: `(+ (* (+ (* x h) y) c) k)` |
| `geom.row-of [w c h i]` | `w,c,h ≥ 1`, `0 ≤ i < w·h·c` | `(and (= result (/ i (* w c))) (and (>= result 0) (< result h)))` | factor deletion: `(/ i w)` |
| `geom.col-of [w c h i]` | as `row-of` | `(and (= result (/ (mod i (* w c)) c)) (and (>= result 0) (< result w)))` | operator replacement and factor deletion: `(mod i w)` |
| `geom.chan-of [c i]` | `c ≥ 1`, `i ≥ 0` | `(and (= result (mod i c)) (and (>= result 0) (< result c)))` | `/` for `mod`: `(/ i c)` |
| `geom.hflip-x [w x]` | `w ≥ 1`, `0 ≤ x < w` | `(= result (- (- w 1) x))` | literal off by one: `(- w x)` |
| `geom.scale-src [sw dw x]` | `sw,dw ≥ 1`, `0 ≤ x < dw` | `(and (= result (/ (* x sw) dw)) (and (>= result 0) (< result sw)))` | index off by one: `(/ (* (+ x 1) sw) dw)` |
| `px.invert-v [v]` | `0 ≤ v ≤ 255` | `(= result (- 255 v))` | literal off by one: `(- 254 v)` |
| `px.threshold-v [v t]` | `v, t` in `0..255` | `(or (and (>= v t) (= result 255)) (and (< v t) (= result 0)))` | relational replacement: `(if (> v t) 255 0)` |
| `px.gray-v [r g b]` | each in `0..255` | `(= result (/ (+ r (+ g b)) 3))` | literal: `(/ (+ r (+ g b)) 2)` |
| `at.invert-at [buf w h c i]` | raster invariant, `0 ≤ i < (bytes-length buf)` | `(= result (- 255 (bytes-get buf i)))` | index off by one: `(invert-v (bytes-get buf (+ i 1)))` |
| `at.hflip-at [buf w h c i]` | as `invert-at` | `(= result (bytes-get buf (+ (* (+ (* y w) (- (- w 1) x)) c) k)))`, with `y`, `x`, `k` written out from `i` as above | identity body: `(bytes-get buf i)`, the WEAKNESS-MUTANT-1 mutant |
| `ops.invert [buf w h c]` | raster invariant | `(= (bytes-length result) (bytes-length buf))` | shape-verified; no pointwise mutant is refuted |
| `ops.crop [buf w h c x0 y0 cw ch]` | raster invariant, the window inside the image | `(= (bytes-length result) (* (* cw ch) c))` | shape-verified |

Every example mutant in this table is produced by the Part D mutation set, and a test holds that (P5). `gray-v` uses a positive numeral divisor, which is admitted today, so it does not need Part C. `vflip`, `grayscale`, `blur` (3×3, clamped indices, `/ … 9`) and `resize` (nearest-neighbour through `scale-src`) follow the same `*-at` and `ops` pattern.

**What is proved, and where.** The per-pixel statement, such as "the byte at index `i` is `255 −` the input byte at `i`", is proved once in each `*-at` generator at a symbolic `i`. That is a statement for every `i` in range, by ∀-introduction. `bytes-tabulate` stores exactly the generator's value at each index, by the codegen of Part B. So the whole-image statement holds at run time, and it rests on the codegen stamp, as every sealed builtin does. The solver does not see the whole-image statement: an `ops` post states the length only, and a caller of an `ops` function learns the length and not the content. The whole-image statement is also stated as a `check` with `for-all`, for tested evidence. Text parsing stays in the shell; the header scans read bytes, not strings.

## Part B: `bytes-tabulate`, an addition

### Surface

```lisp
(bytes-tabulate n gen a1 … ak)   ; gen : T1 … Tk int -> int
```

`gen` must be the bare name of a top-level `def` (not `def-shell`) that has a `post`. A lambda, a function-typed parameter or a `def-shell` is the type error `tabulate-gen-not-named`. The arity is checked against `gen`'s signature, and the last parameter of `gen` is the index. JSON-AST: `{"kind":"app","fn":"bytes-tabulate","args":[n, {"kind":"var","name":"gen"}, a1, …, ak]}`. No new node kind.

### Semantics

`result` has length `n`, and `result[i] = gen(a1, …, ak, i)` for `0 ≤ i < n`. Evaluation is call-by-value: `n` and `a1 … ak` are evaluated once, in order, before the index loop. Codegen forces each of them explicitly, because generated Haskell is lazy and an unforced argument would never be evaluated at `n = 0` (P9). Then each `gen` call runs in index order.

Codegen has the same run-time backstop as `bytes_make`:

1. Stop with the `bytes_make` message when `n < 0`.
2. Stop with "too large to represent" when `n > maxBound :: Int`, before any narrowing.
3. Stop with "outside byte range 0..255" when a `gen` value is outside `0..255`, before narrowing it to `Word8`.

After these checks the buffer is filled in place (`BS.unfoldrN` or `unsafeCreate`), in O(n) time and O(n) space. `BS.pack` over a list is not acceptable: it holds the whole list before it allocates. `gen` is pure and the result is fresh, so strict immutability holds. Under the raster `pre` the guards cannot fire in the core.

### Obligations at a call site (PROVE polarity)

Let `ι` be a fresh integer constant for the call site.

- **T1.** `n ≥ 0`.
- **T2, the generator's `pre` over the range.** `0 ≤ ι < n ⟹ pre_gen(a, ι)`.
- **T3, the byte range.** `0 ≤ ι < n ∧ pre_gen(a, ι) ∧ post_gen(a, ι, v) ⟹ 0 ≤ v ≤ 255`, with `v` fresh.

A fresh constant stands for an arbitrary index, so one proof covers all of them. This is ∀-introduction. It holds because `ι` occurs in no hypothesis except its range, and the body VCs have no kvars that could capture it. If kvars ever return to body VCs, this argument must be restated. T2 means the run-time `pre` check of `gen` never fails inside a verified caller. T3 means guard 3 never fires.

### Fact for the caller

**L, the length.** `bytesLen(r) = n`, on a fresh term `r`. It is exact when `n` is exact (ABSTRACTION-LEN-EXACT-1). `bytes-tabulate` joins `bytes-make` in the abstracted builtins: an UNSAFE answer resting on its result falls back with `abstraction:app:bytes-tabulate`, exit 0. No content fact is emitted, and reads of `r` carry only the byte-range fact that every `bytes` read has.

`r` is fresh for each AST occurrence and is never keyed on text or on `(gen, args)`. With no content fact, two occurrences cannot become one term, which is the failure BYTES-MAKE-ALIAS-1 had. If a congruence rule is ever added, its key must include `n`, `gen` and every `aᵢ`, as F\* keys `Seq.init`.

### The generator is a callee

Passing `gen` to `bytes-tabulate` is a callee edge, with the same effect as a direct call, for every computation that reads callees:

- the effective level (the meet over callees), so a caller of an `asserted` generator is not `verified`;
- `refutedClosure` and the `depends-on-refuted` drift;
- `--strict-verified-core` admission and CALLEE-POST-UNASSUMED-1;
- the import staleness gate and the `verified_hash` record key, which already count a function passed as a value (`LLMLL.md` §4.4);
- the termination graph, so a cycle through a generator is refused like a cycle through a call.

A tabulate whose generator is not body-faithful and `verified` is admitted, and the caller falls back with the named cause `tabulate-gen-unverified`. The edge matters even without a content fact: T2 and T3 use `gen`'s contract, and the run-time content of the buffer is the generator's.

### Soundness argument

1. L is the length lemma of a fresh term, the same lemma `bytes-make` carries. Codegen produces a buffer of length `n` or stops. The trusted base grows by one sealed builtin with a length lemma and no reflection, so the set goes from thirteen to fourteen.
2. T1 to T3 are proof obligations, not assumptions. They add no trust.
3. The guards make the run-time behaviour match L even when a contract is stripped or a generator is wrong: the program stops rather than narrow a value.
4. The restriction on `gen` makes T2, T3 and the callee edge checkable: a lambda has no `post` to instantiate and no name to put in the graph.

### Later extension, not proposed: content export

Rev 2 proposed a per-read content fact C. The professor review showed that it is sound but has no consumer in the plan, so Rev 3 drops it. The route to export content later is an index-dependent refinement on the `bytes` result, after Vazou, Rondon and Jhala, *Abstract Refinement Types* (ESOP 2013). Liquid Haskell types a vector as `Vec <rng :: Int -> a -> Bool>`, and a read instantiates `rng` at its index. Here the refinement would be `post_gen` carried on the result type of an `ops` function, so a caller gets the generator's post at each of its own reads. This needs no array equality and no `tabulated` atom. It would let `ops` functions become covered rather than shape-verified. It needs its own design record.

## Part C: DIV-VAR-1, division and `mod` by a variable

### Surface and definedness

No new syntax. `(/ e d)` and `(mod e d)` with a non-constant `d` become admissible in clauses and in bodies. `d ≥ 1` is required at each evaluation point:

- in a body, as a PROVE call-site obligation, like the index of `bytes-get`;
- in a clause, as a CLAUSE-WELLDEF-1 entry with `π = d ≥ 1`, which gives the status `ill-defined` when it is not proved.

The bound is `d ≥ 1`, not `d ≠ 0`. For `d ≥ 1`, Haskell `div` and `mod` (floored, Haskell 2010 Report §6.4.2) and SMT-LIB `div` and `mod` (Euclidean) agree, because both give `0 ≤ r < d` and the same quotient for every sign of `e`. For `d < 0` they differ. `rem` and `quot` stay refused. A ground divisor keeps its current treatment: a positive numeral is admitted, and zero or a negative numeral stays refused, as `constArithTerm` refuses them today.

### Every emission site

The division pass rewrites every `/` and `mod` with a variable divisor before emission. This covers bodies, `pre` and `post` clauses, CLAUSE-WELLDEF-1 `π` terms, and callee clauses instantiated at a call site. The check that keeps products out of qualifiers is extended to division. The atoms are bound in each constraint's environment, never as global constants. A raw `e / d` therefore never reaches liquid-fixpoint, where SMT-LIB semantics at `d ≤ 0` would differ from Haskell.

**Σ_auto (P6).** `sigmaAutoPred` in `compiler/src/LLMLL/ObligationMining.hs` refuses a variable divisor, as MUL-VAR-1 Amendment 1 made it refuse a product. Without that, four consumers (`classifyContractFragment`, the strength decision in `ObligationMining`, CLASSIFY-MEASURE and `RefineReuse.buildSubsumptionFQ`) would label a division clause as auto-discharged. The let-binding hints of `compiler/src/LLMLL/Checkout.hs` do not admit division in the first implementation.

### Normal form and pass order

This extends the MUL-VAR-1 normal form. Each distinct pair `(e, d)`, after normal form, gets two atoms, `div##k` and `mod##k`. `(/ e d)` and `(mod e d)` on the same pair share them.

The passes run in this order:

1. Callee-post substitution.
2. The division pass: atoms, then the facts below.
3. The MUL-VAR-1 product pass. Every monomial that a division fact creates, such as `d·q` or `d·t`, enters the product pass's pair set `P`, so the F facts apply to it.

### Facts

`q` is `div##k` and `r` is `mod##k` for the pair `(e, d)`. Each fact is a flat hypothesis with its premises, as in MUL-VAR-1.

| Fact | Statement | Instances | Certificate |
|---|---|---|---|
| D0 definition | `d ≥ 1 ⟹ e = d·q + r ∧ 0 ≤ r ∧ r ≤ d − 1` | each pair | Euclidean division |
| G Galois | `d ≥ 1 ⟹ (d·t ≤ e ⟺ t ≤ q)`, and `d ≥ 1 ⟹ (q ≤ t ⟺ e ≤ d·t + d − 1)` | each pair, for each `t` in the trigger set below | floor division by `d ≥ 1` is the upper adjoint of multiplication by `d` (Graham, Knuth and Patashnik, *Concrete Mathematics*, ch. 3) |
| D4 congruence | `e = e′ ∧ d = d′ ⟹ q = q′ ∧ r = r′` | each two pairs; and each pair that a MUL-VAR-1 rule changes, with the rule's equation as premise, as F9 does | congruence |

G is emitted as four implications, one per direction of each equivalence. G at `t = a` with D0 gives the uniqueness of Rev 2's D1. G at `t = B − 1` gives Rev 2's D2. Monotonicity, Rev 2's D3, follows from G by transitivity. So G replaces three schemas and three instance rules with one schema and one trigger rule.

**The trigger set of G for a pair `(e, d)`** is the union of:

- **T-zero.** `t = 0`.
- **T-literal.** For each comparison or equality literal in the constraint, at any depth and after normal form, that relates `q` with coefficient ±1 to a term `u`: `t = u`, and `t = u − 1` when the literal is strict.
- **T-cofactor.** For each monomial `m` of the MUL-VAR-1 closure that `d` divides as a monomial: `t = m / d − 1`.

Each part is defined over sets of literals and monomials, so the trigger set reads no order and no name.

**Not included.** The nested-divisor law `(x / c) / d = x / (c·d)` and the breakdown law `x mod (y·z) = y·((x / y) mod z) + x mod y`, which the IronFleet and Verus `div_mod` libraries carry. The library writes the column as `(/ (mod i (* w c)) c)`, which needs neither. An author who writes `(mod (/ i c) w)` needs the breakdown law. Each is added only if a witness needs it.

### Hand derivations (answering the review's open question 1)

These are derivations on paper. The witness table must confirm each one.

**`scale-src` range.** `q = (x·sw) / dw`, `pre`: `sw, dw ≥ 1`, `0 ≤ x < dw`. The post literal `q < sw` gives T-literal `t = sw − 1`. G gives `q ≤ sw − 1 ⟸ x·sw ≤ dw·(sw − 1) + dw − 1 = dw·sw − 1`. F5 on the pair `(x, sw)` against `(dw, sw)` gives `x·sw + sw ≤ dw·sw`, and `sw ≥ 1` gives the rest. The monomial `dw·sw` exists only after G creates `d·t`, which is why the pass order puts the product pass last. `q ≥ 0` comes from T-zero: `0 ≤ x·sw` by F1.

**Edge case 7 at `sw = 1`.** The same T-literal instance gives `q ≤ 0`, and T-zero gives `q ≥ 0`, so `q = 0`. Rev 2 claimed this from D0, which needs a nonlinear step. G does not.

**`hflip-at` read bound.** Let `s = w·c`, `q₁ = i / s`, `r₁ = i mod s`, `q₂ = r₁ / c`, `r₂ = i mod c`. The source index is `q₁·s + (w − 1 − q₂)·c + r₂`.

- T-cofactor on the monomial `w·h·c` of the raster `pre`, with `d = w·c`, gives `t = h − 1`. G then gives `q₁ ≤ h − 1`, because `i ≤ w·h·c − 1`. T-zero gives `q₁ ≥ 0`.
- D0 gives `0 ≤ r₁ ≤ w·c − 1`. T-cofactor on `w·c` with `d = c` gives `t = w − 1`, and G gives `q₂ ≤ w − 1`. T-zero gives `q₂ ≥ 0`.
- D0 gives `0 ≤ r₂ ≤ c − 1`.
- In normal form the source index is `q₁·w·c + w·c − c − q₂·c + r₂`. F4 on `(q₁, w·c)` gives `q₁·w·c ≤ h·w·c − w·c`. F1 on `(q₂, c)` gives `q₂·c ≥ 0`. With `r₂ ≤ c − 1` the sum is at most `w·h·c − 1`, which is `bytes-length buf − 1`. The `≥ 0` side follows from F1 on `(q₁, w·c)`, `q₂ ≤ w − 1` with F4 on `(q₂, c)`, and `r₂ ≥ 0`.

This derivation uses three pairs and about twelve F facts, well under the 64-pair limit.

**`row-of` against a body with a let-bound stride.** A post `(/ i (* w c))` and a body that binds `stride` to `(* w c)` and returns `(/ i stride)` give two pairs. The rule `stride → w·c` makes D4 fire with that equation as its premise, so `q = q′`.

### Invariance, limits and termination

- **Invariance.** The pair set, the trigger set and the D4 instances are defined over sets of conjuncts, literals and closure monomials. So the fact set satisfies the three MUL-VAR-1 properties: unchanged under a permutation of conjuncts and an exchange of equation sides, and renamed under a renaming of variables. The MUL-VAR-1 invariance test extends to division witnesses.
- **Limits.** Monomials that G creates count against the MUL-VAR-1 limits of degree 6 and 256 monomials, and their pairs against the 64-pair limit. A further limit of 32 division pairs in one constraint refuses the constraint whole, with `nonlinear:/`. No witness is expected to approach it; the first implementation step rereads it.
- **Termination.** The pair set is fixed by the division pass. No fact creates a division, and the trigger set is finite. So generation ends.

### Refutation

As MUL-VAR-1 decision 2. A `sat` answer is checked again by native z3 with `/` and `mod` read as Haskell `div` and `mod` under the proved `d ≥ 1`. Only a validated `sat` gives `refuted`. An `unknown` from the recheck gives the fallback outcome.

### Version stamps

`checker_soundness_version` does not change (P8). Each fact is a theorem, and Part C admits only terms that were refused before, so no earlier `verified` sidecar becomes false. This follows MUL-VAR-1, "Changing the fact set".

### Witness table (not run)

A script-built table in the manner of the MUL-VAR-1 `rev3.py`, with the fact count and solver time for each row:

1. `row-of`, `col-of`, `chan-of`, `scale-src` and `hflip-at`, each with its range conjuncts, and each generated mutant;
2. `scale-src` at `sw = 1` (edge case 7);
3. the let-bound stride against `(* w c)` (D4);
4. a round-trip statement `row-of(offset(y, x, k)) = y`, which tests G at `t = y`;
5. the MUL-VAR-1 shadowing probe adapted to division, which must be `refuted`;
6. a clause `(=> (>= d 1) (= (/ e d) q))` against the unguarded `(= (/ e d) q)`, where the second must be `ill-defined`;
7. a negative ground divisor and a zero ground divisor, which must stay refused;
8. the invariance test over rows 1 to 4.

Part C does not settle before this table exists.

## Part D: coverage metric and CI ratchets

### Exact posts

A post is **exact** when the compiler proves its determinacy VC:

```
pre(x) ∧ post(x, r₁) ∧ post(x, r₂) ⟹ r₁ = r₂          (illustrative)
```

The VC uses two fresh result symbols in the same fragment, with the same product and division facts. It is the solver form of a discriminative power of 1 (`LLMLL.md` §4.4.6): the post admits exactly one result on every input in the `pre` domain. A `bytes` result cannot pass it without extensionality over all indices, so every `ops` function fails it. Range-only and length-only posts fail it. A post that mentions `result` and still admits many values, such as `(or (= result (- 255 v)) (>= result 0))`, fails it.

### Classes

Every library function falls in exactly one class. The class is recomputed in CI from the compiler, never read from a committed file.

- **covered.** The function's `--json trust-report` entry has the effective level `verified`. It is not in `refuted_fns`, has no `depends-on-refuted` drift, is not `termination_assumed` and is not `overflow_tainted`. Its post is exact.
- **shape-verified.** As covered, except that the post is not exact. All `ops` functions are here until the content-export extension exists.
- **uncovered.** Every other core function: no `post`, a fallback, or a refuted post.
- **shell.** Every function in a module at the shell level of the module table, reported with its level.

`body_faithful` from `--json verify`, and therefore `scripts/fallback_census.py`, is not a coverage source.

A determinacy VC that is true but not proved, through verifier incompleteness, classes a function as shape-verified. That costs coverage and never claims too much.

### Mutants and the refutation rate

Mutants measure a different thing from coverage (P3). Once a post is exact and the function is verified, every mutant that is not equivalent violates the post on some input. Whether the verifier then answers `refuted` or falls back measures the verifier's refutation completeness, not the strength of the specification. `LLMLL.md` §4.4.6 keeps these two axes apart, and Part D does too.

Mutants are generated from the JSON-AST. For each core function the generator applies a fixed set of operators, after Offutt, Lee, Rothermel, Untch and Zapf, *An Experimental Determination of Sufficient Mutant Operators* (TOSEM 1996):

1. **Constant.** Each integer literal off by one, in both directions.
2. **Index.** Each index term off by one, in both directions.
3. **ROR.** Each of `<`, `<=`, `>`, `>=`, `=`, `/=` replaced by each other.
4. **AOR.** Each of `+`, `-`, `*`, `/`, `mod` replaced by each other, including `/` and `mod` by each other.
5. **Factor deletion.** Each factor of a product deleted.
6. **Swap.** Each pair of same-typed arguments swapped, at each call and in the arithmetic.
7. **Identity.** Return the first argument of the result type.
8. **Constant result.** `0`, and `255` for a byte-valued function.
9. **Generator.** For a `*-at` generator or an `ops` body, another library generator of the same signature.

A mutant that does not type-check is dropped. Each outcome is one of three:

- **refuted**: counted in the rate.
- **fallback**, including `abstraction:`: counted against the rate. It never counts as refuted.
- **verified**: under a proved determinacy VC, the mutant is equivalent to the original on the `pre` domain, or the verifier is unsound. Each such mutant goes to a reviewed equivalence file with its reason. An entry that a reviewer cannot explain is a soundness alarm.

The **refutation rate** is refuted mutants divided by non-equivalent mutants, over the core outside `ops`.

### Ratchets

- **Covered set.** The baseline is the set of covered functions, in a reviewed file in `examples/image`. CI prints the diff of that file in its summary whenever it changes. A pinned version-gate step fails when a function in the baseline set is missing or not covered, and when a new core function outside `ops` is not covered.
- **Refutation rate.** A second baseline holds the rate. CI fails when it falls. ABSTRACTION-RESULT-LEN-1 and CONE-DEF-DIRECTION-1 are the rows that would raise it.
- **Core or shell** comes from the module table in Part A. Moving a function between levels is an edit to that table and to this record.
- **Targets.** Covered set: every core function outside `ops` at the first release; the y4m core shows this is possible. Shape-verified: every `ops` function. The refutation rate is reported with no target, because it depends on verifier rows outside this record.

## Edge cases and degenerate inputs

1. **`w = 0` or `h = 0` in a file header.** The decoder returns a sentinel. The raster `pre` stops any core function from receiving it; at the shell-to-core call that `pre` is a run-time check. Channel: contract.
2. **Refutation of a wrong divisor.** `row-of` with body `(/ i w)`. At `w = 2`, `c = 3`, `i = 3` the body gives 1 and the post requires 0. Expected: `refuted`, after the native recheck. Channel: contract. This tests refutation, not a G instance.
3. **Positive witness for T3.** `(def bad-at [buf: bytes i: int] -> int (pre (and (>= i 0) (< i (bytes-length buf)))) (post (>= result 0)) (+ (bytes-get buf i) 1))`, used as `(bytes-tabulate (bytes-length buf) bad-at buf)`. T3 fails at `v = 256`. Expected: the caller does not verify, and the message names T3. Channel: contract. Codegen: the same program run with contracts stripped stops at the first byte 255 with "outside byte range 0..255".
4. **Negative controls for aliasing.** Each must not verify. Channel: contract.
   - 4a. A function that builds `r1 = (bytes-tabulate 3 g a)` and `r2 = (bytes-tabulate 5 g a)` with post `(= (bytes-length r1) (bytes-length r2))`: expected `refuted`.
   - 4b. The same two tabulates in a body whose post is `false`: expected not verified.
   - 4c. As 4a, with both lengths named `n` in nested `let`s, `3` outside and `5` inside: expected `refuted`.
5. **`n = 0`.** T2 and T3 hold with a false premise. Codegen returns the empty buffer and calls `gen` zero times, after forcing `a1 … ak`. A test passes an argument that stops the program, `(bytes-get buf 99)` on a 4-byte `buf`, with `n = 0`: expected a run-time stop. Channel: codegen test.
6. **A negative divisor**, such as `(/ x (- 0 w))`. `d ≥ 1` fails: the body is not proved, or the clause is `ill-defined`. Haskell would run it, so the fragment is narrower than the language on purpose. Channel: contract.
7. **Resize with `dw > sw`, or `sw = 1`.** G gives `0 ≤ q ≤ sw − 1`, and `q = 0` at `sw = 1` (Part C, hand derivations). Channel: contract.
8. **PNM maxval other than 255, or 16-bit samples.** The decoder returns a sentinel. The spec is silent on 16-bit samples, on purpose, for the first release.
9. **Hostile headers.** A width of 10⁶ digits: sentinel at the tenth digit. `w·h·c` above 2⁶³: sentinel from the cap before any allocation. `w·h·c` far larger than the file: sentinel from the size check. Channel: contract on the scan posts, and a pytest on each file.
10. **Tabulate length past `maxBound :: Int`.** Outside the core only, since the raster `pre` bounds every core length. A `def-shell` calling `(bytes-tabulate 18446744073709551621 g)`, which is 2⁶⁴ + 5: expected run-time stop with "too large to represent", not a 5-byte buffer. Channel: codegen test.
11. **Unverified generator.** A generator whose body falls back, used by a tabulating caller. Expected: the caller's effective level is not `verified`, the cause is `tabulate-gen-unverified`, and the caller is uncovered. Channel: trust.
12. **Cycle through a generator.** `f` tabulates over `g`, and `g` calls `f`. Expected: refused as an undischarged recursion. Channel: type and termination.
13. **Positive witness for the determinacy check.** `geom.hflip-x` with post `(= result (- (- w 1) x))` passes and is covered. The same function with post `(and (>= result 0) (< result w))` verifies, fails determinacy, and is shape-verified. Channel: trust.

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Raster invariant, the sample cap, `offset` post | contract | (a) QF-LIA with MUL-VAR-1 product facts |
| `geom` division posts and their ranges; `*-at` source-index posts | contract | (b) nonlinear, kept decidable by D0, G and D4. Not measured. |
| `*-at` reads, given `geom` ranges | contract | (a) QF-LIA with the array class |
| Point kernels | contract | (a) QF-LIA |
| T1, T2, T3 at a tabulate | contract | (a) QF-LIA with one fresh constant |
| L at a tabulate | trust: sealed-builtin length lemma on `codegen_semantics_version`, backed by the run-time guards | quantifier-free |
| Generator verdict | trust: callee edge | effective level, no new obligation |
| Determinacy VC | trust: coverage class | same fragment as the post |
| Whole-image statement | ∀-introduction in each generator, plus codegen; tested by `check` with `for-all` | not a solver goal; not routed to Lean |
| `decreases` and the digit cap in header scans | contract | (a) QF-LIA |

Boundary: `LLMLL.md` §5.3.3 and §5.3.5. Nothing goes to Lean.

## Affected surface

- `LLMLL.md` §13.12: a `bytes-tabulate` row with a length lemma only; the sealed set goes from thirteen to fourteen. §5.3.3: facts D0, G and D4, the trigger set, the pass order and the limit. §13: the `/` and `mod` rows gain the `d ≥ 1` rule. The CLAUSE-WELLDEF-1 table gains `/` and `mod`. §4.4: the tabulate generator as a callee edge.
- `compiler/src/LLMLL/TypeCheck.hs`: the generator check, `def` only.
- `compiler/src/LLMLL/FixpointEmit.hs`: `bytes-tabulate` in `abstractedBuiltins` and the sealed set; T1 to T3; the refusal scan for `/` and `mod`; the division pass at every emission site; the qualifier exclusion; the determinacy VC.
- `compiler/src/LLMLL/ObligationMining.hs`: `sigmaAutoPred` refuses a variable divisor.
- `compiler/src/LLMLL/CodegenHs.hs`: the `bytes-tabulate` emission with the three guards and forced arguments.
- Trust report and program graph: the generator edge, the fallback cause `tabulate-gen-unverified`, and the exactness flag that Part D reads. These increase `trust_report_version`.
- Version stamps: `codegen_semantics_version` increases with Part B. `checker_soundness_version` does not change for Part B or Part C.
- `examples/image` (new): the library, the covered-set baseline, the rate baseline, the mutant generator, the equivalence file, and a pinned version-gate step.
- Roadmap: file BYTES-TABULATE-1 (G7, DECIDE until this record settles) and IMAGE-LIB-1. DIV-VAR-1 moves to PLAN when Part C settles.
- **Additions:** `bytes-tabulate`, a new builtin with an assumed length lemma. The soundness argument is in Part B.

## Rows the library needs, in order

1. **BYTES-TABULATE-1** (new). Without it, no whole-image operation is O(n) from verified generators. It unblocks `invert` and `threshold`, whose generators need no coordinate arithmetic. It does not depend on Part C.
2. **DIV-VAR-1.** It unblocks the `geom` division posts, every `*-at` post with a source index, crop, blur and resize.
3. **IMAGE-LIB-1.** The library, the determinacy check, the mutants and the ratchets.
4. **ABSTRACTION-RESULT-LEN-1** and **CONE-DEF-DIRECTION-1** (DECIDE). They raise the refutation rate. They do not affect the covered set.
5. **POST-CALL-XMOD-1** (DECIDE). Optional. It would let a `*-at` post call `geom` instead of restating the arithmetic.
6. **Content export** (no row yet). The abstract-refinement extension of Part B. It would move `ops` from shape-verified to covered.
7. **Not needed by the core:** SIG-SCALAR-ARM-1, PAIR-NEST-PROJ-1, POST-CONJ-SPLIT-1. The Part A representation avoids them.
8. **FFI-KERNEL-1: hold.** Each C kernel is trusted, not verified. The trigger is a measured `bytes-tabulate` throughput below a stated workload's need. That measurement is not run.

## Risks and open questions

1. **R1. The G trigger set may be too narrow or too costly.** Verification ergonomics. Part C, not measured. Blocks the settlement of Part C until the witness table runs. The hand derivations cover the three witnesses the review named; MUL-VAR-1 found that realistic witnesses defeat paper arguments.
2. **R2. `ops` functions are shape-verified only.** Scope. A caller of `ops.invert` learns the length and not the content. The content-export extension is the fix, and it is not proposed.
3. **R3. The determinacy VC can fail through incompleteness.** Verification ergonomics. A strong post that the solver cannot show to be deterministic is classed shape-verified. This costs coverage, not soundness.
4. **R4. `bytes-tabulate` throughput is not measured.** Scope. Each byte calls `gen` with `Integer` arithmetic. PERF-TEXT-1 measured about 10 µs per sample on a text path, not on this one. Complicates the FFI-KERNEL-1 decision.
5. **R5. The trusted base grows by one length lemma.** Soundness, disclosed. The same kind of lemma as `bytes-make`, with the same guards.
6. **R6. `d ≥ 1` is narrower than Haskell `div`.** Spec drift if `LLMLL.md` §13 does not change in the same release. Complicates.
7. **R7. The mutant generator is test infrastructure that the refutation rate depends on.** Scope. A generator defect that drops mutants inflates the rate. The operator set is fixed in this record, and a test holds that every example mutant in the contract table is generated. The covered set does not depend on the generator.

## Decisions for the user

1. The `bytes-tabulate` generator must be a named top-level `def` with a `post`; passing it is a callee edge; and the builtin carries a length lemma only, with content export deferred. Recommendation: yes.
2. The divisor rule is `d ≥ 1`, and `rem` and `quot` stay refused. Recommendation: yes.
3. Coverage is the trust report's `verified` plus a proved determinacy VC; the refutation rate is a separate ratchet; `ops` are counted as shape-verified. Recommendation: yes.
4. The library starts in `examples/image` and moves to the hub later. Recommendation: yes.
5. The sample cap is 2²⁸ samples and a header number has at most 9 digits. Recommendation: yes. A larger cap only changes one literal.

## Next steps

1. Settle Part B and Part D on the user's decisions. Part B does not depend on Part C, so the compiler-engineer plan for BYTES-TABULATE-1 can start then.
2. Run the Part C witness table.
3. Revise Part C on the table, then settle it.
4. The compiler-engineer plan for DIV-VAR-1, then IMAGE-LIB-1.

## Appendix: review dispositions

### Security review of Rev 1 (2026-11-20)

The review used the threat model of the Restatement and ran probes against llmll 0.41.0. It reported no critical finding.

| Finding | Severity | Change |
|---|---|---|
| H1. Tabulate codegen narrows without guards | high | Part B "Semantics": three guards, `BS.pack` excluded; edge cases 3 and 10 |
| H2. The Rev 1 aliasing control cannot detect aliasing | high | Part B freshness rule; edge cases 4a to 4c |
| H3. C rests on an unverified generator; C lacks `pre_gen` | high | Part B "The generator is a callee"; edge case 11. C itself is dropped in Rev 3 |
| H4. `body_faithful` lists functions whose post is refuted | high | Part D "Classes"; baseline recounted from the trust report, unchanged at 132 |
| H5. Range-only and length-only posts accept wrong bodies; `abstraction:` accepted as refuted | high | Part A exact posts; Part D determinacy VC and the three-outcome mutant rule |
| M1. No caps on dimensions, digits or resize targets | medium | Part A "Representation" and "Untrusted input"; edge case 9 |
| M2. The ratio ratchet can be gamed | medium | Part D "Ratchets": a set, a reviewed file, levels from the module table |
| M3. Division must not reach qualifiers or kvars | medium | Part C "Every emission site"; witness table rows 5 to 7 |
| M4. The generator must be pure and terminating | medium | Part B: `def` only, callee edge in the termination graph; edge case 12 |
| L1. The shell-to-core `pre` is a run-time check | low | Part A "Untrusted input" rule 4 |
| L2. Evaluate the arguments once | low | Part B "Semantics" |
| L3. Instance generation needs a termination rule | low | Moot in Rev 3: C is dropped. Part C states termination for its facts |
| L4. Version stamps | low | "Affected surface" |
| L5. Fallbacks after tabulate reads | low | Moot for C; the refutation-rate ratchet carries the remaining effect |

### Professor review of Rev 2 (2026-11-20, `image-library-review.md`)

The review confirmed the soundness of C, the freshness argument, ∀-introduction for T2 and T3, the `d ≥ 1` rule, D0 to D3 as theorems, and decidability. It found no route to a false `verified`.

| Finding | Change |
|---|---|
| P1. D1 and D2 instance sets undefined; `scale-src` and `sw = 1` missed; no congruence fact | Part C: G with a defined trigger set, D4, pass order, invariance, limits; hand derivations; witness table rows 1 to 4 |
| P2. Fact C has no consumer | Alternative (a): C dropped; length lemma only; content export deferred to an abstract-refinement design |
| P3. Coverage mixes spec strength with refutation completeness | Part D: covered set and refutation rate as two ratchets |
| P4. "Exact post" has no mechanical definition | Part D: the determinacy VC; edge case 13 |
| P5. The mutation set misses the table's own mutants | Part D: ROR, AOR and factor deletion added; a test holds that the table's examples are generated |
| P6. Σ_auto consumers not covered by M3 | Part C: `sigmaAutoPred` refuses a variable divisor; `Checkout.hs` hints do not admit division |
| P7. Callers repeat nonlinear range proofs | Part A: range conjuncts on `geom` posts |
| P8. `checker_soundness_version` raised without reason | Part C "Version stamps": not raised |
| P9. Arguments not forced at `n = 0` | Part B "Semantics"; edge case 5 test |
