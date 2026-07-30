# External Integrations

**Analysis Date:** 2026-07-30

## APIs & External Services

**Mistral AI (Leanstral proof prover):**
- Service: Mistral API for LLM-assisted proof generation
  - What it's used for: Generating Lean 4 proofs for obligation verification
  - Endpoint: `POST https://api.mistral.ai/v1/chat/completions`
  - SDK/Client: HTTP via Haskell `Network.HTTP.Types` (no SDK wrapper)
  - Auth: API key from environment (`LLMLL_LEANSTRAL_API_KEY`)
  - Implementation: `compiler/src/LLMLL/MCPClient.hs::proveWithLeanstral`
  - Modes:
    - Direct (`--leanstral`): Real Mistral API call, extracts Lean fenced block, kernel-checks result
    - Mock (`--leanstral-mock`): Emits `by sorry` (rejected by anti-laundering guard)
  - Security: API key read from environment only; never logged, never persisted, never on CLI argv

**Anthropic Claude API:**
- Service: Claude for multi-agent orchestration
  - What it's used for: Lead Agent decomposition of intents into architecture plans
  - SDK/Client: anthropic>=0.25.0 (Python)
  - Auth: ANTHROPIC_API_KEY (env var, managed by Python SDK)
  - Implementation: `tools/llmll-orchestra/llmll_orchestra/lead_agent.py`
  - Models: Supports Claude Opus/Sonnet/Haiku for different agent roles
  - Integration: Lead Agent generates JSON architecture plans consumed by hole-filling agents

## Data Storage

**Databases:**
- Not used — all state is ephemeral per-request or file-based

**File Storage:**
- Local filesystem only
  - Source files: `.llmll` in `examples/`, user projects
  - Verified cache: `~/.llmll/verified/` (optional, loaded by `typeCheckWithCache`)
  - Checkout locks: `~/.llmll/checkouts/` (JSON files with timestamps)
  - Proof cache: `~/.llmll/proof-cache.json` (Leanstral proofs, upgradeable)
  - Sketch tokens: `~/.llmll/sketch.token` (generated on first serve)
  - Event logs: JSONL format, written during `test` runs (optional via `--event-log`)
  - Temporary files: System temp dir for intermediate `.fq` files, subprocess outputs

**Caching:**
- Verified sidecar caching: Optional via `--cache` flag
  - Stores JSON with proof results per function
  - Invalidated if source hash changes or different verification level requested
  - Location: `<source>.verified.json` (same dir as source)

- Proof cache: Optional via `--proof-artifact`
  - Stores Leanstral proofs (upgrade path from fixpoint-only to Leanstral)
  - JSON format in `~/.llmll/proof-cache.json`
  - Lookup key: obligation hash (SHA256 of obligation expression)

- Memory-only caches during compilation (not persisted):
  - TypeCheck environment caching (reduce re-elaboration)
  - Contract environment caching (reuse obligation mining)
  - Alias map caching (symbol resolution)

## Authentication & Identity

**Serve Endpoint Auth:**
- Type: Bearer token (custom, not OAuth)
- Implementation: `compiler/src/LLMLL/Serve.hs::withAuth`
- Generation: Auto-generated on startup (random 4-word 16-digit hex, prefixed `sk-`)
  - Stored in `~/.llmll/sketch.token` for agent reuse
  - Can be supplied via `--token` flag or disabled with `--token ""`
- Endpoints:
  - GET /health: No auth required
  - POST /typecheck, POST /sketch, POST /checkout, POST /checkout/release, POST /patch: Auth required
- Default binding: 127.0.0.1:7777 (localhost only; TLS delegated to reverse proxy)

## Monitoring & Observability

**Error Tracking:**
- None — errors logged to stderr only

**Logs:**
- Stderr: Human-readable diagnostics, token generation, warnings
- Stdout: JSON output when --json flag used
- Event logs (optional): JSONL format written during `test` runs
  - Captured via `compiler/src/LLMLL/Replay.hs::parseEventLog`
  - Replayed with `--replay` flag for deterministic re-execution
- Trust reports: JSON or text output (--trust-report flag)
  - Includes verification tier, refutation evidence, proof caching status
- Proof artifacts: Unified reproducible record (--proof-artifact flag)
  - LCF anti-laundering guard (sanitizeProof) prevents sorry-smuggling

## CI/CD & Deployment

**Hosting:**
- Docker registry: ghcr.io (GitHub Container Registry)
  - Triggered on version tags (vX.Y.Z)
  - Multi-stage build: builder (haskell:9.6.6) + runtime (debian:bookworm-slim)
  - Acceptance gate: Runs `scripts/tests/docker-acceptance.sh` on PRs
    - Verifies `conserve-bad.llmll` refutes (exit 1)
    - Verifies `conserve.llmll` verifies (exit 0)

- GitHub Pages: Static site hosted from `site/` (Jekyll-based)
  - Workflow: `.github/workflows/pages.yml`
  - Publishes blog and documentation
  - Blog content moved from docs/blog/ to site/blog/

**CI Pipeline:**
- GitHub Actions (three workflows)
  - `version-gate.yml`: Fast gates (C1-C4 banner/schema + DRIFT-DOC-3/4), pytest harness
    - No Stack build in this job (drift gates only)
    - Runs `scripts/version_gate.sh` for doc consistency checks
  - `docker-publish.yml`: Image build + push
    - build-test job: On PR/push, no push to registry
    - publish job: On vX.Y.Z tag, pushes to ghcr.io
  - `pages.yml`: Deploy static site on push to main

**Secrets Management:**
- GitHub: Stores LLMLL_LEANSTRAL_API_KEY as repository secret (accessible in CI)
- Local dev: Read from environment (LLMLL_LEANSTRAL_API_KEY)
- Never in git history; .env file ignored but present for local config

## Environment Configuration

**Required env vars:**
- `LLMLL_LEANSTRAL_API_KEY` — Mistral API key (if using `--leanstral` flag)

**Optional env vars (inferred from code):**
- `PATH` — Must include `fixpoint` (liquid-fixpoint binary) for `verify` subcommand
- `PATH` — Must include `z3` (SMT solver) for `verify` subcommand
- `HOME` — Token file written to `$HOME/.llmll/sketch.token`
- `TEMP` or `TMP` — System temp dir for intermediate files

**Secrets location:**
- GitHub Actions: Repository secrets (LLMLL_LEANSTRAL_API_KEY)
- Local: Environment variable or .env file (not committed)
- Docker: Passed via build args or environment at runtime (not baked into image)

## Webhooks & Callbacks

**Incoming (Serve Endpoint):**
- `GET /health` — Health check (no body required)
  - Returns: `{"status": "ok", "version": "X.Y.Z"}`

- `POST /typecheck` — Full type-checking
  - Body: LLMLL S-expression or JSON-AST
  - Content-Type: application/json (JSON-AST) or text/plain (S-expression)
  - Returns: `{"success": true/false, "diagnostics": [...]}`

- `POST /sketch` — Sketch inference (hole type inference)
  - Body: LLMLL S-expression or JSON-AST with holes
  - Returns: `{"holes": [{"name": "h1", "type": "int", "status": "OPEN", ...}], ...}`

- `POST /checkout` — Lock a hole for exclusive editing
  - Body: `{"file": "<source.ast.json>", "pointer": "<JSON-Pointer>"}`
  - Returns: `{"token": "checkout-<uuid>", "locked_by": "...", "expires_at": "..."}`
  - Concurrent checkouts: Rejected if pointer already locked

- `POST /checkout/release` — Unlock a hole
  - Body: `{"file": "<source>", "token": "<checkout-token>"}`
  - Returns: `{"released": true}`

- `POST /patch` — Apply RFC 6902 JSON-Patch
  - Body: `{"source": "<ast.json>", "patch": [{"op": "replace", "path": "/...", "value": ...}]}`
  - Returns: `{"patched": "<updated-ast.json>", "diagnostics": [...]}`

**Outgoing:**
- None — LLMLL is passive; agents call the serve endpoint, not the reverse
- Event log replay: Deterministic re-execution uses captured event logs (not webhooks)

## Integration Patterns

**Multi-Agent Orchestration:**
1. Lead Agent (`tools/llmll-orchestra/llmll_orchestra/lead_agent.py`) calls Claude API
   - Intent → Architecture plan (JSON)
2. Agents receive plan + checkout lock
3. Agents call `POST /checkout` to lock a hole
4. Agents call `POST /sketch` to infer hole type
5. Agents generate code + call `POST /patch` to apply fill
6. Agents call `POST /checkout/release` to unlock

**Proof Generation (Leanstral):**
1. `llmll verify --leanstral <file.llmll>`
2. Emits `.fq` constraints via liquid-fixpoint backend
3. For unsolved constraints, calls Mistral API (proveWithLeanstral)
4. Extracts Lean code, runs anti-laundering guard (sanitizeProof)
5. Executes `lake env lean --run` to kernel-check proof
6. Upgrades proof cache if successful (upgradeLeanstralPosts)

**Verification Caching:**
1. Check `~/.llmll/verified/<hash>.json` before compilation
2. If hit, load cached verification (deterministic reuse)
3. If miss, run full verification, save to sidecar
4. Proof cache lookup: SHA256(obligation) → Leanstral proof JSON

---

*Integration audit: 2026-07-30*
