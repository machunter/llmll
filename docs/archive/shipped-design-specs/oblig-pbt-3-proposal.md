# OBLIG-PBT-3 — PBT-to-Trust-Report Write-Back

> **Version:** Rev 2 — Professor review incorporated
> **Date:** 2026-05-13
> **Implements:** `docs/compiler-team-roadmap.md` row 165 (v0.10.5 — Future Module System Codegen / OBLIG-PBT-3)
> **Prerequisites:** OBLIG-PBT-2 (v0.10.5-pre) shipped, R6d trust-report aggregate (v0.10.4) shipped
> **Reviewed:** Professor — Rev 1 (7 gaps + 2 open questions, all resolved in Rev 2). See [`oblig-pbt-3-review.md`](../professor-reviews/oblig-pbt-3-review.md).
> **Status:** Settled — awaiting compiler-engineer hand-off

---

## 1. Motivation

LLMLL's evidence model (`LLMLL.md` §4.4.1) admits four display levels — `verified`, `contract-checked`, `tested`, `asserted` — arranged in a partial-order diamond lattice. As of v0.10.5-pre, three of those four levels are produced from runtime evidence: `verified` and `contract-checked` from `llmll verify`'s liquid-fixpoint discharge, and `asserted` as the structural default. The fourth — **`tested`** — is constructed only from source-annotated `:trust tested` markers (`Parser.hs:381`, `ParserJSON.hs:289`) and from `.verified.json` cache deserialization (`VerifiedCache.hs:52`). No code path threads `runPropertyTests` outcomes into `TrustReport.hs:enrichEntry`.

Two consequences:

1. **The spec is ahead of the implementation.** `LLMLL.md §4.4.1` line 341 states that `tested` is assigned "when `llmll test` passes." `LLMLL.md §5.1` line 485 states that a `pass` outcome contributes `tested` evidence "per §5.3.5 lattice." Both lines describe a behavior the compiler does not perform. This drift was identified in `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 16 (§F-033).

2. **The strong-form H1-Assurance hypothesis for Phase 3 is structurally unreachable.** Per `postmortem-001:2084`, the `tested` field of the R6d `tier_profile` is unreachable on any property whose `for-all` bindings include a non-primitive type, which covers all three Phase-3 problems (`001-hangman`, `002-bank-ledger`, `003-rate-limiter`).

OBLIG-PBT-3 closes this gap. It threads `PBTPassed` results into the trust report as `DLTested n` evidence on the postcondition of the function under test, with provenance hashing for staleness invalidation.

---

## 2. Scope

**In scope:**
- A linkage rule from `(check ...)` blocks to contracted `def-logic` / `letrec` functions
- A lift rule from `PBTPassed` runs to `DLTested n` evidence on the function's `csPost`
- Sidecar persistence with property-body SHA-256 hashes for staleness validation
- A per-clause split of the trust-report `tier_profile` aggregate (`tier_profile_pre`, `tier_profile_post`) with `trust_report_version` bumped `1.0.0 → 1.1.0`
- Spec disclosures: linkage rule, sample-count semantics, sidecar invariant change, design divergence from Liquid Haskell

**Out of scope (deferred to OBLIG-PBT-4):**
- `:subject` keyword metadata on `(check ...)` blocks for explicit subject attribution
- Coverage-instrumented sample counts distinguishing witnessing vs vacuous evaluations
- Generator-side discard saturation fixes for deep nested unfolds (deferred separately — candidate OBLIG-PBT-5)

**Out of scope under feature freeze:**
- No new builtins, syntax constructs, FFI tiers, WASI capabilities, or orchestration features
- No JSON-AST source-schema delta (`expectedSchemaVersion` stays `"0.4.0"`)

---

## 3. Linkage rule — singleton head-position subject

A `(check ...)` block lifts at most **one** function. Let `HEAD(propBody)` denote the set of names `f` such that `f` appears as the operator of some `EApp` node reachable by recursive descent through `EApp`-arguments, `ELet`, `EIf`, `EMatch`, `EPair`, `ELambda`, `EDo`, and `EOp`-arguments. Let `HEAD-contracted(propBody, Σ)` be the subset of `HEAD` that resolves under the assembled statement list `Σ` (post-`assembleTestStatements`) to an `SDefLogic n _ _ c _` or `SLetrec n _ _ c _ _` with `contractPost c /= Nothing`.

The lift triggers only when `HEAD-contracted` is a **singleton** `{f}`. Multi-subject properties — those mentioning two or more contracted callees in head position — emit an informational diagnostic from `llmll test` ("property covers multiple contracted callees; no trust evidence recorded — split the property or wait for `:subject` metadata in OBLIG-PBT-4") and produce no lift.

**Rationale.** A property body invoking multiple contracted functions cannot be decomposed into independent evidence for each; the property witnesses joint behavior. Crediting both functions with `DLTested n` from one observation overallocates evidence (Pacheco-Lahiri-Ernst, *Feedback-directed random test generation*, ICSE 2007). The singleton restriction is the conservative reading. Agent-authored properties divide into two shapes: **operation-preserves-its-own-postcondition** (the `withdraw` example — the operation under test produces the value the property observes; head-set typically singleton modulo uncontracted observers) and **observer-of-operation** (`(= (total-balance l) (total-balance (transfer l from to amt)))` and similar — operation and observer are distinct contracted functions; head-set canonically multi-callee) — the canonical **metamorphic-relation** property idiom per Hughes 2020 *How to Specify It!* §3, distinct from state-machine command-sequence properties (Claessen-Hughes, `eqc_statem`-style) which LLMLL has not adopted. Phase 2's c01 cell on `002-bank-ledger` measured this division empirically: under v0.10.5, n=12/12 PBTPassed bodies hit the multi-callee guard (`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 17 §LT-B (informed), 2026-05-14). The conservative singleton fallback therefore suppresses ~100% of `PBT-Lift` candidates on the metamorphic-relation / observer-of-operation idiom — the natural shape of "operation preserves observable property" — which OBLIG-PBT-4's `:subjects [f g]` opt-in is designed to unblock.

The restriction is intentionally tight; OBLIG-PBT-4's `:subject` metadata route lifts the restriction by letting agents declare joint-evidence explicitly via `:subjects [f g]`.

---

## 4. Inference rule

```
              (SCheck p) ∈ Σ
              status(p) = PBTPassed
              evaluatedSamples(p) = n
              HEAD-contracted(propBody p, Σ) = {f}      (singleton)
              SDefLogic f _ _ c _  ∈  Σ ∪ importedExposed(Σ)
              contractPost c = Just _
              hash(propBody p) = h
            ─────────────────────────────────────────────────────
            csPost(f) ⊑  DLTested n   with  pbt_witnesses ∋ {h, desc(p)}
```

`⊑` denotes lattice-respecting monotonic upgrade: the lift applies only when the current `csPost.erDisplayLevel` is `DLAsserted`. Pre-existing `DLTested`, `DLContractChecked`, or `DLVerified` entries are preserved per `evidenceCovers` (`Syntax.hs:362-371`). The merge primitive is `Module.mergeCS`, already used by `buildTrustReport` for sidecar-over-base merging.

**Side conditions:**

1. **Subject scoping.** `f` may be a name local to the source file or a name imported via `(open path …)` and resolved through `assembleTestStatements`.
2. **Failure suppresses lift.** `PBTFailed` records no `DLTested`. The failing property is surfaced as a diagnostic to the user but does not contribute to `pbt_witnesses`.
3. **Skipped is no-op.** `PBTSkipped` (static-eval bottoms, QuickCheck-discard saturation) contributes zero trust evidence per `LLMLL.md §5.1:487`.
4. **PBTError is treated as PBTSkipped for write-back.** Exceptions during QuickCheck propagate as user-facing diagnostics; the trust-report channel ignores them.
5. **Interface laws do not lift `def-logic` posts.** Properties extracted from `SDefInterface.defInterfaceLaws` at `PBT.hs:168-173` are parametric over interface implementations, not concrete evidence for `def-logic` functions invoked in the law body. Distinct trust channel; out of scope.
6. **Lift targets `csPost` only.** Preconditions are caller-side obligations whose evidence channel is the call-site VC. Lifting `csPre` from PBT would conflate two evidence channels and produce false trust.

---

## 5. Sample-count semantics

`evaluatedSamples(p)` is **the number of property-body evaluations that reduced to `True`, with no evaluation reducing to `False`**:

- **Static-eval path** (`PBT.hs:210-217`): `evaluatedSamples = nSamples = 100`. All 100 samples produced concrete `LitBool` evaluations.
- **QuickCheck fallback path** (`PBT.hs:381-411`): `evaluatedSamples = numTests` from `Result.Success` — non-discarded evaluations under `QC.discard` semantics.

The spec disclosure at `LLMLL.md §4.4.1` and `§5.1` must read:

> `DLTested n` records that `n` samples were generated and the property body reduced to `True` on each; no sample produced `False`. This is a lower bound on assertions of the postcondition: under an implication-shape property `(if pre then post else true)`, samples for which `pre` fails count as `True` evaluations vacuously. A coverage-instrumented count distinguishing genuine postcondition witnesses from vacuous evaluations is a follow-on (OBLIG-PBT-4); under v0.10.5, `n` is honest about evaluation but not about exercise.

This is the explicit-disclosure resolution to the Hughes 2020 (*How to Specify It!*) §4 coverage-tracking concern. The honest count requires `QC.classify` / `QC.cover` instrumentation, which is engineer-time non-trivial and routes to OBLIG-PBT-4 alongside the `:subject` metadata work.

---

## 6. Multi-property accumulation

When multiple `(check)` blocks lift the same `f` (each singleton on `f`, each `PBTPassed`):

```
n_total(f) = max { evaluatedSamples(p) | p covers f, status(p) = PBTPassed }
pbt_witnesses(f) = ⋃ { {hash(p), desc(p)} | p covers f, status(p) = PBTPassed }
```

`max` is the **within-channel join**: independent passing properties each constitute a witness; the strongest single witness dominates. This is distinct from the diamond lattice's cross-channel `evidenceMeet` at `Syntax.hs:344-358`, which uses `min` on `(DLTested, DLTested)` pairs by design — that operation is the GLB across pre/post of a single function, not the join across independent properties on the same clause.

`sum` was considered and rejected: aggregating across properties with potentially overlapping sample distributions would over-claim without statistical independence assumptions.

---

## 7. Property-body provenance and staleness

Each PBT-derived `DLTested` sidecar entry **must** carry the SHA-256 of every contributing property body:

```json
"pbt_witnesses": [
  { "hash": "sha256:abc123…", "description": "transfer_preserves_total_balance" },
  { "hash": "sha256:def456…", "description": "transfer_updates_balances_correctly" }
]
```

The hash is taken over the canonical-serialized `propBody` expression. The engineer-slot choice between piggybacking on the existing `ctVerifiedHash` machinery (`Module.hs`) versus a fresh SHA-256 path is open; either is sound.

`buildTrustReport` validates on read. A `DLTested` entry whose `pbt_witnesses` does not include at least one hash that matches a live `(check)` body — in the local source or in any imported module on the trust-closure path — is **downgraded to `DLAsserted`** for that build. The downgrade is silent at info-level but surfaced as a diagnostic under `--trust-report`:

```
⚠ f.csPost was previously tested by property "<description>"; no live property body matches the cached hash. Evidence downgraded to asserted.
```

This makes the cache deterministically honest: editing a property body invalidates the cached `DLTested`; deleting a property removes the lift; running `llmll test` again regenerates fresh evidence with fresh hashes.

---

## 8. Sidecar invariant statement

`LLMLL.md §4.4.4` must state, in addition to the existing text:

> The `.verified.json` sidecar for a source file `S` may carry entries keyed by **qualified imported names** (e.g., `lib.f`) when a `(check ...)` in `S` lifted the contract of an imported function `f` from module `lib`. This extends the prior invariant that sidecars were keyed by locally-defined names only. Downstream consumers must accept qualified keys; the `collectAllContractStatus` build path at `TrustReport.hs:148-155` already merges by qualified-name across the module cache, so the change is read-side compatible. The sidecar-write target for a PBT-lifted entry is the source file's sidecar (where the `(check)` lives), not the imported module's sidecar.

The `ctVerifiedHash` staleness guard (MOD-1, `Module.hs:meContracts`) covers the imported-sidecar-changed staleness vector; PBT-specific staleness is covered by `pbt_witnesses` (§7). These two mechanisms compose.

---

## 9. Trust-report shape

`trust_report_version` bumps `1.0.0 → 1.1.0`. The trust-report JSON gains two new top-level fields parallel to `tier_profile`:

```
"tier_profile":      { verified, proved, contract_checked, tested, asserted, no_contract }   (unchanged — per-function meet)
"tier_profile_pre":  { verified, proved, contract_checked, tested, asserted, no_contract }   (new — per pre clause)
"tier_profile_post": { verified, proved, contract_checked, tested, asserted, no_contract }   (new — per post clause)
```

Per-clause aggregates are computed by:

```
effectiveLevelPre(e)  = meet(csPre(e),  meet_{c ∈ reachable(e)} effectiveLevel(c))
effectiveLevelPost(e) = meet(csPost(e), meet_{c ∈ reachable(e)} effectiveLevel(c))
```

Each per-function `effectiveLevelPre`/`Post` is then classified into the six buckets via the existing `aggregateTiers` classifier (`TrustReport.hs:355-372`). The classification is `no_contract` when the corresponding clause is `Nothing`.

**Rationale.** The per-function `tier_profile` reduction `meet(pre, post, transitive deps)` pins the effective level to `DLAsserted` whenever any clause or transitive callee sits at the lattice bottom. Pre-OBLIG-PBT-3 this asymmetry was latent because verifier evidence routinely covered post but never pre (per `Main.hs:1186-1212`'s asymmetric SAFE write). OBLIG-PBT-3 makes the asymmetry actionable — c02-shape functions with `pre = DLAsserted` and `post = DLTested` would otherwise contribute only to `tier_profile.asserted`, defeating the lift's empirical visibility. The per-clause split exposes the post-side evidence directly to downstream harness consumers (the R6d `Cred(R)` predicate).

**Not a freeze violation.** Per `TrustReport.hs:95-99`, the trust-report JSON emit is one-way; `trust_report_version` is independent of source AST schema versioning. The bump is documented downstream-tooling surface, not language surface.

---

## 10. Design-divergence disclosure

`LLMLL.md §5.1` or `§4.4.1` must include one paragraph:

> LLMLL admits a statistical evidence channel (`DLTested`) into the trust-report partial order. This is a deliberate departure from Liquid Haskell (Vazou et al., *Refinement Types for Haskell*, POPL 2014), which restricts its refinement-display to logical evidence only. The rationale is that AI-agent-emitted code is often outside the QF-LIA fragment that admits liquid-fixpoint discharge, and an empirical channel — honest about its statistical character per §4.4.1's epistemic-status note — gives the trust report something to surface for that majority. The diamond lattice's incomparability between `DLContractChecked` and `DLTested` prevents agents or readers from silently treating statistical evidence as logical (per `Syntax.hs:355-357`: their meet is `DLAsserted`, not either of them).

This is the spec-side acknowledgment of the design choice the trust system has been carrying since v0.8.1b but never explicitly defended.

---

## 11. `:subject` keyword — deferred to OBLIG-PBT-4

The professor critique (`oblig-pbt-3-review.md` Q-PROF-1) correctly identifies that `:subject f` on `(check ...)` is structurally **metadata**, parallel to `:source` (`LLMLL.md §4.6`), `:level` on `(trust …)` (`LLMLL.md §4.4.3`), and `:decreases` on `letrec` (`LLMLL.md §4.2`) — and is therefore not a new construct under the feature-freeze policy at `docs/compiler-team-roadmap.md:28-31`.

The deferral to OBLIG-PBT-4 is a **scoping** choice, not a freeze-compliance claim:

- v0.10.5 OBLIG-PBT-3 ships the head-position-singleton fallback. Existing `(check)` blocks lift without annotation. Multi-subject properties produce diagnostics but no lift.
- v0.10.6+ OBLIG-PBT-4 introduces `:subject f` (or `:subjects [f g]` for explicit joint-evidence) as optional metadata on `(check)`. Annotated check blocks bypass the head-position scan. Existing programs continue to work.

This sequencing keeps v0.10.5's scope tight: no JSON-AST schema delta, no surface change, no team-consensus exception per `docs/compiler-team-roadmap.md:31`.

**Note (Addendum-17 informed, 2026-05-14).** The original deferral framing treated OBLIG-PBT-4 as a low-priority follow-on absorbing edge cases the v0.10.5 cut did not need to handle. Phase 2's c01 re-probe under v0.10.5 inverts this: n=12/12 PBTPassed bodies on the `002-bank-ledger` problem family hit the multi-callee guard (the observer-of-operation idiom characterized in §3), and OBLIG-PBT-4 is therefore now **Phase-3-gating in combination with OBLIG-PBT-5 / F-033**. The two are independent blockers on independent shapes — F-033 covers c02/c03 (body-side static-eval discard on deep-product and `?proof-required`-in-post bodies); OBLIG-PBT-4 covers c01 (shallow-product observer-of-operation, multi-callee subject disambiguation). On the Phase-3 problem suite, both shapes are present. The compiler-engineer is recommended to bundle OBLIG-PBT-4 and OBLIG-PBT-5 in a single engineer turn — they amortize on the `PBT.hs` surface and share the writeback consumption point at `PBT.hs:660-676`. No change to the OBLIG-PBT-4 design surface in §11 itself: `:subject f` / `:subjects [f g]` opt-in metadata, head-position scan bypassed when annotated, freeze-compliant per Q-PROF-1.

**Engineer-time-pressure fallback (professor 2026-05-14).** If engineer-time forces serialization of the OBLIG-PBT-4 + OBLIG-PBT-5 bundle, ship **OBLIG-PBT-5 first** (the body-evaluator fix is the more mechanism-discriminating signal — a re-run showing `samples_run > 0` on c02/c03 distinguishes "the body evaluator was the blocker" from "something deeper is the blocker"), followed by **OBLIG-PBT-4 immediately after**. Drift-protection is explicit: OBLIG-PBT-4 must not slip to a later milestone, because OBLIG-PBT-5 alone leaves the strong-form H1-Assurance question unresolved — c01-shape problems would continue to fail the multi-callee guard at saturation.

### 11.1 Lift semantics for `:subjects [f g]` — pinned 2026-05-14 (professor Q2 closure)

OBLIG-PBT-4 ships `:subject f` / `:subjects [f₁ … fₖ]` (k ≥ 1) keyword metadata on `(check ...)` blocks. The lift semantics, left undefined in §11's deferral framing and surfaced as an open question by the professor's path-1 review (Q2, 2026-05-14), is pinned as **per-subject `DLTested n` lifts under explicit-annotation opt-in, with shared `pbt_witnesses` cross-linking**. The single-subject case (`:subject f`) is sugar for `:subjects [f]`; the runtime has one code path.

**Inference rule:**

```
              (SCheck p) ∈ Σ
              subjects(p) = {f₁, …, fₖ}   (k ≥ 1, explicit annotation)
              status(p) = PBTPassed
              evaluatedSamples(p) = n
              ∀i. SDefLogic fᵢ _ _ cᵢ _ ∈ Σ ∪ importedExposed(Σ)
              ∀i. contractPost cᵢ = Just _
              hash(propBody p) = h
            ──────────────────────────────────────────────────────
            ∀i. csPost(fᵢ) ⊑ DLTested n   with   pbt_witnesses ∋ {h, desc(p)}
```

Every `fᵢ` receives its own `DLTested n` evidence record on `csPost`; all `k` records share the same `pbt_witnesses` entry `(h, desc(p))`. The lift remains lattice-respecting monotonic upgrade per `Module.mergeCS` (existing semantics; no change). The Pacheco-Lahiri-Ernst overallocation objection that grounded the original singleton-fallback conservativism (§3) is mitigated structurally: **explicit annotation is the agent's consent to joint-evidence allocation**. The unannotated multi-callee diagnostic at `PBT.hs:671-676` continues to refuse implicit lift; `:subjects` opts in. This matches the JML `@testing` convention's per-method credit under explicit-subject annotation — one of the two routes in the literature split the professor cited.

**Why not a single conjoint record.** The alternative — one `DLJointTested [Name] n` record (or a `subjects: [Name]` field on `DLTested`) — is more soundness-honest (one observation, one record) but pays a schema cost: `EvidenceRecord` reshape; `mergeCS` / `mergePbtWriteback` update; `trust_report_version` bump 1.1.0 → 1.2.0; `VerifiedCache.hs:40-41` deserialization extension with back-compat shim; and an unprincipled aggregation decision in `aggregateTiers` (does a joint record for k=2 subjects count as 1 `tested` clause-entry or 2?). The per-subject route preserves the auditability the conjoint reading was protecting: a reviewer inspecting `f.post.pbt_witnesses` and `g.post.pbt_witnesses` detects the shared hash `h` and infers joint evidence without a schema change. The 1.2.0 bump is avoided — the experiment-lead's harness `Cred(R)` consumer at the v0.10.6 boundary does not couple with a schema bump at Phase-3 launch, which is the brittle coupling the conjoint route would have introduced.

**Edge cases (S1–S9):**

| # | Input shape | Behavior | Channel | Citation |
|---|---|---|---|---|
| S1 | `:subject f` on `(check p)` with singleton head-position `{f}` | Identical to inferred-singleton; one `DLTested n` on `f.post` | trust | §3 |
| S2 | `:subjects [f g]` with `PBTPassed`, both contracted | Two `DLTested n` records, one on `f.post`, one on `g.post`; shared `pbt_witnesses` hash | trust | §11.1 inference rule |
| S3 | `:subjects [f g]` but `f` has `contractPost = Nothing` | Lift `g.post` only; emit informational diagnostic on `f` ("declared subject has no postcondition; no slot to lift"); no failure | trust | §4 side condition 1 |
| S4 | `:subjects [f]` (one-element list) with multi-callee head-set `{f, g}` | The annotation overrides the head-position scan; lift `f.post` only; `g` does not receive credit | trust | §11.1 — explicit annotation authoritative over inferred head-set |
| S5 | `:subjects [f g]` but the property body mentions neither | Both `f.post` and `g.post` receive `DLTested n` per the annotation; the annotation does not require body-mention | trust / weakness | §11.1 — declarative; declared-subject-not-mentioned-in-body is a weakness-channel item, candidate OBLIG-PBT-6 |
| S6 | `:subjects []` (empty list) | Treat as malformed `(check ...)`; emit parse-time diagnostic; no lift | parser | parser-slot |
| S7 | `:subjects [f f]` (duplicate) | Deduplicate to `{f}`; lift `f.post` once | trust | proposal-internal normalization |
| S8 | `:subjects [f g]` cross-module (`f` local, `g` imported via `(open …)`) | Both lift; qualified-name resolution from `assembleTestStatements` applies independently per subject | trust | §4 side condition 1 |
| S9 | Two `(check ...)` blocks with overlapping `:subjects [f]` and `:subjects [f g]`, both `PBTPassed` | `mergePbtWriteback` joins per existing semantics (max on `DLTested n` sample counts; union of `pbt_witnesses` deduplicated by hash) | trust | §6 (unchanged) |

**Risks.** Annotation-declarative-vs-body-mention divergence (S5) is small under OBLIG-PBT-4 alone, medium if an agent learns to game it by declaring `:subjects [f g]` on a body that exercises only `f`; a weakness-channel rule that flags declared-subject-not-mentioned-in-body is a clean follow-on (candidate OBLIG-PBT-6) but does not gate OBLIG-PBT-4 ship. Pacheco-Lahiri-Ernst overallocation under joint-witness on metamorphic-relation properties is mitigated by the consent-via-annotation reading; `DLTested n` is a probabilistic-evidence display level (`LLMLL.md §4.4.1:347` epistemic-status note), not a logical count. The JML / EvoSuite literature split is resolved in favor of the JML `@testing`-per-method route on schema-cost grounds.

**State-machine command-sequence surface (design horizon, v0.12+).** If LLMLL adds an `eqc_statem`-style command-sequence surface in v0.12+, the joint-evidence-via-command-sequence route becomes available, and `:subjects` could be retired for that surface. Recorded as a design-horizon footnote; not actionable now.

**Compiler-surface delta (on top of OBLIG-PBT-3).** `PBT.hs:pbtTrustWriteback` extends with `:subjects` annotation lookup, folding over the subject list to emit per-subject `csPost` entries with shared-hash cross-link. `Syntax.hs:SCheck` carries optional `checkSubjects :: [Name]` field (default `[]`); parser populates from `:subjects` keyword arg. **Schema delta is additive-optional, AST schema only (corrected 2026-05-14 post-engineer-implementation):** `expectedSchemaVersion` bumps `"0.4.0"` → `"0.5.0"` — the new optional `CheckDecl.subjects` field on a `"additionalProperties": false` shape requires the SemVer-minor bump for strict-validator consumers. `trust_report_version` stays `"1.1.0"` (unchanged — the per-subject lift route does not modify `EvidenceRecord` shape, only emits more entries). The original "no schema delta" commitment was authored on the assumption that the JSON-AST schema is tolerant of additive keyword fields; that assumption was false under the actual schema's strict-`additionalProperties` invariant. This correction does not alter the design — per-subject lifts under explicit-annotation opt-in still hold, the conjoint-record rejection on harness-coupling grounds still holds — but documents the AST schema bump the engineer correctly applied during implementation. `VerifiedCache.hs:40-41` unchanged — `DLTested n` record shape unchanged; `pbt_witnesses` already serialized per OBLIG-PBT-3 §6. Test surface: new OBLIG-PBT-4 `:subjects` describe block in `compiler/test/Spec.hs` covering S1–S9.

---

## 12. Edge cases and degenerate inputs

| # | Input shape | Behavior | Channel | Citation |
|---|---|---|---|---|
| E1 | Property body mentions no `def-logic`/`letrec` (operators only) | `HEAD-contracted` empty; no lift | trust | §3 |
| E2 | Same function in multiple head-positions in one body | Subject set is a `Set Name`; lift once | trust | §3 |
| E3 | Multi-subject property (e.g., `(= x (decrypt (encrypt x)))`) | `HEAD-contracted` ≥ 2; no lift; informational diagnostic | trust | §3 |
| E4 | Subject has `contractPost = Nothing` | No slot to lift | trust | §4 premise |
| E5 | Function with pre asserted, post lifted to tested | `tier_profile.asserted` increments (per-function meet); `tier_profile_post.tested` increments (per-clause split) | trust | §9 |
| E6 | Function already at `DLVerified` from prior verify | `mergeCS` preserves `DLVerified`; lift is monotonic non-degrading | trust | `Syntax.hs:362-371` |
| E7 | Property skipped (QC-discard saturation, c02/c03 mechanism) | `PBTSkipped`; no lift | trust | §4 side condition 3 |
| E8 | Cross-module: local check covers imported function | Sidecar entry written under qualified name `lib.f` in importing-file sidecar | trust | §8 |
| E9 | Local name shadows imported name | `assembleTestStatements` right-bias picks local; subject is local | trust | `PBT.hs:131-133` |
| E10 | Idempotent re-run | `mergeCS` on `(DLTested n, DLTested n)` is `DLTested n`; `pbt_witnesses` deduplicated by hash | trust | §6 |
| E11 | Mixed pass/skip on same function | Only `PBTPassed` properties contribute hashes and counts | trust | §4 side condition 3 |
| E12 | Mixed pass/fail on same function | Passing property lifts; failing property surfaces as diagnostic; no veto | trust | §4 side condition 2 |
| E13 | Property body edited between runs | Hash mismatch on read → downgrade to `DLAsserted`; next `llmll test` re-lifts with new hash | trust | §7 |
| E14 | Property deleted between runs | No live hash matches → downgrade to `DLAsserted`; cache does not leak | trust | §7 |
| E15 | `trust_report_version: 1.0.0` consumer reads `1.1.0` emit | New fields ignored; scalar `tier_profile` unchanged in shape | trust / consumer-compatibility | §9 |

---

## 13. Verification mapping

OBLIG-PBT-3 introduces **no new proof obligations**. The PBT-to-trust pipeline is empirical evidence recording, not verification. No SMT VCs are emitted. No Lean obligations are generated. The verifier's constraint set under `llmll verify` is unchanged.

| Obligation introduced | Channel | Fragment | Cite |
|---|---|---|---|
| (none — empirical evidence only) | trust | N/A (statistical, not logical) | `LLMLL.md §4.4.1:347` epistemic-status note |

**Strict-immutability invariant preserved.** Sidecar writes are pure functional rewrites of a merged `Map.unionWith mergeCS` of loaded + computed maps. PBT runs in `IO` but the effect is sealed at the existing `loadVerified` / `saveVerified` boundary (`VerifiedCache.hs:130-153`). No aliasing.

---

## 14. Affected surface

| Artifact | Change | Owner |
|---|---|---|
| `LLMLL.md §4.4.1` | Tighten `tested` "When assigned" line; add design-divergence paragraph (§10) | doc-lead |
| `LLMLL.md §4.4.4` | Sidecar invariant statement (§8); per-clause aggregate description (§9); `pbt_witnesses` mechanic | doc-lead |
| `LLMLL.md §4.4.5` (new subsection) | New subsection "PBT-derived trust evidence" hosting the `PBT-Lift` inference rule (§4) and its side conditions. Slots between §4.4.4 and §4.5. | doc-lead |
| `LLMLL.md §5.1` | Tighten outcome table for singleton-head-position linkage; `evaluatedSamples` semantics disclosure (§5); cross-reference §4.4.5 for the formal lift rule | doc-lead |
| `compiler/src/LLMLL/PBT.hs` | `headContractedSubject :: [Statement] -> Expr -> Maybe Name`; `pbtTrustWriteback :: [Statement] -> PBTResult -> Map Name ContractStatus` | engineer |
| `compiler/app/Main.hs` `doTest` | After `runPropertyTests`: load `.verified.json`, build PBT-derived map, `Map.unionWith mergeCS`, save. `max` over multi-property coverage | engineer |
| `compiler/src/LLMLL/TrustReport.hs` | `aggregateTiers` extended to emit three TierProfiles; `pbt_witnesses` validated on read; `trustReportEmitVersion` bumps to `1.1.0` | engineer |
| `compiler/src/LLMLL/VerifiedCache.hs` | `erToJSON`/`erFromJSON` extended with optional `pbt_witnesses` field; back-compatible | engineer |
| `compiler/src/LLMLL/Syntax.hs` | Optional: extend `EvidenceRecord` with `erPbtWitnesses :: [PbtWitness]`; or carry inside `erSource` as structured JSON. Engineer chooses. | engineer |
| `docs/llmll-ast.schema.json` | **No change.** | — |
| `docs/llmll-trust-report.schema.json` | Bump to `1.1.0`; document new fields | doc-lead |
| `docs/compiler-team-roadmap.md` row 165 | OBLIG-PBT-3 close-out (☐ → ☑) | doc-lead |
| `docs/compiler-team-roadmap.md` new row | OBLIG-PBT-4: `:subject` metadata + coverage-instrumented `evaluatedSamples` | doc-lead |
| `CHANGELOG.md` v0.10.5 entry | Extend the existing "Unreleased" block with OBLIG-PBT-3 content; replace F-033 Known Limitation with "Closed by OBLIG-PBT-3" | doc-lead |
| `compiler/test/Spec.hs` | New `OBLIG-PBT-3` describe block: E2, E3, E5, E6, E8, E10, E12, E13, E14, E15 | engineer |

---

## 15. Risks

1. **Engineer-side hashing primitive choice.** `pbt_witnesses` hash strategy is engineer-slot. *Bite:* small; either piggyback on `ctVerifiedHash` or use a fresh SHA-256 path.
2. **PBTError provenance.** `PBTError` runs do not appear in `pbt_witnesses`. Spec must state this explicitly. *Bite:* small; documentation clarity.
3. **Cross-module hash collection.** `pbt_witnesses` may reference property bodies in modules other than the one whose sidecar holds the entry. Read-side validation must walk imported modules' `(check)` blocks via the existing `ModuleCache` traversal. *Bite:* small; reuses existing trust-closure traversal.
4. **Concurrent sidecar writes** (`llmll test` and `llmll verify` racing). LLMLL has no concurrent compile model; rely on filesystem atomic-write conventions (write to temp + rename). Engineer slot. *Bite:* small.
5. **`tier_profile` v1.0.0 consumers ignore new fields.** Existing harness `Cred(R)` predicate (v0.10.4) reads scalar `tier_profile`; needs update to consume `tier_profile_post` for the OBLIG-PBT-3 signal to enter the H1-Assurance discriminator. *Bite:* experiment-lead slot; couples but does not gate v0.10.5 ship.

Soundness, decidability, strict-immutability, and freeze-policy risks all close cleanly under §3 – §11.

---

## 16. Cross-references

- **Postmortem trail:** `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 16 (F-033 surface; LT-B re-probe routing)
- **Roadmap row:** `docs/compiler-team-roadmap.md` row 165
- **Professor review:** [`oblig-pbt-3-review.md`](../professor-reviews/oblig-pbt-3-review.md)
- **Prior PBT roadmap rows:** OBLIG-PBT-2 (row 164, shipped), MOD-PBT-1 (row 163, shipped)
- **Phase-3 framework:** `docs/design/language-comparison-experiments.md` §Soundness Assessment (R6d operationalization at line 37)
- **Sibling design constraints:** v0.8.1b evidence model (`docs/archive/shipped-design-specs/`), R6d trust-report tier profile (v0.10.4 CHANGELOG)

---

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal has been folded into this appendix and the source file archived to `docs/archive/professor-reviews/oblig-pbt-3-review.md`. One line per finding; all resolved in Rev 2 of this proposal.

**Source:** `docs/design/oblig-pbt-3-review.md` at commit `fb236c9b2aadbeea6e170ec447c13f12700e97d6` (review dated 2026-05-13; reviewer: Lead Consultant for Formal Language Design).

### Gaps (all resolved in Rev 2)

1. **`DLTested n` carries a misleading sample count under QuickCheck-discard semantics.** Rev 1's `n = numTests` ignores `qcSamples` discards under `==>`. Resolved: Rev 2 §6 makes `evaluatedSamples` explicit and distinguishes from `numTests`.
2. **Body-name-broadcast over-credits multi-subject properties.** Rev 1 lifted `DLTested` onto every named function in head-position. Resolved: Rev 2 §3 narrows the linkage rule to *singleton head-position* and sequences `:subject` metadata to OBLIG-PBT-4.
3. **Sidecar invariant change is not as invisible as Rev 1 claims.** `tier_profile` shape change breaks v1.0.0 consumers. Resolved: Rev 2 §4 bumps `trust_report_version` 1.0.0 → 1.1.0 and documents the migration.
4. **The aggregate-pin is created by OBLIG-PBT-3, not merely exposed.** Rev 1 framed the `effectiveLevel = meet(pre, post)` aggregate-pin as pre-existing. Resolved: Rev 2 §5 introduces per-clause `tier_profile_pre`/`tier_profile_post` so PBT signal is not pinned by `pre`'s assertion-status.
5. **`min`-over-coverage is the wrong reduction within a single evidence channel.** Cross-channel meet ≠ within-channel join. Resolved: Rev 2 §7 specifies the within-channel reduction as max-coverage / first-seen-hash, not the diamond `evidenceMeet`.
6. **Property staleness is not deferrable.** Rev 1 deferred body-hash to a future extension. Resolved: Rev 2 §8 adds SHA-256 property-body provenance with read-side staleness downgrade in this release.
7. **The proposal does not consult Liquid Haskell on the philosophical point.** Resolved: Rev 2 §11 adds an explicit design-divergence statement vs Liquid Haskell (LH has no QC-to-refinement-display channel; LLMLL's choice is deliberate).

### Open questions (both resolved in Rev 2)

- **Q-PROF-1.** Justify rejection of `:subject` keyword on `(check ...)` blocks under feature-freeze. Resolved: Rev 2 §10 sequences `:subject` to OBLIG-PBT-4, with the rationale that under-freeze additive emit (singleton head-position) is sound and freeze-compliant; `:subject` enables joint-multi-subject lifts that require an evaluation-coverage primitive.
- **Q-PROF-2.** Specify how `DLTested n` is to be interpreted under implication-shape properties. Resolved: Rev 2 §6 ties `evaluatedSamples` to QuickCheck's discard accounting and notes that implication-shape properties may evaluate `< qcSamples` of their domain.

### Overall assessment (recorded)

The review's overall assessment recommends approval for compiler-engineer hand-off subject to Rev 2 resolution of all seven gaps. Rev 2 (settled 2026-05-13) carries each resolution inline at the cited §-references above.
