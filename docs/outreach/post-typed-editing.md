# Typed file editing: what if the editor rejected ill-typed patches?

When Claude Code edits a file, the Edit tool gets two strings — `old_string` and `new_string` — and the harness substitutes them. There's no structural validation. If the new string introduces a type error, an unbalanced brace, or a contract violation, you find out the next time something runs over the file. Edits are bytes; the type system is "any sequence of bytes that doesn't crash later."

That's fine for most languages. **LLMLL is an experiment in what happens when you flip it: edits are typed, scope-contained, and rejected at the patch boundary if they don't fit.** It's not a different kind of agent — it's a different kind of editor. The interesting question is whether the design generalizes.

The lifecycle for filling an unimplemented hole:

1. **Discover.** `llmll holes file.ast.json --json` returns every `?hole` with its type, scope, and dependency edges. The agent doesn't infer what's open from comments — the compiler tells it.

2. **Checkout.** `llmll checkout file.ast.json /statements/2/body` locks one hole and returns a token plus the *local typing context*: bindings in scope (Γ), expected return type (τ), and available functions monomorphized against the concrete scope (Σ). Concurrent checkout on the same pointer is rejected with a structured diagnostic; locks have a TTL.

3. **Patch.** The agent submits an RFC 6902 JSON-Patch scoped to the locked subtree. The compiler re-parses, re-typechecks, and — if the function carries contracts — re-verifies via SMT. If anything fails, the patch is rejected and the diagnostic points at the *patch operation* that broke things, not at the file.

4. **Iterate.** Next agent picks up the next hole. Type environments are cached between patches; only the touched subtree is re-verified.

The result is concurrent editing without merge conflicts (each agent owns one subtree, scope-contained), structural validation before commit (no "tests fail later"), and the agent never has to infer what's in scope — the compiler hands it the typing context as a JSON object. An HTTP endpoint (`llmll serve`) lets agents drive this through a tool interface rather than the CLI.

The lineage worth naming: this is what tool-use looks like when the tool is *the language semantics*, not a wrapper around shell commands. Compare to MCP — MCP gives an agent structured handles to operate on the world; hole/checkout/patch gives it structured handles to operate on the *program*. The shapes rhyme.

What this doesn't replace: most code isn't LLMLL, and the typed-edit story doesn't help when your language doesn't emit structured obligations. But the design suggests a research direction — what would a typed edit primitive for TypeScript look like? `tsc --build`'s incremental mode already has the machinery; what's missing is the obligation surface and the patch protocol. An MCP server that exposed `tsc-checkout` / `tsc-patch` against a project's AST would be a non-trivial but tractable thing to build.

A walkthrough of the full loop on a small `withdraw` function — including a deliberate contract violation that gets rejected at the patch boundary, then the correct attempt that verifies — is at [docs/outreach/walkthrough-checkout-patch.md](https://github.com/machunter/llmll/blob/main/docs/outreach/walkthrough-checkout-patch.md). The end-to-end multi-agent version is at [docs/orchestrator-walkthrough.md](https://github.com/machunter/llmll/blob/main/docs/orchestrator-walkthrough.md). Two frozen benchmarks ([ERC-20](https://github.com/machunter/llmll/tree/main/examples/erc20_token), [TOTP RFC 6238](https://github.com/machunter/llmll/tree/main/examples/totp_rfc6238)) show the lifecycle on real specs.

LLMLL is GPLv3, solo project. Repo: [github.com/machunter/llmll](https://github.com/machunter/llmll). Feedback on the typed-edit framing especially welcome — particularly from anyone working on MCP servers for code, structured tool outputs, or harness-level edit primitives.
