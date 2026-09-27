# orchestrator_walkthrough: delegate holes before and after the agents fill them

An authentication module whose function bodies start as `?delegate` holes, each
naming the agent that should fill it (`@crypto-agent`, `@session-agent`,
`@gateway-agent`), and the same module with reviewed fills. Every delegated
function carries an `on_failure` fallback, so the unfilled module already
type-checks.

The module has two kinds of function. The three authentication decisions
(`token-valid?`, `hash-ok?`, `decide`) carry postconditions, and the solver
proves the filled bodies. The three plumbing functions (`hash-password-impl`,
`login-handler`, `authenticate-request`) build strings and `Result` values, have
no postcondition, and are not proved. The step-by-step guide is
[`docs/orchestrator-walkthrough.md`](../../docs/orchestrator-walkthrough.md);
the trust split is in [`WALKTHROUGH.md`](WALKTHROUGH.md).

| File | What it is |
|---|---|
| `auth_module.ast.json` | The unfilled module: 6 delegate holes, 3 of them under a postcondition |
| `auth_module_filled.ast.json` | The module with reviewed fills |
| [`WALKTHROUGH.md`](WALKTHROUGH.md) | The flow in brief, the trust split, and how this differs from `tools/llmll-orchestra/fixtures/auth_module/` |

## Commands (outputs reproduced against llmll 0.26.9)

Run from this directory, on a copy (`verify` writes a `.verified.json` sidecar).
The `.fq written to` and `.verified.json written to` lines are omitted.

```bash
llmll check ./auth_module.ast.json
llmll holes ./auth_module.ast.json
```
```
✅ ./auth_module.ast.json — OK (8 statements)
./auth_module.ast.json — 6 holes (0 blocking)
  [AGENT] ?delegate @crypto-agent in def hash-password-impl
  [AGENT] ?delegate @crypto-agent in def token-valid?
  [AGENT] ?delegate @crypto-agent in def hash-ok?
  [AGENT] ?delegate @gateway-agent in def decide
  [AGENT] ?delegate @session-agent in def-shell login-handler
  [AGENT] ?delegate @gateway-agent in def-shell authenticate-request
```
Both exit 0. `llmll holes ./auth_module_filled.ast.json` reports `0 holes`.

```bash
llmll verify ./auth_module_filled.ast.json
```
```
   body-faithful: token-valid?, hash-ok?, decide
   body-fallback: login-handler
   Running liquid-fixpoint ...
✅ ./auth_module_filled.ast.json — SAFE (liquid-fixpoint)
```
Exit 0. The three decisions are proved from their bodies. `login-handler` falls
back because it has a `pre` and no `post`.

```bash
llmll verify ./auth_module_filled.ast.json --spec-coverage
```
```
Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     4 / 6   (67%)
    Verified:                   3
    Tested:                     0
    Asserted:                   1
  Unspecified:                  2
    hash-password-impl, authenticate-request
────────────────────────────────────────────
  Effective coverage: 67% (4/6)
```
Exit 0. `--trust-report` counts `verified: 3` and `no contract: 3`; it puts
`login-handler` under `no contract` because it has no `post`.

On the unfilled skeleton, `llmll verify ./auth_module.ast.json` prints
`partial: 0 of 3 contracted functions proved; 3 assumed, not proved: token-valid?, hash-ok?, decide`:
the contracts are present and the holes are not yet filled.
