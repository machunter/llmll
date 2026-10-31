---
title: BYTE-IO — professor review of Rev 0
status: "Archived 2026-10-31. Two passes (of Rev 0, and of the Rev 1 P1 narrowing). Folded as the Appendix of docs/design/byte-io-proposal.md (M2) at settlement of Rev 2"
reviewer: professor
date: 2026-10-31
reviews: "docs/design/byte-io-proposal.md (Rev 0)"
---

# BYTE-IO — professor review of Rev 0

## Verdict

**Settle with changes.** The five parts are sound as written, because every operation without an exact reflection makes its caller fall back. The design does not need a different tradition. It needs two decisions and a set of small repairs.

1. **Answer to the open question: yes.** A sealed builtin can be reflected partially without a false `refuted`. The condition is a change to the verdict, not to the reflection (P1). Adopt the change and fold `BYTES-PARTIAL-REFLECT-1` into this record. Without it, the `bytes-slice` precondition is runtime-only, and the reason Rev 0 gives for that precondition does not hold.
2. **Reflect `bytes-widen` as the identity on its argument.** Do not assume `bytesLen(r) = n` (P2).
3. **Keep the three exact bitwise forms.** They are exact over every integer, not only non-negative ones (P3). Exclude the mask `−1` and bound the shift constant (P4).
4. **Keep shape (b), the `RBytes` arm.** The arm passes the four-part rule on the shape reading. The break is bounded and one-time (P5, P6).
5. **Repair the worked examples.** `and` takes two arguments. Every multi-clause `pre` in the examples fails `check` (P8).
6. **The `rotl32-7` post is stateable and proves.** Measured on llmll 0.33.2 (P9). Remove risk 3.

No finding is a soundness defect in Rev 0 as written. P2 is a soundness hazard in an ambiguous clause. P1 is the decision that most changes what the record delivers.

## Restatement

Rev 0 adds an unsized byte sequence `bytes` (strict `ByteString`), distinct from `bytes[n]` and joined by `bytes-widen`. It adds byte-level file and stdio commands that deliver a sixth `Response` arm `RBytes`. It adds `string-code-at` and `string-from-code`. It adds five bitwise operations over `int`, of which ground shifts and `bit-and` with a mask `2^w − 1` reflect exactly into QF-LIA, and every other use makes the caller fall back.

## Context located

1. `docs/design/byte-io-proposal.md` Rev 0, the whole record.
2. `LLMLL.md:633`: `refuted` means "disproved, not merely unproven"; a caller of a refuted callee gets `depends-on-refuted` at the strongest severity.
3. `LLMLL.md:1137` and roadmap row `CALL-CONGRUENCE-1` (`docs/compiler-team-roadmap.md:213`): an opaque call is a fresh variable, and a true post can already be reported `refuted` (witness W5).
4. `LLMLL.md:1129`: constant arithmetic (`SIGMA-CONST-ARITH-1`); `/` and `mod` need a positive ground divisor.
5. `LLMLL.md:13`: still says `Σ_auto` is "linear integer arithmetic without `*`, `/` or `mod`". This contradicts `:1129` (P12).
6. `LLMLL.md:1132`: the array class; the length equation `bytesLen(v) = n` "is earned per position rather than asserted per binder".
7. `LLMLL.md:2164-2177` (§9.7): bulk payloads go through the filesystem; a body-faithful `Response` match covers `RList` with a wildcard.
8. `compiler/src/LLMLL/FixpointEmit.hs:2316` (`byteArraySort = FQArr FQInt FQInt`), `:2318-2324` (FACT-AG-LEN removed the binder-level length), `:6109-6113` (`bytesLenParamPre`), `:6169-6173` (`bytesLenRetPost`).
9. `compiler/src/LLMLL/FixpointEmit.hs:3222-3245` (`typeToSort`; the default is `FQInt`), `:3373-3378` (`admissiblePayload` admits only `int`, `bool`, `string`), `:3465-3476` (`buildCtorSums`).
10. `compiler/src/LLMLL/FixpointEmit.hs:2483` (`wholeArrEqClause`). Rev 0 cites `:4474-4486`; the line numbers have drifted.
11. `compiler/src/LLMLL/CodegenHs.hs:537-552` (`bytes_*` over `[Word8]`), `:2380` (`bytes-length` emission converts to `Integer`), `:2591` (`toHsType TString = "String"`), `:788-791` (`string_compare` is `compare` on `String`).
12. `compiler/src/LLMLL/TypeCheck.hs:4566-4601` (`compatibleWith`; `TBytes m` against `TBytes n` at `:4596`), `TypeAdmissibility.hs:262-276`, `Contracts.hs:422`, `RespFact.hs` (per-arm facts).
13. `docs/llmll-ast.schema.json:565-573`: `TypeBytes.length` has `"minimum": 1`. This confirms drift D1.
14. `docs/design/effect-response-channel-proposal.md:434-448`: the four-part arm rule.
15. Literature. Clarke, Grumberg, Jha, Lu and Veith, *Counterexample-Guided Abstraction Refinement*, CAV 2000. Godefroid, Nori, Rajamani and Tetali, *Compositional May-Must Program Analysis*, POPL 2010. Leino, *Dafny: An Automatic Program Verifier for Functional Correctness*, LPAR 2010. Bradley, Manna and Sipma, *What's Decidable About Arrays?*, VMCAI 2006. Sofronie-Stokkermans, *Hierarchic Reasoning in Local Theory Extensions*, CADE 2005.
16. `docs/design/multilangbench-scope-evaluation.md` Rev 2 is the only prior draft. No other draft in `docs/design/` covers byte IO or bitwise operations.

## Witnesses (GHC 9.6.4, llmll 0.33.2)

| ID | Test | Result |
|---|---|---|
| W1 | `shiftL x k == x * 2^k`, `shiftR x k == div x (2^k)`, `x .&. (2^w − 1) == mod x (2^w)`, for x in a set of 19 values that includes negatives and values above 2^64, k and w in 0..70 | all `True` |
| W2 | `5 .&. (−1)` on `Integer` | `5` (identity, not a modulus) |
| W3 | `xor a b == a + b − 2·(a .&. b)` and `(a .&. b) + (a .|. b) == a + b`, for a and b in 0..300 | `True` |
| W4 | `shiftL 5 (−1)` and `shiftR 5 (−1)` on `Integer` | both raise `arithmetic overflow` |
| W5 | `rotl32-7` written with the Rev 0 reflections, `(+ (mod (* x 128) 4294967296) (/ x 33554432))`, post `0 ≤ result ≤ 2^32 − 1` | SAFE |
| W6 | rotate by 7 then by 25, inlined, post `(= result x)` | SAFE |
| W7 | W6 with the false post `(<= result 4294967294)` | refuted (correct: `x = 2^32 − 1`) |
| W8 | the Rev 0 `b64-group` pre, `(and c1 c2 c3 c4 c5 c6)` | `error: operator 'and' expects 2 args, got 6` |

## Answer to question 1: can `bytes-slice` be reflected partially without a false `refuted`?

**Yes.** The reflection is not the problem. The verdict label is the problem.

**The reflection is sound.** Reflect `(bytes-slice b s e)` as a fresh array term `r` with the fact `bytesLen(r) = e − s`. That fact is true of the runtime value. So the emitted VC is an over-approximation of the program: every behaviour of the program is a model of the VC. If the solver answers SAFE, the post holds on every execution. This is the standard soundness argument for abstraction (Clarke et al., CAV 2000). The precedent in LLMLL is a call to a contracted user callee. Assume-guarantee replaces the callee body by its post, which is also an over-approximation.

**The false `refuted` comes from the verdict map.** UNSAFE on an over-approximated VC means "the abstraction admits a counterexample". It does not mean "the program has one". CEGAR calls such a counterexample potentially spurious. May/must analysis gives it no must-fail status (Godefroid et al., POPL 2010). Dafny reports such a failure as "might not hold", not as a disproof (Leino, LPAR 2010). `LLMLL.md:633` defines `refuted` as disproof. So `refuted` is correct only when no abstraction in the VC can cause the counterexample.

**LLMLL already violates this rule in one place.** `LLMLL.md:1137` and `CALL-CONGRUENCE-1` accept that an opaque call can make a true post `refuted`. Callers then receive `depends-on-refuted` at the strongest severity (`LLMLL.md:633`). Rev 0 is right to refuse to extend that defect to builtins. It is wrong to conclude that the builtin must therefore fall back.

**The rule that admits partial reflection.** Classify each VC term as exact or abstracted. An abstracted term is a sealed builtin reflected by true but incomplete facts, or an opaque call result. Map the solver result as follows:

| Solver | VC has no abstracted term | VC has an abstracted term |
|---|---|---|
| SAFE | `verified` | `verified` |
| UNSAFE | `refuted` | **not refuted**: the fallback outcome, cause `abstraction:app:<name>` |

The right column, second row, is exactly what Rev 0 gives today for every function that calls `bytes-slice`. So the rule is a strict improvement. Every function that falls back under Rev 0 either verifies or keeps its Rev 0 outcome. No function moves to `refuted`. Runtime `pre` assertions do not change. `--strict-verified-core` refuses the abstraction outcome as it refuses `erBodyFallback`.

**Why user contracts stay `refuted`.** A callee contract is also an abstraction. But the user wrote it and can strengthen it. `LLMLL.md:633` treats a refutation as relative to stated contracts, and that reading is the established one for modular verification. A builtin's facts are not visible or changeable by the user. So the line is: an abstraction that the user cannot change must not produce `refuted`. Apply the same rule to opaque call results. That closes `CALL-CONGRUENCE-1`'s false `refuted` with no new encoding.

**Contents of a slice.** The exact content axiom is `∀j. 0 ≤ j < e − s ⇒ r[j] = b[s + j]`. Its read `b[s + j]` has arithmetic on the bound variable. That is outside the array property fragment (Bradley, Manna and Sipma, VMCAI 2006), so no completeness result covers it. Ground instances at each read of `r` that occurs in the VC are true facts. They are sound under the rule above, and they need no completeness claim. Treat them as an optional increment.

**What this decides.** `BYTES-PARTIAL-REFLECT-1` is admissible now. `BITWISE-WIDTH-1` is admissible on the same rule (P7). Neither needs a three-valued solver result. Each needs one bit per VC, "contains an abstracted term", and that bit is syntactic.

## Gaps and hazards

Ordered by severity. Severity is **blocking** (must change before settlement), **major** (should change before settlement), or **minor** (can change in the next revision or at implementation).

**P1. The `bytes-slice` precondition is runtime-only, and Rev 0's reason for the precondition then fails.** Severity: blocking. Class: scope (verification ergonomics).
Rev 0 says that `bytes-slice` has a `pre` and not a clamp because "a `pre` makes the error a PROVE obligation at the call" (proposal, part 4). The verification-mapping row says the same `pre` is "runtime only in Rev 0, because the caller falls back". Any function that slices falls back, so its offset arithmetic is never checked statically. Byte codecs are mostly offset arithmetic. The same applies to `string-code-at`, whose index `pre` is QF-LIA over `strLen` but runtime-only.
Recommendation: adopt the verdict rule in the answer to question 1. Then reflect these as length or range facts in v1, each a disclosed assumed post under `codegen-determined`:
- `bytes-slice`: `bytesLen(r) = e − s`.
- `bytes-concat`: `bytesLen(r) = bytesLen(a) + bytesLen(b)`.
- `bytes-to-list`: `listLen(r) = bytesLen(b)`.
- `bytes-from-string`: `strLen(s) ≤ bytesLen(r) ≤ 4 · strLen(s)` (P10 explains the bounds).
- `string-code-at`: a UF `strCode(s, i)` with the ground fact `0 ≤ strCode(s, i) ≤ 1114111`.
- `string-from-code`: `strLen(r) = 1`.
Use an uninterpreted function, not a fresh variable, for `strCode`. A UF keeps congruence, so the `CALL-CONGRUENCE-1` problem does not arise.

**P2. `bytes-widen` must not assume `bytesLen(r) = n` from the type.** Severity: blocking for `BYTES-UNSIZED-1`. Class: soundness.
The mapping row gives the post `r = b ∧ bytesLen(r) = n`. It says the length is "proved from `bytesLenParamPre`". That proof exists only where `b` is a parameter (`FixpointEmit.hs:6109`) or the result of a call with a `bytes[n]` return (`:6169`). For a `let`-bound or `match`-bound `bytes[n]` value there is no such fact. FACT-AG-LEN removed the binder-level length on purpose (`FixpointEmit.hs:2318-2324`, `LLMLL.md:1132`). If an implementation reads the row as an assumed post, it re-introduces the asserted length that FACT-AG-LEN removed.
Recommendation: reflect `(bytes-widen b)` as the term `⟦b⟧` itself. `bytes` and `bytes[n]` share `byteArraySort` (`FixpointEmit.hs:2316`) and one `bytesLen` symbol. So the identity is exact, and every length fact that `b` has transfers by congruence. This adds no assumed post. The only trust is the codegen claim that `BS.pack` keeps the bytes, which is the same kind of claim as the existing `bytes-get` axiom.

**P3. The three exact bitwise forms do not depend on non-negativity.** Severity: major (it changes the stated argument, not the design). Class: soundness argument.
Witness W1 shows that on Haskell `Integer`, `shiftL x k = x · 2^k`, `shiftR x k = ⌊x / 2^k⌋` and `x .&. (2^w − 1) = x mod 2^w` hold for negative `x` too. SMT-LIB `div` and `mod` with a positive divisor are floor division and a non-negative remainder, so they agree with Haskell `div` and `mod` there (`LLMLL.md:1129`). The `a ≥ 0` precondition is a specification choice for the consumers. It is not a premise of the reflection. Rev 0 says that "every range fact below holds only for non-negative operands". That is true of the `BITWISE-WIDTH-1` lemmas, not of the three exact forms.
Recommendation: state the soundness argument without the precondition. Keep `k ≥ 0` (W4: GHC 9.6.4 raises `arithmetic overflow` for a negative count on both `shiftL` and `shiftR`; Rev 0 mentions only `shiftL`). The language-team can keep `a ≥ 0` for uniformity. Then a later relaxation needs no new proof.

**P4. Mask recognition and shift size need two side conditions.** Severity: major. Class: soundness (emitter), decidability (size).
First, the recognizer for `m = 2^w − 1` must require `m ≥ 0` after folding. The common test `m .&. (m + 1) == 0` also accepts `m = −1`. On `Integer`, `x .&. (−1) = x` (W2), which is not `x mod 2^w` for any `w`. The `b ≥ 0` call-pre usually fails first, but the emitter must not depend on that. Second, `2^c` for a large ground `c` produces a numeral of `c` bits in the `.fq` file. `(bit-shl x 1000000)` folds to a million-bit constant.
Recommendation: recognize the mask on the folded value with `m ≥ 0`. Reflect a ground shift only when `c` is at most a fixed bound, for example 4096. Above the bound, fall back with `Refused by: app:bit-shl`. State the bound in §5.3.3 beside the existing ground-constant text.

**P5. The arm-admissibility argument holds on the shape reading, and Rev 0 understates it.** Severity: major (it decides the user's open question 1). Class: scope.
Rev 0 concedes that hex makes criterion 1 "arguable". The stronger argument is about the program, not the encoding. Under (c), every reader matches `RText`, then calls `bytes-from-hex`, then matches a `Result` whose `Error` arm cannot occur for runtime-produced hex. The verifier cannot know that the arm is dead, because `bytes-from-hex` is uninterpreted. So (c) adds a dead branch to every reader that the agent must write and that no channel discharges. The four-part rule exists to keep the arm set small without such encodings. Criterion 1 should read "not expressible by an existing arm without a decoding step that can fail". On that reading, `RCode` is not redundant with decimal text, and `RBytes` is not redundant with hex. The memory figure is correct: a GHC `String` cell is three words, and characters below 256 are shared static closures, so about 48 bytes for each file byte.
Recommendation: keep (b). Amend criterion 1 in the effect-response-channel rule with the decoding-step wording, so the next arm is judged the same way.

**P6. The `RBytes` arm changes the `Response` datatype in every `.fq` file that uses it.** Severity: major. Class: soundness (emitter), regression risk.
`buildCtorSums` (`FixpointEmit.hs:3465-3476`) declares a native datatype for `Response` with a field sort from `typeToSort` for each payload. `typeToSort` has no clause for byte types and defaults to `FQInt` (`:3245`). An `RBytes` field would then be declared at `int`. The match that names `RBytes` falls back (`admissiblePayload`, `:3373`), so no array value meets the `int` field today. But the default is the same class of defect that `JSON-1` repaired for `Json` (`:3227-3232`).
Recommendation: give the new type an explicit `typeToSort` and `typeToSortA` clause at `byteArraySort`. Add a regression gate: every in-tree body-faithful `Response` match verifies with the same verdict before and after the arm is added. Add `RBytes` to `Contracts.hs:422` and decide its `RespFact.hs` rows. A fact `bytesLen(b) ≥ 0` is the only candidate, and the measure discipline gives it already.

**P7. `BITWISE-WIDTH-1` reduces to one uninterpreted function.** Severity: major (it decides a deferred row). Class: scope.
Witness W3 confirms two identities for non-negative operands: `or(a, b) = a + b − and(a, b)` and `xor(a, b) = a + b − 2 · and(a, b)`. So `bit-or` and `bit-xor` are exact linear terms over one UF `band(a, b)`. Only `band` is abstracted, with the ground facts `0 ≤ band(a, b) ≤ a` and `band(a, b) ≤ b`. The width lemma `a < 2^w ∧ b < 2^w ⇒ or(a, b) < 2^w` does not follow from those facts, so it must be a separate ground fact. With it, `crc-bits`, `crc-byte` and `crc-loop` in the Rev 0 example prove their 32-bit range posts.
Recommendation: under the verdict rule of question 1, file `BITWISE-WIDTH-1` as admissible, not parked. Specify how `w` is chosen. The simplest rule: instantiate the width fact at each `w` for which `2^w − 1` or `2^w` occurs as a ground constant in the function's contract.

**P8. The worked examples fail `check`.** Severity: minor. Class: spec drift (examples).
`and` takes two arguments (W8). `crc-bits`, `crc-byte`, `crc-loop`, `b64-group`, `add32` and `rotl32-7` use `and` with three to six arguments.
Recommendation: nest `and`, or file an n-ary `and` as a separate row. The examples will become fixtures, so they must check.

**P9. The `rotl32-7` post is stateable and proves.** Severity: minor (it closes risk 3). Class: verification ergonomics.
Witness W5 writes the body with the Rev 0 reflections, `(* x 128)` and `(/ x 33554432)`. The post `0 ≤ result ≤ 2^32 − 1` is SAFE. The proof needs integer reasoning: `(mod (* 128 x) 2^32)` is a multiple of 128, and `x / 2^25 ≤ 127`. Z3's LIA procedure finds both. Witness W6 shows that the rotate-by-25 of the rotate-by-7 is the identity on `0..2^32 − 1`, and this also proves. A false post is refuted (W7). One limit stays: a post that relates a rotate to `bit-or` or `bit-xor` is not stateable as an exact term until P7.
Recommendation: remove risk 3. Add W5 and W6 to the fixture set for `BITWISE-1`.

**P10. `bytes-from-string` length bounds depend on drift D2.** Severity: minor. Class: spec drift.
`string` is a Haskell `String` of code points (`CodegenHs.hs:2591`). `LLMLL.md` §3.1 calls it a UTF-8 byte sequence. Under the mapping in part 4, a code point becomes 1 to 4 bytes, U+DC80 to U+DCFF become 1 byte, and other lone surrogates become 3 bytes (U+FFFD). So `strLen(s) ≤ bytesLen(r) ≤ 4 · strLen(s)`. A reader who believes §3.1 would assume `bytesLen(r) = strLen(s)`, which is false for non-ASCII text.
Recommendation: repair §3.1 as D2 says. Use the two bounds of P1 as the only length facts for `bytes-from-string`.

**P11. CHAR-CODE-1 preconditions are correct. State the result range without a surrogate exclusion.** Severity: minor. Class: specification.
The constants are right: 55296 = 0xD800, 57343 = 0xDFFF, 1114111 = 0x10FFFF. GHC's `chr` accepts surrogates and fails only above 0x10FFFF. So the surrogate exclusion in `string-from-code` is a design choice for safe encoding at the IO boundary, and it is the right choice. `string-code-at` can return U+DC80 to U+DCFF from argv or a listing (`LLMLL.md:1408`). So its range fact must be `0..1114111` with no hole for surrogates. Agreement with `string-compare` holds by construction: `string_compare` is `compare` on `String` (`CodegenHs.hs:788-791`) and `string-code-at` reads `ord`. The index must be compared as `Integer` before `!!` narrows it, under `INT-INDEX-WRAP-1`.
Recommendation: state the result fact as above. Name the `Integer` comparison in the §13.6 row.

**P12. `LLMLL.md:13` contradicts `SIGMA-CONST-ARITH-1`.** Severity: minor. Class: spec drift.
Line 13 excludes `*`, `/` and `mod` from `Σ_auto`. Line 1129 admits them with a ground constant. `BITWISE-1` adds three more constant forms, so the summary line becomes more wrong.
Recommendation: route to documentation-lead with D1 and D2. The fix is one clause: "with constant multipliers and positive constant divisors".

**P13. Two stdio edge cases are missing.** Severity: minor. Class: specification.
First, `BS.hGetContents` closes `stdin`. A second `wasi.io.stdin-bytes` in the same run either delivers an empty `RBytes` or an `RErr`. The spec must say which. Second, a `:mode cli` program can mix `wasi.io.stdout` (text, through the UTF-8 character buffer) with `wasi.io.stdout-bytes` (`BS.hPut`, the byte buffer). The output order must equal the command order.
Recommendation: specify the second read as `RBytes` of length 0, which matches the empty-file rule in edge case 1. Add a fixture that interleaves text and byte writes and checks the output order.

**P14. Citation drift in Rev 0.** Severity: minor. Class: spec drift.
`wholeArrEqClause` is at `FixpointEmit.hs:2483`, not `:4474-4486`. The uninterpreted-builtin list is at `LLMLL.md:1135`, not `:1133`. The in-tree census now gives 65 `RList` arms in 24 files, with the untracked `examples/netpbm*` directories present.
Recommendation: cite by function name, as the `reifyBytesZeroLen` comment advises (`FixpointEmit.hs:2333-2335`).

## Critique of the remaining points

- **One type or two (question 4).** Two types is right for LLMLL. A single type with an optional length is the Liquid Haskell approach: one `ByteString` with a length measure and refinement subtyping between `{v | len v = n}` and the plain type. LLMLL excludes refinement subtyping (`LLMLL.md:18`). The four head-syntax readers of `TBytes n` would also break. This is a scope divergence from Liquid Haskell, not a soundness defect. The shared SMT sort makes the identity reflection of P2 possible, so the two types cost nothing in the verifier.
- **Narrowing (`BYTES-NARROW-1`).** When it ships, give it the `pre` form `bytesLen(b) = n` (PROVE), take `n` from the determining context as `bytes-zero` does, and reflect it as the identity. Do not give it a `Result` form. A `Result` payload of array sort is not admissible (`FixpointEmit.hs:3373`), and FACT-AG-LEN gives a `match` binder no length. A narrowed value passed to a `bytes[n]` parameter would then face a call-pre `bytesLen(arg) = n` that no fact can discharge.
- **Separate JSON kind `bytes-unsized`.** Correct. An optional key would make a dropped `length` a silent type change.
- **The `LlmllBytes` class.** Sound. The emitter keeps one name for each operation, and `emitApp` already converts `bytes_length` to `Integer` (`CodegenHs.hs:2380`). Each instance is new trusted code under `codegen_semantics_version`, as Rev 0 says.
- **Replay and the event log (question 3).** Neither (b) nor (c) changes determinism. The console event log records stdin lines and stdout text, not `Response` values. `wasi.fs.read-bytes` in console mode is as deterministic as `wasi.fs.read`: both depend on the file. Byte stdio is refused in console mode. The only difference is the encoding that a future `REPLAY-INJECT` must choose for an `RBytes` payload. That is a deferred format decision, not a reason to prefer (c).
- **The breaking change.** The census is an upper bound, and it is the right metric. A body-faithful `Response` match already covers `RList` with a wildcard (`LLMLL.md:2174-2176`), so most verified code does not break. The diagnostic must name `RBytes` and the one-line repair. Rust's `#[non_exhaustive]` would avoid the next break, but it removes the missing-arm error that agents rely on. Do not adopt it.
- **Literature position.** Dafny (`bv8`, `seq<bv8>`) and F\* (machine integers) choose QF-BV. LLMLL chooses unbounded `int` with exact linear cases. That choice cannot verify mixing functions such as a ChaCha20 quarter round. Rev 0 states this plainly, and the statement is accurate. P7 recovers range facts. It does not recover functional correctness of XOR mixing. That still needs the `machine-int` opt-in named in `LLMLL.md` §3.1.

## Recommendation

1. **Adopt the abstraction verdict rule** from the answer to question 1. UNSAFE on a VC that contains a builtin abstraction or an opaque call result reports the fallback outcome with cause `abstraction:app:<name>`, not `refuted`. File it as its own row. It also closes the false `refuted` of `CALL-CONGRUENCE-1`.
2. **Fold `BYTES-PARTIAL-REFLECT-1` into v1** with the length and range facts of P1. Then the `bytes-slice` and `string-code-at` preconditions are PROVE obligations, as Rev 0 intends.
3. **Reflect `bytes-widen` as the identity** (P2). Remove its assumed post.
4. **Keep the three exact bitwise forms.** Restate their soundness without non-negativity (P3). Add the mask and shift-size side conditions (P4).
5. **Move `BITWISE-WIDTH-1` from the parking lot to a row** that ships after the verdict rule (P7).
6. **Keep (b).** Amend criterion 1 with the decoding-step wording (P5). Add the `typeToSort` clause and the `Response` regression gate (P6).
7. **Repair the examples** (P8) and close risk 3 with W5 and W6 (P9).
8. **Ship order.** `BITWISE-1` (exact forms only) and `CHAR-CODE-1` can ship first, as Rev 0 proposes. Neither needs the verdict rule to be sound; both gain from it later with no surface change. Ship the verdict rule before `BYTES-UNSIZED-1`. Then ship `BYTES-UNSIZED-1`, `BYTES-READ-1` and `BYTES-WRITE-1` in one release, so the `Response` break happens once and the arm never exists without its value type. Ship `BITWISE-WIDTH-1` and `FFI-BYTES-1` after that, in either order.

## Open questions for the language-team

1. Specify the classification of "abstracted term" as a syntactic predicate on the emitted VC. State whether a `RespFact.hs` arm fact counts as an abstraction. It is a true but incomplete fact about a builtin result, so by the rule above it should.
2. Specify the trigger set for the `BITWISE-WIDTH-1` width fact: which ground `w` values are instantiated, and whether the fact is emitted per `band` term or per function.

## Follow-up review — Rev 1 P1 narrowing (2026-10-31)

**Verdict: accept with change.** The count condition is correct. Its scope is too narrow. Rev 1 applies the count only to uncontracted callees and function-typed parameters. A contracted callee has the same encoding, so it has the same defect.

### Restatement

Rev 1 "Part 0", clause 2, makes an opaque call result abstracted only when the VC holds two or more calls to the same callee. The list "These are **not** abstracted" exempts "the result of a contracted callee under assume-guarantee" without a count. The question is whether a single-call UNSAFE is a true refutation, and whether the two-call condition covers every case where the encoding is weaker than the semantics.

### Context located

1. `docs/design/byte-io-proposal.md` Rev 1, "Part 0": clause 2, the "not abstracted" list, and "Why one opaque call is not abstracted".
2. `compiler/src/LLMLL/FixpointEmit.hs`, `bodyToPredM`, the contracted-callee branch: it returns a `CallVC` with `cvResultVar = resultVar`, a fresh `_call_g_N` binder per call site, and the callee post as `cvPostAssumption`. No equality between two call binders is emitted.
3. `LLMLL.md` §5.3.3, "Opaque calls add no symbol": an uncontracted call is a fresh binder; two equal calls get unrelated binders.
4. `LLMLL.md` §4.4.1, the `refuted` note: "disproved"; a caller gets `depends-on-refuted` because "its assume-guarantee proof rests on a postcondition known to be false".
5. `LLMLL.md` §0 (anchor `nc-005`): the caller proves the callee `pre` and assumes the callee `post`.
6. `docs/compiler-team-roadmap.md`, row `CALL-CONGRUENCE-1`: describes only uncontracted and parameter callees. Its cheap form is CSE in `aNormalizeBody`.
7. `docs/design/fn-param-uf-1-proposal.md` Rev 0, witness table: W3 (true refutation), W5 (false refutation), W6 (true refutation; the parameter's return refinement is not assumed).

### Witnesses (llmll 0.33.2)

In each case `g` is `(def-shell g [x: int] -> int (post (>= result 0)) (if (< x 0) (- 0 x) x))`. It is contracted and verifies body-faithful.

| ID | Caller | Today | Concrete truth | Rev 1 |
|---|---|---|---|---|
| A1 | `h [a: int]`, post `(= result 0)`, body `(- (g a) (g a))` | refuted | true | **refuted (false)**: `g` is contracted, so it is exempt |
| A2 | `h8 [a: int b: int]`, post `(>= result 0)`, body `(if (= a b) (- (g a) (g b)) 0)` | refuted | true | **refuted (false)**. CSE in `aNormalizeBody` does not fix this, because `a` and `b` differ as syntax |
| A3 | `h1 [a: int]`, post `(>= result (- 0 a))`, body `(g a)` | refuted | true | refuted: correct under the modular reading (P16) |
| A4 | `fib`-shaped `f [n: int]`, pre `(>= n 0)`, post `(>= result 0)`, body `(if (< n 2) n (- (f (- n 1)) (f (- n 2))))` | refuted | false (`f 4 = -1`) | refuted. Under the P15 rule it becomes the fallback outcome |
| A5 | post `(= result (g a))`, body `(g a)` | caller falls back | — | not affected: a call in a contract is outside the fragment |
| A6 | `(string-length "abc")` and `(string-length (string-concat s "x"))` | fall back, `Refused by: app:string-length` | — | not affected |

### Findings

**P15. The count condition must cover every call encoded as a fresh binder, contracted or not.** Severity: blocking. Class: soundness of the claim (not of SAFE).

Rev 1 says two calls make the encoding weaker than the semantics "for every contract". That argument does not depend on whether the callee has a contract. `bodyToPredM` gives a contracted call the same fresh binder as an uncontracted one. It adds only the callee post. So A1 and A2 report `refuted` on true posts, and `verify` exits 1. Rev 1's exemption keeps both false refutations. The exemption must apply only to a single call.

The cost of the wider rule is A4. A recursive function with two self-calls, or any function with two calls to one contracted callee, loses `refuted` on UNSAFE. It gets the fallback outcome. This loses information and does not lose soundness. The wider rule keeps W3, W6 and every single-call refutation.

**P16. `refuted` is a modular verdict. Single-call UNSAFE is a correct modular refutation.** Severity: major. Class: spec drift.

Under assume-guarantee (`LLMLL.md` §0, `nc-005`), the caller is checked against the callee contracts that the verifier assumes. The callee bodies are not used. So `refuted` must mean this: some implementation of each callee that satisfies its assumed contract makes the caller's obligation fail. It does not mean a concrete bug. A3 shows the difference. The program is correct, but `g`'s post is weaker than its body. This is the standard reading in Dafny and in Liquid Haskell. Neither tool claims that a modular failure is a concrete bug. A concrete claim needs a must-analysis (Godefroid, Nori, Rajamani and Tetali, *Compositional May-Must Program Analysis*, POPL 2010).

With one call to each callee, the fresh binder is exact for this meaning. Take a solver countermodel with argument `x` and result `v`. The value `v` satisfies the callee post at `x`. A function that returns `v` at `x` and any contract-allowed value elsewhere satisfies the contract. It realizes the counterexample. With two calls whose arguments are equal in the countermodel, no single function can return two different values. So the countermodel can be unrealizable. That is the reason for the count, and it is the congruence (functionality) axiom of uninterpreted functions. The fresh-binder encoding omits that axiom. A real UF application in the solver would supply it.

Two wording defects follow. First, Rev 1 says `refuted` "is relative to stated contracts". W6 shows that a stated return refinement on a function-typed parameter is not assumed. The correct phrase is "relative to the callee contracts that the verifier assumes". Second, `LLMLL.md` §4.4.1 says a refuted function is "disproved" and that `depends-on-refuted` rests on "a postcondition known to be false". A3 shows that both claims are too strong. The documentation-lead should restate `refuted` as a modular disproof: the post does not follow from the body and the assumed callee contracts. The `depends-on-refuted` text should say "a postcondition not established", not "known to be false".

**P17. No single-occurrence abstraction outside Rev 1's clause 1 gives a false `refuted`.** Severity: none. Class: confirmation.

1. A builtin with true but incomplete facts is abstracted at one occurrence by clause 1, with no count. That is correct. One partial reflection is already weaker than the semantics, because the builtin has an exact meaning that the facts do not state.
2. A single call through a function-typed parameter (FN-PARAM-UF-1) is exact under P16. The parameter is universally quantified at its declared type without refinement. W3 and W6 are correct refutations.
3. The builtins that `Σ_auto` leaves uninterpreted make the caller fall back today (A6). They never reach the solver, so they cannot be refuted.
4. Measures such as `strLen` are function symbols in the `.fq` file. The solver applies congruence to them, so they do not have the fresh-binder defect.
5. A call inside a contract makes the function fall back (A5).
6. A `RespFact.hs` arm fact constrains a free parameter binder. Rev 1's answer to open question 1 is correct, and it changes my earlier position. A true fact on a free value removes counterexamples and adds none.

One side condition remains, and it does not need a rule. The realizer in P16 needs the callee contract to allow some result at every input that satisfies its `pre`. If the contract allows no result at some input, the assumption is `false` there, and the solver reports SAFE, not UNSAFE. So an unrealizable contract cannot produce a false `refuted`. That callee fails its own body VC or falls back, and the existing trust machinery reports it.

**P18. Ackermann constraints are a better cheap form for `CALL-CONGRUENCE-1` than CSE.** Severity: minor. Class: scope (not required to settle).

For each pair of calls to one callee in one constraint environment, emit the hypothesis `(args_i = args_j) ⇒ (r_i = r_j)`. The formula is quantifier-free and needs no new symbol (Ackermann, *Solvable Cases of the Decision Problem*, 1954; Bryant, German and Velev, ACM TOCL 2(1), 2001; Kroening and Strichman, *Decision Procedures*, ch. 4). With these hypotheses, the multi-call encoding is exact under P16. W5, A1 and A2 then verify, and A4 keeps `refuted`. CSE fixes A1 and W5 only. A pair whose argument is a function value, or whose argument sort has no equality in the `.fq` file, gets no hypothesis and stays abstracted under clause 2. If `CALL-CONGRUENCE-1` adopts this form, clause 2 shrinks to those pairs. This decision belongs to that row, and its trigger now has measured witnesses (A1, A2).

### Recommended rule text

Replace clause 2 of "Abstracted term" in Rev 1 "Part 0" with:

> 2. It is the result binder of a call that the VC encodes as a fresh binder: a call to a named callee, contracted or uncontracted, including a self-call or a call to a member of the same recursive cycle, or a call through a function-typed parameter. The VC must also hold two or more such calls to the same callee. Calls are counted in the constraint's environment, and the arguments are not compared.

Replace the entry "the result of a contracted callee under assume-guarantee" in the "not abstracted" list with:

> the result of the only call to a callee in the VC, contracted or not.

Change "`refuted` is relative to stated contracts" to "`refuted` is relative to the callee contracts that the verifier assumes".

### What the proposal must add to settle

1. Add A1, A2 and A4 to the fixtures in "Verdict changes to existing programs". A1 and A2 move from `refuted` to the fallback outcome. A4 also moves, and the record must state this cost.
2. Widen the `CALL-CONGRUENCE-1` row text to include contracted callees, and record A2 as the witness that CSE does not cover. Note P18 as the candidate cheap form.
3. Route P16's wording change for `LLMLL.md` §4.4.1 to the documentation-lead as a new drift item.

After these three changes, I have no open item. The proposal can settle.
