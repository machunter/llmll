# LLMLL — Outreach Bundle

Three pieces, designed to be posted independently or read together. Two short framing posts target different audiences — research/alignment and Claude Code-adjacent product — and a supporting walkthrough both posts link to.

| Piece | Audience | Length | Channels |
|---|---|---|---|
| [Verification as a coordination protocol](#verification-as-a-coordination-protocol) | Alignment / agent research | ~590 words | Anthropic research blog (guest), alignment forum, research Twitter |
| [Typed file editing: what if the editor rejected ill-typed patches?](#typed-file-editing-what-if-the-editor-rejected-ill-typed-patches) | Claude Code, MCP / dev-tool builders | ~625 words | Claude Code subreddit, dev Twitter, HN |
| [Walkthrough: filling a hole through checkout/patch](#walkthrough-filling-a-hole-through-checkoutpatch) | Both — supporting material | ~800 words | Linked from both posts |

Both posts assume the reader has not seen LLMLL before; the walkthrough assumes the reader has just clicked through from one of them.

---

## Verification as a coordination protocol

Most multi-agent coding systems — LangGraph, AutoGen, the parallel-consultant patterns now common in agent harnesses — coordinate through conversation. Agents talk to each other (often through a synthesizer) and the burden of keeping outputs compatible lives in the conversation. **LLMLL is an experiment in replacing that conversation with a compiler.** Agents don't coordinate by talking. They coordinate by attaching formal specifications to every interface, and the compiler refuses to merge any output that fails to satisfy them.

Concretely: a lead agent decomposes a program into typed holes — placeholders carrying a precise type signature and `pre`/`post` contracts. Specialist agents check out individual holes, submit JSON-Patch operations against the program's AST, and the compiler re-verifies before accepting. A `?delegate` hole carries everything the next agent needs to fill it — the expected return type, the in-scope bindings, the contract obligations the result must discharge — without any prose handoff. The coordination contract is the type signature plus the clauses; the enforcement is liquid-fixpoint plus Z3.

This reframes hallucination. An agent can produce any candidate implementation it likes; the compiler accepts it iff it satisfies the spec. Generation becomes generate-and-check search with a formal filter — structurally similar to RL-with-verifiers, but with the verifier being a sound SMT decision procedure over a known fragment rather than a learned reward model.

**The catch is specification quality.** A verified program against a weak spec is still wrong; the spec just didn't notice. LLMLL makes this risk first-class through two mechanisms.

*Weakness checking* (`llmll verify --weakness-check`). After a SAFE verification result, the compiler constructs trivial candidate bodies — identity, constant zero, empty string, `true` — and asks: does any of them also satisfy the contract? If `sort-list`'s postcondition `(= (list-length result) (list-length input))` is satisfied by `(def-logic sort-list [xs] xs)`, the spec is flagged as under-specified, with the trivial body that passed shown to the agent. This is a calibration mechanism for specifications: the system tells you when your spec is overconfident about what it constrains.

*A trust lattice with propagated levels.* Every contract clause carries a display level — `verified` (SMT proof), `contract-checked` (consistency only), `tested` (PBT), or `asserted` (runtime check). Trust propagates: a `verified` conclusion that transitively depends on an `asserted` callee is flagged as epistemic drift in `--trust-report`. No "verified" claim silently rests on an unproven assumption. This is interpretability for the verification chain — every audit-relevant judgment is named, and the assumption graph is walkable.

The shipped surface is a non-recursive QF-LIA core with compositional assume-guarantee reasoning across function call chains; an interactive proof path (Lean 4 via Leanstral MCP) is designed but blocked on tooling. Two frozen benchmarks — [ERC-20](https://github.com/machunter/llmll/tree/main/examples/erc20_token) and [TOTP RFC 6238](https://github.com/machunter/llmll/tree/main/examples/totp_rfc6238) — show the verification-scope matrix on real specifications, and the [v0.10 obligation-guided coding spec](https://github.com/machunter/llmll/blob/main/docs/design/oblig-0-spec.md) describes how structured obligation reports give an agent the hole's full proof context as a single JSON object.

The honest open question is whether today's models can write contracts that catch real bugs rather than generic ones. Spec quality, not syntax, is the actual bottleneck — and it's tractable: target domains (financial compliance, protocol implementation, cryptography) already have specifications as external standards, so the agent's task is *translation*, not *invention*. The whole system is itself a case study in this question, since LLMLL was built solo with AI tools as collaborators.

Full one-pager: [docs/one-pager.md](https://github.com/machunter/llmll/blob/main/docs/one-pager.md). LLMLL is GPLv3 — feedback welcome.

---

## Typed file editing: what if the editor rejected ill-typed patches?

When Claude Code edits a file, the Edit tool gets two strings — `old_string` and `new_string` — and the harness substitutes them. There's no structural validation. If the new string introduces a type error, an unbalanced brace, or a contract violation, you find out the next time something runs over the file. Edits are bytes; the type system is "any sequence of bytes that doesn't crash later."

That's fine for most languages. **LLMLL is an experiment in what happens when you flip it: edits are typed, scope-contained, and rejected at the patch boundary if they don't fit.** It's not a different kind of agent — it's a different kind of editor. The interesting question is whether the design generalizes.

The lifecycle for filling an unimplemented hole:

1. **Discover.** `llmll holes file.ast.json --json` returns every `?hole` with its type, scope, and dependency edges. The agent doesn't infer what's open from comments — the compiler tells it.

2. **Checkout.** `llmll checkout file.ast.json /statements/2/body` locks one hole and returns a token plus the *local typing context*: bindings in scope (Γ), expected return type (τ), and available functions monomorphized against the concrete scope (Σ). Concurrent checkout on the same pointer is rejected with a structured diagnostic; locks have a TTL.

3. **Patch.** The agent submits an RFC 6902 JSON-Patch scoped to the locked subtree. The compiler re-parses, re-typechecks, and — if the function carries contracts — re-verifies via SMT. If anything fails, the patch is rejected and the diagnostic points at the *patch operation* that broke things, not at the file.

4. **Iterate.** Next agent picks up the next hole. Type environments are cached between patches; only the touched subtree is re-verified.

The result is concurrent editing without merge conflicts (each agent owns one subtree, scope-contained), structural validation before commit (no "tests fail later"), and the agent never has to infer what's in scope — the compiler hands it the typing context as a JSON object. An HTTP endpoint (`llmll serve`) lets agents drive this through a tool interface rather than the CLI.

The lineage worth naming: this is what tool-use looks like when the tool is *the language semantics*, not a wrapper around shell commands. Compare to MCP — MCP gives an agent structured handles to operate on the world; hole/checkout/patch gives it structured handles to operate on the *program*. The shapes rhyme.

What this doesn't replace: most code isn't LLMLL, and the typed-edit story doesn't help when your language doesn't emit structured obligations. But the design suggests a research direction — what would a typed edit primitive for TypeScript look like? `tsc --build`'s incremental mode already has the machinery; what's missing is the obligation surface and the patch protocol. An MCP server that exposed `tsc-checkout` / `tsc-patch` against a project's AST would be a non-trivial but tractable thing to build.

A walkthrough of the full loop on a small `withdraw` function — including a deliberate contract violation that gets rejected at the patch boundary, then the correct attempt that verifies — is in the next section. The end-to-end multi-agent version is at [docs/orchestrator-walkthrough.md](https://github.com/machunter/llmll/blob/main/docs/orchestrator-walkthrough.md). Two frozen benchmarks ([ERC-20](https://github.com/machunter/llmll/tree/main/examples/erc20_token), [TOTP RFC 6238](https://github.com/machunter/llmll/tree/main/examples/totp_rfc6238)) show the lifecycle on real specs.

LLMLL is GPLv3, solo project. Repo: [github.com/machunter/llmll](https://github.com/machunter/llmll). Feedback on the typed-edit framing especially welcome — particularly from anyone working on MCP servers for code, structured tool outputs, or harness-level edit primitives.

---

## Walkthrough: filling a hole through checkout/patch

This is a one-task tour of LLMLL's typed editing loop: start with a function whose body is a `?hole`, watch a wrong attempt get rejected at the patch boundary, then watch the right attempt verify. Five commands end-to-end.

### The starting state

`withdraw.llmll`:

```lisp
(type PositiveInt (where [x: int] (> x 0)))

(def-logic withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  ?body_impl)
```

The function has a precondition, a postcondition, and an unimplemented body. Type checking succeeds (a hole is well-typed), but the program cannot run.

### 1. Discover the open holes

```bash
$ llmll holes withdraw.llmll --json
{
  "holes": [
    { "name": "body_impl",
      "pointer": "/statements/1/body",
      "kind": "hole-named",
      "type": "int" }
  ]
}
```

The compiler reports one open hole, named `body_impl`, located at the `withdraw` body, expected type `int`. The agent doesn't have to grep for `?` markers — the compiler hands it the list.

### 2. Convert to JSON-AST and check out the hole

`checkout` requires JSON-AST input — the lock targets a JSON Pointer.

```bash
$ llmll build withdraw.llmll --emit json-ast -o withdraw.ast.json
$ llmll checkout withdraw.ast.json /statements/1/body
```

The response is a structured token plus the *local typing context* the agent needs to fill the hole:

```json
{
  "token": "a1b2c3d4e5f6...",
  "ttl_seconds": 3600,
  "expected_return_type": "int",
  "in_scope": [
    { "name": "balance", "type": "int",         "source": "param" },
    { "name": "amount",  "type": "PositiveInt", "source": "param" }
  ],
  "available_functions": [
    { "name": "+", "params": [["a","int"],["b","int"]], "returns": "int", "status": "builtin" },
    { "name": "-", "params": [["a","int"],["b","int"]], "returns": "int", "status": "builtin" }
  ],
  "type_definitions": [
    { "name": "PositiveInt", "kind": "alias", "base": "int", "predicate": "(> x 0)" }
  ]
}
```

The agent now knows: it must return an `int`; it has `balance: int` and `amount: PositiveInt` in scope; arithmetic builtins are available; `PositiveInt` is `int` with the predicate `x > 0`. No prose, no inference from surrounding code.

### 3. Wrong attempt — gets rejected at the patch boundary

Suppose the agent (incorrectly) proposes `(+ balance amount)`. It submits a JSON-Patch:

```json
{
  "token": "a1b2c3d4e5f6...",
  "patch": [
    { "op": "test",
      "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace",
      "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "+",
                 "args": [ {"kind":"var","name":"balance"},
                           {"kind":"var","name":"amount"} ] } }
  ]
}
```

```bash
$ llmll patch withdraw.ast.json patch.json
```

Type checking passes — both arguments are `int`, the result is `int`, the expected type matches. But the compiler also re-runs verification because the function carries a contract:

```
✗ withdraw.ast.json — UNSAFE (liquid-fixpoint)

  Constraint failed: postcondition of `withdraw`
    pointer:    patch-op/1/value
    contract:   (= result (- balance amount))
    body:       (+ balance amount)
    counterexample:  balance = 0, amount = 1
                     ⇒ result = 1, but expected (- balance amount) = -1

  Patch rejected. File unchanged. Lock retained.
```

Two things to notice. The diagnostic points at `patch-op/1/value` — the patch operation that broke things — not at a line in the file. And the lock is *retained*, so the agent can retry without re-checking out. The file on disk is unchanged.

### 4. Correct attempt — verifies and commits

The agent revises to `(- balance amount)` and re-submits:

```json
{
  "token": "a1b2c3d4e5f6...",
  "patch": [
    { "op": "test",    "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace", "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "-",
                 "args": [ {"kind":"var","name":"balance"},
                           {"kind":"var","name":"amount"} ] } }
  ]
}
```

```bash
$ llmll patch withdraw.ast.json patch.json
✓ withdraw.ast.json — SAFE (liquid-fixpoint)
  Patched /statements/1/body. Lock cleared.
```

Re-verification succeeded; the lock is released; the file is updated.

### 5. Confirm with the trust report

```bash
$ llmll verify withdraw.ast.json --trust-report
# Trust Report
# ──────────────────────────────────────────
#   withdraw:
#     pre:  verified (liquid-fixpoint)  body-faithful: ✓
#     post: verified (liquid-fixpoint)  body-faithful: ✓
# ──────────────────────────────────────────
#   1 function, 0 epistemic drift warnings.
```

`body-faithful: ✓` means the verifier didn't fall back to contract-only — it encoded the actual body as a verification condition and proved the contract from it. This is the strongest evidence level the system produces.

### What this loop gave you

- **Concurrent editing without conflicts.** A second agent could have checked out a different hole in the same file simultaneously. Patches are scope-contained to the locked subtree.
- **Structural validation before commit.** No "tests fail later." A patch that breaks types or contracts never reaches the file.
- **Local typing context as data.** The agent never had to read surrounding code to know what was in scope; the checkout response carried it as a JSON object.
- **Diagnostics that point at the *patch operation*, not the file.** Errors are addressed to the agent that caused them, in the form the agent submitted.

The same loop scales to a `def-interface` skeleton with N specialist agents filling N holes in parallel — see [docs/orchestrator-walkthrough.md](https://github.com/machunter/llmll/blob/main/docs/orchestrator-walkthrough.md) for that version. The shape doesn't change; only the number of locks held simultaneously.

---

> **Note on JSON shapes.** The CLI outputs in the walkthrough are derived from `compiler/src/LLMLL/Checkout.hs:164-189` and the spec; exact serialization (key ordering, optional fields, full builtin list) may differ in details. Run the commands once and snapshot real output before publishing to an external audience.

> **Source.** This bundle lives in `docs/outreach/` alongside `post-coordination-protocol.md`, `post-typed-editing.md`, and `walkthrough-checkout-patch.md` — the same content split into individual files for easier copy-paste into separate posting channels.
