---
name: cascading-refinement-proposal
title: "CASCADING REFINEMENT — agent-driven recursive hole decomposition"
status: "Rev 2 (acyclicity decided: Option 3) — design-ahead-of-build, sequenced after MATCH-WIDEN"
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
**(d) any call-graph cycle the spawn creates is detected and its members honestly degraded** (below).

**Cycle handling: honest partial-correctness degradation (Rev 2 — decided).** Compositional
Hoare / assume-guarantee is sound **only** for acyclic call graphs: LLMLL "excludes functions in
recursive call cycles from compositional encoding and verifies [them] contract-only"
(`LLMLL.md:13,24`; mutual recursion forces `def-shell`, `:465`). Nothing in the protocol *prevents*
an agent from spawning a `Gᵢ` that transitively calls back into an ancestor `H`. The Rev-0/Rev-1
hazard was not the cycle itself but that the degradation is **silent** — the cycle members fall to
`asserted` while the tree keeps reporting per-node `verified`. **The decision (2026-07-06) is
Option 3: `refine` ADMITS a cycle-creating spawn, detects the cycle (LLMLL already does, `:24`), lets
its members fall to contract-only — but makes the degradation VISIBLE**, so the trust-closure never
launders a recursive core into a full `verified` top claim. Concretely, the decomposition-trust meet
(Layer 3 (d)) must **floor on any contract-only cycle member**: a cascade containing a recursive core
reads honestly as "verified modulo a partial recursive core," never silently `verified`. This is a
decidable graph check (detect the cycle) plus a trust-closure floor — **no reject-gate, and no new
SMT obligation** — and it is exactly the treatment `letrec` already receives (§5.3.5
partial-correctness). It is distinct from cascade-*process* termination (Risk 5, an orchestration
budget). **Option 2 (route the cycle to R7 strict-descent) is the follow-up upgrade**, not a
prerequisite: when R7 ships, a cyclic node moves from partial (`asserted`) to total (`verified`) with
no redesign. Option 1 (forbid cycles outright) was rejected — it would make cascading unable to
express recursion at all, and the recursion it would forbid is mostly int-recursion (recursive *data*
is already firewalled by the data-scope track), so it buys little at high cost.

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

**(b) Feasibility (no-miracle) gate — a second, complementary check (Rev 1 add).** Gate each invented
`C_{Gᵢ}` on **feasibility**: `pre_Gᵢ ⇒ ∃ result. post_Gᵢ` (refinement-calculus feasibility, Back/von-
Wright/Morgan). This catches the pathology *opposite* to vacuity — an **infeasible** invented contract
(post unsatisfiable for some valid input) makes `Gᵢ` unfillable, stalling the cascade or letting an
agent hide behind an impossible sub-goal. It is a QF-LIA **satisfiability** check on `pre ∧ post` —
decidable, cheap, orthogonal to CDP. It does *not* close the vacuity-vs-incorrectness gap (Risk 1);
data-refinement simulation (Hoare–He–Sanders; Gardiner–Morgan) is the tool for that only when a step
changes data *representation*, which is not the common case here — available-if-needed, not a general
closer.

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
7. **Infeasible invented contract (Rev 1 — the feasibility gate's witness).** Agent `refine`s `H` into
   a call to `(def g [x: int] -> int (pre (>= x 0)) (post (< result 0)) ?body)` whose post is
   satisfiable, but consider instead `(post (and (> result x) (< result x)))` — unsatisfiable for
   every `x`. Expected: the **feasibility gate rejects** the spawn — `∃result. post` is UNSAT, so `g`
   is unfillable and `H`'s "proof" leans on an impossible sub-goal. Channel: **trust** (feasibility
   SAT check, QF-LIA). Cite: Layer 3 (b).

## Verification mapping

- **Per-node refinement-step VC** — Channel: **contract**. Fragment: **QF-LIA + acyclic-datatype**,
  auto-discharged by liquid-fixpoint — it *is* the existing assume-guarantee VC (FixpointEmit.hs:158–
  159), no new fragment, no new obligation shape. `LLMLL.md §5.3.3/§5.3.5`.
- **Contract-quality (CDP) gate** — Channel: **trust** (an evidence-axis check, not a body-VC).
  Fragment: **QF-LIA** — CDP solves one `.fq` per Ω candidate (CDP.hs), each in the existing
  auto-discharge fragment. The *new* content is the threshold `θ` and the admission decision, not a
  new solver obligation.
- **Feasibility gate (Rev 1)** — Channel: **trust**. Fragment: **QF-LIA** — a *satisfiability* check
  on `pre ∧ post` (`∃result. post` under `pre`), decidable in the auto-discharge fragment. A new
  admission check, not a new body-VC obligation shape.
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
2. **Per-contract vs composed gating — OPEN.** Is the CDP/feasibility gate applied per-contract (cheap, but
   joint-vacuity uncaught — Layer 3 (d)) or to the *composed* decomposition (catches conspiracy,
   expensive)? If per-contract, confirm R5 (c) is the intended cover for joint vacuity.

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
