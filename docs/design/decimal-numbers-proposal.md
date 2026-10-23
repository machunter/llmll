---
title: DECIMAL-1 — a numeric surface for non-integer numbers
status: Rev 1 draft, 2026-10-23 (FLOAT-LIT-1 decisions settled for the engineer; Rev 0 direction user-approved 2026-10-21; not yet reviewed)
rows: DECIMAL-1 (G7, PLAN, after SIGMA-CONST-ARITH-1); FLOAT-LIT-1 (G3, PLAN, independent); FLOAT-OPS-1 (G7, DECIDE, trigger-gated); STR-TO-INT-STRICT-1 (G7, DECIDE)
review: none (no professor pass)
---

# DECIMAL-1: a numeric surface for non-integer numbers

**Status: Rev 1 draft, 2026-10-23.** Rev 1 settles three `FLOAT-LIT-1` decisions that Rev 0 left open, from the engineer's measurements. See "Rev 0 → Rev 1" below. Nothing else in Rev 0 changes.

**Rev 0, 2026-10-21.** The language-team wrote this proposal on 2026-10-21 from a real-program probe. The user approved the direction the same day. No professor pass was made. There is no earlier numeric, decimal or float proposal in this folder, so this is the base draft.

**User decisions recorded with Rev 0.**

- `DECIMAL-1` is sequenced after `SIGMA-CONST-ARITH-1`.
- `FLOAT-LIT-1` proceeds independently.
- `FLOAT-OPS-1` and `STR-TO-INT-STRICT-1` stay DECIDE.

### Rev 0 → Rev 1 (2026-10-23)

Source: the compiler-engineer's `FLOAT-LIT-1` measurements on `b8691124`. The compiler source is unchanged since then, at `2628c5fc` (v0.31.0). The user asked the language-team to settle three decisions before implementation.

| Change | Why | Where |
|---|---|---|
| The literal `-0.0` denotes `+0.0` in both front ends | JSON already reads `-0.0` as `0.0`, and the Layer 2 canonical-zero rule wants one zero | Decision R1-1 |
| Pattern key `literal_kind` (`int` or `float`) is added; the schema goes from 0.13.0 to 0.14.0, additive | aeson cannot tell `2` from `2.0`, so a float pattern `2.0` round-trips as an int pattern | Decision R1-2 |
| A literal pattern whose type is incompatible with the scrutinee is a check error; it was a warning | LLMLL has no implicit `int` to `float` conversion in expressions, so patterns must not have one either | Decision R1-2 |
| A lexical definition of FLOAT for §12, the RFC 8259 number grammar without the sign, that must have a fraction or an exponent | §12 names FLOAT and does not define it; the parser accepts `00.5` and `1e+3` and refuses `1.` and `.5` | Decision R1-3 |
| New drift D7: an exponent is read as a bounded `Int`, so `1e18446744073709551617` compiles as `10.0` | Measured by the engineer in both front ends; the exponent wraps | Drift list, R1-3 |
| New drift D8: codegen emits a negative float literal bare, so the pattern `(Box -0.5)` fails in GHC | Measured by the engineer | Drift list, R1-1 |
| `float-literal-range` is reported by `llmll check` in phase `parse` | The decision needs the literal text, which only the parser has | R1-3 |
| `JSON-INT-UNBOUNDED-1` is outside `FLOAT-LIT-1` | It concerns `int`, not `float` | R1-4 |

#### Decision R1-1: the literal `-0.0` denotes `+0.0`

The alternatives were to reject `-0.0`, or to keep IEEE negative zero.

- **Rule.** A float literal whose value is zero denotes `+0.0`, whatever its sign or spelling. This covers `-0.0`, `0e5` and `-0.000`. Codegen emits `0.0` for each of them.
- **No information an LLMLL program can see is lost.** The mathematical value of `-0.0` is 0. LLMLL `=` lowers to Haskell `==`, for which `-0.0 == 0.0` is true. There is no float printing, division or ordering until `FLOAT-OPS-1`.
- **The two front ends already agree.** aeson's `Scientific` has no negative zero, so JSON `-0.0` already reads as `0.0`. Keeping IEEE negative zero would need a new raw-byte rule in the JSON reader in order to create a value that the language cannot observe.
- **Rejecting is worse.** `-0.0` is a reasonable way to write zero. A diagnostic would tell the author nothing they need to act on.
- **It fits Layer 2.** Under `FLOAT-OPS-1`, every operation result changes negative zero to positive zero. With this rule, the literals and the operation results come from the same set: finite doubles with one zero.
- **The FFI is the only place negative zero can still come from.** Until `FLOAT-OPS-1`, a Tier 1 `float` result can still be negative zero. The Layer 2 forcer `llmll_uF` closes this; R1-1 does not.
- **Soundness.** No verifier fact depends on a `float` value, because `float` is a carrier sort outside `Σ_auto` (§5.3.3). `codegen_semantics_version` is not spent.
- **Positive witnesses.** These are codegen hspec cases:
  - `(def z [] -> float -0.0)` emits `0.0`, and `isNegativeZero` of the emitted value is `False`.
  - `(def n [] -> float -0.5)` emits `(-0.5 :: Double)`.
  - The pattern `(Box -0.5)` emits `(Box (-0.5 :: Double))`. This fixes D8, and GHC accepts it.
  - The JSON `lit-float` with value `-0.0` gives the same `0.0`.

#### Decision R1-2: a `literal_kind` pattern key, and incompatible literal patterns become errors

The engineer's default is confirmed, with one widening. The alternative was a type-directed rule, under which `2` matches a `float` scrutinee by value. It is rejected.

- **Key.** A JSON-AST `literal` pattern gains the optional key `"literal_kind"`, with values `"int"` and `"float"`. The name follows the snake_case style of `return_type` and `pre_clauses`. The schema goes from 0.13.0 to 0.14.0. The change is additive, and every older version stays readable.
- **Reading the key.**
  - If the key is absent, the reading is the same as today: an integral number is `int`, and any other number is `float`.
  - `"literal_kind": "float"` with the number `2` reads as the float `2.0`.
  - `"literal_kind": "int"` with the number `2.5` is a parse error.
  - The key on a string or boolean value is a parse error.
- **Writing the key.** `AstEmit` writes `"literal_kind": "float"` on every float pattern. With that, the S-expression → JSON → S-expression round trip of a float pattern is exact.
- **Why not the type-directed rule.** In expressions, `(def n2 [] -> float 1)` is a type error today ("expected float, got int", measured on v0.30.10). A type-directed pattern rule would add an `int` to `float` conversion in patterns alone, and the S-expression meaning of `2` would then depend on the scrutinee's type. One literal type rule for expressions and patterns is simpler to state and to check.
- **The widening.** The engineer's default makes an error of an `int` literal pattern against a `float` scrutinee. Rev 1 makes an error of every literal pattern whose type `compatibleWith` refuses. Today these are warnings, emitted where `checkPatternExpanded` handles `PLiteral` in `compiler/src/LLMLL/TypeCheck.hs`.
- **Only one case changes behaviour.** Every other incompatible pair (a string against an `int`, or a boolean against an `int`) already fails in GHC. Only an `int` literal against a `float` scrutinee compiles today, because a Haskell numeric literal pattern is overloaded. So the widening refuses no program that builds today, except that one.
- **The corpus has no case.** A grep of the tracked `.llmll` files found float-shaped text only inside strings.
- **Gate.** In a corpus sweep, no new error may appear except the `int`-against-`float` case.
- **Channel.** Type, reported by `llmll check`.
- **Positive witnesses.**
  - `(match x (2 a) (_ b))` with `x: float` is a check error.
  - `(match x (2.0 a) (_ b))` with `x: float` passes.
  - Emitting that program to JSON writes `"literal_kind": "float"`. Reading it back gives `LitFloat 2.0`, not `LitInt 2`, which closes D6.

#### Decision R1-3: the lexical definition of FLOAT, and how the two front ends relate

**§12 text:**

```
literal  = INT | "-" INT | FLOAT | "-" FLOAT | STRING | "true" | "false" ;
FLOAT    = DIGITS ( FRAC [ EXP ] | EXP ) ;
DIGITS   = "0" | NZDIGIT { DIGIT } ;
FRAC     = "." DIGIT { DIGIT } ;
EXP      = ( "e" | "E" ) [ "+" | "-" ] DIGIT { DIGIT } ;
```

- **FLOAT is the RFC 8259 `number` production without its leading `-`, and with a fraction or an exponent required.** The sign belongs to the `"-" FLOAT` production, as the `"-" INT` production carries the sign of INT.
- **Accepted:** `0.5`, `1.25e-3`, `1e3`, `1E+3`, `-0.5`.
- **Refused:**
  - `1.` and `.5`: the parser refuses them today, and so does RFC 8259.
  - `00.5` and `01e3`: leading zeros. RFC 8259 refuses them; the parser accepts them today.
  - A leading `+` such as `+0.5`: §12 has no `"+" INT` either.
- **Value.** A FLOAT denotes the exact decimal value its digits and exponent spell. It is rounded to the nearest double, with ties to even.
- **Range.** The literal is refused with `float-literal-range` in either of two cases:
  - The rounded magnitude is infinite.
  - The decimal value is not zero, but it rounds to zero.
  Subnormal results are accepted.
- **Exponent text (D7).** The exponent is read as text, and its size is not limited by a machine integer. A very large exponent gives `float-literal-range`. It must never wrap. The engineer's plan uses the S-expression lexer and a raw-byte pre-scan for JSON. That plan meets this rule.
- **Phase.** `float-literal-range` needs the literal's text, so `llmll check` reports it in phase `parse`.
- **S-expression and JSON.** The two front ends must accept the same set of float values. They need not accept the same set of spellings.
  - JSON follows RFC 8259, and the node kind (`lit-float`), not the spelling, marks a float. So JSON `2` under `lit-float` is the float `2.0`. In the S-expression syntax, `2` is an INT.
  - The two kinds of input share one range rule and one rounding rule, so a value accepted by one front end is accepted by the other.
  - Every accepted FLOAT, with or without its sign, is also a valid RFC 8259 number. So `AstEmit` can write any S-expression float without changing its value.
- **The leading-zero refusal changes accepted input.** The tracked corpus has no such literal. INT is not changed: `007` stays a valid INT. That asymmetry is known, and it is left alone because INT is outside this row.
- **Unary minus stays a type error.** `(- 0.5)` remains a type error until `FLOAT-OPS-1`: the `-` operator takes two `int` operands. `float-neg` is the Layer 2 name. A negative float is written as the literal `-0.5`.
- **Channel.** Type (a parse-phase diagnostic). No solver obligation exists.
- **Positive witnesses.**
  - `(def big [] -> float 1e400)` gives `float-literal-range`.
  - `(def t [] -> float 2e-324)` gives `float-literal-range`. It is below half the smallest subnormal, so it rounds to zero.
  - `(def s [] -> float 4.9e-324)` is accepted, as the smallest subnormal `5.0e-324`.
  - `(def w [] -> float 1e18446744073709551617)` gives `float-literal-range`. Today it is `10.0` (D7).
  - `(def l [] -> float 00.5)` is a parse error.
  - `(def p [] -> float 1E+3)` is accepted as `1000.0`.

#### Decision R1-4: `JSON-INT-UNBOUNDED-1` is outside `FLOAT-LIT-1`

A JSON `lit-int` above 2^63 is refused, although `int` is unbounded. That is an `int` defect and does not belong to the float row. It is filed as its own row, G3, PLAN.

- **Shared code, separate rows.** It can share the raw-byte number pre-scan with D7, and the engineer may ship the two together.
- **D7 stays inside `FLOAT-LIT-1`.** The JSON `lit-int` exponent wrap (`1e18446744073709551617` read as `10`) is part of D7. It is fixed in this row, because it is the same exponent reader.

## Restatement

A csv-report probe on v0.30.10 needed decimal numbers. It parsed values such as `"12.50"`, `"+3.10"` and `"1e3"`, and computed their sum, minimum, maximum and mean. `float` is listed as a type in `LLMLL.md` §3.1, but it has no operations. The probe therefore wrote about 35 lines of fixed-point arithmetic in millionths over `int`. In that code, `(* x 1000000)` fell back as nonlinear. That is the `SIGMA-CONST-ARITH-1` gap.

The question is which non-integer numeric surface LLMLL ships. The measure is the verification story: `Σ_auto` is QF-LIA-based, so a floating-point contract cannot be discharged.

Two reference classes apply. The measurement set is the probe's Python reference, which used `Decimal`, not `float`. The design-reference set is Dafny `real`, Liquid Haskell `Double` and F\*.

## Context located

1. `docs/design/INDEX.md`: no numeric, decimal or float proposal exists. Three drafts are adjacent:
   - `docs/design/int-3-machine-int-sketch.md` covers bounded `int` only.
   - `docs/design/native-json-proposal.md` D-3 deferred a `float` JSON projection because it lands outside `Σ_auto`.
   - `docs/design/equality-capable-types-proposal.md` does not mention `float`.
2. `LLMLL.md` §3.1 says `float` is a "64-bit IEEE 754 double", with the examples `3.14` and `-0.5`.
3. `LLMLL.md` §13.1, §13.2 and §13.7 define every arithmetic, ordering and numeric utility over `int` only. §13.2 lists `float` under `=` as "numeric/value equality". It says nothing about NaN or negative zero.
4. `LLMLL.md` §13.13 stores JSON numbers as source lexemes. `json-get-number` and `json-as-number` return a string. The family has `json-of-int`, but nothing can emit a non-integer JSON number.
5. `LLMLL.md` §5.3.3 classes `float` as a carrier sort outside `Σ_auto`, "rejected inside int predicates".
6. `compiler/src/LLMLL/TypeCheck.hs`:
   - In `builtinEnv`, no name takes or returns `TFloat`.
   - The only producer of `TFloat` is `inferLiteral` on `LitFloat`.
   - `coreExcludedBuiltins` is the def-shell-only mechanism. Its comment limits it to names whose fallback is unconditional.
7. `compiler/src/LLMLL/CodegenHs.hs`:
   - `float` lowers to `Double`.
   - `emitLit` prints a float literal with `show`.
   - `string_to_int` is implemented with `reads`.
8. `compiler/src/LLMLL/Parser.hs` `pLiteral` reads an unsigned float with `L.float`, which accepts an exponent. `compiler/src/LLMLL/Lexer.hs` `pNumberLit` has no exponent, but only `compiler/test/Spec.hs` imports that module.
9. `compiler/src/LLMLL/FixpointEmit.hs` `typeToSort` has no `TFloat` arm, so `TFloat` falls through to the `FQInt` default. The JSON-1 comment on the `Json` arm calls that fall-through a trap.
10. `compiler/src/LLMLL/Ffi.hs` and `docs/design/ffi-tier1-proposal.md` D3: `float` crosses the boundary as `Double`, with forcer `llmll_uW`. No D10 boundary type involves `Double`.
11. `compiler/src/LLMLL/ProofArtifact.hs` sets `codegenSemanticsVersion` to `"int-unbounded-1"`. `CHANGELOG.md` (v0.23.8 and the entry above it) limits the stamp to `int` versus `machine-int`. It records that `INT-3` needs the stamp unspent.
12. `docs/compiler-team-roadmap.md`, row `SIGMA-CONST-ARITH-1` (MEASURE). Its target is multiplication by a numeral, and integer division and `mod` by a numeral `k > 0`.

### What `float` does today (measured on v0.30.10)

- **Literals.** `1.5` and `1e3` are accepted. `1e3` is emitted as `1000.0`.
- **Equality.** `(= x y)` at `float` type-checks. It lowers to Haskell `==`.
- **Everything else is refused.** `(+ x y)`, `(< x y)` and `(- 0.0 0.5)` fail with "expected int, got float". There is no float parse, print or conversion, and no JSON projection.
- **The verifier.** A `post (= result x)` over a `float` falls back, reported as "Refused by: var". The post is assumed, not proved.
- **What can carry a `float`.** A `float` can be a parameter, a return value or a sum-type payload. PBT generates it with `arbitrary :: Gen Double`, and FFI Tier 1 passes it as `Double`.

### Spec and code drift

- **D1.** `LLMLL.md` §3.1 gives `-0.5` as an example value. The parser refuses it ("unexpected '.'"). The §12 literal grammar (`"-" INT | FLOAT`) agrees with the code. No negative `float` can be written at all. The table should move, or the grammar should gain `"-" FLOAT`. This proposal takes the second option, in `FLOAT-LIT-1`.
- **D2 (defect).** `1e400` passes `llmll check`, but codegen emits the bare identifier `Infinity`. GHC does not have that name in scope, so the build fails. `1e-400` silently becomes `0.0`. The cause is that `L.float` converts to `Double` with no range check. The code should move.
- **D3 (latent).** `typeToSort TFloat` resolves to `FQInt`. The fallback firewall stops it today (measured). It is the same trap the JSON-1 comment names. The code should move.
- **D4.** §13.2 calls float `=` "value equality". It is an equivalence today only because no NaN reaches the surface. A negative zero cannot be written either.
- **D5 (adjacent).** `string-to-int` accepts `" 42"` and `"(42)"` (measured through `reads`). §13.7 says only "Parse; Error on failure". The strict `decimal-parse` below would disagree with it.
- **D7 (Rev 1, measured by the engineer).** megaparsec and aeson read a float exponent as a bounded `Int`. `1e18446744073709551617` compiles as `10.0`, and as `10` for a JSON `lit-int`. See R1-3.
- **D8 (Rev 1, measured by the engineer).** `emitLit` prints a float literal bare, so a negative float in a pattern such as `(Box -0.5)` fails in GHC. Codegen emits `(-0.5 :: Double)`. See R1-1.
- **D6 (minor).** `parseLiteralValue` in `compiler/src/LLMLL/ParserJSON.hs` turns an integral JSON number into `LitInt`. A float pattern literal `2.0` therefore becomes an `int` pattern.

## Design proposal

**Recommendation: two layers.** Option (c) ships now, option (a) is designed here and deferred behind a trigger, and option (b) is rejected for now.

- **Layer 1, option (c): `DECIMAL-1`.** It provides exact decimal arithmetic over `int`, with an explicit scale, through four builtins.
  - `int` arithmetic is already in `Σ_auto`. Scaled `+`, `-` and comparison are QF-LIA today.
  - After `SIGMA-CONST-ARITH-1`, rescaling by a numeral and rounded division by a numeral are QF-LIA too.
  - The results match the probe's `Decimal` reference exactly. IEEE double would not: `0.1 + 0.2` gives `0.30000000000000004`.
- **Layer 2, option (a): `FLOAT-OPS-1`, DECIDE, trigger-gated.** It is an IEEE-double op set with finite-only semantics. It is def-shell-only and `asserted`. The semantics are fixed below, so that the `FLOAT-LIT-1` fixes do not decide them by accident.
  - **Trigger.** The first program that needs non-decimal math (square root, exponent or logarithm), or IEEE storage. The MultiLangBench SQLite `REAL` storage class is the expected case (`docs/design/multilangbench-scope-evaluation.md`).
- **Option (b), rejected for now: an exact `rational` or `real` type.** This is Dafny's path.
  - It needs a new theory in `Σ_auto` (linear real, or mixed integer and real, arithmetic), and the §5.3.3 statement would grow.
  - liquid-fixpoint's support for the real sort has not been measured.
  - A rational such as 1/3 still needs a scale and a rounding mode before it can be printed, so the surface becomes Layer 1's anyway.
  - The product of two values stays nonlinear.
- **Also rejected for now: a typed-scale `decimal[s]`.** This would be a scale-indexed type in the style of `bytes[n]`, lowered to `int` in the solver and in codegen.
  - It would catch a scale mismatch at type-check time.
  - It costs a new type constructor and polymorphic operators, and no scale-mixing defect has been seen yet.
  - It has the same representation as Layer 1, so moving to it later is a mechanical change.
- **Not followed: Liquid Haskell's encoding.** As we understand it, Liquid Haskell embeds `Double` in the SMT real sort. That encoding ignores IEEE rounding, NaN and overflow, so it is unsound for them. LLMLL does not reflect `float` into any sort.

### Layer 1 surface (`DECIMAL-1`)

| Name | Signature | Contract | Semantics |
|---|---|---|---|
| `decimal-parse` | `string int -> Result[int, string]` | `(pre (and (>= k 0) (<= k 4096)))` | `(decimal-parse s k)` is `ok v`, where `v` is the value of `s` times ten to the power `k`, exactly. It is `err` when that product is not an integer. It never rounds silently. |
| `decimal-format` | `int int -> string` | `(pre (and (>= k 0) (<= k 4096)))` | `(decimal-format v k)` writes `v` divided by ten to the power `k`, with exactly `k` fractional digits. It writes no exponent and no `+`. It writes `-` only when `v < 0`, and no point when `k = 0`. |
| `div-half-even` | `int int -> int` | `(pre (!= d 0))` | `(div-half-even n d)` is the exact quotient of `n` by `d`, rounded half to even. This is the IEEE 754 default mode and the `Decimal` default context. Floor division stays the job of the existing operator. |
| `json-of-number` | `string -> Result[Json, string]` | none | It is `ok` exactly when `s` matches the RFC 8259 `number` production. The lexeme is stored and serialized verbatim, as §13.13 specifies. |

**Parse grammar.** The grammar is ASCII-only and locale-free:

```
[+-]? ( D+ ('.' D*)? | '.' D+ ) ( [eE] [+-]? D+ )?        where D = [0-9]
```

- **No trimming.** The caller trims. This differs from `string-to-int` (D5).
- **Refused inputs.** `"NaN"`, `"inf"`, `"1,5"`, `"1_000"`, `""`, `"."` and `"1e"` are all `err`.
- **Exponent bound.** An exponent whose absolute value exceeds 4096 is `err`. This stops input from forcing a very large `Integer`.
- **JSON numbers are a subset.** The RFC 8259 number grammar is a subset of this grammar, so the result of `json-as-number` goes straight into `decimal-parse`.

**Round-trip law.** For `0 ≤ k ≤ 4096`, `(decimal-parse (decimal-format v k) k)` is `(ok v)`.

**Division of work.** `decimal-parse`, `decimal-format` and `json-of-number` go in `coreExcludedBuiltins`, so they are def-shell-only.

- **The JSON precedent applies.** These names are never reflected, so a `def` that calls one always falls back. The exclusion makes that fallback visible at `check` time.
- **Results re-enter `Σ_auto`.** Their `int` results are ordinary integers. The intended shape is to parse in a `def-shell`, then decide in a `def` (§13.13, Verification).
- **`div-half-even` is admitted in `def`.**

**The probe, rewritten.**

- `parse-number` becomes `(decimal-parse (string-trim raw) 6)`.
- `format-fixed` and `pad6` become `decimal-format`. Trimming zeros stays a six-line user definition.
- The probe's own `div-round` becomes `div-half-even`. The name `div-half-even` was chosen so that it does not collide with that user definition.
- JSON output uses `(json-of-number (decimal-format x 6))`.

A grep of the repository's `.llmll` files finds no collision with any of the four new names.

**Reflecting `div-half-even`.** The builtin is reflected by unfolding its definition, as §13.7 does for `abs`, `min` and `max`. For a positive numeral `d`, the definition is:

```
div-half-even(n, d) == let q = (n div d), r = (n mod d) in
                       if 2r > d then q + 1
                       else if 2r < d then q
                       else q + (q mod 2)
```

- **When it is linear.** The unfolding is linear once `SIGMA-CONST-ARITH-1` admits `div`, `mod` and multiplication by a numeral.
- **No new axiom.** It adds no assumed post, so the closed sealed-builtin axiom set of §13.12 does not change.
- **Other divisors.** For a non-numeral or negative `d`, the result is not reflected. The call falls back with a `nonlinear:` cause, and the precondition is still proved.

**Codegen.**

- Every Layer 1 value is a Haskell `Integer`.
- `decimal_parse` is written by hand in the generated preamble. It uses neither `reads` nor `Data.Scientific`, which keeps the zero-dependency rule of the JSON preamble.
- `decimal_format` uses `quotRem` on the absolute value.
- `div_half_even` follows the definition above with Haskell `div` and `mod`, which round toward negative infinity. A negative `d` is normalized by negating both operands.

**Schema delta.** None. The new builtins are names, and `lit-float` does not change.

**Strict immutability.** Every name is a pure function that is total or `Result`-valued. None has state or an effect.

### `FLOAT-LIT-1`: drift fixes, independent of both layers

- **Grammar.** Add `"-" FLOAT` to the §12 literal grammar and to `pLiteral` in `compiler/src/LLMLL/Parser.hs`. Fix the §3.1 example to match.
- **Range check.** Reject at `check` time, with diagnostic `float-literal-range`, any literal that converts to positive or negative infinity. Reject any non-zero literal that converts to `0.0` in the same way. Apply this in the S-expression parser and in `compiler/src/LLMLL/ParserJSON.hs`.
- **Sort.** Give `typeToSort TFloat` an explicit opaque-carrier arm or an explicit refusal, instead of `FQInt`.
- **Spec.** State in §3.1 that `float` has literals and `=` only, until `FLOAT-OPS-1` ships.
- **JSON patterns.** Fix D6 in the same row.
- **Rev 1.** The meaning of `-0.0`, the D6 mechanism and the FLOAT lexical definition are settled in R1-1 to R1-3. D7 and D8 are in this row. The schema goes to 0.14.0 (R1-2); the "no schema change" statement applies to Layer 1 only.

### Layer 2 semantics, fixed now (`FLOAT-OPS-1`)

- **Finite only.** Every float operation checks its result. A NaN or infinite result is a runtime error, `FloatNonFinite`, in the same category as `DivisionByZero` from the integer division operator.
- **Canonical zero.** A negative-zero result becomes positive zero.
- **What this buys.** Every `float` value is a finite double, and there is one zero. On that set IEEE `==` is identity. So `=` is reflexive, an equivalence and a congruence, and `float` stays an equality-capable type. `map[float,v]` keys stay valid. This is why the trap is chosen over IEEE NaN semantics.
- **Determinism.** The IEEE 754 NaN row of the non-determinism table in `LLMLL.md` no longer applies.
- **Arithmetic and ordering.**
  - Arithmetic: `float-add`, `float-sub`, `float-mul` and `float-div`. `float-div` traps on a zero divisor.
  - Ordering: `float-lt` and `float-le`, a total order on the finite set.
  - `float-neg`, `float-abs`, `float-min` and `float-max`.
  - `float-sqrt`, which traps on a negative argument.
- **Conversions.**
  - `int-to-float` is correctly rounded, half to even, through `fromRational . toRational`. A magnitude that overflows traps.
  - `float-floor`, `float-ceiling`, `float-truncate` and `float-round` map `float` to `int`. `float-round` is half to even, which is Haskell's `round`. The conversion is exact for finite input.
- **Parse.** `float-parse` has type `string -> Result[float, string]`. It uses the `decimal-parse` grammar and rounds to nearest, ties to even. It is `err` on overflow, and on a non-zero value that underflows to zero.
- **Print.** `float-to-string` prints the shortest digits that identify the value, using GHC `floatToDigits`.
  - It lays them out by the ECMAScript `Number::toString` rule: positional notation for decimal exponents from -6 up to, but not including, 21, and exponent notation outside that range.
  - The round-trip law is that `(float-parse (float-to-string x))` is `(ok x)`.
- **JSON.** A float goes to JSON as `(json-of-number (float-to-string x))`. No `json-get-float` is added, which keeps D-3 of `docs/design/native-json-proposal.md` in force.
- **Def-shell only.** Every `float-*` name goes in `coreExcludedBuiltins`.
- **FFI.** The FFI Tier 1 forcer for a `float` result changes from `llmll_uW` to a checking `llmll_uF`. A Hackage export then cannot introduce NaN or negative zero. That is the only interaction with D10 of `docs/design/ffi-tier1-proposal.md`, and it needs no new boundary type.

## Edge cases and degenerate inputs

1. **Positive witness for parse.**
   - Inputs and results:
     - `(decimal-parse "+3.10" 6)` is `ok 3100000`.
     - `(decimal-parse "1e3" 2)` is `ok 100000`.
     - `(decimal-parse "12.50" 2)` is `ok 1250`.
     - `(decimal-parse ".5" 1)` is `ok 5`.
   - Channel: trust (sealed builtin, `asserted`, oracle battery).
   - Cite: the Layer 1 table.
2. **A value that is inexact at the scale.**
   - `(decimal-parse "1.234" 2)` is `err`, and `(decimal-parse "1.230" 2)` is `ok 123`. This matches the probe's limit of one to six fractional digits.
   - Channel: trust. The type channel forces the caller to handle the `err` arm.
3. **Negative zero, locale and unsupported forms.**
   - `(decimal-parse "-0.0" 2)` is `ok 0`.
   - `"1,5"`, `" 1"`, `"NaN"` and `"1e5000"` are `err`.
   - Channel: trust.
4. **Positive witness for the scale precondition.**
   - Input: a `def` with parameter `k: int` and no `pre` calls `(decimal-parse s k)` from a `def-shell` caller path.
   - Result: the PROVE call-site obligation `(>= k 0)` is refuted, not assumed. A numeral scale such as `6` discharges it trivially.
   - Channel: contract, QF-LIA.
   - Cite: the call rule of `LLMLL.md` §5.3.4.
5. **Format.**
   - `(decimal-format 1250 2)` is `"12.50"`.
   - `(decimal-format -5 2)` is `"-0.05"`.
   - `(decimal-format 0 2)` is `"0.00"`.
   - `(decimal-format 7 0)` is `"7"`.
   - Channel: trust, plus the round-trip law as a PBT property, which gives the `tested` tier.
6. **Positive witness for rounding.**
   - Ties:
     - `(div-half-even 7 2)` is `4`.
     - `(div-half-even 5 2)` is `2`.
     - `(div-half-even -7 2)` is `-4`.
   - Non-ties:
     - `(div-half-even 2 3)` is `1`.
     - `(div-half-even 1 3)` is `0`.
   - Proof: after `SIGMA-CONST-ARITH-1`, `(def h [n: int] -> int (pre (= n 7)) (post (= result 4)) (div-half-even n 2))` is body-faithful SAFE.
   - Refutation: the same definition with `(post (= result 3))` is refuted. Truncation would give 3. Half-up would agree on this tie, but it gives 3 on `(div-half-even 5 2)`.
   - Channel: contract, QF-LIA.
7. **A mean with a variable divisor.**
   - Input: `(div-half-even sum count)` with `(pre (> count 0))`.
   - The precondition `(!= count 0)` is proved in QF-LIA.
   - The value is not reflected. A post that the mean lies between the minimum and the maximum needs the sum to be at least `count` times the minimum, which is nonlinear.
   - Channel: contract, fragment (b). The post falls back to `asserted`, and it is not routed to Lean by default.
8. **A zero divisor.**
   - `(div-half-even n 0)` fails the PROVE obligation at `check` time.
   - When `d` is an unconstrained parameter, the obligation is refuted, so the caller needs a `pre`.
   - Channel: contract.
9. **JSON numbers.**
   - `(json-of-number "12.50")` is `ok`.
   - `"+3.1"`, `".5"`, `"1."` and `"NaN"` are `err` under RFC 8259.
   - The output of `decimal-format` always satisfies RFC 8259.
   - Channel: trust.
10. **Positive witness for the literal range (`FLOAT-LIT-1`).**
    - `(def big [] -> float 1e400)` gives `float-literal-range` at `check`. Today it passes `check` and fails the GHC build.
    - `1e-400` gives the same diagnostic.
    - `-0.5` parses.
    - Channel: type (a check-time diagnostic).
11. **The float layer (`FLOAT-OPS-1`).**
    - Traps:
      - `(float-div 1.0 0.0)` traps with `FloatNonFinite`.
      - `(float-mul 1e300 1e300)` traps.
    - Canonical zero: `(= (float-neg 0.0) 0.0)` is `true`.
    - Printing:
      - `(float-to-string 0.1)` is `"0.1"`.
      - `(float-to-string 1e21)` is `"1e+21"`.
    - Rounding: `(float-parse "0.1")` added to `0.2` gives `0.30000000000000004`. This is why Layer 1, not Layer 2, serves decimal data.
    - Channel: trust (runtime trap). The spec is silent on IEEE status flags, and that is intentional.

## Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| Scale precondition `0 ≤ k ≤ 4096` on `decimal-parse` and `decimal-format` | contract | (a) QF-LIA, PROVE at the call site | `LLMLL.md` §5.3.4 |
| Precondition `d ≠ 0` on `div-half-even` | contract | (a) QF-LIA | §5.3.4 |
| Value of `div-half-even` for a positive-numeral `d` | contract (body-faithful) | (a) QF-LIA after `SIGMA-CONST-ARITH-1`; (b) until then | `compiler/src/LLMLL/FixpointEmit.hs` reflection sites named in that row |
| Value of `div-half-even` for a variable `d` | contract | (b) nonlinear, falls back to `asserted`; Lean only on an explicit `?proof-required` | §5.3.3; §5.3.5, the row for multiplication, division and `mod` |
| Scaled `+`, `-`, `<` and `=` | contract | (a) QF-LIA today | §5.3.3, QF-LIA core |
| Rescale `(* x 1000000)` | contract | (a) after `SIGMA-CONST-ARITH-1`; (b) today | `docs/compiler-team-roadmap.md` |
| Correctness of parse and format, the round-trip law, and `json-of-number` validity | trust | no solver obligation: an `asserted` sealed builtin, an oracle battery at the build gate, and PBT for the `tested` tier | §13.13, Trust tier (the JSON precedent) |
| The finite invariant on every `float-*` result | trust | no solver obligation: def-shell-only, `asserted`, a runtime trap | §5.3.3 (`float` as a carrier sort) |

**Trust disclosure.**

- **Layer 1.** It adds no axiom to the closed set in §13.12. The trust report lists `decimal-parse`, `decimal-format` and `json-of-number` as `asserted` sealed builtins, in the same way as the JSON family.
- **Layer 2.** `float-*` is in `coreExcludedBuiltins`, so float code cannot appear in a `def`.
  - Every function that uses float code is a `def-shell` at tier `asserted`, or `tested` when PBT evaluates it.
  - `--strict-verified-core` refuses any closure that reaches such a function.
  - No new trust kind is needed.

**Version stamps.**

- **`codegen_semantics_version`.** Neither layer spends it. `int` codegen does not change, and no verifier fact depends on how `float` is generated. `INT-3` keeps the stamp unspent.
- **`checker_soundness_version`.** It does not change, because `Σ_auto` gains no theory. The `div-half-even` unfolding uses only symbols that `SIGMA-CONST-ARITH-1` admits.

**Equality-capable types.** Layer 1 values are `int`, so the rule of `docs/design/equality-capable-types-proposal.md` is unaffected. Under Layer 2, `float` stays equality-capable because finite-only semantics make `=` lawful (see Layer 2). Today `=` on `float` is lawful only because NaN cannot be reached (D4).

## Affected surface

- **`LLMLL.md`:**
  - §3.1: the `float` row, the `-0.5` example and a note that there are no operations.
  - §12: the literal grammar gains `"-" FLOAT`.
  - §13.2: a note that float `=` is an equivalence on finite canonical values.
  - §13.7: three new names.
  - §13.13: `json-of-number`.
  - §5.3.5: a matrix row for `div-half-even`.
  - The IEEE 754 row of the non-determinism table, when Layer 2 ships.
- **`compiler/src/LLMLL/TypeCheck.hs`:** `builtinEnv` gains four names. `coreExcludedBuiltins` gains `decimal-parse`, `decimal-format` and `json-of-number`.
- **`compiler/src/LLMLL/CodegenHs.hs`:** the preamble functions and the range check in `emitLit`. Under Layer 2, `llmll_uF` in `compiler/src/LLMLL/Ffi.hs` and the forcer generator.
- **`compiler/src/LLMLL/Parser.hs` and `compiler/src/LLMLL/ParserJSON.hs`:** signed float literals, the range diagnostic, and D6.
- **`compiler/src/LLMLL/FixpointEmit.hs`:** the `div-half-even` unfolding, after `SIGMA-CONST-ARITH-1`, and a `typeToSort TFloat` arm.
- **`compiler/src/LLMLL/PBT.hs` and the test evaluator:** implement the new names, so that `llmll test` evaluates the round-trip property instead of skipping it. The probe found the evaluator skips string builtins today.
- **`compiler/src/LLMLL/AgentSpec.hs`:** the builtin list, unless it is derived from `builtinEnv`.
- **`docs/llmll-ast.schema.json`:** no change.

**Additions and their soundness argument.**

- **Four builtins.** Each one is a pure function that is total or `Result`-valued.
- **`div-half-even`.** It is reflected only by unfolding its definition, so it adds no assumed post.
- **The other three.** They are never reflected and are excluded from `def`. No `def` can therefore depend on an unproved fact about them.

## Risks and open questions

1. **The scale is a value, not a type.** Classification: verification-ergonomics. Adding a scale-2 value to a scale-6 value type-checks. This complicates use but does not block the proposal. The upgrade path is `decimal[s]`, taken when a scale-mixing defect is seen.
2. **Layer 1 proves less before `SIGMA-CONST-ARITH-1`.** Classification: scope. Rescaling and `div-half-even` by a numeral fall back until that row ships. The user resolved this on 2026-10-21: `DECIMAL-1` is sequenced after `SIGMA-CONST-ARITH-1`.
3. **`string-to-int` accepts loose input (D5).** Classification: spec-drift. Two parsers in §13.7 would disagree on whitespace. Tightening `string-to-int` changes behaviour, so it has its own DECIDE row, `STR-TO-INT-STRICT-1`. This only matters at scale.
4. **The Layer 2 trap departs from IEEE.** Classification: scope. A program cannot use infinity as a sentinel value. The departure is intentional because it keeps `=` lawful. It matters only when `FLOAT-OPS-1` fires.
5. **The D2 build failure is live today.** Classification: soundness of the passage from `check` to `build`. `llmll check` accepts a program that GHC rejects. Its scope is small. `FLOAT-LIT-1` fixes it, and nothing here blocks it.

## Hand-off

- **Recommended option.**
  - Option (c) ships as `DECIMAL-1`, after `SIGMA-CONST-ARITH-1`.
  - `FLOAT-LIT-1` ships independently.
  - Option (a) is recorded as `FLOAT-OPS-1`, DECIDE, gated on the first program that needs IEEE math or IEEE storage.
  - Option (b) and `decimal[s]` are rejected for now, with an upgrade path.
- **Rows for the documentation lead to file:**
  - `DECIMAL-1` `[CT]`, G7, PLAN. Its prerequisite is `SIGMA-CONST-ARITH-1`.
  - `FLOAT-LIT-1` `[CT]`, G3, PLAN. It covers drift D1, D2, D3, D6, D7 and D8, under decisions R1-1 to R1-3.
  - `JSON-INT-UNBOUNDED-1` `[CT]`, G3, PLAN (Rev 1, R1-4). It is separate from `FLOAT-LIT-1`, but it may share the JSON number pre-scan.
  - `FLOAT-OPS-1` `[DESIGN]`, G7, DECIDE, trigger-gated.
  - `STR-TO-INT-STRICT-1`, G7, DECIDE. It covers drift D5.
- **Engineer summary.**
  - `DECIMAL-1`: four builtins over `Integer`, all pure. Three are def-shell-only and `asserted`, with an oracle battery. `div-half-even` is reflected by unfolding when its divisor is a numeral. There is no schema change and no version-stamp change.
  - `FLOAT-LIT-1`, as settled in Rev 1:
    - `"-" FLOAT` and the RFC-shaped FLOAT lexical definition (R1-3).
    - An exponent read as text, with no wrap (D7), and a parse-phase `float-literal-range`.
    - A zero-valued literal emitted as `0.0`, and a negative literal emitted parenthesized and annotated (R1-1, D8).
    - The optional pattern key `literal_kind`, with the schema at 0.14.0, and every incompatible literal pattern made an error (R1-2).
    - A `typeToSort TFloat` arm.
- **Blocking professor questions:** none.
