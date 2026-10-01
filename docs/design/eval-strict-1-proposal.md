---
name: eval-strict-1-proposal
title: "EVAL-STRICT-1: LLMLL is call-by-value, and code generation conforms"
status: "Rev 2, SETTLED 2026-09-29. Rev 1 accepted by the user 2026-09-29, and Rev 2 (the §0.1 amendment, `do` steps, zero-parameter definitions) accepted the same day. Migration MEASURED 2026-09-29 (eval-strict-1-measure-findings.md): no LLMLL source changes. Filed as EVAL-STRICT-1 (G2). Code-track; next is the engineer plan for the conforming code generator. The professor review is folded below."
date: 2026-09-28
author: language-team
consumers: [compiler-engineer, documentation-lead, professor, user]
reviews: "../archive/professor-reviews/eval-strict-1-review.md (professor, Rev 0; folded in the appendix)"
measurement: "eval-strict-1-measure-findings.md (engineer, 2026-09-29)"
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
> - **`do` blocks.** A `do` block (§9.6) evaluates as the `let` chain it compiles
>   to. Every step is evaluated to a value before the block's result, including
>   an anonymous step, whose state is discarded, and a `:discard` step, whose
>   command is discarded.
> - **Zero-parameter definitions.** A definition with no parameters is a function
>   of no arguments. A call `(k)` evaluates the body of `k` at that call; no
>   definition is evaluated at program start, and a call that is not reached
>   evaluates nothing. A bare reference `k` is a function value and evaluates
>   nothing. Because the body is pure, an implementation may reuse the value of
>   an earlier call to `k`; a call that fails fails at every call that reaches it.
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

### 4.4 The semantic foundation (`LLMLL.md` §0.1)

§0.1 now defines the language by what the generated Haskell does (`NC-001`,
`NC-002`), and states soundness against that program (`NC-004`). Today that
makes lazy evaluation normative: the §2 probe's exit 1 is "the correct
behavior" under `NC-002`. Rev 2 inverts the direction. The §4.1 subsection is
the semantics; the generated program implements it; a divergence is a code
generation defect. The trusted-base sentences `NC-036` to `NC-040` already name
code generation as trusted, so they stay.

Replacement text, to land in the same change as the conforming code generator
and not before it (before it, the current text describes the compiler
correctly):

> LLMLL is call-by-value, and §4.N states its evaluation order and the only
> forms that are not strict.`NC-001` The compiler is the reference
> implementation of that semantics: generated Haskell that evaluates
> differently from §4.N is a defect in code generation, not a definition of
> the language.`NC-002` There is no separate formal semantics document; §4.N is
> prose.`NC-003` Verification conditions emitted by `llmll verify` are sound with
> respect to the call-by-value semantics of §4.N under mathematical-integer
> (unbounded) semantics: a verified contract holds for all well-typed inputs,
> and there is no overflow gap on `int`, because `int` is unbounded on both
> sides (§5.3.5).`NC-004`

Registry rows (`scripts/norm-claims/registry.json`), re-affirmed in the same
change, as its README requires for an edited sentence:

| Id | Disposition now | Disposition after |
|---|---|---|
| `NC-001` | `assumed` (definitional stance) | `fixture`: the `@run` fixtures for edge cases 3, 10 and 12 below, each carrying `;; @norm: NC-001` |
| `NC-002` | `assumed` (definitional) | `assumed`: the compiler as reference implementation is still a decision; the reason names §4.N |
| `NC-003` | `informative` | `informative` |
| `NC-004` | `falsified-by` `gate:refute-crux` | unchanged; only the phrase "this generated-program semantics" changes |

`NC-001` moves from `assumed` to `fixture`, so the assumed count falls by one.
The fixtures use `@run` (`scripts/doc-claims/README.md`) and grade on output
text, so each edge case chosen fails with a message, never by divergence: a
fixture that must not terminate cannot be graded.

### 4.5 `do` blocks

§9.6 already says a `do` block "is compiled directly into a pure `let` chain".
Rev 2 makes the evaluation of that chain the §4.1 `let` rule, so a `do` block
needs no rule of its own. The consequence to state is that an anonymous step
and a `:discard` step are still evaluated: discarding a component of a value
does not skip computing the value. `emitDo` in
`compiler/src/LLMLL/CodegenHs.hs` binds every step in one lazy Haskell `let`
with tuple patterns, so today a step whose result nothing reads is never
evaluated. The measurement's code generator did not force `do` steps either
(findings, "What the measurement does not show", item 2).

### 4.6 Zero-parameter definitions

Twenty-three definitions in the repository take no parameters, one of them in
`tools/` (`stage-count` in `tools/llmll-driver/registry.llmll`, called as
`(stage-count)` in `sequencer.llmll`). The type checker gives a bare reference
the type `fn[0 args] -> int` and a call the type `int`: measured on v0.26.17,
`(+ x k)` fails with `type mismatch in '+': expected int, got fn[0 args] -> int`
and `(+ x (k))` checks. So the surface already treats `k` as a function; Rev 2
gives it the evaluation of one.

Two readings were open. "Once at program start" makes a program fail on a
definition it never calls, and needs an initialization order across modules
that the spec does not have. "At each call" follows from the §4.1 application
rule with zero arguments and needs nothing new. Rev 2 takes "at each call".
Reuse of an earlier call's value is allowed because it is not observable: the
body is pure, and a failing body fails again at the next call.

Code generation emits `k = <body>` today, a Haskell top-level value (a CAF),
and represents the bare reference and the call by the same Haskell term. That
is correct only because the term is lazy. A code generator that forces
arguments would evaluate the body when a bare `k` is passed as an argument,
which §4.1 forbids. The engineer's plan must keep the two apart.

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
10. **An anonymous `do` step that fails (Rev 2).**
    `(do [_ <- (pair s (list-length (unwrap (list-tail xs)))) :discard] (pair s (wasi.io.stdout "done")))`
    with `xs` empty fails with the `list-tail` error. Lazy code prints `done`.
    Channel: none statically (§4.5).
11. **A named `do` step whose state is never read (Rev 2).**
    `[s1 <- (pair (list-map xs f) cmd)]`, with `f` failing on an element and `s1`
    not read by a later step, fails. A code generator that forces only to WHNF
    returns. Channel: none statically (§4.5); conformance witness.
12. **A zero-parameter definition that fails and is never called (Rev 2).**
    `(def-shell broken [] -> int (unwrap (string-to-int "x")))` in a program that
    never calls `(broken)` runs normally. Under "once at program start" it would
    fail. Channel: spec is silent (intentional), §4.6.
13. **A bare reference passed as a value (Rev 2).**
    `(let [(g broken)] 0)` returns 0. `(let [(g broken)] (g))` fails at `(g)`.
    Channel: type (the bare reference has type `fn[0 args] -> int`), §4.6.

## 6. Verification mapping

No new obligation. Fragments are unchanged (§5.3.3). The Lean path
(`compiler/src/LLMLL/LeanTranslate.hs`) targets a strict language, so this
proposal makes it more consistent.

## 7. Affected surface

- `LLMLL.md`: the new §4 subsection; §5.3 "Sequential chains" drops "in
  evaluation order" and cites the subsection; §13.3 lists `=>` beside `and`
  and `or`; §0.1 `NC-001` to `NC-004` replaced as in §4.4; §9.6 cites the §4
  subsection for step evaluation.
- `scripts/norm-claims/registry.json`: rows `NC-001` to `NC-004` re-affirmed;
  `NC-001` becomes `fixture` (§4.4).
- `scripts/doc-claims/`: `@run` fixtures for edge cases 3, 10 and 12, each
  tagged `;; @norm: NC-001`.
- `docs/getting-started.md` and the checkout brief: state the strategy and the
  two unspecified orders. Agents write the code, so they must see the rule.
- `compiler/src/LLMLL/CodegenHs.hs`: conformance for every container in
  `toHsType`; an audit of the preamble for laziness it relies on.
- `compiler/src/LLMLL/CodegenHs.hs` `emitDo`: every step evaluated (§4.5);
  `emitDefLogic` for a zero-parameter definition: a bare reference must stay
  unevaluated when it is passed as an argument (§4.6).
- `compiler/src/LLMLL/Contracts.hs`: the comment on `wrapPre` becomes history;
  its `EIf` form stays correct.
- `compiler/src/LLMLL/FixpointEmit.hs`: no change. `exprToPred` is the
  enforcement point of the contract rule.
- Tests: edge cases 1 to 13 as built programs. Cases 6 to 8 and 11 separate WHNF
  from full evaluation.
- Roadmap (doc-lead): file `EVAL-STRICT-1` in G2, cross-referenced to
  `SHELL-CALL-PRE-1` and `DEF-ADMIT-XMOD-1`.

## 8. Risks

1. **Existing programs that depend on laziness.** Scope. Measured 2026-09-29
   (`eval-strict-1-measure-findings.md`): every gate that builds and runs an
   LLMLL program passes with bindings and arguments forced to full values, so
   no source changes. Residual: paths no gate runs, and the four positions the
   measurement did not force (`do` steps, zero-parameter definitions, unbound
   results, the preamble). Rev 2 fixes the semantics of the first two.
2. **Forcing at every use is slow.** Performance; complicates. The same
   measurement found 2.27 times on the path-lint run when every use forces a
   full value, and 1.09 times when it forces only the outermost constructor.
   Values built strict once, then forced to WHNF, conform at the lower cost.
3. **The cost of strict strings.** Scale. Evaluating a `String` fully costs
   time in proportion to its length, and the driver handles large JSON and
   Markdown texts. The mechanism, and whether `Text` is worth the change, is
   the engineer's decision, backed by a measurement.
4. **Crash or hang is now left open by the spec (edge case 2).** Ergonomics. A
   test cannot pin which failure a program with two failing parts shows.
   Checked: no test pins it today; `compiler/test/Spec.hs` checks only
   generated source text for the `Precondition violated in` message.
5. **The preamble relies on laziness.** `repeat 0` needs a lazy spine. The
   engineer keeps the preamble outside the strictness mechanism or rewrites it.
6. **Partial runs of holed programs fail sooner (edge case 4).** Matters only
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
- **Rev 2 (2026-09-29).** Rev 1 accepted by the user. Adds three items from the
  migration measurement and the v0.26.15 ceremony finding:
  - §4.4: the §0.1 replacement text for `NC-001` to `NC-004` and the registry
    rows; `NC-001` moves from `assumed` to `fixture`;
  - §4.5: `do` steps are evaluated as the `let` chain they compile to,
    including discarded steps;
  - §4.6: a zero-parameter definition is evaluated at each call, never at
    program start; a bare reference is a function value.

  Edge cases 10 to 13 and the risk entries on migration and cost are new.

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal is
folded here and the source file archived to
[`docs/archive/professor-reviews/eval-strict-1-review.md`](../archive/professor-reviews/eval-strict-1-review.md).
Folded at the settlement of Rev 2, 2026-09-29.

**Source:** `docs/design/eval-strict-1-review.md` at commit
`449b655c8ced812153ed651728e74b018a8ac358` (reviewed 2026-09-28; reviewer: Lead Consultant for Formal
Language Design). One round, against Rev 0. The review did not see Rev 2's additions (§4.4 to §4.6).

### Round 1 recommendation, against Rev 0, and its outcome

**Accept, with four text changes.** The reviewer found Rev 0's direction correct and rejected lazy
contracts (Chitil, ICFP 2012; Degen, Thiemann and Wehr, 2012) as the alternative: they keep a
laziness LLMLL does not use and add machinery. Each change and where it landed:

1. **Leave the order unspecified.** Rev 0 promised left-to-right evaluation, which GHC does not keep:
   strictness analysis under `-O` may evaluate strict arguments in any order, and only `pseq` fixes it
   (Peyton Jones et al., PLDI 1999). Rev 1 leaves argument order and the order of independent `let`
   bindings unspecified, and which of two failures is observed unspecified (§4.1, edge case 2).
2. **Strict constructors, not "no component left unevaluated".** In ML a value is built only from
   values, so no separate deep-forcing rule is needed; the Rev 0 wording invited a `deepseq` at every
   binding. The review also corrected Rev 0's claim about `Data.Map.Strict`, which forces a map's
   values only to WHNF. Rev 1 states strict constructors and containers and adds the map-with-list-values
   witness (edge case 7). The 2026-09-29 measurement confirmed the cost of the rejected wording:
   forcing a full value at every use cost 2.27 times on the path-lint run.
3. **Add `=>` to the non-strict forms; state `<=>` strict.** Adopted in Rev 1 (§4.1, edge case 5).
4. **Write the contract firewall into the spec.** Partial correctness is sound under call-by-value
   only while a specification contains no term that can diverge; F\* enforces this with its
   `Tot`/`Div` split (Swamy et al., POPL 2016), and LLMLL only because `exprToPred` reflects no user
   function. Rev 1 adds the rule that a contract mentions only builtins and constructors, and that a
   user function may enter one only if its termination is proved (§4.1, §4.2).

The review's convergence note stands unchanged: functions in the verified core are total on their
`pre`, so by Turner's argument (JUCS 2004) the strategy changes meaning only in `def-shell` code and
partial builtins, and the crash-to-hang shift of edge case 1 is acceptable because a program with
either behavior was already incorrect.
