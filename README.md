# LLMLL — v0.13.7

**AI writes the code; the compiler proves it matches the spec — and rejects a type-correct-but-wrong implementation before it merges.**

LLMLL (Large Language Model Logical Language) is a language and verification pipeline whose primary author is an LLM agent, not a human. Agents coordinate through formal contracts the compiler enforces — not through conversation. An agent can *hallucinate* an implementation and that's fine, as long as it satisfies the contract: verification turns hallucination from a failure mode into a search strategy (generate a candidate, check it against the spec, accept or reject).

> **Current version:** see [`CHANGELOG.md § Latest`](CHANGELOG.md#Latest). Full release notes per version live in CHANGELOG; this README does not duplicate them.

---

## See it: a bug that type-checks, caught anyway

An agent fills a `?hole` for `withdraw(balance, amount)`. The fill below is **type-correct** (`int + int → int`) and passes example tests — but it *adds* the amount instead of subtracting it. Types and tests miss it; the SMT solver does not:

```text
# fill:  (+ balance amount)      ← type-correct, wrong
$ llmll patch demo.ast.json patch-wrong.json
{
  "result": "PatchVerifyError",
  "message": "body verification of 'withdraw' failed —
              implementation does not satisfy postcondition (constraint #0)"
}

# fill:  (- balance amount)      ← correct
$ llmll patch demo.ast.json patch-correct.json
{ "result": "PatchSuccess" }
```

The gate **fails closed**: a patch that doesn't verify never lands. That is the whole pitch in ten lines — every other tool merges code that type-checks; LLMLL proves it wrong first.

<!-- TODO: refutation GIF — 60–90s asciinema of this loop (type-correct fill → verify REFUTES → fix → accepted) -->
*(A 60–90s screen capture of this loop will live here.)*

Full copy-pasteable walkthrough: [`DEMO-RUNBOOK.md`](examples/withdraw-demo/DEMO-RUNBOOK.md) (commands verified against `llmll 0.13.7`) · narrated version: [`DemoPost.md`](examples/withdraw-demo/DemoPost.md). A richer **payments-core** demo — conservation across a verified call chain ("money can't be created on the overdraft branch") — becomes the flagship once it lands.

---

## Try it

The full repair loop (hole → rejected bad fills → accepted fix → verified) is the copy-pasteable [`DEMO-RUNBOOK.md`](examples/withdraw-demo/DEMO-RUNBOOK.md). Build first:

```bash
cd compiler && stack build
stack exec llmll -- --help
```

Requires GHC ≥ 9.4 + Stack ≥ 2.9. The proof step also needs `z3` + `liquid-fixpoint`.

> **`verify` is loud without the solver.** With `z3`/`liquid-fixpoint` absent it prints a `SOLVER NOT FOUND — NOTHING WAS PROVEN` banner and exits `3` (not a silent pass) — install both to see the refutation. See [`docs/getting-started.md`](docs/getting-started.md).

---

## What it is

LLMLL treats **verification as the coordination protocol**. A lead agent defines types and contracts (the *what*); specialist agents fill typed holes with the *how*; the compiler verifies each fill against its contract before merging. Agents trust each other's *contracts*, not each other's *code*. Merges are structured JSON-AST patches, not text diffs — so there are no structural merge conflicts, and every patch is re-verified before it lands.

**It does not claim program correctness.** It guarantees that all code is *consistent with its declared specifications*, and it tracks how strong each guarantee is: a `verified` contract was proven by the SMT solver; an `asserted` one was not. Trust propagates — no `verified` claim silently rests on an unproven dependency. The weakness checker (`--weakness-check`) even flags a contract so weak that a trivial implementation satisfies it.

---

## What's proven vs. not — read this before believing the headline

The **shipped** proof path is SMT (Z3 via liquid-fixpoint) over a non-recursive **QF-LIA core**: integer linear arithmetic, let-bindings, conditionals, calls to contracted functions (assume-guarantee), and 2-arm `Result` matches. That covers numeric bounds, conservation invariants, and length preservation. Everything else — strings, general recursion, non-`Result` ADTs, non-linear arithmetic (`* / mod`), IO — **falls back** to contract-only checking, property tests, or runtime assertions, each carrying an explicit trust label (full matrix below and in [`LLMLL.md §5.3.5`](LLMLL.md)).

An interactive proof path for the rest (Lean 4 via "Leanstral" MCP) is **designed but not shipped** — it runs in mock mode only (`--leanstral-mock`), blocked on external availability.

[`docs/one-pager.md`](docs/one-pager.md) carries the full **Claim-to-Evidence map** — every claim mapped to a shipped command or an explicit "Planned"/"Not shipped" label. The scope-honesty is deliberate; read it before sharing.

---

## Compiler

The active compiler is a **Haskell stack project** in `compiler/`. It is the only supported backend as of v0.2.

| Command | What it does |
|---------|--------------| 
| `llmll check <file> [--strict]` | Parse + type-check; emit structured diagnostics. With `--strict`: unbound variables, unknown functions, unknown operators, and branch type mismatches are hard errors instead of warnings. Without `--strict`: text mode renders accumulated warnings on success (v0.10.2). |
| `llmll holes <file> [--deps] [--deps-out FILE]` | List all `?hole` expressions. With `--deps`: include dependency graph in `--json` output. With `--deps-out`: persist graph to file. |
| `llmll test <file>` | Run property-based tests (`check`/`for-all` blocks via QuickCheck) |
| `llmll build <file> [-o <dir>]` | Generate a Haskell package (`src/Lib.hs` + `package.yaml` + `stack.yaml`). Accepts both `.llmll` S-expression and `.ast.json` JSON-AST sources. |
| `llmll verify <file> [--fq-out FILE] [--leanstral-mock] [--trust-report] [--weakness-check] [--obligations] [--obligation-report] [--spec-coverage] [--strict-verified-core] [--cdp]` | Emit `.fq` constraint file and run `liquid-fixpoint` (if installed). With `--leanstral-mock`, also runs Leanstral proof pipeline on `?proof-required` holes. With `--trust-report`, prints per-function trust summary with transitive closure, epistemic drift warnings, and `weakness-ok` suppressions (note: `--trust-report` reloads persisted evidence **instead of running fixpoint**, so a solver-refutable function renders as `asserted`, not `refuted` — use the default `verify` or `--strict-verified-core` to surface `refuted`). With `--weakness-check`, detects specs that admit trivial implementations. With `--obligations`, suggests postcondition strengthening when UNSAFE at cross-function boundaries. With `--obligation-report`, emits structured JSON obligation report for every hole, unproven contract, and failed call-site precondition (v0.10.0). With `--spec-coverage`, classifies every function and computes effective specification coverage ratio. With `--strict-verified-core`, hard-errors if any function falls back from body-faithful verification, carries overflow-tainted verified evidence, or is refuted (body-faithful but disproved by the solver), transitively over the call graph (v0.9.0 + INT-1 v0.10.8 + VERIFY-RPT-1 v0.11). With `--cdp`, computes contract discriminative power per function (LT-CDP v0.11): emits a paired `discriminative_axis` block in the trust-report JSON alongside the existing diamond-lattice evidence axis. |
| `llmll typecheck --sketch <file>` | Partial-program type inference. Returns inferred type for every `?hole` plus `holeSensitive`-annotated errors and `invariant_suggestions` from the pattern registry. |
| `llmll serve [--host H] [--port P] [--token T]` | Expose `--sketch` as `POST /sketch` HTTP endpoint for agent swarms. Default: `127.0.0.1:7777`. |
| `llmll checkout <file.ast.json> <pointer>` | Lock a `?hole` for exclusive agent editing. Returns a checkout token with the hole's contract context (`contract_pre`, `postcondition_goal`, `path_condition`) and typing context (`in_scope`, `type_definitions`). Use `--release` to abandon, `--status` to query TTL. |
| `llmll patch <file.ast.json> <patch.json>` | Apply an RFC 6902 JSON-Patch to a checked-out hole. Re-verifies type safety before committing. |
| `llmll hub fetch <pkg>@<ver>` | Download a package into the hub cache (`~/.llmll/modules/`). |
| `llmll hub scaffold <template> [--output DIR]` | Generate a project from a `llmll-hub` skeleton template (`~/.llmll/templates/`). |
| `llmll hub query --signature <sig>` | Search hub cache for functions matching a type signature (e.g. `"int -> int -> int"`). |
| `llmll replay <source> <log>` | Rebuild program, replay event log inputs, compare outputs for determinism verification. |
| `llmll spec [--json]` | Emit agent prompt specification from compiler builtins. Text (default) or JSON output. |
| `llmll version` | Print compiler version and exit. Supports `--json` for `{"version":"…"}` output. Also available as `llmll --version`. |
| `llmll repl` | Start an interactive LLMLL REPL |

### Input formats

Both source formats compile to identical AST nodes:

| Format | Extension | Best for |
|--------|-----------|----------|
| S-expressions | `.llmll` | Human editing, concise iteration |
| JSON-AST | `.ast.json` | AI agents — schema-constrained, structurally valid by construction |

The JSON-AST schema is at `docs/llmll-ast.schema.json`.

### Build the compiler

Requires GHC ≥ 9.4 + Stack ≥ 2.9.

```bash
cd compiler
stack build
stack exec llmll -- --help
```

→ Full build guide and known-good patterns: [`docs/getting-started.md`](docs/getting-started.md)

---

## Quick start

```bash
cd compiler

# Check the example
stack exec llmll -- check ../examples/hangman_sexp/hangman.llmll

# Build a Haskell package in generated/hangman_sexp
stack exec llmll -- build ../examples/hangman_sexp/hangman.llmll -o ../generated/hangman_sexp

# Build from JSON-AST
stack exec llmll -- build ../examples/hangman_json/hangman.ast.json -o ../generated/hangman_json

# Run the generated game
cd ../generated/hangman_json && stack build && stack exec hangman
```

---

## Verification Boundary

LLMLL provides body-faithful SMT verification for a **non-recursive QF-LIA core** with **compositional call-chain reasoning** (v0.9.0): integer literals, integer-typed variables, simple let-bindings, conditionals, function calls to contracted functions (assume-guarantee), `Result` pattern matching, and linear arithmetic (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`, `!=`). Programs outside that fragment fall back to contract-only verification, property-based testing, or runtime assertions with explicit trust labels.

| Construct | SMT body-faithful | Fallback |
|---|---|---|
| `ELit`, `EVar` (int) | ✅ | — |
| `EOp` (+, -, =, <, <=, >=, >, !=) | ✅ | — |
| `ELet` (PVar, int RHS) | ✅ | — |
| `EIf` (≤4096 paths) | ✅ (path-split) | — |
| `EApp` (contracted callee) | ✅ (v0.9.0 assume-guarantee) | — |
| `EApp` (uncontracted / recursive self) | ❌ | contract-only |
| `EMatch` on `Result` (2-arm) | ✅ (v0.9.0 two-path) | — |
| `EMatch` (general ADT), `EPair`, `ELambda`, `EDo` | ❌ | runtime |
| `letrec` (own body VC) | ❌ | runtime + `:decreases` |
| Non-linear ops (*, /, mod) | ❌ | runtime + `?proof-required` |
| **Int overflow** | ⚠ | Z3 `Int` ≠ Haskell `Int64` |

> **Integer overflow model gap:** Z3 reasons over mathematical integers; Haskell `Int` wraps at 2⁶³. Contracts proven in the solver may not hold at overflow boundaries.

Full verification matrix: [`LLMLL.md §5.3.5`](LLMLL.md).

---

## Examples

### Verification demos (`llmll verify`)

| Demo | What it proves |
|------|----------------|
| [`examples/tcp_rfc793/`](examples/tcp_rfc793/) | RFC 793 connection state machine reaches `verified` on legal-successor safety; `step-bad` is `refuted` |
| [`examples/payments-core/`](examples/payments-core/) | Verified `transfer` over a `debit` call edge (no-overdraw); `settle` is the COMP-3b `Result`-match return |
| [`examples/session-pay/`](examples/session-pay/) | Connected demo: protocol state-safety + verified payment + bounded amount in one `verified` function |
| [`examples/nested-result/`](examples/nested-result/) | A nested `Result`-variable match (under `let`) reaches `verified` — the COMP-3b-general showcase |
| [`examples/banking_ledger/`](examples/banking_ledger/) | Three-level assume-guarantee chain (`transfer → withdraw → safe-subtract`), all verified |
| [`examples/withdraw-demo/`](examples/withdraw-demo/) | The repair loop (hole → rejected bad fills → accepted fix → verified) + the `return-refine` beat |

### Language / runtime examples

| Example | Format | Description |
|---------|--------|-------------|
| `examples/hangman_sexp/` | S-expression | Full Hangman game with ASCII gallows art; uses `def-main :mode console` |
| `examples/hangman_json/` | JSON-AST | Same program, JSON-AST schema-constrained version |
| `examples/tictactoe_sexp/` | S-expression | Two-player Tic-Tac-Toe; demonstrates `:done?` + `:on-done` |
| `examples/tictactoe_json/` | JSON-AST | Same Tic-Tac-Toe program in JSON-AST format |
| `examples/life_sexp/` | S-expression | Conway's Game of Life; multi-module (`core`, `world`, `main`) |
| `examples/life_json/` | JSON-AST | Same Life program in JSON-AST format |
| `examples/withdraw.llmll` | S-expression | Simple withdraw with `pre`/`post` contracts; acceptance gate |
| `examples/hangman_json_verifier/` | JSON-AST | Hangman with verified `apply-guess` contracts (`llmll verify`) |
| `examples/tictactoe_json_verifier/` | JSON-AST | Tic-Tac-Toe with verified `set-cell` contracts |
| `examples/conways_life_json_verifier/` | JSON-AST | Conway's Life with verified `count-neighbors` and `next-cell` contracts |
| `examples/pair_type_test/` | Mixed | TPair type system and do-notation test fixtures |
| `examples/event_log_test/` | S-expression | v0.3.1 event log codegen validation |
| `examples/proof_required_test/` | S-expression | v0.3.1 Leanstral proof pipeline validation |
| `examples/erc20_token/` | JSON-AST | v0.6.0 ERC-20 benchmark — frozen ground truth with verification-scope matrix |
| `examples/totp_rfc6238/` | JSON-AST | v0.6.1 TOTP RFC 6238 benchmark — crypto builtins, RFC `:source` provenance |

---

## Repository layout

```
LLMLL.md                    ← canonical language specification
CHANGELOG.md                ← release notes
compiler/                   ← Haskell compiler (stack project)
  src/LLMLL/
    Parser.hs               ← S-expression parser (Megaparsec)
    Lexer.hs                ← Megaparsec lexer (tokens, whitespace, layout)
    ParserJSON.hs           ← JSON-AST parser
    Syntax.hs               ← AST types (incl. ModulePath, ModuleEnv, ModuleCache, TPair — v0.3)
    TypeCheck.hs            ← Bidirectional type checker
    HoleAnalysis.hs         ← Hole collector (?hole expressions)
    CodegenHs.hs            ← Haskell code emitter
    AstEmit.hs              ← JSON-AST emitter (--emit json-ast round-trip)
    Contracts.hs            ← Runtime contract assertion generator
    PBT.hs                  ← QuickCheck property runner
    Diagnostic.hs           ← Structured error/warning types
    Module.hs               ← Multi-file module resolver, cycle detection, ModuleCache
    Hub.hs                  ← llmll-hub registry fetch, scaffold, and local cache
    Sketch.hs               ← Partial-program type inference (--sketch)
    Serve.hs                ← HTTP endpoint for agent swarms (llmll serve)
    FixpointIR.hs           ← D4: .fq constraint IR + text emitter
    FixpointEmit.hs         ← D4: typed AST → .fq + ConstraintTable builder
    DiagnosticFQ.hs         ← D4: liquid-fixpoint output → [Diagnostic] with JSON Pointers
    Replay.hs               ← v0.3.1: JSONL event log parser + replay execution
    LeanTranslate.hs        ← v0.3.1: LLMLL contracts → Lean 4 theorem obligations
    MCPClient.hs            ← v0.3.1: MCP JSON-RPC client (mock-first)
    ProofCache.hs           ← v0.3.1: per-file .proof-cache.json sidecar (SHA-256)
    TrustReport.hs          ← v0.3.2: transitive trust closure analysis (--trust-report)
    VerifiedCache.hs        ← v0.3: .verified.json sidecar read/write
    WeaknessCheck.hs        ← v0.3.5: trivial-body spec weakness detection
    InvariantRegistry.hs    ← v0.4.0: pattern-based invariant suggestion database
    ObligationMining.hs     ← v0.4.0: downstream postcondition strengthening suggestions
    ObligationAssembly.hs   ← v0.10.0: structured obligation report assembly + JSON encoding
    GuardClassifier.hs      ← v0.10.0: shared guard classification (verifier + obligations)
    SpecCoverage.hs         ← v0.6.0: specification coverage metric + governance guardrails
    JsonPointer.hs          ← RFC 6901 pointer resolution + descendant hole search
  package.yaml / stack.yaml
examples/
  hangman_sexp/             ← Full Hangman (S-expression)
  hangman_json/             ← Full Hangman (JSON-AST)
  tictactoe_sexp/           ← Tic-Tac-Toe (S-expression)
  tictactoe_json/           ← Tic-Tac-Toe (JSON-AST)
  life_sexp/                ← Conway's Life (S-expression, multi-module)
  life_json/                ← Conway's Life (JSON-AST, multi-module)
  withdraw.llmll            ← Contract demo
  hangman_json_verifier/    ← Hangman with verified contracts
  tictactoe_json_verifier/  ← Tic-Tac-Toe with verified contracts
  conways_life_json_verifier/ ← Life with verified contracts
  erc20_token/              ← v0.6.0 ERC-20 benchmark (frozen ground truth)
  totp_rfc6238/             ← v0.6.1 TOTP RFC 6238 benchmark
  benchmarks/               ← v0.10.0 OBLIG-B benchmark suite (B1/B3/B5)
  withdraw-demo/            ← flagship repair-loop demo: holes → checkout/patch → two-axis trust + composition (see "See it in action")
  pair_type_test/           ← TPair + do-notation test fixtures
  orchestrator_walkthrough/ ← Auth module orchestration exercise
docs/
  UPDATE-PROTOCOL.md        ← Doc canonical-sources + per-change update matrix (DOC-CONSOLIDATE D1)
  getting-started.md        ← Build guide, known-good patterns, schema versioning
  compiler-team-roadmap.md  ← Engineering backlog and shipped-releases history
  llmll-ast.schema.json     ← JSON-AST schema v0.6.0 (use with AI agents; CheckoutToken introduced v0.3.0; CheckDecl.subjects introduced v0.5.0)
  orchestrator-walkthrough.md ← End-to-end orchestration walkthrough
  one-pager.md              ← Project overview / pitch document
  design/                   ← Active design proposals (status in design/INDEX.md)
    INDEX.md                ← Reading guide for active design documents
  archive/                  ← Superseded design specs, shipped proposals, professor reviews, wasm investigations
tools/
  llmll-orchestra/          ← Python orchestrator (pip package)
    llmll_orchestra/
      orchestrator.py       ← Fill-mode orchestrator
      lead_agent.py         ← v0.4.0: Lead Agent skeleton generation (plan/lead/auto modes)
      quality.py            ← v0.4.0: Skeleton quality heuristics
      agent.py              ← LLM agent interface
      compiler.py           ← Compiler CLI wrapper
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [`LLMLL.md`](LLMLL.md) | Full language specification — types, syntax, FFI, grammar, builtins |
| [`docs/getting-started.md`](docs/getting-started.md) | Build guide + known-good patterns + schema versioning (single reference for agents) |
| [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) | Engineering backlog and shipped-releases history (current version in [CHANGELOG § Latest](CHANGELOG.md#Latest)) |
| [`docs/llmll-ast.schema.json`](docs/llmll-ast.schema.json) | Machine-readable JSON-AST schema |
| [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) | Doc canonical-sources table and per-change update matrix (DOC-CONSOLIDATE D1) |
| [`docs/orchestrator-walkthrough.md`](docs/orchestrator-walkthrough.md) | End-to-end multi-agent orchestration walkthrough with auth module exercise |
| [`docs/one-pager.md`](docs/one-pager.md) | Project overview — problem, approach, status, related work |
| [`docs/design/INDEX.md`](docs/design/INDEX.md) | Reading guide for all active design documents |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes by version |

---

## License

GPLv3 with LLMLL Runtime Library Exception — see [`LICENSE`](LICENSE).
