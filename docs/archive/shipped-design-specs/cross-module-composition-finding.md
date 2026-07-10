# XMOD-COMP — Cross-Module Verified Composition is a Multi-Layer Gap

> **Version:** Rev 1 — finding/scoping doc.
> **Date:** 2026-06-19
> **Working handle:** XMOD-COMP. Roadmap tag to be assigned.
> **Status:** **CLOSED — all five layers fixed (v0.14.18).** Layers 1–4 by ADMIT-VERIFIED / XMOD-ALIAS / XMOD-TIER / **XMOD-AG (v0.14.17)**; layer 5 (checkout `consumed_guarantees`) by **XMOD-CG-BRIEF (v0.14.18)** — the brief's `ContractEnv` is seeded from the module cache with the verify path's exact recipe, and the previously-untested `callee_tier` keying resolves a bare opened-import callee through its qualified trust entry (generalized `injectOpenedAliases`) instead of the `"builtin"` fallthrough. E2e-confirmed via `checkout` on a cross-module fixture. The sibling brief channels closed by **XMOD-SCOPE-BRIEF (v0.14.19)**: `available_functions` lists imported exported contracted functions under their callable names (`status: "imported"`), `in_scope` carries imported names via a seeded sketch env (bare opened aliases labeled `open-import`), and the obligation report's per-hole `contracted_functions` gains the same vocabulary. Nothing of this finding remains open. The finding below is the original 2026-06-19 record, kept for the layer stack and the process lesson (§4).
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
| 4 | **Body-VC emission** — the cross-module caller's *own* body VC: the emission `ContractEnv` must carry the imported callee's contract so the assume-guarantee `EApp`-contracted branch fires (else `body-fallback` → `asserted`) | `FixpointEmit.hs` / `Module.hs` emission `cenv` | **FIXED** (XMOD-AG, v0.14.17) | firsthand CLI: `body-faithful: safe-withdraw` cross-module; imported refinement-aliased-param case also body-faithful |
| 5 | **`consumed_guarantees` (checkout brief)** — the channel drops imported callees entirely | `Main.hs` checkout `cenv` was `buildContractEnv stmts` (same-file; XMOD-AG made only the verify path cache-aware) | **FIXED** (XMOD-CG-BRIEF, v0.14.18) | checkout `cenv` seeded from the module cache (`cacheAwareAliasMap`/`cacheAwareContractEnv`, the verify path's recipe); `callee_tier` for a bare opened-import callee resolves via generalized `injectOpenedAliases` (was the untested `"builtin"` fallthrough). E2e: the brief carries the imported callee's guarantee + real tier; contrast test pins the pre-fix drop |

**The net after layers 1–3 are fixed:** the cross-module composer is *admitted*, *type-checks*, and its dependency edge *shows the callee at `verified*` — but it **still floors to `asserted`**, because **layer 4** leaves its own body VC non-body-faithful. So cross-module verified composition is **not yet reachable**, and at least layers 4–5 (and possibly more below 4) remain.

## 3. Why stop here

- **Same-module composition delivers every use case** (and every withdraw-demo beat): a same-module composer that discharges a callee's pre and proves its post reaches `verified`; `consumed_guarantees` surfaces via `checkout`; the call-site precondition obligation fires on a non-discharging caller. All firsthand-confirmed.
- **The remaining layers are real engineering**, each in a different subsystem (emission `cenv`, obligation-report keying), with no guarantee layer 4 is the last. This is a scoped project, not a demo blocker.

## 4. Process lesson (worth keeping)

The XMOD-ALIAS and XMOD-TIER engineer agents were **sandbox-blocked from running the `llmll` binary** (only `stack build`/`stack test` permitted). Their on-disk-fixture tests passed on the layer they fixed, but the **end-to-end CLI revealed the next layer** each time (e.g. XMOD-TIER's POS test passed while the CLI composer still floored at layer 4). **Cross-layer features need a binary-level end-to-end check, not just per-layer unit tests** — the language-team's firsthand CLI runs were the only thing catching the residual floors. When an engineer agent cannot run the binary, treat a green test suite as "this layer is fixed," **not** "the end-to-end behavior works."

## 5. What's landed vs. open (for whoever picks this up)

**Landed (green on `feat/composition-admit-verified`, keep):** ADMIT-VERIFIED (layer 1), XMOD-ALIAS (layer 2 — independently valuable, a pre-existing bug fix), XMOD-TIER (layer 3 — the dropped-edge fix is a real correctness gain even standalone: it also prevented *over-crediting* a caller of a weaker cross-module callee).

**Closed (v0.14.17):** layer 4 (emission `cenv` carries the imported contract) by XMOD-AG — a cross-module composer verifies body-faithful end-to-end, including the imported refinement-aliased-param case (`xmod-alias`, plus a `needs-pos` test whose post *requires* the imported refinement). No further layer was found hiding below 4.

**Closed (v0.14.18):** layer 5 by XMOD-CG-BRIEF — the checkout `cenv` is seeded from the module cache with the verify path's exact recipe (`cacheAwareAliasMap` + `cacheAwareContractEnv`, extracted from `emitFixpointWithCache` so the two paths cannot drift), and the flagged-untested `callee_tier` keying is fixed: a bare opened-import callee resolves through its qualified trust entry via `injectOpenedAliases` (generalized over the map's value type) instead of falling through to `"builtin"`.

**Closed (v0.14.19, XMOD-SCOPE-BRIEF):** the sibling brief channels observed during the v0.14.18 e2e. `available_functions` lists imported **exported** contracted functions under the name the entry module calls them by (bare when `(open ...)`-ed — selective filter honored, a local def shadows — else qualified; `status: "imported"`); `in_scope` carries imported names via a cache-seeded sketch env (`seedCacheEnv`; the walk's existing `SOpen` handler labels the bare alias `open-import`); the obligation report's per-hole `contracted_functions` gains the same vocabulary with its trust map bare-aliased (`injectOpenedAliases`). E2e-confirmed on a cross-module fixture through both `checkout` and `verify --obligation-report`.

**Also noted (pre-existing, out of scope):** `buildTrustReport` call sites in `Main.hs` (1126/1226/1260) pass the raw reloaded entry sidecar, not the staleness-validated one — a latent same-file staleness gap flagged by the XMOD-TIER engineer.
