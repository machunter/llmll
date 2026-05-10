# Compiler Engineer — Findings from Experiment 001

**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — split from former `language-team.md` (S1, S3) and `documentation-team.md` (D1.2) under the new five-role pipeline. `compiler-engineer` owns implementation in `compiler/src/LLMLL/`.

This file covers two work units:

- **CE-A — Soundness blockers** (S1 + S3): two compiler bugs that block grade-A signal on delegation-shaped problems. `?delegate` fallback expression is never typechecked; PBT vacuity defaults unevaluable property samples to `True`.
- **CE-B — Diagnostic surface** (D1.2): `llmll check` text-mode renderer suppresses accumulated warnings on success.

A conditional **CE-C** item (parser enforcement of S4 identifier-shape regex) is gated on the `language-team`'s S4 resolution — see `findings/language-team.md`. CE-C only fires if the language-team requests belt-and-suspenders enforcement at `ParserJSON.hs:428-431` in addition to JSON Schema validation.

---

## CE-A · Soundness blockers

### S1. `on_failure` Is Parsed but Never Typechecked

**Priority:** Blocker — no grade-A signal on delegation-shaped problems is meaningful until this ships.

#### Evidence

[TypeCheck.hs L1030](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L1030):

```haskell
inferHole (HDelegate spec) = pure (delegateReturnType spec)
```

The fallback expression in `delegateOnFailure` is never visited by the typechecker. [ParserJSON.hs L548](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ParserJSON.hs#L548) admits it into the AST, but no typing rule constrains it. Any `Γ ⊢ e : ?` is accepted, including ill-formed constructor applications like `(Result.Error DelegationError)`.

#### Why We Saw What We Saw

Flash try1's `(Result.Error DelegationError)` in `on_failure` produced rc=0 from `llmll check` not because non-strict tolerated an unknown function, but because the unknown-function lookup at [TypeCheck.hs L920–940](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L920-L940) is never reached for fallback expressions. The schema's prose constraint at `docs/llmll-ast.schema.json:630` ("ASCII only. No dots.") is independently unenforced — but that is downstream of the dropthrough, and is in the `language-team`/`documentation-lead` track (S4 + DL-A) rather than this file.

#### Fix

`inferHole (HDelegate spec)` must additionally run `checkExpr (delegateOnFailure spec) (delegateReturnType spec)` when the fallback is present.

#### Acceptance

`?delegate ... → T (on-failure e)` holds iff `Γ ⊢ e : T` under the function's typing context. A regression test in `compiler/test/` exercises a `?delegate` whose `on_failure` references an unknown identifier and asserts that `llmll check` emits a diagnostic.

#### Spec touch (joint with `language-team`)

If the typing rule for `?delegate` in `LLMLL.md §11.2` does not currently state explicitly that the fallback expression is checked against the delegate return type, that clarification is owned by `language-team` (LT-A small touch). The compiler implementation does not block on the spec edit, but the spec edit should land in the same release for consistency.

---

### S3. PBT Vacuity — Unevaluable Properties Default to True

**Priority:** Blocker

#### Evidence

[PBT.hs L205–208, L236–239](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/PBT.hs#L236-L239):

```haskell
tryQuickCheck bindings body
  | all isSimpleType (map snd bindings) = Just (runQC bindings body)

prop env = case evalExprStatic env body of
  Just (ELit (LitBool b)) -> b
  _                       -> True  -- skip unevaluable
```

Properties whose binders pass `all isSimpleType` enter the QuickCheck path. Inside that path, an unevaluable body returns `True` per sample, counting as a successful pass. Empty-binding `for-all` clauses pass the predicate vacuously. Properties with non-simple binders (e.g. `string`) take the higher-level `Skipped` path and do not exhibit this issue.

#### Why We Saw What We Saw

Several runs reported `effective_passed > 0` on checks whose underlying functions emit `error` at runtime per the delegate-codegen behavior in `CodegenHs.hs`. Those passes are not test evidence; they are silent vacuity.

#### Fix

Unevaluable samples must never be counted as `pass`. The principled outcomes are `skip`, `fail`, or a new `unknown` status. Default-True is unsound.

#### Acceptance

For every QuickCheck-eligible property, samples where `evalExprStatic` does not reduce to `LitBool` are categorised explicitly and excluded from the success count. The status surfaces in `llmll test` output. Re-running experiment 001 against the same five-model panel produces zero attempts where `effective_passed > 0` is driven by unevaluable samples.

#### Spec touch (joint with `language-team`)

If the new `unknown` status is user-visible in `llmll test` output, the test-status taxonomy in `LLMLL.md` (the section that documents `llmll test` output) is owned by `language-team` (LT-A small touch). A status name visible to AI agents is normative surface. The compiler implementation can choose any concrete name; the spec-side decision is which name lands.

---

## CE-B · Diagnostic surface

### D1.2. `llmll check` Text-Mode Suppresses Accumulated Warnings on Success

**Priority:** High leverage, trivial. Pairs with `experiment-lead` D1.1 (require `--strict` in agent instructions); either is independently sufficient, both is preferred.

#### Problem

`llmll check` in text mode prints `OK` on success and suppresses accumulated warnings. Agents that read text output (the default) never see the diagnostic unless `--strict` (warnings → errors with nonzero rc) or `--json` (structured output) is requested. Non-strict mode is sketch-mode tolerance for forward references and holes; warnings emitted in non-strict mode carry information that should still surface.

#### Evidence

Flash try1's solution called `is-Result(...)`. Non-strict `llmll check` exited 0 and the agent concluded the solution was valid. The evaluator ran `--strict` → exit code 1 → grade F. The non-strict warning that would have flagged `is-Result` as an unknown identifier was not rendered to text-mode output.

#### Fix

Update the text-mode rendering path (likely in `compiler/src/LLMLL/Diagnostic.hs`) to surface accumulated warnings on success, while preserving the rc=0 contract of non-strict mode. Concrete shape:

```
OK
  (warning) is-Result: unknown identifier at solution.ast.json:42
  (warning) Result.Error: unknown identifier at solution.ast.json:67
```

The exact format is the engineer's call; `--json` already does this via the structured diagnostics array, so the change is rendering-side, not analysis-side.

#### Acceptance

`llmll check` in text mode prints accumulated warnings on success. Re-running experiment 001 against the same five-model panel produces zero attempts where the agent finalises a solution while non-strict warnings remain unsurfaced.

---

## Conditional CE-C · Parser enforcement for S4 *(may be skipped)*

If the `language-team`'s S4 resolution (identifier-shape regex in `docs/llmll-ast.schema.json`) is treated as the sole enforcement point, no compiler-side change is needed. If the language-team requests paired enforcement at `ParserJSON.hs:428-431` to catch identifiers that bypass schema validation (e.g., ad-hoc parser invocations), `compiler-engineer` adds a regex check at the qual-app collapse site. Default assumption: schema-only enforcement, CE-C does not fire.

---

## Withdrawn

**"Treat `Result.Ok` ≡ `ok`, `Result.Error` ≡ `err` as accepted aliases"** — withdrawn. [TypeCheck.hs L115–129](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L115-L129) defines `ok`/`err`/`is-ok`/`unwrap`/`unwrap-or` as the only Result-related builtins. `Result.Ok` and `Result.Error` are not registered constructor names. Their apparent acceptance was a consequence of S1. Documenting them as aliases would bless accidental behaviour. Resolution lands in `language-team` D2 (three-layer rule) and `documentation-lead` DL-A (mechanical edits).

---

## Priority

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| **S1** | Typecheck `on_failure` | Blocker | Low |
| **S3** | PBT vacuity | Blocker | Low |
| **D1.2** | Text-mode warning surface | High leverage, trivial | Low |
| **CE-C** | Parser regex enforcement *(conditional)* | Defence in depth | Low |

## Hand-offs

- **`language-team`** — small spec touches on S1 (typing rule for fallback expression in `LLMLL.md §11.2`) and S3 (test-status taxonomy if `unknown` is user-visible). See LT-A small-touch items in `findings/language-team.md`.
- **`experiment-lead`** — companion item D1.1 (require `--strict` in `agent-instructions.md`). See `findings/experiment-lead.md`.
- **`documentation-lead`** — CHANGELOG entry under the version that ships S1 + S3 + D1.2; `docs/getting-started.md §4` Known-Good Patterns may want an entry on warning surfacing. See DL-A in `findings/documentation-lead.md`.

## Suggested branch shape

- `fix/delegate-fallback-typecheck` — S1
- `fix/pbt-vacuity-unknown-status` — S3
- `fix/check-text-mode-warnings` — D1.2

Bundle is engineer's call; suggest separate branches because the three modules are independent and the test-count delta is easier to attribute.
