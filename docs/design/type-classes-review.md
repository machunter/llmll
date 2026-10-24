---
title: TYPE-CLASSES — professor review of Rev 0
status: review of `type-classes-proposal.md` Rev 0 DRAFT (2026-10-24); standalone, not folded
reviewer: professor
---

# TYPE-CLASSES — professor review of Rev 0

## Verdict

**Choose S0, not S+.** The proposal describes S+ as "HM(X) restricted to two closed predicates". That description assumes that `check` infers a type scheme for a definition with an untyped parameter. It does not. `check` gives an untyped parameter the wildcard type `TCustom "_"`, which unifies with every type and records nothing. S+ therefore needs Damas–Milner inference for unannotated definitions first, and a constraint layer second. The constraint layer is a solved problem. The inference layer contradicts `LLMLL.md` §3.4.6 ("no global unification"), and the proposal does not cost it.

The defect that F1 reports is also wider than constraints. Plain type errors escape `check` through the same wildcard (witnesses W1, W5, W6 and W8 below). F1 is one case of an unchecked dynamic type with no run-time cast. S0 removes the wildcard and so closes every case. S+ as written closes only the constraint case.

## Restatement

Rev 0 asks for no user-declared classes. It names two closed built-in predicates, `Eq?` and `Ord?`, and proposes that `check` infer them onto definitions with untyped parameters and test them at each call site (S+). The alternative S0 makes a type annotation mandatory on every parameter. The proposal asks two questions. Is S+ a known-complete design with no inference pitfalls? If user instances arrive later, is specialization before VC emission the accepted way to keep reflection, and how is proof reuse keyed?

## Context located

1. `compiler/src/LLMLL/Parser.hs:250-254` (`pDefParam`): a parameter with no `: type` parses as `TCustom "_"`.
2. `compiler/src/LLMLL/ParserJSON.hs:679-683`: the JSON-AST path gives the same `TCustom "_"`.
3. `compiler/src/LLMLL/TypeCheck.hs:3849-3850` (`structuralUnify`) and `:3898-3899` (`compatibleWith`): `TCustom "_"` unifies with any type and binds no variable.
4. `compiler/src/LLMLL/TypeCheck.hs:3095-3115`: U-Lite per-call-site substitution. `checkEqDefined` and `checkOrdDefined` read only this call's substitution.
5. `compiler/src/LLMLL/TypeCheck.hs:4047-4052`: a missing return type is also `TCustom "_"`.
6. `compiler/src/LLMLL/Module.hs:455-456` (`compatibleTy`): the wildcard is compatible with every type across modules too.
7. `compiler/src/LLMLL/CodegenHs.hs:2492,2514`: codegen lowers `TCustom "_"` to the Haskell variable `a`, so GHC does the real inference.
8. `LLMLL.md` §3.4.6 (line 397): "local type inference … no global unification"; type information enters "from only two sources — surface annotations … and holes".
9. `LLMLL.md` §12 (lines 2554-2566): `typed-param = IDENT ":" type`; the proposal's F2 is correct.
10. `LLMLL.md` §8.8 and §8.8.1 (lines 1595-1650): `def-interface` with typed methods and `:laws`, tested by QuickCheck. **The proposal does not cite it.**
11. `LLMLL.md` §5 item 5 (line 733): interface laws are "parametric over implementations" and live on a distinct trust channel.
12. `LLMLL.md` §3.1 (line 142) and roadmap row `FLOAT-OPS-1`: `float` has `=` only; the planned arithmetic is finite-only.
13. `LLMLL.md` §13.5 (line 2854): the ordered types O, and "comparing equal coincides with `=`".
14. `docs/design/ambig-tvar-1-proposal.md`: settled, not shipped; its soundness argument step 1 assumes that user definitions are monomorphic in an ambiguous variable.
15. `docs/design/equality-capable-types-proposal.md` (CTOR-FN-FIELD-1): equality capability is a greatest fixpoint over user types. The proposal cites `noEqWitness` but not this record.

## Witnesses

Built compiler: llmll 0.30.10 (`b869112`), scratchpad copy. GHC 9.6.6, type-check only (`-fno-code`) of the emitted `Lib.hs`. I did not run `verify` or fixpoint. The `_` code paths that I cite are unchanged at `7f5b6786`.

| ID | Program | `check` | GHC |
|---|---|---|---|
| W1 | `(def-shell inc1 [x] (+ x 1))` `(def-shell g [] -> string (inc1 "a"))` | OK | `Couldn't match type ‘Integer’ with ‘[Char]’` |
| W5 | `(def-shell first-of [p] (first p))` `(def-shell g [] -> int (+ (first-of (pair "a" 1)) 1))` | OK | `Couldn't match type ‘[Char]’ with ‘Integer’` |
| W6 | `(def-shell id1 [x] x)` `(def-shell g [] -> int (id1 "a"))` | OK | `Couldn't match type ‘[Char]’ with ‘Integer’` |
| W8 | `(def-shell g [] -> int (let [(f (fn [y] (+ y 1)))] (f "a")))` | OK | `Couldn't match type ‘[Char]’ with ‘Integer’` |
| W2 | `(def-shell apply-cmp [f x] (f x x))` | error: `'f' is not a function … value of type _` | not reached |
| W4 | `(def-shell mysort [xs] (list-sort xs))` `(… (mysort (list-empty)))` | OK | `Ambiguous type variable ‘a0’ … (Ord a0)` (AMBIG-TVAR-1 not shipped in 0.30.10) |

W1, W5, W6 and W8 involve no class constraint. W8 shows that an untyped `fn` parameter in a synthesized position has the same escape. W2 shows that an untyped parameter cannot be applied, so untyped parameters are first-order today.

## Answer to question 1: is S+ known-complete, and should LLMLL choose it?

**The constraint layer is known-complete.** Two closed predicates with structural decomposition are the textbook case of qualified types. The relevant results are these:

- Jones, *Qualified Types: Theory and Practice* (CUP 1994), and Odersky, Sulzmann and Wehr, *Type Inference with Constrained Types* (TAPOS 1999), give principal types when the constraint system has decidable entailment and every predicate on a constructed type reduces to predicates on its parts.
- `Eq?` and `Ord?` reduce that way. `Eq?(list a)` is `Eq? a`, `Eq?(pair a b)` is `Eq? a ∧ Eq? b`, and `Eq?` of a function, `Command` or `Promise` is false. `Ord?(pair a b)` is `Ord? a ∧ Ord? b`, and `Ord?(list a)` is false.
- User types take no type parameters (`Syntax.hs` `STypeDef`). So a predicate on a user type is a constant, computed once by `noEqWitness` or `noOrdWitness`. No instance context ever mentions a variable through a user type.
- Standard ML equality type variables are the one-predicate case (Milner, Tofte, Harper and MacQueen, *The Definition of Standard ML (Revised)*, 1997, §4.4 and §4.7). Inference with them is principal.

**Known costs in the literature, mapped to LLMLL.**

- Appel, *A Critique of Standard ML* (JFP 1993), names equality types as a source of complexity out of proportion to their use. OCaml did not adopt them and kept a polymorphic `compare` that fails at run time. Successor ML discussions proposed removal. The cost is in signatures and abstraction, which LLMLL does not have, so the critique applies only weakly.
- Go's `comparable` (Go 1.18) admitted interface types that panic at run time. Go 1.20 then separated "comparable" from "strictly comparable". The lesson is that a closed predicate still needs an exact rule at every existential type. LLMLL has one such type, `Json`, and already refuses it (`mentionsJson`).
- F\*'s `eqtype` (`hasEq`) is computed for each inductive type, with `noeq` and `unopteq` qualifiers as escapes. Dafny's `T(==)` is written by the user on a type parameter. Both match the CTOR-FN-FIELD-1 greatest fixpoint. Neither infers the characteristic onto an unannotated function, because neither has unannotated functions.
- Haskell's `Eq` and `Ord` with defaulting require the ambiguity check of Jones 1994 §5. An unfixed variable with only `Eq?` or `Ord?` is ambiguous. AMBIG-TVAR-1 makes that coherent by a parametricity argument, so S+ inherits a sound default.

**The pitfalls the proposal lists, one by one.**

- **Value restriction.** Not a pitfall. LLMLL has no mutable reference cells, so generalization needs no value restriction (Wright, *Simple Imperative Polymorphism*, LASC 1995, is only needed with refs). GHC's monomorphism restriction applies to pattern bindings, and LLMLL definitions lower to function bindings, including `f ()` for a nullary definition.
- **Let-polymorphism.** A small risk, in the safe direction. If `check` does not generalize a local `let` and GHC does, `check` rejects programs that GHC accepts. That is conservative, but it must be written down.
- **Higher-order builtins.** `list-fold` and `list-map` take a lambda. Under HM, the lambda's parameter type is unified with the builtin's expected function type, and constraints flow normally. No principality loss. W2 shows that an untyped parameter cannot itself be a function today, so S+ adds no higher-order inference unless it lifts that rule.
- **Records and sum types containing functions.** No pitfall for inference, because user types are not parametric. The predicate is a constant per type.
- **Recursive types.** `Eq?` is a greatest fixpoint and `Ord?` a least fixpoint; both are computed once. Recursive *definitions* are the real case. Without signatures, HM infers monomorphic recursion, and polymorphic recursion is not inferable (Henglein, TOPLAS 1993; Kfoury, Tiuryn and Urzyczyn, TOPLAS 1993). GHC refuses the same programs, so `check` and GHC agree.
- **Cross-module inference.** A real cost. `meContracts` (`Syntax.hs:1132`) stores parameter types, and `Module.hs:455-456` treats `_` as compatible with everything. S+ must export the inferred scheme with its predicates. The interface format and the evidence key change, and a scheme now depends on the callee's body, so a body edit can change a caller's acceptance.
- **The JSON-AST surface.** The decisive cost. LLMLL has no type-variable syntax. An inferred scheme `∀a. Ord? a ⇒ list[a] -> list[a]` cannot be written in `.llmll`, in the JSON-AST, or in an `--emit` round trip. A diagnostic must describe a type that the agent cannot write. The agent's only repair is to make the function monomorphic, which is S0 by hand.

**Where an agent's program fails under S+ but not under S0.** Two places.

1. **Error location.** HM reports a mismatch where unification fails, not where the agent made the mistake (Wand, *Finding the Source of Type Errors*, POPL 1986; Heeren, *Top Quality Type Error Messages*, PhD thesis, Utrecht 2005; Pavlinovic, King and Wies, OOPSLA 2014). Under S0 every error is local to one annotated boundary. The governing criterion is one-shot acceptance, so error locality decides this.
2. **Body-dependent acceptance.** Under S+, editing a callee's body can add a predicate to its scheme. Every caller at a type outside O then fails, with no change to the caller or to any signature. Under S0 a caller depends only on the callee's written signature.

**Where S+ inference becomes non-principal.** It does not, under the rules above. Principality is lost only if `check` adds features that the proposal does not propose: polymorphic recursion, higher-rank arguments, or overloaded numeric literals. Hole-directed checking (§3.4.6 Check-Hole) needs care. A goal type may now contain a constrained variable, and the sketch output must print it.

**Recommendation for question 1: S0.** S+ is sound and principal on paper. In this compiler it is a new inference engine, a new interface format, and a type language that the surface cannot write. S0 restores the §3.4.6 invariant that type information enters only through annotations and holes. It closes W1, W5, W6 and W8 as well as P7, P8 and P9.

## Answer to question 2: specialization before verification, and proof-reuse keys

The literature has two disciplines. Each one keys proof reuse differently.

**(A) Verify generically against the class contract, then specialize for code.**

- *Liquid Haskell.* Liu, Parker, Redmond, Kuper, Hicks and Vazou, *Verifying Replicated Data Types with Typeclass Refinements in Liquid Haskell* (OOPSLA 2020), put refinements on class methods. Each instance is checked once against the method refinements and the stated laws. Polymorphic client code is checked once against the class-level refinements, with the dictionary abstract. Reflection does not see through an abstract dictionary, so client proofs use the laws as hypotheses.
- *F\*.* Type classes are records, resolved by a Meta-F\* tactic (Martínez et al., *Meta-F\*: Proof Automation with SMT, Tactics, and Metaprograms*, ESOP 2019). Laws are record fields with proofs. Generic code is verified once. Specialization is done afterward by normalization and inlining, as HACL\* and EverCrypt do for agile code (Protzenko et al., *EverCrypt*, IEEE S&P 2020). The specialized term is not re-verified; its correctness follows by substitution.
- *Lean 4 and Isabelle.* A theorem quantifies over the instance argument (`[inst : Ord α] [LawfulOrd α]`). A proof is done once and instantiated by application. Isabelle's type classes work the same way, with code generation by dictionary translation (Haftmann and Wenzel, *Constructive Type Classes in Isabelle*, TYPES 2006; Haftmann and Nipkow, FLOPS 2010).
- *Dafny traits.* Callers verify against the trait method's specification. Each class proves once that its override refines that specification (Ahmadi, Leino and Nummenmaa, *Automatic Verification of Dafny Programs with Traits*, FTfJP 2015). This is behavioral subtyping, as in Liskov and Wing (TOPLAS 1994).

In (A), proof reuse is keyed per instance by one obligation: the instance satisfies the class contract. Client proofs are keyed by the generic definition alone.

**(B) Specialize, then verify each instantiation.**

- *SPARK.* GNATprove analyzes a generic unit only through its instantiations (SPARK User's Guide, "Generics"). Each instance is proved again, with no reuse across instances.
- *Why3.* `clone` instantiates a theory. Lemmas proved in the abstract theory are reused, and only the instantiated axioms become new goals (Filliâtre and Paskevich, *Why3 — Where Programs Meet Provers*, ESOP 2013). This is a hybrid of (A) and (B).

**Which one fits LLMLL.** Discipline (A) needs a generic proof language for the laws. In LLMLL the laws are quantified, so they are class (c), Lean only, as Rev 0 fact 1 says. Σ_auto cannot discharge them. Discipline (B) keeps body-faithful reflection, because after specialization the dictionary is a known constant and its methods inline. So **(B) is the accepted way for an auto-discharge verifier**, with SPARK as the precedent. It is not the way of Liquid Haskell, F\*, Lean or Dafny, and the proposal should not cite those systems as precedent for (B).

**The key for (B).** Key the evidence on the content of the specialized body, not on the pair (definition, instance name). The hash must cover the definition body, the contract, and the bodies and contracts of every instance method reached, transitively. A key on the instance name repeats the fact-4 hazard: an edit to the instance body would leave a stale record valid. Specialization also fails for polymorphic recursion and for dictionaries stored in data. LLMLL must forbid both if option 4 ever lands. LLMLL already lacks type-variable syntax, so most of this holds by construction.

## Gaps and hazards

Ordered by severity.

1. **S+ is not an extension of the current checker.** Class: spec drift and scope. Cite: `Parser.hs:254`, `TypeCheck.hs:3849-3850`, `LLMLL.md` §3.4.6. The proposal says that `check` "generalizes a definition" and records predicates "in the definition's scheme". No scheme exists; the parameter is `TCustom "_"`. This blocks S+ as costed. Rev 1 must either cost HM inference for unannotated definitions or drop S+.
2. **F1 is a gradual-typing escape, not a constraint escape.** Class: soundness (check against build). Cite: W1, W5, W6, W8. `TCustom "_"` behaves as the dynamic type `?` of Siek and Taha (*Gradual Typing for Functional Languages*, Scheme Workshop 2006). It has consistency but no cast, and the back end is statically typed GHC. Every type error can pass through it, not only `Eq` and `Ord`. This widens `CONSTRAINT-ESCAPE-1`; rename or re-scope the row.
3. **Lambda parameters are not covered.** Class: spec drift. Cite: W8; `LLMLL.md` §12 has no rule for an untyped `fn` parameter. S0 must say what happens to `(fn [y] …)`. The smallest rule is the Pierce–Turner one: an untyped lambda parameter is legal only in a checking position whose expected type is a known function type, such as an argument of `list-map` or `list-fold`. Elsewhere it needs an annotation.
4. **`def-interface` is missing from the analysis.** Class: scope. Cite: `LLMLL.md` §8.8 and §8.8.1, line 733. LLMLL already has named method signatures with `:laws`, tested by QuickCheck on a separate trust channel. Option 4 is "add a type parameter to `def-interface`", not "new statement kinds". The schema cost in Rev 0 option 4 is overstated, and the laws channel already exists.
5. **The defaulting rule under S+ needs a spec statement.** Class: spec drift. Cite: `ambig-tvar-1-proposal.md` "Soundness argument" step 1, and §13.5. GHC defaults to `()`, and `unit` is not in O. Under S+ the spec cannot say "defaulted to unit" for an `Ord?` variable; it must say "unobservable" (AMBIG-TVAR-1 already proves that). Also, step 1 assumes that user definitions are monomorphic in the ambiguous variable. S+ makes them polymorphic, so the argument must be re-checked for inferred schemes. S0 keeps step 1 true. Under S0 this item disappears.
6. **Edge case 6 depends on an unshipped decision.** Class: ergonomic. Cite: W4. On 0.30.10, `(mysort (list-empty))` fails GHC. The proposal states it "stays OK"; that is true only after AMBIG-TVAR-1 ships.
7. **Coherence is stated too strongly.** Class: soundness framing. Cite: Rev 0 fact 4. Coherence is a soundness requirement only because LLMLL keys evidence on a body that does not name its instances. Lean is incoherent by priority and still sound, because the instance is an explicit argument of every theorem. The correct requirement is "evidence keys cover the elaborated, dictionary-explicit body". Global coherence is one way to get that, not the only way.
8. **The verification-cost claims are mostly right, with one error.** Class: verification. Rev 0 fact 3 offers specialization as a repair "and reflection is kept". That is right for discipline (B). Fact 1 says the laws are "class (c), Lean only". That is right for proof, but `:laws` already gives them a `tested` path (item 4). Fact 6 (PBT parity) is right and understated: the untyped evaluator in `Contracts.hs` would need dictionary elaboration shared with codegen, which is the PBT-EVAL-PARITY-1 failure class.
9. **The size measure is a lower bound of the wrong thing.** Class: ergonomic. Rev 0 counts definitions with no typed parameter (13). The S0 cost is every untyped parameter, in `def`, `def-shell`, `letrec` and `fn`. The proposal should also count how many of these are used at two or more types. Only those lose anything under S0. The three files it names read as accessors used at one type each.

## Critique of the ranking

- **S0 belongs first, S+ last among the live options.** The reasons are in the verdict.
- **Option B (document the dictionary idiom) is correct and should ship with S0.** Name `def-interface` in that paragraph as the shape of a dictionary record, and `list-sort-by` with a key as the order idiom.
- **Option 3 (enum declaration order) is correctly trigger-gated.** Add one cost: an enum in O still cannot be a map key, because keys are `{int,string}`. Most enum-sorting programs also want enum-keyed maps.
- **Option 4 is ranked correctly but costed wrongly.** It extends `def-interface` (item 4). Its verification plan must state discipline (B) and the content-hash key from question 2.
- **Option 5 (Haskell classes) is correctly rejected.** The best argument is the error-message argument, and Rev 0 already makes it.
- **Option 6 (functors, modular implicits) is correctly rejected.** Why3 `clone` is the nearest verified analogue and needs parameterized theories, which §8 does not have.

## What Rev 0 missed

- **Printing (`Show`).** No generic printer exists; `int-to-string` is monomorphic (`TypeCheck.hs:191`). `map-get` needs `Show k` only for its error text, and keys are `{int,string}`. No `Show?` predicate is needed. State this, so that a future generic `to-string` builtin is recognised as the first trigger for a third predicate.
- **Hashing.** Maps are `Data.Map` (ordered), not hash maps. No `Hash?` predicate is needed while keys are `{int,string}`. If option 3 lets enums into map keys, the verifier's array class must change first, and that change is larger than a predicate.
- **The numeric tower.** `+` is `int -> int -> int` (`TypeCheck.hs:111`) and reflects to QF-LIA. FLOAT-OPS-1 will be the first pressure for an overloaded `+`. Recommend separate operator names for `float`, as OCaml does with `+.`. An overloaded `+` makes the solver sort of a VC depend on inference, and it removes the guarantee that `+` is always LIA. FLOAT-OPS-1's finite-only rule keeps `=` at `float` reflexive. Write that dependency down: `Eq?` includes `float` only because NaN is excluded. DECIMAL-1 option (c) is `int`-scaled and needs no class.
- **`Ord?` and `=` agreement.** §13.5 already states "comparing equal coincides with `=`" on O. This is the `Ord`/`Eq` compatibility law. Under any user-instance option it becomes a proof obligation per instance. Record it now as a built-in fact of O.

## Recommendation

1. **Adopt S0, with the Pierce–Turner lambda rule.** Every parameter of `def`, `def-shell`, `def-logic` and `letrec` carries a type. An untyped `fn` parameter is legal only in a checking position with a known function type. Remove `TCustom "_"` as a parameter type from the parser, the JSON parser and the checker. `param_type` becomes required in the schema, which is a version change. Give the removal a deprecation release that warns first, with a message that prints the type GHC would infer if the build is available, or names the call site that fixes it.
2. **Re-scope the defect row.** `CONSTRAINT-ESCAPE-1` should be "untyped-parameter escape", with W1, W5, W6, W8, P7, P8 and P9 as witnesses. It is a G3 defect and P9 is a silent spec violation.
3. **Keep the two predicate names in the spec as documentation only.** Name `Eq?` and `Ord?` in §3 as the closed sets that `=`, `list-contains`, `list-sort` and `list-sort-by` require. No inference attaches them to user definitions under S0.
4. **Ship option B with S0**, citing `def-interface` and `list-sort-by`.
5. **If option 4 ever triggers,** build it as a type parameter on `def-interface`, verify by specialization before VC emission (discipline B), and key evidence on the content hash of the specialized body.

## Open questions for the language-team

1. Measure the S0 migration exactly. Count every untyped parameter in `def`, `def-shell`, `letrec` and synthesized `fn` positions across tracked `.llmll` files, and count how many of those definitions are called at two or more distinct types. If that second number is zero, S0 loses no expressiveness that the corpus uses.
2. If Rev 1 keeps S+, cost the inference engine explicitly: where the inferred scheme is stored in `ModuleEnv`, how a diagnostic prints a constrained variable that the surface cannot write, and whether the AMBIG-TVAR-1 soundness argument step 1 still holds for inferred polymorphic user definitions.
