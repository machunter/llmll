# Item 7a: Stratified Verification — Language Team Brief

**Origin:** Professor-team debate on Principle 4 (Runtime Contract Verification)  
**Date:** 2026-04-11  
**Status:** Awaiting review  

---

## Context

Principle 4 currently reads:

> **Runtime Contract Verification:** Logic functions declare `pre` and `post` conditions enforced as runtime assertions. These contracts are the machine-checked trust interface between agents: a caller does not need to understand an implementation, only that its contract holds.

This no longer reflects reality. The compiler already has compile-time verification via liquid-fixpoint (Phase 2b), `?proof-required` holes for non-linear contracts, and Leanstral integration planned for v0.3. The principle name and spec text must be updated to reflect the **stratified** nature of contract verification.

---

## Deliverable 1: Rewrite Principle 4 in §1

### Current text (LLMLL.md line 16)

```markdown
4. **Runtime Contract Verification:** Logic functions declare `pre` and `post` conditions enforced as runtime assertions. These contracts are the machine-checked trust interface between agents: a caller does not need to understand an implementation, only that its contract holds.
```

### Proposed replacement

```markdown
4. **Design by Contract with Stratified Verification:** Logic functions declare `pre` and `post` conditions as formal specifications. These contracts are the trust interface between agents. Verification is stratified: contracts in the decidable arithmetic fragment are proven at compile time (liquid-fixpoint / Z3); contracts requiring induction are routed to interactive proof (Leanstral); contracts outside both fragments are enforced as runtime assertions and flagged with `?proof-required`. A caller can inspect a contract's *verification level* — proven, tested, or asserted — without reading the implementation.
```

### Rationale

- The old name ("Runtime Contract Verification") was misleading — most contracts in the QF-linear fragment are proven statically.
- The new name foregrounds the *stratification* and introduces the concept of a **verification level** that the rest of the spec can reference.
- The last sentence creates a design obligation: verification level must be machine-readable metadata, not just CLI output.

---

## Deliverable 2: Rewrite §4.4 (Contract Semantics)

### Current text (LLMLL.md lines 239–251)

The current §4.4 conflates runtime and compile-time behavior and uses the phrase "belt-and-suspenders" informally.

### Proposed replacement

Replace §4.4 with the following:

```markdown
### 4.4 Contract Semantics

| Context | What happens on violation |
|---------|--------------------------|
| `pre` violation | `AssertionError` raised before body executes. The caller is buggy. |
| `post` violation | `AssertionError` raised before result is returned. The implementation is buggy. |
| Both satisfied | Result is returned normally. |

#### 4.4.1 Verification Levels

Every `pre` and `post` clause carries a **verification level** that describes how the contract has been checked:

| Level | Meaning | When assigned |
|-------|---------|---------------|
| `proven` | Formally verified via SMT (Z3) or interactive proof (Lean). The contract holds for all well-typed inputs. | `llmll verify` reports SAFE |
| `tested` | Not formally proven, but not falsified by property-based testing. Trust is proportional to sample coverage. | `llmll test` passes; `llmll verify` skips or emits `?proof-required` |
| `asserted` | Enforced as a runtime assertion only. No static or dynamic evidence of correctness beyond the assertion itself. | Default for any contract not yet run through `verify` or `test` |

The verification level is recorded per-contract, per-function in the module's exported metadata (see §8 — `ModuleEnv` extensions).

#### 4.4.2 Runtime Assertion Modes

The `--contracts` flag controls which runtime assertions are compiled into the output:

| Mode | Assertions included | Default for |
|------|---------------------|-------------|
| `--contracts=full` | All contracts (proven + tested + asserted) | `llmll test` |
| `--contracts=unproven` | Only `tested` and `asserted` contracts; `proven` contracts are stripped | `llmll build` (when a cached verify result exists) |
| `--contracts=none` | No runtime assertions | Opt-in only; requires explicit flag |

Without a prior `llmll verify` pass, `llmll build` defaults to `--contracts=full`.

> [!IMPORTANT]
> **Invariant:** Stripping a `proven` contract must not change observable behavior for any well-typed program. This invariant depends on `.fq` emitter faithfulness — see compiler team brief for verification obligations.

#### 4.4.3 Trust-Level Propagation

When module B imports module A and calls a function whose contract is `tested` or `asserted`, the compiler emits a **downstream trust warning**:

```
⚠ Function foo.bar.withdraw has an unproven postcondition.
  Your module inherits this trust gap.
```

The downstream module can acknowledge the gap explicitly:

```lisp
(trust foo.bar.withdraw :level asserted)
```

This silences the warning and makes the trust decision visible in source. An agent auditing module B can enumerate all `(trust ...)` declarations to see which unproven contracts it depends on.

`(trust ...)` declarations must appear in the import block (same ordering rules as `import`, `open`, `export`).
```

---

## Deliverable 3: Update CHANGELOG.md

Add an entry under v0.3 (in development):

```markdown
- **Principle 4 renamed** from "Runtime Contract Verification" to "Design by Contract with Stratified Verification." Contracts now carry a verification level (`proven`, `tested`, `asserted`). `--contracts` flag controls runtime assertion compilation. Trust-level propagation warns downstream modules about unproven dependencies.
```

---

## Open Questions for Review

> [!WARNING]
> **Granularity of `tested` level.** Should `tested` carry a sample count (e.g., `tested(1000)`) to distinguish high-coverage testing from minimal coverage? The professor raised this; deferring to v0.4 seems reasonable, but the `VerificationLevel` enum design should leave room for future refinement (e.g., `Tested { sampleCount :: Int }` rather than a bare tag).

> [!IMPORTANT]
> **`(trust ...)` syntax.** The proposed `(trust foo.bar.withdraw :level asserted)` form is new surface syntax. It needs:
> - A grammar rule in §12
> - A JSON-AST node kind in the schema
> - Parser support
>
> This is a cross-team dependency — the language team defines the syntax; the compiler team implements it.

---

## Relationship to Other Items

| Item | Relationship |
|------|-------------|
| Item 6 (`?delegate` lifecycle) | Agents filling holes via JSON-Patch will need to see the verification level of contracts in the subtree they are editing. The checkout metadata should include this. |
| Item 7b (compiler team brief) | Implementation counterpart to this spec. Covers `VerificationLevel` data type, `--contracts` flag, and `.fq` emitter faithfulness invariant. |
