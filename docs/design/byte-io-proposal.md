---
title: BYTE-IO — byte read and write, an unsized byte type, character codes and bitwise operations
status: Rev 2, SETTLED 2026-10-31 (user-approved). Rev 2 adopts the professor's follow-up review of the Rev 1 P1 narrowing (P15–P18, verdict "accept with change"). The user settled shape (b) and the ship order on 2026-10-31, and approved settlement the same day.
rows: CHAR-CODE-1, BYTES-READ-1, BYTES-WRITE-1 (existing, DECIDE → PLAN); BITWISE-1, ABSTRACTION-VERDICT-1, BYTES-UNSIZED-1 (absorbs BYTES-PARTIAL-REFLECT-1), BITWISE-WIDTH-1, FFI-BYTES-1 (new, PLAN); BYTES-NARROW-1, BYTES-SLICE-CONTENT-1 (new, Trigger-gated Parking Lot)
review: two professor passes (of Rev 0 and of the Rev 1 P1 narrowing, 2026-10-31), folded below as the Appendix; the standalone file is archived at docs/archive/professor-reviews/byte-io-review.md
---

# BYTE-IO — byte read and write, an unsized byte type, character codes and bitwise operations

**Status: Rev 2, SETTLED 2026-10-31.** The user approved the design work on 2026-10-30. The professor reviewed Rev 0 on 2026-10-31 with the verdict "settle with changes". Rev 1 addressed every finding P1–P14. The professor then reviewed the Rev 1 P1 narrowing with the verdict "accept with change" (P15–P18). Rev 2 makes that change. The user settled the two open decisions of Rev 0 and approved settlement on 2026-10-31. Both review passes are folded below as the [Appendix](#appendix--professor-review-log).

## Decisions (settled by the user, 2026-10-31)

1. **Shape (b) for the transport.** The read delivers a sixth `Response` arm, `RBytes bytes`. Alternative (c), hex text on `RText`, is rejected. The professor's P5 strengthens the reason: (c) adds a dead `Error` branch to every reader that no channel discharges.
2. **Ship order.** Four steps, in this order. The section "Implementation sequence" gives one row per step.
   1. `BITWISE-1` and `CHAR-CODE-1`.
   2. The abstraction verdict rule, as its own row, `ABSTRACTION-VERDICT-1`.
   3. `BYTES-UNSIZED-1`, `BYTES-READ-1` and `BYTES-WRITE-1` in one release. So the `Response` break happens once, and the arm never exists without its value type.
   4. `BITWISE-WIDTH-1` and `FFI-BYTES-1`, in either order.

## Changes from Rev 1

The professor's follow-up review of the Rev 1 P1 narrowing gave the verdict "accept with change". Rev 2 makes these changes. No other part of Rev 1 changes.

| Review item | Disposition | Where |
|---|---|---|
| P15 (blocking): the count condition must cover every call that the VC encodes as a fresh binder, contracted or not | **Adopted.** Clause 2 of "Abstracted term" is the professor's text. The exempt-list entry becomes "the result of the only call to a callee in the VC, contracted or not". | "Part 0" |
| P15, cost: a function with two calls to one contracted callee, or two self-calls, loses `refuted` on UNSAFE | **Adopted and stated.** Witnesses A1, A2 and A4 are fixtures of step 2. A1 and A2 are a false `refuted` on llmll 0.33.2 today. A4 is a true `refuted` that becomes the fallback outcome. | "Part 0, verdict changes"; edge cases 26, 27, 28 |
| P16: `refuted` is a modular verdict | **Adopted.** "Relative to stated contracts" becomes "relative to the callee contracts that the verifier assumes". The `LLMLL.md` §4.4.1 wording is drift D7, routed to the documentation-lead and the language-team. | "Part 0"; drift D7 |
| P17: no other single-occurrence abstraction gives a false `refuted` | **Noted.** No change. It confirms the Rev 1 answer on `RespFact.hs` arm facts. | — |
| P18: Ackermann hypotheses as the cheap form of `CALL-CONGRUENCE-1` | **Recorded as the recommended next form of `CALL-CONGRUENCE-1`.** Not needed for settlement. The row text widens to contracted callees. | "Part 0, what stays open"; "Proposed roadmap rows" |

## Changes from Rev 0

| Review item | Disposition | Where |
|---|---|---|
| P1 (blocking): `bytes-slice` and `string-code-at` preconditions are runtime-only | **Adopted.** The abstraction verdict rule is a new part and its own row, `ABSTRACTION-VERDICT-1`. The length and range facts ship in v1. `BYTES-PARTIAL-REFLECT-1` leaves the parking lot and is absorbed into `BYTES-UNSIZED-1`. **Adapted in one point:** a call result counts as abstracted only when the VC holds two or more calls to the same callee. One call is the exact modular meaning, so a single-call `refuted` stays. Rev 2 widens the count to contracted callees (P15). | "Part 0"; "Part 4, partial reflection"; "Verification mapping" |
| P2 (blocking): `bytes-widen` must not assert `bytesLen(r) = n` | **Adopted.** `(bytes-widen b)` reflects as `⟦b⟧`. No assumed post. The codegen claim is disclosed as an axiom. | "Part 4, typing"; "Verification mapping" |
| P3: the exact forms do not need non-negativity | **Adopted.** The soundness argument is restated for all integers (W1). The `a ≥ 0` precondition stays, as a specification choice. `k ≥ 0` stays for both shifts (W4). | "Part 5" |
| P4: mask `−1` and shift size | **Adopted.** The mask is recognized on the folded value with `m ≥ 0`. A ground shift reflects only when `c ≤ 4096`. Above that, the caller falls back with `Refused by: app:bit-shl` or `app:bit-shr`. | "Part 5"; edge cases 19, 20 |
| P5: criterion 1 on the shape reading | **Adopted.** Criterion 1 reads "not expressible by an existing arm without a decoding step that can fail". The amendment to the effect-response-channel record routes to the documentation-lead. | "Part 1"; "Findings routed to other owners" |
| P6: `typeToSort` defaults to `FQInt` | **Adopted, and widened.** The new type gets explicit `typeToSort` and `typeToSortA` clauses at `byteArraySort`. A regression gate covers every in-tree `Response` match. Reading found that `TBytes n` has the same default today (D6). | "Part 1, engineering risk"; "Affected surface" |
| P7: `BITWISE-WIDTH-1` is admissible | **Adopted.** It leaves the parking lot and is step 4. The professor's question on the trigger set is answered: one width fact per `band` term, for each `w` whose `2^w` or `2^w − 1` is a ground constant in the function's contract. | "Part 6" |
| P8: `and` takes two arguments | **Adopted.** Every multi-clause `and` is nested. The existing-surface parts of the examples were run through `check` and `verify` on llmll 0.33.2. | "Worked examples" |
| P9: `rotl32-7` proves | **Adopted.** Risk 3 is removed. W5 and W6 become `BITWISE-1` fixtures. | "Worked examples"; "Risks" |
| P10: `bytes-from-string` length bounds | **Adopted.** `strLen(s) ≤ bytesLen(r) ≤ 4 · strLen(s)` is the only length fact. D2 stays routed. | "Part 4, partial reflection" |
| P11: CHAR-CODE-1 result range | **Adopted.** The range fact is `0..1114111` with no surrogate hole. The index is compared as `Integer` before `!!`. | "Part 3" |
| P12: `LLMLL.md` line 13 contradicts `SIGMA-CONST-ARITH-1` | **Adopted as drift D5**, routed to the documentation-lead. | "Findings routed to other owners" |
| P13: two stdio edge cases | **Adopted.** A second `wasi.io.stdin-bytes` delivers `RBytes` of length 0. Text and byte writes to standard output keep command order. Both get fixtures. | "Part 1"; "Part 2"; edge cases 21, 22 |
| P14: citation drift and census | **Adopted.** Compiler citations name functions, not lines. The census is re-measured: 65 arms in 24 files. | "Context located"; "Part 1, cost" |
| Open question 1 to the language-team: what is an abstracted term; does a `RespFact.hs` arm fact count | **Answered, with a divergence.** The predicate is syntactic and is stated in "Part 0". An arm fact does **not** count. Its subject is a delivered parameter, and a fact on a parameter only removes counterexamples. | "Part 0" |
| Open question 2 to the language-team: the width-fact trigger set | **Answered.** | "Part 6" |
| Self-found R1: Rev 0 called `b64-group` "fully verified" | **Corrected.** Measured: `b64-group` falls back (`Refused by: app:string-concat` or `app:string-char-at`), and a function with no `post` proves nothing. The index arithmetic moves to `b64-sextet`, which verifies. | "Worked examples" |
| Self-found R2: Rev 0 edge case 14 said `check` refuses `(bit-shl x -1)` | **Corrected.** Measured: `check` accepts a literal negative index on `bytes-get` today. There is no check-time literal fold for builtin preconditions. | edge case 14 |

## Restatement

LLMLL cannot read or write a byte that is not UTF-8 text. It cannot hold a byte sequence whose length is unknown at compile time. It cannot convert a character to its code point, and it has no bitwise operators. So a programmer cannot write a PNG or PPM codec, base64, CRC32, ChaCha20 or a compressor in the language. This record designs six parts:

0. **ABSTRACTION-VERDICT-1** (new tag, from P1): an UNSAFE VC that contains an abstracted term reports the fallback outcome, not `refuted`.
1. **BYTES-READ-1**: a byte-level read from a file and from standard input.
2. **BYTES-WRITE-1**: a byte-level write to a file and to standard output.
3. **CHAR-CODE-1**: `string-code-at` and `string-from-code`.
4. **BYTES-UNSIZED-1** (new tag): an unsized `bytes` type, its operations, its partial reflection and its relation to `bytes[n]`.
5. **BITWISE-1** (new tag): `bit-and`, `bit-or`, `bit-xor`, `bit-shl` and `bit-shr`, with three exact reflections.
6. **BITWISE-WIDTH-1** (new tag, from P7): range and width facts for the non-exact bitwise forms.

The read and the write use one shape. The roadmap requires this (`BYTES-WRITE-1`, Next Action).

**Two reference classes.** The measurement set is the MultiLangBench SQLite task and the TOOL-RFC-006 port, which spawns `od` and `printf` because the language cannot touch bytes. The design-reference set is the verified-language ecosystem. Dafny has `seq<bv8>` and bit-vector types. F\* has `FStar.Bytes` and machine integers. Liquid Haskell reasons over `ByteString` length through measures. LLMLL's choice is narrower than all three: unbounded `int`, exact reflection of the linear cases, and true but incomplete facts for the rest. Part 5 states the cost.

## Context located

- The professor review of Rev 0 (findings P1–P14, witnesses W1–W8) and the follow-up review of the Rev 1 P1 narrowing (findings P15–P18, witnesses A1–A6). Both are folded below as the Appendix.
- `docs/compiler-team-roadmap.md` rows `BYTES-READ-1`, `BYTES-WRITE-1`, `CHAR-CODE-1`, `FFI-OPAQUE-1`, `SIGMA-CONST-ARITH-1` (closed, v0.32.0), `FFI-CONV-1` (closed), `REPLAY-INJECT` (parked) and `CALL-CONGRUENCE-1` (Trigger-gated Parking Lot). No row names bitwise operations.
- `docs/compiler-team-roadmap.md` group G1, "The verdict: soundness and disclosure": the home of `ABSTRACTION-VERDICT-1`. `TRUST-REFUTED-PERSIST-1` is in the same group.
- `docs/design/fn-param-uf-1-proposal.md` Rev 0, "Congruence": the source of `CALL-CONGRUENCE-1` and its witness W5.
- `docs/design/multilangbench-scope-evaluation.md` Rev 2: fixes four points for shape (b). This record keeps all four.
- `docs/design/collect-order-1-proposal.md` Rev 0: `string-code-at` must agree with `string-compare` on one-character strings.
- `docs/design/ffi-tier1-proposal.md` Rev 3, D10 and the reach table: `ByteString` waits on an unsized byte type.
- `docs/design/effect-response-channel-proposal.md`, "An arm is admissible iff all four hold": the four-part arm rule.
- `LLMLL.md` §3.1: `int` is unbounded; a QF-BV `machine-int` opt-in is future work. §3.2: `bytes[n]` only; `Response` has five arms.
- `LLMLL.md` §4.4.1, the `refuted` note: `refuted` means disproved, and a caller of a refuted callee gets `depends-on-refuted`.
- `LLMLL.md` §5.3.3: `Σ_auto`; constant arithmetic (`SIGMA-CONST-ARITH-1`); the array class over `bytes[n]`; the list of uninterpreted builtins that fall back with `Refused by: app:<name>`; "Opaque calls add no symbol".
- `LLMLL.md` §9.7: `Response`; "arms classify shape, not provenance"; bulk payloads travel through the filesystem.
- `LLMLL.md` §13.6, §13.9, §13.11 ("Variable-length byte types … are deferred"), §13.12 (the closed sealed-builtin axiom set), the Tier 1 reach table.
- `compiler/src/LLMLL/TypeCheck.hs`: `builtinEnv` (`wasi.fs.read`, `wasi.fs.write`, `wasi.fs.sha256`, the five `Response` constructors, the comment "A new Response arm would break every exhaustive match on Response"); `inferArrayOp`; `compatibleWith` (the `TBytes m` against `TBytes n` case).
- `compiler/src/LLMLL/TypeAdmissibility.hs`, `builtinAliases`: the `Response` sum; its comment says "There is deliberately no RBytes arm".
- `compiler/src/LLMLL/CodegenHs.hs`: `data Response`; `wasi_fs_read` and `wasi_fs_write` (UTF-8 pins); `wasi_fs_sha256` (`BS.readFile`); the `bytes_*` preamble over `[Word8]` (index checked as `Integer`); `toHsType`; `captureStdout`; the console and cli `main` bodies; `string_compare`.
- `compiler/src/LLMLL/FixpointEmit.hs`: `byteArraySort`; the four readers of `TBytes n` by head syntax; the `bytes-get` and `bytes-set` reflection; `wholeArrEqClause`; `typeToSort` and `typeToSortA` (no clause for any byte type, default `FQInt`); `admissiblePayload` (only `int`, `bool`, `string`); `admissibleDatatype`; `buildCtorSums`; `injectRangeFacts`; `bytesLenParamPre`; `bytesLenRetPost`; the FACT-AG-LEN comment above `reifyBytesZeroLen`.
- `compiler/src/LLMLL/RespFact.hs`: per-arm facts on delivered `Response` binders, opt-in by a fact request.
- `compiler/src/LLMLL/Contracts.hs`, `builtinCtorNames`.
- `compiler/src/LLMLL/Parser.hs`, `pBytesType` (requires `[n]`); `compiler/src/LLMLL/ParserJSON.hs` (kind `bytes` reads `length`).
- `docs/llmll-ast.schema.json`, `TypeBytes.length` with `"minimum": 1`.

**Drift found during reading.** Each item is a finding. None is repaired here. The section "Findings routed to other owners" names the owner of each.

- **D1. Schema against parser.** `docs/llmll-ast.schema.json` `TypeBytes` declares `"length": {"minimum": 1}`. `LLMLL.md` §3.2 and `pBytesType` accept `bytes[0]`. A JSON-AST program with `bytes[0]` is valid to the compiler and invalid to the schema. The professor confirmed this. The schema should move to `"minimum": 0`.
- **D2. `string` is described as bytes.** `LLMLL.md` §3.1 calls `string` an "Immutable UTF-8 byte sequence". The runtime is a Haskell `String`, a sequence of code points. §13.2 and §13.6 agree with the runtime. §3.1 should say "sequence of Unicode code points, written as UTF-8 at the IO boundary". P10 shows the cost: a reader of §3.1 would assume `bytesLen(bytes-from-string s) = strLen(s)`, which is false for non-ASCII text.
- **D3. `CHAR-CODE-1` cites a precondition that does not exist.** The row says `string-code-at` "takes `string-char-at`'s index `pre`". `string-char-at` has no `pre`. It is total and answers `""` out of range (§13.6). This record gives `string-code-at` a real `pre` (part 3).
- **D4. The `Response` arm comment is a design input.** The `TypeCheck.hs` comment and the `TypeAdmissibility.hs` comment record that a sixth arm breaks every exhaustive match. That is correct. Part 1 measures the cost. No routing is needed. The comments change when step 3 ships.
- **D5. `LLMLL.md` §0 contradicts §5.3.3 (P12).** The summary near the top of `LLMLL.md` says `Σ_auto` is linear integer arithmetic "without `*`, `/` or `mod`". §5.3.3 admits them with a ground constant (`SIGMA-CONST-ARITH-1`). `BITWISE-1` adds three more constant forms, so the summary becomes more wrong.
- **D6. `typeToSort` has no clause for `TBytes n`.** Found by reading while checking P6. `typeToSort` has clauses for `int`, `bool`, `string`, lists, `Json`, `float`, dependent types and pairs, and defaults to `FQInt`. A user sum with a `bytes[n]` payload passes `admissibleDatatype`, because a non-sum payload is a leaf. So `buildCtorSums` and `typeSorts` can declare that field at `int` today. A match that uses the payload falls back through `admissiblePayload`, so no array value meets the `int` field. This is the class of trap that the `JSON-1` and `FLOAT-LIT-1` comments in `typeToSort` describe. Not measured with a witness; the engineer confirms it.
- **D7. `LLMLL.md` §4.4.1 overstates `refuted` (P16).** The `refuted` note says a refuted function is "disproved". It says `depends-on-refuted` rests on "a postcondition known to be false". Under assume-guarantee, `refuted` is modular. It is relative to the callee contracts that the verifier assumes, not to the callee bodies. Witness A3 is a correct program that is `refuted`, because `g`'s post is weaker than its body. The note should restate `refuted` as a modular disproof: the post does not follow from the body and the assumed callee contracts. The `depends-on-refuted` text should say "a postcondition not established".

## Design proposal

### Summary of the recommended shape

| Part | Recommendation |
|---|---|
| 0. Verdict | An UNSAFE VC that contains an abstracted term reports the fallback outcome with cause `abstraction:app:<name>`, not `refuted`. A SAFE VC reports `verified`, as today. |
| 1. Read | Shape (b): `wasi.fs.read-bytes : string -> Command` and `wasi.io.stdin-bytes : Command`, which deliver a new arm `RBytes bytes`. |
| 2. Write | The same shape: `wasi.fs.write-bytes : string bytes -> Command` and `wasi.io.stdout-bytes : bytes -> Command`, which deliver `RNone` or `RErr`. |
| 3. Character codes | `string-code-at : string int -> int` with an index `pre`, and `string-from-code : int -> string` with a code-point `pre`. After step 2, both carry true but incomplete facts. |
| 4. Unsized bytes | A new type `bytes`, separate from `bytes[n]`, compiled to strict `Data.ByteString.ByteString`. `bytes-widen` reflects as the identity. Five operations carry exact length or range facts. |
| 5. Bitwise | Five operations over `int`. Shifts by a ground constant `c ≤ 4096` and `bit-and` with a ground mask `2^w − 1 ≥ 0` reflect exactly. Every other form falls back in step 1. |
| 6. Bitwise facts | After step 2, `bit-and` becomes one uninterpreted function `band`. `bit-or` and `bit-xor` become exact linear terms over `band`. Range and width facts make 32-bit range posts provable. |

### Part 0: the abstraction verdict rule (ABSTRACTION-VERDICT-1)

**Problem.** The verifier can reflect an operation exactly, or it can make the caller fall back. A third choice exists: reflect a fresh term with true but incomplete facts. That reflection is an over-approximation of the program, so SAFE is sound (Clarke et al., CAV 2000). But UNSAFE then means "the abstraction admits a counterexample", not "the program has one". `LLMLL.md` §4.4.1 defines `refuted` as disproof. So today a partial reflection can report a true post as `refuted`. `CALL-CONGRUENCE-1` is an existing case of that defect. Rev 0 avoided the defect by fallback, and P1 shows the cost: the `bytes-slice` and `string-code-at` preconditions became runtime-only.

**Abstracted term.** A term of the emitted VC is *abstracted* when one of these holds:

1. It is the application of a sealed builtin that this record reflects by true but incomplete facts. The v1 set is `bytes-slice`, `bytes-concat`, `bytes-concat-many`, `bytes-to-list`, `bytes-from-string`, `string-code-at` and `string-from-code`. `BITWISE-WIDTH-1` adds `band`.
2. It is the result binder of a call that the VC encodes as a fresh binder: a call to a named callee, contracted or uncontracted, including a self-call or a call to a member of the same recursive cycle, or a call through a function-typed parameter. The VC must also hold two or more such calls to the same callee. Calls are counted in the constraint's environment, and the arguments are not compared.

These are **not** abstracted: a parameter; a `match` binder of a parameter; the result of the only call to a callee in the VC, contracted or not; an exact reflection (the three bitwise forms, `bytes-get`, `bytes-set`, `bytes-length`, `bytes-make`, `bytes-widen`, constant arithmetic); a binder that carries a `RespFact.hs` arm fact.

**Why one call is not abstracted (adaptation of P1, widened by P15).** The professor's Rev 0 rule treats every opaque call result as abstracted. This record narrows it to a count. A single fresh binder at a call stands for "any value the callee's contract allows". That is the exact modular meaning. `refuted` is relative to the callee contracts that the verifier assumes (P16). The user can strengthen a callee contract and change the verdict. Two calls are different. The encoding gives them unrelated binders, but every LLMLL function is pure, so equal arguments give equal results. The encoding then omits the congruence axiom, and it is weaker than the semantics for every contract.

The count does not depend on whether the callee has a contract (P15). `bodyToPredM` in `compiler/src/LLMLL/FixpointEmit.hs` gives a contracted call the same fresh `_call_g_N` binder as an uncontracted call. It adds only the callee post as an assumption. No equality between two call binders is emitted. So W5 of `fn-param-uf-1` (two calls to `le`) and witnesses A1 and A2 (two calls to a contracted `g`) move to the fallback outcome. W3 (one call, false post) stays `refuted`. The count keeps every single-call refutation. It loses no soundness, because the condition only decides between `refuted` and the fallback outcome.

**Why an arm fact is not abstracted (answer to the professor's open question 1).** A `RespFact.hs` fact constrains the payload binder of a delivered `Response`. That binder is a parameter of the step. Without the fact it is free, and a free parameter is universally quantified under the step's `pre`. A true fact on a free value can only remove counterexamples. It cannot create one. The abstracted element in the professor's argument is the fresh term itself, not the fact on it.

**The bit.** Each fixpoint constraint gets one bit: "contains an abstracted term". The bit is set when the constraint's head, or a binder in its environment, is or is defined by an abstracted term. The bit is syntactic. The engineer may compute it over the binders that share an atom with the head, transitively (the cone of influence). The narrower form keeps more refutations. The coarser form, the whole environment, is also correct, because a false positive only changes `refuted` to the fallback outcome.

**The verdict map.**

| Solver | Bit clear | Bit set |
|---|---|---|
| SAFE | `verified` | `verified` |
| UNSAFE | `refuted`, as today | the fallback outcome, cause `abstraction:app:<name>` |

The fallback outcome is the one `erBodyFallback` gives today. The post is assumed, not proved. The trust level comes from `check`/`for-all` (`tested`) or is `asserted`. `W-BODY-FALLBACK` names the first abstracted term as `Refused by: abstraction:app:<name>` (`FALLBACK-ATTRIB-1` attribution). A caller does not get `depends-on-refuted`. `verify` does not exit 1 for this function. `--strict-verified-core` refuses the outcome, as it refuses `erBodyFallback`. The rule applies to every constraint of the function, the post and each call-pre alike. A call-pre in this outcome is reported on the existing `call-pre unchecked` edge line, and the runtime assertion stays.

**Strict improvement over Rev 0 for builtins.** Every function that falls back under Rev 0 because it calls one of the v1 set either verifies or gets the same fallback outcome. No function moves to `refuted` because of a builtin.

**Verdict changes to existing programs.** The rule changes verdicts that exist today. Each change goes from `refuted` to the fallback outcome, and only where a VC holds two calls to one callee, contracted or not. `CALL-CONGRUENCE-1` W5 changes. The `fn-param-uf-1` fixtures W5, W6 and MMF-6 must be re-measured, and their expected verdicts change where the condition holds.

Step 2 adds three fixtures from the professor's follow-up review, measured on llmll 0.33.2. In each, `g` is `(def-shell g [x: int] -> int (post (>= result 0)) (if (< x 0) (- 0 x) x))`. `g` is contracted and verifies body-faithful.

| ID | Caller | Today (0.33.2) | Concrete truth | Expected under this rule |
|---|---|---|---|---|
| A1 | `h [a: int]`, post `(= result 0)`, body `(- (g a) (g a))` | `refuted` | true | fallback outcome, `Refused by: abstraction:app:g` |
| A2 | `h8 [a: int b: int]`, post `(>= result 0)`, body `(if (= a b) (- (g a) (g b)) 0)` | `refuted` | true | fallback outcome, `Refused by: abstraction:app:g` |
| A4 | `f [n: int]`, pre `(>= n 0)`, post `(>= result 0)`, body `(if (< n 2) n (- (f (- n 1)) (f (- n 2))))` | `refuted` | false (`f 4 = -1`) | fallback outcome, `Refused by: abstraction:app:f` |

**A1 and A2 are a false `refuted` in llmll 0.33.2 today.** Both posts are true, and `verify` exits 1 on both. The rule corrects them. CSE in `aNormalizeBody` corrects A1 and does not correct A2, because `a` and `b` differ as syntax. **A4 is the cost of P15.** Its post is false, and the rule replaces a correct `refuted` with the fallback outcome. A recursive function with two self-calls, and any function with two calls to one contracted callee, loses `refuted` on UNSAFE in the same way. The loss is information, not soundness. The engineer decides whether `checker_soundness_version` changes. A `refuted` verdict saved before the change can be incorrect after it (see `TRUST-REFUTED-PERSIST-1`).

**What stays open in `CALL-CONGRUENCE-1`.** The rule closes its claim-accuracy half: a true post is no longer `refuted`. The completeness half stays: the posts of W5, A1 and A2 are still not proved. The row text must widen to cover contracted callees, because A1 and A2 have the same encoding defect as W5. The documentation-lead applies that roadmap edit at settlement.

**Recommended next form of `CALL-CONGRUENCE-1` (P18).** For each pair of calls to one callee in one constraint environment, emit the hypothesis `(args_i = args_j) ⇒ (r_i = r_j)`. This is Ackermann's reduction (Ackermann 1954; Bryant, German and Velev, ACM TOCL 2(1), 2001). The formula is QF-LIA and needs no new symbol. With these hypotheses, the multi-call encoding is exact under the modular reading. W5, A1 and A2 then verify, and A4 keeps `refuted`. CSE fixes only A1 and W5. A pair whose argument is a function value, or whose argument sort has no equality in the `.fq` file, gets no hypothesis and stays abstracted under clause 2. If the row adopts this form, clause 2 shrinks to those pairs. This form is the recommended next step for the row. Settlement of this record does not need it. The row stays trigger-gated, and its trigger now has measured witnesses (A1, A2).

**First builtin consumers.** Step 2 ships the facts for `string-code-at` and `string-from-code` (part 3). They are the first builtins on the rule, and they need no new type. The bytes facts ship with the type in step 3. The `band` facts ship in step 4.

### Part 4 first: the unsized `bytes` type (BYTES-UNSIZED-1)

Parts 1 and 2 need a value type before they need a command. So the type comes first.

**Surface.** In S-expressions the type is the bare word `bytes`. `bytes[n]` keeps its meaning. In JSON-AST the type is a new kind:

```json
{ "kind": "bytes-unsized" }
```

A separate kind is chosen over an optional `length` key on kind `bytes`. With an optional key, a generator that drops `length` by mistake gets a different type and no schema error. With a separate kind, the dropped key stays a schema error (`TypeBytes` requires `length`). This follows the strict-keys direction of `AST-STRICT-KEYS-1`. The professor agrees.

**Representation.** `bytes` compiles to strict `Data.ByteString.ByteString`. The value is immutable, so strict immutability holds. `BS.index` and `BS.length` are O(1). `BS.take` and `BS.drop` are O(1) slices. The generated preamble already imports `qualified Data.ByteString as BS`. Every generated project already depends on `bytestring` through `cryptohash-sha256`. So the type adds no package.

**`bytes[n]` stays a separate type.** It keeps its `[Word8]` lowering (`toHsType`). Two reasons hold. First, rewriting `bytes[n]` as `{v : bytes | bytesLen v = n}` breaks the four readers that match `TBytes n` by head syntax. Second, it needs refinement subtyping, which `LLMLL.md` excludes (§0). The professor names this a scope divergence from Liquid Haskell, not a soundness defect. There is no implicit conversion in either direction.

**Typing.** The new type gets its own `Type` constructor. Its name is the engineer's choice.

```
Γ ⊢ b : bytes                         Γ ⊢ b : bytes[n]
──────────────────────────────        ──────────────────────────────────
Γ ⊢ (bytes-length b) : int            Γ ⊢ (bytes-widen b) : bytes

Γ ⊢ b : bytes    Γ ⊢ i : int          Γ ⊢ b : bytes   Γ ⊢ i : int   Γ ⊢ v : int
──────────────────────────────        ──────────────────────────────────────────
Γ ⊢ (bytes-get b i) : int             Γ ⊢ (bytes-set b i v) : bytes
```

`bytes` is not compatible with `bytes[n]` in `compatibleWith`. `bytes-zero` stays `bytes[n]`-only, because it reads its length from the declared return.

**`bytes-widen` reflects as the identity (P2).** `⟦(bytes-widen b)⟧ = ⟦b⟧`. `bytes` and `bytes[n]` share `byteArraySort` and the one `bytesLen` symbol, so the identity is exact. Every length fact that `b` has transfers by congruence. The reflection adds **no** assumed post. In particular it does not assert `bytesLen(r) = n`. A `let`-bound or `match`-bound `bytes[n]` value has no length fact (FACT-AG-LEN), and the widen must not give it one. The one trust item is the codegen claim that `BS.pack` keeps the bytes. That claim is of the same kind as the existing `bytes-get` axiom, and it is disclosed under `codegen-determined`.

**Operations.** The three existing operations become overloaded over `bytes[n]` and `bytes`. `inferArrayOp` already special-cases them. The preamble gains one class with two instances, so codegen keeps emitting one name per operation:

```haskell
class LlmllBytes b where
  bytes_length :: b -> Int
  bytes_get    :: b -> Integer -> Integer
  bytes_set    :: b -> Integer -> Integer -> b
instance LlmllBytes [Word8]       -- the existing bodies, unchanged
instance LlmllBytes BS.ByteString -- BS.length, BS.index, a copy with one byte replaced
```

This is the engineer's choice. It is shown only to fix one property: the `bytes[n]` path does not change. `emitApp` already converts `bytes_length` to `Integer`.

| Function | Signature | Precondition | Result |
|---|---|---|---|
| `bytes-length` | `bytes -> int` | — | The number of bytes. |
| `bytes-get` | `bytes int -> int` | `0 ≤ i < (bytes-length b)` | The byte at `i`, in `0..255`. |
| `bytes-set` | `bytes int int -> bytes` | `0 ≤ i < (bytes-length b)`, `0 ≤ v ≤ 255` | A copy with byte `i` replaced. O(n). |
| `bytes-make` | `int int -> bytes` | `n ≥ 0`, `0 ≤ v ≤ 255` | `(bytes-make n v)`: `n` copies of byte `v`. The **length comes first**. |
| `bytes-slice` | `bytes int int -> bytes` | `0 ≤ s ≤ e ≤ (bytes-length b)` | `(bytes-slice b s e)`: the half-open range `[s, e)`. O(1). |
| `bytes-concat` | `bytes bytes -> bytes` | — | `a` followed by `b`. |
| `bytes-concat-many` | `list[bytes] -> bytes` | — | All elements in order. O(total length). |
| `bytes-from-list` | `list[int] -> Result[bytes, int]` | — | `Success` when every element is in `0..255`. Otherwise `Error i`, where `i` is the index of the first element out of range. |
| `bytes-to-list` | `bytes -> list[int]` | — | Each byte as an `int`, in order. |
| `bytes-widen` | `bytes[n] -> bytes` | — | The same bytes. |
| `bytes-from-string` | `string -> bytes` | — | The UTF-8 encoding of the string. See the note below. |
| `bytes-to-string` | `bytes -> Result[string, int]` | — | `Success` when the bytes are valid UTF-8. Otherwise `Error k`, where `k` is the offset of the first byte of the first invalid sequence. |

**Partial reflection (P1; absorbs `BYTES-PARTIAL-REFLECT-1`).** Each of these reflects as a fresh term with the facts given. Each term is abstracted under part 0. Each fact is true of the runtime value and is disclosed as an assumed post under `codegen-determined`.

| Application | Fresh term | Facts |
|---|---|---|
| `(bytes-slice b s e)` | `r : byteArraySort` | `bytesLen(r) = e − s` |
| `(bytes-concat a b)` | `r : byteArraySort` | `bytesLen(r) = bytesLen(a) + bytesLen(b)` |
| `(bytes-concat-many xs)` | `r : byteArraySort` | `bytesLen(r) ≥ 0` (the measure gives it) |
| `(bytes-to-list b)` | `r : list` | `listLen(r) = bytesLen(b)` |
| `(bytes-from-string s)` | `r : byteArraySort` | `strLen(s) ≤ bytesLen(r) ≤ 4 · strLen(s)` (P10) |

The `bytes-slice` precondition `0 ≤ s ≤ e ≤ bytesLen(b)` is now a PROVE obligation at the call, which is the reason Rev 0 gave for a `pre` over a clamp. The ground content instances of a slice, `r[j] = b[s + j]` at each read of `r`, are true and sound under part 0. They are not in v1. They are filed as `BYTES-SLICE-CONTENT-1` in the parking lot. The exact content axiom quantifies over `j` with arithmetic on the bound variable, which is outside the array property fragment (Bradley, Manna and Sipma, VMCAI 2006).

`bytes-from-list` and `bytes-to-string` still make the caller fall back with `Refused by: app:<name>`. Their result is a `Result` with an array payload, and `admissiblePayload` admits only `int`, `bool` and `string`.

**Why `bytes-slice` has a `pre` and `string-slice` clamps.** Byte formats are offset arithmetic. A clamp converts an offset error into a short read, and the short read fails later and far away. A `pre` makes the error a PROVE obligation at the call. That is the polarity `bytes-get` already has (§13.12). The difference from `string-slice` is intentional, and the row text will say so.

**Why `bytes-from-list` returns `Result`.** "Every element is in `0..255`" quantifies over a list. It is not QF-LIA. A `pre` that the verifier cannot state would be a runtime-only obligation with no static channel. A `Result` makes the failure a value, which the type checker forces the caller to handle.

**`bytes-from-string` and lone surrogates.** A `string` can hold a lone surrogate. GHC decodes an undecodable byte `x` in argv or a directory name as U+DC00 + `x`, in the range U+DC80 to U+DCFF (`LLMLL.md` §7, the argv note). `bytes-from-string` maps such a code point back to the single byte `x`. So a path from `wasi.proc.args` converts to its original bytes. Any other lone surrogate encodes as U+FFFD (`EF BF BD`), the rule `hs-text` already uses. So each code point gives 1 to 4 bytes, which is the source of the P10 bounds. `bytes-to-string` is strict. It never produces a lone surrogate, and it refuses invalid UTF-8 with `Error`.

**Equality and order.** `=` and `!=` on `bytes` are byte-wise equality at run time. In the verifier, `=` over a `bytes` operand falls back to contract-only. This is the existing rule for `bytes[n]` and `map` (`wholeArrEqClause`). The array encoding carries unconstrained values outside `[0, n)`, so array equality is not observational equality. `bytes` is not an ordered type, so `compare` and `list-sort` refuse it. `bytes` is not a `map` key.

**Not in this record.** A byte literal syntax is not proposed. A conversion from `bytes` to `bytes[n]` is filed as `BYTES-NARROW-1` and deferred. When it ships, it takes the professor's form: a `pre` `bytesLen(b) = n` (PROVE), `n` from the determining context as for `bytes-zero`, reflection as the identity, and no `Result` form. `sha256`, `hmac` and other hash functions over `bytes` are not proposed.

### Part 1: the read (BYTES-READ-1)

**Shape (b), settled by the user on 2026-10-31.**

| Constructor | Signature | Capability | Response |
|---|---|---|---|
| `wasi.fs.read-bytes` | `string -> Command` | `(import wasi.fs (capability read PATH))` | `RBytes b` with the file's bytes, never decoded; `RErr` on any IO failure |
| `wasi.io.stdin-bytes` | `Command` (nullary) | `(import wasi.io (capability stdin))` | `RBytes b` with all of standard input to end of file; `RBytes` of length 0 when standard input is already consumed; `RErr` on IO failure, or when the program is not `:mode cli` |

**The new arm.**

```
Response ::= RNone | RText string | RCode int | RErr string | RList list[string] | RBytes bytes
```

**Admissibility under the four-part rule, with criterion 1 amended (P5).**

1. *Non-redundancy.* Amended reading: an arm is redundant only if an existing arm expresses the payload **without a decoding step that can fail**. Hex on `RText` needs `bytes-from-hex`, which returns a `Result`. Its `Error` arm cannot occur for runtime-produced hex. The verifier cannot know that, because `bytes-from-hex` is uninterpreted. So every reader would carry a dead branch that no channel discharges. On this reading `RBytes` is not redundant with hex, and `RCode` is not redundant with decimal text. The criterion passes.
2. *No fragment widening.* The payload type `bytes` reflects to the existing array sort. A match that names `RBytes` falls back, as a match that names `RList` does (§9.7 note). No new fragment is needed.
3. *File-indirection test.* The operation exists to bring file contents into the program. Routing the payload "through the filesystem" means reading the file, which is the operation itself. The test fails, so the arm is needed.
4. *Shape, not capability.* `RBytes` names a payload shape. Both read commands produce it.

**Runtime.** `wasi_fs_read_bytes` is `BS.readFile` inside `llmll_publish_io`. `BS.readFile` is strict, so no lazy thunk escapes the `try`. `wasi_io_stdin_bytes` is `BS.hGetContents stdin`, also strict. `BS.hGetContents` reads raw bytes and ignores the handle's text encoding. It closes `stdin` when it finishes. A later `BS.hGetContents` on the closed handle raises an `IOException`. So the runtime tests `hIsClosed stdin` first and delivers `RBytes` of length 0 (P13). This matches the empty-file rule of edge case 1. In `:mode console`, the harness owns `stdin` as its line source. So `wasi.io.stdin-bytes` there publishes `RErr` and reads nothing. Edge case 6 adds a `check` error for the case `check` can see.

**Why `wasi.io.stdin-bytes` and not `(wasi.fs.read-bytes "/dev/stdin")`.** Both work in `:mode cli`. The path form has no mode check and depends on `/dev/stdin` existing. The named command states the authority (`capability stdin`) and lets `check` refuse it in console mode. The path form stays legal and is documented as equal in `:mode cli`.

#### Cost of the arm: a breaking change, re-measured

A sixth arm makes every exhaustive `Response` match without a wildcard a `check` error. **Re-measured 2026-10-31** with `grep -rc "((RList" --include='*.llmll' .`: **65 match arms that name `RList`, in 24 files.** The count includes the untracked `examples/netpbm/main.llmll` (one arm). `examples/netpbm-swarm/` has none. Rev 0 counted 64 in 23 before that directory existed. The files are the in-tree tools (`tools/llmll-driver/sequencer.llmll` has 15), seven `scripts/build-smoke/` programs, five `scripts/tests/fixtures/` programs, one compiler fixture and the netpbm example. No `.ast.json` file names `RList`. A match that also has a wildcard is not affected, so 65 is an upper bound. A body-faithful `Response` match already covers `RList` with a wildcard (§9.7), so most verified code does not break. The repair at each site is one line, `((RBytes _) …)`, or a wildcard. `LLMLL.md` §9.7, §3.2 and `docs/getting-started.md` show five-arm matches and need the same edit.

External programs break the same way. The diagnostic must name `RBytes` and give the one-line repair, so an agent repairs it on the first attempt. Rust's `#[non_exhaustive]` would avoid the next break, but it removes the missing-arm error that agents rely on. It is not adopted.

#### Engineering risk: the `Response` datatype in the `.fq` file (P6)

`buildCtorSums` declares a native datatype for `Response`. Each payload field gets its sort from `typeToSort`. `typeToSort` has no clause for any byte type and defaults to `FQInt`. So an `RBytes` field would be declared at sort `int`. No array value meets that field today, because a match that names `RBytes` falls back. But the default is the trap that `JSON-1` repaired for `Json` and `FLOAT-LIT-1` repaired for `float`. Three requirements follow.

1. **Explicit sort clauses.** `typeToSort` and `typeToSortA` get a clause for the new type at `byteArraySort`. The same clause covers `TBytes _`, which has the same default today (D6).
2. **A regression gate on existing `Response` matches.** Every in-tree body-faithful function that matches on `Response` verifies with the same verdict before and after the arm is added. The gate runs over the 24 files of the census and the `Response` fixtures under `compiler/test/`. A changed verdict fails the gate.
3. **The constructor lists.** `RBytes` is added to `builtinCtorNames` in `Contracts.hs` and to `builtinAliases` in `TypeAdmissibility.hs`. `RespFact.hs` gets no row for `RBytes`. The one candidate fact, `bytesLen(b) ≥ 0`, is already given by the measure discipline.

### Part 2: the write (BYTES-WRITE-1)

| Constructor | Signature | Capability | Response |
|---|---|---|---|
| `wasi.fs.write-bytes` | `string bytes -> Command` | `(import wasi.fs (capability write PATH))` | `RNone` on success, `RErr` on IO failure. `(wasi.fs.write-bytes path data)`: the **path comes first**, as in `wasi.fs.write`. The parameter types differ, so a reversed call is a type error. |
| `wasi.io.stdout-bytes` | `bytes -> Command` | `(import wasi.io (capability stdout))` | `RNone`. Writes the bytes to standard output, never encoded. In any mode other than `:mode cli` it publishes `RErr` and writes nothing. |

**Runtime.** `wasi_fs_write_bytes` is `BS.writeFile` inside `llmll_publish_io`. It overwrites, as `wasi_fs_write` does. `wasi_io_stdout_bytes` is `BS.hPut stdout`. `wasi_io_stdout` does not catch an IO failure, because a failure of the harness's own output is harness breakage. `wasi.io.stdout-bytes` follows the same rule in `:mode cli`.

**Order of mixed text and byte output (P13).** A `:mode cli` program can mix `wasi.io.stdout` and `wasi.io.stdout-bytes`. The output order must equal the command order. Both writers use the one `stdout` handle. `BS.hPut` flushes the handle's character buffer before it writes, and it ignores the text encoding. So `wasi.io.stdout-bytes` must not set binary mode on `stdout`, and must not write to the file descriptor directly. The UTF-8 pin stays in force for text writes. A fixture interleaves text and byte writes and checks the byte-exact output.

**Why standard output needs its own command.** `(wasi.fs.write-bytes "/dev/stdout" b)` opens `/dev/stdout` with truncation. When standard output is redirected to a file, that truncates the file and loses every earlier write of the run. `BS.hPut stdout` appends to the open handle.

**Why console mode is refused.** In `:mode console`, `captureStdout` redirects standard output to a temporary file for each step, reads it back as UTF-8 text, and writes it to the event log as a JSON string. Bytes that are not UTF-8 fail that decode inside the harness. The event log has no field for bytes.

**One shape for both directions.** The read delivers `bytes` on `RBytes`. The write takes `bytes`. A program that reads, transforms and writes never converts through text. `wasi.fs.write` and `wasi.fs.read` keep their UTF-8 pins (FS-ENCODING-1).

### Part 3: character codes (CHAR-CODE-1)

| Function | Signature | Precondition | Result |
|---|---|---|---|
| `string-code-at` | `string int -> int` | `(and (>= i 0) (< i (string-length s)))` | The code point at index `i`, in `0..1114111`. |
| `string-from-code` | `int -> string` | `(and (and (>= c 0) (<= c 1114111)) (or (< c 55296) (> c 57343)))` | The one-character string for code point `c`. |

**Why a `pre` on `string-code-at`, when `string-char-at` has none (D3).** `string-char-at` can answer `""` out of range, because `""` is a `string` and is distinguishable. `string-code-at` returns an `int`. Every non-negative `int` is a possible answer. A sentinel such as `-1` flows into arithmetic without a type error. A `pre` is the polarity `bytes-get` already uses. The obligation is QF-LIA over the `string-length` measure.

**Runtime index check (P11).** The runtime compares `i` as an `Integer` against the length before `!!` narrows it to `Int`, under `INT-INDEX-WRAP-1`. The §13.6 row names this.

**Reflection, by step.** In step 1, a call to either function makes the caller fall back with `Refused by: app:string-code-at` or `app:string-from-code`. The preconditions are runtime assertions in step 1. In step 2, under part 0:

- `(string-code-at s i)` reflects as `strCode(s, i)`, an uninterpreted function `Str × Int → Int`, with the ground fact `0 ≤ strCode(s, i) ≤ 1114111`. A UF and not a fresh binder: congruence then makes two equal calls agree, so the `CALL-CONGRUENCE-1` problem does not arise.
- `(string-from-code c)` reflects as a fresh string term `r` with `strLen(r) = 1`.
- Both preconditions become PROVE obligations at the call.

**The range has no surrogate hole (P11).** `string-code-at` can return U+DC80 to U+DCFF, from argv or a directory listing. So the range fact is `0..1114111`, with no exclusion for surrogates. `string-from-code` refuses surrogates in its `pre`. GHC's `chr` accepts them, so this is a design choice for safe encoding at the IO boundary. So the round trip `string-from-code ∘ string-code-at` is partial on such strings. That is correct: `string-from-code` builds text, and a surrogate is not text. To recover the original byte, use `bytes-from-string` (part 4).

**Agreement with `string-compare`.** For one-character strings `a` and `b`, `(string-compare a b)` equals `(compare (string-code-at a 0) (string-code-at b 0))`. The `collect-order-1` record requires this. `string_compare` is `compare` on `String`, and `string-code-at` reads `ord`. So they agree by construction. A `check`/`for-all` property pins it.

**Cost.** `string-code-at` is O(i), because `string` is a Haskell `String`. A loop over every index is O(n²). For byte-level work, convert once with `bytes-from-string` and loop with `bytes-get`, which is O(1). The §13.6 row will say so.

### Part 5: bitwise operations (BITWISE-1)

**Surface.**

| Function | Signature | Precondition | Result |
|---|---|---|---|
| `bit-and` | `int int -> int` | `a ≥ 0`, `b ≥ 0` | bitwise AND |
| `bit-or` | `int int -> int` | `a ≥ 0`, `b ≥ 0` | bitwise OR |
| `bit-xor` | `int int -> int` | `a ≥ 0`, `b ≥ 0` | bitwise XOR |
| `bit-shl` | `int int -> int` | `a ≥ 0`, `k ≥ 0` | `(bit-shl a k)` is `a · 2^k`. The **value comes first**. |
| `bit-shr` | `int int -> int` | `a ≥ 0`, `k ≥ 0` | `(bit-shr a k)` is `⌊a / 2^k⌋`. The **value comes first**. |

There is no `bit-not`. On an unbounded integer, the complement of a non-negative number is negative. A fixed-width NOT is `(bit-xor x 4294967295)` for 32 bits. There is no rotate. A rotate needs a width. "Worked examples" shows a 32-bit rotate that stays linear.

**Why the operands are non-negative (restated after P3).** The restriction is a specification choice. It is not a premise of the exact reflections. Haskell's `Data.Bits` on `Integer` is well defined for negative values (infinite two's complement). Two reasons keep the `pre`. First, the target consumers work on bytes and unsigned words, and a negative operand there is a defect. Second, the `BITWISE-WIDTH-1` facts of part 6 (`0 ≤ band(a, b) ≤ a`) hold only for non-negative operands. A later relaxation of `a ≥ 0` needs no new proof for the three exact forms. Each `pre` is QF-LIA.

**Why `k ≥ 0`.** GHC 9.6.4 raises `arithmetic overflow` for a negative count on both `shiftL` and `shiftR` (review W4). A `pre` makes that a PROVE obligation instead of a crash.

**Shift amounts are not narrowed silently.** `Data.Bits` takes the count as `Int`. The runtime compares `k` as an `Integer` before it narrows, following `INT-INDEX-WRAP-1`. For `bit-shr`, a `k` above `maxBound :: Int` answers `0`, which is the exact value for any value that fits in memory. For `bit-shl`, such a `k` cannot produce a result that fits in memory. The runtime raises a named error, as `(* x y)` on huge operands exhausts memory. The §13 row will state this.

**Verification: what is exact.** The verifier reasons over unbounded integers in QF-LIA (§5.3.3). Three forms reflect exactly:

| Form | Side condition (after folding) | Reflection |
|---|---|---|
| `(bit-shl e c)` | `c` a ground constant, `0 ≤ c ≤ 4096` | `(* e 2^c)` |
| `(bit-shr e c)` | `c` a ground constant, `0 ≤ c ≤ 4096` | `(/ e 2^c)` |
| `(bit-and e m)` or `(bit-and m e)` | `m` a ground constant, `m ≥ 0`, `m = 2^w − 1` for some `w ≥ 0` | `(mod e 2^w)` |

**Soundness of the three forms, for every integer `e` (P3).** On Haskell `Integer`, `shiftL x k = x · 2^k`, `shiftR x k = ⌊x / 2^k⌋` and `x .&. (2^w − 1) = x mod 2^w`. These hold for negative `x` and for `x` above `2^64` (review W1, 19 values, `k` and `w` in `0..70`). SMT-LIB `div` and `mod` with a positive divisor are floor division and a non-negative remainder. They agree with Haskell `div` and `mod` there (`SIGMA-CONST-ARITH-1`). So each reflection equals the runtime value. The `a ≥ 0` precondition is not used.

**The two side conditions (P4).**

1. **The mask is tested on its folded value, and `m ≥ 0` is required.** The test `m .&. (m + 1) = 0` also accepts `m = −1`. On `Integer`, `x .&. (−1) = x` (review W2), which is not `x mod 2^w` for any `w`. The `b ≥ 0` call-pre usually fails first, but the emitter must not depend on that. A mask needs no size bound, because the emitted numeral `2^w` is one more than the literal the program wrote.
2. **A ground shift reflects only when `c ≤ 4096`.** `2^c` becomes a numeral of `c` bits in the `.fq` file, so `(bit-shl x 1000000)` would write a million-bit constant. Above the bound the caller falls back with `Refused by: app:bit-shl` or `app:bit-shr`. The bound goes into §5.3.3 beside the existing ground-constant text.

A ground constant is the one `SIGMA-CONST-ARITH-1` defines: a literal, or a closed term folded at emission. A `let`-bound constant is not ground.

**Every other form falls back in step 1.** `bit-or` and `bit-xor` in every form, `bit-and` with any other operand, and a shift by a non-ground or too-large amount make the caller fall back with `Refused by: app:bit-xor` (or the matching name). This is the existing rule for uninterpreted builtins such as `string-lower` (§5.3.3). The preconditions of a fallen-back call are still asserted at run time. Step 4 replaces the fallback for `bit-and`, `bit-or` and `bit-xor` (part 6). A non-ground or too-large shift keeps the fallback.

**Trust consequence.** In a codec, index arithmetic, byte ranges, offsets, field extraction by shift and mask, and modular addition verify in step 1. After step 4, 32-bit range posts over XOR and OR also verify. Functional correctness of XOR mixing does not verify at any step. A ChaCha20 quarter round is `tested` or `asserted`. `--strict-verified-core` refuses it. That needs the QF-BV `machine-int` opt-in named in §3.1, which this record does not add. This is a scope boundary, not a soundness gap.

**Sibling row.** Bitwise operations are designed here, because every worked example needs them. They are filed as `BITWISE-1`, because they share no code path with the byte type or the commands. `BITWISE-1` ships in step 1. It needs no `Response` change, no type and no schema change.

### Part 6: bitwise range and width facts (BITWISE-WIDTH-1)

This part ships in step 4, after part 0. It replaces the step-1 fallback for `bit-and`, `bit-or` and `bit-xor`. The exact forms of part 5 keep their exact reflections.

**Encoding.** One uninterpreted function `band : Int × Int → Int` is the only abstracted symbol. It is abstracted under part 0.

| Application | Reflection |
|---|---|
| `(bit-and a b)`, not an exact mask form | `band(a, b)` |
| `(bit-or a b)` | `a + b − band(a, b)` |
| `(bit-xor a b)` | `a + b − 2 · band(a, b)` |

The two identities hold on `Integer` (review W3: `(a .&. b) + (a .|. b) = a + b` and `xor a b = a + b − 2·(a .&. b)`, for `a` and `b` in `0..300`). So `bit-or` and `bit-xor` are exact linear terms over `band`.

**Facts per `band(a, b)` term.** Each fact is ground QF-LIA. Each holds for `a ≥ 0` and `b ≥ 0`, which the call-pre guarantees.

1. `0 ≤ band(a, b)`, `band(a, b) ≤ a`, `band(a, b) ≤ b`.
2. For each `w` in `W(f)`: `(a < 2^w ∧ b < 2^w) ⇒ a + b − band(a, b) < 2^w`. This is the width fact for `or`. It also bounds `xor`, because `xor(a, b) ≤ or(a, b)` follows from fact 1.

Fact 1 gives `xor(a, b) ≥ 0`, because `band(a, b) ≤ a` and `band(a, b) ≤ b`. The width fact does not follow from fact 1, so it is separate.

**The trigger set `W(f)` (answer to the professor's open question 2).** `W(f)` is the set of `w` with `1 ≤ w ≤ 4096` such that `2^w` or `2^w − 1` occurs as a ground constant, after folding, in the `pre` or `post` of the function `f` under verification. The fact is emitted once per `band` term and per `w` in `W(f)`. A function with a 32-bit contract gets `W(f) = {32}`. The count is the number of `band` terms times `|W(f)|`, which is small in practice. Constants in the body do not trigger, because the facts serve the contract.

**What this proves.** `crc-bits`, `crc-byte` and the CRC loop of "Worked examples" prove their 32-bit range posts (P7). A post that relates a rotate to `bit-or` or `bit-xor` becomes stateable as a term. Its proof still needs the right facts, and functional XOR identities stay out of reach.

### Builtin signatures, effects and `Response` arms

| Builtin | Effect label | Arm | Addition |
|---|---|---|---|
| `wasi.fs.read-bytes` | `fs.read` | `RBytes`, `RErr` | new builtin, new arm |
| `wasi.io.stdin-bytes` | `io.stdin` (new label) | `RBytes`, `RErr` | new builtin, new capability `stdin` |
| `wasi.fs.write-bytes` | `fs.write` | `RNone`, `RErr` | new builtin |
| `wasi.io.stdout-bytes` | `io.stdout` | `RNone`, `RErr` | new builtin |
| `bytes-*` (part 4), `string-code-at`, `string-from-code`, `bit-*` | pure | — | new builtins, callable from `def` |

**Soundness argument for the additions.**

1. **Strict immutability.** `ByteString` is immutable. `bytes-set` copies. No operation exposes a mutable buffer. The commands are `Command` values, as every `wasi.*` constructor is.
2. **Logic functions cannot crash from IO.** Every new command runs inside `llmll_publish_io` and delivers an IO failure as `RErr`. The two `stdout` writers follow the existing no-catch rule for the harness's own output channel.
3. **No pure operation is partial without a `pre` or a `Result`.** `bytes-get`, `bytes-set`, `bytes-make`, `bytes-slice`, `string-code-at`, `string-from-code` and the five `bit-*` operations carry QF-LIA preconditions. `bytes-from-list` and `bytes-to-string` return `Result`. Every precondition is also asserted at run time.
4. **The trusted base grows by a named set.** "Verification mapping" lists each new assumed post and axiom. Each is disclosed in the trust report under `codegen-determined`, as §13.12 requires for the closed set.
5. **The verifier does not over-claim.** Each reflection is exact or is a true over-approximation. An over-approximation that yields UNSAFE reports the fallback outcome, not `refuted` (part 0). So no new operation can make a true post `refuted`. The verdict rule also removes one existing case where a true post is `refuted` (`CALL-CONGRUENCE-1`).
6. **Capability.** `stdin` is a new `wasi.io` capability. `check` matches capabilities by namespace only (CAP-1-REAL), so this adds a declaration, not an enforcement.

### Schema delta

- `Type` gains the kind `bytes-unsized` with no other key (step 3).
- `TypeBytes.length` minimum moves from 1 to 0 (drift D1). This is a correction, and it can ship alone.
- No new statement or expression kinds. The new builtins are ordinary applications.
- `schemaVersion` changes from 0.15.0 to 0.16.0 in step 3, because a new type kind is a schema change (`AST-TYPE-ALIAS-1` precedent). Steps 1, 2 and 4 change no schema.

## Worked examples

All examples are `:mode cli`. A cli `:step` takes `(State, Response)` (§9.5). The terminating step's command is not performed (§9.7), so each program prints one step before it halts. Every `and` has exactly two arguments (P8).

**What was run.** The parts that use only existing surface were run on llmll 0.33.2 (a local build of `main`), with each bitwise call written as its step-1 reflection. `add32`, `rotl32-7` and `b64-sextet` passed `check` and were SAFE and body-faithful under `verify`. A copy of `b64-sextet` with the false post `(<= result 62)` was refuted, as expected (`b0 = 255`). The review's W5 and W6 cover `rotl32-7` and its inverse. The CRC and PPM examples use `bytes`, `RBytes` and the new commands, so they cannot run before step 3.

### CRC-32 of a file

```lisp
(import wasi.fs (capability read "/data" :deterministic false))
(import wasi.io (capability stdout :deterministic false))   ;; also covers wasi.io.stderr (namespace match)
(export)

;; One bit of the reflected CRC-32 (polynomial 0xEDB88320 = 3988292384).
;; (bit-and c 1) is exact: (mod c 2). (bit-shr c 1) is exact: (/ c 2).
;; bit-xor: step 1 falls back (Refused by: app:bit-xor); step 4 reflects it
;; over band, and the 32-bit post proves with W(f) = {32}.
(def-shell crc-bits [c: int k: int] -> int
  (pre (and (and (>= c 0) (<= c 4294967295)) (>= k 0)))
  (post (and (>= result 0) (<= result 4294967295)))
  (decreases k)
  (if (= k 0)
      c
      (crc-bits (if (= (bit-and c 1) 1)
                    (bit-xor (bit-shr c 1) 3988292384)
                    (bit-shr c 1))
                (- k 1))))

(def-shell crc-byte [c: int b: int] -> int
  (pre (and (and (>= c 0) (<= c 4294967295)) (and (>= b 0) (<= b 255))))
  (post (and (>= result 0) (<= result 4294967295)))
  (crc-bits (bit-xor c b) 8))

;; Body-faithful from step 3: crc-byte is called through its contract
;; (assume-guarantee), bytes-get's index pre 0 <= i < bytesLen(buf) is
;; discharged in the else branch, and bytes-get's result is in 0..255.
(def-shell crc-loop [buf: bytes i: int c: int] -> int
  (pre (and (and (>= i 0) (<= i (bytes-length buf)))
            (and (>= c 0) (<= c 4294967295))))
  (post (and (>= result 0) (<= result 4294967295)))
  (decreases (- (bytes-length buf) i))
  (if (= i (bytes-length buf))
      c
      (crc-loop buf (+ i 1) (crc-byte c (bytes-get buf i)))))

(def-shell crc32 [buf: bytes] -> int
  (bit-xor (crc-loop buf 0 4294967295) 4294967295))

(def-shell step [s: int r: Response] -> (int, Command)
  (if (>= s 1)
      (pair 2 (wasi.io.stdout ""))
      (match r
        ((RBytes b) (pair 1 (wasi.io.stdout (int-to-string (crc32 b)))))
        ((RErr e)   (pair 1 (wasi.io.stderr e)))
        (_          (pair 1 (wasi.io.stderr "unexpected response"))))))

(def-shell done? [s: int] -> bool (>= s 2))

(def-main :mode cli
  :init (pair 0 (wasi.fs.read-bytes "/data/image.png"))
  :step step
  :done? done?)
```

**What the trust report shows, by step.** After step 3, `crc-loop` is `verified`. Memory safety of every read and the 32-bit range of the running value rest on `crc-byte`'s contract. `crc-bits` and `crc-byte` fall back on `bit-xor`, so their posts are `tested` or `asserted`, and `crc-loop` inherits that through assume-guarantee. After step 4, `crc-bits` and `crc-byte` prove their range posts, and the chain is `verified` for range. The value of the CRC is never `verified`; a `check`/`for-all` against a reference vector makes it `tested`. `(decreases (- (bytes-length buf) i))` needs `bytes-length` as a measure component in a `decreases` clause. Today only `list-length` and `string-length` are checked there (§5.3.3, termination row). `BYTES-UNSIZED-1` adds `bytes-length`.

### base64 of a three-byte group

```lisp
;; Every operation reflects exactly in step 1: bit-shl and bit-shr by ground
;; constants, bit-and with the mask 63 = 2^6 - 1. Measured on 0.33.2 in its
;; step-1 reflection: body-faithful, SAFE.
(def-shell b64-sextet [b0: int b1: int b2: int j: int] -> int
  (pre (and (and (and (>= b0 0) (<= b0 255)) (and (>= b1 0) (<= b1 255)))
            (and (and (>= b2 0) (<= b2 255)) (and (>= j 0) (<= j 3)))))
  (post (and (>= result 0) (<= result 63)))
  (let [(n (+ (bit-shl b0 16) (+ (bit-shl b1 8) b2)))]
    (if (= j 0) (bit-and (bit-shr n 18) 63)
      (if (= j 1) (bit-and (bit-shr n 12) 63)
        (if (= j 2) (bit-and (bit-shr n 6) 63)
          (bit-and n 63))))))

(def-shell b64-char [i: int] -> string
  (pre (and (>= i 0) (<= i 63)))
  (string-char-at "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" i))

;; Falls back on the string assembly (Refused by: app:string-concat-many).
;; Its b64-char call-pre is reported on the call-pre unchecked line and is
;; asserted at run time. b64-sextet's verified post is why it holds.
(def-shell b64-group [b0: int b1: int b2: int] -> string
  (pre (and (and (and (>= b0 0) (<= b0 255)) (and (>= b1 0) (<= b1 255)))
            (and (>= b2 0) (<= b2 255))))
  (string-concat-many
    [(b64-char (b64-sextet b0 b1 b2 0))
     (b64-char (b64-sextet b0 b1 b2 1))
     (b64-char (b64-sextet b0 b1 b2 2))
     (b64-char (b64-sextet b0 b1 b2 3))]))
```

The group is OR-free by design. The three bytes occupy disjoint bit ranges, so `+` gives the same value as `bit-or` and stays linear. Rev 0 called `b64-group` fully verified. That was wrong: a string-building function falls back on `string-char-at` or `string-concat`, and a function with no `post` proves nothing (self-found R1, measured). The verified part is `b64-sextet`, which carries the index range. The full encoder loops over `(bytes-length buf)` in steps of three and pads the last group. Its index obligations discharge as `crc-loop`'s do.

### A 32-bit rotate and add, as in ChaCha20

```lisp
(def-shell add32 [a: int b: int] -> int
  (pre (and (and (>= a 0) (<= a 4294967295)) (and (>= b 0) (<= b 4294967295))))
  (post (and (>= result 0) (<= result 4294967295)))
  (mod (+ a b) 4294967296))

;; rotl32 by the ground constant 7. The two parts occupy disjoint bits, so +
;; replaces bit-or and the body stays linear.
(def-shell rotl32-7 [x: int] -> int
  (pre (and (>= x 0) (<= x 4294967295)))
  (post (and (>= result 0) (<= result 4294967295)))
  (+ (mod (bit-shl x 7) 4294967296) (bit-shr x 25)))
```

Both verify (P9). `add32` was run as written. `rotl32-7` was run in its step-1 reflection, `(+ (mod (* x 128) 4294967296) (/ x 33554432))`, and is SAFE. The proof needs integer reasoning: `(mod (* 128 x) 2^32)` is a multiple of 128, and `x / 2^25 ≤ 127`. Z3's LIA procedure finds both. Review W6 shows that the rotate by 25 of the rotate by 7 is the identity on `0..2^32 − 1`, and that also proves. Review W7 shows a false post is refuted. W5 and W6 become `BITWISE-1` fixtures. The ChaCha20 quarter round XORs after each add, so the quarter round's functional post is not provable at any step.

### A binary PPM (P6) image

```lisp
(import wasi.fs (capability write "/out" :deterministic false))

;; A 2x1 image: one red pixel, one blue pixel.
(def-shell ppm [] -> Result[bytes, int]
  (match (bytes-from-list [255 0 0 0 0 255])
    ((Success px) (Success (bytes-concat (bytes-from-string "P6\n2 1\n255\n") px)))
    ((Error i)    (Error i))))

(def-shell step [s: int r: Response] -> (int, Command)
  (if (= s 0)
      (match (ppm)
        ((Success img) (pair 1 (wasi.fs.write-bytes "/out/tiny.ppm" img)))
        ((Error i)     (pair 1 (wasi.io.stderr (int-to-string i)))))
      (pair 2 (wasi.io.stderr ""))))
;; done? and def-main as in the CRC example, with :init (pair 0 (wasi.io.stderr "")).
```

The header is ASCII, so `bytes-from-string` gives its bytes exactly. The pixels are bytes `0xFF` and `0x00`, which no `string` literal can carry through `wasi.fs.write`. This is the `BYTES-WRITE-1` fixture case (`bin.dat`, stage 5b of `tools/build-smoke/buildsmoke.llmll`), which today spawns `/usr/bin/printf`.

## Edge cases and degenerate inputs

1. **An empty file.** `(wasi.fs.read-bytes p)` on a zero-length file delivers `RBytes b` with `(bytes-length b) = 0`. It does not deliver `RNone`. This follows `wasi.fs.list`, where an empty directory is `RList []`. Channel: spec, runtime. Citation: `wasi_fs_list` in `CodegenHs.hs`.
2. **A file that is not UTF-8.** `(wasi.fs.read-bytes p)` delivers every byte. `(wasi.fs.read p)` still delivers `RErr`, unchanged. Channel: spec is explicit. Citation: `wasi_fs_read`.
3. **A directory, a missing path, a FIFO.** A directory or a missing path delivers `RErr`. A FIFO blocks until its writer closes it, as `wasi.fs.read` does. Channel: spec is silent today for `wasi.fs.read` on a FIFO (gap, flag; not new).
4. **An index at the length.** `(bytes-get b (bytes-length b))` fails its `pre`. In a body-faithful function with a contract, it is `refuted` when no abstracted term is in the constraint (part 0). When `b` comes from `bytes-slice`, the constraint holds an abstracted term, and the outcome is the fallback outcome with the runtime assertion. Elsewhere it is a runtime assertion failure naming `bytes-get`. Channel: contract. Citation: the `bytes-get` call-pre in `FixpointEmit.hs`.
5. **An index above `2^63`.** `(bytes-get b 18446744073709551617)` is compared as an `Integer` before narrowing and fails the `pre`. It does not wrap to index 1. Channel: contract, runtime. Citation: `INT-INDEX-WRAP-1`, the `bytes_get` preamble body.
6. **`wasi.io.stdin-bytes` in a console program (positive witness).** This program is a `check` error, kind `byte-stdio-console`:

   ```lisp
   (import wasi.io (capability stdin) (capability stdout :deterministic false))
   (def-shell step [s: int input: string r: Response] -> (int, Command)
     (pair 1 wasi.io.stdin-bytes))
   (def-shell done? [s: int] -> bool (>= s 1))
   (def-main :mode console :init (pair 0 (wasi.io.stdout "")) :step step :done? done?)
   ```

   The rule fires when the entry module's `def-main` is `:mode console` and a def of the program names `wasi.io.stdin-bytes` or `wasi.io.stdout-bytes`. A library module compiled without an entry is not checked. The runtime `RErr` is the backstop for it. Channel: type (check-time), then runtime. Citation: new; `def-main-step-arity` is the precedent for a mode-dependent check.
7. **`(wasi.fs.read-bytes "/dev/stdin")` in a console program.** `check` does not refuse it, because a computed path cannot be seen. The harness and the read compete for the same descriptor, and the result depends on buffering. Channel: spec is silent (intentional). The §13.9 row says "use `:mode cli`".
8. **`(bytes-slice b 3 2)`.** Fails `0 ≤ s ≤ e`. It does not answer empty, unlike `string-slice`. From step 3 this is a PROVE obligation at the call. Channel: contract. Citation: part 4.
9. **`(bytes-from-list [256])`.** Delivers `Error 0`. `(bytes-from-list [])` delivers `Success` with length 0. Channel: type (the caller must match the `Result`).
10. **`(bytes-to-string (bytes-from-list [0xC3]))`, a truncated sequence.** Delivers `Error 0`. Channel: type.
11. **A path from argv with byte `0xFF`.** `wasi.proc.args` delivers U+DCFF. `(bytes-from-string a)` gives the single byte `0xFF`. The P10 bounds hold: `strLen = 1`, `bytesLen = 1`. Channel: spec.
12. **`(string-code-at "" 0)`.** Fails `0 ≤ i < 0`. From step 2 this is a PROVE obligation at the call. Channel: contract.
13. **`(string-from-code 55296)`, a surrogate.** Fails the `pre`. Without it, a later `wasi.fs.write` of the string would raise in the UTF-8 encoder. Channel: contract. Citation: the `CHAR-CODE-1` row.
14. **`(bit-shl x -1)`.** Fails `k ≥ 0`. `check` accepts the call, because there is no check-time literal fold for builtin preconditions (measured on 0.33.2 with `(bytes-get b -1)`: `check` OK). In a body-faithful function with a contract, the call-pre is refuted. Otherwise it is a runtime assertion failure. Rev 0 said `check` refuses it; that was wrong (self-found R2). Channel: contract.
15. **`(bit-and x 255)` versus `(bit-and x 254)`.** The first reflects as `(mod x 256)` and keeps the function body-faithful. The second is not a mask of the form `2^w − 1`. In step 1 it makes the function fall back. From step 4 it is `band(x, 254)` with range facts. Channel: verification routing. This boundary must be in the §5.3.3 text, because a reader will expect any constant mask to verify.
16. **`(= a b)` over two `bytes` values in a `post`.** Contract-only fallback, `guard:whole-structure-eq`. Channel: verification routing. Citation: `wholeArrEqClause`.
17. **`wasi.io.stdout-bytes` with an empty value.** Writes nothing and delivers `RNone`. Channel: spec.
18. **A 2 GB file.** `BS.readFile` allocates it. A file larger than memory fails with `RErr` if GHC reports the allocation failure as an `IOException`, and kills the process otherwise. Channel: spec is silent (gap, flag). Streaming reads are a non-goal of this record.
19. **`(bit-and x -1)` (P4).** The folded mask is `−1`. The recognizer requires `m ≥ 0`, so the form is not exact. The `b ≥ 0` call-pre fails. In step 1 the caller falls back. The emitter never writes `(mod x 2^w)` for it. Channel: verification routing, then contract.
20. **`(bit-shl x 5000)` (P4).** `c = 5000` is ground but above the bound 4096. The caller falls back with `Refused by: app:bit-shl`. The runtime computes the value. Channel: verification routing.
21. **Two `wasi.io.stdin-bytes` commands in one run (P13).** The first delivers all of standard input. The second delivers `RBytes` of length 0. Channel: spec, runtime. A fixture runs both.
22. **Text and byte writes interleaved on standard output (P13).** `(wasi.io.stdout "a")`, then `(wasi.io.stdout-bytes b)` with `b` = `[0xFF]`, then `(wasi.io.stdout "c")` writes the bytes `61 FF 63`, in that order. Channel: spec, runtime. A fixture checks the bytes.
23. **The verdict rule fires on a true post (positive witness for part 0).** From step 2:

    ```lisp
    (def-shell a-code [] -> int
      (post (= result 97))
      (string-code-at "a" 0))
    ```

    The VC holds `strCode("a", 0)` with only the range fact, so the solver answers UNSAFE. The constraint holds an abstracted term. The outcome is the fallback outcome, `Refused by: abstraction:app:string-code-at`, not `refuted`. The post is true, so `refuted` would misstate the program. Channel: trust. Citation: part 0.
24. **The verdict rule does not fire on one opaque call (negative witness for part 0).** `fn-param-uf-1` W3: one call through `le`, with a false post. The VC holds one call to `le`, so the bit is clear. The verdict stays `refuted`. Channel: trust.
25. **The verdict rule on two equal calls.** `CALL-CONGRUENCE-1` W5: `(if (le a b) (if (le a b) 0 1) 0)` with post `(= result 0)`. The VC holds two calls to `le`. Before step 2 it is `refuted`. After step 2 it is the fallback outcome, cause `abstraction:app:le`. The post is true. Channel: trust.
26. **Two calls to one contracted callee, true post (A1, P15).** `h [a: int]`, post `(= result 0)`, body `(- (g a) (g a))`, with the `g` of part 0. On 0.33.2 this is `refuted`, a false refutation. From step 2 the VC holds two calls to `g`, so the bit is set. The outcome is the fallback outcome, cause `abstraction:app:g`. Channel: trust.
27. **Two calls with different argument syntax (A2, P15).** `h8 [a: int b: int]`, post `(>= result 0)`, body `(if (= a b) (- (g a) (g b)) 0)`. On 0.33.2 this is `refuted`, a false refutation. CSE does not merge `(g a)` and `(g b)`. From step 2 the outcome is the fallback outcome, because clause 2 does not compare arguments. Channel: trust.
28. **Two self-calls, false post (A4, the cost of P15).** `f [n: int]`, pre `(>= n 0)`, post `(>= result 0)`, body `(if (< n 2) n (- (f (- n 1)) (f (- n 2))))`. The post is false: `f 4 = -1`. On 0.33.2 this is `refuted`, which is correct. From step 2 the outcome is the fallback outcome, cause `abstraction:app:f`. The rule gives up this refutation. The `CALL-CONGRUENCE-1` Ackermann form (P18) would restore it. Channel: trust.

## Verification mapping

| Obligation or fact | Channel | Fragment | Citation |
|---|---|---|---|
| The verdict bit "contains an abstracted term" | trust (verdict map) | syntactic, no solver call | part 0 |
| `bytes-get` index pre `0 ≤ i < bytesLen(b)` on `bytes` | contract (PROVE) | QF-LIA + measure | §5.3.3 array class |
| `bytes-get` result `= select(b, i)` | assumed post (existing axiom, now also at `bytes`) | array theory | §13.12 closed set |
| byte-range fact `0 ≤ select(b,i) ≤ 255` on a `bytes`-rooted read | ground-fact family (existing) | QF-LIA | `injectRangeFacts` |
| `bytes-set` pre, store reflection and length lemma on `bytes` | contract; assumed post (existing axiom, now also at `bytes`) | array theory + QF-LIA | the `bytes-set` reflection |
| `bytes-length` on `bytes` as `bytesLen(b)`; `bytesLen(b) ≥ 0` | reflection; `measure-nonneg` family | QF-LIA + measure | §5.3.3 measure class |
| `bytes-make n v`: pre `n ≥ 0 ∧ 0 ≤ v ≤ 255`; post `r = const(v) ∧ bytesLen(r) = n` | contract; **new assumed post** | array theory | the `bytes-zero` shape |
| `bytes-widen b`: `⟦b⟧` | exact reflection; **new axiom** (codegen claim that `BS.pack` keeps the bytes); no assumed post | identity | P2; `byteArraySort` |
| `bytes-slice` pre `0 ≤ s ≤ e ≤ bytesLen(b)` | contract (PROVE) from step 3 | QF-LIA | part 4 |
| `bytes-slice`, `bytes-concat`, `bytes-concat-many`, `bytes-to-list`, `bytes-from-string` length facts | **new assumed posts**; abstracted terms | QF-LIA + measure | part 4 table |
| `bytes-from-list`, `bytes-to-string` | caller falls back, `Refused by: app:<name>` | outside (array payload in `Result`) | `admissiblePayload` |
| `string-code-at` pre `0 ≤ i < strLen(s)`; `string-from-code` pre | contract; runtime only in step 1, PROVE from step 2 | QF-LIA + measure | part 3 |
| `strCode(s, i)` range `0..1114111`; `strLen(string-from-code c) = 1` | **new assumed posts** from step 2; abstracted terms | QF-LIA + UF | part 3 |
| `bit-shl e c`, `c` ground, `0 ≤ c ≤ 4096` | exact reflection `e · 2^c` | QF-LIA | `SIGMA-CONST-ARITH-1` |
| `bit-shr e c`, `c` ground, `0 ≤ c ≤ 4096` | exact reflection `e div 2^c` | QF-LIA | `SIGMA-CONST-ARITH-1` |
| `bit-and e m`, `m = 2^w − 1 ≥ 0` after folding | exact reflection `e mod 2^w` | QF-LIA | `SIGMA-CONST-ARITH-1` |
| `bit-*` operand pres `a ≥ 0`, `b ≥ 0`, `k ≥ 0` at a reflected call | contract (PROVE) | QF-LIA | new call-pre, `call-pre:<name>` tag |
| `bit-or`, `bit-xor`, other `bit-and`, in step 1; non-ground or too-large shifts, always | caller falls back, `app:<name>` | outside (QF-BV) | §3.1 `machine-int` note |
| `band(a, b)` facts `0 ≤ band ≤ a`, `band ≤ b`; width fact per `w ∈ W(f)` | **new assumed posts** from step 4; abstracted term | QF-LIA + UF | part 6 |
| `bit-or`, `bit-xor` over `band` | exact linear terms over the UF | QF-LIA + UF | part 6; review W3 |
| `RBytes` payload in a `match` arm | the match falls back, as for `RList` | outside the admissible payloads | §9.7 note |
| Commands (`wasi.fs.read-bytes` and the others) | none; `Command` values carry no obligation | — | §9 |

**New trusted items.** Each is disclosed under `codegen-determined` and rides `codegen_semantics_version`. Assumed posts: `bytes-make`; the five bytes length facts of part 4; the two `CHAR-CODE-1` facts; the `band` facts. Axiom: `bytes-widen` as the identity. The existing `bytes-get`, `bytes-set` and `bytes-length` axioms extend from `bytes[n]` to `bytes` with the same terms. That extension adds to the trusted base, because the `ByteString` instance is new code. **No Lean obligation is introduced.** Nothing routes to `?proof-required`. Every new obligation is QF-LIA, with arrays, measures or one UF, inside §5.3.3.

## Affected surface

- **`compiler/src/LLMLL/FixpointEmit.hs`** and the verdict path in **`compiler/src/LLMLL/TrustReport.hs`** (step 2): the per-constraint bit; the verdict map; the cause `abstraction:app:<name>`; the call-count condition "two or more calls to one callee, contracted or not". `--strict-verified-core` refuses the new outcome. The `fn-param-uf-1` fixtures W5, W6 and MMF-6 are re-measured. A1, A2 and A4 are new fixtures.
- **`compiler/src/LLMLL/Syntax.hs`** (step 3): a new `Type` constructor; `typeLabel` prints `bytes`.
- **`compiler/src/LLMLL/Parser.hs`, `ParserJSON.hs`, `AstEmit.hs`** (step 3): the bare `bytes` type; JSON kind `bytes-unsized`. A program that names a user type `bytes` would change meaning. Measured 2026-10-30: `grep -rn "(type bytes" --include=*.llmll` finds none in the tree.
- **`compiler/src/LLMLL/TypeCheck.hs`**: `builtinEnv` entries for every new name; `inferArrayOp` for `bytes`; `compatibleWith`; the `byte-stdio-console` check; equality admits `bytes`; order refuses it.
- **`compiler/src/LLMLL/TypeAdmissibility.hs`**: `RBytes` in `builtinAliases`; the comment there is replaced.
- **`compiler/src/LLMLL/Contracts.hs`**: `builtinCtorNames` gains `RBytes`; the static evaluator reduces the new pure operations; `for-all` needs a `bytes` generator.
- **`compiler/src/LLMLL/CodegenHs.hs`**: `data Response`; the four command bodies, with the closed-`stdin` test and the shared `stdout` handle; the `LlmllBytes` class or an equivalent; `toHsType` for `bytes`; the bitwise bodies with `Integer` comparison before narrowing; the `string-code-at` `Integer` index check; the reserved-name list.
- **`compiler/src/LLMLL/FixpointEmit.hs`** (steps 1, 3, 4): `typeToSort` and `typeToSortA` clauses at `byteArraySort` for the new type and for `TBytes _` (P6, D6); the array sort at every site that tests `TBytes`; `bytes-make` and `bytes-widen` reflection; the five partial reflections; the three exact bitwise forms with the P4 side conditions in `exprToPred`, `bodyToPredM` and `appLabel`, beside `constLinear`; the `strCode` UF; the `band` UF, its facts and `W(f)`. `GuardClassifier.hs` gets the same exact forms in guards.
- **`compiler/src/LLMLL/TrustReport.hs`**: the new trusted items in the disclosed set.
- **Termination**: `bytes-length` as a `decreases` measure component.
- **`docs/llmll-ast.schema.json`**: kind `bytes-unsized`; `TypeBytes.length` minimum 0 (D1); `schemaVersion` 0.16.0.
- **`LLMLL.md`** (doc-lead, after each step ships): §0 summary (D5); §3.1 `string` row (D2); §3.2; §4.4.1 the `refuted` note and the new fallback cause; §5.3.3 the verdict rule, the array class, the bitwise boundary and the shift bound; §9.7 arm table, criterion 1 and examples; §13.6 two rows; §13.9 four rows; §13.11 note ("Variable-length byte types … are deferred" is withdrawn); §13.12 the `bytes` operations and the new trusted items; a new §13 subsection for bitwise operations; the Tier 1 reach table.
- **In-tree programs** (step 3): up to 65 match arms in 24 files gain an `RBytes` arm or a wildcard. The regression gate of part 1 runs on them.
- **`tools/build-smoke/buildsmoke.llmll` stage 5b** (step 3): replace the `printf` spawn with `wasi.fs.write-bytes`. TOOL-RFC-006's `od` spawn can use `wasi.fs.read-bytes`.

### FFI boundary (FFI-BYTES-1)

`bytes` lowers to strict `Data.ByteString.ByteString`. So the Tier 1 boundary needs no converter for it, as `int` needs none for `Integer`. `bytes` is valid in parameters and in results. `bytes[n]` stays refused in a result. A result has no length to check against `n`, and nothing changes that.

Reach that this unlocks in `Data.ByteString`: `reverse`, `append`, `isPrefixOf`, `isSuffixOf`, `isInfixOf`, `null`, and `length` through `hs-int`. Still unreachable: exports with `Word8` arguments (`elem`, `cons`, `map`), exports with `Int` arguments (`take`, `drop`, which need `FFI-NARROW-1`), and lazy `ByteString` (`FFI-OPAQUE-1`). A `hs-word8` boundary type is not proposed. The forcer for a `ByteString` result is WHNF, which is full evaluation for a strict `ByteString`. `FFI-BYTES-1` ships in step 4, after `BYTES-UNSIZED-1`.

### Response, replay and the event log (G4)

- **The console event log does not change.** It records `(stdin line, stdout text)` per step (`eventJsonL`). It does not record `Response` values. Byte stdio is refused in console mode, so no byte reaches the log.
- **`:mode cli` writes no event log** (§9.5). Byte stdio is allowed there.
- **`REPLAY-INJECT` (parked) inherits one item.** If it ships, a value log must encode an `RBytes` payload in JSON, as base64 or hex. The professor agrees this is a deferred format decision, not a reason to prefer (c).
- **`:deterministic true`** stays refused on `wasi.fs`. The new `wasi.fs` commands inherit the refusal. `wasi.io.stdin-bytes` reads a non-deterministic source and is refused the same way.

### What the design must not break

1. **`bytes[n]` verification.** The four head-syntax readers of `TBytes n` and the `bytes-zero` length axiom stay as they are. FACT-AG-LEN stays: no binder gains an asserted length (P2).
2. **The text commands.** `wasi.fs.read` and `wasi.fs.write` keep their UTF-8 pins (FS-ENCODING-1). `stdout` keeps its UTF-8 pin for text writes.
3. **The closed axiom set.** Every new trusted item is listed above and disclosed.
4. **Claim accuracy.** No new reflection can make a true post `refuted` (part 0).
5. **Existing `Response` verdicts.** The regression gate of part 1 holds every in-tree verdict fixed across step 3.
6. **Index safety.** No index or shift count wraps before it is compared (`INT-INDEX-WRAP-1`).
7. **Effect failures are values.** Every new command delivers `RErr`, and none raises into a logic function.
8. **Strict evaluation.** `BS.readFile` and `BS.hGetContents` are strict. No lazy thunk escapes the `try`.
9. **The console harness.** Its stdin loop and its stdout capture do not see bytes.
10. **Safe Haskell.** User modules stay `{-# LANGUAGE Safe #-}`. `Data.ByteString` is `Trustworthy`, so a Safe module may import it. The engineer confirms this for the generated `Lib.hs`.

## Implementation sequence

The user settled this order on 2026-10-31. Each step is one release unless the row says otherwise.

| Step | Rows | Content | Depends on | `Response` or schema change |
|---|---|---|---|---|
| 1 | `BITWISE-1`, `CHAR-CODE-1` | The five `bit-*` operations; the three exact forms with the P4 side conditions; W5 and W6 as fixtures. `string-code-at` and `string-from-code` with their `pre`s; callers fall back in this step. | nothing | none |
| 2 | `ABSTRACTION-VERDICT-1` | The verdict rule of part 0; the cause `abstraction:app:<name>`; the call-count condition, contracted or not; `--strict-verified-core`; re-measured `fn-param-uf-1` fixtures; the A1, A2 and A4 fixtures. The first builtin consumers: the `strCode` UF and the `string-from-code` length fact. Witnesses: edge cases 23 to 28. | step 1 for the `CHAR-CODE-1` consumers | none |
| 3 | `BYTES-UNSIZED-1`, `BYTES-READ-1`, `BYTES-WRITE-1`, in one release | The `bytes` type and its operations; the five partial reflections; `bytes-widen` as the identity; `bytes-length` in `decreases`; the four commands; the `RBytes` arm; `typeToSort` clauses (with D6); the `Response` regression gate; the migration of 65 arms in 24 files; the `byte-stdio-console` check; the P13 fixtures. | step 2 | `Response` gains `RBytes`; schema 0.16.0 |
| 4 | `BITWISE-WIDTH-1`, `FFI-BYTES-1`, in either order | `band` with its facts and `W(f)`; `bit-or` and `bit-xor` over `band`. `bytes` at the Tier 1 boundary and the reach table. | `BITWISE-WIDTH-1`: steps 1 and 2. `FFI-BYTES-1`: step 3 | none |

## Risks and open questions

1. **The sixth arm breaks every exhaustive `Response` match.** Classification: scope. Citation: the `TypeCheck.hs` comment; the census above. Bite: complicates. The in-tree repair is up to 65 one-line edits in 24 files. External programs break once. The user accepted this with shape (b).
2. **The `Response` datatype sort default.** Classification: soundness (emitter). Citation: `typeToSort`, `buildCtorSums`. Bite: complicates step 3. Without the explicit clause, `RBytes` is declared at `int`. The clause and the regression gate close it (part 1).
3. **The verdict rule changes existing verdicts.** Classification: spec drift, regression. Citation: part 0. Bite: complicates step 2. Each change goes from `refuted` to the fallback outcome. The `fn-param-uf-1` fixtures and any saved `refuted` must be re-measured. The engineer decides the stamp. A1 and A2 move from a false `refuted`; A4 moves from a true one.
4. **The verdict rule loses some true refutations.** Classification: verification ergonomics. Citation: part 0. Bite: only matters at scale. A false post in a function that also calls `bytes-slice` reports the fallback outcome, not `refuted`. So does a false post in a function with two calls to one callee, such as A4. The cone-of-influence form of the bit limits the loss. The trade keeps claim accuracy, which the project ranks first.
5. **Most of a codec does not verify functionally.** Classification: verification ergonomics. Citation: parts 5 and 6. Bite: limits the claim, does not block. After step 4, ranges verify, and XOR mixing values do not. The §13 text must state this plainly.
6. **Overloading `bytes-get` over two representations.** Classification: spec drift. Citation: `inferArrayOp`. Bite: complicates. Codegen today emits one name with no type in hand. A Haskell class keeps that true; another route needs type-directed emission.
7. **`bytes` as a reserved type word.** Classification: scope. Bite: only matters at scale. The in-tree census finds no user type named `bytes`; external programs are not measured.
8. **Memory on large inputs.** Classification: scope. Citation: edge case 18. Bite: only matters at scale. The design reads whole files. Streaming is a non-goal.
9. **`bytes-set` is O(n).** Classification: verification ergonomics (cost). Bite: only matters at scale. A loop of `bytes-set` is O(n²). The idiom is to build a `list[int]` and call `bytes-from-list` once. The §13.12 row will say so, as §13.5 does for `list-append`.

Rev 0 risk 3 (the `rotl32` post is not measured) is removed. The professor measured it (review W5, W6, W7), and this revision ran it again (P9).

## Proposed roadmap rows

These tags are proposals. This record does not edit the roadmap. The documentation-lead files them.

| Tag | Group | Next action on settlement | Content |
|---|---|---|---|
| `BITWISE-1` | G7 | PLAN | Step 1. The five operations and the three exact reflections, with the mask `m ≥ 0` test and the shift bound 4096. |
| `CHAR-CODE-1` (existing) | G7 | DECIDE → PLAN | Step 1. `string-code-at`, `string-from-code`, their `pre`s and the `Integer` index check. Its facts ship in step 2. The row's `string-char-at` precondition citation is corrected (D3). |
| `ABSTRACTION-VERDICT-1` | G1 | PLAN | Step 2. An UNSAFE constraint that contains a builtin abstraction, or two or more calls to one callee (contracted or not, self-calls included), reports the fallback outcome with cause `abstraction:app:<name>`, not `refuted`. Closes the false-`refuted` half of `CALL-CONGRUENCE-1`. Ships the `CHAR-CODE-1` facts as its first builtin consumers. Fixtures A1, A2, A4. |
| `BYTES-UNSIZED-1` | G7 | PLAN | Step 3. The `bytes` type, the operations of part 4, the partial reflections (absorbs `BYTES-PARTIAL-REFLECT-1`), `bytes-widen` as the identity, `bytes-length` in `decreases`, the `typeToSort` clauses (with D6), schema kind `bytes-unsized`. Depends on `ABSTRACTION-VERDICT-1`. |
| `BYTES-READ-1` (existing) | G4 | DECIDE → PLAN | Step 3. `wasi.fs.read-bytes`, `wasi.io.stdin-bytes`, the `RBytes` arm, the `Response` regression gate, the in-tree migration. Ships with `BYTES-UNSIZED-1`. |
| `BYTES-WRITE-1` (existing) | G4 | DECIDE → PLAN | Step 3. `wasi.fs.write-bytes`, `wasi.io.stdout-bytes`, `byte-stdio-console`, the interleaving fixture. Ships with `BYTES-READ-1`. |
| `BITWISE-WIDTH-1` | G7 | PLAN | Step 4. `band` with range and width facts, the trigger set `W(f)`, `bit-or` and `bit-xor` over `band`. Depends on `BITWISE-1` and `ABSTRACTION-VERDICT-1`. Moved from the parking lot (P7). |
| `FFI-BYTES-1` | G3 | PLAN | Step 4. `bytes` at the Tier 1 boundary; reach table update. Depends on `BYTES-UNSIZED-1`. |
| `BYTES-NARROW-1` | Parking lot | — | `bytes → bytes[n]` in the professor's `pre` form. Trigger: a consumer that feeds a file into `sha1` or `hmac-sha1`. |
| `BYTES-SLICE-CONTENT-1` | Parking lot | — | Ground content instances `r[j] = b[s + j]` for a slice. Trigger: a real program whose post relates slice contents to the source. |
| `CALL-CONGRUENCE-1` (existing) | Parking lot | scope narrowed, text widened | The row text widens from uncontracted and parameter callees to every call encoded as a fresh binder, contracted callees included. Witnesses A1 and A2 (false `refuted` on 0.33.2); A2 is not fixed by CSE. The false-`refuted` half closes with `ABSTRACTION-VERDICT-1`. The completeness half stays, with the same trigger. Recommended next form: Ackermann hypotheses (P18). |

`BYTES-PARTIAL-REFLECT-1` is not filed. Its content is part of `BYTES-UNSIZED-1`.

## Findings routed to other owners

| Finding | Owner | What moves |
|---|---|---|
| D1: `TypeBytes.length` `"minimum": 1` | documentation-lead (schema) | `docs/llmll-ast.schema.json` to `"minimum": 0`. Can ship alone. |
| D2: §3.1 calls `string` a UTF-8 byte sequence | documentation-lead | `LLMLL.md` §3.1: "sequence of Unicode code points, written as UTF-8 at the IO boundary". |
| D3: the `CHAR-CODE-1` row cites a nonexistent `pre` | documentation-lead | The roadmap row text, when the row moves to PLAN. |
| D5 (P12): §0 says `Σ_auto` has no `*`, `/`, `mod` | documentation-lead | `LLMLL.md` §0: "with constant multipliers and positive constant divisors". |
| D6: `typeToSort` defaults `TBytes n` to `FQInt` | compiler-engineer | Fixed in step 3 with the new clause. The engineer confirms it with a witness first. |
| P5: criterion 1 of the four-part arm rule | documentation-lead | The effect-response-channel record and `LLMLL.md` §9.7: "not expressible by an existing arm without a decoding step that can fail". |
| D7 (P16): `LLMLL.md` §4.4.1 says "disproved" and "known to be false" | documentation-lead, language-team | The `refuted` note restated as a modular disproof; `depends-on-refuted` says "a postcondition not established". The language-team confirms the final wording. |
| `REPLAY-INJECT` inherits the `RBytes` encoding | documentation-lead | The parked row's scope names it when the row is next edited. |

## Open questions for the user

None. The user settled shape (b) and the ship order on 2026-10-31.

## Open questions for the professor

None. The professor answered Rev 0's question (partial reflection is admissible under a verdict rule). Rev 1 answered the professor's two questions to the language-team in parts 0 and 6. The professor's follow-up review accepted both Rev 1 divergences, the call count and the arm-fact answer, with one change: the count covers contracted callees (P15). Rev 2 makes that change. The professor states no open item after it.

## Hand-off on settlement

(a) `docs/design/byte-io-proposal.md`. (b) Rev 2, settled 2026-10-31. (c) `docs/design/byte-io-review.md` existed as a standalone review with two passes. The documentation-lead folded it below as the Appendix on 2026-10-31 and archived it at `docs/archive/professor-reviews/byte-io-review.md` (M2). (d) Code-track. The engineer takes the four steps of "Implementation sequence" in order, one plan per step. Step 1 touches `TypeCheck.hs`, `CodegenHs.hs`, `FixpointEmit.hs` and `GuardClassifier.hs`, with no schema change. Step 2 touches the verdict path in `FixpointEmit.hs` and `TrustReport.hs`. Step 3 is the one breaking release. The documentation-lead files the rows above, widens the `CALL-CONGRUENCE-1` row text, and routes the findings at settlement.

## Appendix — Professor review log

Folded 2026-10-31 by documentation-lead (M2), at settlement of Rev 2. The two passes are copied unchanged from the standalone review. The standalone file is archived at [`../archive/professor-reviews/byte-io-review.md`](../archive/professor-reviews/byte-io-review.md). The file was never committed at its old path, so the archive copy is the first committed version. The per-item dispositions are in [Changes from Rev 0](#changes-from-rev-0) and [Changes from Rev 1](#changes-from-rev-1) above. Pass 2 states no open item after the three changes that Rev 2 makes.

### Pass 1 (on Rev 0, 2026-10-31)

#### Verdict

**Settle with changes.** The five parts are sound as written, because every operation without an exact reflection makes its caller fall back. The design does not need a different tradition. It needs two decisions and a set of small repairs.

1. **Answer to the open question: yes.** A sealed builtin can be reflected partially without a false `refuted`. The condition is a change to the verdict, not to the reflection (P1). Adopt the change and fold `BYTES-PARTIAL-REFLECT-1` into this record. Without it, the `bytes-slice` precondition is runtime-only, and the reason Rev 0 gives for that precondition does not hold.
2. **Reflect `bytes-widen` as the identity on its argument.** Do not assume `bytesLen(r) = n` (P2).
3. **Keep the three exact bitwise forms.** They are exact over every integer, not only non-negative ones (P3). Exclude the mask `−1` and bound the shift constant (P4).
4. **Keep shape (b), the `RBytes` arm.** The arm passes the four-part rule on the shape reading. The break is bounded and one-time (P5, P6).
5. **Repair the worked examples.** `and` takes two arguments. Every multi-clause `pre` in the examples fails `check` (P8).
6. **The `rotl32-7` post is stateable and proves.** Measured on llmll 0.33.2 (P9). Remove risk 3.

No finding is a soundness defect in Rev 0 as written. P2 is a soundness hazard in an ambiguous clause. P1 is the decision that most changes what the record delivers.

#### Restatement

Rev 0 adds an unsized byte sequence `bytes` (strict `ByteString`), distinct from `bytes[n]` and joined by `bytes-widen`. It adds byte-level file and stdio commands that deliver a sixth `Response` arm `RBytes`. It adds `string-code-at` and `string-from-code`. It adds five bitwise operations over `int`, of which ground shifts and `bit-and` with a mask `2^w − 1` reflect exactly into QF-LIA, and every other use makes the caller fall back.

#### Context located

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

#### Witnesses (GHC 9.6.4, llmll 0.33.2)

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

#### Answer to question 1: can `bytes-slice` be reflected partially without a false `refuted`?

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

#### Gaps and hazards

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

#### Critique of the remaining points

- **One type or two (question 4).** Two types is right for LLMLL. A single type with an optional length is the Liquid Haskell approach: one `ByteString` with a length measure and refinement subtyping between `{v | len v = n}` and the plain type. LLMLL excludes refinement subtyping (`LLMLL.md:18`). The four head-syntax readers of `TBytes n` would also break. This is a scope divergence from Liquid Haskell, not a soundness defect. The shared SMT sort makes the identity reflection of P2 possible, so the two types cost nothing in the verifier.
- **Narrowing (`BYTES-NARROW-1`).** When it ships, give it the `pre` form `bytesLen(b) = n` (PROVE), take `n` from the determining context as `bytes-zero` does, and reflect it as the identity. Do not give it a `Result` form. A `Result` payload of array sort is not admissible (`FixpointEmit.hs:3373`), and FACT-AG-LEN gives a `match` binder no length. A narrowed value passed to a `bytes[n]` parameter would then face a call-pre `bytesLen(arg) = n` that no fact can discharge.
- **Separate JSON kind `bytes-unsized`.** Correct. An optional key would make a dropped `length` a silent type change.
- **The `LlmllBytes` class.** Sound. The emitter keeps one name for each operation, and `emitApp` already converts `bytes_length` to `Integer` (`CodegenHs.hs:2380`). Each instance is new trusted code under `codegen_semantics_version`, as Rev 0 says.
- **Replay and the event log (question 3).** Neither (b) nor (c) changes determinism. The console event log records stdin lines and stdout text, not `Response` values. `wasi.fs.read-bytes` in console mode is as deterministic as `wasi.fs.read`: both depend on the file. Byte stdio is refused in console mode. The only difference is the encoding that a future `REPLAY-INJECT` must choose for an `RBytes` payload. That is a deferred format decision, not a reason to prefer (c).
- **The breaking change.** The census is an upper bound, and it is the right metric. A body-faithful `Response` match already covers `RList` with a wildcard (`LLMLL.md:2174-2176`), so most verified code does not break. The diagnostic must name `RBytes` and the one-line repair. Rust's `#[non_exhaustive]` would avoid the next break, but it removes the missing-arm error that agents rely on. Do not adopt it.
- **Literature position.** Dafny (`bv8`, `seq<bv8>`) and F\* (machine integers) choose QF-BV. LLMLL chooses unbounded `int` with exact linear cases. That choice cannot verify mixing functions such as a ChaCha20 quarter round. Rev 0 states this plainly, and the statement is accurate. P7 recovers range facts. It does not recover functional correctness of XOR mixing. That still needs the `machine-int` opt-in named in `LLMLL.md` §3.1.

#### Recommendation

1. **Adopt the abstraction verdict rule** from the answer to question 1. UNSAFE on a VC that contains a builtin abstraction or an opaque call result reports the fallback outcome with cause `abstraction:app:<name>`, not `refuted`. File it as its own row. It also closes the false `refuted` of `CALL-CONGRUENCE-1`.
2. **Fold `BYTES-PARTIAL-REFLECT-1` into v1** with the length and range facts of P1. Then the `bytes-slice` and `string-code-at` preconditions are PROVE obligations, as Rev 0 intends.
3. **Reflect `bytes-widen` as the identity** (P2). Remove its assumed post.
4. **Keep the three exact bitwise forms.** Restate their soundness without non-negativity (P3). Add the mask and shift-size side conditions (P4).
5. **Move `BITWISE-WIDTH-1` from the parking lot to a row** that ships after the verdict rule (P7).
6. **Keep (b).** Amend criterion 1 with the decoding-step wording (P5). Add the `typeToSort` clause and the `Response` regression gate (P6).
7. **Repair the examples** (P8) and close risk 3 with W5 and W6 (P9).
8. **Ship order.** `BITWISE-1` (exact forms only) and `CHAR-CODE-1` can ship first, as Rev 0 proposes. Neither needs the verdict rule to be sound; both gain from it later with no surface change. Ship the verdict rule before `BYTES-UNSIZED-1`. Then ship `BYTES-UNSIZED-1`, `BYTES-READ-1` and `BYTES-WRITE-1` in one release, so the `Response` break happens once and the arm never exists without its value type. Ship `BITWISE-WIDTH-1` and `FFI-BYTES-1` after that, in either order.

#### Open questions for the language-team

1. Specify the classification of "abstracted term" as a syntactic predicate on the emitted VC. State whether a `RespFact.hs` arm fact counts as an abstraction. It is a true but incomplete fact about a builtin result, so by the rule above it should.
2. Specify the trigger set for the `BITWISE-WIDTH-1` width fact: which ground `w` values are instantiated, and whether the fact is emitted per `band` term or per function.

### Pass 2 (on the Rev 1 P1 narrowing, 2026-10-31)


**Verdict: accept with change.** The count condition is correct. Its scope is too narrow. Rev 1 applies the count only to uncontracted callees and function-typed parameters. A contracted callee has the same encoding, so it has the same defect.

#### Restatement

Rev 1 "Part 0", clause 2, makes an opaque call result abstracted only when the VC holds two or more calls to the same callee. The list "These are **not** abstracted" exempts "the result of a contracted callee under assume-guarantee" without a count. The question is whether a single-call UNSAFE is a true refutation, and whether the two-call condition covers every case where the encoding is weaker than the semantics.

#### Context located

1. `docs/design/byte-io-proposal.md` Rev 1, "Part 0": clause 2, the "not abstracted" list, and "Why one opaque call is not abstracted".
2. `compiler/src/LLMLL/FixpointEmit.hs`, `bodyToPredM`, the contracted-callee branch: it returns a `CallVC` with `cvResultVar = resultVar`, a fresh `_call_g_N` binder per call site, and the callee post as `cvPostAssumption`. No equality between two call binders is emitted.
3. `LLMLL.md` §5.3.3, "Opaque calls add no symbol": an uncontracted call is a fresh binder; two equal calls get unrelated binders.
4. `LLMLL.md` §4.4.1, the `refuted` note: "disproved"; a caller gets `depends-on-refuted` because "its assume-guarantee proof rests on a postcondition known to be false".
5. `LLMLL.md` §0 (anchor `nc-005`): the caller proves the callee `pre` and assumes the callee `post`.
6. `docs/compiler-team-roadmap.md`, row `CALL-CONGRUENCE-1`: describes only uncontracted and parameter callees. Its cheap form is CSE in `aNormalizeBody`.
7. `docs/design/fn-param-uf-1-proposal.md` Rev 0, witness table: W3 (true refutation), W5 (false refutation), W6 (true refutation; the parameter's return refinement is not assumed).

#### Witnesses (llmll 0.33.2)

In each case `g` is `(def-shell g [x: int] -> int (post (>= result 0)) (if (< x 0) (- 0 x) x))`. It is contracted and verifies body-faithful.

| ID | Caller | Today | Concrete truth | Rev 1 |
|---|---|---|---|---|
| A1 | `h [a: int]`, post `(= result 0)`, body `(- (g a) (g a))` | refuted | true | **refuted (false)**: `g` is contracted, so it is exempt |
| A2 | `h8 [a: int b: int]`, post `(>= result 0)`, body `(if (= a b) (- (g a) (g b)) 0)` | refuted | true | **refuted (false)**. CSE in `aNormalizeBody` does not fix this, because `a` and `b` differ as syntax |
| A3 | `h1 [a: int]`, post `(>= result (- 0 a))`, body `(g a)` | refuted | true | refuted: correct under the modular reading (P16) |
| A4 | `fib`-shaped `f [n: int]`, pre `(>= n 0)`, post `(>= result 0)`, body `(if (< n 2) n (- (f (- n 1)) (f (- n 2))))` | refuted | false (`f 4 = -1`) | refuted. Under the P15 rule it becomes the fallback outcome |
| A5 | post `(= result (g a))`, body `(g a)` | caller falls back | — | not affected: a call in a contract is outside the fragment |
| A6 | `(string-length "abc")` and `(string-length (string-concat s "x"))` | fall back, `Refused by: app:string-length` | — | not affected |

#### Findings

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

#### Recommended rule text

Replace clause 2 of "Abstracted term" in Rev 1 "Part 0" with:

> 2. It is the result binder of a call that the VC encodes as a fresh binder: a call to a named callee, contracted or uncontracted, including a self-call or a call to a member of the same recursive cycle, or a call through a function-typed parameter. The VC must also hold two or more such calls to the same callee. Calls are counted in the constraint's environment, and the arguments are not compared.

Replace the entry "the result of a contracted callee under assume-guarantee" in the "not abstracted" list with:

> the result of the only call to a callee in the VC, contracted or not.

Change "`refuted` is relative to stated contracts" to "`refuted` is relative to the callee contracts that the verifier assumes".

#### What the proposal must add to settle

1. Add A1, A2 and A4 to the fixtures in "Verdict changes to existing programs". A1 and A2 move from `refuted` to the fallback outcome. A4 also moves, and the record must state this cost.
2. Widen the `CALL-CONGRUENCE-1` row text to include contracted callees, and record A2 as the witness that CSE does not cover. Note P18 as the candidate cheap form.
3. Route P16's wording change for `LLMLL.md` §4.4.1 to the documentation-lead as a new drift item.

After these three changes, I have no open item. The proposal can settle.
