---
name: dup-def-1-engineer-plan
title: "DUP-DEF-1: check rejects a duplicate top-level name"
status: "Plan approved and executed 2026-09-06, shipped v0.20.0: 1857 → 1865 hspec examples, corpus sweep found no duplicate in 361 files. Routed from docs/design/norm-claim-proposal.md finding F1 by the user's instruction to route the findings."
date: 2026-09-06
author: compiler-engineer
consumers: [user, documentation-lead, llmll-patch-implementer]
style: "ASD-STE100 Simplified Technical English. Haskell identifiers, compiler messages and test names keep their exact bytes."
---

# DUP-DEF-1: `check` rejects a duplicate top-level name

## Restatement

`LLMLL.md` §1.1 says a name bound twice in one scope is a compile error. At HEAD only GHC enforces it, at `build`. `check`, `verify` and codegen accept a module that defines one name twice. The plan adds one pass to `checkStatements` in `TypeCheck.hs` that rejects the duplicate with a kind-tagged error before verification runs.

## Context located

1. `compiler/src/LLMLL/TypeCheck.hs:1388-1400`, `checkStatements`: the first pass collects `topLevel` with `collectTopLevel` and builds `aliasMap` with `Map.fromList`. Nothing looks for a repeated name.
2. `compiler/src/LLMLL/TypeCheck.hs:1443-1451`: the constructor-duplicate pass, "Phase 1". It is the pattern to copy, with one difference named in the plan summary: it calls `tcWarnOrError`, which warns unless `tcStrictMode` is set (`:819-822`).
3. `compiler/src/LLMLL/TypeCheck.hs:1505-1530`, `collectTopLevel`: one list carries both namespaces. `SDef`, `SDefShell`, `SLetrec`, `SDefLogic` and `SDefInvariant` register as functions; `STypeDef` and `SDefInterface` register as `TCustom` types. `SDefMain` has no name and is not collected.
4. `compiler/src/LLMLL/TypeCheck.hs:833-839`, `withEnv`: `foldr (uncurry Map.insert)`, so the first definition wins in the environment and later ones are shadowed silently.
5. `compiler/src/LLMLL/TypeCheck.hs:611-613`, `tcErrorK`, and `:1736-1750`, the `sealed-type-redefinition` error: the kind-tagged precedent. `compiler/src/LLMLL/Diagnostic.hs:566` renders the kind in `--json` output.
6. `compiler/src/LLMLL/CodegenHs.hs:243`: every non-main statement is emitted, so two `def f` reach GHC as two bindings. `:1898-1901`, `emitMainHs`: `(dm:_)` takes the first `def-main` and drops the rest silently.
7. Measured on 2026-09-06 with the 0.19.0 binary. Two `(def f …)`: `check` prints `OK (3 statements)`, `build` fails with `Multiple declarations of 'f'`. `def f` plus `def-shell f`: `check` OK. Two `(type Shape …)`: `check` OK. Two `def-main` (the `pair_type_test` fixture with its `def-main` repeated): `check` OK, 4 statements. `verify` on two contracted `def f`: prints `body-faithful: f, f`, and the wrong body refutes in either order, because both bodies are emitted as constraints.
8. `LLMLL.md` §12 note 5: `let` bindings are sequential, so `(let [(x n) (x (+ x 1))] x)` is a nested shadow and stays legal.
9. `docs/compiler-team-roadmap.md`: no row on duplicate names exists (searched `duplicate`, `DUP-`). Row `SPEC-LAYOUT-1` governs where a new hspec block goes.
10. `docs/design/norm-claim-proposal.md` finding F1: the origin. NC-011 takes `row: DUP-DEF-1` until this ships, then `fixture` with `check-error`.
11. `compiler/test/Spec.hs:12414-12420`: the local `checkSrc` and `errorsOf` helpers a new block can copy. `:15073-15075`: the sealed-type test shape.
12. `compiler/src/LLMLL/TypeCheck.hs` comment near `:1452`: the XMOD-CTOR-2 note that the corpus is check-only and a defect can verify for months without compiling. That is the reason for the corpus sweep in the test plan.

## Plan summary

Add `checkDuplicateTopLevel :: [Statement] -> TC ()` and call it in `checkStatements` after the alias-cycle check and before `withEnv topLevel`. It groups names in two namespaces, functions and types, and counts `def-main` statements. Each name that appears more than once, and a `def-main` count above one, emits `tcErrorK "duplicate-definition"`. The error is unconditional, not `tcWarnOrError`: the spec says compile error, GHC refuses the program anyway, and a warning would leave `verify` and its sidecar green on a program `build` rejects. The cost is about 25 lines in one module, eight hspec examples, one doc-claims fixture, and no schema or solver change.

Message text, exact: `duplicate top-level definition 'f': defined 2 times in this module; a name is bound once per scope (LLMLL.md §1.1)`. For `def-main`: `duplicate def-main: 2 in this module; a module has at most one entry point`.

## Affected surface

- `compiler/src/LLMLL/TypeCheck.hs:1388-1445`: new pass in `checkStatements`; new function `checkDuplicateTopLevel` beside `collectTopLevel`.
- `compiler/test/Spec.hs`: new `describe "DUP-DEF-1: duplicate top-level names are rejected at check"`, eight examples, placed after the `FALLBACK-REASON-CONST-1` block. The `SPEC-LAYOUT-1` nesting defect affects the reported path and not the verdict.
- `scripts/doc-claims/duplicate-def-rejected.llmll`: new fixture, `@doc: LLMLL.md §1.1`, `@expect: check-error:duplicate top-level definition`, plus its row in `scripts/doc-claims/README.md`. The fixture also carries `@norm: NC-011` once the norm-claim registry exists.
- `LLMLL.md` §1.1: unchanged. The sentence becomes true at `check`. Doc-lead's slot.
- `docs/llmll-ast.schema.json`: no change.
- `docs/compiler-team-roadmap.md`: new row `DUP-DEF-1` `[CT]`, filed by the doc-lead; closed by the doc-lead on ship.
- `CHANGELOG.md`: one entry. Doc-lead's slot.

## Verification impact

No solver-time delta: the pass runs before emission. No new obligation. The fragment is unchanged. No function falls back. The trust effect is small and real: today `verify` can write a sidecar that records `f` as body-faithful for a module with two correct `f` bodies, and that module cannot build. After the change the module fails `check`, so no sidecar is written.

## Performance budget

GHC recompiles `TypeCheck.hs` and its dependents, about the cost of any one-line edit in that module. Runtime is one sort and group over the top-level statement list, under a millisecond on any module in the tree. Test-suite delta: eight examples, under one second. No `.fq`, binary, or cache effect.

## Contract plan

Nothing lands in the provable fragment. The change is Haskell compiler code, not an LLMLL program.

## Test plan

New hspec examples, all through the local `checkSrc` shape at `Spec.hs:12414`:

1. Two `(def f …)` → one error, kind `duplicate-definition`, message contains `'f'` and `2 times`.
2. `def f` plus `def-shell f` → error.
3. Two `(type Shape …)` → error.
4. Two `def-main` → error with `duplicate def-main`.
5. Negative: `(def shape …)` plus `(type Shape …)` → no error; namespaces are separate.
6. Negative: `(let [(x n) (x (+ x 1))] x)` → no error; sequential shadowing is not a duplicate.
7. JSON-AST parity: example 1 through `ParserJSON` gives the same kind.
8. Negative: a local `def g` in a module that `open`s a module exporting `g` → no new error from this pass; the pass is intra-module. Whatever `open` reports today stays as it is.

Corpus sweep, before and after: run `llmll check` over the 361 `.llmll` files outside `.stack-work`. Expected new failures: zero. Any new failure is a real defect that GHC never saw, on the XMOD-CTOR-2 precedent, and is reported with the file name, not fixed silently.

Python suite: unchanged; run it to confirm.

Test-count target: 1857 hspec examples, 0 failures, measured on HEAD (v0.19.1) on 2026-09-06 with `stack test` → 1865. End-to-end: `llmll check` on the new doc-claims fixture through the DRIFT-CT-2 gate.

## Rollback

Single revert of one module and one test block. No flag. No schema version. No sidecar migration. Programs that checked with a duplicate now fail `check`; they could never build, so the unwind cost is the corpus sweep's count of such files, expected zero.

## Risks and unknowns

1. **A corpus file defines a name twice and has verified for months.** Scope. `TypeCheck.hs` comment at XMOD-CTOR-2. The sweep in the test plan measures it. If found, it blocks nothing: the file is a defect and gets its own fix.
2. **Divergence from the constructor pass.** DX. The constructor pass at `:1443-1451` warns in default mode and says "first definition wins". This pass errors. A reader may ask why the two differ. The answer goes in the code comment: a duplicate constructor still builds, a duplicate binding does not.
3. **The `open` boundary.** Spec-drift. A local definition that shadows an opened name is not touched. If the user wants that case decided, it is a separate row.
4. **`def-main` multiplicity was silent in codegen.** DX. `emitMainHs` keeps the first. After this change the case never reaches codegen. No change to `CodegenHs.hs` is planned; the `(dm:_)` pattern stays as dead tolerance.

## Hand-off to documentation-lead, on ship

Tag `DUP-DEF-1`. User-visible change: `llmll check` rejects a module that defines one function or type name twice, or carries two `def-main` forms, with error kind `duplicate-definition`. No schema delta. Test delta: +8 hspec, +1 doc-claims fixture. CHANGELOG candidate: "`check` rejects a duplicate top-level name; GHC no longer finds it first." Spec: `LLMLL.md` §1.1 needs no edit; NC-011 in the norm-claim registry moves from `row` to `fixture`.

