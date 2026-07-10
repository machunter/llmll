---
name: cascading-refinement-engineer-plan
title: "Cascading refinement — engineer feasibility read + staged build plan"
status: "Feasibility read (v0.14.12 baseline) — consumes cascading-refinement-proposal.md Rev 2"
date: 2026-07-06
author: compiler-engineer (fork)
---

# Cascading refinement — engineer feasibility read

**Headline: far more reuse than the "R2/R8-scale" framing implied.** The substrate for all three
layers already exists in the shipped compiler. The genuinely-new work is **two pieces** — the
`refine` protocol (scope relaxation + request shape) and the feasibility SAT-gate — plus thin
wiring. Total for a **demo-capable** `refine` op with Option-3 cycle handling: **M** (Stages 1–3);
the full contract-quality gates add **S–M** (Stage 4). Not XL. The one true scale prerequisite (R8
incremental re-verify) is **not needed for the blog demo**.

## Per-layer feasibility (reuse vs. new, cited)

### Layer 1 — per-node verification: **FREE (reuse).**
`applyPatch` (PatchApply.hs:254–317) already re-parses → **re-typechecks the whole module**
(`typeCheck mode emptyEnv stmts`, :299) → **re-verifies via SMT** (`reVerify fp stmts`, :303) on
*every* patch. Assume-guarantee (`cvPreObligation`/`cvPostAssumption`, FixpointEmit.hs:158–159) is
emitted across the module. So when a `refine` adds a contracted `Gᵢ` and fills `H` to call it, the
existing lifecycle verifies `H` modulo `Gᵢ`'s contract and `Gᵢ` (contract-only until its `?body` is
filled) with **zero new verification code**. Cost caveat: the re-verify is **whole-module per
refine** — fine for demo-scale, the R8 concern at scale (below).

### Layer 2 — the `refine` op + growing tree + resync: **the real work, but mostly small.**
- **Def-spawn — reuse.** `PatchAdd` (PatchApply.hs:77,224) already inserts a new node; a spawn is
  `add /statements/- <new def with ?body>`. No new op needed.
- **Scope relaxation — THE genuinely-new protocol piece.** `validateScope` (:193–203) rejects any op
  path outside the checkout pointer's subtree — this is exactly what forbids adding a sibling `def`
  today. `refine` needs a *bounded* relaxation: permit `add`s at `/statements/-` **iff** the added
  node is a `def`/`def-shell` with a fresh name that the filled body `e_H` references. This is a
  new predicate + a `refine` path distinct from plain `patch` (plain `patch` keeps the strict
  scope-check). **New design + safety-critical** (an over-broad relaxation lets an agent inject
  arbitrary top-level defs). ~M.
- **Resync (compare-and-swap) — FREE (reuse).** `checkStaleness` (PatchApply.hs:271,331) already
  compares the token's `ctSourceHash` against the current file (OBLIG-1, v0.10). A `refine` changes
  the file hash → every *other* outstanding token goes stale → its next patch is `PatchAuthError`
  → re-checkout. The DemoPost compare-and-swap the proposal describes is already implemented; a
  structural spawn is just another hash change.
- **Growing tree / frontier — S (mostly reuse).** HoleAnalysis.hs already computes a dependency
  graph: `analyzeHolesWithDeps` (:126), `holeDependsOn` edges (:88), `holeCycleWarn` (:89),
  `depends_on` JSON emission (:507). There is **no persistent tree to maintain** — the module *is*
  the tree, and each `llmll holes` re-analyzes it, so the newly-spawned `?body` holes appear as the
  next frontier automatically. Work: surface the parent/child relation in `--deps` output. ~S.
- **CLI verb — S.** `Cmd*` pattern in Main.hs (CmdCheckout :122, CmdPatch :127). Add `CmdRefine`. ~S.

### Layer 3 — contract-quality gates + Option-3 cycle handling: **reuse-heavy.**
- **Cycle detection — FREE (reuse).** FixpointEmit.hs:99,262–270 already builds the call graph
  (`buildCallGraph`) and runs `stronglyConnComp` to compute the recursive `sccSet` (CyclicSCC), and
  already excludes cycle members from compositional encoding (contract-only). Option-3's "detect the
  cycle at spawn" is a direct reuse of this on the post-`refine` module.
- **Trust-meet cycle-floor (Option 3) — S–M (extend).** `effectiveLevel` (TrustReport.hs:24,67–75)
  already meets self-tier with the transitive-callee **post** tier (Position B), consumed by the
  `callee_tier` lever. Option 3 = extend the meet to **floor on any contract-only cycle member**
  (the `sccSet` members), so a recursive core reads as "verified modulo a partial recursive core."
  This is an extension of the existing meet, not a new axis.
- **CDP spawn-gate — S (reuse; earlier worry resolved).** CDP (CDP.hs:12–15) is **contract-based**:
  it *synthesizes* the closed Ω candidate set for a contract and counts how many satisfy it —
  it does **not** need the function's own body. So it runs on an unfilled (`?body`) `Gᵢ` directly.
  The gate is a thin wrapper: reject a spawn whose `cdpSatisfyingCount / cdpCandidateCount`
  (CDP.hs:82–84) exceeds floor θ. ~S.
- **Feasibility gate — S–M + SPIKE.** `pre ⇒ ∃ result. post` is a **satisfiability** query on
  `pre ∧ post`, but liquid-fixpoint is a **validity/UNSAT-oriented** Horn solver — CDP's "does any
  candidate satisfy" is a *fixed-basis* proxy, not a true `∃`. So a genuine feasibility check needs
  either a direct SMT SAT call or a synthesis encoding. **Spike required** (query polarity).

## Recommended staged build (each stage independently verifiable)

- **Stage 1 — `refine` op skeleton (M).** New `CmdRefine` + request shape {`replace /…/body` + one-or-more
  `add /statements/- <def …?body>`} + the bounded scope relaxation + freshness/reference check; reuse
  the whole applyPatch lifecycle (re-typecheck + re-verify). **Acceptance:** refine a hole `H` into a
  body calling a spawned contracted `G`; `H` verifies modulo `G`'s contract; `G` shows up as a new
  frontier hole in `llmll holes`. *This alone is the core demo.*
- **Stage 2 — growing-tree frontier + resync confirmation (S).** Surface parent/child in `holes --deps`;
  confirm concurrent tokens go stale + re-checkout across a spawn (reuse `checkStaleness`).
- **Stage 3 — Option-3 cycle handling (S–M).** Detect a spawned cycle (`buildCallGraph`/`stronglyConnComp`
  on the grown module) and floor the `effectiveLevel` meet on contract-only cycle members. **Acceptance:**
  a cascade that spawns a recursive core reads as partial-correctness at the top, not silent `verified`.
- **Stage 4 — contract-quality gates (S–M).** CDP spawn-gate (floor θ, reuse `CDPResult`) + the
  feasibility gate (after the spike). **Acceptance:** a spawn of `(def g …(post true)?body)` is rejected
  (CDP), and a spawn with an unsatisfiable post is rejected (feasibility).

**Blog demo needs Stages 1–3** (the `refine` op + honest cycle handling). Stage 4 enriches the
"who-trusts-the-decomposition" narrative; the CDP half (S) is cheap enough to include, the
feasibility half can trail after its spike.

## Regression surface
Low. `refine` is an **additive** path (new verb) that reuses the patch lifecycle; the scope
relaxation applies **only** on the refine path — plain `patch` keeps `validateScope` unchanged
(PatchApply.hs:276). The Layer-3 extensions (meet floor, CDP gate) are additive to the trust report.
The one place to guard: the meet-floor must not perturb existing (acyclic) `effectiveLevel` outputs —
gate it on `sccSet` non-membership (identity on acyclic callees).

## Residual unknowns (spikes — do before committing to build)
1. **`refine` protocol shape + scope-relaxation safety predicate.** New verb vs. `PatchOp` extension;
   the exact "added def is fresh + referenced by the body" constraint. The one real design decision.
2. **Feasibility-gate query polarity.** liquid-fixpoint is validity/UNSAT-oriented; a true `∃result.post`
   SAT check needs a direct SMT SAT call or a synthesis encoding — confirm the cheapest path.
3. **Whole-module re-verify cost → R8.** `applyPatch` re-verifies the whole module per refine
   (PatchApply.hs:299,303). Fine for demo-scale; **R8 incremental slice re-verify is the scale
   prerequisite**, not a demo blocker. Flag, don't build yet.

## Effort summary
- Demo-capable refine op + Option-3 (Stages 1–3): **M**.
- Full gates (Stage 4): **+S–M** (feasibility half gated on spike 2).
- R8 incremental re-verify (scale only, deferred): separate **M–L**, not on the demo path.

**Bottom line:** cascading refinement is a **M** build for the blog demo, not the XL project the
"R2/R8-scale" label suggested — because assume-guarantee, the patch lifecycle, the staleness resync,
cycle detection, CDP, and the trust meet are all already shipped. Recommend: spike #1 (the protocol),
then build Stages 1–3.
