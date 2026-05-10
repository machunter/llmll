# Language Team — Findings from Experiment 001

**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — rewritten under the new five-role pipeline. Items E1–E3 moved to `findings/experiment-lead.md`. Items S1 and S3 are primarily `compiler-engineer` work — see `findings/compiler-engineer.md`; this file retains only the small spec touches that pair with them. The remaining first-class items (S4 + D2 + D3) are bundled into a single design proposal — Activity LT-A — covering the AI-agent-facing pedagogical surface in `LLMLL.md §11.2 / §12 / §13.8` and `docs/getting-started.md §4`.

This file covers one work unit:

- **LT-A — Pedagogical surface design proposal**: one design proposal covering identifier shape in JSON-AST (S4), three-layer Result-pattern resolution (D2), `?proof-required` pedagogical hook (D3), and small spec touches on S1 (typing rule for `?delegate` fallback) and S3 (test-status taxonomy if `unknown` is user-visible).

The rationale for bundling: all five touches sit in adjacent neighborhoods of `LLMLL.md` and `docs/getting-started.md §4`. They are pedagogical surface aimed at AI agents — the project's primary consumer. Splitting risks inconsistent tone across adjacent paragraphs.

Document drafts produced by this skill should land at `docs/design/<topic>.md` per the established proposal/review pattern (see `docs/design/oblig-0-spec.md`, `docs/design/invariant-discovery-proposal.md`); the `documentation-lead` then promotes settled content into `LLMLL.md` and `docs/getting-started.md` after `compiler-engineer` ships any blocking implementation. See `findings/documentation-lead.md` for the doc-pass items (DL-A).

---

## LT-A · Pedagogical surface design proposal

### S4. JSON-AST Permits Dotted `app.fn` Despite the Documented Constraint

**Priority:** Defence in depth (not a blocker, but should land in parallel with the other LT-A items)

#### Evidence

- `docs/llmll-ast.schema.json:630` — prose constraint "ASCII only. No dots.", no `pattern` regex attached.
- [ParserJSON.hs L428–431](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ParserJSON.hs#L428-L431) — `qual-app` collapses to `EApp` with a dotted name.
- `LLMLL.md §12:1571,1581` — EBNF: dotted identifiers belong to `qual-ident`, hence `qual-app`.

Dotted names parse and survive into the typechecker's name-keyed lookup table without constraint.

#### Resolution (normative)

The identifier regex is normative; document it once in the schema and once in `LLMLL.md §12` so the EBNF and the schema cannot drift. Proposed shapes:

```json
"ExprApp.fn":          { "pattern": "^[A-Za-z_][A-Za-z0-9_?\\-]*$" }
"ExprQualApp.qual_fn": { "pattern": "^[A-Za-z_][A-Za-z0-9_?\\-]*(\\.[A-Za-z_][A-Za-z0-9_?\\-]*)+$" }
```

The `?` and `-` characters preserve the existing identifier convention (`string-empty?`, `is-ok`, etc.; see [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129)). The `qual_fn` pattern enforces `IDENT { "." IDENT }` per the EBNF.

**Enforcement scope:** schema-side validation is sufficient. Paired parser-side enforcement at `ParserJSON.hs:428-431` is *optional defence in depth* and is recorded as conditional CE-C in `findings/compiler-engineer.md`. Default recommendation: schema-only.

#### Acceptance

A JSON-AST validator rejects `{"kind":"app","fn":"Result.Error",...}` before the parser runs. `qual-app` requires at least one dot. The regex appears verbatim in both `docs/llmll-ast.schema.json` and `LLMLL.md §12`.

---

### D2. Three-Layer Result-Pattern Resolution

**Priority:** Agent accuracy. Sequenced after S1 ships.

#### Spec drift identified

`LLMLL.md §13.8` documents `ok`/`err`/`is-ok` as builtins. `LLMLL.md §11.2:1267,1300–1301` mixes `Result.Error` (in `on_failure` and prose) with `Success`/`Error` (in match arms). This produced the constructor confusion observed across 18 attempts.

`Result.Ok` and `Result.Error` are **not** registered constructor names in [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129). Their apparent acceptance was a consequence of S1 (the typechecker never traversed the fallback expressions where they appeared). Once S1 ships, `Result.Error` in `on_failure` will fail to typecheck and the existing examples become broken.

#### Resolution (normative)

The compiler is canonical. Three-layer rule, normative:

- **Construct values.** Use `(ok x)` and `(err e)` — the typed builtins from [TypeCheck.hs L125–127](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L125-L127).
- **Match values.** Use bare `Success` and `Error` constructors. [CodegenHs.hs L692–697](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L692-L697) confirms these are the canonical pattern names; codegen rewrites them to Haskell `Right`/`Left`.
- **Test values.** Use `(is-ok x)` for boolean property checks. There is no `is-Result`; structural assertions go through `match`.

`Result.Ok` and `Result.Error` are explicitly *not* registered names. Documenting them as aliases would bless accidental behaviour. Remove from spec examples wherever they appear in `LLMLL.md`.

#### Acceptance

`LLMLL.md §11.2 / §13.8` and `docs/getting-started.md §4` describe the three layers consistently. Zero remaining occurrences of `Result.Ok` or `Result.Error` in spec examples. The `compiler-engineer` S1 fix and this resolution land in the same release; CHANGELOG entry references both.

#### Appendix: Constructor Usage Across 15 Passing Solutions

- `ok`/`err`/`is-ok` (fn calls): 9 of 11 passing runs — the dominant pattern.
- `Result.Error` as `app.fn`: 1 occurrence (Flash try1, a *failing* run).
- `Result.Error` as `qual_fn`: 1 occurrence (Flash try2, passing).
- `Result.Ok`: 0 occurrences.
- `Success`/`Error` as match pattern: 0 occurrences across all 15 passing solutions.

The constructor-confusion narrative is a real but minor effect; the soundness blockers in `findings/compiler-engineer.md` (S1, S3) dominate.

---

### D3. `?proof-required` Pedagogical Hook

**Priority:** Required for experiments 002/003 to produce a meaningful grade-A signal.

#### Problem

Across all 15 passing solutions, zero `?proof-required` markers were emitted. [evaluate_run.py L76,82–86](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L76-L86) shows experiments 002 and 003 set `post.proof_required: True` on key contracts — the marker is the documented escape there. The current spec introduces `?proof-required` only in `LLMLL.md §12:1583–1589` (grammar) and verification prose (§5.3.5), far from where agents look first.

#### Resolution (normative)

Add a top-level entry to `docs/getting-started.md §4` and a paragraph in `LLMLL.md §13.8` connecting Result helpers to the proof-required escape: when the contract on a function is asserted but cannot be verified (delegation, non-linear arithmetic, map invariants), mark the contract clause `?proof-required` and the agent receives credit for declaring the obligation rather than papering it over.

The pedagogical hook in `§13.8` is small — one paragraph anchored to the existing Result-helpers section, since contracts on Result-returning functions are the most common case where the escape applies.

#### Acceptance

`docs/getting-started.md §4` has a `?proof-required` entry that explains when to use the marker, with at least one worked example. `LLMLL.md §13.8` has a paragraph linking Result helpers to the proof-required escape. Re-running experiment 002 (after E3 fix lands) produces non-zero `?proof-required` emissions on the verification-bounded contracts.

---

### Small spec touches paired with `compiler-engineer`

These are not standalone LT-A items; they are spec edits that travel with the corresponding compiler implementations. Each is one or two sentences of prose, not a full design.

#### S1 (paired with `compiler-engineer` CE-A)

If `LLMLL.md §11.2` does not currently state explicitly that the fallback expression in `?delegate ... → T (on-failure e)` is checked against the delegate return type `T`, add the rule:

> `Γ ⊢ e : T` is required for `?delegate ... → T (on-failure e)` to be well-typed.

The compiler implementation does not block on this edit; the spec edit should land in the same release for consistency. Empirical likelihood that the rule is already implicit in §11.2: high. Verify before drafting.

#### S3 (paired with `compiler-engineer` CE-A)

If the new `unknown` status from PBT vacuity fix becomes user-visible in `llmll test` output, the test-status taxonomy in the spec needs to record it. Likely placement: the `LLMLL.md` section that documents `llmll test`. Status name is `compiler-engineer`'s call; spec-side decision is recording it as a public status alongside `pass`/`fail`/`skip`.

---

## Withdrawn

**"Treat `Result.Ok` ≡ `ok`, `Result.Error` ≡ `err` as accepted aliases."** Withdrawn. [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129) defines `ok`/`err`/`is-ok`/`unwrap`/`unwrap-or` as the only Result-related builtins. `Result.Ok` and `Result.Error` are not registered constructor names. Their apparent acceptance was a consequence of S1. Documenting them as aliases would bless accidental behaviour.

**"Document the A-grade ceiling per experiment."** Withdrawn. Replaced by `experiment-lead` E3 — fix the contract-expectation inconsistency rather than documenting it.

---

## Priority

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| **D2** | Three-layer Result resolution | Agent accuracy | Low (after S1) |
| **D3** | `?proof-required` pedagogical hook | Required for 002/003 | Low |
| **S4** | Identifier-shape regex (normative) | Defence in depth | Low |
| **S1** small touch | Fallback typing rule clarification | Joint with CE-A | Trivial |
| **S3** small touch | `unknown` status taxonomy | Joint with CE-A | Trivial |

## Hand-offs

- **`compiler-engineer`** — S1 and S3 implementation owners. This file's small touches travel with their implementation. See `findings/compiler-engineer.md`.
- **`experiment-lead`** — none. E1, E2, E3, D1.1, D4 are wholly within harness scope. See `findings/experiment-lead.md`.
- **`documentation-lead`** — Activity DL-A: writes the schema patch (S4), the LLMLL.md and `docs/getting-started.md` edits (D2, D3), and the CHANGELOG entry. Sequenced after S1 ships **and** LT-A is approved by user. See `findings/documentation-lead.md`.
- **`professor`** — none. The five LT-A items are spec/pedagogy reconciliation against the existing compiler, not novel design that requires outside-PL adjudication. If user wants a sanity check on the regex shape (S4) or the three-layer Result rule (D2) against external precedent, route after this file is settled.
