---
title: A4 Flagship — Emergent Token-Revocation Service (RFC 7009/7662)
status: COMPLETE 2026-07-17 — all five phases done; artifact = examples/token-revocation-emergent/ (8 fns / 5 modules, all body-faithful, 2 agent-invented; 9 frozen cruxes in the refute-crux gate; findings F-1..F-4 in its README)
author: scoping talk (user + assistant), 2026-07-17
track: Data Scope Extension Lever A, row A4 ("flagship data example") — the payoff demonstration for the v0.14.33–46 arc
---

# A4 Flagship — Emergent Token-Revocation Service

> **Status:** Scoped and settled with the user 2026-07-17. Decisions final: domain = **token revocation/introspection (RFC 7009/7662)**; construction = **emergent cascade** (no authored scaffold); **no bait hole** (reserved as a possible separate example); fill agents = **blind, tool-disabled `claude -p`, checkout-brief-sole-channel** (the secure-channel-emergent discipline). Sequencing = **residue lift first**.

## What A4 proves

The data counterpart of `examples/secure-channel-emergent` (the control-flow flagship): one coherent program where bytes bounds, map key-presence/aliasing, RMW pipelines, cross-module map assume-guarantee, and string-tagged values with distinctness + length all carry real obligations. Ends at verify/trust-report (assurance-not-bugs). The composition claim is new: **RFC text → provenance-tagged contracts (R3 pipeline, `:source`) → blind agent cascade (emergent decomposition via `refine`) → whole-program verified → trust report** — the first artifact where both the spec origin and the implementation origin are machine-auditable.

## Settled decisions

1. **Domain: OAuth-shaped token revocation/introspection.** RFC 7662 introspection ("active" is literally the RFC vocabulary), RFC 7009 revocation. Data surface: `tokens : map[int,string]` (token-id → `"active"`/`"revoked"`/`"expired"` — the string-tag read/decision surface), `grants : map[int,int]` (the mutating spine), `digest : bytes[32]` (bounds), request `method : string` (literal dispatch, the STRLIT witness). Rejected alternatives: firewall/policy table (no RMW spine, no RFC tie-in), wire-format parser (bytes already showcased by secure-channel).
2. **Emergent cascade, not authored scaffold.** No reference solution. A small seed of top-level RFC-derived contracts; agents invent the decomposition via `refine` (shipped, incl. REFINE-REUSE). The data surface is forced at the seed boundary — seed signatures carry the map/bytes/string types, so type propagation + contract obligation pull map-presence pres and status-literal posts down the cascade; agents cannot route around the data types, only decompose within them.
3. **No bait hole.** The unsteered-bait pattern (secure-channel F-6) is deliberately excluded — it adds an agent-behavior claim to an assurance-shaped demo. Reserved as a possible separate example.
4. **Fill discipline: unchanged.** Blind, tool-disabled `claude -p`; the checkout brief is the sole information channel (no forced failures, no hints beyond the contract). Known failure modes already patched: hollow self-call fills (HOLE-STATUS v0.14.21), subagent git writes (PreToolUse guard), parallel-fill collisions (worktree isolation).
5. **Refutation layer: post-fill, author-injected.** After the wave verifies, mutate the verified fills — drop the revocation put, skip the status check, alias a key, accept `"GET"` on the revoke endpoint, off-by-one the digest — and CI-gate each refutation (`refute-crux` discipline). Independent of agent behavior; this is the assurance claim.

## Phase plan

| Phase | Work | Gate |
|---|---|---|
| **1. Residue lift** ✅ **SHIPPED v0.14.47** | String-valued map **returns** (`strMapArraySort` marker; all `== mapArraySort` dispatch sites widened) + **param-string put values** (`mapPutValVars` → carrier + `SortEnv`) + string **RMW chains** (`MRGet` value sort). `revoke : tokens → tokens` and `set(m, k, s)` verify with refute twins; **cross-call string-map A-G probed** (risk 2 cleared: bad caller refuted at call site). 1254 H / 0, refute-crux 26/26. | ✅ all gates passed |
| **2. Seed contracts** ✅ | Seven `:source`-tagged roots across five modules, every contract `qf_lia`; `VERIFICATION_SCOPE.md` = S0 model + Q1–Q9 inventory. **Bonus ship v0.14.48**: the STRLIT body-channel flip, found feasibility-probing the introspect shape (it fell back → vacuous SAFE; the expiry-skip bug now refutes). | ✅ all contracts in-fragment |
| **3. Pilot** ✅ | 3 modules filled blind: 5 accepted fills incl. a **spontaneous 2-function cascade** (agent-invented contracts for `token-status-active`/`token-unexpired`). One harness finding (F-1 bare-atom converter, fixed pre-wave); zero compiler findings. | ✅ gate passed — wave opened |
| **4. The wave** ✅ | `revocation` + `spine` filled; `serve`'s agent composed `(if (introspect …) (grant …) 0)` — the **cross-module A-G obligation discharged** (grant's pre proven from introspect's post). F-2: map-returning bare tail call falls back (pre-existing; agent inlined). | ✅ 8/8 body-faithful, whole-service SAFE, spine trust `verified: 5` |
| **5. Refute twins + close-out** ✅ | 9 frozen cruxes (4 good twins = the agents' bodies; 5 refutes = expiry-skip / dropped-put / method-gate-at-call-site / unconditional-serve / fp-false-accept) added to `refute-crux-gate` → **35/35**. F-3: stale stack binary caught (gate preflight lesson). Findings F-1..F-4 in the example README. | ✅ gate green on the current binary |

## Risks

1. **Data holes under blind fill** (the pilot's purpose): a map-contract hole may elicit fallback-shaped fills (e.g., unguarded `map-get`). Pilot gates the wave.
2. **Cross-module A-G for string-valued maps is unprobed** — A2.1's component-aware substitution was built/tested on int maps; a string-map-param callee's pre substitution needs a probe during Phase 1.
3. **Cascade-shape risk**: agents may decompose into shapes the residue still firewalls (string `map-empty` construction, string keys). Mitigation: seed signatures pass stores as params (API-shaped, construction never needed); string keys are absent from the seed vocabulary.

## Out of scope

String keys (`map[string,·]`), string `map-empty` construction (both remain clean fallback); the bait-hole example; any convergence/speed comparison (per the demo-strategy stance).
