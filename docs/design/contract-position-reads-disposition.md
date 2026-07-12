# Contract-Position Partial Reads (`bytes-get` / `map-get` in `pre`/`post`) — Disposition

> **Status:** Settled (language-team disposition, 2026-07-12). No spec change; one lint follow-on
> routed to compiler-engineer (CONTRACT-READ-LINT). Closes the finding routed by the LEVER-A1 and
> LEVER-A2 implementation passes.

## The question

A bytes/map read in a **contract** reflects as a total SMT `select` with no well-formedness
obligation (`FixpointEmit.exprToPred`, `:2066` bytes case; `mapPairTermsC` for maps) — unlike a
read in a **body**, which carries its index-in-bounds / key-presence precondition as a PROVE
call-site obligation (`bodyToPredM`, `:2486`). An out-of-bounds contract read is meaningful to the
solver (it denotes the encoding's junk value, per the recorded two-array cost — proposal §5) but
errors at the runtime assertion (§5.3.4 backstop). Dafny answers this with well-formedness proofs
for contract expressions; Liquid Haskell totality-checks reflected functions. What does LLMLL do?

## Soundness analysis (the deciding argument)

Neither verdict can become a silently false claim through a total-select contract read:

- **`verified` cannot be silently unsound.** For inputs where every contract read is in-bounds /
  present, solver and runtime semantics coincide (exact reflection). For inputs where a contract
  read is out-of-bounds, the generated program's contract assertion **fail-stops** before any value
  flows (`§5.3.4` runtime backstop; semantics-of-record is the generated program, `LLMLL.md §0.1`).
  No execution exists that returns a value violating a solver-proved post.
- **`refuted` cannot contradict a runtime-satisfiable contract.** A refutation counter-model that
  hinges on junk values corresponds to executions in which the contract check itself aborts — the
  contract is satisfied by no execution, so "the implementation does not satisfy the contract"
  remains operationally true. The §5.3.4 `:962` refuted-means-counterexample claim survives, with
  one degradation noted below.

This is why the F1/F3 treatment (whole-structure `=`, unconditionally out-of-fragment) does **not**
extend to reads: whole-structure `=` mis-encodes a *legitimate observational claim* and can
spuriously refute an observationally true post; an out-of-bounds contract read is an *ill-formed
contract* whose every divergence is fail-stop-visible.

## What degrades (the residual warts)

1. **`verified`-yet-always-crashing contracts are expressible.** `(post (= (bytes-get b 9)
   (bytes-get b 9)))` on `bytes[8]` verifies trivially and aborts on every execution. Not unsound;
   a spec-quality defect in the CDP/vacuity family.
2. **Refutation localization degrades.** A junk-dependent counter-model names an input whose
   witness at runtime is a contract-assertion crash, not a clean post-violation observation.

Both are author-error surfaces, and the author is typically an agent — which argues for a
machine-visible signal, not a proof burden.

## Disposition

**(a) Status quo, documented** — contract reads are total selects; this note is the record —
**plus (c) a scoped lint**, routed to compiler-engineer as **CONTRACT-READ-LINT (low)**: warn on
the statically decidable slice, a literal index against a literal `bytes[n]` bound
(`(bytes-get b 9)` where `b : bytes[8]`), and optionally a `map-get` whose enclosing clause
carries no `map-has` conjunct on the same map/key pair (heuristic tier, may ship later). W-series
warning, non-blocking, JSON-visible (the F-001 lesson: a guardrail invisible to `--json` is
invisible to agents).

**(b) Dafny-style well-formedness side-obligations are declined for now** — a new obligation
channel over contract expressions is real machinery (emission, classification, report surface,
trust interaction), and the soundness analysis shows it purchases claim-*quality*, not claim-
*correctness*. It is the principled end-state and the recorded lever: revisit when agent-authored
contract corpora show out-of-bounds contract reads at a frequency the lint's literal slice does not
catch.

## Verification mapping

No new obligations. The lint is syntactic (type channel, no solver); the declined option (b) would
have been QF-LIA per read (in-fragment) — recorded for the future row.
