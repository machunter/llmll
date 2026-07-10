---
name: cascading-refine-protocol-spike
title: "Cascading `refine` op — protocol spike"
status: "Spike (2026-07-06) — GO for Stages 1-3"
author: compiler-engineer
---

# `refine` protocol spike

The one real design decision the feasibility plan flagged before Stages 1-3: the `refine` protocol
shape + the scope-relaxation safety predicate. Design settled; core move empirically confirmed;
`compiler/src` left clean.

## D1 — protocol shape (reuse `applyPatch` wholesale)

A `refine` is a `patch` with a relaxed scope check. Same `PatchRequest` (`{token, patch:[ops]}`,
PatchApply.hs:70-73); same lifecycle `applyPatch` (PatchApply.hs:254-314): token validate → OBLIG-1
`checkStaleness` compare-and-swap (:271) → scope check (:276) → `applyOps` (:285) → `parseJSONASTValue`
(:291) → `typeCheck` (:299) → `reVerify` (:303) → write + clear lock (:313). **Zero new verify code:**
`reVerify` runs the module's assume-guarantee VCs (FixpointEmit.hs:158-159); a spawned contracted `G`
is a callee `H` verifies *modulo*.

**Ops in a `refine` request** decomposing hole `H` (at checkout pointer `/statements/<h>/body`) into
body `e_H` calling new defs `G₁…Gₙ`:
- `PatchReplace /statements/<h>/body <e_H>` — fill H (within checkout scope; existing).
- `PatchAdd /statements/- <Gᵢ-json>` — append each new top-level def (`?body` hole, contract fixed).
  `/statements/-` is the RFC-6902 array-append; `applyOp (PatchAdd …)` already handles it (:224-226).

**CLI:** a new verb `llmll refine` (dual of `patch`) that calls `applyPatch` with a `RefineScope`
mode, rather than overloading `patch` — the relaxed scope predicate is then opt-in and explicit, not a
silent widening of `patch`'s guarantees.

## D2 — the scope-relaxation safety predicate (the crux)

`validateScope` (PatchApply.hs:193-203) currently requires every op path to be descendant-or-self of
the checkout pointer. A `refine`'s `PatchAdd /statements/-` is a sibling-level add → outside H's
subtree → it must be admitted, but **bounded**. A `refine` op-set is admissible iff:

1. **Exactly one `PatchReplace` at `/statements/<h>/body`** — the fill of H, within scope (existing check).
2. **Every other op is a `PatchAdd /statements/-`** — additive-only. *No* `PatchReplace`/`PatchRemove`
   at any path outside H's subtree. **Prevents:** tampering with / removing an existing verified sibling.
3. **Each added statement is a `def`/`def-shell` with a FRESH name** (not already bound in the module).
   **Prevents:** shadowing/redefining an existing function (e.g. re-adding `withdraw` with a weaker
   contract). — **Load-bearing finding (D3): this must be an EXPLICIT check in the `refine` path;
   `typeCheck` does NOT reject a duplicate top-level def** (probed: `llmll check` on a module with two
   `final-step` defs → `OK (3 statements)`, exit 0). Freshness cannot be delegated to re-typecheck.
4. **Each added def is BODY-REFERENCED** — its name appears as a call in `e_H`. **Prevents:** smuggling
   in unrelated / hidden top-level functions under H's mandate (a def the body never calls → reject).
5. **Each added def's body is a hole** (`?body`) — `refine` *spawns* frontier holes; it does not fill
   them (fills are `patch`). (Soft: a fully-authored helper could be allowed, but the canonical refine
   spawns holes; keep the invariant tight for the demo.)

Clauses 3 and 4 are the new explicit checks; 1, 2 are a tightening of the existing scope check for the
`RefineScope` mode. This is a **bounded** relaxation — additive, fresh, body-referenced — not an
arbitrary-write escape.

## D3 — empirical probe (M-feasibility CONFIRMED)

Constructed the post-`refine` module directly (H = `verify-kx` filled to `(final-step ok)`; G =
`final-step`, contract fixed, body `?impl`) and ran the existing machinery:

- `llmll verify` → `body-faithful: verify-kx`, `body-fallback: final-step`, `call-pre obligations:
  verify-kx`, **SAFE**. H verifies **modulo G's contract** (assume-guarantee; H discharges G's pre at
  the call site), G is contract-only. **Zero new verify code.**
- `llmll holes` → `1 holes (0 blocking)` · `?impl in def-shell final-step`. G's body is a **new
  frontier hole**.

So the core cascade step — add contracted G + fill H to call it → H verified-modulo-G, G a new hole —
works on shipped machinery. The full patch-apply path (token + lock + `applyOps` of the add) is a
straightforward reuse; the only gate between it and this result is the D2 scope predicate. (The
verification core was probed directly, so **no temporary `validateScope` edit was needed — `compiler/src`
is clean**.)

## D4 — feasibility-gate SAT approach

The Layer-3 feasibility gate rejects an infeasible invented contract: `pre ⇒ ∃result. post`. Full
feasibility is `∀inputs. pre ⇒ ∃result. post` — a ∀∃ (quantifier-alternation) formula liquid-fixpoint's
QF fragment cannot decide directly. The tractable, adequate gate for the intended purpose (catch a
*grossly* infeasible sub-goal, e.g. `post = (and (> result x) (< result x))`, UNSAT for every input):

- Introduce a fresh witness `w` for `result`; check **SAT of `pre ∧ post[w/result]`**. UNSAT ⇒ no input
  admits any result ⇒ grossly infeasible ⇒ **reject the spawn**. SAT ⇒ feasible for ≥1 input ⇒ admit.
- Phrased for liquid-fixpoint's validity/UNSAT orientation: emit the VC `(pre ∧ post[w/result]) ⇒ false`
  and solve — **VALID** (the antecedent is UNSAT) ⇒ infeasible ⇒ reject; **refuted** (a satisfying
  counterexample exists) ⇒ feasible ⇒ admit. This is a contract-only VC with a fresh `result` witness
  and no body — expressible on the **existing CDP contract-only `.fq` emit path** (CDP.hs already emits
  per-candidate contract-only queries), so it needs no new solver plumbing.
- **Residual (honest):** this catches gross (all-inputs) infeasibility, not subtle
  feasible-for-some-but-not-all-inputs cases (that is the ∀∃ problem, out of QF). Adequate for the
  gate's stated job; note the limitation. **Spike-level, not a redesign.**

## Verdict

**GO for Stages 1-3.** Protocol = `applyPatch` reuse + a `RefineScope` mode of `validateScope`.
Genuinely-new code: (i) the D2 safety predicate (with the **explicit freshness check** — the one thing
re-typecheck does not give us), (ii) the `refine` verb wiring, (iii) the feasibility-gate `.fq` emit
(reuses the CDP path). All small. The M estimate for the blog demo (Stages 1-3) holds; the feasibility
gate stays S with the D4 approach. `compiler/src` clean; nothing committed.
