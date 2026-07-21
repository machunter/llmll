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
3. **Trust:** none of `hash-password-impl`, `verify-token-impl`, or
   `authenticate-request` carry a `pre`/`post` at all in this fixture, so they
   land in `--spec-coverage`'s **Unspecified** bucket, not `asserted` — the
   out-of-process carve-out (LLMLL.md §4.4 / §11.2) is real, but this fixture
   doesn't exercise it, since there's no stated contract to be asserted-not-
   proven in the first place. `login-handler` (a `def-shell`) is the one
   function that shows `asserted`, from its own hand-written `pre` — unrelated
   to the delegate-filled bodies it composes. Verifying the filled module
   (`llmll verify auth_module_filled.ast.json --spec-coverage`) shows this
   1-contracted-of-4 split directly (`Functions with contracts: 1 / 4 (25%)`);
   `--trust-report`'s summary counts the same functions differently (it buckets
   the three contract-less delegates as `no contract`, so `asserted: 0`).

> Distinct from `tools/llmll-orchestra/fixtures/auth_module/` — despite the name,
> that fixture is *not* concrete: `llmll holes
> tools/llmll-orchestra/fixtures/auth_module/auth_module.ast.json`
> shows 2 unfilled `?delegate` holes (`login-handler`, `validate-session`),
> deliberately left as-is since `tools/llmll-orchestra`'s own scan/dry-run/
> full-run examples use it in that state (it lives with the orchestrator now). The distinction from this
> walkthrough's fixtures is which *story* each tells (delegation/orchestration
> mechanics here vs. the orchestrator's own CLI examples there), not
> holes-vs-no-holes. Do not merge.
