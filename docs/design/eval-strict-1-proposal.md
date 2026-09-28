---
name: eval-strict-1-proposal
title: "EVAL-STRICT-1: LLMLL is call-by-value, and code generation conforms"
status: "Rev 1, READY FOR ADJUDICATION 2026-09-28. Rev 0 reviewed by professor (eval-strict-1-review.md); all four findings accepted in Rev 1. No roadmap row filed yet; proposed row EVAL-STRICT-1 in G2. Code-track. The first engineer step is a migration measurement (a strict build of the tree run against the existing covers), which sizes the migration and does not decide the semantics."
date: 2026-09-28
author: language-team
consumers: [compiler-engineer, documentation-lead, professor, user]
reviews: "eval-strict-1-review.md (professor, Rev 0)"
related: "shell-call-pre-1-proposal.md (finding D3 there opened this proposal)"
---

# EVAL-STRICT-1: LLMLL is call-by-value, and code generation conforms

**One line.** `LLMLL.md` states no evaluation strategy. The verifier reasons as
if evaluation were strict, and the generated Haskell is lazy. Under that
mismatch `verify` makes a claim that a built program falsifies. This proposal
makes LLMLL call-by-value and makes code generation conform.

## 1. Summary

- LLMLL is call-by-value. Constructors and the builtin containers are strict.
- The only non-strict forms are `if`, `match`, `and`, `or`, `=>` and a `fn` body.
- Argument order and the order of independent `let` bindings are unspecified.
  When more than one sub-expression fails, which failure is observed is
  unspecified.
- A contract mentions only builtins and constructors. A user function may enter
  a contract only if its termination is proved. This is what makes partial
  correctness sound.
- Code generation must deliver full values for every container type. The GHC
  `Strict` pragma alone does not: it evaluates to the outermost constructor.

No new proof obligation is introduced. Existing claims become correct.

## 2. Background: the measured defect

Probe program (v0.26.13), one module:

```
(def tally [seen: int] -> int (pre (>= seen 0)) (post (>= result 1)) (+ seen 1))
(def-shell spin [x: int] -> int (post (and (= result 1) (= result 2))) (spin x))
(def-shell use [s: int] -> int (post (>= result 0))
  (let [(y (spin s))] (tally (- 0 5))))
(def-shell ctl [s: int] -> int (post (>= result 0))
  (let [(y (+ s 0))] (tally (- 0 5))))
```

- `verify` refutes the call-site `pre` of `tally` in `ctl`, and accepts the
  same call in `use`. In `use`, the contradictory post of `spin` is in the
  context, so the goal holds vacuously.
- With `ctl` removed and a `:mode cli` entry that calls `(use 3)`, `verify`
  prints `SAFE ... 2 proved only if they terminate: spin, use (via spin)`.
- The built binary exits 1 at once with `Precondition violated in tally`.
  Lazy code never evaluates `y`, so `use` terminates and violates the `pre`.

The claim "proved only if it terminates" is the partial-correctness reading. It
is correct under call-by-value and incorrect under call-by-need. The runtime
`pre` check caught this run; the static claim is still wrong.

This is the second contract defect caused by laziness. The comment on
`wrapPre` in `compiler/src/LLMLL/Contracts.hs` records the first: a `pre` check
bound to an unused `let` never ran.

## 3. Context

1. `LLMLL.md` has no evaluation-strategy section. §13.3 specifies `and` and `or`
   as short-circuit. §5.3 "Sequential chains" speaks of calls "in evaluation
   order" and does not define that order.
2. `docs/archive/shipped-design-specs/agent-prompt-semantics-gap.md` §A.2 wrote
   the agent-facing rule "Strict evaluation: all arguments are evaluated before
   function application". No live file carries this text now. The project
   stated the intent once and then lost it.
3. `compiler/src/LLMLL/CodegenHs.hs`:
   - `emitOp` lowers `and`, `or` and `=>` to short-circuit Haskell, and `<=>`
     to `==`, which evaluates both operands.
   - `if` lowers to Haskell `if`; `match` lowers to `case`.
   - `emitHole` lowers every hole kind to `error`.
   - `toHsType` maps `string` to `String`, `bytes` to `[Word8]`, `list` to a
     Haskell list, `pair` to a tuple, `Result` to `Either`, `map` to `Map.Map`,
     and `Command` to `IO ()`. Every container is lazy today.
   - The runtime preamble uses `take 20 (... ++ repeat 0)`, which needs a lazy
     list spine inside the preamble.
4. `compiler/src/LLMLL/FixpointEmit.hs`, `exprToPred`: a contract may apply only
   builtins, constructors and the `ok`, `err`, `is-ok` encodings. Every other
   application returns `Nothing`. `bodyToPredM` requires both operands of `and`
   and `or` to be pure predicates, so the verifier never depends on
   short-circuit order.
5. Design-reference set. Dafny, F\*, Lean 4 and Idris 2 are strict by default
   (Idris 2 marks laziness with `Lazy`). Liquid Haskell is lazy and needed
   termination checking by default to stay sound (Vazou et al., ICFP 2014).
   LLMLL's design, partial correctness with optional termination, matches the
   strict group.

## 4. Design

### 4.1 Spec text for a new subsection at the end of `LLMLL.md` §4

> **Evaluation strategy.** LLMLL is call-by-value.
>
> - **Values.** A value is an integer, float, boolean, unit, string, or bytes;
>   a constructor, pair, `Result`, list or map whose components are values; or
>   an opaque value: a function closure, a `Command` or a `Promise`.
>   Constructors and the builtin containers are strict: they are built only
>   from values.
> - **Application.** `(f e₁ … eₙ)` evaluates each `eᵢ` to a value, then applies
>   `f`. The order in which the arguments are evaluated is unspecified.
>   Builtins follow the same rule.
> - **`let`.** Each binding is evaluated to a value before the body. A binding
>   can see only the bindings before it. The order in which independent
>   bindings are evaluated is unspecified.
> - **Failure.** An evaluation fails when it reaches a failed `pre`, a hole, a
>   runtime error, or does not terminate. When more than one sub-expression
>   would fail, which failure is observed is unspecified.
> - **Non-strict forms, and only these.** `if` evaluates its condition, then
>   exactly one branch. `match` evaluates its scrutinee, then exactly one arm.
>   `and`, `or` and `=>` evaluate their right operand only when the left
>   operand does not decide the result (§13.3); `<=>` evaluates both operands.
>   A `fn` body is evaluated only when the function is applied.
> - **Opaque values.** Evaluating a `Command` builds the action and does not
>   run it. Effects happen only when the `def-main` harness runs a `Command`
>   (§9.4), in the order the harness runs them.
> - **Contracts.** A `pre` is evaluated when the function is entered, after its
>   arguments. A contract mentions only builtins and constructors. A user
>   function may enter a contract only if its termination is proved. This rule
>   is what makes partial correctness sound: a specification never contains a
>   term that can diverge.

### 4.2 What this settles in the verifier

| Existing claim | Under lazy codegen (today) | Under EVAL-STRICT-1 |
|---|---|---|
| Body VC with callee posts in context (F-NIW-4) | Sound only if every callee whose post is assumed terminates | Sound as partial correctness |
| "proved only if they terminate" | Incorrect when a non-terminating binding is never evaluated (§2) | Correct |
| Runtime `pre` check | Runs only if the callee's result is used | Runs at every call reached |

- `exprToPred` already enforces the contract rule. The spec now states it, so a
  future reflection feature (in the manner of Liquid Haskell's `reflect`) must
  satisfy it.
- SHELL-CALL-PRE-1 needs no termination filter on its context, and its
  must-fail outcome is named `violated-if-reached`.
- The row `LAZY-POST-CTX-1`, drafted in SHELL-CALL-PRE-1 Rev 1, is not filed.
  Its content is this proposal's conformance work.

### 4.3 Code-generation conformance

The acceptance criterion is behavioral: the edge cases in §5, run as built
programs. The mechanism is the engineer's choice. It must cover every type in
`toHsType` that holds components: user types, lists, `bytes`, `string`, pairs,
`Result`, and the values of a map.

The `Strict` pragma alone does not conform, because it evaluates a binding only
to its outermost constructor. `Data.Map.Strict` alone does not conform either,
for the same reason. Changing `string` to `Text` is one way to make strings
strict; it is a representation change with its own cost, and this proposal
does not require it.

## 5. Edge cases

1. **Positive witness: the lazy false proof.** The program in §2. `y` diverges
   and `tally` is never reached, so the "proved only if it terminates" claim is
   true. Observable change: exit 1 becomes a hang. Channel: contract, with the
   termination disclosure on the trust channel.
2. **Order not fixed.** `(f (spin x) (tally (- 0 5)))` either diverges or fails
   with `Precondition violated in tally`. Both conform. Partial correctness
   holds under both. Channel: spec is silent on which failure (intentional).
3. **A value bound before its guard.**
   `(let [(h (list-head xs))] (if (list-empty? xs) 0 h))` fails on an empty
   list; today it returns 0. The program is incorrect under the stated
   semantics and is a migration target. Channel: none statically.
4. **A hole in a strict position.** `(let [(x ?todo)] (if c x 0))` fails at the
   binding, even when `c` is false. A hole in a branch not taken does not fail.
   Channel: type (hole analysis already reports the hole).
5. **Short-circuit.** `(=> (not (list-empty? xs)) (= (list-head xs) 0))` does
   not evaluate `list-head` on an empty list. The same holds for `and` and
   `or`. `(<=> p q)` evaluates both. Channel: §13.3 and §4.1.
6. **Deep list (conformance witness).**
   `(let [(ys (list-map spin xs))] (list-length ys))` with `xs` not empty
   diverges. A WHNF-only codegen returns the length.
7. **Map with list values (conformance witness).** A map value built by
   `(list-map spin xs)` and then only tested for key presence diverges.
   `Data.Map.Strict` alone returns.
8. **String contents (conformance witness).** A `string` built from a failing
   sub-expression and then only measured must fail. A lazy `String` can
   return. The engineer confirms the exact builtin shape with a probe.
9. **Opaque values.** `(let [(g (fn [x: int] (spin x)))] 0)` returns 0.
   Building a `wasi.fs.write` command evaluates its arguments and performs no
   write. Channel: spec is silent (intentional).

## 6. Verification mapping

No new obligation. Fragments are unchanged (§5.3.3). The Lean path
(`compiler/src/LLMLL/LeanTranslate.hs`) targets a strict language, so this
proposal makes it more consistent.

## 7. Affected surface

- `LLMLL.md`: the new §4 subsection; §5.3 "Sequential chains" drops "in
  evaluation order" and cites the subsection; §13.3 lists `=>` beside `and`
  and `or`.
- `docs/getting-started.md` and the checkout brief: state the strategy and the
  two unspecified orders. Agents write the code, so they must see the rule.
- `compiler/src/LLMLL/CodegenHs.hs`: conformance for every container in
  `toHsType`; an audit of the preamble for laziness it relies on.
- `compiler/src/LLMLL/Contracts.hs`: the comment on `wrapPre` becomes history;
  its `EIf` form stays correct.
- `compiler/src/LLMLL/FixpointEmit.hs`: no change. `exprToPred` is the
  enforcement point of the contract rule.
- Tests: edge cases 1 to 9 as built programs. Cases 6 to 8 separate WHNF from
  full evaluation.
- Roadmap (doc-lead): file `EVAL-STRICT-1` in G2, cross-referenced to
  `SHELL-CALL-PRE-1` and `DEF-ADMIT-XMOD-1`.

## 8. Risks

1. **Existing programs that depend on laziness.** Scope; complicates. The count
   is unknown: the driver alone is 8,522 lines, and `tools/` and `examples/`
   add more. A strict build run against the existing covers sizes the
   migration. It does not decide the semantics.
2. **The cost of strict strings.** Scale. Evaluating a `String` fully costs
   time in proportion to its length, and the driver handles large JSON and
   Markdown texts. The mechanism, and whether `Text` is worth the change, is
   the engineer's decision, backed by a measurement.
3. **Crash or hang is now left open by the spec (edge case 2).** Ergonomics. A
   test cannot pin which failure a program with two failing parts shows.
   Checked: no test pins it today; `compiler/test/Spec.hs` checks only
   generated source text for the `Precondition violated in` message.
4. **The preamble relies on laziness.** `repeat 0` needs a lazy spine. The
   engineer keeps the preamble outside the strictness mechanism or rewrites it.
5. **Partial runs of holed programs fail sooner (edge case 4).** Matters only
   at scale.

## 9. Revision history

- **Rev 0 (2026-09-28).** Call-by-value to full values; left-to-right order;
  non-strict forms `if`, `match`, `and`, `or`, `fn`.
- **Rev 1 (2026-09-28).** Folds the professor review:
  - order unspecified, and which failure is observed is unspecified (H1);
  - strict constructors and containers instead of "no component left
    unevaluated" (H2);
  - `=>` added to the non-strict forms, `<=>` stated strict (H3);
  - the contract rule written into the spec (H4).

  Two Rev 0 claims were also corrected. `string` lowers to a lazy `String`,
  not `Text`. `Data.Map.Strict` is strict only to WHNF. `Command` is recorded
  as an opaque `IO ()` value.
