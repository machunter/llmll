# LLMLL Repair-Loop Demo — Capture Runbook

> **Artifact:** "From a bad agent patch to verified trust closure."
> **Fixture:** [`demo.ast.json`](demo.ast.json) — `PositiveInt`, `withdraw` (typed hole), `double` (pre-verified), `maxi` (typed hole). The JSON-AST is what the agent checkout/patch protocol operates on; [`demo.llmll`](demo.llmll) is the human-readable source it is generated from (`llmll build ./demo.llmll --emit -o .`). [`audit.llmll`](audit.llmll) / [`audit.ast.json`](audit.ast.json) is a thin **shell** module over the core, used only by the authority-axis step (7).
> **Verified against:** `llmll 0.13.1`, real `liquid-fixpoint` on PATH, `jq` on PATH. The two-axis trust closure (§6) and the composition step (§6.5) require v0.13.0 (TRUST-PRE's `caller_obligations` axis + DEMO-COMP); the step-2 checkout brief's `expected_return_type` requires v0.13.1 (DEF-RET — `withdraw`/`double`/`maxi` declare `-> int`). The step-2 brief was re-captured on `0.13.1` (2026-06-21); the other steps carry their prior `0.13.0` / v0.12.x captures (a full byte-for-byte re-capture across DEMO-COMP + DEF-RET is pending).

This is the canonical capture script for the public repair-loop demo. It supersedes the older single-function `withdraw.ast.json` flow, which could only ever show `verified: 0` in the summary (sound but visually self-undercutting — see [Why these functions](#why-these-functions)).

---

## What the demo proves

LLMLL turns *"did the AI write correct code?"* from a judgment call into a machine-checkable verdict — and is honest about which part of that verdict is **proven** versus **assumed**. The three functions stage three distinct points:

- `withdraw` — a contract (`pre: balance ≥ amount`, `post: result = balance − amount`) with an empty body (`?body_impl`). The legible on-ramp: a sign-error fill is type-correct but contract-violating.
- `double` — proven, **no precondition**: a fully-closed function that earns top-tier `verified`.
- `maxi` — a postcondition that is a complete **property** (`result ≥ a` ∧ `result ≥ b` ∧ `result ∈ {a, b}`), *not* a copy of the body. A plausible wrong fill (returns the *min*) type-checks and passes most tests, but the verifier refutes it for all inputs and localizes the defect to each branch. This is the evidential case — verification doing work types and tests cannot.

The climax dashboard shows all three `verified` — `withdraw` included: it proved its job. But `withdraw` carries a **visible caller-obligation** (`balance ≥ amount`) on a second, orthogonal axis — what a *caller* must guarantee — surfaced explicitly rather than folded into the tier. *Is it correct?* and *what must a caller honor?* are answered separately, and step 6.5 shows that obligation **enforced** the moment something composes with `withdraw`. No other AI tool draws that distinction — that two-axis honesty *is* the product.

A fourth artifact, [`audit.llmll`](audit.llmll), adds a second, **orthogonal** reading the trust lattice does not give: *authority*. As of v0.12.0 (Bundle B0), `verify --obligation-report` reports a per-function `effect_summary` — the object-capability authority a function may exercise — answering *"what can it touch?"* alongside *"is it correct?"*. Step 7 surfaces it.

---

## Prerequisites

```bash
llmll --version          # must report 0.13.1 (DEF-RET expected_return_type; TRUST-PRE caller_obligations + DEMO-COMP consumed_guarantees from 0.13.0, on top of the v0.12.x features; see note below)
which fixpoint           # must resolve — refuted/verified verdicts require the real solver
which jq                 # used to build patches and project JSON output to the values that matter
```

> **Critical:** a binary older than `b914587` (2026-06-06) reports `success: true` on the bad fill and can never render `verified` — the very bugs this demo was blocked on. Step 2's inline checkout brief additionally requires the OBLIG-1 population that shipped in `0.11.2`; on `0.11.1` the same `checkout` call returns `contract_pre` / `postcondition_goal` / `in_scope` as `null`. Step 7's `effect_summary` / `cross_module` fields require `0.12.0` (Bundle B0) or later. **The two-axis trust closure (§6, `caller_obligations`) and the composition step (§6.5) require `0.13.0`** (TRUST-PRE + DEMO-COMP), and the step-2 brief's `expected_return_type` requires `0.13.1` (DEF-RET). If `llmll --version` is not ≥ `0.13.1`, run `cd compiler && stack install` first. (The `--version` number alone is not proof; confirm the brief fields are populated.)

Work from a scratch directory so every command is relative and `patch` can mutate files freely:

```bash
mkdir -p /tmp/llmll-demo
cp examples/withdraw-demo/demo.ast.json  /tmp/llmll-demo/
cp examples/withdraw-demo/audit.ast.json /tmp/llmll-demo/   # for the authority-axis step (7)
cd /tmp/llmll-demo
```

All commands below assume you are in `/tmp/llmll-demo` and use `./` paths.

### The agent protocol

The demo drives the JSON-AST coordination protocol — how a *swarm* of agents edits one program safely:

- `checkout` reserves a hole and returns a token.
- `patch` applies an RFC 6901-pointer JSON-Patch that is **type-checked and verified at submission, and rejected if it fails** — distinct `PatchTypeError` / `PatchVerifyError` / `PatchAuthError` result codes.

> **Gating note.** `llmll patch` returns exit `1` *and* a `result` field on rejection; exit `0` + `PatchSuccess` on success. `llmll verify` exits `1` on any refuted/unproven function, `0` when the run is fully SAFE. Gate scripts on `$?`; the JSON `result`/`success` fields carry the detail.

### The two inspection probes

The demo is didactic because after every step you *look at the files* and confirm the system did exactly what it claimed. Two probes, used throughout:

```bash
# (P1) Fingerprint the program — did a patch actually change it?
shasum -a256 demo.ast.json | cut -c1-12

# (P2) Read the lock file — who is holding which hole right now?
jq -r '.tokens[].pointer' demo.llmll-lock.json     # which holes are reserved
jq  '.tokens | length'    demo.llmll-lock.json      # how many live reservations
```

Each step ends with a **🔍 Check** using these.

---

## The steps

### 1 — Survey the holes (with dependency graph)

The `2>/dev/null` drops a benign stderr warning (`def body is entirely a single named hole … prefer targeted holes`) that fires because each body is a whole-body stub — exactly the demo's intent; the JSON report itself is on stdout and is unaffected:

```bash
llmll holes ./demo.ast.json --deps --json 2>/dev/null | jq .
```

Output — two fillable holes, one in `withdraw`, one in `maxi`; `double` is already complete. Each carries its `pointer` (the checkout target) and `depends_on` (empty here — no hole blocks another):

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

**What each hole demands — the obligation report.** `holes` tells you *where* to fill; `verify --obligation-report` tells you *what* to fill. It emits a three-channel brief per hole — the bindings in scope (type channel), the precondition the body may assume and the postcondition it must prove (contract channel), and what it's allowed to lean on (trust channel). Projecting `withdraw`'s:

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

That is the agent's contract: fill `/statements/1/body` with an expression over `balance` and `amount` that, *assuming* `balance ≥ amount`, *proves* `result = balance − amount`. The full object also carries the trust channel, the callable `available_functions`, and OBLIG-4 repair `suggestions`; `expected_type` reads `int` — `withdraw` declares `-> int` (DEF-RET, v0.13.1), so the body hole carries its type.

> `verify --obligation-report` is the **whole-program** view — every hole, unproven contract, call-site failure, and `refuted_fns` at once. As of `0.11.2`, `checkout` (next step) returns this *same per-hole brief inline* for the single hole you reserve, so an agent gets the spec and the lock in one call — you'll see it ride in with the token in step 2. Use the report when surveying the program; use the checkout brief when working one reserved hole.

### 2 — Reserve every hole up front (the swarm model)

A swarm divides labor: one agent takes `withdraw`, another takes `maxi`. Reserve **both** holes before touching either — this is the move that hints at parallel agents.

Capture the **full** response from each checkout, not just the token — as of `0.11.2` the response carries the hole's per-hole brief inline, so one call yields both the lock (the `token`, for patching) and the spec (for filling):

```bash
CO_W=$(llmll checkout ./demo.ast.json /statements/1/body --json)   # agent A
CO_M=$(llmll checkout ./demo.ast.json /statements/3/body --json)   # agent B
TOKEN_W=$(jq -r '.token' <<<"$CO_W")
TOKEN_M=$(jq -r '.token' <<<"$CO_M")
```

**The spec rode in with the lock.** Project agent A's response down to the brief — it is the *same* three-channel contract `verify --obligation-report` emitted above, scoped to the one hole A reserved:

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
    { "name": "double", "type": "fn[1 args] -> int" },
    { "name": "maxi", "type": "fn[2 args] -> int" },
    { "name": "withdraw", "type": "fn[2 args] -> int" }
  ],
  "type_definitions": [
    { "base_type": "int", "kind": "dependent", "name": "PositiveInt" }
  ]
}
```

`contract_pre` and `postcondition_goal` are exactly the assume/prove pair from step 1's report. The checkout `in_scope` is *wider*: where the report's `type_channel` projection listed only the contract's free variables (`balance`, `amount`), checkout hands the agent the full scope — the `PositiveInt` alias and the sibling top-level functions (`double`, `maxi`, `withdraw`, each `"source": "let-binding"`) as the callable vocabulary. `expected_return_type` now reads `"int"` — `withdraw` declares `-> int` (DEF-RET, v0.13.1), so the body hole carries its type; `available_functions` carries the contracted-user vocabulary (`double` / `maxi` / `withdraw` with `pre` / `post` / `tier` / `return_type`, DEMO-COMP). `assumptions`, `path_condition`, and `obligation_id` come back `null` for this hole.

<details><summary>Full <code>CO_W</code> response (<code>jq . &lt;&lt;&lt;"$CO_W"</code>) — token, ttl, and staleness hashes alongside the brief</summary>

```json
{
  "assumptions": null,
  "contract_pre": "(>= balance amount)",
  "hole_kind": "hole-named",
  "in_scope": [
    { "name": "PositiveInt", "source": "let-binding", "type": "PositiveInt" },
    { "name": "amount", "source": "param", "type": "PositiveInt" },
    { "name": "balance", "source": "param", "type": "int" },
    { "name": "double", "source": "let-binding", "type": "fn[1 args] -> int" },
    { "name": "maxi", "source": "let-binding", "type": "fn[2 args] -> int" },
    { "name": "withdraw", "source": "let-binding", "type": "fn[2 args] -> int" }
  ],
  "obligation_id": null,
  "path_condition": null,
  "pointer": "/statements/1/body",
  "postcondition_goal": "(= result (- balance amount))",
  "expected_return_type": "int",
  "source_hash": "e2edf9dd21e58339a16caf6d2c7fe48d9da3d71f6ac86adb8db283f3aa9784d4",
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

> **🔍 Check — two live reservations in one lock file.**
> ```bash
> jq -r '.tokens[].pointer' demo.llmll-lock.json
> ```
> ```
> /statements/1/body
> /statements/3/body
> ```
> `jq '.tokens | length' demo.llmll-lock.json` → `2`. The lock sidecar `demo.llmll-lock.json` holds an *array* of reservations — two agents, two holes, one program.

> **Concurrency model — this is compare-and-swap, not a mutex.** Each token witnesses `(hole pointer + the file's content hash at checkout)`. A reservation lets you *attempt* a patch; it does **not** freeze the file. The first patch to land changes the file's hash, which (a) auto-releases that hole's lock and (b) makes every *other* outstanding token **stale** — its content-hash no longer matches. A stale token's patch is rejected `PatchAuthError`, and the holder must release and re-checkout against the new state before committing. That is how the swarm avoids lost updates: agent B re-reads the latest program before its write lands. You will see this happen at step 5.

### 3 — The bad fills — caught on two channels

LLMLL rejects on **two distinct channels** before any bad code lands. A rejected patch must leave the program byte-for-byte unchanged — we check that each time.

#### 3a — type channel

The fill `(+ balance "oops")` is broken on its own terms (adding a string to an int).

```bash
# S-expression equivalent:   ?body_impl  →  (+ balance "oops")
jq -n --arg t "$TOKEN_W" '{token:$t, patch:[
  {op:"test",    path:"/statements/1/body", value:{kind:"hole-named",name:"body_impl"}},
  {op:"replace", path:"/statements/1/body", value:{kind:"app",fn:"+",args:[
     {kind:"var",name:"balance"},{kind:"lit-string",value:"oops"}]}}]}' > ./patch-type.json
llmll patch ./demo.ast.json ./patch-type.json | jq '{result, message: .diagnostics[0].message}'
```

```json
{
  "result": "PatchTypeError",
  "message": "type mismatch in '+': expected int, got string"
}
```

> **🔍 Check — rejection left the program untouched, locks intact.**
> ```bash
> shasum -a256 demo.ast.json | cut -c1-12     # same fingerprint as before the patch
> jq '.tokens | length' demo.llmll-lock.json  # still 2 — neither reservation consumed
> ```

*"The type channel catches the obvious. Every language does this."*

#### 3b — contract channel

The fill `(+ balance amount)` is **type-correct** (`int + int → int`) but violates the postcondition for every valid input.

```bash
# S-expression equivalent:   ?body_impl  →  (+ balance amount)
jq -n --arg t "$TOKEN_W" '{token:$t, patch:[
  {op:"test",    path:"/statements/1/body", value:{kind:"hole-named",name:"body_impl"}},
  {op:"replace", path:"/statements/1/body", value:{kind:"app",fn:"+",args:[
     {kind:"var",name:"balance"},{kind:"var",name:"amount"}]}}]}' > ./patch-wrong.json
llmll patch ./demo.ast.json ./patch-wrong.json | jq '{result, message: .diagnostics[0].message}'
```

```json
{
  "result": "PatchVerifyError",
  "message": "body verification of 'withdraw' failed — implementation does not satisfy postcondition (constraint #0)"
}
```

> **🔍 Check — still untouched.** `shasum` unchanged; `jq '.tokens | length'` still `2`. The gate **fails closed**: verified at submission, disproved by liquid-fixpoint, rejected — nothing committed.

*"This type-checks — every other tool would merge it. LLMLL proves it wrong anyway."*

### 4 — The repaired fill — accepted (and the lock auto-releases)

Correct body `(- balance amount)`, agent A's token still valid (the rejected patches never moved the file):

```bash
# S-expression equivalent:   ?body_impl  →  (- balance amount)
jq -n --arg t "$TOKEN_W" '{token:$t, patch:[
  {op:"test",    path:"/statements/1/body", value:{kind:"hole-named",name:"body_impl"}},
  {op:"replace", path:"/statements/1/body", value:{kind:"app",fn:"-",args:[
     {kind:"var",name:"balance"},{kind:"var",name:"amount"}]}}]}' > ./patch-correct.json
llmll patch ./demo.ast.json ./patch-correct.json | jq '{result}'
```

```json
{ "result": "PatchSuccess" }
```

> **🔍 Check — the program changed, and agent A's reservation was consumed.**
> ```bash
> shasum -a256 demo.ast.json | cut -c1-12          # NEW fingerprint — the body is now `-`
> jq -r '.tokens[].pointer' demo.llmll-lock.json   # only /statements/3/body remains
> ```
> Locks went `2 → 1`: a successful patch **auto-releases** the hole it filled. Agent A is done. **Agent B's `TOKEN_M` is now stale** — the file hash it witnessed no longer exists.

### 5 — `maxi`: resync the stale reservation, then the evidential bug

This step does double duty: it shows the compare-and-swap resync the concurrency note promised, *and* it is the "isn't this a toy?" beat — `maxi`'s spec is a property a type-passing wrong body still violates.

#### 5a — agent B discovers its token is stale, and resyncs

```bash
# Naively reusing the pre-acquired TOKEN_M now fails — the program moved under it.
# S-expression equivalent:   ?maxi_body  →  a   (any fill works; this only probes the stale token)
jq -n --arg t "$TOKEN_M" '{token:$t, patch:[
  {op:"test",    path:"/statements/3/body", value:{kind:"hole-named",name:"maxi_body"}},
  {op:"replace", path:"/statements/3/body", value:{kind:"var",name:"a"}}]}' > ./pm0.json
llmll patch ./demo.ast.json ./pm0.json | jq '{result}'        # -> {"result":"PatchAuthError"}

# Resync: release the stale reservation, re-checkout against the current program.
STALE=$(jq -r '.tokens[]|select(.pointer=="/statements/3/body").token' demo.llmll-lock.json)
llmll checkout ./demo.ast.json --release "$STALE" | jq '{released}'    # -> {"released":true}
TOKEN_M=$(llmll checkout ./demo.ast.json /statements/3/body --json | jq -r '.token')
```

> **🔍 Check — the new token witnesses the current program.**
> ```bash
> [ "$(jq -r '.tokens[0].source_hash' demo.llmll-lock.json | cut -c1-12)" \
>   = "$(shasum -a256 demo.ast.json | cut -c1-12)" ] && echo "in sync"
> ```
> *"`PatchAuthError` isn't a bug — it's the swarm refusing a lost update. Agent B re-reads the committed program, then proceeds."*

#### 5b — the type-passing bug (returns the *min*)

`(if (> a b) b a)` — a one-character slip; type-correct, and any test with `a = b` passes.

```bash
# S-expression equivalent:   ?maxi_body  →  (if (> a b) b a)
jq -n --arg t "$TOKEN_M" '{token:$t, patch:[
  {op:"test",    path:"/statements/3/body", value:{kind:"hole-named",name:"maxi_body"}},
  {op:"replace", path:"/statements/3/body", value:{kind:"if",
     cond:{kind:"op",op:">",args:[{kind:"var",name:"a"},{kind:"var",name:"b"}]},
     then_branch:{kind:"var",name:"b"},
     else_branch:{kind:"var",name:"a"}}}]}' > ./patch-maxi-bad.json
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

Both branches refuted, each named.

> **🔍 Check — untouched, reservation still held.** `shasum` unchanged; `jq '.tokens | length'` still `1`.

#### 5c — the repair

Correct body `(if (> a b) a b)` (swap the two `var` names):

```bash
# S-expression equivalent:   ?maxi_body  →  (if (> a b) a b)
jq -n --arg t "$TOKEN_M" '{token:$t, patch:[
  {op:"test",    path:"/statements/3/body", value:{kind:"hole-named",name:"maxi_body"}},
  {op:"replace", path:"/statements/3/body", value:{kind:"if",
     cond:{kind:"op",op:">",args:[{kind:"var",name:"a"},{kind:"var",name:"b"}]},
     then_branch:{kind:"var",name:"a"},
     else_branch:{kind:"var",name:"b"}}}]}' > ./patch-maxi-correct.json
llmll patch ./demo.ast.json ./patch-maxi-correct.json | jq '{result}'      # -> {"result":"PatchSuccess"}
```

> **🔍 Check — program changed, all reservations released.**
> ```bash
> shasum -a256 demo.ast.json | cut -c1-12          # NEW fingerprint
> jq '.tokens | length' demo.llmll-lock.json       # 0 — the swarm has dispersed
> ```
> The lock file remains on disk with an empty `tokens` array; `0` means no hole is reserved. (To abandon a reservation without patching, `llmll checkout ./demo.ast.json --release <token>` — the same call used in the resync.)

### 6 — Verify the trust closure (the climax) — two axes

`verify --trust-report --json` emits **two** JSON documents on stdout — the verify result, then the trust report — so `jq -s '.[1]'` slurps both and selects the report. We project the two axes that matter (the full object also carries per-function `dependencies`, `drifts`, `discriminative_axis`):

```bash
llmll verify ./demo.ast.json --strict-verified-core --trust-report --json 2>/dev/null \
  | jq -s '.[1] | {summary,
                   functions: [.entries[] | {name, post: .post_level, effective: .effective_level,
                                             requires: (.caller_obligations // [] | map(.requires))}]}'
```

```json
{
  "summary": {
    "asserted": 0,
    "contract_checked": 0,
    "drifts": 0,
    "no_contract": 0,
    "tested": 0,
    "verified": 3
  },
  "functions": [
    { "name": "withdraw", "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)", "requires": ["(>= balance amount)"] },
    { "name": "double",   "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)", "requires": [] },
    { "name": "maxi",     "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)", "requires": [] }
  ]
}
```

Exit `0` (`jq` reads the same stream that sets it). The report carries **two orthogonal axes**, and the JSON shows both:

- **The trust axis (`effective`)** — all three functions are `verified`. `withdraw` is *not* demoted for having a precondition: it proved its Hoare triple `{balance ≥ amount} body {result = balance − amount}`, so it is `verified`, full stop. (A function whose body the solver could *not* prove would read `asserted`/`contract_checked` here — that is what the trust axis is for.)
- **The obligation axis (`requires` / `caller_obligations`)** — `withdraw` carries a *visible caller-obligation*: `balance ≥ amount`. That is the part a **caller** must honor — surfaced explicitly, not folded into the tier. `double` and `maxi`, precondition-free, carry none.

*Two questions, answered separately:* **is it correct?** (`verified`) and **what must a caller guarantee?** (the obligation axis). The precondition's "assumed-ness" is real — but it lives where it belongs, on the caller. Step 6.5 shows it *enforced*.

### 6.5 — Composition: the obligation flows down

The obligation axis is not a label — it is **enforced** the moment something *composes* with `withdraw`. [`compose.llmll`](compose.llmll) is a same-module composer that calls the verified `withdraw`:

```lisp
(def-shell guarded-withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  (withdraw balance amount))
```

`guarded-withdraw` *discharges* `withdraw`'s precondition (its own `pre` guarantees `balance ≥ amount` at the call site) and proves its own post by leaning on `withdraw`'s — so it reaches `verified` too:

```bash
llmll verify ./compose.llmll --strict-verified-core --trust-report --json 2>/dev/null \
  | jq -s '.[1] | {summary, functions: [.entries[] | {name, effective: .effective_level}]}'
```
```json
{ "summary": { "asserted": 0, "contract_checked": 0, "drifts": 0, "no_contract": 0, "tested": 0, "verified": 2 },
  "functions": [ { "name": "withdraw", "effective": "verified (liquid-fixpoint)" },
                 { "name": "guarded-withdraw", "effective": "verified (liquid-fixpoint)" } ] }
```

**What a composer may lean on — the checkout brief.** Check out a hole inside a composer and the brief hands back the `consumed_guarantees` axis — what it may *assume* without re-proving:
```json
"consumed_guarantees": [
  { "callee": "withdraw", "guarantee": "(= result (- balance amount))",
    "instantiated": "(= <call-result> (- balance amount))", "status": "discharged" } ]
```
`status: discharged` means "`withdraw` already proved this — assume it, don't re-derive it." Trust flows **up** from the callee.

**Drop the precondition, and the system refuses the code.** Remove `guarded-withdraw`'s `pre` ([`compose-bad.llmll`](compose-bad.llmll)) — now nothing guarantees `balance ≥ amount` at the call site:
```bash
llmll verify ./compose-bad.llmll
```
```
error: call-site precondition of 'withdraw' not satisfied in 'guarded-withdraw' — caller does not prove callee's precondition (constraint #2)
```

One fact, **three views**: the *report* surfaces it (`caller_obligations`), the *verifier* enforces it (the call-site VC), and the *protocol* rejects a patch that violates it (`PatchVerifyError / callee-precondition-unmet`). The caller-obligation is load-bearing — compose with `withdraw` and you **must** discharge `balance ≥ amount`, or your code does not land.

### 7 — The authority axis (`effect_summary`)

The trust lattice answers *"is it correct?"*. A second, **orthogonal** axis answers *"what can it touch?"* — the object-capability **authority** a function may exercise. As of v0.12.0 (Bundle B0), `verify --obligation-report` emits a per-function `effect_summary`. The core (`demo.ast.json`) is pure — every function reports `∅`, which makes the point but does not exercise the feature. So [`audit.llmll`](audit.llmll) is a thin **shell** module over the core: it `(import demo)`s the verified `withdraw` and adds the one thing the core deliberately does not do — an audit line to `stdout`.

```bash
llmll verify ./audit.ast.json --obligation-report --json 2>/dev/null \
  | jq -s '.[0] | {cross_module, effect_summary}'
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

- **`effect_summary`** — `audit-withdraw` exercises exactly `["stdout"]`, and nothing else. The `withdraw` it imports from the core contributes `∅` to the union — the authority is the shell's, minimal and named. (A function reaching `?delegate`, opaque FFI, or an unresolved import would report `"unbounded"` (⊤) instead.)
- **`cross_module: "supported"`** — the summary composed *across* the `(import demo)` edge: the core module resolved and was fully walked, so its `∅` contribution is **sound rather than assumed** (the *∅-iff-fully-walked* rule). An unresolved import would have forced `⊤`.

This is the core/shell split made measurable, and it is **orthogonal to step 6**: authority ⊥ trust. A `verified` function may still be `⊤`-authority; this `asserted` shell reaches exactly one capability. Two questions — *is it correct?* and *what may it touch?* — answered separately, neither collapsed into the other.

### 8 — (Optional) Discriminative-power axis

Append `--cdp`. **This is the one human-readable step** — `--cdp` does *not* populate the JSON trust report (under `--json` the per-function `discriminative_axis` stays `"basis": "not-measured"`, `"score": null` regardless of flag order), so its scores exist only in the text output:

```bash
llmll verify ./demo.ast.json --strict-verified-core --trust-report --cdp
```

```
   CDP measured 3 function(s):
   double: score=1.000 (1/6 candidates satisfy) [const-satisfies-post]
   maxi: score=1.000 (1/7 candidates satisfy) [const-satisfies-post]
   withdraw: score=0.644 (2/7 candidates satisfy) [identity-satisfies-post, const-satisfies-post]
```

CDP measures how *tight* a contract is — the **score** is the discriminative measure (`maxi` and `double` are maximal at `1.000`; `withdraw`'s exact-value contract scores `0.644`). The bracketed advisories are sampling-based hints that appear broadly; read the score, not the flags. Powerful for a technical audience; **drop this step for a general audience** to keep the climax on the trust lattice.

---

## Narration cues

- **Step 2:** "Two agents, two holes, one program — reserved at once. Watch what the system does when their writes collide."
- **Step 3a → 3b:** "Types catch the obvious — wrong type, rejected. But this next fill *type-checks*, and every other tool would merge it. LLMLL proves it wrong anyway." The two distinct result codes (`PatchTypeError` then `PatchVerifyError`) are the type → contract escalation made concrete; the 🔍 checks prove nothing was committed either time.
- **Step 4 → 5a:** "Agent A commits. Agent B's reservation is now stale — and the system says so (`PatchAuthError`) rather than letting B clobber A's work. B re-reads and proceeds. That's the swarm's safety property in one move."
- **Step 5b:** "`maxi` is where it earns its keep. The spec says the answer is ≥ both inputs and is one of them — it doesn't say *how*. A fill that returns the min type-checks and passes most tests. The solver refutes it for every input and names *which branch* is wrong."
- **Step 6, the key line:** *"All three are verified — `withdraw` included. It proved its job. What it carries is a separate thing: a caller-obligation, `balance ≥ amount`, on its own axis. We don't demote a function for having a precondition — we name the precondition as the caller's to honor. Two questions, two axes."*
- **Step 6.5 (composition), the payoff:** *"Now watch the obligation become real. A function that calls `withdraw` and discharges `balance ≥ amount` is verified too. Drop that guarantee and the verifier refuses the code — the call-site precondition is exactly the obligation the report showed. The report names it, the verifier enforces it, the protocol rejects violations of it. One fact, three views."*
- **Step 7 (authority):** *"Correctness is one axis; authority is the other — what the code is even allowed to touch. The core proves correct **and** reaches nothing. The shell that logs an audit line reaches exactly `stdout`, and the report names it — composed across the import edge. Trust and authority are separate questions, and LLMLL answers both without conflating them."* Drop this step too for a purely correctness-focused pitch; lead with it for a security/capability audience.

> **Reading the report — two axes, don't scalarize.** The summary `verified` count is the *trust* axis (did the body prove its spec?); it no longer demotes a function for *having* a precondition. The *obligation* axis (`caller_obligations`) reports separately what a caller must guarantee. An agent that greps `effective_level == "verified"` and stops gets a true answer to *"is it correct?"* but misses *"what must I guarantee to call it?"* — read both. (Historical note: before TRUST-PRE this demo showed `withdraw` floored to `asserted: 1`. That floor conflated a function's *verification status* with its *caller's obligation* — a category error — and was removed; the precondition is now surfaced on its own axis. See [`docs/design/precondition-tier-proposal.md`](../../docs/design/precondition-tier-proposal.md).)

---

## Why these functions

`withdraw` carries a precondition **and** reaches `verified` — it proved its Hoare triple `{balance ≥ amount} body {result = balance − amount}`; its precondition is surfaced on the *obligation* axis (`caller_obligations`), not folded into the tier. `double` and `maxi`, precondition-free, carry no obligation — so the obligation axis itself tells a story: one function a caller must guarantee something to call, two it can call freely. `guarded-withdraw` (in [`compose.llmll`](compose.llmll), step 6.5) then makes that obligation *operational*: composing with `withdraw` forces you to discharge it, or the verifier refuses your code.

`maxi` is the evidential function, and it was chosen deliberately over a `clamp` example. `clamp`'s natural spec (`lo ≤ result ≤ hi`) is a *range*, which a constant body (`return lo`) satisfies — an under-specified contract (CDP scores it `0.472`, flags `const-satisfies-post`), and it cannot be completed cleanly because LLMLL has no implication operator. `maxi`'s property (`result ≥ a` ∧ `result ≥ b` ∧ `result ∈ {a, b}`) is **complete** with only conjunction and disjunction: it pins `result` to `max(a, b)` uniquely, no trivial body satisfies it (CDP `1.000`), and it stays inside the QF-LIA fragment liquid-fixpoint discharges. It is a sharp, honest instance of what the verifier genuinely does — relational/bounds properties over linear integer arithmetic, localized to the branch — not a stretch toward correctness it cannot prove.

`audit-withdraw` (in [`audit.llmll`](audit.llmll)) is **not** a fourth *core* function — it is a **shell** over the core, and it exists to make the authority axis (step 7) non-trivial. The core is pure, so its `effect_summary` is uniformly `∅`; a demo that only ever showed `∅` would not exercise Bundle B0. The shell imports the core's `withdraw` and adds the single capability the core deliberately lacks (`stdout`), so `effect_summary` reads `["stdout"]` and `cross_module` reads `"supported"` — authority composed across the import edge. It is a `def-shell` (not `def`) precisely because touching the world is non-body-faithful: the core's own `--strict-verified-core` gate (step 6) would *correctly* reject it. That is why it lives in its own module — so the climax stays pristine and the authority axis is shown without compromising the trust closure.
