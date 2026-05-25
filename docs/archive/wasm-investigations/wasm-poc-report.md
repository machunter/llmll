# GHC WASM Proof-of-Concept Report

> **Date:** 2026-04-16
> **Compiler version:** v0.3.2
> **Verdict:** CONDITIONAL GO — feasible for pure logic, but requires significant toolchain work

---

## 1. Environment Assessment

| Component | Status | Details |
|-----------|--------|---------|
| Host GHC | 9.6.6 (via Stack) / 9.6.4 (system) | aarch64-apple-darwin |
| `wasm32-wasi-ghc` | ❌ Not installed | Not part of standard GHC distributions |
| `wasmtime` | ❌ Not installed | WASI runtime not present |
| `ghc-wasm-meta` | ❌ Not cloned | Required toolchain manager |
| Homebrew | ❌ Not available | Cannot use `brew install wasmtime` |

**The GHC WASM backend is a separate cross-compiler.** It is not a flag on the stock GHC binary. You must install a custom GHC build via [`ghc-wasm-meta`](https://gitlab.haskell.org/ghc/ghc-wasm-meta), which provides `wasm32-wasi-ghc`, `wasm32-wasi-cabal`, and the `wasi-sdk`.

## 2. Generated Code Analysis (hangman_json_verifier)

The generated `Lib.hs` is **244 lines** of pure Haskell with these dependencies:

| Dependency | Used For | WASM Compatible? |
|------------|----------|-----------------|
| `base` | Prelude, Data.List, Data.Char | ✅ Yes — core library, works on WASM |
| `containers` | Data.Map.Strict | ✅ Yes — pure Haskell, no FFI |
| `QuickCheck` | Property-based tests (check blocks) | ⚠️ Probably — uses `System.Random`, may need shim |
| `System.IO` | `hPutStr stderr`, stdin/stdout | ⚠️ Conditional — WASI provides stdio via fd 0/1/2 |

**The generated user logic is entirely pure.** No network, no filesystem, no threading. The only IO is the `def-main` console harness (stdin/stdout via `System.IO`).

### Runtime preamble assessment

The runtime preamble (~150 lines) uses only:
- `Data.List` (pure)
- `Data.Char` (pure)
- `Data.Map.Strict` (pure)
- `System.IO.hPutStr` (WASI stdio)

**Verdict: The generated hangman code should compile to WASM with minimal changes.**

## 3. Compiler Dependencies (what does NOT need to compile to WASM)

The **compiler itself** (`llmll` binary) does NOT need to run in WASM. Only the **generated output** runs in a WASM sandbox. The compiler's dependencies (megaparsec, aeson, warp, optparse-applicative, etc.) are irrelevant to the WASM story.

This is an important distinction: `llmll build --target wasm` means "compile the generated Haskell to WASM", not "run the compiler in WASM."

## 4. Blockers Identified

### Blocker 1: Toolchain Installation (MEDIUM)

**Issue:** `wasm32-wasi-ghc` must be installed via `ghc-wasm-meta`. This is a ~1GB download including `wasi-sdk`, a custom GHC build, and WASI system libraries. It's not available via `ghcup` or `stack` as a standard target.

**Mitigation:** One-time setup. Can be scripted. Add a `scripts/setup-wasm-toolchain.sh` that automates the `ghc-wasm-meta` installation.

**Impact on users:** Any user wanting `--target wasm` must run the setup script first. CI needs the toolchain pre-installed.

### Blocker 2: Stack vs. Cabal (MEDIUM)

**Issue:** Our generated projects use Stack (`stack.yaml` + `package.yaml`). The WASM cross-compiler uses `wasm32-wasi-cabal`, not Stack. Stack does not support cross-compilation targets.

**Mitigation:** For `--target wasm`, generate a `cabal.project` file alongside the existing Stack files. The `llmll build --target wasm` path would invoke `wasm32-wasi-cabal build` instead of `stack build`.

**Impact:** Need to add Cabal project file generation to `CodegenHs.hs`. Dual build system (Stack for native, Cabal for WASM).

### Blocker 3: QuickCheck in WASM (LOW)

**Issue:** QuickCheck uses `System.Random` which relies on OS entropy. WASI provides `random_get` but the Haskell `random` package may need a shim.

**Mitigation:** Two options:
1. Strip `check` blocks from WASM builds (they're development-time, not production)
2. Use `wasi:random/random` import for `random_get` — this is a standard WASI capability

**Impact:** If we strip check blocks, no issue. If we keep them, minor shim work.

### Blocker 4: GHC Version Alignment (LOW)

**Issue:** Our Stack resolver uses GHC 9.6.6. The `ghc-wasm-meta` WASM backend may be on a different GHC version (typically tracks GHC HEAD or recent stable).

**Mitigation:** The generated code uses basic Haskell — no GHC extensions that vary between 9.x versions. Version skew is unlikely to cause issues for the generated code.

## 5. What Would `llmll build --target wasm` Look Like?

```
llmll build --target wasm examples/hangman_sexp/hangman.llmll
```

1. Parse + type-check (unchanged)
2. Generate `Lib.hs` + `Main.hs` (unchanged)
3. Generate `hangman.cabal` (NEW — instead of package.yaml)
4. Strip `check` blocks (optional — `--contracts none` already does this)
5. Invoke `wasm32-wasi-cabal build` instead of `stack build`
6. Output: `hangman.wasm` in the output directory
7. Run with: `wasmtime hangman.wasm` (or any WASI runtime)

## 6. Capability Enforcement in WASM

This is the v0.4 payoff. WASM capabilities map cleanly to LLMLL capabilities:

| LLMLL Capability | WASI Interface | Enforcement |
|-----------------|----------------|-------------|
| `cap.read "/data"` | `wasi:filesystem/preopens` | Only preopened directories are accessible |
| `cap.net-connect "https://..."` | `wasi:sockets/tcp` | Not available unless explicitly granted |
| `cap.http-get` | `wasi:http/outgoing-handler` | Component model import |
| `cap.random-get` | `wasi:random/random` | Standard WASI import |

**Docker's network/filesystem policy is replaced by WASM import declarations.** If the module doesn't import `wasi:sockets`, it physically cannot make network calls. This is a compile-time guarantee, not a runtime policy.

## 7. Recommendation

### GO — with phased approach

| Phase | Work | Estimate | Prerequisite |
|-------|------|----------|-------------|
| **Phase 0** | Install `ghc-wasm-meta` + `wasmtime`, compile hangman by hand | 1 day | None |
| **Phase 1** | Add `--target wasm` flag, generate `.cabal` file, invoke `wasm32-wasi-cabal` | 2-3 days | Phase 0 success |
| **Phase 2** | Strip check blocks for WASM builds, add WASI capability import mapping | 2 days | Phase 1 |
| **Phase 3** | CI integration, setup script, docs | 1 day | Phase 2 |

**Total: ~6-7 days of engineering work for v0.4.**

### Risk Assessment

- **Technical risk: LOW.** The generated code is pure Haskell with minimal IO. The WASM backend handles this well.
- **Toolchain risk: MEDIUM.** `ghc-wasm-meta` is maintained by a small team. If it falls behind GHC releases, we're blocked.
- **Ecosystem risk: LOW.** Our dependencies (`base`, `containers`) are core libraries with WASM support. We don't use anything exotic.

### Immediate Next Step

**Install `ghc-wasm-meta` and run the manual compilation:**

```bash
# 1. Install ghc-wasm-meta
git clone https://gitlab.haskell.org/ghc/ghc-wasm-meta.git
cd ghc-wasm-meta && ./setup.sh
source ~/.ghc-wasm/env

# 2. Install wasmtime
curl https://wasmtime.dev/install.sh -sSf | bash

# 3. Try compiling the hangman Lib.hs
cd /path/to/generated/hangman_json_verifier
wasm32-wasi-cabal init
wasm32-wasi-cabal build

# 4. Run it
wasmtime dist-newstyle/.../hangman.wasm
```

If this works, v0.4 WASM hardening is straightforward. If it doesn't, the error messages will identify the specific blockers.

---

> **Filed as:** v0.3.2 GHC WASM PoC spike
> **Status:** Report complete — Phase 0 (manual compilation) not yet executed (requires toolchain installation)
