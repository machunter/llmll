# Orchestrator Walkthrough: delegate-hole resolution and what gets proved

Shows the hole-resolution flow on an authentication module whose function bodies
start as `?delegate` holes and are filled by out-of-process agents. The full
step-by-step guide, with a live run, is
[`docs/orchestrator-walkthrough.md`](../../docs/orchestrator-walkthrough.md).

1. **`auth_module.ast.json`** is the *unfilled* module: a `Decision` type
   (`Reuse`, `Fresh`, `Deny`) and six holes. `llmll holes auth_module.ast.json`
   lists them: `6 holes (0 blocking)`.
   - Decisions, each with a `post`: `token-valid?` and `hash-ok?`
     (`@crypto-agent`), `decide` (`@gateway-agent`).
   - Plumbing, no `post`: `hash-password-impl` (`@crypto-agent`),
     `login-handler` (`def-shell`, `@session-agent`, with a `pre`),
     `authenticate-request` (`def-shell`, `@gateway-agent`, routes on `decide`).

   Every delegated function carries an `on_failure` fallback, so the module
   type-checks (`llmll check auth_module.ast.json` gives OK, 8 statements).
   `llmll holes --deps` puts the four `def` holes in Tier 0 and the two
   `def-shell` holes in Tier 1.
2. **`auth_module_filled.ast.json`** is the module with reviewed fills.
3. **Trust.** `llmll verify auth_module_filled.ast.json` reports
   `body-faithful: token-valid?, hash-ok?, decide`: the solver proves each
   decision body against its postcondition. The plumbing is not proved.
   `hash-password-impl` and `authenticate-request` have no contract and land in
   `--spec-coverage`'s **Unspecified** bucket. `login-handler` shows `asserted`
   from its own `pre` and falls back as `no-post`. The spec-coverage line is
   `Functions with contracts: 4 / 6 (67%)` with `Verified: 3`.
   `--trust-report` counts `verified: 3` and `no contract: 3`.

   The plumbing has no postcondition because the solver cannot prove one for it
   on v0.26.9: `string-concat` bodies, `Result`-returning `if` bodies, and
   equality with a string-payload constructor such as `(ok s)` all fall back.
   An accepted plumbing fill is checked for its type only. In the live run the
   guide describes, the accepted `hash-password-impl` returned `"sha1$"` plus the
   raw password, which is not a hash, and nothing flagged it.

> Distinct from `tools/llmll-orchestra/fixtures/auth_module/`. Despite the name,
> that fixture is *not* concrete: `llmll holes
> tools/llmll-orchestra/fixtures/auth_module/auth_module.ast.json`
> shows 2 unfilled `?delegate` holes (`login-handler`, `validate-session`),
> deliberately left as-is since `tools/llmll-orchestra`'s own scan/dry-run/
> full-run examples use it in that state. The distinction from this
> walkthrough's fixtures is which *story* each tells (delegation, orchestration
> and proof here vs. the orchestrator's own CLI examples there), not
> holes-vs-no-holes. Do not merge.
