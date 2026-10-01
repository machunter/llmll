---
name: eval-strict-1-measure-plan
title: "EVAL-STRICT-1: migration measurement plan (engineer)"
status: "EXECUTED 2026-09-29; results in eval-strict-1-measure-findings.md. Measurement only; no patch landed in the tree."
date: 2026-09-29
author: compiler-engineer
consumers: [user, language-team, documentation-lead]
related: "eval-strict-1-proposal.md (Rev 1, accepted 2026-09-29)"
---

# EVAL-STRICT-1: migration measurement plan

## Restatement

Build a throwaway compiler whose generated Haskell is call-by-value. Rebuild the
tree with it and run the existing gates. Count what fails, and why. The result
sizes the migration. It does not choose the final codegen mechanism.

## Context located

- `docs/design/eval-strict-1-proposal.md` §4.3, §5, §8: the acceptance criterion is
  behavioral; edge cases 6 to 8 separate WHNF from full values.
- `compiler/src/LLMLL/CodegenHs.hs` `emitLet`: emits one Haskell `let { ... }`, so
  every binding is lazy and the group is recursive in Haskell.
- `CodegenHs.hs` `emitApp`, `emitExpr (EApp ...)`: arguments are emitted in place;
  nothing forces them. Constructors go through the same path.
- `CodegenHs.hs` `emitDefLogic`: emits a signature only when the return type is
  not polymorphic (`isPolyType`); otherwise GHC infers it.
- `CodegenHs.hs` `emitTypeDef`: user types derive `(Eq, Show)` only.
- `CodegenHs.hs` `emitLibHs`: the runtime preamble and user code share one
  `Lib.hs`. A module-wide `Strict` pragma would change the preamble too
  (proposal risk 4) and blur which failures are user-program failures.
- `.github/workflows/version-gate.yml`: the list of gates that build and run
  LLMLL programs (tool ports, covers, runtime pytest cells, orchestra).
- `docs/compiler-team-roadmap.md` row `EVAL-STRICT-1`: the MEASURE step is named
  there; this plan is its implementation.

## Plan summary

The instrument is a scratch copy of the compiler at `f525266`, patched in
`CodegenHs.hs` only. It is built in the scratchpad and never committed. An
environment variable `LLMLL_EVAL` selects `lazy` (today), `whnf` or `deep`. Codegen
forces a value at two points: each `let` binding, and each argument of an
application that is not already a variable or a literal. A `let` becomes nested
`case F (e) of !p -> ...`, so bindings are sequential. `F` is the identity for
`whnf` and `Control.DeepSeq.force` for `deep`. Everything else stays as today:
`if`, `match`, `and`, `or`, `=>` and lambda bodies are not forced. The preamble
is not changed, so a failure inside it is attributed to the preamble on
purpose. `deep` adds `deriving (Generic, NFData)` to user types, orphan
`NFData` instances for `IO a` and `Async a` at WHNF, and `deepseq` to the
generated `package.yaml`.

## Affected surface (scratch copy only)

- `CodegenHs.hs` `emitLet`, `emitExpr (EApp ...)`, `emitTypeDef`, `emitLibHs`
  header, `emitPackageYaml`: the three-mode switch.
- `CodegenHs.hs` `emitDefLogic`: in `deep` mode, omit a signature that has a
  type variable, so GHC infers the `NFData` constraint.
- The repository tree: no change. The installed `llmll` binary: no change.

## What runs, in this order

1. **Instrument controls.** `lazy` mode must emit the same `Lib.hs` bytes as
   the `f525266` binary for every tool and example. The nine proposal edge
   cases are built as programs. `deep` must meet all nine. `whnf` must fail
   6, 7 and 8 and meet the rest. An instrument that fails a control is fixed
   before any count is taken.
2. **Build census.** `llmll build` of every entry program in `tools/`,
   `examples/` and the pytest fixtures, in all three modes. A build failure in
   `whnf` or `deep` is an instrument or type-inference failure, not a program
   failure, and is listed separately.
3. **Behavior census.** Each gate in `version-gate.yml` that builds and runs an
   LLMLL program is run three times, with `llmll` on `PATH` in each mode. The
   gates are the tool ports and their covers, the runtime pytest cells, the
   orchestra tests and the build-gate cover. `lazy` must match the `f525266`
   results; a difference there is a harness fault, not a finding.
4. **Classification.** Each gate that passes in `lazy` and fails in `whnf` or
   `deep` is traced to one construct. The class is one of: a value bound
   before its guard (edge case 3), a hole in a strict position (edge case 4), a
   preamble dependency, a performance limit (a time-out or a large slowdown),
   or other. Each is recorded with the source file and the function.
5. **Time.** The wall-clock time of each gate in each mode is recorded. The
   driver's large-string paths are the expected cost (proposal risk 2).

The hspec suite is not run under the instrument. Its codegen tests compare
generated text, so every mode change fails them by construction.

## Deliverable

A findings file `docs/design/eval-strict-1-measure-findings.md` with the three
censuses, the classification table, the time table, and a recommendation. The
recommendation states the codegen mechanism for the real patch and the
migration work in the tree, with a count.

## Verification impact

None. The verifier is not changed. `verify` results are not part of the
measurement, because EVAL-STRICT-1 changes no obligation (proposal §6).

## Performance budget

One scratch compiler build (about 10 minutes cold, shared Stack snapshot).
Each mode rebuilds every tool and example; about 3 times the CI build time of
those steps. No effect on the repository build or test time.

## Contract plan

Nothing lands in the provable fragment. The instrument is scratch code and the
measurement changes no LLMLL source.

## Test plan

The instrument controls in step 1 are its tests. `stack test` on `main` is not
touched: baseline and delta are both zero because no tree file changes.

## Rollback

Delete the scratch directory. Nothing in the tree or on `PATH` changes.

## Risks and unknowns

1. **Argument forcing misses a path.** Verification. A value that reaches a
   preamble builtin through a higher-order call (`list-map` and a lambda) is
   forced only where the result is bound. Edge cases 6 and 7 test this path;
   a gap there is fixed before step 2.
2. **Polymorphic signatures in `deep` mode.** Build. A signature with a type
   variable in a parameter needs `NFData a`. The plan omits that signature;
   if inference then fails, the count of such functions is reported.
3. **`case` with a constructor pattern is refutable.** Scope. A `let` that
   destructures a pair keeps Haskell's lazy match today. Under the instrument
   it fails at the binding. That is the call-by-value behavior, so it counts
   as a finding, not an instrument fault.
4. **The pytest cells pin compiler text in some tests.** Scope. A text pin
   fails in every non-lazy mode. Those cells are listed and excluded by name.
