# ADMIT-VERIFIED — Strict-Core Admission of Independently-Verified Callees

> **Version:** Rev 2 (2026-06-19) — **BUILT (Option 2, user-chosen), green: 884 tests; admissibility wall FIXED.** Scope clarified (§0): this fixes *admission*; composition itself reaches `verified` (CLI-confirmed). An interim "does NOT unblock the demo (composed callers floor)" note was a misdiagnosis, now corrected. Prior: Rev 1 — initial draft, two consults folded (professor soundness + compiler-engineer feasibility, both 2026-06-18).
> **Date:** 2026-06-18
> **Working handle:** ADMIT-VERIFIED (roadmap tag to be assigned — the row is currently **unticketed**; see §7).
> **Implements / unblocks:** [`compositional-trust-closure-proposal.md`](compositional-trust-closure-proposal.md) (DEMO-COMP) — whose verified-`def`→`def` composition demo is unreachable until this lands. Closes a **designed-but-never-wired** piece of LT-INV (`core-shell-inversion-proposal.md:171` §3.5).
> **Prerequisites:** v0.9.0 assume-guarantee composition (`CallVC`, shipped); v0.11 LT-INV core/shell grammar + `checkCalleeAdmissibility`; `--strict-verified-core` transitive trust closure (`TrustReport.teEffectiveLevel`, shipped).
> **Reviewed:** professor consult (soundness — adjudicates the in-pass requirement a phase-ordering artifact; recommends option 1; literature: F\* `.fsti`/`.checked`, Dafny export+snapshots, LH imported-checked-specs, Jones/Abadi-Lamport rely-guarantee); compiler-engineer consult (feasibility — three-defect wiring root cause; `erVerifiedHash` schema delta; option-2 scoping). Folded directly per the REF-META appendix pattern; no standalone `-review.md`.
> **Status:** **Rev 2 — Option 2 BUILT and green (884 tests, all four soundness corrections binary-confirmed). Admissibility wall FIXED; composition reaches `verified` (CLI-confirmed).** See §0 for scope.

---

## 0. Build outcome + the wall this does NOT fix (Rev 2; READ FIRST)

Option 2 was implemented (user's choice over the recommended Option 1) and is **green: 884 tests, 0 failures**, all four mandatory soundness corrections landed and binary-confirmed (evidence-loaded-before-check / full-conjunction-not-bare-flag / hash-covers-(body,pre,post)+version-tag / fail-closed-on-absent-hash). **A strict-core `def` can now call a verified `def` with no `core-membership-violation` — the admissibility wall is genuinely fixed.**

**One sound design deviation:** the engineer *replaced* the legacy bare-`erBodyFaithful` admission leg with the full conjunction (rather than adding a fourth leg alongside it). Once persisted evidence enters `tcContractStatus`, the bare-flag leg admits hash-absent and overflow-tainted records — a hole — and there is no in-pass fresh-evidence consumer for it, so replacement is the only sound choice. Confirmed by tests (overflow-tainted / asserted-only / absent-hash callees all rejected).

**Scope clarification (integrity):** ADMIT-VERIFIED fixes *admission* — a strict-core `def` may now call a verified `def`. **Composition does reach `verified`** (CLI-confirmed 2026-06-19: `verified: 4, asserted: 0` for a leaf + three composers — see [`compositional-trust-closure-proposal.md`](compositional-trust-closure-proposal.md) §0). An interim note here claimed composition "still floors to `asserted` even with admission fixed"; that was the **same misdiagnosis** that briefly mislabelled DEMO-COMP — a cold-`--trust-report` render plus non-working fixture shapes, not a flooring. Corrected. ADMIT-VERIFIED's actual contribution stands: it unblocks the *strict-core `def`* composition path (cross-module, and same-file via the two-step warm seed); `def-shell` composers (the banking_ledger pattern) already reached `verified` without it. The soundness diagnosis below (wiring gap, not a soundness barrier; TCB unchanged) was vindicated by the green build.

---

## 1. Motivation

A strict-core `def` calling another user `def` is rejected at type-check with `core-membership-violation`, **even when the callee is independently verified body-faithful and its evidence is persisted** to `.verified.json`. Reproduced empirically (patched 0.12.1 binary, 2026-06-18): same-file `def`→`def` (×2 passes), and cross-module — verify a core module to a `.verified.json`, then import it — all rejected; only `def-shell` (non-body-faithful → never `verified`) composes. This makes the spec's own v0.9.0 assume-guarantee composition (`LLMLL.md §2` line 56: "sound when both functions are independently verified") **unreachable in strict core**, and blocks DEMO-COMP's entire thesis (demonstrate *verified* compositional trust closure).

**Both consults converge: this is a wiring gap, not a soundness requirement.** The in-pass `erBodyFaithful` requirement in `checkCalleeAdmissibility` (`TypeCheck.hs:347`) conflates (a) *full transitive body-faithfulness* — re-establish the callee's body VC inside the caller's pass — with (b) *modular assume-guarantee* — trust the callee's separately-verified contract; the caller's body is body-faithful **modulo** `g`'s independently-discharged `(pre_g ⟹ post_g)`. The spec blesses (b) at line 56; the check enforces (a), which the type-check phase **cannot** satisfy for any user callee (verification runs *after* type-check). It is categorically blind, not merely conservative.

**This was designed.** The LT-INV proposal (`core-shell-inversion-proposal.md:171` §3.5) explicitly chose the persisted-sidecar route over a two-pass type-check, naming "populate `erBodyFaithful` from prior `.verified.json` sidecars" as the mechanism and accepting "cold-cache builds may require a verify-then-build sequence." **That population was never wired**, and the row is unticketed (`roadmap:262` shows the shipped admission as exactly `body-faithful | trustedPrelude | builtinEnv`). DEMO-COMP is the first feature to exercise a `def`→`def` edge.

## 2. The wiring gap — three compounding defects (engineer)

1. **Entry-file evidence loaded after the gate.** `doVerify` (`Main.hs:1098-1120`) runs the strict-core type-check gate (`:1100`) and `exitFailure`s *before* `loadVerified fp` (`:1115`+). The entry file's own sidecar never feeds `tcContractStatus`.
2. **No same-file incremental population.** `tcContractStatus` is seeded only from imported modules (`TypeCheck.hs:491-514`); the entry file starts `Map.empty`. A leaf's evidence is never produced-then-consumed within one invocation (no SCC/topological pass).
3. **Cross-module key duality.** Imported evidence is merged into `meContractStatus` under **qualified** keys (`prefix<>name`, `:511-513`), but `SOpen` injects callees under **bare** keys into `tcEnv` *only* (`:830`), never `tcContractStatus`. The bare-name admissibility lookup (`:1032`) always misses.

**Spec-drift finding (route to language-team/doc-lead):** LT-INV §3.5 / Risk #2 (`:393`) assumed `erBodyFaithful` is "likely already there per MOD-1's `meContracts`." The engineer refuted this: `meContracts :: Map Name ([(Name,Type)], Contract, Maybe Type)` (`Syntax.hs:751`) carries contract *expressions* only — no `EvidenceRecord`. Body-faithful evidence lives in `meContractStatus` (qualified) + the entry sidecar (unloaded pre-type-check). The LT-INV spec NOTE must be rewritten against the real evidence path.

## 3. Design — two options; recommend Option 1

### Option 1 (recommended — professor-preferred, phase-clean)

**Relax `checkCalleeAdmissibility` to admit any callee bearing an in-scope *contract* (a type-check-available fact), and defer the verified-composition verdict to the existing `--strict-verified-core` transitive trust closure.** Strict-core type-check admission becomes *structural* (contract present ⇒ admit); the strict-core *guarantee* moves entirely to verify-time, where it already lives: `--strict-verified-core` conjunct (d) ("an `asserted`-tier dependency") plus the tier meet (`teEffectiveLevel`, `LLMLL.md §5.3.5:1006`) already refuse `verified` to any caller of an unverified callee, transitively by assume-guarantee. This is the F\*/Dafny architecture ("verify against the interface; the proof obligation lives in the verifier"), respects the REF-META-4 phase distinction (no verification verdict in the type checker), and **reuses** the transitive-staleness machinery rather than re-implementing it.

For **same-file** composition — the demo's case — this is near-trivial: relax the gate, and the existing single-pass verifier produces fresh body-faithful evidence per function and the shipped `CallVC` assume-guarantee handles the edge. **No schema field, no staleness guard** (everything verifies fresh in one pass; staleness only arises for persisted cross-module evidence). *Validation gate for implementation:* confirm that with the gate relaxed, same-file `quadruple`/`double` verifies and `quadruple` reaches `verified` via `CallVC` (DEMO-COMP appendix states `CallVC` ships in full).

**Cost:** weakens *check-time* strict-core enforcement to *verify-time*. `llmll check --strict` would no longer flag a `def`→unverified-`def` call; `llmll verify --strict-verified-core` still hard-errors. The professor adjudicates this a *phase correction*, not a regression: a "is the callee proven?" question belongs to the verifier, not the type checker, and the verify-time closure already enforces it soundly.

### Option 2 (the cross-module staleness increment — defer as a follow-on)

Add the persisted-evidence admission leg *inside* `checkCalleeAdmissibility`, with the wiring to feed `tcContractStatus`: load the callee's persisted `.verified.json` before the check (fixing defects 1–3), and admit on the **full conjunction** — never bare `erBodyFaithful`. This requires net-new schema: `erVerifiedHash :: Maybe Text` on `EvidenceRecord` (`Syntax.hs:378`, which today has **no** hash field — `erSource` is `:source` provenance, not a hash), stamped by the verifier over `canonicalPropBodyHash` (`PBT.hs:558`) and validated on load adjacent to `downgradeStaleSidecar` (`TrustReport.hs:307`). This is the cross-module case (the verifier trusts a persisted sidecar verdict without re-verifying). **Recommend deferring** to a follow-on increment; Option 1 unblocks the demo and same-file/warm composition without it.

### Spec restatement (both consults, mandatory regardless of option)

Restate the LT-INV core-membership invariant as **modular body-faithfulness**: *a strict-core `def` `f` is body-faithful **modulo** the separately-verified contracts of its callees, each itself (recursively) body-faithful-modulo-its-callees, grounded at trusted-prelude/builtins.* The current implicit "transitively body-faithful" phrasing is what produced the (a)-vs-(b) confusion and the over-conservative gate. This is a doc-lead edit to the LT-INV text + `LLMLL.md §5.3.4`.

## 4. Edge cases and degenerate inputs

1. **Recursive / SCC callee.** A function in a call cycle is contract-only (body VC excluded by design, `FixpointEmit.hs:870-873`) ⇒ degraded tier ⇒ under Option 1 it is admitted structurally but the closure floors the caller's tier (cannot reach `verified`); under Option 2 it correctly fails the body-faithful leg. **Channel: trust.** Either way: **fail closed** — no silent `verified`. Cite `LLMLL.md §5.3.4` SCC exclusion; DEMO-COMP §5 edge 3.
2. **Cold same-file forward composition (no prior verify).** Under Option 1 the single verify pass produces the leaf's evidence before the caller's tier is computed in the closure — works. Under Option 2's "load entry sidecar before type-check," a first-ever verify still rejects until a second pass (the LT-INV §3.5 "verify-then-build" cost). **Channel: type / trust.** Option 1 avoids this; it is a reason to prefer Option 1.
3. **Absent persisted hash (Option 2 only).** A pre-change sidecar with no `verified_hash` must be treated as **not admissible** (fail-closed), never as unguarded admission. **Channel: trust (soundness-critical).** Cite engineer Risk #1; the single load-bearing correctness detail of Option 2.
4. **Contract drift with stable body (Option 2 only).** Callee's `pre`/`post` changed while its body text did not ⇒ a body-only hash silently admits stale evidence. **Channel: trust (soundness hole).** Mitigation: hash canonical **(body, pre, post)** + semantics-version tag (professor; resolves the engineer's open question). Cite `PBT.hs:558` canonicalization precedent.
5. **Overflow-tainted / escape-discharged callee evidence.** A callee SAFE only via `?proof-required` escape or LT-PPR runtime fallback, or carrying `erOverflowTainted`, must **not** be admitted as `verified`-grade. Require `isVerifiedLevel ∧ erBodyFaithful ∧ ¬erOverflowTainted ∧ fragment-pure` — the same conjunction `--strict-verified-core` already enforces. **Channel: trust.** This is automatic under Option 1 (the closure already applies these conjuncts); explicit under Option 2.

## 5. Verification mapping

- **Admission is not an SMT obligation** — it is a lookup (Option 2) or a structural contract-presence check (Option 1). **No new `.fq` constraints, no new obligations, 0ms solver delta.**
- **The transitive verified-composition guarantee** is the **existing** `--strict-verified-core` closure: conjunct (d) asserted-dependency + the tier meet, transitive by assume-guarantee (`LLMLL.md §5.3.4`/`§5.3.5:1006`). **Not new machinery.**
- **Staleness guard (Option 2)** — a SHA-256 over canonical `Expr`, microseconds/function, matching the PBT-witness hashing already run on every `--trust-report`. **Not an SMT obligation.**
- **Fragment: QF-LIA, unchanged.** Admitted callees are by construction body-faithful QF-LIA functions; no escape to nonlinear or Lean. Cite `LLMLL.md §5.3.3`.

**TCB impact: none.** The callee was verified by the same verifier, same fragment, same VC semantics; reading its verdict trusts exactly the computation an in-pass re-walk would. The compiler *already* trusts a persisted `erBodyFaithful` flag for a stronger decision — contract-stripping the runtime post-assertion (`Contracts.hs:208-223`). This is the Liquid-Haskell *imported-checked-spec* case, not the `assume` case (DEMO-COMP §3.1's `consumed_guarantees`-vs-`assumptions` split).

## 6. Affected surface

**Option 1 (recommended, minimal):**
- `compiler/src/LLMLL/TypeCheck.hs:347-361` — relax `checkCalleeAdmissibility`: admit a callee with an in-scope contract (pre or post present in `tcContractStatus`/`meContracts`), in addition to `trustedPrelude`/`builtinEnv`. Strict-core verdict deferred to the closure.
- `compiler/app/Main.hs` — confirm `--strict-verified-core` conjunct (d) + meet already gate caller tiers transitively (shipped; no change expected — validate).
- Tests: same-file + cross-module `def`→`def` admitted at type-check, caller `verified` iff callee verified, floored otherwise; recursion/SCC floored (fail-closed).

**Option 2 (deferred cross-module increment):**
- `Syntax.hs:378` add `erVerifiedHash :: Maybe Text` (additive; ~8–10 module recompile fan-out; positional `EvidenceRecord` construction sites must add the field — GHC-enforced).
- `VerifiedCache.hs:72-119` emit/parse `verified_hash` when-present (back-compat, fail-closed on absent).
- `Main.hs:1318` stamp `erVerifiedHash` at `saveVerified` over `canonicalPropBodyHash` of the def body (+ contract per §4.4).
- `TypeCheck.hs:812-832` (`SOpen`) inject bare-keyed `ContractStatus` into `tcContractStatus`, mirroring the `tcEnv` injection.
- new staleness function adjacent to `TrustReport.hs:307` `downgradeStaleSidecar`.

**Spec / roadmap (doc-lead, post-ship):**
- `LLMLL.md §5.3.4`/§5.3.5 — restate the invariant as *modular* body-faithfulness; rewrite the LT-INV §3.5/Risk-#2 evidence-path NOTE against `meContractStatus`+sidecar (not `meContracts`).
- `docs/compiler-team-roadmap.md` — **new row** (this work is unticketed): "strict-core persisted-evidence `def`→`def` admission."

## 7. Risks and open questions

1. **Option 1 weakens check-time strict-core enforcement** *(scope / phase).* `llmll check --strict` no longer flags `def`→unverified-`def`; verify-time `--strict-verified-core` still does. **Bite: behavioral, intentional** — the professor adjudicates it a phase correction. Name it explicitly in the spec restatement.
2. **Option 2 absent-hash fail-open** *(soundness).* If absent `verified_hash` is admitted rather than rejected, unguarded stale evidence is trusted. **Bite: blocks Option 2 soundness if mis-implemented** — fail-closed default, tested.
3. **LT-INV §3.5 spec-drift** *(spec-drift).* The shipped spec/proposal text describes an evidence path (`meContracts` carries `erBodyFaithful`) that does not exist. **Bite: documentation** — route to doc-lead with the corrected path.
4. **DEMO-COMP Rev 2 still needs Rev 3** *(coordination).* Independently of this wall, Rev 2 §3.3/§5/§6/§10 over-claim `withdraw-twice → 2` call-site obligations (nested-contracted-call fallback, build-agent finding #4). Rev 3 must correct that and re-base the fixture on flat composition once ADMIT-VERIFIED lands.

**Open question for the user (the one decision):** Option 1 (relax the gate; defer to the verify-time closure — phase-clean, minimal, unblocks the demo) vs. Option 2 (persisted-evidence leg in the type-checker now — larger, adds the cross-module staleness machinery up front). Recommendation: **ship Option 1 to unblock DEMO-COMP; ticket Option 2 as the cross-module follow-on.** Both consults' technical open questions are mutually resolved (hash scope = canonical (body, pre, post) + version tag; transitive staleness → existing closure).
