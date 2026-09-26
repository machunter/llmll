# orchestrator_walkthrough: delegate holes before and after the agents fill them

An `AuthSystem` module whose implementations start as `?delegate` holes, each naming
the agent that should fill it (`@crypto-agent`, `@session-agent`, `@gateway-agent`),
and the same module after the orchestrator merged the agents' bodies back. Every
delegated function carries an `on_failure` fallback, so the unfilled module already
type-checks.

The example is about resolution mechanics, not proof. Only `login-handler` has a
contract (an explicit `pre`), so the filled module proves nothing, and spec
coverage shows the split between the one contracted function and the three
unspecified ones. The trust discussion is in [`WALKTHROUGH.md`](WALKTHROUGH.md).

| File | What it is |
|---|---|
| `auth_module.ast.json` | The unfilled module: 4 delegate holes |
| `auth_module_filled.ast.json` | The module after the agents returned and the bodies were merged |
| [`WALKTHROUGH.md`](WALKTHROUGH.md) | The flow step by step, the trust split, and how this differs from `tools/llmll-orchestra/fixtures/auth_module/` |

## Commands (outputs reproduced against llmll 0.26.5)

Run from this directory, on a copy (`verify` writes a `.verified.json` sidecar).

```bash
llmll check ./auth_module.ast.json
llmll holes ./auth_module.ast.json
```
```
✅ ./auth_module.ast.json — OK (5 statements)
./auth_module.ast.json — 4 holes (0 blocking)
  [AGENT] ?delegate @crypto-agent in def hash-password-impl
  [AGENT] ?delegate @crypto-agent in def verify-token-impl
  [AGENT] ?delegate @session-agent in def-shell login-handler
  [AGENT] ?delegate @gateway-agent in def-shell authenticate-request
```
Both exit 0. `llmll holes ./auth_module_filled.ast.json` reports `0 holes`.

```bash
llmll verify ./auth_module_filled.ast.json
```
```
   body-fallback: login-handler
   Running liquid-fixpoint ...
⚠️  ./auth_module_filled.ast.json — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```
Exit 0: SAFE here means no contradiction was found, not that anything was proved.

```bash
llmll verify ./auth_module_filled.ast.json --spec-coverage
```
```
Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     1 / 4   (25%)
    Verified:                   0
    Tested:                     0
    Asserted:                   1
  Unspecified:                  3
    hash-password-impl, verify-token-impl, authenticate-request
────────────────────────────────────────────
  Effective coverage: 25% (1/4)
```
Exit 0. `--trust-report` counts the same four functions as `no contract: 4`,
because none of them has a post.
