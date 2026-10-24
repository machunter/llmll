---
title: AMBIG-TVAR-1 — an element type that nothing fixes, under Eq or Ord in the generated Haskell
status: Rev 0, SETTLED 2026-10-24 (language-team, at the user's request; option (a) chosen)
rows: AMBIG-TVAR-1 (DECIDE settled, moves to PLAN; row text corrected, see "Row corrections")
review: none
---

# AMBIG-TVAR-1 — an element type that nothing fixes, under Eq or Ord in the generated Haskell

## Decision

**Option (a).** `check` does not change. Every module that codegen emits enables GHC's `ExtendedDefaultRules`. GHC then instantiates a type variable that nothing fixes, and that carries only `Eq`, `Ord` or `Show`, at the unit type `()`. Option (b), a check-time refusal, is rejected.

The decision rests on three reasons.

1. **The program has a meaning, so a refusal would change the language.** §4.7 defines the value of `(= (list-empty) (list-empty))` as `true` and of `(list-length (list-sort (list-empty)))` as `0`. LLMLL has no type classes. The failure exists only in the generated Haskell. `LLMLL.md` §0 says that generated Haskell that evaluates differently from §4.7 is a defect in code generation. This is such a defect.
2. **The value cannot depend on the instance.** The argument is in "Soundness argument" below. It holds for every member of the class, including members the row does not name.
3. **GHC decides where the default applies.** The defaulting step runs at exactly the sites where GHC finds an ambiguity, and nowhere else. Option (b) needs a second inference engine in `check` that predicts GHC's ambiguity. Any difference between the two engines either keeps the defect or refuses a program that builds. Witnesses W8, W12 and W14 show three ways in which an annotation fixes the type at a distance.

## Restatement

A program can pass `check` and fail `build` with `Ambiguous type variable ‘a0’`. This happens when a builtin with a class constraint in the codegen preamble receives a type that nothing in the program fixes. The roadmap row (`docs/compiler-team-roadmap.md`, row `AMBIG-TVAR-1`, G3) offers two repairs. This record chooses one and corrects the row's description of the class.

## Context located

1. **`docs/compiler-team-roadmap.md`, row `AMBIG-TVAR-1`**: the two options, and the claim "the value cannot depend on it: every such list is empty".
2. **`docs/design/collect-order-1-proposal.md`**: the ordered types O and `order-undefined`.
3. **`compiler/src/LLMLL/TypeAdmissibility.hs`, `noOrdWitness`**: an unresolved type variable is lenient ("on the generic path's wildcard discipline"). This record makes that leniency correct by design: an unfixed type is instantiated at `()`, and its order is never observed.
4. **`compiler/src/LLMLL/TypeCheck.hs`, `checkOrdDefined` and `checkEqDefined`**: both read the substitution at the call site. Neither of them refuses an unresolved type variable.
5. **`compiler/src/LLMLL/CodegenHs.hs`, the preamble**. These signatures carry a class constraint:
   - `list_contains :: Eq a => …`
   - `list_sort :: Ord a => …`
   - `list_sort_by :: Ord k => …`
   - `map_has :: Ord k => …`
   - `map_get :: (Ord k, Show k) => …`
   - `map_put :: Ord k => …`
   - `wasi_http_response :: Integral i => …`

   `emitOp` lowers `=` and `!=` to the Haskell equality and inequality operators, which carry `Eq`. The two lists of module pragmas are in the preamble header and in the `Main.hs` harness header.
6. **`compiler/src/LLMLL/Contracts.hs`, `evalBuiltinApp` and `valueEq`**: the PBT evaluator has no types. It reduces `(list-sort nil)` to `nil` and `(= nil nil)` to `true`, so it already gives the values of §4.7.
7. **`LLMLL.md` §4.7**: "Constructors and the builtin containers are strict: they are built only from values." A `fn` body is evaluated only on application.
8. **`LLMLL.md` §0, the soundness boundary**: "GHC compiles the generated program, so its code generation is taken as faithful to the Haskell the compiler emits." `ExtendedDefaultRules` is a GHC feature inside that boundary.

## Homework: is "the value cannot depend on it" true?

**Method.** I built the compiler from this worktree at `03e7195e` (it reports v0.31.0). I ran `check` and `build --emit-only` on each witness. Then I type-checked the emitted `Lib.hs` with GHC 9.6.6 (resolver lts-22.43) twice: once as emitted, and once with `{-# LANGUAGE ExtendedDefaultRules #-}` added. I also compiled and ran a standalone Haskell copy of the preamble functions with the default enabled. I did not run `verify` or fixpoint.

**Result.** The row's reason ("every such list is empty") is too narrow. W20 holds a non-empty `Result`, and its value still does not depend on the instance. The correct statement and its proof follow.

### Soundness argument

Let `a` be a type variable that GHC reports as ambiguous in an expression `e`. Then `e` is well typed at every instance of `a` that satisfies the constraints. The constraints come only from `Eq`, `Ord` and `Show`.

1. **No value of type `a` exists at run time.** By §4.7, a container holds only values. A value of type `a` would need a source of type `a`. User definitions are monomorphic in `a`, because an ambiguous `a` occurs in no signature. FFI signatures are monomorphic. The polymorphic builtins (`list-empty`, `map-empty`, `ok`, `err`, `list-head`, `unwrap`) produce an `a` only from an input `a`, or produce none. The methods of `Eq`, `Ord` and `Show` consume values of `a` and never create one. By parametricity, every closed expression of type `a` fails or does not terminate.
2. **Call-by-value forces each such expression before the builtin runs.** §4.7 evaluates each argument to a value, and each constructor component to a value. Codegen realizes this with a bang-pattern `case` around each argument (EVAL-STRICT-1). So an expression of type `a` fails before any `Eq`, `Ord` or `Show` method sees it. Inside a key function the same holds: the key's components are forced in the lambda body (witness W18).
3. **Therefore no method of the chosen instance is ever applied to a value.** The comparison or sort reads only the parts of the structure that do not have type `a`: list spines, map spines, constructor tags, and components at fixed types. The result is the same for every instance. A failure, when there is one, happens before the method call, so it is also the same for every instance.

The instance `()` is a valid choice: it has `Eq`, `Ord` and `Show`. Its methods are strict, so even an unforced argument would fail as it does for a fixed type. I measured this: `compare undefined ()` and `undefined == ()` both fail.

### Every member of the class

| Member | Constraint in the preamble | In the row? |
|---|---|---|
| `list-sort` | `Ord a` | yes |
| `list-sort-by` | `Ord k` (the key type) | yes |
| `=` and `!=` | `Eq` at the whole argument type | yes |
| `list-contains` | `Eq a` | yes |
| `map-has`, `map-put` | `Ord k` | **no** |
| `map-get` | `Ord k` and `Show k` | **no** |
| `map-keys`, `map-entries`, `map-empty` | none | not members |
| `wasi.http.response` | `Integral i` | not a member: Haskell 2010 defaulting already resolves it, and its argument is an `int` |

**The `=` member covers any type that contains the unfixed variable.** Examples are a `Result` (W6, W20), a pair (W7), a nested list (W9) and a map (W15). The row names only lists.

**User functions with unannotated parameters are not members.** Codegen emits no signature for them, and GHC infers a constrained polymorphic type (W16 builds).

**PBT evaluator parity holds before and after the fix.** The evaluator in `compiler/src/LLMLL/Contracts.hs` has no types and computes the §4.7 value directly. A value of type `a` that fails at run time (for example `unwrap` of an `Error`) does not reduce in the evaluator, and the sample is discarded. That is the existing behaviour for `unwrap` at any type, so this record changes nothing there.

## Witnesses

All programs are one `def-shell` named `f` with no parameters. Each passes `check` at `03e7195e`.

- "GHC as emitted" is the result of type-checking the emitted `Lib.hs`.
- "With the default" is the same file with the pragma added. Every witness type-checks with it.
- "Value" is the result under §4.7, which the fixed build must produce.

| ID | Body (declared return) | GHC as emitted | Value |
|---|---|---|---|
| W1 | `(list-length (list-sort (list-empty)))` (int) | ambiguous `a0`, from `list_sort` | `0` |
| W2 | `(= (list-empty) (list-empty))` (bool) | ambiguous, from `==` | `true` |
| W3 | `(list-contains (list-empty) (unwrap (list-head (list-empty))))` (bool) | ambiguous, from `list_contains` | fails: `unwrap: list_head: empty list` |
| W4 | `(list-length (list-sort-by [1 2] (fn [x: int] (unwrap (list-head (list-empty))))))` (int) | ambiguous `k0`, from `list_sort_by` | fails in the key |
| W5 | `(list-length (map-keys (map-put (map-empty) (unwrap (list-head (list-empty))) 0)))` (int) | ambiguous, from `map_put` | fails before `map-put` |
| W6 | `(= (err "x") (err "x"))` (bool) | ambiguous, from `==` | `true` |
| W7 | `(= (pair (list-empty) 1) (pair (list-empty) 1))` (bool) | ambiguous, from `==` | `true` |
| W9 | `(!= [(list-empty)] [(list-empty)])` (bool) | ambiguous, from the inequality operator | `false` |
| W10 | `(map-has (map-empty) (unwrap (list-head (list-empty))))` (bool) | ambiguous `k0`, from `map_has` | fails before `map-has` |
| W13 | `(let [(e (list-empty))] (list-length (list-sort e)))` (int) | ambiguous, from `list_sort` | `0` |
| W15 | `(= (map-empty) (map-empty))` (bool) | ambiguous `k0`, from `==` | `true` |
| W18 | `(list-length (list-sort-by [1 2] (fn [x: int] (pair (unwrap (list-head (list-empty))) x))))` (int) | ambiguous, from `list_sort_by` | fails in the key |
| W19 | `(map-get (map-put (map-empty) (unwrap (list-head (list-empty))) 0) (unwrap (list-head (list-empty))))` (int) | ambiguous `k0`, from `map_put` | fails before `map-put` |
| W20 | `(= (ok 1) (ok 1))` (bool) | ambiguous `e0` (the error type), from `==` | `true`: a **non-empty** value |

**Quiet witnesses.** Each of these already builds, and its emitted code and value must not change.

| ID | Program | Why it builds |
|---|---|---|
| W8 | `(list-sort (list-empty))` with declared return `list[int]` | the return type fixes the element type |
| W12 | `(g (list-sort (list-empty)))`, where `g` takes `xs: list[int]` | a callee parameter fixes it |
| W14 | `(let [(e (list-sort (list-empty)))] e)` with return `list[int]` | the return fixes it through a `let` |
| W16 | `(def-shell eq [x y] (= x y))` called as `(eq 1 1)` | no signature is emitted, so GHC generalizes |

**Refused before codegen.** `(list-sort-by (list-empty) (fn [x: int] (list-empty)))` is `order-undefined` at key type `list[a]`, because `list` is not in O. This record does not change that.

**Runtime check (standalone copy of the preamble, default enabled).** W1 gives `0`. W2, W6 and the empty-map equality give `True`. A singleton list of an empty list sorts to length `1`. W3, W4 and W10 fail with `unwrap: list_head: empty list`. A numeric expression `show (2 ^ 10)` still gives `1024`, so numeric defaulting is unchanged.

## Design

**Spec text, for promotion into `LLMLL.md` §4.7** (spec register):

> **Types that nothing fixes.** A program can leave a type unfixed. Examples are the element type of a `(list-empty)` that is only compared or sorted, and the key type of a `(map-empty)` that is only compared. Such a type is not observable: no value of it can exist (§4.7 builds containers only from values, and no builtin makes a value of an unfixed type). The program is well typed and its value is defined. `check` accepts it, and `build` instantiates the type at `unit`. `(= (list-empty) (list-empty))` is `true`, and `(list-length (list-sort (list-empty)))` is `0`.

**Codegen rule.** Every Haskell module that codegen emits carries `ExtendedDefaultRules`. This includes the library module, the `Main.hs` harness and every per-module or FFI shim module. A pragma in each module header is preferred to a package-level `default-extensions` entry, because the module then states its own semantics when it is built outside the generated package.

**Why the default is conservative.** `ExtendedDefaultRules` adds `()` and the list type in front of the standard default list. It also relaxes the standard rule that requires a numeric class. Both changes act only on a type variable that is still ambiguous after inference. Before this change such a variable is a compile error. For a variable that standard defaulting already resolves, a numeric class is present, and neither `()` nor the list type has a numeric instance, so GHC picks the same type as before. Therefore:

- every program that builds today builds with the same types and the same behaviour;
- only programs that fail today with an ambiguity error change, and they now build.

**What does not change.** `check`, `checkOrdDefined`, `checkEqDefined`, `noOrdWitness`, the JSON-AST schema and FixpointEmit do not change.

## Edge cases

1. **A non-empty structure with an unfixed type (W20).** `(= (ok 1) (ok 1))` gives `true`. Channel: none at check time; codegen. Cite: Soundness argument, step 3.
2. **A failing value of an unfixed type (W3, W5, W10, W19).** The program builds and fails at run time with the same message that a fixed-type program gives. Channel: runtime failure (§4.7 "Failure"). Cite: Soundness argument, step 2.
3. **A key function that returns a failing value (W4, W18).** It fails during key evaluation for a non-empty list. With an empty list the key is never applied and the result is `[]`. Channel: runtime failure. Cite: §4.7, `fn` body.
4. **A type fixed at a distance (W8, W12, W14).** No defaulting happens, and the emitted code is unchanged. Channel: none. Cite: Codegen rule, conservativity.
5. **An unfixed type outside O inside a key (`list[a]`).** It stays `order-undefined`. Channel: type. Cite: `compiler/src/LLMLL/TypeCheck.hs`, `checkOrdDefined`.
6. **A program that GHC defaults today (a numeric literal under `show`).** The type is unchanged (Integer). Channel: none. Cite: Codegen rule. The engineer measures this on the existing build corpus.

## Verification mapping

The fix adds no proof obligation. No QF-LIA, nonlinear or Lean obligation exists to classify. No predicate reaches the solver, so `Σ_auto` and the sealed-builtin axiom set do not change.

| Concern | Channel | Fragment | Note |
|---|---|---|---|
| Acceptance of an unfixed type | type | none | `check` is unchanged and already accepts it |
| The value of a program with an unfixed type | none (semantics) | none | defined by §4.7; the instance cannot change it (Soundness argument) |
| The default instance | trust, existing boundary | none | a GHC feature inside the §0 code-generation boundary; no new trust-report row |
| PBT parity | contract (`tested`) | none | the evaluator has no types and already computes the §4.7 value |

## Rejected: option (b)

Option (b) refuses at `check` when no annotation in the enclosing definition fixes the type. It is rejected for four reasons:

1. It refuses programs whose value §4.7 defines (W1, W2, W20).
2. It needs `check` to reproduce GHC's inference for the whole definition. W8, W12 and W14 show three ways in which a type is fixed at a distance. `check` reads a substitution at each call site and does not solve for the whole definition.
3. Any difference between the two inference engines repeats the G3 failure or refuses a program that builds.
4. It gives an author a diagnostic about a type that has no observable effect.

## Row corrections

These corrections are for the doc-lead to make in the row text of `AMBIG-TVAR-1`:

1. The class also includes `map-has`, `map-put` and `map-get` (W5, W10, W19). `=` and `!=` are members at any type that contains the unfixed variable, not only lists (W6, W7, W15, W20).
2. "Every such list is empty" becomes "no value of the unfixed type exists at run time". W20 holds a non-empty `Result`.
3. The marker changes from DECIDE to PLAN.

## Hand-off

**Engineer.**
- Add `{-# LANGUAGE ExtendedDefaultRules #-}` to every module codegen emits: the preamble pragma list, the `Main.hs` harness header, and every other emitted module, including FFI shims.
- Make no change to `check`.
- Update the comment on `noOrdWitness` in `compiler/src/LLMLL/TypeAdmissibility.hs`. The leniency on a type variable is now correct by design, under this record.
- Add W1, W2, W3, W6, W9, W15 and W20 as build-and-run fixtures with the values in the witness table. Add W8, W12 and W14 as quiet fixtures whose emitted Haskell must not change apart from the pragma line.
- Measure the existing build-smoke corpus. Compile it with `-Wtype-defaults` with and without the pragma. The set of defaulting warnings must be identical. Do not run `verify` for this measurement.

**Doc-lead.**
- Promote the spec text under "Design" into `LLMLL.md` §4.7 after the engineer ships.
- Make the three row corrections in `docs/compiler-team-roadmap.md`, then close the row.
- Add one INDEX line for this record.
- Write a CHANGELOG entry saying that programs that failed GHC with an ambiguous type now build, and that no program that built before changes.
- There is no review file to fold.

## Open questions for the professor

None. The soundness argument rests on parametricity, the §4.7 evaluation rule and GHC's documented defaulting. The witnesses settle each step. No literature question changes the decision.
