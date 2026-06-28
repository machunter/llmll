# Orchestrator Walkthrough — delegate-hole resolution

Shows the hole-resolution flow: an `AuthSystem` interface whose implementations
start as `?delegate` holes and are filled by out-of-process agents.

1. **`auth_module.ast.json`** — the *unfilled* module. `hash-password-impl` and
   `verify-token-impl` are `hole-delegate` bodies (`@crypto-agent`); `login-handler`
   (a `def-shell`) composes them and delegates session-building to `@session-agent`.
   Every delegated function carries an `on_failure` fallback, so the module still
   type-checks (`llmll check auth_module.ast.json` → OK).
2. **`auth_module_filled.ast.json`** — the *resolved* module after the agents
   return implementations and the loop merges them back.
3. **Trust:** delegate-bodied functions stay `asserted` (the out-of-process
   carve-out, LLMLL.md §4.4 / §11.2) — verifying the filled module shows which
   functions reach which tier.

> Distinct from `examples/auth_module/` — that ships concrete impls (no holes);
> this one is the *delegation/orchestration* story. Do not merge.
