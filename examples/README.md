# LLMLL examples — index

A map of every example, grouped by what it demonstrates. Run any of them with the
`llmll` compiler on your `$PATH`:

```bash
llmll verify <path> --strict-verified-core   # body-faithful verdict, hard-fails on fallback
llmll verify <path> --trust-report           # per-function trust tiers + transitive closure
```

**How to read the "teeth" column.** The strongest examples ship a discriminative
contract, a *good* impl that verifies, and an obvious-wrong *twin* the solver
**refutes**. `CI` marks the families frozen in `make refute-crux-gate` (a bad
twin that stops refuting fails the build). `asserted` marks examples that
type-check and carry contracts but sit outside the SMT-decidable fragment, so
nothing is solver-proven (an explicit "not proven", not a silent pass).

## Flagships — emergent decomposition & famous bugs

| Example | Demonstrates | Teeth |
|---|---|---|
| [`secure-channel-emergent/`](secure-channel-emergent/) | Heartbleed-domain secure channel, 25 fns / 7 import-linked modules, decomposition **invented by agents** via cascading `refine` (no reference solution); spine composes six modules through cross-module assume-guarantee | 1 refute twin (goto-fail) |
| [`token-revocation-emergent/`](token-revocation-emergent/) | OAuth RFC 7662/7009 introspection/revocation, 8 fns / 5 modules; both RFC-`:source` contracts and agent-invented bodies are machine-auditable | 5 refute twins, CI |
| [`heartbleed/`](heartbleed/) | Heartbleed (CVE-2014-0160) + a TLS record layer; the unbounded-`claimed`-length heartbeat is refuted at `copy-bytes`' bound. Scales to a 163-fn channel. Complements (does not duplicate) `secure-channel-emergent` | refute twin |
| [`gotofail/`](gotofail/) | Apple "goto fail" (CVE-2014-1266) with real sum types: `Verified` only if the signature stage returned `Continue` | refute twins, CI |

## Verification demos — discriminative contract, good verifies / bad refutes

| Example | Demonstrates | Teeth |
|---|---|---|
| [`payments-core/`](payments-core/) | Two-account conservation over a pair return ("money can't be created"); `transfer` over a `debit` call edge; `settle` Result-match | refute twins |
| [`bytes-bounds/`](bytes-bounds/) | `bytes[n]` memory safety: off-by-one (`<=` for `<`) and out-of-range write refute at the call site | refute twins, CI |
| [`banking_ledger/`](banking_ledger/) | Three-level assume-guarantee chain (`transfer → withdraw → safe-subtract`); the twin that drops one guard refutes at the call site | refute twin, CI |
| [`session-pay/`](session-pay/) | Protocol state-safety + verified payment + bounded amount composed in one verified function | 3 refute twins, CI |
| [`tcp_rfc793/`](tcp_rfc793/) | RFC 793 connection state machine; legal-successor safety verifies, `step-bad` refutes | refute twin, CI |
| [`rfc1982_serial/`](rfc1982_serial/) | RFC 1982 wrap-around serial arithmetic via the spec-from-RFC pipeline; the naive-`<` DNS bug refutes | refute twins, CI |
| [`nested-result/`](nested-result/) | A nested `Result`-variable match under a `let` reaches verified; bad twin refutes | refute twin, CI |
| [`refined-payload/`](refined-payload/) | A matched `Result[Pos,string]` arm uses its payload's `> 0`; a caller forwarding a weaker `Result[int]` is refused | refute + refusal |
| [`outcome-totality/`](outcome-totality/) | Payload-carrying `Accepted(n)`/`Rejected(n)` totality; always-Accepted twin refutes | refute twin, CI |
| [`total-recursion/`](total-recursion/) | `(decreases n)` upgrades recursion to total correctness; a bad measure fails on the distinct `measure-not-decreasing` channel | refute twin, CI |
| [`niw-measure/`](niw-measure/) | A `string-length` measure inside a refinement predicate (`Word = {s | len > 0}`); bare-string twin refutes | refute twin, CI |

## Workflow & feature demos

| Example | Demonstrates |
|---|---|
| [`withdraw-demo/`](withdraw-demo/) | The repair loop: hole → checkout/patch → rejected bad fills → accepted fix → verified; two-axis trust report, composition, CDP, proof-artifact |
| [`refine-demo/`](refine-demo/) | Cascading `refine`: one hole decomposed top-down into a contracted sub-hole tree, every intermediate state verified; two guardrails reject a vacuous or orphan decomposition |
| [`delegate_demo/`](delegate_demo/) | Delegate-hole resolution (a `?delegate` hole filled by a named agent) |
| [`orchestrator_walkthrough/`](orchestrator_walkthrough/) | End-to-end orchestrator flow over an auth module; trust vs. spec-coverage split |
| [`replay-demo/`](replay-demo/) | `llmll replay`: build a console program, capture its event log, then rebuild and replay to verify deterministic outputs (`docs/getting-started.md`'s replay example) |
| [`leanstral-demo/`](leanstral-demo/) | The Lean-tier ("C-property") path: a nonlinear obligation Z3 marks `asserted` becomes `verified-lean` under `--leanstral`, kernel-checked. Degrades cleanly without an API key |

## RFC-sourced benchmarks (frozen, mixed tiers)

| Example | Demonstrates |
|---|---|
| [`erc20_token/`](erc20_token/) | ERC-20 spec-to-contract benchmark, JSON-AST only; verification-scope matrix + weakness governance |
| [`totp_rfc6238/`](totp_rfc6238/) | TOTP RFC 6238: RFC `:source` provenance + weakness-ok governance over opaque crypto. Bodies are `asserted` placeholders by design (see its WALKTHROUGH) |
| [`benchmarks/`](benchmarks/) | Agent-fill benchmark **seeds** (holed programs B1/B3/B5), consumed by `compiler/test` and the experiment harness — not standalone verified examples |

## Language / runtime & syntax showcases (no verification teeth)

These show the surface language and codegen, not the solver. Contracts, where
present, land at the `asserted` tier.

| Example | Notes |
|---|---|
| [`hangman_sexp/`](hangman_sexp/) · [`hangman_json/`](hangman_json/) | Full Hangman in each surface format; `hangman_json` is `docs/getting-started.md`'s worked example |
| [`tictactoe_sexp/`](tictactoe_sexp/) | Two-player Tic-Tac-Toe (`:done?` + `:on-done`) |
| [`life_sexp/`](life_sexp/) · [`life_json/`](life_json/) | Conway's Life, multi-module, in each surface format |
| [`hangman_json_verifier/`](hangman_json_verifier/) · [`tictactoe_json_verifier/`](tictactoe_json_verifier/) | Games with contracts — **asserted, not solver-proven** (the board is a `list`, outside the decidable fragment) |
| [`effect-authority/`](effect-authority/) | Effect-row authority over-approximation (informational obligation report) |
| `../examples/withdraw.llmll` | Minimal `pre`/`post` acceptance-gate demo (single file) |

## Known issues (see `docs/design/examples-audit-2026-07-20-compiler-followups.md`)

- [`conways_life_json_verifier/`](conways_life_json_verifier/) — currently **crashes** liquid-fixpoint under v0.14.61 (a Bool/Int sort mismatch from an untyped boolean helper; regression, fix routed to the compiler team). Its committed sidecar still records the older `verified` result.
- [`proof_required_test/`](proof_required_test/) — its documented `--leanstral-mock` reproduction predates the fail-closed mock and no longer reproduces; slated for rewrite or archival.
