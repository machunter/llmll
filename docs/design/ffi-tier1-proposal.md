---
title: FFI-TIER1-1 — making Tier 1 Hackage imports work
status: Rev 2, SETTLED 2026-10-20
rows: FFI-TIER1-1 (G3); depends on FN-PARAM-PAREN-1 (G3)
review: two professor passes (Rev 0 and Rev 1, 2026-10-19 and 2026-10-20), folded below as the Appendix; no standalone review file
---

# FFI-TIER1-1: making Tier 1 Hackage imports work

**Status: Rev 2, SETTLED 2026-10-20.** Rev 0 was the language-team draft of 2026-10-19. Rev 1 answered the first professor review. Rev 2 applies the seven edits of the second professor review, which asked for no further pass.

## Change log

### Rev 0 → Rev 1 (first professor review)

| Finding | Disposition | Where |
|---|---|---|
| (a) no `ffi` trust level; disclose per entry | **Accepted.** New additive key `ffi_assumptions`, own and inherited. **Pushback:** an additive key needs no `trust_report_version` change. | D9 |
| (b) ship D3 before a conversion layer; narrowing as a QF-LIA `pre` | **Accepted.** The `pre` needs contracts on interface entries, which is its own addition. | D3, rows |
| 1 two build-time gaps (export existence, type agreement) | **Accepted.** | D7 |
| 2 instantiation, not equality | **Accepted.** | D3, soundness 1 |
| 3 lazy results move the failure site | **Accepted, forcing chosen.** **Pushback on the means:** no `deepseq`; reuse the EVAL-STRICT-1 forcers. | D1 |
| 4 `LINE` reset; columns count generated text | **Accepted.** | D1, D7 |
| 5 strict core keeps rejecting FFI callers | **Accepted.** Uninterpreted FFI is a later addition. | Verification mapping |
| 6 Safe claim at two lines | **Accepted and widened** to the `seccomp-bpf` claim. | Findings |
| 7 reach is narrower than stated | **Accepted.** Reach table added. | D8 |
| 8 pinned signature table | **Accepted as a follow-up row.** **Correction:** `compiler/generated-deps.txt` holds package names, not versions. The versions come from the generated `stack.yaml` resolver, `lts-22.43`. | Rows |

### Rev 1 → Rev 2 (second professor review)

| Edit | Disposition | Where |
|---|---|---|
| 1 forcers are a table keyed by builtin name, not built from types | **Accepted, verified.** `esResultForcers` is a name-keyed list. `llmll_uE` has the fixed type `Either String a`. `llmll_uP` forces each component to WHNF only. No map forcer exists. Rev 2 specifies a type-directed generator `forcerFor` and three new combinators. Still no `deepseq`. | D1 |
| 2 a function-typed parameter loses its parentheses | **Accepted, verified, preferred option taken.** `toHsType (TFn args ret)` joins the parts with `" -> "` and adds no parentheses, so a function-typed parameter flattens into the outer arrow. FFI-TIER1-1 depends on FN-PARAM-PAREN-1. `filter` is marked as blocked in the reach table. | D3, D8, rows |
| 3 "at the call" is stronger than the mechanism | **Accepted, with the citation.** `llmll_full` forces when its result is first demanded. The EVAL-STRICT-1 invariant (the comment that opens `runtimePreamble`) forces every argument, let binding and do step to WHNF. So the first demand is the nearest enclosing argument, let binding or do step, not the call itself. Rev 2 says "at the first demand" and names that point. | D1, E13, soundness 5 |
| 4 "Schema: none" is incorrect | **Accepted.** `docs/llmll-trust-report.schema.json` `$defs.TrustEntry` allows extra properties, but every additive precedent key (`assumed_facts`, `builtin_axioms`, `inherited_axioms`) is declared there. Rev 2 adds an `ffi_assumptions` property. `trust_report_version` does not change. | Affected surface |
| 5 cross-module inheritance; `LINE` before both binding lines | **Accepted.** E14 added. D9 states the cross-module mechanism (answer below). D1 emits a `LINE` pragma before the signature and before the definition. | D1, D9, E14 |
| 6 a function type nested inside `R` passes the side condition | **Accepted, refusal option taken.** D3 refuses a function type anywhere inside `R`. No reach is lost: no export in the reach table returns a structure that contains a function. | D3, E11b |
| 7 rows | **Accepted.** SAFE-HASKELL-CLAIM-1 covers the Docker, `seccomp-bpf` and Safe claims. FFI-CONTRACT-1 is in G1. FN-PARAM-PAREN-1 is a new G3 PLAN row, ordered before FFI-TIER1-1. | Rows |

**The open question from the second review, answered.** An importer's trust entry does inherit `ffi_assumptions` from an imported `def-shell`. The rows travel through `ModuleEnv.meStatements`, not through a sidecar. See D9.

## Restatement

LLMLL.md §7 calls Tier 1 FFI (`haskell.*` imports) "zero developer action", but no Hackage export can be reached from a program today. The interface form passes `check` and fails `build`, because nothing defines the interface name in the generated Haskell.

This proposal generates one forced, typed binding for each interface entry. It moves every measured failure except two into `check`. The two that stay with GHC at build are export existence and type agreement, and the `LINE` pragma reports both at the `.llmll` line. The trust report discloses each Hackage dependence on the entries that rest on it.

**Reference class.** Liquid Haskell, F\* and Dafny treat a foreign call as an assumed boundary with a declared type. Dafny's `audit` and Lean's `#print axioms` list that assumption for each declaration. D9 follows that disclosure pattern.

## Context located

**Measured on llmll 0.30.6** (Rev 0 probes):

| Test | Program | `check` | `build` / run |
|---|---|---|---|
| f1 | `haskell.filepath` interface `take-extension : string -> string` | OK | `Variable not in scope: take_extension` |
| sim-ok | f1's generated code plus a hand-added binding `take_extension :: String -> String` = `System.FilePath.takeExtension` | — | builds, prints `.gz` |
| sim-bad | the same binding declared `String -> Integer` | — | GHC `Couldn't match type ‘[Char]’ with ‘Integer’` |
| sim-bad + `LINE` pragma | as above | — | the same error at `f1.llmll:3:18` |
| f2 | interface entry named `string-length` | OK; the builtin is silently replaced | GHC type error |
| f3 | `remove-file : string -> Command` (`haskell.directory`) | OK | `Variable not in scope: remove_file` |
| f4 | a `def` calls `take-extension` | strict-core error naming `llmll verify` | — |
| f5 | `haskell.optparse-applicative` | OK | parse error on the import line |
| f6 | an interface entry and a `def-shell` with the same name | OK | duplicate definition once bindings exist |
| f7 | an interface type that names a user type | OK | no Hackage export can return it |
| f8 | an interface name passed to `list-map` | OK | — |
| fmain2 | two modules declare the same entry | OK | duplicate definition in the one `Lib.hs` |

**Measured on llmll 0.30.6** (second review): `(def-shell apply-pred [f: (fn [string] -> bool) s: string] -> bool (f s))` passes `check`. Its signature is generated as `apply_pred :: String -> Bool -> String -> Bool`, and `build` fails. This is FN-PARAM-PAREN-1.

Code:
- `compiler/src/LLMLL/CodegenHs.hs`:
  - `hackageModuleMap` holds nine packages, and `hackageImportLine` emits a qualified import (v0.30.6).
  - `hackagePkgNames` has dead `warp` and `wai` cases.
  - `toHsType`: `int` is `Integer`, `bytes` is `[Word8]`, `Command` is `IO ()`, `Result[T,E]` is `Either E T`. `TFn` with parameters adds no parentheses.
  - `runtimePreamble` states the EVAL-STRICT-1 invariant and defines `llmll_uW`, `llmll_uL`, `llmll_uS`, `llmll_uE` and `llmll_full`; `llmll_uP` is defined further down.
  - `esForceArgs` forces each non-atomic argument to WHNF. `esForceResult` wraps a builtin call in `llmll_full`, looking the forcer up in `esResultForcers` by name.
  - `llmll_response_slot` uses `NOINLINE` and `unsafePerformIO`.
- `compiler/src/LLMLL/TrustReport.hs`: `markBuiltinAxioms` and `markInheritedAxioms`. The second walks `teDeps` inside one report; imported callees reach it through a map that `compiler/app/Main.hs` builds from the module cache (`recordedAxiomMap`).
- `compiler/src/LLMLL/Syntax.hs` `ModuleEnv`: carries `meStatements` (the parsed statements) and `meBuiltinAxioms` (read from the sidecar).
- `docs/llmll-trust-report.schema.json` `$defs.TrustEntry`: `additionalProperties: true`; additive keys are still declared as properties.
- `Dockerfile`: builds the toolchain image, whose entry point is `llmll`. It runs no generated program in a container and has no seccomp profile.
- LLMLL.md §7 (sandbox sentence) and §10 pipeline step 4: claim Docker, `seccomp-bpf` and `{-# LANGUAGE Safe #-}`.
- No earlier design record or INDEX entry covers FFI.

## Design proposal

### D1. One forced binding per interface entry
For `(import haskell.P (interface [[n T] …]))`, with `T = A1 -> … -> Ak -> R`, codegen writes into `Lib.hs`:

```haskell
{-# LINE <import line> "<file>.llmll" #-}
<hs n> :: <toHsType T>
{-# LINE <import line> "<file>.llmll" #-}
<hs n> a1 … ak = llmll_full (<forcerFor R>) (<Module P>.<camel n> a1 … ak)
{-# LINE <next generated line> "Lib.hs" #-}
```

- **Eta-expansion to all k arguments.** The forcer applies to the result `R`. A zero-argument entry forces its constant.
- **Two `LINE` pragmas.** A pragma sets the number of the line after it. One before each binding line makes GHC attribute both lines to the import line. The last pragma returns attribution to `Lib.hs`.
- **`forcerFor :: Type -> Text`** is a new type-directed generator over D3's result types:

  | `R` | Forcer |
  |---|---|
  | `int`, `float`, `bool`, `unit` | `llmll_uW` |
  | `string`, `bytes[n]` | `llmll_uS` |
  | `list[T]` | `llmll_uL (forcerFor T)` |
  | `map[K,V]` | `llmll_uM (forcerFor K) (forcerFor V)` (new) |
  | pair `(A, B)` | `llmll_uP2 (forcerFor A) (forcerFor B)` (new) |
  | `Result[T,E]` | `llmll_uEi (forcerFor E) (forcerFor T)` (new) |

- **The three new runtime combinators** (illustrative):
  - ``llmll_uM rk rv m = Map.foldrWithKey (\k v acc -> rk k `seq` rv v `seq` acc) () m``. `Data.Map.Strict` forces each value to WHNF only, so a nested structure inside a value still needs the walk.
  - ``llmll_uP2 ra rb (a, b) = ra a `seq` rb b``.
  - `llmll_uEi re _ (Left e) = re e`; `llmll_uEi _ rt (Right t) = rt t`. The existing `llmll_uE` fixes the error type to `String` and cannot serve.
- The existing `esResultForcers` table stays as it is. `forcerFor` may later replace it; that is not part of this row.
- **When a failure appears.** `llmll_full` forces the whole result when the binding's result is first demanded. Under the EVAL-STRICT-1 invariant, that demand happens at the nearest enclosing argument, let binding or do step. A bottom inside a library result therefore appears there, not later inside a traversal at an unrelated site.
- `<hs n>`, the RESERVED-NAME-1 rename and the qualified import are unchanged from Rev 0.

### D2. Name rule
`camel n` maps `take-extension` to `takeExtension`. A name that contains `?`, `!`, `'` or `.` is `ffi-name-unmappable`.

### D3. Types an interface may use
Allowed: `int`, `float`, `string`, `bool`, `unit`, `bytes[n]`, `list[T]`, `map[K,V]`, pairs, `Result[T,E]` over these, and, as parameters, `fn` types over these. Refused with `ffi-type-unsupported`: user types, type variables, `Promise`. `Command` is refused by D4.

**Side condition on the result.** After eta-expansion, `R` must contain no function type anywhere. That covers a function result, `list[fn …]`, a pair with a function component and a `Result` over a function. A forcer can evaluate a function only to its outermost form, so the forcing guarantee in D1 would not hold. A curried result is written as more parameters instead.

**Function-typed parameters need FN-PARAM-PAREN-1.** `toHsType` does not parenthesise a function type in parameter position today. FFI-TIER1-1 ships after FN-PARAM-PAREN-1. If the order cannot hold, the engineer refuses function-typed parameters with `ffi-type-unsupported` until it does.

**What GHC checks.** The declared type is closed. GHC checks that it is an **instance** of the export's type, which is often polymorphic and constrained. `Data.Map.Strict.insert :: Ord k => k -> a -> Map k a -> Map k a` accepts a declaration at `int` and `string`. Instance resolution then fixes behaviour at the declared types. The check is decidable and sound. It is not an equality test.

**Stated limit.** `int` is `Integer`. `Int`-, `Text`-, `ByteString`- and `Maybe`-typed exports are unreachable. A conversion layer is FFI-CONV-1. Its `Integer` to `Int` narrowing is a QF-LIA range precondition, which needs FFI-CONTRACT-1.

### D4. No effects through Tier 1
`Command` or `Promise` anywhere in `T` is `ffi-effect-refused`.

### D5. Closed package set
Only the nine `hackageModuleMap` keys are accepted; any other is `ffi-unknown-package`. Remove the dead `warp` and `wai` cases from `hackagePkgNames`.

### D6. Interface names are top-level names
- A builtin name is `builtin-redefinition`.
- A name that another top-level definition in the build uses is `duplicate-definition`.
- Interface names are not exported.
- Identical entries in two modules give one binding. The same name at different types is `duplicate-definition`.

### D7. The two build-time gaps
`check` cannot run GHC (BUILD-NOSTACK-1). Two questions stay with GHC at build:

1. **Export existence.** `[take-extention (fn [p: string] -> string)]` passes `check` and fails `build` with GHC's `Not in scope` error.
2. **Type agreement.** The declared type must be an instance of the export's type (sim-bad, measured).

Both fail closed. With the D1 pragmas, GHC reports both at the `.llmll` import line. The line is correct. The column counts characters in the generated text, not in the source; §7 states this. FFI-SIG-TABLE-1 moves both gaps into `check`.

### D8. Spec text and reach
§7 changes to say "declared interface", the D2–D7 rules and the two build-time gaps. It adds this reach table, derived from the D3 type rule against each module's export types. It is not measured export by export.

| Package | Module | Reach | Why |
|---|---|---|---|
| filepath | `System.FilePath` | most named functions: `takeExtension`, `takeFileName`, `takeDirectory`, `replaceExtension`, `splitPath`, `joinPath`, `normalise`, `isAbsolute` | `FilePath` is `String`; symbolic operators fail D2 |
| containers | `Data.Map.Strict` | part: `insert`, `delete`, `member`, `union`, `fromList`, `toList`, `keys`, `elems`, `findWithDefault`; `filter` after FN-PARAM-PAREN-1 | `size` is `Int`; `lookup` returns `Maybe`; `!` fails D2 |
| aeson | `Data.Aeson` | none | `Value` and lazy `ByteString` have no LLMLL type |
| text | `Data.Text` | none | every export uses `Text` |
| bytestring | `Data.ByteString` | none | `bytes` lowers to `[Word8]` |
| vector | `Data.Vector` | none | `Vector` has no LLMLL type |
| time | `Data.Time` | none | no LLMLL counterpart; the clock is IO |
| directory | `System.Directory` | none | every export is IO (D4) |
| process | `System.Process` | none | every export is IO (D4) |

§13.11a: remove the `haskell.warp`, `haskell.unix` and `haskell.optparse-applicative` examples. Replace the `haskell.aeson` example with a pointer to the native `Json` operations (§13.13). Add the working `haskell.filepath` example.

### D9. Trust-report disclosure
- Each trust-report entry gains an additive key **`ffi_assumptions`**: a list of `{ "origin", "package", "export" }` rows. The key is omitted when the list is empty, as `assumed_facts` is.
- `origin` is the entry itself for a direct call. For an inherited row it is the callee through which the assumption arrives.
- **The trust level does not change.** The evidence lattice and `evidenceMeet` stay as they are. TRUST-LEVEL-FLOOR-1 floors keep their meaning.
- **No `trust_report_version` change.** The schema gains the property (Affected surface).
- Meaning of a row: "this verdict assumes `<package>.<export>` is total and has no hidden effects at the declared type."

**Within one module**, a new `markFfiAssumptions` walks `teDeps` as `markInheritedAxioms` does.

**Across modules**, the rows come from source, not from a sidecar. Which interface names a function calls is a syntactic fact. Every imported module's parsed statements are already in the module cache as `ModuleEnv.meStatements`. The verify path builds one map from each imported function's bare and qualified name to its transitive FFI rows, computed over each module's own statements and its own imports. The map has the same key shape as `recordedAxiomMap`. `markFfiAssumptions` reads a callee's rows from that map when the callee is not an entry in the current report.

This differs from builtin axioms on purpose. Axiom sets depend on the emitter, so they come from the `.verified.json` sidecar and can be unrecorded. FFI rows have no unrecorded state, because the source is always present. No sidecar key and no `Nothing` row are needed.

## Edge cases and degenerate inputs

| # | Input | Expected | Channel |
|---|---|---|---|
| E1 (fires) | f3: `[remove-file (fn [p: string] -> Command)]` | `ffi-effect-refused` | type (D4) |
| E2 (fires) | f2: entry `string-length` | `builtin-redefinition` | type (D6) |
| E3 (fires) | f5: `haskell.optparse-applicative` | `ffi-unknown-package` | type (D5) |
| E4 (fires) | f7: result type `Opts` | `ffi-type-unsupported` | type (D3) |
| E5 (fires) | sim-bad: `-> int` for a `String` export | GHC error at the `.llmll` import line | build (D7 gap 2) |
| E5b (fires) | `take-extention` | GHC `Not in scope` at the `.llmll` import line | build (D7 gap 1) |
| E6 | f8: entry used as a value | the binding is an ordinary function | — |
| E7 | entry `show` | `show_u1 = Module.show` | codegen |
| E8 | fmain2: the same entry in two modules | one binding; differing types are `duplicate-definition` | type (D6) |
| E9 | f4: a `def` calls an entry | strict-core error kept; the message names the Hackage boundary | type |
| E10 | a partial export, such as a `head`-like function on `[]` | a crash at the first demand of the binding's result; outside the guarantees | trust (D9 row) |
| E11 (fires) | `[f (fn [x: int] -> (fn [y: int] -> int))]` | `ffi-type-unsupported`, the result is a function; write `[f (fn [x: int y: int] -> int)]` | type (D3) |
| E11b (fires) | `[f (fn [x: int] -> list[(fn [y: int] -> int)])]` | `ffi-type-unsupported`, a function inside the result | type (D3) |
| E12 | `def-shell` `main-step` calls `take-extension`; `run` calls `main-step` | both entries carry a row; the one on `run` has `origin: main-step` | trust (D9) |
| E13 | an export returns a list with a bottom in its tail | the crash appears at the enclosing argument, let binding or do step | runtime (D1) |
| E14 | module `paths` has `def-shell` `ext-of` calling `take-extension`; the entry module imports `paths` and its `run` calls `paths.ext-of` | `run` carries a row with `origin: paths.ext-of`, `package: filepath`, `export: takeExtension` | trust (D9, cross-module) |
| E15 (fires) | `[keep (fn [p: (fn [s: string] -> bool) xs: list[string]] -> list[string])]` before FN-PARAM-PAREN-1 | refused with `ffi-type-unsupported` if FFI-TIER1-1 ships first; builds after FN-PARAM-PAREN-1 | type (D3) |

## Verification mapping
- **No new proof obligations.** An interface function has no body and no contract. Nothing goes to QF-LIA or to Lean.
- **Type agreement** is GHC instance checking at build. It is not an SMT obligation.
- **Strict verified core:** a `def` calling an interface function stays inadmissible (f4). Admitting an FFI function as an uninterpreted symbol under a disclosed totality assumption is FFI-UNINTERP-1.
- **Trust:** callers are `def-shell`, so `asserted` or `tested`. D9 discloses the assumption; the level is unchanged.
- **Later narrowing precondition** (FFI-CONV-1 with FFI-CONTRACT-1): `(pre (and (>= x -9223372036854775808) (<= x 9223372036854775807)))`, QF-LIA (§5.3.3).

## Soundness argument
1. The Haskell function is used at exactly the type the type checker assumed. D3 makes that type closed, and GHC checks that it instantiates the export's type.
2. It performs no effect visible in its type (D4).
3. It cannot collide with another name in the build (D6 and the qualified import).
4. Every refusal happens in `check` except two: export existence and type agreement. GHC decides both at build, and both fail closed.
5. A failure inside a library result appears at the first demand of the binding's result, which EVAL-STRICT-1 places at the enclosing argument, let binding or do step (D1). D3's result rule keeps every result fully forceable.
6. Every verdict that rests on a Hackage function says so in the trust report, across module boundaries (D9).

Still assumed, and stated: the library is total and has no hidden effects (`unsafePerformIO`), and GHC is correct. The builtins, which are also Haskell, have the same status.

## Affected surface
- `compiler/src/LLMLL/TypeCheck.hs` `checkStatement (SImport)`: the four new errors; the D3 result rule; the builtin, duplicate and deduplication checks.
- `compiler/src/LLMLL/CodegenHs.hs`: forced, eta-expanded bindings; `forcerFor`; `llmll_uM`, `llmll_uP2` and `llmll_uEi` in the runtime preamble; the two `LINE` pragmas and the reset; interface names in `renameStatements`; the dead `warp` and `wai` cases removed.
- `compiler/src/LLMLL/TrustReport.hs`: `markFfiAssumptions` and the `ffi_assumptions` emit.
- `compiler/app/Main.hs`: the cross-module FFI map, built from the module cache next to `recordedAxiomMap`, passed on every trust-report path.
- `compiler/src/LLMLL/Diagnostic.hs`: four constructors; the E9 message.
- `docs/llmll-trust-report.schema.json`: an additive `ffi_assumptions` property under `$defs.TrustEntry`; `trust_report_version` does not change.
- Tests: build-and-run for sim-ok and for one export from each reachable row; unit tests for E1–E4, E8, E11, E11b and E15; build tests for E5 and E5b asserting the `.llmll:` location; trust-report tests for E12 and E14; a build-and-run test for E13.
- Docs (doc-lead): §7 and §13.11a per D8; the row citation from §13.10 to §13.11a.
- **Addition:** this is a new FFI tier surface. The soundness argument above is its design record.

## Risks
1. **Reach is small.** Scope. Two of nine packages give any reach (D8). FFI-CONV-1 and FFI-SIG-TABLE-1 decide whether Tier 1 is useful. Complicates; does not block.
2. **Forcing cost.** Performance. A large `Map` result is traversed once per call. This is the same trade as EVAL-STRICT-1. Only matters at scale.
3. **The reach table is derived, not measured.** Spec drift. The engineer's build test exercises one export from each reachable row. Complicates.
4. **`aeson`, `text` and `vector` are outside `compiler/generated-deps.txt`.** An import of one of them adds a package the CI cache key does not cover. Only matters for CI time.
5. **Order with FN-PARAM-PAREN-1.** Scope. If FFI-TIER1-1 ships first, function-typed parameters are refused (E15). Complicates only.

## Findings outside the scope
- **The §7 sandbox sentence** claims Docker, `seccomp-bpf` and `{-# LANGUAGE Safe #-}`, and §10 pipeline step 4 repeats the Safe claim. All three are false today. The `Dockerfile` builds the toolchain image only and runs no generated program. No tracked file has a seccomp profile. Generated code uses `unsafePerformIO` and `NOINLINE`, so `Safe` cannot compile it. The spec must move. Row SAFE-HASKELL-CLAIM-1.
- **FN-PARAM-PAREN-1.** A function-typed parameter of any `def` or `def-shell` loses its parentheses in `toHsType`. That program passes `check` and fails `build`. The only tracked program with that shape is `compiler/test/fixtures/minmax-frag/shadow-param.llmll`, and no build test covers it.
- The FFI-TIER1-1 roadmap row cites §13.10; the examples are in §13.11a.

## Proposed new roadmap rows (doc-lead)

In dependency order:

1. **FN-PARAM-PAREN-1** (G3, **PLAN**): `toHsType` parenthesises a function type in parameter position. Acceptance: the `apply-pred` program builds and runs, under a new build test. Precedes FFI-TIER1-1.
2. **FFI-TIER1-1** (G3): the existing row. Change its citation to §13.11a, and its marker from DECIDE to **PLAN**, citing this record.
3. **SAFE-HASKELL-CLAIM-1** (**DOC**): correct the Docker, `seccomp-bpf` and Safe claims in LLMLL.md §7 and §10 step 4.
4. **FFI-SIG-TABLE-1** (G3, **DECIDE**): a pinned table of the nine modules' export types for resolver `lts-22.43`, read by `check`, so D7's two gaps become `check` errors.
5. **FFI-CONTRACT-1** (G1, **DECIDE**): `pre` and `post` on interface entries, assumed at call sites and listed in `ffi_assumptions`.
6. **FFI-CONV-1** (G7, **DECIDE**): Int and Integer, Text and String, ByteString and bytes, and Maybe conversions at the Tier 1 boundary. Depends on FFI-CONTRACT-1.
7. **FFI-UNINTERP-1** (G1, **DECIDE**): admit a pure FFI function into the strict core as an uninterpreted symbol under a disclosed totality assumption.

## Appendix — Professor review log

### Review 1, of Rev 0 (2026-10-19)
- **(a) A separate `ffi` trust level: no.** A dependence on Hackage code is an assumption, not a weaker kind of evidence. A new level would change `evidenceMeet` and the TRUST-LEVEL-FLOOR-1 floors. Disclose it per entry, closed over callers, beside TRUST-AXIOM. Precedents: Lean's `#print axioms`, Dafny's `audit` of `{:extern}`, F\*'s `assume val`.
- **(b) Ship D3 before the conversion layer.** The layer only widens reach and changes no accepted program. The later narrowing is a QF-LIA `pre` clause.
- **Hazards:** D7 omitted export existence; "equality" should be "instantiation"; lazy results move the failure site; disclosure was missing from the trust surface; strict core rejects pure exports (kept, later addition); the Safe claim appears twice; reach is narrower than stated; the `LINE` pragma needs a reset.
- **Recommended follow-up:** a pinned signature table checked in `check`.
- **Language-team response:** all accepted (Rev 1). Two objections: no version change for an additive key, and no `deepseq`.

### Review 2, of Rev 1 (2026-10-20)
- **Verdict:** settle with the listed edits; no Rev 2 review needed. Both language-team objections stand.
- **Hazards:**
  1. The forcers are a name-keyed table, and three D3 types have no correct combinator.
  2. A function-typed parameter loses its parentheses in `toHsType`; this is an earlier defect (FN-PARAM-PAREN-1).
  3. "At the call" is stronger than the mechanism.
  4. The schema needs an `ffi_assumptions` property even with no version change.
  5. Cross-module inheritance was unstated, and the `LINE` pragma needs a second line.
  6. The sandbox sentence's Docker claim is also false.
  7. A function type nested inside `R` passed the side condition.
- **Reach spot-check:** the `filepath` and `containers` rows are correct, except that `filter` is blocked by hazard 2.
- **Rows:** FFI-CONTRACT-1 belongs in G1; add FN-PARAM-PAREN-1 before FFI-TIER1-1.
- **Open question:** whether an importer inherits `ffi_assumptions`, and through which structure. Answered in D9: yes, through `ModuleEnv.meStatements`.
- **Language-team response:** all seven edits accepted (Rev 2).
