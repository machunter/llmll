# RFC 1982 Serial Number Arithmetic — Verification Scope Matrix + Clause Inventory

**Claim.** RFC 1982's serial arithmetic — wrap-around addition (§3.1) and the
case-split comparison relations (§3.2), the arithmetic whose naive misreading
(`newer == bigger`) was a real historical DNS bug class — is **solver-proven** at
SERIAL_BITS = 32 (the DNS SOA width): all three contracts are body-faithful
`verified`, the naive-`<` comparison mutant and the no-wrap addition mutant are
**refuted**, and the undefined-comparison corner (pairs at distance exactly 2^31)
is encoded by the biconditionals and demonstrated by a passing property.

This example is the **spec-from-RFC pipeline's §4 evaluation run**
([`docs/design/spec-from-rfc-pipeline.md`](../../docs/design/spec-from-rfc-pipeline.md)):
built by procedure S0→S5, and the first example to persist the **S1 clause
inventory** (gap G1) — the table below is the template future RFC examples copy.

| # | Function | Post | Body | Verdict | Source |
|---|----------|------|------|---------|--------|
| 1 | `serial-add` | ✅ range + exact wrap value (linear case split for `mod 2^32`) | ✅ conditional subtraction | **verified** (body-faithful) | RFC 1982 §3.1 |
| 2 | `serial-lt` | ✅ biconditional, verbatim-shaped from §3.2 | ✅ decision chain (`if`) | **verified** (body-faithful) | RFC 1982 §3.2 |
| 3 | `serial-gt` | ✅ biconditional, verbatim-shaped from §3.2 | ✅ decision chain (`if`) | **verified** (body-faithful) | RFC 1982 §3.2 |

**Proven: 3 · Asserted: 0** (`--strict-verified-core --trust-report`:
`verified: 3, asserted: 0`; pres are caller obligations, surfaced as `asserted`
per-clause rows — the standing pre-display convention). Effective coverage
**100% (3/3), no `⊘`** — nothing in this RFC is opaque; contrast
`examples/totp_rfc6238` (crypto core, Proven 0) and match `examples/tcp_rfc793`
(pipeline ceiling, all-proven).

## S0 — Fragment scoping (decided before authoring)

- **The `modulo` trap (the S0 decision that matters):** §3.1's
  `s' = (s + n) modulo (2 ^ SERIAL_BITS)` is nonlinear as written (`mod` ∉ QF-LIA).
  Under §3.1's own precondition (`n ≤ 2^31 - 1`) and §2's space bound
  (`s < 2^32`), the sum is `< 2^32 + 2^31`, so the mod reduces to **one
  conditional subtraction** — a linear case split, inside `Σ_auto`. This is the
  pipeline's C2 "restrict the surface form" disposition, chosen at S0, not
  discovered at verify time.
- **SERIAL_BITS = 32**, the DNS SOA width (RFC 1982's own motivating instance).
  The 2^32-scale literals are unproblematic for the solver (verify ≈ instant);
  no didactic down-scaling needed.
- Comparison (§3.2) is pure linear ordering + subtraction + bool — in `Σ_auto`
  as shipped (bool admitted v0.14.14).
- Nothing routes to `weakness-ok`/`?proof-required`: no opaque primitives, no
  quantified/temporal clauses. The §4 "undefined" prose maps to preconditions
  and to the biconditionals' both-false region, not to a trust channel.

## S1 — Clause inventory (the G1 artifact — first persisted instance)

Quoted text is verbatim from RFC 1982 (fetched from rfc-editor.org during this
run). Every normative clause is dispositioned; C-classes per
`spec-from-rfc-pipeline.md` §1.2.

| ID | RFC § | Normative text (quoted) | Class | Disposition → contract site |
|----|-------|--------------------------|-------|------------------------------|
| Q1 | §2 | "Serial numbers are formed from non-negative integers … the lowest … is zero, the maximum is always one less than a power of two." / SERIAL_BITS "gives the power of two which results in one larger than the largest integer" | C2 | space bound `0 ≤ s < 2^32` → `pre` of all three fns (`:source "RFC 1982 §2 …"`) |
| Q2 | §3.1 | "s' = (s + n) modulo (2 ^ SERIAL_BITS)" | C2 (nonlinear as written → **linear case split** under Q3's bound) | `serial-add` post (`:source "RFC 1982 §3.1 …"`) |
| Q3 | §3.1 | "n is taken from the range of integers [0 .. (2^(SERIAL_BITS - 1) - 1)]" / "Addition of a value outside the range … is undefined." | C2 | `serial-add` pre — "undefined" = caller obligation, not a defined behavior to encode |
| Q4 | §3.2 | "s1 is said to be equal to s2 if and only if i1 is equal to i2" | C2 | native `=` on `int`; no dedicated function (folded into Q5/Q6's `not (= s1 s2)` conjunct) |
| Q5 | §3.2 | "s1 is said to be less than s2 if, and only if, s1 is not equal to s2, and (i1 < i2 and i2 - i1 < 2^(SERIAL_BITS - 1)) or (i1 > i2 and i1 - i2 > 2^(SERIAL_BITS - 1))" | C2 | `serial-lt` post, biconditional (`<=>`), verbatim-shaped |
| Q6 | §3.2 | "s1 is said to be greater than s2 if, and only if, s1 is not equal to s2, and (i1 < i2 and i2 - i1 > 2^(SERIAL_BITS - 1)) or (i1 > i2 and i1 - i2 < 2^(SERIAL_BITS - 1))" | C2 | `serial-gt` post, biconditional (`<=>`), verbatim-shaped |
| Q7 | §3.2/§4 | "there are some pairs of values s1 and s2 for which s1 is not equal to s2, but for which s1 is neither greater than, nor less than, s2. An attempt to use these ordering operators on such pairs … produces an undefined result." | C2-derived + C5 | implied by Q5+Q6 biconditionals (both false at distance exactly 2^31); demonstrated by check "a pair at distance exactly 2^31 is neither lt nor gt" |
| Q8 | §4 | "implementations are free to return either result, or to flag an error, and users must take care not to depend on any particular outcome." | C6 | prose about implementation freedom in the undefined region — our implementation picks total functions (both relations false there), which is one of the RFC-permitted behaviors; recorded, not contracted |
| Q9 | §5.1/§5.2 | examples at SERIAL_BITS == 2 and 8 ("255+1 == 0", "0 > 255", "It is undefined whether 2 > 0 or 0 > 2") | C5 (**width-adapted**) | three `check` blocks at SERIAL_BITS = 32 analogs — the RFC's vectors are width-parametric, so verbatim vectors do not transfer to the 32-bit instance (pipeline finding: C5 rows need a width column) |

**RFC-side coverage:** 9/9 normative clauses dispositioned (7 contracted or
check-carried, Q4 folded, Q8 recorded C6). This is the ratio the pipeline's §2
audit needs and `--spec-coverage` cannot see (it measures functions, not
clauses).

## Files

- `serial.llmll` / `serial.ast.json` — clean implementation → **verified** (SAFE,
  strict-core; trust report `verified: 3`).
- `serial-lt-bad.llmll` — the historical bug: plain `<`. Refuting witness
  s1 = 2^32-1, s2 = 0 (RFC: s1 < s2 TRUE; naive: false) →
  **refuted: serial-lt**.
- `serial-add-bad.llmll` — addition without the wrap →
  **refuted: serial-add** (post's range clause).
- `serial-lt-weak.llmll` — co-evolution exhibit: same naive body, post weakened
  to the one-directional near-ascending reading → **SAFE** (bug survives).
  Notably, `--weakness-check` DOES fire on this shape ("distinguishes your
  implementation from (lambda [...] true)") — a stronger mechanized signal than
  the tcp_rfc793 weak exhibit, where nothing fires; see the pipeline findings.

## Reproduce

```
llmll verify ./serial.llmll --strict-verified-core           # SAFE — verified: 3
llmll verify ./serial-lt-bad.llmll --strict-verified-core    # refuted: serial-lt
llmll verify ./serial-add-bad.llmll --strict-verified-core   # refuted: serial-add
llmll verify ./serial-lt-weak.llmll --strict-verified-core   # SAFE — bug survives the weak contract
llmll verify ./serial.llmll --spec-coverage                  # 100% (3/3), no suppression
llmll test   ./serial.llmll                                  # 3/3 properties pass; PBT witnesses recorded (:subjects)
```
