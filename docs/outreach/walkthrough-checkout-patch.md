# Walkthrough: filling a hole through checkout/patch

This is a one-task tour of LLMLL's typed editing loop: start with a function whose body is a `?hole`, watch a wrong attempt get rejected at the patch boundary, then watch the right attempt verify. Five commands end-to-end.

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

## 2. Convert to JSON-AST and check out the hole

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

## 3. Wrong attempt — gets rejected at the patch boundary

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

## 4. Correct attempt — verifies and commits

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

## 5. Confirm with the trust report

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

## What this loop gave you

- **Concurrent editing without conflicts.** A second agent could have checked out a different hole in the same file simultaneously. Patches are scope-contained to the locked subtree.
- **Structural validation before commit.** No "tests fail later." A patch that breaks types or contracts never reaches the file.
- **Local typing context as data.** The agent never had to read surrounding code to know what was in scope; the checkout response carried it as a JSON object.
- **Diagnostics that point at the *patch operation*, not the file.** Errors are addressed to the agent that caused them, in the form the agent submitted.

The same loop scales to a `def-interface` skeleton with N specialist agents filling N holes in parallel — see [docs/orchestrator-walkthrough.md](https://github.com/machunter/llmll/blob/main/docs/orchestrator-walkthrough.md) for that version. The shape doesn't change; only the number of locks held simultaneously.

---

> **Note on JSON shapes.** The CLI outputs above are derived from `compiler/src/LLMLL/Checkout.hs:164-189` and the spec; exact serialization (key ordering, optional fields, full builtin list) may differ in details. Run the commands once and snapshot real output before publishing to an external audience.
