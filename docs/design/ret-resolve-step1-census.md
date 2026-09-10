---
name: ret-resolve-step1-census
title: "RET-RESOLVE step 1: the bare-wildcard census over both source surfaces"
status: "Rev 2, MEASURED 2026-09-10 at v0.23.0 against HEAD 264e8c5, with the installed baseline binary preserved before any rebuild. Step 1 of the nine-step sequence in docs/design/ret-resolve-implementation-plan.md; changes no compiler source. VERDICT, unchanged from Rev 1: the byte-identity prediction is NOT REFUTED and is NOT fully corroborated. Over 318 files and 1400 definition heads, ZERO contracted bare wildcards resolve to a non-FQInt sort; 12 resolve and every one is int; 22 are unresolved by this reader and are not evidence in either direction. Every eliminative count in the plan reproduces exactly, INCLUDING the JSON-AST figure of 139 unannotated heads. REV 2 RETRACTS TWO REV 1 CLAIMS. Rev 1 reported the plan overcounted JSON-AST unannotated heads by 24 and had misclassified totp_filled.ast.json :: generate-totp. Both retractions were wrong and the plan was right, because Rev 1 assumed a returns key on a def head is an annotation. IT IS NOT. Measured by probe: returns:bool over an int body checks OK, while return_type:bool over the same body is a type error; and all six returns keys in erc20.ast.json forced to bool leave check byte-identical. The parser SILENTLY IGNORES returns on a def head. What survives is a sharper finding than either reading: 24 tracked def heads carry a return annotation that the compiler discards, that docs/llmll-ast.schema.json forbids under additionalProperties false, and that nothing validates, because no gate checks a tracked .ast.json against the schema. A THIRD finding stands unchanged: the plan risk-2 blind-spot list is incomplete by one; the measured count is five, not four."
date: 2026-09-10
author: compiler-engineer
consumers: [user, language-team, professor, documentation-lead]
---

# RET-RESOLVE step 1: the bare-wildcard census

**One line.** The prediction that RET-RESOLVE leaves the corpus `.fq` byte-identical survives a
wider search than the one that produced it, and the attempt to fault the plan's JSON-AST numbers
instead uncovered a return annotation that 24 tracked functions declare and the compiler throws away.

## 1. Why this exists

[`ret-resolve-implementation-plan.md`](ret-resolve-implementation-plan.md) sequences nine steps and
puts two measurements before any code, because step 2 can refute the gate's prediction before the
patch exists. Step 1 is the census: read both source surfaces, record the bare-wildcard set, its
resolution, and the Kleene round count, over the whole sweep population.

The plan's own classification claims are marked **corroborative**, not eliminative, with the reason
given in terms: "The reader is not `inferExpr`." This document does not remove that limit. It
re-runs the measurement with an independent reader and reports where the two agree, where they
disagree, and which half of each claim is evidence.

## 2. Verdict

**The byte-identity prediction is not refuted.** Over 318 files and 1400 definition heads, **no
contracted bare wildcard resolves to a sort other than `FQInt`**, on either surface. `typeToSort`
ends `typeToSort _ = FQInt`, so a bare `TVar "?"` and a resolved `int` lower to the same sort and the
emitted bytes do not move.

**It is also not fully corroborated, and the gap is stated rather than absorbed.** Of the 34
contracted bare wildcards found, **12 resolve to a concrete type and every one of those is `int`**.
The other **22 are unresolved by this reader**. An unresolved entry is not evidence that the sort is
unchanged; it is an entry this reader could not decide. Section 7 lists all 22 by name so the sweep
in step 2 can settle them.

**The eliminative half reproduces exactly.** Nine corpus counts, the three S-expression head counts,
and the JSON-AST unannotated count of 139 all match the plan to the digit. Those come from
`git ls-files` and from reading a key, not from modelling inference.

**Rev 1 of this document got the JSON-AST half wrong and section 6 now carries the correction.** The
error and its repair are both instructive, so section 6 records them rather than quietly restating
the right number.

## 3. Method, and what it cannot do

A syntactic reader over both surfaces. It models three compiler rules, named rather than paraphrased:

1. `collectTopLevel` seeds every unannotated head at `TVar "?"`.
2. `checkStatement` never refines the environment binding for a definition, so during the first pass
   a call to an unannotated definition synthesizes the wildcard whatever the source order.
3. `inferExpr` on an `EIf` returns the then-branch type unless `preferConcreteOnSelfCall` fires.
   The Kleene rounds use SC3', the SCC-conditioned variant, so the preference fires for a call to any
   member of the enclosing strongly connected component rather than for a bare self-call only.

Builtin return types are **extracted from `builtinEnv` in `compiler/src/LLMLL/TypeCheck.hs`** by a
balanced scanner, not transcribed, so the table cannot drift from the compiler by hand. Polymorphic
builtins whose result depends on an argument (`first`, `second`, `unwrap`, `unwrap-or`, `list-head`,
`list-tail`, `list-nth`, `pair`, `ok`, `err`, `list-fold`) are given structural rules; the reader
carries structured types rather than flat names for exactly this reason.

**Four limits, and each one biases the count in a named direction.**

1. **The reader is not `inferExpr`.** It approximates. Classification claims below are corroborative.
2. **It is per-file.** It performs no cross-module seeding, so a wildcard whose resolution comes from
   an imported module stays unresolved here. Two of the 22 unresolved entries are exactly that
   case (`xmod-alias/use.llmll` and `xmod-tier/compose.llmll`, both `safe-withdraw`). The plan's step
   6 is where cross-module seeding lands.
3. **It over-reports the bare set** relative to the plan, because unmodelled constructors, `do`
   blocks and `list-map` yield an undetermined type. **This is the safe direction for a refutation
   search:** it examines more candidates than the plan did and still finds no counterexample.
4. **An unresolved entry lowers to `FQInt` in the sort column by default.** That default is the
   compiler's (`typeToSort _ = FQInt`) and is correct for an unresolved wildcard *today*. It says
   nothing about what the entry would resolve to under the pass, which is why section 7 separates
   resolved from unresolved instead of reporting one sort histogram.

The reader lives in the session scratchpad and is **not committed**. Section 9 routes that.

## 4. Corpus size: nine counts, nine reproductions

Measured with `git ls-files`, which is eliminative.

| Population | Plan | Measured | |
|---|---|---|---|
| Rev 2 census corpus, `.llmll` under `examples/`, `compiler/test/fixtures/`, `tools/` | 228 | **228** | reproduces |
| The same roots, `.ast.json` | 79 | **79** | reproduces |
| `FALLBACK-CENSUS-1` population, both surfaces | 250 | **250** | reproduces |
| of which `.llmll` | 175 | **175** | reproduces |
| of which `.ast.json` | 75 | **75** | reproduces |
| Compiler fixture corpus | 68 | **68** | reproduces |
| of which `.llmll` | 64 | **64** | reproduces |
| of which `.ast.json` | 4 | **4** | reproduces |
| **Sweep population, the union** | **318** | **318** | reproduces |

The sweep population is 239 `.llmll` plus 79 `.ast.json`. The plan reaches 318 as 250 plus 68; this
census reaches it as 239 plus 79 over the union of the roots. The two routes agree.

## 5. The S-expression surface reproduces, except the bare count

228 files, over the Rev 2 census roots.

| Claim | Plan | Measured | |
|---|---|---|---|
| Definition heads (`def` and `def-shell`) | 1120 | **1120** | reproduces |
| Unannotated heads | 102 | **102** | reproduces |
| Unannotated and contracted | 30 | **30** | reproduces |
| Kleene rounds to fixpoint | 2 | **2** | reproduces |
| Heads with a bare `TVar "?"` recorded `tau_ret` | 16 | **35** | differs |
| of those, contracted | 13 | **16** | differs |
| Contracted bare wildcards that resolve, all to `int` | 12 of 12 | **10 of 10** | direction reproduces |

**The bare count is unreconciled and the difference is not a defect in either direction.** This
reader over-reports (limit 3 above); the plan's reader may have been narrower. What matters for the
gate is that the larger candidate set contains no counterexample. `examples/banking_ledger/banking.llmll`
reproduces the plan's per-file figure exactly: four contracted bare wildcards, every one resolving to
`int`.

## 6. The JSON-AST surface, and the retraction that produced the real finding

79 files, 276 definition heads.

### 6.1 What Rev 1 claimed, and why it was wrong

Rev 1 of this document reported two refutations of the plan. **Both are withdrawn.** The plan was
right on both counts, and the reasoning that produced the retractions is worth keeping because the
repair is the finding.

Rev 1 observed that the tracked `.ast.json` corpus carries two spellings on definition heads,
`return_type` on 137 and `returns` on 24, with zero heads carrying both. It then assumed both are
return annotations, concluded that the plan's 139 unannotated heads was `276 - 137` and therefore an
overcount of exactly 24, and concluded that
`examples/totp_rfc6238/totp_filled.ast.json :: generate-totp` was an annotated head rather than a
bare wildcard.

**The assumption was never tested, and it is false.**

### 6.2 The probe

Two definition heads, identical bodies returning `int`, differing only in the key that declares a
`bool` return. Run against the preserved v0.23.0 baseline binary:

| Probe | Declared | Body | `llmll check` |
|---|---|---|---|
| `"returns": bool` | `bool` | `(+ x 1)`, an `int` | **OK, no error** |
| `"return_type": bool` | `bool` | `(+ x 1)`, an `int` | **`error: type mismatch in 'p': expected bool, got int`** |

Confirmed on a real corpus file rather than on the synthetic pair alone. All six `returns` keys in
`examples/erc20_token/erc20.ast.json` were rewritten to `bool` over their `int` bodies. `check`
returns the identical result, `OK (6 statements, 6 warnings)`.

**The parser silently ignores a `returns` key on a definition head.** Only `return_type` is an
annotation. With the reader corrected, the JSON-AST unannotated count is **139**, which is the
plan's figure to the digit, and `generate-totp` is a contracted bare wildcard resolving to `int`,
which is the plan's classification exactly.

### 6.3 The finding that survives, which is larger than either reading

**Twenty-four tracked definition heads declare a return type that nothing honours and nothing
rejects.** Three facts compose:

1. **The compiler discards the key.** Measured above.
2. **The schema forbids the key.** `docs/llmll-ast.schema.json` defines `def` and `def-shell` with
   `"additionalProperties": false` and declares `return_type` as the only return key. Those 24 heads
   are therefore schema-invalid. The `returns` spelling does exist in the schema, but on a different
   shape: a DEMO-COMP brief, where `return_type` is documented as "alias of 'returns'". The alias
   runs the other way there, which is how the two spellings came to look interchangeable.
3. **Nothing validates the corpus against the schema.** A search of `scripts/` and `compiler/test/`
   finds no JSON-Schema validation of a tracked `.ast.json` at all. So neither the parser nor CI
   reports these heads.

The consequence is a silent one. `examples/erc20_token/erc20.ast.json` declares `int` returns on
`total-supply`, `balance-of`, `transfer`, `approve` and two more, and not one of those declarations
is checked against its body. `transfer` is one of the two functions `FRAGMENT-BASIS-1` named as the
only contract-post fragment escapes in the whole tree, so this is not confined to a quiet corner of
the corpus.

**Two independent readers have now been wrong about this key in opposite directions.** The plan's
census read `return_type` only and reported the compiler-true count. Rev 1 of this document read both
and reported a count no component of the system agrees with. A field that two readers cannot agree on
is an instrument defect regardless of which reader was right, and section 9 routes it to the schema
surface rather than to `RET-RESOLVE`.

### 6.4 The JSON-AST surface, measured with the corrected reader

| Claim | Plan | Measured | |
|---|---|---|---|
| Definition heads | 276 | **276** | reproduces |
| Unannotated heads | 139 | **139** | reproduces |
| Kleene rounds | 2 | **2** | reproduces |
| `totp_filled.ast.json :: generate-totp`, contracted bare, resolves to `int` | yes | **yes** | reproduces |
| Bare wildcards | 6 | **41** | differs, see section 5 on direction |
| of those, contracted | 1 | **18** | differs |
| Contracted bare resolving to a non-`FQInt` sort | 0 | **0** | reproduces |

Both of the plan's characterized resolutions reproduce exactly:
`examples/hangman_json_verifier/hangman.ast.json :: game-won?` resolves to **`bool`**, and
`examples/life_json/world.ast.json :: evolve` resolves to a **pair**.

## 7. The contracted bare wildcards, resolved and unresolved

Over the full 318-file sweep population: **1400 definition heads, 244 unannotated, 70 unannotated and
contracted, 76 bare `tau_ret`, of which 34 are contracted.** Kleene reaches the fixpoint in **2
rounds** on both surfaces, one productive and one confirming.

**Resolved: 12 of 12 resolve to `int`.** No counterexample on either surface.

**Unresolved by this reader: 22.** These are not evidence in either direction, and step 2's sweep is
what settles them.

| File | Function | Why it is unresolved here |
|---|---|---|
| `compiler/test/fixtures/xmod-alias/use.llmll` | `safe-withdraw` | cross-module; needs the step 6 seed |
| `compiler/test/fixtures/xmod-tier/compose.llmll` | `safe-withdraw` | cross-module; needs the step 6 seed |
| `examples/benchmarks/b1-withdraw.llmll` | `withdraw` | reader gap |
| `examples/benchmarks/b5-double.llmll` | `double` | reader gap |
| `examples/proof_required_test/proof_required_test.llmll` | `safe-div` | reader gap |
| `examples/withdraw-demo/withdraw.llmll` | `withdraw` | reader gap |
| `examples/erc20_token/erc20.ast.json` | `allowance` | hole body; and see section 6.3 |
| `examples/erc20_token/erc20.ast.json` | `approve` | hole body; and see section 6.3 |
| `examples/erc20_token/erc20.ast.json` | `balance-of` | hole body; and see section 6.3 |
| `examples/erc20_token/erc20.ast.json` | `total-supply` | hole body; and see section 6.3 |
| `examples/erc20_token/erc20.ast.json` | `transfer` | hole body; and see section 6.3 |
| `examples/erc20_token/erc20.ast.json` | `transfer-from` | hole body; and see section 6.3 |
| `examples/orchestrator_walkthrough/auth_module.ast.json` | `login-handler` | reader gap |
| `examples/tictactoe_json_verifier/tictactoe.ast.json` | `make-board` | reader gap |
| `examples/tictactoe_json_verifier/tictactoe.ast.json` | `set-cell` | reader gap |
| `examples/totp_rfc6238/totp.ast.json` | `compute-time-step` | hole body; and see section 6.3 |
| `examples/totp_rfc6238/totp.ast.json` | `dynamic-truncate` | hole body; and see section 6.3 |
| `examples/totp_rfc6238/totp.ast.json` | `generate-totp` | hole body; and see section 6.3 |
| `examples/totp_rfc6238/totp.ast.json` | `pad-otp` | hole body; and see section 6.3 |
| `examples/totp_rfc6238/totp.ast.json` | `validate-totp` | hole body; and see section 6.3 |
| `examples/withdraw-demo/withdraw.ast.json` | `withdraw` | reader gap |
| `tools/llmll-orchestra/fixtures/auth_module/auth_module.ast.json` | `login-handler` | reader gap |

**Eleven of the 22 are in `erc20.ast.json` or `totp.ast.json`, and those are the files section 6.3
names.** Their heads carry a discarded `returns` key and an unfilled hole body, so the reader has
neither a declaration nor a body to work from. Whether the pass resolves them at all depends on what
fills the holes, which is not a question this census can answer and not one step 2 answers either.

## 8. The gate's blind spot is confirmed, and it is one entry larger than the plan says

The plan's risk 2 names **four** contract-free change candidates invisible to the `.fq` gate. A
contract-free function emits no constraint, so a resolution change inside it moves nothing in the
file and the gate reports an agreement it never checked.

Measured, the count is **five**:

| File | Function | Resolves to | Sort |
|---|---|---|---|
| `examples/hangman_sexp/hangman.llmll` | `game-won?` | `bool` | `FQBool` |
| `examples/life_sexp/world.llmll` | `evolve` | pair | `FQPair` |
| `examples/hangman_json/hangman.ast.json` | `game-won?` | `bool` | `FQBool` |
| `examples/hangman_json_verifier/hangman.ast.json` | `game-won?` | `bool` | `FQBool` |
| `examples/life_json/world.ast.json` | `evolve` | pair | `FQPair` |

The four the plan lists are rows 2 to 5. **The missing entry is row 1**, and the plan names it in a
different section, its Rev 2 census summary, as one of "the three non-contracted wildcards". So the
document has the fact and the risk list does not carry it.

This does not change the plan's conclusion, which is that byte-identity is an incomplete gate and a
second half is owed comparing the fallback set and the trust tiers. It widens the population that
second half must cover by one file on the S-expression surface.

## 9. What is owed

1. **Step 2 remains the decision point.** Twenty-two contracted bare wildcards are unresolved here.
   The pre-change baseline sweep settles the ones with real bodies against the actual `inferExpr`
   rather than against a model. The eleven with hole bodies are settled by whatever fills the holes.
2. **The plan needs one correction, and it is smaller than Rev 1 of this document claimed.** Its
   corpus-measurement section stands. Its risk-2 blind-spot list gains
   `examples/hangman_sexp/hangman.llmll :: game-won?`, which the plan already names in its own Rev 2
   census summary. That edit is the compiler-engineer's, on the compiler-engineer's document.
3. **The discarded `returns` key belongs to the schema surface, not to `RET-RESOLVE`.** Twenty-four
   tracked definition heads declare a return type that the parser throws away, that the schema
   forbids under `"additionalProperties": false`, and that no gate validates. Section 6.3 gives the
   evidence. File it against the schema surface, where the decision is whether the parser should
   reject the key, whether the schema should admit it, and whether a tracked `.ast.json` should be
   validated against the schema at all.
4. **The reader is not committed.** It lives in the session scratchpad. A census that cannot be
   re-run is a claim, not an instrument. If this census is to gate anything, the reader belongs under
   `scripts/` with a cover, in the shape `scripts/fallback_census.py` already established.
