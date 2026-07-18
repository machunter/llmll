---
name: cascading-refinement-proposal
title: "CASCADING REFINEMENT — agent-driven recursive hole decomposition"
status: "Rev 5 (professor fold: QE/qsat-complete discharge, ∃result over refined return type, minimal witness, realizes reserved spec-inconsistent; 2026-07-18) — feasibility gate READY FOR ENGINEER"
date: 2026-07-06
author: language-team
consumers: [professor, compiler-engineer]
---

# CASCADING REFINEMENT — agent-driven recursive hole decomposition

## Restatement

Today a scaffold's decomposition is authored up front: a human writes the full solution, holes it
out, and agents fill a *fixed, flat* set of leaf holes (`examples/heartbleed/scaffold_holeout.py`;
the flat-list model of `agent-orchestration.md:220`). The design problem is to make the decomposition
itself **emergent**: start from a few top-level contracted holes, and let an agent *refine* a hole
into a body that calls **newly-introduced** contracted sub-functions (each a fresh `?body` hole),
recursively, until every open hole is directly fillable. The hole set becomes a **growing refinement
tree** rather than a fixed frontier. This is precisely **stepwise refinement** (Wirth 1971; Back &
von Wright's *refinement calculus*; Morgan, *Programming from Specifications*), mechanized under
agent authorship — and it is the project's own stated differentiator
(`strategic-positioning.md:22`: "typed holes as **decomposition** primitives across agents"), so far
only half-realized. The design-reference set is the verified-language ecosystem under
*agent-authoring* conditions; no other member (LiquidHaskell, F\*, Dafny, Idris) exposes refinement
*steps* as a concurrency/decomposition protocol, so the novelty is the protocol + the trust story for
an *agent-invented* decomposition, not the per-step logic (which is classical).

## Context located

1. `compiler/src/LLMLL/FixpointEmit.hs:32–34,158–159,195–202` — assume-guarantee is already the
   verification substrate: `cvPreObligation` (caller **proves** callee pre) + `cvPostAssumption`
   (caller **assumes** callee post). A caller verified against a callee's *contract* needs nothing
   new. **This is Layer 1 — the proving is already solved.**
2. `compiler/src/LLMLL/PatchApply.hs:7,188` — "all op paths must be **descendant-or-self of the
   checkout pointer**"; the patch lifecycle re-typechecks + re-verifies the whole module (steps 6/6.5).
   The scope-check is exactly what forbids introducing a sibling `def` today. **This is Layer 2 — the
   protocol gap.**
3. `compiler/src/LLMLL/TrustReport.hs:24,68–76,222–224` — `effectiveLevel` already propagates a
   transitive-callee **POST** tier up (Position B), consumed by `ObligationAssembly`'s `callee_tier`
   lever; `caller_obligations` is an additive per-entry axis (TRUST-PRE). The up-the-tree propagation
   machinery exists; it carries *tier*, not yet *contract strength*. **Layer 3 reuse point.**
4. `compiler/src/LLMLL/CDP.hs:2–20` — CDP (LT-CDP, v0.11; `contract-discriminative-power-proposal.md`
   Rev 2) enumerates a **closed Ω candidate set**, solves per-candidate, and reports the fraction
   satisfying the contract (`spec-too-tight-for-omega` = maximally discriminative). **Layer 3 core —
   the vacuity detector for invented contracts.** `docs/compiler-team-roadmap.md:224` tracks the CDP
   concept; this proposal **extends** it (spawn-time gate + tree-propagated meet), stated below.
5. `agent-orchestration.md:220,415` — flat hole list, `holes --deps` dependency-graph precursor;
   `examples/withdraw-demo/DemoPost.md` — the compare-and-swap concurrency model this must extend.
   No in-flight draft on cascading refinement exists (checked INDEX + grep) — this is from-scratch.
6. No surface gate: the former feature freeze was retired (2026-07-10); current `llmll 0.14.11`. A new
   `refine` verb is a new orchestration operation — permitted, but named below with its soundness
   argument.

## Design proposal

Three layers. Only Layer 3 is genuinely new logic; Layers 1–2 are composition and protocol.

### Layer 1 — per-step verification (reuse, no new fragment)

A refinement step decomposes hole `H : σ_H` (contract `C_H = pre_H / post_H`) into a body `e_H` that
calls new functions `G₁…Gₙ`, each declared with a contract `C_{Gᵢ}` and a `?body`. The step is
**correct** exactly when `e_H` verifies against `C_H` *assuming* each `C_{Gᵢ}` — the existing
assume-guarantee VC (`cvPreObligation` for each call, `cvPostAssumption` for each result;
FixpointEmit.hs:158–159). Each `Gᵢ` later refines or fills, verified against its *own* `C_{Gᵢ}`.
**Framing (Rev 1 correction).** The whole-tree guarantee is the transitivity of **partial-correctness
compositional Hoare logic** — the procedure-call rule (assume callee spec, discharge callee pre;
FixpointEmit.hs:32–34) composed over the tree — **not** the *total*-correctness refinement calculus of
Back/von-Wright/Morgan, which additionally requires termination and a refinement lattice LLMLL does
not use. Stepwise refinement (Wirth; Morgan) remains the right *intuition* and lineage for the
decomposition move, but the delivered guarantee is partial correctness, converging with the §5.3.5
`letrec` disclaimer. The total-vs-partial gap is *exactly* the acyclicity/termination question that
Layer 2 must discharge (below): compositional Hoare transitivity is sound **only for an acyclic call
graph** (`LLMLL.md:13,24`). **No new proof obligation on the body side** — the per-node VC is the
QF-LIA + acyclic-datatype fragment already discharged (`§5.3.3/§5.3.5`). The one structural cost: a
step grows the module (adds `Gᵢ` statements), triggering re-typecheck + re-verify (PatchApply 6/6.5),
which motivates incremental slice re-verification (R8).

### Layer 2 — the `refine` operation and the growing tree (protocol)

**Surface.** Introduce `refine` as the dual of `patch`: `patch` closes a leaf (body over in-scope
vocabulary only); `refine` *decomposes* a hole by installing a body **and** the sub-functions it
calls, atomically. A `refine` request (held under `H`'s checkout token) carries: (i) the body `e_H`
for `H`; (ii) a list of new top-level defs `Gᵢ = (def NAME_i params_i -> ret_i (pre …)(post …) ?body)`
with fresh names. The operation, under one advisory lock: adds the `Gᵢ` statements, replaces `H`'s
hole with `e_H`, re-typechecks, and re-verifies `H` modulo the `Gᵢ` contracts (Layer 1). It succeeds
only if (a) `H` verifies, (b) each `NAME_i` is fresh, (c) each `C_{Gᵢ}` passes the Layer-3 gate, and
**(d) any call-graph cycle the spawn creates is detected and its members carry the visible `termination_unverified` marker** (below).

**Cycle handling: partial correctness with a visible marker (Rev 3 — reconciled to REC-PARTIAL-MARK, 2026-07-10).**
Compositional Hoare / assume-guarantee over a cycle is sound at **partial** correctness — each member
proves its body assuming its callees' (transitively its own) posts (`LLMLL.md §0.1`; the v0.14.13
reconciliation). A cycle member is therefore **not** contract-only: it verifies body-faithful and can
reach a `verified` post, exactly as a hand-written recursive `def-shell` does. (The Rev-2 premise that
LLMLL "verifies recursive-cycle members contract-only," citing the pre-v0.14.13 `LLMLL.md:13,24`, was
stale and is dropped.) Nothing in the protocol *prevents* an agent from spawning a `Gᵢ` that
transitively calls back into an ancestor `H`. The Rev-0/Rev-1 hazard was that any degradation would be
**silent**. **The decision (2026-07-06, revised 2026-07-10) is Option 3: `refine` ADMITS a
cycle-creating spawn, detects the cycle, and its members verify at partial correctness carrying the
automatic `termination_unverified` marker** (per-entry flag + top-level `partial_fns`, REC-PARTIAL-MARK,
v0.14.23) — the marker is the VISIBLE signal that replaces the silent-degradation hazard, so the trust
closure never launders a partial recursive core into a *total* top claim. This is the correction over
Rev 2: a spawn-created cycle and a hand-written cycle now land at the **same** tier (body-faithful
partial + `termination_unverified`). Grading a refine-path cycle strictly below a hand-written one — the
Rev-2 "fall to contract-only / `asserted`" treatment — was a provenance-dependent verdict the trust
model forbids. The decomposition-trust meet (Layer 3 (d)) surfaces the marker at the cascade top
("verified modulo an unverified-termination recursive core"); it does **not** floor the member to
`asserted`. This is a decidable graph check (detect the cycle) plus marker propagation — **no
reject-gate, and no new SMT obligation** — the same treatment a hand-written cycle receives (`§4.2`,
`§4.4.4`, `§5.3.5`). It is distinct from cascade-*process* termination (Risk 5, an orchestration
budget). **Option 2 (route the cycle to REC-DESCENT / R7 strict-descent) is the follow-up upgrade**, not
a prerequisite: when descent ships, a cyclic node moves from partial to total and the marker clears,
with no redesign. Option 1 (forbid cycles outright) was rejected — it would make cascading unable to
express recursion at all, and the recursion it would forbid is mostly int-recursion (recursive *data* is
already firewalled by the data-scope track), so it buys little at high cost.

This is a **scope relaxation of the patch protocol**, not an unbounded one: a `refine` may add
statements *only* at top level and *only* defs that `e_H` references, so the AST growth is confined
to the refinement `H` licenses. `patch`'s descendant-or-self scope-check (PatchApply.hs:188) stays
for plain fills.

**Growing tree.** The hole model generalizes from a flat list to a tree: `refine`ing `H` makes the
`Gᵢ` holes `H`'s children. `llmll holes` reports the open **frontier** (unrefined, unfilled leaves);
`holes --deps` (agent-orchestration.md:415) becomes the tree. `checkout` briefs already carry
`available_functions`; a child's brief lists its parent-visible siblings as callable vocabulary.

**Concurrency.** A `refine` adds defs → changes the source hash → invalidates outstanding tokens,
exactly the DemoPost compare-and-swap. A refinement is therefore a **structural commit** siblings
resync to (release + re-checkout against the grown tree). This is correct-by-construction (no lost
update) and the reason R8 incremental re-verify matters: a resync after a *sibling* refinement should
re-verify only the affected slice, not the whole tree.

**Termination.** No forced stop: a hole is a **leaf** when the agent chooses `patch` (a body that
fits the fragment) over `refine` (needs helpers). This is where **MATCH-WIDEN is the enabler** — a
richer body-faithful fragment means more holes are directly `patch`-able, so the cascade **bottoms
out at meaningful leaves** instead of spawning trivial micro-functions to dodge the narrow fragment.
A depth/node budget guards runaway refinement (Risk 4); a *no-magic* progress condition (each
`C_{Gᵢ}` must be strictly "smaller" than `C_H` under a syntactic measure) is the refinement-calculus
feasibility analogue — proposed as orchestration policy, not a VC.

### Layer 3 — contract quality: who trusts the invented decomposition (the core)

The soundness threat unique to *agent-invented* decomposition: if a `Gᵢ`'s contract is **too weak**,
`H` verifies against it while the decomposition guarantees nothing. `(def g … (post true) ?body)`
lets any `H` that calls `g` discharge trivially. Refinement calculus assumes a *human* author whose
judgment vouches for each sub-spec; under agent authorship that judgment must be **mechanized**.

**(a) Spawn-time CDP gate — a vacuity FILTER, not a soundness guarantee (Rev 1 recast).** At
`refine`, run CDP (CDP.hs) on each invented `C_{Gᵢ}`: a vacuous contract admits most/all of the closed
Ω candidate set (constant/identity/projection satisfies it), a discriminative one admits few
(`spec-too-tight-for-omega`); reject a spawn whose `C_{Gᵢ}` CDP fraction exceeds a floor `θ`. This
catches naïve vacuity (`post true`). **It is not gaming-resistant, and must not be presented as
making agent-invented decomposition sound.** CDP is inherently **Ω-relative** — it is "observational
over Ω" with *no* Ω-independent check (CDP.hs:21,121–126), and Ω is closed and versioned hence known
(CDP.hs:12,23). An agent optimizing to pass its own gate can craft an Ω-discriminative yet hollow
contract: precisely the **F-002 self-attestation-gaming** class, which the project settled as having
**no follow-on mechanism** (`expiring-intentional-proposal.md:6`). Promoting CDP from diagnostic to
*gate* re-opens that settled-unclosable question as load-bearing, so the gate is a filter, and the
gaming-resistant complement is **peer-relative, not basis-relative** pressure — see (c).

**(b) Feasibility (no-miracle) gate — SETTLED Tier-2, professor-hardened (Rev 5).** Gate each invented
`C_{Gᵢ}`, per-contract, on refinement-calculus **feasibility** (Back/von-Wright/Morgan; Dijkstra's
excluded-miracle law `wp(S, false) = false`): `∀input. pre_Gᵢ(input) ⇒ ∃result. (Rret(result) ∧
post_Gᵢ(input, result))`, where `Rret` is the sub-contract's return-type refinement predicate
α-renamed to `result` (the OBLIG-1 binder discipline; omitting it under-rejects on refined `-> {v|…}`
returns). An **infeasible** contract (some valid input has no satisfying result) makes `Gᵢ` unfillable,
so every downstream fill is refuted at that input and the repair loop cannot converge. **Discharge is a
COMPLETE quantified-LIA procedure — quantifier elimination on the single bound `result` (Cooper/Omega)
reducing to a QF-LIA residual, or `qsat` (Bjørner–Janota) — NOT default MBQI**, which is incomplete for
quantified LIA and can return `unknown`; LIA-completeness is a shipping requirement, so fail-open is the
non-LIA backstop only, not a routine path. The gate rejects iff the negation
`∃input. pre ∧ ∀result. ¬(Rret ∧ post)` is SAT; the model **is the witnessing input**, and it is
**minimized** (νZ, minimize `Σ|inputᵢ|`) so it names the boundary (`x=y=5` for a `-> Pos` `sub` at the
equal-arguments edge) rather than an arbitrary corner. **Why Tier 2, not `SAT(pre ∧ post)` (Tier 1):**
Tier 1 is mere *consistency*, not feasibility — it catches only a *globally* contradictory post and is
blind to the common LLM mistake, a *locally* infeasible post (missing precondition on a partial
operation); it also false-rejects a dead helper (`pre` UNSAT), which Tier 2 correctly admits. **This
gate REALIZES the Ω-independent semantic-infeasibility check reserved at `CDP.hs:119-132`** (the
"structurally different existential SAT query" that comment names as future work), and does so more
correctly than the reserved Tier-1 `UNSAT(pre∧post)` sketch; it is complementary to — not a replacement
for — CDP's Ω-*relative* `WarnSpecInconsistentOrUnproven` epistemic signal. The gate does *not* close
the vacuity-vs-incorrectness gap (Risk 1), nor does it guarantee **fragment-realizability** — a contract
feasible over ℤ may be realizable only outside `Σ_auto` (nonlinear/recursive) or only by an
`Int64`-overflowing witness; "feasible" means feasible over ℤ, so rejections are sound in the machine
model (ℤ-infeasible ⇒ `Int64`-infeasible) while admissions may over-admit (fail-open).

**(c) Peer-relative pressure (R5), first-class.** Because the CDP gate is basis-relative and gameable
(a), the load-bearing gaming-resistant defense is **R5 differential implementation pressure**:
independently-invented decompositions of the same `H`, compared — a sub-contract only one decomposition
needs is suspect. This is promoted from "candidate mitigation" (Rev 0) to a first-class part of the
contract-quality story; it is peer-relative, so it does not degrade against an agent targeting a fixed
public Ω.

**(d) Decomposition-trust propagation — honest reporting, not adversarial-composition soundness.**
Extend `effectiveLevel` (TrustReport.hs:68–76) so a refined function's trust carries a
**decomposition-quality** signal = the **meet** (weakest) of its subtree's invented-contract CDP
scores, surfaced the way `caller_obligations`/`callee_tier` surface tier — a cascade with one vacuous
sub-contract reads weak even if every node is `verified`. **Limitation (Rev 1):** the meet scores
contracts *in isolation* and therefore misses **joint (conspiratorial) vacuity** — two individually-
discriminative sub-contracts that are jointly hollow (`G₁`'s post ∧ `G₂`'s pre together let `H`
discharge vacuously). Contract adequacy is not compositional the way `min` assumes; rely-guarantee
(Jones 1983) frames interacting components but presumes non-adversarial conditions. The meet is an
honest *lower-bound report*, not a soundness guarantee against an adversarially-chosen decomposition —
gating the *composed* decomposition, or R5 (c), is what would catch joint vacuity.

**Research-track relation.** This **extends** the tracked CDP concept (`roadmap:224`), it does not
approximate or sidestep it: CDP today scores one contract in isolation for a human to read; cascading
applies the same score as a *spawn admission gate* and *propagates its meet up the refinement tree*.
The gate threshold `θ` and the meet-propagation are the new spec surface; the score is reused verbatim.

## Edge cases and degenerate inputs

1. **Positive witness — a valid cascade step.** `H = (def verify-kx [...] -> Verdict (post …) ?body)`.
   Agent `refine`s: body `(final-verdict (run-stages …) …)`, spawning `run-stages` and `final-verdict`,
   each with a discriminative contract + `?body`. Expected: `verify-kx` verifies modulo the two
   contracts; both become frontier holes; both CDP-gates pass. Channel: **contract** (per-node VC) +
   **trust** (CDP gate). Cite: FixpointEmit.hs:158–159; CDP.hs.
2. **Positive witness of the guard — too-weak invented contract (must be caught).** Agent `refine`s
   `H` into a call to `(def g [x: int] -> int (post true) ?body)`. Expected: the CDP gate **rejects**
   the spawn — `post true` admits the entire Ω basis (identity, constants, projections all satisfy),
   CDP fraction = 1.0 ≫ θ. Without the gate, `H` would verify vacuously. Channel: **trust** (CDP
   discrimination floor). This is the minimal concrete firing input for the Layer-3 guard.
3. **Discriminative-but-wrong contract (NOT caught — honest gap).** Agent invents a `C_g` that is
   discriminative (passes CDP) but does not capture the *intended* behavior (`g` computes the wrong
   function, yet `H` and `g` both verify against `C_g`). Expected: **admitted** — CDP measures
   non-vacuity, not correctness. Channel: **spec is silent (gap — flag)**. This is the
   specification-adequacy limit and the top risk; it is why the top-level contract must remain
   human-authored or externally anchored (`specification-sources.md`). No compiler channel closes it;
   R5 differential pressure or multi-agent decomposition agreement are the candidate mitigations.
4. **Runaway refinement.** An agent `refine`s without ever `patch`ing. Expected: bounded by a
   depth/node budget; beyond it, the frontier hole is forced to `patch`-or-fail. Channel: **trust**
   (orchestration budget), not a VC. Cite: no current site — new budget.
5. **Name collision on spawn.** A spawned `Gᵢ` name already binds. Expected: `refine` rejected at
   re-typecheck (duplicate top-level binding). Channel: **type**. Cite: PatchApply step 6 re-typecheck.
6. **Cycle-creating spawn (Rev 1 — the acyclicity guard's positive witness).** Agent `refine`s `H`
   into a body calling a spawned `G` whose own contracted `?body` will (per the frontier) need to call
   back into `H` (or `H`'s ancestor) — a call-graph cycle. Expected: `refine` **rejected** by the
   acyclicity side-condition (Layer 2 (d)), or the cycle routed to R7 strict-descent with a termination
   obligation. Without the guard, the cycle members degrade to contract-only (`asserted`) while the
   tree reports `verified` — an unsound top claim. Channel: **type/trust** (a decidable call-graph
   acyclicity check). Cite: `LLMLL.md:13,24,465`. This is the concrete firing input for fold #1.
7. **Infeasible invented contract — the feasibility gate's witnesses (Rev 5: local, global, refined, dead, ℤ).**
   (i) *Local* infeasibility: `(def sub [x: int, y: int] -> int (pre true) (post (and (= result (- x y))
   (>= result 0))) ?body)` — impossible when `x < y`. **Rejects**, minimal witness `x=0, y=1`; the agent
   adds `(pre (>= x y))`. (ii) *Global* contradiction `(post (and (> result x) (< result x)))` — rejects
   for every input. (iii) *Refined-return* infeasibility (Δ2 positive witness): `(def sub [x, y] -> Pos
   (pre (>= x y)) (post (= result (- x y))) ?body)` — at `x = y` the only post-witness is `0 ∉ Pos`.
   **Rev-5 rejects** with witness `x=5, y=5`; Rev-4 (unrefined domain) admitted it. (iv) *Dead helper*
   `(pre false)` — **admits** (vacuously feasible); the reserved Tier-1 `UNSAT(pre∧post)` would have
   mis-rejected it (Δ4). (v) *ℤ-only witness* (a `result` only outside `Int64`) — **admits** (feasible
   over ℤ, a missed rejection tolerated by fail-open); rejections stay sound in the machine model.
   Channel: **trust** (feasibility, QE-complete quantified-LIA). Cite: Layer 3 (b); `CDP.hs:119-132`;
   `LLMLL.md §5.3.5`.

## Verification mapping

- **Per-node refinement-step VC** — Channel: **contract**. Fragment: **QF-LIA + acyclic-datatype**,
  auto-discharged by liquid-fixpoint — it *is* the existing assume-guarantee VC (FixpointEmit.hs:158–
  159), no new fragment, no new obligation shape. `LLMLL.md §5.3.3/§5.3.5`.
- **Contract-quality (CDP) gate** — Channel: **trust** (an evidence-axis check, not a body-VC).
  Fragment: **QF-LIA** — CDP solves one `.fq` per Ω candidate (CDP.hs), each in the existing
  auto-discharge fragment. The *new* content is the threshold `θ` and the admission decision, not a
  new solver obligation.
- **Feasibility gate (Rev 5 — SETTLED Tier 2, QE-complete)** — Channel: **trust**. Fragment:
  **quantified LIA made decidable-and-complete by QE** — `∀input. pre ⇒ ∃result. (Rret ∧ post)`;
  eliminating the single bound `result` (Cooper/Omega) yields a **QF-LIA residual** auto-dischargeable
  in the fragment the compiler already owns (`LLMLL.md §5.3.3`), or discharge the whole via `qsat`.
  **Never default MBQI** (incomplete → `unknown`); LIA-completeness is required, not fail-open. Reject
  iff `∃input. pre ∧ ∀result. ¬(Rret ∧ post)` is SAT; the νZ-minimized model is the returned witness.
  A new admission check discharged by a complete quantified-LIA procedure, not a new body-VC. (Tier-1
  `SAT(pre ∧ post)` is mere consistency, not feasibility — superseded.)
- **Decomposition-trust meet** — Channel: **trust**. No solver: a lattice meet over subtree CDP
  scores, propagated by the existing `effectiveLevel` machinery (TrustReport.hs:68–76). No fragment.
- **Call-graph acyclicity (Rev 1)** — Channel: **type/trust**. Fragment: **none** — a decidable graph
  reachability check on the augmented call graph at each `refine`, *not* an SMT obligation. (A
  legitimately-recursive decomposition routed to R7 would add a strict-descent obligation; QF-LIA if a
  linear `:decreases` measure, else research-track.)
- **Net:** cascading refinement introduces **no new QF-LIA/nonlinear/Lean *body* obligation** — the
  per-node VC is unchanged assume-guarantee. Its novelty is the **trust channel** (CDP-as-filter +
  feasibility + strength propagation), a **graph-acyclicity side-condition** (fold #1), and the
  **protocol** (Layer 2). The hard part is orchestration + trust composition + the acyclicity guard,
  not new verification math.

## Affected surface

- `compiler/src/LLMLL/PatchApply.hs` — the `refine` operation (scope-relaxed, top-level-def-adding,
  atomic add-body-and-subholes); its re-verify path reuses steps 5–6.5.
- `compiler/src/LLMLL/CDP.hs` — expose the per-contract CDP fraction as a spawn-admission predicate
  with a floor `θ`.
- `compiler/src/LLMLL/TrustReport.hs:68–76` — add the decomposition-quality meet to `effectiveLevel`.
- `compiler/src/LLMLL/HoleAnalysis.hs` + `holes --deps` (agent-orchestration surface) — the
  growing-tree model + frontier reporting.
- Checkout/lock machinery (`Checkout.hs`) — resync semantics for a structural (spawn) commit.
- `LLMLL.md §9` / a new subsection (doc-lead) — the `refine` operation and refinement-tree model.
- `docs/compiler-team-roadmap.md` (doc-lead) — a first-class track; relates to **R2** (self-hosted
  orchestrator), **R8** (incremental re-verify), and **CDP** (`:224`).
- **Surface-gate status:** none — the former feature freeze was retired; `refine` is permitted with the
  soundness argument (Layer 1 correctness + Layer 3 gate). Name it, do not grant silently.
- **Strict immutability:** preserved. `refine` is pure AST **growth** — it adds new immutable
  statements and replaces one hole node with a body; no existing node is mutated, no reference
  aliased. Consistent with the no-mutable-references invariant.

## Risks and open questions

1. **Silent cycle degradation (Rev 2 — resolved, no longer blocks).** *Soundness.* Assume-guarantee is
   sound only for acyclic call graphs (`LLMLL.md:13,24,465`); a spawned cycle degrades its members to
   contract-only. The Rev-1 framing ("blocks — must reject or R7") is **superseded** by the decided
   **Option 3** (Layer 2 (d)): admit the cycle, detect it (already done, `:24`), and floor the
   decomposition-trust meet on contract-only cycle members so the degradation is *visible*. *Bite: no
   longer blocks* — the fix is a decidable cycle-detect + a trust-closure floor, not a reject-gate and
   not R7. R7 strict-descent is the follow-up total-correctness upgrade.
2. **CDP catches vacuity, not incorrectness — and the gate is Ω-gameable.** *Soundness (adequacy +
   gaming).* The spawn gate admits a discriminative-yet-wrong decomposition (edge case 3), and because
   CDP is Ω-relative with a known basis (CDP.hs:12,21,23,121–126) an adversarial author can pass it
   with a hollow-but-discriminative contract — the F-002 settled-unclosable class
   (`expiring-intentional-proposal.md:6`). "Is this the *right* decomposition" is the
   specification-adequacy/oracle problem, not fully mechanizable. *Bite: bounds the trust claim* —
   cascading yields "verified against a decomposition whose sub-contracts are each non-vacuous and
   feasible," strictly weaker than "verified against a human-vouched spec"; the top contract must stay
   externally anchored, and R5 (Layer 3 (c)) is the gaming-resistant complement. *Does not block; it
   bounds what may be claimed.*
3. **The trust meet misses joint (conspiratorial) vacuity.** *Soundness (composition).* `min` over
   isolated CDP scores does not detect two sub-contracts jointly hollow (Layer 3 (d)). *Bite: the meet
   is honest reporting, not an adversarial-composition guarantee* — gate the composed decomposition or
   lean on R5.
4. **Protocol + tree + resync is real orchestration work.** *Scope.* Layer 2 is R2/R8 territory.
   *Bite: the build, not the design.*
5. **Cascade-process non-termination (runaway refinement).** *Scope.* An agent may `refine` without
   bottoming out — distinct from #1 (that is *program* call-graph acyclicity; this is the *process*).
   *Bite: minor* — depth/node budget + a no-magic progress measure.
6. **Re-verify cost per refinement.** *Verification-ergonomics.* PatchApply re-verifies the whole
   module per step (6/6.5). *Bite: at scale* — needs R8 incremental slice re-verify.
7. **Threshold `θ` calibration.** *Verification-ergonomics.* Too high rejects loose-but-honest
   contracts; too low admits near-vacuous ones. *Bite: only at scale* — empirical calibration
   (experiment-lead); `θ` interacts with the `spec-entropy :intentional` surface (F-002 lineage).

## Professor review — resolved + open (Rev 1)

The Rev-0 questions to the professor are **answered**: (1) refinement-calculus *feasibility* is a
genuine complementary criterion — it catches infeasibility, the opposite of vacuity — and is
QF-LIA-mechanizable, now Layer 3 (b); it does **not** close the vacuity-vs-incorrectness gap, which is
the oracle problem (convergence, Risk 2). (2) The meet is honest reporting, not an
adversarial-composition guarantee (Layer 3 (d)); the gaming-resistant composition is peer-relative R5
(Layer 3 (c)), not a stronger meet.

Two questions the professor routed **back to language-team**:

1. **Acyclicity policy — RESOLVED (Rev 2, 2026-07-06): Option 3.** `refine` neither forbids the cycle
   nor blocks on R7; it **admits, detects, and honestly degrades** (contract-only cycle members, trust
   meet floored so nothing is laundered — Layer 2 (d)). Cascading *can* express recursion, as
   partial-correctness, exactly like `letrec`; R7 strict-descent is the follow-up that upgrades it to
   total. Rationale: the hazard was silent degradation, not the cycle; forbidding would kill recursion
   for little gain (recursive *data* is already firewalled by data-scope).
2. **Per-contract vs composed gating — RESOLVED (Rev 4, 2026-07-18): per-contract.** Both spawn-admission
   gates (CDP vacuity — already shipped per-contract v0.14.13 — and Tier-2 feasibility) run per invented
   sub-contract. Feasibility *is* a per-contract property (`∀input. pre ⇒ ∃result. post` is about one
   contract); folding joint vacuity into it is a category error. Joint (conspiratorial) vacuity is an
   adequacy problem, routed to **R5 peer-relative pressure** (Layer 3 (c)), not to the gate — confirming
   R5 as the intended cover (Risk 3 unchanged).

## Rev 1 changelog (professor fold)

Folded the professor critique of Rev 0. Substantive changes:

1. **Acyclicity obligation added — the blocking fix.** `refine` gains a soundness side-condition
   (Layer 2 (d)): reject a cycle-creating spawn or route to R7, because assume-guarantee is sound only
   on acyclic call graphs (`LLMLL.md:13,24,465`). Promoted to **Risk 1 (soundness, blocks)**; new edge
   case 6; new verification-mapping row (decidable graph check, not SMT).
2. **CDP gate recast as a vacuity *filter*, not a soundness guarantee** (Layer 3 (a)) — named its
   Ω-gameability and the F-002 settled precedent (`expiring-intentional-proposal.md:6`); **R5
   differential pressure promoted to first-class** (Layer 3 (c)).
3. **Feasibility (no-miracle) gate added** (Layer 3 (b)) — `pre ⇒ ∃result.post`, QF-LIA SAT; new edge
   case 7; new verification-mapping row.
4. **Framing corrected** (Layer 1) — the guarantee is partial-correctness compositional Hoare, not
   total-correctness refinement calculus; the total-vs-partial gap is exactly the acyclicity question.
5. **Joint-vacuity flagged** (Layer 3 (d), Risk 3) — the meet is honest reporting, not
   adversarial-composition soundness.
6. **Convergence named** — the professor and this proposal agree that vacuity ≠ incorrectness is the
   irreducible oracle-problem ceiling (Risk 2).

## Rev 2 changelog (acyclicity decision)

User decision (2026-07-06): **Option 3 for the acyclicity policy** — `refine` admits cycle-creating
spawns, detects the cycle, and honestly degrades its members to contract-only with the trust meet
floored (Layer 2 (d)), rather than rejecting or blocking on R7. **Risk 1 downgraded from "blocks" to
"resolved"** (the fix is cycle-detect + trust-floor, not a reject-gate). **Professor open-question 1
(acyclicity policy) marked RESOLVED.** R7 strict-descent recorded as the follow-up total-correctness
upgrade (Option 2). Rationale: the hazard was *silent* degradation, not the cycle; the treatment
mirrors `letrec` partial-correctness (§5.3.5); forbidding (Option 1) would kill recursion for little
gain since recursive *data* is already firewalled by the data-scope track. **One professor question
remains open** (per-contract vs composed gating for joint vacuity). Next: doc-lead roadmap/INDEX entry
for the cascading track.

## Rev 4 changelog (feasibility gate settled → ready for engineer)

User adjudication (2026-07-18): the feasibility (no-miracle) gate ships as **Tier 2 — true
refinement-calculus feasibility** (`∀input. pre ⇒ ∃result. post`), per-contract. Substantive changes:

1. **Layer 3 (b) settled** — Tier-2 feasibility (Presburger, decidable via a direct Z3 query) over the
   Tier-1 `SAT(pre ∧ post)` weakening. Rationale is agent-iteration burden: the infeasible contracts
   LLMs actually author are *locally* infeasible (missing precondition on a partial operation), which
   Tier 1 admits and Tier 2 catches; Tier 2 also returns the witnessing input (the model of the negated
   query), naming the precondition to add. Tier 1 recorded as the documented-gap fallback only if the
   direct-Z3 path is deferred.
2. **Verification-mapping row corrected** — the feasibility gate is **quantified LIA / Presburger via a
   direct Z3 query**, NOT the QF-LIA liquid-fixpoint path the Rev-1 row claimed. It stays in `Σ_auto`'s
   decidable envelope but introduces a new solver-invocation shape.
3. **Professor open-question 2 (per-contract vs composed) RESOLVED — per-contract.** Joint vacuity stays
   routed to R5 (Layer 3 (c)); the gate does not attempt it.
4. **Status → ready for `compiler-engineer`.** The remaining Layer-3 work (Tier-2 feasibility gate +
   decomposition-trust meet) has no open design question.

## Rev 5 changelog (professor fold)

Folded the professor critique of Rev 4 (six findings; both professor open questions answered in-body).
Substantive changes:

1. **Discharge hardened to a COMPLETE quantified-LIA procedure** (finding 1) — QE on the single bound
   `result` (Cooper/Omega) → QF-LIA residual, or `qsat`; never default MBQI. LIA-completeness is a
   shipping requirement; fail-open demoted to the non-LIA backstop. Converges with the engineer's sole
   open question (z3 `unknown`), retiring it. Layer 3 (b) + verification-mapping row updated.
2. **`∃result` quantifies over the REFINED return type** (finding 2; answers professor Open Q2) —
   conjoin the return-type refinement `Rret` (α-renamed to `result`, the OBLIG-1 discipline) into the
   existential; omitting it under-rejects on `-> {v|…}` returns. New edge case 7(iii) positive witness.
3. **Minimal witness** (finding 3) — the rejection returns a νZ-minimized input so it names the
   boundary, not an arbitrary corner; normative because the witness is Tier-2's whole rationale.
4. **Realizes the reserved `spec-inconsistent`** (finding 5; answers professor Open Q1) — the gate is
   the Ω-independent semantic-infeasibility check `CDP.hs:119-132` reserves, stronger and more correct
   than the reserved Tier-1 `UNSAT(pre∧post)` sketch (which mis-rejects dead helpers); complementary to
   CDP's Ω-relative epistemic warning. Redirect the CDP comment (engineer).
5. **Claim-scoping** — "feasible" is over ℤ, so rejections are sound in the machine model and admissions
   over-admit (finding 4, edge case 7(v)); the gate does not guarantee fragment-realizability (finding
   6). Both bound the "no-miracle" claim without changing behavior.

Engineer deltas from the Rev-4 plan: (1) discharge tactic = QE or `qsat`, LIA-complete, not default
`check-sat`; (2) `∃result` conjoins `Rret`; (3) reject path returns a νZ-minimized witness; (4) redirect
the `CDP.hs:119-132` comment. Module placement, `refineGate` seam, fail-open backstop, and test family
from Rev 4 stand.
