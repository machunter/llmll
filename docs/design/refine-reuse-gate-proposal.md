---
title: "REFINE-REUSE — reuse retrieval for cascading refinement"
status: "Rev 1 — SETTLED (professor-folded; relaxed tier dropped). Ready for compiler-engineer."
authors: [language-team]
relates: [cascading-refinement-proposal.md, contract-discriminative-power-proposal.md, cross-module-assume-guarantee-proposal.md]
review: refine-reuse-gate-review.md
---

# REFINE-REUSE — reuse retrieval for cascading refinement

## Rev 1 changes (folding the professor review)

The professor review (`refine-reuse-gate-review.md`) is folded. The material change is a
reclassification, not a patch:

- **Dropped the fail-closed `--strict-refine` reject (finding 1, open question 1 conceded).** A
  verified, non-vacuous, fully-referenced decomposition that duplicates a contract is *well-formed* —
  non-canonical, not defective. Blocking it conflated hygiene with well-formedness. The entire
  specification-matching / component-retrieval literature is *retrieval*, never prohibition
  (Zaremski-Wing TOSEM'97; Mili et al. TSE'97; Fischer-Schumann NORA/HAMMR). This is now a
  **retrieval/hygiene facility**: an advisory `reuse_suggestions` brief channel plus at most a
  **non-blocking** `W-REUSE` warning. It is no longer "a third gate, sibling of vacuity/orphan."
- **Retracted the parallel-module framing (hazard 2).** Peer modules are invisible to each other
  until imported; the facility reaches sequential intra-module and already-imported candidates only.
- **α-normalize parameters before any contract comparison (hazard 4).**
- **Canonical-contract index for exact-match, not a pairwise solver scan (hazard 5).**
- **Added a guarded positive witness with a nontrivial `pre_D` and renamed parameters (hazard 6,
  open question 2).**
- **Spawn-order determinism (hazard 3) is resolved by construction** — an advisory/warning leaves
  the emitted program identical regardless of authoring order.

Downstream note: the roadmap Stage-4 row (`docs/compiler-team-roadmap.md`, Cascading Refinement
staged table) still reads "reuse gate (REFINE-REUSE)" and must be retitled to a retrieval/advisory
facility. That is doc-lead's slot; flagged, not edited here.

## Restatement

`refine` always *spawns* fresh contracted sub-holes and never surfaces whether an existing definition
already discharges the contract it is about to invent, so blind subtrees accrue semantically
duplicate functions (different name, contract-equivalent). This proposes a **reuse-retrieval
facility** keyed on **contract-subsumption** (an implication relation, not name or syntax): the
checkout/refine brief gains a `reuse_suggestions` channel ranking existing in-scope defs that subsume
a spawned sub-contract, and refine may emit a non-blocking `W-REUSE` warning on an exact-equivalent.
Nothing is rejected.

## Context located

1. `docs/design/refine-reuse-gate-review.md` — the professor review folded into Rev 1.
2. `compiler/src/LLMLL/PatchApply.hs` — `validateRefineScope` (3) *freshness* (name-collision reject)
   and (4) *orphan*. Rev 0 framed this facility as generalizing (3) into a reject; Rev 1 does not — a
   name collision is malformed (two defs, one name), a contract duplicate is not.
3. `compiler/src/LLMLL/CDP.hs:174–181`; `cascading-refinement-proposal.md` §"Layer 3" — the vacuity
   and feasibility gates. These reject *malformed* decompositions; REFINE-REUSE does not join them.
4. `compiler/src/LLMLL/FixpointEmit.hs:829–854` — the COMP-4(b) refinement-subtyping emit (Vazou
   ICFP'14, `:829`) and its fast-path `renameVar xbA "v" pA == renameVar xbP "v" pParamE` (`:849`):
   it normalizes only the refinement binder `v`, **not** free parameter names. Rev 1 α-normalizes
   parameters upstream so blind subtrees' divergent parameter naming does not defeat matching.
5. `compiler/src/LLMLL/Checkout.hs:194–198, 995–1004` — the brief already carries in-scope siblings
   with contracts (`ctAvailableFunctions`) and an advisory `ctHubSuggestions` channel; the reuse
   signal rides these.
6. `compiler/src/LLMLL/HubQuery.hs` — `queryBySignature` / `structuralMatch`; the reuse facility
   layers α-normalized contract comparison on top of this signature filter (the NORA/HAMMR shape).
7. `compiler/src/LLMLL/Syntax.hs:825–831` (`ModuleEnv.meExports`, `meContracts`) — a `ModuleEnv`
   exists only for a loaded/imported module; **concurrent peer modules are mutually invisible**.
8. `docs/design/cross-module-assume-guarantee-proposal.md` (Rev 1, settled) — seeds *imported* callee
   contracts into the body-VC `ContractEnv`. This **expands the imported-candidate pool** once modules
   `(import)` each other, but does *not* make concurrent, not-yet-linked peers visible; concurrent-peer
   dedup remains out of scope (see Risks).

**Drift finding (route to doc-lead).** The roadmap *Future — Cascading Refinement* staged table
(`docs/compiler-team-roadmap.md:187–208`) still frames stages 1–3 as unshipped; the `refine` op and
CDP vaciety gate shipped v0.14.13 (demo runs v0.14.16). Carried over from Rev 0, still open.

## Design proposal

**Classification.** A *retrieval/hygiene facility*, not a well-formedness gate. Vacuity and orphan
reject defects; REFINE-REUSE surfaces an opportunity on a well-formed decomposition. It never
rejects, never mutates the program; its output is a brief channel and an optional warning.

### The subsumption relation (unchanged from Rev 0)

For a spawned sub-hole with contract `Cₛ = (preₛ, postₛ)` and an existing def `D` with the
positionally-aligned contract `C_D = (pre_D, post_D)`, `D` **subsumes** the spawn (`D` can serve it)
iff `preₛ ⇒ pre_D` (contravariant precondition) and `post_D ⇒ postₛ` (covariant postcondition). Both
directions ⇒ **exact-equivalence**. This is behavioral subtyping (Liskov-Wing TOPLAS'94) and
Zaremski-Wing's *plug-in match* / *exact match* (TOSEM'97).

### α-normalization (new — hazard 4)

Before any comparison, both contracts are α-normalized: parameters renamed to positional canonical
names (`p0, p1, …`) and the refinement binder to `v`. The COMP-4(b) fast-path (`FixpointEmit.hs:849`)
normalizes only `v`; blind subtrees name parameters divergently (`(= computed expected)` vs
`(= a b)`), so parameter α-normalization is the step that makes the common cross-subtree duplicate
detectable at all.

### Two tiers, neither blocking

- **Exact-match warning (`W-REUSE`, index-backed).** Canonicalize each contract to a normal-form key
  (α-normalized parameters + a syntactic normal form of the predicate) and index the candidate pool
  by key. A spawn whose key collides with an in-scope def's key emits a non-blocking `W-REUSE`
  ("spawned `bytes-eq` is contract-identical to in-scope `mac-matches`; consider calling it"). Key
  lookup is `O(spawns)`, no solver call. **Sound but incomplete**: it catches syntactic-after-
  normalization equality, not full semantic equality (`(> x 0)` vs `(>= x 1)` over `int` are equal
  but key-distinct) — acceptable, since a missed warning is a cleanliness cost, never unsound.
- **Subsumption advisory (`reuse_suggestions`, solver-backed).** For the semantic cases the key
  misses, rank signature-compatible candidates (`HubQuery.structuralMatch` pre-filter) by whether
  they subsume the spawn, via the existing refinement-subtyping implication (`FixpointEmit`). Surfaced
  in the brief as `reuse_suggestions`; the filling agent decides. Bounded to the signature-filtered
  survivors.

### Candidate pool (honest reach — hazard 2)

`{ in-module siblings }` (in the brief with contracts) `∪` `{ imported defs }` (`meContracts`; widened
by cross-module-assume-guarantee once modules link). **Not** concurrent peer modules — they are
invisible until imported. The hub tier (`queryBySignature`) stays advisory and requires an `import`
to act on.

### Reuse is already mechanically available

A fill body may call any in-scope sibling today: `validateRefineScope` clause (4) constrains only
that *spawned* names are referenced, not that references are spawned; re-typecheck admits calls to
existing in-scope defs (`PatchApply.hs`). So acting on a suggestion is a normal fill (drop the
redundant spawn, call the existing def) — no new mechanism, and no reject if the agent declines.

## Edge cases and degenerate inputs

1. **Exact-match warning fires (index tier).** Module has
   `mac-matches [computed:int expected:int] -> bool (post (<=> result (= computed expected)))`. Agent
   spawns `bytes-eq [computed:int expected:int] -> bool (post (<=> result (= computed expected)))`.
   After α-normalization both keys are `[p0:int p1:int]→bool | (<=> v (= p0 p1))`. Keys collide →
   `W-REUSE` names `mac-matches`. Non-blocking. Channel: **trust/hygiene** (normal-form key equality),
   no solver call.
2. **Guarded plug-in subsumption → advisory, no warning (contravariant-pre, renamed params — hazard 6
   / open question 2).** Existing
   `safe-div [n:int d:int] -> int (pre (not (= d 0))) (post (= result (div n d)))`. Agent spawns
   `divide [x:int y:int] -> int (pre (> y 0)) (post (= result (div x y)))`. α-normalize both to
   `[p0 p1]`. Pre-side `preₛ ⇒ pre_D` = `(> p1 0) ⇒ (not (= p1 0))` **holds**; post-side
   `post_D ⇒ postₛ` = `(= v (div p0 p1)) ⇒ (= v (div p0 p1))` **holds** — but only *after* parameter
   α-normalization (`n/d` vs `x/y` would defeat the `FixpointEmit.hs:849` binder-only fast-path).
   `safe-div` subsumes the spawn → **`reuse_suggestions`** advisory. Not exact: converse pre
   `(not (= p1 0)) ⇒ (> p1 0)` fails at `p1 < 0`, so **no `W-REUSE`**. Channel: **contract**
   (subsumption implication), QF-LIA. This is the guarded positive witness: nontrivial `pre_D`,
   renamed parameters, plug-in-but-not-exact.
3. **Signature mismatch — silent.** Existing `mac-matches [computed:int expected:int]`; spawn
   `handshake-up [hs_state:int] -> bool`. `structuralMatch` rejects on arity before any key or query.
   Channel: **type**; no work.
4. **Contract escapes to Lean — advisory abstains.** Spawn `post` nonlinear/quantified or
   `?proof-required`-tier: the subsumption implication is not QF-LIA, so the advisory abstains and the
   candidate is surfaced "signature-only (contract not machine-comparable)"; the exact-match key still
   works if the predicate has a normal form. Channel: **escapes to Lean** (`LLMLL.md §5.3.5`); nothing
   blocks either way.
5. **Duplicate is also vacuous — vacuity still owns it.** If a spawn is both vacuous and duplicated,
   the CDP vacuity gate rejects it first (a defect in isolation, `CDP.hs:174`); REFINE-REUSE only
   observes well-formed spawns. Facility ordering: structural (D2) → contract-quality gates (vacuity,
   feasibility) → REFINE-REUSE (advisory, never rejects). Spec silent on multi-candidate ranking ties
   (surface all; agent picks) — intentional.

## Verification mapping

- **Exact-match key (`W-REUSE`).** Channel: **trust/hygiene**. Fragment: **decidable and cheap** —
  normal-form-key equality, no proof obligation, no solver. Sound-but-incomplete by construction.
- **Subsumption advisory (`reuse_suggestions`).** Obligation: `(preₛ ⇒ pre_D) ∧ (post_D ⇒ postₛ)` per
  signature-compatible candidate, on α-normalized contracts. Channel: **contract** (the same
  refinement-subtyping emitter as COMP-4(b), `FixpointEmit.hs:826–854`; Vazou ICFP'14). Fragment:
  **QF-LIA, auto-discharged by liquid-fixpoint** when both contracts ⊆ `Σ_auto` (`LLMLL.md §5.3.3`);
  **abstains** (advisory-only, no obligation emitted) when either escapes to Lean (`§5.3.5`). New
  query *site*, not a new fragment.

Because nothing is rejected, no proof obligation gates program admission — a mis-proven implication
degrades a suggestion, never a program. This is a strictly weaker demand on the solver than Rev 0's
blocking gate.

## Affected surface

- `compiler/src/LLMLL/HubQuery.hs` — α-normalized contract key + query-by-contract atop
  `structuralMatch`.
- `compiler/src/LLMLL/Checkout.hs` — populate `reuse_suggestions`; `briefVersion` bump (from
  `0.12.1`).
- `compiler/src/LLMLL/PatchApply.hs` — emit non-blocking `W-REUSE` at refine time; **no new
  `PatchApplyError`** (changed from Rev 0).
- `compiler/src/LLMLL/FixpointEmit.hs` — reuse the refinement-subtyping implication for the advisory
  ranking; add α-normalization of free parameters upstream of the `:849` fast-path.
- A small canonical-contract normalizer/key (new; the index of hazard 5).
- `docs/llmll-ast.schema.json` — additive `reuse_suggestions` brief field.
- `LLMLL.md` (doc-lead, post-ship) — refine-brief description; `docs/compiler-team-roadmap.md`
  (doc-lead) — retitle the Stage-4 row from "gate," plus the stages-1–3-shipped reconciliation.

Out-of-scope-under-freeze: none (freeze lifted v0.11). Out-of-scope-by-design: concurrent-peer
cross-module dedup (needs a shared cross-module refinement store — see Risks).

## Risks and open questions

1. **Concurrent-peer duplication is unreachable** — *scope*. Peer modules are invisible until imported
   (`Syntax.hs:825–831`); the facility catches sequential intra-module + imported candidates only.
   Catching concurrent-peer dedup needs a first-class cross-module refinement store indexed by
   canonical contract (Mili, Mili & Mittermeir, IEEE TSE 23(7), 1997) — an orchestrator-level artifact,
   materially larger than a refine-time facility. *Bite:* bounds the reach; explicitly excluded, not a
   defect.
2. **Exact-match key is incomplete** — *verification-ergonomics*. Normal-form equality misses
   semantically-equal, syntactically-distinct contracts; those fall to the solver-backed advisory or
   are missed. *Bite:* a missed suggestion, never unsound; only matters as coverage.
3. **Advisory cost over the candidate pool** — *verification-ergonomics / scale*. Signature pre-filter
   + α-normalized key index keep the solver off the hot path (contra the pairwise `O(spawns×candidates)`
   of Rev 0). Reference cost model: CDP-perf (`roadmap:66`). *Bite:* at scale, mitigated by the index.
4. **Suggestion ignored** — *scope*. Advisory by design; an agent may spawn a duplicate anyway. That is
   the correct failure mode for a well-formed program (a warning, not a wall). *Bite:* none — this is
   the conceded design.

## Resolved decisions

- **Relaxed match — DROPPED (settled).** Zaremski-Wing distinguish *exact*, *plug-in*, and *relaxed*
  match. Rev 1 ships exact (the `W-REUSE` key) and plug-in (the `reuse_suggestions` advisory) — both
  point at a def the agent can actually *call*. Relaxed match (partial overlap, neither side subsumes)
  points at defs that cannot be called, only imitated; at refinement granularity contracts are small
  enough that "related shape" over-matches, so a relaxed tier is noise. **No third advisory tier; no
  schema room reserved for it.** Reopen only if empirical use shows plug-in coverage is too narrow.
