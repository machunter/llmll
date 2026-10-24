---
title: SIGMA-CONST-ARITH-1 — linear constant arithmetic in Σ_auto
status: Rev 0, SETTLED 2026-10-24 (user-requested settlement of the MEASURE row; no professor pass)
rows: SIGMA-CONST-ARITH-1 (G1, MEASURE → PLAN)
review: none (no professor pass)
---

# SIGMA-CONST-ARITH-1: linear constant arithmetic in Σ_auto

**Status: Rev 0, SETTLED 2026-10-24.** The user asked the language-team to settle the row and to do its MEASURE step in the same pass. This record does both. No professor pass was made.

The row is the prerequisite of `DECIMAL-1` (`docs/design/decimal-numbers-proposal.md`). It is also the condition for assurance credit on the MultiLangBench byte-codec contracts (`docs/design/multilangbench-scope-evaluation.md`, Rev 2).

## Restatement

Today the verifier refuses every term that is written with `*`, `/` or `mod`. It refuses linear forms too, such as `(* 8 r)` and `(mod r 8)`. These are refused because of the operator name, not because they are nonlinear.

This record decides which constant forms enter `Σ_auto`, and on what soundness argument. It also decides the trust effect and the version-stamp effect, and gives a witness for each edge.

The reference class is the verified-language set. Liquid Haskell, Dafny and F\* all accept multiplication by a constant, and integer division and modulus by a constant, as decidable arithmetic.

## Measurements

All measurements were made on 2026-10-24. Compiler-side results come from llmll 0.31.0, built from `03e7195e` in this worktree. Solver-side results come from the pinned `fixpoint` binary, run on hand-written single-file `.fq` witnesses with the flags llmll passes (`-q --json`). No corpus sweep was run.

### M1. The refusal sites at `03e7195e`

The row cites `:3585`, `:3830-3834` and `:4350`. Those line numbers are now wrong, so this record cites the sites by name. The refusal exists at seven sites, not three.

| Site | What it refuses |
|---|---|
| `exprToPred` in `compiler/src/LLMLL/FixpointEmit.hs`, the "non-linear ops: reject" arm | Contract and refinement terms. |
| `bodyToPredM` in `compiler/src/LLMLL/FixpointEmit.hs`, the "Non-linear operators: reject" arm | Body-faithful VC terms. |
| `appLabel` in `compiler/src/LLMLL/FixpointEmit.hs` | The `nonlinear:` fallback label. |
| `classifyGuardM` in `compiler/src/LLMLL/GuardClassifier.hs` | `if` guards. A parity test such as `(= (mod x 2) 0)` cannot path-split. |
| The callee exclusion lists in `compiler/src/LLMLL/FixpointEmit.hs` (the contracted-callee arm of `bodyToPredM`) and `compiler/src/LLMLL/ObligationAssembly.hs` | Keep `*`, `/` and `mod` out of the user-callee path. This is correct, and it stays. |
| `isCoreBodySyntactic` in `compiler/src/LLMLL/Syntax.hs`, through `isLinearOp` | A `def` body. See M3. |
| `isNonLinear` in `compiler/src/LLMLL/HoleAnalysis.hs` | Adds a `?proof-required non-linear-contract` hole whenever a `*`, `/` or `mod` node has a non-literal operand. `(* 8 r)` gets this hole too. |

`compiler/src/LLMLL/FixpointIR.hs` `FQBinOp` has only `FQAdd` and `FQSub` as arithmetic constructors. There is no multiplication, division or modulus.

### M2. The solver accepts the forms, and its rounding is Euclidean

The witnesses below are hand-written `.fq` files. Each one states a hypothesis (`lhs`) and a goal (`rhs`).

| Witness | Hypothesis, then goal | Result |
|---|---|---|
| w1 | `x = 0 - 7`, `result = x mod 8`; goal `result = 1` | Safe |
| w1n | the same; goal `result = 0 - 7` (truncation) | Unsafe |
| w2 | `x = 0 - 7`, `result = x / 8`; goal `result = 0 - 1` | Safe |
| w2n | the same; goal `result = 0` (truncation) | Unsafe |
| w3 | `result = 8 * r`; goal `result = r + r + r + r + r + r + r + r` | Safe |
| w3n | the same; goal `result = 7 * r` | Unsafe |
| w4 | `result = 3 * (x + y)`; goal `result = 3*x + 3*y` | Safe |
| w5 | `result = r * (0 - 3)`; goal `result + 3*r = 0` | Safe |
| neg | `result = -3 * x` (a negative literal, as `show` renders it); goal `result + 3*x = 0` | Safe |
| w6 | `result = (8 * r) mod 8`; goal `result = 0` | Safe |
| w7 | `result = (x / 8) * 8 + x mod 8`; goal `result = x` | Safe |
| w8 | `n > 0`, `result = n / 2`; goal `result < n` | Safe |
| w8n | `n >= 0`, `result = n / 2`; goal `result < n` | Unsafe (n = 0) |
| w9 | `result = x mod 8`; goal `0 <= result < 8` | Safe |
| w10 | `n = 7` and the `div-half-even n 2` unfolding of `DECIMAL-1`; goal `result = 4` | Safe |
| w10n | the same; goal `result = 3` | Unsafe |
| w11 | `result = 0 * x`; goal `result = 0` | Safe |
| w12 | `result = x / 1`; goal `result = x` | Safe |
| w13 | `result = x * y`; goal `result = y * x` (outside the admitted set) | Safe |
| n1 | `x = 0 - 7`, `result = x mod (0 - 8)`; goal `result = 1` | **Safe** |
| n2 | `x = 0 - 7`, `result = x / (0 - 8)`; goal `result = 1` | **Safe** |
| n3, n4 | `x = 7`, `result = x / 0`; goal `result = 12345`, then goal `result /= 12345` | Unsafe, Unsafe |

**What these show.**

- **Rendering.** liquid-fixpoint parses `*`, `/` and `mod` in infix form on the `int` sort, including a negative literal operand.
- **Rounding.** It hands `/` and `mod` to Z3 as SMT-LIB `div` and `mod`, which round in the Euclidean way.
- **Negative divisor.** In GHC, `(-7) mod (-8)` is `-7` and `(-7) div (-8)` is `0`. The solver proves `1` and `1` for the same terms (n1 and n2). A negative divisor would therefore let the verifier prove a value the program never computes. That is a **soundness defect**, and it is why a negative divisor stays refused.
- **Positive divisor.** In GHC, `(-7) mod 8` is `1` and `(-7) div 8` is `-1`, which match w1 and w2.
- **Zero divisor.** The solver leaves `x / 0` unconstrained (n3 and n4 are both Unsafe), while the program raises `DivisionByZero`. Admitting it would be sound but would prove nothing, so it stays refused.

### M3. Front-end facts

- **A `def` that multiplies or divides is refused today.** The S-expression parser turns `*` and `/` into `EOp` nodes, because `isOperator` in `compiler/src/LLMLL/Parser.hs` lists them. `isCoreBodySyntactic` refuses an `EOp` whose operator fails `isLinearOp`.
  - `(def m8 [r: int] -> int (* 8 r))` fails `llmll check` with "body contains non-core syntax — … non-linear arithmetic". The `DECIMAL-1` and byte-codec arithmetic is therefore not admitted in a `def` at all. It does not merely fall back.
- **`mod` is not refused, so the two front-end paths disagree.** `mod` is not in `isOperator`, so it parses as an `EApp`. `(def par [x: int] -> bool (if (= (mod x 2) 0) true false))` passes `check` and falls back silently, with "body-fallback: par" and no `W-BODY-FALLBACK` line.
- **`def-shell` falls back with a label.** `(* 8 r)`, `(mod x 8)` and `(/ x 8)` fall back with the labels `nonlinear:*`, `nonlinear:mod` and `nonlinear:/`.
- **A contract that multiplies falls back.** `(post (= result (* 8 r)))` over the linear body `(+ r (+ r …))` falls back. The body is linear; only the contract term refuses.
- **Codegen.** `/` lowers to Haskell `` `div` ``, and `mod` lowers to `` `mod` `` (`emitOp` in `compiler/src/LLMLL/CodegenHs.hs`). Both round toward negative infinity. `int` is `Integer`, so `*` is exact.

## Design proposal

### Surface: the admitted forms

A **ground constant** is an integer literal, or a closed term built from ground constants with `+`, `-`, `*`, `/` and `mod`. The compiler folds it to one integer at emission time, using the codegen semantics: exact `Integer` arithmetic, and Haskell `div` and `mod`.

- **Folding needs a positive divisor.** A `/` or `mod` inside a ground constant folds only when its divisor folds to a value greater than 0. Otherwise the whole term is not ground.
- **Examples.** `8`, `-3`, `(- 0 7)`, `(* 2 4)` and `(/ 256 2)` are ground constants.

An integer term `e` is **admitted** when it is one of the following:

| Form | Condition | Emitted |
|---|---|---|
| a ground constant | none | `FQLit v`, where `v` is the folded value |
| `(* c e)` or `(* e c)` | `c` is a ground constant (any sign, including 0); `e` is admitted | `c * e` |
| `(/ e c)` | `c` is a ground constant with value `> 0`; `e` is admitted | `e / c` (SMT `div`) |
| `(mod e c)` | `c` is a ground constant with value `> 0`; `e` is admitted | `e mod c` (SMT `mod`) |
| every form admitted today | unchanged | unchanged |

**Refused forms.** These keep their `nonlinear:` label and route exactly as they do today:

- the product of two terms where neither is a ground constant;
- a divisor that is not a ground constant;
- a ground divisor that is less than or equal to 0;
- `rem`, `^` and `**`.

**Nesting is recursive.** `(* 3 (+ x y))`, `(mod (/ x 8) 4)` and `(+ (* 256 hi) lo)` are all admitted.

**No constant propagation through `let`.** `(let [(k 8)] (* k x))` is refused, because `k` is a variable, not a ground constant. Write the literal instead. This keeps the admitted set a syntactic property that `check` can decide without data-flow analysis.

### Where the rule applies

One predicate, `constLinear`, decides membership. It replaces the name-based refusal at each site in M1:

1. **`exprToPred`** (contracts and refinement aliases) and **`bodyToPredM`** (bodies) emit the new IR terms for admitted forms. Refused forms return `Nothing`, as they do today.
2. **`classifyGuardM`** admits the same forms in `if` guards.
3. **`appLabel`** keeps `nonlinear:*`, `nonlinear:/` and `nonlinear:mod` for refused forms only. The labels do not change.
4. **`isCoreBodySyntactic`**: an `EOp` with `*`, `/` or `mod` is core syntax exactly when it is admitted.
   - The S-expression `(def m8 [r: int] -> int (* 8 r))` then passes `check`. `(def f [x: int y: int] -> int (* x y))` is still a core-grammar violation.
   - The `EApp` spelling of `mod` keeps today's admission and loses its silent fallback when the form is admitted. A refused `mod` in a `def` is not made an error by this row (risk 3).
5. **`isNonLinear`** (the advisory `?proof-required non-linear-contract` hole) fires only for refused forms. It no longer fires on `(* 8 r)`.
6. **The callee exclusion lists** do not change.

`compiler/src/LLMLL/FixpointIR.hs` gains three `FQBinOp` constructors, rendered `*`, `/` and `mod`. Fixpoint's `/` is integer `div` on the `int` sort (M2).

**Not changed by this row.** Codegen, the JSON-AST schema (operators are names), the type checker's arithmetic signatures, `isSimpleDecreases` (the `complex-decreases` advisory hole), and the `rem` / `^` / `**` refusal.

### Soundness argument

The claim is: for every admitted term `e` and every environment, the integer that the generated Haskell computes for `e` equals the value of the emitted SMT term under Z3's integer semantics. The argument is per operator.

- **Ground constants.** The folder uses the same `Integer` operations and the same `div` and `mod` as codegen, so the folded value is the runtime value. Folding only shortens the term the solver sees.
- **`(* c e)`.** Haskell `Integer` multiplication is exact, and SMT `*` over `Int` is mathematical multiplication. The two agree for every `c`, including 0 and negative values. With `c` a numeral, the term is linear.
- **`(/ e c)` and `(mod e c)` with `c > 0`.** Haskell defines `q = floor(e / c)` and `r = e - c·q`, so `0 ≤ r < c`. SMT-LIB defines `div` and `mod` (Euclidean) as the unique `q` and `r` with `e = c·q + r` and `0 ≤ r < |c|`. When `c > 0`, both definitions describe the same unique pair, so the two semantics agree.
  - M2 confirms this at `e = -7`: `mod` gives 1 and `div` gives -1 in both.
  - When `c < 0` they disagree (n1, n2, and the GHC results in M2), so a negative divisor is refused.
  - When `c = 0`, Haskell raises and SMT leaves the value unconstrained, so a zero divisor is refused.
- **Decidability.**
  - A product with a numeral is in QF-LIA as SMT-LIB defines it. The QF_LIA logic allows `(* c x)` with `c` a numeral.
  - `div` and `mod` by a positive numeral are outside the SMT-LIB QF_LIA symbol set, but they are a definitional extension of it. Each occurrence `t = e div c`, `s = e mod c` is equisatisfiable with fresh `t` and `s` under the linear constraints `e = c·t + s` and `0 ≤ s ≤ c - 1`.
  - So every admitted VC is equisatisfiable with a QF-LIA formula of a bounded size, and the `Σ_auto` statement of `LLMLL.md` §5.3.3 (a sound and complete decision procedure; "SAFE" is a decidable side condition) still holds.
  - This is the same treatment Presburger arithmetic gives divisibility by a constant.
- **Strict immutability.** The change is in the verifier only. No runtime construct is added.

**No new axiom.** No sealed-builtin axiom is added, and the closed set of `LLMLL.md` §13.12 is unchanged. `*`, `div` and `mod` are interpreted symbols of the integer theory, like `+` and `-`.

**The trusted claim.** Codegen emits `div` and `mod` for `/` and `mod`. That is a translation-faithfulness claim of the same kind as the existing claim for `+`.

### Trust and version-stamp effect

- **`checker_soundness_version` stays at `"3"`.** `LLMLL.md`'s note on the checker epoch keeps the stamp when the only effect is that clauses which did not translate now translate, while every clause that translated before emits the same term.
  - Admitted forms are exactly the clauses that returned `Nothing` before.
  - A clause with no `*`, `/` or `mod` node goes through unchanged code.
  - A ground constant that the solver path already saw as a literal emits the same literal.
  - **Engineer's gate.** A two-build `.fq` sweep over the corpus. Every changed `.fq` must contain a newly admitted term, and every file without one must be byte-identical. If the sweep shows another change, the stamp question reopens.
- **`codegen_semantics_version` is not spent.** Codegen does not change. `INT-3` keeps the stamp.
- **Trust moves only toward the evidence.**
  - A function that used to fall back is now `proved` or `refuted`.
  - A `refuted` result is a post that was assumed before and is false. That is the intended effect, and it is not a regression.
  - No verdict moves from `proved` to anything else.
  - `--strict-verified-core` admits more, never less.
- **Hole reports and `llmll check` change.** These do not touch the stamp.
  - The advisory `non-linear-contract` hole disappears for admitted forms.
  - An S-expression `def` using an admitted `*` or `/` changes from a core-grammar error to accepted.

## Edge cases and degenerate inputs

1. **Positive witness, `mod`.**
   - Input: `(def md [x: int] -> int (pre (= x (- 0 7))) (post (= result 1)) (mod x 8))`.
   - Expected: body-faithful SAFE. With `(post (= result (- 0 7)))` (truncation) it is refuted.
   - Channel: contract, QF-LIA. Cite: M2 w1 and w1n.
2. **Positive witness, `/`.**
   - Input: the same shape with `(/ x 8)`.
   - Expected: `(post (= result (- 0 1)))` is SAFE. `(post (= result 0))` is refuted.
   - Channel: contract, QF-LIA. Cite: M2 w2 and w2n.
3. **Positive witness, `*` in a `def` and in a contract.**
   - Input: `(def m8 [r: int] -> int (post (= result (+ r (+ r (+ r (+ r (+ r (+ r (+ r r)))))))) (* 8 r))`.
   - Expected: it passes `check` (today a core-grammar error, M3) and verifies SAFE. A post of `(* 7 r)` is refuted.
   - The mirror case `(def lin [r: int] -> int (post (= result (* 8 r))) (+ r …))` verifies. Today it falls back.
   - Channel: type for admission; contract, QF-LIA, for the post. Cite: M2 w3 and w3n; M3.
4. **Negative divisor stays refused.**
   - Input: `(mod x -8)` or `(/ x (- 0 8))`.
   - Expected: `nonlinear:mod` or `nonlinear:/`, fallback, tier `asserted`.
   - Admitting it would let the solver prove `result = 1` at `x = -7` while the program returns `-7` (M2 n1; GHC). The refusal is a soundness requirement, not a convenience.
   - Channel: contract fallback, fragment (b).
5. **Zero divisor stays refused.**
   - Input: `(/ x 0)` or `(/ x (- 1 1))`.
   - Expected: refused, because the ground divisor is not `> 0`. At runtime it is `DivisionByZero`.
   - The solver would leave the quotient unconstrained (n3 and n4).
   - Channel: contract fallback. The spec is silent on a divide-by-zero obligation, and that is intentional; it is a separate row if it is ever wanted.
6. **Degenerate constants.**
   - `(* 0 x)` is admitted and equals 0 (w11).
   - `(/ x 1)` equals `x` (w12). `(mod x 1)` equals 0.
   - `(* -3 x)` is admitted with a negative coefficient (neg, w5).
   - No special case is needed.
   - Channel: contract, QF-LIA.
7. **Ground folding.**
   - `(* 2 3)` emits `6`.
   - `(/ x (* 2 4))` is admitted with divisor 8.
   - `(/ x (- 0 8))` folds to -8 and is refused.
   - `(/ 7 0)` does not fold, so it is not ground. A term that contains it is refused.
   - Channel: contract.
8. **No propagation through `let`.**
   - Input: `(let [(k 8)] (* k x))`.
   - Expected: refused with `nonlinear:*`. The literal form is admitted.
   - The spec is silent on constant propagation, and that is intentional.
   - Channel: contract fallback.
9. **Product of two variables.**
   - Input: `(* x y)`.
   - Expected: refused as today: a core-grammar error in a `def`, `nonlinear:*` in a `def-shell`.
   - Z3 happens to prove `x*y = y*x` (M2 w13), but that is outside `Σ_auto`. Membership is decided by syntax, not by solver luck.
   - Channel: fragment (b).
10. **Parity guard.**
    - Input: `(def par [x: int] -> bool (post (= result (= (mod x 2) 0))) (if (= (mod x 2) 0) true false))`.
    - Expected: the guard classifies, the paths split, and the result is SAFE. Today the function falls back silently (M3).
    - Channel: contract, QF-LIA.
11. **A termination measure.**
    - Input: `(decreases n)` on a recursion that calls itself at `(/ n 2)` under `(pre (> n 0))`.
    - Expected: the decrease obligation `n / 2 < n` translates and discharges (M2 w8). Under `n >= 0` it is refuted (w8n), which is a correct refusal at `n = 0`.
    - The `complex-decreases` advisory hole for a non-variable measure is out of scope.
    - Channel: contract, QF-LIA.
12. **The `DECIMAL-1` consumer.**
    - Input: the `div-half-even n 2` unfolding at `n = 7`.
    - Expected: SAFE for `result = 4` and refuted for `result = 3` (M2 w10 and w10n). This is the condition `DECIMAL-1` waits on.
    - Channel: contract, QF-LIA.

## Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| Any VC containing only admitted `*`, `/` or `mod` forms | contract (body-faithful or contract VC) | (a) QF-LIA; `div` and `mod` by a positive numeral by definitional extension | `LLMLL.md` §5.3.3; this record, Soundness |
| `if` guards containing admitted forms | contract (path split) | (a) QF-LIA | `compiler/src/LLMLL/GuardClassifier.hs` |
| A product of two non-constant terms, a non-ground divisor, or a divisor `≤ 0` | contract fallback | (b) nonlinear, refused by syntax; Lean only on an explicit `?proof-required` | `LLMLL.md` §5.3.5, the row for multiplication, division and `mod` |
| `rem`, `^`, `**` | contract fallback | (b), unchanged | as today |

No obligation is routed to Lean by default. No obligation goes to the trust channel, and no axiom is added.

## Affected surface

**Engineer (code-track):**

- `compiler/src/LLMLL/FixpointIR.hs`: three `FQBinOp` constructors and their `emitOp` renderings.
- `compiler/src/LLMLL/FixpointEmit.hs`:
  - `exprToPred` and `bodyToPredM` emit admitted forms.
  - `appLabel` labels only refused forms.
  - A shared ground-constant folder and the `constLinear` predicate.
- `compiler/src/LLMLL/GuardClassifier.hs`: `classifyGuardM` admits the same forms.
- `compiler/src/LLMLL/Syntax.hs`: `isCoreBodySyntactic` admits an admitted `EOp` form.
- `compiler/src/LLMLL/HoleAnalysis.hs`: `isNonLinear` delegates to the same predicate.
- Tests:
  - the twelve edge cases as hspec cases;
  - n1 as a regression guard that a negative divisor stays refused;
  - the two-build `.fq` sweep as the stamp gate.

**Documentation lead (after the engineer ships):**

- `LLMLL.md` §5.3.3: the paragraph that records the omission ("the symbol set above omits `*`, `/` and `mod`"). Rewrite it to state the admitted forms and the positive-divisor rule.
- `LLMLL.md` §5.3.5: split the matrix row for multiplication, division and `mod` into an admitted row (✅ in both SMT columns) and a refused row.
- `LLMLL.md` §13.1: note that `/` and `mod` round toward negative infinity, and that they verify when the divisor is a positive constant.
- `docs/compiler-team-roadmap.md`: close `SIGMA-CONST-ARITH-1` on ship. Correct its stale line citations by naming the sites, as this record does. Update the `DECIMAL-1` row's prerequisite note.

**Additions.** None: this widens the reflected symbol set, with the soundness argument above. It adds no builtin, construct, FFI tier or capability.

## Risks and open questions

1. **The stamp gate can fail.** Classification: spec-drift. If the `.fq` sweep shows a change in a file with no admitted term, a translation that was believed fixed has moved. Then `checker_soundness_version` must increase. This complicates the release only.
2. **The row's line citations are wrong.** Classification: spec-drift. `:3585`, `:3830-3834` and `:4350` no longer point at the sites. The sites are named in M1. This is a doc-lead item.
3. **`mod` in a `def` is admitted and `*` is not, for a refused form.** Classification: scope. After this row, an admitted `*` or `/` `EOp` is core syntax, and a refused one is a core-grammar error. A refused `mod` (an `EApp`) is still admitted and falls back. Making the two spellings agree is a front-end question about `isOperator`, outside this row. It matters only at scale.
4. **Agents may write `(let [(k 8)] (* k x))` and see a refusal.** Classification: verification-ergonomics. The `nonlinear:*` diagnostic should say that a literal operand is admitted. This complicates use but does not block the row.

## Hand-off

- **Proposal:** `docs/design/sigma-const-arith-1-proposal.md`, Rev 0, settled. There is no review file.
- **Engineer summary.**
  - **Admitted forms.** `*` with a ground-constant operand of any sign; `/` and `mod` with a ground-constant divisor `> 0`. Folding uses Haskell semantics. There is no propagation through `let`.
  - **Implementation.** One predicate, applied in `exprToPred`, `bodyToPredM`, `classifyGuardM`, `isCoreBodySyntactic` and `isNonLinear`. Three new IR operators.
  - **Labels.** The refusal labels do not change.
  - **Versions and schema.** No schema change. `codegen_semantics_version` is not spent. `checker_soundness_version` stays at `"3"`, under the two-build `.fq` sweep gate.
  - **Witnesses.** The twelve edge cases. Witnesses 1, 2, 3 and 10 must flip from fallback, or from a check error, to SAFE. Witnesses 4 and 5 must stay refused.
- **Documentation-lead summary.** Rewrite the omission paragraph of `LLMLL.md` §5.3.3. Split the §5.3.5 matrix row. Add the floor-rounding and verification note to §13.1. Close the roadmap row and update the `DECIMAL-1` prerequisite note.
- **Blocking professor questions:** none.
