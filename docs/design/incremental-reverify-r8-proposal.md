# Incremental Patch Re-Verification (R8) — Proposal

> **Status:** Rev 0 (design + soundness argument; 2026-07-20). Both soundness premises verified
> against the code. Ready for engineer feasibility read. Scope: `llmll patch` only (not `refine`).

## The question

`patch` today re-verifies the **whole merged module** after every fill. `PatchApply.reVerify`
(`PatchApply.hs:537`) calls `emitFixpointWith … stmts` over *all* statements and runs
liquid-fixpoint on the whole `.fq`. For a repair loop that fills many holes in a large module, the
SMT cost is `O(module)` per patch — the dominant wall-clock item once a module has more than a
handful of contracted functions. R8 replaces the whole-module re-verify with the **dependency
slice** the fill actually touches.

## Soundness argument (the deciding point)

Two premises, each verified against the current code:

- **P1 — contract preservation.** `patch` fills only **body-position** holes. Contract-position holes
  and `?proof-required` holes are excluded from the checkout/patch dependency graph
  (`HoleAnalysis.hs:622,680`: `not (isContractPointer (holePointer e))`). So a patch **never changes
  any function's contract** (pre/post).
- **P2 — modular verification conditions.** Verification is assume-guarantee modular: a function
  `F`'s body-VC is emitted from `F`'s own precondition and its callees' **contracts** — never another
  function's **body** (`FixpointEmit.hs:32-34`, the assume-guarantee discipline). No cross-function
  body coupling exists in the emitted `.fq`.

**Conclusion.** A patch fills a body hole in exactly one function `F`, changing only `F`'s body. By
P2, every *other* function `G`'s body-VC is a function of (`G`'s pre, `G`'s body, `G`'s callees'
contracts) — all unchanged — so `G`'s constraints are **character-identical** before and after. By
P1 no contract changed, so no caller's assume-guarantee assumption of `F` changed either. Therefore
re-verifying **exactly `{F}`** discharges every obligation the whole-module re-verify would, and no
obligation is dropped. The slice is **sound and complete**, and it is a singleton.

This is *simpler* than the roadmap's conservative "node-VC + fill-induced callee slice +
staleness-recheck" framing: the callee slice is unnecessary (callees are assumed via their
contracts, which already hold and are not re-verified), and staleness-recheck is unnecessary within
a single patch (nothing but `F`'s body changed).

### Why the fill's new callees don't enlarge the slice

If `F`'s fill introduces a new call `F → G`, `F`'s body-VC now *assumes* `G`'s contract. `G`'s
contract is an **input** (it already exists in the module), not an obligation to re-discharge. `G`'s
own body-VC is untouched. The slice stays `{F}`; the module's contracts remain available to the
emitter as context.

## Slice definition

For a patch that fills the hole at pointer `p` inside the statement for function `F`:

```
reverifySlice(patch p) = { F }        -- F = the function enclosing p
```

Type-checking stays **whole-module** (it is solver-free and cheap, and it must still catch a fill
that introduces a cross-function type error). Only the **SMT body-VC step** — the expensive part —
is sliced.

## Implementation plan

1. **`EmitOptions.emitBodyVCTargets :: Maybe [Name]`** (new field; `Nothing` = all functions, today's
   behavior; `Just names` = emit body-VC constraints only for `names`). The emitter still walks all
   statements for **contract** context (so `F`'s assume-guarantee assumptions resolve) but emits a
   body-VC constraint only for a targeted function. Default `Nothing` preserves every existing caller.
2. **`reVerify` computes the slice.** `applyPatch` already knows the checked-out pointer; map it to
   the enclosing function name `F` (the statement whose subtree contains `p`), and call
   `reVerify fp stmts` with `emitBodyVCTargets = Just [F]`. Fall back to `Nothing` (whole module) if
   the enclosing function can't be resolved — fail-safe, never fail-unsound.
3. **No schema / trust surface change.** The `.fq` is emit-only and internal; the verdict (SAFE/UNSAFE)
   and its diagnostics are identical — only fewer constraints are emitted and solved.

## Validation

- **Correctness:** a regression asserting that, for a module with an intentionally-refuted second
  function, patching a *different* function's hole still yields the same SAFE/UNSAFE verdict for the
  patched function as the whole-module path (the slice must not hide or invent a refutation).
  Additionally: a differential test that the sliced `.fq` for `F` is a subset of the whole-module
  `.fq`'s `F`-constraints (same constraint ids), proving completeness.
- **Latency (the roadmap's demonstration):** a repair-loop benchmark over a synthetic N-function
  module, patch one hole, whole-module vs sliced wall-clock as N grows (basis:
  `experiments/cdp-perf-0/`). Expectation: whole-module scales with N, sliced is flat.

## Out of scope

- **`refine`** spawns *new* contracted functions; their fresh body-VCs must be verified — a different
  (additive) slice, deliberately excluded from this Rev.
- **Contract edits.** Not reachable via `patch` today (P1). Were a future op to edit a contract, the
  slice would extend to the transitive callers of the edited function (their A-G assumptions change) —
  recorded here as the forward lever, not built.
