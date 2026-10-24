---
title: INT-INDEX-WRAP-1 — an int argument is never narrowed by wrapping
status: Rev 0, SETTLED 2026-10-24 (option (a) chosen; the user asked the language-team to settle the row)
rows: INT-INDEX-WRAP-1 (G2, DECIDE to PLAN); BYTES-LEN-RANGE-1 (new, G1, PLAN); BYTES-SET-PBT-PRE-1 (new, G1, PLAN); EXIT-STATUS-DOC-1 (new, spec drift, DOC); PROC-RUN-TIMEOUT-1 (new, G7, DECIDE)
review: none (no professor pass)
---

# INT-INDEX-WRAP-1 — an int argument is never narrowed by wrapping

## Settled decision

**Option (a).** An `int` argument outside `Int64` is an ordinary out-of-range value. Each builtin answers what its own out-of-range rule already says. `list-nth` answers `Error`, `string-char-at` answers `""`, `string-slice` clamps, and `bytes-get` and `bytes-set` fail their runtime precondition. The runtime compares the unbounded value first. It narrows to `Int` only a value that the comparison has placed inside a collection, where the narrowing is exact.

Option (b), a bound on indices in the Class A note and the trust closure, is rejected. The reasons are in "Why not option (b)".

The same rule covers the two other narrowing sites that the census found in the runtime: the `wasi.proc.run` and `wasi.proc.exec` timeouts, and the `:status` exit value. The census also found one narrowing site in the S-expression parser. That site gives a false `verified` today, so it is filed as a separate G1 row, `BYTES-LEN-RANGE-1`.

`codegen_semantics_version` and `checker_soundness_version` do not change. `pbtGeneratorTag` changes from `"gen2"` to `"gen3"`, so `tested` evidence earned under the old evaluator is downgraded once.

## Restatement

The Class A shims convert an unbounded `int` (Haskell `Integer`) to `Int` with `fromIntegral`. That conversion keeps the low 64 bits. So an index of 2⁶⁴ reads as 0, and `(list-nth xs 18446744073709551616)` answers `Success` with the first element. The spec gives every `int` value an answer through the builtin's out-of-range rule. The question is whether the runtime must honour that for all `int` values, or whether the spec must exclude indices outside `Int64` from the builtin's domain. The runtime and the PBT evaluator must give one answer.

## Context located

1. `docs/compiler-team-roadmap.md`, G2 row `INT-INDEX-WRAP-1`: the DECIDE between (a) and (b).
2. `LLMLL.md` §13.5 (`list-nth`: "`Error` on out-of-range"), §13.6 (`string-slice` clamps, `string-char-at` returns `""`), and the §13.6 Class A note. The note bounds collection **lengths** to `2⁶³ − 1`. It says nothing about indices.
3. `LLMLL.md` §13.12: `bytes-get` and `bytes-set` carry the precondition `0 ≤ i < n`. The §13.12 "sealed-builtin axiom set" says their assumed posts ride `codegen_semantics_version`.
4. `LLMLL.md` §5.3.3, array class: `bytesLen(v) = n` is earned per position, and the index-in-bounds precondition is a PROVE-polarity call-site obligation.
5. `LLMLL.md` §9.5, "The terminal status": the text says a POSIX exit status is the low 8 bits, so 300 gives 44 and 256 gives 0. This is **spec drift**: see edge case 9.
6. `docs/archive/shipped-design-specs/int-2-boundary-shims.md` §3.1: the INT-2 decision that kept `Int` signatures for the Class A primitives and put `fromIntegral` at the call seam. This proposal changes that decision for index arguments only.
7. `compiler/src/LLMLL/CodegenHs.hs`, `emitApp`: the six Class A clauses that emit `(fromIntegral … :: Int)` for `bytes-get`, `bytes-set`, `bytes-zero`, `list-nth`, `string-slice` and `string-char-at`. The preamble's `wasi_proc_run`, `wasi_proc_exec` (`timeout (fromIntegral (secs * 1000000))`) and the two `llmll_terminate` definitions (`ExitFailure (fromIntegral n)`).
8. `compiler/src/LLMLL/RuntimePure.hs`: `list_nth`, `string_slice` and `string_char_at` take `Int`. The BEGIN/END region is pinned to the preamble by the Spec.hs test "PBT-EVAL-PARITY-1: every RuntimePure block is in the preamble verbatim".
9. `compiler/src/LLMLL/Contracts.hs`: `intIx` copies the seam (`fromIntegral` to `Int`) for `list-nth`, `string-slice` and `string-char-at`. The bytes arms (`bytesChainGet`) compare in `Integer` and do not narrow. `evalBuiltinApp "bytes-set"` checks no precondition.
10. `compiler/src/LLMLL/FixpointEmit.hs`: `bodyToPredM` for `bytes-get` and `bytes-set` (the PROVE pre `0 ≤ i < bytesLen(b)`, the reflection post); `sealedAxiomBuiltins`; `nonNegMeasures` (`strLen`, `listLen`, `bytesLen` are each `≥ 0`). The emitter reflects no `list-nth`, `string-char-at` or `string-slice`, and no `respFact` names them.
11. `compiler/src/LLMLL/Parser.hs`, `pBytesType`: `TBytes (fromIntegral n)` from an unbounded literal. `compiler/src/LLMLL/ParserJSON.hs`: the `bytes` type reads `length` as `Int`. Aeson refuses a value above `Int64` and accepts a negative value.
12. `compiler/src/LLMLL/PBT.hs`: `pbtGeneratorTag = "gen2"` and `genInt`, which draws from `choose (−2⁶⁴, 2⁶⁴)` at weight 1 of 10. So the shipped generator reaches indices outside `Int64`.
13. `compiler/src/LLMLL/ProofArtifact.hs` (`codegenSemanticsVersion = "int-unbounded-1"`) and `compiler/src/LLMLL/VerifiedCache.hs` (`checkerSoundnessVersion = "3"`).
14. Related rows: `FFI-NARROW-1` (G7; `hs-int` arguments are refused because the narrowing is partial), `JSON-INT-UNBOUNDED-1` (G3; a JSON `lit-int` above `Int64` is a decode error), `PROC-BOUNDARY-1 residue (1)` (the same incorrect 300-to-44 text as item 5).

No design record exists for this row. This is Rev 0.

## Census: every narrowing of an `int` to `Int`

The census read every `fromIntegral`, `fromInteger`, `toEnum` and `:: Int` site in `compiler/src/LLMLL/CodegenHs.hs`, `RuntimePure.hs`, `Contracts.hs`, `Ffi.hs`, `Parser.hs` and `ParserJSON.hs`. A conversion from `Int` to `Integer` widens and cannot lose a value. Only the direction `Integer` to `Int` is listed as narrowing.

| Site | Surface | Direction | Value outside `Int64` today | Decision |
|---|---|---|---|---|
| `emitApp "list-nth"`, `intIx` | index | narrows | low 64 bits used as the index | D1: compare in `Integer` |
| `emitApp "string-char-at"`, `intIx` | index | narrows | low 64 bits | D1 |
| `emitApp "string-slice"`, `intIx` | start, end | narrows | low 64 bits, then clamp | D1 |
| `emitApp "bytes-get"` | index | narrows | low 64 bits; the precondition check sees the wrapped value | D1 |
| `emitApp "bytes-set"` | index | narrows | low 64 bits | D1 |
| `emitApp "bytes-zero"` | length from `TBytes` | `Int` to `Int` | not reachable: the value comes from `TBytes Int` | none; see D4 |
| `pBytesType` (S-expression parser) | `bytes[n]` length | narrows | low 64 bits; 2⁶³ becomes −2⁶³ | D4: new G1 row |
| `ParserJSON` `bytes.length` | `bytes[n]` length | aeson `Int` | refused above `Int64`; −1 accepted | D4 |
| `wasi_proc_run`, `wasi_proc_exec` | `secs * 1000000` | narrows | low 64 bits of the microsecond count | D2: clamp |
| `llmll_terminate` (console and cli) | `:status` value | narrows | low 64 bits; a multiple of 2⁶⁴ crashes | D3 |
| `list-length`, `string-length`, `bytes-length` | result | widens | none | none; the Class A length note stays |
| `range` | endpoints | `Integer` throughout | none | none |
| `regex_spans`, `regex_replace_all` | internal offsets | narrows | not reachable: offsets come from a `String` | none |
| `wasi_http_response`, `RCode` | status | `Integer` throughout | none | none |
| `wasi_clock_monotonic`, `wasi.fs.size`, `wasi.fs.stat` | result | widens | none | none |
| `Ffi.convOut` `hs-int` | result | widens | none | none |
| `Ffi` `hs-int` argument | argument | refused (E18) | not reachable | none; `FFI-NARROW-1` |
| `ParserJSON` `lit-int` | literal | aeson `Int` | refused | none; `JSON-INT-UNBOUNDED-1` |

No `list-take`, `list-drop`, `string-repeat` or `list-range` builtin exists in `builtinEnv` (`compiler/src/LLMLL/TypeCheck.hs`), so none is listed. A future builtin with an `int` count or index follows D1.

## Design proposal

### D1. The index rule

**Rule.** Let `b` be one of `list-nth`, `string-char-at`, `string-slice`, `bytes-get` and `bytes-set`. Let `i` be any `int` argument in an index position. The runtime evaluates `b`'s range test on the unbounded value of `i`. It converts `i` to `Int` only after the test places `i` inside `[0, n]`, where `n` is the collection length.

**Answers.** The rule changes no spec text about these builtins. It makes the runtime agree with the text that exists:

| Builtin | `i ≥ 2⁶³` | `i ≤ −2⁶³ − 1` |
|---|---|---|
| `list-nth xs i` | `Error`, and the message shows the true `i` | `Error` |
| `string-char-at s i` | `""` | `""` |
| `string-slice s i j` (as start) | start clamps to `string-length s` | start clamps to 0 |
| `string-slice s i j` (as end) | end clamps to `string-length s` | end clamps to 0 |
| `bytes-get b i`, `bytes-set b i v` | runtime precondition failure, as for any `i ≥ n` | runtime precondition failure, as for any `i < 0` |

**Soundness argument (runtime agrees with spec).** Let `n` be a collection length. The Class A note gives `n ≤ 2⁶³ − 1`. Each builtin's spec answer depends on `i` only through the tests `0 ≤ i`, `i < n`, and the clamp `min n (max 0 i)`. The new runtime evaluates those tests in `Integer`, so it computes the spec answer for every `i`. The only conversion left is of a value already inside `[0, n]`. On that interval `fromIntegral :: Integer -> Int` is the identity embedding, because `[0, n] ⊆ [0, 2⁶³ − 1]`. So no wrap can occur.

**Implementation shape (settled).** The index parameters of `list_nth`, `string_char_at`, `string_slice`, `bytes_get` and `bytes_set` become `Integer`. The comparison and the conversion move inside each definition. The `emitApp` clauses for the five builtins pass the argument with no `fromIntegral`. `intIx` in `Contracts.hs` becomes the identity on `Integer`.

The rejected alternative keeps `Int` signatures and adds a saturating seam, `max minBound (min maxBound i)`, in `emitApp` and in `intIx`. Saturation gives the same answers, by the lemma "for any interval `I` inside the `Int` range, `x ∈ I` iff `sat x ∈ I`, and `clamp_I (sat x) = clamp_I x`". It is rejected for two reasons. First, the seam would stay in two places, `emitApp` and `intIx`, that only hand discipline keeps equal. With `Integer` signatures the range logic lives inside the RuntimePure BEGIN/END region, and the existing Spec.hs region test keeps the two copies equal. Second, the `list_nth` error message would show the saturated value `9223372036854775807` and not the index the program passed.

The length builtins keep `Int` results widened to `Integer`. The Class A length note keeps its bound. A length above `2⁶³ − 1` needs a collection that no machine can hold, so that bound costs nothing in practice. An index above `2⁶³ − 1` needs one literal or one `string-to-int` on input text.

**Cost.** One `Integer` comparison per call. A small `Integer` is the `IS` constructor, so the comparison does not allocate. `STR-INDEX-LINEAR-1`'s cache path is unchanged after the test.

### D2. Process timeouts clamp

`wasi.proc.run` and `wasi.proc.exec` compute `secs * 1000000` in `Integer` and narrow it for `System.Timeout.timeout`. The runtime clamps the microsecond count into `[minBound, maxBound]` of `Int` before the conversion.

Soundness: inside `Int64` the clamp is the identity, so no current behaviour changes. Above it, the timeout becomes `2⁶³ − 1` microseconds, about 292,471 years. No child process can tell that from a longer timeout. Below it, the count stays negative, and `timeout` with a negative count waits without limit, as every negative count does today. `wasi.proc.exec` already refuses `secs < 1` before the child starts, so only the upper clamp applies to it. `timeout maxBound` was measured on GHC 9.6.6 (aarch64-osx) with and without `-threaded`; both returned `Just` for a 0.2 s action.

### D3. The `:status` exit value

`llmll_terminate` (the `console` and `cli` harnesses in `CodegenHs.hs`) computes the exit value in `Integer` before the conversion. A value above 255 or below −127 exits with `ExitFailure 255`. Every other value keeps its current path: 0 calls `exitSuccess`, and the value is passed to `exitWith (ExitFailure n)`.

Soundness: GHC's `exitWith` already exits 255 for every `Int` value outside `−127..255` (measured: 256, 300, −128 and 2³² each exit 255). So inside `Int64` the rule changes nothing. Outside `Int64` it removes the wrap, which today crashes the harness on any multiple of 2⁶⁴ (`exitWith: invalid argument (ExitFailure 0)`, exit 1) and gives arbitrary values elsewhere. This decision does not choose a different exit-status semantics. That choice belongs to `EXIT-STATUS-DOC-1` below.

### D4. A `bytes[n]` length outside `[0, 2⁶³ − 1]` is a check error (new row `BYTES-LEN-RANGE-1`, G1)

`pBytesType` narrows the literal with `fromIntegral`. So `bytes[9223372036854775808]` becomes `TBytes (−9223372036854775808)`. The JSON front end accepts `"length": -1`. In both cases the verifier receives `bytesLen(result) = n` with `n < 0` from the `bytes-zero` constructor axiom, and `bytesLen(result) ≥ 0` from `nonNegMeasures`. The hypotheses contradict, so every goal discharges.

Measured on the v0.30.10 binary (the emitter code is the same on `main` `03e7195e`):

```lisp
(def mk [] -> bytes[9223372036854775808]
  (post (= 1 2))
  (bytes-zero))
```

`llmll verify` reports `body-faithful: mk` and `SAFE (liquid-fixpoint)`. The `.fq` left-hand side holds `(bytesLen _bv_call_bytes_zero_0) >= 0` and `(bytesLen _bv_call_bytes_zero_0) = -9223372036854775808`. The JSON form with `"length": -1` also reports SAFE. The control, `bytes[7]` with the same post, is refuted. This is a false `verified`, so it is G1, not G2.

**Rule.** A `bytes[n]` type with `n < 0` or `n > 2⁶³ − 1` is a `check` error in both front ends, with one diagnostic kind (suggested name `bytes-length-range`). The S-expression parser must not narrow before the check. The verifier then never receives a negative or wrapped `n`, and the `nonNegMeasures` fact is consistent with every constructor axiom.

This row is separate because its severity is higher than G2. The engineer can ship it in the same patch.

### D5. Evidence and stamps

- **`codegen_semantics_version` stays `"int-unbounded-1"`.** Its scope is `int` against `machine-int` (CHANGELOG precedent: the arm that "raises a runtime error where GHC already raised one" did not spend it, because `INT-3` needs it unspent). D1 to D3 make the generated code agree with the stamp's meaning at a seam where it did not. The validity of each sealed-builtin axiom (`bytes-get`, `bytes-set`) is conditioned on the PROVE pre `0 ≤ i < bytesLen(b)`, and with D4 `bytesLen(b) ≤ 2⁶³ − 1`. On that domain the old and new runtimes agree.
- **`checker_soundness_version` stays `"3"`.** D1 to D3 change no emitted constraint, so no verdict moves. D4 moves verdicts, but only of a source that stops type-checking. Every consumer of that sidecar reaches the type check first. The engineer confirms this for each sidecar read path (the `trust-report` and `spec-coverage` commands, and an imported module loaded from its sidecar). If any path reads the sidecar without a type check of its source, the version changes to `"4"`.
- **`pbtGeneratorTag` changes from `"gen2"` to `"gen3"`.** A `tested` record says that a property held on samples of the program as built. The fix changes the built program and the evaluator on samples outside `Int64`, and `genInt` draws those samples. A record earned on such a sample can be false for the new program. Changing the tag downgrades every `tested` record once, until `llmll test` runs again. `verified` is not affected. This is the `PBT-GEN-NEG-1` mechanism. The tag comment must say that the tag also names the evaluator semantics.
- **Schema:** none. **`trust_report_version`, obligation-report `schema_version`:** unchanged. **New diagnostic kind:** one, from D4.

### Why not option (b)

1. **`int` is unbounded (§3.1), and an index is an ordinary `int`.** A CLI program reads an index from input with `string-to-int`, which answers an unbounded `Integer`. Under (b) the text `18446744073709551616` in a CSV cell selects the first row. The length bound in the Class A note is not a precedent: no machine holds 2⁶³ elements, but any program can hold the value 2⁶⁴.
2. **(b) is a spec change that weakens documented answers.** `list-nth` returns `Result` so that out-of-range is a value and not a crash. A domain restriction makes `list-nth` partial on a value its type admits, and nothing reports a call outside the domain.
3. **(b) cannot be checked.** The verifier reflects no `list-nth` or `string-*` index, so a domain bound on them would be a trust-closure line with no obligation behind it. To check it, each call would need a new `pre` (`i < 2⁶³`), which is a new sealed-builtin precondition and work for every caller.
4. **(a) costs one comparison per call and no spec text.** The out-of-range rules already exist. Only the Class A note and the INT-2 design note about the seam change.

### Relation to tracked rows

`FFI-NARROW-1` asks the same question for Hackage exports. Its DECIDE lists "a run-time range check that answers through `Result`". This proposal **anticipates** that option for builtins, where an out-of-range answer already exists. It does not decide `FFI-NARROW-1`, because a Hackage export has no out-of-range rule of its own. `JSON-INT-UNBOUNDED-1` will let a JSON literal exceed `Int64`. When it lands, the JSON `bytes.length` field must go through the D4 range rule, and JSON literal indices reach D1 as S-expression literals do today.

## Edge cases and witnesses

All runtime witnesses were built and run with the v0.30.10 binary in the session scratchpad. The relevant `emitApp`, preamble, `RuntimePure` and `Parser` code is the same on `main` `03e7195e`. Each "after" answer is the D1 to D4 rule applied to the spec text.

1. **Positive witness, D1, `list-nth` at 2⁶⁴.** `xs = [10, 20, 30]`. `(list-nth xs 18446744073709551616)` answers `Success 10` today; 2⁶⁴ + 1 answers `Success 20`. After: `Error`. Channel: trust (sealed-builtin runtime semantics, §7) and PBT. Cite: §13.5.
2. **Positive witness, D1, negative side.** `(list-nth xs -18446744073709551616)` answers `Success 10` today; −2⁶⁴ + 1 answers `Success 20`. After: `Error`. Channel: trust and PBT.
3. **Quiet case, D1.** `(list-nth xs 9223372036854775808)` (2⁶³) answers `Error` today by accident, with the message "index -9223372036854775808 out of range". `(list-nth xs -9223372036854775809)` answers `Error` with "index 9223372036854775807". After: the same `Error`, and the message names the true index. `(list-nth xs 2)` is `Success 30` before and after.
4. **Positive witness, D1, `string-char-at`.** `(string-char-at "abc" 18446744073709551618)` answers `"c"` today; 2⁶⁴ and −2⁶⁴ answer `"a"`. After: `""`. Cite: §13.6.
5. **Positive witness, D1, `string-slice` clamp.** Measured today: `(string-slice "abc" 18446744073709551616 18446744073709551618)` gives `"ab"`; after, `""` (both endpoints clamp to 3). `(string-slice "abc" 0 18446744073709551615)` gives `""`; after, `"abc"`. `(string-slice "abc" 0 9223372036854775808)` gives `""`; after, `"abc"`. `(string-slice "abc" -9223372036854775809 2)` gives `""`; after, `"ab"`. Cite: §13.6 clamp rule.
6. **Positive witness, D1, bytes precondition.** In a `def-shell` with `b : bytes[4]`, `(bytes-set b 18446744073709551617 7)` writes index 1, and `(bytes-get b 18446744073709551616)` reads index 0. The measured program printed `70`. After: the runtime precondition fails at the `bytes-set` call. Channel: contract, runtime half (§5.3.4 backstop). The PROVE pre would refute both calls in a body-faithful `def`, so this case reaches run time only through a `def-shell` or an unchecked call (`call-pre unchecked`, §5.3.4).
7. **Positive witness, D2, timeout.** `(wasi.proc.run "/bin/sleep" ["2"] "." "/dev/null" "/dev/null" 18446744073710 "/dev/null")` answers `RErr "wasi.proc.run: /bin/sleep exceeded 18446744073710s"` after about 0.5 s. The microsecond count wrapped to 448,384. After: the child runs to completion and the answer is `RCode 0`. Quiet case: `secs = 9223372036855` wraps negative today and waits without limit; after, it clamps and also completes (measured today: `RCode 0`, 2.5 s).
8. **Positive witness, D3, exit value.** A `cli` program whose `:status` returns 18446744073709551616 prints `exitWith: invalid argument (ExitFailure 0)` and exits 1. After: exit 255. Quiet cases, measured and unchanged: 256, 300, −128 and 4294967296 exit 255; −1 exits 129 and −9 exits 137, because GHC sends the process the signal `−n`.
9. **Spec drift found by edge case 8 (`EXIT-STATUS-DOC-1`).** `LLMLL.md` §9.5 says "a `:status` returning 300 truncates to 44, and one returning 256 exits **0 and reports success**". The measured exits are 255 and 255. The roadmap row `PROC-BOUNDARY-1 residue (1)` repeats the same text. Channel: spec is silent on the real behaviour (gap — flag). The doc fix is in the doc-lead hand-off.
10. **Positive witness, D4.** The `bytes[9223372036854775808]` program in D4 verifies SAFE with `(post (= 1 2))`. The JSON form with `"length": -1` verifies SAFE. After: both are a `check` error. Quiet case: `bytes[18446744073709551619]` reads as `bytes[3]` today, so the verifier and the runtime agree on 3, but the declared type is false. After: a `check` error. Channel: type.
11. **Positive witness, `BYTES-SET-PBT-PRE-1` (found during the census, not a narrowing).** `(check "p" (for-all [i: int] (= (bytes-length (bytes-set (z) i 1)) 4)))`, with `z : -> bytes[4]` returning `(bytes-zero)`, passes `llmll test` (measured, 2 of 2 properties passed). Every sample with `i ∉ [0, 4)` violates `bytes-set`'s precondition, and the built program fails there. `evalBuiltinApp "bytes-set"` builds the store chain with no bound check, where `bytes-get` discards the sample. §5.1 "Precondition-guarded samples" says such a sample is discarded. Channel: PBT (`tested`). Rule: the evaluator discards a `bytes-set` sample whose index is outside `[0, n)` or whose value is outside `0..255`, as it does for `bytes-get`.
12. **PBT evidence, D5.** `genInt`'s weight-1 bucket `choose (−2⁶⁴, 2⁶⁴)` gives an index outside `Int64` on about half of its draws. A property `(for-all [j: int] (=> (>= j 3) (= (string-slice "abc" 0 j) "abc")))` is falsified today on any `j` in `[2⁶³, 2⁶⁴)`, because the end wraps negative and the slice is `""`. After: it passes. The tag change makes any `tested` record from the old evaluator render `asserted` until `llmll test` runs again.

## Verification mapping

| Obligation or claim | Channel | Fragment | Note |
|---|---|---|---|
| D1 answers of `list-nth`, `string-char-at`, `string-slice` | trust (sealed builtin, §7) and PBT | none; no solver obligation | The emitter reflects none of the three. The answers are runtime semantics, tested by PBT through the shared RuntimePure definitions |
| D1 for `bytes-get`, `bytes-set`: `0 ≤ i < bytesLen(b)` | contract, PROVE polarity at the call site | **(a) QF-LIA**, unchanged | The emitted constraint does not change. The runtime half of the same precondition now fires for every out-of-range `i` |
| Sealed axioms `r = select(b, i)`, `r = store(b, i, v)`, `bytesLen(r) = bytesLen(b)` | trust (`codegen_semantics_version`) | **(a)**, unchanged | Valid under the PROVE pre. With D4, the pre implies `i ≤ 2⁶³ − 2`, where narrowing is exact |
| D4: `0 ≤ n ≤ 2⁶³ − 1` for each `bytes[n]` | type | none (syntactic side condition) | Removes the contradiction between the constructor axiom and `nonNegMeasures` |
| D2 timeout clamp, D3 exit value | trust (harness semantics) | none | No program-visible value changes inside `Int64` |
| `BYTES-SET-PBT-PRE-1` discard | PBT (`tested`) | none | §5.1 precondition-guarded samples |

**`Σ_auto` is unchanged.** No symbol, sort or axiom is added. The sealed-builtin axiom set of §13.12 stays closed. The `.fq` output of every program that passes `check` before and after is byte-identical, because `FixpointEmit.hs` does not change.

## Affected surface

- **`compiler/src/LLMLL/RuntimePure.hs`**: `list_nth`, `string_slice` and `string_char_at` take `Integer` indices (D1). The references `string_slice_ref` and `string_char_at_ref` outside the region follow.
- **`compiler/src/LLMLL/CodegenHs.hs`**: the same three definitions in `runtimePreamble` (region test); `bytes_get` and `bytes_set` take an `Integer` index; the five `emitApp` clauses drop `fromIntegral`; the `emitApp "bytes-zero"` clause is unchanged; `wasi_proc_run` and `wasi_proc_exec` clamp the microsecond count (D2); both `llmll_terminate` definitions apply D3. The LT-INT comment above the Class A clauses changes.
- **`compiler/src/LLMLL/Contracts.hs`**: `intIx` returns `Integer` with no narrowing; its comment changes. `evalBuiltinApp "bytes-set"` discards a sample outside the precondition (`BYTES-SET-PBT-PRE-1`).
- **`compiler/src/LLMLL/PBT.hs`**: `pbtGeneratorTag` to `"gen3"`, and its comment names the evaluator.
- **`compiler/src/LLMLL/Parser.hs`**, **`ParserJSON.hs`**, **`TypeCheck.hs`**, **`Diagnostic.hs`**: the D4 range check and its diagnostic kind. `TBytes` can keep `Int` if the check runs on the literal before narrowing.
- **`compiler/test/Spec.hs`**: the parity properties that apply `fromIntegral` to `x` before calling `RP.list_nth`, `RP.string_slice` and `RP.string_char_at` change to pass the `Integer`. Each positive witness above becomes a regression test. Witness 10 needs a fixture under the false-SAFE regression set.
- **`LLMLL.md`**: §13.6 Class A note; §9.5 exit-status text; §13.5 and §13.6 rows unchanged. See the doc-lead hand-off.
- **`docs/archive/shipped-design-specs/int-2-boundary-shims.md`**: not edited (archived). The §13.6 note supersedes its §3.1 seam for index arguments.
- **Additions:** none. No builtin, construct, capability or FFI tier is added. D4 adds one diagnostic kind.

## Risks and open questions

1. **D4 is a false `verified` in the shipped compiler.** Class: soundness. Cite: D4 witness. Effect: blocks nothing here, but it outranks this row. File it in G1 and ship it no later than D1.
2. **The `"gen3"` tag downgrades every `tested` record once.** Class: verification-ergonomics. Cite: `PBT-GEN-NEG-1` precedent. Effect: one `llmll test` run per tree. The cheaper option, no tag change, leaves a record that may be false for the new program, and nothing marks it.
3. **D3 keeps GHC's signal behaviour for −127..−1.** Class: spec-drift. Cite: edge case 8. Effect: minor. `EXIT-STATUS-DOC-1` records the real behaviour now. A later decision can normalize the exit value, for example to `n mod 256` as the §9.5 text assumed. That is a behaviour change and needs its own row.
4. **`wasi.proc.run` has no rule for `secs ≤ 0`.** Class: spec-drift (spec is silent; gap). Cite: `System.Timeout.timeout` contract: 0 times out at once after the child starts, and a negative count never times out. `wasi.proc.exec` refuses `secs < 1`. Effect: minor. Filed as `PROC-RUN-TIMEOUT-1` (G7, DECIDE). Not a narrowing, so D2 does not change it.
5. **A future builtin with an `int` count.** Class: scope. Cite: census. Effect: only matters when one is added (`CHAR-CODE-1`'s `string-from-code` is the next candidate). D1 is the rule for it.

## Open questions for the professor

None. Each candidate failed the negative test: the census, the measured witnesses and the existing out-of-range rules answered it.

## Hand-off

- **Proposal file:** `docs/design/int-index-wrap-1-proposal.md`, **Rev 0, settled**. No standalone review file exists, so no fold-and-archive (M2) is triggered.
- **Rows** (doc-lead files and moves them):
  1. `INT-INDEX-WRAP-1` (G2): DECIDE to **PLAN**, option (a), with D1 to D3 and the D5 tag change.
  2. `BYTES-LEN-RANGE-1` (new, **G1**, PLAN): D4. Witness: `bytes[9223372036854775808]` with `(post (= 1 2))` verifies SAFE.
  3. `BYTES-SET-PBT-PRE-1` (new, G1, PLAN): the evaluator discards a `bytes-set` sample outside its precondition. Witness: edge case 11.
  4. `EXIT-STATUS-DOC-1` (new, DOC): the §9.5 text and the `PROC-BOUNDARY-1 residue (1)` row state measured exit values.
  5. `PROC-RUN-TIMEOUT-1` (new, G7, DECIDE): the meaning of `secs ≤ 0` for `wasi.proc.run`.
- **Engineer summary (code-track).** Change the index parameters of `list_nth`, `string_char_at` and `string_slice` to `Integer` inside the RuntimePure region and the preamble together. Do the same for `bytes_get` and `bytes_set` in the preamble. Compare in `Integer` and convert only a value inside `[0, n]`. Remove `fromIntegral` from the five `emitApp` index clauses, and make `intIx` the identity on `Integer`. Clamp `secs * 1000000` to the `Int` range in `wasi_proc_run` and `wasi_proc_exec`. In both `llmll_terminate` definitions, send any value above 255 or below −127 to `ExitFailure 255` before the conversion. Change `pbtGeneratorTag` to `"gen3"`. In the same patch or before it, reject `bytes[n]` with `n < 0` or `n > 2⁶³ − 1` in both front ends with one diagnostic kind. Make the evaluator discard out-of-precondition `bytes-set` samples. `FixpointEmit.hs` does not change; confirm that the `.fq` files of the tracked corpus are byte-identical by emission only, never by a corpus-wide `verify`. Confirm that each sidecar read path type-checks its source first, or change `checker_soundness_version` to `"4"`. `codegen_semantics_version` stays `"int-unbounded-1"`. Each positive witness in the edge-case list becomes a regression test.
- **Doc-lead summary (after the engineer ships).** `LLMLL.md` §13.6, the Class A note: keep the length bound, remove the statement that `fromIntegral` shims sit at the seam for index arguments, and add: "An index argument is compared as an unbounded `int`. An index outside the collection, including one outside `Int64`, gets the builtin's out-of-range answer: `list-nth` answers `Error`, `string-char-at` answers `""`, `string-slice` clamps, and `bytes-get` and `bytes-set` fail their precondition." `LLMLL.md` §9.5: replace "the low 8 bits" and "300 truncates to 44, and one returning 256 exits 0 and reports success" with the measured rule: 0 exits 0, 1 to 255 exit with that value, −127 to −1 end the process with signal `−n`, and every other value exits 255. Keep the advice to declare the `0..255` range. Update the `PROC-BOUNDARY-1 residue (1)` row text the same way. `LLMLL.md` §13.9: one sentence for `wasi.proc.run` and `wasi.proc.exec`, "a timeout longer than about 292,000 years acts as that bound". Name the new D4 diagnostic kind wherever §13.12 lists `bytes[n]` rules. CHANGELOG: the `"gen3"` downgrade and its one-time cost, and that `codegen_semantics_version` and `checker_soundness_version` are unchanged (or `"4"` if the engineer finds a read path without a type check).
