---
title: GENERICS — user type parameters on def-shell (v1), with generic def and generic types deferred
status: Rev 1 SETTLED, 2026-10-24. The user decided: (1) v1 scope accepted, `:type-params` on def-shell only, no generic types, no generic def; (2) S0 stays an unsettled draft, and GENERICS-1 lands with the local guard of rule 5, with no dependency on S0; (3) FN-PARAM-UF-1 lands before GENERICS-1.
rows: GENERICS-1 and GENERIC-COMPARE-1 (G7, PLAN), GENERICS-2 (G7, DECIDE), GENERIC-TYPES-1 (Trigger-gated Parking Lot); filed by the doc-lead from "Hand-off"
review: docs/design/generics-review.md (professor, of Rev 0); standalone, folded by the doc-lead at settlement
---

# GENERICS — user type parameters on def-shell (v1)

## Decisions

The user settled Rev 1 on 2026-10-24. No design changed at settlement.

1. **The v1 scope is accepted.** `:type-params` is allowed on `def-shell` only. Generic type declarations (`GENERIC-TYPES-1`) and generic `def` (`GENERICS-2`) are deferred.
2. **S0 is not settled and stays a draft.** GENERICS-1 lands with the local guard of rule 5, and it has no dependency on S0. The guard is: every parameter of a generic `def-shell` is typed, and an untyped argument at a generic call is the error `untyped-arg-to-generic`. If S0 lands later, the guard becomes redundant, and it can stay or be removed.
3. **FN-PARAM-UF-1 lands before GENERICS-1.** The key-function idiom therefore loses no reflection when generics ship. This record depends only on that ordering, not on the details of the FN-PARAM-UF-1 design record, which is still in progress.

## Summary

**v1 (`GENERICS-1` and `GENERIC-COMPARE-1`).**

- **Declaring.** A `def-shell` can declare type parameters in a `:type-params` clause.
- **Constraints.** A type parameter carries at most one constraint, `eq`, `ord` or `key`. The sets are closed and built in; there are no user instances.
- **Rigid checking.** A generic body and its contract are checked once, with each type parameter rigid.
- **Local instantiation.** Type arguments are synthesized at each call, in a stated order (local type inference with the colored extension for lambda results).
- **One new builtin, `compare`.**
- **Verification.** It specializes each used instantiation and then verifies the copy (SPARK discipline). Evidence is keyed on the content hash of the copy *with its type arguments expanded*.
- **Codegen.** It stays polymorphic. Each Haskell context is derived from the preamble signatures that the body reaches.

**Deferred.**
- **v2 (`GENERICS-2`):** generic `def`, with a check-time admission gate per instance, and the hybrid that tries a generic proof first.
- **Trigger-gated (`GENERIC-TYPES-1`):** generic `type` declarations, with the CTOR-FN-FIELD-1 extension and a regular-recursion rule.

**Value.** The P1 queue section goes from 13 definitions and 91 lines to 4 and 27. P3 saves 10 of 185 lines. The corpus shows no demand; this is stated as a risk, with a MEASURE.

**Verification, stated honestly (review finding 6).**
- A generic `(a ord)` function that applies `compare` directly keeps reflection at `int` after specialization.
- A generic function that takes a key or comparator **function** falls back at that call until FN-PARAM-UF-1 lands.
- The P1 rewrite uses the key form. P1 proved nothing before, so it loses nothing. In general, though, the key idiom moves code from reflected to fallback.
- v1 therefore teaches `(a ord)` with direct `compare` as the first idiom, and the key form as the second.

## Changes from Rev 0

| Review item | Disposition | Where |
|---|---|---|
| Verdict 1 / gap 1: `key` lowers to the wrong context (witness G1) | **Adopted, in the stronger form.** Each emitted context is derived from the preamble signatures the body and contract reach, not from the declared constraint. `key` reaching `map-get` emits `(Ord k, Show k)`. The declared constraint must entail every derived class. | "Codegen" |
| Verdict 2 / gap 2: rule 2 over strongly connected components | **Adopted**, with a positive witness. | "Rules", edge case 4 |
| Verdict 3 / gap 3: hash the expanded type arguments | **Adopted.** It covers user type declarations, alias expansions and refinement predicates, transitively. | "Verification" step 4 |
| Verdict 4 / gap 4: CTOR-FN-FIELD-1 for generic types (witness G2) | **Adopted into `GENERIC-TYPES-1`**, which leaves v1 together with generic types. | "Deferred" |
| Verdict 5: witness 12 proves at an uninterpreted sort too | **Adopted.** The new witness has a post that mentions the order, and it needs reflexivity of `compare`. It proves only after specialization at `int`. | edge case 12 |
| Gap 5: the constraint test on contract clauses | **Adopted.** `pre`, `post` and `decreases` are checked with rigid parameters. | "Checking a generic definition" |
| Gap 6: "none lost" holds only for P1 | **Adopted.** See the summary and "Idioms". | "Idioms" |
| Gap 7: strict-core admission | **Adopted, as option (b).** `:type-params` is allowed on `def-shell` only in v1. Option (a), a check-time gate keyed per instance, comes with generic `def` in v2. | "Deferred" |
| Gap 8: nested (non-regular) generic types | **Adopted into `GENERIC-TYPES-1`** as the regular-recursion rule. | "Deferred" |
| Gap 9 and question 2: the synthesis order when a parameter occurs only in a lambda's result | **Answered.** | "Instantiating at a call" |
| Gap 10: defer generic type declarations | **Adopted.** | "Deferred" |
| Gap 11: PBT lift per instance | **Adopted.** `subject_key` is the content hash of the specialized copy. | "Testing" |
| Question 1: refinement aliases as type arguments | **Answered: allowed in v1, with a different argument from the review.** Specialization makes every refinement obligation explicit in the copy, so v1 does not need the abstract-refinement argument. v2 does need it. | "Refinement aliases as type arguments" |
| Q2 answer: amend `nc-038` (Wadler–Blott, Jones) | **Adopted**, with draft text. | "Codegen" |
| Q1 answer: an unfixed instantiation | **Adopted.** It is specialized at `int` in v1, not at an uninterpreted sort. | "Verification" step 6 |
| Sequence after S0 | **Superseded at settlement (decision 2):** no dependency on S0; the local guard of rule 5 is enough. | "Dependency on S0" |
| `key` as "the §13.12 map-key class, whatever it is" | **Adopted.** | "Surface" |
| Report instantiation counts in `verify` output | **Adopted.** | "Verification" step 7 |

## Restatement

The probe found that the gap is generics, not overloading. A function over "a list of ordered things" must be written once per element type. Rev 1 answers the review: a smaller v1, five repairs, and two questions answered.

**Reference classes.**
- **Measurement set:** agents writing programs (the one-shot criterion in `docs/compiler-team-roadmap.md`).
- **Design-reference set:** Liquid Haskell, F\*, Dafny, Idris, Lean and SPARK (see "Design-reference set").

## Context located

1. **Value probe, 2026-10-24** (session scratchpad): P1, the priority queue; P3, the log analyser; witness w4 (a call through a function parameter falls back).
2. **`docs/design/generics-review.md`**: the professor's review of Rev 0, with GHC witnesses G1 and G2.
3. **`docs/design/type-classes-proposal.md` Rev 1** (draft, on main): S0, which makes parameter types explicit. **Not settled.**
4. **`docs/design/ambig-tvar-1-proposal.md`**: an unfixed type is unobservable. Soundness step 1 assumes that no definition creates a value of a type variable from nothing.
5. **`docs/design/collect-order-1-proposal.md`**: the ordered types O, and why `<` stays int-only.
6. **`docs/design/equality-capable-types-proposal.md`**: CTOR-FN-FIELD-1, which `GENERIC-TYPES-1` must extend.
7. **`LLMLL.md` §0**: anchor `nc-038`, "the verification conditions describe what they emit". Anchor `nc-007`: mutual recursion is allowed.
8. **`LLMLL.md` §3.4.1 and §3.4.6**: refinement-alias introduction and elimination; local inference with per-call-site instantiation and no global unification.
9. **`compiler/src/LLMLL/CodegenHs.hs`**: the preamble is already polymorphic with dictionaries (`list_sort :: Ord a => …`, `map_get :: (Ord k, Show k) => …`).
10. **`compiler/src/LLMLL/FixpointEmit.hs`**: `augmentContractPre` and `augmentContractPost` fold refinement-alias predicates of the parameters and return into the effective contract, and that contract enters the evidence key.
11. **`compiler/src/LLMLL/TypeCheck.hs`**: `freshenFnType` and the per-call-site substitution; `checkEqDefined` and `checkOrdDefined`.
12. **`compiler/src/LLMLL/TypeAdmissibility.hs`**: `noEqWitness` and `noOrdWitness`. Both are lenient on `TVar`, which a rigid parameter must not inherit.
13. **`compiler/src/LLMLL/Contracts.hs`**: the untyped PBT evaluator.
14. **`docs/llmll-ast.schema.json`**: version 0.14.0. There is no type-variable kind.

## Evidence (unchanged from Rev 0, re-scoped)

| Program | Today | Under v1 |
|---|---|---|
| P1 priority queue at `int`, `string` and `Task` | 13 queue definitions, 91 code lines | 4 generic `def-shell`s, 27 lines. The file goes from 168 to about 105 lines |
| P3 log analyser | `group-by-string` and `group-by-int`; `show-groups-s` and `show-groups-i` | `group-by` and `show-groups`. The file goes from 185 to 175 lines |

**Counter-evidence.**
- A clone scan of the corpus (bodies compared with types erased) found 5 families, all one-line record accessors in `tools/llmll-driver/sequencer.llmll`. Records would fix those, not generics.
- The type-classes Rev 1 measurement found no untyped parameter used at two types.
- The review is right that P1 is a selected witness, not a measurement.

v1 is about half the cost of Rev 0's scope. Under v1 neither rewrite needs a generic type or a generic `def`.

## Design proposal (v1)

### Surface

```lisp
(def-shell pick-min :type-params [(a ord)] [x: a y: a] -> a
  (post (<= (compare result y) 0))
  (if (<= (compare x y) 0) x y))
```

**The `:type-params` clause.**
- It is allowed **only on `def-shell`** in v1. On `def`, `type`, `letrec` or `def-interface` it is the error `type-params-not-supported`, naming `GENERICS-2` or `GENERIC-TYPES-1`.
- **An entry** is a bare lowercase name, or `(name constraint)`.
- **A name** must not be a primitive type name or a user type name (`type-param-shadow`).
- **Scope:** value-parameter types, the return type, `pre`, `post`, `decreases`, and every annotation in the body.

**Constraints**, which form the lattice `key ⇒ ord ⇒ eq`:
- `eq`: the type has `=` (§13.2; the CTOR-FN-FIELD-1 walk and `mentionsJson` find nothing);
- `ord`: the type is in O (§13.5);
- `key`: the type is in **the map-key class of §13.12, whatever that class is**. Today that is `{int, string}`. If D3 widens the class, `key` widens with it and keeps its name.

A bare name allows only passing, storing and returning.

**`compare`** (`GENERIC-COMPARE-1`):

| Name | Signature | Constraint | Semantics | Generated Haskell |
|---|---|---|---|---|
| `compare` | `a a -> int` | `a` is `ord` | -1, 0 or 1 by the order on O: numeric at `int`; `false < true` at `bool`; `string-compare` at `string`; lexicographic at a pair. `(compare x y) = 0` exactly when `(= x y)` (§13.5). | `llmll_compare :: Ord a => a -> a -> Integer`. It returns an `Integer`, not Haskell's `Ordering`, and does not use the Prelude name. |

**JSON-AST.**
- The version increases by one minor step, numbered in landing order relative to S0.
- `def-shell` gains an optional `type_params`. Each entry is `{ "name": "a" }` or `{ "name": "k", "constraint": "ord" }`, where `constraint` is one of `eq`, `ord` or `key`.
- `Type` gains the kind `{ "kind": "type-var", "name": "a" }`.
- No `args` on `TypeNamed` in v1; that moves to `GENERIC-TYPES-1`.
- Both additions are optional, so the change is additive.

### Rules

1. **Determined.** Every type parameter occurs in at least one value-parameter type (`type-param-not-determined`). There is no syntax for explicit instantiation.
2. **Regular recursion, per strongly connected component.** In each strongly connected component of the call graph, every call between members passes the component's type parameters unchanged (`polymorphic-recursion`). The component is the one that the trust report already computes for termination. This bounds the instantiation set. The rule follows ECMA-335 Partition II, which forbids expansive generic cycles, and Rust's recursion limit reports the same case.
3. **`for-all`.** No type parameter in a `for-all` binding (`for-all-type-param`).
4. **FFI.** No type parameter in a value passed to or from a Tier 1 import (`ffi-type-param`).
5. **Untyped parameters.** Every parameter of a generic `def-shell` carries a type. No argument to a generic call may synthesize to the untyped wildcard (`untyped-arg-to-generic`). See "Dependency on S0".

### Checking a generic definition

- **Rigid parameters.** A type parameter is rigid: it is a new type constructor that unifies only with itself. `TVar` keeps its meaning as a placeholder at a call. The CTOR-FN-FIELD-1 walk, `noOrdWitness` and the key test read a rigid parameter by its declared constraint, never leniently.
- **The whole definition is checked**: the body, and `pre`, `post` and `decreases`. A `post` is a run-time assertion under the default `--contracts=full`, so `(post (= result x))` at a bare `a` needs `eq`. Without it, the error is `constraint-missing`, on the clause.
- Errors stay inside the definition, which is checked once.

### Instantiating at a call (answer to review question 2)

At `(f e1 … en)`, the checker takes the arguments in this order. Steps 3 and 4 are the colored local type inference refinement (Odersky, Zenger and Zenger, POPL 2001) of Pierce–Turner.

1. **Synthesize** every argument that is not a lambda. A named function passed as a value (`task-prio`) is synthesized like a variable.
2. **Match** these types one way against `f`'s parameter types. This fixes some type parameters. Matching never binds a variable of the caller.
3. **Check each lambda whose parameter types are all known**, in argument order. A parameter type is known if it is annotated, or fixed by step 2, or fixed by an earlier lambda in this step.
   - Synthesize the lambda body with those parameter types.
   - Match its result type against the expected result.
   - This fixes a parameter that occurs only in a function's result, such as `k` in `pq-insert`'s `key: (fn [a] -> k)`.
   - Repeat step 3 until no lambda changes anything. This takes at most as many rounds as there are lambdas.
4. **If a lambda remains** whose parameter type is still unfixed and unannotated, the call is the error `type-param-not-determined`. It is reported at the call, naming the type parameter and the lambda. The hint asks for an annotation on the lambda parameter.
5. **Test each declared constraint** on its type argument:
   - a concrete type is tested with the existing walks (`order-undefined`, `equality-undefined`, `map-key-undefined`), and the message names the instantiation;
   - a rigid parameter of the enclosing generic satisfies the constraint when its own constraint entails it.
6. **A type parameter that stays unfixed** with no lambda depending on it, for example from `(list-empty)`, is legal and unobservable (AMBIG-TVAR-1).

### Refinement aliases as type arguments (answer to review question 1)

**Allowed in v1.** At `(pick-min p q)` with `p q : PositiveInt`, step 2 binds `a := PositiveInt`.

The specialized copy `pick-min@[PositiveInt]` has `x`, `y` and `result` of type `PositiveInt`. `augmentContractPre` adds `x > 0 ∧ y > 0` to the effective `pre`, as an assumption (elimination, §3.4.1). `augmentContractPost` adds `result > 0` to the effective `post`, as an obligation (introduction).

The copy therefore **states** every refinement obligation that the generic body does not. Specialization verifies it like any other post, so v1 needs no abstract-refinement argument. Here the obligation proves, because each branch returns `x` or `y`.

The review's argument is still needed for **v2's** generic-proof path: a generic body cannot create an `a`, so every `a` result is an `a` input and carries its refinement. That is the same fact as AMBIG-TVAR-1 step 1 and rule 1, and v2 states it once and cites it from both places.

The predicate enters the evidence hash (step 4 below).

### Verification: specialize, then verify (discipline B)

1. **Instantiation set.** Walk from every non-generic definition through its calls, and collect the pairs (generic `def-shell`, expanded type arguments). By rule 2 the set is finite. Depth can still grow it, so step 7 reports the count.
2. **Specialization.** Substitute in parameters, return, `pre`, `post`, `decreases` and annotations. A call to another generic goes to its specialized copy.
3. **Emission.** The copy goes through the emitter unchanged, so it verifies exactly as a hand-written copy would.
   - `compare` at `int` unfolds to `(if (< a b) -1 (if (= a b) 0 1))` and stays QF-LIA.
   - At `bool`, and at pairs of `int` and `bool`, it unfolds to the composition.
   - At `string`, or at a pair containing `string`, it is uninterpreted, and the caller falls back.
4. **The evidence key** is the content hash of the copy, covering:
   - the copy's body and effective contract after substitution;
   - the **expanded type arguments**: each user type declaration the arguments name, each alias expansion, and each refinement predicate, transitively;
   - transitively, the same for every specialized callee.

   An edit to `(type Task …)` or to an alias predicate changes the key.
5. **Reporting.** The trust report lists `f@[T…]` under the source definition. TRUST-AXIOM rows name the copy, and the sealed-builtin axiom set does not change.
6. **An unfixed instantiation** is specialized at `int`. `int` satisfies `key`, and so `ord` and `eq`. The choice is sound because the type is unobservable (AMBIG-TVAR-1). GHC defaults the running program to `()`. The two choices differ only on a type no value inhabits. v1 builds no uninterpreted-sort path.
7. **`verify` output** prints the instantiation count for each generic definition and in total, for example `generics: 3 definitions, 7 instances`.
8. **Uninstantiated generic:** it gets no evidence and the label `unverified (generic, not instantiated)`.
9. **Cross-module:** specialized and verified in the importing module's run, and stored in its sidecar under the content hash.

### Testing

- PBT tests a generic at concrete instantiations (rule 3).
- A property's `subject_key` for a generic subject is the **content hash of the specialized copy** it calls. `tested` lifts only to `f@[int]`, never to `f@[string]` or to `f`.
- The evaluator in `compiler/src/LLMLL/Contracts.hs` has no types and needs none. No operation dispatches on a type, so erasure gives parity. `compare` gets one evaluator arm through `OrdK`.

### Codegen

**Polymorphic Haskell.** A type parameter becomes a Haskell type variable. **The context is derived, not declared.** It is the union of the classes that the preamble signatures reached by the body and contract demand at that parameter:
- `=` gives `Eq`;
- `list-sort` and `compare` give `Ord`;
- `map-get` gives `Ord` and `Show`;
- likewise for every other preamble function.

A test pins the derivation against the preamble signatures. This closes witness G1 for every future preamble change. `check` already guarantees that the declared constraint entails each derived class. A derived class that the declared constraint does not entail is a compiler defect, and the build stops with an internal error.

**The `nc-038` amendment** (draft text for the doc-lead, for `LLMLL.md` §0):

> `CodegenHs` and the codegen preamble produce that program, so the verification conditions describe what they emit, up to dictionary elaboration: a function polymorphic in a type parameter, or a polymorphic preamble function, runs with GHC's dictionary for the instantiating type, and each type has exactly one instance, the derived one, whose behaviour this specification defines. Under that condition the dictionary-passing program is equivalent to the specialized program that the verifier checks (Wadler and Blott, *How to Make Ad-hoc Polymorphism Less Ad Hoc*, POPL 1989; Jones, *Coherence for Qualified Types*, Yale RR-989, 1993).

**The three facts the equivalence needs:**
1. the derived `Ord` at each type in O is the spec's order (COLLECT-ORDER-1);
2. `llmll_compare` returns the `Integer` -1, 0 or 1;
3. the derived contexts cover every class reached.

**The argument is coherence, not parametricity.** The bang patterns of EVAL-STRICT-1 apply `seq` at type variables, and that weakens parametricity (Johann and Voigtländer, POPL 2004). The preamble already relies on this equivalence for `list-sort`, so the amendment adds nothing to the trusted base. Monomorphized codegen is a fallback that is not built, used only if a non-derived instance ever appears.

### Idioms (review finding 6)

**First idiom: `(a ord)` with `compare` applied directly.** It keeps reflection at `int`, and edge case 12 shows that it proves. Use it when the element's own order is the wanted order:

```lisp
(def-shell sorted-insert :type-params [(a ord)] [x: a q: list[a]] -> list[a] …)
```

**Second idiom: a key function into O.** Use it when the order is a projection, such as a Task by priority. The call `(key x)` goes through a function parameter, so it falls back until FN-PARAM-UF-1 lands. P1's Task queue needs this form; its `int` and `string` queues could use the first.

**Option B (an explicit comparator)** stays documented. It is no longer the way to share code across types.

### Dependency on S0

**Settled (decision 2): GENERICS-1 does not depend on S0.** Without S0, the checker has three type-variable notions: `TCustom "_"`, the per-call `TVar` and the rigid parameter. Mixing the wildcard with a rigid parameter is what the review warns about. GENERICS-1 closes that hazard with rule 5 as a **local guard**:
- every parameter of a generic `def-shell` carries a type, which is S0 inside generic definitions only;
- an argument at a generic call that synthesizes to `TCustom "_"` is the error `untyped-arg-to-generic`.

The wildcard then never meets a rigid parameter or a constraint test, so the hazard is closed without S0's corpus migration. The rest of the corpus keeps the escape that type-classes Rev 1 reports, and that escape stays S0's business.

This differs from the review's "make GENERICS-1 depend on the S0 row". A hard dependency would let an unrelated decision block this row, and the guard is enough for soundness.

**Note.** If S0 lands later, rule 5's guard becomes redundant: every parameter is typed, and the wildcard no longer exists as a parameter type.

### Deferred

**`GENERICS-2`, v2.**
- Generic `def`, with a **check-time** admission gate keyed per instance (review option a). The instantiation set and the content hash are syntactic, so `check` can look up each instance's evidence in the sidecar.
- The hybrid: try one generic proof first, at an uninterpreted sort, with quantifier-free `compare` facts as sealed axioms under TRUST-AXIOM rows (the range −1 to 1, and `compare x y = 0 ⇔ x = y`). Specialize only at instances where `compare` unfolds and the generic proof failed.
- The hybrid needs the review's three side conditions:
  1. the emitter commutes with substitution, shown by a battery test that compares the specialized and generic encodings;
  2. every axiom holds at every `ord` type;
  3. the abstract-refinement argument for alias arguments.

**`GENERIC-TYPES-1`, trigger-gated.** It adds generic `type` declarations, the `args` field on `TypeNamed`, and type application `Name[T…]`. It needs two extra rules:
- **The CTOR-FN-FIELD-1 extension (witness G2).** Compute equality capability with each type parameter assumed capable. Emit `deriving (Eq, Show)` only if the fixed fields are capable, and let GHC's `Eq a => Eq (Opt a)` handle the parameter. Refuse `=` at `Opt[(fn …)]` by the existing rule, with the arguments substituted.
- **Regular recursion for types.** A recursive use of a generic type inside its own declaration passes its parameters unchanged. This refuses nested datatypes (Bird and Meertens, MPC 1998), whose specialization would never terminate.

Trigger: a program that needs `Opt[a]`, a generic tree or a generic queue type.

## P1 and P3 rewritten (v1)

### P1

The queue section uses the key idiom, because the Task queue orders by priority:

```lisp
(def-shell pq-insert :type-params [a (k ord)]
    [key: (fn [a] -> k) x: a q: list[a]] -> list[a]
  (post (= (list-length result) (+ (list-length q) 1)))
  (decreases (list-length q))
  (match (list-head q)
    ((Success h)
      (if (<= (compare (key x) (key h)) 0)
          (list-prepend x q)
          (match (list-tail q)
            ((Success t) (list-prepend h (pq-insert key x t)))
            ((Error e) (list-prepend x q)))))
    ((Error e) (list-prepend x q))))

(def-shell pq-from-list :type-params [a (k ord)] [key: (fn [a] -> k) xs: list[a]] -> list[a]
  (list-fold xs (list-empty) (fn [acc: list[a] x: a] (pq-insert key x acc))))

(def-shell pq-sorted? :type-params [a (k ord)] [key: (fn [a] -> k) q: list[a]] -> bool
  (decreases (list-length q))
  (match (list-tail q)
    ((Success t)
      (match (list-head q)
        ((Success x)
          (match (list-head t)
            ((Success y) (and (<= (compare (key x) (key y)) 0) (pq-sorted? key t)))
            ((Error e) true)))
        ((Error e) true)))
    ((Error e) true)))

(def-shell pq-show :type-params [a] [show: (fn [a] -> string) q: list[a]] -> string
  (string-concat-many (list-map q (fn [x: a] (string-concat (show x) " ")))))
```

- **Lines:** 27 against 91 in the queue section; the file goes from 168 to about 105.
- **Recursion:** `pq-insert` and `pq-sorted?` recurse at their own type parameters, so rule 2 holds.
- **Derived contexts:** `pq-insert :: Ord k => …`; `pq-show` has none.
- **Instances:** three per key-form definition: `[int, int]`, `[string, string]` and `[Task, int]`.
- **Verification:** unchanged from today. Each copy falls back on the `match` on `list-head`, as the hand-written copies did, and also on the key call (FN-PARAM-UF-1).

### P3

```lisp
(def-shell group-by :type-params [a (k key)] [xs: list[a] key: (fn [a] -> k)] -> map[k, list[a]]
  (list-fold xs (map-empty)
    (fn [m: map[k, list[a]] r: a]
      (let [(kv (key r))]
        (map-put m kv (if (map-has m kv) (list-append (map-get m kv) r) [r]))))))

(def-shell show-groups :type-params [a (k key)] [show-key: (fn [k] -> string) g: map[k, list[a]]] -> string
  (string-concat-many
    (list-map (map-entries g)
      (fn [e: (k, list[a])]
        (string-concat-many [(show-key (first e)) ": " (int-to-string (list-length (second e))) "\n"])))))
```

- The derived context for `group-by` is `(Ord k, Show k)`, because the body reaches `map-get`. This is the G1 repair.
- `show-groups` reaches only `map_entries :: Map.Map k v -> [(k, v)]`, which demands no class, so its derived context is empty. The declared `key` is still checked at every call, so callers stay in the map-key class.
- **Lines:** the file goes from 185 to 175.

## Edge cases and positive witnesses

| # | Input | Expected | Channel |
|---|---|---|---|
| 1 | `(def-shell mem :type-params [a] [x: a xs: list[a]] -> bool (list-contains xs x))` | `constraint-missing` on the body (positive witness) | type |
| 1b | `(def-shell same :type-params [a] [x: a] -> a (post (= result x)) x)` | `constraint-missing` on the `post` (positive witness, gap 5) | type |
| 2 | `(pq-from-list rec-level recs)`, where `Level` is a sum type | `order-undefined` naming `(k ord)` (positive witness) | type |
| 3 | `(def-shell empty-q :type-params [a] [] -> list[a] (list-empty))` | `type-param-not-determined` at the definition (positive witness) | type |
| 3b | `(pq-from-list (fn [x] x) (list-empty))` | `type-param-not-determined` at the call: `a` is unfixed by the arguments and the lambda parameter is unannotated (positive witness, synthesis step 4) | type |
| 4 | `f :type-params [a]` calls `(g (list-prepend x (list-empty)))`, and `g :type-params [b]` calls `(f y)`, so `f` passes `list[a]` around the cycle | `polymorphic-recursion` on the component `{f, g}` (positive witness, rule 2 over the component) | type |
| 5 | `(+ x 1)` with `x: a` | type mismatch, "expected int, got a" | type |
| 6 | `(for-all [x: a] …)` | `for-all-type-param` | type |
| 7 | a generic body that passes `x: a` to a Tier 1 import | `ffi-type-param` | type |
| 8 | `:type-params [int]` | `type-param-shadow` | type |
| 9 | `(def f :type-params [a] …)` or `(type Opt :type-params [a] …)` | `type-params-not-supported`, naming the deferred row (positive witness for the v1 scope) | type |
| 10 | `(group-by xs f)` where `f` returns `bool` | `map-key-undefined` for `(k key)` (positive witness) | type |
| 11 | `(pq-sorted? (fn [x: int] x) (list-empty))` | `a` is fixed to `int` by the annotated lambda. With `(pq-sorted? key (list-empty))` inside a generic caller, `a` stays the caller's rigid parameter. Fully unfixed instantiations are specialized at `int` | none (AMBIG-TVAR-1) |
| 12 | `pick-min` (above), called at `int` and at `string` | **`pick-min@[int]` is predicted to prove.** In the `else` branch `result = y`, and the post needs `compare y y ≤ 0`. That holds only when `compare` is interpreted: at `int` it unfolds. **At an uninterpreted sort the proof fails**, because nothing says `compare y y = 0`. `pick-min@[string]` falls back for the same reason. This is the positive witness that specialization adds a proof (review verdict 5). Not yet measured | contract |
| 13 | `(pick-min p q)` with `p q : PositiveInt` | `pick-min@[PositiveInt]` gets `pre` `x > 0 ∧ y > 0` and post obligation `result > 0`. Both are stated, and the obligation is predicted to prove (question 1) | contract |
| 14 | an edit to the predicate of `PositiveInt` | the content hash of `pick-min@[PositiveInt]` changes, and the old evidence is not reused (repair 3) | trust |
| 15 | a property at `int` calling `pick-min` | `subject_key` is the hash of `pick-min@[int]`. `tested` does not lift to `pick-min@[string]` | trust |
| 16 | `group-by` codegen | context `(Ord k, Show k)`; GHC accepts it. G1 is closed | none (build) |
| 17 | before S0, `(pq-show (fn [x: int] (int-to-string x)) q)` where `q` comes from an untyped parameter | `untyped-arg-to-generic` (positive witness for rule 5) | type |

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Type-argument synthesis (steps 1 to 4) and constraint entailment | type | decidable: one-way matching, at most one round per lambda, and a finite lattice |
| Rule 2 over components | type | decidable: an SCC computation over a finite call graph |
| The body VC of a specialized copy | contract | the same fragment as the hand-written copy |
| `compare` at `int`, `bool` and their pairs | contract | (a) QF-LIA, by definitional unfolding; no assumed post |
| `compare` at `string` or a pair containing `string` | contract | uninterpreted, so the caller falls back |
| Refinement obligations of an alias type argument | contract | stated in the copy by `augmentContractPre` and `augmentContractPost`; (a) QF-LIA when the predicate is |
| A property of a generic for every type | none | not stated; it would be (c), and PBT tests it per instance |

`Σ_auto` and the sealed-builtin axiom set do not change in v1. v2's quantifier-free `compare` facts would join the axiom set with TRUST-AXIOM rows.

## Design-reference set

| Language | Generics | Verification |
|---|---|---|
| Liquid Haskell | parametric polymorphism; abstract refinements (ESOP 2013) | once, generically |
| F\* | dependent, universe-polymorphic, implicit arguments | once, generically. KaRaMeL monomorphizes for C because C has no polymorphism, and the extraction is trusted |
| Dafny | type parameters with closed characteristics `(==)`, `(0)`, `(!new)` | once, generically. Each type parameter is an abstract Boogie type, so this is the model for v2's hybrid (Leino, LPAR 2010) |
| Idris 2 | dependent types, erased implicit arguments | once, generically |
| Lean 4 | universe polymorphism, instance arguments | once, generically; `@[specialize]` is for speed only |
| SPARK | Ada generics, instantiated explicitly | **per instance**; GNATprove analyses instances. This is the precedent for v1 |

LLMLL v1 takes SPARK's verification, Dafny's closed constraint set, and colored local type inference instead of SPARK's explicit instantiation. v2 adds Dafny's generic-first proof at an uninterpreted sort.

## Rejected alternatives

The same list as Rev 0, with these changes:
- Generic types and generic `def` are now **deferred**, not part of v1.
- Monomorphized codegen is a fallback that is not built (the review's answer to Rev 0's question 2).

Rejected:
- option B alone;
- untyped parameters as generics;
- Damas–Milner inference;
- C++-style templates;
- explicit instantiation at every call;
- overloading `<`;
- constraints on type declarations;
- higher-kinded parameters.

Pair or enum map keys (D3) and user instances are out of scope.

## Affected surface (v1)

- **`LLMLL.md`**:
  - §0: the `nc-038` amendment;
  - §3: `:type-params` on `def-shell`, the `eq`, `ord` and `key` constraints, rigid checking, and rules 1 to 5;
  - §3.4.6: synthesis steps 1 to 6;
  - §5.3.3 and §5.3.4: specialization, the evidence key, and the instantiation count;
  - §12: the clause and `type-var`;
  - §13: `compare`.
- **`docs/llmll-ast.schema.json`**: one minor version, additive. `type_params` on `def-shell`, and the `type-var` kind.
- **`compiler/src/LLMLL/Syntax.hs`**, **`compiler/src/LLMLL/Parser.hs`** and **`compiler/src/LLMLL/ParserJSON.hs`**: the clause and the rigid-parameter type.
- **`compiler/src/LLMLL/TypeCheck.hs`**:
  - rigid checking of the body and the contract;
  - synthesis steps 1 to 6;
  - rules 1 to 5, with rule 2 on the components already computed for the trust report.
- **`compiler/src/LLMLL/TypeAdmissibility.hs`**: rigid parameters in the three walks.
- **`compiler/src/LLMLL/FixpointEmit.hs`**: the instantiation set, specialization, `compare` unfolding, the expanded-argument evidence key, and the count.
- **`compiler/src/LLMLL/CodegenHs.hs`**: derived contexts, `llmll_compare`, and a test that pins the derivation against the preamble.
- **`compiler/src/LLMLL/Contracts.hs`**: one `compare` arm.
- **The PBT lift:** `subject_key` per copy.

## Risks and open questions

1. **The value evidence is one designed probe.** Class: scope. Mitigation: an experiment-lead MEASURE that asks agents for container-shaped programs at two or more element types, and counts copies and verification outcomes with and without generics.
2. **The key idiom moves code from reflected to fallback** until FN-PARAM-UF-1. Class: verification-ergonomics. **Resolved by decision 3:** FN-PARAM-UF-1 lands before GENERICS-1. `(a ord)` with direct `compare` is still taught first.
3. **The specialization count grows with nesting depth.** Class: verification-ergonomics. The count is reported (step 7), and v2's hybrid bounds it.

## Open questions for the user

None. All three questions were answered on 2026-10-24 (see "Decisions").

No question is left for the professor. Both review questions are answered above. One answer differs from the review: refinement aliases are allowed in v1 on the specialization argument, not on the abstract-refinement argument, which moves to v2.

## Hand-off (settlement)

- **(a) Proposal file:** `docs/design/generics-proposal.md`.
- **(b) Settled revision:** Rev 1, 2026-10-24.
- **(c) Review fold (M2):** `docs/design/generics-review.md` is a standalone professor review (one round, of Rev 0), ready to fold into this record as an appendix and archive. The doc-lead does the fold and the INDEX label update.
- **(d) Rows for the doc-lead to file.** The groups and markers are proposals; the doc-lead owns placement.

| Row | Tags | Group, marker | Depends on | Content |
|---|---|---|---|---|
| `GENERICS-1` | `[CT][SPEC]` | G7, PLAN | **FN-PARAM-UF-1 lands first** (decision 3). No dependency on S0 (decision 2). | v1: `:type-params` on `def-shell`; `eq`, `ord` and `key`; rigid checking of body and contract; synthesis steps 1 to 6; rules 1 to 5 (rule 5 is the local guard); specialize then verify, with the expanded-argument content-hash key and instantiation counts; polymorphic codegen with derived contexts; `subject_key` per copy; additive schema change; the `nc-038` amendment |
| `GENERIC-COMPARE-1` | `[CT][SPEC]` | G7, PLAN | GENERICS-1 (it can land with it) | the `compare` builtin, `llmll_compare` with an `Integer` result, unfolding at `int` and `bool`, and one PBT evaluator arm |
| `GENERICS-2` | `[CT][SPEC]` | G7, DECIDE | GENERICS-1 | v2: generic `def` with a check-time admission gate per instance; the generic-proof-first hybrid under the review's three side conditions, with quantifier-free `compare` facts as sealed axioms with TRUST-AXIOM rows |
| `GENERIC-TYPES-1` | `[CT][SPEC]` | Trigger-gated Parking Lot | GENERICS-1 | generic `type` declarations, `args` on `TypeNamed`, type application, the CTOR-FN-FIELD-1 extension (witness G2), and the regular-recursion rule for types. Trigger: a program that needs `Opt[a]`, a generic tree or a generic queue type |

- **Engineer summary (GENERICS-1 and GENERIC-COMPARE-1).** Start after FN-PARAM-UF-1 ships.
  - **Front ends:** the clause and the `type-var` kind in both front ends (`compiler/src/LLMLL/Parser.hs`, `compiler/src/LLMLL/ParserJSON.hs`).
  - **Types:** a rigid-parameter `Type` constructor in `compiler/src/LLMLL/Syntax.hs`.
  - **Checker:** rigid checking, synthesis and rules 1 to 5 in `compiler/src/LLMLL/TypeCheck.hs`; rigid parameters in the walks of `compiler/src/LLMLL/TypeAdmissibility.hs`.
  - **Verifier:** the instantiation set, specialization, `compare` unfolding, the evidence key and the counts in `compiler/src/LLMLL/FixpointEmit.hs`.
  - **Codegen:** derived contexts, `llmll_compare`, and a test that pins the derivation against the preamble, in `compiler/src/LLMLL/CodegenHs.hs`.
  - **PBT:** one `compare` arm in `compiler/src/LLMLL/Contracts.hs`.
  - **Regression tests:** each edge case with a positive witness becomes one, including G1 (edge case 16) and the predicted proof of edge case 12.
- **Doc-lead summary (on ship).**
  - **`LLMLL.md` §0:** the `nc-038` amendment, using the text under "Codegen".
  - **`LLMLL.md` §3, §3.4.6 and §12:** the clause, constraints, synthesis order and rules.
  - **`LLMLL.md` §5.3.3 and §5.3.4:** specialization, the evidence key and the counts.
  - **`LLMLL.md` §13:** `compare`.
  - **`docs/llmll-ast.schema.json`:** the schema version, in landing order.
  - **CHANGELOG:** an entry for the release.
