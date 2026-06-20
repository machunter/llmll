# XMOD-COMP — Cross-Module Verified Composition is a Multi-Layer Gap

> **Version:** Rev 1 — finding/scoping doc.
> **Date:** 2026-06-19
> **Working handle:** XMOD-COMP. Roadmap tag to be assigned.
> **Status:** **Finding — partially fixed, deliberately stopped.** Three layers fixed and green on branch `feat/composition-admit-verified`; at least two layers remain open. Tracked here as a scoped project; **not a prerequisite for any demo** (same-module composition works end-to-end).
> **Origin:** surfaced 2026-06-19 while re-scripting the withdraw-demo to show verified composition (TRUST-PRE + DEMO-COMP). A cross-module composer (`(import core)(open core)` + a function that calls the imported, verified `withdraw`) does **not** reach trust-tier `verified`, whereas the identical composition **in-module does**. Each fix attempted revealed the next layer.

---

## 1. The goal and the finding

**Goal:** a function in module B that imports a `verified` function from module A and composes with it (discharging its precondition, proving its own post) should reach trust-tier `verified` — exactly as it does in-module.

**Finding:** this requires **at least five independent subsystem fixes**. It is an *unimplemented feature*, not a bug. Same-module composition works fully; cross-module is wired only partway.

## 2. The layer stack (empirically established, in the order each surfaced)

| # | Layer | Subsystem | Status | Evidence |
|---|---|---|---|---|
| 1 | **Admission** — a strict-core `def` may *call* an imported verified `def` (type-check `checkCalleeAdmissibility`) | `TypeCheck.hs` | **FIXED** (ADMIT-VERIFIED, `admit-verified-callee-proposal.md`) | green; `core-membership-violation` gone |
| 2 | **Type resolution** — arithmetic/comparison on an imported refinement-alias-typed value (`>=`/`-` on `PositiveInt`) | `TypeCheck.hs` `tcAliasMap` seed | **FIXED** (XMOD-ALIAS; *pre-existing ~3-month bug*, commit `9931a77a`) | green; `expected int, got PositiveInt` gone |
| 3 | **Trust-report tier/edge** — the imported callee's verified tier reaches the importer's trust report; the cross-module dependency edge is captured | `TrustReport.hs` (bare-vs-qualified key; `injectOpenedAliases` + cross-module staleness guard) | **FIXED** (XMOD-TIER) | green; `demo.withdraw` reads `verified`, `safe-withdraw depends_on: [withdraw post: verified]` |
| 4 | **Body-VC emission** — the cross-module caller's *own* body VC: the emission `ContractEnv` must carry the imported callee's contract so the assume-guarantee `EApp`-contracted branch fires (else `body-fallback` → `asserted`) | `FixpointEmit.hs` / `Module.hs` emission `cenv` | **OPEN** | firsthand CLI: `body-fallback: safe-withdraw` cross-module; `verified` same-module |
| 5 | **`consumed_guarantees.callee_tier`** — the obligation-report surface has the same bare-vs-qualified cross-module name miss as layer 3 | `ObligationAssembly.hs` `trustLabel` | **OPEN** (flagged by the XMOD-TIER engineer; out of that scope) | per engineer report |

**The net after layers 1–3 are fixed:** the cross-module composer is *admitted*, *type-checks*, and its dependency edge *shows the callee at `verified*` — but it **still floors to `asserted`**, because **layer 4** leaves its own body VC non-body-faithful. So cross-module verified composition is **not yet reachable**, and at least layers 4–5 (and possibly more below 4) remain.

## 3. Why stop here

- **Same-module composition delivers every use case** (and every withdraw-demo beat): a same-module composer that discharges a callee's pre and proves its post reaches `verified`; `consumed_guarantees` surfaces via `checkout`; the call-site precondition obligation fires on a non-discharging caller. All firsthand-confirmed.
- **The remaining layers are real engineering**, each in a different subsystem (emission `cenv`, obligation-report keying), with no guarantee layer 4 is the last. This is a scoped project, not a demo blocker.

## 4. Process lesson (worth keeping)

The XMOD-ALIAS and XMOD-TIER engineer agents were **sandbox-blocked from running the `llmll` binary** (only `stack build`/`stack test` permitted). Their on-disk-fixture tests passed on the layer they fixed, but the **end-to-end CLI revealed the next layer** each time (e.g. XMOD-TIER's POS test passed while the CLI composer still floored at layer 4). **Cross-layer features need a binary-level end-to-end check, not just per-layer unit tests** — the language-team's firsthand CLI runs were the only thing catching the residual floors. When an engineer agent cannot run the binary, treat a green test suite as "this layer is fixed," **not** "the end-to-end behavior works."

## 5. What's landed vs. open (for whoever picks this up)

**Landed (green on `feat/composition-admit-verified`, keep):** ADMIT-VERIFIED (layer 1), XMOD-ALIAS (layer 2 — independently valuable, a pre-existing bug fix), XMOD-TIER (layer 3 — the dropped-edge fix is a real correctness gain even standalone: it also prevented *over-crediting* a caller of a weaker cross-module callee).

**Open (the XMOD-COMP project):** layer 4 (emission `cenv` carries the imported contract → cross-module caller body-faithful) and layer 5 (`callee_tier` bare/qualified keying), plus a verification pass that *no further layer* hides below 4. Recommend a single dedicated effort with a **binary-level end-to-end acceptance test** (`verify` a cross-module composer → `verified`) as the gate, not per-layer unit tests.

**Also noted (pre-existing, out of scope):** `buildTrustReport` call sites in `Main.hs` (1126/1226/1260) pass the raw reloaded entry sidecar, not the staleness-validated one — a latent same-file staleness gap flagged by the XMOD-TIER engineer.
