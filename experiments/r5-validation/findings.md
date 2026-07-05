# R5 — Differential Implementation Pressure: empirical validation (observational stages 1–2)

**Role:** Experiment Lead — empirical-descriptive.
**Date:** 2026-07-04
**Compiler:** `llmll 0.14.6` (main tree `/Users/burcsahinoglu/Documents/llmll`), pre-built.
**Solver:** `fixpoint` (`~/.local/bin/fixpoint`) + `z3` (`/opt/homebrew/bin/z3`) on PATH.
`liquid-fixpoint` is not installed; `classifyFillStatus` resolves `liquid-fixpoint` then
falls back to `fixpoint` (`app/Main.hs:1978-1980`), so the fallback binary carried every run.
**Spec under test:** `docs/design/differential-implementation-pressure-proposal.md` Rev 2 §3–§4.
**Code under test:** `compiler/src/LLMLL/DivergenceCheck.hs` (stages 1–2 pure core),
`compiler/src/LLMLL/Checkout.hs` (`checkoutHoleMulti`, `promoteDivergenceWinner`,
`.llmll-diverge.json` sidecar), `compiler/app/Main.hs` (`doDivergeReport`, `classifyFillStatus`).

## Goal

Two questions:

1. **Does R5 surface genuinely under-constrained contracts on realistic inputs** — i.e. when
   ≥2 fills *both verify against the real solver* yet *observably differ*, does the pipeline
   emit `under-constraint-witness` with a distinguishing input?
2. **Does the professor's chief caveat bite in practice** — do correlated same-distribution
   agents make convergence (`no-divergence-observed`) near-vacuous as evidence of spec tightness?

## Method

Every case is driven through the **real CLI end-to-end**, not the pure unit-test seam
(`test/Spec.hs:10387+` hand-supplies `FillStatus`; here the actual type-checker + solver classify
each fill, exercising `classifyFillStatus`):

1. Author a shared `.llmll` with a `?body` hole; `llmll build --emit` → `.ast.json`.
2. `llmll checkout <shared.ast.json> <pointer> --multi N` once per fill → each call joins the
   same divergence session and returns an **isolated scratch copy** path.
3. Build each fill variant (`.llmll` with the body inlined) → `.ast.json`, and copy it **over**
   the corresponding scratch (this is the fill an agent would have written into its scratch).
4. `llmll diverge-report <shared.ast.json> <session-id>` → the `divergence_witness` record.

Driver: `scratchpad/r5drive.sh` (session flow); sources under
`experiments/r5-validation/work/`. The shared file is never written by the session (isolation
invariant); each fill's verified/refuted/type-error status is decided by `fixpoint`.

## Validation matrix — results

| # | Case | Contract | Fills (all authored to type-check) | Expected verdict | Actual verdict | Match |
|---|------|----------|-----|------------------|--------------------|:---:|
| 1 | Weak clamp | `(post (>= result lo))` | A `(if (< x lo) lo x)`, B `lo` | `under-constraint-witness` | `under-constraint-witness` | yes |
| 2 | Tight dec | `(post (= result (- n 1)))` | A `(- n 1)`, B `(+ n -1)` | `no-divergence-observed` | `no-divergence-observed` | yes |
| 3 | Intentional clamp | `(post (>= result lo))` + `(spec-entropy :intentional)` | A `(if (< x lo) lo x)`, B `lo` | `suppressed-intentional` | `suppressed-intentional` | yes |
| 4 | N=1 | `(post (>= result lo))` | A `(if (< x lo) lo x)` only | `insufficient-fills` | `insufficient-fills` | yes |
| 5 | Sibling-call coverage bound | `(post (>= result lo))` | A `(maxi x lo)` (calls sibling), B `lo` | A → `type-error`, dropped | A `type-error`, B verified → `no-divergence-observed` | yes |
| 6 | Common-mode | `(post (>= result lo))` | A `(if (< x lo) lo x)`, A' identical | `no-divergence-observed` | `no-divergence-observed` | yes |
| 7 | Refuted partition | `(post (>= result lo))` | A clamp, B `lo`, R `x` (violates post) | R partitioned out; A,B → witness | verified `[A,B]`, refuted `[R]` → `under-constraint-witness` | yes |

**7/7 matched expectation.** All verified/refuted statuses were decided by the real solver,
not asserted.

### Case-by-case detail

**Case 1 — the firing case (positive branch).** Both fills verify against `fixpoint`
(confirmed also standalone: `verify clamp_fillA.llmll` / `clamp_fillB.llmll` → SAFE). The record:

```json
{ "verdict": "under-constraint-witness", "n_submitted": 2,
  "status_partition": { "verified": ["fillA","fillB"], "refuted": [], "type_error": [] },
  "distinguishing_witness": { "input": { "x": 0, "lo": -1 },
    "outputs": [ {"output":"0","representative":"fillA"},
                 {"output":"-1","representative":"fillB"} ] },
  "spec_entropy_suppressed": false }
```

The spec `(>= result lo)` says only "≥ lo"; it does not pin *which* value ≥ lo. R5 exhibits a
concrete input `(x=0, lo=-1)` where the clamp returns `0` and the constant-`lo` fill returns
`-1` — a real, replayable proof that the contract admits two intended behaviours. **This is the
core claim and it holds under the real solver.**

*Note on the witness input.* The design narrative (§4.1) uses `(x=5, lo=0)`; the pipeline
reports `(x=0, lo=-1)`. Both are genuine distinguishing points. `mkWitness`
(`DivergenceCheck.hs:278`) returns the **first** probe (in Ω order) where the buckets disagree;
Ω is the cartesian product with the first parameter varying slowest, so `(x=0, lo=-1)` (index 3
of 25) precedes `(x=5, lo=0)`. Not a defect — just not the doc's illustrative point.

**Case 2 — tight contract, quiet convergence.** An equality post forces every verified fill to
equal `n-1` on all inputs, so `(- n 1)` and `(+ n -1)` (both SAFE under the solver) share one
observational bucket → `no-divergence-observed`, `distinguishing_witness: null`. As designed,
this carries **no** tightness claim.

**Case 3 — intentional under-constraint suppressed.** Same divergent fills as case 1, but the
shared function carries `(spec-entropy :intentional)`. `resolveSpecEntropy` (via
`dcSpecEntropy`) flips the verdict to `suppressed-intentional` while **still witnessing** the
divergence (2 buckets, `distinguishing_witness.input = {x:0, lo:-1}` present,
`spec_entropy_suppressed: true`). The gate reads the shared file's contract, not the scratch's.

**Case 4 — degenerate N=1.** Opened a `--multi 2` session but joined only one member and placed
one fill → `n_submitted: 1` → `insufficient-fills`, no witness. (Nothing to compare.)

**Case 5 — the coverage bound (documented, confirmed, and sharper than "bounded").** Fill A is
`(maxi x lo)` — a call to a user-defined sibling `maxi` that computes `max`, i.e. **exactly the
verified clamp of case 1** (`maxi` verifies standalone → SAFE; `(if (< x lo) lo x)` = `max(x,lo)`
verified in case 1). Under `diverge-report`'s isolated synthetic emission
(`classifyFillStatus`, `Main.hs:2050`), only builtins + type-defs resolve — `maxi` is unbound —
so A classifies as **`type-error`** and is silently dropped from the verified partition. With
only B left, the verdict is `no-divergence-observed`.
**The semantics matter:** A is a *genuinely valid, genuinely divergent* implementation. Its
silent drop means R5 reports "no divergence" on a spec that is, in truth, under-constrained.
This is edge-case 6 / §7-R-3 in the proposal ("bite: bounded"), but empirically the bite is
**a second false-negative channel on the convergent branch**, independent of common-mode
correlation: *any* sibling-calling fill is invisible to the divergence signal.

**Case 6 — common-mode caveat, live.** Two same-distribution agents that emit the **identical**
clamp both verify and land in one bucket → `no-divergence-observed`, even though the spec is
demonstrably loose (case 1's constant-`lo` fill also verifies). Convergence here is **vacuous**
as evidence of tightness — precisely the professor's caveat.

**Case 7 — solver-driven partition (not just the unit-test seam).** Fill R = `x` violates
`(>= result lo)` (standalone: "body verification of 'clamp-lo' failed … does not satisfy
postcondition"). End-to-end, R is classified `refuted` by the solver and excluded from
bucketing; the two verified fills still produce the witness. This confirms stage-1 partition
works through the real solver, not only in `Spec.hs` where statuses are hand-supplied.

## Verdict: does R5 surface real under-constraint?

**Yes, on the divergent branch, and soundly.** When two fills both pass the real verifier and
differ on Ω, R5 emits a concrete, replayable distinguishing input (cases 1, 3, 7). A witnessed
divergence **cannot be manufactured**: both fills provably satisfy the contract, so the contract
provably admits ≥2 behaviours. The positive branch is exactly as strong as the design claims —
an existential under-constraint *proof*, not a heuristic.

The intentional-suppression gate (case 3), the N=1 guard (case 4), the equality-contract quiet
case (case 2), and the solver-driven refuted partition (case 7) all behave to spec.

## Does the common-mode caveat bite in practice? — Yes, and there are two channels.

The negative verdict (`no-divergence-observed`) is weak evidence of spec tightness, for two
empirically-confirmed reasons:

1. **Correlation (case 6).** Same-distribution agents converge on the same implementation, so
   convergence tells you about the agents, not the spec. The design correctly refuses to draw a
   tightness conclusion from it (the verdict wording is `no-divergence-observed`, never "spec is
   tight"). But this makes the negative branch near-informationless whenever fills are coupled.
2. **Sibling-call drop (case 5).** *Independently* of correlation, any valid-but-sibling-calling
   fill is reclassified `type-error` and removed before bucketing — so a real divergence can be
   silently deleted, again yielding a spurious `no-divergence-observed`.

Both are inherent limits of the observational increment, **not** false positives: neither can
make R5 *invent* an under-constraint witness on the divergent branch. The asymmetry the proposal
asserts (sound positive branch, unreliable negative branch) holds under test. Practically: treat
`under-constraint-witness` as actionable evidence; treat `no-divergence-observed` as "no signal,"
never as "spec is adequate."

## Bugs found

**None in the compiler.** Stages 1–2 match the Rev 2 spec on all 7 end-to-end cases, including
the solver-driven verified/refuted/type-error partition. The behaviours that look like gaps are
the *documented* bounds (sibling-call drop, common-mode convergence), and they behaved exactly as
documented.

Two non-defect notes for downstream roles:

- **(descriptive, doc-lead)** The reported distinguishing input can differ from the proposal's
  illustrative `(x=5, lo=0)` because `mkWitness` returns the first Ω-order disagreement
  (`(x=0, lo=-1)` here). If the doc's example is meant to be reproducible verbatim, either note
  "first Ω disagreement" or reorder `probeValuesFor TInt` (`DivergenceCheck.hs:136`). Purely
  cosmetic.
- **(descriptive, harness gotcha, not a compiler issue)** A `post` clause takes a *single*
  predicate; `(post p q)` is a parse error. Multi-conjunct postconditions must be written
  `(post (and p q))` (used for `maxi` in case 5). Worth a one-line mention in getting-started if
  not already present.

## Reproduction

Sources: `experiments/r5-validation/work/*.llmll`. Driver: `scratchpad/r5drive.sh`
(args: `CASE HOLE_SRC POINTER CAPACITY FILL_SRC...`). From `compiler/`, e.g. case 1:

```
../<scratchpad>/r5drive.sh case1_clamp \
  ../experiments/r5-validation/work/clamp_hole.llmll /statements/0/body 2 \
  ../experiments/r5-validation/work/clamp_fillA.llmll \
  ../experiments/r5-validation/work/clamp_fillB.llmll | jq .
```

Standalone fill checks: `stack exec llmll -- verify <fill>.llmll`.

## Addendum (2026-07-05) — Case 5 sibling-call suppression FIXED (v0.14.9)

The Case-5 / §Common-mode channel (2) false-negative — *any* sibling-calling fill silently
reclassified `type-error` and dropped before bucketing — is **fixed**. `classifyFillStatus`
(`app/Main.hs`) no longer classifies fills via isolated synthetic emission; it verifies each
fill in the **shared program's context** — the hole-fn's body is substituted by the fill,
sibling defs are kept and pinned to the trusted shared definitions (a fill cannot weaken a
helper it calls), and property `check`s are dropped. A `def-shell` fill then verifies its post
**modularly** through helper calls (each callee's contract discharges the call).

Re-validated end-to-end through the real solver (`liquid-fixpoint`):
- **Sibling-divergence, `def-shell` (the fix)** — `work/sib_shell_{hole,fillA,fillB}.llmll`
  (`clampS` post `(>= result lo)`, fill A `(maxi x lo)` calling sibling `maxi`, fill B `lo`):
  both now `verified` → `under-constraint-witness`, distinguishing input `{x:0, lo:-1}` (A→0,
  B→-1). **Pre-fix this was a spurious `no-divergence-observed`** (A dropped to `type_error`).
- **Real on-disk datapoint** (`runs/…-payments-core-realfill` transfer, claude-opus-4-8 +
  gpt-5.5, both call sibling `debit`, `def-shell`): both now `verified` → `no-divergence-observed`
  (correct — the two fills are byte-identical). **Pre-fix both dropped to `type_error`.**

**Residual (conservative, documented)** — `work/sib_{hole,fillA,fillB}.llmll` (the original
Case-5 sources: **strict `def clamp-sib`** calling `maxi`): post-fix, fill A `(maxi x lo)` still
classifies `type-error` and fill B `lo` verifies → `no-divergence-observed` (verdict unchanged
from the original run). The *mechanism* changed, though: `maxi` is now in scope (a sibling def),
but the strict-core admissibility gate rejects the call because this isolated pass doesn't run
the pipeline's leaf-verification pre-pass, so `maxi` isn't marked body-faithful — the error is
now "callee not body-faithful," not "callee unbound." Conservative — never a manufactured
witness; R5 hole-fns are `def-shell` by convention, so the modular path is the common one. The
negative branch's remaining weakness is thus **common-mode correlation alone**. Full suite green
(1064/0). See `differential-implementation-pressure-proposal.md` Rev 4.
