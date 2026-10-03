---
name: example-build-1-measure-findings
title: "EXAMPLE-BUILD-1: why three examples pass check and fail build"
status: "MEASURED 2026-10-02 on v0.27.2 (159d641). Two causes, each confirmed by a control that removes it. The row's MEASURE is answered; the next action is a PLAN for each cause."
date: 2026-10-02
author: compiler-engineer
consumers: [user, compiler-engineer, documentation-lead]
related: "eval-strict-1-measure-findings (the census that filed the row)"
---

# EXAMPLE-BUILD-1: why three examples pass check and fail build

## 1. What was measured

The row (filed from the `EVAL-STRICT-1` build census) names three files that pass `llmll check` and fail `llmll build`: `examples/bytes-bounds/zero-buffer.llmll` with `GHC-83865`, and `examples/refine-demo/base.llmll` and `base.ast.json` with Stack's `S-4804`. Each was rebuilt on v0.27.2 from a `git archive` copy, the generated source and the Stack log were read, and each named cause was removed by a control to show it is the cause.

All three still fail on v0.27.2 with the same errors.

## 2. Cause A: contract instrumentation hides `bytes-zero` from its length

`zero-buffer.llmll`:

```
(def make-buffer [] -> bytes[32]
  (post (= (bytes-length result) 32))
  (bytes-zero))
```

The generated `Lib.hs` calls `bytes_zero` with no argument, and the runtime defines `bytes_zero :: Int -> [Word8]`:

```
(case (bytes_zero ) of { !result -> (if ... then (error "Postcondition violated in make-buffer") else result) })
```

`bytes-zero` takes its length from the declared return type. `CodegenHs` does that in one place: `emitBodyExpr` matches a body that is exactly `(bytes-zero)` under `-> bytes[n]` and emits `bytes_zero n` (the LEVER-A0 case). But `llmll build` runs `Contracts.instrumentContracts` first, in the default `--contracts=full` mode. `wrapPost` rewrites the body to `(let [result (bytes-zero)] (if (not post) (runtime-error …) result))`, and `wrapPre` wraps it in an `if`. The body is then no longer exactly `(bytes-zero)`, so the call reaches the generic `emitExpr` path, which emits no length.

**Controls.**

| Build | Result |
|---|---|
| `zero-buffer.llmll`, default `--contracts=full` | `GHC-83865`, exit 1 |
| `zero-buffer.llmll --contracts=none` | exit 0 |
| `relay-buffer.llmll`, `relay-overflow.llmll` (their `fresh32` is `(bytes-zero)` with no contract) | exit 0 |
| a `bytes-zero` body with a `pre` only | `GHC-83865`, exit 1 |

**Class.** Any `def` or `def-shell` whose body is `(bytes-zero)` and that has a `pre` or a `post` fails to build under `--contracts=full` or `unproven`. `check` and `verify` are unaffected: the verifier reads the length from the return type (`reifyBytesZeroLen` in `FixpointEmit`). In-tree population: one file (`zero-buffer.llmll`). `bytes-zero` is legal only as a whole body under a literal `-> bytes[n]`, so a contract is the only thing that can wrap it.

## 3. Cause B: the generated package is named after the file, and `base` is taken

`base.llmll` and `base.ast.json` generate a package whose `package.yaml` says `name: base`, and that package depends on `base >= 4.14`. Stack reads the local package as a replacement for the GHC boot library `base` and stops:

```
Error: [S-4804]
  In the dependencies for QuickCheck-2.14.3(-old-random):
    * base dependency cycle detected: base, regex-base, regex-tdfa, base
```

**Controls.**

| Build | Result |
|---|---|
| `base.llmll`, `base.ast.json` | `S-4804`, exit 1 |
| the same files copied to `basex.llmll`, `basex.ast.json` | exit 0, both |
| a one-line `text.llmll` (`text` is in the dependency closure) | `S-4804`, `text dependency cycle detected: text, regex-tdfa, text` |

**Class.** The package name is the file stem. A stem equal to any package in the generated package's dependency closure collides. The closure on v0.27.2 is 32 packages besides the generated one, measured with `stack ls dependencies`: `QuickCheck array async base binary bytestring containers cryptohash-sha256 deepseq directory exceptions filepath ghc-bignum ghc-boot-th ghc-prim hashable mtl os-string parsec pretty process random regex-base regex-tdfa rts splitmix stm template-haskell text time transformers unix`. `check` accepts any stem. In-tree population: the two `base` files; no other tracked `.llmll` or `.ast.json` stem is in the closure.

## 4. What this does not decide

The fixes are owed by a PLAN, not chosen here. The directions, with a recommendation for each:

- **Cause A.** Resolve the length before instrumentation, so the instrumented body already carries it, rather than teaching `emitExpr` about `bytes-zero` in every position. The determining context is the declared return type at the definition, which instrumentation has in hand. Recommended: give `bytes-zero` its length as an argument when the definition is instrumented, and keep the LEVER-A0 case for the uninstrumented body. Test: the four control rows above as build cells.
- **Cause B.** Make the package name independent of the stem, for example a fixed prefix (`llmll-<stem>`), so no stem can name a Haskell package. Rejecting colliding stems at `check` would track a dependency list that changes with the runtime. Recommended: the prefix. Test: `base` and `text` stems build.

Neither cause is a verification defect: no verdict depends on either. Both are cases of `check` and `build` disagreeing, which is G3's admission.
