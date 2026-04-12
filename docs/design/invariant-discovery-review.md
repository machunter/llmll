# Professor Review: Mechanisms for Invariant Discovery in LLMLL

**Reviewer:** Lead Consultant for Formal Language Design  
**Document under review:** "Invariant Discovery Mechanisms" (external team write-up)  
**Date:** 2026-04-12

---

## Overall Assessment

This is an unusually well-structured proposal. The central reframing — from "can LLMs invent specs?" to "can we arrange the system so that underspecification produces visible friction?" — is the right conceptual move. It converts a vague AI-capability question into an engineering problem with measurable outcomes.

That said, the proposal contains a mixture of ideas at different maturity levels. Some are immediately actionable within the current LLMLL architecture; others require significant new infrastructure; a few have subtle soundness issues that need addressing before they can be trusted. Let me go through them systematically.

---

## 1. What the proposal gets right

### The failure-mode taxonomy (§1) is precise and useful

The three-way split between *wrong spec*, *weak spec*, and *missing spec* is the correct decomposition. I would add one observation: in a system with stratified verification (which LLMLL already has — `proven` / `tested` / `asserted`), these failure modes map to different verification tiers:

| Failure mode | Where it surfaces | Current LLMLL mechanism |
|---|---|---|
| Wrong spec | `llmll verify` reports UNSAFE | liquid-fixpoint contradiction |
| Weak spec | Passes verify but permits bad implementations | **No current mechanism** |
| Missing spec | No contract exists; behavior unconstrained | **No current mechanism** |

This confirms the proposal's focus is correct: LLMLL's verification pipeline is well-equipped for (1) and has structural gaps for (2) and (3).

### The counterpressure principle (§2) is the right design heuristic

> "A system discovers missing specifications only when some mechanism makes underspecification painful."

This is exactly how dependent type theories work in practice. The difference between a system that *permits* specification and one that *pressures* toward specification is the difference between optional documentation and a type error. LLMLL should be in the latter category wherever possible.

---

## 2. Mechanism-by-mechanism critique

### §3 — Differential Implementation Pressure: **Strong. Ship this first.**

This is the highest-value, most architecturally aligned idea in the document. Here is why it fits LLMLL so well:

1. **LLMLL already has typed holes** (`?name`, `?delegate @agent`). The system already models "a gap to be filled by an agent."
2. **LLMLL already has multiple agents** (the swarm model, §11). Independent agents filling the same hole is not a hypothetical — it is the designed usage pattern.
3. **LLMLL already has contract verification** (`llmll verify`). The infrastructure to check "does this implementation satisfy the contract?" exists.

What is *missing* is the comparative step: rather than accepting the first valid fill, compare multiple fills and flag divergence.

> [!IMPORTANT]
> **Concrete implementation path:** Extend `llmll checkout` to support a `--multi` mode. Instead of exclusive locks, allow N agents to independently fill the same `?delegate` hole. After all N fills arrive, the compiler runs a *divergence analysis* pass:
> 1. Type-check all N fills against the existing contract.
> 2. For each pair of accepted fills, synthesize distinguishing inputs (using QuickCheck-style generation from `for-all` infrastructure).
> 3. If distinguishing inputs exist, report them as **candidate invariant suggestions**.

The sort example in the proposal is pedagogically effective but understates the practical difficulty. Let me sharpen it:

```lisp
(def-logic sort-users [users: list[User]]
  (post (= (list-length result) (list-length users)))
  ?sort_impl)
```

Agent A implements stable sort by name. Agent B implements sort by ID. Both satisfy `list-length` preservation. The question is whether the divergence analysis can generate the *right* candidate invariant. "Sortedness" is easy; "stable with respect to what key?" is hard.

> [!WARNING]
> **The hard problem here is invariant *synthesis* from divergence, not divergence *detection*.** Detection is straightforward (generate inputs, compare outputs). Synthesis — "what predicate separates the intended behavior from the unintended?" — is where LLMs may actually contribute. But the quality of that contribution is empirically unknown and must be validated.

**Recommendation:** Implement divergence detection first. Defer invariant synthesis to a second phase. Even without synthesis, a compiler message like:

```
⚠ 3 of 4 candidate implementations for ?sort_impl diverge on input [User("alice", 2), User("bob", 1)].
  Consider strengthening the postcondition.
```

...is already extremely valuable.

---

### §4 — Downstream Obligation Mining: **Very strong. Natural fit for the type system.**

This is the most PL-native idea in the document and the one closest to what dependent type checkers already do.

LLMLL has the infrastructure for this today, in embryonic form:

- `llmll verify` emits `.fq` constraints and runs liquid-fixpoint.
- When verification fails, `DiagnosticFQ.hs` maps constraint IDs back to source locations via JSON Pointers.

What is *missing* is the **blame attribution** step. Currently, a failed proof obligation produces a message like:

```
✗ Constraint 7 UNSAFE at /statements/3/post
```

The proposal asks for:

```
✗ Caller requires: uniqueIds(result)
  Producer normalizeUsers does not guarantee this.
  Candidate strengthening: postcondition uniqueIds(output)
```

This is essentially **abduction** — given a failed proof obligation at the call site, work backward to find plausible postconditions on the callee that would make the proof go through.

> [!IMPORTANT]
> **This is feasible within the liquid-fixpoint framework.** When fixpoint reports UNSAFE, the unsatisfied constraint is available. The compiler can:
> 1. Identify whether the missing fact involves a cross-function boundary (call to an imported function).
> 2. Extract the needed predicate from the unsatisfied constraint.
> 3. Check whether that predicate is expressible as a valid `(post ...)` clause on the callee.
> 4. Emit a structured diagnostic with the candidate strengthening.

**Proof obligation:** The candidate strengthening must be *sound* — adding it must not introduce contradictions. This is checkable: propose the strengthening, re-run fixpoint with it added, verify SAFE.

**Relationship to trust propagation:** LLMLL v0.3 already has `(trust ...)` declarations (§4.4.3). Downstream obligation mining would generate *the inverse*: instead of the caller saying "I accept this trust gap," the compiler says "here is what the callee would need to guarantee to close this trust gap."

---

### §5 — Adversarial Implementation Search: **Conceptually strong, but needs careful scoping.**

The proposal reframes this as "spec red-teaming." The core idea:

> Given a contract, search for the dumbest implementation that still satisfies it.

This is a compelling use of LLMs. But there are subtleties:

**Problem 1: What counts as "degenerate"?** The identity function satisfying a sort contract is clearly degenerate. But what about a function that returns `(list-empty)` for a contract that only specifies `(post (>= (list-length result) 0))`? That is degenerate but also *technically the intended behavior* for some functions. The system needs a notion of "intended generality" to distinguish between:

- A contract that is intentionally weak (e.g., a function that may return any non-negative-length list)
- A contract that is *accidentally* weak (e.g., a sort that forgot to specify sortedness)

**Problem 2: The adversary must be constrained to the type system.** An unconstrained adversarial search can always find pathological implementations by exploiting runtime exceptions, non-termination, or undefined behavior. In LLMLL this is partially handled by totality enforcement (`letrec :decreases`), but the coverage is not complete.

> [!TIP]
> **My recommendation:** Scope adversarial search to the *same fragment* that `llmll verify` covers. Ask the adversary: "Find a QF-LIA-satisfying implementation that differs from the reference implementation on some well-typed input." This keeps the game decidable and makes the results trustworthy.

---

### §6 — Property Discovery from Implementation Disagreement: **Useful but derivative of §3.**

This is operationally the same as differential implementation pressure (§3) with an added synthesis step. The synthesis step ("what semantic property distinguishes the desired behavior?") is the hard part and the one where LLM quality matters most.

I would not treat this as a separate mechanism. Instead, fold it into the §3 workflow as **Phase 2: invariant synthesis from divergence data.**

---

### §7 — Spec Entropy from Hole Size: **Interesting metric, but measurement is tricky.**

The idea of "spec entropy" — quantifying how many semantically distinct implementations satisfy a contract — is theoretically appealing. But measuring it in practice requires sampling the space of valid implementations, which is:

- Computationally expensive (each sample requires type-checking + contract verification)
- Biased by the sampling strategy (LLM-generated implementations are not uniformly distributed over the space of valid programs)
- Sensitive to the choice of "semantic distinctness" (observational equivalence when?)

> [!NOTE]
> **A practical proxy for spec entropy:** Count the number of *distinct output vectors* produced by N candidate implementations on a fixed test suite. This is cheaper than full semantic comparison and correlates with the theoretical notion. LLMLL's `check`/`for-all` infrastructure already generates test inputs; reuse those.

The decomposition-pressure aspect (split the hole, add intermediate types) is valuable but harder to operationalize. It requires the system to *suggest* type-level refactorings, which is a substantially harder problem than suggesting predicates.

---

### §8 — Counterexample-Guided Contract Strengthening (CEGIS): **Most mature; ship early.**

This is the most standard approach and the easiest to integrate. LLMLL already has:

- `QuickCheck`-style property testing (`check`/`for-all` blocks)
- Contract assertions (`pre`/`post`)
- Structured diagnostics

The workflow would be:

1. Run `llmll test` — properties pass.
2. Run adversarial/exploratory input generation — find an input where the implementation produces a surprising result.
3. Ask: "Is this result intended?" If not, synthesize a predicate that excludes it.
4. Propose the predicate as a candidate postcondition.

The challenge the proposal correctly identifies is **lifting counterexamples to predicates**. A counterexample is concrete; a predicate is universal. The gap between them is exactly the inductive generalization problem.

> [!TIP]
> **Pragmatic approach:** Use the invariant pattern registry (§9) as the search space for candidate predicates. Given a counterexample, enumerate standard laws and check which ones would exclude the bad behavior. This avoids open-ended synthesis.

---

### §9 — Invariant Pattern Registry: **High leverage, low novelty. Ship it.**

This is specification autocomplete and it is the right thing to build.

LLMLL already has the hooks:

- `type` declarations carry structural information about data shapes
- `def-logic` function names carry semantic information about intent
- The module system provides domain context

A registry keyed by `(data structure × function shape × domain)` that suggests standard laws is immediately valuable. For LLMLL specifically:

| Pattern | Trigger | Suggested invariant |
|---|---|---|
| `list[a] → list[a]` | Function returns same element type | `(= (list-length result) (list-length input))` or subset thereof |
| `encode`/`decode` pair | Complementary function names | Round-trip: `(= (decode (encode x)) x)` |
| `State → State` | State transformer | Conservation of some numeric field |
| `sort`-like | Name contains "sort" or "order" | `sorted(result)` ∧ `permutation(input, result)` |

> [!IMPORTANT]
> **Integration with `llmll typecheck --sketch`:** The sketch pass already infers types for holes. Extend it to also emit invariant suggestions from the registry, keyed by the inferred type. This turns spec autocomplete into a compiler feature, not a separate tool.

---

### §10 — Algebraic Law Expectation: **Correct in principle, requires typeclass infrastructure.**

LLMLL does not currently have a typeclass system beyond `def-interface`. For algebraic law expectations to work, the language needs a way to express:

- "This type is a monoid" → expect `(= (mappend mempty x) x)` and associativity.
- "These two functions form an encoder/decoder pair" → expect round-trip.

`def-interface` could be extended with an optional `:laws` clause:

```lisp
(def-interface Codec
  [encode (fn [a] -> string)]
  [decode (fn [string] -> Result[a, string])]
  :laws [(for-all [x: a] (= (decode (encode x)) (ok x)))])
```

This is a natural extension of the existing interface mechanism and makes law enforcement a first-class language feature rather than an external tool suggestion.

---

### §11 — Proof-Obligation Explanation: **Critical for usability. Partially addressed.**

LLMLL v0.3.1 already has `DiagnosticFQ.hs` which maps fixpoint results back to source. But the current messages are low-level:

```
✗ Constraint 7 UNSAFE at /statements/3/post
```

The proposal asks for:

```
This proof would go through if dedup(output) guaranteed unique(output).
Consider strengthening the postcondition of dedup.
```

This is the same point as §4 (downstream obligation mining) but focused on the *presentation* layer. Both need to be addressed together.

---

## 3. Architectural alignment with LLMLL

The proposal's most important insight — and the one I want to highlight — is in §12:

> **Multi-agent differential implementation pressure, adversarial loophole-finding, and downstream obligation mining** exploit LLMLL's existing architecture (multiple agents, typed holes, verification gates, structured AST patches).

This is correct. Let me map each first-tier mechanism to specific LLMLL infrastructure:

| Mechanism | LLMLL component it extends |
|---|---|
| Differential implementation | `?delegate` + `llmll checkout` + `llmll patch` + `llmll verify` |
| Adversarial loophole-finding | `check`/`for-all` + `pre`/`post` + QuickCheck generators |
| Downstream obligation mining | `FixpointEmit.hs` + `DiagnosticFQ.hs` + trust propagation (§4.4.3) |

None of these require new language semantics. They require new *compiler passes* and new *orchestration modes* for the multi-agent workflow.

---

## 4. What the proposal gets wrong or glosses over

### 4.1 The healthy-diversity problem is harder than acknowledged

The proposal mentions it in §16 but does not give it sufficient weight. Many real-world contracts are *intentionally* permissive:

- A cache is permitted to evict any entry.
- A scheduler is permitted to choose any ready thread.
- A hash map's iteration order is unspecified.

If the invariant discovery system flags every instance of intentional nondeterminism as "underspecification," it will produce so many false positives that developers ignore it.

> [!WARNING]
> **Required mitigation:** The system needs an explicit `(spec-entropy :intentional)` annotation (or similar) that says "this contract is deliberately weak; do not flag divergence." Without this, the adversarial/differential mechanisms will cry wolf.

### 4.2 The contract entropy metric conflates semantic and observational equivalence

Two implementations can be semantically different but observationally equivalent on all well-typed inputs. The contract entropy metric as described measures *observational* divergence, not *semantic* divergence. For linear arithmetic (LLMLL's current decidable fragment), this distinction may not matter. For richer fragments (strings, lists, ADTs), it does.

### 4.3 No discussion of incremental strengthening convergence

The proposal describes an iterative loop: discover missing invariant → strengthen contract → repeat. But it does not address: **does this converge?** Can the strengthening process oscillate (add predicate P, then discover P is too strong, weaken to P', then discover P' is too weak...)?

For the CEGIS-style approach this is well-studied: CEGIS converges when the hypothesis space is finite. For LLM-generated predicates it is not studied at all. The proposal should acknowledge this open question.

### 4.4 Computational cost is unaddressed

Running N independent implementations per hole, then comparing all pairs on a test suite, then running adversarial search, then mining downstream obligations — this is expensive. The proposal should discuss:

- How many implementations per hole? (I suggest 3 as a practical minimum, 5 as a target.)
- What is the wall-clock budget per hole?
- Which mechanisms are run in CI vs. interactively?

---

## 5. Recommended prioritization for LLMLL

Given the current state of the compiler (v0.3.1 shipped, 181 tests passing, liquid-fixpoint + mock Leanstral operational), here is my recommended implementation order:

### Phase A — Immediate (v0.3.2 or v0.4)

1. **Invariant Pattern Registry** (§9) — highest leverage, lowest implementation cost. Extend `llmll typecheck --sketch` to emit invariant suggestions.
2. **Proof-Obligation Explanation** (§11 / §4) — extend `DiagnosticFQ.hs` with abductive reasoning for cross-function failures.

### Phase B — Near-term (v0.4 or v0.5)

3. **Differential Implementation Pressure** (§3) — extend `llmll checkout` with `--multi` mode; add divergence analysis pass.
4. **CEGIS-style Contract Strengthening** (§8) — extend `llmll test` with adversarial input generation and predicate suggestion.

### Phase C — Research (v0.5+)

5. **Adversarial Loophole Search** (§5) — requires careful scoping to avoid false positives.
6. **Spec Entropy Metric** (§7) — requires sampling infrastructure and semantic equivalence decisions.
7. **Algebraic Law Templates** (§10) — requires `def-interface :laws` extension.

---

## 6. The concept I would formalize

The proposal suggests two names: "specification pressure" and "contract entropy." I prefer "contract entropy" because it is measurable, but I would define it more carefully:

> **Contract discriminative power** of a specification `S` over type `T → U`: the inverse of the number of observationally-distinguishable implementations of `T → U` that satisfy `S`, measured over a reference test suite of cardinality `N`.

High discriminative power = strong contract.  
Low discriminative power = weak or missing invariants.

This gives you a scalar metric per function boundary, which enables:
- Dashboard visualization ("which functions are underspecified?")
- CI gates ("no function with discriminative power below threshold `k` may be marked `proven`")
- Trend tracking ("are contracts getting stronger over time?")

---

## 7. Summary

| Aspect | Verdict |
|---|---|
| Central reframing | **Correct and important.** "Friction from underspecification" is the right design principle. |
| First-tier mechanisms | **Architecturally aligned.** All three exploit existing LLMLL infrastructure. |
| Soundness | **Some gaps.** Healthy diversity vs. underspecification needs explicit handling. Convergence of iterative strengthening is unaddressed. |
| Practicality | **Partially addressed.** Computational cost and false-positive rates need investigation. |
| Novelty | **Genuine.** The combination of multi-agent divergence + verification gates + adversarial search is not present in existing systems I know of. |
| Recommended next step | **Formalize contract discriminative power.** Then demonstrate differential implementation pressure on one nontrivial example (parser round-tripping recommended — it exercises both the sort-like and the encoder/decoder law patterns). |

> [!IMPORTANT]
> **The single most important thing to do next:** Take one function boundary from the existing LLMLL examples (I suggest `apply-guess` from `hangman_json_verifier/`) and manually demonstrate the differential implementation pressure workflow:
> 1. Write 3 different implementations that satisfy the current contract.
> 2. Find distinguishing inputs.
> 3. Propose a missing postcondition.
> 4. Show that the strengthened contract rejects the degenerate implementations.
> 
> This concrete demonstration will make the abstract ideas tangible and reveal practical difficulties the proposal currently glosses over.
