---
name: ctor-decl-guard-proposal
title: "CTOR-DECL-GUARD-1: a constructor the .fq file cannot sort gives a disclosed fallback, not a solver crash"
status: "Rev 1, SETTLED 2026-11-04 (user-approved). The user accepted the recommendation: a new cause `constructor-not-reflected`; option B (withdraw recursive sums, repair imported sums and `bytes[n]` fields). No professor pass: the proposal applies a settled rule."
date: 2026-11-04
author: language-team
rows: "CTOR-DECL-GUARD-1 (G1, PLAN after settlement). Filed from the CTOR-FIELD-SORT-1 plan (closed, v0.36.0). Related: ALIAS-SUM-SORT-1 (G1, PLAN), FQ-FREEVAR-GUARD-1 (shipped)."
consumers: [user, compiler-engineer, documentation-lead]
---

# CTOR-DECL-GUARD-1: constructors the .fq file cannot sort

**Status: Rev 1, SETTLED 2026-11-04.** The language-team wrote Rev 1 on 2026-11-04 and measured each case on 0.36.0. The user accepted the recommendations the same day. The row moves from DECIDE to PLAN.

All measurements are on `llmll 0.36.0`, built from main `a339fbb8` with `stack build`, and liquid-fixpoint 0.9.6.3.7. The witness programs were run outside the repository; the engineer adds them as fixtures with the names used below.

## Restatement

Three shapes of constructor reach liquid-fixpoint with a sort the solver cannot accept. The solver stops with "elaborate solver failed", `verify` exits 1, and no function in the file gets a verdict. The row asks for the cause name a withdrawn function gets, and then a guard and one repair. This proposal also asks the user to decide how many of the three cases to repair rather than withdraw.

## Decisions (settled by the user, 2026-11-04)

The user accepted each recommendation below.

**Question 1 (the row's DECIDE).** What cause name does a function get when its constraint applies a constructor that the `.fq` file does not declare as a datatype constructor with the matching arity?

**Recommendation.** A new cause, `constructor-not-reflected`, with the constructor named in `erFallbackConstructs` as `ctor:<Name>`. Do not reuse `constraint-symbols-unbound`: in two of the three cases the symbol is declared, so that name would be false.

**Question 2 (scope).** Which cases does this row repair, and which does it only withdraw?

**Recommendation.** Option B below. Withdraw case 1 (it is outside the decidable fragment by `LLMLL.md §3.4.3`). Repair case 2 by emitting the imported `data` declaration. Repair case 3 by declaring a `bytes[n]` field at the array sort. The arity guard cannot catch case 3, so case 3 must be repaired, not guarded.

## Context located

1. `docs/compiler-team-roadmap.md` row `CTOR-DECL-GUARD-1` and closed row `CTOR-FIELD-SORT-1`.
2. `compiler/src/LLMLL/FixpointEmit.hs:3541-3555` `admissibleDatatype`: a sum that reaches a cycle is not admissible.
3. `FixpointEmit.hs:3559-3570` `typeSorts`: an inadmissible sum gets a `data` declaration whose constructors have no fields.
4. `FixpointEmit.hs:3591-3604` `fieldSort`: keeps `typeToSort` for an owner that reaches recursion and for a sort that names a sum not in `localSums`.
5. `FixpointEmit.hs:3670-3683` `buildCtorSums`: the match translator's field map, from the same `fieldSort`.
6. `FixpointEmit.hs:891-892` `localSums`: the entry module's `STypeDef` sums only. `:751` `dataScanStmts` includes imported statements for the Pair2 and Result checks, but `typeSorts` runs only over the entry module's `stmts` (`:907-910`).
7. `FixpointEmit.hs:6467-6479` `measureConstant`: an unknown applied symbol gets the default sort `[Str] -> int`. An imported `ctor_*` symbol falls here.
8. `FixpointEmit.hs:1020-1035` `ctorNames`: only constructors in `dataDecs` are excluded from the measure sweep.
9. `FixpointEmit.hs:1054-1110` FQ-FREEVAR-GUARD-1: routes a function whole to fallback when a constraint names a symbol its environment lacks. This is the site the row names.
10. `FixpointEmit.hs:266-277` `FallbackCause` and `renderFallbackCause`: the existing cause names.
11. `FixpointEmit.hs:3976-3991`, the `exprToPred` match comment. **The row is now partly incorrect.** It says the comment claims FQ-FREEVAR-GUARD-1 withdraws such a constructor. The comment was corrected in `6adae19e` and now says "withdraws neither". The third item of the row's plan is done.
12. `LLMLL.md §3.4.3`: `Σ_auto` contains the **acyclic** datatype theory. A recursive datatype in a body-faithful VC would make the verdict depend on the solver run.
13. `LLMLL.md §4.1` (return annotation paragraph): "a constructor-dependent post over a non-admissible type stays a deliberate fallback". **Spec-code drift:** the code crashes where the spec says fallback.
14. `examples/netpbm-swarm/types.llmll:22-27`: a user comment that documents the case 2 crash ("The sort Str is not numeric") and the workaround (declare each sum in the module that produces it).

No design record exists on this topic (`docs/design/INDEX.md`, checked).

## Witnesses and measurements

Each witness was run with `llmll verify`. "Crash" means exit 1, "elaborate solver failed", and no `.verified.json`.

| Witness | Shape | Today | `.fq` cause |
|---|---|---|---|
| `w1_rec.llmll` | `(type Tree (\| Leaf int) (\| Node Tree))`, `def-shell mk` post `(= result (Node (Leaf n)))` | crash | `data Tree 0 = [ \| ctor_leaf { } \| ctor_node { }]`, arity 0 applied to 1 argument; `result` bound at `int` |
| `w1b_mutrec.llmll` | `A (\| AStop int) (\| AGo B)`, `B (\| BStop int) (\| BGo A)`, post `(= result (AGo (BStop n)))` | crash | the same, for a mutual cycle |
| `w1c_field_rec.llmll` | `W (\| Wrap Tree) (\| Nil int)`, post `(= result (Nil n))` | crash | `W` reaches `Tree`, so `W` is inadmissible and fieldless. **The constructor applied has an `int` field and still crashes.** |
| `imp/w2_imp.llmll` | `T (\| Big int) (\| Small int)` in `imp/tlib.llmll`; importer `def mk` post `(= result (Big n))` | crash | no `data T`; `constant ctor_big : func(0, [Str; int])` |
| `imp/w2c_impwrap.llmll` | importer declares `W (\| Wrap T) (\| Nil int)`, post `(= result (Wrap (Big n)))` | crash | the same as `w2_imp` |
| `imp/w2b_impfield.llmll` | the same `W`, post `(= result (Nil n))` | SAFE | a constructor of the imported sum is not applied |
| `imp/w2d_match.llmll` | importer matches on `t: T` | SAFE | matching an imported sum works, as the netpbm comment says |
| `w3_bytes.llmll` | `Blob (\| Full bytes[4]) (\| Empty int)`, `def mk [b: bytes[4]]` post `(= result (Full b))` | crash | `ctor_full_0 : int`, but `b : (Map_t int int)`. **Arity 1 matches.** |
| `w3b_bytes_gate.llmll` | the same with a `bytes-get` pre | crash | the same |
| `imp/w3g.llmll` | a `bytes[4]` value from an imported callee `zb`, in a function with no bytes operation | crash | the callee result binder is `(Map_t int int)` too |
| `w4_map.llmll` | a `map[int,int]` field | fallback, `constraint-symbols-unbound` | caught today by FQ-FREEVAR-GUARD-1 |
| `w5_list.llmll`, `w6_str.llmll` | a `list[int]` field, a `string` field | verified | `Lst`, `Str` field sorts are correct |

**What a repair would give.** Hand-patched `.fq` files, run with `fixpoint` directly:

- `patched/w2_imp.fq` with `data T 0 = [ | ctor_big { ctor_big_0 : int } | ctor_small { ctor_small_0 : int }]` added: Safe.
- `patched/w3_bytes.fq` with `ctor_full_0 : (Array_t int int)`: Safe. `imp/w3g_p.fq` with the same field: Unsafe, which is the correct verdict (the `Full` branch breaks the post `(= result (Empty n))`).
- `patched/w1_rec.fq` with full recursive fields and `result : Tree`: Safe. A wrong post (`w1_rec_ref.fq`) is Unsafe, and a selector goal (`w1_rec_sel.fq`) is Safe. So liquid-fixpoint accepts a recursive declaration. The obstacle for case 1 is the spec (§3.4.3), not the solver.

**A finding on the row's plan.** The row's guard fires when "a constraint applies a `ctor_*` symbol with no declaration or with an arity that differs from its declaration". That guard catches case 1 (arity 0, applied to 1). It catches case 2 only if "no declaration" means "no `data` declaration", because `measureConstant` declares the symbol as a `constant`. **It does not catch case 3.** In case 3 the constructor is declared, the arity is 1, and only the field sort is wrong. A guard on declaration and arity alone leaves case 3 a crash.

**A finding on the row's case 3 text.** The row says a bytes binder's sort depends on the per-function array gate, "so no one field sort is right". On every source measured, the bytes term is array-sorted: a `bytes[n]` parameter (its length pre self-activates the gate, FACT-AG-LEN) and an imported callee result (`imp/w3g.llmll`, in a function with no bytes operation). So the array sort is the one field sort observed. A source that still binds a bytes term at `int` was not found.

## Options

**Option A. Guard only.** Add the guard at the FQ-FREEVAR-GUARD-1 site. Any constraint that applies a `ctor_*` symbol that is not a `data` constructor of matching arity routes its owning function whole to fallback, cause `constructor-not-reflected`. Cases 1 and 2 become fallbacks. Case 3 stays a crash unless the guard also compares sorts, which needs sort inference over constraint terms in the emitter. File the repairs as separate rows.

**Option B. Guard, plus repair cases 2 and 3 (recommended).**
- Case 1: guarded, as in A. This agrees with §3.4.3 and with the §4.1 sentence "stays a deliberate fallback".
- Case 2: emit the `data` declaration of each imported sum whose constructor occurs in a constraint, with its field sorts by `fieldSort`, and include imported sums in `localSums`. The guard stays as a net for any residue (for example an imported recursive sum, which then is case 1).
- Case 3: in `fieldSort`, a `bytes[n]` field (after alias expansion) gets the array sort that `sortA1` gives a bytes binder. The guard does not cover this case, so the acceptance must include `w3_bytes`, `w3b_bytes_gate` and `imp/w3g`.

**Option C. Option B, and also emit recursive sums in full.** The solver accepts it (`patched/w1_rec*.fq`). But it reverses `LLMLL.md §3.4.3`: a recursive datatype is outside `Σ_auto`, and the spec states the verdict would then depend on the solver run. It also overturns the ADT-CARRIER-COLLAPSE-1 pins (`ModuleSpec` ACR-5 to ACR-10) and the strict-core gate's refusal of recursive constructors. The gain is small: with no induction, few posts over a recursive value are provable. This is an addition with its own soundness argument, not a repair. It does not belong in this row.

## Why option B is sound

1. **The guard only removes claims.** A routed function's VC is withdrawn and its post is assumed and disclosed (`W-BODY-FALLBACK`, tier `asserted`). It cannot produce `verified` or `refuted`. Today the file gives no verdict at all, so the guard changes "no verdict" into "disclosed fallback" for the routed function and a real verdict for every other function in the file.
2. **Case 2 adds a declaration that matches the source.** The imported `STypeDef` is the same type the importer's terms are typed against (the module cache, `meStatements`). The emitted declaration has the same constructors and the same field sorts it would have in the declaring module. No fact is added. The datatype axioms (constructor injectivity, distinctness, selectors) hold for the run-time values, because codegen compiles the sum to a Haskell `data` type.
3. **Case 3 corrects a sort, and adds no fact.** A `bytes[n]` value is already reflected as an array in every binder. Declaring the field at the same sort makes the term well-sorted. The length fact is not attached to the field; it stays earned per position (`LLMLL.md §5.3.3`, array class). A matched `Full b` payload is not given `bytesLen(b) = 4` by this change.
4. **Admissibility does not change.** Case 2 and case 3 do not change which sums are admissible. A recursive imported sum stays fieldless and is guarded.

## Design proposal

**Cause.** Add `FallbackCtorNotReflected`, rendered `constructor-not-reflected`. Record `ctor:<Name>` for each constructor that triggered it, on the `erFallbackConstructs` channel, as `post-unassumed:app:<callee>` does for its cause. The warning text: "'f' applies constructor C, whose datatype the verifier does not reflect (a recursive or non-admissible sum). Its body VC is withdrawn and its post is assumed."

**Guard predicate.** Over the assembled file, flag a constraint when a term `FQApp c args` has `c` with the `ctor_` prefix and either (i) `c` is not a constructor of any `data` declaration, or (ii) `length args` differs from the declared field count. Route the owning function whole, as FQ-FREEVAR-GUARD-1 does, so its call-pre constraints are withdrawn with it. Keep an orphan constraint (no origin) as today. Run the check before the free-symbol check, so a function that matches both gets this cause and not `constraint-symbols-unbound`.

**Where the guard sits.** At the assembled-file boundary, next to FQ-FREEVAR-GUARD-1. A translator-level refusal (`exprToPred` returning `Nothing` for a constructor of an inadmissible sum) would give the existing causes and a finer route at call sites. But constructors reach the file through at least four translators (body, pre/post, callee post at a call, match reflection), and FQ-FREEVAR-GUARD-1 exists because per-translator checks missed sites. The boundary check is the net. A translator-level refinement can follow later.

**Repairs.** Case 2 and case 3 as described under Option B.

**Comment.** No change needed; `6adae19e` already corrected it. The row text should drop that item.

**Spec text for `LLMLL.md`** (doc-lead, after the engineer ships): add `constructor-not-reflected` to the list of fallback causes, with "a constraint applies a constructor of a recursive or non-admissible sum". Extend the §4.1 sentence: "a constructor-dependent post over a non-admissible type stays a deliberate fallback (cause `constructor-not-reflected`)".

## Edge cases and degenerate inputs

E1. **Positive witness, recursive.** `w1_rec.llmll`. Expected: `mk` falls back with `constructor-not-reflected`, `ctor:Node`. Exit 0, partial. Channel: trust.

E2. **Positive witness, mutual recursion.** `w1b_mutrec.llmll`. Expected: as E1, `ctor:AGo`. Channel: trust.

E3. **A non-recursive constructor of an inadmissible sum.** `w1c_field_rec.llmll`, post `(= result (Nil n))`. `Nil` has an `int` field, but its owner `W` is fieldless. Expected: fallback, `ctor:Nil`. This shows that the trigger is "any payload constructor of an inadmissible sum", wider than the row's title. Channel: trust.

E4. **Positive witness, imported.** `imp/w2_imp.llmll` and `imp/w2c_impwrap.llmll`. Expected under option B: both verify, because `data T` is emitted. Under option A: both fall back with `ctor:Big`. A wrong post (`(= result (Small n))`) must be refuted under B. Channel: contract (B) or trust (A).

E5. **Positive witness, bytes field.** `w3_bytes.llmll`, `w3b_bytes_gate.llmll`, `imp/w3g.llmll`. Expected under option B: `w3_bytes` verifies, `imp/w3g` is refuted (measured on the patched `.fq`). Under option A: still a crash, because arity matches. Channel: contract.

E6. **Matching on an imported or recursive sum.** `imp/w2d_match.llmll` verifies today. Expected: unchanged. The guard reads applied constructor terms; a match reflects through selectors of a declared type, or skolemises. Note that under option B, a match on an imported sum may start to reflect through the new `data T` instead of skolemising. The census must show no verdict change from that. Channel: contract.

E7. **Name collision.** The importer declares a sum with the same name as an imported sum, or two imports declare one name. Expected: emit the imported declaration under its qualified name, or do not emit it and guard. Never emit two `data` declarations with one name. Spec is silent (gap, flag); the engineer must choose and test it.

E8. **Transitive import.** `T` imported from `a`, with a field of a sum from `b` that `a` imports. Expected: emit both declarations; `fieldSort` must see both in the extended `localSums`. If either is not emitted, the field keeps `int` and the guard does not catch the mismatch (as case 3). So the extended set must be closed under field reference. Channel: contract.

E9. **A map field.** `w4_map.llmll`. Expected: unchanged, fallback `constraint-symbols-unbound`. A map value splits into two arrays and cannot be one field. Not this row. Spec is silent (intentional).

E10. **An alias to a sum as a field.** Handled by `ALIAS-SUM-SORT-1`, not here. The guard does not catch it, because arity matches.

## Verification mapping

| Obligation or change | Channel | Fragment |
|---|---|---|
| Withdrawal by the guard | trust (fallback, `asserted`) | none: no obligation is emitted |
| A post over an imported admissible sum (case 2 repaired) | contract | (a) acyclic datatype theory with QF-LIA, auto-discharged, `LLMLL.md §3.4.3` |
| A post that builds a constructor with a `bytes[n]` field (case 3 repaired) | contract | (a) datatype theory with arrays and QF-LIA, the combination §5.3.3 already cites for the array class |
| A post over a recursive sum (case 1) | trust | outside `Σ_auto` by §3.4.3; no Lean route is added |

## Affected surface

1. `compiler/src/LLMLL/FixpointEmit.hs`: `FallbackCause` and `renderFallbackCause` (new cause); the guard next to FQ-FREEVAR-GUARD-1; `localSums` and the `typeSorts` loop extended to imported sums whose constructors occur in a constraint; `fieldSort` gains a `bytes[n]` arm.
2. `scripts/fallback_census.py`, the only file outside `FixpointEmit.hs` that names cause strings (grep). The new cause must be listed there.
3. `LLMLL.md`: the fallback-cause list and the §4.1 sentence.
4. `examples/netpbm-swarm/types.llmll:22-27`: the comment about imported sums becomes incorrect under option B. The doc-lead should correct it.
5. `docs/compiler-team-roadmap.md` row text: drop the comment item; state that the arity guard does not cover case 3.

No addition: no new builtin, construct, capability or FFI tier. Option C would be one.

## Risks and open questions

1. **Case 3 under option A stays a crash.** Classification: scope. The row's acceptance ("each of the three witnesses gives a verdict or a disclosed fallback") cannot pass with a declaration-and-arity guard alone. The bite: blocks option A as written.
2. **Emitting imported declarations changes match reflection.** Classification: verification-ergonomics. A match on an imported sum may move from skolem to datatype reflection (E6). The bite: complicates; the census decides it.
3. **An int-sorted bytes term may exist on a path not measured.** Classification: verification-ergonomics. Then the array field sort crashes on that path, and the guard does not catch it. The bite: only matters at scale. The engineer should search the binder-sort sites for a `TBytes` that reaches `typeToSort` instead of `sortA1`.
4. **The crash is not a soundness defect.** Classification: scope. A crash gives no verdict, so nothing false is reported. The stake is that one such constructor removes the verdict of every function in the file, and the spec says fallback. This sets the priority, not the design.

No question for the professor. The only PL question, recursive datatypes in `Σ_auto`, is already settled by §3.4.3, and this proposal does not reopen it.

## Acceptance

`w1_rec`, `w1b_mutrec`, `w1c_field_rec` fall back with `constructor-not-reflected`. `imp/w2_imp` and `imp/w2c_impwrap` verify, and a wrong post on each is refuted. `w3_bytes` verifies and `imp/w3g` is refuted. `imp/w2d_match`, `w4_map`, `w5_list`, `w6_str` keep today's result. The census shows no other change.
