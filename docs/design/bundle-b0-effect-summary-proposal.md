# Bundle B0 — Per-Function Effect/Authority Summary (4th Informational Obligation-Report Channel)

> **Version:** Rev 2 — professor review folded (the summary is recast from a must-lower-bound to a sound **may-over-approximation** with a genuine top **⊤** at opaque boundaries; object-capability + may/must anchors; the no-trust orthogonality affirmed). Rev 1 (2026-06-14) framed the summary as a reachable-capabilities lower bound with an advisory `effect_summary_complete` flag.
> **Date:** 2026-06-14 (Rev 1; Rev 2)
> **Implements:** `docs/compiler-team-roadmap.md` Bundle B track, stage **B0**; [`docs/design/v0.12-direction.md §3`](v0.12-direction.md) (the settled B0 spec: catalog, transitive inference, informational, coarse-labels guardrail).
> **Prerequisites:** None new — derives from the existing capability-import surface (`SImport` / `Capability`, [`Syntax.hs:649-673`](../../compiler/src/LLMLL/Syntax.hs)) and the obligation-report machinery ([`ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs)). Orthogonal to the REF-META track.
> **Origin:** v0.12 Bundle B stage 0 (memo §3). B0's empirical result (`experiments/minimal-agent/001-two-agent-auth`) is the authorization gate for the **B1 engineer build** (not the B1 LT proposal).
> **Reviewed:** Professor review (2026-06-14, in-conversation) — recommendation `revise-and-resubmit` (one substantive semantic fix; the rest affirmed). Folded into this Rev 2 (see `## Appendix — Professor review log`). No standalone `-review.md`; folded directly per the REF-META-1/3/4/5 appendix pattern.
> **Status:** Settled (Rev 2) — professor review folded; **code-track** (implies a compiler-engineer build: the ⊤-lattice closure, the union-encoded report field, the no-trust-wiring test). Pending compiler-engineer plan, then experiment-lead B0 experiment, then documentation-lead.

---

## 1. Motivation

Per `docs/design/v0.12-direction.md §3`, Bundle B0 surfaces a **per-function effect summary** — the coarse capabilities reachable through a function's call graph — as a 4th channel in the obligation report, alongside the existing type / contract / trust channels ([`ObligationAssembly.hs:819-821`](../../compiler/src/LLMLL/ObligationAssembly.hs)). It is **informational** to the compiler: it does not gate trust or verification. The B0 experiment measures whether surfacing the summary improves agent **capability-correctness**.

That measured purpose makes the summary's *approximation direction* load-bearing. Capability-correctness — "is it safe to call `f` where capability `c` is forbidden?" — is a **may** question: it needs an *upper* bound on what `f` can do ("`f` exercises **at most** these capabilities"). A *lower* bound ("`f` reaches at least these, maybe more") is unsound for that question: `eff(f) = {fs.read}` read as a lower bound does not license "`f` does not touch the network." B0 is therefore an **authority summary** in the object-capability sense (Miller, *Robust Composition*, 2006): a function's authority is the set of capabilities transitively reachable from it, and a component whose effects the analysis cannot see carries full ambient authority — the lattice top **⊤**. This is a sound **may-over-approximation** (Nielson–Nielson–Hankin, *Principles of Program Analysis*; Lucassen–Gifford, *Polymorphic Effect Systems*, POPL 1988), not the must-lower-bound of Rev 1.

The summary is informational to the *compiler's* trust lattice yet **sound for the *agent* consumer** — two consumers, two contracts (§4.3). The row-polymorphic-effects literature (Koka, Frank, Leijen) anchors B1+ (annotated `Command {ρ} a` rows), not B0's coarse summary sets.

## 2. Scope

**In scope.** The per-function authority summary as a may-over-approximation over the closed coarse catalog `Σ_eff`; the ⊤ top for opaque boundaries; the transitive least-fixpoint over the call graph; the report-channel surface and its schema delta; the no-trust-tier-effect boundary.

**Out of scope.** Capability *enforcement* (the existing `checkWasiCapability` per-call gate, [`TypeCheck.hs:867`](../../compiler/src/LLMLL/TypeCheck.hs), is enforcement; B0 is summary — see §4.3 *sidesteps*). Value-indexed capability paths (`fs.read "/data"`) — the import-declaration mechanism's slot; B0 stays coarse (memo §3 guardrail). Annotated effect rows (B1), row-polymorphic inference (B2), effect-aware contracts (B3). No new surface, no new builtin, no JSON-AST schema change.

## 3. Surface

**None.** B0 is report-surface inference over existing capability declarations + body inspection — no S-expression or JSON-AST change. (Annotated `Command {stdout, fs.read} a` rows are B1.)

## 4. Semantics

### 4.1 The authority lattice

The closed coarse catalog is `Σ_eff = {stdout, fs.read, fs.write, net.http, random, crypto}` (memo §3), each label the inversion of a `wasi.*` capability namespace or effectful builtin (`wasi.filesystem` → `fs.read`/`fs.write`; `wasi.cli`/Command stdout → `stdout`; `wasi.sockets`/`wasi.http` → `net.http`; `random-int` → `random`; crypto stubs §13.11 → `crypto`).

The summary lattice is `L = (2^Σ_eff ∪ {⊤}, ⊑)`: the powerset ordered by `⊆`, with a **fresh top ⊤ adjoined above the full 6-set**. `⊤ ⊐ {all six labels}`. The full 6-set means "may exercise at most these six *known* capabilities"; **⊤ means "may exercise any capability — including capabilities outside `Σ_eff`."** ⊤ and the 6-element set are distinct (this distinctness is load-bearing — §7, Risk 4).

### 4.2 The inference (may-over-approximation, least fixpoint)

```
  eff(f)  =  own(f)  ⊔  ⊔_{g ∈ calls(f)} eff(g)        ( ⊔ = ∪ ;  x ⊔ ⊤ = ⊤ )
```

- **`own(f) = ⊤`** if `f`'s body directly contains an **opaque effect** — a `?delegate` / `?delegate-async` / `?scaffold` hole (out-of-process agent, §3.4.3), a `haskell.*` / `c.*` FFI call (sealed at the builtin boundary), or any namespace outside the `Σ_eff` map. Opaque callees' effects are genuinely unanalyzable, so the sound may-bound past them is ⊤. Otherwise `own(f)` is the set of catalog labels for `f`'s direct `wasi.*` / effectful-builtin calls.
- **Join, not drop.** If any callee is ⊤, the caller is ⊤ (`x ⊔ ⊤ = ⊤`) — an opaque callee makes the caller's authority unbounded, rather than silently dropping the unseen effects (the Rev 1 error).
- **Least fixpoint over SCCs** (recursive / mutually-recursive functions): terminates — `L` is finite (`2^6 + 1` elements).
- **Reading.** `eff(f) = S ⊆ Σ_eff` ⟺ "`f` exercises **at most** `S`"; `eff(f) = ⊤` ⟺ "`f` may exercise any capability"; `eff(f) = ∅` ⟺ "`f` is capability-free" (a sound, strong guarantee). Reachability over-approximates execution (a `wasi.*` call under a never-taken branch still counts) — the correct, cheap may-bound. No path-sensitivity (no soundness gain, real cost).

### 4.3 The two-consumer soundness boundary

- **To the compiler — informational.** `eff` does **not** enter the trust meet (§4.4 lattice), the `EvidenceRecord`, or `verified` / `--strict-verified-core` admissibility, and does not change any verification verdict. Authority ⊥ trust (object-capability): a `verified` function may have `eff = ⊤` (it calls a delegate); a capability-free function (`eff = ∅`) may be `asserted`.
- **To the agent — a sound may-bound.** The agent uses `eff` for capability-correctness: "safe to call `f` where `net.http` is forbidden" ⟺ `net.http ∉ eff(f) ∧ eff(f) ≠ ⊤`. Soundness here is exactly what the B0 experiment measures.

These are *different consumers with different contracts*; the summary serves both only as a sound may-bound that is excluded from the compiler's trust lattice. "Not trust-gating" (true) is orthogonal to "sound for the agent" (also required) — Rev 1 conflated them.

**Tracked-concept relation.** B0 **sidesteps** capability *enforcement* (the existing `checkWasiCapability` per-call gate, [`TypeCheck.hs:867`](../../compiler/src/LLMLL/TypeCheck.hs) — B0 summarizes, it does not gate); **anticipates** B1/B2/B3 (memo §3); is **orthogonal** to the trust lattice. The 4th channel is descriptive — it carries no obligation to discharge, unlike the three obligation-bearing channels.

## 5. Edge cases and degenerate inputs

1. **Pure function.** `own = ∅`, no effectful callees → `eff = ∅` = "exercises no capabilities" (sound, strong). *Channel:* effect (4th). *Cite:* §4.2 reading.
2. **Effect only via a transitive callee** (`f` calls `g`, `g` reads fs). `eff(f) = ∅ ⊔ {fs.read} = {fs.read}` — "at most fs.read." *Channel:* effect. *Cite:* join over `calls(f)`.
3. **Function reaching a `?delegate` hole.** `own(f) = ⊤` → `eff(f) = ⊤` (`"unbounded"`). The agent reads ⊤ as "not capability-bounded — unsafe to assume." Not `{} + flag`. *Channel:* effect (+ trust: the delegate is already `asserted`-tier). *Cite:* §3.4.3 carve-out; Miller 2006 (opaque component = ambient authority).
4. **Recursive / mutual SCC.** Least fixpoint over finite `L`; terminates; SCC members share the join. *Channel:* effect. *Cite:* §4.2.
5. **FFI / out-of-catalog namespace.** Opaque effect → `own(f) = ⊤`. The catalog stays closed at six; the escape is ⊤, not a new label. *Channel:* effect. *Cite:* §4.1.

## 6. Verification mapping

B0 introduces **no proof obligation and no SMT obligation**. The summary is a **decidable least-fixpoint over a finite lattice** (`2^6 + 1`), non-SMT, reported in the informational (4th) channel — the same computational status as the §3.4.4 well-formedness check, not an auto-discharge obligation.

| Item | Channel | Fragment | Cite |
|---|---|---|---|
| `eff(f)` computation (finite-lattice least fixpoint) | informational (4th, report) | Decidable, non-SMT | `v0.12-direction.md §3`; [`ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs) |
| Trust / verification interaction | — | **None** — orthogonal by construction (no trust-meet, no `EvidenceRecord`, no SMT) | §4.3; §4.4; §5.3.4 |

## 7. Schema delta

- **Report, not AST.** Per-function `effect_summary` in the `--obligation-report` JSON, a **union**: either a sorted JSON array of `Σ_eff` labels (the bounded may-set) **or** the string `"unbounded"` (⊤). The union forces consumers to handle ⊤; there is no separate advisory flag, and `"unbounded"` is never the 6-element array (the distinctness of Risk 4 / professor Q1).
- *Optional (engineer/experiment choice, non-load-bearing):* when `"unbounded"`, additionally surface an `observed` array (statically-visible labels) clearly marked non-exhaustive — human/agent insight only; the **bound** remains ⊤.
- **Version:** the **obligation-report** schema version `orSchemaVersion` 0.11.0 → **0.12.0** (additive field; [`ObligationAssembly.hs:594`](../../compiler/src/LLMLL/ObligationAssembly.hs) / `:803` `"schema_version"`). **No `trust_report_version` change** — the summary lands in the `--obligation-report` artifact, not the `--trust-report`, so `trust_report_version` stays 1.3.0. **No JSON-AST `schemaVersion` bump** — no AST change. *(Engineer-corrected: Rev 1/2 named `trust_report_version` in error; the obligation report carries its own `orSchemaVersion`, distinct from the trust report's version.)*
- **Required-field treatment:** additive/optional; byte-unaffected on the existing three channels for consumers that ignore it.

## 8. Affected surface

Code-track (B0 implies a compiler-engineer build):

- **`compiler/src/LLMLL/ObligationMining.hs`** — `own(f)` extraction (scan body for `wasi.*` / effectful-builtin applications; the `⊤`-on-opaque rule for delegate/scaffold holes, FFI, out-of-catalog namespaces); the namespace→label map (inversion of `importPath`, [`Syntax.hs:649`](../../compiler/src/LLMLL/Syntax.hs)).
- **`compiler/src/LLMLL/ObligationAssembly.hs`** — the `L`-lattice join / least-fixpoint closure over the call graph (reusing `buildCallGraph` / `stronglyConnComp`, [`:277`](../../compiler/src/LLMLL/ObligationAssembly.hs)); the `effect_summary` union field in `ObligationReport` and its encoder ([`:156`](../../compiler/src/LLMLL/ObligationAssembly.hs), [`:801-821`](../../compiler/src/LLMLL/ObligationAssembly.hs)); **`orSchemaVersion` 0.11.0 → 0.12.0** ([`:594`](../../compiler/src/LLMLL/ObligationAssembly.hs)).
- **`compiler/src/LLMLL/TrustReport.hs`** — **not modified** (`trust_report_version` stays 1.3.0); it is the **read-only invariance target** of the soundness-wiring test, which pins that no `effect_summary` value (including ⊤) reaches `effectiveLevel` / the trust meet / the `EvidenceRecord`.
- **`compiler/src/LLMLL/Module.hs` / `Syntax.hs`** — read-only: the capability-import surface (`importPath`, `Capability`, `isBuiltinImport`) the label map inverts.
- **`docs/llmll-ast.schema.json`** — **no change** (report-versioned, not AST-versioned).
- **`LLMLL.md §5`** (obligation-report docs; new effect-summary subsection) + **`docs/getting-started.md §4`** if a known-good pattern emerges — documentation-lead, post-ship.
- **Freeze:** report-surface inference, no new construct (analogous to the v0.10 obligation report). Freeze-compatible; v0.12 is post-freeze regardless. Not out-of-scope-under-freeze.
- **Downstream:** experiment-lead B0 experiment (`experiments/minimal-agent/001-two-agent-auth`) — the authorization gate for the B1 *engineer build* (not the B1 LT proposal).

## 9. Risks and open questions

1. **~~Approximation direction~~ — RESOLVED** (Rev 2): may-over-approximation + ⊤. The summary is sound for the agent consumer; the experiment measures the right artifact.
2. **⊤-collapse precision.** *Classify: verification-ergonomics / scope.* *Cite:* edge cases 3/5. *Bite: only at scale* — a program dense in delegates/FFI yields mostly `"unbounded"`, low information. This is *honest* (such programs genuinely have unbounded static authority); the value is in the precisely-bounded (non-⊤) functions; the optional `observed` field mitigates for human readers. A precision concern, not a soundness one.
3. **"Informational" must stay out of the trust meet — airtight.** *Classify: soundness (wiring).* *Cite:* §4.3, §4.4; [`TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs). *Bite: blocks if mis-wired* — the engineer test plan must assert no `effect_summary` value (incl. ⊤) changes any trust verdict. A wiring mistake would silently make a descriptive authority label gate `verified`.
4. **⊤ encoding distinctness.** *Classify: spec-drift-prevention.* *Cite:* §7. *Bite: complicates* — `"unbounded"` (⊤) must be a distinct sentinel, never the 6-element array; collapsing them is unsound (a delegate may exercise capabilities `Σ_eff` does not even name).

## Appendix — Professor review log

Professor review (2026-06-14, in-conversation), recommendation `revise-and-resubmit` (one substantive semantic fix; the rest affirmed). Findings, folded into Rev 2:

- **H1 (→ §1, §4.1–4.2).** Approximation direction wrong: the must-lower-bound should be a sound **may-over-approximation** (the use case — capability-correctness — is a may-question needing an upper bound). Past opaque boundaries the sound may-bound is **⊤**, not "drop the unseen effects and flag incompleteness." Recast `eff` as an upper bound with a ⊤ top; opaque callees join to ⊤.
- **H2 (→ §4.3).** "Informational to the compiler" ≠ "no soundness obligation": the *agent* is a soundness consumer (it uses the summary for capability-correctness, which the B0 experiment measures), so a must-under-approximation would be unsound-for-purpose and confound the B1 gate. Sharpened the two-consumer boundary; the no-trust orthogonality is correct *and* a sound may-bound is independently required.
- **H3 (→ §7).** The `effect_summary_complete: false` advisory flag is isomorphic to ⊤ only if load-bearing; replaced it with a **⊤ sentinel value** in a union encoding a consumer cannot ignore.
- **H4 (affirm, → §4.3).** The no-trust-tier orthogonality and the coarse-catalog granularity are correct; the object-capability frame names why (authority ⊥ trust). Kept verbatim. Convergence: the language-team reached the orthogonality inward; the professor's object-capability / may-must reading supplied the direction correction.
- **Anchor (→ §1).** Re-anchored to the object-capability model (Miller, *Robust Composition*, 2006) and the may/must analysis distinction (Nielson–Nielson–Hankin; Lucassen–Gifford, POPL 1988); the Koka/Frank/Leijen row-polymorphism anchor is deferred to B1+.
- **Q1 (→ §4.1, §7).** ⊤ is "any capability, including outside the catalog" — a genuine top *above* `2^Σ_eff`, encoded as a distinct sentinel (`"unbounded"`), never the 6-element set.
