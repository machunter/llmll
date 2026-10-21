---
name: multilangbench-scope-evaluation-review
title: "Professor review of the MultiLangBench scope evaluation (Rev 0 and Rev 1)"
status: "Archived 2026-10-21. Folded as the Appendix of docs/design/multilangbench-scope-evaluation.md (M2). Both passes were adopted in full and produced Rev 2"
reviewed: "MultiLangBench scope evaluation Rev 0 and Rev 1, language-team, 2026-10-20"
consumers: [language-team, compiler-engineer, user]
---

# Professor review: MultiLangBench scope evaluation

The record under review is [`multilangbench-scope-evaluation.md`](../../design/multilangbench-scope-evaluation.md). The first pass reviews Rev 0. The second pass reviews Rev 1. The second pass withdraws one recommendation of the first pass: the documentation budget of matched size. The language-team answered the open question of the second pass in Rev 2, §4.

# Pass 1 (on Rev 0)

## Restatement
The language-team recommends adopting MultiLangBench later, as a secondary probe, once Phase 3 has run. It recommends scheduling paired byte I/O and a new `char ↔ int` item on their own merit after FFI-TIER1-1, without the benchmark pulling them forward. This critique tests the validity of the benchmark, the claim that the assurance-credit variant can be verified, and the representation of the byte type.

## Context located
- `LLMLL.md:13` and `LLMLL.md:1086`: the shipped `Σ_auto` omits `*`, `/` and `mod` entirely. `(* 8 r)` and `(mod r 8)` report `nonlinear:` and fall back, even though both are linear.
- `LLMLL.md:1086`: "The omission stands because no program in this repository needs the wider set." This is a policy choice, not a decidability limit.
- `compiler/src/LLMLL/FixpointEmit.hs:5667`: `nonNegMeasures = ["strLen", "listLen", "bytesLen"]`. A `bytesLen` measure already exists in the verifier.
- `compiler/src/LLMLL/FixpointEmit.hs:4188`: `bytes[n]` contracts map to `byteArraySort`, the array-theory encoding.
- `LLMLL.md §13.12`: the sealed-builtin axioms add ground facts at each bytes read (`byte-range`). They are instantiated per term, not quantified.
- `docs/design/language-comparison-experiments.md:236-253`: controls #2 ("Python should not be asked to do less") and #9 ("Do not collapse proof into tests").
- `experiments/language-comparison-backlog.md:78`: Phase 3 is blocked on S1–S8, open since 2026-05-15.
- No review or draft on byte representation exists in `docs/design/`.

## Gaps and hazards

1. **The assurance-credit variant cannot be verified on today's `Σ_auto`.** Class: spec-drift (inside the proposal). Source: `LLMLL.md:1086`.
   - The language-team says the varint, big-endian and page-header contracts "sit in QF-LIA". In the mathematical theory, they do. In LLMLL's shipped symbol set they do not: every `(* 128 x)`, `(/ x 128)` and `(mod x 256)` reports `nonlinear:` and falls back.
   - The result would be `tested` or `asserted`, never `verified`. The Assurance tuple would then show less than the proposal promises.
   - Effect: this point of the recommendation fails as written. It is repairable. `LLMLL.md:1086` names the fix: widen `Σ_auto` to multiplication by a numeral and `div`/`mod` by a positive numeral.
   - SMT-LIB's `LIA` logic already admits both forms (Barrett, Fontaine and Tinelli, *The SMT-LIB Standard 2.6*, §Logics, `QF_LIA`: "multiplication by constants" and `div`/`mod` by numerals). Z3 stays complete on them. A byte codec is the first program in the repository that needs the wider set, so the stated reason for the omission no longer holds.

2. **Contamination makes the cross-language comparison invalid.** Class: scope (measurement validity).
   - SQLite's C source, and many ports and close clones, are in every frontier model's pretraining data. A C, Python or Rust agent can lean on memory of the implementation, not just the specification. An LLMLL agent must reproduce the architecture and also the surface syntax.
   - The pass-rate difference then measures how much the language was exposed in pretraining **multiplied by** how much of the task was memorized. It does not measure language quality.
   - This is a general threat in code benchmarks: Jain et al., *LiveCodeBench* (2024), and Riddell et al., *Quantifying Contamination in Evaluating Code Generation Capabilities of Language Models* (ACL 2024).
   - Effect: it does not block an LLMLL-only use. It does block reading LLMLL's position relative to Python or OCaml as a property of the language. The language-team's "own baselines" condition is necessary but not enough.

3. **(P1) The construct is not one-shot correctness.** Class: scope.
   - An end-state pass rate over an unbounded session measures agentic engineering stamina, the quality of in-context documentation, and the language, all mixed together. `docs/compiler-team-roadmap.md:6` optimizes the probability of acceptance on the first submission. MultiLangBench gives that no weight.
   - The "zero-pretraining usability floor" reading is also confounded. The LLMLL agent gets `LLMLL.md` in context and the Python agent gets nothing, so the treatment differs in two variables, not one. This is the documentation-as-intervention confound named for unseen-language evaluation in Cassano et al., *Knowledge Transfer from High-Resource to Low-Resource Programming Languages for Code LLMs* (OOPSLA 2024).
   - Effect: the valid use is **longitudinal and within LLMLL**: the same model and harness on LLMLL vN versus vN+1. There, both confounds cancel. The cross-language reading needs the same documentation budget for every language, for example a language reference of matched size given to the Python agent as well, or it must be withdrawn.

4. **The Phase 3 condition makes adoption effectively indefinite.** Class: scope.
   - Phase 3 has waited five months on S1–S8, which are user decisions, not engineering work. "After Phase 3 runs" therefore chains a cheap probe to an unrelated bottleneck.
   - The longitudinal use in finding 3 needs no Phase 3 machinery. It needs the byte I/O items, a runner and one model.
   - Effect: it complicates the recommendation. The condition should be "byte I/O shipped and the harness rules in place", not "Phase 3 complete".

5. **List-backed bytes mix runtime cost into the language score.** Class: scope (measurement validity) / ergonomic.
   - `bytes[n]` compiles to `[Word8]` (`CodegenHs.hs:2303`), so `bytes-get` costs O(i). A timeout from a 60-second budget would count against the language for a code-generation choice the agent cannot affect.
   - The new type should compile to an immutable `Data.ByteString`. It is immutable in Haskell, so strict immutability holds, and `slice` costs O(1).
   - Effect: it only matters at scale, but it should be fixed in the design, not after the measurement.

6. **(P2) The representation of the byte type.** Class: decidability.
   - **Use a length measure on an unindexed `bytes`, and keep `bytes[n]` as sugar for `{v : bytes | bytesLen v = n}`.** The existential `∃n. bytes[n]` forces packing and unpacking at every read site, and LLMLL has no existential elimination form. The measure reuses the `bytesLen` measure that already exists (`FixpointEmit.hs:5667`) and the existing array sort, so `bytes[n]` and `bytes` unify instead of becoming two types. This is the Liquid Haskell treatment of `Data.ByteString`, verified with a length measure: Vazou, Seidel and Jhala, *LiquidHaskell: Experience with Refinement Types in the Real World* (Haskell '14), §5.
   - **Keep slice and concat decidable by axiomatizing length universally and contents per term.** The length posts `bytesLen (concat a b) = bytesLen a + bytesLen b` and, under `0 ≤ s ≤ e ≤ bytesLen b`, `bytesLen (slice b s e) = e − s` are QF-LIA. The content facts, such as `get (slice b s e) i = get b (s + i)`, should be instantiated at each `get`-on-`slice` term the body contains. That is the same ground-instantiation discipline the `byte-range` facts already use (`LLMLL.md §13.12`), and it stays quantifier-free.
   - The quantified form belongs to the array property fragment, which is decidable (Bradley, Manna and Sipma, *What's Decidable About Arrays?*, VMCAI 2006). LLMLL does not need it if it instantiates at terms the program uses. A post that quantifies over all indices ("the slice equals the source everywhere") should stay out of `Σ_auto` and route to `?proof-required`.

7. **The purity rule is narrower than the language-team states.** Class: scope.
   - Banning `haskell.*` imports and every `wasi.proc` capability except `args` is correct. The model can also reach Haskell code in a second way: `llmll build` emits a Haskell package, and an agent with shell access could edit Haskell source in the generated package directly and rebuild with `stack build`.
   - Effect: it complicates the harness. The runner must rebuild from the `.llmll` source in a clean directory and grade only that build.

## Recommendation
Accept the language-team's ADOPT-LATER verdict and its decision not to pull byte I/O forward for the benchmark. Revise four points:

1. **Make the benchmark's primary use longitudinal and within LLMLL.** Track version-over-version pass rate with a fixed model and harness. Allow a cross-language reading only with matched documentation budgets for every language, and label it as confounded by contamination.
2. **Replace the Phase 3 condition** with "BYTES-READ-1 + BYTES-WRITE-1 + `char ↔ int` shipped, and the harness rules in place".
3. **Before claiming assurance credit, widen `Σ_auto`** to multiplication by a numeral and `div`/`mod` by a positive numeral, as a separate small item. Without it, withdraw the "QF-LIA, verified" claim for the codec contracts. The widening has independent value and its decidability argument is already in `LLMLL.md:1086`.
4. **Fix the byte representation in the paired design** as an unindexed `bytes` with the `bytesLen` measure, `bytes[n]` as refinement sugar, a `ByteString` backing, length axioms in QF-LIA, and content axioms instantiated per term.

## Open questions for the language-team
1. Does a refinement-sugar `bytes[n]` keep every existing `bytes[n]` program's verdict unchanged? In particular, `bytes-zero`'s rule that the return type sets the length (`FixpointEmit.hs:2244-2261`) and the `byte-range` facts must still fire when `n` is an index read from a refinement, not taken from the type syntax.
2. Is the `Σ_auto` widening one item or two? Multiplication by a numeral is trivially linear. `div` and `mod` by a numeral need the floor convention pinned against Haskell's `div`/`mod` and SMT-LIB's Euclidean `div`, and these disagree on negative divisors.

# Pass 2 (on Rev 1)

## Restatement
Rev 1 keeps the adopt-later verdict, with four changes:
- The primary use becomes a longitudinal track within LLMLL.
- The gate becomes three shipped items: BYTES-READ-1, BYTES-WRITE-1 and `CHAR-CODE-1`.
- The assurance-credit claim now depends on a new `SIGMA-CONST-ARITH-1` widening.
- A separate unindexed `bytes` type is added, joined to `bytes[n]` by an explicit `bytes-widen`.

This pass checks those revisions and the two answers the language-team gave.

## Context located
- `LLMLL.md:18`: no refinement subtyping. Rev 1's Q1 answer rests correctly on this.
- `compiler/src/LLMLL/FixpointEmit.hs:2244-2261`: one syntax match shared by four readers. This confirms that rewriting `bytes[n]` would break them.
- `examples/bytes-bounds/EXPECTED_VERDICTS.json`: six frozen verdicts, which serve as the regression gate.
- `compiler/src/LLMLL/Parser.hs:637-641`: `pBytesType` uses `pIntLit = L.decimal`. **`bytes[0]` parses and a negative length cannot.** This settles Rev 1's open item in its edge case 2.
- `compiler/src/LLMLL/FixpointEmit.hs:3585`, `:3830-3834`, `:4350`: `*`, `/`, `mod` and `rem` are refused in three places. The widening touches all three.
- `compiler/src/LLMLL/FixpointIR.hs`: a grep found no constructor for multiplication or `mod`. The IR may need new operators, which the engineer must confirm.
- `compiler/app/Main.hs:1463-1466`: the backend is the `liquid-fixpoint` binary, not Z3 called directly with SMT-LIB.
- `compiler/src/LLMLL/CodegenHs.hs:2165`: codegen lowers `mod` to Haskell `` `mod` ``, which rounds toward −∞.

## Gaps and hazards

1. **The cross-language reading should be dropped, not matched.** Class: scope (measurement validity). Bite: it changes the recommendation.
   - My previous pass proposed reference documentation of matched size for every language. That suggestion was wrong, and I withdraw it.
   - Matched documentation removes one variable: the documentation in context. It leaves the larger one: pretraining exposure, including memorized SQLite implementations in C, Python and Rust.
   - No documentation budget makes "LLMLL vs Python" a measurement of the language. Any number from it reads as one anyway, which is the external-register risk from Rev 0.
   - Rev 1 should remove the cross-language reading from the recommendation. Keep only the longitudinal track.

2. **The longitudinal track needs controls that Rev 1 does not state.** Class: scope (measurement validity). Bite: it complicates the track.
   - **Model drift.** A model alias that the provider updates between runs changes the subject. Pin a dated model snapshot for the whole series.
   - **The documentation is part of the treatment.** `LLMLL.md` changes with each version, so the track measures the language and its documentation together. That is acceptable, because LLMLL ships them together, but the reports must say so. Record each run's `LLMLL.md` hash.
   - **Variance.** Long agentic sessions vary a lot between runs. One run per version cannot tell a version effect from noise.
   - Pre-register the number of runs per version and the comparison test. Run at least 5 seeds per version, and report a bootstrap interval on the pass rate of the 272-test subset.
   - Each seed costs one full session. Fix the budget before the first run, on the `language-comparison-experiments.md` Control #7a precedent.

3. **`SIGMA-CONST-ARITH-1` is larger than "small".** Class: scope / spec-drift. Bite: it complicates the plan, not the soundness.
   - The decidability argument is correct. The backend is liquid-fixpoint, though, so the operative question is what liquid-fixpoint passes to Z3, not what SMT-LIB's `QF_LIA` allows.
   - liquid-fixpoint's `mod` translates to SMT-LIB `mod`, which is Euclidean. That is safe only because Rev 1 limits divisors to positive numerals.
   - The refusal lists sit at three places in `FixpointEmit.hs`, and the IR may need new operators. The engineer should size this before the roadmap calls it PLAN.
   - **Rev 1's witness is good, and I keep it.** `(mod (- 0 7) 8) = 1` separates floor and Euclidean rounding from truncation. Add a second witness, `(/ (- 0 7) 8) = -1`. Truncation gives 0 there, so the quotient lowering is checked too, not only the remainder.

4. **`CHAR-CODE-1` is a partial pair, and LLMLL has no char type.** Class: soundness (codegen faithfulness). Bite: it blocks a naive design.
   - LLMLL has no `char`; `string-char-at` returns a 1-character `string` (`LLMLL.md §13.6`). So the pair is really two builtins: `string-code-at : string int → int`, and `string-from-code : int → string`.
   - `string-from-code` is partial over `int`. A code above `0x10FFFF` makes Haskell's `chr` raise. A surrogate code (`0xD800`–`0xDFFF`) gives a `Char` that the UTF-8 encoder on `wasi.fs.write` rejects at run time (`CodegenHs.hs:787-792` sets `utf8`).
   - The precondition must exclude both ranges: `(and (>= c 0) (<= c 1114111) (or (< c 55296) (> c 57343)))`. That is QF-LIA, so it is cheap. Without it, the builtin breaks the no-crash property that `CodegenHs.hs` relies on for Commands. Rev 1 does not mention this.
   - It is a design fact the paired proposal must state, not a question.

5. **Is `bytes-widen`'s length post a disclosed axiom, or a proved fact?** Class: ergonomic / trust. Bite: it only matters if the trust report counts it.
   - Rev 1 discloses it under `codegen-determined`. That is honest but not the best choice. The post `bytesLen result = n` is true by the definition of the conversion, and `n` is the source's literal length.
   - If the emitter instantiates `bytesLen` on the source from the `TBytes n` annotation, as `bytesLenParamPre` already does, the post follows from an equation the source already carries. No new disclosed axiom is needed.
   - Prefer the fewest disclosed axioms. Each one is a line the trust report must explain to an agent reading it.

6. **The Q1 answer is correct, and the convergence matters.** Class: none (agreement).
   - Keeping `TBytes n` separate, with one explicit conversion builtin, matches how Liquid Haskell handles `Data.ByteString`. The length lives in a measure, and the indexed form does not exist as a separate type there. LLMLL keeps its indexed form for history.
   - My refinement-sugar framing and the language-team's syntax analysis reach the same semantics by different routes. That agreement is a reason to settle this point now.

## Recommendation
Settle Rev 1 after four changes:
1. **Remove the cross-language reading.** MultiLangBench is a longitudinal track within LLMLL only. Withdraw the matched-documentation idea, which was mine.
2. **State the longitudinal controls:** a pinned model snapshot, a recorded `LLMLL.md` hash, at least 5 pre-registered seeds per version, a bootstrap interval, and a fixed budget.
3. **File `SIGMA-CONST-ARITH-1` as MEASURE, not PLAN,** until the engineer has sized the IR and the three refusal sites. Add the quotient witness.
4. **Specify `CHAR-CODE-1`** as `string-code-at` and `string-from-code`, with the range-and-surrogate precondition. Prove `bytes-widen`'s length post from the source annotation instead of disclosing it.

## Open questions for the language-team
1. Does the longitudinal track need its own pass/fail signal, or is it a descriptive time series? If a version's pass rate falls outside the prior interval, does that block a release, or only file a finding? Without an answer, the track measures something nobody acts on.
