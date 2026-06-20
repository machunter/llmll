# Holes, Locks, Patches & Verification

A walkthrough of the LLMLL repair loop — for developers who want to see what "AI writes the code, the compiler proves it" actually looks like at the command line.

## What LLMLL is, in one paragraph

LLMLL is a programming language built for AI agents to author code *collaboratively and verifiably*. Every function carries a **contract** — a precondition and a postcondition — and unfinished spots in the body are explicit **typed holes**. An agent doesn't just paste text into a file: it **checks out** a hole (taking a lock), submits a **patch**, and that patch is rejected unless it (1) type-checks and (2) is **proven** by an SMT solver to satisfy the contract. The result is a program where you can ask, per function, *"is this actually correct, or are we taking someone's word for it?"* — and get a machine-checked answer.

This post walks the whole loop on a tiny three-function program: surveying holes, reserving them for a swarm of agents, patches that fail (first on types, then on logic), patches that succeed, the compare-and-swap concurrency model, and the final trust report.

A note on formats: LLMLL source comes in two shapes — a human-readable **s-expression** form, and a machine-processable (and mildly human-readable) **JSON-AST**. We'll read the program in s-expression form; the checkout/patch protocol operates on the JSON-AST.

> **Versions.** `llmll 0.12.1`, JSON-AST schema `0.6.0`. The schema version is stamped into the program itself — `demo.ast.json` opens with `"schemaVersion": "0.6.0"` — so any downstream tool or agent can refuse an input it doesn't understand instead of misreading it.

## The program we're building

```lisp
;; Three functions, three points the demo makes:
;;   withdraw — a contract whose post restates the body; the legible on-ramp (sign-error catch).
;;   double   — proven, no precondition: a "fully closed" companion that earns top-tier `verified`.
;;   maxi     — a post that is a complete *property* (result is ≥ both inputs and is one of them),
;;              not a copy of the body: the evidential case. A plausible wrong fill (returns the
;;              min) type-checks and passes most tests, but the verifier refutes it for all inputs
;;              and localizes the defect to each branch.

(type PositiveInt (where [x: int] (> x 0)))

(def withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  ?body_impl)

(def double [x: int]
  (post (= result (+ x x)))
  (+ x x))

(def maxi [a: int b: int]
  (post (and (and (>= result a) (>= result b))
             (or (= result a) (= result b))))
  ?maxi_body)
```

`?body_impl` and `?maxi_body` are the holes — `double` is already filled. The equivalent JSON-AST is too unwieldy for the page, but it's what every command below actually reads (`llmll build ./demo.llmll --emit -o .` generates it).

## Warming up: where are the holes?

```bash
llmll holes ./demo.ast.json --deps --json 2>/dev/null | jq .
```

```json
[
  {
    "agent": null,
    "cycle_warning": false,
    "depends_on": [],
    "inferred-type": null,
    "kind": "named",
    "message": "hole: ?body_impl",
    "module-path": "def withdraw",
    "pointer": "/statements/1/body",
    "status": "non-blocking"
  },
  {
    "agent": null,
    "cycle_warning": false,
    "depends_on": [],
    "inferred-type": null,
    "kind": "named",
    "message": "hole: ?maxi_body",
    "module-path": "def maxi",
    "pointer": "/statements/3/body",
    "status": "non-blocking"
  }
]
```

There are a few fields here, but the one that matters for the rest of the demo is the **`pointer`**: an RFC 6901 JSON Pointer to the exact node in the syntax tree that needs filling. That's the address an agent checks out and patches.

## What does the hole demand? The obligation report

`holes` tells you *where* the work is. To learn *what* to build, ask for the obligation report — `verify --obligation-report`. For each hole it emits a **three-channel brief**: the bindings in scope and their types (type channel), the precondition the body may assume and the postcondition it must prove (contract channel), and what it's allowed to lean on (trust channel). Let's project `withdraw`'s down to the essentials:

```bash
llmll verify ./demo.ast.json --obligation-report --json 2>/dev/null \
  | jq '.obligations[] | select(.origin=="/statements/1/body")
        | {function,
           in_scope: [.type_channel.in_scope[] | {name, type}],
           assume:   .contract_channel.preconditions,
           prove:    .contract_channel.postcondition_goal}'
```

```json
{
  "function": "withdraw",
  "in_scope": [
    { "name": "balance", "type": "int" },
    { "name": "amount", "type": "PositiveInt" }
  ],
  "assume": [ "(>= balance amount)" ],
  "prove": "(= result (- balance amount))"
}
```

That's the whole job, machine-readable: fill `withdraw`'s body with an expression over `balance` and `amount` that — *assuming* `balance ≥ amount` — *proves* `result = balance − amount`. An agent never has to guess the spec; it's handed the in-scope vocabulary, the assumption, and the goal. (The full report also lists the callable `available_functions` and, once a fill fails, concrete repair `suggestions`.)

`verify --obligation-report` is the **whole-program** view (every hole, unproven contract, and call-site failure at once) — what you reach for when surveying the program rather than working a single hole. *Where* and *what* (holes + obligation) come first; *who's working on it* (the lock) comes when an agent commits to a hole.

## Getting the locks

Picture a swarm of agents told to fill these holes. The first thing each one does is grab a token-lock — essentially *"I'm working on this node."* You call `llmll checkout` with the pointer; it hands back a token. Capture the **full** response, not just the token — it carries the hole's brief inline, so one call gives both the lock and the spec. Let's take both holes now:

```bash
CO_W=$(llmll checkout ./demo.ast.json /statements/1/body --json)
CO_M=$(llmll checkout ./demo.ast.json /statements/3/body --json)
TOKEN_W=$(jq -r '.token' <<<"$CO_W"); TOKEN_M=$(jq -r '.token' <<<"$CO_M")
```

**The spec rode in with the lock.** Project agent A's response — it's the same three-channel contract the obligation report gave us, scoped to the one hole A reserved:

```bash
jq '{contract_pre, postcondition_goal,
     in_scope: [.in_scope[] | {name, type}], type_definitions}' <<<"$CO_W"
```

```json
{
  "contract_pre": "(>= balance amount)",
  "postcondition_goal": "(= result (- balance amount))",
  "in_scope": [
    { "name": "PositiveInt", "type": "PositiveInt" },
    { "name": "amount", "type": "PositiveInt" },
    { "name": "balance", "type": "int" },
    { "name": "double", "type": "fn[1 args] -> ?" },
    { "name": "maxi", "type": "fn[2 args] -> ?" },
    { "name": "withdraw", "type": "fn[2 args] -> ?" }
  ],
  "type_definitions": [
    { "base_type": "int", "kind": "dependent", "name": "PositiveInt" }
  ]
}
```

`contract_pre` and `postcondition_goal` are exactly the assume/prove pair from the obligation report. The checkout `in_scope` is *wider*, though: the report projected to the contract's free variables (`balance`, `amount`), while checkout returns the full scope — the `PositiveInt` alias and the sibling top-level functions (`double`, `maxi`, `withdraw`, each `"source": "let-binding"`) as the agent's callable vocabulary. (`expected_return_type` and `available_functions` are reserved for a later OBLIG pass and omitted for now.)

This same call also creates a lock file, `demo.llmll-lock.json`. Peeking under the hood:

```json
{
  "file": "./demo.ast.json",
  "tokens": [
    {
      "hole_kind": "hole-named",
      "pointer": "/statements/1/body",
      "source_hash": "0dcfc362556b3ef2df2c473ff7cea09bb380639d302937341a611e1ac927f7e0",
      "timestamp": "2026-06-09T04:46:15.085855Z",
      "token": "45bdeb1cbc02be044fc58519a9b5fe8d68c604bdbcc823cd57b98a5ce273149b",
      "ttl": 3600,
      "verified_hash": null
    },
    {
      "hole_kind": "hole-named",
      "pointer": "/statements/3/body",
      "source_hash": "0dcfc362556b3ef2df2c473ff7cea09bb380639d302937341a611e1ac927f7e0",
      "timestamp": "2026-06-09T04:46:21.980753Z",
      "token": "6f7d03dd0543e156050f57063deeb6553a0c6bbc102d90283a2afb0409be6edc",
      "ttl": 3600,
      "verified_hash": null
    }
  ]
}
```

(Trimmed to the lock-bookkeeping fields — each entry also carries the full per-hole brief shown above: `in_scope`, `contract_pre`, `postcondition_goal`, `type_definitions`, plus `assumptions` / `path_condition` as `null` where the hole has none.) One lock file holds an **array** of reservations: two agents, two holes, one program. The fields that do the work are `pointer`, `source_hash`, `ttl`, and the `token` we carry across operations.

<details><summary>The complete <code>CO_W</code> response (<code>jq . &lt;&lt;&lt;"$CO_W"</code>) — brief and lock bookkeeping in one object</summary>

```json
{
  "assumptions": null,
  "contract_pre": "(>= balance amount)",
  "hole_kind": "hole-named",
  "in_scope": [
    { "name": "PositiveInt", "source": "let-binding", "type": "PositiveInt" },
    { "name": "amount", "source": "param", "type": "PositiveInt" },
    { "name": "balance", "source": "param", "type": "int" },
    { "name": "double", "source": "let-binding", "type": "fn[1 args] -> ?" },
    { "name": "maxi", "source": "let-binding", "type": "fn[2 args] -> ?" },
    { "name": "withdraw", "source": "let-binding", "type": "fn[2 args] -> ?" }
  ],
  "obligation_id": null,
  "path_condition": null,
  "pointer": "/statements/1/body",
  "postcondition_goal": "(= result (- balance amount))",
  "source_hash": "0dcfc362556b3ef2df2c473ff7cea09bb380639d302937341a611e1ac927f7e0",
  "timestamp": "2026-06-11T06:47:22.69762Z",
  "token": "6087457baa8d6adf1c694e934b3e7c0b4a7041d6b3a685b46b1792d15c785e51",
  "ttl": 3600,
  "type_definitions": [
    { "base_type": "int", "kind": "dependent", "name": "PositiveInt" }
  ],
  "verified_hash": null
}
```

</details>

### The concurrency model: compare-and-swap, not a mutex

This is the part worth slowing down on. Each token witnesses `(hole pointer + the file's content hash at checkout)`. A reservation lets you *attempt* a patch — it does **not** freeze the file. The first patch to land changes the file's hash, which:

1. auto-releases that hole's lock, and
2. makes every *other* outstanding token **stale** — its witnessed hash no longer matches.

A stale token's patch is rejected (`PatchAuthError`); the holder must release and re-checkout against the new state before committing. That's how the swarm avoids lost updates: an agent always re-reads the latest program before its write lands. We'll watch this happen with `maxi` later.

### Taking the pulse

Before we touch anything, three commands we'll reuse after every step to confirm the system did exactly what it claimed. None are LLMLL-specific.

**(1)** Did the program change?

```bash
shasum -a256 demo.ast.json | cut -c1-12      # → 0dcfc362556b
```

**(2)** Which holes are reserved right now?

```bash
jq -r '.tokens[].pointer' demo.llmll-lock.json
# /statements/1/body
# /statements/3/body
```

**(3)** How many live locks? (Should match the count from (2).)

```bash
jq '.tokens | length' demo.llmll-lock.json    # → 2
```

## Failure #1: the trivial one (types)

We'll start with the least interesting failure: code that doesn't even type-check. Here's `patch-type.json`, which fills `withdraw`'s body by adding a string to an int:

**Installs (S-expression):** `(+ balance "oops")`

```json
{
  "token": "45bdeb1cbc02be044fc58519a9b5fe8d68c604bdbcc823cd57b98a5ce273149b",
  "patch": [
    { "op": "test",    "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace", "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "+", "args": [
        { "kind": "var", "name": "balance" },
        { "kind": "lit-string", "value": "oops" } ] } }
  ]
}
```

Note the payload carries the lock token and the pointer to the node. The `test` op asserts the slot currently holds the `?body_impl` hole — the patch is refused if someone got there first. Let's apply it:

```bash
llmll patch ./demo.ast.json ./patch-type.json | jq '{result, message: .diagnostics[0].message}'
```

```json
{
  "result": "PatchTypeError",
  "message": "type mismatch in '+': expected int, got string"
}
```

**Pulse check** — `shasum` → `0dcfc362556b` (unchanged), `jq '.tokens | length'` → `2`. The rejected patch left the program byte-for-byte intact and consumed no reservation. The gate fails closed.

## Failure #2: the interesting one (logic)

Now a fill that *does* type-check: `(+ balance amount)`. It's `int + int → int`, so the type checker is happy — but it violates the postcondition (`result = balance − amount`) for every valid input. This is exactly the class of bug that ships: locally plausible, globally wrong, invisible to types and to most tests.

**Installs (S-expression):** `(+ balance amount)`

```json
{
  "token": "45bdeb1cbc02be044fc58519a9b5fe8d68c604bdbcc823cd57b98a5ce273149b",
  "patch": [
    { "op": "test",    "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace", "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "+", "args": [
        { "kind": "var", "name": "balance" },
        { "kind": "var", "name": "amount" } ] } }
  ]
}
```

```bash
llmll patch ./demo.ast.json ./patch-wrong.json | jq '{result, message: .diagnostics[0].message}'
```

```json
{
  "result": "PatchVerifyError",
  "message": "body verification of 'withdraw' failed — implementation does not satisfy postcondition (constraint #0)"
}
```

A different result code — `PatchVerifyError`, not `PatchTypeError`. The patch was type-checked *and* handed to the solver, which disproved it. Every other tool would have merged this.

**Pulse check** — `shasum` → `0dcfc362556b` (unchanged), locks still `2`. Nothing committed.

## Success: the repair

The repair subtracts instead of adds:

**Installs (S-expression):** `(- balance amount)`

```json
{
  "token": "45bdeb1cbc02be044fc58519a9b5fe8d68c604bdbcc823cd57b98a5ce273149b",
  "patch": [
    { "op": "test",    "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace", "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "-", "args": [
        { "kind": "var", "name": "balance" },
        { "kind": "var", "name": "amount" } ] } }
  ]
}
```

```bash
llmll patch ./demo.ast.json ./patch-correct.json | jq .
```

```json
{
  "result": "PatchSuccess",
  "statements": 4
}
```

**Pulse check** — now things move:

```bash
shasum -a256 demo.ast.json | cut -c1-12      # → dd454597e6b0   (NEW — the body changed)
jq -r '.tokens[].pointer' demo.llmll-lock.json # /statements/3/body  (withdraw's lock auto-released)
```

One hole left to fill — and notice agent A's reservation is gone, consumed by the successful patch. Which means agent B's `TOKEN_M`, witnessed against the *old* hash, is now stale. That's our next scene.

## maxi: resync the stale reservation, then the evidential bug

This step does double duty: it shows the compare-and-swap resync the concurrency model promised, *and* it's the "isn't this a toy?" beat — `maxi`'s contract is a real **property**, and a type-passing wrong body still gets caught.

### Stale Token; resync

Agent B naively reuses the token it grabbed at the start:

**Installs (S-expression):** `a` — the content is irrelevant here; we're only probing the stale lock.

```json
{
  "token": "6f7d03dd0543e156050f57063deeb6553a0c6bbc102d90283a2afb0409be6edc",
  "patch": [
    { "op": "test",    "path": "/statements/3/body",
      "value": { "kind": "hole-named", "name": "maxi_body" } },
    { "op": "replace", "path": "/statements/3/body",
      "value": { "kind": "var", "name": "a" } }
  ]
}
```

```bash
llmll patch ./demo.ast.json ./pm0.json | jq .
```

```json
{
  "message": "obligation context is stale — re-checkout required (source file changed)",
  "result": "PatchAuthError"
}
```

The file's hash changed when `withdraw` was filled, so the token no longer matches. This isn't a bug — it's the system refusing a lost update. Release the stale lock and check out fresh:

```bash
llmll checkout ./demo.ast.json --release "$TOKEN_M" | jq . # { "released": true }
TOKEN_M=$(llmll checkout ./demo.ast.json /statements/3/body --json | jq -r '.token')
```

Now we hold a token that witnesses the *current* program.

### The type-passing bug (returns the min)

A one-character slip — the branches are swapped. It type-checks, and any test where `a = b` passes:

**Installs (S-expression):** `(if (> a b) b a)`

```json
{
  "token": "35ff645fbe6f4a18673a26801be7aff7246c0d44ca04f2f94112760e52314449",
  "patch": [
    { "op": "test",    "path": "/statements/3/body",
      "value": { "kind": "hole-named", "name": "maxi_body" } },
    { "op": "replace", "path": "/statements/3/body",
      "value": { "kind": "if",
        "cond": { "kind": "op", "op": ">", "args": [
          { "kind": "var", "name": "a" }, { "kind": "var", "name": "b" } ] },
        "then_branch": { "kind": "var", "name": "b" },
        "else_branch": { "kind": "var", "name": "a" } } }
  ]
}
```

```bash
llmll patch ./demo.ast.json ./patch-maxi-bad.json | jq '{result, branches: [.diagnostics[].message]}'
```

```json
{
  "result": "PatchVerifyError",
  "branches": [
    "body verification of 'maxi' failed (then-branch does not satisfy postcondition) (constraint #2)",
    "body verification of 'maxi' failed (else-branch does not satisfy postcondition) (constraint #3)"
  ]
}
```

The solver doesn't just say "wrong" — it refutes **each branch** and names it. This is the payoff of a property-shaped contract: `maxi`'s spec says nothing about *how* to compute the max, only that the result must be ≥ both inputs and equal to one of them. Many bodies satisfy types; only the right one satisfies the property.

**Pulse check** — `shasum` → `dd454597e6b0` (unchanged), locks still `1`.

### The repair

The fix is one swap — `then`/`else` exchanged. Same patch shape:

**Installs (S-expression):** `(if (> a b) a b)`

```bash
llmll patch ./demo.ast.json ./patch-maxi-correct.json | jq .
```

```json
{
  "result": "PatchSuccess",
  "statements": 4
}
```

**Pulse check** — the program changed again and the swarm has dispersed:

```bash
shasum -a256 demo.ast.json | cut -c1-12      # → 270351f1118b
jq '.tokens | length' demo.llmll-lock.json    # → 0   (no holes reserved)
```

## Verify the trust closure

Both holes are filled and every patch was proven on the way in — so what does the finished program's trust report say?

`verify --trust-report --json` emits two JSON documents on stdout (the verify result, then the report), so `jq -s '.[1]'` slurps both and selects the report. We project the fields that matter:

```bash
llmll verify ./demo.ast.json --strict-verified-core --trust-report --json 2>/dev/null \
  | jq -s '.[1] | {summary,
                   functions: [.entries[] | {name, post: .post_level, effective: .effective_level,
                                             requires: (.caller_obligations // [] | map(.requires))}]}'
```

```json
{
  "summary": {
    "asserted": 0, "contract_checked": 0, "drifts": 0,
    "no_contract": 0, "tested": 0, "verified": 3
  },
  "functions": [
    { "name": "withdraw", "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)", "requires": ["(>= balance amount)"] },
    { "name": "double",   "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)", "requires": [] },
    { "name": "maxi",     "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)", "requires": [] }
  ]
}
```

The report carries **two orthogonal axes**:

- **The trust axis (`effective`)** — all three are `verified`, `withdraw` included. It proved its Hoare triple `{balance ≥ amount} body {result = balance − amount}`, so it is verified; a function whose body the solver *couldn't* prove would read `asserted` here instead.
- **The obligation axis (`requires`)** — `withdraw` carries a visible caller-obligation, `balance ≥ amount`: the part a *caller* must establish, surfaced explicitly rather than folded into the tier. `double` and `maxi` carry none.

*Is it correct?* and *what must a caller guarantee?* are two questions, answered on two axes — neither collapsed into the other. (Deliberately so: an earlier version of this report *floored* `withdraw` to `asserted` for merely having a precondition, conflating its verification status with its caller's obligation. That was a category error; the precondition now lives on its own axis — see [`precondition-tier-proposal.md`](../../docs/design/precondition-tier-proposal.md).)

## Composition: the obligation flows down

The obligation axis is not a label — it is **enforced** when something *composes* with `withdraw`. [`compose.llmll`](./compose.llmll) adds a `guarded-withdraw` that calls it:

```lisp
(def-shell guarded-withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  (withdraw balance amount))
```

It *discharges* `withdraw`'s precondition (its own `pre` guarantees `balance ≥ amount` at the call site) and proves its post by leaning on `withdraw`'s — so it reaches `verified` too. And when an agent checks out a hole in a composer, the brief hands back what it may *assume* without re-proving — `consumed_guarantees: [{ "callee": "withdraw", "guarantee": "(= result (- balance amount))", "status": "discharged" }]`. Trust flows **up** from the callee.

Drop the precondition ([`compose-bad.llmll`](./compose-bad.llmll)) and the verifier refuses the code:
```
error: call-site precondition of 'withdraw' not satisfied in 'guarded-withdraw' — caller does not prove callee's precondition
```

One fact, **three views**: the report surfaces the obligation (`caller_obligations`), the verifier enforces it (the call-site VC), and the patch protocol rejects violations (`callee-precondition-unmet`). That — verified *and* what a caller owes, with the obligation enforced on composition — is the thing LLMLL gives you that a green CI check doesn't.

## The authority axis: what can it touch?

The trust report answers *"is it correct?"*. A second, orthogonal question is *"what is it even allowed to touch?"* — the object-capability **authority** a function may exercise. `verify --obligation-report` answers it with a per-function `effect_summary`.

Our three core functions are pure, so their authority is uniformly empty (`∅`) — true, but it doesn't show the machinery doing anything. So [`audit.llmll`](./audit.llmll) is a thin **shell** over the core: it imports the verified `withdraw` and adds the one thing the core deliberately does *not* do — an audit line to `stdout`.

```bash
llmll verify ./audit.ast.json --obligation-report --json 2>/dev/null \
  | jq '{cross_module, effect_summary}'
```

```json
{
  "cross_module": "supported",
  "effect_summary": [
    { "effects": ["stdout"], "function": "audit-withdraw" }
  ]
}
```

Two readings:

- **`effect_summary`** — `audit-withdraw` exercises exactly `["stdout"]`, nothing more. The `withdraw` it imports contributes `∅` to the union; the authority is the shell's, named and minimal. A function that reached a delegate hole, opaque FFI, or an unresolved import would read `"unbounded"` instead — the analysis over-approximates, so it never *under*-reports what code can touch.
- **`cross_module: "supported"`** — the summary composed *across* the `(import demo)` edge: the core module resolved and was walked in full, so its `∅` contribution is sound rather than assumed. An import the analysis couldn't follow would force `"unbounded"`.

Authority is orthogonal to trust: a `verified` function can still reach every capability, and this `asserted` shell reaches exactly one. *Is it correct?* and *what can it touch?* are two questions, and LLMLL answers them separately instead of folding one into the other.

## (Optional) Discriminative power

One more axis, for the curious. `--cdp` measures how *tight* a contract is — what fraction of candidate bodies satisfy it. A loose contract that anything satisfies isn't pinning down much.

Heads-up: this is the one human-readable-only step. `--cdp` does **not** populate the JSON report (under `--json` the per-function `discriminative_axis` stays `"basis": "not-measured"`, `"score": null`), so the scores live only in the text output:

```bash
llmll verify ./demo.ast.json --strict-verified-core --trust-report --cdp
```

```text
   CDP measured 3 function(s):
   double: score=1.000 (1/6 candidates satisfy) [const-satisfies-post]
   maxi: score=1.000 (1/7 candidates satisfy) [const-satisfies-post]
   withdraw: score=0.644 (2/7 candidates satisfy) [identity-satisfies-post, const-satisfies-post]
Trust Report
────────────────────────────────────────────────────────────
  double:    pre:  —        |  post: verified (liquid-fixpoint)
  maxi:      pre:  —        |  post: verified (liquid-fixpoint)
  withdraw:  pre:  asserted  |  post: verified (liquid-fixpoint)
────────────────────────────────────────────────────────────
Summary:
  verified:         3
  contract-checked: 0
  tested:           0
  asserted:         0
  no contract:      0
```

The **score** is the measure (`maxi` and `double` are maximal at `1.000`; `withdraw`'s exact-value contract scores `0.644`). The bracketed advisories are sampling hints that show up broadly — read the score, not the flags.

## Wrapping up

In one tiny program we walked the entire LLMLL loop a developer actually cares about:

- **Holes + pointers** — work is addressable down to a single AST node.
- **The spec rides in with the lock** — `checkout` returns the hole's full per-hole brief inline: the contract `pre`/`post` to prove, the in-scope vocabulary, and the relevant type definitions. An agent reserves a hole *and* receives what to build in one call, no separate obligation query — the same three-channel contract `verify --obligation-report` emits program-wide, scoped to the one hole you hold.
- **Checkout/patch with locks** — multiple agents reserve and edit one program, with a compare-and-swap model that refuses lost updates instead of silently clobbering.
- **A gate that fails closed on two channels** — type errors (`PatchTypeError`) and contract violations (`PatchVerifyError`) are both rejected *before* anything lands, with the offending branch named.
- **A trust report with two axes** — the *trust* axis (`verified`: did the body prove its spec?) and the *obligation* axis (`caller_obligations`: what a caller must guarantee to call it), kept separate rather than collapsed into one floored number.
- **Composition that enforces obligations** — a function that calls a verified one reaches `verified` only by discharging its precondition at the call site (leaning on its discharged post via `consumed_guarantees`); drop the guarantee and the verifier refuses the code. The report's obligation, the verifier's VC, and the protocol's rejection are one fact, three views.
- **An authority axis orthogonal to trust** — `effect_summary` reports the object-capabilities each function may reach, composing across module imports, so *"is it correct?"* and *"what can it touch?"* stay separate questions.

The full, copy-pasteable command script for this walkthrough lives in [`DEMO-RUNBOOK.md`](./DEMO-RUNBOOK.md), and the program itself in [`demo.llmll`](./demo.llmll).

## Future work

This demo stayed small on purpose — a few small functions and plain integer math. A handful of things a richer demo would want aren't filled in yet. The good news for whoever writes that next demo: the `checkout` response already has slots for all of them; they just come back empty today. Nothing here has to change to use them — they'll simply start carrying more once they're wired up.

- **Tell the agent the return type, not just the inputs.** Today `checkout` hands back the bindings in scope and the contract to satisfy, but the `expected_return_type` field is empty — the agent works out the return type from the contract. When a hole returns something less obvious than an `int` — a `Result`, a record, a list of something — stating the expected type up front saves a guess. A future demo could pick a hole where that actually bites and show the type arriving with the lock.

- **Hand over the callable functions, with their signatures.** Right now the agent sees sibling function *names* in `in_scope` (`double`, `maxi`, `withdraw`), but not a structured list of what they take and return — the `available_functions` field is still empty. The moment a demo is about *composition* — where the right fill is "call this helper and adapt its result" rather than a one-line formula — you want that menu handed over directly, argument and return types included, instead of making the agent read them off the source. That's the natural next demo: real functions calling each other, not just arithmetic.

- **Show what the body is allowed to lean on.** The precondition tells the body what's guaranteed on the way in. A fuller picture also spells out what the body may *trust* — for instance, a helper that's already been verified, so the agent doesn't re-prove it. That `assumptions` channel is reserved but empty here. A demo spanning a verified helper and the code that calls it could make that hand-off visible.

- **Carry the locking story across files.** The authority axis already crosses a module boundary — `audit.llmll` imports the core and `effect_summary` composes across the edge (`cross_module: "supported"`). The *checkout/patch* protocol hasn't caught up: `checkout` knows only the hole's own file, so following a hole's context across a module boundary is the missing piece. The compare-and-swap locking works the same regardless of file count — it just needs scope information that crosses files for a swarm editing *across* modules.

The throughline: this walkthrough proved the loop on a toy. The deferred pieces are exactly what you'd reach for to run the same loop on something that looks like a real project — more types, more functions calling each other, more files, more agents working at once.
