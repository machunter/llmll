# Minimal-Agent Experiment — Summary of Findings

**What we set out to determine:** whether an AI agent can write a *correct* LLMLL program from minimal context on the **first round** — the whole program (or a hole-fill) authored once, against nothing but the language reference, the JSON-AST schema, and a problem statement, with the compiler judging correctness (type-check, contracts, body-faithful verification).

This document states what the program of experiments determined about that question. It is deliberately **not** a record of the compiler bugs, harness defects, or language-surface gaps the runs also surfaced; those were the working residue of building the instrument, and they live in the per-postmortem files and `findings.md`. This is only the answer to the question we asked.

---

## What we ran

Across the program the harness exercised the breadth of the v0.3–v0.14 language surface, in two regimes:

- **Blank-slate authoring** — the agent writes the whole program from `problem.md`:
  - `001` two-agent auth: `def-interface`, blocking `?delegate`, `on-failure`, `Result`, a `?proof-required` postcondition.
  - `002` async report pipeline: `?delegate-async` / `await`, `Result` pattern-matching, `def-invariant`, `?proof-required`.
  - `004` capability-bounded summarizer: `wasi.fs.*` capability discipline, capability-correct composition (a network-reaching helper as the trap).
- **Fill-the-hole** — the agent fills a body hole against a pre-authored scaffold, graded by whether the fill provably realizes a withheld or declared contract:
  - `005` seeded return-holes (refinement-aliased and two-channel returns).
  - `006` reservoir clamp; `007`–`010` the **Lever A array class** — `map[{int,string},{int,bool,string}]` and `bytes[n]` — culminating in two fixtures built specifically to induce a plausible subtle error (a transfer that must preserve conservation; a byte operation that must saturate).

Models across the program were the frontier tier of their day: Claude Opus (4.7 → 4.8), `gpt-5.5` (codex), and Gemini (3-pro → 3.1-pro).

## What we determined

**Frontier agents one-shot correct LLMLL, consistently, across every task type the harness posed.**

- **Agent coordination (001, 002):** every attempt produced a structurally correct program — `def-interface`s, the right blocking vs. async delegation, `on-failure` fallbacks, `Result` construction and `Success`/`Error` matching, and a `?proof-required` marker on the delegation-bounded postcondition. The agents used the language's inference (writing the inner type at the delegation site and letting the compiler infer the `Promise`/`Result` wrappers) rather than over-annotating.
- **Contract discipline (005, 006):** agents emitted `?proof-required` on exactly the obligations the verifier cannot discharge — the out-of-fragment postconditions — reaching **100% correct marker emission** (8/8) on the clean runs, and grade A (a fully correct contracted solution) once the instrument measured it faithfully.
- **Capability discipline (004):** agents composed a filesystem-only summarizer and **avoided the network-reaching helper 18/18**, respecting an effect boundary they were only told about in prose.
- **The data-verification fragment (006–010):** on the Lever A array class, **30/30 grade B (verified-correct) across three frontier models** on the two fixtures explicitly designed to trip them — and **0/54 wrong fills across the whole solver-catches campaign**. Each fill was body-faithfully verifiable: not merely accepted, but machine-proved to satisfy the contract. The models did not make the induced errors (a dropped debit leg; a missing saturation clamp); they wrote the correct body first try.

Across the entire program, **where a solution was graded below the ceiling, the cause was a measurement artifact — the instrument mis-scoring a structurally-correct solution — rather than an authoring failure.** The agents were, in effect, never the bottleneck. The dominant difficulty in the whole effort was building a benchmark discriminating enough to catch a frontier agent being wrong; the agents kept not being wrong.

## The one thing the experiments could **not** determine

The final campaign set out to observe the verification safety net *catching* an agent: a blind visible test plus a withheld postcondition, so that a subtly-wrong fill would pass the agent's own testing yet be refuted by the solver. The safety net is real — every hand-written wrong fill was refuted body-faithfully by the same machinery — but **it was never triggered by a real agent fill, because the agents did not produce wrong fills.** The value of verification *under agent error* is therefore established by construction, not by an observed agent mistake.

Whether that gap is closable inside the auto-decidable fragment at all — or whether it structurally requires weaker agents (where errors appear as non-compiling attempts, not subtly-wrong-but-verifiable ones) or out-of-fragment tasks (dependent lengths, induction, richer invariants) — is the open question the program surfaces and does not itself resolve.

## Bottom line

For the LLMLL surface exercised, the answer to the founding question is **yes, and robustly**: frontier agents produce first-round-correct, contract-satisfying, body-faithfully-verifiable LLMLL at a rate that saturates the benchmark. The empirical loop confirmed the one-shot-correctness premise the language was built on. What it leaves open is not whether agents can write verifiable LLMLL — they can — but where, if anywhere, the verifier's error-catching value becomes observable rather than latent.
