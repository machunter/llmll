---
name: shell-call-pre-1-proposal
title: "SHELL-CALL-PRE-1: a call from a body that falls back proves nothing about the callee's pre, and nothing says so"
status: "Rev 3, SETTLED 2026-10-01 (accepted by the user). Next: compiler-engineer plan for Part 2, gated on a prototype outcome count. Rev 0 reviewed by professor (shell-call-pre-1-review.md); Rev 1 folded the review; Rev 2 removed the termination filter (T) because of EVAL-STRICT-1; Rev 3 checks Part 2 against the shipped call-by-value semantics (LLMLL.md §4.7, v0.27.0). Part 1 SHIPPED v0.26.14 (68a1112). Part 2 is code-track and has no open dependency; it waits on adjudication and on a prototype that counts outcomes per site. Roadmap row SHELL-CALL-PRE-1 (G1) carries DECIDE; this proposal answers it: both shapes, A producing evidence and B carrying it."
date: 2026-10-01
author: language-team
consumers: [compiler-engineer, documentation-lead, professor, user]
reviews: "shell-call-pre-1-review.md (professor, Rev 0)"
related: "eval-strict-1-proposal.md (shipped v0.27.0; Part 2 rests on LLMLL.md §4.7); roadmap rows PARTIAL-FNS-GRAPH-1, DEF-ADMIT-XMOD-1"
---

# SHELL-CALL-PRE-1: call-site preconditions in bodies that fall back

**One line.** Call-site `pre` obligations come only from a built body VC. A
caller whose body falls back gets none. Since v0.26.14, `verify` names these
calls on a `call-pre unchecked:` line, and nothing proves them.

## 1. Summary

The roadmap row asked for a choice: (A) prove the callee's `pre` at the call
site, or (B) disclose that nothing proved it. This proposal does both, in two
parts.

| Part | What it does | Depends on | Changes a verdict? | State |
|---|---|---|---|---|
| 1 | Repairs the TRUST-PRE disclosure for opened imports (finding D2) and adds one `verify` line | nothing | no | SHIPPED v0.26.14 (`68a1112`) |
| 2 | Emits call-site `pre` obligations in bodies that fall back, in a side query with four outcomes | EVAL-STRICT-1 (shipped v0.27.0); a prototype count | no (report and warning only) | this revision |

## 2. Measurements

1. **Same-module probe (v0.26.13).** A `def tally` has `(pre (>= seen 0))`. A
   `def-shell caller` calls `(tally (- 0 5))`. `verify` prints `SAFE` and exits
   0. The trust report gives `caller` a `caller_obligations` row
   `(>= seen 0)`. The row states the predicate and not whether this call meets
   it.
2. **Copy of `tools/doc-path-lint/pathlint.llmll` (v0.26.13).** `scan-file`
   calls `tally` and `pl-status` calls `status-of`, both through
   `open adjudicate`. Both callers showed
   `carries_caller_obligations: false`. This was finding D2, fixed by Part 1.
3. **Call-site population (re-measured v0.27.0, 2026-10-01).** `llmll verify`
   on each `def-main` program under `tools/` prints the `call-pre unchecked:`
   pairs. There are 15 caller-to-callee pairs in 4 programs:

   | Program | Pairs |
   |---|---|
   | `tools/doc-path-lint/pathlint.llmll` | 2 (`scan-file -> adjudicate.tally`, `pl-status -> adjudicate.status-of`) |
   | `tools/llmll-driver/sequencer.llmll` | 9 (four `shape.*-conform?` calls from `shape-verdict`, and one each to `barrier-condition-met?`, `feasibility-established?`, `matrix-complete?`, `omission-free?`, `verdict-of`) |
   | `tools/llmll-driver/spine.llmll` | 2 |
   | `tools/llmll-driver/wave.llmll` | 2 |

   The five other tool programs have none. A pair can have more than one site:
   `outp-decide` calls `verdict-of` twice. Rev 2 estimated about 21 sites. The
   prototype counts sites, not pairs.
4. **Why a site cannot be proved from nothing.** In `pathlint`,
   `(tally (found-of acc2) true)` passes the result of `found-of`, a
   `def-shell` JSON read with no `post`. The argument is unconstrained.
   Non-negative length facts (`nonNegMeasures`) do reach `list-length` and
   `string-length` arguments. Both `spine.llmll` sites pass a `list-length` result, but
   `bad-barrier-count` also requires `excluded >= listed-barrier`, which no
   length fact gives.
5. **A `post` is checked at run time (v0.27.0).** A probe `def-shell neg`
   with `(post (>= result 0))` and body `(- 0 5)`, built with the default
   `--contracts=full`, stops with `Postcondition violated in neg`, exit 1.
   The check comes from `wrapPost` in `compiler/src/LLMLL/Contracts.hs`. The
   probe's caller of `tally` is never entered. Section 4.2 uses this result.

## 3. Findings outside the row

- **D1 (spec drift), RESOLVED v0.26.14.** `LLMLL.md` §5.3.4 now has the
  paragraph "A caller with no body VC": nothing proves a callee's `pre` at
  those calls, and the runtime assertion is the only check. Part 2 changes
  that paragraph (Section 7).
- **D2 (code defect), FIXED v0.26.14.** The bare-versus-qualified name family
  of `PARTIAL-FNS-GRAPH-1`.
- **D3 (spec gap), SETTLED v0.27.0.** `LLMLL.md` §4.7 states call-by-value.
- **D4 (record defect), new in Rev 3.** The professor review, Context item 1,
  says no build mode removes the runtime `pre` check. `--contracts=none`
  removes every runtime assertion (`applyContractsMode` in
  `compiler/src/LLMLL/Contracts.hs`; `LLMLL.md` §4.4.2). `--contracts=unproven` never removes a `pre` (`filterContracts`).
  The Rev 2 text repeated the claim. Rev 3 states the modes in Section 4.2.

## 4. Design

### 4.1 Part 1: repair the disclosure (SHIPPED v0.26.14)

- `markCallerObligations` in `compiler/src/LLMLL/TrustReport.hs` resolves
  callee names through the module-qualified call graph. The resolver is
  `LLMLL.CallGraph` (`qualifiedCallGraph`, `resolveIn`), shared with
  `PARTIAL-FNS-GRAPH-1`. Rev 2 named `LLMLL.ProgramGraph`; the shipped module
  is `LLMLL.CallGraph`.
- `verify` prints `call-pre unchecked: <caller> -> <callee>, ...` for each
  call from an entry-module function with no body VC. The exit status does not
  change (`uncheckedCallPres`, `compiler/app/Main.hs`).

### 4.2 Part 2: call-site obligations in a body that falls back

For each call site *s* of a callee *g* with `pre_g` in `Σ_auto`, in a caller
*f* whose body VC was not built:

```
Γ_s  ⊢  pre_g[a₁/x₁ … aₙ/xₙ]
```

Each argument aᵢ is a fresh variable, constrained by the facts below when it
translates. Γ_s holds only facts that translate faithfully. Every other fact is
dropped:

- `pre_f`, when it translates (the RESP-FACT-1 `preUsable` rule);
- each enclosing `if` guard that `exprToPred` translates, with the polarity of
  its arm;
- the left operand of an enclosing `and`, `or` or `=>` whose right operand
  contains *s*, when it translates: `l` for `and` and `=>`, `¬l` for `or`
  (new in Rev 3);
- each enclosing `let` equality, and each `do` step binding, whose right-hand
  side translates, resolved by lexical scope (the F-NIW-4b `inScopeLbs`
  precedent);
- for an argument that is a call `h(...)`, including a zero-parameter call
  `(k)`, a fresh result variable with `h`'s `post` assumed (the F-NIW-4
  `ctxCalls` precedent);
- the non-negative length facts (`nonNegMeasures`).

A `match` arm adds no fact in this revision. Dropping it is sound and costs
yield only.

**Soundness argument, against `LLMLL.md` §4.7.** The claim is: every kept
fact is true in every evaluation that enters *g* at *s*. Each fact rests on
one §4.7 clause.

| Fact | §4.7 clause | Why it holds when *g* is entered at *s* |
|---|---|---|
| `pre_f` | Contracts: a `pre` is evaluated on entry, after the arguments | *f* was entered, so its `pre` check passed |
| `if` guard, with polarity | Non-strict forms: `if` evaluates its condition, then exactly one branch | *s* is in the branch that the guard value selected |
| `and` / `or` / `=>` left operand | Non-strict forms: the right operand is evaluated only when the left does not decide | *s* is in the right operand, so the left had the value that does not decide |
| `let` and `do` binding equality | `let`: each binding is a value before the body; `do`: a `let` chain | the binding was evaluated to a value before *s*, and values are immutable (§1 item 1) |
| `h`'s `post` for an argument `h(...)` | Application: each argument is a value before *g* is applied | `h` returned, so its `post` holds at partial correctness |
| a variable captured by a `fn` | `fn` body is evaluated only when applied | the closure was built after the enclosing facts held, and values do not change |
| length facts | the builtin's result is a value | builtin semantics |

The Failure clause makes the order of argument evaluation and the choice of
failure unspecified. This does not affect the claim. *g*'s `pre` is checked
only on entry, and entry needs every argument to be a value.

Dropping a fact makes the goal harder, never easier. So a `proved` site is a
valid proof, relative to the `post`s it used, which the report names. An
argument that does not translate yields no constraint and the outcome
`unproved`, never a silent drop.

**What a used `post` rests on.** A `post` that `h`'s body VC proves holds by
§0.1 NC-004. A `post` that nothing proves is an assumption in the static
verdict. Measurement 5 shows that the built program also checks it, under
`--contracts=full` and `--contracts=unproven`. In those builds, an execution
that violates `h`'s `post` stops in `h` and never enters *g* at *s*. Under
`--contracts=none`, no check remains, and the assumption is the only basis.
The static trust tier is the same in every mode: the §5.3.4 meet, with an
`inherited-axiom` row for each `post` not proved. Edge case 4 states the
consequence.

**No dependency remains.** Rev 2 waited on EVAL-STRICT-1. It shipped at
v0.27.0, and §0.1 NC-001 now defines LLMLL by §4.7. The Rev 2 fallback, which
shipped Part 2 with the termination filter (T) before EVAL-STRICT-1, is
removed. A non-terminating `h` never returns, so its `post` is never a fact at
an entered site.

**Outcomes.** One side query, following the precedent of
`checkWeaknessCandidate` in `compiler/app/Main.hs`. A failed goal there is not a
counterexample, so it must not share the program's query. Each site is checked
in this order, with at most three kvar-free constraints:

| Order | Check | Outcome |
|---|---|---|
| 1 | Γ_s ⊢ false | `unreachable` |
| 2 | Γ_s ⊢ pre_g[args] | `proved`, at the meet of the levels of the facts used (§5.3.4) |
| 3 | Γ_s ⊢ ¬pre_g[args] | `violated-if-reached` |
| 4 | otherwise | `unproved`, with reason `context`, `argument-outside-fragment` or `pre-outside-fragment` |

Check 3 is sound only because check 1 comes first: a consistent Γ_s that proves
¬pre means every evaluation that enters *g* at *s* violates the `pre`.
"Reached" in the outcome name means "*g* is entered at *s*", that is, every
argument at *s* is a value.

**Headline.** When not zero, the `verify` headline adds the counts, for example
`SAFE (...); call sites: 1 violated-if-reached, 2 unreachable`. The exit status
does not change. The `call-pre unchecked:` line from Part 1 then lists only the
sites that are not `proved`.

**Code generation does not read the outcomes.** The runtime `pre` check stays at
every site, including `proved` ones. The outcomes never enter the
`ContractStatus` map that `applyContractsMode` reads. `filterContracts` keeps
every `pre` under `--contracts=unproven` today, and Part 2 does not change
that.

**Trust report.** Each site appears as a `precondition-obligation` with its
§11.2 sited id and its outcome. A proved site lists every `post` it relied on
that nothing proves, as an `inherited-axiom` row. A callee drops off a caller's
`caller_obligations` only when every call site to it is `proved`.

## 5. Edge cases

1. **Positive witness, must-fail through a `let`.**
   `(def-shell c [s: int] -> int (let [(n (- 0 1))] (tally n)))` gives
   Γ_s ⊢ ¬(n ≥ 0): `violated-if-reached`. Channel: contract.
2. **Positive witness, `unreachable`.**
   `(if (> x 0) (if (< x 0) (tally (- 0 5)) 0) 0)` in a body that falls back.
   Both guards are kept, Γ_s is unsat, and the outcome is `unreachable`, not
   `proved`. Channel: contract.
3. **Literal violation.** `(tally (- 0 5))` in a `def-shell`: a closed false
   goal, `violated-if-reached`. Today: `SAFE`, and `call-pre unchecked`
   names the pair without a verdict.
4. **Argument from a helper with no post.** `(tally (found-of acc2) true)`:
   `unproved (context)`. If `found-of` gains `(post (>= result 0))`, the site
   is `proved` relative to that `post`, and the report names it as an
   `inherited-axiom`. Under `--contracts=full`, a run that violates the new
   `post` now stops in `found-of` and not in `tally`. The trust moves to
   `found-of`; it is not removed. Channel: trust.
5. **Guarded call.** `(if (>= x 0) (tally x) 0)`: the guard is kept and the
   site is `proved`. With `(regex-match ...)` as the guard, it is dropped and
   the site is `unproved (context)`: a false alarm by design, never a
   refutation.
6. **Shadowing (soundness hazard).**
   `(let [(x (- 0 1))] (let [(x (found-of r))] (tally x)))`: the inner `x` must
   not take the outer equality. A wrong walker gives a false result in either
   direction. A test cell is owed.
7. **Call inside a lambda.** In `(list-filter rows (fn [r: Json] ...))`, an
   argument bound by the lambda has no facts: `unproved
   (argument-outside-fragment)`. A captured variable keeps its enclosing facts:
   `(if (>= n 0) (list-map xs (fn [r: int] (tally n))) ...)` is `proved`.
8. **Short-circuit operand (positive witness, new in Rev 3).** A callee
   `ok? [n: int] -> bool` with `(pre (>= n 0))`, called as
   `(and (>= x 0) (ok? x))`. The left operand is kept and the site is `proved`.
   `(or (>= x 0) (ok? x))` keeps `¬(x ≥ 0)` and gives `violated-if-reached`.
   A walker that kept `l` for `or` would give a false `proved`. A test cell is
   owed for each operator.
9. **Zero-parameter call (new in Rev 3).** `(tally (k))` with
   `(def k [] -> int (post (>= result 0)) 3)`. §4.7 evaluates `(k)` at the
   call, so the `post` of `k` is assumed and the site is `proved`. A bare `k`
   is a function value, not an `int`, and cannot be an argument here.
10. **Opened versus qualified callee.** `scan-file` calls `tally` through
    `open`. Part 1 lists it (measurement 3). Part 2 gives it an outcome.
11. **Callee `pre` outside `Σ_auto`.** No constraint:
    `unproved (pre-outside-fragment)`.

## 6. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Γ_s ⊢ false; Γ_s ⊢ pre_g[args]; Γ_s ⊢ ¬pre_g[args] | contract (`precondition-obligation`), outcome on the trust channel | QF-LIA whenever emitted (§5.3.3); the fragment is closed under negation |

Nothing is nonlinear, and nothing goes to Lean. The new `and` / `or` / `=>`
facts are `exprToPred` translations and stay in the same fragment.

## 7. Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: a context walker for bodies that fall
  back, emitting into a second constraint set. `collectCallPreObligations` is
  unchanged.
- `compiler/app/Main.hs`: the side query; the headline counts; the
  `call-pre unchecked:` line filtered to sites that are not `proved`.
- `compiler/src/LLMLL/TrustReport.hs`: the transitive rule in
  `markCallerObligations` becomes site-aware.
- `compiler/src/LLMLL/ObligationAssembly.hs`: sited
  `precondition-obligation` rows with outcomes.
- `LLMLL.md` §5.3.4, the paragraph "A caller with no body VC" (the side query
  and its outcomes); §5.3.5 (the two call-pre paths); §11.2 (outcome values);
  `tools/VERIFICATION.md` "What is not proved".
- The professor review, Context item 1 (D4): doc-lead adds a dated correction
  note on fold. The review text itself is not reworded.

## 8. Risks

1. **Context walker errors.** Soundness. Edge cases 6 and 8 are the two places
   where a wrong walker gives a false `proved`. Part 2 is blocked until both
   have test cells.
2. **Low yield.** Ergonomics. Many driver arguments come from `def-shell`
   readers with no `post`. The prototype reports the count per outcome on the
   15 pairs of measurement 3 before the design settles.
3. **Output volume.** The driver has 357 functions without contracts. The
   `verify` line gives counts per caller; the full list belongs in the trust
   report.
4. **Two call-pre paths.** A body in the fragment uses the main query, where a
   failure is UNSAFE. A body that falls back uses the side query, where a
   failure is `unproved`. §5.3.5 must state this. It is intended: only a body
   VC can make a failed goal a counterexample.
5. **`--contracts=none` (new in Rev 3).** Scope. A `proved` site that used an
   unproved `post` has no runtime backing in this mode. The static tier already
   shows this through the `inherited-axiom` row. No change to the outcome is
   proposed; §5.3.4 states the mode.

## 9. Revision history

- **Rev 0 (2026-09-28).** Part 1 and Part 2; outcomes `proved`, `unproved`,
  `violated-if-reached` (closed-false only).
- **Rev 1 (2026-09-28).** Folds the professor review:
  - termination filter (T) on callee posts in Γ_s (H1);
  - `unreachable` checked first (H2);
  - must-fail widened to Γ_s ⊢ ¬pre and renamed `violated-if-evaluated` (H3);
  - one resolver shared with `PARTIAL-FNS-GRAPH-1` (H4);
  - headline counts (H5) and a trust tier per site (H6).

  Measured: the in-fragment call-pre path has the lazy false proof today. The
  row `LAZY-POST-CTX-1` was drafted. Finding D3 was opened.
- **Rev 2 (2026-09-28).** D3 is settled by EVAL-STRICT-1 (call-by-value).
  Consequences:
  - (T) is removed, and Part 2 depends on EVAL-STRICT-1 instead;
  - the outcome name returns to `violated-if-reached`;
  - `LAZY-POST-CTX-1` is not filed;
  - `PARTIAL-FNS-GRAPH-1` is no longer a prerequisite; it still shares the
    Part 1 resolver.
- **Rev 3 (2026-10-01).** Checked against the shipped `LLMLL.md` §4.7
  (v0.27.0). Part 1 shipped at v0.26.14. Changes:
  - the soundness argument cites one §4.7 clause for each kept fact;
  - Γ_s keeps the left operand of `and`, `or` and `=>`, a zero-parameter
    call's `post`, and the facts of a variable captured by a `fn`;
  - the Rev 2 fallback with (T) is removed, since no dependency remains;
  - the resolver is cited as `LLMLL.CallGraph`, the shipped module;
  - D1 and D2 are marked resolved; D4 records that `--contracts=none` removes
    the runtime `pre` check;
  - measurement 3 is re-measured (15 pairs in 4 programs); measurement 5 shows
    that a `post` is checked at run time;
  - the outcomes are stated not to enter `applyContractsMode`.
