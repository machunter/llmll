---
title: FFI buffers — passing byte buffers to native kernels
status: Rev 1, DRAFT 2026-11-02. Not reviewed. Not approved by the user.
rows: FFI-KERNEL-1 (proposed, G7, PLAN on settlement; answers FFI-TIER2-1 and lifts FFI-TIER2-REFUSE-1 for one import form); FFI-BYTES-1 (G3, PLAN; text amended, content unchanged); FFI-TIER2-1 (G7, DECIDE; answered and absorbed); FFI-NARROW-1 (G7, DECIDE; answered for kernel entries only); FFI-CONTRACT-1 (G3, DECIDE; `pre` answered for kernel entries only); FFI-UNINTERP-1 (anticipated, not changed); BYTES-READ-RANGE-1 (proposed, G4, DECIDE); FFI-KERNEL-REUSE-1, FFI-KERNEL-HS-1, FFI-KERNEL-POST-1 (proposed, Trigger-gated Parking Lot)
review: none yet
---

# FFI buffers — passing byte buffers to native kernels

**Status: Rev 1, DRAFT 2026-11-02.** The language-team wrote this revision on 2026-11-02. No professor pass exists. The user has not adjudicated it.

## Restatement

A video library needs this shape. A verified LLMLL core does container parsing, bounds and index arithmetic, and frame bookkeeping. Native code does the pixel work on frames of millions of bytes. LLMLL has no way to give a byte buffer of run-time length to native code and get one back. The settled Tier 2 plan (`docs/design/ffi-determinism-proposal.md` Part 7) maps scalars only. This record designs the buffer boundary: the type it uses, the Tier 1 step, the Tier 2 C convention (ownership, lifetime, mutation), the verification facts a caller may use, the trust disclosure, and the ship order.

The design-reference set is the verified-language ecosystem, not the measurement set. Liquid Haskell reaches C through GHC's FFI with no checked contract at the boundary. F\* and Dafny extract to C or call native code under an `assume`d specification. The bar for LLMLL is a boundary whose memory-safety preconditions and output-length facts are checked or earned, and whose remaining assumptions are named in the trust report per verdict.

## Context located

1. `docs/design/byte-io-proposal.md` Rev 2, SETTLED 2026-10-31, Part 4 and "FFI boundary". This is the BYTE-IO decision. It settles the unsized type `bytes` (strict `ByteString`), its operations, its partial reflections and its length measure `bytesLen`. Its ship order has four steps. Step 2 (`ABSTRACTION-VERDICT-1`) shipped in v0.34.0. Step 1 (`BITWISE-1`, `CHAR-CODE-1`) and step 3 (`BYTES-UNSIZED-1`, `BYTES-READ-1`, `BYTES-WRITE-1`) are open. **This record builds on Part 4. It does not design a second unsized type.**
2. `docs/design/ffi-determinism-proposal.md` Rev 1, SETTLED. Part 1 refuses `c.*` at `check`. Part 3 gives the congruence rules R1–R5, and R2 is the sort criterion. Part 7 lists the six parts of `FFI-TIER2-1`, all scalar.
3. `docs/design/ffi-tier1-proposal.md` Rev 3, SETTLED. D1 is the forced binding. D3 refuses `bytes[n]` in a result, because nothing checks its length. D5 closes the package set at nine. D9 is the `ffi_assumptions` row. D10 adds the boundary types.
4. `docs/compiler-team-roadmap.md` rows `FFI-TIER2-1`, `FFI-BYTES-1`, `BYTES-UNSIZED-1`, `FFI-DETERM-GATE-1`, `FFI-NARROW-1`, `FFI-CONTRACT-1`, `FFI-UNINTERP-1`, `FFI-OPAQUE-1`, `BYTES-SLICE-CONTENT-1`, `SAFE-HASKELL-CLAIM-1`.
5. `LLMLL.md` §3 (`bytes[n]` is fixed length), §5.3.3 (the array class; `bytesLen` earned per position; `bytesLenParamPre`, `bytesLenRetPost`), §7 (External Bridge; the reach table row for `bytestring` reads "none"), §13.12 (the closed sealed-builtin axiom set).
6. `compiler/src/LLMLL/Ffi.hs`, `ffiImportErrors`: every `c.*` import gets `ffi-tier2-refused`. `allowed` admits `TBytes _` in arguments only; `mentionsBytes` refuses it in a result.
7. `compiler/src/LLMLL/CodegenHs.hs`: `toHsType (TBytes _) = "[Word8]"`; the preamble defines `bytes_get`, `bytes_set`, `bytes_length` over `[Word8]`. `emitFfiStub` and `emitFfiDecl` still write `foreign import ccall "<llmll name>"` at the LLMLL type. No checked program reaches them since v0.34.1.
8. `compiler/src/LLMLL/AbstractionVerdict.hs`: the shipped verdict rule implements clause 2 (repeated calls). The clause-1 builtin set arrives with `CHAR-CODE-1` and `BYTES-UNSIZED-1`.
9. `compiler/src/LLMLL/PBT.hs`, `runPropertyTestsWithFfi`: the property runner is an interpreter. A property that reaches an FFI call skips, with a reason (PBT-EVAL-PARITY-1).
10. `compiler/src/LLMLL/TrustReport.hs`, `ffiNote`: the row text already says "deterministic within one run … total, and with no hidden effects".

No in-flight draft on this topic exists. This record is new.

**Drift found while reading.**

- **DR1.** `LLMLL.md` §7, reach table, row `bytestring`, names `BYTES-READ-1` as the blocker. The blocker is `BYTES-UNSIZED-1`, and the row that lifts it is `FFI-BYTES-1`. Route: documentation-lead, at the `FFI-BYTES-1` ship.
- **DR2.** `LLMLL.md` §7 and §10 say the generated modules compile under `{-# LANGUAGE Safe #-}`. `compiler/src/LLMLL/CodegenHs.hs` emits no `Safe` pragma. This drift is already filed as `SAFE-HASKELL-CLAIM-1`. It bears on this record: the kernel binding below uses `unsafePerformIO`. If that row moves toward emitting `Safe`, the kernel bindings must live in a separate `Trustworthy` module.

## Design proposal

### Summary of the recommended design

| Part | Recommendation |
|---|---|
| 1. Type | The boundary type is `bytes` from `BYTES-UNSIZED-1`. No new type. Length is the `bytesLen` measure. `bytes[n]` stays refused in an FFI result. |
| 2. Tier 1 | Ship `FFI-BYTES-1` as settled. It does **not** unblock the use case. No Tier 1 export does pixel work, and D5 closes the package set. |
| 3. Kernel convention | Tier 2 returns as one import form: a `c.*` import with a `kernels` list and a named C source file. Each kernel is a pure function from `bytes` and `int` arguments to one `bytes` or one `int` result. |
| 4. Ownership | The Haskell runtime allocates every buffer. C reads inputs through a const pointer, writes one fresh output buffer, and keeps no pointer after it returns. No buffer is mutable from LLMLL. |
| 5. Length | A `bytes` result has a mandatory `out-len` clause: a linear term over the `int` arguments and the argument lengths. The binding allocates exactly that many bytes. The caller gets `bytesLen(result) = out-len` as a codegen-determined fact. |
| 6. Preconditions | A kernel may carry `pre` clauses in QF-LIA. The binding checks them at run time before the call. The verifier proves them at each call site with a body VC. |
| 7. Verification | A kernel call reflects as a fresh term with the length fact. The term is abstracted under `ABSTRACTION-VERDICT-1`, so UNSAFE gives the fallback outcome, not `refuted`. |
| 8. Trust | One `ffi_assumptions` row per kernel, with `package: "c.<lib>"`, the C symbol, the source path and its SHA-256. The row text adds memory safety and the buffer rules to the D9 assumption. |
| 9. Order | `BYTES-UNSIZED-1` (BYTE-IO step 3), then `FFI-BYTES-1`, then `FFI-KERNEL-1`. `FFI-KERNEL-1` answers and absorbs `FFI-TIER2-1`. |

### Part 1 — The unsized byte type at the boundary

**Decision.** The boundary uses `bytes` as `BYTES-UNSIZED-1` defines it. It lowers to strict `Data.ByteString.ByteString`. This record adds no type and no type kind.

**Why `bytes` serves a native boundary.** Three properties of strict `ByteString` matter here.

1. Its payload is pinned memory. The garbage collector does not move it. So a pointer to it stays valid during a foreign call, including a `safe` call, during which the collector can run.
2. `Data.ByteString.Unsafe.unsafeUseAsCStringLen` gives a pointer and a length with no copy. A `bytes-slice` result is an offset view, and the pointer accounts for the offset.
3. `Data.ByteString.Internal.create` allocates a pinned buffer of a given size and gives its pointer to an `IO` action. The result is an ordinary immutable `ByteString` with no copy.

So a frame crosses the boundary in both directions with no copy. The only per-call cost is the output allocation and its zero fill (Part 3).

**Why not `bytes[n]`.** `bytes[n]` lowers to `[Word8]`, a linked list. A 6 MB frame as `[Word8]` is a list of six million cells. Its conversion to a C pointer is O(n) with a large constant. `bytes[n]` stays valid in a Tier 1 argument (D3). In a kernel argument it is refused with `ffi-type-unsupported`, and the message tells the author to call `bytes-widen`.

**Length as a refinement fact.** The verifier already has the measure `bytesLen` over `byteArraySort`, with `bytesLen(v) ≥ 0` (`LLMLL.md` §5.3.3). Part 4 of `BYTES-UNSIZED-1` reflects `bytes-length` as `bytesLen(b)` and gives `bytes-slice` the fact `bytesLen(r) = e − s`. This record adds one more source of a length fact: the `out-len` clause of a kernel (Part 4 below). It adds no new symbol and no new sort.

**`bytes[n]` in an FFI result stays refused.** The D3 reason still holds: nothing checks a Haskell-returned `[Word8]` against `n`. A kernel could carry `bytes[n]` as its result type, because the binding allocates exactly `n` bytes. This record does not propose it, because `bytes` with `out-len` covers the same case and keeps one result type. `BYTES-NARROW-1` stays parked.

### Part 2 — Tier 1 first (`FFI-BYTES-1`)

**Decision.** Ship `FFI-BYTES-1` as BYTE-IO settled it, as step 4, after `BYTES-UNSIZED-1`. `bytes` is valid in Tier 1 parameters and results. Its converter is `id`, and its forcer is WHNF, which forces a strict `ByteString` in full. This record adds one sentence to the row: a `bytes` result from a Tier 1 export carries no length fact. The caller gets a length only from `bytes-length` at run time, or from `FFI-CONTRACT-1` when that row ships.

**Do Tier 1 bytes alone unblock the use case? No.** The reasons are measured against the reach table and the type rules, not against a program.

1. **No Tier 1 export does pixel work.** The settled reach in `Data.ByteString` is `reverse`, `append`, `isPrefixOf`, `isSuffixOf`, `isInfixOf`, `null` and `length` through `hs-int`. The exports that transform bytes (`map`, `zipWith`, `foldl'`) take a `Word8` callback, and no boundary type exists for `Word8`. `Data.Vector` needs `FFI-OPAQUE-1`, and its unboxed and storable variants are not in the D5 module set.
2. **D5 closes the package set.** A program cannot import its own Haskell module or a Hackage package such as `JuicyPixels` or `vector`'s storable interface. Opening D5 is a larger decision than this record. It also brings the `FFI-DETERM-GATE-1` review for every new export.
3. **A per-byte callback is the wrong cost model.** Even with a `Word8` boundary type, `BS.map f` calls an LLMLL closure six million times per frame. The closure works on `Integer`, and every byte goes through `toInteger` and `fromInteger`.
4. **An LLMLL-native pixel loop is the wrong cost model too.** `bytes-set` copies, so a loop of `bytes-set` is O(n²) (BYTE-IO risk 9). The settled idiom, a `list[int]` and one `bytes-from-list`, holds one boxed `Integer` per byte. For a 1080p RGB frame (6,220,800 bytes) that is an estimated few hundred MB of heap per frame. This figure is an estimate and is not measured.

So Tier 1 bytes are a prerequisite and a small, separate release. The use case needs a native kernel, and that is Tier 2.

**Alternative considered: a developer-owned Haskell kernel.** A third tier could import a developer-written Haskell module with a pure `ByteString -> ByteString` function. It needs no C ABI. It is filed as `FFI-KERNEL-HS-1` in the parking lot, for two reasons. First, it reopens D5 by a back door: such a module can import any package and call `unsafePerformIO`. Second, its trust text would be the same as a C kernel's, so it adds a second path with no new guarantee. The kernel convention below is written so that this tier can reuse it later with no surface change.

### Part 3 — The kernel convention (`FFI-KERNEL-1`)

**Scope.** Tier 2 returns as one import form only. A `c.*` import with an `interface` list stays refused with `ffi-tier2-refused`. A `c.*` import with a `kernels` list and a `source` clause is accepted. A direct call to an arbitrary C ABI, such as `abs` from the C standard library, is not supported. The author writes a short shim in the kernel source instead.

**Surface (S-expression).**

```lisp
(import c.pix
  (source "cbits/pix.c")
  (kernels [
    [rgb-to-gray
      (symbol "pix_rgb_to_gray")
      (fn [src: bytes npix: int] -> bytes)
      (pre (= (bytes-length src) (* 3 npix)))
      (out-len npix)]
    [sad
      (symbol "pix_sad")
      (fn [a: bytes b: bytes] -> int)
      (pre (= (bytes-length a) (bytes-length b)))]]))
```

- `source` names one C file, relative to the program's directory. `build` copies it into the generated project and lists it under `c-sources` in `package.yaml`. More than one file per import is not in v1.
- `symbol` is the C symbol. It is mandatory. The LLMLL name follows the Tier 1 name rule (D2, D6). This is part 2 of `FFI-TIER2-1`.
- The type is `fn [p1: T1 … pk: Tk] -> R`. Each `Ti` is `bytes` or `int`. `R` is `bytes` or `int`. Every other type is `ffi-type-unsupported`. `Command` and `Promise` are `ffi-effect-refused` (part 4 of `FFI-TIER2-1`).
- `pre` is zero or more clauses in the kernel predicate vocabulary (below).
- `out-len` is mandatory when `R` is `bytes` and refused when `R` is `int`.

**Kernel predicate vocabulary.** A `pre` clause and the `out-len` term may use: the `int` parameters; `(bytes-length p)` for a `bytes` parameter `p`; integer literals; `+`, `-`; `*` with at least one literal operand; `=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`. Nothing else is accepted, and the diagnostic is `ffi-kernel-term-unsupported`. Every term in this vocabulary is linear, so every obligation is QF-LIA. The vocabulary is evaluable at run time in O(1), because `BS.length` is O(1).

**Surface (JSON-AST).** The `import` node gains two optional keys. `source` is a string. `kernels` is an array of objects with the required keys `name`, `symbol`, `type`, and the optional keys `pre` (an array of expressions) and `out_len` (an expression). An import node with `kernels` must also have `source`, and must not have `interface`. `ParserJSON` checks both rules. The schema version changes by one minor step. It shares the change with any other schema change in the same release.

**The C ABI.** The generated stub declares one C prototype per kernel. Arguments appear in declared order. A `bytes` parameter becomes two C arguments. An `int` parameter becomes one. The output comes last.

| LLMLL | C | Rule |
|---|---|---|
| `bytes` parameter `p` | `const uint8_t *p, size_t p_len` | `p` may be `NULL` when `p_len` is 0. C reads at most `p_len` bytes. C never writes through `p`. |
| `int` parameter `x` | `int64_t x` | The binding checks `-2^63 ≤ x < 2^63` (below). |
| `bytes` result | `uint8_t *out, size_t out_len` | `out_len` is the value of the `out-len` term. The buffer is zero-filled before the call. C writes at most `out_len` bytes. |
| `int` result | `int64_t *out` | C writes one value. |
| return value | `int32_t` | 0 is success. Any other value is a kernel failure. |

The `rgb-to-gray` entry above gives this prototype:

```c
int32_t pix_rgb_to_gray(const uint8_t *src, size_t src_len,
                        int64_t npix,
                        uint8_t *out, size_t out_len);
```

**The generated binding.** The binding is a pure Haskell function. Its shape is illustrative. The engineer chooses the code.

```haskell
rgb_to_gray :: BS.ByteString -> Integer -> BS.ByteString
rgb_to_gray src npix
  | not (inI64 npix)                         = llmll_kernel_fail "c.pix" "rgb-to-gray" "int argument npix outside int64"
  | not (toInteger (BS.length src) == 3 * npix) = llmll_kernel_fail "c.pix" "rgb-to-gray" "pre"
  | n < 0                                    = llmll_kernel_fail "c.pix" "rgb-to-gray" "out-len < 0"
  | otherwise = unsafePerformIO $
      BSU.unsafeUseAsCStringLen src $ \(p, pl) ->
        BSI.create (fromInteger n) $ \o -> do
          fillBytes o 0 (fromInteger n)
          st <- c_pix_rgb_to_gray (castPtr p) (fromIntegral pl) (fromInteger npix) o (fromInteger n)
          when (st /= 0) (llmll_kernel_status "c.pix" "rgb-to-gray" st)
  where n = npix
foreign import ccall safe "pix_rgb_to_gray" c_pix_rgb_to_gray
  :: Ptr Word8 -> CSize -> Int64 -> Ptr Word8 -> CSize -> IO Int32
```

Five rules fix the binding's behaviour. The engineer may change the code but not these rules.

1. **Check order.** The binding checks the `int64` range of each `int` argument, then each `pre` clause in order, then `out-len ≥ 0`. The first failed check stops the program with exit 1 and a message that names the import, the kernel and the clause. The C function is not called.
2. **The output is zero-filled.** The binding fills the output with zeros before the call. So bytes that the kernel does not write are 0, not uninitialized memory. This makes the output a function of the inputs even for a kernel that skips bytes.
3. **`safe` foreign call.** The call is `safe`, so the garbage collector and other threads can run during a long kernel. All buffers are pinned, so this is correct. An `unsafe` option is not in v1.
4. **A nonzero status stops the program.** The status is reported with exit 1, as a failed runtime `pre` assertion is. The kernel result is not a `Result`. A kernel that can fail on valid input must state the condition as a `pre`. A `Result`-returning kernel is not in v1, because `admissiblePayload` admits no array payload, so its length fact would be lost (BYTE-IO Part 4, note on `bytes-from-list`).
5. **Forcing.** The result is forced in full when it is first demanded, as D1 requires. For a strict `ByteString` and for an `int`, WHNF is full evaluation.

**Ownership and lifetime.**

| Question | Rule |
|---|---|
| Who allocates an input buffer? | The Haskell runtime, earlier, as an ordinary `bytes` value. |
| Who allocates the output buffer? | The binding, once per call, with exactly `out_len` bytes. |
| Can C write into an input? | No. The pointer is `const`, and the row text states the rule. C can break it with a cast. That is a trust failure, not a type error (edge case 9). |
| Can the output alias an input? | No. The output is a fresh allocation. |
| How long is a pointer valid? | From the start of the C call to its return. C must not keep any pointer after it returns. |
| Who frees? | The garbage collector frees every buffer. C frees nothing it did not allocate. |
| May C allocate? | Yes, for scratch memory that it frees before it returns. The row text requires no leak to be observable, which "no hidden effects" covers. |

**Strict immutability holds.** No LLMLL value changes after it exists. The output buffer is written only inside `create`, before any LLMLL code can see the value. That is the same pattern `bytes-set` uses, which copies into a fresh buffer. The inputs are read-only by contract. The contract is not enforced by the type system, and the trust report says so.

**Why not an explicit output-buffer convention.** A caller-supplied output buffer (`(blur src dst)`, where C writes into `dst`) avoids one allocation per frame. It is mutation of an LLMLL value, so it breaks strict immutability unless `dst` is used linearly. LLMLL has no linear types. So v1 allocates per call. The cost is one pinned allocation and one `memset` per frame. GHC allocates a large pinned object directly with the OS allocator, and a `memset` of a 25 MB 4K RGB frame takes a few milliseconds. Both figures are estimates and are not measured. Buffer reuse is filed as `FFI-KERNEL-REUSE-1` in the parking lot, with a trigger: a measured pipeline in which allocation is more than 10% of frame time.

### Part 4 — Verification

**The kernel call reflects.** Today a direct FFI call in a VC makes the caller fall back (`docs/design/ffi-determinism-proposal.md` Part 3, R4). A kernel call does not. It reflects as a fresh term with the facts below. This is the same treatment as the partial reflections of BYTE-IO Part 4.

| Application | Fresh term | Facts the caller may assume | Category |
|---|---|---|---|
| `(k a1 … ak)`, `R = bytes` | `r : byteArraySort` | `bytesLen(r) = ⟦out-len⟧` with each parameter replaced by its argument | codegen-determined |
| `(k a1 … ak)`, `R = int` | `r : int` | none | — |

The fact is true of every value the binding returns, because the binding allocates exactly that many bytes. So it is codegen-determined, in the same category as the `bytes-zero` length axiom (`LLMLL.md` §13.12). It is not an assumption about the C code. It rides `codegen_semantics_version`.

**Each kernel call is abstracted.** A kernel call joins clause 1 of the abstracted-term definition (`docs/design/byte-io-proposal.md` Part 0). Its fresh term carries true but incomplete facts. So an UNSAFE constraint that holds it reports the fallback outcome with cause `abstraction:app:<kernel>`, not `refuted`. A SAFE constraint reports `verified`. The closed sealed-builtin axiom set grows by one schema, "the output length of a kernel", and not by one item per kernel.

**The `pre` is a PROVE obligation at each call.** The `pre` clauses, the `int64` range of each `int` argument, and `out-len ≥ 0` form the kernel's effective precondition. At a call inside a function with a body VC, §5.3.4's call rule proves it under PROVE polarity. At a call from a function with no body VC, the existing `call-pre unchecked: <caller> -> <kernel>` line names the edge, and the runtime check stays. The runtime check is never removed, even when the call site is proved, because C memory safety must not depend on a verdict.

**Which functions may call a kernel.** A `def-shell` may call a kernel. A `def` that calls a kernel stays `core-membership-violation`, as for Tier 1 (`LLMLL.md` §7, "Tier 1 effects"). Admission to `def` is the `FFI-UNINTERP-1` decision. This record anticipates it: a kernel is already an uninterpreted symbol with a disclosed assumption, so `FFI-UNINTERP-1` can admit kernels with no new rule. The motivating shape still works without it. The core is a set of `def`s over offsets, lengths and slices. A thin `def-shell` calls the kernel and passes the result back to the core (worked example).

**Congruence (`CALL-CONGRUENCE-1`, R2).** Two calls to one kernel in one constraint get an Ackermann hypothesis only when R2 holds for every argument sort and the result sort.

- **`int` arguments and an `int` result.** R2 holds. The hypothesis is emitted.
- **A `bytes` argument and an `int` result.** The premise `a_i = a_j` is array equality in the model. Model array equality implies equal contents on `[0, bytesLen)` and, by congruence of `bytesLen`, equal lengths. So it implies run-time equality. A premise that is stronger than run-time equality keeps the hypothesis sound. The conclusion is over `int`, where R2 holds. **The hypothesis is emitted.** In practice it fires when both calls take the same binder, which is the common case.
- **A `bytes` result.** The conclusion `r_i = r_j` asserts model array equality. Equal run-time results can have model arrays that differ outside `[0, bytesLen)`, and the encoding never reflects whole-array `=` (`wholeArrEqClause`). **No hypothesis is emitted in v1.** The pair stays abstracted under clause 2, so the verdict is never a false `refuted`. Professor question 1 asks whether the hypothesis is sound here.

**What the caller may not assume.** Nothing about the content of a `bytes` result. Nothing about the value of an `int` result. A content or value `post` on a kernel would be an assumption about the C code. It would rest only on the `ffi_assumptions` row. That is `FFI-CONTRACT-1` territory, and for kernels it is filed as `FFI-KERNEL-POST-1` in the parking lot.

**Testing evidence.** The property runner interprets the program, so a `check` or `for-all` that reaches a kernel skips (PBT-EVAL-PARITY-1). A function that calls a kernel gets no `tested` evidence from properties. Its evidence is `verified` (its post proved with the length fact) or `asserted`. This is a stated limit, not a defect.

### Part 5 — The trust report

**Row.** Every verdict that rests on a kernel carries one `ffi_assumptions` row per kernel, through the existing D9 mechanism (`markFfiAssumptions`, the cross-module map, the obligation-report `trust_channel` projection). The row keys are the D9 keys plus three additive keys.

| Key | Value |
|---|---|
| `origin` | as D9 |
| `package` | `"c.<lib>"`, for example `"c.pix"` |
| `export` | the C symbol, for example `"pix_rgb_to_gray"` |
| `kind` | `"c-kernel"` (new; a Tier 1 row omits it) |
| `source` | the `source` path as written |
| `source_sha256` | the SHA-256 of the C file at `verify` time |

The hash ties the verdict to the C code it assumed. A later change to the C file does not change the LLMLL verdict hash. A reader compares the two hashes to find that the assumption was made about other code.

**Row text.** The text report prints this line for a kernel row:

```text
≈ assumes c.pix kernel pix_rgb_to_gray (cbits/pix.c, sha256 <first 12 hex>) (ASSUMED, not proved: native code, taken as deterministic within one run (equal arguments give equal results), memory-safe (it reads at most the passed length of each input and writes at most out_len bytes of the output), it does not write an input, it keeps no pointer after it returns, it returns status 0 on every input that meets its pre, and it has no hidden effects)
```

This text is the strengthening that the determinism record requires for C (professor H9, Part 7 item 5). It is stronger than the Tier 1 text in four named clauses.

**Trust level.** The level does not change, as D9 decides for Tier 1. `evidenceMeet` and the TRUST-LEVEL-FLOOR-1 floors keep their meaning. A function whose post is proved with the kernel length fact is `verified`, with the row. The row is the disclosure. `--strict-verified-core` does not apply, because a kernel caller is a `def-shell`.

**The codegen-determined fact.** The length fact is listed once in the closed axiom set, as the schema "kernel output length". The trust report shows it under `codegen-determined` for each function whose VC uses it, as it shows the `bytes-zero` axiom.

**Effect summary.** A function that calls a kernel keeps `"unbounded"` in `effect_summary`, as every `c.*` callee does today (`LLMLL.md` §9). The summary is a sound over-approximation, and native code can reach any capability. The purity in the row text is an assumption, so the summary does not use it.

**Determinism gate.** `FFI-DETERM-GATE-1` reviews Tier 1 exports by name. A kernel is developer code, so no denylist applies. The row text carries the whole assumption.

### Part 6 — Staging and the rows

**Recommended order.**

| Step | Rows | Content | Depends on |
|---|---|---|---|
| A | `BYTES-UNSIZED-1`, `BYTES-READ-1`, `BYTES-WRITE-1` | BYTE-IO step 3, unchanged. | `ABSTRACTION-VERDICT-1` (shipped). Step 1 is not a dependency of step 3 for this use case. |
| B | `FFI-BYTES-1` | BYTE-IO step 4, with the one added sentence of Part 2. | A |
| C | `FFI-KERNEL-1` | Parts 3–5 of this record. Lifts `ffi-tier2-refused` for a `c.*` import with `kernels`. Answers and closes `FFI-TIER2-1`. | A. B is not a strict dependency, but B is smaller and should ship first. |
| — | `BYTES-READ-RANGE-1` | A ranged file read. Needed before a real video file, which is too large to read whole. Not designed here. | A |

**`FFI-KERNEL-1` relative to `FFI-TIER2-1`.** `FFI-TIER2-1` asks whether to build Tier 2, and lists six scalar parts. This record answers: build Tier 2 as the kernel convention, not as a general C type mapping. Each of the six parts has an answer.

| `FFI-TIER2-1` part | Answer in this record |
|---|---|
| 1. Type mapping | `bytes` to a pointer and a length; `int` to `int64_t` with a run-time range check; nothing else. |
| 2. Symbol names | The mandatory `symbol` clause. |
| 3. Reach (`import FFI`) | The generated stub module and its `foreign import`, imported by `Lib.hs`. |
| 4. D4 for `c.*` | `ffi-effect-refused` for `Command` or `Promise` in a kernel type. |
| 5. D9 for `c.*` | Part 5: the row, its three new keys and its text. |
| 6. Fixtures | W-C and W8 are rewritten as kernels with a C shim, because a direct call to `abs` is not supported. The new fixtures are in "Affected surface". |

**Effect on each existing row.**

| Row | Effect |
|---|---|
| `FFI-TIER2-1` | **Closed by `FFI-KERNEL-1`** when it ships. The DECIDE is answered now, on settlement of this record. |
| `FFI-TIER2-REFUSE-1` (closed, v0.34.1) | **Amended in effect.** The refusal stays for every `c.*` import without `kernels`. The `LLMLL.md` §7 text changes at the `FFI-KERNEL-1` ship. |
| `FFI-BYTES-1` | **Amended text.** One sentence: a Tier 1 `bytes` result carries no length fact. It does not unblock native work. |
| `BYTES-UNSIZED-1` | Unchanged. It gains a dependent. |
| `FFI-NARROW-1` | **Answered for kernels only.** A kernel `int` argument has a range `pre` that is proved at call sites with a body VC and checked at run time always. The Tier 1 question stays open. This answer is evidence for the first of its two shapes. |
| `FFI-CONTRACT-1` | **Answered for kernels only, `pre` half.** A kernel may carry `pre`. The `post` half stays open, and for kernels it is `FFI-KERNEL-POST-1`. |
| `FFI-UNINTERP-1` | Unchanged. Anticipated: a kernel is admissible under its rule with no new rule. |
| `FFI-DETERM-GATE-1` | Unchanged. It does not apply to developer code. |
| `CALL-CONGRUENCE-1` (closed, v0.35.0) | No change to the rules. The R2 instances gain "a `bytes` argument with an `int` result". |
| `BYTES-SLICE-CONTENT-1` | Unchanged. A kernel gives no content facts either. |
| `SAFE-HASKELL-CLAIM-1` | Gains a note: the kernel binding uses `unsafePerformIO` and must stay out of a `Safe` module. |

## Worked example

A raw RGB video file has a header of `hdr` bytes, then frames of `3 * npix` bytes each. The core computes the offset of a frame and slices it. The shell calls the kernel.

```lisp
;; core: the frame at offset off, proved in bounds
(def frame-at [file: bytes off: int len: int] -> bytes
  (pre (and (>= off 0) (>= len 0) (<= (+ off len) (bytes-length file))))
  (post (= (bytes-length result) len))
  (bytes-slice file off (+ off len)))

;; shell: one gray frame
(def-shell gray-frame [file: bytes off: int npix: int] -> bytes
  (pre (and (>= off 0) (>= npix 0) (< npix 1000000000)
            (<= (+ off (* 3 npix)) (bytes-length file))))
  (post (= (bytes-length result) npix))
  (rgb-to-gray (frame-at file off (* 3 npix)) npix))
```

**Expected verdicts after step C.** These are derived from the rules, not measured, because nothing in step A to C exists yet.

- `frame-at` is `verified`. The `bytes-slice` pre is proved from the `pre`. The post follows from the slice length fact `bytesLen(r) = e − s`.
- `gray-frame` is `verified`, with one `c.pix` row. The `frame-at` pre is proved from the shell `pre`. The `frame-at` post gives `bytesLen = 3 · npix`, so the kernel `pre` holds. The `int64` range `pre` on `npix` follows from the bound `npix < 10^9` in the shell `pre`. Without that bound the range is not provable, because `bytesLen(file)` has no upper bound in the model (edge case 3). The post follows from the kernel length fact `bytesLen(r) = npix`.

The frame size `w · h · 3` is a product of two variables, so it is not QF-LIA. The core keeps `npix` as one `int`. The relation `npix = w · h` is checked once, where the header is parsed, with an `assert`-style runtime check, or it is left out of the contract.

## Edge cases and degenerate inputs

1. **A `pre` violation, positive witness.** Input: `(rgb-to-gray s 100)` where `s` has 299 bytes. Behaviour: in a caller with a body VC, the PROVE obligation `bytesLen(s) = 300` fails, and the caller is `refuted` if the term is not abstracted, else the fallback outcome. At run time the binding stops with exit 1 and the message `c.pix rgb-to-gray: pre (= (bytes-length src) (* 3 npix)) failed`. C is not called. Channel: contract, then run time. Citation: Part 4; binding rule 1.
2. **`out-len` is negative.** Input: a kernel with `(out-len (- n 1))` called with `n = 0`. Behaviour: `out-len ≥ 0` is part of the effective `pre`. It is a PROVE obligation at the call and a run-time check. Channel: contract. Citation: binding rule 1.
3. **An `int` argument outside `int64`.** Input: `(rgb-to-gray s (* 4 4611686018427387904))`. Behaviour: the range check fails at run time. A body VC proves the range only if bounds are known. A `bytesLen` value has no upper bound in the model, so the length of a real frame does not give one. The author states `(< npix 1000000000)` or similar in the caller's `pre`. Channel: contract, then run time. Citation: Part 3, the ABI table. This is the `FFI-NARROW-1` shape.
4. **A zero-length input.** Input: `(sad empty empty)`. Behaviour: C receives a pointer that may be `NULL` with length 0. The ABI table states this. A kernel that dereferences it fails the memory-safety clause of its row. Channel: trust. Citation: Part 3.
5. **A zero-length output.** Input: `(rgb-to-gray empty 0)`. Behaviour: the binding allocates 0 bytes and calls C with `out_len = 0`. The result is the empty `bytes`, and `bytesLen(r) = 0` holds. Channel: spec is silent on the pointer value (intentional; C must not dereference it).
6. **The kernel skips some output bytes.** Input: a kernel that writes only even indices. Behaviour: the odd bytes are 0, because the binding zero-fills. The output is a function of the inputs. Channel: run time (rule 2). Citation: Part 3.
7. **Nonzero status.** Input: a kernel that returns 3. Behaviour: the program stops with exit 1 and `c.pix rgb-to-gray: status 3`. Partial correctness holds: no LLMLL code runs after the failure. The row text says status 0 on every input that meets the `pre`, so a nonzero status is a trust failure. Channel: trust. Citation: binding rule 4.
8. **Two calls with the same arguments.** Input: `(+ (sad a b) (sad a b))` under post `(= result (* 2 (sad a b)))`. Behaviour: R2 holds (`bytes` arguments, `int` result), so the Ackermann hypothesis is emitted and the post can verify. For `rgb-to-gray` twice with a post on equality of the two results, no hypothesis is emitted. The post is not proved, and the outcome is fallback, not `refuted`. Channel: contract (congruence), then the verdict rule. Citation: Part 4.
9. **C writes an input or keeps a pointer.** Input: a kernel that casts away `const` and writes `src[0]`. Behaviour: undefined. Another LLMLL value that shares the buffer (a slice) can change. No channel catches it. Channel: trust. The row text names both rules.
10. **The same buffer passed twice.** Input: `(sad a a)`. Behaviour: both pointers address the same memory. Both are read-only, so no conflict exists. Channel: spec is silent (intentional).
11. **A slice as input.** Input: `(rgb-to-gray (bytes-slice file 100 400) 100)`. Behaviour: the pointer is the slice start, and `src_len` is 300. No copy happens. C must not read before the pointer. Channel: trust (memory safety). Citation: Part 1.
12. **`bytes[n]` as a kernel argument.** Input: `(fn [k: bytes[32]] -> bytes)`. Behaviour: `ffi-type-unsupported`, with the advice to declare `bytes` and call `bytes-widen`. Channel: type. Citation: Part 1.
13. **A nonlinear `out-len`.** Input: `(out-len (* w h))`. Behaviour: `ffi-kernel-term-unsupported`, because neither operand is a literal. Channel: type (the `check` vocabulary rule). Citation: Part 3.
14. **A changed C file after `verify`.** Input: edit `pix.c`, then `build` without `verify`. Behaviour: the old trust report keeps the old `source_sha256`. The verdict does not change, because it does not depend on the C content. A reader detects the change by the hash. Channel: trust (disclosure). Citation: Part 5.
15. **A kernel called from a `def`.** Behaviour: `core-membership-violation`, as for Tier 1. Channel: type (core membership). Citation: Part 4.

## Verification mapping

| Obligation | Channel | Fragment | Where it is emitted |
|---|---|---|---|
| Kernel `pre` at a call site | contract (PROVE) | QF-LIA: the vocabulary is linear by construction | the call rule of `LLMLL.md` §5.3.4; `compiler/src/LLMLL/FixpointEmit.hs`, with the kernel's effective `pre` in the contract environment |
| `int64` range of each `int` argument | contract (PROVE) | QF-LIA with literal bounds | the same |
| `out-len ≥ 0` | contract (PROVE) | QF-LIA | the same |
| `bytesLen(r) = out-len` | assumed post, codegen-determined | QF-LIA, over the existing `bytesLen` UF | the kernel reflection; disclosed in the closed axiom set (`LLMLL.md` §13.12) |
| Ackermann hypothesis, `bytes` arguments and `int` result | contract (assumed hypothesis) | QF-LIA plus array equality in the premise only | `CALL-CONGRUENCE-1` R1–R3 |
| Determinism, memory safety, no write to inputs, no retained pointer, status 0 | trust | not a solver obligation | the `ffi_assumptions` row |

No obligation goes to Lean. Nothing in this record is nonlinear. The one nonlinear relation of the use case, `npix = w · h`, stays in the program, outside the kernel vocabulary (`LLMLL.md` §5.3.3, the `Σ_auto` boundary: constant multipliers only).

## Soundness argument for the addition

`FFI-KERNEL-1` is an addition: a new import form and a new trusted path. Six points carry the argument.

1. **Strict immutability.** No LLMLL value changes after it exists. The output is written inside `create`, before it is a value. Inputs are read-only by contract, and the contract is disclosed per verdict.
2. **Memory-safety preconditions are checked, not assumed.** Every length relation that C needs is a `pre` in QF-LIA, proved where possible and checked at run time always. The remaining memory-safety claim is about the C code only, and the row names it.
3. **The length fact is earned by codegen.** `bytesLen(r) = out-len` holds because the binding allocates exactly `out-len` bytes. It joins the closed axiom set as one schema.
4. **The verifier does not over-claim.** A kernel call is an abstracted term, so an UNSAFE answer is never reported as `refuted` because of it. Congruence is emitted only where R2 holds.
5. **Logic functions do not see IO.** A kernel has a pure type. Its failures stop the program, as a failed runtime `pre` does. No exception reaches LLMLL code as a value.
6. **The assumption is visible.** Every verdict that rests on a kernel carries a row with the C symbol, the source path and its hash. The effect summary stays `unbounded`.

## Affected surface

- `compiler/src/LLMLL/Ffi.hs`: `ffiImportErrors` accepts a `c.*` import with `kernels` and `source`, and keeps `ffi-tier2-refused` for every other `c.*` import. A new check validates kernel types, the predicate vocabulary and the `out-len` rule.
- `compiler/src/LLMLL/Syntax.hs`, `compiler/src/LLMLL/Parser.hs`, `compiler/src/LLMLL/ParserJSON.hs`: the import node gains `source` and `kernels`.
- `compiler/src/LLMLL/CodegenHs.hs`: `emitFfiStub` and `emitFfiDecl` are replaced by the kernel binding and the `foreign import`. `package.yaml` gains `c-sources`. The preamble gains `llmll_kernel_fail` and `llmll_kernel_status`.
- `compiler/src/LLMLL/TypeCheck.hs`: kernels enter the environment with their LLMLL types; a `def` call stays `core-membership-violation`.
- `compiler/src/LLMLL/FixpointEmit.hs`: the kernel reflection, the effective `pre`, the length fact, the clause-1 abstraction mark, and the R2 instance for `bytes` arguments with an `int` result.
- `compiler/src/LLMLL/TrustReport.hs`: the row keys `kind`, `source`, `source_sha256`, and the kernel row text. `docs/llmll-trust-report.schema.json`: the three additive keys.
- `docs/llmll-ast.schema.json`: `source` and `kernels` on the import node; one minor schema version change.
- `LLMLL.md` §7 (Tier 2 row and a new "Kernels" subsection), §13.12 (the axiom-set schema), §5.3.3 (the kernel reflection). Documentation-lead, after the ship.
- Fixtures: the worked example with a C kernel, built and run; the positive witness of edge case 1, at `verify` and at run time; edge cases 6, 7, 8, 12 and 13; W-C and W8 rewritten as kernels; a `c.*` import with `interface` still refused.

## Risks

1. **The assumption is large and unchecked.** Classification: soundness (trusted base). Citation: Part 5. Bite: limits the claim, does not block. C can break every clause of the row text. The design keeps the C-side claim to one row and moves every length relation into checked `pre`s. A debug mode that hashes each input before and after the call would detect writes to inputs. It is not proposed for v1.
2. **The whole-file read does not fit video.** Classification: scope. Citation: BYTE-IO risk 8. Bite: blocks a real video file, not the design. `wasi.fs.read-bytes` reads a whole file. A container of several GB needs a ranged read. `BYTES-READ-RANGE-1` is proposed and not designed here.
3. **Per-call allocation and zero fill.** Classification: verification ergonomics (cost). Bite: only matters at scale. The costs in Part 3 are estimates. The engineer measures them on a 4K frame before the ship. `FFI-KERNEL-REUSE-1` holds the remedy.
4. **No `tested` evidence for kernel callers.** Classification: verification ergonomics. Citation: `compiler/src/LLMLL/PBT.hs`. Bite: complicates. Properties skip at a kernel call. Running properties against the built binary is a separate, larger change.
5. **A C toolchain at build.** Classification: scope. Bite: complicates CI and `getting-started`. GHC brings a C compiler through its toolchain, so `stack build` compiles `c-sources`. The engineer confirms this on the pinned resolver and in the Docker image.
6. **`SAFE-HASKELL-CLAIM-1` interaction.** Classification: spec drift. Citation: DR2. Bite: only matters if that row moves toward emitting `Safe`.

## Proposed roadmap rows

These tags are proposals. This record does not edit the roadmap.

| Tag | Group | Next action on settlement | Content |
|---|---|---|---|
| `FFI-KERNEL-1` | G7 | PLAN | Parts 3–5. Depends on `BYTES-UNSIZED-1`. Answers and, at ship, closes `FFI-TIER2-1`. |
| `BYTES-READ-RANGE-1` | G4 | DECIDE | A read of `len` bytes at offset `off` of a file, as `RBytes`. Trigger: the first program over a file larger than memory. |
| `FFI-KERNEL-REUSE-1` | Parking lot | — | Output-buffer reuse across calls. Needs a linearity discipline. Trigger: allocation above 10% of frame time, measured. |
| `FFI-KERNEL-HS-1` | Parking lot | — | A developer-owned Haskell kernel with the same convention. Trigger: a kernel that is simpler in Haskell than in C. |
| `FFI-KERNEL-POST-1` | Parking lot | — | Content or value `post`s on a kernel, assumed under the row. Trigger: a caller post that needs a kernel fact other than length. |

## Findings routed to other owners

| Finding | Owner | What moves |
|---|---|---|
| DR1: the §7 reach row names `BYTES-READ-1` | documentation-lead | Name `BYTES-UNSIZED-1` and `FFI-BYTES-1`, at the `FFI-BYTES-1` ship. |
| DR2: `Safe` is claimed and not emitted | documentation-lead (`SAFE-HASKELL-CLAIM-1`) | Add the kernel note to the row. |
| `FFI-BYTES-1` gains one sentence | documentation-lead | Part 2. |
| `FFI-TIER2-1` is answered | documentation-lead | DECIDE answered on settlement; closed at the `FFI-KERNEL-1` ship. |

## Open questions for the user

1. **Mandatory zero fill.** The zero fill makes a kernel that skips bytes deterministic. It costs one `memset` per call. Keep it mandatory, as proposed, or allow an entry to opt out?
2. **Tier 2 scope.** This record supports kernels only and keeps a direct call to an arbitrary C ABI refused. Confirm that `FFI-TIER2-1` closes on that scope.

## Open questions for the professor

1. **Congruence over an array-sorted result.** The model of `bytes` is an array plus the measure `bytesLen`, and the array is unconstrained outside `[0, bytesLen)`. Two equal run-time results can have model arrays that differ there. Is the Ackermann hypothesis `(a_i = a_j) ⇒ (r_i = r_j)` sound when `r` has this sort? A candidate argument: every model of the other constraints can be changed to make `r_i` and `r_j` agree outside the range, because no emitted fact reads outside it. The answer decides whether Part 4 emits the hypothesis for a `bytes` result.
2. **A checked boundary precondition with an assumed callee.** The kernel `pre` is proved at call sites and also checked at run time, and the callee is unverified C. Is there an established treatment, such as higher-order contracts with blame (Findler and Felleisen, ICFP 2002), that says the runtime check should stay, as Part 4 decides, or that an unverified callee changes how a proved call-site `pre` is reported?

## Hand-off on settlement

Not settled. On settlement: (a) `docs/design/ffi-buffer-proposal.md`; (b) the settled revision; (c) no standalone review file exists yet; (d) code-track. The engineer plans `FFI-KERNEL-1` after `BYTES-UNSIZED-1` and `FFI-BYTES-1`. The documentation-lead files the rows above and answers the `FFI-TIER2-1` DECIDE in the roadmap.
