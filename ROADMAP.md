# LLMLL roadmap

This is the public summary. The team's internal work log, with every open item, its evidence and its history, is [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md). Release notes are in [`CHANGELOG.md`](CHANGELOG.md). No release is currently scheduled; the next one is cut from the open work below, and this page makes no date commitments.

## What has shipped

- **SMT proof of function bodies against their contracts** (Z3 via liquid-fixpoint) over linear integer arithmetic, `bool`, conditionals, n-arm matches on non-recursive sums, pairs and datatype construction, `bytes[n]` and `map` operations, and string literals. Calls to contracted functions, in the same file or imported, verify by assume-guarantee. A recursive function with a `(decreases e)` measure verifies as total. ([README: Verification Boundary](README.md#verification-boundary))
- **An agent protocol built on typed holes.** `llmll checkout` hands an agent a hole with its contract and scope; `llmll patch` applies a JSON-Patch fill only if the program still type-checks and the solver does not refute it; `llmll refine` fills a hole and spawns contracted sub-holes in one step.
- **A trust level for every function** (`verified`, `asserted` and others), propagated so that a `verified` claim never rests on an unproven callee, plus checks that flag weak contracts (`--weakness-check`, `--cdp`).
- **A `verify` headline that says how much was proved.** `✅` only when every function with a postcondition is proved and no proof rests on an unproved import or on a recursion without a `(decreases e)` measure; otherwise `⚠️` names the functions that are assumed, proved only if they terminate, or proved on unproved imports. `--strict-verified-core` fails on assumed functions and on callers of unproved imports.
- **Fail-closed behaviour without a solver.** With `z3` or `liquid-fixpoint` missing, `verify` says nothing was proven and exits 3, and `patch` and `refine` refuse to apply a contracted patch.
- **Replayable proof records.** `--proof-artifact` writes a verification record; `llmll replay-artifact` re-runs it under the pinned solver and fails closed on any mismatch.
- **An experimental Lean path** for nonlinear obligations: `--leanstral` has an AI prover write a Lean proof, and the Lean kernel checks it.
- **Programs that run.** A `def-main` program is a step machine: `:mode console` reads one stdin line per step, and `:mode cli` performs commands with no stdin and exits with a declared status. `llmll replay` re-runs a console program on its recorded stdin and reports how many turns' output matched.
- **A Haskell backend and a Docker image** (`ghcr.io/machunter/llmll`) that bundles the compiler and both solvers.
- **The repository's own CI gates are LLMLL programs** in `tools/`; see [README: The repository runs on LLMLL](README.md#the-repository-runs-on-llmll).

## What is next

Open work is grouped by where the fix lands, in priority order. Tags in parentheses name the matching item in the internal log.

1. **The verdict.** Close the remaining cases where a stored proof record could go stale or the trust report under-discloses. No open item in this group has a demonstrated false "SAFE" verdict. `verify --trust-report` and `verify --spec-coverage` now run the solver and exit on its verdict, and the render of saved results without the solver is the separate `llmll trust-report` command (TRUST-REPORT-GATE-1, closed). Two follow-ups are open: save a `refuted` verdict so that a module importing a disproved function can show it as refuted (TRUST-REFUTED-PERSIST-1), and apply the same evidence check to the cross-module trust-gap warning, which can show an outdated `tested` label (TRUST-GAP-KEY-1). (G1)
2. **Crash-freedom of built programs.** A program that passes `check` should not crash at run time. No item in this group is open. `Success` and `Error` are reserved constructor names by design, because they are `Result`'s own constructors (RESULT-CTOR-RRW, closed). (G2)
3. **One verdict across `check` and `build`.** Remove the cases where `check` passes and the Haskell build then fails, and where a diagnostic misleads: Unicode operator aliases that do not work (ALIAS-LOWER-1); a JSON-AST node that may drop an unknown key without a message (AST-STRICT-KEYS-1); `True` or `False` written as a value, which `check` warns about and `build` rejects (RESERVED-NAME-1 residue). User names that collide with Haskell's own names, such as `show`, `map`, `Left` or `Just`, now build, because the compiler renames them in the generated code (RESERVED-NAME-1, closed). Three gaps remain in that renaming: a whole-module `haskell.*` import, the local names of the generated `main` harness, and the printed names of constructors in the legacy pipe-text sum-type form (RESERVED-NAME-1 residue). (G3)
4. **Commands, responses and replay.** Measure what a second and third declared `Response` fact cost before adding more (RESP-FACT-2). Replay with injected responses waits on a trigger (REPLAY-INJECT). (G4)
5. **Capability enforcement.** The `capability` clause is declarative today; decide how the compiler enforces it (CAP-1-REAL). (G5)
6. **The module system.** Enforce `def-interface` conformance, which the spec already describes (IFACE-CONFORM). Make `run`, `patch`, `serve`, `repl` and `refine` load imports as `check` and `verify` do (XMOD-RUN-LOAD-1), and have `llmll test` run a property that calls a qualified import (PBT-QUAL-1). (G6)
7. **Builtins and system interface.** Byte-level file reads and writes, path normalization, case-insensitive and capturing regular expressions, setting a child process's environment, reporting the host platform, and the kind of each entry in a directory listing. Each has a measured workaround, and each ships when a second program needs it or when the workaround weakens trust or correctness. (G7)
8. **Instruments over the repository.** The rule-stating descriptions in the JSON-AST schema are checked by nothing (SCHEMA-TRUTH-1 residue); no CI job runs `check` over the shipped examples, so one that stops type-checking would go unnoticed (TOTP-CHECK-1); some gates report success when they cannot decide. (G8)

Unscheduled directions with their own sections in the internal log: per-module code generation, a WASM sandbox target, a wider data fragment, and cascading refinement. Production Lean verification (LEAN-GA), an MCP interface and an HTTP server entry mode (HTTP-SERVE-1) wait on a trigger.

## Deliberate boundaries

- **Consistency with the spec, not program correctness.** A contract that rules out wrong bodies but describes the wrong behaviour still passes. The weakness and CDP checks measure non-vacuity, not fidelity to intent.
- **Outside the SMT fragment, no proof.** String structure, nonlinear arithmetic, recursive payloads, lambdas and effectful code fall back to contract-only checks, property tests or runtime assertions, each with an explicit trust label.
- **Not planned** (from the internal log's "What's NOT on this Roadmap"): a second backend (Haskell is the only target), a Python FFI, a hand-built Lean prover, a UI frontend, IDE plugins before the CLI and HTTP interfaces stabilize, and indexed or dependent types (a research topic, not a release target).
