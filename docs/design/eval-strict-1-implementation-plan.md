---
name: eval-strict-1-implementation-plan
title: "EVAL-STRICT-1: implementation plan for call-by-value code generation (engineer)"
status: "APPROVED 2026-09-29; IMPLEMENTED on eval-strict-1/cbv-codegen 2026-09-30, with the deviations the last section records. Implements eval-strict-1-proposal.md Rev 2 (SETTLED)."
date: 2026-09-29
author: compiler-engineer
consumers: [user, documentation-lead, professor]
related: "eval-strict-1-proposal.md (Rev 2); eval-strict-1-measure-findings.md"
---

# EVAL-STRICT-1: implementation plan

## Restatement

Make the generated Haskell call-by-value as `eval-strict-1-proposal.md` Rev 2
§4.1, §4.5 and §4.6 state. The patch changes `compiler/src/LLMLL/CodegenHs.hs`
and the runtime preamble. It changes no verifier, type checker or schema.

## Context located

- `docs/design/eval-strict-1-proposal.md` Rev 2: the semantics, edge cases 1 to
  13, and the §0.1 text that lands with this patch (§4.4).
- `docs/design/eval-strict-1-measure-findings.md`: every gate passes when
  bindings and arguments are forced; full-value forcing at each use costs
  2.27 times on path-lint, WHNF forcing 1.09 times.
- `CodegenHs.hs` `emitLet`: one recursive Haskell `let`, so every binding is
  lazy. Measured on v0.26.17: `(let [(x 1) (x (+ x 1))] x)` passes `llmll check`
  and fails `llmll build` with GHC `Conflicting definitions for ‘x’`. The
  instrument's sequential `case` bindings build it and print 2.
- `CodegenHs.hs` `emitExpr`, `emitApp`, `emitOp`, `EPair`: arguments are
  emitted in place and never forced.
- `CodegenHs.hs` `emitDo`: one lazy `let` with tuple patterns; an unread step
  is never evaluated (proposal §4.5).
- `CodegenHs.hs` `toHsType (TFn args ret)`: `fn [] -> int` lowers to `Integer`,
  so a zero-parameter definition is a Haskell top-level value (proposal §4.6).
- `CodegenHs.hs` `emitMainHs`: the harness binds `let (s', cmd) = step s line r`
  and `let (state0, initCmd) = ...`, both lazy patterns.
- `CodegenHs.hs` `runtimePreamble`: `list_map = flip map`, `list_filter = flip
  filter`, `list_fold xs acc f = foldl f acc xs`, `string_concat = (++)`,
  `int_to_string = show`, `range from to = [from .. to - 1]`, and others. Each
  returns a lazy structure.
- `compiler/src/LLMLL/TypeCheck.hs` `builtinEnv`: about 100 builtins. A scan of
  its return types found 34 that return a list, string, map, pair or `Result`;
  the scan missed `bytes-set` and `bytes-zero`, so it is a lower bound.
- `compiler/src/LLMLL/ProofArtifact.hs` `codegenSemanticsVersion`:
  `"int-unbounded-1"`, the stamp that `replay-artifact` compares.
- Measured on the scratch instrument, 2026-09-29: in `whnf` mode, 1 hspec
  example of 2161 fails that passes in `lazy` mode. It is `HG-16`, which pins
  the `package.yaml` dependency list; the instrument added `deepseq` there.
- `docs/compiler-team-roadmap.md` row `EVAL-STRICT-1` (G2, marker PLAN).

## Plan summary

The patch keeps one invariant: **the WHNF of every term the generated code
builds is a full value.** Four rules establish it. (1) Every argument of an
application, constructor, operator and pair is forced to WHNF before the call.
(2) Every `let` binding and every `do` step is forced to WHNF before the body.
(3) Every builtin that returns a structure returns it fully built when its
arguments are full values, and it evaluates every user callback call that
call-by-value evaluates. (4) The harness forces each `(state, command)` pair
before it runs the command. The invariant follows by induction on the term,
because a full value's parts are full values. WHNF forcing needs no type class,
so a polymorphic binding needs no constraint and the `deep`-mode build failure
in the findings cannot occur. Rule 3 replaces both options the findings named:
no strict wrapper type and no `Text` change is needed. Each builtin builds only
its new cells, so a structure is never walked twice.

## Affected surface

`compiler/src/LLMLL/CodegenHs.hs`, in the order the patch applies them:

1. `emitLet`: nested `case e of !p -> ...` in binding order. Bindings become
   sequential, so a later binding may reuse an earlier name.
2. `emitExpr` for `EApp`, `EOp` and `EPair`: each argument that is not a
   variable, a literal or a lambda is bound by a forced `case` before the
   call. `and`, `or` and `=>` keep their right operand lazy.
3. `emitDo`: one forced `case` per step, anonymous and `:discard` steps
   included.
4. `toHsType (TFn [] ret)`: `() -> ret`. A zero-parameter definition emits
   `k () = <body>` with signature `k :: () -> T`.
5. `emitApp` for a zero-argument application: `(k)` emits `k ()` when `k` is
   not a builtin and not a constructor. A bare `k` stays a function value.
6. `ELambda []`: `(\() -> body)`. No zero-parameter lambda exists in the tree
   today, so this is for consistency with item 5.
7. `runtimePreamble`: strict producers for the container-returning builtins
   (table below). No other preamble function changes, so its internal laziness
   (`take 20 (... ++ repeat 0)`) stays and is not observable.
8. `emitMainHs`: `let !(s', cmd) = ...` and `let !(state0, initCmd) = ...`.
9. `emitLibHs`, `emitMainHs` headers: `{-# LANGUAGE BangPatterns #-}`.

| Builtin | Preamble today | Change |
|---|---|---|
| `list-map` | `flip map` | strict map: force each result, build the spine |
| `list-filter` | `flip filter` | strict filter: force each predicate result |
| `list-fold` | `foldl` | `foldl'` |
| `list-append` | `xs ++ [x]` | spine-forced append |
| `range` | `[from .. to - 1]` | spine-forced |
| `string-concat`, `string-concat-many`, `string-slice`, `string-trim`, `string-char-at`, `int-to-string` | lazy `String` | spine-forced result |
| `string-split` | lazy pieces | each piece and the spine forced |
| `bytes-set`, `bytes-zero`, `sha1`, `hmac-sha1` | lazy `[Word8]` | spine-forced result |
| `json-parse`, `json-serialize`, `json-get-string`, `json-as-string`, `json-get-number`, `json-as-number` | lazy tree and strings | one forcing pass over the result |

`list-prepend`, `pair`, `ok`, `err`, `list-head`, `list-tail`, `list-nth` and
`map-put` need no change: they return their forced arguments, or a part of
one, in one new cell. `Data.Map.Strict` already forces a stored value to WHNF,
which rule 3 makes a full value. The implementation re-reads the 34 rows of
`builtinEnv` against the preamble before it is review-ready, and adds any row
this table misses.

`compiler/src/LLMLL/ProofArtifact.hs`: `codegenSemanticsVersion` changes to
`"int-unbounded-1+cbv-1"`. A proof artifact written under lazy code generation
states soundness against a semantics this patch removes, so `replay-artifact`
must refuse it.

Not changed: `FixpointEmit.hs`, `TypeCheck.hs`, `Contracts.hs` (its `wrapPre`
comment becomes history; `documentation-lead` routes a comment edit only if
asked), `docs/llmll-ast.schema.json` (no schema change).

Documentation, in the same release, by `documentation-lead`: `LLMLL.md` §4
subsection (proposal §4.1), §0.1 replacement (proposal §4.4), §5.3, §9.6 and
§13.3 edits (proposal §7); `scripts/norm-claims/registry.json` rows `NC-001` to
`NC-004`; CHANGELOG; roadmap row.

## Verification impact

- Solver time: no change. No VC changes.
- New obligations: none (proposal §6).
- Trust model: the `codegen_semantics_version` stamp changes. Proof artifacts
  from earlier versions fail `replay-artifact`; that is the intended result.
  The implementation measures whether `VerifiedCache` keys a sidecar on the
  stamp, and states the count of committed sidecars that must be regenerated.
- Fragment: unchanged.
- Strict-verified-core: no function changes tier.
- Claims that change meaning: "proved only if they terminate" becomes correct
  (proposal §4.2). The §2 probe changes from exit 1 to non-termination.

## Performance budget

- GHC build of the compiler: one module, `CodegenHs.hs`, and its dependents
  `compiler/app/Main.hs` and `compiler/test/Spec.hs`.
- Generated code: `Lib.hs` grows by 18% to 53% (measured for the `whnf`
  instrument, which forces the same positions). Generated-program GHC build
  time rose 26% across the census in `whnf` mode, with a caveat: the
  measurement machine was shared at the time.
- Program runtime: acceptance limit **1.25 times** base on the path-lint live
  run and on the driver cover, alone on the machine, three runs each. The
  instrument's `whnf` mode measured 1.09 times without rule 3; rule 3 adds one
  pass over each new structure.
- `stack test` wall-clock: the new built-program tests add about 13 GHC builds
  of small programs, about 3 minutes.

## Contract plan

Nothing lands in the provable fragment. The patch changes code generation and
the Haskell preamble, which are outside `Σ_auto` and are trusted base
(`LLMLL.md` §0.1, `NC-037`, `NC-038`).

## Test plan

Baseline, measured 2026-09-29 on `f525266`: 2161 hspec examples; 417 Python in
`scripts/tests`.

1. **Edge cases as built programs:** `compiler/test/Spec.hs`, a new
   `EVAL-STRICT-1` block, 13 examples. Each builds a program with the subject
   and asserts its stdout and exit status. Cases 1, 2 and 6 to 8 diverge; each
   runs under a 10-second limit and asserts that it did not finish. All other
   cases assert a message or a value.
2. **Invariant checks:** 4 examples that separate WHNF from full values
   through each rule: a `list-map` result with one failing element, a map whose
   value is such a list, a string built by `string-concat-many` over such a
   list, and a `list-fold` whose failing intermediate step is discarded by the
   next one.
3. **Sequential `let`:** 1 example, `(let [(x 1) (x (+ x 1))] x)` builds and
   returns 2. Today it passes `check` and fails `build` (context above), so
   the patch also closes one check-versus-build disagreement.
4. **Zero-parameter definitions:** edge cases 12 and 13, plus 1 example that
   passes `stage-count`'s shape as a value and calls it through a binding.
5. **`NC-001` fixtures:** `scripts/doc-claims/` `@run` fixtures for edge
   cases 3, 10 and 12, each with `;; @norm: NC-001`. `DRIFT-CT-2` runs them.
6. **Text pin:** `HG-16` (the `emitPackageYaml` dependency list) is re-read;
   the patch adds no dependency, so it is expected to pass unchanged.

Target: 2161 + 19 = at least 2180 hspec examples; 417 Python unchanged; the
three new doc-claims fixtures pass.

End to end: rerun the measurement's behavior census with the patched compiler.
That is the seven port covers and live runs, pytest, the orchestra tests and
the driver cover. Run the build-smoke steps alone; `scripts/build_smoke.sh`
writes the fixed path `/tmp/llmll-fsenc`.

## Rollback

A single revert of the patch commit restores lazy code generation. No schema
or sidecar format changes. The stamp reverts with it. Worst case: a proof
artifact written by the patched compiler refuses to replay on the reverted one.

## Risks and unknowns

1. **A builtin missing from the rule-3 table.** Verification; complicates. A
   missed builtin returns a lazy structure, so a value can hold a thunk and
   the invariant fails for that builtin only. Mitigation: the `builtinEnv`
   re-read in the affected surface, and one invariant example per builtin
   family in the test plan.
2. **Laziness hidden in the preamble reaching a value.** Verification;
   complicates. A preamble function that returns part of its internal lazy
   state (for example the `wasi.fs.read` text) breaks rule 3. The FS-ENCODING-1
   work already forces read text inside its bracket (`evaluate (length ...)`).
   The implementation lists each `Response` payload source and confirms it.
3. **Order-dependent output in a gate.** Scope; only matters at scale. The
   proposal leaves argument order unspecified; a gate that pins which of two
   failures it sees would change. The measurement found none.
4. **Case bindings are monomorphic.** Build; only matters at scale. A `let`
   that binds a lambda and uses it at two types fails to compile. The census
   built 145 programs with `case` bindings and found none; the
   `withdraw-demo` failures on `main` built under them instead.
5. **Proof-artifact replay refusal.** DX; small. Users who stored artifacts
   must regenerate them. The CHANGELOG entry states this.

## Deviations recorded during implementation

Each was surfaced to the user before it was kept; items 4 and 5 were decided
by the user on 2026-09-30.

1. **The stamp does not change.** `codegenSemanticsVersion` stays
   `"int-unbounded-1"`. The v0.23.x CHANGELOG entry scopes the stamp to int
   versus machine-int and says INT-3 needs it unspent, and no VC changes, so a
   replayed verdict is unaffected.
2. **Built-program tests are pytest cells, not hspec examples.** The hspec
   suite does not build generated programs by convention (its `FR-5` case
   says so). The runtime cells are `scripts/tests/test_eval_strict_1.py` (14
   cells, a CI step in the spec-roundtrip job); hspec pins the emitted shapes
   (13 examples, `ES-1` to `ES-13`).
3. **Rule 3 is applied at the call site.** One table in `CodegenHs.hs`
   (`esResultForcers`) wraps a structure-returning builtin in `llmll_full` with
   its forcer, so the preamble bodies stay as they were, with two exceptions:
   `list-fold` uses `foldl'`, and `string-concat` copies its left operand
   strictly and shares the right one (`llmll_appendS`). `ES-11` checks the
   table against `builtinEnv`.
4. **`llmll build` removes a stale `.cabal` file (BUILD-DIR-REUSE).** The
   doc-claims port builds every `@run` fixture into one directory, and the
   second one failed with Stack `S-368` "Multiple Cabal files found". The
   tree had one `@run` fixture before this patch, so the defect was latent.
   With that fixed, the same directory held each earlier program's executable
   in `.stack-work/install/*/*/*/bin`, and the port, which needs exactly one
   binary there, reported no-single-binary. `staleCabalFiles` and
   `staleExecutables` select the files, `compiler/app/Main.hs` removes them at the three
   sites that write `package.yaml`, and `ES-13` pins both selections. The
   doc-claims live gate then passed 35 of 35.
5. **The runtime limit is 1.5 times, not 1.25.** Path-lint measured 12.3 s
   against 8.7 s with the forcers, and 10.3 s with every forcer disabled.
   Disabling any one kind of forcer saved nothing, and peak memory fell (155 MB
   against 197 MB), so the cost is evaluation call-by-value requires and lazy
   code skipped: values path-lint builds and never reads. `string_split` now
   makes one left-to-right pass. Final measurement, alone on the machine,
   three interleaved rounds: base 8.7 to 8.8 s, patched 11.6 to 12.1 s (1.33
   to 1.39 times), output byte-identical. Finding what path-lint computes and
   does not read is left to a separate row.
