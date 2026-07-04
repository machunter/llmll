# R5 — Differential Implementation Pressure (Multi-Agent Divergence as an Existential Spec-Adequacy Witness)

> **Version:** Rev 3 — empirical validation folded (Appendix C): **7/7 cases matched end-to-end through the real solver, no compiler bugs**; the sibling-call bound is confirmed as a **witness-suppression** false-negative channel, and the common-mode caveat is empirically confirmed (two false-negative channels, no false positives). Rev 2 folded the stage-3 feasibility read (Appendix B): the witness comes from stage-2 Ω-replay not a stage-3 model (no counterexample extraction), the stage-3 gate must also exclude **branch-skolem** bodies, and stage-3 is a deferred SAFE-direction prover. Rev 1 folded the professor review (Appendix A).
> **Status:** Proposed (Rev 3). **Stages 1–2 SHIPPED** — merged to `main` (`4336ae2`), released in **v0.14.7**, and **empirically validated** (7/7, Appendix C). **Stage 3 DEFERRED** (NO-GO as scoped; optional SAFE-direction prover, §3/§5).
> **Date:** 2026-07-04
> **Implements:** Active-Items row `R5 — Differential Implementation Pressure`; research-track source `docs/archive/research-track.md §5`.
> **Prerequisites (stages 1–2, met):** CDP machinery (`LLMLL.md §4.4.6`; `resolveSpecEntropy` for the gate); `evalExprStaticWith` (`Contracts.hs`) for Ω-replay; the session-lock relaxation (`Checkout.hs`). **Stage 3 (deferred):** a net-new product-program emission path in `FixpointEmit.hs` **and** direct-z3 `(get-model)` for the counterexample — neither exists today.
> **Reviewed:** Professor (Rev 0 → Rev 1, Appendix A); engineer feasibility read (stage 3, Appendix B).

---

## 1. Background and positioning

The diamond-lattice evidence axis (`LLMLL.md §4.4.1`) answers *"do we know this implementation satisfies the spec?"*. **Contract Discriminative Power (CDP, §4.4.6)** answers *"does the spec rule out enough wrong implementations?"* — scoring `DP_Ω(S)` over a closed observation set Ω using a *synthetic* candidate catalog.

**What R5 is.** Not a new CDP score with a different candidate basis — an **existential under-constraint witness generator**: N agents fill one hole; when ≥2 fills *both verify* yet *observably differ*, R5 emits a **boolean verdict + a distinguishing witness** (from stage-2 Ω-replay), not a Shannon DP number. Its output *feeds* CDP's typed-state machine; it does not fork that schema or overload `basis`. R5 is a re-derivation — **oracle-inverted differential testing** (McKeeman 1998) ≡ **specification-coverage** (Chockler–Kupferman–Vardi, FMSD 2006, already §4.4.6's citation) — novel only in candidate basis (real agent fills) + trust-report packaging.

## 2. Surface *(built)*

- `llmll checkout <file> <pointer> --multi N` (N≥2) — opens/joins a **divergence session**: N concurrent tokens on ONE pointer, each with an **isolated scratch copy** (byte-for-byte snapshot + own scratch lock); the shared source is never written. Session state lives in a disjoint `.llmll-diverge.json` sidecar, so the `CheckoutLock`/`CheckoutToken` schema is untouched. `promoteDivergenceWinner` is the only sanctioned write-back. For sensitivity (§7 R-2), fills should be **forced-diverse** (distinct models/prompts/temperature; "produce a semantically distinct valid fill").
- `llmll diverge-report <file> <session-id>` — classifies each member's fill (type-check + real solver) and emits the `divergence_witness` record.

## 3. Semantics — the three-stage funnel

1. **Status partition.** Bucket fills by verify outcome `{verified, refuted, type-error}`; only `verified` fills carry the signal.
2. **Observational bucketing (Ω-replay) — gated by `(spec-entropy …)`.** Run each verified fill over a shared probe set Ω (reusing `evalExprStaticWith`); bucket by output-vector.
   - **1 bucket ⟹ `no-divergence-observed`** — reported as exactly that, **not** "spec pins behavior" (correlated same-distribution agents make convergence a false-negative machine for spec-looseness, §7 R-2).
   - **≥2 buckets ⟹ `under-constraint-witness`** with the distinguishing probe input + per-bucket outputs — **unless** the function is `(spec-entropy :intentional)` (caches/schedulers/relational specs), in which case verdict = `suppressed-intentional`. The witness *is the Ω-replay divergence*; no solver is involved.
3. **Semantic tier — DEFERRED (see Appendix B).** An optional SAFE-direction equivalence *prover* over a narrow sub-fragment (below). It is **not** the witness path — the pipeline emits no counterexample model, so a stage-3 UNSAFE yields only a boolean "provably inequivalent," never the distinguishing input (which stage-2 already supplies). Its only value is the SAFE direction: dedup + off-Ω-blind-spot closure for that sub-fragment. Currently a marked stub (`semanticEquivalenceStub`).

**Output** — a standalone `divergence_witness` JSON record (referenced by pointer from the obligation report, never merged into `discriminative_axis`): `{session, hole, n_submitted, status_partition, verified_buckets, verdict, distinguishing_witness, spec_entropy_suppressed}`, `verdict ∈ {under-constraint-witness, no-divergence-observed, suppressed-intentional, insufficient-fills}`.

## 4. Edge cases and degenerate inputs

1. **Positive witness — the firing case (via Ω-replay, no solver).** `(def clamp-lo [x: int lo: int] (post (>= result lo)) ?hole)`; Fill A `(if (< x lo) lo x)`, Fill B `lo`. Both verify; **stage-2 Ω-replay** (probe set includes `x=5,lo=0`) finds A=5, B=0 → `under-constraint-witness`, distinguishing input `(x=5,lo=0)`. *(Rev 2: the witness is the observed Ω divergence — NOT a stage-3 "UNSAT-with-exact-model", which the pipeline cannot produce.)* Channel: observational (Ω-replay). Verified end-to-end in the build.
2. **Fragment-boundary case — why stage-3 gates hard (Rev 2: two skolem doors).** `(def use-h [x: int] (post (>= result 0)) ?hole)` with contracted `h` (weak post `≥0`); Fill A `(h x)`, Fill B `(let [y (h x)] y)` — identical. Assume-guarantee gives independent skolems `r_f≠r_g` → a naive equivalence VC reports spurious `≠`. **The same hazard recurs through a *second* door: opaque-sum match payloads** — `(match res ((ok v) v) …)` binds each arm payload as an independent `FQTrue` skolem (`FixpointEmit.hs:1782`), so two identical fills matching the same `res` get unrelated payload skolems → spurious `≠`. **Stage-3 must therefore be emitted only for bodies that are call-free AND branch-skolem-free** (`collectBranchBinders = []`), not merely "call-free `Σ_auto`". For such bodies stage-3 is not emitted → no spurious witness. Channel: the §5 gate.
3. **`:intentional` cache case — suppressed.** `cache-lookup` with `(spec-entropy :intentional)` and divergent verified fills → `suppressed-intentional`. Channel: the `resolveSpecEntropy` gate. Verified in the build.
4. **Quiet convergent case.** Tight post → 1 bucket → `no-divergence-observed`, no tightness claim (§3, §7 R-2).
5. **Degenerate — N=1 or all-refuted.** N=1 → `insufficient-fills`. All-refuted → spec is tight *or* agents are bad — orthogonal to intentional under-constraint; report the partition, no divergence verdict.
6. **Known coverage bound (Rev 2, from the build).** `diverge-report`'s per-fill classification uses isolated synthetic emission (same discipline as `--cdp`/`--weakness-check`): a fill that calls **user-defined sibling functions** classifies as `type-error` (only builtins + type-defs resolve in isolation), silently dropping it from the verified partition. Self-contained functions — the common case and the R5 witness — work fully. Documented in the code; a future lift is to resolve siblings in the isolated emission. Channel: stage-1 partition (bound, flagged).
7. **Off-Ω blind spot.** Two fills agree on every Ω-probe but differ off-Ω → observationally convergent; stage-3 (if built) closes this only for the call-free/branch-skolem-free sub-fragment — precisely not the complex bodies where off-Ω matters. Spec silent — bounded gap, same caveat as CDP §4.4.6.

## 5. Verification mapping

Stages 1–2 (shipped) introduce **no solver obligation** — Ω-replay is pure evaluation (`evalExprStaticWith`); the per-fill verified/refuted classification reuses the existing body-VC path. The one *potential* new obligation is stage-3's **pairwise equivalence** `f(x)=g(x) ∀x`:

- **Channel:** contract (relational).
- **Fragment (Rev 2 — corrected & narrowed):** decidable only for **call-free, branch-skolem-free, ≲64-path** `Σ_auto` bodies. Excluded: any `CallVC` (contracted `EApp` → independent skolems), any `BranchVC` skolem binder (opaque-sum match payloads → the second skolem door, edge case 2), recursion, non-`Σ_auto` components, non-admissible selectors. The path count is bounded because a naive product is `O(paths_f × paths_g)` (up to ~1.6×10⁷ constraints; `flattenBodyVC` materializes every path), so a `countPathsBounded 4097` guard must fall back to observational **before flattening** when `pf×pg > 4096` — forcing each body ≲64 paths.
- **Emission (Rev 2 — cost re-scoped):** the mechanics **compose existing machinery** (~150 LOC): the goal-shaped constraint idiom of the call-pre obligation (`FixpointEmit.hs:768-771`), shared param binding as the relational low-equality-of-inputs, and the already-global α-renamer (`bodyCounterRef`, disjoint across functions for free). Rev 1's "dominant build cost" framing was **overstated for mechanics**. The real blocker is that **the counterexample model does not exist**: `FQUnsafe` carries only failed constraint IDs (`DiagnosticFQ.hs:75`), not an SMT assignment — so stage-3 cannot emit the distinguishing input; producing it needs net-new direct-z3 `(get-model)`. This is why stage-3 is a SAFE-direction *prover* (dedup / off-Ω closure), not a witness generator. Cite `LLMLL.md §5.3.3 / §5.3.4`.

## 6. Affected surface *(stages 1–2 built; stage-3 pending)*

- **`compiler/src/LLMLL/DivergenceCheck.hs`** *(new, built)* — status partition, `resolveSpecEntropy`-gated Ω-bucketing (via `evalExprStaticWith`), verdicts, `divergence_witness` assembly; `semanticEquivalenceStub` for stage 3.
- **`compiler/src/LLMLL/Checkout.hs`** *(built)* — `checkoutHoleMulti` (session, isolated scratch, `.llmll-diverge.json` sidecar), `promoteDivergenceWinner`; exclusivity enforced both directions.
- **`compiler/app/Main.hs`** *(built)* — `checkout --multi N`, `diverge-report`, shared `assembleCheckoutContext`.
- **`compiler/llmll.cabal` / `package.yaml`** *(built)* — `LLMLL.DivergenceCheck` exposed.
- **Stage 3 (pending):** a product-program emitter + the call-free/branch-skolem-free/path gate in `FixpointEmit.hs`, and (for a real witness) direct-z3 model extraction.
- Docs (doc-lead, post-ship) — `LLMLL.md §4.4.6` R5 subsection; roadmap R5 → shipped-stages-1–2.

## 7. Risks and open questions

1. **Exclusive-lock relaxation vs. repair-loop safety.** *Soundness.* Handled: isolated scratch per token; shared tree written only by `promoteDivergenceWinner`; disjoint sidecar preserves the existing schema. **Resolved in the build.**
2. **Common-mode correlation — the convergent branch is unreliable.** *Verification-ergonomics.* The divergent branch is a sound witness (a divergence can't be faked); convergence under same-distribution agents is a false-negative machine (Eckhardt–Lee 1985; Littlewood–Miller 1989; Knight–Leveson 1986). Confine positive claims to the divergent branch; apply forced diversity; no "spec is tight" verdict from convergence. **Reflected in the `no-divergence-observed` wording.**
3. **Sibling-call classification bound.** *Coverage.* Isolated synthetic emission classifies sibling-calling fills as `type-error` (edge case 6). **Bite: bounded; self-contained functions unaffected; documented.**
4. **Stage-3 value is narrow and non-load-bearing.** *Scope.* SAFE direction = dedup + off-Ω closure over a small fragment (marginal vs stage-2); UNSAFE cannot emit the witness (no model). **Bite: deferred; do not gate stages 1–2 on it.**

## 8. Open questions for the professor — answered (Rev 1)

- **Q1** — Named: oracle-inverted differential testing (McKeeman 1998) ∘ specification-coverage (CKV 2006). Common-mode correction is structural (restrict positive claims to the divergent branch; forced diversity), not numeric.
- **Q2** — Real-agent basis is a **stronger under-constraint bug-finder**, a **weaker adequacy metric** (no closed denominator; coupling needs independence; one-sided). Basis for the §1 witness-generator reposition.

---

## Appendix A — Professor review (Rev 0), folded

Verdict: accept-with-revisions; two soundness-blocking findings. (1) Gate the equivalence obligation (contracted `EApp` gives independent skolems → spurious divergence); relabel `Σ_auto` not QF-LIA; the two-program path does not exist and must be built — `conserve.llmll:19-22` is single-body (verified). (2) Wire the `(spec-entropy :intentional)` gate; demote the convergent branch (Knight–Leveson). (3) Reposition as a witness generator, not a CDP-score extension. Minor: delete the "(intentional)" gloss on all-refuted; add a call-carrying fragment-boundary witness. All folded into Rev 1.

## Appendix B — Stage-3 feasibility read + build (Rev 2), folded

**Verdict: NO-GO for stage-3 as a witness generator; stages 1–2 suffice and are built.** Findings: (i) the witness comes from stage-2 Ω-replay, not stage-3 — `FQUnsafe` has no SMT model (`DiagnosticFQ.hs:75`), so stage-3 UNSAFE is only a boolean; (ii) a *second* skolem door — opaque-sum match payloads (`buildOpaqueSumBranch`, `FixpointEmit.hs:1782`) — reintroduces spurious `≠`, so the gate must also exclude `collectBranchBinders ≠ []`; (iii) emission mechanics compose existing IR (~150 LOC, cheap); (iv) `O(paths_f×paths_g)` blow-up needs a `pf×pg>4096` fall-back before flattening; (v) sound-firing fragment (call-free ∩ branch-skolem-free ∩ ≲64-path) excludes the complex bodies where off-Ω matters. If ever built: a SAFE-direction dedup/equivalence prover reporting `provably-equivalent` / `not-provably-equivalent-off-Ω (no witness)`; drop the "exact model" promise until direct-z3 `get-model` is funded. All folded into §3–§7. **Stages 1–2 built** in worktree `agent-ad8a0f2d2cab5dd48` (`stack test` 1035/0).

## Appendix C — Empirical validation (Rev 3), folded

`experiments/r5-validation/findings.md` — R5 stages 1–2 validated **end-to-end through the real CLI** (`checkout --multi` → per-token scratch fills → `diverge-report`), every fill's status decided by the real solver (`fixpoint` + z3), not hand-supplied. **7/7 cases matched the Rev 2 spec; no compiler bugs.**

- **Under-constraint is surfaced soundly.** Weak-contract cases (clamp `(>= result lo)` with `(if (< x lo) lo x)` vs `lo`) emit `under-constraint-witness` with a concrete replayable distinguishing input; a refuted fill is correctly partitioned out first. The divergent branch cannot be faked.
- **The common-mode caveat bites — two false-negative channels (no false positives):** (a) correlated same-distribution agents converge, making `no-divergence-observed` vacuous as tightness evidence; (b) **independently**, a sibling-calling fill that is *genuinely valid and genuinely divergent* (e.g. `(maxi x lo)`, which verifies standalone and equals the accepted clamp) is silently reclassified `type-error` and dropped **before** bucketing — so a real divergence is suppressed. This is the §4-6 coverage bound, now understood as a **witness-suppression** channel, not merely a dropped fill. **Future fix:** resolve user-defined siblings in the isolated synthetic emission so such fills are classified on their real merits (an R5 follow-on; routes to compiler-engineer).
- **Practical usage guidance (belongs in the eventual `LLMLL.md §4.4.6` R5 text):** trust `under-constraint-witness`; treat `no-divergence-observed` as **"no signal," never "spec is adequate."**
- **Doc correction owed to §4-1:** the emitted witness is the **first Ω-order disagreement** (`DivergenceCheck.hs:278`, probe order `:136`), so the actual output is `(x=0, lo=-1)`, not the illustrative `(x=5, lo=0)` — either note "first Ω disagreement" in §4-1 or reorder the int probe set. Cosmetic; no behavior change.
