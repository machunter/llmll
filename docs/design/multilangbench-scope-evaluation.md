---
title: MultiLangBench scope evaluation
status: Rev 2, SETTLED 2026-10-20 (user-approved)
rows: CHAR-CODE-1 (new, DECIDE), SIGMA-CONST-ARITH-1 (new, MEASURE), BYTES-READ-1 and BYTES-WRITE-1 (note only)
review: two professor passes (Rev 0 and Rev 1, 2026-10-20), folded below as the Appendix; the standalone file is archived at docs/archive/professor-reviews/multilangbench-scope-evaluation-review.md
---

# MultiLangBench scope evaluation

**Status: Rev 2, SETTLED 2026-10-20.** The language-team wrote Rev 0 on 2026-10-20. The professor made two passes, and the language-team revised twice. The user approved Rev 2 the same day. The professor's two passes are folded below as the [Appendix](#appendix--professor-review-log).

This is a scope evaluation, not a design proposal. It decides whether an external benchmark is useful to LLMLL, and what it changes in the queue. It specifies no surface syntax. The paired byte-I/O design that it orders is future work.

## Restatement

OpenAI published MultiLangBench on 2026-10-19 (github.com/openai/MultiLangBench, Apache-2.0). The task is to implement SQLite 3.40.1 from its documentation only. The program gets a database path as an argument and SQL on standard input. It changes the database file in place. Real SQLite then runs a validation query on the file, and the output must match a golden file. The canonical subset is 272 tests, each with a 60-second limit. The score is pass rate and API cost. The repository has tests and no agent harness. The published results are for GPT models only.

The evaluation answers two questions:

1. Is MultiLangBench useful within LLMLL's current scope?
2. Does it justify moving the byte-I/O items (`BYTES-READ-1`, `BYTES-WRITE-1`) and a new character-code item ahead of the queue?

**Answers.** (1) Yes, later, as a **longitudinal track within LLMLL only**. (2) No. The byte-I/O and character-code items are justified on their own merit, and they keep their normal place in the queue.

## Context located

- `docs/design/strategic-positioning.md:10`: the thesis is multi-agent coordination. MultiLangBench exercises none of the four protected novelties (`:14-30`).
- `docs/design/strategic-positioning.md:54-62`: "a small language removes the training need" is a listed overclaim. A cross-language MultiLangBench result would read as a test of it.
- `docs/design/strategic-positioning.md:65-79`: protocol implementations are a target domain. A file-format engine is close to it.
- `docs/compiler-team-roadmap.md:6`: the governing criterion is one-shot correctness. MultiLangBench grades the end state of a long session.
- `docs/design/language-comparison-experiments.md:204-253`: the Correctness and Assurance scores are separate. Control #7a fixes the budget before launch, and Control #9 forbids collapsing proof into tests.
- `experiments/language-comparison-backlog.md:78`: Phase 3 is blocked on S1–S8, open since 2026-05-15.
- `docs/compiler-team-roadmap.md:138-139`: `BYTES-READ-1` and `BYTES-WRITE-1` are OPEN/DECIDE, filed from TOOL-RFC-006.
- `docs/compiler-team-roadmap.md:141`: `FFI-CONV-1` needs a `ByteString` to bytes mapping.
- `LLMLL.md:13`, `LLMLL.md:1086`: the shipped `Σ_auto` omits `*`, `/` and `mod`, also in linear forms such as `(* 8 r)`.
- `LLMLL.md:18`: LLMLL has no refinement subtyping.
- `compiler/src/LLMLL/FixpointEmit.hs:2244-2261`: four readers match the syntax `TBytes n`. That match is deliberate.
- `compiler/src/LLMLL/FixpointEmit.hs:3585`, `:3830-3834`, `:4350`: the three places that refuse `*`, `/`, `mod` and `rem`.
- `compiler/src/LLMLL/FixpointEmit.hs:5667`: the `bytesLen` measure exists.
- `compiler/src/LLMLL/Parser.hs:637-641`: `bytes[0]` parses. A negative length does not.
- `compiler/src/LLMLL/CodegenHs.hs:2303`: `bytes[n]` compiles to `[Word8]`.
- `compiler/src/LLMLL/CodegenHs.hs:787-792`: `wasi.fs.write` writes UTF-8.
- `scripts/version_gate.sh` and `docs/UPDATE-PROTOCOL.md:47`: every release gate is deterministic and runs in CI.
- `experiments/repair-loop/README.md:241`: provider incidents count as contamination of a run.

### Feasibility read (compiler-engineer, 2026-10-20)

The engineer built two test programs with the v0.30.8 compiler.

- **What works.** In `:mode cli`, `wasi.proc.args` gives the database path at index 0. `(wasi.fs.read "/dev/stdin")` reads the SQL. `wasi.fs.write` overwrites the file. The test program exited 0, and the file content equalled the input.
- **What blocks.** `wasi.fs.read` decodes the file as UTF-8 text. On a real SQLite database of 8192 bytes, the read returned `RErr … hGetContents: invalid argument (cannot decode byte sequence starting from 153)`. No program can read or write the SQLite file format today.
- **A second gap.** LLMLL has no builtin from a character to its code, or from a code to a character. `string-char-at` returns a 1-character `string`.
- **Performance.** List-backed bytes are probably fast enough for the 272 tests. This was not measured.

## Evaluation

### 1. What the benchmark measures for LLMLL

It measures whether one agent, given only `LLMLL.md`, can write a large stateful program that passes behavioural tests. It does not measure contracts, holes, the trust report, checkout and patch, or multi-agent coordination. An engine with no contracts scores the same as a verified one. So the result is a measure of general usability, not evidence for the thesis.

### 2. No cross-language reading

The evaluation **makes no comparison with another language**. This includes OpenAI's published numbers, and it includes baselines we run ourselves.

- SQLite's C source and many ports are in every frontier model's pretraining data. An agent in C, Python or Rust can use memorized implementations. An LLMLL agent cannot.
- The LLMLL agent also gets `LLMLL.md` in context, and the other agents get nothing. Giving every language a reference of the same size removes this second difference only. Pretraining exposure stays, and it is the larger difference.
- A pass-rate gap therefore measures pretraining exposure and memorization together. No documentation budget turns it into a measure of the language.

### 3. The longitudinal track

The valid use is the same model and the same harness on LLMLL vN and on a later version. Pretraining exposure is then constant. The track measures LLMLL and its documentation together. That is acceptable because LLMLL ships them together. Each report must state it.

**Controls.** The experiment-lead writes the plan before the first run and keeps it unchanged afterwards, on the Control #7a precedent.

1. **Model.** Pin one dated model snapshot for the whole series. Do not use a model alias that the provider can update.
2. **Documentation.** Record the hash of `LLMLL.md` for each run.
3. **Variance.** Pre-register at least 5 seeds for each measurement point. Report a bootstrap interval on the pass rate of the 272-test subset.
4. **Budget.** Fix the total budget before the first run. Each seed costs one full agent session.
5. **Cost.** Report API cost next to the pass rate, as the MultiLangBench README defines it.

### 4. The track is descriptive. It never blocks a release.

The track is a time series with a defined finding trigger. It is not a release gate.

**Why it is not a gate.**

- **Release cadence.** The repository has ten release tags from v0.29.1 (2026-10-14) to v0.30.9 (2026-10-20). One measurement point needs at least 5 long agent sessions. A run for each release would cost more time and money than the releases it gates.
- **Gate type.** Every release gate today is deterministic and runs in CI: `scripts/version_gate.sh`, `stack test`, `pytest`, and the frozen verdict files. A paid, stochastic measurement of several hours is a different kind of evidence. As a gate, it would make a release depend on a provider's availability.
- **Role authority.** The experiment-lead's output is descriptive. Changes to the spec and the compiler belong to the roles after it. A result outside the interval is input to those roles, not a verdict.

**The rule.**

1. **When to measure.** Measure at each minor version (v0.31.0, v0.32.0, and so on), not at patch versions. A run can also be requested after a change aimed at general usability, such as the byte-I/O items.
2. **Trigger.** If the interval of a new point does not overlap the interval of the previous point, the experiment-lead files a finding under `experiments/repair-loop/findings/` or under the track's own findings folder. The trigger applies to a decrease and to an increase. An unexplained increase shows which change helped, so it is as useful as a decrease.
3. **Finding content.** The finding gives the diff between the two `LLMLL.md` hashes and the list of releases between the two points. It also gives the three most frequent failure categories, grouped by the SQLite test file each failed test came from. The language-team and the compiler-engineer use it to separate a language effect from a documentation effect.
4. **No trigger.** A change inside the interval files nothing. A non-overlap from one seed set, with no rerun, files the finding and marks it "unreplicated".

### 5. Fit with one-shot correctness

The benchmark gives no weight to first-attempt acceptance. The only link is indirect: fewer repair turns lower the API cost. The track therefore complements the governing criterion and does not measure it.

### 6. Byte I/O and character codes on their own merit

These items belong in the queue without the benchmark.

- TOOL-RFC-006 spawns `od` and `printf` to work around the missing byte I/O. The rule in `docs/design/llmll-tooling-campaign.md` §5 makes each such spawn a gap that needs a fix.
- The protocol domain needs binary wire formats.
- `FFI-CONV-1` needs a target type for `ByteString`.
- Without character codes, text encodings, parsers and checksums need lookup tables.

MultiLangBench is a later consumer of these items. It is not the reason for them.

### 7. Assurance credit

An engine's codec parts can carry contracts: the varint codec, big-endian integers, page-header field ranges and cell-offset bounds. These use multiplication by a constant and `div` and `mod` by a constant. They are linear, but the shipped `Σ_auto` refuses them (`LLMLL.md:1086`). Today they would report `nonlinear:` and fall back. They would be `tested` or `asserted`, never `verified`.

Assurance credit therefore depends on `SIGMA-CONST-ARITH-1` (below). If the harness collects the trust report, the track reports an Assurance tuple next to the pass rate, following Control #9. This is an LLMLL-side measurement, not a leaderboard entry.

## Decisions for the queue

### `CHAR-CODE-1` (new row, DECIDE)

LLMLL has no character type, so the item is two builtins on `string` and `int`.

- `string-code-at : string int → int` returns the code point at an index. Its precondition is the same index bound as `string-char-at`.
- `string-from-code : int → string` returns a 1-character string. Its precondition is:

```
(and (>= c 0) (<= c 1114111) (or (< c 55296) (> c 57343)))
```

Above `0x10FFFF`, Haskell's `chr` raises an exception. A surrogate code (`0xD800` to `0xDFFF`) gives a `Char` that the UTF-8 encoder of `wasi.fs.write` rejects at run time. The precondition excludes both ranges. Without it, a Command could crash. The precondition is in QF-LIA.

### `SIGMA-CONST-ARITH-1` (new row, MEASURE)

Widen `Σ_auto` to these forms:

- `(* k x)` and `(* x k)` with a numeral `k`;
- `(/ x k)` and `(mod x k)` with a numeral `k > 0`.

A negative divisor or a divisor that is not a numeral keeps the `nonlinear:` route.

**Why a positive divisor is required.** Haskell's `div` and `mod` round toward −∞. liquid-fixpoint passes `mod` to SMT-LIB, where it is Euclidean. The two conventions differ only for a negative divisor.

**Why MEASURE and not PLAN.** The refusals sit at three places in `compiler/src/LLMLL/FixpointEmit.hs` (`:3585`, `:3830-3834`, `:4350`). A grep of `compiler/src/LLMLL/FixpointIR.hs` found no constructor for multiplication or `mod`. The engineer sizes these before the row moves to PLAN.

**Required witnesses.**

1. `(mod (- 0 7) 8)` must verify the post `result = 1`. Floor and Euclidean rounding give 1. Truncation gives −7.
2. `(/ (- 0 7) 8)` must verify the post `result = -1`. Truncation gives 0.

Together they check that the emitter lowers neither operator to a truncating form.

### `BYTES-READ-1` and `BYTES-WRITE-1` (note on the existing rows)

The paired design uses shape (b): a real byte type and an `RBytes` result arm. This record fixes four points for it.

1. **Type.** A new unindexed type `bytes`, compiled to an immutable `Data.ByteString`. `ByteString` is immutable, so strict immutability holds. Its slice costs O(1), and its index read costs O(1).
2. **Length.** The type uses the existing `bytesLen` measure and the existing array sort in the verifier.
3. **`bytes[n]` stays a separate type.** Rewriting `bytes[n]` to `{v : bytes | bytesLen v = n}` would break the four syntax readers (`FixpointEmit.hs:2244-2261`). It would also need refinement subtyping, which `LLMLL.md:18` excludes. One explicit builtin joins the two types: `bytes-widen : bytes[n] → bytes`. The reverse direction is out of scope, because no consumer needs it.
4. **`bytes-widen`'s length post is proved, not disclosed.** The post is `bytesLen result = n`. The emitter instantiates `bytesLen` on the source from its `TBytes n` annotation, as `bytesLenParamPre` already does. The post then follows from an equation the source carries. The trust report gets no new disclosed axiom.

The paired design also covers `CHAR-CODE-1` and the byte mapping of `FFI-CONV-1`. Standard input must be allowed as a byte source.

### Order

1. FFI-TIER1-1 first.
2. Then one paired design: byte I/O, `CHAR-CODE-1`, and the byte mapping of `FFI-CONV-1`.
3. `SIGMA-CONST-ARITH-1` goes when there is space, after its MEASURE step.
4. The experiment-lead builds the MultiLangBench runner when the byte-I/O items and `CHAR-CODE-1` have shipped. Phase 3 is not a precondition.

### Harness rules

The runner enforces these rules. The compiler cannot, because it checks capabilities by namespace only (CAP-1-REAL).

1. Reject any `haskell.*` import. A Hackage SQLite binding would pass the tests and break the benchmark's purity rule.
2. Reject a `wasi.proc` import with any capability other than `args`. This prevents a call to an outside SQLite or Python.
3. Rebuild from the `.llmll` source in a clean directory, and grade only that build. An agent with a shell could otherwise edit the Haskell source in the generated package.

## Edge cases

1. **A Hackage SQLite binding through FFI Tier 1.** Channel: harness rule 1. The spec is silent, and that is intentional.
2. **A call to an outside SQLite or Python through `wasi.proc`.** Channel: harness rule 2.
3. **A 0-byte starting database.** Sample test `000040b0…` has an empty `initial_database.sql`. The byte read must return a `bytes` of length 0, not an error. Channel: type. `bytes[0]` already parses (`Parser.hs:641`).
4. **Non-UTF-8 bytes in the SQL on standard input.** `(wasi.fs.read "/dev/stdin")` returns an error, and the test fails. Channel: the paired design must allow standard input as a byte source.
5. **64-bit integer overflow**, for example `SELECT 9223372036854775807 + 1`. LLMLL's `int` is unbounded, so the engine must emulate SQLite's behaviour by hand. Channel: contract, in QF-LIA, through range checks the agent writes.
6. **`(mod x -8)` or `(/ x y)` with a variable `y`.** These stay outside `Σ_auto` and report `nonlinear:mod` or `nonlinear:/`. Channel: contract fallback. This is the negative side of `SIGMA-CONST-ARITH-1`.
7. **`bytes-widen` on a `bytes[0]`.** The result has `bytesLen = 0`. Every `bytes-get` on it fails the precondition `0 ≤ i < 0`. Channel: contract, QF-LIA.
8. **A `bytes[32]` passed where a `bytes` is expected.** This is a type error, because there is no subtyping. The diagnostic should name `bytes-widen` as the repair. Channel: type.
9. **Positive witness for `bytes-widen`.** Widen a `bytes[32]`, then read at index 40. The read must refute. This is the discriminating negative for the length post, on the `examples/bytes-bounds/relay-overflow.llmll` precedent.
10. **Positive witness for the finding trigger.** Point A has the interval [0.10, 0.18]. Point B has the interval [0.21, 0.30]. The intervals do not overlap, so a finding is filed for an increase.

## Verification mapping

This evaluation creates no obligations itself. The items it orders create these:

| Obligation | Channel | Fragment |
|---|---|---|
| `string-from-code` range and surrogate precondition | contract | (a) QF-LIA |
| `string-code-at` index precondition | contract | (a) QF-LIA |
| `SIGMA-CONST-ARITH-1` terms | contract | (a) QF-LIA |
| `bytes-widen` length post | contract, from the source annotation | (a) QF-LIA |
| `bytes-slice` and `bytes-concat` length posts, under `0 ≤ s ≤ e ≤ bytesLen b` | contract | (a) QF-LIA |
| Content facts for slice and concat, instantiated at each read of the result (the `byte-range` discipline, `LLMLL.md §13.12`) | contract | (a) QF-LIA plus arrays, no quantifiers |
| A post quantified over all indices of a slice | contract | (c) `?proof-required` |

## Risks

1. **The first result is near 0.** Class: scope. With no cross-language reading, a low number only sets the baseline of the series.
2. **The total cost of the track.** Class: scope. Each point needs at least 5 sessions. The fixed budget and the minor-version cadence limit this.
3. **The size of `SIGMA-CONST-ARITH-1` is unknown.** Class: scope. The MEASURE step answers it.
4. **List-backed `bytes[n]` stays slow.** Class: performance. Only the new `bytes` type gets the `ByteString` backing. A program that keeps using `bytes[n]` keeps O(i) reads.

## Hand-off

- **(a) Record:** `docs/design/multilangbench-scope-evaluation.md`.
- **(b) Settled revision:** Rev 2.
- **(c) Review:** folded below as the Appendix on 2026-10-21 (M2). The standalone file is archived at [`../archive/professor-reviews/multilangbench-scope-evaluation-review.md`](../archive/professor-reviews/multilangbench-scope-evaluation-review.md), with no redirect stub, because the old path was never committed.
- **(d) Doc-lead summary (spec-track):** add one INDEX row. File `CHAR-CODE-1` (`[CT][SPEC]`, DECIDE) and `SIGMA-CONST-ARITH-1` (`[CT]`, MEASURE). Add a note to `BYTES-READ-1` and `BYTES-WRITE-1` that records shape (b) and the four representation points, and cites this record.
- **Experiment-lead backlog item:** the MultiLangBench longitudinal track, blocked until `BYTES-READ-1`, `BYTES-WRITE-1` and `CHAR-CODE-1` have shipped.

## Appendix — Professor review log

Folded 2026-10-21 by documentation-lead (M2). The two passes are copied unchanged from the standalone review. Pass 2 withdraws the matched-documentation recommendation of Pass 1. The open question of Pass 2 is answered in §4 of this record.

### Pass 1 (on Rev 0)

#### Restatement
The language-team recommends adopting MultiLangBench later, as a secondary probe, once Phase 3 has run. It recommends scheduling paired byte I/O and a new `char ↔ int` item on their own merit after FFI-TIER1-1, without the benchmark pulling them forward. This critique tests the validity of the benchmark, the claim that the assurance-credit variant can be verified, and the representation of the byte type.

#### Context located
- `LLMLL.md:13` and `LLMLL.md:1086`: the shipped `Σ_auto` omits `*`, `/` and `mod` entirely. `(* 8 r)` and `(mod r 8)` report `nonlinear:` and fall back, even though both are linear.
- `LLMLL.md:1086`: "The omission stands because no program in this repository needs the wider set." This is a policy choice, not a decidability limit.
- `compiler/src/LLMLL/FixpointEmit.hs:5667`: `nonNegMeasures = ["strLen", "listLen", "bytesLen"]`. A `bytesLen` measure already exists in the verifier.
- `compiler/src/LLMLL/FixpointEmit.hs:4188`: `bytes[n]` contracts map to `byteArraySort`, the array-theory encoding.
- `LLMLL.md §13.12`: the sealed-builtin axioms add ground facts at each bytes read (`byte-range`). They are instantiated per term, not quantified.
- `docs/design/language-comparison-experiments.md:236-253`: controls #2 ("Python should not be asked to do less") and #9 ("Do not collapse proof into tests").
- `experiments/language-comparison-backlog.md:78`: Phase 3 is blocked on S1–S8, open since 2026-05-15.
- No review or draft on byte representation exists in `docs/design/`.

#### Gaps and hazards

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

#### Recommendation
Accept the language-team's ADOPT-LATER verdict and its decision not to pull byte I/O forward for the benchmark. Revise four points:

1. **Make the benchmark's primary use longitudinal and within LLMLL.** Track version-over-version pass rate with a fixed model and harness. Allow a cross-language reading only with matched documentation budgets for every language, and label it as confounded by contamination.
2. **Replace the Phase 3 condition** with "BYTES-READ-1 + BYTES-WRITE-1 + `char ↔ int` shipped, and the harness rules in place".
3. **Before claiming assurance credit, widen `Σ_auto`** to multiplication by a numeral and `div`/`mod` by a positive numeral, as a separate small item. Without it, withdraw the "QF-LIA, verified" claim for the codec contracts. The widening has independent value and its decidability argument is already in `LLMLL.md:1086`.
4. **Fix the byte representation in the paired design** as an unindexed `bytes` with the `bytesLen` measure, `bytes[n]` as refinement sugar, a `ByteString` backing, length axioms in QF-LIA, and content axioms instantiated per term.

#### Open questions for the language-team
1. Does a refinement-sugar `bytes[n]` keep every existing `bytes[n]` program's verdict unchanged? In particular, `bytes-zero`'s rule that the return type sets the length (`FixpointEmit.hs:2244-2261`) and the `byte-range` facts must still fire when `n` is an index read from a refinement, not taken from the type syntax.
2. Is the `Σ_auto` widening one item or two? Multiplication by a numeral is trivially linear. `div` and `mod` by a numeral need the floor convention pinned against Haskell's `div`/`mod` and SMT-LIB's Euclidean `div`, and these disagree on negative divisors.

### Pass 2 (on Rev 1)

#### Restatement
Rev 1 keeps the adopt-later verdict, with four changes:
- The primary use becomes a longitudinal track within LLMLL.
- The gate becomes three shipped items: BYTES-READ-1, BYTES-WRITE-1 and `CHAR-CODE-1`.
- The assurance-credit claim now depends on a new `SIGMA-CONST-ARITH-1` widening.
- A separate unindexed `bytes` type is added, joined to `bytes[n]` by an explicit `bytes-widen`.

This pass checks those revisions and the two answers the language-team gave.

#### Context located
- `LLMLL.md:18`: no refinement subtyping. Rev 1's Q1 answer rests correctly on this.
- `compiler/src/LLMLL/FixpointEmit.hs:2244-2261`: one syntax match shared by four readers. This confirms that rewriting `bytes[n]` would break them.
- `examples/bytes-bounds/EXPECTED_VERDICTS.json`: six frozen verdicts, which serve as the regression gate.
- `compiler/src/LLMLL/Parser.hs:637-641`: `pBytesType` uses `pIntLit = L.decimal`. **`bytes[0]` parses and a negative length cannot.** This settles Rev 1's open item in its edge case 2.
- `compiler/src/LLMLL/FixpointEmit.hs:3585`, `:3830-3834`, `:4350`: `*`, `/`, `mod` and `rem` are refused in three places. The widening touches all three.
- `compiler/src/LLMLL/FixpointIR.hs`: a grep found no constructor for multiplication or `mod`. The IR may need new operators, which the engineer must confirm.
- `compiler/app/Main.hs:1463-1466`: the backend is the `liquid-fixpoint` binary, not Z3 called directly with SMT-LIB.
- `compiler/src/LLMLL/CodegenHs.hs:2165`: codegen lowers `mod` to Haskell `` `mod` ``, which rounds toward −∞.

#### Gaps and hazards

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

#### Recommendation
Settle Rev 1 after four changes:
1. **Remove the cross-language reading.** MultiLangBench is a longitudinal track within LLMLL only. Withdraw the matched-documentation idea, which was mine.
2. **State the longitudinal controls:** a pinned model snapshot, a recorded `LLMLL.md` hash, at least 5 pre-registered seeds per version, a bootstrap interval, and a fixed budget.
3. **File `SIGMA-CONST-ARITH-1` as MEASURE, not PLAN,** until the engineer has sized the IR and the three refusal sites. Add the quotient witness.
4. **Specify `CHAR-CODE-1`** as `string-code-at` and `string-from-code`, with the range-and-surrogate precondition. Prove `bytes-widen`'s length post from the source annotation instead of disclosing it.

#### Open questions for the language-team
1. Does the longitudinal track need its own pass/fail signal, or is it a descriptive time series? If a version's pass rate falls outside the prior interval, does that block a release, or only file a finding? Without an answer, the track measures something nobody acts on.
