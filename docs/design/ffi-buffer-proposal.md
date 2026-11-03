---
title: FFI buffers — passing byte buffers to native kernels
status: Rev 2, DRAFT 2026-11-02, professor review folded; awaiting user settlement
rows: FFI-KERNEL-1 (proposed, G7, PLAN on settlement; answers FFI-TIER2-1 and lifts FFI-TIER2-REFUSE-1 for one import form); FFI-BYTES-1 (G3, PLAN; text amended, content unchanged); FFI-TIER2-1 (G7, DECIDE; answered and absorbed, closes on kernels only); FFI-NARROW-1 (G7, DECIDE; answered for kernel entries only); FFI-CONTRACT-1 (G3, DECIDE; `pre` answered for kernel entries only); CALL-CONGRUENCE-1 (closed; R2 argument condition amended); FFI-UNINTERP-1 (anticipated, not changed); AWAIT-ASYNC-1 (G1, PLAN; not changed, kernel failure consistent with it); BYTES-READ-RANGE-1 (proposed, G4, DECIDE); PRE-FAIL-EXIT-1 (proposed, G2, DECIDE); FFI-KERNEL-REUSE-1, FFI-KERNEL-HS-1, FFI-KERNEL-POST-1, FFI-KERNEL-LIB-1 (proposed, Trigger-gated Parking Lot)
review: one professor pass (of Rev 1, 2026-11-02, verdict "accept with changes", H1–H11 and answers to Q1 and Q2), folded below as the Appendix. The standalone file stays at docs/design/ffi-buffer-professor-review.md until settlement; doc-lead archives it then (DOC-CONSOLIDATE M2).
---

# FFI buffers — passing byte buffers to native kernels

**Status: Rev 2, DRAFT 2026-11-02, professor review folded; awaiting user settlement.** The language-team wrote Rev 1 on 2026-11-02. The professor reviewed Rev 1 the same day ("accept with changes"). Rev 2 adopts every required change of that review and the user's answers to the four open questions. The user has not settled the record.

## Changes in Rev 2

Each line names a review item, the change, and the place in this record.

| Item | Change | Where |
|---|---|---|
| H1 (soundness, blocks) | `out-len ≤ 2^63 − 1` joins the effective `pre`. The binding checks it before the allocation. The verifier proves it at each call. Edge case 2b is new. | Part 3 rule 1; Part 4; edge case 2b |
| H2 (trust contract) | The row's memory-safety and status clauses are conditional on the `pre`. The length fact is codegen-determined given the memory-safety clause. | Part 4; Part 5 row text; soundness point 3 |
| H3 (false `refuted`) | New codegen-determined fact `bytesLen(b) ≤ 2^63 − 1` for every `bytes` term, one schema in the closed axiom set. LLMLL supports 64-bit targets only (user decision). The worked example drops the bound `npix < 10^9`. | Part 1 "Target width"; Part 4; worked example; edge case 3 |
| H4 (stated guarantee) | A kernel failure and a failed binding check end the process with `_exit(1)` after a flush, with no Haskell exception. The failure ends the whole program, also in an awaited task (user decision). The general case for ordinary `pre` failures is the proposed row `PRE-FAIL-EXIT-1`. | Part 3 rules 1 and 4; soundness point 5; rows |
| H5 (determinism) | The `int` result cell starts at 0. The row text adds "its result depends only on its arguments" and "reentrant". Zero fill stays mandatory with no opt-out (user decision). | Part 3 ABI table and rule 2; Part 5 |
| H6 (disclosure) | A quoted `#include` in the kernel source is refused in v1. The `cc-options` are fixed and recorded in the row. `build` records the hash again and warns on a change. | Part 3 `source`; Part 5; edge case 14 |
| H7 (spec drift) | R2's argument condition is amended to "model equality implies run-time equality". `congSort` gains `bytes` for argument positions only. | Part 4 "Congruence"; Affected surface; routed findings |
| H8 (spec precision) | Part 4 states why clause 1 applies to a kernel. The mark comes from the kernel symbol. The `asserted` cost is risk 5. | Part 4; Affected surface; risk 5 |
| H9 (spec drift) | DR2 is rewritten. Bindings go into the generated FFI module, not `Lib.hs`. `unsafePerformIO` stays the primitive. | DR2; Part 3; Affected surface |
| H10 (scope) | `FFI-TIER2-1` closes on kernels only (user decision). A general C mapping is refused by design. `FFI-KERNEL-LIB-1` is parked for a named native library. The row printer branches on `kind`. | Part 3 "Scope"; Part 6; rows; Affected surface |
| H11 (smaller points) | Edge case 1 states when a `pre` violation is `refuted`. Edge case 5 adds that the pointer may be `NULL`. The `bytes[n]` refusal is unchanged. | Edge cases 1, 5, 12 |
| Q1 (congruence, `bytes` result) | The v1 omission stays. Invariants I1 and I2 are the recorded condition for any future hypothesis. A pointwise read form is the preferred future form. | Part 4 "Congruence" |
| Q2 (proved `pre`, unverified callee) | The runtime check stays. A proved call-site `pre` is reported as proved. Each runtime message names the party it blames. | Part 3 rule 1 and rule 4; Part 4 |
| Y4M probe | Measured evidence from `examples/y4m/FRICTION.md` (F1, F2, F5) replaces an unmeasured estimate and sets the trigger of `BYTES-READ-RANGE-1`. | Part 2 item 4; Part 6; worked example |

## Restatement

A video library needs this shape. A verified LLMLL core does container parsing, bounds and index arithmetic, and frame bookkeeping. Native code does the pixel work on frames of millions of bytes. LLMLL has no way to give a byte buffer of run-time length to native code and get one back. The settled Tier 2 plan (`docs/design/ffi-determinism-proposal.md` Part 7) maps scalars only. This record designs the buffer boundary: the type it uses, the Tier 1 step, the Tier 2 C convention (ownership, lifetime, mutation, failure), the verification facts a caller may use, the trust disclosure, and the ship order.

The design-reference set is the verified-language ecosystem, not the measurement set. Liquid Haskell reaches C through GHC's FFI with no checked contract at the boundary. F\* and Dafny extract to C or call native code under an `assume`d specification. The bar for LLMLL is a boundary whose memory-safety preconditions and output-length facts are checked or earned, and whose remaining assumptions are named in the trust report per verdict.

## Context located

1. `docs/design/byte-io-proposal.md` Rev 2, SETTLED 2026-10-31, Part 4 and "FFI boundary". This is the BYTE-IO decision. It settles the unsized type `bytes` (strict `ByteString`), its operations, its partial reflections and its length measure `bytesLen`. Its ship order has four steps. Step 2 (`ABSTRACTION-VERDICT-1`) shipped in v0.34.0. Step 1 (`BITWISE-1`, `CHAR-CODE-1`) and step 3 (`BYTES-UNSIZED-1`, `BYTES-READ-1`, `BYTES-WRITE-1`) are open. **This record builds on Part 4. It does not design a second unsized type.**
2. `docs/design/ffi-determinism-proposal.md` Rev 1, SETTLED. Part 1 refuses `c.*` at `check`. Part 3 gives the congruence rules R1–R5, and R2 is the sort criterion. Part 7 lists the six parts of `FFI-TIER2-1`, all scalar.
3. `docs/design/ffi-tier1-proposal.md` Rev 3, SETTLED. D1 is the forced binding. D3 refuses `bytes[n]` in a result, because nothing checks its length. D5 closes the package set at nine. D9 is the `ffi_assumptions` row. D10 adds the boundary types.
4. `docs/compiler-team-roadmap.md` rows `FFI-TIER2-1`, `FFI-BYTES-1`, `BYTES-UNSIZED-1`, `FFI-DETERM-GATE-1`, `FFI-NARROW-1`, `FFI-CONTRACT-1`, `FFI-UNINTERP-1`, `FFI-OPAQUE-1`, `BYTES-SLICE-CONTENT-1`, `SAFE-HASKELL-CLAIM-1`, `AWAIT-ASYNC-1`.
5. `LLMLL.md` §3 (`bytes[n]` is fixed length), §5.3.3 (the array class; `bytesLen` earned per position; `bytesLenParamPre`, `bytesLenRetPost`), §7 (External Bridge; the reach table row for `bytestring` reads "none"), §13.12 (the closed sealed-builtin axiom set).
6. `compiler/src/LLMLL/Ffi.hs`, `ffiImportErrors`: every `c.*` import gets `ffi-tier2-refused`. `allowed` admits `TBytes _` in arguments only; `mentionsBytes` refuses it in a result.
7. `compiler/src/LLMLL/CodegenHs.hs`: `toHsType (TBytes _) = "[Word8]"`; the preamble defines `bytes_get`, `bytes_set`, `bytes_length` over `[Word8]`. `emitFfiStub` and `emitFfiDecl` still write `foreign import ccall "<llmll name>"` at the LLMLL type, into the generated module `FFI/<Lib>.hs` (`ffiFiles`). No checked program reaches them since v0.34.1. A runtime `pre` failure is `error "pre-condition failed"`, a synchronous exception. `llmll_rxTotal` and the `EAwait` code catch synchronous exceptions. Generated programs link the `-threaded` RTS.
8. `compiler/src/LLMLL/AbstractionVerdict.hs`: the shipped verdict rule implements clause 2 (repeated calls). The clause-1 builtin set arrives with `CHAR-CODE-1` and `BYTES-UNSIZED-1`.
9. `compiler/src/LLMLL/FixpointEmit.hs`: `congSort` admits `TInt`, `TBool` and `TString` only. `collectCallBinders` skips every call that has a congruence key.
10. `compiler/src/LLMLL/PBT.hs`, `runPropertyTestsWithFfi`: the property runner is an interpreter. A property that reaches an FFI call skips, with a reason (PBT-EVAL-PARITY-1).
11. `compiler/src/LLMLL/TrustReport.hs`, `ffiNote` and `renderFfi`: the row text says "deterministic within one run … total, and with no hidden effects". The row line prints the prefix `haskell.` for every row.
12. `examples/y4m/FRICTION.md`: the Y4M probe against v0.35.1. F1: binary input is impossible, so the probe spawns `od` and `xxd`. F2: about 550 bytes of memory and 1.8–2.5 µs per input byte. F5: the frame size `w*h` is nonlinear, so no contract states it.
13. `docs/design/ffi-buffer-professor-review.md`: the professor review of Rev 1, folded as the Appendix.

No other in-flight draft on this topic exists.

**Drift found while reading.**

- **DR1.** `LLMLL.md` §7, reach table, row `bytestring`, names `BYTES-READ-1` as the blocker. The blocker is `BYTES-UNSIZED-1`, and the row that lifts it is `FFI-BYTES-1`. Route: documentation-lead, at the `FFI-BYTES-1` ship.
- **DR2 (rewritten in Rev 2, H9).** `LLMLL.md` §7 and §10 say the generated modules compile under `{-# LANGUAGE Safe #-}`. `compiler/src/LLMLL/CodegenHs.hs` emits no `Safe` pragma, and the preamble already uses `unsafePerformIO` in several places. This drift is already filed as `SAFE-HASKELL-CLAIM-1`, and that row names `unsafePerformIO` as the reason. The kernel binding adds no new obstacle to `Safe`. It adds a new kind of trusted code: `Data.ByteString.Unsafe`, `Data.ByteString.Internal` and a `foreign import`. So the bindings live in the generated FFI module `FFI/<Lib>.hs`, not in `Lib.hs`. A future `Safe` split then marks one module `Trustworthy`.
- **DR3 (new in Rev 2, H4).** `LLMLL.md` says a failed runtime `pre` stops the program. The code raises `error`, and two handlers catch it: `llmll_rxTotal` (`CodegenHs.hs:730-736`) turns it into the regex fallback value, and the `EAwait` code (`CodegenHs.hs` ~2346-2349) turns it into `Left (show e)`. So an ordinary `pre` failure can become a value. Route: the proposed row `PRE-FAIL-EXIT-1`. This record does not fix the general case. It specifies the kernel case only.
- **DR4 (new in Rev 2, H3).** `LLMLL.md` does not state the supported target width. Generated code assumes `Int` is 64 bits in at least `BYTES-LEN-RANGE-1` and `INT-INDEX-WRAP-1`. Route: documentation-lead, with the statement in Part 1.

## Design proposal

### Summary of the recommended design

| Part | Recommendation |
|---|---|
| 1. Type | The boundary type is `bytes` from `BYTES-UNSIZED-1`. No new type. Length is the `bytesLen` measure. A new codegen-determined fact bounds it: `bytesLen(b) ≤ 2^63 − 1`. LLMLL supports 64-bit targets only. `bytes[n]` stays refused in an FFI result. |
| 2. Tier 1 | Ship `FFI-BYTES-1` as settled. It does **not** unblock the use case. No Tier 1 export does pixel work, and D5 closes the package set. |
| 3. Kernel convention | Tier 2 returns as one import form: a `c.*` import with a `kernels` list and a named C source file. Each kernel is a pure function from `bytes` and `int` arguments to one `bytes` or one `int` result. A direct call to an arbitrary C function stays refused. |
| 4. Ownership | The Haskell runtime allocates every buffer. C reads inputs through a const pointer, writes one fresh, zero-filled output buffer, and keeps no pointer after it returns. No buffer is mutable from LLMLL. |
| 5. Length | A `bytes` result has a mandatory `out-len` clause: a linear term over the `int` arguments and the argument lengths. The binding checks `0 ≤ out-len ≤ 2^63 − 1` and allocates exactly that many bytes. The caller gets `bytesLen(result) = out-len` as a codegen-determined fact, given the memory-safety clause of the row. |
| 6. Preconditions | A kernel may carry `pre` clauses in QF-LIA. The binding always checks them at run time before the call. The verifier proves them at each call site with a body VC. |
| 7. Failure | A failed check or a nonzero status ends the whole process with `_exit(1)` after a flush. No Haskell exception exists, so no handler can turn the failure into a value. The message names the blamed party. |
| 8. Verification | A kernel call reflects as a fresh term with the length fact. The term is abstracted under clause 1 of `ABSTRACTION-VERDICT-1`, so UNSAFE gives the fallback outcome, not `refuted`. |
| 9. Trust | One `ffi_assumptions` row per kernel, with `package: "c.<lib>"`, the C symbol, the source path, its SHA-256 and the `cc-options`. The row text makes memory safety and status 0 conditional on the `pre`, and adds determinism and reentrancy. |
| 10. Order | `BYTES-UNSIZED-1` (BYTE-IO step 3), then `FFI-BYTES-1`, then `FFI-KERNEL-1`. `FFI-KERNEL-1` answers and absorbs `FFI-TIER2-1`. |

### Part 1 — The unsized byte type at the boundary

**Decision.** The boundary uses `bytes` as `BYTES-UNSIZED-1` defines it. It lowers to strict `Data.ByteString.ByteString`. This record adds no type and no type kind.

**Why `bytes` serves a native boundary.** Three properties of strict `ByteString` matter here.

1. Its payload is pinned memory. The garbage collector does not move it. So a pointer to it stays valid during a foreign call, including a `safe` call, during which the collector can run.
2. `Data.ByteString.Unsafe.unsafeUseAsCStringLen` gives a pointer and a length with no copy. A `bytes-slice` result is an offset view, and the pointer accounts for the offset.
3. `Data.ByteString.Internal.create` allocates a pinned buffer of a given size and gives its pointer to an `IO` action. The result is an ordinary immutable `ByteString` with no copy.

So a frame crosses the boundary in both directions with no copy. The only per-call cost is the output allocation and its zero fill (Part 3).

**Why not `bytes[n]`.** `bytes[n]` lowers to `[Word8]`, a linked list. A 6 MB frame as `[Word8]` is a list of six million cells. Its conversion to a C pointer is O(n) with a large constant. `bytes[n]` stays valid in a Tier 1 argument (D3). In a kernel argument it is refused with `ffi-type-unsupported`, and the message tells the author to call `bytes-widen`. The professor agrees that this cost model is a sufficient reason (H11.1).

**Length as a refinement fact.** The verifier already has the measure `bytesLen` over `byteArraySort`, with `bytesLen(v) ≥ 0` (`LLMLL.md` §5.3.3). Part 4 of `BYTES-UNSIZED-1` reflects `bytes-length` as `bytesLen(b)` and gives `bytes-slice` the fact `bytesLen(r) = e − s`. This record adds two facts. The `out-len` clause of a kernel gives one (Part 4 below). The target width gives the other (next paragraph). It adds no new symbol and no new sort.

**Target width (new in Rev 2, H3).** LLMLL supports 64-bit targets only. This is a user decision of 2026-11-02. On a 64-bit target, the length of a `ByteString` is an `Int`, so it is at most `maxBound :: Int = 2^63 − 1`. So the verifier may assume this fact for every term of `byteArraySort`:

```text
bytesLen(b) ≤ 9223372036854775807        (2^63 − 1)
```

The fact is codegen-determined. It joins the closed axiom set (`LLMLL.md` §13.12) as one schema, "the upper bound of a byte length". It is QF-LIA. Without it the model has no upper bound on a length, and a correct kernel caller can be `refuted` (edge case 3). The fact is also true of `bytes[n]`, because `BYTES-LEN-RANGE-1` already refuses an `n` outside `Int64`. Because only 64-bit targets are supported, `codegen_semantics_version` does not need to carry a target width. The fact is true of every `bytes` value, so `BYTES-UNSIZED-1` may ship it before `FFI-KERNEL-1`. The engineer decides; `FFI-KERNEL-1` ships it at the latest.

**`bytes[n]` in an FFI result stays refused.** The D3 reason still holds: nothing checks a Haskell-returned `[Word8]` against `n`. A kernel could carry `bytes[n]` as its result type, because the binding allocates exactly `n` bytes. This record does not propose it, because `bytes` with `out-len` covers the same case and keeps one result type. `BYTES-NARROW-1` stays parked.

### Part 2 — Tier 1 first (`FFI-BYTES-1`)

**Decision.** Ship `FFI-BYTES-1` as BYTE-IO settled it, as step 4, after `BYTES-UNSIZED-1`. `bytes` is valid in Tier 1 parameters and results. Its converter is `id`, and its forcer is WHNF, which forces a strict `ByteString` in full. This record adds one sentence to the row: a `bytes` result from a Tier 1 export carries no length fact other than the target-width bound of Part 1. The caller gets a length only from `bytes-length` at run time, or from `FFI-CONTRACT-1` when that row ships.

**Do Tier 1 bytes alone unblock the use case? No.** The reasons are measured against the reach table and the type rules, and item 4 against the Y4M probe.

1. **No Tier 1 export does pixel work.** The settled reach in `Data.ByteString` is `reverse`, `append`, `isPrefixOf`, `isSuffixOf`, `isInfixOf`, `null` and `length` through `hs-int`. The exports that transform bytes (`map`, `zipWith`, `foldl'`) take a `Word8` callback, and no boundary type exists for `Word8`. `Data.Vector` needs `FFI-OPAQUE-1`, and its unboxed and storable variants are not in the D5 module set.
2. **D5 closes the package set.** A program cannot import its own Haskell module or a Hackage package such as `JuicyPixels` or `vector`'s storable interface. Opening D5 is a larger decision than this record. It also brings the `FFI-DETERM-GATE-1` review for every new export.
3. **A per-byte callback is the wrong cost model.** Even with a `Word8` boundary type, `BS.map f` calls an LLMLL closure six million times per frame. The closure works on `Integer`, and every byte goes through `toInteger` and `fromInteger`.
4. **An LLMLL-native pixel loop is the wrong cost model too.** `bytes-set` copies, so a loop of `bytes-set` is O(n²) (BYTE-IO risk 9). The settled idiom, a `list[int]` and one `bytes-from-list`, holds one boxed `Integer` per byte. The Y4M probe measured this path (`examples/y4m/FRICTION.md` F2). On a 3,456,229-byte clip it used about 550 bytes of memory and 1.8–2.5 µs per input byte. For a 1080p RGB frame (6,220,800 bytes) that is about 3.4 GB and 11–16 s per frame. The measurement includes the text round trip through `od`, which is about 80% of the time. So the figure is an upper bound for the `list[int]` path, not an exact cost. It replaces the unmeasured Rev 1 estimate.

So Tier 1 bytes are a prerequisite and a small, separate release. The use case needs a native kernel, and that is Tier 2.

**Alternative considered: a developer-owned Haskell kernel.** A third tier could import a developer-written Haskell module with a pure `ByteString -> ByteString` function. It needs no C ABI. It is filed as `FFI-KERNEL-HS-1` in the parking lot, for two reasons. First, it reopens D5 by a back door: such a module can import any package and call `unsafePerformIO`. Second, its trust text would be the same as a C kernel's, so it adds a second path with no new guarantee. The kernel convention below is written so that this tier can reuse it later with no surface change.

### Part 3 — The kernel convention (`FFI-KERNEL-1`)

**Scope (amended in Rev 2, H10 and user decision).** Tier 2 returns as one import form only. A `c.*` import with an `interface` list stays refused with `ffi-tier2-refused`. A `c.*` import with a `kernels` list and a `source` clause is accepted. A direct call to an arbitrary C function, such as `abs` from the C standard library, stays refused by design. The author writes a short shim in the kernel source instead. A general C type mapping would bring pointers, structs and callbacks, and none of them has a contract that is checked or earned. `FFI-TIER2-1` closes on this scope. One C file with no `extra-libraries` excludes native libraries such as `libyuv` or a codec library. Linking a named native library under this convention is parked as `FFI-KERNEL-LIB-1`. Its trust text must then name the library and its version.

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
- **Local headers are refused (new in Rev 2, H6).** `check` reads the `source` file. Every `#include` line whose argument does not start with `<` gets `ffi-kernel-include-refused`. This covers `#include "helper.h"` and a macro include. A system header (`#include <stdint.h>`) is accepted, because the generated `package.yaml` adds no `include-dirs`, so it resolves only in the toolchain. So the source hash covers all program-local C code.
- `symbol` is the C symbol. It is mandatory. The LLMLL name follows the Tier 1 name rule (D2, D6). This is part 2 of `FFI-TIER2-1`.
- The type is `fn [p1: T1 … pk: Tk] -> R`. Each `Ti` is `bytes` or `int`. `R` is `bytes` or `int`. Every other type is `ffi-type-unsupported`. `Command` and `Promise` are `ffi-effect-refused` (part 4 of `FFI-TIER2-1`).
- `pre` is zero or more clauses in the kernel predicate vocabulary (below).
- `out-len` is mandatory when `R` is `bytes` and refused when `R` is `int`.

**Kernel predicate vocabulary.** A `pre` clause and the `out-len` term may use: the `int` parameters; `(bytes-length p)` for a `bytes` parameter `p`; integer literals; `+`, `-`; `*` with at least one literal operand; `=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`. Nothing else is accepted, and the diagnostic is `ffi-kernel-term-unsupported`. Every term in this vocabulary is linear, so every obligation is QF-LIA. The vocabulary is evaluable at run time in O(1), because `BS.length` is O(1). The binding evaluates each term over `Integer`, so the check itself cannot wrap.

**Surface (JSON-AST).** The `import` node gains two optional keys. `source` is a string. `kernels` is an array of objects with the required keys `name`, `symbol`, `type`, and the optional keys `pre` (an array of expressions) and `out_len` (an expression). An import node with `kernels` must also have `source`, and must not have `interface`. `ParserJSON` checks both rules. The schema version changes by one minor step. It shares the change with any other schema change in the same release.

**The C ABI.** The generated stub declares one C prototype per kernel. Arguments appear in declared order. A `bytes` parameter becomes two C arguments. An `int` parameter becomes one. The output comes last.

| LLMLL | C | Rule |
|---|---|---|
| `bytes` parameter `p` | `const uint8_t *p, size_t p_len` | `p` may be `NULL` when `p_len` is 0. C reads at most `p_len` bytes. C never writes through `p`. |
| `int` parameter `x` | `int64_t x` | The binding checks `-2^63 ≤ x ≤ 2^63 − 1` (rule 1). |
| `bytes` result | `uint8_t *out, size_t out_len` | `out_len` is the value of the `out-len` term, with `0 ≤ out_len ≤ 2^63 − 1`. The buffer is zero-filled before the call. `out` may be `NULL` when `out_len` is 0. C writes at most `out_len` bytes. |
| `int` result | `int64_t *out` | The cell is set to 0 before the call (new in Rev 2, H5). C writes one value. |
| return value | `int32_t` | 0 is success. Any other value is a kernel failure. |

The `rgb-to-gray` entry above gives this prototype:

```c
int32_t pix_rgb_to_gray(const uint8_t *src, size_t src_len,
                        int64_t npix,
                        uint8_t *out, size_t out_len);
```

**The generated binding.** The binding is a pure Haskell function in the generated module `FFI/<Lib>.hs` (H9). `Lib.hs` imports it. Its shape is illustrative. The engineer chooses the code.

```haskell
rgb_to_gray :: BS.ByteString -> Integer -> BS.ByteString
rgb_to_gray src npix
  | not (inI64 npix)                            = llmll_kernel_die Caller "c.pix" "rgb-to-gray" "int argument npix outside int64"
  | not (toInteger (BS.length src) == 3 * npix) = llmll_kernel_die Caller "c.pix" "rgb-to-gray" "pre (= (bytes-length src) (* 3 npix)) failed"
  | n < 0                                       = llmll_kernel_die Caller "c.pix" "rgb-to-gray" "out-len < 0"
  | n > maxI64                                  = llmll_kernel_die Caller "c.pix" "rgb-to-gray" "out-len > 2^63-1"
  | otherwise = unsafePerformIO $
      BSU.unsafeUseAsCStringLen src $ \(p, pl) ->
        BSI.create (fromInteger n) $ \o -> do
          fillBytes o 0 (fromInteger n)
          st <- c_pix_rgb_to_gray (castPtr p) (fromIntegral pl) (fromInteger npix) o (fromInteger n)
          when (st /= 0) (llmll_kernel_die_io Kernel "c.pix" "rgb-to-gray" ("status " ++ show st))
  where n = npix
foreign import ccall safe "pix_rgb_to_gray" c_pix_rgb_to_gray
  :: Ptr Word8 -> CSize -> Int64 -> Ptr Word8 -> CSize -> IO Int32

-- preamble: write the message, flush, end the process. No exception is raised.
llmll_kernel_die_io :: Party -> String -> String -> String -> IO a
llmll_kernel_die_io party lib k msg = do
  hPutStrLn stderr (lib ++ " " ++ k ++ ": " ++ msg ++ " (blame: " ++ showParty party ++ ")")
  hFlush stdout >> hFlush stderr
  c_exit 1                                   -- foreign import ccall unsafe "_exit"
  error "unreachable"
```

Six rules fix the binding's behaviour. The engineer may change the code but not these rules.

1. **Check order.** The binding checks the `int64` range of each `int` argument, then each `pre` clause in order, then `out-len ≥ 0`, then `out-len ≤ 2^63 − 1` (new in Rev 2, H1). All checks run before the allocation. The first failed check ends the process as rule 4 states, with a message that names the import, the kernel, the clause, and the blamed party `caller`. The C function is not called. The check runs on every call, also when the call site is proved (Part 4).
2. **The output is zero-filled, and the `int` cell starts at 0.** The binding fills the output with zeros before the call. For an `int` result it allocates the cell with the value 0 (`with 0`). So bytes or a cell that the kernel does not write are 0, not old heap or stack data. This removes one source of non-determinism and one data leak. It does not make the output a function of the inputs by itself: the kernel must also meet the determinism clauses of its row (Part 5). Zero fill is mandatory. No kernel entry can opt out (user decision 2026-11-02). An opt-out would turn a checked guarantee into a new assumption ("the kernel writes every output byte").
3. **`safe` foreign call.** The call is `safe`, so the garbage collector and other threads can run during a long kernel. All buffers are pinned, so this is correct. An `unsafe` option is not in v1. Generated programs use the `-threaded` RTS, so two tasks can run one kernel at the same time. The row text requires the kernel to be reentrant (Part 5).
4. **A failure ends the process with no Haskell exception (rewritten in Rev 2, H4).** A failed check of rule 1 or a nonzero status ends the process with exit 1. The binding writes the message to `stderr`, flushes `stdout` and `stderr`, and calls `_exit(1)` through a `foreign import`. `System.Posix.Process.exitImmediately` is an acceptable alternative where the generated project already depends on `unix`. The binding must not use `error`, `throwIO` or `exitWith`. `ExitCode` is a synchronous exception, and two handlers in the runtime catch synchronous exceptions: `llmll_rxTotal` and the `EAwait` code. So a failure inside a regex argument does not become the regex fallback value. A failure inside an awaited task ends the whole program, not only the task (user decision 2026-11-02). This is consistent with `AWAIT-ASYNC-1`, which makes an interrupt during `await` end the program instead of becoming a value. Because no exception exists, a thunk that failed is never evaluated again, so C is never called a second time for it. A status failure names the blamed party `kernel` and the C symbol and source path. The kernel result is not a `Result`. A kernel that can fail on valid input must state the condition as a `pre`. A `Result`-returning kernel is not in v1, because `admissiblePayload` admits no array payload, so its length fact would be lost (BYTE-IO Part 4, note on `bytes-from-list`).
5. **Forcing.** The result is forced in full when it is first demanded, as D1 requires. For a strict `ByteString` and for an `int`, WHNF is full evaluation.
6. **`unsafePerformIO`, not `unsafeDupablePerformIO`.** The duplicable form can run C twice for one thunk under the threaded RTS. That is harmless for a deterministic kernel and costly for a large frame (H9).

**Runtime messages and blame (new in Rev 2, Q2).** Under Findler and Felleisen a failed `pre` blames the caller and a failed post or status blames the callee. The two messages are:

```text
c.pix rgb-to-gray: pre (= (bytes-length src) (* 3 npix)) failed (blame: caller)
c.pix rgb-to-gray: status 3 (blame: kernel pix_rgb_to_gray, cbits/pix.c)
```

**The general case is a separate row.** An ordinary runtime `pre` failure still uses `error`, and the same two handlers catch it (DR3). This record does not change that. It proposes `PRE-FAIL-EXIT-1` (G2, DECIDE) for the general case. The kernel case cannot wait for that row, because the soundness argument of this record depends on it.

**Ownership and lifetime.**

| Question | Rule |
|---|---|
| Who allocates an input buffer? | The Haskell runtime, earlier, as an ordinary `bytes` value. |
| Who allocates the output buffer? | The binding, once per call, with exactly `out_len` bytes. |
| Can C write into an input? | No. The pointer is `const`, and the row text states the rule. C can break it with a cast. That is a trust failure, not a type error (edge case 9). |
| Can the output alias an input? | No. The output is a fresh allocation. |
| How long is a pointer valid? | From the start of the C call to its return. C must not keep any pointer after it returns. |
| Who frees? | The garbage collector frees every buffer. C frees nothing it did not allocate. |
| May C allocate? | Yes, for scratch memory that it frees before it returns. The row text requires that the result depends only on the arguments, so uninitialized scratch memory must not reach the result. |

**Strict immutability holds.** No LLMLL value changes after it exists. The output buffer is written only inside `create`, before any LLMLL code can see the value. That is the same pattern `bytes-set` uses, which copies into a fresh buffer. The inputs are read-only by contract. The contract is not enforced by the type system, and the trust report says so.

**Why not an explicit output-buffer convention.** A caller-supplied output buffer (`(blur src dst)`, where C writes into `dst`) avoids one allocation per frame. It is mutation of an LLMLL value, so it breaks strict immutability unless `dst` is used linearly. LLMLL has no linear types. So v1 allocates per call. The cost is one pinned allocation and one `memset` per frame. GHC allocates a large pinned object directly with the OS allocator. The professor estimates a `memset` of a 25 MB 4K RGB frame at 1–3 ms from memory bandwidth. Both figures are estimates and are not measured. Buffer reuse is filed as `FFI-KERNEL-REUSE-1` in the parking lot, with a trigger: a measured pipeline in which allocation and zero fill are more than 10% of frame time.

### Part 4 — Verification

**The kernel call reflects.** Today a direct FFI call in a VC makes the caller fall back (`docs/design/ffi-determinism-proposal.md` Part 3, R4). A kernel call does not. It reflects as a fresh term with the facts below. This is the same treatment as the partial reflections of BYTE-IO Part 4.

| Application | Fresh term | Facts the caller may assume | Category |
|---|---|---|---|
| `(k a1 … ak)`, `R = bytes` | `r : byteArraySort` | `bytesLen(r) = ⟦out-len⟧` with each parameter replaced by its argument; also `0 ≤ bytesLen(r) ≤ 2^63 − 1` from the existing measure and Part 1 | codegen-determined, given the row's memory-safety clause |
| `(k a1 … ak)`, `R = int` | `r : int` | none | — |

**Why the length fact is codegen-determined (amended in Rev 2, H2).** The binding allocates exactly `out-len` bytes, and `out-len` is in `[0, 2^63 − 1]` by rule 1. So the fact is true of every value the binding returns, provided the C code does not write outside its buffers. A write past `out_len` is undefined behaviour, and no fact holds after it. So the fact is codegen-determined *given* the memory-safety clause of the row. It is in the same category as the `bytes-zero` length axiom (`LLMLL.md` §13.12). It rides `codegen_semantics_version`. The disclosure is complete, because every verdict that uses the fact carries the row.

**Each kernel call is abstracted (reason added in Rev 2, H8).** A kernel call joins clause 1 of the abstracted-term definition (`docs/design/byte-io-proposal.md` Part 0). Its fresh term carries true but incomplete facts. So an UNSAFE constraint that holds it reports the fallback outcome with cause `abstraction:app:<kernel>`, not `refuted`. A SAFE constraint reports `verified`.

BYTE-IO Part 0 keeps a single call to a contracted LLMLL callee out of the abstracted set. The reason is P16: `refuted` is relative to the callee contract, and the author can strengthen that contract. A kernel is different. The import form fixes its contract, and v1 gives the author no way to strengthen it (`FFI-KERNEL-POST-1` is parked). So a `refuted` verdict that rests on a kernel result would be a claim that the author cannot act on. Clause 1 is the correct rule here, and it does not contradict the single-call rule.

The mark comes from the kernel symbol, not from the call-binder count. `collectCallBinders` skips every call that has a congruence key, and a kernel with an `int` result gets a key under R1. A mark from the count would let such a kernel pair escape the mark.

The closed sealed-builtin axiom set grows by two schemas: "the output length of a kernel" and "the upper bound of a byte length" (Part 1). It does not grow by one item per kernel.

**The `pre` is a PROVE obligation at each call.** The `pre` clauses, the `int64` range of each `int` argument, `out-len ≥ 0` and `out-len ≤ 2^63 − 1` form the kernel's effective precondition. At a call inside a function with a body VC, §5.3.4's call rule proves it under PROVE polarity. At a call from a function with no body VC, the existing `call-pre unchecked: <caller> -> <kernel>` line names the edge, and the runtime check stays.

**A proved `pre` is reported as proved, and the runtime check stays (Q2).** A sound proof of the `pre` is a fact about the caller alone. The C callee's status does not change it (Wadler and Findler, ESOP 2009). So the report shows it as proved. The runtime check is never removed, for three reasons. First, the binding is one function for all callers, and some callers have no body VC. Second, a proved `pre` is relative to the callee contracts the verifier assumes (P16), so an upstream fallback or `asserted` callee makes it conditional. Third, a wrong proof here gives undefined behaviour in C, not a wrong value. The binding is a safe API over unsafe code. It must be safe for every well-typed caller, not only for verified callers (RustBelt, POPL 2018). The row text makes memory safety conditional on the `pre` (Part 5), so the runtime check is the memory-safety guard.

**Which functions may call a kernel.** A `def-shell` may call a kernel. A `def` that calls a kernel stays `core-membership-violation`, as for Tier 1 (`LLMLL.md` §7, "Tier 1 effects"). Admission to `def` is the `FFI-UNINTERP-1` decision. This record anticipates it: a kernel is already an uninterpreted symbol with a disclosed assumption, so `FFI-UNINTERP-1` can admit kernels with no new rule. The motivating shape still works without it. The core is a set of `def`s over offsets, lengths and slices. A thin `def-shell` calls the kernel and passes the result back to the core (worked example).

**Congruence (`CALL-CONGRUENCE-1`; amended in Rev 2, H7 and Q1).** Two calls to one kernel in one constraint get an Ackermann hypothesis only when R2 holds for every argument sort and the result sort. Rev 2 amends R2's argument condition.

- **Amended R2, argument condition.** Rev 1 read R2 as "an injective map from run-time values to model values". For `bytes` no such map exists: one run-time value has many model arrays. The property that an argument position needs is weaker: **model equality on the sort implies run-time equality**. `int`, `bool` and `string` satisfy it, so the amendment is a generalization of R2, not an exception. `bytes` satisfies it, because `bytesLen` is a function and `select` agrees with the run-time value on `[0, bytesLen)`. The result condition of R2 does not change. The engineer adds a `bytes` clause to `congSort` for argument positions only.
- **`int` arguments and an `int` result.** R2 holds. The hypothesis is emitted.
- **A `bytes` argument and an `int` result.** The argument condition holds under the amended R2. The result condition holds for `int`. **The hypothesis is emitted.** In practice it fires when both calls take the same binder, which is the common case.
- **A `bytes` result.** **No hypothesis is emitted in v1.** The professor shows that the hypothesis would be sound under two invariants of the encoding. Call an array term *fresh* if it is a parameter, a call result or a partial-reflection result.
  - **I1 (range locality).** Every emitted fact that mentions a fresh array term reads it only through `bytesLen` or through `select` at an index that the same constraint bounds to `[0, bytesLen)`.
  - **I2 (no whole-array pin).** No emitted fact equates a fresh array term to a non-fresh array term, such as `Map_default(v)` (the `bytes-zero` reflection) or `const(v)` (the `bytes-make` reflection).

  The hypothesis still gains almost nothing today. `=` on `bytes` never reaches the solver (`wholeArrEqClause`), and the length part of the conclusion already follows from the `out-len` fact. A future `FFI-KERNEL-POST-1` post of the form `result = (bytes-make n 0)` would break I2 and make a hypothesis unsound. So the pair stays abstracted under clause 2, and the verdict is never a false `refuted`. I1 and I2 are the recorded condition for any future hypothesis over a `bytes` result. If a trigger needs content agreement, the preferred form is pointwise and needs neither invariant: `(a_i = a_j ∧ 0 ≤ t < bytesLen(r_i)) ⇒ select(r_i, t) = select(r_j, t)` for each read index `t` in the constraint.

**What the caller may not assume.** Nothing about the content of a `bytes` result. Nothing about the value of an `int` result. A content or value `post` on a kernel would be an assumption about the C code. It would rest only on the `ffi_assumptions` row. That is `FFI-CONTRACT-1` territory, and for kernels it is filed as `FFI-KERNEL-POST-1` in the parking lot.

**Testing evidence.** The property runner interprets the program, so a `check` or `for-all` that reaches a kernel skips (PBT-EVAL-PARITY-1). A function that calls a kernel gets no `tested` evidence from properties. Its evidence is `verified` (its post proved with the length fact) or `asserted`. This is a stated limit, not a defect (risks 4 and 5).

### Part 5 — The trust report

**Row.** Every verdict that rests on a kernel carries one `ffi_assumptions` row per kernel, through the existing D9 mechanism (`markFfiAssumptions`, the cross-module map, the obligation-report `trust_channel` projection). The row keys are the D9 keys plus four additive keys.

| Key | Value |
|---|---|
| `origin` | as D9 |
| `package` | `"c.<lib>"`, for example `"c.pix"` |
| `export` | the C symbol, for example `"pix_rgb_to_gray"` |
| `kind` | `"c-kernel"` (new; a Tier 1 row omits it) |
| `source` | the `source` path as written |
| `source_sha256` | the SHA-256 of the C file at `verify` time |
| `cc_options` | the fixed C compiler options of the generated `package.yaml` (new in Rev 2, H6) |

**What the hash covers (amended in Rev 2, H6).** Local headers are refused (Part 3), so the C file is all the program-local C code. The generated `package.yaml` fixes the `cc-options` to one set that the engineer chooses. The set does not contain `-ffast-math`, and a program cannot change it in v1. The row records it, so a reader knows the flags under which the kernel was assumed. The C compiler version is not recorded in v1 (risk 7). A later change to the C file does not change the LLMLL verdict hash. A reader compares the two hashes to find that the assumption was made about other code. `build` computes the hash again. When the `verify` record that `build` reads for the program carries a different hash, `build` warns with `ffi-kernel-source-changed`. The engineer chooses where `build` reads the `verify` hash.

**Row text (rewritten in Rev 2, H2 and H5).** The text report prints this line for a kernel row. The printer branches on `kind`: a kernel row prints `c.<lib> kernel`, not the `haskell.` prefix of a Tier 1 row (H10).

```text
≈ assumes c.pix kernel pix_rgb_to_gray (cbits/pix.c, sha256 <first 12 hex>, cc-options <options>) (ASSUMED, not proved: native code, taken to meet its pre-conditioned contract: on every input that meets its pre, it reads at most the passed length of each input, writes at most out_len bytes of the output and no other memory of the program, does not write an input, keeps no pointer after it returns, and returns status 0; on every input, its result depends only on its arguments (equal arguments give equal results), it is reentrant and safe to call from two threads at once, and it has no hidden effects)
```

This text is the strengthening that the determinism record requires for C (professor H9 of that record, Part 7 item 5). It is stronger than the Tier 1 text in named clauses. The memory-safety and status clauses are conditional on the `pre`, so the `pre` is the memory-safety guard and the runtime check of rule 1 has content. A realistic kernel such as `pix_rgb_to_gray` reads `src[3·i + 2]` for `i < npix` and relies on `src_len = 3·npix`. It meets the conditional clause and not an unconditional one.

**Trust level.** The level does not change, as D9 decides for Tier 1. `evidenceMeet` and the TRUST-LEVEL-FLOOR-1 floors keep their meaning. A function whose post is proved with the kernel length fact is `verified`, with the row. The row is the disclosure. `--strict-verified-core` does not apply, because a kernel caller is a `def-shell`.

**The codegen-determined facts.** The kernel length fact and the byte-length upper bound are listed once each in the closed axiom set, as two schemas. The trust report shows each under `codegen-determined` for each function whose VC uses it, as it shows the `bytes-zero` axiom.

**Effect summary.** A function that calls a kernel keeps `"unbounded"` in `effect_summary`, as every `c.*` callee does today (`LLMLL.md` §9). The summary is a sound over-approximation, and native code can reach any capability. The purity in the row text is an assumption, so the summary does not use it.

**Determinism gate.** `FFI-DETERM-GATE-1` reviews Tier 1 exports by name. A kernel is developer code, so no denylist applies. The row text carries the whole assumption.

### Part 6 — Staging and the rows

**Recommended order.**

| Step | Rows | Content | Depends on |
|---|---|---|---|
| A | `BYTES-UNSIZED-1`, `BYTES-READ-1`, `BYTES-WRITE-1` | BYTE-IO step 3, unchanged. It may ship the byte-length upper bound of Part 1. | `ABSTRACTION-VERDICT-1` (shipped). Step 1 is not a dependency of step 3 for this use case. |
| B | `FFI-BYTES-1` | BYTE-IO step 4, with the one added sentence of Part 2. | A |
| C | `FFI-KERNEL-1` | Parts 3–5 of this record. Lifts `ffi-tier2-refused` for a `c.*` import with `kernels`. Answers and closes `FFI-TIER2-1`. | A. B is not a strict dependency, but B is smaller and should ship first. |
| — | `BYTES-READ-RANGE-1` | A ranged file read. Not designed here. Not on the path for files that fit in memory (below). | A |
| — | `PRE-FAIL-EXIT-1` | The general case of rule 4 for ordinary `pre` failures. Independent of A–C. | none |

**Evidence from the Y4M probe (new in Rev 2).** The probe in `examples/y4m/` bears on the order in three ways.

1. **Step A is the first blocker, not step C (F1).** The probe cannot read a Y4M file. `wasi.fs.read` decodes UTF-8 and fails on the first non-UTF-8 byte. So the probe spawns `od` and `xxd`. No kernel helps a program that cannot read its input. This confirms that step A comes first.
2. **Step A, not `BYTES-READ-RANGE-1`, removes the memory wall for clips that fit in memory (F2).** The probe used about 550 bytes of memory per input byte. At that rate a 93 MB 30-frame 1080p clip needs about 50 GB. About 80% of the time is the text round trip, which step A removes. A strict `ByteString` holds one byte per input byte, so the same clip needs about 93 MB for the file. This figure is derived from the representation, not measured, because step A does not exist yet. So `BYTES-READ-RANGE-1` is not needed for such a clip. Its trigger is a file larger than memory, or a measured cost of a whole-file read for random frame access (F3: `frame N` cannot seek). It stays DECIDE.
3. **The frame size stays out of the kernel vocabulary (F5).** `w*h` is a product of two variables. The probe found that no contract can state it, in a `def` or a `def-shell`. So an `out-len` of `(* w h)` is refused (edge case 13), and the author passes `npix` as one `int`. The worked example follows that shape.

**`FFI-KERNEL-1` relative to `FFI-TIER2-1`.** `FFI-TIER2-1` asks whether to build Tier 2, and lists six scalar parts. This record answers: build Tier 2 as the kernel convention, not as a general C type mapping. A general C mapping is refused by design (user decision 2026-11-02). Each of the six parts has an answer.

| `FFI-TIER2-1` part | Answer in this record |
|---|---|
| 1. Type mapping | `bytes` to a pointer and a length; `int` to `int64_t` with a run-time range check; nothing else. |
| 2. Symbol names | The mandatory `symbol` clause. |
| 3. Reach (`import FFI`) | The generated module `FFI/<Lib>.hs`, which holds the bindings and their `foreign import`s and which `Lib.hs` imports. |
| 4. D4 for `c.*` | `ffi-effect-refused` for `Command` or `Promise` in a kernel type. |
| 5. D9 for `c.*` | Part 5: the row, its four new keys and its text. |
| 6. Fixtures | W-C and W8 are rewritten as kernels with a C shim, because a direct call to `abs` is not supported. The new fixtures are in "Affected surface". |

**Effect on each existing row.**

| Row | Effect |
|---|---|
| `FFI-TIER2-1` | **Closed by `FFI-KERNEL-1`** when it ships, on the kernels-only scope. The DECIDE is answered now, on settlement of this record. The closing text states that a general C mapping is refused by design and names `FFI-KERNEL-LIB-1`. |
| `FFI-TIER2-REFUSE-1` (closed, v0.34.1) | **Amended in effect.** The refusal stays for every `c.*` import without `kernels`. The `LLMLL.md` §7 text changes at the `FFI-KERNEL-1` ship. |
| `FFI-BYTES-1` | **Amended text.** One sentence: a Tier 1 `bytes` result carries no length fact other than the target-width bound. It does not unblock native work. |
| `BYTES-UNSIZED-1` | Gains a dependent. It may ship the byte-length upper bound of Part 1. |
| `FFI-NARROW-1` | **Answered for kernels only.** A kernel `int` argument has a range `pre` that is proved at call sites with a body VC and checked at run time always. The Tier 1 question stays open. This answer is evidence for the first of its two shapes. |
| `FFI-CONTRACT-1` | **Answered for kernels only, `pre` half.** A kernel may carry `pre`. The `post` half stays open, and for kernels it is `FFI-KERNEL-POST-1`. |
| `FFI-UNINTERP-1` | Unchanged. Anticipated: a kernel is admissible under its rule with no new rule. |
| `FFI-DETERM-GATE-1` | Unchanged. It does not apply to developer code. |
| `CALL-CONGRUENCE-1` (closed, v0.35.0) | **R2 argument condition amended** to "model equality implies run-time equality" (Part 4). The result condition is unchanged. `congSort` gains `bytes` in argument positions. |
| `AWAIT-ASYNC-1` | Unchanged. A kernel failure inside an awaited task ends the program, which is consistent with that row. A likely owner of the await path of `PRE-FAIL-EXIT-1`. |
| `BYTES-SLICE-CONTENT-1` | Unchanged. A kernel gives no content facts either. |
| `SAFE-HASKELL-CLAIM-1` | Gains a note: the kernel bindings use `unsafePerformIO`, `Data.ByteString.Unsafe`, `Data.ByteString.Internal` and `foreign import`, and live in `FFI/<Lib>.hs`, which a `Safe` split marks `Trustworthy`. |

## Worked example

A raw RGB video file has a header of `hdr` bytes, then frames of `3 * npix` bytes each. The core computes the offset of a frame and slices it. The shell calls the kernel.

```lisp
;; core: the frame at offset off, proved in bounds
(def frame-at [file: bytes off: int len: int] -> bytes
  (pre (and (>= off 0) (and (>= len 0) (<= (+ off len) (bytes-length file)))))
  (post (= (bytes-length result) len))
  (bytes-slice file off (+ off len)))

;; shell: one gray frame
(def-shell gray-frame [file: bytes off: int npix: int] -> bytes
  (pre (and (>= off 0) (and (>= npix 0) (<= (+ off (* 3 npix)) (bytes-length file)))))
  (post (= (bytes-length result) npix))
  (rgb-to-gray (frame-at file off (* 3 npix)) npix))
```

**Expected verdicts after step C.** These are derived from the rules, not measured, because nothing in step A to C exists yet.

- `frame-at` is `verified`. The `bytes-slice` pre is proved from the `pre`. The post follows from the slice length fact `bytesLen(r) = e − s`.
- `gray-frame` is `verified`, with one `c.pix` row. The `frame-at` pre is proved from the shell `pre`. The `frame-at` post gives `bytesLen = 3 · npix`, so the kernel `pre` holds. The `int64` range of `npix` and `out-len ≤ 2^63 − 1` follow from `off ≥ 0`, `off + 3·npix ≤ bytesLen(file)` and the Part 1 bound `bytesLen(file) ≤ 2^63 − 1`. Rev 1 needed the arbitrary bound `npix < 10^9` in the shell `pre`. Rev 2 does not (H3). The post follows from the kernel length fact `bytesLen(r) = npix`.

The frame size `w · h · 3` is a product of two variables, so it is not QF-LIA (`examples/y4m/FRICTION.md` F5). The core keeps `npix` as one `int`. The relation `npix = w · h` is checked once, where the header is parsed, with a runtime check in the shell, or it is left out of the contract.

## Edge cases and degenerate inputs

1. **A `pre` violation, positive witness.** Input: `(rgb-to-gray s 100)` where `s` has 299 bytes. Behaviour: in a caller with a body VC, the PROVE obligation `bytesLen(s) = 300` fails. The kernel's own result is not in the environment of its own call-pre. So when `s` is a parameter or comes from a contracted LLMLL callee, the caller is `refuted`. Only when `s` comes from another kernel or a clause-1 builtin is the outcome the fallback outcome (H11.2). At run time the binding writes `c.pix rgb-to-gray: pre (= (bytes-length src) (* 3 npix)) failed (blame: caller)` and ends the process with exit 1. C is not called. Channel: contract, then run time. Citation: Part 4; binding rules 1 and 4.
2. **`out-len` is negative.** Input: a kernel with `(out-len (- n 1))` called with `n = 0`. Behaviour: `out-len ≥ 0` is part of the effective `pre`. It is a PROVE obligation at the call and a run-time check. Channel: contract. Citation: binding rule 1.
2b. **`out-len` above `2^63 − 1` (new in Rev 2, H1).** Input: a kernel `quad` with `(fn [n: int] -> bytes)` and `(out-len (* 4 n))`, called with `n = 2^62`. Behaviour: `n` is in `int64` range, and `out-len = 2^64` is not. Rev 1 would call `BSI.create (fromInteger n)`, which wraps to 0, so the returned value would break `bytesLen(r) = 2^64`. Rev 2 checks `out-len ≤ 2^63 − 1` before the allocation and ends the process with blame `caller`. At a call with a body VC the obligation is proved or fails. A term over lengths alone, such as `(+ (bytes-length a) (bytes-length b))`, is not always provable from the Part 1 bound, so the caller may need to state a bound (risk 8). Channel: contract, then run time. Citation: binding rule 1; Part 4.
3. **An `int` argument outside `int64`.** Input: `(rgb-to-gray s (* 4 4611686018427387904))`. Behaviour: the range check fails at run time. At a call with a body VC the range obligation fails, and the caller is `refuted`. A bound on a length now gives a bound on an argument that is related to it, because of the Part 1 fact. In the worked example `npix ≤ bytesLen(file) / 3 ≤ (2^63 − 1) / 3`, so the range is proved with no extra `pre`. An argument that is not related to a length needs a bound in the caller's `pre`. Channel: contract, then run time. Citation: Part 1; Part 3, the ABI table. This is the `FFI-NARROW-1` shape.
4. **A zero-length input.** Input: `(sad empty empty)`. Behaviour: C receives a pointer that may be `NULL` with length 0. The ABI table states this. A kernel that dereferences it fails the memory-safety clause of its row. Channel: trust. Citation: Part 3.
5. **A zero-length output.** Input: `(rgb-to-gray empty 0)`. Behaviour: the binding allocates 0 bytes and calls C with `out_len = 0`. The pointer may be `NULL`, as for an input (H11.3), and C must not dereference it. The result is the empty `bytes`, and `bytesLen(r) = 0` holds. Channel: spec is silent on the pointer value (intentional).
6. **The kernel skips some output bytes.** Input: a kernel that writes only even indices. Behaviour: the odd bytes are 0, because the binding zero-fills. No old heap data reaches the result. Channel: run time (rule 2). Citation: Part 3.
6b. **An `int` kernel returns status 0 with no write (new in Rev 2, H5).** Input: `sad` returns 0 and never writes `*out`. Behaviour: the result is 0, because the binding sets the cell to 0. Channel: run time (rule 2).
7. **Nonzero status.** Input: a kernel that returns 3. Behaviour: the program ends with exit 1 and `c.pix rgb-to-gray: status 3 (blame: kernel pix_rgb_to_gray, cbits/pix.c)`. Partial correctness holds: no LLMLL code runs after the failure, because no exception exists for a handler to catch. The row text says status 0 on every input that meets the `pre`, so a nonzero status is a trust failure. Channel: trust. Citation: binding rule 4.
7b. **A kernel failure inside a handler (new in Rev 2, H4).** Input: a regex argument thunk, or an awaited task, that calls a kernel whose `pre` fails. Behaviour: the process ends with exit 1. The regex does not answer its fallback value, and the `await` does not give `Left`. Other tasks end with the process. Channel: run time (rule 4). Citation: DR3; binding rule 4.
8. **Two calls with the same arguments.** Input: `(+ (sad a b) (sad a b))` under post `(= result (* 2 (sad a b)))`. Behaviour: the amended R2 holds (`bytes` arguments, `int` result), so the Ackermann hypothesis is emitted and the post can verify. For `rgb-to-gray` twice with a post on equality of the two results, no hypothesis is emitted. The post is not proved, and the outcome is fallback, not `refuted`. Channel: contract (congruence), then the verdict rule. Citation: Part 4.
9. **C writes an input or keeps a pointer.** Input: a kernel that casts away `const` and writes `src[0]`. Behaviour: undefined. Another LLMLL value that shares the buffer (a slice) can change. No channel catches it. Channel: trust. The row text names both rules.
10. **The same buffer passed twice.** Input: `(sad a a)`. Behaviour: both pointers address the same memory. Both are read-only, so no conflict exists. Channel: spec is silent (intentional).
11. **A slice as input.** Input: `(rgb-to-gray (bytes-slice file 100 400) 100)`. Behaviour: the pointer is the slice start, and `src_len` is 300. No copy happens. C must not read before the pointer. Channel: trust (memory safety). Citation: Part 1.
12. **`bytes[n]` as a kernel argument.** Input: `(fn [k: bytes[32]] -> bytes)`. Behaviour: `ffi-type-unsupported`, with the advice to declare `bytes` and call `bytes-widen`. Channel: type. Citation: Part 1.
13. **A nonlinear `out-len`.** Input: `(out-len (* w h))`. Behaviour: `ffi-kernel-term-unsupported`, because neither operand is a literal. Channel: type (the `check` vocabulary rule). Citation: Part 3; `examples/y4m/FRICTION.md` F5.
14. **A changed C file after `verify`.** Input: edit `pix.c`, then `build` without `verify`. Behaviour: the old trust report keeps the old `source_sha256`. The verdict does not change, because it does not depend on the C content. `build` computes the hash again and warns with `ffi-kernel-source-changed` (H6). Channel: trust (disclosure). Citation: Part 5.
14b. **A local header (new in Rev 2, H6).** Input: `pix.c` contains `#include "tables.h"`. Behaviour: `check` fails with `ffi-kernel-include-refused`. The author inlines the header in the source file. Channel: type (`check`). Citation: Part 3.
15. **A kernel called from a `def`.** Behaviour: `core-membership-violation`, as for Tier 1. Channel: type (core membership). Citation: Part 4.

## Verification mapping

| Obligation | Channel | Fragment | Where it is emitted |
|---|---|---|---|
| Kernel `pre` at a call site | contract (PROVE) | QF-LIA: the vocabulary is linear by construction | the call rule of `LLMLL.md` §5.3.4; `compiler/src/LLMLL/FixpointEmit.hs`, with the kernel's effective `pre` in the contract environment |
| `int64` range of each `int` argument | contract (PROVE) | QF-LIA with literal bounds | the same |
| `out-len ≥ 0` | contract (PROVE) | QF-LIA | the same |
| `out-len ≤ 2^63 − 1` (new, H1) | contract (PROVE) | QF-LIA with a literal bound | the same |
| `bytesLen(r) = out-len` | assumed post, codegen-determined given the row's memory-safety clause | QF-LIA, over the existing `bytesLen` UF | the kernel reflection; disclosed in the closed axiom set (`LLMLL.md` §13.12) |
| `bytesLen(b) ≤ 2^63 − 1` for every `bytes` term (new, H3) | assumed fact, codegen-determined (64-bit targets only) | QF-LIA with a literal bound | the `bytesLen` measure facts; disclosed in the closed axiom set |
| Ackermann hypothesis, `bytes` arguments and `int` result | contract (assumed hypothesis) | QF-LIA plus array equality in the premise only | `CALL-CONGRUENCE-1` R1–R3, with the amended R2 |
| Determinism, reentrancy, memory safety under the `pre`, no write to inputs, no retained pointer, status 0 under the `pre` | trust | not a solver obligation | the `ffi_assumptions` row |

No obligation goes to Lean. Nothing in this record is nonlinear. The one nonlinear relation of the use case, `npix = w · h`, stays in the program, outside the kernel vocabulary (`LLMLL.md` §5.3.3, the `Σ_auto` boundary: constant multipliers only).

## Soundness argument for the addition

`FFI-KERNEL-1` is an addition: a new import form and a new trusted path. Six points carry the argument.

1. **Strict immutability.** No LLMLL value changes after it exists. The output is written inside `create`, before it is a value. Inputs are read-only by contract, and the contract is disclosed per verdict.
2. **Memory-safety preconditions are checked, not assumed.** Every length relation that C needs is a `pre` in QF-LIA, proved where possible and checked at run time always. The row makes memory safety conditional on the `pre`, so the check is the guard. The remaining memory-safety claim is about the C code only, and the row names it.
3. **The length facts are earned by codegen.** `bytesLen(r) = out-len` holds because the binding checks `0 ≤ out-len ≤ 2^63 − 1` and allocates exactly that many bytes, given the row's memory-safety clause. `bytesLen(b) ≤ 2^63 − 1` holds because a `ByteString` length is an `Int` on a 64-bit target. Each joins the closed axiom set as one schema.
4. **The verifier does not over-claim.** A kernel call is an abstracted term, so an UNSAFE answer is never reported as `refuted` because of it. Congruence is emitted only where the amended R2 holds. A `bytes` result gets no hypothesis.
5. **Logic functions do not see IO, and a failure is never a value.** A kernel has a pure type. A failed check or a nonzero status ends the process with `_exit(1)` and raises no Haskell exception. So no handler in the runtime, including `llmll_rxTotal` and `await`, can turn the failure into a value. A failed thunk is never evaluated again.
6. **The assumption is visible.** Every verdict that rests on a kernel carries a row with the C symbol, the source path, its hash and the `cc-options`. The effect summary stays `unbounded`.

## Affected surface

- `compiler/src/LLMLL/Ffi.hs`: `ffiImportErrors` accepts a `c.*` import with `kernels` and `source`, and keeps `ffi-tier2-refused` for every other `c.*` import. A new check validates kernel types, the predicate vocabulary and the `out-len` rule. A new check reads the source file and refuses a non-system `#include` (`ffi-kernel-include-refused`).
- `compiler/src/LLMLL/Syntax.hs`, `compiler/src/LLMLL/Parser.hs`, `compiler/src/LLMLL/ParserJSON.hs`: the import node gains `source` and `kernels`.
- `compiler/src/LLMLL/CodegenHs.hs`: `emitFfiStub` and `emitFfiDecl` are replaced by the kernel binding and the `foreign import`, both in the generated module `FFI/<Lib>.hs`. `package.yaml` gains `c-sources` and the fixed `cc-options`. The preamble gains `llmll_kernel_die`, which writes, flushes and calls `_exit(1)` (or `exitImmediately`) with no exception.
- `compiler/src/LLMLL/TypeCheck.hs`: kernels enter the environment with their LLMLL types; a `def` call stays `core-membership-violation`.
- `compiler/src/LLMLL/FixpointEmit.hs`: the kernel reflection, the effective `pre` (with `out-len ≤ 2^63 − 1`), the length fact, the byte-length upper bound for every `bytes` term, the clause-1 abstraction mark taken from the kernel symbol (not from `collectCallBinders`), and a `bytes` clause in `congSort` for argument positions only.
- `compiler/src/LLMLL/AbstractionVerdict.hs`: kernel symbols join the clause-1 set.
- `compiler/src/LLMLL/TrustReport.hs`: the row keys `kind`, `source`, `source_sha256`, `cc_options`; the kernel row text; a branch on `kind` in `renderFfi`, so a kernel row does not print the `haskell.` prefix. `docs/llmll-trust-report.schema.json`: the four additive keys.
- `build`: computes the source hash again and warns with `ffi-kernel-source-changed` on a difference from the `verify` hash.
- `docs/llmll-ast.schema.json`: `source` and `kernels` on the import node; one minor schema version change.
- `LLMLL.md` §7 (Tier 2 row and a new "Kernels" subsection), §13.12 (the two axiom-set schemas), §5.3.3 (the kernel reflection and the byte-length bound), and a statement that LLMLL supports 64-bit targets only. Documentation-lead, after the ship.
- `docs/design/ffi-determinism-proposal.md` Part 3 R2 and its `LLMLL.md` text: the amended argument condition. Documentation-lead.
- Fixtures: the worked example with a C kernel, built and run; the positive witness of edge case 1, at `verify` and at run time; edge cases 2b, 6, 6b, 7, 7b, 8, 12, 13 and 14b; W-C and W8 rewritten as kernels; a `c.*` import with `interface` still refused. Edge case 7b needs one fixture inside a regex argument and one inside `await`.

## Risks

1. **The assumption is large and unchecked.** Classification: soundness (trusted base). Citation: Part 5. Bite: limits the claim, does not block. C can break every clause of the row text. The design keeps the C-side claim to one row and moves every length relation into checked `pre`s. A debug mode that hashes each input before and after the call would detect writes to inputs. It is not proposed for v1.
2. **The whole-file read does not fit every video file.** Classification: scope. Citation: BYTE-IO risk 8; `examples/y4m/FRICTION.md` F2, F3. Bite: blocks files larger than memory, not the design. With step A a file costs about one byte of memory per byte, so clips that fit in memory work. `BYTES-READ-RANGE-1` is proposed for larger files and for seek, and is not designed here.
3. **Per-call allocation and zero fill.** Classification: verification ergonomics (cost). Bite: only matters at scale. The costs in Part 3 are estimates. The engineer measures them on a 4K frame before the ship. `FFI-KERNEL-REUSE-1` holds the remedy. Zero fill stays mandatory there too, unless that row adds a disclosed opt-out.
4. **No `tested` evidence for kernel callers.** Classification: verification ergonomics. Citation: `compiler/src/LLMLL/PBT.hs`. Bite: complicates. Properties skip at a kernel call. Running properties against the built binary is a separate, larger change.
5. **A false kernel-caller post is never `refuted` (new in Rev 2, H8).** Classification: verification ergonomics. Citation: Part 4, clause 1. Bite: complicates every kernel caller. An UNSAFE answer gives the fallback outcome, and properties skip, so such a function is `asserted`. The author gets a weaker signal than for an ordinary function. This is the cost of a contract that the author cannot strengthen.
6. **A C toolchain at build.** Classification: scope. Bite: complicates CI and `getting-started`. GHC brings a C compiler through its toolchain, so `stack build` compiles `c-sources`. The engineer confirms this on the pinned resolver and in the Docker image.
7. **The C compiler version is not disclosed (new in Rev 2, H6).** Classification: disclosure (trust). Bite: only matters at scale. The row records the source hash and the `cc-options`, not the compiler version. A different compiler can change a floating-point kernel's result. Recording it is left to `FFI-KERNEL-LIB-1` or a later row.
8. **A sum of lengths in `out-len` may need a stated bound (new in Rev 2, H1).** Classification: verification ergonomics. Bite: complicates. The Part 1 bound gives each length `≤ 2^63 − 1`, so a sum of two lengths is not provably `≤ 2^63 − 1`. The caller states a bound in its `pre`. At run time the check never fails on a real 64-bit machine, because the address space is smaller.
9. **The flush in rule 4 can block (new in Rev 2, H4).** Classification: scope (implementation). Bite: only matters at scale. If the failing thunk is evaluated while the same thread holds the `stdout` handle lock, `hFlush stdout` can block. The engineer checks this case. A flush of `stderr` alone is an acceptable fallback, at the cost of lost buffered output.
10. **`SAFE-HASKELL-CLAIM-1` interaction.** Classification: spec drift. Citation: DR2. Bite: low. The bindings live in `FFI/<Lib>.hs`, so a `Safe` split marks one module `Trustworthy`.

## Proposed roadmap rows

These tags are proposals. This record does not edit the roadmap.

| Tag | Group | Next action on settlement | Content |
|---|---|---|---|
| `FFI-KERNEL-1` | G7 | PLAN | Parts 1 (byte-length bound, if `BYTES-UNSIZED-1` does not ship it) and 3–5. Depends on `BYTES-UNSIZED-1`. Answers and, at ship, closes `FFI-TIER2-1` on the kernels-only scope. |
| `BYTES-READ-RANGE-1` | G4 | DECIDE | A read of `len` bytes at offset `off` of a file, as `RBytes`. Trigger: the first program over a file larger than memory, or a measured cost of whole-file reads for random frame access (`examples/y4m/FRICTION.md` F2, F3). Not needed for a clip that fits in memory once step A ships. |
| `PRE-FAIL-EXIT-1` | G2 | DECIDE | An ordinary runtime `pre` failure raises `error`, and two handlers catch it: `llmll_rxTotal` (`CodegenHs.hs:730-736`) gives the regex fallback value, and the `EAwait` code (`CodegenHs.hs` ~2346-2349) gives `Left (show e)`. So a failed `pre` can become a value. Decide whether every runtime `pre` failure ends the process as kernel rule 4 does. `AWAIT-ASYNC-1` is a likely owner of the await path. |
| `FFI-KERNEL-REUSE-1` | Parking lot | — | Output-buffer reuse across calls. Needs a linearity discipline. Trigger: allocation and zero fill above 10% of frame time, measured. |
| `FFI-KERNEL-HS-1` | Parking lot | — | A developer-owned Haskell kernel with the same convention. Trigger: a kernel that is simpler in Haskell than in C. |
| `FFI-KERNEL-POST-1` | Parking lot | — | Content or value `post`s on a kernel, assumed under the row. Must keep invariant I2 (Part 4), or use the pointwise form. Trigger: a caller post that needs a kernel fact other than length. |
| `FFI-KERNEL-LIB-1` | Parking lot | — | Link a named native library (for example `libyuv` or a codec library) under the kernel convention, through `extra-libraries`. The trust text names the library and its version. Trigger: a kernel that needs a native library that cannot be copied into the source file. |

## Findings routed to other owners

| Finding | Owner | What moves |
|---|---|---|
| DR1: the §7 reach row names `BYTES-READ-1` | documentation-lead | Name `BYTES-UNSIZED-1` and `FFI-BYTES-1`, at the `FFI-BYTES-1` ship. |
| DR2: `Safe` is claimed and not emitted | documentation-lead (`SAFE-HASKELL-CLAIM-1`) | Add the kernel note to the row: bindings in `FFI/<Lib>.hs`. |
| DR3: an ordinary `pre` failure can become a value | documentation-lead (file `PRE-FAIL-EXIT-1`) | File the row; cross-reference `AWAIT-ASYNC-1`. |
| DR4: the target width is not stated | documentation-lead | State in `LLMLL.md` that LLMLL supports 64-bit targets only. |
| R2 argument condition amended | documentation-lead | Amend `CALL-CONGRUENCE-1` R2 in `LLMLL.md` and note it in `docs/design/ffi-determinism-proposal.md`, at the `FFI-KERNEL-1` ship. |
| `FFI-BYTES-1` gains one sentence | documentation-lead | Part 2. |
| `FFI-TIER2-1` is answered | documentation-lead | DECIDE answered on settlement; closed at the `FFI-KERNEL-1` ship, on kernels only; file `FFI-KERNEL-LIB-1`. |

## Decisions recorded

The user answered the Rev 1 open questions and the professor's two questions on 2026-11-02.

1. **Zero fill.** Mandatory for every kernel entry. No opt-out in v1 (Part 3 rule 2).
2. **Tier 2 scope.** `FFI-TIER2-1` closes on kernels only. A direct call to an arbitrary C function stays refused and needs a C shim. Native-library linking is parked as `FFI-KERNEL-LIB-1` (Part 3 "Scope").
3. **Target width.** LLMLL supports 64-bit targets only. The byte-length bound is `2^63 − 1` (Part 1).
4. **Failure inside an awaited task.** A kernel failure ends the whole program, consistent with `AWAIT-ASYNC-1`. The mechanism is a flush and `_exit(1)` with no Haskell exception (Part 3 rule 4). The general case is `PRE-FAIL-EXIT-1`.

## Open questions for the professor

None in Rev 2. The review answered Q1 and Q2, and Part 4 records both answers.

## Hand-off on settlement

Not settled. On settlement: (a) `docs/design/ffi-buffer-proposal.md`; (b) Rev 2, or a later revision; (c) a standalone review exists at `docs/design/ffi-buffer-professor-review.md` and is already folded below, so it is ready for archive (M2); (d) code-track. The engineer plans `FFI-KERNEL-1` after `BYTES-UNSIZED-1` and `FFI-BYTES-1`. The documentation-lead files the rows above, answers the `FFI-TIER2-1` DECIDE in the roadmap, and archives the review file.

## Appendix — Professor review log

Folded 2026-11-02 by the language-team, in Rev 2. The review is copied unchanged below, without its frontmatter (reviews: Rev 1, DRAFT 2026-11-02; verdict: ACCEPT WITH CHANGES, H1–H11, answers to Q1 and Q2). The standalone file stays at [`ffi-buffer-professor-review.md`](ffi-buffer-professor-review.md) until settlement. Line citations in the review refer to the tree at Rev 1 and may move.

### Review of Rev 1 (2026-11-02)

#### Restatement

The draft reopens Tier 2 as one import form. A `c.*` import names one C file and a list of *kernels*. Each kernel is a pure function from `bytes` and `int` to one `bytes` or one `int`. The Haskell binding checks a QF-LIA `pre`, allocates a zero-filled output of `out-len` bytes, and calls C through a `safe` foreign call under `unsafePerformIO`. The verifier gets one codegen-determined fact, `bytesLen(r) = ⟦out-len⟧`, and marks each kernel call as an abstracted term. The trust report gets one `ffi_assumptions` row per kernel, with the C source hash.

**Verdict: accept with changes.** The architecture is right. Inputs are pinned and read-only, the output is fresh, every length relation is a checked `pre`, and the C code is one disclosed assumption. Two defects make a stated fact false or a stated guarantee false (H1, H4). One defect makes `refuted` false on correct programs (H3). The other findings are wording, disclosure and scope.

#### Context located

1. `docs/design/byte-io-proposal.md` Part 0 (lines 120–166): the abstracted-term definition, clause 1 and clause 2, and the P16 modular reading of `refuted`.
2. `docs/design/byte-io-proposal.md` Part 4 (lines 168–250): `bytes` reflections; `=` on `bytes` falls back through `wholeArrEqClause`.
3. `docs/design/byte-io-proposal.md:626`: `bytes-make` reflects as `r = const(v)`. This array is `v` outside `[0, n)`. It matters for Q1.
4. `docs/design/ffi-determinism-proposal.md` Part 3, R1–R5 (lines 110–137): R2 asks for an *injective* run-time-to-model map on argument sorts.
5. `docs/design/ffi-determinism-proposal.md` Part 7 (lines 158–169): the six parts of `FFI-TIER2-1`.
6. `compiler/src/LLMLL/FixpointEmit.hs:4691-4706`: `congSort` admits only `TInt`, `TBool`, `TString`.
7. `compiler/src/LLMLL/FixpointEmit.hs:5701-5730`: `addCongruence` and `congruenceFact` emit `¬(a = b) ∨ r = r'`, and drop syntactically equal argument pairs.
8. `compiler/src/LLMLL/FixpointEmit.hs:5740-5750`: `collectCallBinders` skips every call that has a congruence key.
9. `compiler/src/LLMLL/FixpointEmit.hs:4902-4909`: `bytes-zero` reflects as `r = Map_default(0)`.
10. `compiler/src/LLMLL/CodegenHs.hs:2247-2254`: a runtime `pre` failure is `error "pre-condition failed"`, a synchronous exception.
11. `compiler/src/LLMLL/CodegenHs.hs:730-736`: `llmll_rxTotal` catches every synchronous exception in a regex evaluation and answers the fallback.
12. `compiler/src/LLMLL/CodegenHs.hs:2348-2349`: an awaited task converts `SomeException` into `Left (show e)`, a value.
13. `compiler/src/LLMLL/CodegenHs.hs:299, 666, 670, 732, 941`: the preamble already uses `unsafePerformIO`.
14. `compiler/src/LLMLL/CodegenHs.hs:2685`: generated programs link the `-threaded` RTS since `PROC-TIMEOUT-1`.
15. `compiler/src/LLMLL/TrustReport.hs:2258-2262`: `ffiNote` and the row line hard-code the prefix `haskell.`.
16. `CHANGELOG.md:435`: `BYTES-LEN-RANGE-1` refused a `bytes[n]` length outside `Int64` for soundness. H1 is the same defect class.
17. `docs/compiler-team-roadmap.md:162`: `SAFE-HASKELL-CLAIM-1` already names `unsafePerformIO` as the reason `Safe` cannot compile.

No other in-flight draft on native buffers exists in `docs/design/`.

#### Answers to the author's questions

##### Q1. Congruence over a `bytes` result

**Short answer.** The hypothesis `(a_i = a_j) ⇒ (r_i = r_j)` is sound for a kernel `bytes` result under two invariants of the encoding. The candidate argument is correct in direction but incomplete. Keep the v1 omission anyway, because the hypothesis gains almost nothing today. If a later trigger needs content agreement, emit a pointwise read form, which needs no invariant.

**What soundness means here.** The hypothesis is sound when every concrete run has a model of the whole constraint, hypothesis included. The model may choose any array for a run-time `bytes` value, provided the array agrees with the value on `[0, bytesLen)`.

**The proof, and where the candidate argument is incomplete.** Call an array term *fresh* if it is a parameter, a call result or a partial-reflection result. Assume these two invariants.

- **I1 (range locality).** Every emitted fact that mentions a fresh array term reads it only through `bytesLen` or through `select` at an index that the same constraint bounds to `[0, bytesLen)`.
- **I2 (no whole-array pin).** No emitted fact equates a fresh array term to a non-fresh array term, such as `Map_default(v)` or `const(v)`.

Under I1 and I2, choose each fresh term's array as `κ(v)`, where `v` is its run-time value. `κ(v)` agrees with `v` in range. Outside the range it carries a tag that is a function of `v` alone, and that differs from every non-fresh array in the model. The domain is infinite, so such a tag exists. Then three things hold. Every range-local fact keeps its truth (I1). No pinned term conflicts (I2). Array equality between fresh terms is now exactly run-time equality. So `r_i = r_j` holds whenever the run-time results are equal, and determinism of the kernel gives that equality when the arguments are equal.

The candidate argument changes one array after the fact. That is not enough by itself, for two reasons. First, the change must propagate to every term built from `r_j` by `Map_store` or by an alias, and each of those terms must also be range-local. Second, `bytesLen` is an uninterpreted function. A changed array can collide with an unrelated array that has a different `bytesLen`. The `κ` construction removes both problems. It is the standard canonical-model argument for the array theory (de Moura and Bjørner, "Generalized, efficient array decision procedures", FMCAD 2009; Bradley, Manna and Sipma, VMCAI 2006, for the role of index bounds).

**Why I2 is not a formality.** `byte-io-proposal.md:626` reflects `bytes-make n v` as `const(v)`, which is `v` outside the range. `FixpointEmit.hs:4906` reflects `bytes-zero` as `Map_default(0)`. Today `wholeArrEqClause` makes every user `=` on `bytes` fall back, so no fact equates a kernel result to such a term. A future `FFI-KERNEL-POST-1` post of the form `result = (bytes-make n 0)` would break I2. Then the hypothesis can force two run-time-equal results to be equal to different constant arrays, which makes the constraint unsatisfiable for a real run. That is an unsound `verified`.

**Why to keep the omission.** `=` on `bytes` never reaches the solver. So the only consumer of `r_i = r_j` is a read, such as `(bytes-get (k a) t)` at two call sites. The length part of the conclusion already follows from the `out-len` fact. If a trigger needs the read part, emit `(a_i = a_j ∧ 0 ≤ t < bytesLen(r_i)) ⇒ select(r_i, t) = select(r_j, t)` for each read index `t` in the constraint. This form is ground and range-local. It is sound with no appeal to I1 or I2.

**A correction to the `bytes`-argument case.** The draft says R2 "holds" for a `bytes` argument with an `int` result. The conclusion is right, but R2 as written does not cover it. R2 asks for an *injective* map from run-time values to model values (`ffi-determinism-proposal.md:116`). For `bytes` no such function exists: one run-time value has many model arrays. The draft's real argument uses a different property: model `=` implies run-time `=`. That property is what an argument position needs. It holds for `int`, `bool` and `string` as well, so it is a correct generalization of R2, not an exception to it. See H7.

##### Q2. A proved call-site `pre` with an unverified callee

**Short answer.** Keep the runtime check. Do not change how a proved call-site `pre` is reported. The literature supports both choices, but for a reason that the draft does not state.

**Blame.** In Findler and Felleisen ("Contracts for higher-order functions", ICFP 2002) a precondition is the client's obligation. A failed `pre` blames the caller, and a failed `post` blames the server. Wadler and Findler ("Well-typed programs can't be blamed", ESOP 2009) show that the more precisely typed side of a boundary is never blamed. Here the LLMLL caller is the precise side for the `pre`. A sound verifier proof of the `pre` means the check never fails. So the proof is a fact about the caller alone. The C callee's status does not change it. Report the proved `pre` as proved.

**Why the check stays.** Static contract checking removes a check only when every path to it is proved (Xu, Peyton Jones and Claessen, "Static contract checking for Haskell", POPL 2009; Nguyễn, Tobin-Hochstadt and Van Horn, "Soft contract verification", ICFP 2014). That condition fails here for three reasons.

1. The binding is one function for all callers. Some callers have no body VC: the draft keeps the `call-pre unchecked` edge for them. Removal per call site needs one binding per call site.
2. A proved `pre` is relative to the callee contracts the verifier assumes (P16). In the worked example the kernel `pre` rests on the post of `frame-at`. A fallback or `asserted` callee upstream makes that proof conditional.
3. The cost of a wrong proof is different. A wrong proof elsewhere gives a wrong value. Here it gives undefined behaviour in C.

The right frame is RustBelt (Jung et al., "RustBelt", POPL 2018). A safe API over unsafe code must be safe for *every* well-typed caller, not only for verified callers. The binding is that safe API, and the runtime check is what makes it safe. Matthews and Findler ("Operational semantics for multi-language programs", POPL 2007) give the same result for boundaries between languages: the boundary carries the check.

**What must change for this answer to hold.** The row text must make memory safety conditional on the `pre`. See H2. Otherwise the `pre` is not a memory-safety guard, and the reason to keep the check is weaker.

**Blame in the runtime message.** Binding rule 1 reports a `pre` failure and rule 4 reports a status failure with the same exit and a similar message. Under Findler–Felleisen these two failures blame different parties. The `pre` failure blames the LLMLL caller. The status failure blames the C code, against its row. State the party in each message.

#### Gaps and hazards

Ordered by severity.

##### H1. `out-len` above `maxBound :: Int` makes the length fact false

**Classification:** soundness. **Bite:** blocks; a one-clause fix.

The binding evaluates `out-len` over `Integer` and calls `BSI.create (fromInteger n)`. `fromInteger` to `Int` wraps modulo 2^64. The binding checks `out-len ≥ 0` but not an upper bound. The `int64` check covers each `int` argument, not the `out-len` term. A term such as `(* 4 npix)` or `(+ (bytes-length a) (bytes-length b))` can exceed `2^63 − 1` with every argument in range.

Then the allocation and the C `out_len` agree with each other, so C stays in bounds. But the verifier assumed `bytesLen(r) = ⟦out-len⟧` with the unwrapped value. That fact is false for the returned value. This is the defect class that `BYTES-LEN-RANGE-1` closed for `bytes[n]` (`CHANGELOG.md:435`), and `INT-INDEX-WRAP-1` closed for indices.

**Required.** Add `out-len ≤ 2^63 − 1` to the effective `pre`. Check it at run time before the allocation, in the order of binding rule 1. Prove it at each call site with the other clauses. Add edge case 2b: an `out-len` above `maxBound`.

##### H2. The row text makes memory safety unconditional, so the `pre` guards nothing

**Classification:** soundness of the stated argument. **Bite:** complicates; wording.

The row text says the kernel is "memory-safe (it reads at most the passed length of each input and writes at most out_len bytes of the output)". That claim does not depend on the `pre`. If it holds, a `pre` violation cannot cause a memory fault, and soundness point 2 ("Memory-safety preconditions are checked, not assumed") has no content. A realistic kernel does not satisfy the unconditional claim. `pix_rgb_to_gray` reads `src[3·i + 2]` for `i < npix` and trusts that `src_len = 3·npix`. Its memory safety rests on the `pre`.

**Required.** Write the row clause as conditional: "on every input that meets its `pre`, it reads at most the passed length of each input, writes at most `out_len` bytes, and returns status 0". This is the contract the design actually needs. It also makes Q2's argument for the runtime check exact.

**Related wording.** Part 4 says the length fact "is not an assumption about the C code". This is too strong. A write past `out_len` is undefined behaviour, and no fact holds after it. The fact is codegen-determined *given* the memory-safety clause of the row. The disclosure is still complete, because every verdict that uses the fact carries the row. Say this in Part 4 and in soundness point 3.

##### H3. No upper bound on `bytesLen` causes a false `refuted`

**Classification:** soundness of `refuted` (claim accuracy). **Bite:** complicates every kernel caller.

The model has `bytesLen(v) ≥ 0` and no upper bound. At run time a `ByteString` length is an `Int`, so `bytesLen(v) ≤ 2^63 − 1` always holds. Edge case 3 and the worked example show the result. Without the arbitrary bound `npix < 10^9`, the `int64` range obligation fails, and the caller is `refuted` (no abstracted term is in its environment). But the program is correct: `off + 3·npix ≤ bytesLen(file) ≤ 2^63 − 1` gives the range. This is a false `refuted` against `LLMLL.md` §4.4.1. P16 does not excuse it, because `file` is a parameter, not a callee contract that the author can strengthen.

**Required.** Add the codegen-determined fact `bytesLen(b) ≤ 2^63 − 1` for every `bytes` term. It is true of every `ByteString` on a 64-bit target. It is QF-LIA. It joins the closed axiom set as one schema, as the kernel length fact does. With it, the worked example verifies without `npix < 10^9`, and many `out-len` bounds of H1 become provable. Name the 64-bit target in the fact, because the bound is `maxBound :: Int`.

##### H4. A kernel failure is a catchable exception, so "no exception reaches LLMLL code as a value" is false

**Classification:** soundness of a stated guarantee (partial correctness). **Bite:** complicates; the fix is in the binding.

Binding rule 4 and soundness point 5 say that a failure stops the program and that no exception reaches LLMLL code as a value. The generated runtime has two handlers that catch synchronous exceptions:

- `llmll_rxTotal` (`CodegenHs.hs:730-736`) forces a regex result inside `try`. If a regex argument is a thunk that calls a kernel, a kernel failure inside it becomes the regex fallback value.
- An awaited task (`CodegenHs.hs:2348-2349`) converts `SomeException` into `Left (show e)`, which LLMLL code then reads.

`exitWith` is not a way out: `ExitCode` is a synchronous exception, and both handlers catch it. The existing runtime `pre` uses `error` (`CodegenHs.hs:2247-2254`), so the same defect already exists for ordinary `pre` failures. The kernel case is worse, because the draft relies on the guarantee in its trust argument. Also, a thunk whose evaluation threw can be evaluated again, which calls C a second time.

**Required.** Specify in binding rule 4 that a kernel failure ends the process without a Haskell exception. Flush `stderr`, then call `exitImmediately` (`System.Posix.Process`) or a foreign `_exit`. Apply the same rule to the `pre` and range checks of rule 1. File the general case (ordinary `pre` failures caught by the two handlers) as a separate row. `AWAIT-ASYNC-1` is a likely owner for the await path.

##### H5. Zero fill is necessary but not sufficient for determinism

**Classification:** soundness of the trust assumption. **Bite:** complicates; wording and one binding rule.

Zero fill removes one real source of non-determinism. `BSI.create` returns pinned memory that is not cleared, and a kernel that skips bytes would expose old heap data. That also leaks data across values. So zero fill is correct, and it is the right default. But the draft's argument "This makes the output a function of the inputs" claims too much. Four gaps remain.

1. **The `int` result cell is not initialized.** The ABI passes `int64_t *out`. The draft gives no initial value. A kernel that returns status 0 without a write exposes an old stack or heap word. **Required:** initialize the cell to 0 (`with 0`), by the same argument as the zero fill.
2. **Concurrency.** Generated programs use `-threaded` (`CodegenHs.hs:2685`), and a `safe` call releases the capability. Two tasks can run one kernel at the same time. A kernel with `static` state is then not deterministic. **Required:** add "reentrant and safe to call from two threads at once" to the row text.
3. **Other run-time state.** C can read uninitialized scratch memory, the floating-point environment, a clock or a random source. The row clause "no hidden effects" covers these only under the broad reading. State it in the row as "its result depends only on its arguments".
4. **Compiler flags.** `-ffast-math` or a different `-O` level can change a floating-point kernel's result. See H6.

**On the user's open question 1 (opt out of zero fill).** Keep it mandatory in v1. An opt-out converts a checked guarantee into a new assumption ("the kernel writes every output byte"). That reverses the design rule "checked or earned". The measured cost belongs to `FFI-KERNEL-REUSE-1`. If a trigger shows that `memset` costs more than the stated threshold, add the opt-out there, with the new clause in the row text. A memory-bandwidth estimate for a 25 MB frame is 1–3 ms. That figure is an estimate and is not measured.

##### H6. `source_sha256` hashes one file, but the compiled code depends on more

**Classification:** disclosure (trust). **Bite:** only matters at scale; it under-discloses.

The C file can `#include "helper.h"` from its directory. The hash does not cover that header. The compiled kernel also depends on `cc-options` and on the C compiler version. A reader who compares hashes can then miss a change in the assumed code.

**Required.** Choose one of two rules. Either refuse a quoted `#include` in v1, or hash the C file and each local header it includes. Fix the `cc-options` in the generated `package.yaml` and record them in the row. Also record the hash at `build`, and warn when it differs from the `verify` hash (edge case 14).

##### H7. The `bytes`-argument instance needs an amended R2, not a new R2 instance

**Classification:** spec drift. **Bite:** complicates; wording plus one code clause.

The draft lists "a `bytes` argument with an `int` result" as a new R2 instance, with no change to the rules. R2's first condition asks for an injective map from run-time values to the model (`ffi-determinism-proposal.md:116`). That map does not exist for `bytes`. The draft's own argument uses "model `=` implies run-time `=`". This property is weaker than injectivity, and it is the property an argument position needs.

**Required.** Amend R2's argument condition to "model equality on the sort implies run-time equality". Note that `int`, `bool` and `string` satisfy it, and that `bytes` satisfies it because `bytesLen` is a function and `select` agrees with the run-time value in range. Keep the result condition as it is. The engineer adds a clause for the new `bytes` type to `congSort` (`FixpointEmit.hs:4698-4702`), for argument positions only.

##### H8. Clause-1 abstraction is the right choice, but its reason and its interaction with congruence are not stated

**Classification:** spec precision. **Bite:** complicates.

Part 0 of BYTE-IO keeps a single call to a contracted callee out of the abstracted set. The reason is that `refuted` is relative to the callee contract, and the author can strengthen that contract (P16). A kernel is different. Its contract is fixed by the import form, and v1 gives the author no way to strengthen it (`FFI-KERNEL-POST-1` is parked). So a `refuted` verdict would be a claim that the author cannot act on, and clause 1 is correct. **Required:** write this reason in Part 4. Without it, a reader can take clause 1 as a contradiction of the single-call rule.

The code needs care. `collectCallBinders` skips every call with a congruence key (`FixpointEmit.hs:5745-5746`). A kernel with an `int` result gets a key under R1. The clause-1 mark must come from the kernel symbol, not from the call-binder count, or a kernel pair with a key will escape the mark. State this in Affected surface.

State the cost too. A kernel caller with a false post is never `refuted`. It gets the fallback outcome, and properties skip at a kernel call. So its trust level is `asserted`. This is a large loss of signal for the use case. Name it as a risk beside risk 4.

##### H9. DR2 misframes the `SAFE-HASKELL-CLAIM-1` interaction

**Classification:** spec drift. **Bite:** low.

DR2 says the kernel binding matters "if that row moves toward emitting `Safe`". The preamble already uses `unsafePerformIO` in several places (`CodegenHs.hs:299, 666, 670, 732, 941`), and the roadmap row says so (`docs/compiler-team-roadmap.md:162`). The kernel binding adds no new violation. It adds a new kind of one: `Data.ByteString.Unsafe` and `Data.ByteString.Internal` are not Safe modules, and a `foreign import` is a trusted declaration.

**Recommended.** Emit each binding into the existing generated FFI module (`CodegenHs.hs:15` and `168` already name `FFI/<Lib>.hs`), not into `Lib.hs`. Then a future `Safe` split marks one module `Trustworthy`. Rewrite DR2 to say that the binding adds no new obstacle and that it lives in the FFI module.

`unsafePerformIO` is the correct primitive here, not `unsafeDupablePerformIO`. The duplicable form can run C twice for one thunk under the threaded RTS. That is harmless for a deterministic kernel and costly for a large frame.

##### H10. "Kernels only" is the right closure of `FFI-TIER2-1`, with two scope notes

**Classification:** scope. **Bite:** does not block.

Kernels cover every part of `FFI-TIER2-1` Part 7, and the shim rule replaces a direct call to `abs` at a cost of three lines of C. A general C type mapping would bring pointers, structs and callbacks, and none of them has an answer that is checked or earned. The determinism record already called the Tier 2 assumption "much stronger" (professor H9). Narrowing it to pure kernels is the smallest form that the row text can describe. Accept the closure.

Two notes. First, one C file with no `extra-libraries` excludes every native library. Real video work uses libraries such as `libyuv` or a codec library. Close `FFI-TIER2-1` with the statement that a general C mapping is refused by design, and file a parked row for linking a named native library under the same kernel convention. Its trust text must then name the library and its version. Second, `TrustReport.hs:2262` prints the prefix `haskell.` for every row. The kernel row needs a branch on `kind`. Name it in Affected surface.

##### H11. Smaller points

1. **`bytes[n]` as a kernel argument.** The refusal with advice to call `bytes-widen` is right. The cost model in Part 1 is the reason, and it is sufficient.
2. **Edge case 1.** The text says the caller is `refuted` "if the term is not abstracted". State that the kernel's own result is not in the environment of its own call-pre, so a `pre` violation on plain arguments is `refuted`. Only an argument that comes from another kernel or a clause-1 builtin moves it to the fallback outcome.
3. **Edge case 5.** `BSI.create 0` gives a pointer that C must not dereference. The text says so. Add that `NULL` is also possible, as for an input.

#### Recommendation

Accept the design with the changes below. Ranked by severity:

1. **H1 (soundness, blocks).** Add `out-len ≤ 2^63 − 1` to the effective `pre`. Check it at run time before the allocation, and prove it at call sites.
2. **H4 (soundness of a stated guarantee).** End the process on any kernel failure without a Haskell exception (`exitImmediately` or `_exit` after a `stderr` flush). File the general case for ordinary `pre` failures.
3. **H3 (false `refuted`).** Add the codegen-determined fact `bytesLen(b) ≤ 2^63 − 1` as one schema in the closed axiom set.
4. **H2 (trust contract).** Make the row's memory-safety and status clauses conditional on the `pre`. Restate the length fact as codegen-determined given that clause.
5. **H5 (determinism).** Initialize the `int` result cell to 0. Add "reentrant" and "its result depends only on its arguments" to the row text. Keep zero fill mandatory.
6. **H6 (disclosure).** Refuse or hash local `#include` files. Fix and record `cc-options`. Record the hash at `build` and warn on a change.
7. **H7 (spec drift).** Amend R2's argument condition to "model equality implies run-time equality", and add a `bytes` argument clause to `congSort`.
8. **H8 (spec precision).** State why clause 1 applies to a kernel, mark it from the kernel symbol, and list the `asserted` cost as a risk.
9. **Q1.** Keep the v1 omission for a `bytes` result. Record invariants I1 and I2 as the condition for any future hypothesis. Prefer the pointwise read form if a trigger appears.
10. **Q2.** Keep the runtime check. Report a proved call-site `pre` as proved. Name the blamed party in each runtime message.
11. **H9, H10, H11.** Rewrite DR2 and place bindings in the FFI module. Close `FFI-TIER2-1` on kernels and park native-library linking. Fix the `haskell.` prefix branch and the edge-case wording.

#### Open questions for the language-team

1. H3 adds a 64-bit bound to the model. State whether LLMLL supports any 32-bit target. If it does, the bound is `maxBound :: Int` per target, and `codegen_semantics_version` must carry the target width.
2. H4 changes how a failure ends the process. State whether a kernel failure inside an awaited task ends the whole program or only the task. The draft's "stops the program" and the existing await semantics disagree, and the answer fixes binding rule 4.
