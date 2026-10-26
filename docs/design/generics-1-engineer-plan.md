# GENERICS-1 + GENERIC-COMPARE-1 — engineer implementation plan

Status: DRAFT for approval, 2026-10-25. Input: [`generics-proposal.md`](generics-proposal.md) Rev 1 (SETTLED 2026-10-24). Base: `main` at `4a7e9cb9` (v0.32.0). Paths are relative to `compiler/` unless they start with `docs/` or `scripts/`.

## Restatement

Add rigid, constrained type parameters to `def-shell` in both front ends, and check generic bodies and contracts once. Instantiate generic callees per call by one-way matching, plus a new lambda-checking mode. Verify generic code by specializing each reached instantiation into an ordinary `def-shell` copy before emission. Codegen stays polymorphic, with an explicit signature and class context. Add the `compare` builtin. It unfolds definitionally at `int` and `bool` in the verifier.

## Context located

1. `docs/design/generics-proposal.md` Rev 1: the settled design (rules 1 to 5, synthesis steps 1 to 6, verification steps 1 to 9, edge cases 1 to 17).
2. `docs/compiler-team-roadmap.md` rows `GENERICS-1` (:163) and `GENERIC-COMPARE-1` (:164): PLAN. The FN-PARAM-UF-1 dependency is met (v0.32.0).
3. `src/LLMLL/Syntax.hs:146-164`: the `Type` type. `TVar` is internal only; no parser produces it.
4. `src/LLMLL/Syntax.hs:722-732`: `SDefShell` has 6 positional fields. There are 71 positional uses across `src/` and `app/`.
5. `src/LLMLL/Parser.hs:228-245` (`pDefShell`) and `:637-639` (`resolveNamedType`): a lowercase type name parses as `TCustom n`.
6. `src/LLMLL/ParserJSON.hs:347-370` (`defShellKeys`, `rejectUnknownKeys`), `:619-679` (`parseType`), `:86-107` (schema version 0.14.0).
7. `src/LLMLL/AstEmit.hs:92-106` (def-shell emit) and `:258` (`TVar` emitted as `named`).
8. `src/LLMLL/TypeCheck.hs:3751-3759` (`freshenFnType`), `:3122-3142` (call fold), `:3776-3886` (`structuralUnify`, one-way), `:3215-3217` (lambdas synthesize only, no expected-type push).
9. `src/LLMLL/TypeCheck.hs:3876-3877`: `TCustom "_"` unifies with anything. An expected `TVar` binds to it.
10. `src/LLMLL/TypeCheck.hs:1392-1437` (`checkEqDefined`, `checkOrdDefined`), `:3699-3738` (map-key gate, plain `tcError`). **`map-key-undefined` does not exist in `src/`.**
11. `src/LLMLL/TypeAdmissibility.hs:356-375` (`noEqWitness`), `:385-416` (`noOrdWitness`). Both are lenient on `TVar`.
12. TVar-as-wildcard sites outside the checker: `Module.hs:453-456`, `HubQuery.hs:66-67`, `ObligationAssembly.hs:900-901, :1304`, `WeaknessCheck.hs:293-294`, `CodegenHs.hs:2529`, `AgentSpec.hs:143, :154`, `Checkout.hs:915-952`.
13. `src/LLMLL/TypeCheck.hs:1634-1673`: every type-check entry returns `DiagnosticReport` only. `Module.hs:199` uses `typeCheckWithCacheRet`, which also returns return types.
14. `src/LLMLL/FixpointEmit.hs:805-845` (per-statement loop, entry statements only), `:3186-3209` (`typeToSort _ = FQInt`), `:4234-4430` (user call to `CallVC`), `:6219` and `:6266-6270` (`markIntBuiltins`, `reflectIntBuiltin` for `min`, `max`, `abs`).
15. `src/LLMLL/EvidenceKey.hs:55-124`: the key hashes the body, effective pre and post, decreases, and the declarations of user types in the signature. **Primitive parameter types and the name are not in the preimage.** Callees are hashed one level deep.
16. `app/Main.hs:1341-1386` (verify: strict check, then emit on raw `stmts`), `:659-666` (test: `subject_key` from `evidenceKeys`), `:736` (build path: check, `instrumentContracts`, codegen).
17. `src/LLMLL/CodegenHs.hs:2169-2188` (`emitDefLogic` signature rule), `:2528-2557` (`isPolyType`, `toHsType`), `:446-` (preamble). Six preamble signatures carry a class context: `list_contains` (Eq), `list_sort`, `list_sort_by`, `map_has`, `map_put` (Ord), `map_get` (`(Ord k, Show k)`).
18. `src/LLMLL/CodegenHs.hs:3356`: `compare` is in `hsPreludeNames`. The fallthrough lowering would call Prelude `compare` and return `Ordering`.
19. `src/LLMLL/Contracts.hs:823-837` (`OrdK`, `ordKeyOf`), `:712-714`, `:772-791` (`modeledBuiltins`).
20. `test/Spec.hs:18287-18289` (pins: `builtinEnv` 127, `needsBinding` 96, `resolvedElsewhere` 9), `:18321-18324` (seven hand-written lowerings), `:14393-14420` (RuntimePure parity and evaluator coverage), `:22602-22650` (STR-ORDER-1 template).
21. `src/LLMLL/CodegenHs.hs:2431, :2755, :3247`: the generated project ships no `-Wall` and no `-Werror`.

## Plan summary

The work lands in seven slices on one branch, `generics-1/def-shell-type-params`, in dependency order:
- S1 syntax and front ends;
- S2 rigid checking;
- S3 call-site instantiation and the site table;
- S4 rules 1 to 5;
- S5 the specialization pass and the verifier;
- S6 codegen;
- S7 `compare` (GENERIC-COMPARE-1).

The central design choice is a new `Type` constructor, `TParam Name (Maybe TyConstraint)`, for the rigid parameter. It does not reuse `TVar`, because `TVar` is a wildcard in about nine sites outside the checker (context item 12). A new constructor fails closed at every catch-all that it does not match.

The type checker records each generic instantiation in a **site table**. The specialization pass reads that table, so the pass never infers types again.

Codegen derives the Haskell context from the declared constraint (`eq` to `Eq`, `ord` to `Ord`, `key` to `(Ord, Show)`), not from a walk over the reached preamble calls. A pinned test enforces the coverage fact that `nc-038` needs. This changes the mechanism of the settled design, and Finding F1 explains why.

The estimated cost is about 2,000 to 2,600 changed Haskell lines and about 70 new hspec examples. Programs with no `:type-params` see no change in output, keys or verdicts.

## Affected surface

### S1 — Syntax and front ends
- `src/LLMLL/Syntax.hs:146-164`: add `TParam Name (Maybe TyConstraint)`. Add `data TyConstraint = TCEq | TCOrd | TCKey`, and add `entails :: TyConstraint -> TyConstraint -> Bool` for the lattice `key ⇒ ord ⇒ eq`.
- `src/LLMLL/Syntax.hs:722-732`: add a 7th field, `defShellTypeParams :: [(Name, Maybe TyConstraint)]`. Update the 71 positional patterns, most of them with a `_`. GHC lists every site.
- `src/LLMLL/Syntax.hs:180-222`: `typeLabel (TParam n _) = n` and `typeConstructorName (TParam _ _) = "type-var"`.
- `src/LLMLL/Syntax.hs` (new function, about 60 lines): `bindTypeParams :: Statement -> Either Diagnostic Statement`.
  - It rewrites `TCustom n` to `TParam n c` for each declared `n`.
  - It covers params, the return type, `pre`, `post`, `decreases`, and every annotation in the body (lambda params, typed `let`).
  - Both front ends call it, so they share one rule.
- `src/LLMLL/Parser.hs:228-245`: parse an optional `:type-params [entry…]` between the name and the param brackets. An entry is `name` or `(name eq|ord|key)`.
- `src/LLMLL/Parser.hs:189-311`: on `def`, `letrec`, `def-interface` and `type`, a `:type-params` clause fails with `type-params-not-supported`. The message names `GENERICS-2` or `GENERIC-TYPES-1`. The model is `pDefLogicRemoved` (:163).
- `src/LLMLL/ParserJSON.hs:358`: add `"type_params"` to `defShellKeys` only.
- `src/LLMLL/ParserJSON.hs:175-184`: add a hint for `type_params` on `def`, modelled on the `decreases` hint.
- `src/LLMLL/ParserJSON.hs:446-455`, `:410-415`, `:440-444`: `parseLetrec`, `parseDefInterface` and `parseTypeDecl` reject a `type_params` key today by ignoring it. Add an explicit `type-params-not-supported` check.
- `src/LLMLL/ParserJSON.hs:619-679`: add the kind `"type-var"`, which parses to `TCustom n`. `bindTypeParams` then binds it. A `type-var` whose name is not declared fails with `unknown-type-var`.
- `src/LLMLL/ParserJSON.hs:86-107`: change `expectedSchemaVersion` to `0.15.0`, and keep `0.14.0` in `acceptedSchemaVersions`.
- `src/LLMLL/AstEmit.hs:92-106`: emit `type_params` only when non-empty, so output for existing programs stays byte-identical. At `:258`, add `typeToJson (TParam n _) = {"kind":"type-var","name":n}`. `TVar` keeps its `named` emission.
- `docs/llmll-ast.schema.json`: version 0.15.0, additive. Add `type_params` on `DefShell` (:162). Add `TypeVar` to the `Type` kind enum (:447) and its if/then branch. Also fix the stale `title` "v0.13" at :4.

### S2 — Rigid checking of the definition
- `src/LLMLL/TypeCheck.hs:3776-3886` (`structuralUnify`) and `:3880-3926` (`compatibleWith`): add explicit `TParam` arms. `(TParam a _, TParam b _)` succeeds only when `a == b`. `TParam` against any other concrete type is a mismatch. The existing `TCustom "_"` arms are unchanged. An expected `TVar` binds to a `TParam`, as to any type.
- `src/LLMLL/TypeCheck.hs:4009-4027` (`unify`): reaches `TParam` through `compatibleWith`. No new code.
- `src/LLMLL/TypeAdmissibility.hs:356-416`: `noEqWitness (TParam _ c)` returns `Nothing` when `c` entails `eq`, else `Just`. `noOrdWitness` does the same with `ord`.
  - Add `noKeyWitness`. Extract the int-or-string test from `TypeCheck.hs:3732-3737` so that `key` and the map gate share one predicate (proposal: "the map-key class of §13.12, whatever it is").
- `src/LLMLL/TypeCheck.hs:1392-1437`: when the witness is a `TParam`, emit `constraint-missing` instead of `equality-undefined` or `order-undefined`. The message names the parameter and suggests the constraint, for example `(a eq)`.
  - The contract clauses are already checked in the definition's environment (`TypeCheck.hs:2212-2238`), so edge case 1b reports on the `post`.
- `src/LLMLL/TypeCheck.hs:3699-3738`: give the existing map-key gate the diagnostic kind `map-key-undefined` (message unchanged), and add a `TParam` arm that requires `key`.
- `src/LLMLL/TypeCheck.hs:2197-2238` (`checkStatement SDefShell`), run before the body is checked:
  - `type-param-shadow` when a name is a primitive type or a user type;
  - `type-param-not-determined` (rule 1) when a declared parameter occurs in no value-parameter type;
  - `untyped-param-in-generic` (rule 5, first half) when a value parameter is `TCustom "_"`.
- **Catch-all audit.** Give an explicit, non-lenient `TParam` arm at each site in context item 12. In `Module.compatibleTy`, `TParam` matches only itself. In `CodegenHs.isPolyType`, `TParam` is `False`, so S6 emits the signature.

### S3 — Instantiation at a call, and the site table
- `src/LLMLL/TypeCheck.hs:3751-3759` (`freshenFnType`): before renaming, map each `TParam n _` in a callee type to `TVar n`. This is the only point where a rigid parameter becomes a placeholder.
- `src/LLMLL/TypeCheck.hs:3080-3142`: when the callee's registered type contains a `TParam`, route the call to a new `inferGenericApp` (about 150 lines). It implements synthesis steps 1 to 6:
  1. Infer the arguments that are not lambdas, and run `structuralUnify` one way.
  2. Loop over the lambdas. A lambda is ready when every parameter is annotated or its expected type, after the substitution, has no free fresh `TVar`.
  3. Check each ready lambda with the new `checkLambdaAgainst :: [Type] -> Expr -> TC Type`. It pushes the expected types onto `_` parameters, rejects an annotation that disagrees, infers the body, and unifies the result. Repeat until nothing changes.
  4. A lambda that is never ready gives `type-param-not-determined` at the call, naming the parameter and the lambda.
  5. Rule 5, second half: a type argument that mentions `TCustom "_"` gives `untyped-arg-to-generic`.
  6. Test the declared constraints. A concrete type uses the existing walks, plus `noKeyWitness`. A `TParam` uses `entails`. The message names the instantiation.
  7. A `TVar` that stays unbound is recorded as **unfixed**.
  
  `checkLambdaAgainst` runs only at generic calls. Lambdas at builtin and non-generic calls keep the current synthesis path, so no existing verdict moves.
- `src/LLMLL/TypeCheck.hs` state (:633-667): add `tcGenericSites :: Map SiteKey [Type]`.
  - The key is `(enclosing top-level definition, callee, canonicalExpr of each argument)`.
  - The value is the type arguments in declared order. They can mention the enclosing definition's own `TParam`s, and `TVar "?unfixed"` marks an unfixed one.
  - The table also records each `compare` call, with the operand type, for S7.
  - If one key receives two different values, that is the error `generic-site-ambiguous`. Two identical call texts in one definition then resolve to different types through shadowing. The hint asks for a rename. Finding F2 gives the reasoning.
- `src/LLMLL/TypeCheck.hs:1634-1720`: add `typeCheckStrictWithCacheSites`, which returns `(DiagnosticReport, GenericSites)`. Extend `typeCheckWithCacheRet` (used at `Module.hs:199`) the same way.
- `src/LLMLL/Syntax.hs:1212-1241` (`ModuleEnv`): add `meGenericSites`, filled at `Module.hs:199`. An importer needs it to specialize an imported generic whose body calls other generics.

### S4 — Rules 2 to 4
- **Rule 2** (`polymorphic-recursion`): after `checkStatements` (`TypeCheck.hs:1812-1969`), take each strongly connected component of `HoleAnalysis.buildCallGraph` (`HoleAnalysis.hs:647-657`). Reuse `TC.sccOf` (`TypeCheck.hs:976-986`).
  - For each site in the table whose caller and callee are in the same component and whose caller is generic, require every type argument to be a bare `TParam` of the caller.
  - This is the per-component rule in proposal "Rules" 2. It keeps the type arguments in a cycle from growing, so the instantiation set is finite.
  - The proposal says to reuse the trust-report component. That is `CallGraph.undischargedCycleMembers`, which subtracts discharged cycles, so it is the wrong set here. The plain component is what bounds specialization.
- **Rule 3** (`for-all-type-param`): a `for-all` sits outside every type-parameter scope, so `a` is an unknown type there. When a `for-all` binder's unknown `TCustom n` matches a type-parameter name in the module, report `for-all-type-param` instead, with the hint "instantiate at a concrete type" (`TypeCheck.hs:2290-2297`).
- **Rule 4** (`ffi-type-param`): a rigid parameter can never unify with a Tier 1 boundary type, so the rule holds by construction. Refine the mismatch message to `ffi-type-param` when the callee is a Tier 1 import and the actual type mentions a `TParam` (`TypeCheck.hs:2328`, `Ffi.hs:130-162`).
- **Strict core.** A `def` that calls a generic `def-shell` gives `generic-callee-in-def` at check time, naming `GENERICS-2`. Per-instance admission is v2 (proposal "Deferred"). Today the existing admission would refuse it with a less specific message, because `f` has no evidence under its own name.

### S5 — Specialization pass and verifier
- **New module `src/LLMLL/Specialize.hs`** (about 350 lines): `specialize :: ModuleCache -> GenericSites -> [Statement] -> ([Statement], GenericStats)`.
  1. **Roots.** Collect the roots: every non-generic definition and `check` statement.
  2. **Worklist.** Take each site of a root from the table. For a generic callee, substitute the enclosing instance's type arguments into the site's type arguments, then expand aliases. That gives the pair `(f, [T…])`. An unfixed argument becomes `TInt` (verification step 6). Repeat inside each new copy until no new pair appears. Rule 2 makes this finite. A hard cap of 10,000 copies gives an internal error, so a defect cannot loop forever.
  3. **Copy.** Make an `SDefShell` named `f@[T1,T2]`, with `defShellTypeParams = []`.
     - Do the lookups on the **original** body, keyed by original argument text. Then rewrite each generic call in it to its copy name, and each `compare` site to `compare%int` or `compare%bool` when its operand type is `int` or `bool`.
     - Then substitute `TParam` into params, return, `pre`, `post`, `decreases` and annotations.
  4. **Rewrite the roots.** Rewrite generic calls in the roots the same way. A root that calls a generic always has concrete or unfixed type arguments.
  5. **Imported generics.** For a generic imported from module `M`, qualify the copy's free top-level names with `M`'s path. Otherwise an entry definition with the same name would capture them (`FixpointEmit.hs:551`). Copies go into the entry statement list, so the importer's run verifies them and its sidecar stores them (verification step 9).
  6. **Drop the generic sources** from the output. Return `GenericStats` (definitions and instance counts per definition) for reporting.
  
  The pass returns its input unchanged when no statement has type parameters. That is the guarantee that existing programs are unaffected.
- `app/Main.hs:1341-1348` (`doVerify`): call `typeCheckStrictWithCacheSites`, then `specialize`. Pass the specialized statements to both `buildKeyEnv` and `emitFixpointWithCache`, so the one-`KeyEnv` invariant (HASH-PRE-ASYM) holds.
- `src/LLMLL/FixpointEmit.hs`:
  - Generic sources never reach the emitter. As a defence, a `SDefShell` with non-empty `defShellTypeParams` at `:835-845` is an internal error.
  - `buildContractEnvWith` (:465) skips generic sources. A missed rewrite then falls back as an unknown callee and is never mis-sorted as `FQInt` (`:3209`).
- `src/LLMLL/EvidenceKey.hs:84-124`: add a `(type-args …)` fragment for a copy, with each expanded type argument. Fill it only for copies, so every existing key stays byte-identical.
  - Without it, `pick-min@[int]` and `pick-min@[bool]` hash the same preimage, because primitive parameter types and the name are not hashed (context item 15).
  - Alias predicates already enter through the effective contract, which covers edge case 14. User type declarations enter through `ownTypes`.
  - Callees stay one level deep, as for every definition (Finding F3).
- `app/Main.hs:1406-1428`: print `generics: N definitions, M instances` after `body-faithful:`, only when N > 0. Add the JSON twin `generics: {definitions, instances, per_definition}` to `bodyMetaV` (:1654-1688), also only when N > 0.
- `src/LLMLL/TrustReport.hs:1348-1371`: list each `f@[T…]` record from the sidecar under its source `f`. A generic with no instance gets the label `unverified (generic, not instantiated)` (verification step 8). TRUST-AXIOM rows name the copy. The sealed axiom set is unchanged.
- `app/Main.hs:659-666` (`doTest`): run `specialize` only to compute keys. A property subject that is a generic `f` called at `[T…]` maps to `f@[T…]`, and its `subject_key` is the copy's key. The PBT evaluator still runs the **original**, unspecialized program, which gives erasure parity (proposal "Testing").

### S6 — Codegen
- `src/LLMLL/CodegenHs.hs:2169-2188` (`emitDefLogic`): a generic `def-shell` always emits a signature. The context is the union, over its type parameters, of `eq` to `Eq tp_a`, `ord` to `Ord tp_a`, and `key` to `(Ord tp_a, Show tp_a)`. A bare parameter adds no class.
- `src/LLMLL/CodegenHs.hs:2533-2557`: `toHsType (TParam n _) = "tp_" <> toHsIdent n`. The prefix avoids Haskell keywords and the `a` that untyped parameters emit (`:2552`).
  - Lambda annotations are not emitted (`:2293-2294`), so `ScopedTypeVariables` scoping is not needed.
- **Pinned test (the coverage fact).** For each preamble line with a context `C v`, find the gate in `TypeCheck.hs` that the builtin's argument at `v` goes through. Assert that the mapped classes of the LLMLL constraint that gate demands include `C`.
  - Today that is: `list_contains` (Eq: equality gate), `list_sort` and `list_sort_by` (Ord: order gate), and `map_has`, `map_put`, `map_get` (Ord and Show: key gate).
  - A future preamble line with a new context fails this test until the mapping or gate changes. That closes witness G1 for future preamble changes.

### S7 — `compare` (GENERIC-COMPARE-1)
- `src/LLMLL/TypeCheck.hs:108-`: add `("compare", TFn [TVar "a", TVar "a"] TInt)`. Add a `compare` arm to `checkOrdDefined` (:1421-1424). An unresolved `TVar` is accepted (AMBIG-TVAR-1). A `TParam` needs `ord`.
- `src/LLMLL/CodegenHs.hs`: add `llmll_compare :: Ord a => a -> a -> Integer` to the preamble, with `LT -> -1`, `EQ -> 0`, `GT -> 1`. Mirror it in `src/LLMLL/RuntimePure.hs`.
  - Add a hand-written `emitApp "compare"` (and `compare%int`, `compare%bool`) that lowers to `llmll_compare`. The fallthrough would bind Prelude's `compare` (`:3356`).
  - The `llmll_` prefix is already reserved (`:3478`).
- `src/LLMLL/Contracts.hs:712-791`: add an arm through `ordKeyOf` with `RP.llmll_compare` over `OrdK`, and add `compare` to `modeledBuiltins`.
- `src/LLMLL/FixpointEmit.hs:6266-6270`:
  - `reflectIntBuiltin "compare%int" [a,b] = FQIte (a < b) (-1) (FQIte (a = b) 0 1)`.
  - `compare%bool` is `FQIte (a = b) 0 (FQIte a 1 (-1))`.
  - Add both to the live list of `markIntBuiltins` (:6219).
  - Plain `compare` (string, pair, or a non-specialized site) stays unmodeled and falls back as `app:compare` (`:3893`).
- `scripts/build-smoke/smoke.llmll`: add one `compare` call (required by `test/Spec.hs:18326-18337`).

## Verification impact

- **Solver time.** A program with no `:type-params` has the same `.fq` file and the same solver time. The specialization pass returns early.
  - For a generic program, the cost is the sum over instances of the hand-written copy's cost. P1 has 3 key-form definitions × 3 instances plus `pq-show` × 3, which is 12 copies against 13 hand-written definitions today. P1's `.fq` therefore stays about the same size.
- **New obligations.** None beyond what the copies carry. Each copy carries exactly the obligations of the hand-written equivalent: its `pre`, its `post`, alias introduction and elimination from `augmentContractPre` and `augmentContractPost`, call-site `pre` obligations, and `decreases`.
  - `compare%int` and `compare%bool` add no assumed post and no axiom. They are definitional `FQIte` terms.
- **Fragment.** Copies stay in the fragment of their hand-written equivalent. `compare` at `int` and `bool` stays QF-LIA. At `string` or a pair, it is uninterpreted and the caller falls back.
- **Trust model.**
  - `Σ_auto` and the sealed axiom set are unchanged.
  - `checker_soundness_version` stays at `4`. No existing verdict moves, every existing key is byte-identical, and new verdicts exist only for new constructs.
  - No `.verified.json` migration.
- **Strict-verified-core.** No body-faithful function newly falls back. A `def` cannot call a generic in v1 (S4).
- **Predicted, not yet measured:**
  - `pick-min@[int]` proves (edge case 12);
  - `pick-min@[string]` falls back;
  - `pick-min@[PositiveInt]` proves with the `result > 0` obligation stated (edge case 13).
  
  The test gate measures all three.

## Performance budget

- **GHC build.** `Syntax.hs` changes, so about 45 modules recompile, one full rebuild of about 4 to 6 minutes. `TypeCheck.hs` and `FixpointEmit.hs` are the largest units.
- **Test suite.** About 70 new examples. Most are pure parser and type-check units. About 12 run `verify` end to end and about 4 run GHC builds (edge case 16, P1, P3, `compare` smoke). The estimate is plus 60 to 90 seconds on `stack test`.
- **Compiler runtime.**
  - `llmll check` adds one map insert per generic call.
  - `llmll verify` adds the pass, which is linear in copies × body size. Under 50 ms for P1.
  - `typecheck --sketch` is unchanged. Sketch mode gets no site table, because it does not run `specialize`.
- **Caches.** Existing ProofCache and VerifiedCache hit rates are unchanged, because keys are byte-identical. A copy has a stable key across runs, so it caches like any definition.

## Contract plan

The compiler change is Haskell and lands nothing in the provable fragment. The deliverables that do carry contracts are the LLMLL regression fixtures. Their contracts and refuting bodies are fixed here, before the bodies are written:

- **`scripts/tests/fixtures/generics/pick.llmll`, `pick-min` (edge case 12, strengthened):**
  ```lisp
  (def-shell pick-min :type-params [(a ord)] [x: a y: a] -> a
    (post (and (<= (compare result x) 0) (<= (compare result y) 0)))
    (if (<= (compare x y) 0) x y))
  ```
  - **Refuting body:** `x`. At `[int]`, with x = 1 and y = 0, `compare 1 0 = 1`, so the post fails. Expected: `pick-min-bad@[int]` is refuted, exit 1.
  - **Expected verdicts:** `@[int]` proves, `@[string]` falls back (`app:compare`), and `@[bool]` proves through `compare%bool`.
  - The fixture also keeps the proposal's original one-clause post as a separate definition, so edge case 12 is tested literally.
- **`pick-min` at `PositiveInt` (edge case 13).** The same definition, called with `p q : PositiveInt` from a non-generic caller.
  - **Expected:** the copy's effective post includes `result > 0`, and it proves.
  - **Refuting body:** `(def-shell dec-min :type-params [(a ord)] [x: a y: a] -> a …)` cannot build a new `a`. No refuting body exists in the generic language. That is AMBIG-TVAR-1 step 1, and it is the point of the edge case.
  - So the fixture instead asserts that the obligation text `result > 0` appears in the copy's `.fq` constraint.
- **Module placement.** All fixture definitions are `def-shell`, which can call siblings. No `def` calls a generic in v1, so the one-function-per-module rule for strict `def` does not apply.
- **What stays unproved:**
  - P1's copies fall back on the `match` over `list-head`, as the hand-written copies do today (proposal "P1");
  - any copy that calls `compare` at `string` or a pair (`GENERIC-COMPARE-PAIR-1`, filed below);
  - a key-function call proves only where FN-PARAM-UF-1 already makes it body-faithful.

## Test plan

**Baseline.** Measure `stack test` and `python -m pytest scripts/tests/` on `4a7e9cb9` before the first commit. The last recorded figures are hspec 2765 and Python 605 passed, 5 skipped (`CHANGELOG.md:177`). The target is hspec at least 2830 and Python at least 611, both with 0 failures.

**hspec (`test/Spec.hs`)**, one `describe` per slice:
- **S1 (about 14 examples):**
  - S-expression and JSON parse of `:type-params` with each constraint;
  - `type-params-not-supported` on `def`, `letrec`, `type`, `def-interface`, in both front ends;
  - JSON `unknown-type-var`;
  - AstEmit round trip; byte-identical emission for a program without type parameters;
  - schema 0.15.0 accepted and 0.14.0 still accepted. Update the version pins at `test/Spec.hs:2016-2027, 19689-19691, 23535-23538, 23792, 24032`.
- **S2 (about 12):**
  - edge cases 1, 1b, 5, 8;
  - rigid `a` against rigid `b` is a mismatch;
  - the definition-site `type-param-not-determined` (edge case 3);
  - `untyped-param-in-generic`;
  - `noEqWitness`, `noOrdWitness` and `noKeyWitness` on `TParam` for each constraint;
  - `map-key-undefined` kind on the existing gate.
- **S3 (about 14):**
  - edge cases 2, 3b, 10, 11, 17;
  - the step-3 fixpoint for `pq-insert` (`k` fixed only by the lambda result);
  - a rigid parameter satisfying `ord` through `key`;
  - an unfixed instantiation recorded as unfixed;
  - `generic-site-ambiguous` on a constructed shadowing witness: `(let [(x 1)] (f x))` and `(let [(x "s")] (f x))` in one body;
  - a lambda at a non-generic call keeps synthesis (a regression pin).
- **S4 (about 6):** edge cases 4, 6, 7; a cycle `f [a] ↔ g [b]` passing bare parameters is accepted; `generic-callee-in-def`.
- **S5 (about 12):**
  - `specialize` is the identity on all of `scripts/tests/fixtures/**` that has no type parameters (a corpus pin);
  - copy naming and the alias expansion of the type arguments;
  - the unfixed argument specialized at `int`;
  - the `(type-args …)` fragment present only on copies, and existing keys unchanged on a pinned fixture;
  - edge case 14: a predicate edit changes the copy's key;
  - edge case 15: `subject_key` is the copy's key;
  - the cross-module qualification witness: the importer defines its own `helper`, and the imported generic's copy still calls `M.helper`;
  - the instance count line and its JSON twin;
  - a generic source reaching the emitter is an internal error.
- **S6 (about 5):**
  - signature and context for `eq`, `ord`, `key` and bare;
  - the `tp_` prefix;
  - the preamble coverage pin (S6);
  - edge case 16: a `group-by` signature with `(Ord tp_k, Show tp_k)`.
- **S7 (about 7):**
  - the type of `compare`; `order-undefined` at a sum type;
  - evaluator parity with `RP.llmll_compare` over int, bool, string and pair;
  - codegen lowers to `llmll_compare`, not Prelude `compare`;
  - the `compare%int` and `compare%bool` unfoldings in `.fq`;
  - builtin-redefinition of `compare` is refused;
  - pin updates: `builtinEnv` 127 to 128, hand-written lowerings 7 to 8, and the `resolvedElsewhere` and `needsBinding` counts recomputed and commented at `test/Spec.hs:18262-18289`.

**Python (`scripts/tests/test_generics_1.py`, about 6 tests, run with `LLMLL_BIN` set):**
- `verify` on `pick.llmll`: the edge case 12 and 13 verdicts and the refuting body's exit 1;
- `build` and run of P1 and P3 from the proposal, with GHC accepting both (G1 closed end to end);
- `test` on a property calling `pick-min` at `int`: the record lands on `pick-min@[int]` only;
- the JSON-AST round trip of `pick.llmll`.

**End-to-end commands:** `llmll verify`, `llmll build`, `llmll test` and `llmll trust-report` on `scripts/tests/fixtures/generics/`.

**Corpus regression:** run `verify` on every fixture in `scripts/tests/fixtures/` with fixpoint off `PATH`, and diff the `.fq` output against `main`. The expected diff is empty. Never run fixpoint over the whole corpus, because the memory limit was hit before.

## Rollback

- Each slice is its own commit, and the branch merges as one release.
- A single revert of the merge removes the feature. Nothing outside the new constructs depends on it.
- Schema 0.15.0 is additive, and 0.14.0 stays accepted. A program written for 0.14.0 never sees the new fields.
- No `.verified.json` or `.fq` migration. Existing keys are byte-identical, and copy records (`f@[T…]`) are new keys that an older compiler ignores as unknown definitions.
- Worst-case unwind: revert the merge and keep `compare` (S7) if it is wanted alone. S7 does not depend on S1 to S6 except for the `TParam` arm in `checkOrdDefined`, which is one line.

## Risks and unknowns

1. **The site-table key can collide through shadowing.** Class: DX. Source: S3, Finding F2. Effect: complicates. A collision is refused, never resolved silently, so it is a DX cost and not a soundness cost. The shadowing witness gives the error. Corpus frequency is expected to be zero.
2. **The importer captures names in imported generic copies.** Class: verification. Source: `FixpointEmit.hs:551` (entry definitions shadow imports). Effect: complicates. Without qualification, a copy of `M.f` would call the importer's own `helper`. S5 step 5 qualifies free names, and the S5 witness test pins it.
3. **The catch-all audit misses a `TParam` site.** Class: verification. Source: context item 12. Effect: complicates. A missed site reaches a `_ ->` default. The audit is a grep for `_ ->` in every function that matches `TVar`, plus the S5 internal error that keeps generic sources out of the emitter.
4. **The 71-site `SDefShell` field change.** Class: build. Source: context item 4. Effect: only cost, about half a day. GHC finds every site. A pattern synonym was considered and rejected, because it hides the field from future readers.
5. **Instances grow with nesting depth.** Class: performance. Source: proposal risk 3. Effect: matters only at scale. Rule 2 bounds the set. The count is printed, and the internal cap of 10,000 stops a defect.
6. **The value evidence is one designed probe.** Class: scope. Source: proposal risk 1. Effect: does not block. The experiment-lead MEASURE in the proposal is unchanged.
7. **`compare` was a free name.** Class: DX. A user program that defines `compare` now fails with builtin-redefinition. A grep of every `.llmll` and `.json` file in the repository found no definition named `compare`. The CHANGELOG still names the break.

## Findings for the language-team and doc-lead

- **F1 — The context comes from the declared constraint, not from the reached preamble calls (mechanism change; the rest of the design is unchanged).**
  - Deriving the context from reached calls needs, for every builtin call in a generic body, the binding of the builtin's own type variables. The checker does not keep that binding past one call (`TypeCheck.hs:3816-3821`). There is also no table of builtin names to Haskell signatures (`CodegenHs.hs:2353`).
  - The declared mapping needs neither of these. All three `nc-038` facts still hold, and fact 3 holds by the S6 pinned test.
  - The visible difference is P3's `show-groups`. It gets `(Ord tp_k, Show tp_k)` instead of no context. GHC accepts a redundant context, and the generated project has no `-Wall` (context item 21).
  - An explicit declared signature has one more effect. If the checker ever lets a body reach a class that its constraint does not entail, GHC rejects the body. The defect then fails closed at build time, which is the proposal's "internal error" requirement.
- **F2 — Instantiations are recorded in a site table, not elaborated into the tree.**
  - The checker returns diagnostics only (`TypeCheck.hs:1634`). It has no expression-level pointer outside sketch mode (`:641`).
  - Making it return an elaborated tree would be a refactor of about 4,000 lines.
  - The table keyed by argument text is about 40 lines. Its one failure mode is refused, never silent.
- **F3 — The evidence key stays one level deep.** Proposal verification step 4 says "transitively, the same for every specialized callee". The existing key hashes callee contracts one level deep (`EvidenceKey.hs:26`, HASH-PRE-ASYM), which is assume-guarantee. A callee copy's contract already contains its expanded type arguments, and a deeper change changes the callee's own key. A transitive key would invalidate more evidence and protect nothing more, so the text needs a correction.
- **F4 — Rule 2 uses the plain component.** It does not use the trust report's component, which subtracts discharged cycles (`CallGraph.hs:183-189`). The proposal text should name `HoleAnalysis.buildCallGraph` components.
- **F5 — `compare` at pairs falls back in this release.**
  - Pairs are `FQDataApp "Pair2"` (`FixpointEmit.hs:3186-3209`). Unfolding needs projection measures that the emitter does not define for comparison.
  - File `GENERIC-COMPARE-PAIR-1` (G7, PLAN): unfold `compare` at pairs of `int` and `bool`.
  - The GENERIC-COMPARE-1 row says "int and bool", which this plan meets. The proposal's line about pairs is the part that moves.
- **F6 — New diagnostic kinds:** `type-params-not-supported`, `type-param-shadow`, `type-param-not-determined`, `untyped-param-in-generic`, `untyped-arg-to-generic`, `constraint-missing`, `polymorphic-recursion`, `for-all-type-param`, `ffi-type-param`, `unknown-type-var`, `generic-site-ambiguous`, `generic-callee-in-def`, `map-key-undefined`.
  - `untyped-param-in-generic`, `generic-site-ambiguous`, `generic-callee-in-def` and `unknown-type-var` are not in the proposal.
  - The proposal's `untyped-arg-to-generic` covers only the argument half of rule 5, so the parameter half gets its own name.
- **F7 — Spec drift, recorded and not fixed:** `docs/llmll-ast.schema.json:4` says "v0.13" while the schema is 0.14.0.

## Hand-off (on ship, to documentation-lead)

Prepared at ship time. Planned content:
- Rows `GENERICS-1` and `GENERIC-COMPARE-1` close.
- File `GENERIC-COMPARE-PAIR-1` (F5).
- Proposal text corrections F1, F3 and F4.
- `LLMLL.md` §0 (the `nc-038` amendment, as drafted in the proposal), §3, §3.4.6, §5.3.3, §5.3.4, §12 and §13.
- Schema 0.15.0.
- The CHANGELOG entry, with the measured test delta.
