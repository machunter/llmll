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
llmll-orchestra ../examples/auth_module/auth_module.ast.json --scan-only
```

### Dry run (stub patches, no API calls)

```bash
llmll-orchestra ../examples/auth_module/auth_module.ast.json --dry-run -v
```

### Full run (requires `ANTHROPIC_API_KEY`)

```bash
export ANTHROPIC_API_KEY=sk-ant-...
llmll-orchestra ../examples/auth_module/auth_module.ast.json -v
```

### JSON output

```bash
llmll-orchestra ../examples/auth_module/auth_module.ast.json --scan-only --json
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
| `--model MODEL` | Anthropic model (default: claude-sonnet-4-20250514) |
| `--max-retries N` | Retry attempts per hole (default: 3) |
| `--dry-run` | Use stub agent, no API calls |
| `--scan-only` | Show dependency graph only |
| `--json` | JSON output |
| `-v, --verbose` | Detailed progress to stderr |
