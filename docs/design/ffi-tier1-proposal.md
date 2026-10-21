---
title: FFI-TIER1-1 — making Tier 1 Hackage imports work
status: Rev 3, SETTLED 2026-10-20
rows: FFI-TIER1-1 (G3), FFI-CONV-1 (G3, lossless boundary conversions); FN-PARAM-PAREN-1 (G3) shipped in v0.30.8
review: two professor passes (Rev 0 and Rev 1, 2026-10-19 and 2026-10-20), folded below as the Appendix; Rev 3 reviewed by a short third pass, folded below; no standalone review file
---

# FFI-TIER1-1: making Tier 1 Hackage imports work

**Status: Rev 3, SETTLED 2026-10-20.** Rev 0 was the language-team draft of 2026-10-19. Rev 1 answered the first professor review. Rev 2 applied the seven edits of the second review and settled on 2026-10-20. The user reopened the record the same day to add lossless boundary conversions (D10) and one D3 amendment. Rev 3 settled after a third, short professor review, whose five edits it applies (see the appendix).

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

### Rev 2 → Rev 3 (reopened by the user, 2026-10-20)

Source: the language-team pass that split FFI-CONV-1 (scratchpad draft of 2026-10-20, measured on llmll 0.30.8 with ghci in the `lts-22.43` snapshot).

| Change | Why | Where |
|---|---|---|
| New **D10, boundary types** `hs-text`, `hs-maybe[T]`, `hs-int`, valid only inside a `haskell.*` interface entry | GHC cannot infer the Haskell type at a polymorphic export. A type-class conversion failed on `Map.member (fromL k) (fromL m)` with `Ambiguous type variable ‘k0’`. The entry must state the Haskell side. | D10 |
| D1 binding gains `convIn` on each argument and `convOut` on the result | Converters are generated by type, like `forcerFor`. The forcer runs after `convOut`, on an LLMLL-typed value, so the forcer table does not change. An entry with no boundary type generates the Rev 2 text. | D1, D10 |
| Direction rule: `hs-int` only where a value flows from Haskell to LLMLL; no boundary type inside a function-typed parameter in this revision | `int` to `Int` wraps outside ±2^63, so it needs a precondition. A callback reverses direction. Refusing boundary types in callbacks avoids a variance walk and costs no export in the reach table. | D10 |
| `ByteString` deferred | `bytes[n]` always has a fixed length, so a `ByteString` result of unknown length has no total map into it. | D10, rows |
| **D3 amendment:** `bytes[n]` is refused in a result position | The verifier treats `bytes[n]` as a length fact (`bytesLenRetPost`, `bytesLenParamPre`, LLMLL.md §5.3.3). A Hackage result is not checked against `n`. | D3, E16 |
| §7 states that `string` to `hs-text` replaces a lone surrogate with U+FFFD | GHC decodes argv and directory listings with the file-system encoding, which can produce lone surrogates. `pack` is total but not injective. | D8, D10, E21 |
| D8 reach table replaced | `text` goes from none to most of the module. `containers` gains `lookup`, `lookupMin`, `size`, `filter`, `insertWith`. `time`, `vector`, `aeson` stay at none. | D8 |
| FN-PARAM-PAREN-1 shipped in v0.30.8 | Function-typed parameters now print with parentheses. E15 is resolved; `filter` is no longer blocked. | D3, E15 |
| FFI-NARROW-1 dependency corrected | A range `pre` can be derived from the boundary type, as `bytesLenParamPre` derives a length. It needs a call-site discharge from a `def-shell` caller (SHELL-CALL-PRE-1) or a run-time check that answers through `Result`. It does not need FFI-CONTRACT-1. | Verification mapping, rows |
| New row FFI-OPAQUE-1 | `Day`, `Vector`, `Value` and lazy `ByteString` have no LLMLL type. Sealed handle types are a separate addition. | Rows |

### Rev 3 edits after the third professor review (2026-10-20)

| Change | Why | Where |
|---|---|---|
| Every non-`id` converter carries an explicit Haskell type, for example `(toInteger :: Int -> Integer)` | `toInteger :: Integral a => a -> Integer` lets GHC pick another integral type, or default, at a polymorphic export. The declared `Int` was then checked by nothing. | D10, soundness item 1 |
| Partial exports are marked in the reach table; `Data.Text.splitOn` and `Data.Text.replace` are named in §7 | Both call `error` on an empty delimiter or needle. An agent passes a computed separator that can be empty. | D8, E24, FFI-CONTRACT-1 example |
| `hs-text` as a `map` key in an argument position is refused | `pack` merges two keys that differ only by a lone surrogate. `Data.Map` keeps one value and drops the other with no signal. A §7 sentence does not let an agent act. In result position the key goes through `unpack`, which is injective. | D10, E21 |
| One shared `schemaVersion` change with AST-TYPE-ALIAS-1 | Both rows add type arms to `docs/llmll-ast.schema.json`. Two changes in one release cycle give no information. | Affected surface |
| Each boundary-type schema arm states, in its `description`, that the type is valid only inside an interface entry | A plain `kind` arm accepts the type anywhere. `ParserJSON` refuses it outside an entry (E20). The description records the difference. | D10, Affected surface |

## Restatement

LLMLL.md §7 calls Tier 1 FFI (`haskell.*` imports) "zero developer action", but no Hackage export can be reached from a program today. The interface form passes `check` and fails `build`, because nothing defines the interface name in the generated Haskell.

This proposal generates one forced, typed binding for each interface entry. It moves every measured failure except two into `check`. The two that stay with GHC at build are export existence and type agreement, and the `LINE` pragma reports both at the `.llmll` line. The trust report discloses each Hackage dependence on the entries that rest on it.

Rev 3 adds lossless conversions at the boundary for `Text`, `Maybe` and `Int` results. These need no precondition, so they ship with the binding. Only `int` to `Int` narrowing waits (FFI-NARROW-1).

**Reference class.** Liquid Haskell, F\* and Dafny treat a foreign call as an assumed boundary with a declared type. Dafny's `{:extern}` and F\*'s `assume val` state the foreign type at the boundary; neither infers it. Dafny's `audit` and Lean's `#print axioms` list the assumption for each declaration. D9 follows that disclosure pattern, and D10 follows the explicit-boundary-type pattern.

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

**Measured on llmll 0.30.6** (second review): `(def-shell apply-pred [f: (fn [string] -> bool) s: string] -> bool (f s))` passed `check`, generated `apply_pred :: String -> Bool -> String -> Bool`, and failed `build`. FN-PARAM-PAREN-1 fixed this in v0.30.8.

**Measured on llmll 0.30.8, GHC 9.6.6, resolver `lts-22.43`** (Rev 3, `ghci :t` in the compiler's snapshot):

| Export | Type |
|---|---|
| `Data.Text.toUpper`, `strip` | `Text -> Text` |
| `Data.Text.splitOn` | `Text -> Text -> [Text]` |
| `Data.Text.replace` | `Text -> Text -> Text -> Text` |
| `Data.Text.length` | `Text -> Int` |
| `Data.Text.isInfixOf` | `Text -> Text -> Bool` |
| `Data.Text.justifyLeft` | `Int -> Char -> Text -> Text` |
| `Data.Map.Strict.lookup` | `Ord k => k -> Map k a -> Maybe a` |
| `Data.Map.Strict.size` | `Map k a -> Int` |
| `Data.Map.Strict.lookupMin` | `Map k a -> Maybe (k, a)` |
| `Data.ByteString.length` | `ByteString -> Int` |
| `Data.Time.fromGregorian` | `Year -> MonthOfYear -> DayOfMonth -> Day` (`Year = Integer`, `MonthOfYear = Int`) |
| `Data.Time.diffDays` | `Day -> Day -> Integer` |
| `Data.Aeson.encode` | `ToJSON a => a -> Data.ByteString.Lazy.ByteString` |
| `Data.Vector.fromList` | `[a] -> Vector a` |

A type-class conversion, where GHC infers the Haskell type, works for a monomorphic export (`Data.Text.strip`) and when the result type fixes the variable (`Map.insert`). It fails for `Map.member (fromL k) (fromL m)` with `Ambiguous type variable ‘k0’ … (Conv k0 String)`. So the generator cannot infer the Haskell type at a position.

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

- `compiler/src/LLMLL/Syntax.hs` `TBytes Int`: `bytes` is always fixed-length. LLMLL has no unsized byte type.
- `LLMLL.md` §3: `unit` is a primitive type. §13: optional results use `Result[a, string]` (`list-head`). LLMLL has no `Maybe` and no character type.

## Design proposal

### D1. One forced binding per interface entry
For `(import haskell.P (interface [[n T] …]))`, with `T = A1 -> … -> Ak -> R`, codegen writes into `Lib.hs`:

```haskell
{-# LINE <import line> "<file>.llmll" #-}
<hs n> :: <toHsType (lower T)>
{-# LINE <import line> "<file>.llmll" #-}
<hs n> a1 … ak = llmll_full (<forcerFor (lower R)>) (<convOut R> (<Module P>.<camel n> (<convIn A1> a1) … (<convIn Ak> ak)))
{-# LINE <next generated line> "Lib.hs" #-}
```

- **`lower`** replaces each D10 boundary type with the LLMLL type the program sees. The signature and the forcer use the lowered type. `convIn` and `convOut` read the unlowered type.
- **Eta-expansion to all k arguments.** The forcer applies to the result `R`. A zero-argument entry forces its constant.
- **Two `LINE` pragmas.** A pragma sets the number of the line after it. One before each binding line makes GHC attribute both lines to the import line. The last pragma returns attribution to `Lib.hs`.
- **`forcerFor :: Type -> Text`** is a new type-directed generator over D3's result types:

  | `R` (lowered) | Forcer |
  |---|---|
  | `int`, `float`, `bool`, `unit` | `llmll_uW` |
  | `string` | `llmll_uS` |
  | `list[T]` | `llmll_uL (forcerFor T)` |
  | `map[K,V]` | `llmll_uM (forcerFor K) (forcerFor V)` (new) |
  | pair `(A, B)` | `llmll_uP2 (forcerFor A) (forcerFor B)` (new) |
  | `Result[T,E]` | `llmll_uEi (forcerFor E) (forcerFor T)` (new) |

- **The three new runtime combinators** (illustrative):
  - ``llmll_uM rk rv m = Map.foldrWithKey (\k v acc -> rk k `seq` rv v `seq` acc) () m``. `Data.Map.Strict` forces each value to WHNF only, so a nested structure inside a value still needs the walk.
  - ``llmll_uP2 ra rb (a, b) = ra a `seq` rb b``.
  - `llmll_uEi re _ (Left e) = re e`; `llmll_uEi _ rt (Right t) = rt t`. The existing `llmll_uE` fixes the error type to `String` and cannot serve.
- The existing `esResultForcers` table stays as it is. `forcerFor` may later replace it; that is not part of this row.
- **When a failure appears.** `llmll_full` forces the whole result when the binding's result is first demanded. Under the EVAL-STRICT-1 invariant, that demand happens at the nearest enclosing argument, let binding or do step. A bottom inside a library result therefore appears there, not later inside a traversal at an unrelated site. `convOut` runs inside `llmll_full`, so a bottom that a converter exposes appears at the same point.
- `<hs n>`, the RESERVED-NAME-1 rename and the qualified import are unchanged from Rev 0.
- **An entry with no boundary type** has `convIn` and `convOut` equal to `id` everywhere. Codegen emits nothing for an `id` converter, so the binding text is the Rev 2 text.

### D2. Name rule
`camel n` maps `take-extension` to `takeExtension`. A name that contains `?`, `!`, `'` or `.` is `ffi-name-unmappable`.

### D3. Types an interface may use
Allowed: `int`, `float`, `string`, `bool`, `unit`, `list[T]`, `map[K,V]`, pairs, `Result[T,E]` over these, the D10 boundary types where D10 allows them, and, as parameters, `bytes[n]` and `fn` types over these. Refused with `ffi-type-unsupported`: user types, type variables, `Promise`. `Command` is refused by D4.

**Side condition on the result.** After eta-expansion, `R` must contain no function type anywhere. That covers a function result, `list[fn …]`, a pair with a function component and a `Result` over a function. A forcer can evaluate a function only to its outermost form, so the forcing guarantee in D1 would not hold. A curried result is written as more parameters instead.

**Rev 3 amendment: no `bytes[n]` in a result.** A `bytes[n]` anywhere in `R` is `ffi-type-unsupported`. The Haskell side is `[Word8]` of any length, and nothing checks it against `n`. LLMLL treats `bytes[n]` as a length fact (`bytesLenRetPost`, `bytesLenParamPre`, LLMLL.md §5.3.3), so an unchecked length would give the verifier a false fact. Argument position stays allowed, because the LLMLL value carries its length. No export in the reach table returns bytes.

**Function-typed parameters.** FN-PARAM-PAREN-1 shipped in v0.30.8, so `toHsType` prints a function type in parameter position with parentheses. Function-typed parameters are allowed. A D10 boundary type inside a function-typed parameter is refused (D10).

**What GHC checks.** The declared type, after `lower` and conversion, is closed. GHC checks that the Haskell-side type is an **instance** of the export's type, which is often polymorphic and constrained. `Data.Map.Strict.insert :: Ord k => k -> a -> Map k a -> Map k a` accepts a declaration at `int` and `string`. Instance resolution then fixes behaviour at the declared types. The check is decidable and sound. It is not an equality test.

**Stated limit.** `int` is `Integer`, and `string` is `String`. An export that needs `Text`, `Maybe` or an `Int` result is reached through D10. An `Int` argument (narrowing) is FFI-NARROW-1. `ByteString` and `Char` stay unreachable. Opaque Haskell types (`Day`, `Vector`, `Value`) are FFI-OPAQUE-1.

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
§7 changes to say "declared interface", the D2–D7 and D10 rules and the two build-time gaps. It states the lone-surrogate rule of D10. It adds this reach table. Rows marked M were measured with `ghci :t` in the `lts-22.43` snapshot. The rest are derived from the type rule and are not measured export by export. Exports marked P are **partial**: they call `error` on some inputs that pass `check`.

| Package | Module | Reach | Still unreachable, and why |
|---|---|---|---|
| filepath | `System.FilePath` | most named functions: `takeExtension`, `takeFileName`, `takeDirectory`, `replaceExtension`, `splitPath`, `joinPath`, `normalise`, `isAbsolute` | symbolic operators fail D2 |
| containers | `Data.Map.Strict` | `insert`, `delete`, `member`, `union`, `fromList`, `toList`, `keys`, `elems`, `findWithDefault`, `filter`, `insertWith`; with D10, `lookup` and `lookupMin` (`hs-maybe`) and `size` (`hs-int`) (M) | callbacks that use a boundary type (D10 simplification); `!` fails D2 |
| text | `Data.Text` | with D10: `toUpper`, `toLower`, `strip`, `splitOn` (P), `replace` (P), `isInfixOf`, `isPrefixOf`, `words`, `lines`, `intercalate`, `length` (M) | `Char` arguments (`map`, `filter`, `cons`); `Int` arguments (`take`, `justifyLeft`) need FFI-NARROW-1 |
| bytestring | `Data.ByteString` | none | needs an unsized byte type (BYTES-READ-1) |
| time | `Data.Time` | none (M: `Day` is abstract) | FFI-OPAQUE-1 |
| aeson | `Data.Aeson` | none (M: lazy `ByteString`, `Value`, type classes) | FFI-OPAQUE-1; the native `Json` operations (§13.13) cover the common case |
| vector | `Data.Vector` | none (M: `Vector` is abstract) | FFI-OPAQUE-1 |
| directory | `System.Directory` | none | every export is IO (D4) |
| process | `System.Process` | none | every export is IO (D4) |

§7 names the two partial `text` exports. `Data.Text.splitOn` calls `error` when the delimiter is empty. `Data.Text.replace` calls `error` when the needle is empty. A failure appears at the first demand of the result (D1). The guard is the caller's, until FFI-CONTRACT-1 lets the entry carry it. The first FFI-CONTRACT-1 example is `[split-on (fn [sep: hs-text s: hs-text] -> list[hs-text])]` with `(pre (not (= sep "")))`.

§13.11a: remove the `haskell.warp`, `haskell.unix` and `haskell.optparse-applicative` examples. Replace the `haskell.aeson` example with a pointer to the native `Json` operations (§13.13). Add a working `haskell.filepath` example and a working `haskell.text` example that uses `hs-text`.

### D9. Trust-report disclosure
- Each trust-report entry gains an additive key **`ffi_assumptions`**: a list of `{ "origin", "package", "export" }` rows. The key is omitted when the list is empty, as `assumed_facts` is.
- `origin` is the entry itself for a direct call. For an inherited row it is the callee through which the assumption arrives.
- **The trust level does not change.** The evidence lattice and `evidenceMeet` stay as they are. TRUST-LEVEL-FLOOR-1 floors keep their meaning.
- **No `trust_report_version` change.** The schema gains the property (Affected surface).
- Meaning of a row: "this verdict assumes `<package>.<export>` is total and has no hidden effects at the declared type."

**Within one module**, a new `markFfiAssumptions` walks `teDeps` as `markInheritedAxioms` does.

**Across modules**, the rows come from source, not from a sidecar. Which interface names a function calls is a syntactic fact. Every imported module's parsed statements are already in the module cache as `ModuleEnv.meStatements`. The verify path builds one map from each imported function's bare and qualified name to its transitive FFI rows, computed over each module's own statements and its own imports. The map has the same key shape as `recordedAxiomMap`. `markFfiAssumptions` reads a callee's rows from that map when the callee is not an entry in the current report.

This differs from builtin axioms on purpose. Axiom sets depend on the emitter, so they come from the `.verified.json` sidecar and can be unrecorded. FFI rows have no unrecorded state, because the source is always present. No sidecar key and no `Nothing` row are needed.

**D9 addendum (2026-10-21, FFI-TRUST-OBLIG-1).** D9 names the trust report, but its rule is per verdict: every verdict that rests on a Hackage export says so wherever that verdict is reported. The obligation report's `trust_channel` is such a place. `oblig-0-spec.md` §4.3 defines it as a projection of the function's `TrustEntry` assumption fields, and it gives `assumptions: []` the meaning "assumes nothing". The channel therefore carries each `teFfiAssumptions` row as `{ "kind": "ffi-assumption", "origin", "package", "export" }`, rendered by `ffiAssumptionJson`, after the ground-fact rows. A row is the function's own when `origin` is the channel's function, and is inherited through `origin` otherwise. This is the same rule the text report uses for `≈ assumes` and `≈ inherits … via`. The obligation report's `schema_version` changes from 0.12.4 to 0.12.5. `trust_report_version` does not change, and the trust level does not change.

### D10. Boundary types (Rev 3)

**Surface.** Three type names are valid only inside a `haskell.*` interface entry. Anywhere else each one is `unknown type`.

| Boundary type | Haskell type | LLMLL type the program sees | Where it may appear |
|---|---|---|---|
| `hs-text` | `Data.Text.Text` (strict) | `string` | arguments and result |
| `hs-maybe[T]` | `Maybe T'` | `Result[T, unit]` | arguments and result |
| `hs-int` | `Int` | `int` | result only |

`T'` is the Haskell type of `T`. Boundary types nest inside `list`, `map`, pairs, `Result` and `hs-maybe`. `ByteString` has no boundary type in this revision.

```lisp
(import haskell.text
  (interface
    [[split-on (fn [sep: hs-text s: hs-text] -> list[hs-text])]
     [text-length (fn [s: hs-text] -> hs-int)]]))
(import haskell.containers
  (interface [[lookup (fn [k: string m: map[string, int]] -> hs-maybe[int])]]))
```

Callers see `split-on : (fn [string string] -> list[string])`, `text-length : (fn [string] -> int)` and `lookup : (fn [string map[string, int]] -> Result[int, unit])`.

**JSON-AST.** Each boundary type is a type node: `{"kind": "hs-text"}`, `{"kind": "hs-int"}` and `{"kind": "hs-maybe", "inner": <type>}`. `ParserJSON` accepts them only inside an interface entry. The schema gains three additive type arms. Each arm's `description` states that the type is valid only inside a `haskell.*` interface entry; the schema accepts it anywhere, and `ParserJSON` refuses it elsewhere (E20). The arms share one `schemaVersion` change with AST-TYPE-ALIAS-1, whichever row ships first.

**Converters.** `convIn` maps an LLMLL value to the Haskell type. `convOut` maps a Haskell result back. Both are generated by type. **Every converter that is not `id` is emitted with an explicit Haskell type**, for example `(Data.Text.pack :: String -> Data.Text.Text)` and `(toInteger :: Int -> Integer)`. The annotation fixes the Haskell type at the export, so GHC checks the declared boundary type against the export's type. An `id` converter emits nothing; the lowered signature fixes its type.

| Type | `convIn` (LLMLL → Haskell) | `convOut` (Haskell → LLMLL) |
|---|---|---|
| `hs-text` | `Data.Text.pack` | `Data.Text.unpack` |
| `hs-maybe[T]` | `either (const Nothing) (Just . convIn T)` | `maybe (Left ()) (Right . convOut T)` |
| `hs-int` | refused | `(toInteger :: Int -> Integer)` |
| `list[T]` | `map (convIn T)` | `map (convOut T)` |
| `map[K,V]` | rebuild with converted keys and values; **refused** when `K` contains `hs-text` | rebuild with converted keys and values |
| pair, `Result` | componentwise | componentwise |
| any other D3 type | `id` (emits nothing) | `id` (emits nothing) |

**Which conversions need no precondition.**

| Conversion | Total | Injective | Precondition |
|---|---|---|---|
| `Text` → `string` | yes | yes | none |
| `string` → `Text` | yes | **no**: a lone surrogate (U+D800–U+DFFF) becomes U+FFFD | none |
| `Maybe T` ↔ `Result[T, unit]` | yes | yes | none |
| `Int` → `int` (`toInteger`) | yes | yes | none |
| `int` → `Int` | **no**: values outside ±2^63 wrap | — | **needed**; FFI-NARROW-1 |

**Direction rule.** Variance decides direction, not position. A value flows from Haskell to LLMLL in the entry's result and in a callback's own parameters. A callback's result flows from LLMLL to Haskell. `hs-int` is allowed only where a value flows from Haskell to LLMLL. In this revision a boundary type anywhere inside a function-typed parameter is `ffi-type-unsupported`. That removes the variance walk from the first implementation, and it costs no export in the reach table. `hs-int` in an argument is `ffi-type-unsupported` with the reason "narrowing int to Int needs FFI-NARROW-1".

**Lone surrogates.** GHC decodes argv and directory listings with the file-system encoding, which maps an undecodable byte to a lone surrogate. So a `string` from `wasi.proc.args` or `wasi.fs.list` can change under `pack`. This is not a precondition, because `pack` is total. §7 states it. A plain `hs-text` argument that changes is visible to the caller in the result. A merged map key is not: `Data.Map` keeps one value and drops the other. So `hs-text` inside the key type of a `map` in an argument position is `ffi-type-unsupported`, with the reason "pack is not injective on map keys" (E21). In result position the key goes through `unpack`, which is injective, so it is allowed. No export in the D8 reach table takes a `Map Text` argument, so the refusal costs no reach.

**Soundness of the addition.** The three names add no value to the language: a program can use them only in an interface entry, and every caller sees an existing LLMLL type. Each converter is total, so no new failure arises at the boundary. The direction rule refuses the one conversion that is not total. The map-key rule refuses the one place where a non-injective converter would drop data.

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
| E15 (resolved) | `[keep (fn [p: (fn [s: string] -> bool) xs: list[string]] -> list[string])]` | builds; FN-PARAM-PAREN-1 shipped in v0.30.8 | build (D3) |
| E16 (fires) | interface result `bytes[32]` | `ffi-type-unsupported` (Rev 3 D3 amendment) | type (D3) |
| E17 | `[split-on (fn [sep: hs-text s: hs-text] -> list[hs-text])]`, called with two `string`s | builds; `convIn` is `pack`, `convOut` is `map unpack` | build (D10) |
| E18 (fires) | `[take (fn [n: hs-int s: hs-text] -> hs-text)]` | `ffi-type-unsupported`: narrowing needs FFI-NARROW-1 | type (D10) |
| E19 (fires) | `[f (fn [g: (fn [x: int] -> hs-int)] -> int)]` | `ffi-type-unsupported`: boundary type inside a function parameter | type (D10) |
| E20 (fires) | `hs-text` in a user `def` signature | `unknown type 'hs-text'` | type (D10) |
| E21 (fires) | `[lookup (fn [k: hs-text m: map[hs-text, int]] -> hs-maybe[int])]` | `ffi-type-unsupported`: `hs-text` in a `map` key type in an argument position (`pack` could merge two keys that differ only by a lone surrogate). Write `[lookup (fn [k: string m: map[string, int]] -> hs-maybe[int])]` | type (D10) |
| E21b | `[to-list (fn [m: map[string, int]] -> list[(hs-text, int)])]` and a result `map[hs-text, int]` | allowed; `unpack` is injective | type (D10) |
| E22 | `hs-maybe[hs-maybe[int]]` result | `Result[Result[int, unit], unit]`; nested conversion is componentwise | type (D10) |
| E23 | a Rev 2 entry with no boundary type | the same generated text as Rev 2 | codegen (D1) |
| E24 | `split-on` (E17) called with a computed separator that is `""` | `check` passes; at run time `Data.Text.splitOn` calls `error` (`empty delimiter`) at the first demand of the result | trust (D9 row); stated in §7 (D8); FFI-CONTRACT-1 adds `(pre (not (= sep "")))` |
| E25 (fires) | `[size (fn [m: map[string, int]] -> hs-int)]` where the export's result is polymorphic in an integral type | the binding emits `(toInteger :: Int -> Integer)`; a mismatch with the export's type is a GHC error at the `.llmll` import line | build (D7 gap 2) |

## Verification mapping
- **No new proof obligations.** An interface function has no body and no contract. Nothing goes to QF-LIA or to Lean.
- **Type agreement** is GHC instance checking at build. It is not an SMT obligation.
- **Boundary-type placement and direction** (D10) is a syntactic check at `check`, in the type channel.
- **Converter correctness** (`pack`, `unpack`, `toInteger`, `Maybe` to `Result`, each with an explicit Haskell type) is trust. The converters are compiler-emitted code and change with `codegen_semantics_version`. The D9 row covers the export itself.
- **Strict verified core:** a `def` calling an interface function stays inadmissible (f4). Admitting an FFI function as an uninterpreted symbol under a disclosed totality assumption is FFI-UNINTERP-1.
- **Trust:** callers are `def-shell`, so `asserted` or `tested`. D9 discloses the assumption; the level is unchanged.
- **Later narrowing precondition** (FFI-NARROW-1): `(pre (and (>= x -9223372036854775808) (<= x 9223372036854775807)))`, QF-LIA, class (a) of §5.3.3. The precondition can be derived from the `hs-int` argument, as `bytesLenParamPre` derives a length from a `bytes[n]` parameter. It still needs a call-site discharge from a `def-shell` caller, which SHELL-CALL-PRE-1 says does not happen today. The alternative is a run-time range check that answers through `Result`. FFI-NARROW-1 does not depend on FFI-CONTRACT-1.

## Soundness argument
1. The Haskell function is used at exactly the type the type checker assumed. D3 makes that type closed. D10 makes each boundary conversion explicit and gives every non-`id` converter an explicit Haskell type, so the declared boundary type (for example `Int` for `hs-int`) is fixed at the export. GHC then checks that this Haskell-side type instantiates the export's type.
2. It performs no effect visible in its type (D4).
3. It cannot collide with another name in the build (D6 and the qualified import).
4. Every refusal happens in `check` except two: export existence and type agreement. GHC decides both at build, and both fail closed.
5. A failure inside a library result appears at the first demand of the binding's result, which EVAL-STRICT-1 places at the enclosing argument, let binding or do step (D1). D3's result rule keeps every result fully forceable.
6. Every boundary conversion is total (D10). The one partial conversion, `int` to `Int`, is refused until FFI-NARROW-1. The one non-injective conversion, `pack`, is refused where it would merge map keys.
7. No result gives the verifier a length fact that nothing checked (D3 amendment).
8. Every verdict that rests on a Hackage function says so in the trust report, across module boundaries (D9).

Still assumed, and stated: the library is total and has no hidden effects (`unsafePerformIO`), and GHC is correct. The reach table marks the exports known to be partial (P), and §7 names them. The builtins, which are also Haskell, have the same status. The lone-surrogate change under `pack` is stated in §7 and is not an assumption about the library.

## Affected surface
- `compiler/src/LLMLL/Parser.hs`, `ParserJSON.hs`: parse the three boundary types inside an interface entry only.
- `compiler/src/LLMLL/TypeCheck.hs` `checkStatement (SImport)`: the four new errors; the D3 result rules, including no `bytes[n]` result; the D10 placement and direction rules; `lower` for the entry's visible type; the builtin, duplicate and deduplication checks.
- `compiler/src/LLMLL/CodegenHs.hs`: forced, eta-expanded bindings; `forcerFor`, `convIn`, `convOut`; `llmll_uM`, `llmll_uP2` and `llmll_uEi` in the runtime preamble; the two `LINE` pragmas and the reset; interface names in `renameStatements`; the dead `warp` and `wai` cases removed.
- `compiler/src/LLMLL/TrustReport.hs`: `markFfiAssumptions` and the `ffi_assumptions` emit.
- `compiler/app/Main.hs`: the cross-module FFI map, built from the module cache next to `recordedAxiomMap`, passed on every trust-report path.
- `compiler/src/LLMLL/Diagnostic.hs`: four constructors; the E9 message.
- `docs/llmll-trust-report.schema.json`: an additive `ffi_assumptions` property under `$defs.TrustEntry`; `trust_report_version` does not change.
- `docs/llmll-ast.schema.json`: three additive type arms for the boundary types. Each arm's `description` says the type is valid only inside an interface entry. One `schemaVersion` change is shared with AST-TYPE-ALIAS-1, whichever row ships first.
- Tests: build-and-run for sim-ok, for one export from each reachable row (including one `text` export through `hs-text`, `Map.lookup` through `hs-maybe` and `Map.size` through `hs-int`), and for E17; unit tests for E1–E4, E8, E11, E11b, E16, E18–E21 and E21b; a codegen test that every non-`id` converter carries its explicit type (E25); build tests for E5 and E5b asserting the `.llmll:` location; trust-report tests for E12 and E14; a build-and-run test for E13; a codegen test for E23.
- Docs (doc-lead): §7 and §13.11a per D8; the row citation from §13.10 to §13.11a.
- **Additions:** this is a new FFI tier surface, and D10 adds three interface-only type names. The soundness argument above is the design record for both.

## Risks
1. **Reach is still partial.** Scope. With D10, `filepath`, `containers` and most of `text` are reachable. `time`, `aeson` and `vector` need FFI-OPAQUE-1. Complicates; does not block.
2. **Boundary types are surface.** Scope. Three new type names enlarge what an agent must learn. They are confined to the interface form, and each misuse has an error that names the rule. Complicates only.
3. **Lone surrogates change a value silently.** Soundness of the stated semantics (E21). §7 must state it. Only matters at scale.
4. **Forcing and conversion cost.** Performance. A large `Map` result is traversed once by `convOut` and once by the forcer. This is the same trade as EVAL-STRICT-1. Only matters at scale.
5. **The reach table is partly derived.** Spec drift. The engineer's build test exercises one export from each reachable row. Complicates.
6. **`aeson`, `text` and `vector` are outside `compiler/generated-deps.txt`.** An import of one of them adds a package the CI cache key does not cover. With D10, `text` becomes a real import. Only matters for CI time.

## Findings outside the scope
- **The §7 sandbox sentence** claims Docker, `seccomp-bpf` and `{-# LANGUAGE Safe #-}`; §10 step 4 repeats the Safe claim and step 7 the Docker and `seccomp-bpf` claims. All are false today. Row SAFE-HASKELL-CLAIM-1 (filed, G5, DOC).
- **Equality at incapable types** is CTOR-FN-FIELD-1, settled separately (derive nothing; `equality-undefined` at `check`). It does not affect this record: no interface type admits a function inside a result.

## Proposed roadmap changes (doc-lead)

1. **FFI-TIER1-1** (G3): keep **PLAN**. Note in the status cell that the record is at Rev 3, reopened 2026-10-20 and reviewed by a third professor pass; it settles on the user's approval. D10 is additive: an entry with no boundary type generates the Rev 2 text, so the Rev 2 core can be planned now.
2. **FFI-CONV-1**: narrow it to the lossless set (`hs-text`, `hs-maybe[T]`, `hs-int` in result position) and move it from G7 to G3, beside FFI-TIER1-1. Marker DECIDE until Rev 3 settles, then **PLAN**. It ships in the same release as FFI-TIER1-1.
3. **FFI-NARROW-1** (new, G7, **DECIDE**): `int` to `Int` at the boundary. Choose a derived range `pre` discharged at the call site (needs SHELL-CALL-PRE-1) or a run-time range check that answers through `Result`. It does not depend on FFI-CONTRACT-1.
4. **FFI-OPAQUE-1** (new, G7, **DECIDE**): sealed handle types for opaque Haskell values (`Day`, `Vector`, `Value`). It unlocks `time`, `vector` and `aeson`.
5. **BYTES-READ-1**: no new row. Add a note that an unsized byte type also unlocks `bytestring` at the FFI boundary.
6. **FFI-CONTRACT-1**: unchanged, but FFI-CONV-1's narrowing no longer depends on it; remove "Precedes `FFI-CONV-1`" from its Next Action when FFI-NARROW-1 is filed. Add its first example: `split-on` with `(pre (not (= sep "")))`, since `Data.Text.splitOn` calls `error` on an empty delimiter (E24).

## Questions for the professor (Rev 3) — answered in Review 3

1. **Boundary-type syntax.** Rev 3 states the Haskell side with three interface-only type names (`hs-text`, `hs-maybe[T]`, `hs-int`) and lets callers see the LLMLL type. Two alternatives exist. (a) An annotation on an LLMLL type, such as `(as Text string)`. (b) A Haskell signature string per entry, parsed by the compiler. Which form has the better record in comparable FFIs (Dafny `{:extern}`, F\* `assume val`, Idris `%foreign`, OCaml `external`) for agent-written code? The answer changes the surface the engineer builds.
2. **A non-injective converter on map keys.** `pack` merges keys that differ only by a lone surrogate (E21). Rev 3 states this in §7. The alternative is to refuse `hs-text` as a `map` key. Is a stated, rare value change acceptable for a boundary conversion, or should a non-injective converter be refused where injectivity decides the result?

Both are answered in the appendix (Review 3). Question 1: keep the interface-only type names. Question 2: refuse `hs-text` as a `map` key in argument position.

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

### Review 3, of Rev 3 (2026-10-20)
- **Verdict:** settle Rev 3 after five small edits; no Rev 4 needed. The spot-checks agreed with the code: `TUnit` lowers to `()`, `Result[T, unit]` to `Either () T`, `unit` is a type with literal `()`, and the forcer runs after `convOut`, so the forcer table is unchanged.
- **Q1, syntax:** keep the interface-only type names. Idris 2 `%foreign` is the closest precedent: a fixed set of FFI-safe boundary types, checked by the compiler. OCaml `external`, Dafny `{:extern}` and F\* `assume val` trust the mapping. A Haskell signature string gives `check` nothing to read. An annotation such as `(as Text string)` states the type twice, so the halves can disagree.
- **Q2, map keys:** refuse `hs-text` as a `map` key in argument position. A merged key drops a value with no signal, and a contract cannot see it. Keep it in result position, where `unpack` is injective. Keep the §7 note for plain `hs-text` arguments.
- **Hazards:**
  1. `toInteger` is polymorphic, so `hs-int` fixed no Haskell type. Give every emitted converter an explicit type.
  2. `Data.Text.splitOn` and `Data.Text.replace` call `error` on an empty delimiter or needle. Mark partial exports and name them in §7.
  3. The map-key merge loses data in one direction only (Q2).
  4. Share one `schemaVersion` change with AST-TYPE-ALIAS-1.
  5. State in each boundary-type arm's `description` that it is valid only inside an interface entry.
- **Language-team response:** all five edits accepted, with no pushback. The partiality of `splitOn` and `replace` comes from the `text` package documentation and was not executed; E24 records it as the first FFI-CONTRACT-1 example.
