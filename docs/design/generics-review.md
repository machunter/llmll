---
title: GENERICS — professor review of Rev 0
status: review of `generics-proposal.md` Rev 0 DRAFT (2026-10-24); standalone, not folded
reviewer: professor
---

# GENERICS — professor review of Rev 0

## Verdict

**Accept the design, at a smaller v1 scope, after five repairs.** The core is sound. Rigid type parameters, a closed constraint lattice, local type-argument synthesis and specialize-then-verify are an established combination. The proposal does not need a different tradition. It needs these changes:

1. Lower `key` to `(Ord k, Show k)`, not `Ord k`. As written, the P3 rewrite fails GHC (witness G1).
2. State rule 2 (no polymorphic recursion) over each strongly connected component of the call graph, not over a self-call.
3. Extend the evidence hash to the declarations of the type arguments, including alias expansions and refinement predicates.
4. Extend CTOR-FN-FIELD-1 to generic types, because `deriving (Eq, Show)` fails on a fixed function field (witness G2).
5. Correct witness 12. Its post proves at an uninterpreted sort as well, so it does not show what specialization adds.

The evidence supports a v1 with type parameters on `def-shell` only and no generic `type` declarations. Neither rewrite (P1, P3) uses a generic type or a generic `def`. Those two features carry most of the cost and all of the strict-core admission risk.

## Restatement

Rev 0 adds `:type-params` with constraints from `key ⇒ ord ⇒ eq` on `def`, `def-shell` and `type`. It checks a generic body once, with rigid parameters. It finds type arguments by one-way matching at each call. It verifies by specializing each used instantiation and emitting the copy unchanged. It keys evidence on the content hash of the specialized body. It emits polymorphic Haskell with derived `Eq` and `Ord`, and it adds one builtin, `compare`.

## Context located

1. `docs/design/generics-proposal.md` Rev 0, in this worktree.
2. The value probe run log, logs.md in the session scratchpad probe folder: P1 proves 0 of 5; P3 proves 1 of 6; witness w4 shows that a call through a function parameter falls back.
3. `compiler/src/LLMLL/CodegenHs.hs:574`: `map_get :: (Ord k, Show k) => …`. `:523`: `list_sort :: Ord a => …`. The preamble is already polymorphic with dictionaries.
4. `LLMLL.md` §0 (lines 11-22), anchors `nc-037` and `nc-038`: GHC is trusted, and "the verification conditions describe what they emit".
5. `LLMLL.md` §0, anchor `nc-007`: mutual recursion is allowed and verified by assume-guarantee.
6. `LLMLL.md` §13.6 (line 2881): `string-compare` returns exactly −1, 0 or 1, by code point, and 0 exactly when `=`.
7. `LLMLL.md` §13.5 (line 2854): the ordered types O; "comparing equal coincides with `=`".
8. `compiler/src/LLMLL/Diagnostic.hs:771`: the check-time gate "has no recorded verification" for a `def` callee.
9. `compiler/src/LLMLL/FixpointEmit.hs:3309` (`admissibleDatatype`): the datatype firewall that a specialized `Opt$int` must pass.
10. `docs/design/equality-capable-types-proposal.md` (CTOR-FN-FIELD-1): derive nothing for a type with a function field.
11. `docs/design/ambig-tvar-1-proposal.md`, soundness step 1.
12. `docs/design/type-classes-review.md`: discipline (B) and the content-hash key, which Rev 0 adopts.

## Witnesses (GHC 9.6.6, `-fno-code`, scratchpad `genrev/`)

| ID | Haskell | Result |
|---|---|---|
| G1 | the preamble `map_get :: (Ord k, Show k) => …`, called from `groupCount :: Ord k => Map.Map k [a] -> k -> Int` | `Could not deduce ‘Show k’ arising from a use of ‘map_get’ from the context: Ord k` |
| G2 | `data Box a = Box a (a -> a) deriving (Eq, Show)` | `Could not deduce ‘Eq (a -> a)’ arising from the second field of ‘Box’` |

G1 is the codegen that Rev 0 specifies for P3's `group-by` (`key` lowers to `Ord`), and `group-by` calls `map-get`. G2 is Rev 0's codegen rule ("a generic type becomes `data … deriving (Eq, Show)`") applied to a generic type with a function field. Both pass `check` under Rev 0 and fail `build`; that is the G3 class.

## Answer to question 1: is the hybrid v2 sound and established?

**Yes, it is sound, with three side conditions. The argument is the substitution property of many-sorted first-order validity, not parametricity.** A VC that is valid when `A` is an uninterpreted sort and `compare` an uninterpreted function is true in every structure. A concrete instance `T` gives one such structure: `A` is the carrier of `T`, `=` is equality on it, and `compare` is the order of §13.5. The instance VC is then true, provided that it is the substitution instance of the generic VC, possibly with more hypotheses. This is the reasoning that Dafny uses. Dafny verifies a generic method once, with each type parameter as an abstract type in its Boogie encoding, and `T(==)` lets ghost equality be the prover's equality (Leino, *Dafny: An Automatic Program Verifier for Functional Correctness*, LPAR 2010; Dafny Reference Manual, "Type parameters"). It is also the base case of Liquid Haskell's abstract refinements (Vazou, Rondon and Jhala, *Abstract Refinement Types*, ESOP 2013), where a property proved once at a type variable is instantiated at each use.

**Side condition 1: the emitter must commute with substitution.** The encoding of `f@[T]` must entail the encoding of `f` with `A := T`. Every operation on an `A` value in the generic body is `=`, `compare`, or passing the value along, so this holds if `=` at `T` is solver equality at `T`'s sort. That is true at `int`, `bool`, interned `string`, and admissible datatypes. At `list[…]` it is true in the standard model, where `Lst` is the set of lists. At `float` it needs FLOAT-OPS-1's canonical zero and no NaN. Add a test that the specialized and generic encodings agree on a battery of copies. That test is the evidence for this condition.

**Side condition 2: any axiom about `compare` must hold at every `ord` type.** With `compare` fully uninterpreted, the generic proof assumes nothing, and the condition is empty. A useful generic proof of an order property needs axioms such as the range {−1, 0, 1}, `compare x y = 0 ⇔ x = y`, antisymmetry and transitivity. §13.6 makes the first two true at `string`, and §13.5 states the second for all of O. Transitivity is a quantified axiom, so it leaves QF-LIA. It is sound but not decidable in Σ_auto. Keep v2 to the quantifier-free facts, as sealed axioms with a TRUST-AXIOM row.

**Side condition 3: refinement aliases as type arguments.** Rev 0 does not say whether `T` can be a refinement alias such as `PositiveInt`. If it can, `f@[PositiveInt]` has obligations at every `a`-typed result that the generic VC does not state. The abstract-refinement argument covers them: a generic body cannot create an `a` value, so every `a` result is an `a` input and carries its refinement. Rule 1 and the absence of class methods make that true. It is the same fact that AMBIG-TVAR-1 step 1 needs. State it once and cite it from both places, or refuse refinement aliases as type arguments in v1.

**What changes between `compare` unfolded at `int` and `compare` uninterpreted.** Mixing the two is sound. The unfolded `if`-term is one interpretation of the uninterpreted symbol, and it returns −1, 0 or 1. The difference is completeness. A post that depends on the order needs the unfolding (specialization) or the axioms (v2). A post that does not depend on the order proves generically. **Witness 12 is of the second kind.** `(if c x y)` satisfies `(or (= result x) (= result y))` for every `c`, so `pick` proves at an uninterpreted sort, and the claim "generic verification at an uninterpreted sort would lose that proof" is false for it. A correct witness has a post that mentions the order, for example `(<= (compare result y) 0)`.

**Which order to use.** At `string` and at any pair that contains `string`, `compare` is uninterpreted in both disciplines, so specialization never does better than the generic proof there. Specialization does better only at instances where `compare` unfolds: `int`, `bool`, and pairs of them. The hybrid should try the generic proof first. It should specialize only at interpreted-order instances where the generic proof failed. That bounds the specialization count by the number of distinct interpreted instances, not by all uses.

**Recommendation.** Adopt the hybrid in v2 under the three side conditions. Rev 0 already needs the uninterpreted-sort path for edge case 11 (an unfixed instantiation is "specialized at a fresh uninterpreted sort"). Either build that path in v1 and state its soundness by this argument, or specialize an unfixed instantiation at `int`. `int` is in O, has `eq`, and is a `key`, and the choice is sound because the type is unobservable.

## Answer to question 2: is polymorphic codegen faithful to specialized VCs?

**Yes, it is adequate. Do not monomorphize.** The argument is coherence of the dictionary-passing translation, not parametricity. Wadler and Blott (*How to Make Ad-hoc Polymorphism Less Ad Hoc*, POPL 1989) define the meaning of an overloaded program by its dictionary translation. Jones (*Coherence for Qualified Types*, Yale RR-989, 1993) proves that the meaning is unique when each type has at most one instance. LLMLL has no user instances, so `f d_T` is β-equivalent to the specialized `f@[T]`. GHC's own `SPECIALISE` rewrite relies on the same equivalence. Parametricity in the presence of `seq` is weaker (Johann and Voigtländer, *Free Theorems in the Presence of seq*, POPL 2004). The bang patterns of EVAL-STRICT-1 apply `seq` at type variables. Do not rest the argument on parametricity.

**The argument adds nothing new to the trusted base.** The preamble already runs `list_sort :: Ord a => …` and `map_get :: (Ord k, Show k) => …` with GHC dictionaries (`CodegenHs.hs:523`, `:574`). Every verified program that sorts already depends on this equivalence. So `nc-038` ("the verification conditions describe what they emit") already holds only up to dictionary elaboration. Amend `nc-038` to say so, and cite Wadler–Blott and Jones.

**The argument needs three facts, and Rev 0 states only the first.**

1. The derived instance at each type in O equals the spec's order. COLLECT-ORDER-1 established this. Haskell's `Ord String` is code-point lexicographic, which matches §13.6.
2. The generated `compare` builtin returns the `Integer` −1, 0 or 1, not Haskell's `Ordering`, and does not use the Prelude name. Rev 0 states the name rule; state the result type too.
3. Every class that a preamble function demands at a rigid parameter appears in the emitted context. G1 shows that this fails for `key`.

**Why not KaRaMeL-style monomorphization.** KaRaMeL monomorphizes because C has no polymorphism, not to make F\*'s soundness statement literal. F\* still trusts the extraction (Protzenko et al., *Verified Low-Level Programming Embedded in F\**, ICFP 2017). Monomorphized codegen would make §0 literal only for user generics, while the preamble stays polymorphic. It would also multiply code size by the instantiation count. Keep it as a fallback that is not built, and use it only if a non-derived instance ever appears.

## Gaps and hazards

Ordered by severity.

1. **`key` lowers to the wrong Haskell context.** Class: soundness (check against build), G3. Cite: `CodegenHs.hs:574`, witness G1, the P3 rewrite's `group-by`. This blocks the P3 rewrite. Repair: `key` lowers to `(Ord k, Show k)`. Better, derive each emitted context from the preamble signatures that the body reaches, so that a future preamble change cannot reopen this class.
2. **Rule 2 does not prevent polymorphic recursion through a cycle.** Class: totality (specialization may not terminate). Cite: Rev 0 rule 2; `LLMLL.md` `nc-007` (mutual recursion is allowed). Example: `f[a]` calls `g` at `list[a]`, and `g[b]` calls `f` at `b`. The rule as written accepts this, and specialization diverges. Repair: inside each strongly connected component of the call graph, every call passes the component's type parameters unchanged. Rust reports this case at its recursion limit. The .NET CLI specification (ECMA-335, Partition II, generics) forbids "expansive" instantiation cycles for the same reason. This blocks soundness of "the set is finite".
3. **The evidence hash does not cover the type arguments.** Class: soundness (stale evidence). Cite: Rev 0 "Verification" step 4. If the hash covers `f@[Task]` with the name `Task`, then an edit to `(type Task …)` or to an alias predicate leaves the old record valid. Repair: hash the expanded type arguments, including user type declarations and refinement predicates, transitively.
4. **Generic types break CTOR-FN-FIELD-1.** Class: soundness (check against build). Cite: witness G2; `equality-capable-types-proposal.md`. Equality capability of `Box[T]` now depends on `T` and on fixed fields. Repair: compute capability with each type parameter assumed capable. Emit `deriving` only if the fixed fields are capable. GHC's derived `Eq a => Eq (Opt a)` then handles the parameter. Also, `check` must refuse `=` at `Opt[(fn …)]` by the existing rule, with arguments substituted.
5. **Contract clauses need the same constraint test as the body.** Class: soundness (check against build). Cite: Rev 0 "Checking a generic body"; `--contracts=full` is the default and emits `post` as a run-time assertion. `(post (or (= result x) (= result y)))` with a bare `a` needs `Eq a` in Haskell. State that `pre`, `post` and `decreases` are checked with rigid parameters, so `constraint-missing` fires there too.
6. **"None lost" is true only for P1.** Class: verification ergonomics. Cite: probe w4; FN-PARAM-UF-1. P1 proved nothing before. In general, an `int` copy written with `<=` reflects. The generic copy written with a `key` function parameter falls back at the key call. Only `(a ord)` with `compare` applied directly keeps reflection at `int`. The surface steers agents to the key-function idiom (the P1 rewrite), so generics move code from verified to fallback until FN-PARAM-UF-1 lands. Say this in the summary, and teach `(a ord)` with direct `compare` as the first idiom.
7. **The strict-core admission gate.** Class: scope. Cite: `Diagnostic.hs:771`; Rev 0 risk 3. Moving admission from `check` to `verify` makes `def` conditional on a later run, and that weakens what `def` means. Two repairs exist. (a) Keep the gate at `check`: the instantiation set and the content hash are syntactic, so `check` can look up each instance's evidence in the sidecar. (b) Allow `:type-params` on `def-shell` only in v1. Every rewrite in the proposal is `def-shell`, so (b) costs nothing that the evidence shows. Recommend (b) now, and (a) when generic `def` arrives with v2.
8. **Non-regular recursive generic types.** Class: totality. A declaration such as `(type Nest :type-params [a] (| Leaf a) (| Node Nest[(a, a)]))` is a nested datatype (Bird and Meertens, *Nested Datatypes*, MPC 1998). Specializing it creates infinitely many mangled datatypes. Repair: a recursive use of a generic type inside its own declaration must pass its parameters unchanged. Or drop generic types from v1 (item 10).
9. **Pierce–Turner order for a parameter fixed only by a lambda result.** Class: ergonomic. Cite: Rev 0 "Instantiating at a call", step 3. In `pq-insert`, `k` occurs only in the return type of `key`. Step 3 checks lambdas "against the instantiated function types", but `k` is not yet instantiated. The rule must synthesize the lambda body with its parameter types known, and then fix `k`. This is the known incompleteness of local type inference, addressed by colored local type inference (Odersky, Zenger and Zenger, POPL 2001). State the order. State the error when a parameter is fixed only by an unannotated lambda parameter: `type-param-not-determined`, at the call.
10. **Generic type declarations are not supported by the evidence.** Class: scope. Neither rewrite uses `Opt` or `Queue`. Generic types bring items 4 and 8, mangled datatypes in `admissibleDatatype`, and the `args` field on `TypeNamed`. Defer them to a second row, with a trigger.
11. **The PBT lift key per instance.** Class: soundness of `tested`. Cite: `LLMLL.md` §4.4.4 (line 704), `pbt_witnesses` and `subject_key`. A property at `int` must lift only to `f@[int]`, never to `f@[string]` or to the generic `f`. Rev 0 does not say so. State that `subject_key` is the content hash of the specialized copy.

## Critique of the remaining points

- **The value case.** P1 was designed to need generics, so it is a selected witness, not a measurement. P3 saves 10 of 185 lines. The corpus shows no demand, and Rev 0 says so plainly. The cost of the full scope is a schema change, a new `Type` constructor, type application, a specialization engine, mangling, a new evidence key and a new builtin. That cost is not justified by this evidence. The v1 scope in "Recommendation" removes about half of it, and the MEASURE in risk 1 then decides on the rest.
- **The `key` constraint.** It turns an implementation limit, the verifier's array class `{int, string}`, into a surface constraint. That is acceptable, because widening it later (D3) only accepts more programs. Its lowering is wrong (item 1). Its semantics should be stated as "the map-key class of §13.12, whatever it is", so that D3 does not need a new constraint name.
- **Specialization blow-up.** It is bounded by the reachable instantiation set once item 2 is fixed. It can still grow exponentially in nesting depth, for example when each level instantiates the next at a pair of its own parameters. The v2 order in question 1 reduces the count to the interpreted-order instances. Report the instantiation count in `verify` output, so that growth is visible.
- **Interaction with S0.** Sequence S0 first. Before S0 the checker has three "type variable" notions: `TCustom "_"`, the per-call `TVar` and the new rigid parameter. A generic body that receives an untyped argument would then mix a rigid parameter with the dynamic wildcard, and the constraint test would read the wildcard leniently. Make GENERICS-1 depend on the S0 row. Number the schema versions in landing order.
- **AMBIG-TVAR-1.** The generalized step 1 ("no definition creates a value of a type variable from nothing") is correct under rule 1. It is the same fact as side condition 3 above. Edge case 11 is mostly a non-case, because `pq-show`'s `show` argument usually fixes `a`. Use `(pq-sorted? key (list-empty))` with a generic `key` as the witness.
- **Equality on `Opt[a]` in the solver.** A specialized `Opt$T` uses datatype equality, which is structural. That matches the derived `Eq` if equality at `T` is solver equality (side condition 1). At `T = list[…]`, two lists with equal contents may be distinct `Lst` terms in some models. That makes the solver incomplete, not unsound.
- **Generic types in contracts and measures.** `listLen` is defined on `Lst` for every element type, so measures need no change. A user measure over a generic type is not addressed; defer it with generic types (item 10).

## Recommendation

1. **v1 = GENERICS-1, reduced.** Allow `:type-params` on `def-shell` only. Allow constraints `eq`, `ord` and `key`, rigid checking, Pierce–Turner synthesis with the stated lambda order, `compare`, specialize-then-verify, and polymorphic codegen. Do not include generic `type` declarations or generic `def`.
2. **Apply the five repairs in the verdict.** Fix the `key` lowering to `(Ord k, Show k)`. Apply rule 2 per strongly connected component. Hash the expanded type arguments into the evidence key. Apply the constraint test to contract clauses. Correct witness 12.
3. **Codegen stays polymorphic.** Amend `LLMLL.md` `nc-038` to say that the VCs describe the emitted program up to dictionary elaboration with one instance per type. Cite Wadler–Blott 1989 and Jones 1993.
4. **v2 = the hybrid.** Try the generic proof first, at an uninterpreted sort with quantifier-free `compare` axioms. Specialize only at interpreted-order instances where the generic proof fails. Add generic `def` with the check-time gate keyed per instance.
5. **GENERIC-TYPES-1, trigger-gated.** Add generic type declarations, with the CTOR-FN-FIELD-1 extension and the regular-recursion rule. Trigger: a program that needs `Opt[a]` or a generic tree.
6. **Sequence after S0** in the type-classes record.

## Open questions for the language-team

1. Can a type argument be a refinement alias? If yes, state the abstract-refinement argument (side condition 3) and its tie to AMBIG-TVAR-1 step 1. If no, name the error.
2. Give the exact order of Pierce–Turner synthesis when a type parameter occurs only in a function argument's result type, as `k` does in `pq-insert`. Give the error when no order fixes it.
