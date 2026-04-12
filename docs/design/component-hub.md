# Component Hub — Future Discussion

## The Reusable Parts Analogy

> *"What's the likelihood each hole, once implemented, becomes a reusable 'part' — just like in hardware?"*

### Why it's directionally true

Once a typed hole is filled and its contract is verified, you have:
- A function with a precise type signature (what it takes, what it returns)
- Proven pre/post contracts (what it guarantees)
- A verified implementation that the compiler has accepted

That IS a reusable component. Any other program that needs a function with the same type and contract can use it directly. The `llmll-hub` registry is designed for this — publish verified components, import them by name, the compiler checks compatibility at import time.

### Why it's harder than in EE

1. **Context-dependent contracts.** A 10kΩ resistor is a 10kΩ resistor — the spec is universal. A `sort-list` function might have contract assumptions about the data (does it handle empty lists? negative numbers? lists longer than memory?). Software contracts are more context-sensitive than hardware part specs.

2. **No universal standard.** In EE, component specs are standardized (JEDEC, IEC). In software, there's no equivalent. One agent's `PositiveInt` might mean `> 0`, another's might mean `≥ 1` — same mathematically, but the contracts need unification for reuse. LLMLL's type system handles this (structural comparison), but the problem space is larger.

3. **Combinatorial spec space.** A resistor has resistance, tolerance, power rating — a handful of parameters. A software function's contract can involve arbitrary logical predicates. The "catalog" of reusable parts grows more slowly toward coverage.

4. **Composition complexity.** In EE, you compose via well-understood circuit topologies. In software, composition patterns are more varied and harder to verify compositionally.

---

## The Context-Oriented Hub Idea

> *"Even within the same context, adding a context-oriented hub might be of interest."*

### Concept: Per-Project Component Registry

When a hole is created, the **first thing the orchestrator does** is check whether this piece already exists — not in a global registry, but in a **project-specific hub** scoped to the software being built.

**Workflow:**

1. Lead agent creates `?delegate @specialist "sort users by score" -> list[User]`
2. Before dispatching to the specialist agent, the orchestrator queries:
   - The **project hub** — has this project already verified a function with this signature?
   - The **global hub** — is there a published, verified component that matches?
3. Query is **by type signature + contract**, not by name. A function named `rank-players` with the same signature and compatible contracts would match.
4. If found → reuse immediately, no agent invocation needed
5. If not found → dispatch to specialist agent → on success, register the result in the project hub

### Why this matters

- **Avoids redundant work.** In a large program, different parts may need the same utility (string validation, date formatting, permission checking). Without the hub, each hole gets implemented independently.
- **Agents or orchestrator.** The query could be done by the orchestrator (before delegating) or by the specialist agent itself (as a first step). Either way, the type signature is the lookup key.
- **Progressive accumulation.** As the project grows, the hub accumulates verified components. Later holes are more likely to find matches. The project gets faster to build over time.
- **Cross-project reuse.** A project hub could eventually be published as a package, making its verified components available to other projects.

### Open questions

- How fuzzy should signature matching be? Exact match only, or should `list[int] -> list[int]` match `list[PositiveInt] -> list[PositiveInt]` if the contracts are compatible?
- Should the hub store multiple implementations of the same signature (e.g., different performance characteristics)?
- How does versioning work when a contract changes?
