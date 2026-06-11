# LLMLL Repair-Loop Demo — Capture Runbook

> **Artifact:** "From a bad agent patch to verified trust closure."
> **Fixture:** [`demo.ast.json`](demo.ast.json) — `PositiveInt`, `withdraw` (typed hole), `double` (pre-verified), `maxi` (typed hole). The JSON-AST is what the agent checkout/patch protocol operates on; [`demo.llmll`](demo.llmll) is the human-readable source it is generated from (`llmll build ./demo.llmll --emit -o .`).
> **Verified against:** `llmll 0.11.1`, real `liquid-fixpoint` on PATH, `jq` on PATH. Every command and output block below was captured from that binary on 2026-06-07.

This is the canonical capture script for the public repair-loop demo. It supersedes the older single-function `withdraw.ast.json` flow, which could only ever show `verified: 0` in the summary (sound but visually self-undercutting — see [Why these functions](#why-these-functions)).

---

## What the demo proves

LLMLL turns *"did the AI write correct code?"* from a judgment call into a machine-checkable verdict — and is honest about which part of that verdict is **proven** versus **assumed**. The three functions stage three distinct points:

- `withdraw` — a contract (`pre: balance ≥ amount`, `post: result = balance − amount`) with an empty body (`?body_impl`). The legible on-ramp: a sign-error fill is type-correct but contract-violating.
- `double` — proven, **no precondition**: a fully-closed function that earns top-tier `verified`.
- `maxi` — a postcondition that is a complete **property** (`result ≥ a` ∧ `result ≥ b` ∧ `result ∈ {a, b}`), *not* a copy of the body. A plausible wrong fill (returns the *min*) type-checks and passes most tests, but the verifier refutes it for all inputs and localizes the defect to each branch. This is the evidential case — verification doing work types and tests cannot.

The climax dashboard shows all three: `double` and `maxi` reach `verified`; `withdraw`'s postcondition is proven but the function stays `asserted` because its safety rests on a precondition the **caller** must honor. No other AI tool can draw that distinction — that contrast *is* the product.

---

## Prerequisites

```bash
llmll --version          # must report 0.11.1 (the VERIFY-RPT-1 fix; see note below)
which fixpoint           # must resolve — refuted/verified verdicts require the real solver
which jq                 # used to build patches and project JSON output to the values that matter
```

> **Critical:** a binary older than `b914587` (2026-06-06) reports `success: true` on the bad fill and can never render `verified` — the very bugs this demo was blocked on. If `llmll --version` is not ≥ `0.11.1`, run `cd compiler && stack install` first. (The `--version` number alone is not proof; the fix landed mid-`0.11.0` cycle.)

Work from a scratch directory so every command is relative and `patch` can mutate files freely:

```bash
mkdir -p /tmp/llmll-demo
cp examples/withdraw-demo/demo.ast.json /tmp/llmll-demo/
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

That is the agent's contract: fill `/statements/1/body` with an expression over `balance` and `amount` that, *assuming* `balance ≥ amount`, *proves* `result = balance − amount`. The full object also carries the trust channel, the callable `available_functions`, and OBLIG-4 repair `suggestions`; `expected_type` reads `unknown` here because the hole's return type is left to inference rather than annotated.

> `verify --obligation-report` is the **whole-program** view — every hole, unproven contract, call-site failure, and `refuted_fns` at once. As of v0.11.2, `checkout` (next step) returns this *same per-hole brief inline* for the hole you reserve, so a single-hole agent gets the spec and the lock in one call. Use the report when surveying the program; use the checkout brief when working one reserved hole.

### 2 — Reserve every hole up front (the swarm model)

A swarm divides labor: one agent takes `withdraw`, another takes `maxi`. Reserve **both** holes before touching either — this is the move that hints at parallel agents.

```bash
TOKEN_W=$(llmll checkout ./demo.ast.json /statements/1/body --json | jq -r '.token')   # agent A
TOKEN_M=$(llmll checkout ./demo.ast.json /statements/3/body --json | jq -r '.token')   # agent B
```

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

### 6 — Verify the trust closure (the climax)

`verify --trust-report --json` emits **two** JSON documents on stdout — the verify result, then the trust report — so `jq -s '.[1]'` slurps both and selects the report. We project the fields that matter (the full object also carries per-function `discriminative_axis`, `drifts`, `dependencies`):

```bash
llmll verify ./demo.ast.json --strict-verified-core --trust-report --json 2>/dev/null \
  | jq -s '.[1] | {summary, tier_profile_post,
                   functions: [.entries[] | {name, pre: .pre_level, post: .post_level, effective: .effective_level}]}'
```

```json
{
  "summary": {
    "asserted": 1,
    "contract_checked": 0,
    "drifts": 0,
    "no_contract": 0,
    "tested": 0,
    "verified": 2
  },
  "tier_profile_post": {
    "asserted": 0,
    "contract_checked": 0,
    "no_contract": 0,
    "proved": 0,
    "tested": 0,
    "verified": 3
  },
  "functions": [
    { "name": "withdraw", "pre": "asserted", "post": "verified (liquid-fixpoint)", "effective": "asserted" },
    { "name": "double",   "pre": null,       "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)" },
    { "name": "maxi",     "pre": null,       "post": "verified (liquid-fixpoint)", "effective": "verified (liquid-fixpoint)" }
  ]
}
```

Exit `0` (`jq` reads the same stream that sets it). The report is a **lattice, not a checkmark**, and the JSON makes the two readings explicit:

- **`functions[].effective`** is the per-function meet: `double` and `maxi` are `verified`; `withdraw`'s post is proven but it floors to `asserted` because its precondition is a caller-side obligation.
- **`tier_profile_post.verified: 3`** vs **`summary.verified: 2`** is the whole story in two numbers: *all three* postconditions are machine-proven, but only two functions are `verified` *overall* — `withdraw` carries an assumed precondition the meet honestly refuses to discard.

### 7 — (Optional) Discriminative-power axis

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
- **Step 6, the key line:** read the per-function lines, not the summary header. *"LLMLL proved three postconditions. It awarded top-tier `verified` only to `double` and `maxi`, which stand on nothing. `withdraw`'s safety still rests on a precondition the caller must honor — and the dashboard tells you exactly that, instead of a green check it can't justify."*

> **Known visual landmine.** The summary header counts each function at its *weakest* clause (`evidenceMeet`, sound and documented at `LLMLL.md` §4.4.1). So `withdraw` contributes to `asserted: 1`, not `verified`. With `double` and `maxi` present the summary lands a real `verified: 2`, which is why the multi-function fixture matters: it gives the headline a true top-tier count while keeping `withdraw` honest. Do not "fix" this in the compiler — it is the trust model working as specified (`LLMLL.md:498-501` is this exact shape).

---

## Why these functions

A single-function `withdraw` demo can **never** show `verified` in the summary: `withdraw`'s precondition is a caller-side obligation, `asserted` at its own boundary by design (`LLMLL.md` §4.4.5 side-condition 6), so `meet(asserted, verified) = asserted` caps it. `double` and `maxi` — both precondition-free — are the in-surface way to demonstrate that the lattice *does* award top-tier trust when nothing is assumed, beside the honesty about what is.

`maxi` is the evidential function, and it was chosen deliberately over a `clamp` example. `clamp`'s natural spec (`lo ≤ result ≤ hi`) is a *range*, which a constant body (`return lo`) satisfies — an under-specified contract (CDP scores it `0.472`, flags `const-satisfies-post`), and it cannot be completed cleanly because LLMLL has no implication operator. `maxi`'s property (`result ≥ a` ∧ `result ≥ b` ∧ `result ∈ {a, b}`) is **complete** with only conjunction and disjunction: it pins `result` to `max(a, b)` uniquely, no trivial body satisfies it (CDP `1.000`), and it stays inside the QF-LIA fragment liquid-fixpoint discharges. It is a sharp, honest instance of what the verifier genuinely does — relational/bounds properties over linear integer arithmetic, localized to the branch — not a stretch toward correctness it cannot prove.
