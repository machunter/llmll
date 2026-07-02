# LLMLL Getting Started

> This document is the single reference for building and running LLMLL programs,
> understanding what patterns work in the current compiler, and the JSON-AST schema versioning policy.
> If you find contradictions between this file and older documentation, this file takes precedence.

---

## Part 1 — Build the Compiler

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| GHC + Stack | `ghc >= 9.4`, `stack >= 2.9` | Build compiler and generated Haskell code |
| `fixpoint` + `z3` | any stable | **Optional** (`verify` command only): `stack install liquid-fixpoint` then `brew install z3` |

**Install Stack:** <https://docs.haskellstack.org/en/stable/install_and_upgrade/>

```bash
git clone <repo-url> llmll && cd llmll/compiler
stack build
stack exec llmll -- --help
```

Expected output:

```bash
llmll — AI-to-AI programming language compiler

Usage: llmll [--version] COMMAND [--json] [--grammar MODE]

  LLMLL — Large Language Model Logical Language Compiler (v0.14.4)

Available options:
  -h,--help                Show this help text
  --version                Print compiler version and exit
  --json                   Output diagnostics as JSON
  --grammar MODE           Grammar mode: core-inversion (default) or legacy
                           (backward-compatible grammar)

Available commands:
  check                    Parse and type-check a .llmll or .ast.json file
  holes                    List and classify all holes in a .llmll file
  test                     Run property-based tests (check blocks)
  build                    Compile .llmll to Haskell; use --emit json-ast to
                           emit JSON-AST instead
  build-json               Compile a .ast.json file (JSON-AST) — same as build
                           but from JSON input
  run                      Compile and immediately run an LLMLL program
                           (requires def-main)
  repl                     Start an interactive LLMLL REPL
  hub                      Manage llmll-hub local package cache (fetch,
                           scaffold)
  verify                   Emit .fq constraints and run liquid-fixpoint (if
                           installed)
  typecheck                Parse and type-check; with --sketch infer hole types
                           from context
  serve                    Start HTTP server on 127.0.0.1:7777 for AI agent
                           integration
  checkout                 Lock a hole for exclusive editing
                           (checkout/release/status)
  patch                    Apply an RFC 6902 JSON-Patch to a checked-out hole
  replay                   Replay an event log against a compiled program
  replay-artifact          Re-derive and check a recorded verification artifact
                           (fail-closed)
  spec                     Emit agent specification from compiler builtins
  version                  Print compiler version and exit
```

> [!NOTE]
> The `build` line above literally says "Compile .llmll to Rust" — that's a stale leftover from an early Rust-codegen prototype in the compiler's own `--help` text; actual `build` behavior is Haskell codegen (see [`build`](#build--generate-haskell) below). Tracked as a compiler bug, not a doc error.

---

## Part 2 — Compiler Commands

All commands run from the `compiler/` directory.

### `check` — parse and type-check

```bash
stack exec llmll -- check ../examples/withdraw.llmll
# ✅ ../examples/withdraw.llmll — OK (4 statements)

stack exec llmll -- --json check ../examples/withdraw.llmll
# {"diagnostics":[...],"phase":"typecheck","success":true}
```

### `holes` — inspect holes

```bash
stack exec llmll -- holes ../examples/hangman_json/hangman.ast.json
# examples/hangman_json/hangman.ast.json — 0 holes (0 blocking)
```

| Label | Meaning |
| ------- | --------- |
| `BLOCK` | Execution cannot proceed — must be filled |
| `AGENT` | Delegated to a specialist agent |
| `info` | Non-blocking TODO |

#### `--deps` — dependency graph

Add `--deps` to `--json` output to include a dependency graph between holes.
The orchestrator uses this for topological sorting and parallel scheduling.

```bash
stack exec llmll -- --json holes --deps program.llmll
```

Each hole entry gains two additional fields:

```json
{
  "pointer": "/statements/2/body",
  "kind": "delegate",
  "agent": "@crypto-agent",
  "depends_on": [
    { "pointer": "/statements/0/body",
      "via": "hash-password",
      "reason": "calls-hole-body" }
  ],
  "cycle_warning": false
}
```

- `depends_on`: annotated edges — which holes this hole depends on, why, and via which function
- `cycle_warning`: `true` if this hole was in a broken dependency cycle (mutual recursion)

Only `AgentTask` and `Blocking` body-level holes participate in the graph.
`?proof-required` holes and contract-position holes (`pre`/`post`) are excluded.

#### `--deps-out FILE` — persist dependency graph

```bash
stack exec llmll -- --json holes --deps --deps-out deps.json program.llmll
```

Writes the full JSON output (with dependency data) to `deps.json`. Implies `--deps`.

### `test` — property-based tests

```bash
stack exec llmll -- test ../examples/hangman_json/hangman.ast.json
# ../examples/hangman_json/hangman.ast.json — 0 properties
#   ✅ Passed:  0
#   ❌ Failed:  0
#   ⚠️  Skipped: 0
```

Properties are skipped when they contain `Command`-producing expressions that cannot be statically evaluated.
The skip message names which case applies.

> [!IMPORTANT]
> **Stack lock deadlock** — same lock issue as `build`. Use `--emit-only` to generate the QuickCheck Haskell without running `stack test`:
>
> ```bash
> stack exec llmll -- test hangman.ast.json --emit-only
> #    src/Lib.hs -- 10344 chars
> #    (stack test skipped — --emit-only)
> ```

### `build` — generate Haskell

```bash
# S-expression source
stack exec llmll -- build ../examples/withdraw.llmll

# JSON-AST source (auto-detected by .json or .ast.json extension)
stack exec llmll -- build ../examples/hangman_json/hangman.ast.json -o ../generated/hangman_json
```

> [!IMPORTANT]
> **Stack lock deadlock** — if you have a long-running `stack exec llmll -- repl` terminal open, `llmll build` will deadlock because both try to hold the Stack project lock. Use `--emit-only` to skip the internal `stack build` and run it separately:
>
> ```bash
> # Step 1: write Haskell files only (no stack build)
> stack exec llmll -- build hangman.ast.json -o ../generated/hangman_json --emit-only
>
> # Step 2: build independently
> cd ../generated/hangman_json && stack build
> ```

Output layout:

```bash
generated/hangman_json/
  package.yaml     ← hpack descriptor
  stack.yaml       ← GHC 9.6.6 pin
  src/Lib.hs       ← all def/def-shell, types, builtins preamble
  src/Main.hs      ← runtime harness (only if def-main present)
```

```bash
cd generated/hangman_json && stack build && stack exec hangman
```

### `hub` — package registry

> [!IMPORTANT]
> **This registry is local-tarball-only.** There is no registry-by-name fetch (`llmll hub fetch <pkg>@<ver>` does not exist); HTTPS registry fetch is not supported. The only supported form is installing a local `.tar.gz`:

```bash
# Install a local tarball into the cache (~/.llmll/modules/)
llmll hub fetch --from-file ./llmll-crypto-0.1.0.tar.gz

# Intended cache layout after fetch (tarball's top-level <package>-<version>/
# directory is meant to be stripped on install):
# ~/.llmll/modules/llmll-crypto/0.1.0/
#   hash/bcrypt.ast.json
#   hash/bcrypt.llmll
```

```bash
# Scaffold a new project from a hub skeleton template
llmll hub scaffold web-api-server --output ./my-project
# Template 'web-api-server' not found in ~/.llmll/templates/.
# Install with: llmll hub fetch --from-file <tarball>
```

No scaffold templates ship with the compiler — `hub scaffold` only works once you've fetched a template package yourself via `hub fetch --from-file`.

Import fetched packages using the `hub.` prefix (see §4.9).

```bash
# Query the hub for functions matching a type signature
llmll hub query --signature "int -> int -> int"
# Results:
#   llmll-math.arithmetic.add : int -> int -> int [contracted]
#   llmll-math.arithmetic.mul : int -> int -> int [contracted]

# JSON output for tooling:
llmll hub query --signature "list[int] -> int" --json
# {"query": "list[int] -> int", "results": [{"module": "...", ...}]}
```

> [!NOTE]
> **Type matching semantics:** Query type variables (single letters like `a`, `b`) act as wildcards — `list[a] -> a` matches `list[int] -> int`. `TDependent` constraints are stripped before matching. Parameter order is significant: `int -> string` does not match `string -> int`.

> [!NOTE]
> **Known limitation:** The CLI signature parser handles base types (`int`, `string`, `bool`), `bytes[N]`, `list[T]`, and single-letter type variables. Compound types like `Result[T, E]` and `map[K, V]` are not supported in query signatures — use simpler queries and filter results manually. Compound types in shell arguments may need quoting: `--signature "map[string, int]"`.

### `verify` — liquid-fixpoint contract verification

```bash
# Verify linear arithmetic pre/post contracts at compile time:
stack exec llmll -- verify ../examples/hangman_sexp/hangman.llmll
#    .fq written to /tmp/hangman.fq
#    Running liquid-fixpoint ...
# ✅ hangman.llmll — SAFE (liquid-fixpoint)

# Emit .fq only, specify output path:
stack exec llmll -- verify file.llmll --fq-out out.fq

# JSON output:
stack exec llmll -- --json verify file.llmll

# Run Leanstral proof pipeline on ?proof-required holes (mock mode):
stack exec llmll -- verify file.llmll --leanstral-mock
# Runs liquid-fixpoint first, then scans for ?proof-required holes,
# translates to Lean 4 obligations, resolves via mock prover,
# caches results in .proof-cache.json.

# Leanstral with custom command and timeout:
stack exec llmll -- verify file.llmll --leanstral-cmd /path/to/lean-lsp-mcp --leanstral-timeout 60

# Trust report — transitive trust closure with epistemic drift detection
# (run plain `verify` first so the .verified.json sidecar is warm — see NOTE below):
stack exec llmll -- verify file.llmll
stack exec llmll -- verify file.llmll --trust-report
# Trust Report
# ────────────────────────────────────────────────────────────
#   withdraw:
#     pre:  asserted  |  post: verified (liquid-fixpoint)
#     ↳ calls auth.verify-token (pre: —, post: asserted)
#     ⚠ withdraw is verified, but depends on auth.verify-token which is asserted
# ────────────────────────────────────────────────────────────
# Summary:
#   verified:         3
#   contract-checked: 0
#   tested:           1
#   asserted:         2
#   no contract:      5
#   ⚠ epistemic drifts: 1

# JSON trust report (for tooling consumption):
stack exec llmll -- verify file.llmll --trust-report --json

# NOTE: --trust-report reloads persisted evidence *instead of running fixpoint*.
# A function the solver would refute therefore renders as `asserted` under
# --trust-report, not `refuted`. To surface `refuted`, run the default `verify`
# (which runs fixpoint) or `verify --strict-verified-core`.

# Weakness check — detect specs that admit trivial implementations:
stack exec llmll -- verify file.llmll --weakness-check
# ✅ hangman.llmll — SAFE (liquid-fixpoint)
# ⚠ Spec weakness detected for `sort-list`:
#   Your contract: (post (= (list-length result) (list-length input)))
#   Trivial valid implementation: (def sort-list [input: list[int]] input)
#   Consider strengthening the postcondition.

# Contract Discriminative Power — counted spec-strength metric:
stack exec llmll -- verify file.llmll --cdp
# ✅ file.llmll — SAFE (liquid-fixpoint)
#    Running CDP measurement ...
#    CDP measured 3 function(s):
#    transfer: score=0.823 (3/14 candidates satisfy)
#    cache-lookup: [identity-satisfies-post, const-satisfies-post] score=0.000 (14/14 candidates satisfy)
#    increment: score=1.000 (1/12 candidates satisfy)

# CDP combined with trust-report JSON — pairs DP with the diamond-lattice evidence axis:
stack exec llmll -- --json verify file.llmll --cdp --trust-report

# Spec coverage — how much of your module is under contract:
stack exec llmll -- verify file.llmll --spec-coverage
# Spec Coverage Report
# ────────────────────────────────────────────
#   Functions with contracts:     4 / 7   (57%)
#     Verified:                   2
#     Contract-checked:           0
#     Tested:                     1
#     Asserted:                   1
#   Intentional Underspecification:
#     ⊘ cache-evict — "eviction policy is unspecified by design"
#   Unspecified:                  2
#     sort-list, validate-input
# ────────────────────────────────────────────
#   Effective coverage: 71% (5/7)

# JSON spec coverage (for CI gates / quality.py):
stack exec llmll -- verify file.llmll --spec-coverage --json
```

`--weakness-check` runs **after** a SAFE verification result. For each contracted function, it constructs trivial bodies (identity, constant-zero, empty-string, `true`, empty-list) and checks whether they also satisfy the contract. If any trivial body passes, the spec is flagged as potentially weak. This is advisory — it does not affect the verification outcome.

`--cdp` extends `--weakness-check`'s trivial-body enumeration from a binary "any trivial body passes?" check to a Shannon-normalized counted divergence metric (`DP_Ω(S) = 1 − log|⟦S⟧_Ω| / log|B|`) over the closed candidate set. A high-DP score means the contract is *discriminative* (rules out most observable behaviors); a low-DP score means the contract is *permissive* (admits trivial implementations). The `(spec-entropy :intentional)` annotation on a contract suppresses the low-DP diagnostic when permissiveness is the design (caches, schedulers, unspecified iteration order). The score is *observational* over the candidate set, not semantic — see [`LLMLL.md §4.4.6`](../LLMLL.md) for the load-bearing caveat. `--weakness-check`'s catalog and binary diagnostic surface are unchanged by `--cdp`; the two flags are orthogonal.

#### Spec coverage and the Verification-Scope Matrix

`--spec-coverage` classifies every function in a module as **contracted**, **suppressed** (via `weakness-ok`), or **unspecified**, then computes:

```
effective_coverage = (contracted + suppressed) / total_functions
```

| Classification | Meaning | Example |
|---|---|---|
| **Contracted** | Has at least one `pre` or `post` clause | `transfer` with conservation invariant |
| **Suppressed** | Has a `(weakness-ok name "reason")` declaration and no contracts | `cache-evict` — intentionally unspecified |
| **Unspecified** | No contract, no suppression | `render-board` — pure string rendering |

**Governance guardrails:**

| Warning code | Trigger |
|-------------|--------|
| `W601` | `weakness-ok` target doesn't match any function |
| `W602` | Function has contracts AND `weakness-ok` (contracts take priority) |
| `W603` | More than 50% of functions are suppressed |

**Quality gate thresholds** (in `quality.py`):

| Mode | Threshold | Effect |
|------|----------|--------|
| `--mode auto` | 60% | Blocking failure |
| `--mode lead` | 40% fail, 60% warn | Tiered response |

Each example with a JSON-AST verifier includes a `VERIFICATION_SCOPE.md` file documenting the per-function classification and verification boundary. See `examples/erc20_token/WALKTHROUGH.md` for the full end-to-end benchmark.

#### Clause-level provenance (`:source` annotation)

Contracts can carry a `:source` annotation linking each clause to an external standard or specification:

```lisp
(def-shell transfer [from: string to: string amount: int]
  (pre (>= amount 0)
    :source "ERC-20 §transfer — amount must be non-negative")
  (post (= (total-supply result) (total-supply state))
    :source "ERC-20 §transfer — conservation invariant")
  ?transfer-impl)
```

The annotation is pure metadata — no effect on type checking, verification, or codegen. It appears in `--trust-report` output and `.verified.json` sidecars.

JSON-AST equivalent: add `"pre_source"` / `"post_source"` optional string fields to the contract object.

When multiple `(pre ...)` clauses are combined (via `and`), the `:source` annotation is dropped (ambiguous provenance). Use a single `(pre ...)` with a combined expression when source traceability is needed.

#### Downstream obligation mining

When `llmll verify` reports UNSAFE at a cross-function boundary, the obligation miner extracts the unsatisfied constraint and suggests a postcondition strengthening on the callee:

```bash
stack exec llmll -- verify program.llmll
# ✗ Caller requires: uniqueIds(result)
#   Producer normalizeUsers does not guarantee this.
#   Candidate strengthening: postcondition uniqueIds(output)
```

This leverages existing `TrustReport.hs` transitive closure infrastructure and the new `ObligationMining.hs` module.

#### Obligation report

`--obligation-report` emits a structured JSON report for every hole, unproven contract, and failed call-site precondition. The report is designed for agent consumption — each obligation includes enough context for a mechanical repair procedure.

```bash
stack exec llmll -- verify file.llmll --obligation-report --json
# {
#   "schema_version": "0.12.1",
#   "source_file": "./file.llmll",
#   "cross_module": "single-file",
#   "obligations": [
#     {
#       "kind": "hole-obligation",
#       "function": "withdraw",
#       "origin": "/statements/0/body",
#       "type_channel": {
#         "expected_type": "unknown",
#         "in_scope": [
#           { "name": "balance", "source": "param", "type": "int" },
#           { "name": "amount", "source": "param", "type": "int" }
#         ],
#         "polymorphic": false
#       },
#       "contract_channel": {
#         "preconditions": ["(>= balance amount)"],
#         "postcondition_goal": "(= result (- balance amount))",
#         "path_condition": [],
#         "path_truncated": false,
#         "body_fragment": "hole_bearing",
#         "contract_fragment": "non_qf_lia",
#         "body_faithful_possible": false
#       },
#       "trust_channel": {
#         "effective_level": "asserted",
#         "body_faithful": false,
#         "assumptions": []
#       },
#       "suggestions": [],
#       "contracted_functions": [...],
#       "available_functions": [...]
#     }
#   ],
#   "refuted_fns": [],
#   "effect_summary": [...],
#   "summary": { "total": 1, "discharged": 1, "open": 0, "deferred": 0, "asserted": 0, "refuted": 0 }
# }
```

The three channels below are the three top-level keys on each obligation (`type_channel`, `contract_channel`, `trust_channel`) — `expected_type` is `"unknown"` here because `withdraw` has no `-> RetType` annotation (see §4.25); an annotated function reports the real type instead.

Three obligation channels:

| Channel | Question answered | Source |
|---|---|---|
| **Type obligations** | What shape must this expression have? | Type checker (`--sketch`) |
| **Contract obligations** | What logical property must it satisfy? | Verifier (liquid-fixpoint) |
| **Trust obligations** | What evidence is still missing? | Trust report (evidence model) |

**Branch obligations:** For `EMatch` expressions containing holes, each branch emits a sub-obligation with constructor-refined bindings and per-branch context. Linked to the parent hole obligation via `parent_id`.

**Repair suggestions:** For int-typed holes, the report includes arithmetic candidate expressions synthesized from in-scope variables (O(n²) bounded, cap-8).

**Function lists:** Each obligation includes `contracted_functions` (user-defined with compatible return type and trust labels) and `available_functions` (builtins with compatible signatures). Both lists are capped at 8 entries with truncation signals.

`verify` is **loud, not silent, when the solver is missing**: if `fixpoint` or `z3` is not on `PATH`, it still writes the `.fq` file, but prints a `SOLVER NOT FOUND — NOTHING WAS PROVEN` banner and **exits `3`** (distinct from `1` = refuted) — never a silent pass:

```
   .fq written to /tmp/hole-demo.fq
   body-fallback: withdraw

  ============================================================
  !!  SOLVER NOT FOUND -- NOTHING WAS PROVEN
  ============================================================
  'llmll verify' needs liquid-fixpoint + z3 to discharge proofs.
  Neither was found on PATH, so the contract was NOT checked.
  (This is not a pass -- no proof ran.)
  ...
  ============================================================
EXIT=3
```

The `.fq` file is still written and can be checked manually or in CI once the tools are installed, but do not treat exit `0`/no-error as a pass here — check the exit code, not just "did it crash." If `verify` exits `0` with the solver missing, you are not running the current compiler build.

> [!IMPORTANT]
> `verify` covers the **linear arithmetic fragment** only (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`). Non-linear constraints (`*`, `/`, `mod`) in `pre`/`post` automatically emit `?proof-required(non-linear-contract)` holes (see §4.11) and are skipped by the solver without error. Use `--leanstral-mock` or `--leanstral-cmd` to resolve these holes via the Leanstral proof pipeline.

#### Proof artifact

`--proof-artifact FILE` writes a single, self-contained, replayable verification record — the trust/obligation/`.fq`/sidecar surfaces plus determinism pins (solver version, codegen semantics version) — to `FILE`. `replay-artifact FILE` re-derives it: recomputes the source hash, re-runs the recorded VC under the pinned solver, and **fails closed** on any source/solver-determinism mismatch.

```bash
stack exec llmll -- verify file.llmll --proof-artifact ./file.proof.json
#    proof-artifact written to ./file.proof.json
# ✅ file.llmll — SAFE (liquid-fixpoint)

stack exec llmll -- replay-artifact ./file.proof.json
# ✅ replay reproduced verdict: RSafe
```

Top-level artifact fields: `proof_artifact_version`, `source_path`, `source_hash`, `solver`, `solver_result`, `codegen_semantics_version`, `composed_versions`, `functions`, `vc`, `certificate`, `unsat_core` (reserved — deferred; Z3's core isn't cheaply surfaced through liquid-fixpoint). The §4.1 LCF anti-laundering invariant (a positive tier is unconstructible without its supporting qualifiers) is enforced on both emit and parse — hand-editing a refuted function's record to claim a verified tier is rejected on parse, not silently accepted. This is a **replay** guarantee (re-runs the solver under pinned inputs), not a proof checkable without the solver — that stronger property is the future Lean tier.

#### Body-faithful verification

`llmll verify` encodes function bodies as verification conditions for functions in the decidable QF-LIA fragment. For a function with postcondition Q, precondition P, and body B, the emitter generates:

```
P ∧ (result = ⟦B⟧) ⟹ Q
```

This means `VLProvenSMT` with `body_faithful = true` guarantees the implementation satisfies the contract, not just that the contract is self-consistent.

**Coverage:** `ELet` (with alpha-renaming), `EIf` (path-sensitive), and QF-LIA operators. `EMatch`, recursive `def-shell` bodies, and non-linear expressions fall back to contract-only verification. Functions with >4096 execution paths also fall back with a diagnostic warning.

**JSON output:** `--json verify` includes per-function `body_faithful` and `body_fallback` metadata:

```json
{
  "functions": {
    "withdraw": { "body_faithful": true },
    "sort-list": { "body_fallback": "letrec" }
  }
}
```

**Contract stripping:** `--contracts=unproven` strips postcondition assertions only for functions that are both `VLProvenSMT` and body-faithful. Preconditions are never stripped — body VCs prove postconditions, not preconditions.

**Spec coverage JSON:** `--spec-coverage --json` includes two additional fields in the summary:
- `spec_coverage` — contracted / total (excludes suppressions)
- `suppression_debt` — suppressed / total

### `replay` — deterministic event log replay

```bash
# Run a console program — produces .event-log.jsonl automatically:
stack exec llmll -- build ../examples/event_log_test/event_log_test.llmll
cd event_log_test && stack exec event_log_test
# (interact with program — .event-log.jsonl written on exit)

# Replay: rebuild from source, feed logged inputs, compare outputs:
stack exec llmll -- replay ../examples/event_log_test/event_log_test.llmll event_log_test.event-log.jsonl
# Replay: 5/5 events matched
```

The replay command:
1. Parses the `.event-log.jsonl` file (JSONL — one JSON object per line)
2. Builds the program from source using the standard `build` pipeline
3. Feeds each logged input to the rebuilt program step-by-step
4. Compares actual output against logged output
5. Reports match count and any divergences with sequence numbers

> [!NOTE]
> Event logs are crash-safe: if the program is killed mid-run, the log is valid up to the last flushed line. Partial logs can be replayed.

### `typecheck --sketch` — partial-program type inference

> [!NOTE]
> The `compiler/examples/sketch/` fixtures shipped in this repo use an old schema and grammar (`schemaVersion: "0.2.0"`, `"kind":"def-logic"`) and no longer parse. The worked example below is inlined and current.

```json
// if_hole.ast.json
{
  "schemaVersion": "0.7.0",
  "statements": [
    { "kind": "def", "name": "greet",
      "params": [{ "name": "formal", "param_type": { "kind": "primitive", "name": "bool" } }],
      "body": { "kind": "if", "cond": { "kind": "var", "name": "formal" },
        "then_branch": { "kind": "lit-string", "value": "Dear Sir/Madam" },
        "else_branch": { "kind": "hole-named", "name": "informal_greeting" } } }
  ]
}
```

```bash
stack exec llmll -- typecheck --sketch if_hole.ast.json
# {
#   "holes": [ { "name": "?informal_greeting", "inferredType": "string",
#                "pointer": "/statements/0/body/else",
#                "scope": [ { "name": "formal", "source": "param", "type": "bool" },
#                           { "name": "greet", "source": "let-binding", "type": "fn[1 args] -> ?" } ] } ],
#   "errors": [],
#   "invariant_suggestions": [],
#   "schemaVersion": "0.4.0"
# }
```

Accepts a partial LLMLL program with holes anywhere. Returns:

- `holes[]` — each `?hole`’s inferred type (or `null` if indeterminate) and its RFC 6901 JSON Pointer
- `errors[]` — type errors detectable even with holes present, each annotated with `holeSensitive: bool`
- `invariant_suggestions[]` — invariant suggestions from the pattern registry, keyed by `(type signature, function name pattern)`. Contains ≥5 patterns (list-preserving, sorted, round-trip, subset, idempotent).

`holeSensitive: true` means the error may disappear once holes are filled — fix `holeSensitive: false` errors first.

#### Invariant suggestions

When a function’s type signature matches a known pattern, `--sketch` emits invariant suggestions:

```bash
stack exec llmll -- typecheck --sketch program.ast.json
# {
#   "holes": [...],
#   "errors": [],
#   "invariant_suggestions": [
#     { "function": "sort-list",
#       "pattern": "list[a] → list[a]",
#       "suggestions": ["(= (list-length result) (list-length input))", "(sorted result)"] }
#   ]
# }
```

The pattern registry is stored as data (not code) — adding new patterns does not require recompilation. See `InvariantRegistry.hs` for the full pattern set.

### `serve` — HTTP sketch endpoint

```bash
# Start on default localhost:7777
stack exec llmll -- serve

# Custom host/port/token
stack exec llmll -- serve --host 0.0.0.0 --port 8888 --token my-secret

# Query from an agent
curl -s -X POST localhost:7777/sketch \
     -H "Content-Type: application/json" \
     -d @partial.ast.json | jq '.holes'
```

Every `POST /sketch` is **stateless** — a fresh type-check context per request. Safe for concurrent agent use with no locking. TLS is handled by a reverse proxy (nginx/Caddy); `llmll serve` binds plaintext only.

### `checkout` — lock a hole for exclusive editing

`examples/delegate_demo/program.ast.json` has 2 statements today; its hole (`compute-value`'s `?delegate` body) is at `/statements/1/body`, and — because `compute-value` carries no `pre`/`post` — this particular checkout doesn't populate the contract/typing fields (see "Context-aware fields" below for a hole that does):

```bash
stack exec llmll -- checkout ../examples/delegate_demo/program.ast.json /statements/1/body --json
# {
#   "pointer": "/statements/1/body",
#   "hole_kind": "hole-delegate",
#   "token": "35b582cfbe3a97f8...",
#   "ttl": 3600,
#   "brief_version": "0.12.1",
#   "source_hash": "efab8d7013749661e...",
#   "timestamp": "2026-07-01T19:22:35.87Z",
#   "contract_pre": null, "postcondition_goal": null, "path_condition": null,
#   "obligation_id": null, "assumptions": null, "consumed_guarantees": null,
#   "verified_hash": null
# }

# Check remaining TTL
stack exec llmll -- checkout ../examples/delegate_demo/program.ast.json --status 35b582cfbe3a97f8...
# { "remaining_ttl": 3600 }

# Explicitly release a lock (don't wait for TTL expiry)
stack exec llmll -- checkout ../examples/delegate_demo/program.ast.json --release 35b582cfbe3a97f8...
# { "released": true }
```

> [!IMPORTANT]
> **Flag comes after the file, not before.** `--status TOKEN` / `--release TOKEN` are options on `checkout FILE ...`, not standalone subcommands: `llmll checkout FILE --status TOKEN` / `llmll checkout FILE --release TOKEN`. Putting `--status`/`--release` before `FILE` fails.

`checkout` validates that the RFC 6901 pointer targets a `hole-*` node in the JSON-AST. If the pointer targets a non-hole node but a descendant hole exists, the error includes a hint naming the actual hole pointer. Pointers are normalized: leading zeros in numeric segments are stripped (`/statements/02/body` → `/statements/2/body`).

Locks are per-file (`.llmll-lock.json` alongside the source) with a 1-hour TTL. Stale locks are auto-expired on any `checkout` or `patch` call.

**Context-aware fields** — present when the hole's enclosing function carries a contract and/or the compiler has typing/scope data. A `def withdraw` body-hole with a `pre`/`post` and an `-> int` return type (e.g. `examples/withdraw-demo/demo.ast.json`, `/statements/1/body`) populates all of them:

```bash
stack exec llmll -- checkout ../examples/withdraw-demo/demo.ast.json /statements/1/body --json
# {
#   ...,
#   "contract_pre": "(>= balance amount)",
#   "postcondition_goal": "(= result (- balance amount))",
#   "expected_return_type": "int",
#   "in_scope": [
#     { "name": "amount", "source": "param", "type": "PositiveInt" },
#     { "name": "balance", "source": "param", "type": "int" },
#     { "name": "double", "source": "let-binding", "type": "fn[1 args] -> int" }, ...
#   ],
#   "available_functions": [
#     { "name": "withdraw", "params": [...], "pre": "(>= balance amount)",
#       "post": "(= result (- balance amount))", "return_type": "int",
#       "tier": "asserted", "status": "filled" }, ...
#   ],
#   "type_definitions": [
#     { "name": "PositiveInt", "kind": "dependent", "base_type": "int" }, ...
#   ]
# }
```

| Field | Content |
|-------|---------|
| `contract_pre` / `postcondition_goal` | The hole's precondition (assumable) and postcondition (must prove). `null` when the enclosing function has no contract. |
| `in_scope` | Bindings visible at the hole site, with source provenance (`param`, `let-binding`, `match-arm`, `open-import`). Sorted by priority; truncated at 50 entries if scope is large (`scope_truncated: true`). |
| `expected_return_type` | The expected type at the hole site (τ). Populated for a function-body hole when the enclosing function declares a return type (`-> RetType`), and for a sub-expression hole whose type is fixed by local inference; absent otherwise. |
| `available_functions` | Contracted user functions with `params`/`pre`/`post`/`return_type`/`tier`/`status`. |
| `type_definitions` | User-defined type aliases and sum types referenced by in-scope bindings. Depth-bounded expansion (max 5 levels) with cycle detection. |
| `consumed_guarantees` | A verified callee's post the body may assume without re-proving (composition only); `null` otherwise. |
| `scope_truncated` | `true` if the scope was truncated; absent or `false` otherwise. |
| `path_condition`, `obligation_id`, `assumptions` | Reserved/contextual fields; `null` when not applicable to this hole. |
| `brief_version`, `source_hash`, `verified_hash`, `timestamp` | Bookkeeping: brief schema version, content hash at checkout (for compare-and-swap staleness detection), last-verified hash, and checkout time. |

> [!IMPORTANT]
> `checkout` requires `.ast.json` input. S-expression sources are rejected with: `"checkout requires .ast.json input; run 'llmll build --emit json-ast' first"`.

### `patch` — apply an RFC 6902 JSON-Patch to a checked-out hole

> [!NOTE]
> The `int-mul`/`int-add` builtin names in the repo's `examples/delegate_demo/patch-request.json` fixture don't exist (LLMLL uses the `*`/`+` operators, not those names) — the example below uses a fresh, working patch instead.

```bash
stack exec llmll -- patch ../examples/delegate_demo/program.ast.json ../examples/delegate_demo/patch-request.json
# { "result": "PatchSuccess", "statements": 2 }
```

The patch request is a JSON envelope containing the checkout token and RFC 6902 operations:

```json
{
  "token": "a1b2c3d4e5f6...",
  "patch": [
    { "op": "test",    "path": "/statements/2/body", "value": { "kind": "hole-delegate", ... } },
    { "op": "replace", "path": "/statements/2/body", "value": { "kind": "lit-int", "value": 42 } }
  ]
}
```

Supported operations: `replace`, `add`, `remove`, `test`. The `test` op guards against stale patches. `move` and `copy` are not supported — use `remove` + `add` instead.

**Scope containment:** All patch operations must target nodes within the checked-out subtree. A token for `/statements/2/body` cannot mutate `/statements/0/body`.

**On success:** the updated `.ast.json` is written and the lock is cleared. **On failure:** the original file is unchanged, the lock is preserved for retry, and diagnostics reference the responsible patch operation (e.g., `patch-op/1/body`).

**HTTP endpoints** (via `llmll serve`): `POST /checkout`, `POST /checkout/release`, `POST /patch` — governed by the same bearer token auth as `POST /sketch`.

---

## Part 3 — JSON-AST Schema Versioning

Every `.ast.json` file must include `schemaVersion` at the top level:

```json
{
  "schemaVersion": "0.7.0",
  "llmll_version": "0.14.2",
  "statements": [ ... ]
}
```

The compiler rejects mismatched versions immediately. **Strict mode:** only the exact matching version is accepted.

> [!IMPORTANT]

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Version of the JSON-AST schema shape — this is what the compiler gates on. `kind:"def"` / `kind:"def-shell"` are the canonical forms under the default `GrammarCoreInversion` mode. |
| `llmll_version` | Version of the LLMLL compiler that emitted this file. Informational only — the compiler does not validate this field. Decoupled from `schemaVersion` (the schema bumps independently of the language version). |

**Upgrade path:** bump `schemaVersion` in `docs/llmll-ast.schema.json`, update `expectedSchemaVersion` in `ParserJSON.hs`, re-emit fixtures.

**Round-trip guarantee:** `llmll build file.llmll --emit` (`-o DIR` optional; defaults to `generated/<name>/`) then `llmll build file.ast.json` produces semantically identical output. Any divergence is a bug.

---

## Part 4 — Known-Good Patterns (Current Compiler)

These patterns work in the **current compiler**. Each shows what works today and what the old workaround was.

### 4.1 State Accessor Functions

```json
{ "kind": "def", "name": "state-word",
  "params": [{ "name": "s", "param_type": { "kind": "pair-type", "fst": { "kind": "primitive", "name": "string" }, "snd": { "kind": "primitive", "name": "string" } } }],
  "body": { "kind": "app", "fn": "first", "args": [{ "kind": "var", "name": "s" }] } }
```

✅ **Works.** `first :: pair[a,b] → a` and `second :: pair[a,b] → b` require a `pair-type` parameter; annotate the state param with `{"kind":"pair-type","fst":...,"snd":...}` in JSON-AST.


### 4.2 Type Aliases at Call Sites

```lisp
(type NonNeg (where [n: int] (>= n 0)))
(def use-nonneg [x: NonNeg] x)
```

Passing `(use-nonneg 5)` is now valid — the type checker expands `NonNeg` to its base `int` before unification.

### 4.3 List Literals in JSON-AST

```json
{ "kind": "lit-list", "items": [
    { "kind": "lit-string", "value": " " },
    { "kind": "lit-string", "value": " " },
    { "kind": "lit-string", "value": " " }
]}
```

✅ Desugared by the parser to `foldr list-prepend (list-empty)`. Works for any length including `[]`.

### 4.4 Multi-Segment String Construction

```json
{ "kind": "app", "fn": "string-concat-many",
  "args": [{ "kind": "lit-list", "items": [c0, sep, c1, sep, c2] }] }
```

✅ `string-concat-many :: list[string] -> string` — concatenates without separator.

### 4.5 Built-in Functions

| Function | Signature | Notes |
| -------- | --------- | ----- |
| `string-trim` | `string → string` | Strip leading/trailing whitespace, `\t`, `\n`, `\r` |
| `string-concat-many` | `list[string] → string` | Concat list of strings |
| `list-nth` | `list[a] int → Result[a, string]` | Safe indexed access |
| `string-char-at` | `string int → string` | Single character at index. Returns `""` for negative or out-of-bounds indices. |
| `regex-match` | `string string → bool` | POSIX ERE match via `regex-tdfa`. Invalid patterns return `False` (total).  |
| `hmac-sha1` | `bytes[20] bytes[20] → bytes[20]` | RFC 2104 HMAC-SHA1. Opaque — trust level is `asserted`. |
| `sha1` | `bytes[20] → bytes[20]` | SHA-1 hash. Preamble is a stub — see LLMLL.md §13.11. |

### 4.6 `def-main` Initialisation and Termination

```json
{ "kind": "def-main", "mode": "console",
  "init":    { "kind": "app", "fn": "start-game", "args": [] },
  "step":    { "kind": "var", "name": "game-loop" },
  "done?":   { "kind": "var", "name": "is-game-over?" },
  "on-done": { "kind": "var", "name": "show-result" } }
```

> [!IMPORTANT]
> `:init` must be a **zero-arg function call** `{ "kind": "app", "fn": "start-game", "args": [] }`, not `{ "kind": "var", "name": "start-game" }`.

> [!IMPORTANT]
> **`:on-done` is the canonical hook for end-of-game output.** If `game-loop` prints a win/loss message on the same turn the game ends, the board can render twice. Move all terminal output for the final state into a dedicated `show-result` function and declare it via `:on-done`. See `LLMLL.md §9.5` for the full before/after pattern.

### 4.7 Known Restrictions

| Feature | Status | Notes |
| ------- | ------ | ----- |
| `[...]` list literal as direct argument inside S-expression `if` branch | ❌ Parse error | Hoist into a `let` binding before the `if` (workaround below) |
| `pre`/`post` **linear** contracts | ✅ Verified at compile time via `llmll verify` | — |
| `pre`/`post` **non-linear** contracts (`*`, `/`, `mod`) | ⚠️ Emits `?proof-required` hole; runtime assert still active | planned |
| `EPair` returning `TResult` approximation | ✅ **Fixed** | `EPair` now correctly typed `TPair a b`; `match` on pairs no longer suggests `Success`/`Error` arms |

> [!WARNING]
> **S-expression `[...]` inside `if` branches — use `let` to hoist.**  
> The S-expression parser misreads `]` when a list literal appears as a function argument inside an `if` body:
>
> ```lisp
> ;; FAILS — parse error 'unexpected ]':
> (if won
>     (wasi.io.stdout (string-concat-many ["You won! " word "\n"]))
>     ...)
>
> ;; WORKS — hoist the list into a let binding first:
> (let [(msg (string-concat-many ["You won! " word "\n"]))]
>   (if won (wasi.io.stdout msg) ...))
> ```
>
> This restriction does not apply to JSON-AST (`{"kind": "lit-list", ...}` is always unambiguous).

---

### 4.8 Common Agent Mistakes

| Mistake | Effect | Correct form |
| ------- | ------ | ------------ |
| `def-main` field `"done"` instead of `"done?"` | Silently ignored by JSON parsers; game never terminates | `"done?"` (with `?`) |
| `def-main` field `"onDone"` or `"on_done"` | Silently ignored | `"on-done"` (with hyphen) |
| `"isDone"` instead of `"done?"` | Silently ignored | `"done?"` |
| `:init` as `{ "kind": "var", "name": "start-game" }` | Passes the function, not its result | Must be `{ "kind": "app", "fn": "start-game", "args": [] }` |
| `[...]` list literal as direct argument inside S-expression `if` branch | Parse error: `unexpected ]` | Hoist into a `let` binding before the `if` (see §4.7) |
| `import` after a function definition inside `(module ...)` | Import silently ignored; unknown function at call site | All `import` statements must come before any `def`, `def-shell`, or `letrec` (legacy) |
| Calling `wasi.io.stdout` without `(import wasi.io (capability ...))` | Compile-time `missing-capability` error | Add `(import wasi.io (capability stdout))` before any `wasi.io.*` call |

> [!IMPORTANT]
> **`(module ...)` block — import ordering.** Inside a `(module ...)` wrapper, all `import` statements must appear **before** any `def`, `def-shell`, `type`, or `def-interface` statements (or `letrec` under `--grammar=legacy`). The parser reads imports in a first-pass and will silently ignore imports placed after definitions, causing unexpected "unknown function" errors at the call site. This ordering rule applies to both single-file and multi-file programs.
>
> ```lisp
> ;; CORRECT — imports first:
> (module my-app
>   (import wasi.io stdout)
>   (import haskell.aeson Data.Aeson)
>   (def-shell greet [name: string] (wasi.io.stdout name)))
>
> ;; WRONG — import after def-shell is ignored:
> (module my-app
>   (def-shell greet [name: string] (wasi.io.stdout name))
>   (import wasi.io stdout))   ;; ← ignored, wasi.io.stdout unknown
> ```

---

### 4.9 Multi-File Modules: `open`, `export`, and `hub`

Use these patterns when authoring or consuming multi-module programs.

#### Prefixed access (default)

When `app.main` imports `app.auth`, all exported names from `app.auth` are accessible with the full qualified path — no extra declaration needed:

```lisp
(module app.main
  (import app.auth))

;; Call the exported function with its qualified name:
(app.auth.hash-password raw-str)
```

> [!IMPORTANT]
> **Codegen limitation — use bare names at call sites.**
> Qualified access (`module.fn`) is *accepted by the type-checker and resolver*, but
> The codegen merges all modules into a single flat `Lib.hs` with bare Haskell
> identifiers. A call written as `(world.make-world ...)` becomes `world_make_world`
> in the generated Haskell, which **does not exist** — GHC will error with
> `Variable not in scope: world_make_world`.
>
> **Rule:** always use **bare function names** at call sites, even for
> functions imported from other modules. The `(import world)` statement is still
> required (it triggers module loading and merging); only call sites must be bare.
>
> ```lisp
> ;; ✅ correct:
> (import world)
> (make-world 20 10)
>
> ;; ❌ wrong — produces undefined Haskell identifier:
> (world.make-world 20 10)
> ```
>
> Per-module Haskell output (so `world.make-world` compiles correctly) is planned for a future release.

#### `open` — pull names into local scope

```lisp
;; Bring ALL exports from app.auth into scope as bare names:
(open app.auth)
(hash-password raw-str)   ;; no prefix needed

;; Selective — only hash-password is unprefixed; others still need prefix:
(open app.auth (hash-password))
```

> [!WARNING]
> **Open shadowing.** If two `(open ...)` declarations export the same name, the second wins (last wins, LISP-style). The compiler emits a `WARNING` diagnostic. Use prefixed access when two modules share a function name.

#### `export` — restrict what a module exposes

```lisp
;; Only hash-password and verify-token are visible to importers:
(export hash-password verify-token)

;; Omitting export entirely: all top-level defs are exported by default.
```

The `export` declaration must appear before the first function definition (`def` or `def-shell`) — consistent with the "imports before defs" rule.

#### Hub imports

After fetching a package with `llmll hub fetch`, import it with the `hub.` prefix:

```lisp
(import hub.llmll-crypto.hash.bcrypt (interface [
  [bcrypt-hash   (fn [raw: string] -> bytes[64])]
  [bcrypt-verify (fn [raw: string hash: bytes[64]] -> bool)]
]))
```

The `hub.` prefix tells the resolver to search only `~/.llmll/modules/`, never the local source tree. Hub-cached modules are parsed under the same grammar mode as the invoking command (see `LLMLL.md §8.2`); hub packages must use `def`/`def-shell` node kinds under the default `GrammarCoreInversion` mode.

#### Cross-module `(check ...)` bodies

Property-based tests can call functions defined in imported modules, provided the test module brings them into bare-name scope with `(open ...)`:

```lisp
(import imported)
(open imported)

(check "plus-one increments correctly"
  (for-all [n: int]
    (= (plus-one n) (+ n 1))))
```

Without `(open ...)`, the PBT static evaluator cannot resolve the cross-module call: the property body fails to reduce to a literal Bool and `llmll test` reports the check as `Skipped` rather than `Passed` or `Failed`. The fix is always to add `(open imported)` — qualified references (`imported.plus-one ...`) inside check bodies inherit the codegen limitation described under "Prefixed access (default)" above and do not currently resolve at runtime.

If `imported` declares `(export ...)`, only the listed names are visible to the test module's PBT evaluator (consistent with the type-checker's behavior).

#### JSON-AST nodes for `open` and `export`

```json
{ "kind": "open",   "path": "app.auth", "names": ["hash-password"] }
{ "kind": "open",   "path": "app.auth" }
{ "kind": "export", "names": ["hash-password", "verify-token"] }
```

Omit `"names"` in an `open` node to bring all exports into scope.

#### ⚠️ Limitation: module search root is anchored to the **entry-point** file

> [!WARNING]
> **All `import` paths are resolved relative to the directory of the file you pass to `llmll check` / `llmll build` (the entry-point), not relative to the file that contains the `import` statement.**
>
> This means sub-modules can import sibling sub-modules correctly only when they all live **in the same directory as the entry-point**, or in a flat peer layout.
>
> **What works:**
>
> ```text
> examples/life_json/
>   main.ast.json       ← entry-point: llmll check main.ast.json
>   world.ast.json      ← (import world)   → resolved to ./world.ast.json ✅
>   core.ast.json       ← (import core)    → resolved to ./core.ast.json  ✅
> ```
>
> **What does NOT work currently:**
>
> ```text
> examples/life_json/
>   main.ast.json       ← entry-point
>   life/
>     world.ast.json    ← (import life.core) → searched in examples/life_json/
>     core.ast.json     ← found ✅, but world.ast.json's own imports...
>       ↑   world.ast.json then tries (import life.core)
>           → resolved to examples/life_json/life/core.ast.json ✅ first time,
>             but if world.ast.json's dir ≠ srcRoot, a second-level import
>             from world.ast.json resolves against the entry-point root,
>             not world's directory — so relative sibling imports inside
>             life/ break unless life/ = the entry-point directory.
> ```
>
> **Recommended layout:** keep all module files at the **same directory level** as the entry-point. Use single-segment import names (`import core`, `import world`).
>
> A `--lib <dir>` flag that adds extra search roots is planned for a future release.

---

### §4.10 Recursive Functions (`def-shell`)

Self-recursive functions are declared with `def-shell`. The self-call is a user-defined callee outside the strict-core fragment; no `:decreases` annotation is required or available under the default grammar.

> **Legacy grammar (`--grammar=legacy`).** The `letrec` form provides an explicit `:decreases` termination measure checked for well-foundedness (`measure ≥ 0`) by `llmll verify`. The following examples use `letrec` syntax and require `--grammar=legacy` to parse:

```lisp
;; Simple variable measure — verified automatically by llmll verify:
(letrec countdown [n: int] :decreases n
  (if (= n 0) 0 (countdown (- n 1))))

;; With pre/post contracts:
(letrec list-sum [xs: list[int]] :decreases (list-length xs)
  (pre  (>= (list-length xs) 0))
  (post (>= result 0))\n  (if (list-empty? xs) 0 (+ (list-head xs) (list-sum (list-tail xs)))))
```

JSON-AST:

```json
{ "kind": "letrec",
  "name": "countdown",
  "params": [{ "name": "n", "param_type": { "kind": "primitive", "name": "int" } }],
  "decreases": { "kind": "var", "name": "n" },
  "body": { "kind": "if", "..." : "..." } }
```

> [!IMPORTANT]
> A **simple variable** measure (`:decreases n`) is verified by `llmll verify`. A **complex expression** (`:decreases (- n 1)`) emits a `?proof-required(complex-decreases)` hole — non-blocking, but the solver skips that function.

> [!WARNING]
> Under the default `GrammarCoreInversion`: use `def-shell` for any self-recursive function; `letrec` is not available. Under `--grammar=legacy`: use `letrec` (the legacy explicit-recursion form). `def-logic` is rejected under all modes.

---

### §4.11 `?proof-required` Holes

The compiler auto-emits `?proof-required` holes for constraints outside the decidable linear arithmetic fragment. These holes are **non-blocking**: code compiles with a runtime assertion fallback.

| Hole | Emitted when | Blocking? |
|------|-------------|-----------|
| `?proof-required(complex-decreases)` | `letrec :decreases` is a non-variable expression (`--grammar=legacy` only) | No |
| `?proof-required(non-linear-contract)` | `pre`/`post` contains `*`, `/`, `mod`, `^` | No |
| `(?proof-required :reason "tag" pred-expr)` in `pre`/`post` | Manual annotation; author supplies the predicate expression | No (emits runtime assertion) |

**Manual annotation — bare form** (S-expression):

```lisp
?proof-required    ;; trust=asserted, no runtime assertion emitted
```

**Manual annotation — predicate-carrying form** (`pre`/`post` position only):

```lisp
(pre (?proof-required :reason "non-linear-contract" (>= (* x y) 0)))
```

A predicate-carrying `?proof-required` in `pre`/`post` emits a Haskell runtime assertion (`if pred then () else error "proof-required: reason"`). Non-linear predicates (`*`, `/`, `mod`, `^`) also emit a `QF-LIA` warning at `llmll check`.

**JSON-AST node — bare form:**

```json
{ "kind": "hole-proof-required", "reason": "non-linear-contract" }
```

**JSON-AST node — predicate-carrying form:**

```json
{
  "kind": "hole-proof-required",
  "reason": "non-linear-contract",
  "predicate": {
    "kind": "op",
    "op": ">=",
    "args": [
      { "kind": "var", "name": "result" },
      { "kind": "lit-int", "value": 0 }
    ]
  }
}
```

`llmll holes --json` reports all `?proof-required` holes. `llmll verify` skips them without error and lists skipped function names.

---

### §4.12 String Escape Sequences by Format

S-expression (`.llmll`) and JSON-AST (`.ast.json`) files use different string escape rules. Mixing them up is a common source of parse errors.

| Escape | JSON-AST | S-expression |
| ------ | -------- | -------------------- |
| `\n` newline | ✅ | ✅ |
| `\t` tab | ✅ | ✅ |
| `\r` CR | ✅ | ✅ |
| `\\` backslash | ✅ | ✅ |
| `\"` quote | ✅ | ✅ |
| `\uXXXX` Unicode | ✅ | ✅supported |
| `\xNN` hex | ❌ not valid JSON | ❌ not supported |

**JSON-AST:** follows RFC 8259. Use `\uXXXX` for control characters:

```json
{ "kind": "lit-string", "value": "\u001b[2J\u001b[H" }  // ✅ VT100 clear-screen
{ "kind": "lit-string", "value": "\x1b[2J\x1b[H" }    // ❌ \x1b not valid JSON
```

The compiler emits a hint when it detects the `\x1b` pattern:

```
:hint "JSON strings must use \\uXXXX for control/non-ASCII chars (e.g. \\u001b not \\x1b)"
```

**S-expression:** uses Haskell-style escapes. `\uXXXX` is now also supported:

```lisp
(def clear-screen [] "\u001b[2J\u001b[H")
```

---

### §4.13 Pair-Type JSON-AST Round-Trip

`llmll build --emit` on any program containing `(pair a b)` emits the `"pair-type"` node:

```json
{ "kind": "pair-type", "fst": { "kind": "primitive", "name": "int" }, "snd": { "kind": "primitive", "name": "string" } }
```

> [!IMPORTANT]
> Tooling that post-processes `llmll build --emit` output must match on `"kind": "pair-type"` for pair types, not `"result-type"`.

---

### §4.14 do-notation JSON-AST Schema

The JSON-AST schema for `do`-blocks uses a single, unified `"do-step"` node:

```json
// Named step — binds the result to a state variable
{ "kind": "do-step", "name": "state1", "expr": { /* ... */ } }

// Anonymous step — result is discarded
{ "kind": "do-step", "expr": { /* ... */ } }
```

> [!IMPORTANT]
> The JSON parser **rejects** `"bind-step"` and `"expr-step"` kinds with a migration error; use `"do-step"` for both, keeping the `"name"` property on named steps to capture the bound state.
> `llmll check` enforces state threading. Every step inside a `do`-block must return exactly `(S, Command)`, and the type `S` must be strictly identical across all steps. A mismatch produces a `"type-mismatch"` diagnostic.

### 4.15 Pair Destructuring in `let` Bindings

The binding head of a `let` form can be a **pattern** instead of a simple name, enabling pair destructuring without a separate `match`:

```lisp
;; S-expression: (pair p1 p2) pattern in let binding
(def use-pair [x: int]
  (let [((pair n msg) (make-pair x))]
    (string-concat msg (int-to-string n))))
```

Nested destructuring is supported:

```lisp
(def use-nested [w: string g: int r: bool]
  (let [((pair word (pair count flag)) (make-triple w g r))]
    (if flag
      (string-concat word (int-to-string count))
      word)))
```

**JSON-AST:** Use `"pattern"` instead of `"name"` in the let-binding object. Both forms can appear in the same `"bindings"` array:

```json
{
  "kind": "let",
  "bindings": [
    { "name": "p", "expr": { "kind": "app", "fn": "make-pair", "args": [{"kind": "var", "name": "x"}] } },
    {
      "pattern": {
        "kind": "constructor", "constructor": "pair",
        "sub_patterns": [
          { "kind": "bind", "name": "n" },
          { "kind": "bind", "name": "msg" }
        ]
      },
      "expr": { "kind": "var", "name": "p" }
    }
  ],
  "body": { "kind": "var", "name": "n" }
}
```

> [!NOTE]
> Simple bindings (`"name"`) and pattern bindings (`"pattern"`) are mutually exclusive within a single binding object — the JSON parser enforces a strict `oneOf` on these two keys. Using both in the same object is a parse error.

#### Multi-binding `let` with complex RHS

When a `let` binding's RHS is a complex expression (delegation, `await`, function call returning a pair), bind each intermediate result to its own name. Do **not** inline complex sub-expressions as arguments — the parser may reject them, and the verifier cannot track path conditions through nested calls.

```lisp
;; ✅ CORRECT — each step is a separate let binding:
(def-shell build-report [state: AppState data: ReportData]
  (let [(chart-future (?delegate-async @viz-agent
                         "Render a bar chart from data"
                         -> ImageBytes))]
    (let [(chart-result (await chart-future))]
      (match chart-result
        ((Success img) (pair state (wasi.http.response 200 img)))
        ((Error err)   (pair state (wasi.http.response 500 "Agent failed")))))))

;; ❌ WRONG — inlining await + delegate-async as a direct argument:
(def-shell build-report [state: AppState data: ReportData]
  (match (await (?delegate-async @viz-agent "Render chart" -> ImageBytes))
    ((Success img) (pair state (wasi.http.response 200 img)))
    ((Error err)   (pair state (wasi.http.response 500 "Agent failed")))))
```

The same pattern applies to any multi-step computation: bind results to names with sequential `let`, then use the names in the body.

```json
{
  "kind": "let",
  "bindings": [
    { "name": "chart-future",
      "expr": { "kind": "hole-delegate-async", "agent": "@viz-agent",
                "description": "Render a bar chart from data",
                "return_type": { "kind": "named", "name": "ImageBytes" }}}
  ],
  "body": {
    "kind": "let",
    "bindings": [
      { "name": "chart-result",
        "expr": { "kind": "app", "fn": "await",
                  "args": [{ "kind": "var", "name": "chart-future" }]}}
    ],
    "body": { "kind": "match", "..." : "..." }
  }
}
```

---

### §4.16 Capability Enforcement

Calling a `wasi.*` function without a matching capability import is a **compile-time type error**. The check is in `inferExpr (EApp ...)` — it covers all nesting contexts: `let` RHS, `if` branches, `match` arms, `do` steps, and contract expressions.

```lisp
;; ✅ CORRECT — capability import present:
(module my-app
  (import wasi.io (capability stdout))
  (def-shell greet [name: string]
    (wasi.io.stdout (string-concat "Hello, " name))))

;; ❌ COMPILE ERROR — missing capability import:
(module my-app
  (def-shell greet [name: string]
    (wasi.io.stdout (string-concat "Hello, " name))))
;; Error: wasi.io.stdout requires (import wasi.io (capability ...))
```

**Non-transitive propagation:** If Module A imports `wasi.io` and Module B imports Module A, Module B must **also** declare `(import wasi.io (capability ...))` to call `wasi.io.*` functions directly. Calling them through a wrapper function from Module A is fine — only direct `wasi.*` calls are checked.

```lisp
;; Module B: also needs its own wasi.io import:
(module app.main
  (import app.auth)
  (import wasi.io (capability stdout))   ;; required even though app.auth has it
  (def-shell log-login [user: string]
    (wasi.io.stdout (string-concat "Login: " user))))
```

---

### §4.17 Type Errors for Polymorphic Functions

Polymorphic function calls are type-checked via substitution-based unification against concrete argument types, not a `TVar` wildcard match.

**Examples of type errors this catches:**

```lisp
;; ❌ list-head expects list[a], not int:
(list-head 42)
;; Error: type mismatch: expected list[a], got int

;; ❌ Element type mismatch caught by per-call-site substitution:
(list-map [1 2 3] (fn [x: string] x))
;; Error: type mismatch: list element type int ≠ string

;; ❌ first expects a pair, not a bare value:
(first 42)
;; Error: type mismatch: expected (a, b), got int
```

**Examples of correct usage:**

```lisp
;; ✅ first on a pair — infers type int:
(first (pair 1 "hello"))
;; type: int

;; ✅ Polymorphic builtins work across independent call sites:
(let [(x (list-head [1 2 3]))
      (y (list-head ["a" "b"]))]
  (pair x y))
;; x : Result[int, string], y : Result[string, string]
```

> [!NOTE]
> **Per-call-site scoping:** Each call to a polymorphic function gets its own fresh type variable instantiation. The substitution map does not escape the `EApp` boundary, so `list-head` on `list[int]` in one expression does not constrain `list-head` on `list[string]` elsewhere.

---

### §4.18 Type Soundness

Algorithm W includes an occurs check and let-generalization.

#### Occurs check

A type variable cannot unify with a type that contains itself. This prevents infinite type construction — `structuralUnify` (`TypeCheck.hs`) runs `occursIn` before binding a `TVar`, and on a genuine self-referential unification raises `"infinite type: " <> a <> " occurs in " <> typeLabel actual`.

> [!NOTE]
> The following is a *plausible-looking but not actual* trigger — `(def bad [x: a] (list-prepend x x))` is caught earlier, by an ordinary argument-type mismatch (`x`'s declared type `a` doesn't match `list-prepend`'s second-argument position `list[a]`), not by the occurs check specifically:
> ```lisp
> (def bad [x: a] (list-prepend x x))
> ;; Error: type mismatch in 'list-prepend': expected list[a], got a
> ```
> Both are soundness catches — the occurs check specifically guards against a `TVar` unifying with a compound type built from itself during per-call-site unification (`a ~ list[a]`), which requires a case where the compiler unifies a *fresh inference variable* against a self-referential structure, not a declared parameter type mismatch like the one above.

The `occursIn` helper is structurally total over the `Type` ADT, including `TSumType`.

#### Let-generalization

Top-level `def`, `def-shell`, and `letrec` (legacy) functions are let-generalized: each call site gets its own fresh type variable instantiation. TVar-TVar wildcard closure ensures type variable bindings propagate through chains, and bound-TVar consistency uses recursive `structuralUnify` instead of `compatibleWith`.

```lisp
;; ✅ Polymorphic function works at independent call sites:
(def id [x: a] x)
(let [(n (id 42))
      (s (id "hello"))]
  (pair n s))
;; n : int, s : string — each call site instantiates 'a' independently
```

> [!NOTE]
> **Known limitation:** Let-generalization applies to top-level `def`, `def-shell`, and `letrec` (legacy) functions only. Inner `let`-bound lambdas (e.g., `(let [(id (fn [x: a] x))] (pair (id 1) (id "hello")))`) are not generalized — the `TVar` is shared across call sites within the same `EApp` scope. An explicit generalize/instantiate pass for inner `let` is planned for a future release.

> [!NOTE]
> **Asymmetric wildcard:** the asymmetric wildcard in `TypeCheck.hs` is documented as safe under per-call-site scoping. Each `EApp` gets fresh type variables, so the asymmetry does not leak across call boundaries.

---

### §4.19 Benchmark CI Gates

Two frozen benchmarks have CI gate scripts that verify compiler output against expected results. Use these to guard against regressions.

```bash
# Run the ERC-20 benchmark gate (11 assertions):
make benchmark-erc20

# Run the TOTP benchmark gate (14 assertions):
make benchmark-totp

# Run all benchmark gates:
make benchmark-all
```

| Target | Script | Assertions | What it checks |
|--------|--------|-----------|----------------|
| `benchmark-erc20` | `scripts/benchmark-erc20.sh` | 11 | Parse, spec coverage (100%), trust report, verification-scope matrix, weakness check |
| `benchmark-totp` | `scripts/benchmark-totp.sh` | 14 | Parse, spec coverage (100%), trust report, provenance (`:source` annotations), verification-scope matrix, check blocks (RFC 6238 test vectors) |
| `benchmark-all` | Both scripts | 25 | Runs ERC-20 then TOTP |

> [!NOTE]
> Benchmark gates compare **frozen JSON output** against `EXPECTED_RESULTS.json` in each benchmark's directory. If you modify a benchmark's contracts, update the expected results file and re-freeze. The scripts exit non-zero on any divergence.

### §4.20 Result Patterns: Construct, Match, Test

Result values have three syntactic surfaces. Use the right one in the right position; mixing them is a typecheck error.

```lisp
;; Construct — expression position
(def safe-divide [a: int b: int]
  (if (= b 0)
      (err "division by zero")
      (ok (/ a b))))

;; Match — pattern position only (each arm is its own (pattern body) pair)
(match (safe-divide x y)
  ((Success q)  q)
  ((Error  msg) -1))

;; Test — boolean position
(if (is-ok (safe-divide x y)) "ok" "fail")
```

`Result.Ok` and `Result.Error` are **not** registered constructor names. Use `(ok x)` and `(err e)` for construction, `Success` / `Error` for match patterns, and `(is-ok x)` for boolean tests. See `LLMLL.md §13.8` for the full rule.

**Common mistake:** writing `(Result.Error DelegationError)` inside `(on-failure …)` clauses. `Result.Error` is not a registered identifier — this produces an `unknown identifier` diagnostic. Use `(err DelegationError)` instead.

### §4.21 `llmll check` Warning Surface

`llmll check` non-strict mode surfaces accumulated warnings on success. Agents should read warnings even when the exit code is 0.

```text
✅ solution.ast.json — OK (12 statements, 1 warning)
  (warning) is-Result: unknown identifier at solution.ast.json:42
```

`llmll check --strict` (warnings → errors with nonzero rc) and `llmll check --json` (structured output with the diagnostics array) are also available and produce the same warning surface.

### §4.22 PBT Outcome Discipline

`check` blocks report `pass` / `fail` / `skip` per `LLMLL.md §5.1`. A `skip` is **not** a `pass`. Property bodies that touch unevaluable terms — `?delegate` without `on-failure`, `?proof-required` references, `?delegate-async` / `await`, or command constructors (`wasi.io.stdout`, etc.) — are reported `skip` and contribute zero trust evidence.

Unevaluable samples resolve via `QC.discard` (QuickCheck's `GaveUp` maps to `PBTSkipped`) rather than a vacuous pass. Agents must add `(on-failure …)` clauses or factor `?delegate` calls out of property bodies to lift `skip` outcomes to `pass`.

### §4.23 PBT Complex-Type `for-all` Bindings

```lisp
(check "pair-sum-commutative"
  (for-all [p: (int, int)]
    (= (+ (first p) (second p)) (+ (second p) (first p)))))
```

`for-all` bindings at `(a, b)`, `list[a]`, `result[a, e]`, sum types declared via `(type Color (Red | Green | Blue))`, and user-defined aliases (`(type Ledger (list[Account]))`) generate well-typed samples and reduce end-to-end. Recursive aliases (e.g. `(type Tree (list[Tree]))`) terminate at the depth cap.

**Generator caps.** `maxGenDepth = 5` (recursion depth on aliases and nested types); `listMaxLen = 8` (max generated list length). Properties whose bindings include function types, promises, or free type variables still skip — the catch-all falls back to an integer sample those types cannot accept.

> [!NOTE]
> `PBTPassed` lifts `csPost` on the singleton head-position contracted callee to `DLTested n`. For multi-callee properties, see §4.24 below.

### §4.24 PBT Subject Annotation (`:subject` / `:subjects`)

`(check ...)` blocks can carry an optional `:subject f` (singleton sugar) or `:subjects [f₁ … fₖ]` (joint form) keyword between the description string and the `(for-all …)` body. Annotated properties bypass the head-position scan and explicitly attribute the `DLTested n` evidence to each named subject, per [LLMLL.md §4.4.5](../LLMLL.md#445-pbt-derived-trust-evidence).

```lisp
;; Singleton sugar — equivalent to (check :subjects [transfer] …)
(check "transfer preserves total balance" :subject transfer
  (for-all [l: Ledger, f: Account, t: Account, a: int]
    (= (total-balance l)
       (total-balance (unwrap-or (transfer l f t a) l)))))

;; Joint form — three subjects share one pbt_witnesses hash
(check "transfer well-formedness" :subjects [transfer balance has-account?]
  (for-all [l: Ledger, f: Account, t: Account, a: int]
    (and (>= (balance (unwrap-or (transfer l f t a) l) f) 0)
         (has-account? (unwrap-or (transfer l f t a) l) f))))
```

Each declared subject `fᵢ` whose contract has a `post` clause receives its own `DLTested n` evidence record in `.verified.json`; all per-subject records share one `pbt_witnesses` hash (the canonical-body serialization of `propBody`), so joint provenance is detectable by inspection of the shared hash. Subjects without a postcondition are skipped with an informational diagnostic from `llmll test` — the remaining annotated subjects still lift. Cross-module subjects (declared on imported functions reached via `(open path …)`) key under their qualified path `lib.f` in the local sidecar.

**Parse-time rules.** Empty `:subjects []` is rejected with a parse-time diagnostic. Duplicates are deduped (`:subjects [f f]` produces one record per `f`). Both sexp and JSON-AST surfaces support the metadata: the JSON-AST shape is `CheckDecl.subjects: ["f₁", …]`.

**When to use.** Use `:subjects` when one property's body covers multiple contracted callees and you want each to receive its own `DLTested` evidence — for example metamorphic-relation properties (Hughes 2020 *How to Specify It!* §3) where a structural identity holds across a chain of operations. Without the annotation, the head-position-singleton fallback applies: the unannotated multi-callee diagnostic at [LLMLL.md §4.4.5](../LLMLL.md#445-pbt-derived-trust-evidence) refuses implicit lift to avoid overallocation across independent callees. The annotation is the agent's explicit consent to joint-evidence allocation.

**Joint lifts do not scalar-count as tested.** The trust-report builder identifies witness hashes that appear on ≥2 distinct subjects' post-clause evidence and demotes any pure-joint `DLTested` entry to `DLAsserted` at classify time — a multi-subject `:subjects [f g h]` lift does not inflate `summary.tested`/`tier_profile.tested` by N. The per-subject `EvidenceRecord` and the shared `pbt_witnesses` hash are still emitted into `.verified.json`; the entry's JSON carries an optional `joint_pbt_witness: true` flag, and the top-level emit carries `joint_pbt_witnesses: [{hash, subjects}]` listing the deterministic-ordered groupings. A subject covered by both a `:subjects [f g]` joint property AND a `:subject f` solo property keeps its `+1` tested credit, since at least one witness on its evidence record is non-joint. Source-annotated `DLTested` from `:trust tested` markers (empty `pbt_witnesses`) is unaffected.

---

### §4.25 Core/Shell Grammar

Pass `--grammar=legacy` to parse older `letrec` programs. `def-logic` is not supported under any mode. Two definition keywords are available under the default mode:

| Keyword | AST node | Body restriction | When to use |
|---------|----------|-----------------|-------------|
| `def` | `SDef` | Strict-core whitelist (QF-LIA, `ELet`, `EIf`, `EMatch` Result 2-arm, admitted `EApp`) | Pure integer-arithmetic functions intended for body-faithful SMT verification |
| `def-shell` | `SDefShell` | None | Functions that use lambdas, IO, non-linear ops, or call unverified code |

**Strict-core example:**

```lisp
(def add-positive [x: int y: int]
  (pre (and (>= x 0) (>= y 0)))
  (post (>= result 0))
  (+ x y))
```

**Permissive shell example:**

```lisp
(def-shell format-name [first: string last: string]
  (string-concat first (string-concat " " last)))
```

**Invocation:**

```bash
llmll check myfile.llmll                          # core-inversion by default
llmll --grammar=legacy check myfile.llmll         # legacy letrec programs
llmll verify myfile.llmll --trust-report          # core-inversion by default
```

`letrec` is **not accepted** under the default `GrammarCoreInversion` mode; the compiler emits `core-grammar-violation` and exits non-zero. `def-logic` is rejected under **all** modes with a `removed-construct` diagnostic (no auto-rewrite). Use `def` for strict-core functions and `def-shell` for permissive functions. Pass `--grammar=legacy` to parse legacy `letrec` programs; under legacy, `def` and `def-shell` are not available.

**Optional return-type annotation:**
Both `def` and `def-shell` accept an optional `-> RetType` immediately after the parameter brackets, before the contract clauses. Omit it and the return type is inferred (byte-identical to prior behavior); declare it and the body is checked against `RetType` — and a function-body hole then reports `RetType` as its `expected_return_type` in the checkout brief (otherwise that field is absent on a body hole):

```lisp
(def withdraw [balance: int amount: PositiveInt] -> int
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  ?body_impl)
```

A **refinement-aliased return** (`-> PositiveInt`) discharges: the body-VC proves the refinement, so the function reaches `verified` when the predicate is solver-supported (`Σ_auto`), and is `refuted` if the body violates it. The proven refinement is also **exported to callers**: a caller of `f : -> PositiveInt` may assume `result > 0` without re-proving it (assume-guarantee). A bare `-> RetType` function with no explicit `post` is credited `verified` in the trust report.

**Known restrictions:**
- `def-shell` has no body restriction. Violations of the strict-core grammar inside `def-shell` are silently allowed by design — they are only errors inside `def`.
- Schema `schemaVersion` is `0.7.0` (optional `return_type` on `def`/`def-shell`; the reader also accepts `0.6.0` for backward compatibility). New `.ast.json` files should carry `"schemaVersion": "0.7.0"`. `kind:"def"` / `kind:"def-shell"` are the standard forms under the default `GrammarCoreInversion` mode.

---

## Part 5 — Core Language Quick Reference

```lisp
;; Dependent type (runtime-checked constraint)
(type Name (where [var: basetype] constraint-expr))

;; Pure function with contracts
(def name [param: type ...]
  (pre  precondition-expr)      ;; optional
  (post postcondition-expr)     ;; optional — can reference `result`
  body-expr)

;; Let binding (sequential)
(let [(x expr1) (y expr2)] body)

;; If expression
(if cond then-expr else-expr)

;; Named hole
?my_hole_name

;; Property-based test
(check "description"
  (for-all [param: type ...]
    property-expr))

;; Entry point
(def-main :mode console :init (start-game) :step game-loop)
```

> Unicode aliases are supported: `→` `≥` `≤` `≠` `∧` `∨` `¬` `∀` `λ`
