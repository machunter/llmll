---
name: eval-strict-1-measure-findings
title: "EVAL-STRICT-1: migration measurement findings (engineer)"
status: "MEASURED 2026-09-29 on f525266 (v0.26.17). Implements eval-strict-1-measure-plan.md. No tree file changed."
date: 2026-09-29
author: compiler-engineer
consumers: [user, language-team, documentation-lead]
related: "eval-strict-1-proposal.md (Rev 1, accepted 2026-09-29); eval-strict-1-measure-plan.md"
---

# EVAL-STRICT-1: migration measurement findings

## Result

No program in the tree depends on lazy evaluation on any path that a gate
runs. Every gate that passes today passes in `whnf` mode and in `deep` mode.
The migration of LLMLL source is zero files. The cost is in code generation:
full-value forcing at every call site makes the path-lint tool 2.3 times
slower. The real patch must make values strict when they are built, not
re-force them at every use.

## Instrument

A scratch copy of the compiler at `f525266`, with one change in
`compiler/src/LLMLL/CodegenHs.hs`. The mode is `lazy`, `whnf` or `deep`.

- Each `let` binding becomes a nested `case F (e) of !p -> ...`.
- Each argument of an application or operator that is not a variable, a
  literal or a lambda becomes a forced `case` binding.
- `and`, `or`, `=>`, `if`, `match` and lambda bodies are not forced.
- `F` is the identity in `whnf` and `Control.DeepSeq.force` in `deep`.
- `deep` also derives `Generic, NFData` for every type in `Lib.hs` and gives
  `IO a` and `Async a` a WHNF-only `NFData` instance.

The seven tool ports received between 35 and 454 forcing sites each (454 in
`sequencer`). Generated `Lib.hs` grew by 18% to 53% in `whnf` and by 24% to 70%
in `deep`.

## Controls

| Control | Result |
|---|---|
| `lazy` output against the `f525266` compiler | 314 of 314 generated files byte-identical (293 census, 21 ports) |
| Proposal edge cases 1 to 9 in `deep` | 9 of 9 as the proposal states |
| Edge cases 6, 7, 8 in `whnf` | all 3 return, as a WHNF-only codegen must |
| Edge cases 3, 4 in `whnf` and `deep` | both fail at the binding |
| Edge case 1 (the §2 probe) | `lazy` exits 1 with `Precondition violated in tally`; `whnf` and `deep` do not terminate |

The instrument separates the three semantics on the cases built to separate
them. A pass in the tree is therefore a statement about the tree.

## Build census

145 entry files (138 in `examples/`, 7 tool ports), each built in 4 modes.

| Mode | Builds | Fail |
|---|---|---|
| base (`f525266`) | 145 | 7 |
| `lazy` | 145 | 7 (the same 7) |
| `whnf` | 145 | 3 |
| `deep` | 145 | 4 |

- **`deep` breaks one build.** `examples/hangman_json_verifier/hangman.ast.json`:
  `prop_initial_wrong_count_is_0` forces the result of `state-wrong-count`, whose
  signature `emitDefLogic` omits because its return type is polymorphic. GHC
  cannot resolve `NFData a0`. This is a mechanism fault, not a program fault.
  The real patch must have a type at each forcing site.
- **Side finding, not in scope.** 7 example files fail `llmll build` on
  `main` today: `examples/withdraw-demo/demo`, `withdraw-outcome-bad` (both
  `.llmll` and `.ast.json`), `examples/refine-demo/base` (both) and
  `examples/bytes-bounds/zero-buffer.llmll`. The four `withdraw-demo` files
  build in `whnf` and `deep`. The cause: a hole bound in a Haskell `let` is
  generalized, and `result == (ok ...)` in the post-check has an ambiguous
  type. A `case` binding is monomorphic, so the error goes away. No roadmap row
  names these seven failures.

## Behavior census

Each step ran in each mode, with the port and the compiler both built in that
mode, on a separate clone of `f525266`.

| Step | base | `whnf` | `deep` |
|---|---|---|---|
| `doc_archive_cover.py` (17 cells) and live run | pass | pass | pass |
| `doc_claims_cover.py` (21 cells) and live run | pass | pass | pass |
| `doc_path_lint_cover.py` and live run | pass | pass | pass |
| `refute_crux_cover.py` and live run | pass | pass | pass |
| `build_smoke_cover.py --no-slow` and live run | pass | pass (see note) | pass |
| `version_gate_cover.py` (15 cells) | pass | pass | pass |
| `driver_ll_cover.py` (81 cells) | pass | pass | pass |
| `pytest scripts/tests` | 417 pass | 417 pass | 417 pass |
| `pytest tools/llmll-orchestra/tests` | 115 pass | 115 pass | 115 pass |

Note: the first `whnf` run of `build_smoke_cover.py` failed its control cell.
`scripts/build_smoke.sh` writes to the fixed path `/tmp/llmll-fsenc`, and the
three modes ran at the same time. Rerun alone, it passes. This is a harness
collision, not a finding.

The path-lint live output in `whnf` and `deep` is byte-identical to base.

## Time

Path-lint live run over the tree, alone on the machine, three runs each:

| Mode | Time | Against base |
|---|---|---|
| base | 8.7 s | 1.00 |
| `whnf` | 9.5 s | 1.09 |
| `deep` | 19.7 s | 2.27 |

The other steps are dominated by GHC builds and solver calls, so the runtime
of the program does not show. The census GHC build total rose from 920 s
(base) to 1158 s (`whnf`) and 1322 s (`deep`). The `whnf` and `deep` phases ran
while the covers used the same machine, so these two figures are high.

## What the measurement does not show

1. **Paths no gate runs.** A lazy-dependent expression on a path no gate runs
   is not seen. The controls show the instrument would catch one.
2. **Instrument gaps.** Four positions are not forced: steps in a `do` block
   (`emitDo`), a variable that names a zero-argument definition, a function
   result that no caller binds, and the runtime preamble. Each is lazy in
   the instrument and must be strict in the real patch.
3. **The hspec suite was not run.** Its codegen tests compare generated text.
   The real patch changes that text, so the suite will need new expected
   text; that is part of the patch cost, not the migration.

## Recommendation

1. **The source migration is zero.** No LLMLL program changes. The spec text
   (proposal §4.1) can proceed without a migration plan.
2. **Do not ship force-at-every-use.** `deep` as built here costs 2.3 times on
   the largest text workload. The cause is repeated traversal: each call
   re-walks a value that an earlier call already forced.
3. **Make values strict when they are built.** Strict constructor fields and a
   strict spine for the list, `bytes`, `string` and map types mean a value is
   built once, fully. Then `whnf` forcing at bindings and arguments is enough,
   and `whnf` costs 9% here. Two ways exist:
   - strict wrapper types in the preamble for list, `bytes` and map values;
   - `Text` and strict `ByteString` for `string` and `bytes`.

   The engineer plan for the patch chooses between the two, with a measured
   comparison on path-lint and the driver.
4. **Close the four instrument gaps in the real patch.** Edge cases for each
   go into the test plan.
5. **Put a type at each forcing site.** The `hangman_json_verifier` failure
   shows that forcing needs a known type. Either emit the omitted signatures
   with the class constraint, or force through a monomorphic helper chosen
   from the type checker's result.
6. **Route the seven failing example builds** as a separate `fix/` row. They
   fail today, under lazy codegen, and are not part of EVAL-STRICT-1.
