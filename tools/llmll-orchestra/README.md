# llmll-orchestra

Multi-agent orchestrator for LLMLL hole-filling. Consumes the `llmll` compiler's
`holes --json --deps` output, topologically sorts holes by dependency, and
coordinates LLM agents to fill them via `checkout` → `patch` cycles.

## Install

```bash
cd tools/llmll-orchestra
pip install -e .
```

Requires the `llmll` compiler binary on `$PATH` (or pass `--llmll /path/to/llmll`).

## Usage

### Scan holes and scheduling tiers (no API calls)

```bash
llmll-orchestra fixtures/auth_module/auth_module.ast.json --scan-only
```

### Dry run (stub patches, no API calls)

```bash
llmll-orchestra fixtures/auth_module/auth_module.ast.json --dry-run -v
```

### Full run (requires `ANTHROPIC_API_KEY`)

```bash
export ANTHROPIC_API_KEY=sk-ant-...
llmll-orchestra fixtures/auth_module/auth_module.ast.json --provider anthropic -v
```

### Proof-checked run

`fixtures/ledger/` gives every delegated body a postcondition inside the decidable fragment.
With `--require-proof`, a fill is accepted only when the solver proves it: a correct body written
with a construct outside the fragment (such as `min`) is refused, and the refused construct is fed
back to the agent.

```bash
llmll-orchestra fixtures/ledger/ledger.ast.json --provider anthropic --require-proof -v
llmll verify fixtures/ledger/ledger.ast.json --strict-verified-core
```

Both commands edit the file in place (the second writes a `.verified.json` sidecar), so run them on a copy.

### JSON output

```bash
llmll-orchestra fixtures/auth_module/auth_module.ast.json --scan-only --json
```

## Architecture

```
__main__.py      CLI entry point
compiler.py      Subprocess wrapper (holes, checkout, patch, release)
graph.py         Topological sort + parallel scheduling tiers
agent.py         Anthropic SDK + prompt construction + DryRunAgent
orchestrator.py  Main loop: scan → sort → checkout → fill → patch → retry
```

## Options

| Flag | Description |
|------|-------------|
| `--llmll PATH` | Path to llmll binary |
| `--provider {anthropic,openai}` | LLM provider (default: openai) |
| `--model MODEL` | Model (default: claude-opus-5 for anthropic, gpt-4o for openai) |
| `--require-proof` | Accept a fill only if the solver proves its postcondition (`llmll patch --require-proof`) |
| `--max-retries N` | Retry attempts per hole (default: 3) |
| `--dry-run` | Use stub agent, no API calls |
| `--scan-only` | Show dependency graph only |
| `--json` | JSON output |
| `-v, --verbose` | Detailed progress to stderr |
