# minimal-agent harness — findings (consolidated 2026-05-25 per DOC-CONSOLIDATE §M1)

> Previously fanned out across `findings/{compiler-engineer,language-team,experiment-lead,documentation-lead}.md`. Collapsed to H2-per-role per `docs/design/doc-consolidation-2026-05-24-proposal.md` §4.3. Skills grep their own H2 anchor; internal section headings are demoted one level so each wrapper H2 owns its subtree.

## Compiler-engineer

---

### F-GATE-1. `GrammarCoreInversion` not enforced for `.ast.json` input

**Source:** §8 pre/post comparison, `postmortem-003-s8-gate-pre-post.md`
**Date:** 2026-05-28
**Priority:** Closed — F-GATE-1: commit `cabb1fd` (def-logic JSON-AST); F-GATE-1b: commit `12cd85d` (letrec JSON-AST + S-expression symmetry). §8 gate unblocked; re-run with `manifest.s8-post-e001.json` against HEAD compiler.

`ParserJSON.hs` has no `GrammarMode` parameter. `llmll --grammar=core-inversion check solution.ast.json` accepts `{"kind":"def-logic"}` statements and exits 0. Confirmed on post-arm run `runs/20260528T014158Z/20260528T014158Z-claude-opus-4-7-try01-of-03-e001/solution.ast.json` (two `def-logic` statements, exit 0, `OK (5 statements)`).

**Fix:** In `ParserJSON.hs`, pass `GrammarMode` to the statement-kind dispatch. When `GrammarCoreInversion` and `kind == "def-logic"`, emit a `core-grammar-violation` diagnostic (kind already defined at `Diagnostic.hs:300`) and exit 1. Parser-level enforcement (consistent with S-expression path at `Parser.hs:137`) is preferred over typechecker-level.

**Acceptance:** `llmll --grammar=core-inversion check <file-with-def-logic.ast.json>` exits non-zero with `core-grammar-violation` diagnostic. Post-arm re-run against fixed compiler produces a non-trivial `def`/`def-shell` usage distribution (boundary-form axis of §8 gate becomes measurable).

---

### F-GATE-8. `def-shell + bare hole-proof-required` post trust status is pre-clause-dependent

**Source:** `findings/postmortem-005-s8-gate-redesigned-run.md`
**Date:** 2026-05-29
**Priority:** Medium — compiler investigation required.

Four `def-shell` functions with identical `post: {"kind":"hole-proof-required","reason":"non-linear-contract"}` and `hole-delegate` body produce different trust statuses for the post clause, correlated with the pre clause shape:

| Pre clause | post trust_status |
|-----------|-------------------|
| `string-length(password) > 0` | `"asserted"` |
| `not(string-empty?(password))` | `"tested (100 samples)"` |

A `def-shell` function containing `hole-delegate` in its body should produce `post: "asserted"` unconditionally — the delegation hole makes the return value opaque. The behavioral difference suggests that `string-length` being absent from the PBT static evaluator causes the verifier to flag the whole function "asserted" before attempting the post clause, while `not(string-empty?)` being evaluable causes the verifier to attempt PBT on the bare `hole-proof-required` post independently.

**Route:** `FixpointEmit.hs` / `Contracts.hs` — verify that the `def-shell + hole-delegate` path marks all contract clauses "asserted" regardless of pre clause evaluability.

**Acceptance:** `llmll verify` on a `def-shell` function with `not(string-empty? password)` pre, bare `hole-proof-required` post, and `hole-delegate` body reports `post: asserted`.

Evidence runs: `runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try02-of-05-e001/` (pre-clause-dependent "asserted") and `runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try03-of-05-e001/` ("tested (100 samples)").

---

**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — split from former `language-team.md` (S1, S3) and `documentation-team.md` (D1.2) under the new five-role pipeline. `compiler-engineer` owns implementation in `compiler/src/LLMLL/`.

This file covers two work units:

- **CE-A — Soundness blockers** (S1 + S3): two compiler bugs that block grade-A signal on delegation-shaped problems. `?delegate` fallback expression is never typechecked; PBT vacuity defaults unevaluable property samples to `True`.
- **CE-B — Diagnostic surface** (D1.2): `llmll check` text-mode renderer suppresses accumulated warnings on success.

A conditional **CE-C** item (parser enforcement of S4 identifier-shape regex) is gated on the `language-team`'s S4 resolution — see `findings/language-team.md`. CE-C only fires if the language-team requests belt-and-suspenders enforcement at `ParserJSON.hs:428-431` in addition to JSON Schema validation.

---

### CE-A · Soundness blockers

#### S1. `on_failure` Is Parsed but Never Typechecked

**Priority:** Blocker — no grade-A signal on delegation-shaped problems is meaningful until this ships.

##### Evidence

[TypeCheck.hs L1030](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L1030):

```haskell
inferHole (HDelegate spec) = pure (delegateReturnType spec)
```

The fallback expression in `delegateOnFailure` is never visited by the typechecker. [ParserJSON.hs L548](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ParserJSON.hs#L548) admits it into the AST, but no typing rule constrains it. Any `Γ ⊢ e : ?` is accepted, including ill-formed constructor applications like `(Result.Error DelegationError)`.

##### Why We Saw What We Saw

Flash try1's `(Result.Error DelegationError)` in `on_failure` produced rc=0 from `llmll check` not because non-strict tolerated an unknown function, but because the unknown-function lookup at [TypeCheck.hs L920–940](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L920-L940) is never reached for fallback expressions. The schema's prose constraint at `docs/llmll-ast.schema.json:630` ("ASCII only. No dots.") is independently unenforced — but that is downstream of the dropthrough, and is in the `language-team`/`documentation-lead` track (S4 + DL-A) rather than this file.

##### Fix

`inferHole (HDelegate spec)` must additionally run `checkExpr (delegateOnFailure spec) (delegateReturnType spec)` when the fallback is present.

##### Acceptance

`?delegate ... → T (on-failure e)` holds iff `Γ ⊢ e : T` under the function's typing context. A regression test in `compiler/test/` exercises a `?delegate` whose `on_failure` references an unknown identifier and asserts that `llmll check` emits a diagnostic.

##### Spec touch (joint with `language-team`)

If the typing rule for `?delegate` in `LLMLL.md §11.2` does not currently state explicitly that the fallback expression is checked against the delegate return type, that clarification is owned by `language-team` (LT-A small touch). The compiler implementation does not block on the spec edit, but the spec edit should land in the same release for consistency.

---

#### S3. PBT Vacuity — Unevaluable Properties Default to True

**Priority:** Blocker

##### Evidence

[PBT.hs L205–208, L236–239](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/PBT.hs#L236-L239):

```haskell
tryQuickCheck bindings body
  | all isSimpleType (map snd bindings) = Just (runQC bindings body)

prop env = case evalExprStatic env body of
  Just (ELit (LitBool b)) -> b
  _                       -> True  -- skip unevaluable
```

Properties whose binders pass `all isSimpleType` enter the QuickCheck path. Inside that path, an unevaluable body returns `True` per sample, counting as a successful pass. Empty-binding `for-all` clauses pass the predicate vacuously. Properties with non-simple binders (e.g. `string`) take the higher-level `Skipped` path and do not exhibit this issue.

##### Why We Saw What We Saw

Several runs reported `effective_passed > 0` on checks whose underlying functions emit `error` at runtime per the delegate-codegen behavior in `CodegenHs.hs`. Those passes are not test evidence; they are silent vacuity.

##### Fix

Unevaluable samples must never be counted as `pass`. The principled outcomes are `skip`, `fail`, or a new `unknown` status. Default-True is unsound.

##### Acceptance

For every QuickCheck-eligible property, samples where `evalExprStatic` does not reduce to `LitBool` are categorised explicitly and excluded from the success count. The status surfaces in `llmll test` output. Re-running experiment 001 against the same five-model panel produces zero attempts where `effective_passed > 0` is driven by unevaluable samples.

##### Spec touch (joint with `language-team`)

If the new `unknown` status is user-visible in `llmll test` output, the test-status taxonomy in `LLMLL.md` (the section that documents `llmll test` output) is owned by `language-team` (LT-A small touch). A status name visible to AI agents is normative surface. The compiler implementation can choose any concrete name; the spec-side decision is which name lands.

---

### CE-B · Diagnostic surface

#### D1.2. `llmll check` Text-Mode Suppresses Accumulated Warnings on Success

**Priority:** High leverage, trivial. Pairs with `experiment-lead` D1.1 (require `--strict` in agent instructions); either is independently sufficient, both is preferred.

##### Problem

`llmll check` in text mode prints `OK` on success and suppresses accumulated warnings. Agents that read text output (the default) never see the diagnostic unless `--strict` (warnings → errors with nonzero rc) or `--json` (structured output) is requested. Non-strict mode is sketch-mode tolerance for forward references and holes; warnings emitted in non-strict mode carry information that should still surface.

##### Evidence

Flash try1's solution called `is-Result(...)`. Non-strict `llmll check` exited 0 and the agent concluded the solution was valid. The evaluator ran `--strict` → exit code 1 → grade F. The non-strict warning that would have flagged `is-Result` as an unknown identifier was not rendered to text-mode output.

##### Fix

Update the text-mode rendering path (likely in `compiler/src/LLMLL/Diagnostic.hs`) to surface accumulated warnings on success, while preserving the rc=0 contract of non-strict mode. Concrete shape:

```
OK
  (warning) is-Result: unknown identifier at solution.ast.json:42
  (warning) Result.Error: unknown identifier at solution.ast.json:67
```

The exact format is the engineer's call; `--json` already does this via the structured diagnostics array, so the change is rendering-side, not analysis-side.

##### Acceptance

`llmll check` in text mode prints accumulated warnings on success. Re-running experiment 001 against the same five-model panel produces zero attempts where the agent finalises a solution while non-strict warnings remain unsurfaced.

---

### Conditional CE-C · Parser enforcement for S4 *(may be skipped)*

If the `language-team`'s S4 resolution (identifier-shape regex in `docs/llmll-ast.schema.json`) is treated as the sole enforcement point, no compiler-side change is needed. If the language-team requests paired enforcement at `ParserJSON.hs:428-431` to catch identifiers that bypass schema validation (e.g., ad-hoc parser invocations), `compiler-engineer` adds a regex check at the qual-app collapse site. Default assumption: schema-only enforcement, CE-C does not fire.

---

### Withdrawn

**"Treat `Result.Ok` ≡ `ok`, `Result.Error` ≡ `err` as accepted aliases"** — withdrawn. [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129) defines `ok`/`err`/`is-ok`/`unwrap`/`unwrap-or` as the only Result-related builtins. `Result.Ok` and `Result.Error` are not registered constructor names. Their apparent acceptance was a consequence of S1. Documenting them as aliases would bless accidental behaviour. Resolution lands in `language-team` D2 (three-layer rule) and `documentation-lead` DL-A (mechanical edits).

---

### Priority

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| **S1** | Typecheck `on_failure` | Blocker | Low |
| **S3** | PBT vacuity | Blocker | Low |
| **D1.2** | Text-mode warning surface | High leverage, trivial | Low |
| **CE-C** | Parser regex enforcement *(conditional)* | Defence in depth | Low |

### Hand-offs

- **`language-team`** — small spec touches on S1 (typing rule for fallback expression in `LLMLL.md §11.2`) and S3 (test-status taxonomy if `unknown` is user-visible). See LT-A small-touch items in `findings/language-team.md`.
- **`experiment-lead`** — companion item D1.1 (require `--strict` in `agent-instructions.md`). See `findings/experiment-lead.md`.
- **`documentation-lead`** — CHANGELOG entry under the version that ships S1 + S3 + D1.2; `docs/getting-started.md §4` Known-Good Patterns may want an entry on warning surfacing. See DL-A in `findings/documentation-lead.md`.

### Suggested branch shape

- `fix/delegate-fallback-typecheck` — S1
- `fix/pbt-vacuity-unknown-status` — S3
- `fix/check-text-mode-warnings` — D1.2

Bundle is engineer's call; suggest separate branches because the three modules are independent and the test-count delta is easier to attribute.

---

## Language-team

---

### F-GATE-2. LLMLL.md §4.1 note should state `def-logic` is rejected under `--grammar=core-inversion`

**Source:** §8 pre/post comparison, `postmortem-003-s8-gate-pre-post.md`
**Date:** 2026-05-28
**Priority:** Closed — defence-in-depth edit applied 2026-05-29 (commit `71658b7`). `LLMLL.md §4.1` main body now contains an explicit standalone rejection sentence; the substance was already present in the Note (v0.11 LT-INV) but lacked main-body-flow visibility. Overtaken by a prior spec update 2026-05-28; doc-lead pass 2026-05-29 applied the deferred sentence.

Post-arm claude-opus-4-7-try03 logged `def-logic` under core-inversion grammar as a PROBLEMS.md spec ambiguity (`runs/20260528T014158Z/20260528T014158Z-claude-opus-4-7-try03-of-03-e001/`). The agent read §4.1 but found no explicit statement that `def-logic` is *rejected* — only that `def`/`def-shell` are *activated*. 1 of 6 post-arm agents surfaced this ambiguity explicitly; 5 did not.

**Fix:** Add one sentence to LLMLL.md §4.1 Note: "`def-logic` is not accepted under `--grammar=core-inversion`; use `def` (strict-core) or `def-shell` (permissive)." Small prose touch, no design change.

**Acceptance:** §4.1 contains explicit rejection statement. Zero agents log `def-logic` under core-inversion as an ambiguity in post-arm re-run.

---

---

### §8 Gate Adjudication Hand-off (2026-05-28)

**Source:** `findings/postmortem-004-s8-gate-post-arm-rerun.md`
**Run:** `20260528T145727Z` — 6 attempts, llmll 0.10.8 @ `4252b5f`

Four-axis table for gate outcome determination per `docs/compiler-team-roadmap.md:185`:

| Axis | Pre-arm | Post-arm (clean, n=4) | Delta |
|------|---------|----------------------|-------|
| (a) Pass rate | 6/6 B | 4/4 B | No change |
| (b) Verified | 0/6 | 0/4 | No change |
| (c) ?proof-required | 0/6 | 0/4 | No change |
| **(d) def/def-shell** | **0/6 (0%)** | **8/8 (100%)** | **Axis measurable for first time** |

Clean gate dataset (enforcement-valid, no 429 confounders): claude-opus-4-7 ×3 + gemini-try02 ×1. Gemini try01 excluded (infrastructure failure, 0 output). Gemini try03 excluded from quality axes (grade F attributable to 429-induced session degradation).

**Gate success condition per run plan:** at least one of (a/b/c) improving AND axis (d) > 0. Data: (a/b/c) unchanged; (d) = 100%.

F-GATE-2 (§4.1 prose clarification) — **downgraded to defence-in-depth** at gate adjudication 2026-05-28. The diagnostic hint was sufficient for in-session adaptation (claude try03 documented: "initial `def-logic` rejected → switched to `def-shell`"). **Defence-in-depth edit applied 2026-05-29 (commit `71658b7`):** one sentence added to `LLMLL.md §4.1` main body: "Under `--grammar=core-inversion`, the keyword `def-logic` is rejected at parse time (exit 1, `core-grammar-violation` diagnostic); use `def` for the strict-core form or `def-shell` for the permissive form." Placed before the Note (v0.11 LT-INV) blockquote for main-body-flow visibility. Finding is **closed**.

Gate outcome determination (pass/partial/null per roadmap §8 criteria) is language-team's slot.

---

### §8 Gate Adjudication Close-out (2026-05-28/29)

**Source:** `findings/postmortem-005-s8-gate-redesigned-run.md`
**Run:** `20260528T204620Z` — 8 attempts, manifest `manifest.e001-post-e3.json`, evaluator EL-1+EL-2+E3

Four-axis table (redesigned gate, vs pre-arm `20260528T012230Z`):

| Axis | Pre-arm (n=6) | Post-arm valid (n=6) | Delta |
|------|--------------|----------------------|-------|
| (a) Pass rate | 6/6 B | 6/6 (3× A, 3× C) | Grade A first seen |
| (b) Verified | 0/6 | 0/6 | No change |
| **(c) `?proof-required` emission** | **0/6 (0%)** | **3/6 (50%)** | **Improves — gate criterion met** |
| (d) def/def-shell | 0/6 (0%) | 10/10 (100%) | Confirmed |

Gate pass criterion (`docs/compiler-team-roadmap.md:185`): at least one of (a/b/c) must improve. Axis (c) improves 0→50%. Gate pass confirmed, backing the language-team adjudication at commit `5cab1b7`.

Two grade-A paths: `def` + bare `?proof-required` (claude try01); `def-shell` + LT-PPR predicate-carrying (gemini try01 — first empirical exercise of LT-PPR syntax). Gemini try02 excluded (def-logic rejection, no correction). Gemini try03 excluded (TerminalQuotaError, 0 output).

F-GATE-7 evaluator fix applied — does not change gate outcome. F-GATE-8 (compiler inconsistency: def-shell trust status pre-clause-dependent) routed to compiler-engineer; does not affect gate adjudication (grade A confirmed in 3 attempts independent of the affected cells).

---

**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — rewritten under the new five-role pipeline. Items E1–E3 moved to `findings/experiment-lead.md`. Items S1 and S3 are primarily `compiler-engineer` work — see `findings/compiler-engineer.md`; this file retains only the small spec touches that pair with them. The remaining first-class items (S4 + D2 + D3) are bundled into a single design proposal — Activity LT-A — covering the AI-agent-facing pedagogical surface in `LLMLL.md §11.2 / §12 / §13.8` and `docs/getting-started.md §4`.

This file covers one work unit:

- **LT-A — Pedagogical surface design proposal**: one design proposal covering identifier shape in JSON-AST (S4), three-layer Result-pattern resolution (D2), `?proof-required` pedagogical hook (D3), and small spec touches on S1 (typing rule for `?delegate` fallback) and S3 (test-status taxonomy if `unknown` is user-visible).

The rationale for bundling: all five touches sit in adjacent neighborhoods of `LLMLL.md` and `docs/getting-started.md §4`. They are pedagogical surface aimed at AI agents — the project's primary consumer. Splitting risks inconsistent tone across adjacent paragraphs.

Document drafts produced by this skill should land at `docs/design/<topic>.md` per the established proposal/review pattern (see `docs/design/oblig-0-spec.md`, `docs/design/invariant-discovery-proposal.md`); the `documentation-lead` then promotes settled content into `LLMLL.md` and `docs/getting-started.md` after `compiler-engineer` ships any blocking implementation. See `findings/documentation-lead.md` for the doc-pass items (DL-A).

---

### LT-A · Pedagogical surface design proposal

#### S4. JSON-AST Permits Dotted `app.fn` Despite the Documented Constraint

**Priority:** Defence in depth (not a blocker, but should land in parallel with the other LT-A items)

##### Evidence

- `docs/llmll-ast.schema.json:630` — prose constraint "ASCII only. No dots.", no `pattern` regex attached.
- [ParserJSON.hs L428–431](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ParserJSON.hs#L428-L431) — `qual-app` collapses to `EApp` with a dotted name.
- `LLMLL.md §12:1571,1581` — EBNF: dotted identifiers belong to `qual-ident`, hence `qual-app`.

Dotted names parse and survive into the typechecker's name-keyed lookup table without constraint.

##### Resolution (normative)

The identifier regex is normative; document it once in the schema and once in `LLMLL.md §12` so the EBNF and the schema cannot drift. Proposed shapes:

```json
"ExprApp.fn":          { "pattern": "^[A-Za-z_][A-Za-z0-9_?\\-]*$" }
"ExprQualApp.qual_fn": { "pattern": "^[A-Za-z_][A-Za-z0-9_?\\-]*(\\.[A-Za-z_][A-Za-z0-9_?\\-]*)+$" }
```

The `?` and `-` characters preserve the existing identifier convention (`string-empty?`, `is-ok`, etc.; see [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129)). The `qual_fn` pattern enforces `IDENT { "." IDENT }` per the EBNF.

**Enforcement scope:** schema-side validation is sufficient. Paired parser-side enforcement at `ParserJSON.hs:428-431` is *optional defence in depth* and is recorded as conditional CE-C in `findings/compiler-engineer.md`. Default recommendation: schema-only.

##### Acceptance

A JSON-AST validator rejects `{"kind":"app","fn":"Result.Error",...}` before the parser runs. `qual-app` requires at least one dot. The regex appears verbatim in both `docs/llmll-ast.schema.json` and `LLMLL.md §12`.

---

#### D2. Three-Layer Result-Pattern Resolution

**Priority:** Agent accuracy. Sequenced after S1 ships.

##### Spec drift identified

`LLMLL.md §13.8` documents `ok`/`err`/`is-ok` as builtins. `LLMLL.md §11.2:1267,1300–1301` mixes `Result.Error` (in `on_failure` and prose) with `Success`/`Error` (in match arms). This produced the constructor confusion observed across 18 attempts.

`Result.Ok` and `Result.Error` are **not** registered constructor names in [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129). Their apparent acceptance was a consequence of S1 (the typechecker never traversed the fallback expressions where they appeared). Once S1 ships, `Result.Error` in `on_failure` will fail to typecheck and the existing examples become broken.

##### Resolution (normative)

The compiler is canonical. Three-layer rule, normative:

- **Construct values.** Use `(ok x)` and `(err e)` — the typed builtins from [TypeCheck.hs L125–127](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L125-L127).
- **Match values.** Use bare `Success` and `Error` constructors. [CodegenHs.hs L692–697](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L692-L697) confirms these are the canonical pattern names; codegen rewrites them to Haskell `Right`/`Left`.
- **Test values.** Use `(is-ok x)` for boolean property checks. There is no `is-Result`; structural assertions go through `match`.

`Result.Ok` and `Result.Error` are explicitly *not* registered names. Documenting them as aliases would bless accidental behaviour. Remove from spec examples wherever they appear in `LLMLL.md`.

##### Acceptance

`LLMLL.md §11.2 / §13.8` and `docs/getting-started.md §4` describe the three layers consistently. Zero remaining occurrences of `Result.Ok` or `Result.Error` in spec examples. The `compiler-engineer` S1 fix and this resolution land in the same release; CHANGELOG entry references both.

##### Appendix: Constructor Usage Across 15 Passing Solutions

- `ok`/`err`/`is-ok` (fn calls): 9 of 11 passing runs — the dominant pattern.
- `Result.Error` as `app.fn`: 1 occurrence (Flash try1, a *failing* run).
- `Result.Error` as `qual_fn`: 1 occurrence (Flash try2, passing).
- `Result.Ok`: 0 occurrences.
- `Success`/`Error` as match pattern: 0 occurrences across all 15 passing solutions.

The constructor-confusion narrative is a real but minor effect; the soundness blockers in `findings/compiler-engineer.md` (S1, S3) dominate.

---

#### D3. `?proof-required` Pedagogical Hook

**Priority:** Required for experiments 002/003 to produce a meaningful grade-A signal.

##### Problem

Across all 15 passing solutions, zero `?proof-required` markers were emitted. [evaluate_run.py L76,82–86](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L76-L86) shows experiments 002 and 003 set `post.proof_required: True` on key contracts — the marker is the documented escape there. The current spec introduces `?proof-required` only in `LLMLL.md §12:1583–1589` (grammar) and verification prose (§5.3.5), far from where agents look first.

##### Resolution (normative)

Add a top-level entry to `docs/getting-started.md §4` and a paragraph in `LLMLL.md §13.8` connecting Result helpers to the proof-required escape: when the contract on a function is asserted but cannot be verified (delegation, non-linear arithmetic, map invariants), mark the contract clause `?proof-required` and the agent receives credit for declaring the obligation rather than papering it over.

The pedagogical hook in `§13.8` is small — one paragraph anchored to the existing Result-helpers section, since contracts on Result-returning functions are the most common case where the escape applies.

##### Acceptance

`docs/getting-started.md §4` has a `?proof-required` entry that explains when to use the marker, with at least one worked example. `LLMLL.md §13.8` has a paragraph linking Result helpers to the proof-required escape. Re-running experiment 002 (after E3 fix lands) produces non-zero `?proof-required` emissions on the verification-bounded contracts.

---

#### Small spec touches paired with `compiler-engineer`

These are not standalone LT-A items; they are spec edits that travel with the corresponding compiler implementations. Each is one or two sentences of prose, not a full design.

##### S1 (paired with `compiler-engineer` CE-A)

If `LLMLL.md §11.2` does not currently state explicitly that the fallback expression in `?delegate ... → T (on-failure e)` is checked against the delegate return type `T`, add the rule:

> `Γ ⊢ e : T` is required for `?delegate ... → T (on-failure e)` to be well-typed.

The compiler implementation does not block on this edit; the spec edit should land in the same release for consistency. Empirical likelihood that the rule is already implicit in §11.2: high. Verify before drafting.

##### S3 (paired with `compiler-engineer` CE-A)

If the new `unknown` status from PBT vacuity fix becomes user-visible in `llmll test` output, the test-status taxonomy in the spec needs to record it. Likely placement: the `LLMLL.md` section that documents `llmll test`. Status name is `compiler-engineer`'s call; spec-side decision is recording it as a public status alongside `pass`/`fail`/`skip`.

---

### Withdrawn

**"Treat `Result.Ok` ≡ `ok`, `Result.Error` ≡ `err` as accepted aliases."** Withdrawn. [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129) defines `ok`/`err`/`is-ok`/`unwrap`/`unwrap-or` as the only Result-related builtins. `Result.Ok` and `Result.Error` are not registered constructor names. Their apparent acceptance was a consequence of S1. Documenting them as aliases would bless accidental behaviour.

**"Document the A-grade ceiling per experiment."** Withdrawn. Replaced by `experiment-lead` E3 — fix the contract-expectation inconsistency rather than documenting it.

---

### Priority

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| **D2** | Three-layer Result resolution | Agent accuracy | Low (after S1) |
| **D3** | `?proof-required` pedagogical hook | Required for 002/003 | Low |
| **S4** | Identifier-shape regex (normative) | Defence in depth | Low |
| **S1** small touch | Fallback typing rule clarification | Joint with CE-A | Trivial |
| **S3** small touch | `unknown` status taxonomy | Joint with CE-A | Trivial |

### Hand-offs

- **`compiler-engineer`** — S1 and S3 implementation owners. This file's small touches travel with their implementation. See `findings/compiler-engineer.md`.
- **`experiment-lead`** — none. E1, E2, E3, D1.1, D4 are wholly within harness scope. See `findings/experiment-lead.md`.
- **`documentation-lead`** — Activity DL-A: writes the schema patch (S4), the LLMLL.md and `docs/getting-started.md` edits (D2, D3), and the CHANGELOG entry. Sequenced after S1 ships **and** LT-A is approved by user. See `findings/documentation-lead.md`.
- **`professor`** — none. The five LT-A items are spec/pedagogy reconciliation against the existing compiler, not novel design that requires outside-PL adjudication. If user wants a sanity check on the regex shape (S4) or the three-layer Result rule (D2) against external precedent, route after this file is settled.

---

## Experiment-lead


**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — split from former `language-team.md` (E1–E3) and `documentation-team.md` (D1.1, D4) under the new five-role pipeline. `experiment-lead` owns the `experiments/minimal-agent/` harness end-to-end: scripts, manifests, prompts, evaluator rubric.

This file covers two work units:

- **EL-A — Evaluator overhaul** (E1 + E2 + E3): all changes in `evaluate_run.py` to make B/C separation grounded, feature-scan signals independent, and experiment 001's contract expectation internally consistent.
- **EL-B — Agent-instructions revision** (D1.1 + D4): edits to `experiments/minimal-agent/prompts/agent-instructions.md` to require `--strict` and to elicit *structured* protocol uncertainty rather than reward bullet-count compliance.

---

### EL-A · Evaluator overhaul

#### E1. Delegation-Dependency Exclusion Uses Label Keywords, Not Call-Graph Reachability

**Priority:** Blocker for meaningful B/C separation

##### Evidence

[evaluate_run.py L420–441](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L420-L441). Two mechanisms run in parallel:

1. Structural inspection of the check block's own AST (L430) — rarely fires because checks call the function under test rather than inlining its body.
2. Label regex (L432): `\b(delegate|delegation|fallback|fail-closed|failed|fire-and-forget)\b` — does most of the work.

Same solution → B if the label hits the keyword set, C otherwise. Four of five functional models hit this boundary at the same 67% rate, indicating the boundary is naming-driven rather than evidence-driven.

##### Fix

Replace the label regex with transitive-callees analysis on the function call graph. A check `c` is delegation-dependent iff the transitive closure of functions reachable from `c` contains any expression of `kind ∈ {hole-delegate, hole-delegate-async, await}`.

**Soundness conditions:**

- Cycle-safe DFS (mutual recursion must not loop).
- Indirect calls conservatively over-approximated: any function whose definition contains a delegation marker contaminates every check that reaches it via any path.
- Conditional reachability over-approximated: any reachable delegation marks the check, regardless of branch coverage.

##### Acceptance

`is_delegation_dependent(check, solution_ast)` returns `true` iff a path through the call graph from any callee in `check` reaches a delegation hole, computed with cycle-safe traversal and a conservative treatment of indirection. Re-running 001 against the same five-model panel produces a B/C distribution that is no longer collinear with whether the check label contains a delegation keyword.

---

#### E2. The Feature Scanner Conflates Type Usage with Helper-Call Usage

**Priority:** Quality of grading (not a blocker, can land in parallel)

##### Evidence

[evaluate_run.py L316–347](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L316-L347). The scanner sets `found["Result"] = True` for `kind:"result"`, for `constructor ∈ {Success, Error}`, and for `fn ∈ {Success, Error}`. A single signal feeds `missing_required`.

##### Why This Matters

Gemini-2.5-pro try02 was correctly graded F because its delegate `return_type` was the primitive `string` rather than `kind:"result"`, even though the body called `err()`. The current type-anchored signal caught the defect. Adding `fn ∈ {ok, err, is-ok}` to the same signal would mask it.

##### Fix

Three independent signals:

| Signal | What it tracks | Drives `missing_required`? |
|--------|---------------|---------------------------|
| `Result-type` | `kind:"result"` in any type position | Yes |
| `Result-helpers` | `fn ∈ {ok, err, is-ok, unwrap, unwrap-or}` | No (informational) |
| `Result-pattern` | `match` `constructor ∈ {Success, Error}` | No (informational) |

##### Acceptance

`feature_scan.required` for experiment 001 lists `Result-type`. The other two signals appear in evaluation output (informational columns in `matrix_summary.md` and `evaluation.json`) but do not drive the F grade.

---

#### E3. Experiment 001's Contract Expectation Is Internally Inconsistent

**Priority:** ~~Blocker for grade-A signal~~ **Closed — Option 2 landed 2026-05-28**

##### Evidence

[evaluate_run.py L69–71](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L69-L71) sets `login-handler.pre.proof_required: False`. The experiment spec mandates `?delegate` inside `login-handler`. The verification matrix (`LLMLL.md §5.3.5`) and the README boundary (`README.md:81,89`) make contracts on functions containing delegation holes structurally `asserted`. With `proof_required: False`, the agent's `?proof-required` marker is silently ignored at [evaluate_run.py L497–513](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L497-L513), yielding `asserted_without_proof = 1` and a B ceiling at [evaluate_run.py L741–748](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L741-L748).

These three commitments are not jointly satisfiable.

##### Fix (pick one)

1. **Set `login-handler.pre.proof_required: True`.** The agent's `?proof-required` becomes the documented escape; grade A is reachable. *(Empirically falsified by postmortem-001 F-201 — 8/9 attempts dropped B→C because the pre clause is QF-LIA-tractable and agents correctly did not emit the marker. Reverted in commit `008495f`. Option 1 closed.)*
2. **Restructure the experiment** so the contracted function does not directly contain the delegation hole. Encapsulate `?delegate` in an uncontracted helper and put `pre` on the wrapper. *(Implemented 2026-05-28: `CONTRACT_EXPECTATIONS[1]["login-handler"]` now carries `post.proof_required: True` only (pre removed); `REQUIRED_FEATURES[1]` gains `"post"`; `001-two-agent-auth.md` items 6–7 add the delegation-bounded post contract and a non-delegation-dependent check. Grade A now reachable. Option 2 closed.)*

"Document max grade B" is not a fix — it preserves the inconsistency and trains agents to expect the ceiling rather than exercising the verification surface the rubric is designed to measure.

##### Acceptance

**Met (2026-05-28).** `evaluate_run.py` `CONTRACT_EXPECTATIONS[1]` carries `{"login-handler": {"post": {"proof_required": True}}}`. `REQUIRED_FEATURES[1]` includes `"post"`. `001-two-agent-auth.md` items 6–7 define the post contract and non-delegation-dependent check. `test_evaluate_run.py` `ContractExpectationE3Tests` guards the new state (3 assertions); `QualityGradeTests.test_e001_grade_a_with_nondelegation_check_and_proof_required_post` confirms grade A is reachable with the restructured setup. CHANGELOG entry under `### Experiments — E3 Option 2` in `## Unreleased`. Documented by `documentation-lead`, 2026-05-28.

---

### EL-B · Agent-instructions revision

#### D1.1. Agent Instructions Must Require `--strict`

**Priority:** High leverage, trivial

##### Problem

[agent-instructions.md L25](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/prompts/agent-instructions.md#L25) requires non-strict `llmll check`. Non-strict is sketch-mode tolerance for forward references and holes; finalised solutions should run under `--strict`. The CLI text-mode renderer suppresses warnings on success and prints only `OK`, so the agent never sees the diagnostic unless `--strict` (warnings → errors with nonzero rc) or `--json` (structured output) is requested.

##### Evidence

Flash try1 called `is-Result(...)`. Non-strict check exited 0. The agent concluded the solution was valid. The evaluator ran `--strict` → exit code 1 → grade F.

##### Fix

Update `agent-instructions.md` to require `llmll check solution.ast.json --strict`.

The companion compiler-side fix (surface accumulated warnings on text-mode success) is a `compiler-engineer` item — see `findings/compiler-engineer.md` D1.2. Either fix is independently sufficient; doing both is preferred.

##### Acceptance

Re-running experiment 001 against the same five-model panel produces zero attempts where `--strict` reverses a non-strict pass.

---

#### D4. Audit Agent Instructions for Protocol Salience

**Priority:** Process quality

##### Problem

The original report recommended requiring at least one `PROBLEMS.md` bullet (only GPT-5.5 complied across 18 attempts). This is metric-shaping that rewards compliance theatre. The actual signal — agents not surfacing protocol uncertainties — is a prompt-design gap.

##### Fix

Audit `experiments/minimal-agent/prompts/agent-instructions.md` for whether the protocol is *structured* — for example a section instructing "Before finalising, list any spec ambiguity you resolved by guessing, with the section you consulted and the decision you made" — rather than whether a count threshold is met. The structured form elicits useful uncertainty data; the count threshold rewards padding.

##### Acceptance

The instructions contain at least one structured uncertainty-elicitation section that does not specify a minimum bullet count. Re-running experiment 001 produces protocol-uncertainty entries that vary in count across runs (i.e., the format is doing work, not satisfying a threshold).

---

### Withdrawn

**"Require at least one `PROBLEMS.md` bullet"** — withdrawn. Original report framed compliance count as the metric. This is metric-shaping; D4 above replaces it with structured uncertainty elicitation.

**"Extend feature scanner to match `ok`/`err`/`is-ok` calls as evidence of Result usage"** — withdrawn. The scanner's type-anchored check is doing real work: it correctly graded gemini-2.5-pro try02 F because the delegate `return_type` was the primitive `string` rather than `kind:"result"`. Relaxing to fn-call evidence would mask defects. Replaced by E2's three-signal split.

---

### Priority

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| **E1** | Call-graph delegation analysis | Blocker for B/C separation | Medium |
| **E3** | Contract expectation inconsistency | ~~Blocker~~ **Closed** (Option 2, 2026-05-28) | — |
| **D1.1** | Require `--strict` in instructions | High leverage, trivial | Low |
| **E2** | Three-signal feature scan | Quality of grading | Low |
| **D4** | Structured uncertainty elicitation | Process quality | Low |

### Hand-offs

- **`compiler-engineer`** — companion item D1.2 (text-mode warning surface in `llmll check`). See `findings/compiler-engineer.md`.
- **`language-team`** — none from EL-A / EL-B. Gate findings (EL-C) routed below.

---

### EL-C — §8 gate post-arm rerun (2026-05-28)

**Source:** `findings/postmortem-004-s8-gate-post-arm-rerun.md`
**Run:** `20260528T145727Z` — 6 attempts, llmll 0.10.8 @ `4252b5f`, manifest `manifest.s8-post-e001.json`
**Comparison baseline:** `20260528T012230Z` (pre-arm, GrammarLegacy)

#### F-GATE-3. F-GATE-1b enforcement confirmed; axis (d) is now non-trivial

**Priority:** Confirmation — closes F-GATE-1.
**Consumer:** language-team (gate adjudication)

Binary verified before run: `llmll --grammar=core-inversion check <def-logic-solution>` exits 1 with `core-grammar-violation`. Across 5 harness-passing attempts (3× claude-opus-4-7, 2× gemini-3-pro-preview), the final solutions contain: `def` = 6, `def-shell` = 4, `def-logic` = **0**. `evaluation.json::feature_scan.boundary_form_counts` field confirmed in all 3 attempts evaluated after the `count_boundary_forms` extension landed (try03-claude, gemini-try02, gemini-try03); backfilled for try01 and try02 via evaluator re-run.

Pre-arm (12/12 `def-logic`) vs. post-arm (0/10 `def-logic`) constitutes a valid before/after pair for axis (d).

**Acceptance:** Closed — enforcement confirmed working. See postmortem-004 §Verified findings F-GATE-3.

---

#### F-GATE-4. claude-opus-4-7 try03 demonstrates enforcement-driven in-session adaptation

**Priority:** Observation.
**Consumer:** language-team

`runs/20260528T145727Z/20260528T145727Z-claude-opus-4-7-try03-of-03-e001/logs/agent.stdout.log` final paragraph: *"PROBLEMS.md records the `bin/llmll` wrapper forcing `--grammar=core-inversion` (**initial `def-logic` rejected → switched to `def-shell`**)…"*

The agent submitted `def-logic`, received `core-grammar-violation` (exit 1 + hint text), and rewrote to `def-shell` within the same session. Final solution: 2× `def-shell`, 0× `def-logic`, grade B. Duration: 319s vs 286/306s for try01/try02 — ~25s overhead consistent with one repair cycle.

The diagnostic hint ("Replace `{"kind":"def-logic"}` with `{"kind":"def"}`…`{"kind":"def-shell"}`…") was sufficient to guide adaptation without requiring §4.1 prose clarification.

---

#### F-GATE-5. Gemini-3-pro-preview API throttling (HTTP 429) confounds both post-arm cells

**Priority:** Exclusion condition.
**Consumer:** experiment-lead, language-team (gate adjudication)

- **try01** (`...gemini-3-pro-preview-try01-of-03-e001`): `status: "failed"`, `rc=1`, `dur=234s`, 10 retry attempts, 0 bytes stdout — no work product.
- **try03** (`...gemini-3-pro-preview-try03-of-03-e001`): `status: "passed"`, `rc=0`, `dur=805s`, 20 retry attempts. Grade **F** (`missing_required: ["pre"]`). Boundary forms: `def:2`, zero `def-logic`. The F is attributable to 429-induced session-quality degradation, not enforcement difficulty.
- **try02** is clean: `status: "passed"`, grade B, `def:2`, `dur=502s`.

Enforcement-valid gate dataset (no infra confounders): claude ×3 + gemini-try02 ×1 = **4 attempts. All passed B. All def/def-shell. 0 verified. 0 proof-required.**

---

### Priority (EL-C)

| # | Finding | Consumer | Priority | Effort |
|---|---------|----------|----------|--------|
| **F-GATE-3** | F-GATE-1b confirmed; axis (d) non-trivial | language-team | Confirmation — close F-GATE-1 | None |
| **F-GATE-4** | In-session adaptation evidence (claude try03) | language-team | Observation | None |
| **F-GATE-5** | Gemini 429 throttling confounds gate cells | experiment-lead | Exclusion condition | None |

---

### EL-D — §8 gate redesigned run (2026-05-28)

**Source:** `findings/postmortem-005-s8-gate-redesigned-run.md`
**Run:** `20260528T204620Z` — 8 attempts, llmll 0.10.8 @ `4252b5f`, manifest `manifest.e001-post-e3.json`
**Evaluator:** EL-1 + EL-2 + E3 Option 2 (commit `0d5037e`)
**Comparison baseline:** `20260528T012230Z` (pre-arm, GrammarLegacy)

#### F-GATE-6. Grade A achieved; axis (c) non-trivial; two grade-A paths exercised

**Priority:** Confirmation — gate pass evidenced.
**Consumer:** language-team (gate adjudication close-out)

3 of 6 valid post-arm attempts reached grade A (claude try01-02, gemini try01). Axis (c) — `?proof-required` emission on out-of-core contracts — improves from 0/6 (pre-arm) to 3/6 (post-arm), satisfying the §8 gate pass criterion per `docs/compiler-team-roadmap.md:185`.

Two grade-A paths exercised:
1. `def` (strict-core) + bare `?proof-required` → verifier: "asserted" → prc=1 (claude try01)
2. `def-shell` + predicate-carrying `?proof-required` (LT-PPR) → verifier: "asserted" → prc=1 (gemini try01 — first empirical exercise of the LT-PPR predicate-carrying syntax in a live run)

Grade distribution shift: postmortem-004 = 5× B, 0× A; this run = 3× A, 3× C. Grade B disappears because E3 Option 2's `login-handler.post.proof_required: True` makes the contract expectation mandatory — agents that don't mark `?proof-required` correctly fail `contracts_met` → grade C.

Run directory citations: `runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try01-of-05-e001/evaluation.json`, `runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try01-of-03-e001/evaluation.json`.

**Acceptance:** Closed — gate pass confirmed.

---

#### F-GATE-7. `normalize_trust_status` sample-count suffix mismatch — **fixed**

**Priority:** Applied fix.
**Consumer:** experiment-lead (own fix)

`TRUST_STATUS_PRESENT` (line 137) contains `"tested"`. The trust report emits `"tested (100 samples)"` for PBT-run clauses. `normalize_trust_status` returned the value as-is → exact membership check `"tested (100 samples)" in TRUST_STATUS_PRESENT` failed → `accepted: False` → grade C for try03-05 (should be grade A).

**Fix applied** to `evaluate_run.py:normalize_trust_status`: added `re.sub(r"\s*\(.*\)\s*$", "", value)` before `.lower()`. `"tested (100 samples)"` now normalizes to `"tested"`. Affects: any run where the verifier reports `"tested (N samples)"` for a contract clause.

Note: with this fix applied, re-evaluating try03-05 against their existing solution files would produce grade A (contracts_met=True, effective_total=2, awp=0 → grade A per `quality_grade` function at line 882). The fix does not change the gate outcome — grade A is already confirmed in 3 attempts.

---

#### F-GATE-8. `def-shell + bare hole-proof-required` post trust status is pre-clause-dependent

**Priority:** Medium — compiler-engineer investigation.
**Consumer:** compiler-engineer

Four `def-shell` functions with identical `post: hole-proof-required` (bare, no predicate) and `hole-delegate` body produce different post trust statuses:

| Pre clause | post trust_status |
|-----------|-------------------|
| `string-length(password) > 0` (try02) | `"asserted"` |
| `not(string-empty?(password))` (try03-05) | `"tested (100 samples)"` |

Hypothesis: `string-length` is not in the PBT static evaluator's known-builtin set → unevaluable pre → verifier flags whole function "asserted" before attempting the post clause. `not(string-empty?)` is evaluable → PBT runs on pre; verifier then attempts bare `hole-proof-required` post independently → "tested (N)".

A `def-shell + hole-delegate` body should produce `post: "asserted"` unconditionally — the delegation hole makes the return value opaque. Route to `compiler-engineer` for `FixpointEmit.hs` / `Contracts.hs` investigation.

**Acceptance:** `def-shell + string-empty? pre + bare hole-proof-required post + hole-delegate body` → `post: "asserted"`.

---

#### F-GATE-9. Gemini-try02 submitted `def-logic` without in-session correction

**Priority:** Observation.
**Consumer:** experiment-lead

`runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try02-of-03-e001/` — `check` returned exit 1 with `core-grammar-violation` hint. Agent did not correct `def-logic` → `def`/`def-shell` before stop policy fired. `boundary_form_counts: {def-logic: 2}`. Duration: 180s. Excluded from gate analysis.

Contrast: claude-opus-4-7-try03 (postmortem-004) corrected in-session with ~25s overhead. Enforcement signal was identical. Behavioral difference: gemini-try02 finalized solution without iterating on the compiler rejection.

---

#### F-GATE-10. Gemini-try03 TerminalQuotaError

**Priority:** Exclusion condition.
**Consumer:** experiment-lead

`logs/agent.stderr.log`: `TerminalQuotaError: You have exhausted your capacity on this model. Your quota will reset after 4h11m59s.` `status: failed, rc: 1, dur: 82s`. Third occurrence of gemini quota exhaustion across four gate runs. Clean gemini cell count across postmortem-004 + 005: 2 of 6 gemini attempts usable (try02 in PM-004; try01 in PM-005).

---

### Priority (EL-D)

| # | Finding | Consumer | Priority | Effort |
|---|---------|----------|----------|--------|
| **F-GATE-6** | Grade A confirmed; axis (c) improves; LT-PPR exercised | language-team | Confirmation — close gate | None |
| **F-GATE-7** | normalize_trust_status suffix mismatch | experiment-lead | Applied | Done |
| **F-GATE-8** | def-shell trust status pre-clause-dependent | compiler-engineer | Medium | Investigation + fix |
| **F-GATE-9** | Gemini-try02 no correction on def-logic | experiment-lead | Observation | None |
| **F-GATE-10** | Gemini-try03 TerminalQuotaError | experiment-lead | Exclusion | None |

---

## Documentation-lead


**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — split from former `documentation-team.md` (D1, D2, D3) under the new five-role pipeline. D1.1 moved to `findings/experiment-lead.md` (`prompts/agent-instructions.md` is harness scope, not doc-lead scope). D1.2 moved to `findings/compiler-engineer.md` (`Diagnostic.hs` rendering is compiler scope). The remaining items (D2 mechanical edits, D3 prose, plus the S4 schema patch surfaced in `findings/language-team.md`) bundle into one doc pass — Activity DL-A.

This file covers one work unit:

- **DL-A — Pedagogical surface doc pass**: schema patch for identifier-shape regex (S4), three-layer Result-pattern updates in `LLMLL.md §11.2 / §13.8` and `docs/getting-started.md §4` (D2), `?proof-required` pedagogical paragraph in `LLMLL.md §13.8` and `docs/getting-started.md §4` (D3). One pass, six target docs at most, sequenced after upstream events.

`documentation-lead`'s six-target-doc allowlist: `README.md`, `docs/getting-started.md`, `LLMLL.md`, `docs/llmll-ast.schema.json`, `docs/compiler-team-roadmap.md`, `CHANGELOG.md`. All edits in DL-A land within this scope. The `experiments/<harness>/` doc surface is **not** in scope (it is `experiment-lead`'s).

---

### DL-A · Pedagogical surface doc pass

#### Sequencing — required upstream events

This pass runs only after all three of the following have landed:

1. **`compiler-engineer` CE-A complete.** S1 (typecheck `on_failure`) ships. Required because removing `Result.Error` from the `LLMLL.md §11.2` `on_failure` examples is contradicted by current compiler behavior; the change is consistent only after the compiler enforces the new typing rule.
2. **`language-team` LT-A approved.** The three-layer Result rule, the `?proof-required` pedagogical hook, and the identifier-shape regex are normative decisions. `documentation-lead` does not author them; LT-A confirms them. Approval evidence lives in conversation or as a `docs/design/<topic>.md` draft promoted to settled status.
3. **CHANGELOG seed available.** The compiler-engineer hand-off carries a paragraph describing what landed (S1, S3, D1.2 if bundled). DL-A uses it as the seed for the new CHANGELOG entry.

If any of the three is missing when DL-A is invoked, the doc-lead names the gap and stops. Per the doc-lead skill's input contract, doc updates without an underlying change are forbidden.

---

#### Six target docs — what changes in each

Per the doc-lead update-order discipline (CHANGELOG → README → roadmap → LLMLL.md → getting-started.md → schema):

##### 1. `CHANGELOG.md` — new version entry

Append a `## v<version> — <theme> (<date>)` section above the previous one. Suggested theme: "Soundness blockers + Result-pattern docs" (subject to the engineer's actual bundling). Subsection structure follows the established voice (`### Compiler — <subtheme>`, bolded-identifier bullets):

- `### Compiler — Delegate Fallback Typechecking` (S1)
- `### Compiler — PBT Vacuity Fix` (S3)
- `### Compiler — Diagnostic Surface` (D1.2)
- `### Spec — Three-Layer Result Patterns` (D2)
- `### Spec — `?proof-required` Pedagogical Hook` (D3)
- `### Schema — Identifier-Shape Regex` (S4)

Closing `**Tests:**` line updated to the new test count from `compiler-engineer`'s test additions.

##### 2. `README.md` — version banner, command callout, test count

- Update version banner (line 1 header) and version-callout paragraph if version bumps.
- Update the command-table row for `llmll check` if D1.2 changes user-visible text-mode output (it does; warning lines now appear on success). Voice match: keep terse.
- Update the test-count line to match the CHANGELOG `**Tests:**` line.
- No structural reorganization. The 2-min-read shape is preserved.

##### 3. `docs/compiler-team-roadmap.md` — close completed rows

- Mark any `[CT]` rows that S1 / S3 / D1.2 closed with ☑ or ✅.
- Move the closed milestone block from "Upcoming Releases" to "Shipped Releases" if a milestone fully shipped (unlikely for a soundness-fix release; default expectation is row-level updates only).
- Update the "Summary: Version Plan and Critical Path" status line if the version progression advanced.

##### 4. `LLMLL.md` — spec edits per LT-A resolutions

Three edits, each anchored to the language-team's approved resolution:

- **§11.2 `?delegate` rule (S1 small touch).** Add or clarify: "`Γ ⊢ e : T` is required for `?delegate ... → T (on-failure e)` to be well-typed." Verify against the existing §11.2 prose; the rule may already be implicit and need only a one-sentence clarification rather than a new rule.
- **§11.2 / §13.8 Result-pattern examples (D2).** Replace `Result.Error` and `Result.Ok` occurrences with `(err …)` and `(ok …)` per the three-layer rule. Add (or strengthen) the pedagogical paragraph in `§13.8` distinguishing the three layers — *construct* (`ok`/`err`), *match* (`Success`/`Error`), *test* (`is-ok`).
- **§13.8 `?proof-required` paragraph (D3).** New paragraph linking Result-returning contracts to the proof-required escape: when a contract on a function is asserted but cannot be verified (delegation, non-linear arithmetic, map invariants), mark the contract clause `?proof-required` to declare the obligation rather than paper it over.
- **§12 grammar (S4).** Insert the identifier-shape regex once, normative, with cross-reference to the schema. Cite the EBNF clauses at `LLMLL.md §12:1571,1581` that the regex enforces.
- **`llmll test` output section (S3 small touch).** If the new `unknown` status is user-visible (per `compiler-engineer`'s implementation choice), add it to the test-status taxonomy alongside `pass`/`fail`/`skip`.

Voice match: reference, not tutorial. No marketing register.

##### 5. `docs/getting-started.md §4` — Known-Good Patterns additions

- **Result patterns subsection (D2).** Three-layer rule with a worked example for each layer. Length target: roughly the size of the existing Known-Good Pattern entries.
- **`?proof-required` entry (D3).** Top-level entry in §4 explaining when to use the marker, with at least one worked example showing a Result-returning function whose post-condition is asserted.
- **Warning-on-success note (D1.2).** Brief mention that `llmll check` text mode now emits accumulated warnings on success; agents should read warnings even when rc=0.

Voice match: example-led. Keep the existing entry length cadence.

##### 6. `docs/llmll-ast.schema.json` — identifier regex (S4)

- Add `"pattern"` constraint to `ExprApp.fn` and `ExprQualApp.qual_fn` per the LT-A resolution. Exact regex strings are in `findings/language-team.md` S4.
- Bump schema `version` (and `$id` if applicable) per the schema-versioning discipline.
- Update embedded `examples` blocks if any current example violates the new regex.
- Cross-check that `compiler/src/LLMLL/ParserJSON.hs:428-431` does not need paired enforcement (conditional CE-C in `findings/compiler-engineer.md`); the default assumption is schema-only enforcement.

---

#### Reconciliation pass — cross-doc checks

After all six edits land, run the doc-lead reconciliation pass before signaling review-ready:

- **Version pins agree.** README header == CHANGELOG top entry == `compiler/package.yaml` version == `compiler/llmll.cabal` version == `llmll version` runtime output.
- **Test count agrees.** README test-count line == CHANGELOG closing `**Tests:**` line.
- **Internal links resolve.** Every `[…](…)` link inside the six targets points to a real file or anchor. Anchors that were renamed (e.g., new `?proof-required` subsection in `§13.8`) are updated wherever cited.
- **Command-table truth.** Every command in `README.md`'s table is present in `llmll --help`. The `llmll check` row matches the new text-mode output behavior from D1.2.
- **Schema example validity.** Every JSON example embedded in any of the six targets validates against the updated schema with the new identifier regex. The `Result.Error` examples that were valid before are now invalid; replace, do not delete-without-replace.
- **Roadmap-CHANGELOG cross-reference.** Every roadmap tag mentioned in the new CHANGELOG entry exists in the roadmap doc; every newly-shipped roadmap row has a corresponding CHANGELOG line.
- **Spec-drift residue check.** Grep `Result.Error` and `Result.Ok` across the six targets after edits — should be zero occurrences except in withdrawn/deprecated callout if one is added.

---

### Out-of-scope items surfaced — not edited

Per doc-lead's "no scope expansion" rule, the following surfaced during reconciliation and are flagged but not fixed in this pass:

- `experiments/minimal-agent/prompts/agent-instructions.md` — D1.1 belongs to `experiment-lead`. Doc-lead does not edit harness prompts.
- `compiler/src/LLMLL/Diagnostic.hs` (or wherever D1.2 lands) — compiler code is `compiler-engineer`'s scope.
- `docs/design/*` — language-team's draft surface; doc-lead does not edit in-flight design drafts.
- Any spec-drift discovered in `LLMLL.md` outside the LT-A neighborhoods (§11.2, §12, §13.8) — surface as findings for `language-team` to adjudicate, do not silently fix.

---

### Withdrawn

**"Treat `Result.Ok` ≡ `ok`, `Result.Error` ≡ `err` as accepted aliases."** Withdrawn at the language-team layer — see `findings/language-team.md`. Doc-lead does not document them as aliases.

---

### Priority

| # | Activity | Impact | Effort |
|---|---|---|---|
| **DL-A** | Pedagogical surface doc pass | High (closes spec-drift, surfaces `?proof-required`) | Medium (six-doc reconciliation pass) |

### Hand-offs

- **`compiler-engineer`** — provides the upstream commit (S1 + S3 + D1.2) and a CHANGELOG seed. DL-A consumes both.
- **`language-team`** — provides the LT-A resolution (three-layer Result rule + identifier regex + `?proof-required` hook + small spec-touch text). DL-A consumes the resolution and writes it.
- **`experiment-lead`** — no direct hand-off. The doc-lead's reconciliation pass will not touch harness files or harness prompts; if cross-doc consistency surfaces a harness-side issue (e.g., `agent-instructions.md` references a `llmll check` flag that changed in D1.2), doc-lead flags it back to experiment-lead, does not edit.
- **`professor`** — none.

### POST-PASS workflow

Per the doc-lead skill:

1. Plan, then stop. Surface this file's content as the doc-update plan and wait for user approval.
2. On approval, apply edits in the order above. Stop and re-plan if any planned change is wrong mid-edit.
3. Run the reconciliation pass.
4. Surface a one-paragraph review-ready summary (files touched, line counts, CHANGELOG entry verbatim, any reconciliation gaps that remain).
5. On user authorization, commit with a `docs:` prefix referencing the version or roadmap tags closed. Do not commit autonomously, do not bundle with code changes.
