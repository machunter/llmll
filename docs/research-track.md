# LLMLL Research Track

> **Last updated:** 2026-05-01  
> **Purpose:** Track unversioned research items that may feed into future compiler releases.  
> **Relationship to compiler roadmap:** Items here are *not* part of the compiler engineering backlog ([compiler-team-roadmap.md](compiler-team-roadmap.md)). Each item is promoted to a versioned release only when its **promotion criterion** is met and the compiler team accepts the work.

---

## How Items Are Promoted

1. The research item meets its stated **promotion criterion** (below).
2. A design spec is produced and reviewed.
3. The compiler team accepts the spec and schedules the work into a versioned release.

Until all three conditions are met, the item stays here.

---

## Impact Analysis

> **Assessment date:** 2026-05-01  
> **Context:** The project's strategic bet is that specifications matter more than implementations ([strategic-positioning.md](design/strategic-positioning.md)). The spec-adequacy infrastructure is shipped (weakness-check, spec-coverage, invariant registry). The verification pipeline is operational (452 tests, liquid-fixpoint). Body-faithful VCs shipped (v0.8.0). Evidence model shipped (v0.8.1b). Compositional verification shipped (v0.9.0). Research items are ranked by how much they advance the strategic bet.

| Rank | Item | Impact | Rationale |
|------|------|--------|-----------|
| **1** | **Differential impl pressure** | **High** | Directly attacks the identified strategic weakness: spec quality. Makes underspecification *painful* by having N agents fill the same hole and flagging divergence. Exploits exactly what LLMLL already has (typed holes + multiple agents + verification gates). External consultant concurs: "prototype differential divergence detection without synthesis" is near-term actionable. |
| **2** | **Contract discriminative power** | **Medium-high** | Provides a scalar metric for spec quality. Without a number, you can't set CI thresholds, compare approaches, or track improvement over time. External consultant recommends formalizing this with finite observational semantics. |
| **3** | **Spec-from-RFC pipeline** | **Medium-high** | Makes the system useful on real problems where specs already exist. External consultant elevates this: "LLMLL's strongest target domains already have external specs. Require clause provenance: external paragraph → LLMLL pre/post/law → verification level." Traceability from external spec to verification level is the key differentiator. |
| **4** | **Call-site strict descent** | **Medium** | External consultant correction: "not automatically subsumed by BODY-VC. Body encoding and termination checking are related but not identical proof obligations." Since BODY-VC-0 excludes `letrec`, strict descent still needs its own design rule. Upgraded from Low. |
| **5** | **Indexed/dependent types** | **High ceiling, high risk** | If the hypothesis holds, it's transformative. But indexed types create preservation, progress, totality, erasure, and type-level normalization obligations. External consultant: "Keep this as a narrow spike; do not let it become half of Idris." **Note (2026-05-01):** The highest-value part of the original "type-driven development" idea — obligation-guided agent coding — has been **promoted to v0.10** on the compiler roadmap. This research item now covers only the indexed-type extension (Vect n a, GADTs, type-level arithmetic), which remains deferred. |
| **6** | **Synthetic training corpus** | **Medium, uncertain** | Addresses whether agents can learn to write better specs. ML research with uncertain outcomes. |
| **7** | **Self-hosted orchestrator** | **Low** | External consultant: "adds IO, concurrency, JSON, and effect proof obligations without improving the core verification story. Valuable only after BODY-VC and the effect model are settled." |

---

## Active Research Items

### 1. Indexed / Dependent Types

> **Source:** [type-driven-development.md](design/type-driven-development.md)

> [!IMPORTANT]
> **The obligation-guided agent coding part of this idea has been promoted to v0.10** on the compiler roadmap ([compiler-team-roadmap.md](compiler-team-roadmap.md) § v0.10). What remains here is the indexed-type extension only: `Vect n a`, GADTs, dependent pattern matching, type-level arithmetic, and bidirectional typechecking.

**Original hypothesis:** Step-by-step type-guided deduction (Idris-style case-splitting) improves LLM agent accuracy for hole-filling compared to one-shot contract-based generation.

**Professor's resolution (2026-05-01):** The hypothesis is correct, but 80% of the agent-facing benefit is achievable *without* indexed types. The v0.10 milestone achieves this through structured obligation reports (type + contract + trust), `EMatch` branch obligations, and repair suggestions — using the existing type system.

**What remains in research:** True indexed types (`Vect n a`) require:

| Requirement | Impact |
|---|---|
| Type-level naturals | New kind in the type system |
| Type-level computation (`n + m`) | Type-level evaluator in `TypeCheck.hs` |
| GADT-style pattern matching | Branch type refinement |
| Dependent elimination | Return type depends on matched constructor |
| Bidirectional typechecking | Replaces Algorithm W (Dunfield-Krishnaswami style) |
| Erasure analysis | Which type-level terms exist at runtime |

Each is a multi-week project with deep interactions with the existing type inference engine. Algorithm W does not handle GADTs.

**Compiler impact if promoted:** Fundamental architecture change to `TypeCheck.hs`. Significant — not scoped to a fragment.

**Interaction with v0.10:** v0.10 (obligation-guided coding) does not require indexed types and does not change Algorithm W. Indexed types would be an orthogonal addition.

**Promotion criterion:** Design spec with typing rules for indexed types, bidirectional typechecking migration plan, and erasure strategy.

---

### 2. Self-Hosted Orchestrator

> **Source:** [agent-orchestration.md §Option B](design/agent-orchestration.md)

**Goal:** Rewrite the Python `llmll-orchestra` as an LLMLL program with `def-main :mode cli`. The orchestrator becomes a verified program with contracts on coordination correctness.

**Feature gap (from source doc):**

| Need | LLMLL has it? | Gap |
|------|--------------|-----|
| HTTP POST to `llmll serve` | ✅ `wasi.http.post` | — |
| HTTP POST to LLM APIs | ✅ `wasi.http.post` | — |
| JSON parsing | ✅ `(import haskell.aeson ...)` (v0.4 Aeson FFI) | — |
| State machine loop | ✅ `def-main :mode cli` | — |
| Pattern matching | ✅ `match` on `Result` + `DelegationError` | — |
| Concurrent agent calls | ✅ `?delegate-async` | — |

The only gap identified in the original design doc (JSON parsing) was closed in v0.4 via the Aeson FFI.

**Compiler impact if promoted:** None — the orchestrator uses existing compiler primitives. The compiler team's role is limited to ensuring `llmll serve` API stability.

**Promotion criterion:** Agent accuracy ≥80% on the auth module exercise when filling LLMLL-source holes.

---

### 3. Spec-from-RFC Pipeline

> **Source:** [specification-sources.md §1](design/specification-sources.md)

**Goal:** For LLMLL's target domains (financial, protocol, encryption), external specs already exist as RFCs. Build a pipeline that translates structured external specs into LLMLL contracts.

**Compiler impact if promoted:** Minimal — the pipeline would produce `.ast.json` files that the compiler already consumes.

**Promotion criterion:** Concrete pipeline design doc with at least one worked example (e.g., ERC-20 standard → LLMLL contracts).

---

### 4. Synthetic Training Corpus (Hackage Back-Translation)

> **Source:** [specification-sources.md §5](design/specification-sources.md)

**Goal:** Generate training data for fine-tuning LLMs on LLMLL by back-translating Haskell packages from Hackage.

| Phase | Work |
|-------|------|
| 1 | Haskell-to-LLMLL transpiler for a subset of Hackage (type sigs, QuickCheck props, LH annotations) |
| 2 | Spec lifting: infer contracts from implementations + tests |
| 3 | Benchmark: measure agent hole-fill accuracy before/after fine-tuning |

**Compiler impact if promoted:** None — produces training data, not compiler changes.

**Promotion criterion:** Research proposal with measurable hypothesis and evaluation methodology.

---

### 5. Differential Implementation Pressure

> **Source:** [invariant-discovery-proposal.md §3](design/invariant-discovery-proposal.md) + [invariant-discovery-review.md §3](design/invariant-discovery-review.md)  
> **Professor's assessment:** "Highest-value, most architecturally aligned idea"

**Goal:** `llmll checkout --multi` allows N agents to independently fill the same `?delegate` hole. After all fills arrive, divergence analysis generates distinguishing inputs and flags underspecification.

**Compiler impact if promoted:** New `--multi` flag on `llmll checkout`, new divergence analysis pass in a new module (e.g., `DivergenceCheck.hs`).

**Promotion criterion:** Agent accuracy baseline established (need to know what "normal" divergence looks like before flagging abnormal divergence).

---

### 6. Contract Discriminative Power

> **Source:** [invariant-discovery-review.md §6](design/invariant-discovery-review.md)  
> **Proposed by:** Professor (Lead Consultant for Formal Language Design)

**Goal:** Formalize a scalar metric for contract quality:

> **Contract discriminative power** of a specification `S` over type `T → U`: the inverse of the number of observationally-distinguishable implementations of `T → U` that satisfy `S`, measured over a reference test suite of cardinality `N`.

High discriminative power = strong contract. Low discriminative power = weak or missing invariants.

**Compiler impact if promoted:** New metric in `SpecCoverage.hs` output; possible CI gate threshold.

**Partially shipped precursors:** `--spec-coverage` (v0.6.0) provides function-level coverage. `--weakness-check` (v0.3.5) detects trivially-satisfiable contracts. What remains is the formal discriminative-power scalar and CI integration.

**Promotion criterion:** Math spec ready for implementation (definitions, measurement procedure, example calculations).

---

### 7. Call-Site Strict Descent

> **Source:** [LLMLL.md §5.3.3](../LLMLL.md)

**Goal:** Encode `measure(args') < measure(args)` at each recursive call site for `letrec :decreases` measures. Currently, the verifier checks `n >= 0` (well-foundedness domain membership) but not that the measure strictly decreases at each recursive call.

**Status: NOT automatically subsumed by BODY-VC** (external consultant correction, 2026-04-28). Body encoding and termination checking are related but distinct proof obligations. Since BODY-VC-0 excludes `letrec` (confirmed in approved spec, 2026-04-29), strict descent needs an independent design rule. Even when BODY-VC eventually handles `letrec` bodies, the termination measure constraint (`measure(args') < measure(args)`) is a separate well-foundedness obligation from the functional correctness VC (`body ⊢ post`).

**Compiler impact if promoted:** Extension to `emitFnConstraints` in `FixpointEmit.hs` — add a constraint per recursive call site checking `measure(args') < measure(args)`. This is independent of BODY-VC and can be implemented on its own.

**Promotion criterion:** Independent design spec for call-site descent constraint generation, covering at least simple variable measures.

---

## External Consultant Review (2026-04-28)

> **Reviewer:** External consultant (independent project evaluation)  
> **Scope:** Full worktree review including compiler tests, orchestrator tests, documentation audit, and research track assessment. Compiler tests now at 452 (v0.9.0).

### Key Findings

| Finding | Impact | Resolution |
|---------|--------|------------|
| Python dry-run fixture stale | Test drift | ✅ Fixed |
| LLMLL.md / SpecCoverage JSON drift | Doc drift | ✅ Fixed (SUPP-DEBT, v0.8.0) |
| Call-site strict descent is NOT subsumed by BODY-VC | Analysis correction | Updated item #7 above |
| Spec-from-RFC should require clause provenance traceability | Scope refinement | Updated item #3 impact ranking |
| Self-hosted orchestrator blocked on BODY-VC + effect model | Sequencing | Confirmed low priority |

### Consultant's Recommended Near-Term Ordering

1. ~~Fix the Python dry-run fixture/test drift~~ ✅ Complete
2. ~~Reconcile LLMLL.md with actual SpecCoverage JSON~~ ✅ Complete
3. ~~Write BODY-VC-0 design spec~~ ✅ Complete — shipped in v0.8.0
4. Formalize finite observational contract discriminative power
5. Prototype differential divergence detection without synthesis
6. Promote Spec-from-RFC with a worked traceability example

> [!NOTE]
> Items 1–3 are resolved. Items 4–6 are the remaining research track work.

---

## Relationship to Other Documents

| Document | Relationship |
|----------|-------------|
| [compiler-team-roadmap.md](compiler-team-roadmap.md) | Engineering backlog. Research items are promoted there when accepted. |
| [design/INDEX.md](design/INDEX.md) | Reading guide for all design documents, including source docs for research items. |
| [design/invariant-discovery-review.md](design/invariant-discovery-review.md) | Professor's review of invariant discovery mechanisms — source for items 5 and 6. |
| [design/invariant-discovery-proposal.md](design/invariant-discovery-proposal.md) | External team's full proposal with 9 mechanisms. |
| [design/spec-adequacy-closure.md](design/spec-adequacy-closure.md) | Implementation plan for spec gap closure (Tracks 1–3, all shipped). |
| [design/strategic-positioning.md](design/strategic-positioning.md) | What to overclaim and what not to. Item 4 (synthetic corpus) directly addresses the "agents can write good specs" overclaim. |
