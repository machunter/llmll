# LT-INT / INT-2 — Boundary-Shim Catalog for `int → Integer` Codegen Switch

> **Version:** Rev 1 — initial settled draft
> **Date:** 2026-05-23
> **Implements:** `docs/compiler-team-roadmap.md` v0.11 milestone, Implementation Item 4 (LT-INT / INT-2), Active Items row at `:313`
> **Prerequisites:** v0.10.7 (TC-EOP-1, OBLIG-PBT-5a, INT-1) — INT-PRE baseline must include INT-1's `overflow_tainted` machinery
> **Origin:** Language-team review of experiment-lead's INT-PRE run plan (2026-05-23); finding F1 (boundary-shim catalog underspecification) — the roadmap permission "indexing primitives **may stay** `Int` and use `fromIntegral` at boundary" is not a catalog; INT-PRE Variant B fidelity requires this enumeration to be authored before the engineer mechanically realizes the codegen patch
> **Status:** Settled (proposal) — awaiting INT-PRE baseline and compiler-engineer hand-off

---

## 1. Motivation

LT-INT / INT-2 ships the spec move `int` = "mathematical integer (unbounded)" at [`LLMLL.md §3.1:153`](../../LLMLL.md), aligning the surface type definition with the existing semantic-foundation clause at [`LLMLL.md §0.1:49`](../../LLMLL.md): *"verification … under mathematical-integer (unbounded) semantics — modulo the `Int64` overflow gap documented in §5.3.5."* The gap has been documented since v0.8.1a; INT-2 closes it.

The roadmap entry at [`docs/compiler-team-roadmap.md:157, 313`](../compiler-team-roadmap.md) describes INT-2 as "one-line [`CodegenHs.hs:441`](../../compiler/src/LLMLL/CodegenHs.hs) change (`Int → Integer`) plus preamble-signature ripple at `:232-360` audit (indexing primitives may stay `Int` and use `fromIntegral` at boundary)." The one-line change is mechanical. The preamble audit is not — it requires a per-primitive classification that has not been authored anywhere in the design folder, the roadmap, or the codegen-team comments.

The empirical loop runs INT-PRE before INT-2 commits, with the gate criterion "TOTP regression < 5× → INT-2 proceeds; ≥ 5× → INT-3 freeze-exception candidate." INT-PRE requires a Variant B prototype that mirrors what INT-2 *actually* ships. Without a settled catalog, Variant B is underdetermined: the experiment-lead might measure one boundary choice while INT-2 eventually ships a different one, and the gate adjudication is not reproducible.

This proposal authors the catalog. It classifies each preamble primitive at [`CodegenHs.hs:232-360`](../../compiler/src/LLMLL/CodegenHs.hs) into one of three classes (A: stays `Int`; B: becomes `Integer`; C: stays `Int` under explicit semantic justification), rules on the `range` overload between index-iteration and value-enumeration uses, and names the boundary `fromIntegral` trust closure honestly. The classification is the input the engineer realizes; the catalog is the spec content `documentation-lead` promotes to `LLMLL.md` post-engineer-ship.

---

## 2. Scope

**In scope:**
- Enumeration and per-primitive classification of preamble entries at `CodegenHs.hs:232-360`
- Ratification of the `range` overload decision (split into `range` for value-shape and `range-idx` for index-iteration, or single signature with documented dual-use)
- Statement of the `fromIntegral` boundary trust closure as a documented suppression consistent with the FFI-builtin trust model at [`LLMLL.md §7:814`](../../LLMLL.md)
- The interaction clause between INT-1 (`overflow_tainted` propagation) and INT-2 (unbounded `int`): on `int`-typed values, `overflow_tainted` becomes unreachable; the machinery remains armed for the eventual `machine-int` opt-in tracked at INT-3
- Affected-surface enumeration for the engineer's eventual realization patch

**Out of scope (deferred to compiler-engineer slot):**
- Authorship of the codegen patch itself; this proposal is consumed as engineer input
- The line-by-line preamble Haskell rewrite; the catalog dictates signatures, the engineer types the code
- Test fixture authorship for INT-2's regression suite

**Out of scope (deferred to INT-3):**
- `machine-int` as an opt-in bounded type; this catalog assumes `int` is uniformly unbounded post-INT-2
- QF-BV constraint emitter for bounded-int arithmetic verification
- Any bounded-integer refinement-type alias beyond the existing `PositiveInt`, `GuessCount` examples at `LLMLL.md §3.4:239, 242`

**Out of scope under v0.11 surface — sequencing:**
- INT-2 ships **after** v0.10.7 (TC-EOP-1, OBLIG-PBT-5a, INT-1). The Variant B prototype this catalog dictates is built atop the v0.10.7 baseline; INT-PRE's Variant A measurement is also the v0.10.7 baseline.

---

## 3. Catalog

The preamble at [`CodegenHs.hs:232-360`](../../compiler/src/LLMLL/CodegenHs.hs) carries fifteen entries that touch `Int` in their Haskell signatures. They classify as follows.

### 3.1 Class A — stays `Int` (indexing primitives)

These primitives expose Haskell's idiomatic index/length operations. Their `Int` signature is dictated by the Haskell standard library (`length`, `(!!)`, `take`, `drop`, list-comprehension ranges), not by LLMLL semantics. The LLMLL surface presents them with `int` parameters; the codegen emits `fromIntegral` conversions at call sites.

| Primitive | Haskell signature (unchanged) | LLMLL surface | Conversion point |
|---|---|---|---|
| `list_length` | `[a] -> Int` | `list-length :: list[α] -> int` | `fromIntegral` at use site |
| `list_nth` | `[a] -> Int -> Either String a` | `list-nth :: list[α] -> int -> Result[α,string]` | `fromIntegral` on index argument |
| `string_length` | `String -> Int` | `string-length :: string -> int` | `fromIntegral` at use site |
| `string_slice` | `String -> Int -> Int -> String` | `string-slice :: string -> int -> int -> string` | `fromIntegral` on both index arguments |
| `string_char_at` | `String -> Int -> String` | `string-char-at :: string -> int -> string` | `fromIntegral` on index argument |
| `range-idx` (renamed; see §3.4) | `Int -> Int -> [Int]` | `range-idx :: int -> int -> list[int]` | `fromIntegral` on both endpoint arguments; result list `[Int]` is wrapped as `list[int]` via `map fromIntegral` at the LLMLL boundary |

Six entries. Each preserves its current Haskell signature. The cost of preservation is one `fromIntegral` at each LLMLL-to-Haskell call seam; this is `O(1)` for scalar arguments and `O(n)` for list-of-`Int` returns (see §3.4 for the `range-idx` element-wise wrap).

### 3.2 Class B — becomes `Integer` (semantic-arithmetic primitives)

These primitives are user-facing arithmetic operations whose Haskell type *is* the LLMLL `int` semantics. Their codegen signatures move from `Int` to `Integer`.

| Primitive | Pre-INT-2 signature | Post-INT-2 signature | Notes |
|---|---|---|---|
| `llmll_abs` | `Int -> Int` | `Integer -> Integer` | `abs` is polymorphic in Haskell; no implementation change |
| `llmll_min` | `Int -> Int -> Int` | `Integer -> Integer -> Integer` | `min` polymorphic; no implementation change |
| `llmll_max` | `Int -> Int -> Int` | `Integer -> Integer -> Integer` | `max` polymorphic; no implementation change |
| `int_to_string` | `Int -> String` | `Integer -> String` | `show` polymorphic; no implementation change |
| `string_to_int` | `String -> Either String Int` | `String -> Either String Integer` | **Implementation change**: `reads :: ReadS Integer` instead of `reads :: ReadS Int`. Closes a silent-truncation hazard for inputs exceeding `maxBound :: Int`. |
| `range` (value-shape; see §3.4) | (currently `Int -> Int -> [Int]`) | `Integer -> Integer -> [Integer]` | Implementation: `[from .. to - 1]` works uniformly over `Integer`. |

Six entries. The implementation impact is localized to `string_to_int` (reads-target retypes) and the `range` split (§3.4); the remaining four are signature-only changes courtesy of Haskell's polymorphism.

### 3.3 Class C — stays `Int` with explicit semantic justification

| Primitive | Signature | Justification |
|---|---|---|
| `random_int` | `IO Int` (stub returning `42`) | Random sampling from an unbounded `Integer` has no uniform measure; the construct is mathematically ill-formed without a bounded range. Class C marks this as a *known semantic limitation*. Post-freeze, the principled move is a `bounded-random-int :: int -> int -> int` refinement-type wrapper requiring `lo ≤ hi` (§ INT-3 contingency, optionally). Current behavior is unchanged. |

One entry. No code change. The catalog records the rationale so the post-freeze design exercise has a settled starting point.

### 3.4 The `range` overload decision

`range :: Int -> Int -> [Int]` at `CodegenHs.hs:257-258` is used today in two distinct semantic positions:

1. **Index-iteration position.** `range 0 (list_length xs)` produces a list of indices for traversal; the result is consumed at type `Int` by `list_nth` and similar primitives. The bounded-index semantics is correct here.
2. **Value-enumeration position.** `range lo hi` produces a list of integer *values*; consumers treat the elements as user-LLMLL `int`. Post-INT-2, these values must be unbounded `Integer` to maintain the mathematical-integer guarantee at element type.

A single signature serving both positions leaks bounded semantics into the value-enumeration use, or burdens the index-iteration use with `fromIntegral` conversions on every element. The catalog ratifies the **split**:

- **`range` (value-shape, Class B).** `Integer -> Integer -> [Integer]`. The default; user-LLMLL `(range lo hi)` lowers here.
- **`range-idx` (index-shape, Class A).** `Int -> Int -> [Int]`. Used internally by codegen for `list_*` / `string_*` index iteration; not directly exposed at the LLMLL surface in v0.11.

Codegen-side rewrite: pattern-match call sites of `range`. If the result feeds an indexing primitive (`list_nth`, `string_slice`, `string_char_at`), emit `range-idx`; otherwise emit `range`. The pattern detector lives in the codegen pass, not the type-checker — the type-checker sees `int` at both sites and is silent on the distinction.

A cleaner alternative — make `range-idx` an internal Haskell helper not exposed to LLMLL surface at all, and rely on codegen synthesizing `range-idx` calls only where pattern-matched as index-iteration — is the recommended realization. The engineer adjudicates the precise codegen mechanism; the catalog ratifies the *outcome*: two Haskell symbols, one LLMLL surface symbol (`range`), with the value-shape semantics dominant.

The mechanical-classifier risk is well-bounded: the existing benchmark suite (B1 / B3 / B5 / TOTP / ERC-20) uses `range` only in `range 0 (length xs)`-shaped index-iteration patterns (TOTP `pad-otp`, no others) per spot-check. Any LLMLL programs in `examples/` that use `range` in value-shape acquire correct Integer semantics post-INT-2 by default; the index-shape callers are mechanically detectable.

---

## 4. INT-1 interaction — `overflow_tainted` discharge

INT-1 (`docs/compiler-team-roadmap.md:303`) lands `overflow_tainted` propagation in v0.10.7 on LLMLL-level arithmetic operations (`EOp '+`, `EOp '-`, `EOp '*`, etc.) where the operand types could overflow under bounded-`Int` semantics. The strict-core verified clean tier refuses values carrying the tag.

Post-INT-2, **`overflow_tainted` is unreachable on `int`-typed values.** The LLMLL-level arithmetic is over unbounded `Integer` in the generated Haskell; there is no overflow event to propagate. INT-1's machinery is preserved (its constructor, its propagation rule, its strict-core refusal) but its **trigger set is empty for `int` values**.

The machinery remains armed for the eventual `machine-int` opt-in tracked at INT-3 (`docs/design/int-3-machine-int-sketch.md`). On `machine-int` arithmetic, INT-1's `overflow_tainted` tag fires per its v0.10.7 semantics; the strict-core refusal blocks the `verified` tier accordingly. INT-1 is therefore neither dead code post-INT-2 nor active-on-`int` post-INT-2 — it is dormant on `int`, armed for `machine-int`.

The boundary `fromIntegral` conversion at the LLMLL/Haskell seam (Class A primitives) does *not* produce `overflow_tainted` because LLMLL's verification layer sees only `int` types at the seam, and `int` is unbounded. The Haskell-level `Int` arithmetic *inside* a Class A primitive is FFI-sealed at the builtin boundary and outside INT-1's verification scope by construction (per the FFI-builtin trust model at [`LLMLL.md §7:814`](../../LLMLL.md)).

This clause is the catalog's full statement on the INT-1 / INT-2 interaction. No new INT-1 sub-design is required for INT-2 to ship; the interaction is by-construction-correct given each piece's separately-ratified semantics.

---

## 5. Boundary trust closure

Class A's `fromIntegral` conversions assume the underlying Haskell `Int` is a faithful representation of the value being lifted to `Integer`. This is true for any list or string whose size fits in `maxBound :: Int = 2^63 - 1` on a 64-bit host. For lists or strings exceeding that size, `length` and `(!!)` return wrapped or undefined values, which `fromIntegral` then promotes silently.

The closure is consistent with — and a sub-case of — the existing FFI-builtin trust closure at [`LLMLL.md §7:814`](../../LLMLL.md) and the "sound modulo trust" framing at [`docs/design/verification-debate.md`](verification-debate.md). LLMLL's verification claims do not extend across the FFI seam; the builtin's correctness on its declared input domain is a trust closure, not a verification obligation. The Class A primitives' input domain is "lists and strings constructible within `Int64` capacity," which is the entire constructible-Haskell-value domain in practice.

The closure is documentable as a §13 builtin pre-condition rather than a §7 FFI capability, since the affected primitives are pure-Haskell-internal, not externally-bound. The post-INT-2 spec text at `LLMLL.md §13` should carry the explicit clause:

> Class A indexing primitives (`list-length`, `list-nth`, `string-length`, `string-slice`, `string-char-at`) assume the underlying Haskell representation fits in `Int64`. Programs constructing collections whose size exceeds `2^63 - 1` are outside the builtin's input domain and the verification report does not cover their behavior.

This is `documentation-lead`'s slot post-engineer-ship. The catalog records the spec content; doc-lead promotes it.

---

## 6. Edge cases and degenerate inputs

1. **User-LLMLL code that uses `(range 0 100)` in head position consumed by indexing.** Pre-INT-2: works at `[Int]`. Post-INT-2: works because the codegen-side pattern detector emits `range-idx` for this call. Verification channel: type-checker — `range` and `range-idx` both surface as `int -> int -> list[int]` at LLMLL surface; the type-checker is silent and that is intentional. The codegen pattern detector is the active mechanism. Citation: §3.4 above; engineer realization site at `CodegenHs.hs` (line to be determined).
2. **User-LLMLL code that uses `(range 0 100)` and feeds the result to a user-defined arithmetic function.** Pre-INT-2: works at `[Int]`. Post-INT-2: works at `[Integer]` (Class B). The arithmetic function's `int` parameters lower to `Integer`; uniformity preserved. Verification channel: type-checker. Citation: §3.2 row for `range`.
3. **`string_to_int "999999999999999999999999"` — input exceeds `maxBound :: Int`.** Pre-INT-2: returns `Left "string_to_int: cannot parse '…'"` because `reads :: ReadS Int` rejects out-of-range inputs. Post-INT-2: returns `Right 999999999999999999999999` at Haskell-`Integer`. **Behavior change**, not a regression: this is the user-visible win from INT-2. Verification channel: contract — `string-to-int`'s post-condition is unchanged at LLMLL surface (`Result[int, string]`), but the inhabited output space widens. Citation: §3.2 row for `string_to_int`. Engineer should add a regression test for the wide-input case to the v0.11 suite.
4. **Negative-`Integer` argument to `list_nth` exceeding `Int` range.** Suppose a user computes a value at `int` (unbounded) and passes it as the `idx` argument: `(list-nth xs very-large-negative-integer)`. Codegen emits `fromIntegral very-large-negative-integer :: Int`, which wraps. The wrapped value lands inside `list_nth`, which guards `i < 0 || i >= length xs`. If the wrap produced a value in the valid index range by accident, `list_nth` would return the wrong element. **This is a real soundness hazard.** Verification channel: spec is silent today (intentional gap — the index argument is `int`, the bound at the builtin boundary is `Int`). The principled future fix is either (i) a refinement predicate on `list-nth`'s index parameter `(where [i: int] (and (>= i 0) (< i (list-length xs))))` enforced at the call site, or (ii) INT-3's `machine-int` opt-in. The catalog flags this as a known limitation and does *not* propose a fix; the existing `list_nth` runtime guard catches `i < 0` and out-of-range *Haskell-Int*-valued cases, which is sufficient for any practical use within `Int64` capacity. Citation: `CodegenHs.hs:252-255`.
5. **Empty `range`.** `(range 5 5)` returns `[]` at both `[Int]` and `[Integer]`. No behavior change. Verification channel: spec is silent (intentional — empty list is uniformly correct).
6. **Refinement type alias on user-LLMLL `int`.** `(type PositiveInt (where [x: int] (> x 0)))` at `LLMLL.md §3.4:239` — pre-INT-2, the predicate is implicitly bounded by `Int64`; post-INT-2, it is over unbounded `Integer`. The QF-LIA constraint vocabulary at `FixpointEmit.hs:188-194` already operates on `FQInt`, so no constraint shape changes; the *meaning* of the predicate widens from "positive `Int64`" to "positive `Integer`," matching the spec's pre-existing semantic-foundation claim. Verification channel: contract, QF-LIA, auto-discharged. Citation: `LLMLL.md §3.4:234-251`.

---

## 7. Verification mapping

INT-2 introduces no new proof obligations and removes implicit ones. The pre-existing overflow side conditions that were never first-class in the constraint vocabulary become trivially-true post-INT-2 (because `Integer` is unbounded), simplifying the verifier's job rather than complicating it.

| Obligation | Channel | Fragment | Pre-INT-2 disposition | Post-INT-2 disposition |
|---|---|---|---|---|
| `int` arithmetic non-overflow | contract (implicit) | QF-LIA | Documented gap at §5.3.5 | Trivially true; gap closed |
| `overflow_tainted` propagation on `int` arithmetic (INT-1) | contract | QF-LIA | Active on `int` from v0.10.7 | Dormant on `int`; armed for `machine-int` per INT-3 |
| `PositiveInt`, `GuessCount`, similar refinement-type alias predicates | contract | QF-LIA | Sound over bounded ints | Sound over unbounded ints; predicate vocabulary unchanged |
| Lean translation of integer literals | trust | `?proof-required` | `T.pack (show n)` at `LeanTranslate.hs:60` | Unchanged; Lean `Int` is unbounded |
| `tier_profile` 6-`Int` aggregate at `LLMLL.md §4.4.4:420` | n/a (counter, not verification) | n/a | `Int` counter | `Int` counter (unchanged) |

No constraint emitter changes in `FixpointEmit.hs`. No new builtins. No JSON-AST schema bump. The verification surface *simplifies*. Citation for the QF-LIA boundary: [`LLMLL.md §5.3.5:740-770`](../../LLMLL.md).

---

## 8. Affected surface

**Compiler modules** (engineer's slot, post-INT-PRE-clearance):
- `compiler/src/LLMLL/CodegenHs.hs:441` — one-line `mapLlmllPrimType "int" -> "Integer"`
- `compiler/src/LLMLL/CodegenHs.hs:232-360` — preamble signature rewrites per §3.1, §3.2, §3.3, §3.4
- `compiler/src/LLMLL/CodegenHs.hs` (location TBD) — pattern detector for `range` value-shape vs index-iteration

**Specification documents** (`documentation-lead`'s slot, post-engineer-ship):
- `LLMLL.md §3.1:153` — change "64-bit signed integer" to "mathematical integer (unbounded)"; cross-reference removed `Int64 overflow gap` callout
- `LLMLL.md §5.3.5` — remove the documented `Int64 overflow gap` clause; the gap is closed
- `LLMLL.md §13` — add the §5 boundary trust closure clause for Class A primitives
- `CHANGELOG.md` v0.11 entry — INT-2 spec move recorded
- `docs/compiler-team-roadmap.md:157-158, 313` — INT-2 row status flips to "shipped"
- `docs/llmll-ast.schema.json` — **no change** (the change is type-mapping at codegen, not AST shape)

**Empirical-loop artefacts** (experiment-lead's slot):
- `experiments/int-pre/runs/<timestamp>/` — Variant B is built from this catalog; faithfulness assertion in the postmortem cites this document by SHA

**Out-of-scope-under-freeze flags:**
- INT-2 itself is the freeze-exception that this catalog implements; the freeze lift for v0.11 is tracked at `docs/compiler-team-roadmap.md:26-31` and `:145`. No new freeze exceptions are introduced.

---

## 9. Risks and open questions

1. **`range` pattern detector miscategorization** — *severity: medium; soundness.* If the codegen detector at §3.4 misidentifies a value-shape call as index-shape (or vice versa), the user-visible result is a type-checker-silent semantic shift. The detector's correctness is the new soundness obligation. Mitigation: the engineer's INT-2 regression suite includes a per-call-site categorization test; mechanical migration of the existing benchmark suite verifies no false categorizations on shipped code. Bite: contained to the codegen pass; not a verifier soundness issue.
2. **`Integer` arithmetic regression on TOTP exceeds 5×** — *severity: high; runtime ergonomics.* INT-PRE adjudicates. If escalated, INT-3 sketch at `docs/design/int-3-machine-int-sketch.md` proposes the freeze-exception alternative. Bite: gates INT-2 shipping; out of this catalog's hands.
3. **Class A boundary trust closure on lists exceeding `Int64` capacity** — *severity: low; trust closure.* Practical impact nil; documented honestly in §5. Bite: a future refinement-predicate-on-length design or INT-3 opt-in is the principled fix; not in scope for INT-2.
4. **`string_to_int` widened input domain triggers latent test fixtures** — *severity: low; defence-in-depth.* Pre-INT-2 fixtures may have asserted `Left "cannot parse '…'"` on overlong inputs; post-INT-2 those inputs become `Right`. The engineer's regression suite should grep for such fixtures and update them. Bite: contained to test-fixture authorship.
5. **`random_int` semantic ill-formedness recorded but not fixed** — *severity: low; freeze-policy; scope.* Honest acknowledgement in §3.3; out-of-scope under freeze. Post-freeze design exercise tracked separately. Bite: visible-but-deferred.

---

## 10. Open questions for the professor *(none for this catalog)*

No outside-PL questions remain on this catalog. Vazou-et-al.-style refinement-type-aliased bounded ints (`PositiveInt = {v : Int | v > 0}`) are the established treatment in the Liquid Haskell tradition; LLMLL's existing surface at `LLMLL.md §3.4` already adopts that idiom. The catalog does not extend it.

A latent outside-PL question on `machine-int` primitive-vs-refinement-aliased treatment is hosted at `docs/design/int-3-machine-int-sketch.md` §7; that question is dormant unless INT-PRE escalates.

---

## 11. Cross-references

- INT-2 row at [`docs/compiler-team-roadmap.md:157, 313`](../compiler-team-roadmap.md) — empirically-gated v0.11 milestone item
- INT-PRE row at [`docs/compiler-team-roadmap.md:158, 314`](../compiler-team-roadmap.md) — empirical gate; consumes this catalog as Variant B input
- INT-1 row at [`docs/compiler-team-roadmap.md:303`](../compiler-team-roadmap.md) — v0.10.7 patch-lane interaction documented in §4
- INT-3 sketch at [`int-3-machine-int-sketch.md`](int-3-machine-int-sketch.md) — contingency proposal if INT-PRE escalates
- LT-PPR proposal at [`proof-required-predicate-carrier-proposal.md`](proof-required-predicate-carrier-proposal.md) — sibling v0.11 LT-* proposal; no direct interaction
- LT-INV proposal at [`core-shell-inversion-proposal.md`](core-shell-inversion-proposal.md) — sibling v0.11 LT-* proposal; no direct interaction
- Semantic foundation at [`LLMLL.md §0.1:49`](../../LLMLL.md) — pre-existing mathematical-integer claim INT-2 makes faithful
- QF-LIA boundary at [`LLMLL.md §5.3.3, §5.3.5`](../../LLMLL.md) — constraint vocabulary unchanged
- Verification debate at [`verification-debate.md`](verification-debate.md) — "sound modulo trust" framing the boundary trust closure in §5 inherits from
