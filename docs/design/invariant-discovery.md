# Invariant Discovery — Design Discussion

> **Source:** External critique follow-up, April 2026  
> **Status:** Future design work — addresses the "specification coverage" gap  
> **Key insight:** The bottleneck is not spec *quality* but spec *coverage* — what gets specified at all.

---

## The Problem

LLMLL detects violated constraints and propagates uncertainty. It does NOT yet systematically create pressure to **add invariants that are missing entirely**.

A function with no postcondition is perfectly valid. The system won't complain. But the verification guarantee is empty.

This is the refined version of the "spec quality" concern:

> **Absent specs are invisible. Weak specs are visible. The system handles the second but not the first.**

---

## Six Mechanisms for Driving Invariant Discovery

### 1. Adversarial Agent ("Red Team")

A dedicated agent whose job is to find **trivial or degenerate implementations** that satisfy the current spec.

**Workflow:**
1. After a spec is written, the red-team agent attempts to implement it with the simplest possible code
2. If `identity` satisfies the sort spec → the spec is provably too weak
3. The red-team agent reports: "Your spec for `sort-list` admits `identity` as valid. Missing: `sorted` invariant?"
4. This creates concrete pressure to strengthen the spec

**Why this works:** It's an automated version of what the external reviewer did manually with the sorting example. It turns spec weakness into a specific, actionable diagnostic.

**Implementation:** Could be a mode of the orchestrator — `llmll audit --red-team` — that attempts trivial fills for every typed hole.

### 2. Mutation Testing on Specs

Systematically weaken contracts and check if the implementation still passes:

1. Remove one postcondition clause
2. Re-verify
3. If verification still passes → that clause was never exercised
4. If the weakened spec admits trivial implementations → flag as "spec may be insufficient"

**Analogy:** Like code mutation testing, but for specifications. Instead of "does the test catch this code change?", it asks "does anyone actually depend on this spec clause?"

### 3. Property Mining from Implementations

After an agent implements a function, automatically infer candidate invariants by observing behavior:

1. Generate random inputs (QuickCheck-style)
2. Run the implementation
3. Observe patterns: "output is always sorted," "output length equals input length," "output contains no duplicates"
4. Propose these as contract candidates
5. Agent/user confirms or rejects

**Prior art:** Daikon (MIT) — dynamic invariant detection. Well-studied technique, directly applicable.

### 4. Spec Coverage Metric

Define a heuristic coverage score for specifications:

| Factor | Score contribution |
|--------|-------------------|
| No postcondition at all | 0% |
| Only type constraints | 20% |
| Arithmetic postconditions | 40% |
| Structural postconditions (sorted, unique, etc.) | 60% |
| Fully proven with inductive properties | 80-100% |

Report as `llmll verify --spec-coverage`. Like code coverage but for specifications. Not formally precise, but creates pressure.

### 5. Hub-Driven Spec Suggestions

When a function has a common type signature, suggest contracts from the component hub:

> "Functions with signature `list[int] -> list[int]` in the registry typically have these contracts: `sorted`, `length-preserved`, `subset`. Your function has none. Add?"

This leverages accumulated specification patterns from past projects.

### 6. Counter-Example Display

When a spec admits trivial implementations, show the trivial implementation as evidence:

```
⚠ Spec weakness detected for `sort-list`:
  Your contract: (post (= (length result) (length input)))
  Trivial valid implementation: (lambda [xs] xs)
  Consider adding: (post (sorted result))
```

This is the most direct feedback possible — the system shows you *exactly* how your spec fails to distinguish correct from incorrect.

---

## The Refined Spec Landscape

The external reviewer's key reframe:

> **LLMs can write *local, shallow, and reactive constraints* well, but struggle with *global, minimal, and generative specifications*.**

LLMLL is aligned with LLM strengths because:

| LLMLL's spec requirements | LLM capability | Fit |
|---------------------------|----------------|-----|
| Local constraints | Strong | ✅ |
| Compositional refinements | Moderate | ✅ |
| Incremental from typed holes | Moderate | ✅ |
| Minimal covering specs | Weak | ❌ |
| Global invariants | Weak | ❌ |

The invariant discovery mechanisms above address the ❌ rows by creating **automated pressure** to improve spec coverage.

---

## The Strongest Defensible Position

> **"LLMLL does not require models to produce complete formal specifications. It relies on their ability to generate incremental, local constraints, which current models handle reasonably well. The system's verification loop then exposes missing or weak constraints through trivial implementations, failed tests, or low trust propagation. The remaining challenge is not specification correctness but specification coverage and program decomposition."**

---

## Roadmap Implications

| Item | Priority | Team |
|------|----------|------|
| Red-team agent / `--red-team` mode | **High** — most impactful, directly actionable | Orchestrator |
| Counter-example display for weak specs | **High** — low implementation cost, high signal | Compiler |
| Spec coverage metric (`--spec-coverage`) | Medium | Compiler |
| Property mining (Daikon-style) | Medium — research component | Research |
| Hub-driven spec suggestions | Medium — depends on hub | Orchestrator |
| Spec mutation testing | Low — complex, less urgent | Research |
