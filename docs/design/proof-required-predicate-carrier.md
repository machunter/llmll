# `?proof-required` Predicate-Carrier Expansion — Deferred Design Exploration

> **Status (2026-05-23): Superseded by LT-PPR (v0.11).** The revisit conditions at §"Conditions for revisit" below are satisfied: (1) feature freeze lifted for v0.11 per [`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md) Feature Freeze Policy (architectural correction); (2)(b) downstream-consumer benefit recognized via the core/shell inversion at [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §1.4 — predicate-carrying form is the natural escape hatch from core into shell with retained semantic content. LT-PPR proposal settled in conversation 2026-05-23 (see [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §6 routing); LT-proposal/review pair lands at `proof-required-predicate-carrier-proposal.md` + `-review.md` (drafting). This deferred-exploration doc is preserved as the seed material; the settled v0.11 design lives in the new proposal doc.

> **Historical status (pre-2026-05-23):** Deferred — out of scope under feature freeze (`docs/compiler-team-roadmap.md:28-31`).
> **Origin:** LT-B Risk #4 (post-experiment-001/002 batches, 2026-05-11).
> **Companion:** `findings/postmortem-smoketest-001-002.md` finding #1 (recurrent ambiguity across 5/12 agent attempts).
> **Last updated:** 2026-05-23 (status flip to superseded; original capture 2026-05-11).

This document captures a deferred language-design idea so it is not lost. It is not a proposal awaiting implementation — it is a placeholder for a future LT-proposal/review pair when the conditions for revisit are met. **The "future" referred to is now v0.11 (2026-05-23); see status note above.**

---

## The idea

Currently `?proof-required` is a **leaf hole**. `HoleKind.HProofRequired Text` in `compiler/src/LLMLL/Syntax.hs:242` carries only a reason tag (`"manual"`, `"non-linear-contract"`, `"complex-decreases"`). The marker stands in for an unverifiable predicate; the *intended* predicate is documented adjacent to the marker in prose or trust-report annotations, not in the AST.

A richer feature would let `?proof-required` carry the intended predicate inline:

```lisp
(post (?proof-required (or (is-ok result) (= result (err "invalid")))))
```

The predicate would be parsed, typechecked as `bool`, recorded in the trust report as the specific gap-property, and emitted as a runtime assertion fallback in codegen. The marker would still route to the trust channel as `asserted` (per `LLMLL.md §5.3.5` verification matrix) — it remains a gap-signal in the verification fragment hierarchy — but the verifier, trust-report consumers, and future Lean-discharge paths would have a machine-readable property to track.

## Why agents want this (empirical demand)

Per `findings/postmortem-smoketest-001-002.md` finding #1, **5 of 12 attempts across two model providers** independently surfaced the same ambiguity: *"`LLMLL.md §6 / §13.8` shows the S-expression form `(?proof-required (or …))` with an embedded predicate, but `llmll-ast.schema.json` defines only `kind` and `reason` — no field exists to carry the predicate."* This recurrence is a strong empirical signal that the predicate-carrying form is the intuitive default agents reach for when reading `§13.8`'s hook example.

The intuitive value is real:

- **Machine-readable intent.** The intended property is in the AST instead of buried in a comment. Trust report, obligation report, and downstream tooling can extract it without re-parsing prose.
- **Verifier-extension hook.** A future Lean-discharge path (currently parking-lotted per `docs/compiler-team-roadmap.md`) can ingest the predicate as input directly.
- **Runtime fallback path.** Codegen could emit a runtime assertion over the predicate as a "weak verification" — catches the violation at execution time even though static verification gave up. Closes the gap between "documented intent" and "executable check."
- **Surface uniformity.** A `?proof-required` clause with a predicate behaves like a regular `pre`/`post` clause that the verifier explicitly declined to discharge, rather than a special leaf form. Uniform syntax across the contract surface.

## What it would require

Substantial cross-cutting work:

| Layer | Change |
|---|---|
| **Schema** (`docs/llmll-ast.schema.json`) | Add `predicate: Expr` field to `hole-proof-required`. Relax `additionalProperties: false` accordingly (or list `predicate` in `properties`). Bump schema version. |
| **AST** (`compiler/src/LLMLL/Syntax.hs:242`) | Extend `HProofRequired Text` to `HProofRequired Text (Maybe Expr)` or similar. Round-trip through `AstEmit.hs`. |
| **Parsers** (`ParserJSON.hs`, `Parser.hs`) | Add optional-predicate parsing to both the JSON-AST `"hole-proof-required"` branch and the S-expression hole form per `§12:1583-1589`. |
| **Typechecker** (`TypeCheck.hs`) | When the predicate is present, typecheck it as `bool` in the surrounding `pre`/`post` context with `result` bound where applicable. The clause still routes to trust as `asserted` (verifier does not attempt discharge). |
| **Trust report** (`TrustReport.hs`) | Include the predicate text alongside the asserted-without-proof marker. Surface in `--trust-report` output and obligation reports. |
| **Codegen** (`CodegenHs.hs`) | Emit the predicate as a runtime assertion fallback (`Control.Exception.assert` or equivalent). Currently the leaf marker emits no runtime check; the predicate-carrying form is closer to "weak verification." |
| **Verifier** | **Unchanged.** The predicate is not sent to liquid-fixpoint — `?proof-required` exists *because* the predicate is outside QF-LIA per `LLMLL.md §5.3.3 / §5.3.5`. The predicate is informational for trust + runtime, not constraint-emission. |
| **Spec text** | `§6` clarifies the predicate's role. `§13.8` example becomes canonical (currently corrected to leaf form by LT-B.1). `§12` grammar adds the predicate slot to the hole form. |

Rough size estimate: ~200–400 LOC across the compiler plus ~30 spec lines plus schema-version bump and downstream-fixture updates (mirrors the schema-version bump shape from v0.10.2). Test surface: ~10–15 new unit tests for the new typecheck + parse paths.

## Why deferred

1. **Feature freeze.** Per `docs/compiler-team-roadmap.md:28-31`, freeze runs through v0.10. The richer form is a language-surface change — adds a predicate slot to the AST and grammar. Out of scope under the current freeze policy. Exceptions require explicit team consensus with a written soundness argument; no such argument exists yet.

2. **Substantial scope.** Per the breakdown above: schema + AST + two parsers + typechecker + trust report + codegen + spec text + tests. Not a clarification, a real expansion of the language surface.

3. **Workaround exists.** Per LT-B.1, agents can document the intended predicate adjacent to `(post ?proof-required)` as a source comment or in trust-report annotations. The information loss is real but not blocking — agents and reviewers can locate the predicate, just not via direct AST traversal. The §13.8 corrected example (LT-B.1) is expected to retire the immediate ambiguity once DL-B ships.

4. **Demand may be artificial.** The 5/12 recurrence is a symptom of LT-A D3's broken example (which I introduced), not of agents needing the feature for a specific downstream use case. Once §13.8 is corrected and agents see the canonical bare-marker form, the demand may evaporate. **Re-evaluate after the next post-DL-B experiment batch** before promoting this idea.

## Conditions for revisit

Re-open this exploration when **both** hold:

1. **Feature freeze is lifted** (post-v0.10 — confirmed via roadmap update).
2. **Either** (a) ≥2 experiment batches post-DL-B show recurrent agent demand for the predicate-carrying form *that is not explained by §13.8 confusion* (i.e., agents who saw the corrected example and still want the richer form for a stated reason), **or** (b) a downstream consumer — Leanstral integration, obligation-report mining, runtime-assertion tooling — would meaningfully benefit from the predicate being machine-readable rather than prose-buried.

When revisited, this document becomes the seed for a full LT-proposal/review pair. The proposal half goes here at `docs/design/proof-required-predicate-carrier-proposal.md`; the professor review would land at `docs/design/proof-required-predicate-carrier-review.md` per the established proposal/review naming pattern.

## Open questions for the eventual proposal

- **Predicate semantics for `result` binding.** A `post (?proof-required pred)` with `pred` referencing `result` would need the same binding rule as `(post pred)`. Confirm with the existing `result` handling at `LLMLL.md §13.10`. No new binding semantics anticipated.
- **Interaction with QF-LIA partition.** If the predicate is QF-LIA-tractable, should the verifier attempt discharge and downgrade the marker to a regular `pre`/`post` clause? Or should the marker remain explicit ("agent declared this is a gap") regardless of decidability? Either is defensible; spec needs to pick.
- **Trust-level effect.** The marker currently routes to `asserted`. With a predicate present and a runtime-assertion-fallback emitted, is the trust level `asserted-with-runtime-check` (a new fourth status alongside `verified`/`contract-checked`/`tested`/`asserted`)? Or does the runtime check not change the trust label? Affects the `DisplayLevel` diamond lattice at `LLMLL.md §5.3.5` and `compiler/src/LLMLL/Syntax.hs` `DisplayLevel`.

These are questions for the eventual proposal, not for this capture. Recording them so the future LT-proposal does not have to re-derive them.

---

**Status notes**

- Captured 2026-05-11 from LT-B Risk #4 in the LT-B proposal turn.
- LT-B.1 (canonical bare-marker example fix in §13.8) is the in-flight corrective for the recurrent ambiguity. DL-B implements.
- This document lives in `docs/design/` as a design exploration, not a proposal awaiting implementation. INDEX entry pending.
