---
name: shell-call-pre-1-proposal
title: "SHELL-CALL-PRE-1: a call from a body that falls back proves nothing about the callee's pre, and nothing says so"
status: "Rev 2, READY FOR ADJUDICATION 2026-09-28. Rev 0 reviewed by professor (shell-call-pre-1-review.md); Rev 1 folded the review; Rev 2 removes the termination filter (T) because EVAL-STRICT-1 (eval-strict-1-proposal.md) makes it unnecessary. Part 1 is code-track and ready for the engineer now. Part 2 waits on EVAL-STRICT-1 shipping and on a prototype that counts outcomes per tool. Roadmap row SHELL-CALL-PRE-1 (G1) carries DECIDE; this proposal answers it: both shapes, A producing evidence and B carrying it."
date: 2026-09-28
author: language-team
consumers: [compiler-engineer, documentation-lead, professor, user]
reviews: "shell-call-pre-1-review.md (professor, Rev 0)"
related: "eval-strict-1-proposal.md (depends on it for Part 2); roadmap rows PARTIAL-FNS-GRAPH-1, DEF-ADMIT-XMOD-1"
---

# SHELL-CALL-PRE-1: call-site preconditions in bodies that fall back

**One line.** Call-site `pre` obligations come only from a built body VC. A
caller whose body falls back gets none, `verify` prints nothing, and the trust
report's disclosure is empty for every callee reached through `open`.

## 1. Summary

The roadmap row asked for a choice: (A) prove the callee's `pre` at the call
site, or (B) disclose that nothing proved it. This proposal does both, in two
parts.

| Part | What it does | Depends on | Changes a verdict? |
|---|---|---|---|
| 1 | Repairs the TRUST-PRE disclosure for opened imports (finding D2) and adds one `verify` line | nothing | no |
| 2 | Emits call-site `pre` obligations in bodies that fall back, in a side query with four outcomes | EVAL-STRICT-1 shipped; a prototype count | no (report and warning only) |

## 2. Measurements (v0.26.13)

1. **Same-module probe.** A `def tally` has `(pre (>= seen 0))`. A
   `def-shell caller` calls `(tally (- 0 5))`. `verify` prints `SAFE` and exits
   0. The trust report gives `caller` a `caller_obligations` row
   `(>= seen 0)`. Same-module disclosure works. The row states the predicate
   and not whether this call meets it.
2. **Copy of `tools/doc-path-lint/pathlint.llmll`.** `scan-file` calls `tally`
   and `pl-status` calls `status-of`, both through `open adjudicate`. Both
   callers show `carries_caller_obligations: false`. The dependency row names
   the callee `tally`, and `declaredReqs` is keyed `adjudicate.tally`. The
   lookup in `markCallerObligations` (`compiler/src/LLMLL/TrustReport.hs`)
   misses. This is finding D2.
3. **Call-site population.** A scan of `tools/` finds about 21 call sites of
   core functions that declare a `pre`: 2 in `pathlint`, the rest in the
   driver. An earlier estimate recorded 17. The prototype must count again.
4. **Why a site cannot be proved from nothing.** In `pathlint`,
   `(tally (found-of acc2))` passes the result of `found-of`, a `def-shell`
   JSON read with no `post`. The argument is unconstrained. Non-negative
   length facts (`nonNegMeasures`) do reach `list-length` and `string-length`
   arguments.

## 3. Findings outside the row

- **D1 (spec drift).** `LLMLL.md` §3.4.4 says "No call-pre obligation is
  silently dropped." Measurement 1 shows one dropped with no report. Part 2
  makes the sentence true; until then doc-lead must qualify it.
- **D2 (code defect).** Measurement 2. The bare-versus-qualified name family
  of `PARTIAL-FNS-GRAPH-1`.
- **D3 (spec gap).** `LLMLL.md` states no evaluation strategy. Opened as
  EVAL-STRICT-1.

## 4. Design

### 4.1 Part 1: repair the disclosure

- `markCallerObligations` resolves callee names through
  `LLMLL.ProgramGraph.qualifiedCallGraph`, the resolver that
  `PARTIAL-FNS-GRAPH-1` names. One resolver serves both rows.
- When a caller whose body falls back calls a `pre`-bearing callee, `verify`
  prints `call-pre unchecked: <caller> -> <callee>, ...` beside the existing
  `call-pre obligations:` line. The exit status does not change.

### 4.2 Part 2: call-site obligations in a body that falls back

For each call site *s* of a callee *g* with `pre_g` in `Σ_auto`, in a caller
*f* whose body VC was not built:

```
Γ_s  ⊢  pre_g[a₁/x₁ … aₙ/xₙ]
```

Γ_s holds only facts that translate faithfully. Every other fact is dropped:

- `pre_f`, when it translates (the RESP-FACT-1 `preUsable` rule);
- each enclosing `if` guard that `exprToPred` translates, with the polarity of
  its arm;
- each enclosing `let` equality whose right-hand side translates, resolved by
  lexical scope (the F-NIW-4b `inScopeLbs` precedent);
- for an argument that is a call `h(...)`, a fresh result variable with `h`'s
  `post` assumed (the F-NIW-4 `ctxCalls` precedent);
- the non-negative length facts (`nonNegMeasures`).

**Soundness argument.** Under EVAL-STRICT-1, each kept fact holds in every
evaluation that reaches *s*: a `let` binding and an argument call are values
once execution passes them, so the callee's `post` holds for them (partial
correctness). Dropping a fact makes the goal harder, never easier. So a proved
site is a valid proof, relative to the `post`s it used, which the report names.
An argument that does not translate yields no constraint and the outcome
`unproved`, never a silent drop.

**Why Part 2 waits on EVAL-STRICT-1.** Under today's lazy code generation, a
callee's `post` is a fact only if the callee terminates, because an argument
that is never evaluated may belong to a call that never returns. Rev 1 handled
this with a termination filter (T) on Γ_s, which in turn depended on
`PARTIAL-FNS-GRAPH-1`. EVAL-STRICT-1 removes the cause. If Part 2 must ship
before EVAL-STRICT-1, it ships with (T): Γ_s assumes a callee's `post` only
when the callee is not in `termination_assumed_fns`.

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
¬pre means every evaluation that reaches *s* violates the `pre`.

**Headline.** When not zero, the `verify` headline adds the counts, for example
`SAFE (...); call sites: 1 violated-if-reached, 2 unreachable`. The exit status
does not change. The runtime `pre` check stays at every site, including proved
ones, because code generation must not depend on an advisory query.

**Trust report.** Each site appears as a `precondition-obligation` with its
§11.2 sited id and its outcome. A proved site lists every non-body-faithful
`post` it relied on, as an `inherited-axiom` row. A callee drops off a caller's
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
   goal, `violated-if-reached`. Today: `SAFE`, nothing printed (measurement 1).
4. **Argument from a helper with no post.** `(tally (found-of acc2))`:
   `unproved (context)`. If `found-of` gains `(post (>= result 0))`, the site is
   `proved` relative to that asserted `post`, which the report names. This
   moves the trust to `found-of`; it does not remove it. Channel: trust.
5. **Guarded call.** `(if (>= x 0) (tally x) 0)`: the guard is kept and the site
   is `proved`. With `(regex-match ...)` as the guard, it is dropped and the site
   is `unproved (context)`: a false alarm by design, never a refutation.
6. **Shadowing (soundness hazard).**
   `(let [(x (- 0 1))] (let [(x (found-of r))] (tally x)))`: the inner `x` must
   not take the outer equality. A wrong walker gives a false result in either
   direction. A test cell is owed.
7. **Call inside a lambda.** In `(list-filter rows (fn [r: Json] ...))`, an
   argument bound by the lambda has no facts: `unproved
   (argument-outside-fragment)`.
8. **Opened versus qualified callee.** `scan-file` calls `tally` through
   `open`. Today the disclosure is empty (D2). After Part 1 it lists the site.
   This is Part 1's positive witness.
9. **Callee `pre` outside `Σ_auto`.** No constraint:
   `unproved (pre-outside-fragment)`.

## 6. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Γ_s ⊢ false; Γ_s ⊢ pre_g[args]; Γ_s ⊢ ¬pre_g[args] | contract (`precondition-obligation`), outcome on the trust channel | QF-LIA whenever emitted (§5.3.3); the fragment is closed under negation |

Nothing is nonlinear, and nothing goes to Lean.

## 7. Affected surface

- `compiler/src/LLMLL/TrustReport.hs`: Part 1 name resolution; the transitive
  rule in `markCallerObligations` becomes site-aware.
- `compiler/src/LLMLL/FixpointEmit.hs`: a context walker for bodies that fall
  back, emitting into a second constraint set. `collectCallPreObligations` is
  unchanged.
- `compiler/app/Main.hs`: the side query; the `call-pre unchecked` line; the
  headline counts.
- `compiler/src/LLMLL/ObligationAssembly.hs`: sited `precondition-obligation`
  rows with outcomes.
- `LLMLL.md` §3.4.4 (D1), §5.3.5 (the two call-pre paths), §11.2 (outcome
  values); `tools/VERIFICATION.md` "What is not proved".

## 8. Risks

1. **Shadowing in the context walker.** Soundness. Blocks Part 2 until edge
   case 6 has a test cell.
2. **Low yield.** Ergonomics. Most driver arguments come from `def-shell`
   readers with no `post`, so many sites may land at `unproved (context)`. The
   prototype reports the count per outcome on `pathlint` and the driver's
   `shape.llmll` call sites before the design settles.
3. **Output volume.** The driver has 357 functions without contracts. The
   `verify` line gives counts per caller; the full list belongs in the trust
   report.
4. **Two call-pre paths.** A body in the fragment uses the main query, where a
   failure is UNSAFE. A body that falls back uses the side query, where a
   failure is `unproved`. §5.3.5 must state this. It is intended: only a body
   VC can make a failed goal a counterexample.

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
