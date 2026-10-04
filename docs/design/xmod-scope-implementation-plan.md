---
name: xmod-scope-implementation-plan
title: "XMOD-SCOPE: implementation plan for R1 to R4"
status: "APPROVED 2026-10-03 by the user; handed to llmll-patch-implementer. Implements docs/design/xmod-name-scope-proposal.md Rev 1 (R3 chosen). Closes TYPE-SHADOW-1, XMOD-CTOR-SEVERITY-1 and XMOD-QUAL-CTOR-1."
date: 2026-10-03
author: compiler-engineer
consumers: [user, llmll-patch-implementer, documentation-lead]
style: "ASD-STE100 Simplified Technical English. Haskell identifiers, compiler messages and test names keep their exact bytes."
---

# XMOD-SCOPE: implementation plan for R1 to R4

## Restatement

The proposal's four rules become checker and codegen changes.

- **R1:** one declaration for each top-level name in a build closure, with types and values checked separately.
- **R2:** a type's identity is its declaring module plus its name.
- **R3:** `M.f` and `M.C` resolve when the module imports M, and codegen removes the qualifier.
- **R4:** an imported name that is not in scope is an error in both modes.

The work is name resolution only. No verification condition changes.

## Context located

- `docs/design/xmod-name-scope-proposal.md` Rev 1: the settled rules, the measured cases t1 to t19, and edge cases E1 to E13.
- `docs/design/dup-def-1-engineer-plan.md`: the precedent for one module. It added `checkDuplicateTopLevel` with diagKind `duplicate-definition`.
- `docs/compiler-team-roadmap.md` rows `TYPE-SHADOW-1`, `XMOD-CTOR-SEVERITY-1`, `XMOD-QUAL-CTOR-1`: all at PLAN, and all point to this one plan.
- `compiler/src/LLMLL/Module.hs:166-210` (`loadFromFile`): type-checks each dependency against `cache1`. That cache can also hold sibling modules that this module does not import.
- `compiler/src/LLMLL/Module.hs:264-300` (`buildModuleEnv`): `meStatements` keeps every statement, exported or not, and `meExports` is filtered. So the build closure's full declaration set is already in memory.
- `compiler/src/LLMLL/EvidenceKey.hs:74-83` (`restrictCache`): an existing transitive-import walk over a `ModuleCache`. R1 reuses its shape.
- `compiler/app/Main.hs:502-530` (`loadStatementsMulti`): the entry loader for `check`, `verify`, `build` and `test`. The entry module's cache is its whole closure.
- `compiler/src/LLMLL/TypeCheck.hs:1550-1580` (`typeCheckWithCacheModeRet'`): the single shared typecheck for the entry and for each dependency. `seededEnv` holds qualified exports of every cached module.
- `compiler/src/LLMLL/TypeCheck.hs:1683-1700`: calls `checkDuplicateTopLevel`, then the constructor pass. A duplicate constructor goes through `tcWarnOrError`. Its comment says "a duplicate constructor still builds", which proposal F6 shows is incorrect.
- `compiler/src/LLMLL/TypeCheck.hs:2094-2120` (`checkStatement (SOpen …)`): emits `open-shadow-warning` on any name match. It also matches the prefix as text, so `lib.` matches the keys of a module `lib.sub`.
- `compiler/src/LLMLL/TypeCheck.hs:2384-2389` (`inferExpr (EVar …)`), `:2577-2581` (S4 dotted-name warning), `:2616-2617` and `:3135-3136` (`call to unknown function`): the R3 and R4 sites.
- `compiler/src/LLMLL/TypeCheck.hs:3398` (`compatibleWith _ (TCustom a) (TCustom b) = a == b`): the F3 rule. It is not changed. R2 resolves the names before they reach it.
- `compiler/src/LLMLL/TypeCheck.hs:557`, `:984`, `:1367`, `:1574`: `TCState` and its three positional construction sites.
- `compiler/src/LLMLL/CodegenHs.hs:144-151` (`generateHaskellMulti`): concatenates `meStatements` of every module into one `Lib.hs`. `toHsIdent` (`:2767`) maps `.` to `_`. So `lib.f` becomes `lib_f` and `lib.Ctl` becomes the type `lib_Ctl`, which is not valid Haskell.
- `compiler/src/LLMLL/PBT.hs:153-157`: says that PBT does not resolve qualified names, because §8.5 said the runtime does not. R3 makes that reason incorrect.
- `compiler/test/ModuleSpec.hs:195-213` (M-05) and `compiler/test/Spec.hs:20050-20056` (RF-E8): the two tests whose expectation changes.
- `compiler/test/fixtures/xmod-ag/use_double_qual.llmll`, `ModuleSpec.hs:619,728`: the verifier already proves a qualified call through the qualified contract key.

## Plan summary

Add one new pure module, `LLMLL.BuildScope`. It holds the closure walk, the declaration table, the R1 check and the R2 type resolver. It imports `LLMLL.Syntax` only, so `TypeCheck` and `Module` can both import it without a cycle.

R1 runs once for each typecheck, inside `typeCheckWithCacheModeRet'`, over the current module's own closure. The closure comes from `restrictCache`, not from the whole cache. A collision in a dependency's closure therefore fails that dependency's load. A collision between two branches fails only the entry.

R2 is a load-time rewrite of qualified type names (`TCustom "M.T"` to `TCustom "T"`). It runs once for each module, in `loadFromFile` and `loadStatementsMulti`. After that point, the checker, the verifier, the codegen and the evidence key all see one spelling.

R3 keeps qualified value names in the AST. The verifier and the evidence key already use them. The checker accepts them, and `generateHaskellMulti` removes the qualifier just before emission.

R4 adds a closure lookup at the three unknown-name sites. The changes are about 350 lines of Haskell and about 30 new hspec examples. The solver does not change.

**Why value names stay qualified and type names do not.** A qualified value name is part of the evidence key (`EvidenceKey.depsFragment` reads callee names from the body). It is also the verifier's contract key. If the loader rewrote it, the key of every existing qualified caller would change, and those callers would lose their sidecar evidence. A qualified type name never passed `check` before (t5, t14, t15). So no sidecar holds one, and the load-time rewrite cannot invalidate any evidence.

## Affected surface

**New module**

- `compiler/src/LLMLL/BuildScope.hs` (new, about 200 lines). It exports these functions:
  - `closureOf :: [Statement] -> ModuleCache -> ModuleCache`. This is `restrictCache`, moved here. `EvidenceKey.restrictCache` becomes a re-export, so its callers do not change.
  - `importChain :: [Statement] -> ModuleCache -> ModulePath -> [ModulePath]`. It is a BFS with parent pointers and gives the import path for a diagnostic (E4).
  - `data Decl = Decl { dModule :: ModulePath, dName :: Name, dNs :: Namespace, dExported :: Bool }`, with `data Namespace = NsType | NsValue`.
  - `closureDecls :: ModuleCache -> Map (Namespace, Name) [Decl]`. Type names come from `STypeDef` and `SDefInterface`. Value names come from `SDef`, `SDefShell`, `SDefLogic`, `SLetrec`, `SDefInvariant` and the constructors of each `TSumType`. The constructor list is recomputed here, so the module does not need to import `TypeCheck`.
  - `checkBuildScope :: [Statement] -> ModuleCache -> [Diagnostic]` (R1). One `Decl` comes from each (module, name) pair, so the same module reached twice is counted once (E5). The entry module's own declarations join the table under a sentinel path. A name with two or more distinct declaring modules in one namespace gives one error with diagKind `duplicate-definition`. The text is in the R1 paragraph below.
  - `resolveQualifiedTypes :: [Statement] -> ModuleCache -> [Statement]` (R2). It rewrites `TCustom "M.T"` to `TCustom "T"` when M is a direct import and M declares T. It checks parameter types, return types, the bodies of `STypeDef`, `let` annotations, `ELambda` parameters and interface signatures. An unresolved qualified name stays as written.
  - `unresolvedQualifiedTypes :: [Statement] -> ModuleCache -> [Diagnostic]`. It reports a `TCustom` that is still qualified and whose prefix is a module in the closure. The text: `type 'lib.Ctlx' is not declared in lib`. When the module is in the closure but is not a direct import, it adds `add (import lib)`.
  - `stripModuleQualifiers :: Set ModulePath -> [Statement] -> [Statement]` (R3 codegen). It rewrites `EVar`, `EApp` callee and `PConstructor` names of the form `M.x` to `x` when M is in the set. It uses the longest prefix match. `wasi.*` names never match, because no `wasi` module is in a cache.
- `compiler/package.yaml` / `llmll.cabal`: add `LLMLL.BuildScope` to `exposed-modules`.

**Loader (R2)**

- `compiler/src/LLMLL/Module.hs:166-190` (`loadFromFile`): after `cache1` is built, set `stmts' = resolveQualifiedTypes stmts (closureOf stmts cache1)`. Use `stmts'` for the typecheck and for `buildModuleEnv`.
- `compiler/app/Main.hs:502-517` (`loadStatementsMulti`): apply the same rewrite to the entry statements before the function returns them. Its callers are at `Main.hs:544` (`check`), `:615` (`test`), `:726` (`build`), `:806` (`build` from JSON), `:1257` (`verify`), `:2249` and `:2291` (`typecheck`) and `:2467` (`diverge-report`). Each one gets the rewrite.

**Checker**

- `compiler/src/LLMLL/TypeCheck.hs:557` (`TCState`): add two fields.
  - `tcClosureDecls :: Map (Namespace, Name) [Decl]` (R4).
  - `tcDirectImports :: Set ModulePath` (R3), filled from the module's own `SImport` statements.
  - Update all three construction sites (`:984`, `:1367`, `:1574`). `initialTCState` takes empty values, so a single-file check is unchanged.
- `compiler/src/LLMLL/TypeCheck.hs:1550-1580` (`typeCheckWithCacheModeRet'`):
  - Compute `cl = closureOf stmts cache`.
  - Add `checkBuildScope stmts cl ++ unresolvedQualifiedTypes stmts cl` to the diagnostics.
  - Seed the two new fields from `cl`.
  - The RET-RESOLVE pass (`resolveRetTypes`) keeps the R1 diagnostics out of its own runs, as it does today for all diagnostics.
- `compiler/src/LLMLL/TypeCheck.hs:1683-1700`:
  - Change the duplicate constructor from `tcWarnOrError` to `tcErrorK "duplicate-definition"` (§4.1, E12).
  - Correct the DUP-DEF-1 comment that says "a duplicate constructor still builds" (F6).
- `compiler/src/LLMLL/TypeCheck.hs:2094-2120` (`SOpen`):
  - Delete `open-shadow-warning` for a name that came from a module. R1 now rejects every real collision, and t18 is not a collision (F7).
  - Keep one warning for an opened name that shadows a `builtinEnv` entry. Its text is `'abs' from bi shadows a builtin`. This is the only `check` signal for E13 until `RESERVED-NAME-1` ships, so deleting it would make that case quieter.
  - Match the prefix on a module path, not on text. `lib.` must not pick up `lib.sub.x`. This is a defect the R1 work exposes, and the fix is three lines.
- `compiler/src/LLMLL/TypeCheck.hs:2577-2581` (S4 dotted-name warning): replace the warning with `qualifiedValueCheck func`. This is a new helper, used by the `EApp` path and the `EVar` path. For `M.x`, with M the longest module-path prefix in the closure, it does this:
  - M is a direct import and exports x: no diagnostic.
  - M is a direct import and declares x without exporting it: error `'h' is declared in priv and is not exported`.
  - M is in the closure and is not a direct import: error `lib is not imported here; add (import lib)`.
  - No module in the closure matches the prefix, and the prefix is not `wasi.`: keep the current S4 warning text.
- `compiler/src/LLMLL/TypeCheck.hs:2384-2389`, `:2616-2617`, `:3135-3136` (R4): before `tcWarnOrError` at an unknown bare name x, look up `(NsValue, x)` in `tcClosureDecls`.
  - If it is found, call `tcErrorK "name-not-in-scope"` with the R4 text, in both modes.
  - If it is not found, keep the current `tcWarnOrError`.
  - The texts:
    - `'Ran' is declared in lib; add (open lib) or write lib.Ran`
    - `'a-step' is declared in amain and is not exported`
  - The `EVar` site also needs the qualified case: an unexported `lib.h` misses `seededEnv` today and gives `unbound variable`. Route it to `qualifiedValueCheck` instead.

**Codegen (R3)**

- `compiler/src/LLMLL/CodegenHs.hs:144-151` (`generateHaskellMulti`): set `paths = Set.fromList (map mePath importedEnvs)`. Apply `stripModuleQualifiers paths` to `allStmts` before `generateHaskell`. No other emitter changes. `generateHaskell` (single-file) is unchanged, because without a module there is nothing to strip.
- `compiler/app/Main.hs:620-630` (`doTest --emit-only`) and `PBT.assembleTestStatements`: no change in this plan. See risk 4.

**Tests and fixtures**: see Test plan.

**Docs**

- `docs/llmll-ast.schema.json`: no change. A qualified name is already a dotted string (proposal §4.5).
- `LLMLL.md` §1 item 1, §8.5, §8.5.1, §8.6 and NC-011: documentation-lead, after ship (proposal §7).
- `compiler/src/LLMLL/PBT.hs:153-157`: the comment's §8.5 reason becomes incorrect. Change the comment so it states the real limit and names the follow-up row. Do not change the code.
- `docs/compiler-team-roadmap.md`: documentation-lead closes the three rows. It files one new row for risk 4 (PBT qualified names) if the measurement there shows a failure.

### Diagnostic texts (exact bytes)

- R1: `duplicate top-level definition 'Phase': type declared in modp1 and in modp2; a build's top-level names share one scope (LLMLL.md §1, §8.5)`. If a module is not a direct import, the text adds `(modp2 reached through wrap)`. The diagKind is `duplicate-definition`.
- R1, the entry module against a dependency: `… function declared in this module and in fa …`.
- R4: the texts are listed above. The diagKind is `name-not-in-scope`, which is new.

## Verification impact

- **Solver-time delta:** zero. No `.fq` emission path is touched. `FixpointEmit` sees the same statements, except that R2 rewrites a qualified type name. Today no program with a qualified type name reaches `verify`.
- **New proof obligations:** none.
- **Trust model:** no change to the trust closure, the weakness suppressions or evidence freshness. The evidence keys of existing programs do not move, because R3 leaves value names qualified in the AST. The census in proposal §2.3 shows that no tracked program contains a qualified type name to rewrite. The implementer re-runs that census as the first step (Test plan T0).
- **Fragment:** unchanged. Name resolution only (proposal §6).
- **Strict-verified-core:** no function moves out of body-faithful VC. R1 and R4 add errors only where the build already failed (t1 to t19), so no verified program is rejected.
- **Solver namespace:** after R1, two constructor symbols with the same name cannot reach one `.fq` file (proposal §6, `FixpointIR.fqCtorSym`).

## Performance budget

- **GHC build:** one new module. `TypeCheck.hs` is the recompilation fan-out, as for any checker change. About +5 s on a full `stack build`.
- **`stack test`:** about 30 new examples, each a small in-memory check, plus 3 new fixture builds through GHC (R3 end-to-end, t16 control, t18). Each build costs about 8 s. Estimate +30 s wall-clock.
- **`llmll check` at run time:** the closure walk is linear in the number of import edges. The declaration table is linear in the number of top-level declarations. For the largest tracked program (`tools/llmll-driver/`), that is under 1 ms against a check measured in seconds.
- **Caches:** no ProofCache or VerifiedCache effect.

## Contract plan

This change puts nothing in the provable fragment. All code is Haskell compiler code in the type channel, and no LLMLL source is added except test fixtures, which carry no contracts.

## Test plan

Measured baseline: see the line at the end of this section. All new hspec examples go in `compiler/test/ModuleSpec.hs`, in one new `describe "XMOD-SCOPE"` block. Each test uses either `mkCache` (in memory) or a new fixture directory `compiler/test/fixtures/xmod-scope/`. That directory holds the proposal's §2.1 files: `modp1`, `modp2`, `fa`, `fb`, `ca`, `cb`, `lib`, `wrap`, `priv`, `bi`, and one entry file for each case.

- **T0 (before any code):** re-run the proposal §2.3 census on the branch base. Also search the whole tree for a qualified `TCustom` in a type position. Both counts must be zero. Otherwise stop and report.
- **R1:**
  - E1 (t13) is the positive witness: an error naming `modp1` and `modp2`, with diagKind `duplicate-definition`.
  - E2 (t1, t10): an error, in both strictness modes.
  - E3 (t12): an error.
  - E4 (t11): an error whose text contains `wrap`.
  - E5 (t18): no diagnostic at all, and the build succeeds.
  - E6 (t4): an error in the value namespace.
  - E7 (`Box` type and `Box` constructor across modules): no diagnostic.
  - t2 and t3: an error.
  - A dependency whose own closure collides: the load fails with the error attributed to that dependency.
  - Two siblings that do not import each other, but both declare a name: only the entry check fails.
- **E12 (t19):** an error in both modes. Before this change it was a warning in plain `check`.
- **R2:**
  - E8 (t14, t15): accepted.
  - E9 (t8): still rejected.
  - The type-identity statement owed by `TYPE-SHADOW-1`: two modules declare different sums, `A` and `B`, and a value of `A` passed where `B` is annotated is rejected. Write it with distinct type names, because R1 now rejects equal names.
  - An unknown qualified type (`lib.Ctlx`): an error.
  - A qualified type from a module that is in the closure but is not a direct import: an error with `add (import …)`.
  - After the load-time rewrite, `meAliasMap` keys and `TCustom` names agree. This is checked on the loaded cache.
- **R3:**
  - t5 (`lib.Ran` under annotation `lib.Ctl`) is accepted.
  - t6 (`lib.f`) is accepted, with no S4 warning.
  - An unexported `priv.h`: an error.
  - `sib.f` where `sib` is in the cache but is not imported: an error.
  - `wasi.http.get` gets no new diagnostic (regression).
  - `stripModuleQualifiers` unit tests: longest prefix, `wasi.` untouched, `PConstructor` rewritten, and a name inside a lambda body rewritten.
- **R4:**
  - E11 / t7 (`Ran` not opened): an error in both modes, with the `add (open lib)` text.
  - The unexported case: an error with `is not exported`. This is the negative test for proposal risk 4: the unexported name stays unusable.
  - A name that no module declares keeps the warning in plain `check` (regression).
- **SOpen:**
  - t18 gives no warning.
  - `bi` opened with `abs`: one builtin-shadow warning.
  - `lib` and `lib.sub` both cached, open `lib`: no key from `lib.sub` is injected.
- **Changed expectations:**
  - `ModuleSpec.hs` M-05 now asserts an R1 error (diagKind `duplicate-definition`) instead of `open-shadow-warning`. The test name changes to match.
  - `Spec.hs` RF-E8 now asserts the R4 error text `'a-step' is declared in amain and is not exported`, with severity error. The test name drops "keeps it a warning at check".
  - Each change carries a one-line comment that cites this plan.
- **End-to-end:**
  - `llmll build` on a fixture that uses `lib.f`, `lib.Ran` and `lib.Ctl` without `open` must build and run with the expected output.
  - `use_double_qual.llmll` gets a build-and-run test (proposal §7).
  - `llmll verify` on `use_double_qual.llmll` keeps its current verdict and the same evidence key. Compare the sidecar bytes before and after.
- **Corpus sweep:** `check` every tracked `.llmll` and `.ast.json` file on the branch base and on the branch. The accepted set must not shrink, except for files listed as expected failures. Expected: no change (proposal §2.3).
- **Python:** `python -m pytest scripts/tests/` must pass. No Python change is expected.
- **Count target:** baseline + about 30 hspec examples. No decrease is allowed.

Baseline measured on `main` at `d763207` (2026-10-03): **2200 hspec examples, 0 failures; `pytest scripts/tests/` 312 passed, 134 skipped.** Target: about 2230 hspec examples, with pytest unchanged.

## Rollback

- **Revert:** one commit for each rule group is possible (R1 with E12 and SOpen, R2, R3, R4). But R3 must not ship without R1, so the revert order is R3 before R1. Recommend one feature branch with four commits, merged together.
- **Flag:** none. A flag would keep the warning-then-GHC-failure path alive, and that path is the defect.
- **Schema:** not touched.
- **Caches in user environments:** `.verified.json` keys do not move (Verification impact). No `.fq` file changes.
- **Worst case:** a user program in a hub library has a private helper with the same name as a local helper (proposal risk 1). It was already failing at `build`. It now fails at `check`. Unwinding R1 brings back the GHC error, not a working build.

## Risks and unknowns

1. **An entry loader that does not use `loadStatementsMulti`.** Classification: build / DX. Source: `doRun` (`Main.hs:858`), `doCheckout` (`:2374`), `doPatchWith` (`:2679`) and `compiler/src/LLMLL/Serve.hs` do not appear among the `loadStatementsMulti` callers. If a path skips the R2 rewrite, a qualified type is accepted by `check` and rejected by that path. The implementer must find every call site of `loadModule` and `parseFile` before writing R2, and must route each one through the rewrite. Effect: complicates the plan; does not block it.
2. **`typecheck --sketch` does not run R1.** Classification: DX. Source: `runSketch` takes a `TypeEnv`, not a cache (`TypeCheck.hs:3508`). A sketch of a colliding program reports holes and no collision. `check` still rejects the program. Recommendation: accept this for now, and record it in the hand-off. Adding a cache parameter to `runSketch` changes four callers, and it is a separate change.
3. **Seeded env contains modules this module does not import.** Classification: verification ergonomics. Source: `Module.hs:180` passes `cache1`, which can hold siblings. Today `sib.f` resolves for a module that never imported `sib`. `qualifiedValueCheck` closes this. A program in the tree that relies on it would now be rejected. The corpus sweep measures this. Effect: only a problem if the sweep finds a case.
4. **PBT does not follow R3.** Classification: scope. Source: `PBT.hs:153-176`. `assembleTestStatements` brings in imported definitions for opened modules only, and it does not strip qualifiers. After R3, `build` accepts `lib.f` without `open`, but `llmll test` may report an unknown function. Measure this once on the R3 fixture. If it fails, documentation-lead files a follow-up row. This plan does not widen PBT.
5. **`stripModuleQualifiers` and a local name that contains a dot.** Classification: build. A plain LLMLL identifier contains no `.`; a dotted name is a `QualIdent` (`LLMLL.md` §2.1, lines 59-67). The rewrite matches only prefixes that are module paths in the closure, so a `wasi.*` call and an unmatched dotted name are not changed. Effect: small; covered by the unit tests in R3.
6. **R4 text names a module but the user wants a local name.** Classification: DX. The R4 error fires only when a closure module declares the name. That is exactly the case where GHC would bind it, so the text is correct. Effect: none known.

## Hand-off note for later

After ship, the hand-off to documentation-lead must include these points:

- The `LLMLL.md` §1, §8.5, §8.5.1 and §8.6 texts (proposal §7).
- The new diagKind `name-not-in-scope`.
- The count delta.
- The PBT measurement from risk 4.
- The sketch gap from risk 2.
- The builtin-shadow warning that stays for `RESERVED-NAME-1`.

## Amendment 1 (2026-10-04, approved by the user)

**Trigger.** The implementation passed every test. But the doc-claims CI gate (DRIFT-CT-2) failed on 2 of 35 claims: `scripts/doc-claims/open-after-def-typecheck.llmll` and `open-after-def-verify.llmll`. Each one calls `inc` before its `(open open-aux-lib)`. R4 rejects that call, which is correct. But the R4 text says `add (open open-aux-lib)`, and that misleads, because the `open` is already in the module.

**Change.** At an R4 site, look for a later `(open M)` in the same module that would bring x into scope. If one exists, use this text instead: `'inc' is used before (open open-aux-lib); move the open above its first use`. The diagKind stays `name-not-in-scope`. Add one hspec example for this text. Add one regression example: with no later `open`, the text is the original R4 text.

**Doc follow-up (documentation-lead, after ship).** The two claim fixtures, their rows in `scripts/doc-claims/README.md`, and `docs/getting-started.md` §4.8 and §4.9. The typecheck claim changes from a warning with exit 0 to an error.
