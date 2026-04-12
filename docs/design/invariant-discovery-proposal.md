# Mechanisms for Invariant Discovery in LLMLL

> **Source:** External team write-up  
> **Date:** 2026-04-12  
> **Status:** Under review — see `invariant-discovery-review.md` for professor-team feedback

---

## Framing

> **How does LLMLL create pressure to discover missing specifications, rather than merely verify the ones it already has?**

Verification checks stated obligations. A serious system also needs mechanisms that *surface unstated obligations*.

There is no single silver bullet, so the right answer is a stack of pressures. Some are static, some dynamic, some agentic.

## 1. The key distinction

There are three different failure modes:

1. **Wrong spec**
   The contract says the wrong thing.

2. **Weak spec**
   The contract says something true but insufficient.

3. **Missing spec**
   A property matters, but no one stated it.

The current system is best at (1), somewhat helpful on (2), and weakest on (3).

The investigation should focus on (3): missing invariants.

## 2. The first principle: missing invariants are discovered through *counterpressure*

A system discovers missing specifications only when some mechanism makes underspecification painful.

That pressure can come from:

* proof failure
* ambiguous decomposition
* multiple inconsistent implementations
* test-generated counterexamples
* downstream proof obligations
* human review heuristics

So the design goal is not "AI invents specs from genius." It is:

> **Arrange the workflow so that underspecification produces visible friction.**

That is much more tractable.

## 3. Best mechanism: differential implementation pressure

This is the strongest fit for LLMLL.

Suppose a hole has a type and weak contract. Instead of accepting the first implementation that verifies, you ask multiple agents to fill it independently.

If several substantially different implementations all satisfy the contract, that is evidence the contract is too weak.

This is extremely important.

Because a missing invariant often reveals itself as:

> **too many semantically different programs satisfy the current interface**

That gives you a concrete metric: contract discriminative power.

For example, with sort:

* identity
* reverse
* stable sort
* unstable sort

If several pass, then "sortedness" or "permutation preservation" is missing.

This is much better than merely saying "LLMs may write weak specs." It gives the language a procedure:

* sample multiple candidate implementations
* verify all against current spec
* compare observational divergence
* synthesize new candidate invariants from divergences

That is genuinely strong.

## 4. Second mechanism: downstream obligation mining

This is the most PL-native approach.

Often a missing invariant is not visible at the definition site. It becomes visible only when downstream code tries to use the function.

Example:

* function `normalizeUsers : RawUsers -> Users`
* no invariant about uniqueness of IDs

Later, another function wants:

* `lookupById` to be total or unambiguous

Now the downstream proof obligation fails unless `normalizeUsers` guarantees unique IDs.

This suggests a design rule:

> **Failed downstream verification should generate upstream specification suggestions.**

That is, when a proof fails, the compiler should try to explain whether the missing fact is:

* local to the caller, or
* a plausible missing postcondition of a dependency

This is a very fertile area.

You could make the compiler produce messages like:

> `Caller requires: uniqueIds(result)`
> `Producer normalizeUsers does not guarantee this`
> `Candidate strengthening: postcondition uniqueIds(output)`

That would be far more valuable than raw proof failure.

## 5. Third mechanism: adversarial implementation search

A related but distinct idea:

Instead of searching for a valid implementation, search for a **bad-but-contract-satisfying implementation**.

This is basically a spec red-team.

For a given function spec, ask an agent:

> "Find the dumbest, most pathological implementation that still typechecks and satisfies the contract."

If such an implementation exists and is obviously not intended, you have discovered a missing invariant.

This is excellent for AI-driven systems because LLMs are very good at adversarial loophole-finding once explicitly asked.

This gives you a concrete loop:

* proposer agent writes contract
* adversary agent searches for degenerate witness
* if found, strengthen contract
* repeat until degenerates become hard to find

That is a much better framing than "can models write good specs?"

## 6. Fourth mechanism: property discovery from implementation disagreement

Suppose two verified implementations differ on some inputs. Then there are only a few possibilities:

* the spec is intentionally permissive
* one implementation exploits a loophole
* a distinguishing property is missing

This suggests a synthesis step:

* generate inputs where candidate implementations differ
* ask: what semantic property distinguishes the desired behavior?
* propose that property as a contract candidate

For sorting:

* identity and sort differ on unsorted lists
* candidate distinguishing property: `sorted(output)`

For deduplication:

* left-biased and right-biased differ
* candidate property: stability / first occurrence preserved

This is really an invariant discovery engine built from implementation diversity.

## 7. Fifth mechanism: decomposition pressure from hole size and entropy

The system should detect holes that are too semantically wide.

A hole is suspicious if:

* it has a very broad type
* many candidate implementations satisfy the contract
* downstream users demand many unstated assumptions
* its trust footprint becomes large

This suggests a static metric: call it **spec entropy**.

A function boundary has high entropy when the interface leaves too much behavior unconstrained.

Possible signals:

* many independent implementations accepted
* many downstream assumptions attached
* many failed proof attempts requiring extra facts
* many property tests generated to pin down behavior

When entropy is high, the orchestrator should not just ask for a better proof. It should ask for **refactoring**:

* split the hole
* add intermediate data types
* expose latent phases

This directly targets decomposition quality.

## 8. Sixth mechanism: counterexample-guided contract strengthening

This is the most standard and probably easiest to ship first.

Workflow:

* current contract accepted
* property-based testing or adversarial generation finds behavior humans dislike
* infer a candidate predicate separating good from bad outputs
* propose it as a refinement or postcondition

This is essentially CEGIS for specs.

The challenge is not generating counterexamples. The challenge is lifting them into useful predicates. But LLMs may actually help here:

* counterexample shows output differs
* model proposes semantic description of the difference
* verifier checks whether the description is expressible and valid

This is a very plausible human-AI loop.

## 9. Seventh mechanism: retrieval of invariant patterns

This is less novel, but practical.

Many missing invariants are not unique insights. They are standard patterns:

* length preservation
* permutation preservation
* sortedness
* uniqueness
* monotonicity
* idempotence
* round-trip laws
* non-negativity
* conservation properties

You can maintain a registry of invariant schemas keyed by:

* data structure
* function name patterns
* domain
* algebraic shape

Then when an agent defines a function over lists, maps, parsers, financial ledgers, protocols, etc., the system suggests likely missing laws.

This is not deep theorem proving. It is specification autocomplete. But it may be one of the highest-leverage components.

## 10. Eighth mechanism: algebraic law expectation

This is where category theory and typeclass-style design become useful.

Certain abstractions should come with expected laws:

* parser combinators
* monoids
* optics
* state transitions
* encoders/decoders
* serializers
* caches

If the language knows a component claims to implement a familiar abstraction, it can require or suggest the corresponding laws.

For example:

* decoder/encoder pair → round-trip laws
* set-like structure → idempotence, commutativity
* sort-like transformation → permutation + order

This is powerful because it turns missing invariants from "invent from scratch" into "instantiate a law schema."

## 11. Ninth mechanism: proof-obligation explanation, not just failure

This one matters ergonomically.

A failed proof today often says, effectively, "cannot prove goal." That is not enough.

The system should try to diagnose:

* missing precondition
* missing postcondition
* missing lemma
* wrong decomposition
* unsupported fragment

That explanation layer is central for invariant discovery.

A good system message would be:

> This proof would go through if `dedup(output)` guaranteed `unique(output)`.
> Consider strengthening the postcondition of `dedup`.

That is the beginning of a real assistant for formal design.

## 12. Mechanism ranking for LLMLL

First tier:

* **multi-agent differential implementation pressure**
* **adversarial loophole-finding against contracts**
* **downstream obligation mining with upstream contract suggestions**

Second tier:

* counterexample-guided strengthening
* invariant pattern retrieval
* algebraic law templates

The first-tier ideas are especially aligned with the LLMLL system because they use the fact that it already has:

* multiple agents
* typed holes
* verification gates
* structured AST patches

So they are not add-ons. They exploit the architecture.

## 13. The most important reframing

The goal is not:

> "Have the LLM invent perfect formal specs."

The goal is:

> **Use disagreement, loopholes, and failed obligations to drive iterative strengthening of interfaces.**

That is much more believable, and much more novel.

## 14. A concrete architecture sketch

For each hole or function boundary:

### Phase 1: initial contract

Lead agent proposes:

* type
* minimal pre/postconditions

### Phase 2: candidate implementations

Two or three agents independently implement against that contract.

### Phase 3: divergence analysis

Compiler/tester compares accepted implementations:

* where do they differ?
* can those differences matter downstream?

### Phase 4: adversarial loophole search

A red-team agent tries to construct a degenerate but contract-satisfying implementation.

### Phase 5: strengthening suggestions

System proposes:

* missing postconditions
* missing algebraic laws
* decomposition splits

### Phase 6: trust update

If boundary remains broad, mark it high-entropy / low-trust.

This would make LLMLL feel substantially different from ordinary "generate code, run tests" systems.

## 15. Formal concepts

> **Specification pressure**: the degree to which the surrounding program, alternative implementations, and adversarial search constrain a component's interface beyond its currently declared contract.

> **Contract entropy**: how many semantically distinct implementations remain admissible under the current specification.

These give:

* a design metric
* a research angle
* a story for why AI can improve specs iteratively

## 16. Open risks

The main risk is whether the system can distinguish:

* healthy implementation diversity
  from
* underspecification

That is a good research problem, not a fatal objection.

## 17. Recommended demonstration

The strongest next step would be to formalize 3 concrete mechanisms:

1. adversarial loophole search
2. downstream obligation mining
3. differential implementation comparison

and show them on one nontrivial example, like sorting, parser round-tripping, or financial transaction normalization.
