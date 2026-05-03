# Walkthrough: filling a hole through checkout/patch

This is a one-task tour of LLMLL's typed editing loop: start with a function whose body is a `?hole`, watch a wrong attempt get rejected at the patch boundary, then watch the right attempt verify. Six commands end-to-end.

## The starting state

`withdraw.llmll`:

```lisp
(type PositiveInt (where [x: int] (> x 0)))

(def-logic withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  ?body_impl)
```

The function has a precondition, a postcondition, and an unimplemented body. Type checking succeeds (a hole is well-typed), but the program cannot run.

## 1. Discover the open holes

```bash
$ llmll holes withdraw.llmll --json
[
    {
        "agent": null,
        "inferred-type": null,
        "kind": "named",
        "message": "hole: ?body_impl",
        "module-path": "def-logic withdraw",
        "pointer": "/statements/1/body",
        "status": "non-blocking"
    }
]
```

The compiler reports one open hole at `/statements/1/body`, inside `def-logic withdraw`. The agent doesn't have to grep for `?` markers — the compiler hands it the list.

## 2. Convert to JSON-AST and check out the hole

`checkout` requires JSON-AST input — the lock targets a JSON Pointer.

```bash
$ llmll build withdraw.llmll --emit -o .
✅ JSON-AST written to ./withdraw.ast.json

$ llmll checkout withdraw.ast.json /statements/1/body
{
    "pointer": "/statements/1/body",
    "hole_kind": "hole-named",
    "token": "3002919c6885fdd0...fecffb29ab",
    "ttl": 3600,
    "timestamp": "2026-05-03T01:33:55Z"
}
```

Note: `--emit` is a boolean flag (it emits JSON-AST); `-o` takes a **directory**, not a filename. The output file is named automatically (`withdraw.ast.json`).

The CLI checkout gives the agent a locked pointer and a bearer token. The **HTTP API** (`llmll serve`, port 7777) returns a richer response that also includes `in_scope`, `available_functions`, `type_definitions`, and `expected_return_type` — the full local typing context the agent needs to fill the hole without reading surrounding code.

## 3. Wrong attempt — gets rejected at the patch boundary

Suppose an unauthorized agent (or an agent with a stale token) attempts to patch the hole. The patch boundary rejects it:

```json
{
  "token": "0000000000000000000000000000000000000000000000000000000000000000",
  "patch": [
    { "op": "test",    "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace", "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "+",
                 "args": [ {"kind":"var","name":"balance"},
                           {"kind":"var","name":"amount"} ] } }
  ]
}
```

```bash
$ llmll patch withdraw.ast.json patch-wrong.json
{"message":"invalid or expired checkout token","result":"PatchAuthError"}
```

The patch is rejected — invalid token. The file on disk is unchanged, and the original lock is still held.

The patch boundary also enforces **scope containment**. Even with a valid token, an agent cannot modify nodes outside its checked-out subtree:

```bash
# Trying to modify /statements/0 (the type definition) with a lock on /statements/1/body:
$ llmll patch withdraw.ast.json patch-scope.json
{"message":"scope violation: op path /statements/0/body is outside checkout scope /statements/1/body","result":"PatchAuthError"}
```

## 3a. Wrong implementation — rejected by contract verification

With a valid token, suppose the agent submits `(+ balance amount)` — this type-checks but violates the postcondition `(= result (- balance amount))`:

```json
{
  "token": "3002919c6885fdd0...fecffb29ab",
  "patch": [
    { "op": "test",    "path": "/statements/1/body",
      "value": { "kind": "hole-named", "name": "body_impl" } },
    { "op": "replace", "path": "/statements/1/body",
      "value": { "kind": "app", "fn": "+",
                 "args": [ {"kind":"var","name":"balance"},
                           {"kind":"var","name":"amount"} ] } }
  ]
}
```

```bash
$ llmll patch withdraw.ast.json withdraw-patch-wrong.json
{"result":"PatchVerifyError","diagnostics":[...]}
```

The patch is **rejected** — it type-checks but the SMT solver proves the body violates the contract. The file on disk is unchanged, and the lock is preserved for retry. The `diagnostics` array contains rebased JSON Pointers pointing at the failed constraint.

> **Note:** If `liquid-fixpoint` is not installed, the patch proceeds on typecheck success alone (graceful degradation). The re-verification gate requires the solver binary in `PATH`.

## 4. Correct attempt — patches and verifies

The agent with the valid token submits `(- balance amount)`:

```json
{
  "token": "3002919c6885fdd0...fecffb29ab",
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
{"result":"PatchSuccess","statements":2}
```

The patch applied: the compiler re-parsed, re-typechecked, and re-verified the patched AST against the function's contracts via SMT. The file is updated and the lock is cleared.

Now confirm with `llmll verify`:

```bash
$ llmll verify withdraw.ast.json
   .fq written to /tmp/withdraw.ast.fq
   body-faithful: withdraw
   Running liquid-fixpoint ...
✅ withdraw.ast.json — SAFE (liquid-fixpoint)
   .verified.json written to withdraw.ast.json.verified.json
```

`body-faithful: withdraw` means the verifier encoded the actual body `(- balance amount)` as a verification condition — not just the contract signature. The solver proved: `(>= balance amount) ∧ (result = (- balance amount)) ⟹ (= result (- balance amount))`.

## 5. Confirm with the trust report

```bash
$ llmll verify withdraw.ast.json --trust-report
Trust Report
────────────────────────────────────────────────────────────
  withdraw:
    pre:  asserted  |  post: verified (liquid-fixpoint)
────────────────────────────────────────────────────────────
Summary:
  verified:         0
  contract-checked: 0
  tested:           0
  asserted:         1
  no contract:      0
```

`post: verified (liquid-fixpoint)` means the postcondition was proven by the solver against the actual function body. `pre: asserted` means the precondition is a caller-side assumption — the function asserts it but does not prove it (call-site verification uses compositional VCs via assume-guarantee reasoning).

## What this loop gave you

- **Concurrent editing without conflicts.** A second agent could have checked out a different hole in the same file simultaneously. Patches are scope-contained to the locked subtree.
- **Structural validation before commit.** A patch with an invalid token, expired lock, or out-of-scope pointer never reaches the file.
- **Local typing context as data.** Via the HTTP API, the agent never has to read surrounding code to know what's in scope; the checkout response carries `in_scope`, `available_functions`, and `type_definitions` as structured JSON.
- **Unified safety gate.** The patch boundary enforces authorization, type correctness, *and* contract correctness (via SMT re-verification) in a single `llmll patch` call. A semantically wrong patch is rejected without touching the file.

The same loop scales to a `def-interface` skeleton with N specialist agents filling N holes in parallel — see [docs/orchestrator-walkthrough.md](https://github.com/machunter/llmll/blob/main/docs/orchestrator-walkthrough.md) for that version. The shape doesn't change; only the number of locks held simultaneously.

---

> **Note on JSON shapes.** The CLI outputs above were captured from a real end-to-end run against `compiler/src/LLMLL/Checkout.hs` (ToJSON instance) and `compiler/src/Main.hs` (doCheckout, doPatch). The context-aware checkout (with `in_scope`, `available_functions`, etc.) is available via the HTTP API (`llmll serve`); the CLI `checkout` command returns the base token fields only.
