---
name: image-library-review
title: "Professor review of IMAGE-LIB-1 Rev 2 (Parts B, C and D)"
status: "Review of Rev 2 DRAFT (uncommitted, on main at 29e852bf). Standalone. Not folded. Settles nothing."
date: 2026-11-20
author: professor
reviews: docs/design/image-library-proposal.md
---

# Professor review of IMAGE-LIB-1 Rev 2

**Verdict.** Part B can settle with four amendments. Part C must be revised before its witness table runs. Part D must be revised. I found no route to a false `verified` in Part B or Part C as written. The defects are in the instance sets of Part C, in a fact of Part B that nothing in the plan uses, and in a coverage definition that a machine cannot check.

**Evidence.** Every statement here comes from a reading of the proposal, the compiler at 29e852bf and the cited literature. I ran no build, no `llmll verify` and no solver. Each claim about the compiler gives a file and a line range.

**Three findings change the plan:**

1. The D1 and D2 instance sets of Part C miss two witnesses of the plan, `scale-src` and the `sw = 1` case of edge case 7. D1 has no consumer in the plan (finding 1).
2. Fact C of Part B gives no proof to any function of the plan. An `ops` post states a length only, so the `ops` constraint holds no read of the result (finding 2).
3. "Exact post" in Part D has no mechanical definition. A determinacy VC gives one, and it is the solver form of CDP = 1 (finding 4).

## Restatement

Part B adds `bytes-tabulate`, a sealed builtin. Its result is a fresh array symbol with an exact length fact L. Each read of the result gets a quantifier-free instance C of the universal `∀j. 0 ≤ j < n ∧ pre_gen(a, j) ⟹ post_gen(a, j, r[j])`. Proof obligations T1 to T3 at the call site use an eigenvariable `ι`. Part C admits `/` and `mod` by a variable `d` under a proved `d ≥ 1`. It abstracts each `(e, d)` pair as two atoms and adds four fixed fact schemas D0 to D3, in the manner of the MUL-VAR-1 product pass. Part D counts a function as covered when the trust report says `verified`, its post is "exact", and every generated mutant is `refuted`.

## Context located

1. `docs/design/image-library-proposal.md`, Rev 2. The record under review, with its security-review appendix.
2. `docs/design/mul-var-proposal.md`, "Rules", "Fact set", "Limits" and "Invariance". D0 to D3 must fit this machinery. Part C cites the facts and does not cite the rules, the closure, the invariance property or the limits.
3. `compiler/src/LLMLL/FixpointEmit.hs` lines 442-479. `sealedAxiomBuiltins`, `abstractedBuiltins`, `exactSealedBuiltins`. `bytes-make` is length-only since BYTES-MAKE-ALIAS-1. A content reflection `Map_default(v)` was the false-proof source.
4. `compiler/src/LLMLL/FixpointEmit.hs` lines 4799-4822. `extractQualifiers` returns no qualifier for a clause with a product. The comment states that "LLMLL's body VCs are fully path-enumerated (no kvars)".
5. `compiler/src/LLMLL/FixpointEmit.hs` lines 4785-4797. `appLabel` gives `nonlinear:` labels for `/` and `mod`.
6. `compiler/src/LLMLL/GuardClassifier.hs` lines 345-372. `constArithTerm` folds ground terms and admits a numeral divisor greater than zero. A ground `(/ e c)` reaches liquid-fixpoint as SMT `div`.
7. `compiler/src/LLMLL/ObligationMining.hs` lines 200-228. `isSigmaAuto` is `exprToPred` minus products. Four consumers read it (MUL-VAR-1 Amendment 1).
8. `compiler/src/LLMLL/CodegenHs.hs` lines 600-605 and 2773-2776. `bytes_make` checks length, value and `maxBound` before it narrows. LLMLL `/` lowers to Haskell `div`, and `mod` lowers to `mod`.
9. `LLMLL.md` line 23 and §4.7. Call-by-value semantics, and partial correctness for an undischarged cycle.
10. `LLMLL.md` §4.4.6 and `compiler/src/LLMLL/CDP.hs`. CDP measures how many observable behaviours a contract admits over a closed set `Ω`. DP = 1 means exactly one.
11. `docs/compiler-team-roadmap.md`, rows WEAKNESS-MUTANT-1 and DIV-VAR-1. The swarm found four wrong bodies that verified, and `--weakness-check` reported nothing.
12. `docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md`. It already cites Chockler, Kupferman and Vardi, and DeMillo, Lipton and Sayward.

## Claims checked and found correct

These claims of Rev 2 hold. The language-team does not need to change them.

**B1. C is sound as a per-read instance of a universal.** The universal holds at run time under three conditions. Codegen stores `gen(a, i)` at index `i`. Guard 3 stops the program before a value outside `0..255` is narrowed. `gen` is verified against its own `pre`. With the `pre_gen` premise in C, soundness of C no longer depends on T2. That is the correct repair of H3. Under the partial-correctness reading of `LLMLL.md` line 23, a `gen` that diverges means that no `r` exists, so C is vacuous there. An instance of a valid universal is valid, and a missing instance loses completeness only. This is the standard argument for instance-based procedures (Bradley, Manna and Sipma, *What's Decidable About Arrays?*, VMCAI 2006; Ge and de Moura, *Complete Instantiation for Quantified Formulas in SMT*, CAV 2009).

**B2. Freshness per AST occurrence prevents the BYTES-MAKE-ALIAS-1 failure.** The index sort is `int`, which is infinite. Finitely many C instances therefore cannot force two fresh arrays to be equal, even under array extensionality. So the congruence of `bytesLen` cannot join two lengths. Freshness is stronger than necessary. F\* keys `Seq.init` on the length and the function, and that key is sound because two such terms are equal values. Rev 2 says that a congruence key must contain `n`, `gen` and every `aᵢ`. That rule is the F\* rule, and it is correct.

**B3. T2 and T3 with a fresh constant prove the universal.** This is ∀-introduction under the eigenvariable condition. `ι` must not occur in any hypothesis except its range. The body VCs have no kvars (`compiler/src/LLMLL/FixpointEmit.hs` lines 4807-4812), so no kvar solution can capture `ι`. The claim holds today. It needs restatement if kvars ever return.

**B4. The callee-edge treatment is complete for the computations listed.** `def`-only plus the termination-graph edge closes M4.

**C1. Haskell and SMT-LIB agree for `d ≥ 1`.** The Haskell 2010 Report (§6.4.2) defines `div` to round toward negative infinity, with `(x div y)·y + (x mod y) = x`. SMT-LIB `Ints` defines `div` and `mod` with `0 ≤ mod m n < |n|`. For `n > 0` both give `0 ≤ r < d` and the same `q`, for every sign of `e`. They differ only for `d < 0`. The rule `d ≥ 1` is the smallest correct rule.

**C2. D0 to D3 are theorems of integer division for `d ≥ 1`.** I checked each. The D1 certificate is correct: `|d·(q − a)| = |b − r| < d` forces `q = a`. D2 holds also for `B ≤ 0`, where its premise is false. Each fact is a theorem, so by the MUL-VAR-1 argument ("Changing the fact set") an added fact can only add proofs.

**C3. The fragment stays decidable.** Nonlinear integer arithmetic is undecidable (Matiyasevich, 1970). The atom abstraction keeps the solver query in quantifier-free linear arithmetic with arrays and free functions, which is decidable. The native recheck can return `unknown` on a division by a variable. An `unknown` must give the fallback outcome, as MUL-VAR-1 decision 1 already requires.

## Gaps and hazards

Ordered by severity. Each item states what it affects.

### 1. The D1 and D2 instance sets are not well-defined, and they miss witnesses of the plan

**Class:** decidability and ergonomics. **Source:** Part C, "Facts", rows D1 and D2. `docs/design/mul-var-proposal.md`, "Rules" and "Fact set". **Bite:** blocks the settlement of Part C. The witness table would test an instance rule that has no definition.

**D2, "each atom `B` that shares a monomial with `d`".** One reading is "each cofactor `m / d`, for each monomial `m` in the closure that `d` divides". Under that reading `hflip-at` works. Its `pre` holds `w·h·c`, and `d = w·c` divides it with cofactor `h`. `scale-src` does not work. Its terms are `x·sw` and `dw`. No monomial `dw·sw` exists, so no instance with `B = sw` is made. Then the bound `q < sw`, which every resize caller needs, has no instance. Edge case 7 claims that "D0 gives `q = 0`" when `sw = 1`. That needs `B = 1`. `1` is not an atom, and with D0 alone the solver must exclude `q ≥ 1` from `|dw·q| < dw`. That step is nonlinear. No F-fact gives it unless a literal bound on `q` is already a hypothesis (F7b).

**D1, "each split of the normal form of `e` into `d·a + b`".** The number of splits is finite, at most `2^k` for `k` monomials divisible by `d`. "Each split" can therefore be exponential. More important, the syntactic normal form of `e` is usually one variable. In `row-of` and at every call site, `e` is the parameter `i` or a let binder. The polynomial `(y·w + x)·c + k` reaches `e` only through an equation, that is, through a MUL-VAR-1 rule. Part C does not say whether splits range over the rule closure. Without the closure, D1 has no instance on any program in the plan. With it, the cost is not stated.

**D1 has no consumer in the plan.** `row-of` verifies by atom identity: body and post contain the same pair. No function in the contract table states a round trip such as `row-of(offset(y, x, k)) = y`. Edge case 2 is labelled "Positive witness for D1". It is a refutation, and refutation goes through the native recheck. It does not use D1.

**The established form is a Galois connection.** For `d ≥ 1`, floor division by `d` is the upper adjoint of multiplication by `d` on the ordered integers: `d·t ≤ e ⟺ t ≤ q`, and so `q ≤ t ⟺ e ≤ d·t + d − 1`. (Graham, Knuth and Patashnik, *Concrete Mathematics*, 2nd ed., ch. 3, give the floor form `⌊x⌋ ≥ n ⟺ x ≥ n`.) These two equivalences imply D1, D2 and D3. D1 is the pair at `t = a`. D2 is the second equivalence at `t = B − 1`. D3 follows from transitivity. This is one place where the algebra gives something concrete: one schema with one trigger rule replaces three schemas with three instance rules. cvc5 and z3 purify `div` this way: a fresh `q` with `d·q ≤ e < d·q + d`.

**The verification libraries confirm the inventory.** Dafny turns off nonlinear arithmetic in large proofs and supplies `DivMod` lemma libraries, taken from IronFleet (Hawblitzel et al., SOSP 2015). Verus has the same set in `vstd::arithmetic::div_mod` (Lattuada et al., OOPSLA 2023). That set names the D0 converse (`lemma_fundamental_div_mod_converse`, which is D1), ordering (`lemma_div_is_ordered`, which is D3), and two facts that Part C does not have. One is the nested-divisor law `(x / c) / d = x / (c·d)` (`lemma_div_denominator`). The other is the breakdown `x mod (y·z) = y·((x / y) mod z) + x mod y` (`lemma_breakdown`). An author who writes the column as `(mod (/ i c) w)` and not as `(/ (mod i (* w c)) c)` needs the breakdown law.

**Part C also has no congruence or link fact.** MUL-VAR-1 needed F9 (link) and F10 (congruence) because rules rewrite atoms inside `/` and `mod`. Two pairs `(e, d)` and `(e′, d′)` with `e = e′` and `d = d′` known only by an equation are two atom pairs. D3 covers `e = e′` only when `d` and `d′` are the same syntactic term. A post written `(/ i (* w c))` and a body that divides by a let-bound `stride` meet only through such a fact.

**Required amendment.** Replace D1 to D3 with the following set, or justify the current set against the witnesses above:

- **G (Galois), both directions.** Instances: each comparison or equality literal between `q` and a term `t`, at any depth, after normal form. Add each cofactor `t = m / d − 1` for each monomial `m` of the closure that `d` divides.
- **D0** unchanged.
- **D4, congruence and link:** `e = e′ ∧ d = d′ ⟹ q = q′ ∧ r = r′`. Instances: each two pairs, plus each pair that a rule changes, as F9 does.
- Optional, from the Verus inventory: the nested-divisor law and the breakdown law, if a witness needs them.

Then state for Part C what MUL-VAR-1 states for products. State the **pass order**: callee-post substitution, then C instances, then the division pass, then the product pass. The product pass must put every monomial that a D-fact creates (`d·q`, `d·t`) into its pair set `P`. The `scale-src` bound needs F5 on the pair `(dw, sw)`, and that pair exists only after a G instance creates `dw·sw`. State **invariance** under `π`, `φ` and `ρ`, and **limits** that refuse whole. The number of pairs is fixed, and no fact creates a division, so generation ends. The new monomials count against the 256-monomial and degree-6 limits.

### 2. Fact C proves nothing for any function of the plan

**Class:** scope. **Source:** Part A, "What stays unproved". Part A, contract table, `ops` rows. Part B, "Facts for the caller". **Bite:** does not block. It changes what to settle: one new axiom for no measured gain.

C is instantiated "for each ground read `select(r, j)` that occurs in the constraint". Every `ops` post in the plan states `bytes-length` only. So the `ops` body constraint contains no read of `r`, and it gets no C instance. "Inside the `ops` body by the Part B content fact" is therefore incorrect. Nothing is proved there. A chained tabulate, such as threshold over a grayscale result, needs T2 for the second generator. T2 needs the raster `pre` on the first result, which is a length (L). It does not need content.

So on the plan as written, Part B adds two things to the trusted base: an exact length axiom, which `bytes-make` already has, and a content axiom with no consumer. Liquid Haskell takes the same position in its shipped `Data.Vector` specification, where the result of `generate` gets a length (`vlen`) and no content. LH expresses content through abstract refinements over the index: `Vec <dom :: Int -> Bool, rng :: Int -> a -> Bool>` (Vazou, Rondon and Jhala, *Abstract Refinement Types*, ESOP 2013). A `get` instantiates `rng` at its index. That is C exactly. The abstract-refinement version also gives the "later extension" without the array equality that Rev 2 fears. The refinement parameters ride on the type of `result`, and a caller instantiates them at its own reads. No `tabulated` atom and no equality proof is needed.

**Required amendment.** Choose one of these and state it:

- **(a), recommended.** Settle `bytes-tabulate` with L, T1 to T3, the guards and the callee edge. Classify it with `bytes-make` in `abstractedBuiltins`. Defer C to the later extension, and design that extension as an index-dependent refinement on the `bytes` result in the manner of Vazou et al.
- **(b).** Keep C and name a consumer in the plan, with a witness. One candidate is a core function that reads its own tabulate result at a parameter index `j`. Its post is then a pointwise statement for every `j`, through the eigenvariable `j`. That pattern ties the statement to the tabulate inside that one body, and not to the `ops` function.

If (b) is chosen, three implementation points apply. The instance order must be **reverse** data flow: a C instance at `r₂ = tab(g₂, r₁)` can create a read of `r₁`, so `r₂` is processed first. "The topological order of the data flow" does not give the direction. The result symbol must be in the byte-range evidence set (ARR-RANGE-NAME, `compiler/src/LLMLL/FixpointEmit.hs` lines 999-1008), or its reads lose `0..255`. L and C must be emitted at the binder of the occurrence, never at a use site, so that edge case 4c holds by construction and not only by test.

### 3. The coverage class conflates specification strength with refutation completeness

**Class:** scope. **Source:** Part D, "Classes", "covered"; Risk R3; Rows item 4. `LLMLL.md` §4.4.6. **Bite:** complicates. It makes `core_coverage` depend on ABSTRACTION-RESULT-LEN-1 and CONE-DEF-DIRECTION-1, which are verifier rows and not library rows.

A mutant can have one of three outcomes. It can **verify**, which means either the post is weak or the mutant is equivalent. It can be **refuted**. It can **fall back**, which means the verifier is incomplete on that path. Only the first outcome says something about the specification. Rev 2 sorts the third outcome with the first, so a correct function with a strong post becomes "uncovered" when the verifier cannot build a counterexample. LLMLL already keeps these questions apart. §4.4.6 separates the evidence axis ("do we know the implementation satisfies the spec?") from the discriminative axis ("does the spec rule out wrong implementations?") and does not reduce them to one scalar. Part D reduces them to one class.

H5 was right that `abstraction:` must not count as `refuted`. That stays. The repair is to report two numbers. The first is the covered set, defined with finding 4. The second is a **refutation rate**, the fraction of non-equivalent mutants that are `refuted`. The rate ratchets on its own. It is the measure that ABSTRACTION-RESULT-LEN-1 and CONE-DEF-DIRECTION-1 would raise.

### 4. "Exact post" has no mechanical definition

**Class:** spec-drift and ergonomics. **Source:** Part D, "Its post is exact: it relates `result` to the inputs, not only a length or a range". **Bite:** blocks Part D as a CI gate. The ratchet needs a predicate that a machine computes.

"Relates `result` to the inputs" is syntactic, and it is easy to defeat. `(or (= result (- 255 v)) (>= result 0))` mentions `result` and `v`, and it admits every non-negative result. A mechanical definition exists and uses the solver that Part D already runs. A post is **exact** when this determinacy VC is proved:

```
pre(x) ∧ post(x, r₁) ∧ post(x, r₂) ⟹ r₁ = r₂          (illustrative)
```

The VC uses two fresh result symbols in the same fragment, with the same product and division facts. This is the semantic form of CDP = 1: the post admits exactly one behaviour on every input, not only on `Ω`. It gives Part D three properties for free:

1. `ops` functions classify themselves. A `bytes` result cannot satisfy the determinacy VC without array extensionality over all indices. So every `ops` function fails the VC and is shape-verified, with no hand-kept list.
2. Range-only and length-only posts fail the VC. That closes H5 by construction, and not by review.
3. Equivalent mutants become decidable relative to the verifier. Under a proved determinacy VC, a mutant that verifies is equivalent on the `pre` domain, unless the verifier is unsound. The reviewed exclusion file of R8 then shrinks to a soundness alarm. Mutant equivalence is undecidable in general (Budd and Angluin, *Two Notions of Correctness and Their Relation to Testing*, Acta Informatica 18, 1982). Here the post supplies the oracle.

With determinacy proved and the function verified, every non-equivalent mutant violates the post on some input. Mutants then measure refutation completeness, as finding 3 says, and not specification strength. That is a further reason to keep the two axes apart.

### 5. The fixed mutation set does not generate the table's own example mutants

**Class:** spec-drift. **Source:** Part D, "Mutants", operators 1 to 5. Part A, contract table, column "Example mutant". **Bite:** complicates. The set misses the most common defect class in this library.

The `threshold-v` example, `>` for `>=`, is a relational-operator replacement, and no operator in the set produces it. The `row-of` example, `(/ i w)` for `(/ i (* w c))`, deletes a factor. The `col-of` example, `(mod i w)`, replaces an operator and deletes a factor. Neither change is in the set. These are exactly the defects that WEAKNESS-MUTANT-1 records in `docs/compiler-team-roadmap.md`, such as a wrong-channel neighbour or a stride without `c`. The mutation literature settled a small sufficient set (Offutt, Lee, Rothermel, Untch and Zapf, *An Experimental Determination of Sufficient Mutant Operators*, TOSEM 5(2), 1996). Its five operators are ABS, AOR, LCR, ROR and UOI. The relational and arithmetic replacements, ROR and AOR, are the ones that this set lacks.

**Required amendment.** Add three operators to the fixed set. The first is ROR (`<`, `<=`, `>`, `>=`, `=`, `/=` replaced by each other). The second is AOR on `+`, `-`, `*`, `/` and `mod`, with `/` and `mod` replaced by each other. The third is factor deletion in a product. Then each example in the contract table must be a generated mutant, and a test must hold that.

### 6. The M3 fix covers qualifiers and kvars but not the Σ_auto consumers

**Class:** spec-drift (claim accuracy). **Source:** Part C, "Every emission site". `compiler/src/LLMLL/ObligationMining.hs` lines 200-228. `docs/design/mul-var-proposal.md`, Amendment 1. **Bite:** complicates. No false `verified` results, but labels become incorrect.

When `exprToPred` admitted `*`, every consumer of `isQfLia` widened, and MUL-VAR-1 needed `sigmaAutoPred` to undo that. Part C makes `exprToPred` admit `/` and `mod` by a variable, so the same widening happens again. `classifyContractFragment`, the `ObligationMining` strength decision, CLASSIFY-MEASURE and `RefineReuse.buildSubsumptionFQ` would label a division clause as in the auto-discharge fragment. Part C must extend `sigmaAutoPred` to refuse a variable divisor. It must also say whether the let-binding hints of `compiler/src/LLMLL/Checkout.hs` admit division, as they admit products. No kvar exists in the emitted body VCs (context item 4). So the qualifier exclusion matters mostly to avoid the free-symbol crash, and the Σ_auto exclusion is the one that matters for claims.

### 7. Callers will repeat the nonlinear range proofs unless the `geom` posts carry ranges

**Class:** ergonomics. **Source:** Part A, contract table, rows `row-of`, `col-of`, `scale-src`. **Bite:** matters at scale. Each `*-at` constraint then carries the D-facts and F4 and F5 pairs again, which moves it toward the 64-pair limit of MUL-VAR-1.

Each `geom` post is an equation only. Every `*-at` read must prove its index in range, and the `post` read of `hflip-at` must also be well-defined under CLAUSE-WELLDEF-1. Both proofs then need `0 ≤ row < h`, `0 ≤ col < w` and the offset bound `(y·w + x)·c + k < w·h·c` in the caller. That is the nonlinear part. The MUL-VAR-1 limits name the pair cap as "not local", so an unrelated `let` in a `*-at` can remove these proofs. The standard practice is to prove a range once, as a lemma, and to give callers linear facts. Dafny and Verus do this with lemma calls. In LLMLL the equivalent is a range conjunct in the callee post. Give `row-of`, `col-of`, `chan-of` and `scale-src` a range conjunct, and give `offset` the bound `result < w·h·c`. Each range is then proved where the literal trigger of finding 1 exists. Each `*-at` sees linear facts only, and its proof no longer depends on Part C. That is a large gain in robustness for five extra conjuncts.

### 8. Part C raises `checker_soundness_version` without a stated reason

**Class:** spec-drift. **Source:** Part C, "Affected surface", version-stamps bullet. `docs/design/mul-var-proposal.md`, "Changing the fact set", and its Settlement. **Bite:** minor.

MUL-VAR-1 argues that a fact set made of theorems invalidates no earlier `verified`, so it does not need `checker_soundness_version`. Part C admits terms that were refused before, and its facts are theorems. No earlier verdict changes. Either state which earlier `verified` sidecar Part C invalidates, or leave the stamp unchanged, as MUL-VAR-1 did.

### 9. Call-by-value evaluation of `a1 … ak` must be forced explicitly in codegen

**Class:** totality. **Source:** Part B, "Semantics" and edge case 5. `LLMLL.md` §4.7. **Bite:** minor, but edge case 5 is a test that fails without it.

Generated Haskell is lazy. With `n = 0`, `BS.unfoldrN` never forces the argument thunks, so an argument whose evaluation stops the program with an error is never evaluated. Edge case 5 requires "after evaluating `a1 … ak`". Codegen must force each argument before the loop. A test must use an argument that stops the program at `n = 0`.

## Recommendation

**Part B: settle with amendments.** The soundness argument is correct (B1 to B4). Settle alternative (a) of finding 2. That gives `bytes-tabulate` with L, T1 to T3, the three guards and the callee edge, classified as an abstracted builtin with `bytes-make`. Defer C to the later extension. Redesign that extension as an index-dependent refinement in the manner of Vazou, Rondon and Jhala, which avoids array equality. If the user wants C now, take alternative (b). That requires a named consumer, reverse data-flow order, registration in the byte-range evidence set and binder-site emission. Add the explicit argument forcing of finding 9 in either case.

**Part C: revise to Rev 3 before the witness table runs.** Replace D1 to D3 with the Galois schema G, keep D0 and add congruence D4. Define each instance set over the MUL-VAR-1 rule closure, with literal triggers and monomial cofactors. State the pass order, invariance and limits. Extend `sigmaAutoPred` (finding 6). Move the range reasoning into `geom` posts (finding 7). The witness table must include `scale-src` with a range conjunct, `sw = 1`, a round-trip lemma if D1-type reasoning stays, and a post that divides by a let-bound stride against a body that divides by `(* w c)`. The divisor rule `d ≥ 1` and the Haskell-to-SMT argument can settle as written.

**Part D: revise.** Define "exact" by the determinacy VC (finding 4). Report the covered set and the refutation rate as two separate ratchets (finding 3). Add ROR, AOR and factor deletion to the mutation set, and generate every example mutant of the contract table (finding 5). The set-based ratchet, the module-table rule for core and shell, and the trust-report source can settle as written.

**Convergences.** Finding 2 and the "later extension" text of Rev 2 identify the same missing piece from two directions. Rev 2 says that exporting C is the hard part. This review says that without export, C has no use. Finding 4 and `LLMLL.md` §4.4.6 reach the same quantity, uniqueness of admitted behaviour, from the solver side and from the observation side. The project's own CDP record cites Chockler, Kupferman and Vardi, *Coverage Metrics for Formal Verification* (FMSD 2006). Part D is mutation coverage in their sense, applied to code and not to models. Celik, Palmskog, Parovic, Gallego Arias and Gligoric, *Mutation Analysis for Coq* (ASE 2019), and Goldweber et al., *IronSpec* (OSDI 2024), apply mutation to verified artefacts in the same way, and both treat a mutant that the checker cannot decide as a separate outcome.

## Open questions for the language-team

1. Specify the instance set of each Part C fact as a function of the MUL-VAR-1 rule closure and of the literals of the constraint. Show by hand that the set yields the `scale-src` range, edge case 7 at `sw = 1`, and the `hflip-at` read bound before the witness table runs.
2. State which consumer in IMAGE-LIB-1 reads a tabulate result. If there is none, say whether C is deferred under alternative (a).
