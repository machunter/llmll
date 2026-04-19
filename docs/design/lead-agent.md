# Lead Agent: Automated Skeleton Generation

> **Status:** Design draft
> **Date:** 2026-04-18
> **Context:** The current orchestration pipeline assumes a human writes the
> skeleton (the program structure with `?delegate` holes). This document
> designs the path to having a Lead AI agent generate skeletons from
> natural-language specifications, closing the loop from intent to verified
> program.

### Review History

| Date | Team | Status |
|------|------|--------|
| 2026-04-18 | Compiler Team | Initial draft |

---

## Problem Statement

The LLMLL orchestration pipeline has two distinct phases:

```
Phase 1: Skeleton authoring     ← currently manual
  "Build an auth module with password hashing and session management"
  → LLMLL source with def-interface, def-logic, ?delegate holes, contracts

Phase 2: Hole filling           ← automated (llmll-orchestra)
  LLMLL source with holes → filled program → generated Haskell
```

Phase 2 is solved: `llmll-orchestra` dispatches holes to agents, retries with
diagnostics, and verifies every fill. Phase 1 is entirely manual. The human (or
"Lead Agent" in the docs) writes the skeleton — choosing the architecture, type
signatures, dependency structure, agent assignments, and fallback values.

This is the highest-leverage gap in the system. The skeleton encodes all the
architectural decisions that constrain everything downstream. A bad skeleton
produces a correct-by-types but wrong-by-design program. A good skeleton makes
the specialist agents' jobs easy.

### Why this is hard

Skeleton authoring requires **architectural judgment**, not just code generation:

| Decision | What it determines |
|---|---|
| Which functions exist | The decomposition of the problem |
| Parameter and return types | The specification each agent must satisfy |
| Which functions call which | The dependency DAG (fill order, parallelism) |
| `@agent` assignments | Which specialist handles each piece |
| `on_failure` values | Runtime resilience behavior |
| `pre`/`post` contracts | What correctness means (verification targets) |
| `def-interface` shapes | The public API surface |

A specialist agent filling `hash-password-impl` only needs to produce a
`string`. The skeleton author needed to decide that password hashing is a
separate function, that it takes a `raw-pw: string`, that it returns `string`
(not `bytes[64]`), that `@crypto-agent` handles it, and that `"hash-unavailable"`
is the right fallback. These are design decisions, not synthesis tasks.

---

## Architecture

### Two-phase orchestration

The Lead Agent extends `llmll-orchestra` with a new **`--mode lead`** that runs
before the existing `--mode fill` (the current default):

```
┌─────────────────────────────────────────────────────┐
│                   llmll-orchestra                    │
│                                                     │
│  ┌──────────────────┐    ┌───────────────────────┐  │
│  │  --mode lead      │    │  --mode fill           │  │
│  │                   │    │  (existing)            │  │
│  │  Intent → Skeleton│───▶│  Skeleton → Program   │  │
│  │                   │    │                        │  │
│  │  Lead Agent loop: │    │  Specialist loop:      │  │
│  │  1. Decompose     │    │  1. checkout           │  │
│  │  2. Generate AST  │    │  2. agent.fill_hole    │  │
│  │  3. llmll check   │    │  3. llmll patch        │  │
│  │  4. Iterate       │    │  4. retry              │  │
│  └──────────────────┘    └───────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

A combined mode `--mode auto` runs lead → fill → verify in sequence:

```bash
# The full pipeline: intent → verified Haskell
llmll-orchestra --mode auto \
  --intent "Build an authentication module with password hashing,
            token verification, session management, and a gateway.
            Use a crypto specialist for the low-level operations." \
  --output auth_module.ast.json \
  -v
```

### The Lead Agent loop

The Lead Agent is *not* a single-shot generator. It operates in a
compiler-in-the-loop cycle, the same pattern used for hole filling but at a
different level of abstraction:

```
Intent (natural language)
    │
    ▼
┌─────────────────────────────┐
│  Step 1: Architecture Plan  │  ← LLM generates structured decomposition
│  (functions, types, deps)   │     (JSON, not LLMLL yet)
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Step 2: Skeleton Generation│  ← LLM translates plan → JSON-AST
│  (JSON-AST with ?delegate  │
│   holes, types, contracts)  │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Step 3: Compiler Validation│  ← llmll check (type errors?)
│                             │     llmll holes --deps (DAG sane?)
└──────────┬──────────────────┘
           │
      ┌────┴────┐
      │ Pass?   │
      └────┬────┘
       Yes │  No → feed diagnostics back to Step 2
           ▼
┌─────────────────────────────┐
│  Step 4: Quality Check      │  ← Structural heuristics
│  (good decomposition?       │     (see Quality Criteria below)
│   reasonable types?         │
│   parallelism possible?)    │
└──────────┬──────────────────┘
           │
      ┌────┴────┐
      │ Pass?   │
      └────┬────┘
       Yes │  No → feed advice back to Step 1
           ▼
    Skeleton ready → proceed to --mode fill
```

### Step 1: Architecture Plan

The Lead Agent first produces a **structured architecture document** — not
LLMLL code. This separates reasoning from syntax generation:

```json
{
  "module_name": "auth_module",
  "description": "Authentication module with password hashing, token verification, session management, and gateway routing",
  "interfaces": [
    {
      "name": "AuthSystem",
      "methods": [
        {"name": "hash-password", "params": [["raw-pw", "string"]], "returns": "string"},
        {"name": "verify-token", "params": [["token", "string"]], "returns": "bool"}
      ]
    }
  ],
  "functions": [
    {
      "name": "hash-password-impl",
      "params": [["raw-pw", "string"]],
      "return_type": "string",
      "agent": "@crypto-agent",
      "tier": 0,
      "on_failure": "hash-unavailable",
      "description": "Hash the raw password using a salt-based scheme",
      "contracts": { "pre": null, "post": null }
    },
    {
      "name": "verify-token-impl",
      "params": [["token", "string"]],
      "return_type": "bool",
      "agent": "@crypto-agent",
      "tier": 0,
      "on_failure": false,
      "description": "Verify the session token is well-formed and not expired"
    },
    {
      "name": "login-handler",
      "params": [["username", "string"], ["password", "string"]],
      "return_type": "Result[string, string]",
      "agent": "@session-agent",
      "tier": 1,
      "calls": ["hash-password-impl"],
      "on_failure": "(err \"session-agent unavailable\")",
      "contracts": { "pre": "(not (= (string-length password) 0))" }
    },
    {
      "name": "authenticate-request",
      "params": [["username", "string"], ["password", "string"], ["existing-token", "string"]],
      "return_type": "Result[string, string]",
      "agent": "@gateway-agent",
      "tier": 2,
      "calls": ["verify-token-impl", "login-handler"],
      "on_failure": "(err \"gateway-agent unavailable\")"
    }
  ],
  "dependency_graph": {
    "hash-password-impl": [],
    "verify-token-impl": [],
    "login-handler": ["hash-password-impl"],
    "authenticate-request": ["verify-token-impl", "login-handler"]
  }
}
```

This plan is **not checked by the compiler** — it's a reasoning artifact. The
LLM can iterate on it purely through self-review before committing to LLMLL
syntax.

### Step 2: Skeleton Generation

A second LLM call (or continuation) translates the architecture plan into a
valid JSON-AST file. The prompt includes:

1. The architecture plan from Step 1
2. The LLMLL JSON-AST schema (`docs/llmll-ast.schema.json`)
3. The builtin reference from the gap analysis (Option A — already in the
   specialist agent prompt)
4. One or two example skeletons from `llmll-hub` for structural guidance

The output is a complete `.ast.json` file with `schemaVersion`, `llmll_version`,
and `statements` containing `def-interface`, `def-logic` with `?delegate` holes,
type declarations, and contracts.

### Step 3: Compiler Validation

The orchestrator runs:

```bash
# Does it parse and type-check?
llmll check skeleton.ast.json

# What holes exist and what's the dependency graph?
llmll --json holes --deps skeleton.ast.json
```

If `check` fails, the diagnostics are fed back to the Lead Agent for correction.
This is the same retry-with-diagnostics pattern used for hole filling, but at
the skeleton level.

If `holes --deps` returns unexpected structure (e.g., a long serial chain where
the intent implied parallelism), the orchestrator can flag this for review.

### Step 4: Quality Check

Beyond type-correctness, the orchestrator applies **structural heuristics** to
catch common architectural mistakes:

| Check | What it catches | Severity |
|---|---|---|
| **Parallelism** — Tier 0 has only 1 hole | Everything is serial; intent probably implied parallel work | Warning |
| **Fan-out** — Single function has > 5 dependencies | Over-centralized design; probably needs decomposition | Warning |
| **Missing contracts** — Functions with no `pre`/`post` | Verification pipeline has nothing to check | Info |
| **Loose types** — Everything is `string` | Type system provides no real constraints | Warning |
| **Sentinel collision** — `on_failure` value is in the return type's range | Runtime protocol ambiguity (as identified in the walkthrough) | Warning |
| **Orphan interface** — `def-interface` with no matching implementations | Dead code in the skeleton | Warning |
| **Unassigned agents** — `?delegate` with no `@agent` | Orchestrator can't dispatch without an agent | Error |

These are heuristics, not formal checks. They can be overridden. The
orchestrator presents them as suggestions, not blockers (except "Unassigned
agents," which is a hard error).

---

## The Lead Agent Prompt

### System Prompt (Lead Agent)

The Lead Agent needs a fundamentally different system prompt than the specialist
agents. The specialist prompt says "fill this hole with this type." The Lead
Agent prompt says "architect a program from this intent."

```
You are an LLMLL architecture agent. You receive a natural-language
specification and produce a program skeleton in LLMLL JSON-AST format.

Your output is a PARTIAL program — every function body is a ?delegate hole.
Specialist agents will fill the holes later. Your job is to get the
architecture right: the right functions, the right types, the right
dependencies, and the right agent assignments.

## What you decide

1. DECOMPOSITION — which functions exist and what each one does
2. TYPE SIGNATURES — parameter types and return types for each function
3. DEPENDENCY STRUCTURE — which functions call which (via let bindings)
4. AGENT ASSIGNMENTS — which @agent fills each hole
5. CONTRACTS — pre/post conditions (optional but valuable)
6. FALLBACKS — on_failure values for each delegate
7. INTERFACES — def-interface declarations for API boundaries

## Architecture principles

- MAXIMIZE PARALLELISM: Functions that don't depend on each other should
  be at the same tier. Prefer wide, shallow dependency graphs over deep
  serial chains.
- USE PRECISE TYPES: Result[ok, err] instead of string when operations
  can fail. Pair types for compound returns. Custom ADTs when the domain
  warrants it.
- SEPARATE CONCERNS: Each @agent should have a coherent responsibility.
  Don't mix cryptography and session management in the same agent.
- DESIGN FOR FAILURE: Every ?delegate needs an on_failure value. Choose
  values that downstream functions can detect and handle gracefully.

## Output format

You will be asked to produce output in two stages:
1. An architecture plan (JSON) describing functions, types, dependencies
2. A JSON-AST file conforming to the LLMLL schema

[Include: LLMLL JSON-AST schema excerpt]
[Include: Builtin function reference from gap analysis Option A]
[Include: Type node reference]
```

### User Prompt (per request)

```
## Specification

{user_intent}

## Available agent roles

{agent_registry — from llmll-agents.json}

## Stage

{stage_1_or_stage_2}

## Prior feedback (if any)

{compiler_diagnostics_or_quality_warnings}
```

---

## Integration with Existing Code

### New modules

```
tools/llmll-orchestra/llmll_orchestra/
  lead_agent.py        ← NEW: LeadAgent class, LEAD_SYSTEM_PROMPT,
                         build_lead_prompt(), parse_architecture_plan(),
                         translate_plan_to_ast()
  quality.py           ← NEW: skeleton_quality_check(), heuristic checks
  __main__.py          ← MODIFY: add --mode lead|fill|auto, --intent
  orchestrator.py      ← MODIFY: add lead_run() method
```

### `lead_agent.py` — core interface

```python
@dataclass
class ArchitecturePlan:
    """Structured decomposition of a program."""
    module_name: str
    functions: list[FunctionSpec]
    interfaces: list[InterfaceSpec]
    dependency_graph: dict[str, list[str]]

@dataclass
class FunctionSpec:
    name: str
    params: list[tuple[str, str]]
    return_type: str
    agent: str
    description: str
    on_failure: str | None
    calls: list[str]
    contracts: dict[str, str | None]

class LeadAgent:
    """Generates LLMLL skeletons from natural-language intent."""

    def __init__(self, model: str, provider: str, ...):
        ...

    def generate_plan(self, intent: str, context: dict) -> ArchitecturePlan:
        """Step 1: intent → structured architecture plan."""
        ...

    def generate_skeleton(self, plan: ArchitecturePlan, context: dict) -> dict:
        """Step 2: architecture plan → JSON-AST."""
        ...
```

### `quality.py` — structural heuristics

```python
@dataclass
class QualityWarning:
    severity: str  # "error" | "warning" | "info"
    check: str     # "parallelism" | "fan-out" | "loose-types" | ...
    message: str
    suggestion: str | None

def skeleton_quality_check(
    ast: dict,
    holes: list[HoleEntry],
    tiers: list[list[HoleEntry]],
) -> list[QualityWarning]:
    """Run structural heuristics on a generated skeleton."""
    warnings = []

    # Check: Tier 0 has only 1 hole (low parallelism)
    if len(tiers) > 0 and len(tiers[0]) == 1 and len(tiers) > 2:
        warnings.append(QualityWarning(
            severity="warning",
            check="parallelism",
            message="Tier 0 has only 1 hole but the program has multiple tiers",
            suggestion="Consider whether some functions could be independent",
        ))

    # Check: Everything is string
    # Check: Missing contracts
    # Check: Unassigned agents
    # ...

    return warnings
```

### CLI extension

```bash
# Generate skeleton only
llmll-orchestra --mode lead \
  --intent "Build an auth module..." \
  --output auth_module.ast.json

# Generate + fill + verify (full pipeline)
llmll-orchestra --mode auto \
  --intent "Build an auth module..." \
  --output auth_module_filled.ast.json \
  -v

# Fill only (existing behavior, default)
llmll-orchestra --mode fill auth_module.ast.json
```

### `--mode auto` pipeline

```python
def auto_run(self, intent: str, output: str) -> OrchestratorReport:
    # Phase 1: Lead Agent generates skeleton
    plan = self.lead_agent.generate_plan(intent, context)
    ast = self.lead_agent.generate_skeleton(plan, context)
    write_ast(output, ast)

    # Phase 1b: Compiler validation loop
    for attempt in range(self.max_retries):
        result = self.compiler.check(output)
        if result.success:
            break
        # Feed diagnostics back to Lead Agent
        ast = self.lead_agent.generate_skeleton(
            plan, {**context, "diagnostics": result.diagnostics}
        )
        write_ast(output, ast)
    else:
        return report_failure("skeleton generation failed")

    # Phase 1c: Quality check
    warnings = skeleton_quality_check(ast, holes, tiers)
    # Log warnings, optionally iterate

    # Phase 2: Fill holes (existing orchestrator)
    report = self.run(output)

    # Phase 3: Verify (optional)
    if report.failed == 0:
        self.compiler.verify(output)

    return report
```

---

## Interaction with Existing Features

### `?scaffold` integration

`?scaffold` and the Lead Agent solve the same problem at different levels:

| | `?scaffold` | Lead Agent |
|---|---|---|
| Input | Template name + key-value args | Free-form natural language |
| Output | Pre-built skeleton from hub | Generated skeleton (novel) |
| Flexibility | Fixed templates | Open-ended |
| Reliability | Deterministic (no LLM) | LLM-dependent |
| When to use | Known problem patterns | Novel architectures |

The Lead Agent should **prefer `?scaffold` when a matching template exists**.
The architecture plan step can include a template-matching check:

```python
def generate_plan(self, intent, context):
    # Check if a hub template matches
    templates = self.compiler.hub_list()
    match = self.match_template(intent, templates)
    if match:
        # Use scaffold instead of generating from scratch
        return ScaffoldPlan(template=match.name, customizations=...)
    else:
        # Full generation
        return self._llm_generate_plan(intent, context)
```

### `POST /sketch` integration

The Lead Agent can use `POST /sketch` (from `llmll serve`) for **incremental
validation** during skeleton generation. Instead of generating the full AST
and checking it all at once, the agent can:

1. Generate the `def-interface` → POST /sketch → check types
2. Add `def-logic` stubs one at a time → POST /sketch → check each
3. Add contracts → POST /sketch → check contract syntax

This requires the agent to have tool-use capability (function calling). The
architecture supports it — `POST /sketch` is stateless, so concurrent calls
from a multi-turn agent loop are safe.

### Context-aware checkout (gap analysis Phase C)

When Phase C ships (context-aware checkout with Γ, τ, Σ in the checkout
response), the Lead Agent benefits indirectly: the skeletons it generates will
be filled more accurately by specialist agents because those agents receive
richer typing context. The Lead Agent itself doesn't use checkout (it writes
the skeleton, not the fills).

---

## Phasing

### Phase 0: Architecture plan only (exploratory — ~2 days)

Add `--mode plan` that takes `--intent` and outputs a structured architecture
plan (JSON). No AST generation. No compiler integration. This validates:
- Can the LLM produce a reasonable decomposition?
- Do the architecture plans map cleanly to LLMLL structure?
- What failure modes exist at the planning level?

### Phase 1: Skeleton generation with validation (~3 days)

Add `--mode lead` that generates a JSON-AST skeleton and validates it via
`llmll check`. Retry loop for compiler errors. Quality checks. This delivers:
- End-to-end skeleton generation from intent
- Compiler-validated output
- Human review point before hole filling

### Phase 2: Full auto mode (~2 days, depends on Phase 1)

Add `--mode auto` that chains lead → fill → (optionally) verify. This is
mostly plumbing — connecting the lead output to the existing fill pipeline.

### Phase 3: Iterative refinement with tool-use (~3 days)

Give the Lead Agent access to `POST /sketch` as a tool during skeleton
generation. This transforms it from a single-shot generator into an
iterative, type-directed architect. Requires an agentic framework with
function-calling support (e.g., Anthropic tool use, OpenAI function calling).

### Phase 4: Self-hosted Lead Agent (aspirational)

Write the Lead Agent as an LLMLL program. The Lead Agent becomes a
`def-main :mode cli` program that reads intent from stdin, calls
`llmll serve` via `wasi.http.post`, and writes a skeleton to stdout.
This is the "LLMLL all the way down" endgame described in
[agent-orchestration.md](agent-orchestration.md).

---

## Open Questions

> [!IMPORTANT]
> **Q1: Should the Lead Agent be the same LLM as the specialist agents?**
>
> The specialist agents fill small, well-typed holes. The Lead Agent makes
> architectural decisions. These are fundamentally different tasks. Using a
> more capable model for lead (e.g., o3, opus) and a faster model for
> specialists (e.g., gpt-4o, sonnet) may be the right split. The
> `llmll-agents.json` config already supports per-agent model selection.

> [!IMPORTANT]
> **Q2: How much LLMLL specification does the Lead Agent need?**
>
> The specialist agents need the builtin reference and evaluation rules
> (gap analysis Option A, ~950 tokens). The Lead Agent needs more: the
> JSON-AST schema, type constructor syntax, `def-interface` syntax,
> `?delegate` syntax, and contract syntax. This is roughly 2000–3000
> tokens. Manageable for modern context windows, but we should measure
> and optimize.

> [!IMPORTANT]
> **Q3: How do we evaluate skeleton quality?**
>
> Type-correctness is checkable (the compiler does it). Architectural
> quality is subjective. We could:
> - Compare against human-written skeletons for known problems
> - Measure downstream fill success rate (do specialist agents succeed
>   more often with auto-generated vs hand-written skeletons?)
> - Track dependency graph properties (width, depth, parallelism ratio)

> **Q4: Should the Lead Agent see previous successful skeletons?**
>
> Few-shot prompting with 1–2 example skeletons (like the auth module)
> could dramatically improve output quality. The `llmll-hub` template
> cache is a natural source of examples. The risk is overfitting —
> every skeleton looking like the auth module.

---

## Relationship to Existing Design Docs

| Document | Relationship |
|---|---|
| [agent-orchestration.md](agent-orchestration.md) | Defines the orchestrator/compiler boundary, scheduling strategies, and the self-hosted endgame. This doc extends it with the Lead Agent concept. |
| [agent-prompt-semantics-gap.md](agent-prompt-semantics-gap.md) | The Lead Agent has the same knowledge gap as specialist agents (plus more). Phase A prompt enrichment applies to both. Phase C (context-aware checkout) benefits specialists filling lead-generated skeletons. |
| [orchestrator-walkthrough.md](../orchestrator-walkthrough.md) | The walkthrough demonstrates the current system with a human-written skeleton. The Lead Agent automates Step 0 (which the walkthrough currently starts at). |

---

## Summary

The Lead Agent closes the last manual step in the LLMLL pipeline: skeleton
authoring. It uses the same compiler-in-the-loop pattern that makes hole
filling reliable — generate, validate, iterate — but operates at the
architectural level rather than the expression level. The key design decisions
are: (1) separate planning from code generation (two-step prompt), (2) reuse
the compiler as the validation oracle, and (3) add structural quality
heuristics that catch design mistakes the type system can't see.

The implementation is incremental: architecture plans first, then skeleton
generation, then the full auto pipeline. Each phase is independently useful
and testable.
