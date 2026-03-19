# LLMLL JSON-AST Versioning Policy

**Status:** Active — applies from v0.1.2 onward.

## The `schemaVersion` Field

Every `.ast.json` file produced by or consumed by the LLMLL compiler must include a `"schemaVersion"` field at the top-level `Program` object:

```json
{
  "schemaVersion": "0.1.2",
  "llmll_version": "0.1.2",
  "statements": [ ... ]
}
```

This field is the primary gate for compatibility. The compiler reads `schemaVersion` before any other field and rejects mismatches immediately with a structured JSON diagnostic:

```json
{
  "kind": "schema-version-mismatch",
  "message": "Expected schemaVersion '0.1.2', got '0.1.1'",
  "severity": "error"
}
```

## Version Compatibility Rules (v0.1.x)

| Compiler version | Accepted `schemaVersion` values |
|------------------|---------------------------------|
| v0.1.2           | `"0.1.2"` only                 |
| v0.1.3+          | TBD — backward compat policy deferred to v0.2 discussion |

**Strict mode applies in v0.1.x:** only the exact matching version is accepted. This avoids silent semantic mismatches while the schema is still rapidly evolving.

## Upgrade Path

When the schema changes between patch versions:

1. Bump `schemaVersion` and `$id` in `docs/llmll-ast.schema.json`.
2. Update the `expectedSchemaVersion` constant in `compiler/src/LLMLL/ParserJSON.hs`.
3. Re-emit all golden `.ast.json` fixtures in `examples/` using `llmll build --emit json-ast`.
4. Update this document's compatibility table.

## Round-Trip Guarantee

The LLMLL compiler guarantees that for any valid `.llmll` source file:

```bash
# Step 1: Emit JSON-AST from S-expression source
llmll build FILE --emit json-ast       # writes FILE.ast.json

# Step 2: Build directly from JSON-AST (auto-detected by .json extension)
llmll build FILE.ast.json
```

…produces **semantically identical compiled output** to building the original `.llmll` source directly. Any divergence is a compiler bug.

> **Note:** The `build` command auto-detects `.json` / `.ast.json` files by extension and routes them through the JSON-AST parser automatically. There is no separate `--from-json` flag.

## `llmll_version` vs `schemaVersion`

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Version of the *JSON-AST schema* (shape of the JSON). This is what the compiler gates on. |
| `llmll_version` | Version of the *LLMLL language* that the expressions in `statements` use. Currently always equal to `schemaVersion`. They may diverge in future if the schema stabilises ahead of the language. |
