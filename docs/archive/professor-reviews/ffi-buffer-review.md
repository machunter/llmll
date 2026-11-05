---
title: "Professor review: FFI buffers, native kernels over `bytes`"
status: "Standalone review, one round. Not folded into the proposal; doc-lead folds on settlement (DOC-CONSOLIDATE M2)."
author: professor
date: 2026-11-02
reviews: "docs/design/ffi-buffer-proposal.md (Rev 1, DRAFT 2026-11-02)"
verdict: "ACCEPT WITH CHANGES"
---

# FFI buffers: professor review of Rev 1

## Restatement

The draft reopens Tier 2 as one import form. A `c.*` import names one C file and a list of *kernels*. Each kernel is a pure function from `bytes` and `int` to one `bytes` or one `int`. The Haskell binding checks a QF-LIA `pre`, allocates a zero-filled output of `out-len` bytes, and calls C through a `safe` foreign call under `unsafePerformIO`. The verifier gets one codegen-determined fact, `bytesLen(r) = ⟦out-len⟧`, and marks each kernel call as an abstracted term. The trust report gets one `ffi_assumptions` row per kernel, with the C source hash.

**Verdict: accept with changes.** The architecture is right. Inputs are pinned and read-only, the output is fresh, every length relation is a checked `pre`, and the C code is one disclosed assumption. Two defects make a stated fact false or a stated guarantee false (H1, H4). One defect makes `refuted` false on correct programs (H3). The other findings are wording, disclosure and scope.

## Context located

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

## Answers to the author's questions

### Q1. Congruence over a `bytes` result

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

### Q2. A proved call-site `pre` with an unverified callee

**Short answer.** Keep the runtime check. Do not change how a proved call-site `pre` is reported. The literature supports both choices, but for a reason that the draft does not state.

**Blame.** In Findler and Felleisen ("Contracts for higher-order functions", ICFP 2002) a precondition is the client's obligation. A failed `pre` blames the caller, and a failed `post` blames the server. Wadler and Findler ("Well-typed programs can't be blamed", ESOP 2009) show that the more precisely typed side of a boundary is never blamed. Here the LLMLL caller is the precise side for the `pre`. A sound verifier proof of the `pre` means the check never fails. So the proof is a fact about the caller alone. The C callee's status does not change it. Report the proved `pre` as proved.

**Why the check stays.** Static contract checking removes a check only when every path to it is proved (Xu, Peyton Jones and Claessen, "Static contract checking for Haskell", POPL 2009; Nguyễn, Tobin-Hochstadt and Van Horn, "Soft contract verification", ICFP 2014). That condition fails here for three reasons.

1. The binding is one function for all callers. Some callers have no body VC: the draft keeps the `call-pre unchecked` edge for them. Removal per call site needs one binding per call site.
2. A proved `pre` is relative to the callee contracts the verifier assumes (P16). In the worked example the kernel `pre` rests on the post of `frame-at`. A fallback or `asserted` callee upstream makes that proof conditional.
3. The cost of a wrong proof is different. A wrong proof elsewhere gives a wrong value. Here it gives undefined behaviour in C.

The right frame is RustBelt (Jung et al., "RustBelt", POPL 2018). A safe API over unsafe code must be safe for *every* well-typed caller, not only for verified callers. The binding is that safe API, and the runtime check is what makes it safe. Matthews and Findler ("Operational semantics for multi-language programs", POPL 2007) give the same result for boundaries between languages: the boundary carries the check.

**What must change for this answer to hold.** The row text must make memory safety conditional on the `pre`. See H2. Otherwise the `pre` is not a memory-safety guard, and the reason to keep the check is weaker.

**Blame in the runtime message.** Binding rule 1 reports a `pre` failure and rule 4 reports a status failure with the same exit and a similar message. Under Findler–Felleisen these two failures blame different parties. The `pre` failure blames the LLMLL caller. The status failure blames the C code, against its row. State the party in each message.

## Gaps and hazards

Ordered by severity.

### H1. `out-len` above `maxBound :: Int` makes the length fact false

**Classification:** soundness. **Bite:** blocks; a one-clause fix.

The binding evaluates `out-len` over `Integer` and calls `BSI.create (fromInteger n)`. `fromInteger` to `Int` wraps modulo 2^64. The binding checks `out-len ≥ 0` but not an upper bound. The `int64` check covers each `int` argument, not the `out-len` term. A term such as `(* 4 npix)` or `(+ (bytes-length a) (bytes-length b))` can exceed `2^63 − 1` with every argument in range.

Then the allocation and the C `out_len` agree with each other, so C stays in bounds. But the verifier assumed `bytesLen(r) = ⟦out-len⟧` with the unwrapped value. That fact is false for the returned value. This is the defect class that `BYTES-LEN-RANGE-1` closed for `bytes[n]` (`CHANGELOG.md:435`), and `INT-INDEX-WRAP-1` closed for indices.

**Required.** Add `out-len ≤ 2^63 − 1` to the effective `pre`. Check it at run time before the allocation, in the order of binding rule 1. Prove it at each call site with the other clauses. Add edge case 2b: an `out-len` above `maxBound`.

### H2. The row text makes memory safety unconditional, so the `pre` guards nothing

**Classification:** soundness of the stated argument. **Bite:** complicates; wording.

The row text says the kernel is "memory-safe (it reads at most the passed length of each input and writes at most out_len bytes of the output)". That claim does not depend on the `pre`. If it holds, a `pre` violation cannot cause a memory fault, and soundness point 2 ("Memory-safety preconditions are checked, not assumed") has no content. A realistic kernel does not satisfy the unconditional claim. `pix_rgb_to_gray` reads `src[3·i + 2]` for `i < npix` and trusts that `src_len = 3·npix`. Its memory safety rests on the `pre`.

**Required.** Write the row clause as conditional: "on every input that meets its `pre`, it reads at most the passed length of each input, writes at most `out_len` bytes, and returns status 0". This is the contract the design actually needs. It also makes Q2's argument for the runtime check exact.

**Related wording.** Part 4 says the length fact "is not an assumption about the C code". This is too strong. A write past `out_len` is undefined behaviour, and no fact holds after it. The fact is codegen-determined *given* the memory-safety clause of the row. The disclosure is still complete, because every verdict that uses the fact carries the row. Say this in Part 4 and in soundness point 3.

### H3. No upper bound on `bytesLen` causes a false `refuted`

**Classification:** soundness of `refuted` (claim accuracy). **Bite:** complicates every kernel caller.

The model has `bytesLen(v) ≥ 0` and no upper bound. At run time a `ByteString` length is an `Int`, so `bytesLen(v) ≤ 2^63 − 1` always holds. Edge case 3 and the worked example show the result. Without the arbitrary bound `npix < 10^9`, the `int64` range obligation fails, and the caller is `refuted` (no abstracted term is in its environment). But the program is correct: `off + 3·npix ≤ bytesLen(file) ≤ 2^63 − 1` gives the range. This is a false `refuted` against `LLMLL.md` §4.4.1. P16 does not excuse it, because `file` is a parameter, not a callee contract that the author can strengthen.

**Required.** Add the codegen-determined fact `bytesLen(b) ≤ 2^63 − 1` for every `bytes` term. It is true of every `ByteString` on a 64-bit target. It is QF-LIA. It joins the closed axiom set as one schema, as the kernel length fact does. With it, the worked example verifies without `npix < 10^9`, and many `out-len` bounds of H1 become provable. Name the 64-bit target in the fact, because the bound is `maxBound :: Int`.

### H4. A kernel failure is a catchable exception, so "no exception reaches LLMLL code as a value" is false

**Classification:** soundness of a stated guarantee (partial correctness). **Bite:** complicates; the fix is in the binding.

Binding rule 4 and soundness point 5 say that a failure stops the program and that no exception reaches LLMLL code as a value. The generated runtime has two handlers that catch synchronous exceptions:

- `llmll_rxTotal` (`CodegenHs.hs:730-736`) forces a regex result inside `try`. If a regex argument is a thunk that calls a kernel, a kernel failure inside it becomes the regex fallback value.
- An awaited task (`CodegenHs.hs:2348-2349`) converts `SomeException` into `Left (show e)`, which LLMLL code then reads.

`exitWith` is not a way out: `ExitCode` is a synchronous exception, and both handlers catch it. The existing runtime `pre` uses `error` (`CodegenHs.hs:2247-2254`), so the same defect already exists for ordinary `pre` failures. The kernel case is worse, because the draft relies on the guarantee in its trust argument. Also, a thunk whose evaluation threw can be evaluated again, which calls C a second time.

**Required.** Specify in binding rule 4 that a kernel failure ends the process without a Haskell exception. Flush `stderr`, then call `exitImmediately` (`System.Posix.Process`) or a foreign `_exit`. Apply the same rule to the `pre` and range checks of rule 1. File the general case (ordinary `pre` failures caught by the two handlers) as a separate row. `AWAIT-ASYNC-1` is a likely owner for the await path.

### H5. Zero fill is necessary but not sufficient for determinism

**Classification:** soundness of the trust assumption. **Bite:** complicates; wording and one binding rule.

Zero fill removes one real source of non-determinism. `BSI.create` returns pinned memory that is not cleared, and a kernel that skips bytes would expose old heap data. That also leaks data across values. So zero fill is correct, and it is the right default. But the draft's argument "This makes the output a function of the inputs" claims too much. Four gaps remain.

1. **The `int` result cell is not initialized.** The ABI passes `int64_t *out`. The draft gives no initial value. A kernel that returns status 0 without a write exposes an old stack or heap word. **Required:** initialize the cell to 0 (`with 0`), by the same argument as the zero fill.
2. **Concurrency.** Generated programs use `-threaded` (`CodegenHs.hs:2685`), and a `safe` call releases the capability. Two tasks can run one kernel at the same time. A kernel with `static` state is then not deterministic. **Required:** add "reentrant and safe to call from two threads at once" to the row text.
3. **Other run-time state.** C can read uninitialized scratch memory, the floating-point environment, a clock or a random source. The row clause "no hidden effects" covers these only under the broad reading. State it in the row as "its result depends only on its arguments".
4. **Compiler flags.** `-ffast-math` or a different `-O` level can change a floating-point kernel's result. See H6.

**On the user's open question 1 (opt out of zero fill).** Keep it mandatory in v1. An opt-out converts a checked guarantee into a new assumption ("the kernel writes every output byte"). That reverses the design rule "checked or earned". The measured cost belongs to `FFI-KERNEL-REUSE-1`. If a trigger shows that `memset` costs more than the stated threshold, add the opt-out there, with the new clause in the row text. A memory-bandwidth estimate for a 25 MB frame is 1–3 ms. That figure is an estimate and is not measured.

### H6. `source_sha256` hashes one file, but the compiled code depends on more

**Classification:** disclosure (trust). **Bite:** only matters at scale; it under-discloses.

The C file can `#include "helper.h"` from its directory. The hash does not cover that header. The compiled kernel also depends on `cc-options` and on the C compiler version. A reader who compares hashes can then miss a change in the assumed code.

**Required.** Choose one of two rules. Either refuse a quoted `#include` in v1, or hash the C file and each local header it includes. Fix the `cc-options` in the generated `package.yaml` and record them in the row. Also record the hash at `build`, and warn when it differs from the `verify` hash (edge case 14).

### H7. The `bytes`-argument instance needs an amended R2, not a new R2 instance

**Classification:** spec drift. **Bite:** complicates; wording plus one code clause.

The draft lists "a `bytes` argument with an `int` result" as a new R2 instance, with no change to the rules. R2's first condition asks for an injective map from run-time values to the model (`ffi-determinism-proposal.md:116`). That map does not exist for `bytes`. The draft's own argument uses "model `=` implies run-time `=`". This property is weaker than injectivity, and it is the property an argument position needs.

**Required.** Amend R2's argument condition to "model equality on the sort implies run-time equality". Note that `int`, `bool` and `string` satisfy it, and that `bytes` satisfies it because `bytesLen` is a function and `select` agrees with the run-time value in range. Keep the result condition as it is. The engineer adds a clause for the new `bytes` type to `congSort` (`FixpointEmit.hs:4698-4702`), for argument positions only.

### H8. Clause-1 abstraction is the right choice, but its reason and its interaction with congruence are not stated

**Classification:** spec precision. **Bite:** complicates.

Part 0 of BYTE-IO keeps a single call to a contracted callee out of the abstracted set. The reason is that `refuted` is relative to the callee contract, and the author can strengthen that contract (P16). A kernel is different. Its contract is fixed by the import form, and v1 gives the author no way to strengthen it (`FFI-KERNEL-POST-1` is parked). So a `refuted` verdict would be a claim that the author cannot act on, and clause 1 is correct. **Required:** write this reason in Part 4. Without it, a reader can take clause 1 as a contradiction of the single-call rule.

The code needs care. `collectCallBinders` skips every call with a congruence key (`FixpointEmit.hs:5745-5746`). A kernel with an `int` result gets a key under R1. The clause-1 mark must come from the kernel symbol, not from the call-binder count, or a kernel pair with a key will escape the mark. State this in Affected surface.

State the cost too. A kernel caller with a false post is never `refuted`. It gets the fallback outcome, and properties skip at a kernel call. So its trust level is `asserted`. This is a large loss of signal for the use case. Name it as a risk beside risk 4.

### H9. DR2 misframes the `SAFE-HASKELL-CLAIM-1` interaction

**Classification:** spec drift. **Bite:** low.

DR2 says the kernel binding matters "if that row moves toward emitting `Safe`". The preamble already uses `unsafePerformIO` in several places (`CodegenHs.hs:299, 666, 670, 732, 941`), and the roadmap row says so (`docs/compiler-team-roadmap.md:162`). The kernel binding adds no new violation. It adds a new kind of one: `Data.ByteString.Unsafe` and `Data.ByteString.Internal` are not Safe modules, and a `foreign import` is a trusted declaration.

**Recommended.** Emit each binding into the existing generated FFI module (`CodegenHs.hs:15` and `168` already name `FFI/<Lib>.hs`), not into `Lib.hs`. Then a future `Safe` split marks one module `Trustworthy`. Rewrite DR2 to say that the binding adds no new obstacle and that it lives in the FFI module.

`unsafePerformIO` is the correct primitive here, not `unsafeDupablePerformIO`. The duplicable form can run C twice for one thunk under the threaded RTS. That is harmless for a deterministic kernel and costly for a large frame.

### H10. "Kernels only" is the right closure of `FFI-TIER2-1`, with two scope notes

**Classification:** scope. **Bite:** does not block.

Kernels cover every part of `FFI-TIER2-1` Part 7, and the shim rule replaces a direct call to `abs` at a cost of three lines of C. A general C type mapping would bring pointers, structs and callbacks, and none of them has an answer that is checked or earned. The determinism record already called the Tier 2 assumption "much stronger" (professor H9). Narrowing it to pure kernels is the smallest form that the row text can describe. Accept the closure.

Two notes. First, one C file with no `extra-libraries` excludes every native library. Real video work uses libraries such as `libyuv` or a codec library. Close `FFI-TIER2-1` with the statement that a general C mapping is refused by design, and file a parked row for linking a named native library under the same kernel convention. Its trust text must then name the library and its version. Second, `TrustReport.hs:2262` prints the prefix `haskell.` for every row. The kernel row needs a branch on `kind`. Name it in Affected surface.

### H11. Smaller points

1. **`bytes[n]` as a kernel argument.** The refusal with advice to call `bytes-widen` is right. The cost model in Part 1 is the reason, and it is sufficient.
2. **Edge case 1.** The text says the caller is `refuted` "if the term is not abstracted". State that the kernel's own result is not in the environment of its own call-pre, so a `pre` violation on plain arguments is `refuted`. Only an argument that comes from another kernel or a clause-1 builtin moves it to the fallback outcome.
3. **Edge case 5.** `BSI.create 0` gives a pointer that C must not dereference. The text says so. Add that `NULL` is also possible, as for an input.

## Recommendation

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

## Open questions for the language-team

1. H3 adds a 64-bit bound to the model. State whether LLMLL supports any 32-bit target. If it does, the bound is `maxBound :: Int` per target, and `codegen_semantics_version` must carry the target width.
2. H4 changes how a failure ends the process. State whether a kernel failure inside an awaited task ends the whole program or only the task. The draft's "stops the program" and the existing await semantics disagree, and the answer fixes binding rule 4.

---

# Round 2 (appended at settlement, 2026-11-04)

The second professor review, of Rev 2. Appended unchanged, except that its headings are one level lower and an absolute scratchpad path is shortened. Its frontmatter:

- title: "Professor review, round 2: FFI buffers, native kernels over `bytes`"
- author: professor
- date: 2026-11-04
- reviews: "docs/design/ffi-buffer-proposal.md (Rev 2, DRAFT 2026-11-02, not settled)"
- prior: "docs/design/ffi-buffer-professor-review.md (Rev 1, accept with changes)"
- verdict: "Settle with named small edits (K1-K5). No blocking finding."

## FFI buffers: professor review of Rev 2

### Restatement

Rev 2 keeps the Rev 1 architecture. A `c.*` import with `kernels` and one `source` file gives pure functions from `bytes` and `int` to one `bytes` or one `int`. The binding checks a linear `pre` and the `out-len` range, allocates a zero-filled output, and calls C under `unsafePerformIO`. A failure ends the process with `_exit(1)`. The verifier gets two codegen-determined facts: `bytesLen(r) = out-len` and a new bound `bytesLen(b) ≤ 2^63 − 1`. Each kernel call is a clause-1 abstracted term. The trust report gets one conditional row per kernel.

**Verdict: settle with small edits.** Rev 2 closes every blocking item of round 1. It introduces no new soundness defect in a verdict. One residual false `refuted` (K1) is a choice for the user. The other items are precision edits.

### Context located

1. `docs/design/ffi-buffer-proposal.md` Rev 2, "Changes in Rev 2" table and Parts 1-6: the object of this review.
2. `docs/design/ffi-buffer-professor-review.md`: round 1, H1-H11, Q1, Q2.
3. `compiler/src/LLMLL/FixpointEmit.hs:1953` (comment): `byteArraySort` and `mapArraySort` are one FQ sort, `FQArr FQInt FQInt`. This bears on K2.
4. `FixpointEmit.hs:4832-4836`: `congSort` admits `TInt`, `TBool`, `TString` only. The draft's description is correct; the round-1 line numbers moved.
5. `FixpointEmit.hs:4857-4862`: `cvPostUnassumed = isJust (contractPost contract) && isNothing mPostSubst`. This is the CALLEE-POST-UNASSUMED-1 mark (v0.36.0).
6. `compiler/src/LLMLL/AbstractionVerdict.hs:118-160`: `applyAbstractionVerdict` now decides both `abstraction-unsafe` and `callee-post-unassumed`. Candidates must be in `erBodyFaithfulFns`.
7. `FixpointEmit.hs:5011-5035`: `bytes-zero` reflects as `r = Map_default(0) ∧ bytesLen(r) = n`, only as the whole body of a `-> bytes[n]` def. So invariant I2 is a live constraint, as round 1 said.
8. `compiler/src/LLMLL/CodegenHs.hs:730-736` (`llmll_rxTotal`), `:2253` (`error "pre-condition failed"`), `:2349` (`EAwait`, `Left (show e_)`): DR3 is accurate on the v0.36.0 tree.
9. `compiler/src/LLMLL/Ffi.hs:96`, `:131`, `:189-191`: `ffi-tier2-refused`; `mentionsBytes` refuses `bytes[n]` in a result. Context item 6 of the draft is accurate.
10. `compiler/src/LLMLL/TrustReport.hs:2258-2265`: the `haskell.` prefix is hard-coded. H10's printer branch is still needed.
11. `LLMLL.md:3356` (§13.12): four ground-fact families, injected per occurring term. This bears on K2.
12. `LLMLL.md:1160` (§5.3.4) and `CHANGELOG.md` v0.36.0: the shipped CALLEE-POST-UNASSUMED-1 rule. Rev 2 predates it. It bears on edge case 1 only (K5).
13. `docs/design/clause-welldef-proposal.md` Rev 2 §4.3, "parity rule": a new body-side fact needs the same fact on the clause side. This bears on K2.

### Disposition of round-1 findings

| Item | Status | Rev 2 section | Note |
|---|---|---|---|
| H1. `out-len` above `maxBound` makes the length fact false | **Closed** | Part 3 rule 1; Part 4 effective pre; edge case 2b; binding sketch line `n > maxI64` | The check precedes `BSI.create`. The fact now holds of every returned value. |
| H2. Unconditional memory-safety clause | **Closed** | Part 4 "Why the length fact is codegen-determined"; Part 5 row text; soundness point 3 | The row text is now conditional on the `pre`. |
| H3. No upper bound on `bytesLen` gives a false `refuted` | **Closed in principle; partly in mechanism** | Part 1 "Target width"; worked example; edge case 3 | 64-bit only is a recorded user decision. The emission mechanism needs K2. The sum case remains (K1). |
| H4. A kernel failure is a catchable exception | **Closed** | Part 3 rule 4; DR3; soundness point 5; edge case 7b; `PRE-FAIL-EXIT-1` | `_exit(1)` after a flush, no `ExitCode`. One residual in K4. |
| H5. Zero fill is not sufficient for determinism | **Closed** | Part 3 ABI table, rule 2, rule 3; Part 5 row text; edge case 6b | `with 0`, "depends only on its arguments", "reentrant". Zero fill mandatory (user decision). |
| H6. Hash covers one file | **Partly closed** | Part 3 "Local headers are refused"; Part 5 `cc_options`; edge cases 14, 14b; risk 7 | The `<`-prefix rule has gaps (K3). Compiler version is disclosed as risk 7, which is acceptable. |
| H7. R2 needs an amended argument condition | **Closed** | Part 4 "Congruence"; Affected surface; routed findings | The amended condition is stated correctly, and it generalizes R2. |
| H8. Clause-1 reason and the `collectCallBinders` interaction | **Closed** | Part 4 "Each kernel call is abstracted"; Affected surface; risk 5 | Mark from the kernel symbol. The `asserted` cost is risk 5. |
| H9. DR2 misframed | **Closed** | DR2; Part 3 "The generated binding"; rule 6; risk 10 | Bindings in `FFI/<Lib>.hs`. |
| H10. Kernels-only closure | **Closed** | Part 3 "Scope"; Part 6; `FFI-KERNEL-LIB-1` | User decision recorded. |
| H11. Smaller points | **Closed** | Edge cases 1, 5, 12 | Edge case 1 needs one sentence after v0.36.0 (K5). |
| Q1. Congruence over a `bytes` result | **Closed** | Part 4 "Congruence", I1 and I2 | Omission kept; pointwise form recorded. |
| Q2. Proved `pre`, runtime check | **Closed** | Part 3 "Runtime messages and blame"; Part 4 | Blame named in each message. |
| Open question 1 (32-bit) | **Answered** | Part 1; DR4; Decisions 3 | 64-bit only. |
| Open question 2 (await) | **Answered** | Part 3 rule 4; Decisions 4 | Whole process ends. |

### Gaps and hazards in Rev 2

#### K1. A sum of lengths in `out-len` gives a false `refuted`. (soundness of `refuted`; user choice)

**Classification:** claim accuracy. **Bite:** complicates a kernel shape; not blocking.

Risk 8 says that `(+ (bytes-length a) (bytes-length b))` is not provably at most `2^63 − 1` from the Part 1 bound. It also says that the run-time check never fails on a real machine. Together these mean a correct caller is `refuted`. The counter-model has two buffers of about `2^62` bytes each, and no run can reach it. This is the H3 defect class. Rev 2 records the cost but does not name the verdict. The remedy "the caller states a bound" is the same arbitrary bound that H3 removed for `npix`.

The draft must name the outcome. Two choices are sound.

1. **Keep `refuted`, and document it.** Risk 8 states that the verdict is a false `refuted` for this shape. The `refuted` text names the `out-len` bound and tells the author to add a bound to the `pre`. This is the smaller change. It contradicts the §4.4.1 rule that a correct program is refuted only when a callee post is weaker than its body.
2. **Mark the `out-len ≤ 2^63 − 1` obligation, so its failure falls back.** The mark is the clause-1 mark that the kernel already carries, applied to this one obligation id. A real overflow (edge case 2b, `n = 2^62`) then falls back instead of `refuted`. The run-time check still ends the process. The project ranks a wrong verdict above a lost refutation (ABSTRACTION-VERDICT-1, CALLEE-POST-UNASSUMED-1).

**Recommendation:** choice 2. It removes the last false `refuted` of the design. The cost is a lost refutation on an allocation request of more than 8 EB. Keep the `int64` range obligation of an `int` argument as a hard obligation. An LLMLL `int` is an unbounded `Integer`, so a value outside `int64` is reachable, and edge case 3 is a real refutation.

#### K2. The byte-length bound must be emitted per occurring `bytes` term, not per FQ sort. (precision; small edit)

**Classification:** spec precision. **Bite:** complicates the plan; not a defect in the design.

Part 1 says the fact holds "for every term of `byteArraySort`". In the compiler, `byteArraySort` and `mapArraySort` are the same sort (`FixpointEmit.hs:1953`). A schema keyed on the FQ sort would also apply `bytesLen` to map terms. That is harmless for soundness, because nothing else constrains `bytesLen` of a map. But it is not the stated fact, and it adds noise to every map constraint.

Also, `LLMLL.md` §13.12 disclosures are of two kinds: axiom schemas and ground-fact families injected per occurring term. The bound is a ground fact about each occurring `bytesLen(t)`. The natural home is the `measure-nonneg` family, which already emits `bytesLen(t) ≥ 0` per occurring term (`injectRangeFacts`). That injection reads both sides of a constraint, so it covers clause terms too. This also meets the parity rule of the CLAUSE-WELLDEF-1 Rev 2 draft (§4.3), which requires body-side and clause-side facts to agree.

**Required edit:** in Part 1, Part 4 and the verification mapping, say that the bound is the upper half of `measure-nonneg` for `bytesLen`, injected per occurring `bytesLen` term whose argument has LLMLL type `bytes` or `bytes[n]`. Keep the disclosure as one named family entry.

#### K3. The local-header rule has gaps. (disclosure; small edit)

**Classification:** disclosure (trust). **Bite:** only matters for an adversarial or careless author.

The rule refuses an `#include` whose argument does not start with `<`. Four inputs pass it and still read program-local or arbitrary files:

1. `#include </abs/path/tables.h>` and `#include <../cbits/tables.h>`. GCC and Clang accept a path in angle brackets.
2. C23 `#embed "tables.bin"` and `#embed <...>`.
3. `__asm__(".incbin \"tables.bin\"")`.
4. An angle include that resolves inside the generated project, if Cabal adds the package root or an autogen directory to the include path. The draft asserts that `<…>` "resolves only in the toolchain". The engineer has not confirmed this on the pinned resolver.

**Required edit:** replace the prefix rule with an allowlist of standard C headers (for example `stdint.h`, `stddef.h`, `string.h`, `stdlib.h`, `math.h`, `limits.h`, `stdbool.h`). Refuse `#embed` and `.incbin` by a text scan, with the same diagnostic. Name a fixture for each refusal. An allowlist is simpler to state in the row text than a resolver claim.

#### K4. Allocation failure is a residual path to a value. (stated guarantee; note only)

**Classification:** soundness of a stated guarantee. **Bite:** only matters at scale.

Rule 4 covers a failed check and a nonzero status. `BSI.create` can also fail. Under a heap limit (`-M`), GHC raises `HeapOverflow`, an asynchronous exception. `llmll_rxTotal` rethrows it, but the `EAwait` code catches `SomeException` and gives `Left (show e_)` (`CodegenHs.hs:2349`). So a kernel allocation failure inside an awaited task becomes a value. Without `-M`, the RTS ends the process, and no defect exists.

**Required edit:** one sentence in rule 4. Either state that generated programs set no `-M`, or route the await case to `PRE-FAIL-EXIT-1` and `AWAIT-ASYNC-1`. Soundness point 5 then stays true as written.

#### K5. Edge case 1 predates CALLEE-POST-UNASSUMED-1. (spec drift; one sentence)

**Classification:** spec drift. **Bite:** wording.

Edge case 1 says that a `pre` violation is `refuted` "when `s` is a parameter or comes from a contracted LLMLL callee". Since v0.36.0, if that callee's `post` was not assumed in full at the call, the caller falls back with cause `callee-post-unassumed` (`LLMLL.md:1160`). Add that case. No other part of Rev 2 depends on CALLEE-POST-UNASSUMED-1. A kernel has no authored `post`, so `cvPostUnassumed` is false at a kernel call (`FixpointEmit.hs:4862`). The kernel's clause-1 mark and the CALLEE-POST-UNASSUMED-1 mark share `applyAbstractionVerdict`, and the shipped cause order (`AbstractionVerdict.hs`, `decide`) gives `abstraction-unsafe` only when every failing id carries the abstraction mark. Part 4 should say this in one sentence.

#### K6. Line citations moved. (citation drift; no action before settlement)

Round-1 line numbers in the folded appendix refer to the Rev 1 tree, as the appendix says. Two Rev 2 body citations also moved: `congSort` is now at `FixpointEmit.hs:4832`, and `EAwait` is at `CodegenHs.hs:2349`. The engineer reads by name.

### No new soundness issue in a verdict

I checked four places where Rev 2 adds a fact or a hypothesis.

1. **The byte-length bound.** It is true of every `ByteString` on a 64-bit target, and of every `bytes[n]` by `BYTES-LEN-RANGE-1`. It cannot make a real run's constraint unsatisfiable. With `bytes-zero`, `bytesLen(Map_default(0)) = n` and `n ≤ 2^63 − 1` agree.
2. **The amended R2 for a `bytes` argument.** In a model that represents a run, equal arrays give equal `bytesLen` and equal in-range `select`, so the run-time values are equal. The kernel is deterministic by its row, so the `int` results are equal. The hypothesis holds in that model. A run with equal values but different model arrays makes the premise false, which only weakens the hypothesis.
3. **The `out-len` upper bound in the effective `pre`.** It is a PROVE obligation and a run-time check. It cannot make a fact false. K1 is about verdict accuracy, not about a false fact.
4. **`_exit` instead of `error`.** It removes the H4 path. A failed thunk is not evaluated again.

### Recommendation

Settle Rev 2 after five edits. None of them changes the architecture.

1. **K1.** Name the verdict for an `out-len` sum. Recommended: mark the `out-len ≤ 2^63 − 1` obligation, so its failure falls back. This is the user's choice.
2. **K2.** Emit the byte-length bound as the upper half of `measure-nonneg`, per occurring `bytesLen` term of LLMLL type `bytes`, not per FQ sort.
3. **K3.** Replace the `<`-prefix rule with a standard-header allowlist. Refuse `#embed` and `.incbin`.
4. **K4.** Add one sentence on allocation failure in rule 4.
5. **K5.** Add the `callee-post-unassumed` case to edge case 1, and one sentence on the shared verdict path to Part 4.

### Open questions for the language-team

1. For K1, state which outcome the record adopts for an `out-len` bound that the Part 1 fact cannot prove. Give the text that `verify` prints.
