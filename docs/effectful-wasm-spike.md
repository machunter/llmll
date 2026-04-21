# `effectful` WASM Compatibility Spike — Results

**Date:** 2026-04-21
**Verdict:** ✅ **GO** — `effectful` compiles, links, and runs correctly under `wasm32-wasi`.

## Environment

| Component | Version |
|-----------|---------|
| GHC (cross-compiler) | 9.12.4.20260402 (`wasm32-wasi-ghc`) |
| Cabal | 3.14.2.0 (`wasm32-wasi-cabal`) |
| Wasmtime | 44.0.0 (af382d7d9, 2026-04-20) |
| `effectful` | 2.6.1.0 |
| `effectful-core` | 2.6.1.0 |
| Host | macOS (aarch64) |
| Toolchain | `ghc-wasm-meta` bootstrap.sh, FLAVOUR=9.12 |

## Test Program

Minimal `effectful` program using `State` effect + `runPureEff`:

```haskell
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeApplications #-}
module Main where

import Effectful
import Effectful.State.Static.Local

counter :: (State Int :> es) => Eff es Int
counter = do
  modify @Int (+ 1)
  get @Int

main :: IO ()
main = do
  let result = runPureEff $ runState (0 :: Int) counter
  case result of
    (n, _) -> putStrLn $ "Counter: " ++ show n
```

## Build Log

```
$ wasm32-wasi-cabal build

Building     effectful-core-2.6.1.0 (lib)    ✅
Building     effectful-2.6.1.0 (lib)         ✅
[1 of 1] Compiling Main             ✅
[2 of 2] Linking ...effectful-wasm-spike.wasm ✅
```

All dependencies in the transitive closure compiled without errors:
`primitive`, `stm`, `unliftio-core`, `unliftio`, `monad-control`,
`async`, `transformers-base`, `unordered-containers`, `effectful-core`, `effectful`.

**No C shim failures. No linker errors. No FFI issues.**

## Execution

```
$ wasmtime run effectful-wasm-spike.wasm
Counter: 1
```

Correct output. The `Eff` monad + `State` effect handler executes identically in WASM as on native.

## Implications for LLMLL

1. **Typed effect rows are WASM-compatible.** The planned `Command` type migration from `IO ()` to `Eff '[HTTP, FS, ...] r` will not be blocked by WASM backend limitations. No shims or workarounds required.

2. **`effectful-core` has no C dependencies.** The library is pure Haskell. The only FFI-heavy dependencies in the extended ecosystem (`effectful-plugin` for GHC plugin optimization) are optional and not needed for the core effect system.

3. **Template Haskell:** GHC 9.12 supports TH for WASM targets. `effectful-th` (used by some downstream libraries for boilerplate generation) should work, but was not tested in this spike. Non-blocking — LLMLL codegen does not use TH.

4. **32-bit Int:** WASM is a 32-bit platform. LLMLL's `TInt` maps to Haskell `Integer` (arbitrary precision), which is unaffected. `TBytes Int` size parameters should be validated against 32-bit limits if WASM is the target.

## Recommendation

Proceed with typed effect row design. No design changes needed for WASM compatibility.
The `effectful` migration can be implemented independently of the WASM build target timeline.
