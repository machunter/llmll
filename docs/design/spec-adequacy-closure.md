# Closing the Specification Gap — Design Review & Implementation Plan

> **Status:** Approved in design; implementation planned for v0.3.5–v0.4  
> **Date:** 2026-04-19  
> **Participants:** External reviewer (critique originator), Professor (Lead Consultant for Formal Language Design)  
> **Source documents:** [`invariant-discovery-review.md`](invariant-discovery-review.md), [`invariant-discovery-proposal.md`](invariant-discovery-proposal.md), [`specification-sources.md`](specification-sources.md), [`lead-agent.md`](lead-agent.md), [`strategic-positioning.md`](strategic-positioning.md)

### Review History

| Date | Action | Status |
|------|--------|--------|
| 2026-04-19 | External critique published | Addressed |
| 2026-04-19 | Professor assessment + v1 proposal | Revised |
| 2026-04-19 | External reviewer feedback on v1 | Incorporated |
| 2026-04-19 | v2 proposal (this document) | **Accepted in design** |

---

## 1. The External Critique

An external reviewer assessed the project and concluded:

> *"The project looks farther along at verifying implementations than at ensuring strong specs are produced and shown to work on realistic problems."*

Three specific claims:

| Claim | Assessment |
|-------|-----------|
| **The biggest gap is spec generation and validation, not compiler surface area.** The project can prove "implementation matches contract" but not "contract matches intent." | Correct — and acknowledged by the project's own docs ([`one-pager.md`](../one-pager.md), [`strategic-positioning.md`](strategic-positioning.md), [`specification-sources.md`](specification-sources.md)) |
| **The examples are toy programs**, not benchmarked workloads from target domains. | Correct. Hangman, Tic-Tac-Toe, Conway's Life are pedagogically appropriate but have thin specification surfaces. |
| **Orchestration hardening is a second-tier gap** — some acceptance criteria remain unchecked. | Partially correct but overstated. The compiler primitives are shipped; the orchestrator integration is scheduled next-sprint work (v0.3.5 Track A). |

---

## 2. Professor's Assessment

The critique is **substantially correct in its primary observation, partially correct in its secondary, and slightly misleading in its framing.** Key points:

### What the critique gets right

- LLMLL currently handles *wrong* specs (liquid-fixpoint reports UNSAFE) but has **no shipped mechanism** for *weak* specs or *missing* specs.
- The one-pager explicitly says result quality is bounded by specification quality.
- The examples do not exercise the system in its stated target domains (financial, protocol, cryptographic).

### What the critique underestimates

- The project has **explicitly identified this gap** as its central research question. The [`strategic-positioning.md`](strategic-positioning.md) lists "Agents can write good specs" under "What Is Overestimated." The [`specification-sources.md`](specification-sources.md) rates LLM specification-generation ability as "Weak."
- The engineering ordering is **defensible**: you cannot evaluate specification quality without the verification pipeline that measures it. The instruments (`--trust-report`, `.fq` emitter, stratified verification levels) had to be built first.
- The project has **designed** the countermeasures (weak-spec counter-examples, invariant registry, downstream obligation mining, differential implementation pressure) — they are not yet shipped.

### The fair characterization

> *"LLMLL has built the verification infrastructure needed to make specification quality measurable. Whether it can then leverage that infrastructure to actually produce and evaluate strong specifications — through automated tools, domain translation, or training — is the next research question."*

The most productive response is not architectural — it is **evidential**: ship spec-adequacy tools, demonstrate them on a non-trivial domain problem, and let the results speak.

---

## 3. The Proposal: Three Tracks

### Track 1: Spec Adequacy Feedback (v0.3.5 — compiler, ~6.5 days)

**Goal:** Make the compiler tell you when a spec is weak — both locally (trivial fills) and across function boundaries (missing obligations).

#### 1a. Weak-Spec Counter-Examples (`--weakness-check`) — ~2–3 days

> Source: [compiler-team-roadmap.md W1–W2](../compiler-team-roadmap.md)

After `llmll verify` reports SAFE, attempt to construct trivial implementations that also satisfy the contract. Uses a **fixed set of trivial fill candidates**:

| Candidate | When applicable | What it tests |
|-----------|----------------|---------------|
| Identity: `(fn [x] x)` | Any `a → a` | Does the spec constrain the output at all? |
| Constant: `(fn [x] empty)` | Return type has neutral element | Does the spec require non-trivial output? |
| Projection: `(fn [x y] x)` | Multi-param functions | Does the spec use all parameters? |
| Reverse: `(fn [xs] (list-reverse xs))` | `list[a] → list[a]` | Does the spec enforce ordering? |
| Singleton: `(fn [xs] (list-take 1 xs))` | `list[a] → list[a]` | Does the spec enforce completeness? |

For each candidate, construct the AST, substitute for the function body, run `llmll verify`. If SAFE, emit:

```
⚠ Spec weakness detected for `sort-list`:
  Your contract: (post (= (list-length result) (list-length input)))
  Trivial valid implementation: (fn [xs] xs)
  Consider adding: (post (sorted result))
```

Suggestion text comes from the Invariant Pattern Registry (1c). New module: `WeaknessCheck.hs`.

#### 1b. Spec Coverage Metric (`--spec-coverage`) — ~1 day

> Source: [invariant-discovery.md §4](invariant-discovery.md)

```bash
$ llmll verify --spec-coverage program.llmll

Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     4 / 7   (57%)
  Contracts proven:             2 / 6   (33%)
  Contracts tested:             3 / 6   (50%)
  Contracts asserted:           1 / 6   (17%)
  Functions with no contract:   3       ← invisible today
────────────────────────────────────────────
  Unspecified: sort-list, validate-input, merge-records
```

Walk `[Statement]`, count `def-logic` nodes with/without `pre`/`post`, cross-reference with `.verified.json` sidecar. Makes the *absence* of specs visible.

#### 1c. Invariant Pattern Registry (seed with ~10 patterns) — ~1 day

> Source: [invariant-discovery-review.md §9](invariant-discovery-review.md)

A static lookup table keyed by `(type signature pattern, function name heuristic)`. Powers `--weakness-check` suggestions and `--sketch` contract autocomplete.

| Type pattern | Name signal | Suggested contract |
|---|---|---|
| `list[a] → list[a]` | "sort", "order" | `(post (sorted result))`, `(post (= (list-length result) (list-length input)))` |
| `list[a] → list[a]` | "filter", "select" | `(post (<= (list-length result) (list-length input)))` |
| `list[a] → list[a]` | "dedup", "unique" | `(post (unique result))` |
| `(a, b) → a` + `(a, b) → b` | "encode"/"decode" | `(post (= (decode (encode x)) x))` |
| `a → Result[b, e]` | "validate", "parse" | `(post (match result (Success _) true (Error e) (not (string-empty? e))))` |
| `int → int` | "abs" | `(post (>= result 0))` |
| `list[a] → int` | "count", "length" | `(post (>= result 0))` |
| `string → string` | "hash" | `(post (= (string-length result) HASH_LENGTH))` |

New module: `InvariantRegistry.hs`.

#### 1d. Downstream Obligation Mining — ~2 days

> Source: [invariant-discovery-review.md §4](invariant-discovery-review.md)

When `llmll verify` reports UNSAFE at a cross-function boundary, perform **abductive blame attribution** — identify whether the unsatisfied constraint is a plausible missing postcondition on a callee.

**Current diagnostic:**
```
✗ post-condition of 'transfer-from' not verified (constraint #7)
```

**Upgraded diagnostic:**
```
✗ post-condition of 'transfer-from' not verified (constraint #7)
  Caller requires: (>= (balance-of state from) amount)
  Callee 'balance-of' has no postcondition guaranteeing this.
  Candidate strengthening for 'balance-of':
    (post (>= result 0))
```

**Implementation path (extends existing infrastructure):**

1. Extend `ConstraintOrigin` with `coCallee :: Maybe Name` — set when the constraint involves a cross-function call site.
2. When `FixpointEmit.hs` encounters a `pre` clause referencing a function call, record `coCallee` in the origin.
3. When `DiagnosticFQ.hs` processes an UNSAFE constraint with a `coCallee`, look up the callee's `ContractStatus` (via `TrustReport.collectAllContractStatus`). Extract the needed predicate, check if it's about the callee's return value, and emit the candidate strengthening.
4. **Soundness check:** Re-run fixpoint with the candidate postcondition added. If SAFE, mark suggestion as sound.

Reuses: `ConstraintOrigin` from `DiagnosticFQ.hs`, `extractCalls` from `TrustReport.hs`, `collectAllContractStatus` from `TrustReport.hs`.

> [!IMPORTANT]
> **Scope limitation:** The current fixpoint emitter covers QF linear integer arithmetic only. Downstream obligation mining in v0.3.5 covers **arithmetic obligations that flow through `let` bindings** — not arbitrary predicates over function calls. This is the most valuable case (financial conservation / balance-preservation invariants) but it is not universal. Full predicate-level obligation mining is a v0.5+ item.

#### 1e. Intentional Permissiveness Suppression (`weakness-ok`) — ~0.5 day

> Source: [invariant-discovery-review.md §4.1](invariant-discovery-review.md)

Without a suppression mechanism, `--weakness-check` will produce false positives on every accessor, projection, and deliberately non-deterministic function.

**Solution:** A `(weakness-ok ...)` declaration, analogous to `(trust ...)`:

```lisp
;; "balance-of is a pure accessor — identity-satisfying its spec is fine"
(weakness-ok balance-of "pure accessor — spec is intentionally minimal")

;; "cache-evict may evict any entry — the spec is deliberately permissive"
(weakness-ok cache-evict "eviction policy is unspecified by design")
```

Syntax and placement rules follow `(trust ...)` — per-function, before `def-logic`, idempotent. The reason string is **required**. Suppressions are:

1. Visible in `--trust-report` output (alongside `(trust ...)` declarations).
2. Enumerable by agents auditing the module.
3. NOT applied to `--spec-coverage` — the function's contract status is unchanged.

---

### Track 2: Domain Benchmark (v0.4, alongside Lead Agent — ~5 days)

**Goal:** Demonstrate the full pipeline on a problem where specification quality *matters.*

#### The benchmark: ERC-20 Token Contract

**Why this domain:**
- **External spec exists.** [ERC-20](https://eips.ethereum.org/EIPS/eip-20) defines `transfer`, `approve`, `transferFrom`, `balanceOf`, `totalSupply` with explicit semantic requirements.
- **Specifications are non-trivial.** Balance conservation, authorization constraints, and edge cases exercise the verification pipeline meaningfully.
- **Weak specs have consequences.** A `transfer` without the conservation invariant allows money creation — exactly the bug the spec-adequacy tools should catch.
- **Domain relevance.** Financial contracts are a stated target domain ([`strategic-positioning.md §Target Domains`](strategic-positioning.md)).

#### Verification scoping (honest labeling)

The fixpoint emitter covers QF linear integer arithmetic. The ERC-20 benchmark will demonstrate **mixed verification levels**:

| ERC-20 property | Verification level | Why |
|---|---|---|
| `total-supply` conservation | **Proven** (QF-LIA) | Integer arithmetic over extracted balance values |
| Balance debit/credit | **Proven** (QF-LIA) | Integer arithmetic |
| Allowance deduction | **Proven** (QF-LIA) | Integer arithmetic |
| Non-negative balance | **Proven** (QF-LIA) | Simple comparison |
| Map key membership / absence | **Asserted** | Map operations outside decidable fragment |
| Transfer-to-self edge case | **Tested** (QuickCheck) | Conditional logic, not purely arithmetic |

This is actually a *stronger* demonstration of the stratified system than a toy example where everything is proven — it shows the system handling mixed verification levels on a real problem.

#### Deliverables

| # | Artifact | Description |
|---|----------|-------------|
| B1 | `examples/erc20_token/erc20.ast.json` | Full ERC-20 skeleton with `?delegate` holes, types, and contracts derived from ERC-20 |
| B2 | `examples/erc20_token/erc20_filled.ast.json` | Filled version with verified contracts |
| B3 | `examples/erc20_token/WALKTHROUGH.md` | End-to-end: external spec → LLMLL contracts → verified code → weakness detection → downstream obligation → strengthened contract → re-verification |
| B4 | Weakness demo | Removing the conservation invariant → `--weakness-check` finds money-printing implementation |
| B5 | Trust report demo | `--trust-report` on the multi-function program with cross-function dependencies |
| B6 | Downstream obligation demo | Deliberately weakened callee → compiler suggests missing postcondition |

---

### Track 3: Lead Agent Spec Quality Loop (v0.4, integrated with Lead Agent — ~3 days)

**Goal:** Feed spec-adequacy signals back into the Lead Agent's generation loop before hole-filling begins.

Extends the Lead Agent's Step 4 (Quality Check, from [`lead-agent.md`](lead-agent.md)) with two new checks:

#### 3a. Spec coverage gate

After `llmll check` passes on the generated skeleton, run `llmll verify --spec-coverage`. If coverage falls below threshold (e.g., <50%), feed suggestions from the invariant registry back to the Lead Agent for iteration.

#### 3b. Weakness check in the lead loop

After the skeleton type-checks and has contracts, run `llmll verify --weakness-check`. If any function's contract admits a trivial implementation, feed the trivial fill and suggested strengthening back to the Lead Agent.

#### Architecture

```
Intent → Lead Agent → skeleton.ast.json
                         │
                    llmll check         ← type errors?
                         │
                    --spec-coverage     ← missing contracts? → iterate
                         │
                    --weakness-check    ← weak contracts? → iterate
                         │
                    Quality heuristics  ← loose types, low parallelism?
                         │
                    skeleton ready → --mode fill
```

This creates a **spec-quality gate** between skeleton generation and hole filling. The Lead Agent cannot proceed to filling until its specifications meet a minimum quality bar. This upgrades contracts from advisory metadata into part of the coordination protocol.

---

## 4. Sequencing and Dependencies

```
v0.3.5 (NOW)                        v0.4 (~4-6 weeks)
──────────────────                  ──────────────────────
Track 1: Spec Adequacy              Track 2: Domain Benchmark
  1a. --weakness-check (2-3d)         B1-B6. ERC-20 example (5d)
  1b. --spec-coverage (1d)              includes downstream-suggestion demo
  1c. InvariantRegistry (1d)
  1d. Obligation mining (2d)        Track 3: Lead Agent Spec Loop
  1e. weakness-ok suppression (0.5d)  3a. Spec coverage gate (1d)
                                      3b. Weakness in lead loop (1d)
Already planned:                      + Lead Agent (existing plan, 7d)
  Context-aware checkout (C1-C4,C6)
  Orchestrator E2E (O1-O4)
```

**Total added effort:** ~11 days across v0.3.5 and v0.4, of which 6.5 days are in v0.3.5.

**Internal ordering within Track 1:** 1b (spec-coverage) and 1c (registry) are independent and can be done first. 1a (weakness-check) depends on 1c (registry provides suggestions). 1d (obligation mining) is independent of 1a–1c and can be developed in parallel. 1e (suppression) depends on 1a.

---

## 5. Technical Risks

### Risk 1: ConstraintOrigin provenance for obligation mining

`ConstraintOrigin` currently carries only `coFunction`, `coClause`, `coJsonPtr`, and `coSourceFile`. Downstream obligation mining requires extending it with `coCallee :: Maybe Name` and `coNeededPred :: Maybe FQPred`.

The `coCallee` field requires `FixpointEmit.hs` to recognize when a `pre`/`post` expression contains a function call. Currently `exprToPred` maps `EApp` to arithmetic operators only and returns `Nothing` for everything else. Function calls in predicates are outside QF-LIA.

**Mitigation:** Obligation mining in v0.3.5 covers arithmetic obligations that flow through `let` bindings (the callee's return is bound by `let`, and the caller's predicate references the bound variable). This is the most valuable case — it covers exactly the financial conservation invariant class. Full predicate-level mining is v0.5+.

### Risk 2: ERC-20 benchmark scoping to QF-LIA

The fixpoint emitter covers QF linear integer arithmetic. ERC-20 uses `map[string, int]` with non-integer key types. Map membership operations are outside the decidable fragment.

**Mitigation:** Scope the benchmark honestly. Label which clauses are proven vs. tested vs. asserted. The mixed verification levels actually demonstrate the stratified system working as designed.

### Risk 3: False positive rate on `--weakness-check`

The trivial-fill candidates (identity, constant, projection, reverse, singleton) may satisfy contracts that are intentionally broad (pure accessors, projections, predicates).

**Mitigation:** The `(weakness-ok ...)` suppression mechanism. With the following design choices:
- Reason string is **required** (makes suppressions auditable).
- Suppressions surface in `--trust-report` (makes them visible in CI).
- Suppressions do NOT affect `--spec-coverage` (the function's contract presence is unchanged).

### Risk 4: Computational cost of `--weakness-check`

At most 5 trivial-fill candidates per function, each requiring one `liquid-fixpoint` invocation (~1–2 seconds). For N contracted functions: ~5N × 2s worst-case.

**Mitigation:** Early-exit (stop after first trivial fill found per function). Target <30 seconds for the ERC-20 example (7 functions). Obligation mining (1d) adds no extra fixpoint runs — it reuses failure data from the original verification pass.

---

## 6. What This Does NOT Address (deferred)

| Mechanism | Status | When |
|---|---|---|
| Differential implementation pressure (`--multi`) | Designed | v0.5 or v0.6 |
| Spec mutation testing | Research proposal | v0.6 |
| Daikon-style property mining | Research proposal | v0.6 |
| Synthetic training corpus (Hackage back-translation) | Designed | v0.6 |
| `def-interface :laws` | Language extension | v0.6 |
| Adversarial red-team agent | Designed | v0.5 or v0.6 |
| Iterative strengthening convergence | Open research question | Acknowledged, not gated on |

For v0.3.5–v0.4, strengthening is **one-shot suggestive**: the compiler suggests a candidate, the agent accepts or rejects. The CEGIS-style iterative loop (propose → verify → refine → re-verify) is v0.6 research.

---

## 7. Success Criteria

The spec gap is "closed" (relative to the critique) when all seven hold:

### Detecting weak specs (local)

**SC-1.** `llmll verify --weakness-check` on the ERC-20 example detects that removing the conservation invariant from `transfer` admits a money-printing implementation. The diagnostic names the trivial fill and suggests the missing postcondition.

**SC-2.** `llmll verify --spec-coverage` on the ERC-20 example reports 100% contract coverage with all arithmetic contracts proven.

### Detecting weak specs (compositional)

**SC-3.** The ERC-20 example demonstrates at least one **downstream obligation suggestion**: `transfer-from` fails verification because a callee (e.g., `balance-of` with a deliberately weakened spec) lacks a necessary postcondition. The compiler suggests the missing postcondition on the callee, not just the failure location on the caller.

### Avoiding false positives

**SC-4.** `--weakness-check` on the ERC-20 example does **not** flag `balance-of` (a pure accessor) as weak. Either `(weakness-ok ...)` correctly silences it, or the trivial-fill candidates do not satisfy its actual contract.

### Agent spec generation

**SC-5.** The Lead Agent, given the ERC-20 standard as context, generates a skeleton whose contracts survive `--weakness-check` without human intervention.

### End-to-end evidence

**SC-6.** The ERC-20 walkthrough documents the full pipeline: external spec → LLMLL contracts → verified code → weakness detection → downstream obligation suggestion → strengthened contract → re-verification.

### Performance

**SC-7.** `--weakness-check` on the ERC-20 example (7 contracted functions) completes in under 30 seconds.

---

### Mapping to reviewer demands

| Reviewer demand | Success criterion |
|---|---|
| Catches deliberately weakened specs | SC-1, SC-3 |
| Avoids crying wolf on intentionally permissive interfaces | SC-4 |
| Demonstrates at least one downstream-suggestion loop | SC-3, SC-6 |

| Open issue raised by reviewer | How addressed |
|---|---|
| False positives on healthy diversity | `(weakness-ok ...)` + SC-4 |
| Convergence of iterative strengthening | Scoped to one-shot suggestion for v0.3.5–v0.4 |
| Computational cost | SC-7 + early-exit optimization |

---

## 8. External Reviewer's Final Verdict

> *"I would no longer call spec quality the project's biggest unanswered design problem. I would call it the project's biggest remaining proof burden: they now have a plausible closure path, but they still need the end-to-end demo."*

The design question is answered. The engineering question — can we ship the demo — is next. **Start Track 1 now.**

---

## 9. Relationship to Existing Documents

| Document | Relationship |
|---|---|
| [`compiler-team-roadmap.md`](../compiler-team-roadmap.md) | Track 1 items should be added to v0.3.5. Track 2 and 3 items added to v0.4. |
| [`invariant-discovery-review.md`](invariant-discovery-review.md) | This document implements the Professor's Phase A recommendations (invariant registry + obligation explanation). Phase B (differential pressure) and Phase C (adversarial search) are deferred. |
| [`lead-agent.md`](lead-agent.md) | Track 3 extends the Lead Agent's Step 4 quality checks. |
| [`specification-sources.md`](specification-sources.md) | Track 2 demonstrates Source 1 (external standards) on a concrete example. |
| [`strategic-positioning.md`](strategic-positioning.md) | This work directly addresses the "What Is Overestimated" section. |
| [`one-pager.md`](../one-pager.md) | Success criteria, if met, substantiate the one-pager's claims about spec quality visibility. |
