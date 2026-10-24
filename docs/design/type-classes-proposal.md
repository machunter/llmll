---
title: TYPE-CLASSES — should LLMLL have type classes or a similar constraint mechanism?
status: Rev 1 DRAFT, 2026-10-24. The language-team and the professor agree on the recommendation (S0). The user has not decided, so this record is NOT settled.
rows: none filed; two candidate rows are named in "Hand-off" (UNTYPED-PARAM-ESCAPE-1, PARAM-GRAMMAR-1)
review: docs/design/type-classes-review.md (professor, of Rev 0); standalone, folded by the doc-lead at settlement
---

# TYPE-CLASSES — should LLMLL have type classes or a similar constraint mechanism?

## Summary

**Recommendation (Rev 1): option S0.**

- Every parameter of `def`, `def-shell` and `letrec` carries a type.
- An untyped `fn` parameter is legal only where the expected function type is known (the Pierce–Turner rule).
- The untyped form goes through one release that warns before it is removed.
- LLMLL adds no user-declared type classes now.
- The two closed built-in sets, `Eq?` and `Ord?`, are named in the spec as documentation. Nothing infers them onto user definitions.
- Option B (the explicit-dictionary idiom, with `def-interface` and `list-sort-by`) is documented together with S0.

Rev 0 recommended S+, which inferred constraints onto untyped definitions. **Rev 1 withdraws S+.** The professor showed that `check` has no type scheme to attach a constraint to. An untyped parameter is a wildcard that unifies with every type.

**The measurement settles the migration cost.** The tracked corpus has 26 untyped parameters on definitions and 14 on lambdas. No definition among them is called at two or more types (see "Measurement"). S0 removes no expressiveness that the corpus uses.

## Changes from Rev 0

| Review item | Disposition | Where |
|---|---|---|
| 1. Choose S0, with the Pierce–Turner rule for `fn` and a release that warns first. `param_type` becomes required, which changes the schema version. | **Adopted.** Two additions with evidence: (a) the Pierce–Turner rule is new checker work, because an untyped lambda parameter is not checked even in a checking position today (W10); (b) the warning proposes a type from the call sites that `check` sees, not from GHC. | "Option S0" |
| 2. Re-scope `CONSTRAINT-ESCAPE-1` as an untyped-parameter escape. | **Adopted.** The row becomes `UNTYPED-PARAM-ESCAPE-1`, with witnesses W1, W5, W6, W8, W10, P7, P8 and P9. | "Findings", "Hand-off" |
| 3. Keep `Eq?` and `Ord?` as documentation only. | **Adopted.** | "Option S0" |
| 4. Cite `def-interface` (§8.8), and re-cost option 4 as verify-after-specialize keyed on a content hash. | **Adopted, with one partial rebuttal.** `def-interface` is the right host and its `:laws` channel exists. But it is a per-module signature with no notion of an instance, and LLMLL has no type-variable syntax. So option 4 still needs type-variable syntax in `Type`, which is the larger part of the schema cost. | "Option 4" |
| 5. Correct the generalization claim and edge case 6. | **Adopted.** Rev 0's sentence "`check` generalizes a definition" was wrong and is withdrawn. Edge case 6 holds only after AMBIG-TVAR-1 ships; on `7f5b6786` that row is still OPEN. | "Findings", "Edge cases" |
| 6. Fact 4 wording. | **Adopted.** The requirement is that evidence keys cover the elaborated body with explicit dictionaries. Global coherence is one way to meet it. | "The verification argument" |
| 7. Notes on printing, hashing and the numeric tower. | **Adopted.** | "What a class system would also touch" |
| 8. Measure every untyped parameter, and how many such functions are called at two or more types. | **Done.** | "Measurement" |

The review also corrects Rev 0's citations for discipline (B): Liquid Haskell, F\*, Lean and Dafny verify generically, and SPARK is the precedent for specialize-then-verify. Rev 1 adopts that. The defaulting item in review gap 5 does not apply under S0, because S0 keeps AMBIG-TVAR-1's soundness step 1 true: user definitions stay monomorphic.

## Restatement

The question is whether LLMLL should let a program state "this function works for any type with equality or an order", and whether a program can add a type to such a set. The candidate mechanisms are:

- Haskell type classes;
- Rust traits;
- OCaml modular implicits;
- explicit dictionaries;
- ML functors;
- Go type sets;
- closed built-in constraint sets;
- doing nothing.

**Two reference classes apply.** The **measurement set** is agents writing programs, judged by the governing criterion in `docs/compiler-team-roadmap.md`: one-shot acceptance with verified contracts. The **design-reference set** is Liquid Haskell, F\*, Dafny, Idris and Lean.

## Context located

1. **`docs/compiler-team-roadmap.md`, header**: the one-shot criterion.
2. **`docs/design/type-classes-review.md`**: the professor's review of Rev 0.
3. **`docs/design/ambig-tvar-1-proposal.md`**: settled 2026-10-24, not shipped. GHC defaults an unfixed `Eq` or `Ord` type to `()`. Its soundness step 1 assumes that user definitions are monomorphic.
4. **`docs/design/collect-order-1-proposal.md`**: O, `order-undefined`, and the choice of a key function over a comparator.
5. **`docs/design/equality-capable-types-proposal.md`**: equality capability is a greatest fixpoint over user types (CTOR-FN-FIELD-1).
6. **`compiler/src/LLMLL/Parser.hs`, `pDefParam`**: a bare parameter name parses as `TCustom "_"`. The comment there says "type inference is v0.2", which never happened.
7. **`compiler/src/LLMLL/ParserJSON.hs`, the parameter reader**: `"untyped": true`, or a missing `param_type`, gives `TCustom "_"`.
8. **`compiler/src/LLMLL/TypeCheck.hs`**:
   - `structuralUnify` and `compatibleWith` accept `TCustom "_"` against every type and bind nothing.
   - `checkEqDefined` and `checkOrdDefined` read only the substitution at a builtin call site.
9. **`compiler/src/LLMLL/Module.hs`, `compatibleTy`**: the wildcard is compatible across modules too.
10. **`compiler/src/LLMLL/CodegenHs.hs`**: the wildcard lowers to a Haskell type variable with no signature, so GHC does the real inference.
11. **`LLMLL.md` §3.4.6**: local type inference with no global unification. Type information enters only through annotations and holes.
12. **`LLMLL.md` §12**: `typed-param = IDENT ":" type` for `def` and `def-shell`. There is no rule for an untyped `fn` parameter.
13. **`LLMLL.md` §8.8 and §8.8.1**: `def-interface`, with typed method signatures, structural checking across modules, and `:laws` tested by QuickCheck.
14. **`LLMLL.md` §5, PBT lift rule item 5**: interface laws are parametric over implementations and use a separate trust channel.
15. **`docs/llmll-ast.schema.json`, `TypedParam`**: `param_type` is optional, and a legacy `untyped` flag exists. The emitter writes `"untyped": true` for a bare parameter. The schema version is 0.14.0.

## Findings

### F1. An untyped parameter is an unchecked dynamic type (re-scoped from Rev 0)

`TCustom "_"` behaves like the dynamic type of gradual typing (Siek and Taha, Scheme Workshop 2006): it is consistent with every type, but there is no cast. The back end is statically typed GHC. So **every** type error can pass `check` through it, not only constraint errors.

All rows were run on the compiler built from `03e7195e` (v0.31.0). The professor's W-rows were measured on 0.30.10, and I reproduced W1, W6 and W8 on 0.31.0.

| ID | Program | `check` | GHC |
|---|---|---|---|
| W1 | `(def-shell inc1 [x] (+ x 1))` `(def-shell g [] -> string (inc1 "a"))` | OK | `Couldn't match type ‘Integer’ with ‘[Char]’` |
| W5 | `(def-shell first-of [p] (first p))` used as an int on `(pair "a" 1)` | OK | type mismatch (professor's run) |
| W6 | `(def-shell id1 [x] x)` `(def-shell g [] -> int (id1 "a"))` | OK | type mismatch |
| W8 | `(def-shell g [] -> int (let [(f (fn [y] (+ y 1)))] (f "a")))` | OK | type mismatch |
| W10 | `(def-shell g [] -> list[int] (list-map ["a"] (fn [y] (+ y 1))))` | **OK** | type mismatch expected; the same body with `[y: string]` is the `check` error `type mismatch in '+'` |
| P7 | `srt [xs]` is `(list-sort xs)`, called at `list[Pt]` | OK | `No instance for ‘Ord Pt’` |
| P8 | `same? [x y]` is `(= x y)`, called on two functions | OK | `No instance for ‘Eq (Integer -> Integer)’` |
| P9 | `srt` called at `list[float]` | OK | **builds**; it sorts `float`, which §13.5 forbids |

**W10 is new in Rev 1.** An untyped lambda parameter escapes `check` **even in a checking position**, where the expected type is known. So the Pierce–Turner rule is not only a restriction on the parser. The checker must also push the expected parameter type into the lambda.

**Correction of Rev 0.** Rev 0 said that `check` "generalizes" a definition with an untyped parameter. It does not. No scheme exists. GHC infers a polymorphic type, and `check` sees a wildcard.

### F2. The grammar does not admit untyped parameters (spec drift; unchanged)

§12 requires a type on every `def` and `def-shell` parameter. The parser, the JSON reader, the schema and the §13.4 accessor example all accept a bare name. Under S0 the code and the schema move to match the grammar, and §13.4's example gains types.

### F3. Where constraints live today (unchanged in substance)

`=`, `!=` and `list-contains` require equality. `list-sort` and `list-sort-by` require O. Map operations require keys in `{int,string}`. `check` tests each one at a direct builtin call. GHC handles an unfixed type (AMBIG-TVAR-1, once it ships) and the class constraints of Tier 1 Hackage exports (§7). These sets are closed and built in, like Dafny's `T(==)`, F\*'s `eqtype`, Standard ML's `''a` and Go's `comparable`.

## Measurement

**Method.**
- I copied the 493 tracked `.llmll` files and the 98 tracked `.ast.json` files into the scratchpad.
- I emitted each `.llmll` file as JSON-AST with the built compiler. 490 files emitted. The 3 that failed are the intentional-rejection fixtures under `scripts/doc-claims`; none has an untyped parameter.
- A script walked every `def`, `def-shell`, `letrec`, `def-logic` and `def-invariant` statement and every `lambda`. It counted parameters marked `"untyped": true` or with no `param_type`.
- For each lambda, it recorded whether the lambda is a direct argument of `list-map`, `list-filter`, `list-fold` or `list-sort-by`. That is a checking position under the Pierce–Turner rule.
- For "called at two or more types", I took GHC's inferred types (`-ddump-types` on the emitted Haskell). For every untyped definition whose inferred type is polymorphic, I read its call sites.

**Result.**

| Measure | `.llmll` sources | JSON-AST sources |
|---|---|---|
| Definitions | 2,851 | 333 (including mirrors) |
| Definitions with an untyped parameter | 19, in 3 programs: tictactoe, life (`examples/life_sexp/main.llmll`, `examples/life_sexp/world.llmll`) | 7, all in `examples/life_json` |
| Untyped definition parameters | 19 | 7 |
| `letrec` with an untyped parameter | 0 | 0 |
| Lambdas with untyped parameters | 4 lambdas, 7 parameters (life `count-neighbors` and `render-world`; hangman `display-word` and `all-guessed?`) | 4 lambdas, 7 parameters (the JSON twins of the same programs) |
| Of those lambdas, in a checking position | **all** (`list-fold` 3, `list-map` 1, per source form) | **all** |
| Untyped lambdas in a synthesized position (the W8 form) | **0** | **0** |
| Untyped definitions called at two or more distinct types | **0** | **0** |

**How the last row was decided.**
- GHC infers a monomorphic type for 8 of the tictactoe definitions (for example `board_full' :: [String] -> Bool`).
- It infers a polymorphic type for the accessors (`state-board`, `state-turn`, `make-state`, `world-grid`, `world-width` and `world-height`), for `cell-at`, and for `never-done`.
- Each of those is called only on the program's own state or world value, or, for `never-done`, used once as `:done?`.

So every untyped parameter in the corpus has exactly one type in use. S0 loses no expressiveness that the corpus uses.

**Migration cost.** S0 needs:
- 26 annotations on definition parameters;
- no change to the 14 lambda parameters, which the Pierce–Turner rule admits;
- a schema version change, because the JSON documents of `examples/life_json` stop being readable without `param_type`.

## Options, ranked

### 1. Recommended: S0, explicit parameter types (with the built-in sets named)

**Surface.**
- `typed-param` is required for `def`, `def-shell` and `letrec`, as §12 already says.
- An untyped `fn` parameter is legal only in a checking position whose expected type is a known function type. The positions are an argument of `list-map`, `list-filter`, `list-fold` or `list-sort-by`, or an argument whose parameter type in a user signature is a `fn` type. Everywhere else it is the error `untyped-parameter` (W8).
- `Eq?` and `Ord?` appear in §3 as the names of the closed sets that `=`, `!=`, `list-contains`, `list-sort` and `list-sort-by` require. They have no syntax, and no inference attaches them to user definitions.

**Semantics.** §3.4.6 holds again without exception: type information enters only through annotations, holes and a known expected type. The wildcard `TCustom "_"` stops being a parameter type. It stays a type only where it already has another meaning (a missing return type, which `check` synthesizes).

**Migration in two releases.**
1. **Warning release.** A bare definition parameter is the warning `untyped-parameter`. When all call sites that `check` sees give the parameter the same type, the warning proposes that type in LLMLL's spelling. In all 26 corpus cases every call site uses one type (see "Measurement"), so a suggestion would exist for each; the warning text itself is not yet built or measured. Otherwise it names the call sites. `check` does not run GHC, so the suggestion comes from the call-site substitution and not from GHC's inferred type. This differs from the review on purpose.
2. **Removal release.** The warning becomes an error. `param_type` becomes required in `TypedParam`, the `untyped` flag is removed, and `schemaVersion` changes from 0.14.0 to 0.15.0. A document that omits `param_type` is no longer readable, so this change is not additive. The 7 JSON-source definitions in `examples/life_json` are migrated in the same change.

**Verification.** S0 adds no obligation, and it adds nothing to `Σ_auto` or the axiom set. It closes every row of F1 on the type channel. It keeps the AMBIG-TVAR-1 soundness argument valid, because user definitions stay monomorphic.

**One-shot.**
- Every type error is local to one written boundary (Wand, POPL 1986; Heeren, PhD thesis, 2005).
- A caller depends only on the callee's written signature, never on its body.
- The cost is one annotation per parameter. The corpus shows that authors already write one on 5,194 of 5,213 definition parameters in `.llmll` sources.

**Probe programs and DECIMAL-1.** No change: the probes used typed parameters, and DECIMAL-1 Layer 1 is `int`.

### 2. Ship with S0: document the explicit-dictionary idiom (option B)

There is no language change. Document three idioms:
- an order is a key function into O, as `list-sort-by` takes it, with a pair key for several fields;
- an equality is a projection to an `Eq?` type;
- a group of operations is a record of functions passed as an argument.

Name `def-interface` (§8.8) as the shape of such a record when the operations belong to a module.

Verification: a call through a function value is not reflected, so the caller falls back, as `list-map` with a lambda does today.

### 3. Trigger-gated: built-in declaration order for enums whose constructors take no arguments (option D-enum)

Such an enum would join O in declaration order.
- **Value.** The log analyser could sort a `Level` enum instead of level names as strings.
- **Cost 1.** It reverses COLLECT-ORDER-1's rule that the spec, not declaration order, defines the order.
- **Cost 2.** An enum in O still cannot be a map key, because keys are `{int,string}` (the verifier's array class). Most programs that sort an enum also key a map by it, so they still need a rank function.
- **Trigger.** A program where a hand-written rank key caused a defect.

### 4. Deferred: a type parameter on `def-interface`, verified by specialization (option I), re-costed

**Surface.** A `def-interface` gains a type parameter. An implementation becomes a named value, chosen explicitly at the use site in the Idris style. That removes the need for coherence. The professor's point holds: the method-signature form and the `:laws` channel already exist, so no new statement kind is needed for the interface itself.

**Partial rebuttal.** Two costs remain that Rev 0 counted and the review lowers:
- `def-interface` today is a structural signature that a **module** satisfies. It has one implementation per module and no instance value, so "named implementation" is new surface either way.
- LLMLL has **no type-variable syntax**. The parameter must be written in `Type` and in the JSON-AST. That is the larger schema change, and §3.4.6's "no global unification" then needs a rule for instantiating it.

**Verification: discipline (B), specialize then verify, with SPARK as the precedent.** After specialization the implementation is a known constant, its methods inline, and body-faithful reflection is kept.
- The evidence key is the **content hash of the specialized body**. It covers the definition's body and contract and, transitively, the body and contract of every implementation method reached. A key on the implementation's name would repeat the stale-evidence hazard.
- Polymorphic recursion and implementations stored in data must be forbidden, because specialization cannot remove them.
- Laws stay on `:laws`, tested by QuickCheck. A proof of a law is class (c), Lean only.
- Liquid Haskell, F\*, Lean and Dafny verify generically (discipline A). They are reference points for the laws, not precedents for (B).

**Trigger.** Two or more programs that need user-defined overloading over a user type.

### 5. Rejected for now: Haskell-style type classes (option H)

Option H has the costs of option 4, together with these:
- global coherence, or evidence keys over the elaborated body;
- constraint solving and defaulting for user classes, where AMBIG-TVAR-1's `()` default does not reach, which brings back the G3 class;
- the error messages with the longest repair distance in the Haskell tradition ("No instance", "Ambiguous type variable").

No probe program needed it.

### 6. Rejected: ML functors and modular implicits (options F and M)

§8 has no parameterized modules. Why3's `clone` is the nearest verified analogue, and it needs parameterized theories.

### 7. Rejected: S+, constraint inference onto untyped definitions (Rev 0's recommendation)

S+ is sound and principal on paper (Jones 1994; Odersky, Sulzmann and Wehr 1999; Standard ML equality types). In this compiler it needs:
- a Damas–Milner engine, which contradicts §3.4.6;
- an inferred scheme stored in `ModuleEnv`, whose acceptance depends on the callee's body;
- a constrained type that the surface, the JSON-AST and the diagnostics cannot write.

The agent's only repair would be to make the function monomorphic, which is S0 by hand. The measurement shows the corpus uses none of the polymorphism that S+ would keep.

### 8. Rejected: do nothing (option 0)

It keeps F1: P7, P8 and the type errors W1 to W10 stay GHC failures, and P9 stays a silent violation of §13.5.

## The verification argument (revised)

These facts apply to any option that lets a program define `=` or an order at a type.

1. **`=` stops being the solver's equality** at a type with a user equality. The laws (reflexivity, congruence) are quantified, so they are class (c) to prove. `:laws` gives them a `tested` path today (§8.8.1).
2. **A user order makes "sorted" rest on user code.** This is COLLECT-ORDER-1's argument against comparators.
3. **A dictionary is higher-order.** A call through it is not reflected, so the caller falls back, unless the code is specialized first (discipline B). Specialization keeps reflection.
4. **Evidence must cover what the body means.** An edit to an instance can change what an unedited body means. So the evidence key must cover the elaborated body, with dictionaries explicit, or the specialized body's content (option 4). Global coherence is one way to meet this requirement. Lean is incoherent by priority and still sound, because the instance is an explicit argument of every theorem.
5. **Match branch obligations are unaffected**, unless dictionaries are scrutinized.
6. **PBT parity needs a shared elaboration.** The evaluator in `compiler/src/LLMLL/Contracts.hs` has no types, so it needs dictionary elaboration shared with codegen. That is the PBT-EVAL-PARITY-1 failure class.

S0 avoids all six, because it adds no user instance.

## What a class system would also touch

- **Printing.** There is no generic printer: `int-to-string` is monomorphic, and `map-get` needs `Show k` only for its error text, at keys in `{int,string}`. No `Show?` set is needed. A future generic `to-string` builtin is the first trigger for a third set.
- **Hashing.** Maps are ordered `Data.Map`, not hash maps. No `Hash?` set is needed while keys are `{int,string}`. Admitting enums as keys (option 3) needs a change to the verifier's array class first, and that change is larger than a new set.
- **The numeric tower.** `+` is `int -> int -> int` and always reflects to QF-LIA. `FLOAT-OPS-1` is the first pressure for an overloaded `+`. The recommendation is separate operator names for `float`, as in OCaml's `+.`, so that the solver sort of a VC never depends on inference. `Eq?` contains `float` only because the finite-only rule of `FLOAT-OPS-1` excludes NaN; that dependency is recorded here. DECIMAL-1 Layer 1 is `int`-scaled and needs no class.
- **The `Ord?` and `=` agreement.** §13.5 states that "comparing equal coincides with `=`" on O. This is a built-in fact of O. Under any user-instance option it becomes an obligation for each instance.

## Edge cases and positive witnesses (S0)

1. **Positive witness, warning release:** `(def-shell id1 [x] x)` with the single call `(id1 "a")` gives the warning `untyped-parameter` and proposes `x: string`. Channel: type (warning). Cite: §12.
2. **Positive witness, removal release:** W1 and W6 are the error `untyped-parameter` at `inc1` and `id1`. Once annotated, W1's call `(inc1 "a")` is the ordinary error `type mismatch`. Channel: type.
3. **Positive witness, lambda rule:** W8, `(let [(f (fn [y] (+ y 1)))] …)`, is the error `untyped-parameter`, because `y` is in a synthesized position. Channel: type. Cite: the Pierce–Turner rule.
4. **Positive witness, checking position:** W10 is accepted syntactically, and the propagated type `string` for `y` makes `(+ y 1)` the error `type mismatch in '+'`, as the annotated form already is. Channel: type.
5. **Quiet:** the 8 corpus lambdas (life `count-neighbors` and `render-world`, hangman `display-word` and `all-guessed?`, in both source forms) stay legal and check against the propagated types. Channel: type.
6. **Constraint case:** P7 and P9 become ordinary `order-undefined` errors after annotation, because `srt [xs: list[Pt]]` or `[xs: list[float]]` reaches `checkOrdDefined` at a concrete type. P8 becomes `equality-undefined`. Channel: type.
7. **Unfixed element type:** `(srt (list-empty))` with `srt [xs: list[int]]` is fixed by the annotation. A body-local `(list-sort (list-empty))` builds only after AMBIG-TVAR-1 ships. On `7f5b6786` it still fails GHC. Channel: none, after AMBIG-TVAR-1.
8. **Missing return type:** it stays legal and synthesized. S0 removes the wildcard only as a parameter type. Channel: type.

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| A parameter annotation is present (S0) | type | none (syntactic) |
| The expected type is pushed into an untyped `fn` parameter | type | none (local type inference, §3.4.6) |
| `Eq?` and `Ord?` at a builtin call | type | none (closed predicates over finite type structure, unchanged) |
| Laws of a user implementation (option 4 only) | contract | class (c) to prove; `tested` through `:laws` |
| A call through a dictionary (options B, 4, 5) | contract | not reflected, so the caller falls back; reflected after specialization (option 4) |

S0 adds nothing to `Σ_auto`, nothing to the sealed-builtin axiom set, and no trust-report row.

## Affected surface (S0)

- **`LLMLL.md`**:
  - §3: a short note naming `Eq?` and `Ord?`;
  - §3.4.6: the Pierce–Turner rule for `fn`;
  - §12: a `fn` parameter production with the checking-position condition;
  - §13.4: the accessor example gains types.
- **`docs/getting-started.md`**: examples with bare parameters gain types.
- **`docs/llmll-ast.schema.json`**: in the removal release, `param_type` becomes required, `untyped` is removed, and `schemaVersion` becomes 0.15.0.
- **`compiler/src/LLMLL/Parser.hs`** and **`compiler/src/LLMLL/ParserJSON.hs`**: the bare-parameter path becomes a warning, then an error.
- **`compiler/src/LLMLL/TypeCheck.hs`**:
  - push the expected function type into lambda parameters (W10);
  - remove the parameter use of the wildcard from `structuralUnify` and `compatibleWith`.
- **`compiler/src/LLMLL/Module.hs`**: the same, in `compatibleTy`.
- **Examples:** the three affected programs (tictactoe and life in S-expression form, life in JSON form) gain 26 annotations.
- **Codegen, the verifier and the PBT evaluator:** no change.

## Risks and open questions

1. **The two-release migration delays the fix for P9.** Class: soundness (a spec violation that builds). P9 builds wrongly until the removal release. The warning release should name P9's pattern explicitly. A list sort through an untyped parameter can be detected only after annotation, so the warning is the mitigation. The effect complicates the plan; it does not block it.
2. **The non-additive schema change.** Class: scope. External JSON-AST producers that omit `param_type` break in the removal release. In the corpus, only `examples/life_json` does.
3. **The one-shot claims are hypotheses.** Class: verification-ergonomics. An experiment-lead MEASURE could compare first-attempt acceptance with and without the warning text.

## Open questions for the user (not for the professor)

1. **Adopt S0** as recommended, with option B documented alongside?
2. **The migration timeline:** one warning release, then removal? Or remove at once, because the corpus cost is 26 annotations in 3 programs and no external producer is known?
3. **The order of the rows:** fix W10 (pushing the expected type into lambdas) before or together with the warning release? W10 is an escape on its own, with no deprecation question.

None of these is a professor question. The review answered both Rev 0 questions, and the measurement it asked for is done.

## Hand-off

- **Proposal file:** `docs/design/type-classes-proposal.md`, Rev 1 DRAFT. The review is `docs/design/type-classes-review.md`, which is standalone and ready to fold when the user settles.
- **Candidate rows** (for the doc-lead after the user decides; not filed):
  - `UNTYPED-PARAM-ESCAPE-1` `[CT][SPEC]`: F1, with witnesses W1, W5, W6, W8, W10, P7, P8 and P9. It is a G3 defect whatever the decision, and P9 is a silent spec violation. The fix is S0 with the Pierce–Turner rule.
  - `PARAM-GRAMMAR-1` `[SPEC]`: F2, where §12 disagrees with the parser, the schema and §13.4. It closes with the S0 removal release.
- **Engineer summary (after the user settles):**
  - Warning release: the `untyped-parameter` warning with a type suggestion from the call sites, and expected-type propagation into lambda parameters.
  - Removal release: the error, `param_type` required, schema 0.15.0, the 26 corpus annotations, and removal of the parameter wildcard from unification in `TypeCheck.hs` and `Module.hs`.
  - No verifier or codegen change.
