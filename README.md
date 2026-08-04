# LLMLL — v0.14.83

**AI writes the code; the compiler proves it matches the spec — and rejects a type-correct-but-wrong implementation before it merges.**

LLMLL (Large Language Model Logical Language) is a language and verification pipeline whose primary author is an LLM agent, not a human. Agents coordinate through formal contracts the compiler enforces — not through conversation. An agent can *hallucinate* an implementation and that's fine, as long as it satisfies the contract: verification turns hallucination from a failure mode into a search strategy (generate a candidate, check it against the spec, accept or reject).

> **Current version:** see [`CHANGELOG.md § Latest`](CHANGELOG.md#Latest). Full release notes per version live in CHANGELOG; this README does not duplicate them.

---

## See it: money that can't be created, proven

`conserve(from, to, amount)` returns **both** post-transfer balances, and its contract ties them together: `(first result) + (second result) = from + to` — the total is conserved, full stop. A "helpful" fill that credits the destination one unit extra is **type-correct** and looks harmless on inspection — but it breaks conservation, and the SMT solver refutes it:

```text
# body:  (pair (- from amount) (+ to (+ amount 1)))      ← type-correct, creates money
$ llmll verify conserve-bad.llmll
error: body verification of 'conserve-bad' failed —
       implementation does not satisfy postcondition (constraint #0)

# body:  (pair (- from amount) (+ to amount))             ← correct, conserves the sum
$ llmll verify conserve.llmll
✅ conserve.llmll — SAFE (liquid-fixpoint)
```

The proof is over **both** return values at once — a relational invariant, not a bound on one number. Every other tool merges code that type-checks; LLMLL proves the money didn't move.

<p align="center"><img src="docs/assets/refute.gif" width="760" alt="LLMLL refutes money creation before merge"></p>

Full copy-pasteable walkthrough: [`payments-core/DEMO-RUNBOOK.md`](examples/payments-core/DEMO-RUNBOOK.md) — the composed `transfer`/`debit` call-chain beat and the single-constructor `settle` beat live there too. For the interactive **repair-loop protocol** — an agent checks out a typed `?hole`, submits a patch, and the compiler rejects or accepts it before anything merges — see [`withdraw-demo/DEMO-RUNBOOK.md`](examples/withdraw-demo/DEMO-RUNBOOK.md) (narrated: [`DemoPost.md`](examples/withdraw-demo/DemoPost.md)).

---

## Prove what the solver can't — kernel-checked

Not every property is decidable by SMT. `square(n) = n*n` claims `result ≥ 0` — but `n*n` is **nonlinear**, outside Z3's decidable fragment, so the SMT verifier can only mark the postcondition `asserted` (an explicit "not proven"). With **`--leanstral`**, LLMLL states the obligation as a Lean theorem, has Leanstral prove it, and **checks that proof with the Lean kernel + Mathlib** — recording a `verified-lean` tier with an independently re-checkable `.lean` certificate.

<p align="center"><img src="docs/assets/leanstral.gif" width="760" alt="LLMLL verified-lean demo"></p>

```text
$ llmll verify examples/leanstral-demo/square.llmll --trust-report
  square:  post: asserted                       # Z3 gives up on nonlinear arithmetic

$ LLMLL_LEANSTRAL_API_KEY=… llmll verify examples/leanstral-demo/square.llmll \
    --leanstral --leanstral-lean-project ~/proofcheck --trust-report
  square: Leanstral proof found, Lean kernel + Mathlib CHECKED
  square:  post: verified-lean   (certificate: square.verified.lean)
```

The certificate is a Lean proof term the kernel accepted — checkable by anyone with Lean, without trusting Leanstral *or* LLMLL's compiler. **An AI proved what the SMT solver couldn't, and you don't have to take its word for it.**

> **Experimental.** Opt-in demo; needs a Leanstral API key (`LLMLL_LEANSTRAL_API_KEY`) and a local Lean 4 + Mathlib project. Production Lean verification across all obligation classes is the deferred `LEAN-GA` rebuild. Reproduce: [`examples/leanstral-demo/`](examples/leanstral-demo/) (`demo.sh`) · design: [`docs/design/leanstral-demo-spec.md`](docs/archive/shipped-design-specs/leanstral-demo-spec.md).


---

## Try it

The full repair loop (hole → rejected bad fills → accepted fix → verified) is the copy-pasteable [`DEMO-RUNBOOK.md`](examples/withdraw-demo/DEMO-RUNBOOK.md).

**Zero-install (Docker).** No Haskell toolchain — the image bundles `llmll`, `z3`, and `liquid-fixpoint`:

```bash
# see the SMT refutation of a conservation-breaking fill (no local files needed):
docker run --rm ghcr.io/machunter/llmll verify /opt/llmll/examples/payments-core/conserve-bad.llmll
# verify your own file (mounts the current directory at /work):
docker run --rm -v "$PWD":/work ghcr.io/machunter/llmll verify myfile.llmll
```

**From source.** Build first:

```bash
cd compiler && stack build
stack exec llmll -- --help
```

Requires GHC ≥ 9.4 + Stack ≥ 2.9. The proof step also needs `z3` + `liquid-fixpoint`.

> **`verify` is loud without the solver.** On the from-source path, with `z3`/`liquid-fixpoint` absent it prints a `SOLVER NOT FOUND — NOTHING WAS PROVEN` banner and exits `3` (not a silent pass) — install both to see the refutation. (The Docker image bundles both, so it never hits this.) See [`docs/getting-started.md`](docs/getting-started.md).

---

## What it is

LLMLL treats **verification as the coordination protocol**. A lead agent defines types and contracts (the *what*); specialist agents fill typed holes with the *how*; the compiler verifies each fill against its contract before merging. Agents trust each other's *contracts*, not each other's *code*. Merges are structured JSON-AST patches, not text diffs — so there are no structural merge conflicts, and every patch is re-verified before it lands.

**It does not claim program correctness.** It guarantees that all code is *consistent with its declared specifications*, and it tracks how strong each guarantee is: a `verified` contract was proven by the SMT solver; an `asserted` one was not. Trust propagates — no `verified` claim silently rests on an unproven dependency. The weakness checker (`--weakness-check`) even flags a contract so weak that a trivial implementation satisfies it. Its discriminative-power sibling (`--cdp`) scores how sharply a contract rules out wrong bodies. Both checks measure *non-vacuity, not spec fidelity*: a contract that is discriminative yet captures the wrong behavior still passes, and the code still verifies against it.

---

## What's proven vs. not — read this before believing the headline

The **shipped** proof path is SMT (Z3 via liquid-fixpoint) over a non-recursive **QF-LIA core** — integer linear arithmetic, let-bindings, conditionals, calls to contracted functions (assume-guarantee), and n-arm matches on admissible (non-recursive) sums (`Result` and user ADTs, nested and sequential) — **extended with three decidable theories**: the array class (`bytes[n]` memory safety, and `map[{int,string},{int,bool,string}]` get-after-put / key-presence / construction / read-modify-write), admissible datatype construction, and string **literals** (equality, distinctness, and code-point length). That covers numeric bounds, conservation invariants, length preservation, array/map bounds-and-presence safety, and string-tag discrimination. Everything else — string **structure** (concatenation, substring, regex), non-terminating recursion (recursion with a discharging `(decreases e)` measure verifies total), recursive-payload ADTs, non-linear arithmetic (`* / mod`), IO — **falls back** to contract-only checking, property tests, or runtime assertions, each carrying an explicit trust label (full matrix in [`LLMLL.md §5.3.5`](LLMLL.md)).

An interactive proof path for the rest (Lean 4 via "Leanstral" MCP) is **designed but not shipped** — it runs in mock mode only (`--leanstral-mock`), blocked on external availability.

[`docs/one-pager.md`](docs/one-pager.md) carries the full **Claim-to-Evidence map** — every claim mapped to a shipped command or an explicit "Planned"/"Not shipped" label. The "Planned"/"Not shipped" labels are deliberate; read it before sharing.

---

## Compiler

The active compiler is a **Haskell stack project** in `compiler/`. It is the only supported backend.

| Command | What it does |
|---------|--------------| 
| `llmll check <file> [--strict]` | Parse + type-check; emit structured diagnostics. With `--strict`: unbound variables, unknown functions, unknown operators, and branch type mismatches are hard errors instead of warnings. Without `--strict`: text mode renders accumulated warnings on success. |
| `llmll holes <file> [--deps] [--deps-out FILE]` | List all `?hole` expressions. With `--deps`: include dependency graph in `--json` output. With `--deps-out`: persist graph to file. |
| `llmll test <file>` | Run property-based tests (`check`/`for-all` blocks via QuickCheck) |
| `llmll build <file> [-o <dir>]` | Generate a Haskell package (`src/Lib.hs` + `package.yaml` + `stack.yaml`). Accepts both `.llmll` S-expression and `.ast.json` JSON-AST sources. |
| `llmll verify <file> [--fq-out FILE] [--leanstral-mock] [--trust-report] [--weakness-check] [--obligations] [--obligation-report] [--spec-coverage] [--strict-verified-core] [--cdp] [--strict-verify] [--proof-artifact FILE]` | Emit `.fq` constraint file and run `liquid-fixpoint` (if installed). With `--proof-artifact FILE`, also writes a unified, replayable verification record consolidating the trust/obligation/`.fq`/sidecar surfaces plus the determinism pins. With `--leanstral-mock`, also runs Leanstral proof pipeline on `?proof-required` holes. With `--trust-report`, prints per-function trust summary with transitive closure, epistemic drift warnings, and `weakness-ok` suppressions (note: `--trust-report` reloads persisted evidence **instead of running fixpoint**, so a solver-refutable function renders as `asserted`, not `refuted` — use the default `verify` or `--strict-verified-core` to surface `refuted`). With `--weakness-check`, detects specs that admit trivial implementations. With `--obligations`, suggests postcondition strengthening when UNSAFE at cross-function boundaries. With `--obligation-report`, emits structured JSON obligation report for every hole, unproven contract, and failed call-site precondition. With `--spec-coverage`, classifies every function and computes effective specification coverage ratio. With `--strict-verified-core`, hard-errors if any function falls back from body-faithful verification, carries overflow-tainted verified evidence, or is refuted (body-faithful but disproved by the solver), transitively over the call graph. With `--cdp`, computes contract discriminative power per function: emits a paired `discriminative_axis` block in the trust-report JSON alongside the existing diamond-lattice evidence axis. With `--strict-verify`, runs `--trust-report --weakness-check --spec-coverage --cdp` together — the recommended serious-verify path. |
| `llmll replay-artifact <FILE>` | Re-derive and check a recorded proof artifact: recompute the source hash, re-run the stored VC under the pinned solver, and **fail closed** on any source/solver-determinism mismatch or `unknown`/timeout. |
| `llmll typecheck --sketch <file>` | Partial-program type inference. Returns inferred type for every `?hole` plus `holeSensitive`-annotated errors and `invariant_suggestions` from the pattern registry. |
| `llmll serve [--host H] [--port P] [--token T]` | Expose `--sketch` as `POST /sketch` HTTP endpoint for agent swarms. Default: `127.0.0.1:7777`. |
| `llmll checkout <file.ast.json> <pointer>` | Lock a `?hole` for exclusive agent editing. Returns a checkout token with the hole's contract context (`contract_pre`, `postcondition_goal`, `path_condition`) and typing context (`in_scope`, `type_definitions`). Use `--release` to abandon, `--status` to query TTL. |
| `llmll patch <file.ast.json> <patch.json>` | Apply an RFC 6902 JSON-Patch to a checked-out hole. Re-verifies type safety before committing. |
| `llmll refine <file.ast.json> <refine.json>` | Fill a checked-out hole **and** spawn new contracted sub-holes its body calls, atomically (cascading decomposition). Spawned sub-contracts pass a feasibility (no-miracle) gate (a sub-contract no body can discharge is rejected with a witnessing input) and a CDP vacuity gate; in-scope defs whose contracts subsume a spawned sub-contract are surfaced as advisory `reuse_suggestions` (non-blocking `W-REUSE` on an exact contract-equivalent). |
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

LLMLL provides body-faithful SMT verification for a **non-recursive QF-LIA core** with **compositional call-chain reasoning**: integer literals, integer-typed variables, simple let-bindings, conditionals, function calls to contracted functions (assume-guarantee), `Result` pattern matching, and linear arithmetic (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`, `!=`). Programs outside that fragment fall back to contract-only verification, property-based testing, or runtime assertions with explicit trust labels.

| Construct | SMT body-faithful | Fallback |
|---|---|---|
| `ELit`, `EVar` (int) | ✅ | — |
| `EOp` (+, -, =, <, <=, >=, >, !=) | ✅ | — |
| `ELet` (PVar, int RHS) | ✅ | — |
| `EIf` (≤4096 paths) | ✅ (path-split) | — |
| `EApp` (contracted callee) | ✅ (assume-guarantee) | — |
| `EApp` (uncontracted callee) | ❌ | contract-only |
| `EApp` (recursive self / cycle) | ✅ partial; ✅ total with `(decreases e)` | no measure → `termination_unverified`; k=1 measure → total + strict-core admissible |
| `EMatch` admissible sum (n-arm, `Result`/user ADT, nested + sequential) | ✅ (n-ary int-tag) | — |
| `EMatch` (recursive-sum payload), `EPair` opaque, `ELambda`, `EDo` | ❌ | runtime |
| `letrec` (own body VC) | ❌ | runtime + `:decreases` |
| Non-linear ops (*, /, mod) | ❌ | runtime + `?proof-required` |
| **Int overflow** | ⚠ | Z3 `Int` ≠ Haskell `Int64` |

> **Integer overflow model gap:** Z3 reasons over mathematical integers; Haskell `Int` wraps at 2⁶³. Contracts proven in the solver may not hold at overflow boundaries.

Full verification matrix: [`LLMLL.md §5.3.5`](LLMLL.md).

---

## Examples

Start here: [`examples/README.md`](examples/README.md) is the tiered index to every example.

### Emergent & famous-bug flagships

| Example | What it proves |
|------|----------------|
| [`examples/secure-channel-emergent/`](examples/secure-channel-emergent/) | **Emergent flagship.** A Heartbleed-domain secure channel, 25 functions across 7 import-linked modules, where agents *invented the entire decomposition* via cascading `refine` with no reference solution; the spine composes six modules through cross-module assume-guarantee and declines an unsteered goto-fail bait |
| [`examples/token-revocation-emergent/`](examples/token-revocation-emergent/) | **Emergent data flagship.** An OAuth RFC 7662/7009 introspection/revocation service, 8 functions / 5 modules, where both the contracts (RFC `:source`-tagged) and the agent-invented bodies are machine-auditable; 5 famous-bug refute twins, CI-frozen |
| [`examples/heartbleed/`](examples/heartbleed/) | Heartbleed (CVE-2014-0160) + a full TLS record layer: the buggy heartbeat that echoes an unbounded `claimed` length is `refuted` at `copy-bytes`' bound; scales to a 163-function channel |
| [`examples/gotofail/`](examples/gotofail/) | Apple "goto fail" (CVE-2014-1266) modeled with real sum types: `Verified` only if the signature stage returned `Continue`; the bug (returning `Verified` on the `Abort` arm) is `refuted` |

### Verification demos (`llmll verify`)

| Demo | What it proves |
|------|----------------|
| [`examples/payments-core/`](examples/payments-core/) | **Flagship.** Two-account conservation over a pair return (`conserve`) — "money can't be created"; `transfer` verified over a `debit` call edge (no-overdraw); `settle` is a `Result`-match return |
| [`examples/tcp_rfc793/`](examples/tcp_rfc793/) | RFC 793 connection state machine reaches `verified` on legal-successor safety; `step-bad` is `refuted` |
| [`examples/session-pay/`](examples/session-pay/) | Connected demo: protocol state-safety + verified payment + bounded amount in one `verified` function |
| [`examples/nested-result/`](examples/nested-result/) | A nested `Result`-variable match (under `let`) reaches `verified` |
| [`examples/refined-payload/`](examples/refined-payload/) | A matched `Result[Pos,string]` arm uses its payload's `> 0` (`verified`); a caller forwarding a weaker `Result[int]` is refused |
| [`examples/outcome-totality/`](examples/outcome-totality/) | A payload-carrying `Accepted(n)`/`Rejected(n)` outcome with a verified legal→Accepted / illegal→Rejected totality |
| [`examples/banking_ledger/`](examples/banking_ledger/) | Three-level assume-guarantee chain (`transfer → withdraw → safe-subtract`), all verified; the twin that drops one guard is `refuted` at the call site |
| [`examples/withdraw-demo/`](examples/withdraw-demo/) | The repair loop (hole → rejected bad fills → accepted fix → verified) + the `return-refine` beat |
| [`examples/refine-demo/`](examples/refine-demo/) | Cascading `refine`: one hole decomposed top-down into a contracted sub-hole tree, every intermediate state `verified` via assume-guarantee; two guardrails reject a vacuous or orphan decomposition |
| [`examples/bytes-bounds/`](examples/bytes-bounds/) | `bytes[n]` memory safety: a correct bounds check verifies; the off-by-one (`<=` for `<`) and an out-of-range write are `refuted` at the call site |
| [`examples/total-recursion/`](examples/total-recursion/) | A recursive function with `(decreases n)` verifies **total** (termination discharged); a bad measure fails on the distinct `measure-not-decreasing` channel |
| [`examples/rfc1982_serial/`](examples/rfc1982_serial/) | RFC 1982 serial arithmetic via the spec-from-RFC pipeline: all three functions `verified` with per-clause `:source`; the historical naive-`<` DNS bug refutes |

### Language / runtime examples

| Example | Format | Description |
|---------|--------|-------------|
| `examples/hangman_sexp/` | S-expression | Full Hangman game with ASCII gallows art; uses `def-main :mode console` |
| `examples/hangman_json/` | JSON-AST | Same program, JSON-AST schema-constrained version |
| `examples/tictactoe_sexp/` | S-expression | Two-player Tic-Tac-Toe; demonstrates `:done?` + `:on-done` |
| `examples/life_sexp/` | S-expression | Conway's Game of Life; multi-module (`core`, `world`, `main`) |
| `examples/life_json/` | JSON-AST | Same Life program in JSON-AST format |
| `examples/withdraw.llmll` | S-expression | Simple withdraw with `pre`/`post` contracts; acceptance gate |
| `examples/hangman_json_verifier/` | JSON-AST | Hangman with `apply-guess` contracts (`llmll verify`; asserted, not solver-proven) |
| `examples/tictactoe_json_verifier/` | JSON-AST | Tic-Tac-Toe with `set-cell` contracts (asserted, not solver-proven) |
| `examples/conways_life_json_verifier/` | JSON-AST | Conway's Life — `next-cell`/`count-neighbors` contracts (see its `VERIFICATION_SCOPE.md`) |
| `examples/replay-demo/` | S-expression | The `llmll replay` demo: codegen + deterministic event-log replay (used by `docs/getting-started.md`) |
| `examples/proof_required_test/` | S-expression | Leanstral proof pipeline validation |
| `examples/erc20_token/` | JSON-AST | ERC-20 benchmark — frozen ground truth with verification-scope matrix |
| `examples/totp_rfc6238/` | JSON-AST | TOTP RFC 6238 benchmark — crypto builtins, RFC `:source` provenance |

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
    Syntax.hs               ← AST types (incl. ModulePath, ModuleEnv, ModuleCache, TPair)
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
    FixpointIR.hs           ← .fq constraint IR + text emitter
    FixpointEmit.hs         ← typed AST → .fq + ConstraintTable builder
    DiagnosticFQ.hs         ← liquid-fixpoint output → [Diagnostic] with JSON Pointers
    Replay.hs               ← JSONL event log parser + replay execution
    LeanTranslate.hs        ← LLMLL contracts → Lean 4 theorem obligations
    MCPClient.hs            ← MCP JSON-RPC client (mock-first)
    ProofCache.hs           ← per-file .proof-cache.json sidecar (SHA-256)
    TrustReport.hs          ← transitive trust closure analysis (--trust-report)
    VerifiedCache.hs        ← .verified.json sidecar read/write
    WeaknessCheck.hs        ← trivial-body spec weakness detection
    InvariantRegistry.hs    ← pattern-based invariant suggestion database
    ObligationMining.hs     ← downstream postcondition strengthening suggestions
    ObligationAssembly.hs   ← structured obligation report assembly + JSON encoding
    GuardClassifier.hs      ← shared guard classification (verifier + obligations)
    SpecCoverage.hs         ← specification coverage metric + governance guardrails
    JsonPointer.hs          ← RFC 6901 pointer resolution + descendant hole search
    Checkout.hs             ← Hole checkout with per-file lock management (llmll checkout)
    PatchApply.hs           ← RFC 6902 JSON-Patch application with scope validation + re-verification (llmll patch)
    AgentSpec.hs            ← Compiler-emitted agent spec for LLM system prompts (llmll spec)
    HubQuery.hs             ← Query-by-signature: find hub modules matching a type signature (llmll hub query)
    CDP.hs                  ← contract discriminative power evidence axis (--cdp)
    ProofArtifact.hs        ← unified, replayable verification record (--proof-artifact / replay-artifact)
  package.yaml / stack.yaml
examples/
  hangman_sexp/             ← Full Hangman (S-expression)
  hangman_json/             ← Full Hangman (JSON-AST); getting-started.md's worked example
  tictactoe_sexp/           ← Tic-Tac-Toe (S-expression)
  life_sexp/                ← Conway's Life (S-expression, multi-module)
  life_json/                ← Conway's Life (JSON-AST, multi-module)
  withdraw.llmll            ← Contract demo
  hangman_json_verifier/    ← Hangman with contracts (asserted, not solver-proven)
  tictactoe_json_verifier/  ← Tic-Tac-Toe with contracts (asserted, not solver-proven)
  conways_life_json_verifier/ ← Life with contracts (see its VERIFICATION_SCOPE.md)
  erc20_token/              ← ERC-20 benchmark (frozen ground truth)
  totp_rfc6238/             ← TOTP RFC 6238 benchmark
  benchmarks/               ← agent-fill benchmark seeds (B1/B3/B5)
  secure-channel-emergent/  ← emergent flagship: 25 fns / 7 modules, agents invented the decomposition
  token-revocation-emergent/ ← emergent data flagship: RFC 7662/7009, agent-invented bodies, 5 refute twins
  heartbleed/               ← Heartbleed (CVE-2014-0160) + TLS record layer; scales to a 163-fn channel
  gotofail/                 ← Apple "goto fail" (CVE-2014-1266) with real sum types
  payments-core/            ← flagship verified-payments demo: two-account conservation, transfer/debit call chain, settle (see "See it")
  withdraw-demo/            ← repair-loop demo: holes → checkout/patch → two-axis trust + composition + CDP + proof-artifact
  refine-demo/              ← cascading refine: one hole → contracted sub-hole tree, each state verified
  tcp_rfc793/               ← RFC 793 connection state machine, legal-successor safety
  session-pay/              ← Connected demo: protocol state-safety + verified payment + bounded amount in one verified function
  nested-result/            ← Nested Result-variable match under let
  refined-payload/          ← Matched Result payload refinement + weaker-forward refusal
  outcome-totality/         ← Payload-carrying outcome sum, verified legal/illegal totality
  banking_ledger/           ← Three-level assume-guarantee chain (transfer → withdraw → safe-subtract) + refuting twin
  orchestrator_walkthrough/ ← Auth module orchestration exercise
docs/
  UPDATE-PROTOCOL.md        ← Doc canonical-sources + per-change update matrix
  getting-started.md        ← Build guide, known-good patterns, schema versioning
  compiler-team-roadmap.md  ← Engineering backlog and shipped-releases history
  llmll-ast.schema.json     ← JSON-AST schema (use with AI agents)
  orchestrator-walkthrough.md ← End-to-end orchestration walkthrough
  one-pager.md              ← Project overview / pitch document
  design/                   ← Active design proposals (status in design/INDEX.md)
    INDEX.md                ← Reading guide for active design documents
  archive/                  ← Superseded design specs, shipped proposals, professor reviews, wasm investigations
tools/
  llmll-orchestra/          ← Python orchestrator (pip package)
    llmll_orchestra/
      orchestrator.py       ← Fill-mode orchestrator
      lead_agent.py         ← Lead Agent skeleton generation (plan/lead/auto modes)
      quality.py            ← Skeleton quality heuristics
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
| [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) | Doc canonical-sources table and per-change update matrix |
| [`docs/orchestrator-walkthrough.md`](docs/orchestrator-walkthrough.md) | End-to-end multi-agent orchestration walkthrough with auth module exercise |
| [`docs/one-pager.md`](docs/one-pager.md) | Project overview — problem, approach, status, related work |
| [`docs/design/INDEX.md`](docs/design/INDEX.md) | Reading guide for all active design documents |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes by version |

---

## License

GPLv3 with LLMLL Runtime Library Exception — see [`LICENSE`](LICENSE).
