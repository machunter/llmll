# LLMLL

## What This Is

LLMLL is an AI-to-AI programming language and its compiler: an agent writes a contracted program,
the compiler checks it, and the verifier either discharges the contract's obligations against a
decidable fragment or says exactly what stayed unproven. The compiler is Haskell (`compiler/`),
with a Rust runtime (`runtime/`) and a Python multi-agent orchestrator
(`tools/llmll-orchestra/`). Verification runs through liquid-fixpoint and z3.

## Core Value

A `verified` verdict means what it says. The compiler must never certify an obligation it did not
actually discharge, and where it cannot discharge one it must name the gap rather than absorb it.

Everything else on this project (fragment width, agent ergonomics, throughput) is subordinate to
that. The backlog of record states the governing criterion as *progress toward one-shot
correctness*: does a deliverable reduce iteration burden, increase obligation completeness, or
shorten repair distance for an agent writing LLMLL.

## Requirements

### Active

This milestone is the **compiler backlog, targeting v0.15**. Five requirements, all carrying
precedence-0 authority from `docs/compiler-team-roadmap.md`:

- [x] `REQ-wild-assume-2` — extend the WILD-ASSUME restriction to the `map[k,bool]` arm. Validated in Phase 1, shipped v0.14.74 (2026-08-01). The phase also closed a `TDependent`-wrapper evasion that defeated the `bytes[n]` arm shipped in v0.14.73.
- [ ] `REQ-ret-resolve` — RET-RESOLVE SC3', transitive wildcard return resolution
- [ ] `REQ-fact-ag` — route type-derived VC assumptions through assume-guarantee
- [ ] `REQ-oblig-1-def-invariant` — `def-invariant` axioms in the obligation report `assumptions` field
- [ ] `REQ-contract-read-lint-residual` — the two deferred contract-read lint tiers

Full text, acceptance, and per-requirement provenance: `.planning/REQUIREMENTS.md`.
Phase mapping: `.planning/ROADMAP.md`.

### Deferred (not dropped)

Forty-one further requirements are carried into
`.planning/REQUIREMENTS.md` as a tracked backlog, grouped by track: module-system codegen,
sandboxing/WASM, data-scope levers, Lean tier (LEAN-GA), obligations and spec text, patch/refine
slicing, RFC-SWARM phases 1 to 4, SPEC-AGREE-1 build order a to e, integer semantics, research
track R1/R2/R4, and two items with no backing roadmap row. A future milestone picks one track up.

`REQ-int-3` (`MachineInt` QF-BV alias) joined this list on 2026-07-31, having been scoped in at
bootstrap. Its stated acceptance is a promotion condition that did not fire: INT-PRE measured a
1.015x TOTP regression against a 5x threshold.

### Out of Scope

Permanently excluded, with the reasons the roadmap records:

- Rust codegen backend (dropped v0.1.2; Haskell is the permanent target)
- Python FFI tier (breaks WASM compatibility, dynamically typed)
- A full Lean 4 proof agent built from scratch (Lean discharge goes through Leanstral / LEAN-GA)
- UI / web frontend (target domains are backend)
- IDE plugins (premature; stabilize the CLI and HTTP interface first)
- Indexed / dependent types (research track R1)
- `ELambda` higher-order body VCs (outside `Sigma_auto` by design; lambdas lower to runtime
  contracts; revisit only with a concrete verified-HOF use case)
- `EDo` / effectful bodies inside `Sigma_auto` (effects verify on the capability / effect-row axis,
  not via SMT posts)
- Uncontracted-callee body VCs (contract inference is deliberately local; the contract-only
  fallback is the recorded decision)

## Context

**Released version at milestone start: v0.14.73.** The immediately preceding release closed
SAFE-ARG, the first defect on the FQ-RESULT-SORT line that did not fail closed: a bare inference
wildcard let a `bytes[32]` value satisfy a `bytes[64]` parameter through one unannotated hop, the
verifier asserted `bytesLen(b) = 64` from that parameter's declared type, and the index-in-bounds
obligation was discharged against a false premise. The run reported `SAFE` and persisted a
`verified` sidecar. Codegen's own dynamic bounds check traps at runtime, so what was falsely
certified is the obligation, not a memory read.

Four of the six in-scope requirements sit on the residue of that line:

- `REQ-wild-assume-2` is the `map[k,bool]` arm of the same fix (stage 1 was `bytes[n]`-only).
- `REQ-ret-resolve` is the root-level closure of nine measured crash shapes, deliberately queued
  behind WILD-ASSUME because one of its behaviour channels can turn a crash into `verified`.
- `REQ-fact-ag` is the general form that WILD-ASSUME approximates: no fact derived from a type
  enters a VC antecedent unless the function that declared that type discharged it.
- `REQ-oblig-1-def-invariant` makes the remaining assumptions visible in the obligation report.

**Fragile area the milestone works inside.** The type channel (`TypeCheck.hs`) and the
verification channel (`FixpointEmit.hs`) maintain parallel derivations of type and sort
information. Divergence between them produced FQ-RESULT-SORT-1, FQ-CTOR-COLLIDE-1, and SAFE-ARG.
Every change here needs a measurement gate against the corpus, not a code-review argument.

**Prior art the ingest carried in.** Eighteen documents were classified (12 SPEC, 6 DOC, 0 ADR,
0 PRD). See `.planning/intel/SYNTHESIS.md` for the entry point, `.planning/INGEST-CONFLICTS.md`
for the 20 informational resolutions.

## Constraints

- **Verification boundary**: `Sigma_auto` is bounded by *decidability*, the guarantee that "SAFE"
  is a decidable predicate on a fixed VC. It covers QF-LIA integers, non-recursive tagged unions,
  closed length measures, bool, and (since Lever A) the theory of arrays over `bytes[n]` and
  `map[k,v]` with `{int,string}` keys and `{int,bool,string}` values. List structure (Lever B) and
  recursive data (Lever C) are outside. Widening the boundary to rescue a target is a standing
  anti-pattern: halt and re-target instead.
- **Release ceremony is part of the work, not follow-up**: `scripts/version_gate.sh` requires the
  version to agree across `README.md` line 1, `LLMLL.md` line 1, the top `## vX.Y.Z` heading in
  `CHANGELOG.md`, `compiler/package.yaml`, and `compiler/llmll.cabal`, plus schema-version
  agreement between `docs/llmll-ast.schema.json` and `ParserJSON.expectedSchemaVersion`. A phase is
  not complete until that gate exits 0.
- **Tech stack**: Haskell GHC 9.6.6 via Stack (resolver lts-22.43) in `compiler/`; Rust 2021 in
  `runtime/`; Python 3.10+ in `tools/llmll-orchestra/`. `z3` and the liquid-fixpoint binary must be
  on PATH for `verify`.
- **Build hygiene**: `stack exec llmll` resolves to a stale binary from some working directories
  and the version string does not detect it. Use `(cd compiler && stack build --dry-run llmll)`;
  "Nothing to build." means current. Do not compare mtimes, which is wrong about correct input.
  **Ordering matters (measured in Phase 1):** a bare `stack build llmll` does NOT settle the
  package. After any source or cabal edit the dry-run keeps reporting `Would build:` on the
  Cabal-autogenerated `Paths_llmll.hs`, and `stack build --test --no-run-tests` does not clear it
  either; only a full `stack test` does, occasionally needing two cycles. So run `stack test`
  BEFORE asserting `Nothing to build.`, then run the corpus gate while the assertion holds. A gate
  that asserts currency immediately after `stack build` fails for a reason unrelated to staleness,
  which reads as a broken toolchain and invites weakening the check.
- **Document division of labor**: `LLMLL.md` is the language reference, `docs/compiler-team-roadmap.md`
  is the engineering backlog (tickets, acceptance, decisions), `CHANGELOG.md` is release history.
  `[SPEC]`-tagged work must land in `LLMLL.md` before or alongside its implementation.
- **Evaluation integrity**: for every agent-facing exercise, the `checkout` brief is the sole
  information channel. No hints, no forced failures, no sight of another agent's attempt.
- **Claim discipline**: agreement and absence-of-failure are not evidence. A corpus run with zero
  new failures is a regression check, not a demonstration that a fix works. Where a fix has no
  reaching witness, the phase says so rather than claiming an exploit refuted.

## Key Decisions

**Status: zero decisions are LOCKED.** The ingest set contained no ADR-typed document and no
document carrying an `Accepted` or locked status, so all 24 recorded decisions sit at
`status: proposed`. They are recorded here as context that constrains planning, not as settled
authority. Full text and per-decision provenance: `.planning/intel/decisions.md`.

| Decision (proposed) | Rationale | Outcome |
|---|---|---|
| The if-join wildcard preference ships as RET-RESOLVE SC3', not RET-BRANCH-PREF Stage 2 | Professor review Round 1 finding 1 classifies the unconditioned preference as soundness-adjacent and recommends same-SCC conditioning (Milner 1978; Damas and Milner 1982; Jones 1999 §11) | — Pending (reversible; INFO-2/INFO-3) |
| Integer semantics option (a); `MachineInt` stays post-freeze | INT-PRE cleared the cost gate at 1.015x against a 5x threshold, so INT-3 is recorded dormant | — Pending; the milestone honors the dormancy (scoped out 2026-07-31, deferred backlog) |
| Contract-position reads are total selects; status quo plus a scoped non-blocking lint | Sound in both directions; heuristic tier and Dafny-style side-obligation deferred | — Pending |
| Acyclicity policy for `refine` cycle-creating spawns: Option 3 | Admit, detect, degrade cycle members to contract-only with the trust meet floored | — Pending |
| CDP default-on deferred | All preconditions closed by v0.14.4, cost is 2-3x verify time; `--strict-verify` opt-in preferred | — Pending |
| Full categorical unification declined; Path B mechanized soundness declined | Professor adjudication: disproportionate; the patch-merge invariant stays stipulated | — Pending |
| LEAN-GA is a three-layer rebuild; T-B (server-as-checker) is the trust-correct transport | The model is untrusted proof search, the Lean kernel is the trusted gate | — Pending |
| SPEC-AGREE-1 domain is `Sigma_subsume`, computed per contract; reporting is detection yield, never an unstratified agreement rate | Comparable fraction measured at 10.6% (9/85), an upper bound until re-derived through the real classifier | — Pending |
| Gate J's exclusion-ratio ceiling retired; three conditions replace it | A ratio tracks the genre composition of the target document, not verifier reach | — Pending |
| Majority voting on formalization disagreement rejected | Voting hides disagreement and can certify a shared error (Brilliant, Knight and Leveson) | — Pending |
| Stale-binary detection: ask the build tool | Version strings and mtimes are both wrong about correct input; measured | — Pending |

---
*Last updated: 2026-08-01 after Phase 1 completion (v0.14.74)*
