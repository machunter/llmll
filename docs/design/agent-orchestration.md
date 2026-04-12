# Agent Orchestration: Design Discussion
>
> **Status:** Discussion draft  
> **Date:** 2026-04-11  
> **Context:** The v0.3 compiler delivers the *primitives* for multi-agent coordination (`?delegate`, checkout/patch, `?proof-required`). This document discusses the *workflow layer* that uses those primitives to actually coordinate agents.
---

## The Boundary

The LLMLL compiler is a **verifier**, not a **scheduler**. It answers one question: *"Is this program correct?"* — and provides primitives for agents to submit partial answers.

| Compiler owns | Orchestrator owns |
|---|---|
| Hole discovery (`llmll holes --json`) | Agent discovery (which LLM handles `@crypto-agent`?) |
| Hole locking (`llmll checkout`) | Task scheduling (which holes first? parallel?) |
| Patch verification (`llmll patch`) | Agent execution (API calls, context assembly) |
| Type checking + contracts | Retry / escalation on failure |
| Diagnostic reporting | Progress monitoring + audit trail |
| `llmll serve` HTTP API | Workflow definition + policy |
The compiler exposes primitives via CLI and HTTP. The orchestrator composes those primitives into a workflow.

---

## Analogy

| Domain | Low-level tool | Orchestration layer |
|---|---|---|
| Version control | `git` (commit, merge, diff) | GitHub Actions, CI/CD |
| Containers | Docker (build, run) | Kubernetes |
| Compilation | GCC/GHC | Make / Bazel |
| **LLMLL** | `llmll` (checkout, patch, verify) | **`llmll-orchestra`** |

---

## The Orchestration Loop

Every multi-agent LLMLL workflow follows the same core loop:

```
                    ┌────────────────┐
                    │  Lead Agent    │
                    │  writes the    │
                    │  program with  │
                    │  ?delegate     │
                    │  holes         │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  Orchestrator  │
                    │  reads holes   │
                    │  via llmll     │
                    │  holes --json  │
                    └───────┬────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
        ┌─────▼─────┐ ┌────▼────┐ ┌──────▼──────┐
        │ checkout   │ │checkout │ │  checkout   │
        │ hole A     │ │hole B   │ │  hole C     │
        └─────┬─────┘ └────┬────┘ └──────┬──────┘
              │             │             │
        ┌─────▼─────┐ ┌────▼────┐ ┌──────▼──────┐
        │ Agent A    │ │Agent B  │ │  Leanstral  │
        │ generates  │ │generates│ │  generates  │
        │ JSON-Patch │ │JSON-Patch│ │  proof      │
        └─────┬─────┘ └────┬────┘ └──────┬──────┘
              │             │             │
        ┌─────▼─────┐ ┌────▼────┐ ┌──────▼──────┐
        │ llmll      │ │ llmll  │ │  llmll      │
        │ patch      │ │ patch  │ │  patch      │
        │ (verify)   │ │(verify)│ │  (verify)   │
        └─────┬─────┘ └────┬────┘ └──────┬──────┘
              │             │             │
              └─────────────┼─────────────┘
                            │
                    ┌───────▼────────┐
                    │  All holes     │
                    │  filled?       │
                    │  → llmll build │
                    └────────────────┘
```

### Pseudocode

```python
def orchestrate(program_file, agent_registry, max_retries=3):
    # 1. Discover work
    holes = llmll("holes", "--json", program_file)
    
    # 2. Sort by dependency (blocking delegations before consumers)
    work_queue = topological_sort(holes)
    
    # 3. Process each hole
    for hole in work_queue:
        agent = agent_registry.lookup(hole.agent)
        
        # Lock the hole
        token = llmll("checkout", program_file, hole.pointer)
        
        # Give the agent context
        context = {
            "spec": read("LLMLL.md"),
            "hole": hole,
            "ast_fragment": extract_subtree(program_file, hole.pointer),
            "interface": hole.interface_contract,  # if def-interface exists
            "expected_type": hole.return_type,
        }
        
        # Agent generates a patch
        for attempt in range(max_retries):
            patch = agent.generate_patch(context)
            result = llmll("patch", program_file, patch)
            
            if result.status == "PatchSuccess":
                log_event("hole_filled", hole, attempt)
                break
            elif result.status == "PatchTypeError":
                # Feed diagnostics back to agent for retry
                context["diagnostics"] = result.diagnostics
                context["attempt"] = attempt + 1
            else:
                escalate(hole, result)
                break
        else:
            escalate(hole, "max retries exceeded")
    
    # 4. Build
    llmll("build", program_file)
```

---

## Agent Registry

The orchestrator needs to know which agents exist and how to reach them. This is configuration, not language semantics.

### Option A: Config file (`llmll-agents.json`)

```json
{
  "agents": {
    "@crypto-agent": {
      "provider": "anthropic",
      "model": "claude-sonnet-4-20250514",
      "system_prompt": "You are a cryptography specialist. You implement hash functions and token verification for LLMLL programs. Respond with a JSON-Patch against the program's JSON-AST.",
      "temperature": 0.0,
      "max_retries": 3
    },
    "@viz-agent": {
      "provider": "openai",
      "model": "gpt-4o",
      "system_prompt": "You render data visualizations...",
      "temperature": 0.2
    },
    "@leanstral": {
      "provider": "mcp",
      "endpoint": "lean-lsp-mcp://localhost:8800",
      "capabilities": ["proof-required"]
    }
  },
  "defaults": {
    "provider": "anthropic",
    "model": "claude-sonnet-4-20250514",
    "max_retries": 3,
    "checkout_ttl": 3600
  }
}
```

### Option B: Convention-based (agent = MCP tool name)

In an MCP-native environment, each `@agent-name` maps to an MCP server. The orchestrator is itself an MCP client. No config file needed — agent discovery happens via MCP's resource listing.

### Recommendation

Start with Option A (explicit config). Move to Option B when MCP adoption is mature. The config file is simple to implement and easy to debug
---

## Context Assembly

The hardest part of orchestration is giving the agent the right context. Too little → the agent hallucinates incompatible types. Too much → the context window overflows.

### What each agent needs

| Context item | Source | Required? |
|---|---|---|
| Language spec (`LLMLL.md`) | Filesystem | Yes — always |
| The hole's expected return type | `llmll holes --json` | Yes |
| The hole's `def-interface` contract | `llmll holes --json` | Yes, if interface exists |
| AST subtree around the hole | `program.ast.json` + pointer | Yes — shows surrounding code |
| Diagnostics from previous attempt | `llmll patch` failure result | On retry only |
| Module's type declarations | `program.ast.json` | Recommended — shows ADTs the agent must use |
| Other agents' interfaces | `program.ast.json` | Optional — for cross-agent awareness |

### Context strategy

```
Priority 1:  Hole spec (type, interface, agent name)      ~200 tokens
Priority 2:  Surrounding AST (parent function + params)   ~500 tokens
Priority 3:  Module type declarations                      ~300 tokens
Priority 4:  LLMLL.md relevant sections                    ~2000 tokens
Priority 5:  Full LLMLL.md                                 ~15000 tokens
```

For small models or expensive APIs: send priorities 1–3 + relevant LLMLL.md sections. For large-context models: send everything
---

## Scheduling Strategies

### Sequential (simplest)

Fill holes one at a time, in dependency order. Blocking delegation holes before async ones. Proof holes last (Leanstral is slow).

```
checkout A → agent A → patch A → checkout B → agent B → patch B → ...
```

**Pros:** Simple, deterministic, easy to debug.  
**Cons:** Slow. N holes = N sequential agent calls.

### Parallel (independent holes)

Identify holes that are independent (no type dependency between them) and farm them out simultaneously.

```
checkout A, B, C (parallel) → agents A, B, C → patch A, B, C → checkout D → ...
```

**Pros:** Fast — N independent holes done in 1 round-trip.  
**Cons:** Merge conflicts if patches touch overlapping AST regions. The lock system handles this, but rejections waste agent compute.

### Tiered

Round 1: Fill all `?delegate` blocking holes (they likely affect types downstream).  
Round 2: Fill all `?delegate-async` holes (fire-and-forget, less type impact).  
Round 3: Fill all `?proof-required` holes (Leanstral, slowest).
**Pros:** Natural dependency ordering. Proof holes run last when the AST is stable.  
**Cons:** Fixed strategy, not adaptive.

### Recommendation

Start with **tiered**. The dependency ordering is almost always correct for LLMLL programs: interfaces → implementations → proofs
---

## Error Recovery

### Retry with diagnostics

When `llmll patch` returns `PatchTypeError`, feed the diagnostics back to the agent:

```
"Your patch at /statements/2/body produced a type error:
  Expected: Result[string, DelegationError]
  Got:      string
  At:       patch-op/0/body
Please revise your JSON-Patch. The await expression returns
Result[t, DelegationError], not bare t."
```

The diagnostics are already structured JSON — the orchestrator just needs to format them for the agent's prompt.

### Escalation policy

| Condition | Action |
|---|---|
| Agent succeeds on retry ≤ 3 | Continue |
| Agent fails 3 times | Try different model (e.g., upgrade to opus) |
| Different model also fails | Mark hole as `?delegate-pending`, notify human |
| Lock expires (1 hour) | Release lock, re-queue hole |
| Agent returns malformed patch | Reject immediately, don't count as retry |

### Partial success

If 4 of 5 holes are filled and 1 fails, the program is still partially complete. The orchestrator should:

1. Write the partially-filled AST back
2. Run `llmll holes --json` to show remaining holes
3. Report which agents succeeded and which failed
4. Let the human decide: retry, reassign, or implement manually

---

## Implementation Language

### Option A: Python/TypeScript (pragmatic v1)

The first orchestrator should be written in **Python or TypeScript**.
**Rationale:**

- LLM provider SDKs (Anthropic, OpenAI, Google) are best supported in Python/TypeScript
- MCP client libraries are available in both
- The orchestrator's complexity is in API calls and workflow logic, not type safety
- The compiler team should not own `pip install anthropic`
- The boundary is HTTP: `POST /checkout`, `POST /patch` via `llmll serve`
The compiler is Haskell. The orchestrator is Python. They talk over HTTP. Clean separation.

### Option B: Self-Hosted in LLMLL (the endgame)

The orchestration loop is a state machine: `(State, Input) → (State, Command)`. That is exactly the core LLMLL pattern. The orchestrator *can be an LLMLL program*.

```lisp
(type OrchestraState
  (| Discovering   unit)              ;; waiting for holes --json response
  (| CheckingOut   HoleInfo)          ;; waiting for checkout response
  (| WaitingAgent  CheckoutToken)     ;; waiting for LLM response
  (| Patching      PatchPayload)      ;; waiting for patch verification
  (| Done          list[HoleResult])) ;; all holes resolved
(type HoleResult
  (| Filled    string)     ;; pointer that was filled
  (| Failed    string)     ;; pointer + reason
  (| Escalated string))    ;; pointer, needs human
(def-logic orchestrate-step [state: OrchestraState input: string]
  (match state
    (Discovering _)
      ;; input = JSON response from llmll holes --json
      ;; parse holes, checkout the first one
      (let [[holes (parse-holes input)]]
        (if (= (list-length holes) 0)
            (pair (Done (list-empty)) (wasi.io.stdout "No holes to fill.\n"))
            (let [[first-hole (unwrap (list-head holes))]]
              (pair (CheckingOut first-hole)
                    (wasi.http.post checkout-url
                      (format-checkout-request first-hole))))))
    (CheckingOut hole)
      ;; input = checkout token JSON from llmll serve
      (let [[token (parse-token input)]]
        (pair (WaitingAgent token)
              (wasi.http.post agent-api-url
                (format-agent-prompt hole token))))
    (WaitingAgent token)
      ;; input = LLM response containing JSON-Patch
      (let [[patch (extract-patch input)]]
        (pair (Patching patch)
              (wasi.http.post patch-url
                (format-patch-request token patch))))
    (Patching payload)
      ;; input = patch result from llmll serve
      (let [[result (parse-patch-result input)]]
        (match result
          (Success _) (pair (Done (list-append results (Filled pointer)))
                            (wasi.io.stdout "Hole filled.\n"))
          (Error diag) ...))))  ;; retry or escalate
(def-main
  :mode cli
  :step orchestrate-step)
```

#### Why this matters

**The orchestrator becomes a verified program.** Contracts on coordination logic:

```lisp
;; No hole pointer appears in both "checked out" and "filled"
(def-invariant no-double-checkout [state: OrchestraState]
  ...)
;; login-handler: bounded retries
(pre (<= retry-count max-retries))
;; post: every hole is either Filled, Failed, or Escalated — nothing dropped
(post (= (list-length results) (list-length original-holes)))
```

**The orchestrator can delegate its own subtasks.** The meta-level works: the orchestrator program itself can have `?delegate` holes. One agent writes `parse-holes`. Another writes `format-agent-prompt`. The orchestrator orchestrates its own construction — LLMLL all the way down.
**The orchestrator can orchestrate orchestrators.** A meta-orchestrator coordinates multiple projects, each with their own orchestrator instance. The type system ensures the meta-level and object-level don't conflict.

#### Feature gap analysis

| Need | LLMLL has it? | Gap |
|---|---|---|
| HTTP POST to `llmll serve` | ✅ `wasi.http.post` | — |
| HTTP POST to LLM APIs | ✅ `wasi.http.post` | — |
| JSON parsing of responses | ⚠️ No native JSON parser | Need `json-parse : string → Result[JsonValue, string]` in §13 stdlib, or use `(import haskell.aeson ...)` Tier 1 FFI |
| State machine loop | ✅ `def-main :mode cli` | — |
| Pattern matching on results | ✅ `match` on `Result` + `DelegationError` | — |
| Retry with backoff | ✅ Expressible as state counter | — |
| String formatting for prompts | ✅ `string-concat-many` | — |
| Concurrent agent calls | ✅ `?delegate-async` | — |
| File I/O (read AST, write patches) | ✅ `wasi.fs.read` / `wasi.fs.write` | — |
The **only real blocker** is JSON parsing. Two paths to close it:

1. **Add `json-parse` to §13 stdlib** — `json-parse : string → Result[JsonValue, string]` where `JsonValue` is a built-in sum type. Cleanest, but requires a new built-in type.
2. **Use Haskell FFI** — `(import haskell.aeson (interface [[decode (fn [string] → Result[JsonValue, string])]]))`. Works today with the existing Tier 1 FFI mechanism.

### Recommended path

**Phase 1:** Build the v1 orchestrator in Python (~200 lines). Validates the `llmll serve` API contract. Ships fast.
**Phase 2:** Once JSON parsing is available in LLMLL (either via stdlib addition or Aeson FFI), rewrite the orchestrator as a self-hosted LLMLL program. This becomes:

- A proof-of-concept that LLMLL can build real tools
- A verified orchestrator with contracts on coordination correctness
- A flagship example for the v0.3 exercise problems
**Phase 3:** The self-hosted orchestrator becomes the default. The Python version is retained as a lightweight alternative for environments without the LLMLL compiler installed.

---

## Open Questions
>
> **Q1: Should the orchestrator ship with the compiler?**
>
> Two options:
>
> - `llmll orchestrate` — built into the compiler binary. Zero-setup. But Haskell team owns LLM API clients.
> - `llmll-orchestra` — separate pip/npm package. Uses `llmll serve`. Clean boundary. Two things to install.
>
> Leaning toward: separate package. The compiler should not depend on `http-client` calls to `api.anthropic.com`.
> **Q2: How does the orchestrator know hole dependencies?**
>
> Currently, `llmll holes --json` returns a flat list. The orchestrator would benefit from a dependency graph: "hole B's type depends on hole A's return type." This could be a `--json --deps` flag that adds a `depends_on` field to each hole entry.
>
> Needed before: parallel scheduling.
> **Q3: Should the orchestrator reuse the Event Log?**
>
> The Event Log (roadmap Item 5) records `(Input, CommandResult, captures)` for deterministic replay. The orchestrator's actions (checkout, patch, agent call, result) are a natural extension. Should orchestration events go into the same log format, or a separate audit log?
>
> Leaning toward: same format. One log, one replay mechanism. The orchestrator's events are just another kind of input/result.
> **Q4: How does `?scaffold` interact with orchestration?**
>
> `?scaffold` templates are fetched from `llmll-hub`. The orchestrator could:
>
> - (a) Treat `?scaffold` as a special hole that gets resolved first (before any `?delegate`)
> - (b) Have the Lead Agent resolve `?scaffold` itself during program authoring
>
> Leaning toward: (b). Scaffolding is a Lead Agent responsibility, not a delegation. The orchestrator only handles `?delegate` and `?proof-required` holes.
> **Q5: MCP integration — client or server?**
>
> The orchestrator could be:
>
> - An MCP **client** that calls agents (each agent is an MCP server)
> - An MCP **server** that exposes `orchestrate` as a tool (an IDE like Cursor calls it)
> - Both — an MCP client for agents, MCP server for the IDE
>
> Leaning toward: both. The orchestrator is a bridge between the IDE/human and the agent swarm.
---

## First Milestone

A minimal orchestrator that can run Problem 1 (Two-Agent Auth Module) from the v0.3 exercise problems:

1. Read `auth-module.ast.json`, call `llmll holes --json`
2. Find the two `?delegate @crypto-agent` holes
3. Checkout both holes
4. Call Claude Sonnet with the hole context + LLMLL.md
5. Submit the returned JSON-Patches via `llmll patch`
6. Report success/failure
This is ~200 lines of Python. It validates the entire compiler ↔ orchestrator interface before building anything more complex.
