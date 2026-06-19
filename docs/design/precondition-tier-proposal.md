# TRUST-PRE — Does a Precondition Floor a Function's Trust Tier?

> **Version:** Rev 3 (2026-06-19) — external-consumer question CLOSED (professor): B stands; obligation axis hardened to a first-class persisted `caller_obligations` field. Rev 2 — professor (soundness/design-reference) + engineer (scope) folded; converge on Position B, summary-only. Rev 1 — initial draft.
> **Date:** 2026-06-19
> **Working handle:** TRUST-PRE (a.k.a. DEFECT-1, surfaced by the compiler-engineer ground-truth pass, 2026-06-19). Roadmap tag to be assigned.
> **Origin:** the engineer ground-truth investigation into DEMO-COMP's composition behavior surfaced that the trust *summary* counts `teEffectiveLevel = evidenceMeet(csPre, csPost)`, and `csPre` is always `asserted`, so every precondition-bearing function floors to `asserted` regardless of its proven post.
> **Reviewed:** professor (soundness/design-reference adjudication) and compiler-engineer (true-scope read) consults **in flight** (2026-06-19); findings to be folded.
> **Status:** **SETTLED — external-consumer question CLOSED (professor, 2026-06-19). Design = Position B (summary-only tier) + a first-class persisted `caller_obligations` axis.** Ready for engineer implementation. The **demo re-script remains a separate, deferred decision** (no demo edits until then). See "Rev 3 — external-consumer question CLOSED" below.

---

## Consults folded — settled recommendation (Rev 2, READ FIRST)

Professor (soundness/design-reference) + engineer (scope) returned 2026-06-19 and **converge on Position B**, with one scope sharpening and one real cost the Rev-1 draft under-weighted.

**Settled recommendation: adopt B in its SUMMARY-ONLY form.** The trust-summary / per-function classifiers read the already-existing `teEffectivePostLevel` (`TrustReport.hs:591/596`, which already excludes `csPre`); **do NOT redefine the `teEffectiveLevel` field or the transitive diamond-meet** — that would change how a callee's `asserted` pre propagates into its *callers'* tiers and touch the `callee_tier` soundness lever (engineer risk 2; professor open-Q1). Scope: **~15 LOC + ~4 test flips/additions.** **No new soundness machinery** — the call-site precondition is already a PROVE-polarity solver constraint gated SAFE/UNSAFE (`FixpointEmit.hs:619-620`, `Main.hs:1486-1493`); no new `--strict-verified-core` conjunct is required (professor finding 4, engineer-confirmed).

**Why B (professor):** (1) `meet(csPre, csPost)` is a **category error** — `verify` proves the *implication* `{pre} body {post}` (one verified fact); the precondition is the antecedent, not a proposition the function claims. (2) **Spec-drift inversion:** `§5.3.4` only ever names *call-graph* meets; the pre/post meet lives only in `effectiveLevel` as an accident of `mkER` minting `csPre` at `DLAsserted` with no upgrade channel — **A diverges from the written spec, B aligns with it.** (3) Dafny / F\* / Liquid Haskell **all** report a `requires`-bearing function verified (precondition = caller's call-site obligation); A is an outlier in the systems LLMLL benchmarks against. (4) Direct VERIFY-RPT-1 §3.2 precedent (a distinct axis modelled beside the diamond, not inside the meet). (5) The project **already half-fixed this** — OBLIG-PBT-3's `tier_profile_post` exists to "sidestep the per-function meet that pins `tier_profile` to `DLAsserted` on a contracted function with an unproved pre" (`TrustReport.hs:91-96`).

**The real cost (engineer) — a product reversal, not a defect fix.** The public demo is built on A: the runbook says *"Do not 'fix' this in the compiler — it is the trust model working as specified"* (`DEMO-RUNBOOK.md:474`), and the demo strategy pins its thesis on the `verified: 2` vs `tier_profile_post.verified: 3` contrast ([[project_public_demo_strategy]]). Under B **both read 3** — that contrast collapses and the demo needs re-scripting. B therefore **overrides a deliberate, documented decision** — the user's call, not an engineering patch.

**The open tension — two consumer models (engineer risk 5; escalated to the professor, unanswered):**
- *In-verified-core consumer:* B is correct — the compiler checks the call site.
- *Read-report-then-call-from-unverified-glue consumer:* an agent that reads the trust report and invokes `withdraw` from hand-written glue *outside* the verified core — for it, A's `asserted` headline warns "you must establish the pre," and B's bare `verified` is an over-claim relative to *that* call site.

**Language-team position on the tension:** B's tier-correction is right (the function IS verified), and the external-consumer concern is real but is the *original category error in reverse* — answer it with an **obligation signal** (a prominent per-function "carries N un-discharged caller-precondition obligations" marker; the per-clause `pre:` display already partially provides it), **not** by flooring the *verification* tier. Surface both axes — verification-status AND caller-obligations — don't scalarize one into the other (the same CDP/`refuted` discipline). **Requirement on any B implementation:** the caller-obligation must stay prominently visible for the report-only consumer.

**Separate finding to route (engineer risk 3, spec-drift):** `§5.3.5:1006` documents `--strict-verified-core` conjunct (d) "asserted-tier dependency," but `Main.hs` enforces only (a)(b)(c). Pre-existing drift, masked today by A's floor; under B the team must not assume (d) backstops (it doesn't — the solver call-pre + conjunct (a) do). Resolve (implement (d) or strike it from the spec) → doc-lead/engineer.

**Professor's two language-team questions (carried):** (1) pin the invariant "drop `csPre` from the classifier, never ignore a weak `csPost`"; (2) decide whether per-function `tier_profile` survives or is subsumed by the `tier_profile_pre`/`_post` split it was already patched around.

### Rev 3 — external-consumer question CLOSED (professor, 2026-06-19)

The gating question — does B over-claim for the **read-report-then-call-from-unverified-glue** consumer? — is **resolved: B stands, with the obligation axis hardened.** Prior art is decisive and vindicates not-flooring: Dafny (→C# DLL), F\* (→OCaml/C extraction), Liquid Haskell (→plain-GHC) **all** report a `requires`-bearing function *verified* and carry the precondition as a separately-stated contract the boundary caller must honor; **none** invents a "conditionally-verified" tier. A `verified*` tier annotation is *worse* than an orthogonal marker (it still scalarizes AND touches `evidenceMeet` composition, reintroducing the propagation lever Rev-2 avoided).

**The one real divergence (a hardening, not a reversal):** the prior-art systems convey the precondition **out-of-band** (a `.spec`, an annotation, a header) to a **human** boundary-caller. LLMLL's consumer is a **machine reading a structured report**, so the contract must become an **in-band, structured, always-present, persisted field.** And there is a **safety-polarity asymmetry** vs. `refuted`: ignoring the `refuted` axis fails *safe*-ward (a stale tag over-warns); ignoring a caller-obligation axis fails *unsafe*-ward (you call `withdraw` with no balance check). So the obligation axis is **not optional polish — for the external consumer it carries the safety-critical information.**

**Blessed design (settled):**
1. **Headline tier stays `verified`** — do not floor, do not asterisk.
2. **New first-class `caller_obligations` axis** — per-function, carrying the **predicate** (not a count/name): `caller_obligations: [{ fn, requires: "balance ≥ amount" }]`. Source from `csPre` / `collectCallPreObligations` `FQPred` (`FixpointEmit.hs:1194`); do **NOT** reuse the caller-side `erCallPreFns` (wrong dual — it records who discharges *callees'* pres, not `F`'s own un-discharged pres).
3. **Emission discipline = opposite of `refuted`:** present whenever a `requires` exists, on **every** path (solver-less, sidecar-reload), and **PERSISTED to `.verified.json`** — a `requires` is a static contract property and cannot go stale like a solver verdict, so `refuted`'s deliberate non-persistence must be *inverted* here. *State this explicitly against the `refuted` precedent, not by analogy.*
4. **Headline self-scoping:** co-locate a boolean on the same entry — `"effective_level": "verified", "carries_caller_obligations": true` — so the cheapest single-field agent read already exposes the conditionality; the predicate list sits one field deeper. This discharges the safe-by-default responsibility *without* touching the tier.
5. **Transitive propagation rule (adopted):** an obligation is on `F`'s axis iff `F` **declares** it as `requires`, OR `F` calls a callee whose pre `F` neither discharges (SAFE call-pre VC) nor lifts to its own `requires` — the second disjunct reachable **only for non-strict-core `F`** (inside strict-core, the call-pre VC + conjunct (a) forbid an escaped obligation). **Implementation must verify the second disjunct is non-strict-core-only; if reachable in strict-core, that is a call-pre-VC soundness gap → route to engineer, not a reporting question.**
6. **One report, two axes — NOT a consumer-scoped report** (the CDP `discriminative_axis` precedent applied a third time).

**Scope note:** larger than the Rev-2 "~15 LOC summary-only" estimate — that covers the tier classifier; the `caller_obligations` axis is **net-new structured emission + persistence**, a `refuted_fns`-sized surface. Relationship to DEMO-COMP: distinct from DEMO-COMP's per-*call-site* `PreconditionObligation`/`consumed_guarantees` (this is the per-*function*-contract dual) but the same `FQPred` source — align them in implementation.

**Also folded:** the professor's two Rev-2 questions are adopted — (1) the classifier drops `csPre` but never ignores a weak `csPost`; (2) `tier_profile` is subsumed by `tier_profile_post` (the convergence is acknowledged). Plus the separate conjunct-(d) spec-drift finding (documented but unenforced) is routed to doc-lead/engineer.

---

## Restatement

A function that provably establishes its postcondition under its declared precondition — i.e. faithfully proves `pre ⟹ post` — is nonetheless reported `asserted` (not `verified`) in the trust **summary** whenever it *has* a precondition, because the whole-function effective level meets the always-`asserted` precondition tier against the post tier. The question: **is a precondition function-side evidence that should floor the function's tier (Position A), or a caller-side obligation that belongs off the function's evidence axis (Position B)?** This is a trust-model semantics question, not a verifier-soundness one, and it is entangled with the shipped withdraw-demo, which *relies on* Position A.

## Context located

1. `compiler/src/LLMLL/Syntax.hs:425-438` — `evidenceMeet`; `evidenceMeet(DLAsserted, _) = DLAsserted` (weakest-link).
2. `compiler/app/Main.hs:~1317` — `csPre` is set `DLAsserted` unconditionally ("no call-site VCs"; a precondition is a caller obligation).
3. `compiler/src/LLMLL/TrustReport.hs` — `teEffectiveLevel = evidenceMeet(csPre, csPost)`; the **per-entry** display shows `pre:`/`post:` separately (so `post: verified, effective: asserted` is visible), but the **summary counts** classify on the effective level.
4. `LLMLL.md §4.4.1` — the diamond lattice + weakest-link `evidenceMeet` (Position A's spec basis).
5. `LLMLL.md §5.3.4` (`refuted`, VERIFY-RPT-1 §3.2) — `refuted` is modeled as an **orthogonal marker beside the display level**, deliberately *not* a ⊥ lattice element, "to avoid conflating the evidence-strength axis with the polarity axis." This is the precedent Position B invokes.
6. `examples/withdraw-demo/` — `withdraw` (has `pre`) reports summary `asserted`; `double`/`maxi` (pre-free) report `verified`. The demo's **"proven vs. assumed" narrative is built on this floor.** Empirically confirmed 2026-06-19 (`verified: 2, asserted: 1`).
7. `examples/banking_ledger/banking.llmll.verified.json` — CLI-produced; pre-bearing composers carry `post: verified` per-entry but are summary-floored.
8. DEMO-COMP (`compositional-trust-closure-proposal.md`) — its "**obligation flows down**" beat (the caller must discharge a callee's precondition at the call site) is exactly where Position B relocates the "assumed-ness."

## Design proposal

### The two positions

**Position A — the precondition floors the function (status quo).** A function's guarantee holds only *if* its precondition holds, which nobody has proven at the function's own boundary; so its standalone trust is "proven-but-assumed" = `asserted`. Weakest-link `evidenceMeet` (§4.4.1) is the honest, conservative stance: don't award `verified` to something whose correctness rests on an unproven assumption. The withdraw-demo teaches exactly this contrast (pre-free → `verified`; pre-bearing → `asserted`).

**Position B — the precondition is off the function-side evidence axis (recommended).** A function faithfully proves the *implication* `pre ⟹ post`; that is a complete, `verified` fact about the function. Whether the precondition is *satisfiable in a given call context* is the **caller's** concern, discharged at the call site by the per-call-site precondition obligation LLMLL already emits. So the function's own tier should reflect `csPost`; the precondition should be tracked as an **orthogonal caller-obligation marker**, not folded into the tier via the meet — directly analogous to `refuted` (VERIFY-RPT-1 §3.2): a precondition is a different *axis* (a caller obligation), and meeting it against the evidence-strength axis is the same category error the `refuted`-as-orthogonal-marker decision already rejected.

### Recommendation: Position B

Three arguments, severity-ordered:

1. **Design-reference alignment.** No production verified language (Dafny `requires`, F\* refined arguments, Liquid Haskell refined input types) reports a function *un-verified* because it carries a precondition; the precondition becomes the **caller's** proof obligation at the call site, and the callee is "verified." Under Position A, LLMLL's `verified` tier is reachable *only* by precondition-free functions — a tiny, atypical class that makes the top tier nearly vacuous for real code. *(Routed to the professor for the precise per-system citation.)*
2. **Internal-precedent consistency.** The project already decided (VERIFY-RPT-1 §3.2) that a distinct *axis* (refutation polarity) must not be folded into the evidence-strength lattice. A caller-side obligation is likewise a distinct axis. Position B applies the same discipline; Position A is the un-applied case.
3. **It strengthens, not weakens, the honesty story.** Under B, `withdraw` is `verified` (it proved its implication) **and** every caller must discharge `balance ≥ amount` at the call site — surfaced as a call-site precondition obligation (DEMO-COMP's "obligation flows down" beat). That is a *more* precise account of "what is proven vs. what the caller must guarantee" than a blanket floor, and it co-locates the assumption with the party responsible for it.

### Spec change under B

- A function's effective/summary tier is its **`csPost`** evidence (the body-faithfulness of its postcondition under the assumed pre), **not** `meet(csPre, csPost)`.
- The precondition is retained as a per-function/per-call **caller-obligation** record (it already is, as the call-site `PreconditionObligation`), tracked orthogonally to the lattice.
- **Soundness hinge:** `--strict-verified-core` must enforce that *every call-site precondition obligation is discharged* (a caller invoking a pre-bearing callee without proving its pre must be caught at the call site). If that conjunct is not already present, B adds it. *(Routed to the engineer: is call-site enforcement already wired, or net-new?)*
- `§4.4.1` restated: `evidenceMeet` composes *evidence-strength* tiers (post-side, and transitive-callee posts); a precondition is **not** an evidence-strength input and does not enter the meet. `§5.3.4` restated: the caller-side discharge of a callee precondition is the call-site obligation, not a floor on the callee.

## Edge cases and degenerate inputs

1. **Pre-free function with verified post** (`double`, `maxi`). **Unchanged** under both A and B — reaches `verified`. **Channel: trust.** Cite §4.4.1.
2. **Pre-bearing function with verified post** (`withdraw`). **A:** summary `asserted`. **B:** summary `verified`, with its precondition exposed as a caller obligation. **Channel: trust.** This is the case that changes — and the one the demo currently narrates.
3. **Caller invokes a pre-bearing callee WITHOUT discharging the pre.** **B's soundness test.** The unsoundness must be caught at the **call-site precondition obligation** (UNSAFE → the *caller* floors / `--strict-verified-core` errors on the undischarged call-pre), not by flooring the callee. **Channel: contract (call-site).** Cite the `call-pre:` machinery; this is the load-bearing soundness edge.
4. **Caller discharges the callee's pre** (provides `balance ≥ amount`). The call-pre obligation is SAFE; the caller inherits the callee's `verified` post via the meet over posts. **Channel: trust + contract.** Under B this is a clean verified-composition (and it is DEMO-COMP's `withdraw-twice`-style beat, done with a *flat* working shape).
5. **`refuted` callee.** Orthogonal under both positions (refuted is already off-lattice); B does not change refutation handling. **Channel: trust.** Cite VERIFY-RPT-1 §3.2.

## Verification mapping

- **The tier reclassification itself** (B): **not an SMT obligation** — a lattice/display computation in `TrustReport.hs`. No fragment.
- **The call-site precondition obligation** (where B relocates the assumption): a **contract-channel QF-LIA VC**, *already emitted* (`collectCallPreObligations`); B does not add a new obligation, it relies on the existing one and (possibly) adds a `--strict-verified-core` conjunct that *reads* it. Cite `LLMLL.md §5.3.3`/`§5.3.5`.
- **No change to body-VC emission, the QF-LIA fragment, or solver time.** B is a trust-model/display change plus a strict-core gate read.

## Affected surface

- `compiler/src/LLMLL/TrustReport.hs` — effective-level / summary classification (exclude `csPre` from the function's own effective tier; the engineer's earlier sketch: classify on `teEffectivePostLevel`). **Scope beyond this is the engineer consult's question.**
- `compiler/app/Main.hs` / `--strict-verified-core` — possible new conjunct "(e) an undischarged call-site precondition obligation." (Engineer: already present or net-new?)
- **Existing example goldens** — `examples/withdraw-demo/` (`withdraw` → `verified`; summary `verified: 3`), `banking_ledger`, and any `Spec.hs` trust-summary assertions encoding the current floor. **Blast radius routed to the engineer.**
- `LLMLL.md §4.4.1` / `§5.3.4` — the restatement (doc-lead, post-decision).
- **DEMO-COMP** and the withdraw-demo runbook/DemoPost — narrative update (the "proven-but-assumed floor" beat becomes "verified + call-site obligation").

## Risks and open questions

1. **Changes the shipped demo's narrative** *(scope / pedagogy).* The withdraw-demo's "withdraw floors to asserted = proven-but-assumed" is its signature contrast. B replaces it with "withdraw verified + caller must discharge the pre." **Bite: re-narration, not a regression** — arguably an improvement (§Design arg 3), but it is a deliberate change to a shipped story; the user adjudicates.
2. **Soundness rests on complete call-site enforcement** *(soundness).* B is sound only if *every* undischarged callee precondition is caught at the call site (edge 3). If `--strict-verified-core` does not already enforce this, B must add it; otherwise B would mint `verified` for a function whose precondition a caller silently ignores. **Bite: blocks B until the enforcement is confirmed/added** — the engineer consult resolves this.
3. **Golden/test blast radius** *(spec-drift / churn).* Every test or sidecar encoding the current floor shifts. **Bite: mechanical but wide** — quantified by the engineer.
4. **Position A captures a real intuition** *(scope).* "Don't oversell a function whose safety rests on an assumption" is not wrong, just — under B — relocated to the call site rather than the function. If the team values the standalone-conservative reading, a *third* option is a distinct surface (e.g. report both `verified` and a "carries N caller obligations" badge) without flooring. **Bite: a possible compromise** — flag for the professor.

## Open questions for the professor *(routed 2026-06-19; folding pending)*

1. Do Dafny/F\*/LH report a `requires`-bearing function as *verified*, or floor its verification status? (The design-reference bar for A vs. B.)
2. Is treating a precondition as off the function-side evidence axis (the `refuted`-orthogonal-marker analogy) the principled treatment, or is a precondition categorically different from a refutation in a way that defeats the analogy?
3. Does (B) lose something real that (A) captures — i.e. is there a soundness or honesty property of the standalone floor worth preserving via a compromise (risk 4)?
