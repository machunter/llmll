# INT-3 — `machine-int` QF-BV Alias (Contingency Sketch)

> **Version:** Rev 0 — contingency sketch (not a ratified proposal)
> **Date:** 2026-05-23
> **Implements:** Contingency for `docs/compiler-team-roadmap.md` Active Items row at `:321` (INT-3, P3); promotes to settled proposal IFF INT-PRE escalates per `:158, 314`
> **Prerequisites (if promoted):** v0.10.7 (INT-1 machinery), INT-2 (`int` = `Integer`; this sketch assumes INT-2 has shipped or is shipping concurrently)
> **Origin:** Language-team review of experiment-lead's INT-PRE run plan (2026-05-23); finding F5 (INT-3 design lag could block freeze-exception escalation). Pre-authored to unblock the escalation path so v0.11 is not delayed at the moment of the gate-failure adjudication.
> **Status:** Contingency sketch (Rev 0) — promotes to "Settled (proposal)" if INT-PRE shows TOTP regression ≥ 5×; otherwise stays research-track at P3

---

## 1. Trigger condition

This sketch is dormant unless INT-PRE's TOTP wall-clock regression factor under Variant B (per `docs/design/int-2-boundary-shims.md`) meets or exceeds 5×. The gate criterion is recorded at [`docs/compiler-team-roadmap.md:158, 314`](../compiler-team-roadmap.md):

> If TOTP regresses >5×, escalate INT-3 to freeze-exception; otherwise INT-2 proceeds as planned for v0.11.

The escalation requires a written proposal at proposal-granularity. A one-phrase roadmap entry — "`MachineInt` QF-BV alias" — does not meet the v0.11 freeze-exception bar (per `docs/compiler-team-roadmap.md:26-31`). This sketch is the seed the language-team revises into a Rev 1 settled proposal *only if* the gate fires.

If INT-PRE clears the gate, this sketch remains on the research track at P3 (`:321`) and is revisited only when a future codegen-perf gate or external user demand re-surfaces the need for opt-in bounded integers. The Class C entry on `random_int` at `docs/design/int-2-boundary-shims.md` §3.3 is the lowest-noise candidate trigger for a future revisit.

The sketch is **not exhaustive**. It records the settled design-axis positions language-team holds today, the open questions that the actual Rev 1 proposal must close before engineer hand-off, and the minimum content the freeze-exception decision requires. Promotion to Rev 1 is roughly two pages of additional content and one professor review turn; the engineering surface beyond what is sketched here is left to the eventual Rev 1.

---

## 2. Type name and surface

The opt-in bounded integer type is named **`machine-int`** at the LLMLL surface, distinct from the post-INT-2 unbounded `int`. Alternatives considered and rejected:

| Candidate | Reason rejected |
|---|---|
| `int64` | Hard-codes the host bit-width into the LLMLL surface; precludes a portable `int32` variant later without surface-name proliferation. |
| `MachineInt` | PascalCase violates the §2.5 naming convention for primitive types (lowercase) at [`LLMLL.md §2.5:128-146`](../../LLMLL.md). |
| `bounded-int` | Insufficiently specific; LLMLL already has bounded-int refinement aliases (`PositiveInt`, etc.). The distinction this type marks is *machine-bounded*, not *user-bounded*. |
| `word`, `int-word`, similar | "Word" conventionally signals unsigned in PL idiom; LLMLL's bounded type is signed. |

The name `machine-int` is settled. The Rev 1 proposal need not relitigate.

### 2.1 S-expression

```
(let [x: machine-int 42] ...)
(def-logic widget-id [n: machine-int] ?body)
```

The literal `42` in `machine-int` context lowers to `(42 :: Int)` in Haskell; the type-checker disambiguates from `int` context by parameter declaration. Untyped integer literals continue to default to `int` (= `Integer`) per LLMLL's existing literal-typing rules.

### 2.2 JSON-AST

A new primitive-type spelling `"machine-int"` is admitted at any position where `"int"` is admitted today. The JSON-AST schema bump is required: **`schemaVersion` 0.6.0 → 0.7.0** (additive, following the LT-INV bump 0.5.0 → 0.6.0 documented at `docs/design/core-shell-inversion-proposal.md`). If INT-3 ships in v0.11 as freeze-exception alongside LT-INV, the bump consolidates to 0.5.0 → 0.6.0 (single bump for all v0.11 schema changes); if INT-3 ships in v0.12+ standalone, it carries its own 0.7.0 bump. The Rev 1 proposal commits to one ordering.

---

## 3. Semantics

The settled axis: `machine-int` is a **primitive type**, not a refinement-aliased subtype of `int`. The alternative — `(type machine-int (where [x: int] (and (>= x -9223372036854775808) (<= x 9223372036854775807))))` — was considered and is recorded as the dormant outside-PL question in §7. The primitive-type position is held on three grounds:

1. **Verification fragment.** A refinement-aliased `machine-int` would still emit QF-LIA constraints (over `FQInt`) with bounds side conditions on every arithmetic operation. This is sound but produces verification reports cluttered with `(-2^63 ≤ x + y ≤ 2^63 - 1)` side conditions on every `+`, every `*`. The primitive-type position emits QF-BV constraints directly via Z3's bit-vector theory; the bounds are baked into the type, not the predicate. The downstream verification report is cleaner. Citation: [`FixpointEmit.hs:188-194`](../../compiler/src/LLMLL/FixpointEmit.hs) (current `FQInt` builtin qualifiers; QF-BV path adds parallel `FQBV` constructors).
2. **Constraint-vocabulary uniformity hazard.** Mixing QF-LIA and QF-BV constraints in the same `--trust-report` output is a known liquid-fixpoint complication. The refinement-aliased route forces a per-clause solver-theory decision; the primitive-type route lifts the decision to the type system, which is the established LLMLL pattern.
3. **Idiomatic alignment with Liquid Haskell.** Liquid Haskell distinguishes `Int` (refinable via bit-vector theory automatic-discharge) from `Int64` / `Word32` / etc. (treated as bit-vector primitives in their refinement-predicate vocabulary). LLMLL's `machine-int` follows the latter pattern. Citation: Vazou et al., *Refinement Types for Haskell* (ICFP 2014), Liquid Haskell's `Data.Refined` module conventions.

### 3.1 Bit width

`machine-int` is **64-bit signed** by default, matching Haskell's `Int` on 64-bit hosts. A future portable variant set (`machine-int32`, `machine-int16`, `machine-int8`) is plausible but **out of scope for the Rev 1 proposal**. If a user needs a different bit-width before that variant set exists, the workaround is a refinement-type alias over `machine-int` with tighter bounds:

```
(type machine-int32 (where [x: machine-int] (and (>= x -2147483648) (<= x 2147483647))))
```

This works because the alias's predicate is QF-LIA-tractable (or QF-BV-tractable if the `machine-int` solver theory is active), and bounds are statically checkable.

### 3.2 Overflow semantics

Arithmetic over `machine-int` wraps modulo `2^64` (two's-complement), matching Haskell's `Int` arithmetic. INT-1's `overflow_tainted` machinery (per `docs/compiler-team-roadmap.md:303`) tags any arithmetic result whose value is not proved within bounds; the strict-core `verified` tier refuses tagged values. The Rev 1 proposal must commit to one of two refinement strategies for *clearing* the tag:

- **(a) Verifier-discharged clearance.** The QF-BV solver proves the result is within `[-2^63, 2^63 - 1]` for the operand domain; the tag is cleared automatically. Default; matches the existing `verified`-tier flow on QF-LIA.
- **(b) Source-annotated clearance.** The user writes `(! safe-arith expr)` or a similar marker to assert clearance manually, falling back to `asserted` tier if the verifier cannot discharge. Escape hatch for inputs the verifier cannot bound.

Both ship; the choice between them is per-call-site, mediated by the LLMLL surface. The Rev 1 proposal commits to syntactic detail.

### 3.3 Conversions

Conversions between `int` (unbounded) and `machine-int` (bounded) are explicit:

- `(int->machine-int x)` :: `int -> Result[machine-int, string]`. Returns `Error` if `x` is out of range. Lowers to a runtime bounds check + `fromInteger`.
- `(machine-int->int x)` :: `machine-int -> int`. Total; lowers to `fromIntegral :: Int -> Integer`.

Implicit conversions are forbidden. The type-checker rejects mixed-arithmetic expressions like `(+ user-int user-machine-int)` with a settled error message naming both conversions.

---

## 4. Verification fragment

`machine-int` constraints lift to QF-BV via Z3's bit-vector theory. The compiler emits FQ constraints with a new `FQBV` constructor (parallel to the existing `FQInt`). The Rev 1 proposal must enumerate:

- Which arithmetic operations get QF-BV constraints: `+`, `-`, `*`, `div`, `mod`, `&`, `|`, `xor`, `~`, `<<`, `>>` (the bit-twiddling ops are not currently in LLMLL's operator set; their addition is gated under freeze-exception scope).
- Which comparisons stay QF-LIA-compatible (with bit-width casts) versus require QF-BV: `=`, `!=`, `<`, `>`, `<=`, `>=` over signed `machine-int`.
- The fallback when an obligation crosses the QF-LIA / QF-BV boundary (e.g., a mixed `(if (< i (list-length xs)) ...)` where `i: machine-int` and `list-length` returns `int`): explicit conversion is required at the surface; the type-checker enforces.

This enumeration is the engineering-cost-dominant section of the Rev 1 proposal. A rough cost read: medium implementation effort in `FixpointEmit.hs` + `FixpointIR.hs`; the QF-BV path itself is well-understood Z3 idiom, but the LLMLL-side constraint emitter requires a new branch per operation and per-operand-typing decision.

Citation for the QF-LIA-only present state: [`LLMLL.md §5.3.5:698`](../../LLMLL.md) — "QF-LIA … over `int`. Handles numeric bounds, conservation invariants, length preservation. ~80% of practical contracts." INT-3 adds QF-BV as a sibling theory, raising the joint coverage to a higher fraction at the cost of the dual-theory constraint-vocabulary complication recorded in §3 ground 2.

---

## 5. Migration story

INT-3 is **opt-in only**. Programs that use `int` post-INT-2 continue to compile against an unbounded mathematical-integer surface; INT-3 does not retroactively bound them. Users opt into `machine-int` per-declaration:

```
(def-logic fast-counter [n: machine-int] ?body)   ; opt-in bounded
(def-logic ledger-balance [n: int] ?body)         ; default unbounded
```

The decision is local to each declaration. There is no global `--bounded-int-default` switch; that would proliferate the LLMLL surface in confusing ways and is rejected on the same grounds as the refinement-aliased-machine-int rejection in §3.

The 12 existing example directories at `examples/*/` continue to compile against `int` and are not affected by INT-3 shipping. TOTP specifically: the codepoint where INT-3 might be opted-into is `compute-time-step` (which does heavy modular arithmetic that benefits from machine-int speed); the Rev 1 proposal includes a `pre/post` migration of TOTP showing `compute-time-step :: machine-int -> ...` as a representative example, and re-runs INT-PRE post-INT-3-opt-in to demonstrate the regression-recovery.

---

## 6. Affected surface (if promoted to Rev 1 and shipped)

**Compiler modules** (engineer's slot):
- `compiler/src/LLMLL/Syntax.hs` — new `TMachineInt` constructor on `Type` (or extension of `TPrim`)
- `compiler/src/LLMLL/Parser.hs`, `ParserJSON.hs` — `machine-int` token / `"machine-int"` JSON-AST primitive type
- `compiler/src/LLMLL/TypeCheck.hs` — type-checker treatment of `machine-int`; conversion-only inter-conversion enforcement
- `compiler/src/LLMLL/CodegenHs.hs` — `mapLlmllPrimType "machine-int" -> "Int"`; conversion primitive emission (`int->machine-int`, `machine-int->int`)
- `compiler/src/LLMLL/FixpointIR.hs` — `FQBV` constructor or equivalent for bit-vector constraints
- `compiler/src/LLMLL/FixpointEmit.hs` — QF-BV constraint emitter path; builtin qualifiers for bit-vector
- `compiler/src/LLMLL/Contracts.hs` — contract-clause routing for `machine-int` parameters
- `compiler/src/LLMLL/ObligationMining.hs` — INT-1's `overflow_tainted` activation on `machine-int` arithmetic

**Specification documents** (`documentation-lead`'s slot, post-engineer-ship):
- `LLMLL.md §3.1` — new primitive type `machine-int` row
- `LLMLL.md §3.4` — example refinement-aliased machine-int variants (`machine-int32`, etc.)
- `LLMLL.md §5.3.3, §5.3.5` — verification matrix new row for QF-BV fragment
- `LLMLL.md §13` — conversion primitives `int->machine-int`, `machine-int->int`
- `docs/llmll-ast.schema.json` — `schemaVersion` bump (per §2.2)
- `CHANGELOG.md` v0.11 or v0.12 entry
- `docs/compiler-team-roadmap.md` — INT-3 row status flip

**Empirical-loop artefacts** (experiment-lead's slot):
- `experiments/int-pre/` — post-INT-3 re-run with TOTP `compute-time-step` opted into `machine-int`; expected outcome: regression recovered to baseline ≤ 1.5× (the QF-BV-vs-QF-LIA verification time and `machine-int` runtime are both at parity with pre-INT-2)

---

## 7. Open questions for the professor *(dormant unless promoted)*

If INT-PRE escalates and this sketch promotes to Rev 1, the language-team would consult the professor on two outside-PL questions before committing:

1. **Refinement-aliased vs primitive `machine-int`.** §3 holds the primitive-type position on three grounds, but the refinement-aliased alternative is consistent with Vazou et al.'s general approach in Liquid Haskell, where `Int` is refinable and bounded subtypes are refinement aliases. Does the Liquid Haskell literature treat this as a settled trade-off — primitive types for bit-vector-theory machinery, refinement aliases for QF-LIA-tractable bounds — or is the choice more nuanced? Specific question: when Liquid Haskell users want `Int64` arithmetic with overflow semantics, do they use a refinement alias and rely on the LH `Bitvec` extension, or do they use a primitive type? Citation: Vazou et al., *Refinement Types for Haskell* (ICFP 2014); Vazou et al., *LiquidHaskell: Experience with Refinement Types in the Real World* (Haskell '14); `Data.Refined` namespace conventions.
2. **Bit-twiddling operator admission.** §4 contemplates `&`, `|`, `xor`, `~`, `<<`, `>>` over `machine-int`. These are not currently in LLMLL's operator set. Their addition is gated under freeze-exception scope per `docs/compiler-team-roadmap.md:26-31`. Is the established PL practice to expose bit-twiddling as language-level operators (Haskell `Bits` class), as builtins (Idris, F\*), or to push it entirely into FFI-sealed helpers? The choice affects whether QF-BV constraints need to discharge bit-twiddling correctness or whether the surface stays small enough that bit-twiddling is FFI-only.

Both questions are dormant. If INT-PRE clears the gate, neither needs an answer.

---

## 8. Cross-references

- INT-3 row at [`docs/compiler-team-roadmap.md:321`](../compiler-team-roadmap.md) — current P3 research-track status; flips on escalation
- INT-PRE row at [`docs/compiler-team-roadmap.md:158, 314`](../compiler-team-roadmap.md) — the empirical gate that triggers this sketch's promotion
- INT-2 row at [`docs/compiler-team-roadmap.md:157, 313`](../compiler-team-roadmap.md) — the design move INT-3 supplements with bounded opt-in
- INT-1 row at [`docs/compiler-team-roadmap.md:303`](../compiler-team-roadmap.md) — the `overflow_tainted` machinery this sketch armaments-on-`machine-int`
- INT-2 catalog at [`int-2-boundary-shims.md`](../archive/shipped-design-specs/int-2-boundary-shims.md) — companion document; §3.3 entry on `random_int` is the lowest-noise candidate trigger for a future INT-3 revisit absent INT-PRE escalation
- LT-INV proposal at [`core-shell-inversion-proposal.md`](../archive/shipped-design-specs/core-shell-inversion-proposal.md) — schemaVersion bump coordination noted in §2.2
- Verification matrix at [`LLMLL.md §5.3.5:740-770`](../../LLMLL.md) — current QF-LIA fragment definition; INT-3 adds QF-BV as sibling
- Liquid Haskell `Data.Refined` (external) — refinement-aliased-bounded-int idiom comparison point for §3 and §7
