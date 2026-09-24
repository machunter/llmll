# LLMLL examples: index

Every example, in three tiers: **showcase** (start here), **supporting** (one
feature or workflow each), and **language and syntax** (no verification claim).
A last section lists directories that are test inputs, not demos.

Run any of them with `llmll` on your `PATH` (and `fixpoint` + `z3` for `verify`,
see [getting started](../docs/getting-started.md#install-the-solver-verify-only)):

```bash
llmll verify <path> --strict-verified-core   # body-faithful verdict, hard-fails on fallback
llmll verify <path> --trust-report           # per-function trust tiers + transitive closure
```

`llmll verify` writes a `.verified.json` sidecar next to the file it checks, and a
few examples track theirs. Experiment on a copy of the directory.

## How to read the tables

**Teeth.** The strongest examples ship a discriminative contract, a *good*
implementation that verifies, and an obvious-wrong *twin* the solver **refutes**.

**CI.** The example's verdicts are frozen in its `EXPECTED_VERDICTS.json` and
checked by `make refute-crux-gate`: a bad twin that stops refuting, or a good one
that stops verifying, fails the build. The gated suites under `examples/` are
banking_ledger, bytes-bounds, gotofail, heartbleed,
heartbleed/secure-channel/agent-fill/adversarial, nested-result, niw-measure,
outcome-totality, payments-core, rfc1982_serial, session-pay, tcp_rfc793,
token-revocation-emergent and total-recursion. Everything else is not gated.

**Partial.** `llmll verify` says how much it proved. A file whose function bodies
fall outside the decidable fragment prints `⚠️ ... SAFE ..., partial: K of N
contracted functions proved`, and a file with no postconditions prints
`nothing proved`. Both exit 0: SAFE there means "no contradiction found", not
"proved". The last column records what each example printed on v0.26.1.

## Showcase

| Example | Demonstrates | Teeth | `verify` on v0.26.1 |
|---|---|---|---|
| [`heartbleed/`](heartbleed/) | Heartbleed (CVE-2014-0160) and a TLS record layer: the unbounded `claimed`-length heartbeat is refuted at `copy-bytes`' bound. Scales to a 163-function channel filled by agents ([`secure-channel/`](heartbleed/secure-channel/)), with a goto-fail twin in `agent-fill/adversarial/` | refute twins, CI | filled programs proved; the two `*-scaffold.llmll` files are the unfilled starting points and print partial (0 of 5, 0 of 163); `agent-fill/modules/sc-m7-spine.llmll` verifies only inside the assembled channel |
| [`token-revocation-emergent/`](token-revocation-emergent/) | OAuth RFC 7662/7009 introspection and revocation, 8 functions over 5 modules; RFC-`:source` contracts and agent-invented bodies are both machine-auditable | 5 refute twins, CI | `crux-*` files proved or refuted as frozen; `roots/*.llmll` are holed contracts and print partial |
| [`gotofail/`](gotofail/) | Apple "goto fail" (CVE-2014-1266) with real sum types: `Verified` only if the signature stage returned `Continue` | refute twins, CI | all proved or refuted |
| [`payments-core/`](payments-core/) | Two-account conservation over a pair return ("money can't be created"), `transfer` over a `debit` call edge, `settle` Result-match. Walkthrough: [`DEMO-RUNBOOK.md`](payments-core/DEMO-RUNBOOK.md) | 4 refute twins, CI | all proved or refuted |
| [`secure-channel-emergent/`](secure-channel-emergent/) | Heartbleed-domain secure channel, 25 functions over 7 import-linked modules. The decomposition was **invented by agents** via cascading `refine` (no reference solution); the spine composes six modules through cross-module assume-guarantee | 1 refute twin (goto-fail), not CI | `work/*.ast.json` proved, the mutation check refutes; `roots/*.llmll` are holed contracts and print partial |
| [`rfc1982_serial/`](rfc1982_serial/) | RFC 1982 wrap-around serial arithmetic via the spec-from-RFC pipeline; the naive-`<` DNS bug refutes | refute twins, CI | all proved or refuted |

## Supporting

### Verification demos: discriminative contract, good verifies, bad refutes

| Example | Demonstrates | Teeth |
|---|---|---|
| [`bytes-bounds/`](bytes-bounds/) | `bytes[n]` memory safety: off-by-one (`<=` for `<`) and out-of-range write refute at the call site | refute twins, CI |
| [`banking_ledger/`](banking_ledger/) | Three-level assume-guarantee chain (`transfer → withdraw → safe-subtract`); the twin that drops one guard refutes at the call site | refute twin, CI |
| [`session-pay/`](session-pay/) | Protocol state safety, verified payment and a bounded amount composed in one verified function | 3 refute twins, CI |
| [`tcp_rfc793/`](tcp_rfc793/) | RFC 793 connection state machine; legal-successor safety verifies, `step-bad` refutes | refute twin, CI |
| [`nested-result/`](nested-result/) | A nested `Result`-variable match under a `let` reaches verified; bad twin refutes | refute twin, CI |
| [`refined-payload/`](refined-payload/) | A matched `Result[Pos,string]` arm uses its payload's `> 0`; a caller forwarding a weaker `Result[int]` is refused | refute and refusal |
| [`outcome-totality/`](outcome-totality/) | Payload-carrying `Accepted(n)`/`Rejected(n)` totality; always-Accepted twin refutes | refute twin, CI |
| [`total-recursion/`](total-recursion/) | `(decreases n)` upgrades recursion to total correctness; a bad measure fails on the distinct `measure-not-decreasing` channel | refute twin, CI |
| [`niw-measure/`](niw-measure/) | A `string-length` measure inside a refinement predicate (`Word = {s | len > 0}`); bare-string twin refutes | refute twin, CI |

### Workflow and feature demos

| Example | Demonstrates | `verify` on v0.26.1 |
|---|---|---|
| [`withdraw-demo/`](withdraw-demo/) | The repair loop: hole, checkout/patch, rejected bad fills, accepted fix, verified; two-axis trust report, composition, CDP, proof artifact | the holed starting files (`demo`, `withdraw`) print partial and `audit` prints nothing proved, by design; the filled and composed files prove or refute |
| [`refine-demo/`](refine-demo/) | Cascading `refine`: one hole decomposed top-down into a contracted sub-hole tree, every intermediate state verified; two guardrails reject a vacuous or orphan decomposition | `base` is the holed start and prints partial |
| [`delegate_demo/`](delegate_demo/) | Delegate-hole resolution (a `?delegate` hole filled by a named agent) | nothing proved (no postconditions) |
| [`orchestrator_walkthrough/`](orchestrator_walkthrough/) | End-to-end orchestrator flow over an auth module; trust vs. spec-coverage split | nothing proved (no postconditions) |
| [`leanstral-demo/`](leanstral-demo/) | The Lean-tier path: a nonlinear obligation Z3 leaves `asserted` becomes `verified-lean` under `--leanstral`, kernel-checked. Degrades cleanly without an API key | partial without `--leanstral`, by design |
| [`effect-authority/`](effect-authority/) | Effect-row authority over-approximation (informational obligation report) | nothing proved (no postconditions) |
| [`withdraw.llmll`](withdraw.llmll) | Minimal `pre`/`post` acceptance-gate demo (single file) | proved |

### RFC-sourced benchmarks (frozen, mixed tiers)

| Example | Demonstrates | `verify` on v0.26.1 |
|---|---|---|
| [`tftp_rfc1350/`](tftp_rfc1350/VERIFICATION_SCOPE.md) | TFTP (RFC 1350 + RFC 1123 §4.2.3.1) built by a swarm of blind agents: 124 normative clauses dispositioned, 46 encoded across 23 root contracts, all 23 filled bodies verified. Results: [`wave/RESULTS.md`](tftp_rfc1350/wave/RESULTS.md). Its kill matrix (8 mutants refuted, 1 good twin SAFE) is recorded in `wave/EXPECTED_VERDICTS.json`, but the mutant files were never committed and cannot be regenerated from the repo: `wave/mutants.json` only names them and `RESULTS.md` gives one line per mutation. Not CI | `wave/tftp-filled.ast.json` proved; `roots/tftp.llmll` is the holed surface and prints partial (0 of 23) |
| [`erc20_token/`](erc20_token/) | ERC-20 spec-to-contract benchmark, JSON-AST only; verification-scope matrix and weakness governance | partial (filled: 3 of 5) |
| [`totp_rfc6238/`](totp_rfc6238/) | TOTP RFC 6238: RFC `:source` provenance and weakness-ok governance over opaque crypto. Bodies are `asserted` placeholders by design (see its WALKTHROUGH) | partial (0 of 5), by design |

## Language and syntax

These show the surface language and codegen, not the solver. None of them has a
solver-proven contract, and `verify` says so.

| Example | Notes | `verify` on v0.26.1 |
|---|---|---|
| [`hangman_sexp/`](hangman_sexp/) · [`hangman_json/`](hangman_json/) | Full Hangman in each surface format; `hangman_json` is `docs/getting-started.md`'s worked example | nothing proved |
| [`tictactoe_sexp/`](tictactoe_sexp/) | Two-player Tic-Tac-Toe (`:done?` + `:on-done`) | nothing proved |
| [`life_sexp/`](life_sexp/) · [`life_json/`](life_json/) | Conway's Life, multi-module, in each surface format | nothing proved |
| [`hangman_json_verifier/`](hangman_json_verifier/) · [`tictactoe_json_verifier/`](tictactoe_json_verifier/) | Games with contracts; the board is a `list`, outside the decidable fragment, so the contracts are assumed | partial (0 of 2 each) |
| [`conways_life_json_verifier/`](conways_life_json_verifier/) | Conway's Life with contracts; `next-cell` and `count-neighbors` reach body-faithful `verified` (the one game verifier that does) | partial (3 of 5) |
| [`replay-demo/`](replay-demo/) | `llmll replay`: build a console program, capture its event log, then rebuild and replay to check deterministic outputs (`docs/getting-started.md`'s replay example) | nothing proved |

## Test inputs, not demos

| Directory | What it is |
|---|---|
| [`benchmarks/`](benchmarks/) | Agent-fill benchmark **seeds** (holed programs B1/B3/B5), consumed by `compiler/test` and the experiment harness. Each prints partial (0 of 1) |
| [`proof_required_test/`](proof_required_test/proof_required_test.llmll) | A pipeline test fixture for `?proof-required` holes and the Leanstral path; `scripts/tests/test_console_init_1.py` pins it by name. The reproduction in its header comment predates the fail-closed `--leanstral-mock` and no longer reproduces (`safe-div: unsupported`). Plain `verify` prints partial (0 of 1) |
