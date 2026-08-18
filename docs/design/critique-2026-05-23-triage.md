# External Critique Triage — 2026-05-23

> **Status:** Record of adjudicated triage. Lives here as the durable artifact of the four-turn convergence; downstream skills (compiler-engineer, doc-lead, experiment-lead) consume the routing table at the end.
> **Companion archives:** [`verification-debate.md`](verification-debate.md) (April 2026 formal-methods critique, archived after Path A adjudication); [`oblig-pbt-3-review.md`](../archive/professor-reviews/oblig-pbt-3-review.md) (professor review of OBLIG-PBT-3).

This document captures the adjudication of a fourteen-section external technical critique of LLMLL received 2026-05-23, after four turns of internal review: language-team triage → professor adjudication on three open questions → language-team revision → amended external critic response with retractions, ratifications, and three routed decisions. The remaining work is execution (compiler-engineer, doc-lead, experiment-lead); no further design-team adjudication is required for any of the seventeen tagged items below.

---

## 1. The four-turn convergence record

| # | Critique item | Original critic | LT triage | Professor | Amended critic | Status |
|---|---|---|---|---|---|---|
| 1 | What gets right | accept | accept | n/a | n/a | settled |
| 2 | Path B foundations demand | foundations-first push | misread of Path A; cite [`verification-debate.md`](verification-debate.md) | n/a | **retracted** | settled — narrow to integer faithfulness |
| 3 | Spec drift (LLMLL.md/README/schema) | P0 release blocker | accept; doc-lead + CI gate | n/a | accept + concrete CI gate criteria | **DRIFT-1** (mostly shipped, §3 INT-1-gated), **DRIFT-CI-1** (content-satisfied, workflow pending) |
| 4 | Strict-verified-core admissibility | enumerate rules | accept; codify rule set | n/a | n/a | **STRICT-CORE-1** |
| 5 | Refinement metatheory of record | five missing pieces | route to professor | all five promotable; 2.4→2.1→2.2→2.5→2.3 | narrower framing: checking-mode rule + explicit non-goals | **REF-META-1..5** (framing flipped — see §3.1) |
| 6 | `?proof-required` predicate carrier | richer design | already tracked, deferred | n/a | accept deferral | settled — no move |
| 7 | Termination / `:decreases` | non-negativity ≠ termination | accept; disclaimer + partiality flag | n/a | n/a | **TERM-1** |
| 8 | PBT evidence — sample counts | enrich schema | extend OBLIG-PBT-3 schema | n/a | accept; OBLIG-PBT-5 acceptance criterion + JSON sketches | (folded into OBLIG-PBT-5) |
| 8b | PBT — `:subjects` over-credit | independent per-subject is wrong | flag as PBT-5 candidate | n/a | confirm shipped defect; min vs clean fix tiers | **OBLIG-PBT-5a, OBLIG-PBT-5b** |
| 9 | Module hygiene | per-module codegen | roadmap-tracked MOD-2..MOD-5 | n/a | n/a | settled — already roadmapped |
| 10 | Typed effects + `do` discard | typed rows + explicit discard | out-of-scope under freeze; `do` clarification inside freeze | n/a | n/a | **DO-1** (rows post-freeze deferred) |
| 11 | FFI / crypto naming | rename `sha1` → `sha1_stub` | spec is honest; naming-ergonomics has merit | n/a | **retracted verification claim**; keep naming-ergonomics note | **CRYPTO-1** |
| 12 | `EOp` argument checking | audit obligation | hand to engineer | n/a | real soundness defect; specific fix sketch + regression test enumeration | **TC-EOP-1** |
| 13 | Categorical reading | unify with patch-merge | route to professor | reject full unification (fibrations disproportionate) | narrower unification: DP as valuation on subobject lattice; patch-merge stays stipulated | **DP-FORM-1, TRUST-DP-1** (see §3.2) |
| Q1 | Integer semantics | choose one of (a)/(b)/(c) | route to professor | adopt (a); `MachineInt` post-freeze | accept + concrete v0.10.x → v0.11 transition plan | **INT-PRE, INT-1, INT-2, INT-3** |

Convergence: 14 of 16 critique rows settled directly; 2 rows required minor framing adjudication after the amended-critic turn (refinement metatheory framing, narrower categorical unification). Both adjudications recorded in §3 below.

## 2. Retractions on record

The external critic explicitly retracted two sub-claims after the language-team triage:

1. **ASCII / UTF-8 sub-claim** — [`LLMLL.md:71-117`](../../LLMLL.md) is internally coherent: source files are UTF-8, identifiers are ASCII-only, curated Unicode aliases are accepted only for selected tokens (the `->` / `→` example), and Unicode identifiers are disallowed to defend against homoglyph and invisible-character problems in multi-agent AST merging.

2. **Crypto verification claim** — [`LLMLL.md §13.11`](../../LLMLL.md) already classifies crypto primitives as `asserted`/opaque and caps dependent-function tiers accordingly; the implementation note at line 2024 and the codegen comment at [`CodegenHs.hs:370-383`](../../compiler/src/LLMLL/CodegenHs.hs) make the stub status explicit. The only remaining concern is *naming ergonomics* (CRYPTO-1) — adding a trust-tier annotation that surfaces the stub-backend status in machine-readable form so downstream agents do not misread the standards-grade names.

## 3. Adjudicated framing decisions

### 3.1 Refinement metatheory framing (REF-META-1)

Two framings converged on the same content from different reading paths; the language-team adopted the amended critic's narrower framing.

- **Professor framing** (Vazou-style subtyping): subtyping rule from Vazou ICFP 2014 §3.2 verbatim; `{x:Int | P} <: {x:Int | Q}` iff `P ⇒ Q` valid in QF-LIA.
- **Amended critic framing** (checking-mode-only, non-goals explicit): refinement aliases are transparent (erasure-only) with checking-mode obligation generation. Inference rule:

  ```
  Γ ⊢ e : τ ⇝ O
  Γ ⊢ p[e/x] obligation
  ─────────────────────────
  Γ ⊢ e ⇐ A ⇝ O ∪ { p[e/x] }
  ```

  With explicit non-goals: no general refinement subtyping, no dependent pattern matching, no type-level computation, no proof terms, no sigma types, no boolean-expression-as-type-equality.

**Adjudication: adopt the amended critic's framing.** The two are operationally equivalent — Liquid Haskell's "subtyping" is exactly the critic's checking-mode rule under a different name — but the narrower framing matches LLMLL's actual surface (no `<:` relation user-side, only refinement-typed parameters and returns that flow obligations) and pre-empts the implicit Vazou-closure scope (abstract refinements, parametric refinements, bounded refinements) that would creep in under the broader subtyping framing.

**Soundness statement of record** (tier-aware version, adopted verbatim from the amended critic):

> If `Γ ⊢ e : τ ⇝ O`, all obligations in `O` are discharged at solver-backed evidence level, codegen is faithful for the involved constructs, and no trusted FFI/opaque primitive is used, then the erased generated program preserves the declared refinement predicates at checked introduction and elimination sites.

This matches `strict-verified-core`'s operational enforcement exactly. Path B (mechanized soundness theorem against an independently-defined operational semantics) remains explicitly declined — Liquid Haskell shipped without mechanized soundness for a decade, LLMLL inherits the same pragmatic stance, anchored in [`verification-debate.md`](verification-debate.md).

### 3.2 Narrower categorical unification (DP-FORM-1, TRUST-DP-1)

The amended critic substantially narrowed the original critique's §13 unification ask:

- **Original critique:** full categorical apparatus (programs as objects, patches as morphisms, refinements as subobjects, evidence as thin poset, trust as monotone map, `Command` as graded monad, modules as signatures-with-models); patch-merge invariant *derived* as a functoriality law.
- **Professor adjudication:** reject — fibrations-of-refinements framework exists but is disproportionate (~2-year mechanization for a project under feature freeze); the patch-merge invariant is as good *stipulated* as *derived*; Liquid Haskell, Dafny, F\*, and Lean all stipulate the analogous invariant.
- **Amended critic (revised):** narrower unification only — contracts form a preorder under implication; denotation maps contracts to subobjects of a finite behavior space; DP is a valuation on that subobject lattice. Patch-merge invariant stays stipulated.

**Adjudication: adopt the narrower unification as the DP formalization stance.** The professor's three rejection arguments map as follows under the amended position:

1. *Constructions not in same neighborhood* — no longer applies; the narrower proposal places both DP and contracts in the same lattice.
2. *Framework disproportionate* — substantially relaxed; finite-lattice + valuation is undergraduate-level apparatus, not graduate-thesis-level.
3. *Stipulated is as good as derived* — still applies to the patch-merge invariant, which the amended critic does not try to derive.

Concrete content (lands at [`docs/research-track.md:145-151`](../archive/research-track.md) under DP-FORM-1):

> Let `B_{T,U,Ω}` be the finite set of observational behaviors for functions `T → U` over observation set `Ω`. Let `⟦S⟧_Ω = { b ∈ B_{T,U,Ω} | b satisfies contract S }`. Normalized discriminative-power score:
> `DP_Ω(S) = 1 - log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)`
> with edge cases: `DP = 0` if S admits every behavior; `DP = 1` if S admits exactly one behavior; `DP undefined/flagged` if S is inconsistent.

**Two-axis assurance model** (TRUST-DP-1) — trust-report JSON gains a paired `(evidence, DP)` representation per function rather than a collapsed scalar:

```json
{
  "function": "transfer",
  "evidence": "verified",
  "body_faithful": true,
  "contract_discriminative_power": 0.82,
  "dp_basis": {
    "observation_set": "bank-ledger-v1",
    "behavior_classes": 500,
    "satisfying_classes": 12
  }
}
```

The pair disambiguates the four spec-quality cells the project has been heuristically reaching for since `--weakness-check` shipped in v0.3.5: *verified-strong* (ideal), *verified-weak* (high evidence, low DP), *tested-strong* (lower evidence, high DP), *asserted-strong* (promising spec, poor evidence). Patch-merge invariant remains stipulated per Sub-proposal 3 of the language-team triage.

## 4. Routing table — seventeen tagged items

Tags follow the project's `XXX-N` pattern from [`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md) (OBLIG-, MOD-, TRUST-, EVID-, etc.). Status field tracks downstream-skill progress; lifecycle is *open* → *routed* → *in-progress* → *shipped*.

| Tag | Item | Priority | Owner | Status | Notes |
|---|---|---|---|---|---|
| **DRIFT-1** | LLMLL.md v0.10.1 → v0.10.6 catch-up | P0 | doc-lead | Shipped (Pass 7 closure, v0.10.8) | Pass 5 (`7ccd925`, 2026-05-23) closed §4.2 letrec TERM-1, §9.6 DO-1, §13.11 CRYPTO-1, banner v0.10.1 → v0.10.6 + history rows v0.10.2–v0.10.6, schema `$id` v0.2 → v0.5. Pass 6 (`623c46f`) closed banner v0.10.6 → v0.10.7, v0.10.7 history row, §12 `check` grammar amendment + Grammar Rule 10 for `:subjects`. Pass 7 (`faf1856`, 2026-05-24) closed §3 catch-up via §3.1 NOTE at [`LLMLL.md:162`](../../LLMLL.md) cross-referencing the §5.3.5 `overflow_tainted` callout; INT-1 ship at `900e5ab` + `1585de2` unblocked the residual. |
| **DRIFT-CI-1** | Version-gate CI (5 criteria from amended critic) | P0 | infra / doc-lead | Shipped (engineer infra patch, branch `drift-ci-1/version-gate`) | (1) README version == LLMLL.md version; (2) LLMLL.md version == CHANGELOG top version; (3) schema `schemaVersion` field == `ParserJSON.hs::expectedSchemaVersion`; (4) schema `$id` URL aligns with `schemaVersion` policy; (5) examples inside grammar. Pass 6 (`623c46f`) reconciled C1/C2/C3/C4 to ✅ and verified C5 (reading (ii) round-trip) against the new §12 grammar via the §4.4.5 worked examples. Pass 7 (`faf1856`) + v0.10.8 release commits (`1585de2`, `5c6bdec`) extended the C1+C2 banner-equality chain through v0.10.8. Engineer infra patch on branch `drift-ci-1/version-gate` ships the automation: [`scripts/version_gate.sh`](../../scripts/version_gate.sh) (C1+C2+C3+C4, pure shell + `jq`, no Stack), [`scripts/spec_roundtrip.py`](../../scripts/spec_roundtrip.py) (C5, opt-in via `<!-- ci:roundtrip -->` markers; one initial opt-in block at `LLMLL.md:396` as smoke), [`.github/workflows/version-gate.yml`](../../.github/workflows/version-gate.yml) (two-job workflow on push/PR-to-main), 21 pytest cases at [`scripts/tests/`](../../scripts/tests/) covering the scripts with `llmll`-binary stubs. Both residuals closed. |
| **TC-EOP-1** | EOp arity/type-check fix + regression suite (both frontends) | P0 | engineer | Shipped v0.10.7 | Shipped commit `c8a68de` — `inferExpr (EOp op args)` at [`compiler/src/LLMLL/TypeCheck.hs:981`](../../compiler/src/LLMLL/TypeCheck.hs#L981) rewritten to mirror the `EApp` arity-check + `structuralUnify` per-call-site-substitution loop with `withSegment "args"` pointer-stack discipline and `EHole` bypass; polymorphic `=` / `!=` unify both operands against one bound `TVar`. 9 regression tests under `TC-EOP-1 EOp arity and arg-type checking` in [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs). |
| **REF-META-1** | Checking-mode typing rule + non-goals + soundness statement | P0 | language-team draft → doc-lead | **SHIPPED v0.11** *(status corrected 2026-08-18 — was stale "Settled (proposal Rev 1) — awaiting professor review")* | LT proposal landed at [`docs/design/refinement-metatheory-of-record-proposal.md`](../archive/shipped-design-specs/refinement-metatheory-of-record-proposal.md) (2026-05-24). Adopts amended critic's framing per §3.1 above; checking-mode intro+elim rule + six non-goals + tier-aware soundness statement. Doc-lead promotion target: `LLMLL.md §3.4 / §5`. Recommend batching professor review with LT-INV / LT-CDP / LT-PPR. **Corrected 2026-08-18 by measurement:** the roadmap's "v0.11 LT items (LT-INV, LT-CDP, LT-PPR, LT-INT/INT-2, INT-PRE, REF-META-1)" row reads **All shipped (v0.11)**. The professor review this row was waiting on happened and was folded; the row was never advanced. |
| **OBLIG-PBT-5a** | Multi-subject minimum fix (`joint_pbt_witness` diagnostic + scalar-count exclusion) | P1 | engineer | Shipped v0.10.7 | Shipped commit `fbb8f28` — [`TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs) computes `jointHashes :: Set Text` (post-clause hashes appearing on ≥2 distinct subjects) and demotes joint-only `DLTested` entries to `DLAsserted` in `computeSummary` / `aggregateTiers` / `aggregateTiersPost`; the "every witness is joint" predicate preserves `+1` credit for solo+joint mixes. Per-entry `joint_pbt_witness: true` + top-level `joint_pbt_witnesses` JSON additions. `trust_report_version` stays `1.1.0`. 6 regression tests under `OBLIG-PBT-5a joint PBT witness exclusion` in `Spec.hs`. |
| **INT-PRE** | Experiment-lead cost pre-check: `Int` vs `Integer` on TOTP/ERC-20/B1/B3/B5 | P1 | experiment-lead | Cleared — `int-2-clear` | experiment-lead postmortem-001 (2026-05-24, commit `8cac520`): TOTP test-phase regression factor 1.015 (n=10) against 5.0 gate threshold; byte-identity controls hold across all five benchmarks. See [`experiments/int-pre/findings/postmortem-001.md`](../../experiments/int-pre/findings/postmortem-001.md). INT-2 gate cleared; LT-INT engineer build unblocked. |
| **INT-1** | Integer semantics v0.10.x overflow-tainted marking; strict-core refusal | P1 | engineer | Shipped v0.10.8 | Shipped commit `900e5ab` (+ release chore `1585de2` + Pass 7 doc-lead `faf1856` + CLI help text `5c6bdec`). `erOverflowTainted :: Bool` added to `EvidenceRecord` at [`Syntax.hs:326-331`](../../compiler/src/LLMLL/Syntax.hs#L326-L331); `bodyHasOverflowArith` at [`FixpointEmit.hs:597-642`](../../compiler/src/LLMLL/FixpointEmit.hs#L597-L642) activated post-body-faithful at `:506-516`; `--strict-verified-core` at [`Main.hs:1119-1158`](../../compiler/app/Main.hs#L1119-L1158) refuses `erBodyFallback ∪ erOverflowTaintedFns` with distinct diagnostics naming `?proof-required` + Leanstral / INT-2 escape paths. Additive sidecar + trust-report + obligation-report fields (`overflow_tainted: true` only-when-true); `.verified.json` invalidate-on-missing for pre-v0.10.8 verified body-faithful entries at [`VerifiedCache.hs:158-216`](../../compiler/src/LLMLL/VerifiedCache.hs#L158-L216). `trust_report_version` stays `1.1.0`; JSON-AST `schemaVersion` stays `0.5.0`; verification fragment unchanged. 16 regression tests under `INT-1 (v0.10.8): overflow taint propagation` in `Spec.hs`. Unblocks DRIFT-1 §3 residual. |
| **TRUST-DP-1** | Two-axis (evidence, DP) trust-report schema delta | P1 | language-team draft → engineer | Subsumed into LT-CDP | Subsumed into the v0.11 LT-CDP proposal per [`docs/design/contract-discriminative-power-proposal.md`](../archive/shipped-design-specs/contract-discriminative-power-proposal.md) and [`docs/compiler-team-roadmap.md:155, 312`](../compiler-team-roadmap.md#L155). Two-axis (evidence, DP) trust-report representation is the LT-CDP §Schema delta; `trust_report_version 1.1.0 → 1.2.0` bump bundled with LT-CDP ship. No separate engineer work — fate is tied to LT-CDP. Original framing at §3.2 above. |
| **INT-2** | `int → Integer` codegen switch (v0.11) | P2 | engineer | **SHIPPED v0.11** *(status corrected 2026-07-20 — was stale "engineer-ready; awaiting build")* | Shipped in v0.11 per `CHANGELOG.md §v0.11.0` "LT-INT (v0.11): `int → Integer` codegen switch": `CodegenHs.hs:441/706/723` flipped (`mapLlmllPrimType "int" = "Integer"`), Class B preamble lifts, Class A `fromIntegral` boundary shims, INT-1 taint dormant, 8 L1–L8 regression tests. Verified empirically 2026-07-20 (generated Haskell emits `(x + (1 :: Integer))`). INT-PRE had cleared the gate at 1.015× (postmortem-001, `8cac520`); boundary-shim catalog `docs/archive/shipped-design-specs/int-2-boundary-shims.md` (Rev 1). Successor **INT-3** (`MachineInt`) stays a dormant P3. |
| **OBLIG-PBT-5b** | Multi-subject clean fix (`EvidenceRecord.scope = Singleton subj \| Joint [subjs]`) | P2 | **SHIPPED v0.14.60** *(status corrected 2026-08-18 — was stale "post-freeze")* | post-freeze **Corrected 2026-08-18 by measurement:** the roadmap carries `OBLIG-PBT-5b` in **Resolved cross-cutting items** marked SHIPPED, not in Active Items. `docs/UPDATE-PROTOCOL.md` §3.4 had already recorded this correction on 2026-08-09 without the triage row being updated to match. | `trust_report_version` 1.1.0 → 1.2.0; new `tested-joint` display level |
| **TERM-1** | `:decreases` partiality disclaimer at `LLMLL.md §4.2` [original row read `§3.2`; chapter off-by-one corrected post-ship] | P2 | doc-lead | Shipped | Pass 5 (`7ccd925`) landed the IMPORTANT callout naming the partial-correctness consequence of unverified strict descent; postconditions on `letrec` functions explicitly hold conditionally on termination per [`verification-debate.md`](verification-debate.md) Q4. |
| **DO-1** | `do`-notation explicit discard clarification at `LLMLL.md §9` + compiler warn-or-error | P2 | doc-lead + engineer | **BOTH HALVES SHIPPED** *(status corrected 2026-08-18 — was "Spec-text shipped; compiler warn-or-error open (engineer sub-item)")* | Pass 5 (`7ccd925`) shipped the §9.6 split into Compilation bullet + IMPORTANT "Intermediate commands silently discarded" callout, naming the surprise relative to monadic `do`-notation and signalling the v0.11+ warn-or-error tightening. Engineer compiler-side warn-or-error on non-final `Command`-typed binds remains separable. **Corrected 2026-08-18 by measurement:** the engineer sub-item shipped under a different tag, which is why this row never closed. Roadmap: `DO-ACCUM-1` (a non-final `do` step's `Command` is silently discarded) is **SHIPPED v0.14.80 as DISCARD-1**, and `checkDiscardedCommand` is live in [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs). A tag rename is enough to strand a routing row indefinitely. |
| **CRYPTO-1** | Crypto-stub trust-tier annotation (no rename) at `LLMLL.md §13.11` | P2 | doc-lead | **RETRACTED 2026-08-03 — see CRYPTO-2** | Formerly "Shipped": Pass 5 (`7ccd925`) was credited with landing a `asserted-with-stub-backend` trust-report channel. **That channel does not exist.** `grep -rn 'stub-backend' compiler/` returns zero hits and `TrustReport.hs:1630` emits `"asserted"`; `git show --stat 7ccd925` is `docs(spec, schema)`, a documentation-only commit. What landed was a paragraph describing a mechanism, marked Shipped without a compiler-side witness. The `sha1` / `hmac-sha1` naming decision (retain RFC 2104 / FIPS 180-4 contract names, stub status is an implementation defect) **stands** and is unaffected. |
| **CRYPTO-2** | Retract the `asserted-with-stub-backend` channel; state what actually holds | P2 | doc-lead + language-team | **Open — ROUTED 2026-08-18** | **The retraction.** The `asserted` cap on every function whose trust closure reaches `sha1` / `hmac-sha1` is real, emitted, and sufficient; no separate tier or field exists or should. A tier is the wrong *shape* for this, not merely absent: a tier is a position in an ordered lattice and must be monotone under composition, whereas "reaches an axiom known to be false" asserts the assumption set is inconsistent, from which anything follows, and `LLMLL.md §4.4.1`'s diamond has no bottom element meaning *unsound*. The established mechanism is an **axiom-dependency report over the justification closure** (Lean `#print axioms`, Coq `Print Assumptions`; cf. CompCert's TCB enumeration, Leroy CACM 2009, and foundational PCC, Appel LICS 2001), named `assumed_axioms` and **not scheduled** — it would sit beside the tier rather than subsume it, making it an additive report field rather than a trust-model change. **Blast radius:** two archived proposals used the non-existent channel as a real admissibility criterion (`docs/archive/shipped-design-specs/core-shell-inversion-proposal.md:162`, `refinement-metatheory-of-record-proposal.md:143`), so both encode a gate that can never fire. **Why no gate caught it:** `doc_claims_gate.sh` (DRIFT-CT-2) guards *restriction* claims by running `.llmll` fixtures through `llmll check`; a claim that the trust report emits a given field has no expressible fixture in that harness. Filed as `REPORT-GATE-1` (`driver-ll-open-work.md` R-12). **Routed 2026-08-18:** a roadmap row now exists in Active Items, `CRYPTO-2` `[SPEC][CT]`, naming the spec retraction at `LLMLL.md:2727` as the work. It had been adjudicated since 2026-08-03 with no row, which is why nothing executed it. `REPORT-GATE-1` stays separate and unrouted. |
| **STRICT-CORE-1** | Strict-verified-core admissibility rules codification | P2 | language-team draft → doc-lead | Subsumed into LT-INV | Subsumed into the v0.11 LT-INV proposal per [`docs/design/core-shell-inversion-proposal.md`](../archive/shipped-design-specs/core-shell-inversion-proposal.md) §1 (whitelist grammar for `def` core bodies) and [`docs/compiler-team-roadmap.md:154, 311`](../compiler-team-roadmap.md#L154). LT-INV's whitelist grammar production *is* the strict-verified-core admissibility codification; no separate `LLMLL.md §5.3` sub-section needed pre-LT-INV. Fate is tied to LT-INV. |
| **REF-META-2..5** | Solver-completeness statement, erasure theorem with construction-side discipline, predicate WF rule, typing judgment | P2–P3 | language-team drafts → doc-lead | **SHIPPED v0.12.0** *(status corrected 2026-08-18 — was stale "open")* | Sequence after REF-META-1; piece 2.5 (typing judgment) and 2.3 (predicate WF) are multi-page authoring jobs **Corrected 2026-08-18 by measurement:** the roadmap row "REF-META-2..5 (solver-completeness, predicate WF, erasure, type-assignment)" reads **All promoted / shipped v0.12.0**, and v0.12.0's Shipped-Releases entry names REF-META 1–5. |
| **DP-FORM-1** | DP formalization promotion at `docs/research-track.md:145-151` (narrower lattice-valuation framing) | P3 | doc-lead | Subsumed into LT-CDP | Subsumed into LT-CDP per [`docs/design/INDEX.md:26`](INDEX.md#L26) and [`docs/compiler-team-roadmap.md:155, 312`](../compiler-team-roadmap.md#L155). The narrower lattice-valuation framing from §3.2 above lands in LT-CDP §Semantics; `docs/research-track.md §6` already retired in DRIFT-1 catch-up Pass 3 with cross-reference. No separate doc-lead promotion needed; LT-CDP ships the formalization. |
| **INT-3** | `MachineInt` post-freeze alias under QF-BV verification scope | P3 | language-team design | Dormant — contingency sketch Rev 0 landed | Contingency sketch landed at [`docs/design/int-3-machine-int-sketch.md`](int-3-machine-int-sketch.md) (Rev 0, commit `32a796e`). INT-PRE cleared `int-2-clear` (TOTP 1.015× < 5× gate), so INT-3 stays dormant per the freeze-exception trigger; remains v0.12+ research-track. Promotes to P1 only if a future cost gate fires. |

## 5. Items explicitly declined or deferred

| Item | Status | Reason |
|---|---|---|
| Full categorical unification (fibrations, graded monads, patch-merge derivation) | Declined | Disproportionate per professor adjudication; amended critic did not re-propose |
| Path B mechanized soundness theorem against independent operational semantics | Declined | Inherited from [`verification-debate.md`](verification-debate.md) Path A stance |
| `?proof-required` predicate-carrier expansion | Deferred (already tracked) | See [`proof-required-predicate-carrier.md`](../archive/shipped-design-specs/proof-required-predicate-carrier.md); revisit conditions stand |
| `sha1` / `hmac-sha1` symbol rename to `sha1_stub` | Declined | Spec contract is standards-grade; stub status is implementation concern (handled by CRYPTO-1's trust-tier annotation) |
| Typed effect rows (`Command caps a`) | Deferred to post-freeze (WASM build target) | Out-of-scope under feature freeze per [`compiler-team-roadmap.md:28-31`](../compiler-team-roadmap.md) |
| Module hygiene MOD-2..MOD-5 | Roadmap-tracked, post-freeze | No new finding; the original critique correctly reads the spec as admitting these limitations |

## 6. Downstream hand-off prompts

Each P0/P1 item below ships as a tight hand-off summary; downstream skill prompts can be derived directly from these.

**To compiler-engineer (P0/P1 bundle):**

> TC-EOP-1: arity/type-check fix at [`compiler/src/LLMLL/TypeCheck.hs:981-988`](../../compiler/src/LLMLL/TypeCheck.hs). The current `inferExpr (EOp op _args)` ignores `_args` and returns `builtinEnv`'s result type. Fix: check `length args == length paramTypes`; unify each arg type against the corresponding `paramType`; compose substitutions; return `applySubst finalSubst retType`. Polymorphic equality (`=`) must require both operands unify with the same type variable, not degrade to `any × any → bool`. Regression tests must exercise both S-expression and JSON-AST frontends; cases: `(+ 1 2)`, `(+ 1)`, `(+ "x" 1)`, `(not 1)`, `(= 1 "1")`, `(first 42)`, `(and true 0)`. Narrowing fix, sails through freeze. OBLIG-PBT-5a: add `joint_pbt_witness = true` diagnostic to trust-report when one witness hash appears on >1 subject; exclude joint-only evidence from scalar `tested` counts. Additive, no `trust_report_version` bump.

**To experiment-lead (P1):**

> INT-PRE: measure runtime cost of `int → Integer` codegen change against current `int → Int` on benchmarks B1, B3, B5, TOTP (`examples/totp_rfc6238/`), ERC-20 (`examples/erc20_token/`). Report per-benchmark regression factor. Gate criterion: if TOTP regresses >5×, escalate INT-3 (`MachineInt` QF-BV alias) from P3 to freeze-exception candidate; otherwise INT-2 proceeds as planned for v0.11.

**To language-team (next design-doc cycle):**

> REF-META-1, STRICT-CORE-1, TRUST-DP-1: three design-doc drafts wanted as proposal/review pairs under `docs/design/`. REF-META-1 lands the checking-mode rule + non-goals + soundness statement (content in §3.1 above). STRICT-CORE-1 codifies the admissibility rule set the language-team triage Sub-proposal 2 enumerated. TRUST-DP-1 specifies the trust-report schema delta for the two-axis assurance model (content in §3.2 above). Each draft can route to professor optionally, then to engineer.

**To doc-lead (P0 bundle):**

> DRIFT-1 + DRIFT-CI-1: catch `LLMLL.md` up from v0.10.1 to v0.10.6 (changelog entries v0.10.2 through v0.10.6 enumerate the deltas); reconcile schema `$id` URL with `schemaVersion` field at [`docs/llmll-ast.schema.json:3,16`](../llmll-ast.schema.json); implement the five-criterion CI gate the amended critic specified. Bundle TERM-1, DO-1, CRYPTO-1 spec text into the same pass.
>
> *Closure (2026-05-24): DRIFT-1 mostly shipped via Passes 5 + 6 (see row :110 status); DRIFT-CI-1 content-satisfied via Pass 6 (see row :111 status); TERM-1, DO-1 spec-text, CRYPTO-1 shipped via Pass 5 (see rows :120, :121, :122). Residuals: §3 catch-up gated on INT-1 (v0.10.8); workflow YAML automation and C5 round-trip harness pending infra.*
>
> *Engineer infra-patch closure (branch `drift-ci-1/version-gate`): both DRIFT-CI-1 residuals (`.github/workflows/version-gate.yml` automation + C5 round-trip harness) shipped. See row `:111` status for the artifact set.*

---

**End of triage record.** Future sessions can read this document plus the routing table at §4 to pick up the work without re-deriving any of the adjudication. New work items adopt the same `XXX-N` tag pattern and either extend the §4 table or open new triage records dated separately.

---

## 7. Archive-trigger evaluation, 2026-08-18

`docs/UPDATE-PROTOCOL.md` §3.4 sets this document's archive trigger at "all 17
routing items closed", destination `docs/archive/triages/`, and recorded the
gate as **not evaluated**. It is evaluated here. **The trigger has NOT fired.**

**Two items are open.**

- **`CRYPTO-2`** — open, and **ROUTED 2026-08-18**: an Active-Items roadmap row
  now exists, `CRYPTO-2` `[SPEC][CT]`. It had been adjudicated since 2026-08-03
  (as `R-10` in [`driver-ll-open-work.md`](driver-ll-open-work.md)) with no row,
  which is why nothing executed it. The retraction still holds on measurement:
  `rg 'assumed_axioms|stub-backend' compiler/` returns zero hits. **The primary
  defect is in the spec, not in the archived proposals:** `LLMLL.md:2727` states
  in the present tense, inside an `[!IMPORTANT]` block, that the trust report
  annotates dependencies as `asserted-with-stub-backend`. It does not.
  `REPORT-GATE-1` (`R-12`) covers the class gap and stays separate and
  unrouted.
- **`INT-3`** — `P3 — open` in the roadmap's Active Items, per the dormant
  contingency in [`int-3-machine-int-sketch.md`](int-3-machine-int-sketch.md).

**Four rows were reporting a state the tree contradicted**, and are corrected
above: `REF-META-1`, `OBLIG-PBT-5b`, `DO-1` and `REF-META-2..5`. Every one had
shipped. `DO-1` is the instructive case: its engineer sub-item shipped under a
**different tag** (`DO-ACCUM-1`, as `DISCARD-1`, v0.14.80), and a tag rename is
enough to strand a routing row indefinitely, because nothing joins a triage row
to the roadmap by identity.

**This file's line numbers are pinned by shipped compiler output, so edit it in
place.** `compiler/src/LLMLL/CodegenHs.hs:919` emits `critique-2026-05-23-triage.md:25`
into every generated Haskell program that uses `sha1`; `CHANGELOG.md:5476` cites
`:111` and [`driver-ll-open-work.md`](driver-ll-open-work.md)`:211` cites `:122`.
The four corrections above are single-line cell rewrites and this section is an
append, so no cited line moved. Nothing checks this: DRIFT-DOC-4 lints path
citations, not line numbers.
