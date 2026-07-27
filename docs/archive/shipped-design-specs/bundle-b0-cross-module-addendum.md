# Bundle B0 — Cross-Module Effect-Summary Propagation (Addendum)

> **Version:** Rev 1 — settled across a professor ↔ language-team loop (2026-06-15).
> **Date:** 2026-06-15
> **Status:** Settled (Rev 1) — **SHIPPED** `85d2a7d` (build, 851→855 tests) / `6215add` (docs: CHANGELOG `## Unreleased` + `LLMLL.md` §11.2 effect-summary note).
> **Extends:** [`bundle-b0-effect-summary-proposal.md`](bundle-b0-effect-summary-proposal.md) (Rev 2, shipped `b2d9c1a`). This addendum does **not** reopen that proposal; it records the cross-module extension and supersedes the B0-experiment-gates-B1 framing in that proposal's frontmatter (lines 7, 9) and in [`v0.12-direction.md §3`](v0.12-direction.md) (B1 row, "B0 empirical instrument" paragraph).
> **Origin:** experiment-lead finding **F-B0-3** ([`experiments/minimal-agent/findings/postmortem-007-b0-pilot.md`](../../../experiments/minimal-agent/findings/postmortem-007-b0-pilot.md)) — the shipped single-file B0 summary under-reports across module imports, and is informationally redundant where capabilities are syntactically evident.
> **Reviewed:** Professor (2026-06-15, in-conversation) — soundness verdict on the propagation invariant + the B1 forward-record; convergence named below.

---

## 1. Background

B0 (Rev 2) shipped a per-function `effect_summary`: a sound **may-over-approximation** of the coarse capabilities (`Σ_eff = {stdout, fs.read, fs.write, net.http, random, crypto}`) a function may reach through its call graph, with a genuine top **⊤** (`"unbounded"`) at opaque boundaries. As shipped, `computeEffectSummary` ([`ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs)) walked the **flattened single-file** statement list only: an imported callee was absent from the call graph, defaulted to `∅`, and its effects were **silently dropped** — an unsound under-report for any multi-module program (the report even stamped a hardcoded `cross_module: "unsupported"`).

F-B0-3 surfaced this while attempting to give the B0 experiment discriminating power, and established the deeper point: in single-file LLMLL every capability is **syntactically evident** (namespaced `wasi.*`), so the summary carries non-trivial information only at **opaque boundaries** — cross-module imports, `?delegate`/`?scaffold` holes, FFI. Cross-module imports were the one opaque boundary B0 dropped to `∅` instead of composing.

## 2. The settled extension

**Cross-module composition.** `computeEffectSummary` now folds the loaded `ModuleCache`'s imported statements into its call-graph fixpoint, so an imported function's reachable capabilities propagate into its caller's summary via the existing lattice join. Implemented as the **combined-statements** variant (the imported `meStatements`, already in `ModuleEnv`, are walked alongside the local statements); **no `meEffects` field was added to `ModuleEnv`** — that would have created an `EffectSummary`/`Syntax.hs` import cycle, and the combined-statements form is equivalent and cheaper to land. Output is restricted to the local module's functions; imported defs are folded in solely to resolve cross-module callees.

**The `∅`-iff-fully-walked invariant (soundness-critical; professor Hazard 1).** The lattice ⊥ (`Caps ∅`) is emitted for a function **only when its entire transitive call graph was actually walked** within the loaded cache. Every other terminus joins **⊤**: an unresolved import, a resolved-but-unsummarized callee, and (should re-export of imported names ever be added) a re-export-to-unknown. A callee contributes `∅` only if it is a resolved function (local or imported), a known builtin/declared constructor, or a `primEffect`-recognized primitive (whose effect is already folded into the caller's own effects). **cross-module-unresolved is simply a new member of the opaque-boundary set** alongside `?delegate`/`?scaffold`/FFI — never silently `∅`. The `cross_module` report field is now computed (`"single-file"` | `"supported"`), replacing the hardcoded `"unsupported"`.

**Memoization soundness.** Composition over per-module summaries is the standard summary-based interprocedural analysis (Sharir–Pnueli 1981; Cousot–Cousot modular abstract interpretation): joining sound per-procedure summaries is sound for any monotone join-semilattice, which `L = 2^Σ_eff ∪ {⊤}` is. Bottom-up (post-order) summary computation is well-defined because circular imports are rejected at load ([`Module.hs:120-154`](../../compiler/src/LLMLL/Module.hs)); the effect walk runs only after a successful load.

**Representation.** The summary stays the coarse `Σ_eff` union (`EffectSummary = Caps (Set EffectLabel) | Unbounded`). This same representation serves both the B0 report **and** B1 *monomorphic* rows (a closed `Command {fs.read} a` row is a `Σ_eff` subset — identical shape). Only **B2** (row-polymorphic `{ρ}`, v0.13+) needs a richer representation; nothing is built twice.

## 3. Professor ↔ language-team convergence

The professor (reaching outward — Koka row-effects, Frank abilities, Lucassen–Gifford effect discipline: effects belong **in the type**, visible at the call site without reading the body) and the language-team (reaching inward — `v0.12-direction.md §3` already sites B1's effects in signatures, and F-B0-3 shows B0-the-report is redundant where capabilities are evident) reached the same conclusion from opposite paths: **agent-facing "effect-at-import" belongs at B1's locus (the type), not at a side-channel report.** Convergence across surfaces is signal.

Consequently, cross-module propagation is justified **independently of the B0 experiment**: (a) it is a soundness fix to the shipped multi-module report; (b) it is a **B1 prerequisite** (B1's per-module check needs cross-module effect composition). It was built on those merits; the B0 experiment did not gate it.

## 4. B1 forward-record (not built; feeds the B1 LT proposal)

Recorded here so the B1 LT proposal need not re-derive it:

- **Closed monomorphic rows, pinned.** B1 rows are closed (`{stdout, fs.read}`, no tail). This is a deliberate divergence from the Koka/Frank **open-by-default** convention (Leijen, *Scoped Labels* 2005): a row tail relocates the check from finite-set containment into row unification, which is B2 territory. Pin closed rows in the B1 proposal explicitly.
- **`declared ⊇ inferred` = finite-set containment**, a decidable **type-channel** check strictly below QF-LIA (no arithmetic). The cross-module **inferred** summary (this addendum) is B1's per-module checker for un-annotated and annotated bodies; at import sites an *annotated* callee resolves via its declared row, an *un-annotated* one via the inferred summary (Lucassen–Gifford / Koka modularity).
- **No escape hatch.** A B1 closed row is **unavailable** on a function that reaches ⊤ (a `?delegate`/`?scaffold` hole or FFI): `declared ⊇ ⊤` is false for any closed row, so the type checker rejects the annotation. **The refusal is the soundness property** — a bounded effect row on a body that may exercise any capability would be unsound. Recourse: leave it un-annotated (inferred ⊤ in the report) or do not reach the opaque boundary.
- **Professor's "case-4" is a non-issue.** An *unresolved import* cannot reach the B1 check: a missing module fails at load ([`Module.hs`](../../compiler/src/LLMLL/Module.hs) `Left`-on-missing) and an unbound cross-module name fails strict typecheck (`ModuleSpec` M-02). B1 runs only on loaded, typechecked programs, where every callee resolves; ⊤ enters only via the genuine opaque boundaries above.

## 5. F-B0-3 closure (partial)

The **compiler-engineer half** of F-B0-3 — cross-module `effect_summary` propagation — is **closed**: shipped `85d2a7d`, documented `6215add`. F-B0-3's **experiment** remains gated on the separate **Hub-interface opacity layer** (a Hub-fetched interface publishes a signature + effect summary with the body absent; only that makes a non-telegraphing-yet-counted capability temptation constructible — a local imported `.llmll` is readable by the agent, so it telegraphs). That layer is a distinct, larger effort, not pursued here.

> The F-B0-3 entries in `postmortem-007-b0-pilot.md` and `findings.md` (`## Experiment-lead`) are experiment-lead's surface — a closure-line update there citing `85d2a7d` is **owed to experiment-lead**, not made by the language-team.

## 6. Verification mapping

- **Cross-module propagation (shipped):** introduces **no proof obligation**. It is an abstract-interpretation summary over a finite lattice — informational, never entering the trust meet, `EvidenceRecord`, or verified-core admissibility (the B0 trust-orthogonality invariant, `LLMLL.md §5.3.3` boundary). No QF-LIA / nonlinear / Lean classification applies; single-file summaries are byte-identical to pre-change.
- **B1 check (forward-record, not built):** `declared ⊇ inferred` over closed `Σ_eff` rows = finite-set containment — a decidable **type-channel** check below QF-LIA. Closed rows are what keep it finite; open rows (B2) would escape to unification.

## 7. Affected surface (shipped `85d2a7d`)

- [`compiler/src/LLMLL/ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs) — `computeEffectSummary :: ModuleCache -> [Statement] -> …` (cache-threaded fixpoint, `∅`-iff-fully-walked `calleeEff`, local-only output); `assembleReport` consumes the cache and computes `orCrossModule`.
- [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs) — CM-1..4 (propagation, transitive-opaque→⊤, single-file identity, unresolved→⊤); `ModuleSpec` M-06 pins cyclic-import rejection.
- Docs (doc-lead, `6215add`): `CHANGELOG.md` `## Unreleased`; `LLMLL.md` §11.2 effect-summary note.
- **Owed to doc-lead:** an `INDEX.md` one-liner for this addendum (INDEX status labels are doc-lead's slot).

## 8. Risks and open questions

1. **B1-gate retirement (research-track drift, resolved here).** `v0.12-direction.md §3` gated the B1 engineer build on a B0 experiment F-B0-3 showed is unmeasurable single-file. Retired in this revision; replaced with a B1-native gate (does an effect-typed *signature* improve capability-correct composition, measured against the design-reference set — Liquid Haskell `.spec` / F\* effect interfaces). The B1 LT proposal proceeds independently.
2. **Open-row creep (decidability, B1-time).** The closed-row pin must be explicit in the B1 proposal; an open-row convenience would silently relocate the check out of the finite-containment fragment (Leijen 2005).
3. **`meEffects` not anticipating B2 (scope, v0.13+).** The coarse `Σ_eff` union is right for B0 + B1-monomorphic; B2 row-polymorphism will need a richer representation. Flag so B2 does not silently inherit a too-coarse rep.
