---
name: ret-resolve-proposal
title: "RET-RESOLVE: resolve a wildcard `τ_ret` transitively in a verification-facing pass"
status: "Rev 3, SETTLED. The design does NOT reopen: the Kleene rule, SC1/SC2′/SC3′, the corpus prediction and I1/I2 stand exactly as settled at Rev 2 (four professor review rounds folded). Rev 3 is a routed correction of the CHANNEL ACCOUNT and the PREREQUISITE CHAIN, measured against HEAD at v0.23.0 by docs/design/ret-resolve-implementation-plan.md. Four channels become FIVE: channel 4a (resultLenFact) was DELETED at v0.14.78, two live channels Rev 2 never named are added (4b, post-assumption unblocking at a call site; 4c, ground LHS range facts), and wholeArrEqClause is separated out as channel 5 with its direction corrected. The Rev 2 trust-base disclosure claim is RE-DERIVED and NARROWS to channel 4c alone: 4a is gone, 4b is a repair whose soundness FACT-AG-LEN Stage 3 supplies, and 4c is owed a section 5.3.5 sentence scoped to the life of the open row ARR-RANGE-NAME. Channel 3 is recorded as ASYMMETRIC for the first time: a resolved return adds a definition-site obligation and exports no caller guarantee. Rev 2 called a byte-identical corpus .fq a COMPLETE gate; it is not, because a contract-free function emits no constraint, and four corpus candidates sit in that blind spot. Two affected-surface errors corrected: the stamp is checkerSoundnessVersion in VerifiedCache.hs, not codegen_semantics_version in ProofArtifact.hs, and Main.emitSynthetic is a third consumer of tau_ret. Bare line-number citations replaced by construct names. ALL PREREQUISITES DISCHARGED; RET-RESOLVE is UNBLOCKED. Roadmap row: RET-RESOLVE"
date: 2026-07-29
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# RET-RESOLVE: resolve a wildcard `τ_ret` transitively

**One line.** `collectTopLevel` registers an unannotated return as `TVar "?"`, callers inherit that
wildcard through `inferExpr`, and `sortA1` lowers it to `FQInt`. Resolving the wildcard as a
post-pass over the recorded return-type map closes nine measured crash shapes at the root instead of
one shape at a time.

## Background: what shipped and what did not

FQ-RESULT-SORT-1 stages (a) and (b) plus RET-BRANCH-PREF Stage 1 shipped in **v0.14.72**
(`d97d388`, `68bca3e`, `eb9e1db`; release `f599c8e`). The roadmap row claims the residual is closed
by RET-BRANCH-PREF. Measured against v0.14.72, nine shapes survive, and one of them is a behavioral
conversion introduced by that release.

| Probe | Shape | v0.14.71 | v0.14.72 |
|---|---|---|---|
| `T4a` | bare self-call in `then`, contracted | CRASH `bool` | **verdict** (Stage 1 closed it) |
| `A` | foreign unannotated callee in a branch | CRASH | CRASH |
| `B` | foreign unannotated callee as the whole body | CRASH | CRASH |
| `C` | self-call under `let` | CRASH | CRASH |
| `D_let` | foreign call under `let`, bound then returned | CRASH | CRASH |
| `Q_nested` | foreign call nested two `if`s deep | CRASH | CRASH |
| `M_shellmut` | mutual recursion, two `def-shell`s, literal anchors | CRASH | CRASH |
| `xmod-B` | `B` across a module boundary | not run | CRASH |
| `F_pair` | unannotated callee returning a pair | CRASH `Pair2` | CRASH `Pair2` |
| **`E_str`** | unannotated callee returning a string | **REFUTED verdict** | **CRASH `Str`** |
| `L_mono` | `(let [(r (g n))] (+ r 1))`, `g` returns bool | CRASH operands | CRASH operands |
| `P_int` | unannotated callee returning int (control) | verdict | verdict |
| `R_result` | unannotated callee returning `(ok n)` | not run | verdict (latent) |
| `S_anchorless` | anchorless `def-shell` cycle, contracted | not run | verdict, no crash |

All crashes exit 1. Three of these rows carry the argument for a root fix.

**`E_str` is a conversion, and it is the structural argument.** Before the fix, `synthRet` /
`bodyIsBoolean` ([`FixpointEmit.hs:265-287`](../../compiler/src/LLMLL/FixpointEmit.hs), R1
bool-ret-synth, v0.14.14) synthesized a callee return type only for syntactically boolean bodies, so
a string-returning unannotated callee's call binder defaulted to `FQInt` and matched the equally
defaulted `result` binder; liquid-fixpoint elaborated and returned a correct REFUTED. At HEAD `τ_ret`
makes that call binder `Str` while `result` stays `FQInt`, so the same program crashes. The rule this
exposes: **each increment of sort precision on one side of the reflection equation converts a
silently recovered constraint into a crash on the other, until both sides derive from one source.**

**`R_result` is the next latent instance.** `calleeRetSort` (`:3165-3168`) lowers through
`typeToSort`, whose default is `FQInt` (`:2441`), so an unannotated callee returning `(ok n)` gets an
`int` call binder today and reaches a verdict. Making that site alias-aware converts it to a crash
exactly as stage (b) did for `E_str`. Shape-by-shape re-scoping schedules that conversion for later.

**`L_mono` is the residue no version of this proposal closes.** It type-checks today
(`compatibleWith (TVar _) _ = True`, [`TypeCheck.hs:2185`](../../compiler/src/LLMLL/TypeCheck.hs))
and crashes in the solver on `bool + int`. See "Residue" below.

## Corpus census

Syntactic reader over 151 `.llmll` files in `examples/`, `compiler/test/fixtures/`, `tools/`. It
approximates `inferExpr` over return-position forms and does not follow imports, so it
over-approximates resolvability and under-counts wildcards.

- 937 definition heads, **102 unannotated**, 30 unannotated **and** contracted.
- **18** heads whose `τ_ret` is a wildcard, 15 of them contracted.
- Of those 18: **10 resolve transitively to `int`, all contracted** (`examples/banking_ledger/` ×8,
  `examples/withdraw-demo/` ×2, chains `withdraw → safe-subtract`, `transfer → withdraw`); **3**
  resolve to a type the reader cannot name, all non-contracted (`hangman_sexp`, `life_sexp` ×2);
  **5 are hole bodies** (`?body_impl` and friends), a class distinct from inference wildcards.
- **Zero cycles.**

The consequence that reprices the proposal: every contracted corpus wildcard resolves to `int`, and
`sortA1 int` is the `FQInt` the emitter already defaults to, so RET-RESOLVE is predicted to leave all
128 corpus `.fq` files **byte-identical** and to demote nothing. HOLE-RET, the withdrawn stage (c) of
FQ-RESULT-SORT-1, changed 10 `.fq` files and demoted 12 functions. Same gate, opposite prediction,
and the prediction is checkable before the code is written.

## The rule

Let `τ⁰ = tcRetTypes` after `checkStatements` returns
([`TypeCheck.hs:826`](../../compiler/src/LLMLL/TypeCheck.hs)). Order each entry by
`TVar "?" ⊏ τ` for concrete `τ`, with named-hole types as isolated fixed points. Let `Γ_Δ` bind each
top-level `g` at `TFn (paramTypes g) (Δ g)`.

```
    F(Δ)(f)  =  τ    if  Δ(f) = TVar "?"  and  Γ_Δ ⊢ body(f) ⇒ τ  with τ concrete
             =  Δ(f) otherwise

    τ_ret    =  lfp above τ⁰ of F                                    (Ret-Resolve)
```

`F` is monotone on a product of flat lattices, so Kleene iteration from `τ⁰` converges (Cousot and
Cousot, POPL 1977; the dataflow analogue is Kildall, POPL 1973). Bound: one pass per
strongly-connected component in reverse topological order, which is the `tiSeq` / `tiBindGroup` shape
of Jones, *Typing Haskell in Haskell* (Haskell Workshop 1999) §11. The in-tradition instance to cite
in the spec is liquid type inference as a monotone fixpoint downstream of base-type inference
(Rondon, Kawaguchi and Jhala, PLDI 2008), staged as in Vazou et al. (ICFP 2014). This is **not** a
join: "concrete wins over the re-synthesized value" is a `τ⁰`-biased update, so state it as Kleene
iteration of a monotone update rather than with lattice-join notation.

### Side conditions

**SC1, wildcard-only refinement.** `F` replaces a bare `TVar "?"` only. Named-hole types are
retained, which preserves sketch mode; the discriminant is in the code already, since
`collectTopLevel` produces bare `TVar "?"` (`:919-936`) while `inferHole` produces
`TVar ("?" <> name)` (`:1600`), and both satisfy `isHoleVar` (`:342-344`). A concrete `τ⁰` is
**never revised**, even when re-synthesis in the strengthened environment yields a different concrete
type or an error. `L_mono` is the witness for why.

**SC2′, sandboxed pass.** The pass runs in a state from which **only** the return-type map is
extracted. Diagnostics are discarded, and so is every other accumulator the synthesis traversal
touches: `recordHole` appends to `tcHoles` (`:678-697`, declared `:247`) which is read as
`sketchHoles` at `:2295`, and provenance and let-definition state accumulate the same way. Under
SC2′ the type channel's accept/reject set and the sketch-hole registry are unchanged **by
construction**, which is what exempts this from the strictness hazard that gated RET-BRANCH-PREF
Stage 2.

**SC3′, SCC-conditioned join preference.** Within `F`, an `if` join in which exactly one branch
synthesizes a bare wildcard yields the other branch's type **only when** the wildcard branch's head
is a call to a member of `SCC(f)`. Otherwise the join is by agreement after resolution, and
disagreement retains the wildcard. A singleton SCC is Stage 1's self-call case, so SC3′ generalizes
the shipped rule to its natural boundary and no further: inside the component the wildcard is the
group's own return type being determined by the concrete branch, which is the least-fixpoint step of
a recursive binding (Milner 1978; Damas and Milner, POPL 1982). Outside it the preference is a guess
about a callee, and the sharp reason to refuse it is that `typeToSort`'s `FQInt` default (`:2441`)
can make a wrong guess produce an *elaborable* constraint rather than a crash.

The components are **intra-module by construction**: `buildCallGraph` runs over entry-module
statements ([`HoleAnalysis.hs:599-612`](../../compiler/src/LLMLL/HoleAnalysis.hs), complete over
`EApp`/`ELet`/`EIf`/`EMatch`/`EOp`/`EPair`/`EAwait`/`ELambda`/`EDo`), and the loader's post-order DFS
with cycle detection forbids cross-module recursive groups
([`Module.hs:120-151`](../../compiler/src/LLMLL/Module.hs)). SC3′ does not generalize across imports.

**Cycle rule.** A component with no concrete anchor stays bare-wildcard, lowers to `FQInt`, and keeps
today's behavior. Measured terminal state (`S_anchorless`): both binders sort at `int`, verdict
REFUTED, no crash. No new terminal state is introduced. In `def` position the case is unreachable
anyway: strict-core admissibility rejects a `def` whose callee is not body-faithful (measured on two
probes), so a reachable anchorless cycle requires `def-shell` throughout.

**Cross-module.** Resolution runs per module inside that module's typecheck, seeded with the imported
`meRetTypes` of each cached module (`Module.hs:246-276`, built one line after the import-path
typecheck at `:189-190`). Acyclicity means components resolve bottom-up with no cross-module
fixpoint. `xmod-B` is the witness that the seed extension is required, not optional.

## What the pass changes: five channels

Every consumer reads the post-`effRet` value on the definition-site path. Sorts were the only channel
Rev 0 counted; the count moved four times, and Rev 2's count of four was wrong in both directions.
One channel it named is deleted, and two it never named are live.

**Cite the construct, not the line.** Rev 2's table cited bare line numbers. Several had already moved
by v0.23.0, and a citation that dies silently is worse than none. Every site below names the function
or the equation.

| # | Channel | Site (construct) | Direction | Status at v0.23.0 |
|---|---|---|---|---|
| 1 | Sort lowering of `result` and of call binders | `sortA1` in `emitFnConstraints`; `calleeRetSort` in the `CallVC` arm of `bodyToPredM` | crash to verdict | Live and unchanged |
| 2 | Admissibility gating | `contractSigGuardsBlock`, over `sigPairUnsafe` and `resultReturnUnsafe` | verdict to `asserted` | Live and unchanged |
| 3 | Effective-post augmentation | `augmentContractPost`, at the definition site only | obligation added; `verified` to `refuted` possible | Live and **widened**: FACT-AG-LEN Stage 3 added `bytesLenRetPost`. Asymmetric; see below |
| 4a | Assumption injection from the declared length | `resultLenFact` | was crash or `refuted` to `verified` | **Deleted at v0.14.78.** The channel does not exist. `bytesLenReft`, its binder-side twin, went the same way |
| 4b | Post-assumption unblocking at a call site | the `bytesOpOnResult` and `calleeRetSort` guard in the `CallVC` arm | post dropped, to post assumed | Live. **Sound** under FACT-AG-LEN Stage 3; see the derivation below |
| 4c | Ground facts on the constraint LHS | `injectRangeFacts` with `bytesRootedArr`; `injectBoolValRangeFacts` over `boolValArrs` | `refuted` to `verified` | Live. Reaching population measured **empty** in the corpus. Open row `ARR-RANGE-NAME` owns the name-based decision |
| 5 | Whole-structure equality fallback | `wholeArrEqClause` | body-faithful to contract-only | Live. Conservative. Rev 2 listed it inside channel 4 and mis-stated its direction |

Channel 2 means the pass is not verdict-preserving in general. `X_rectree` (three lines: a recursive
`(type Tree (| Leaf) (| Node Tree))`, a `def-shell` returning `(ok (Node (Leaf)))`, and a contracted
caller) is today reported **body-faithful** with `result : int` standing for a `Result[Tree, …]` and
reaches a verdict; after the pass `resultReturnUnsafe` fires and it becomes `erBodyFallback` /
`asserted`. That demotion is a **repair**: the prior verdict was computed on a binder whose sort
misrepresents the value, which is the window documented in
[`finding-fq-result-sort-default.md`](finding-fq-result-sort-default.md) §"Trust-boundary note".

### Channel 3 is asymmetric, and Rev 2 does not record it

A resolved return adds an obligation at the **definition site** and exports **no** guarantee to
callers. The order is readable in two places and it is deliberate in one of them.

`buildContractEnvWith` builds each entry as `aug params mRet c`, where `mRet` is the **raw**
statement's return type. For an unannotated function that value is `Nothing`, so
`augmentContractPost` performs no return-refinement fold. `emitFixpointWithCache` then maps
`effRet` over the **third slot only**, leaving the augmented contract `c` untouched. The equation is
`(\n (ps, c, mr) -> (ps, c, effRet retTypes n mr))`, and `seedImportedContracts` has the same shape.
`buildContractEnvWith`'s own R1 comment states the intent in terms: the synthesis is "scoped to
no-post so `aug` (`augmentContractPost`) is a no-op and still sees the declared `mRet`", and "the only
value that changes is the third slot `calleeRetSort` reads".

The definition-site path is the opposite. `effRet retTypes name mRet` is passed into the emitter, so
`augmentContractPost` there reads the **resolved** type and folds `bytesLenRetPost`.

**The direction is conservative.** The function owes more and promises the same. A function can
therefore begin failing its own post while every caller sees no change, which is a diagnosis hazard
and not a soundness one. Record it in the trust-boundary note so a reader is not left to derive it
from an emission order.

### The trust-base claim, re-derived

Rev 2 stated, under the old channel 4: "After RET-RESOLVE, some `verified` verdicts rest on the
resolution pass, where none do today. That is an expansion of the trust base, not a repair, and it
must be disclosed in `§5.3.5`." That sentence was carried entirely by `resultLenFact`. The site is
deleted. The claim does not survive unchanged, and it does not dissolve either. **It narrows to
channel 4c alone.** The derivation, channel by channel.

**4a dissolves.** The channel is gone. Nothing to disclose.

**4b dissolves as a trust claim, and it is a repair.** The `CallVC` arm drops the callee's post when
`bytesOpOnResult (contractPost contract)` holds and `calleeRetSort` is not the array sort. Dropping a
post is a sound weakening: a caller that assumes less proves more. Resolving `tau_ret` to `bytes[n]`
makes `calleeRetSort` the array sort, so the guard stops firing and the caller assumes a clause it
previously discarded. Assuming **more** is sound only if something proves the difference, and here
something does, twice over. First, the assumed clause is the callee's own **written** post, which the
callee has always owed. Second, and this is what channel 3's asymmetry buys, the caller assumes the
**raw-augmented** post while the callee discharges the **resolved-augmented** post, which under
FACT-AG-LEN Stage 3 additionally carries `bytesLenRetPost`. The assumption is therefore a strict
subset of the guarantee. A `verified` reached through 4b rests on the callee's discharged VC, exactly
as every other assume-guarantee verdict does. The resolution pass decides **which** guarantee is in
scope; it does not supply the guarantee.

This is worth stating plainly because it changes what Rev 2 was actually complaining about. The trust
expansion Rev 2 named was real, and it was `resultLenFact` injecting a length nobody proved. FACT-AG-LEN
Stage 3 closed it by moving the length from an antecedent to a goal. **The disclosure Rev 2 demanded
was discharged by a different row shipping, not by this proposal.**

**4c survives, and the disclosure is owed for it.** `injectRangeFacts` conjoins `0 <= t` and
`t <= 255` into `conLhs` for a `Map_select` whose array argument satisfies `bytesRootedArr`;
`injectBoolValRangeFacts` conjoins `0 <= v <= 1` for each `$val` array in `boolValArrs`, and
`boolValArrs` is built from `params ++ [("result", rt) | Just rt <- [mRet]]`. Both become reachable
for `result` exactly when the resolved `tau_ret` is a `bytes[n]` or an admissible bool-valued map.

These are facts about the **type**, not about the program: a `bytes[n]` element is in `0..255`, and a
bool-valued map value is in `0..1`. If the resolution is right, the facts are true. The exposure is
that `bytesRootedArr` is **default-true** on any `FQVar` whose name lacks a `$has` or `$val` suffix.
The decision is a variable-name suffix, and the open row `ARR-RANGE-NAME` owns it. RET-RESOLVE does
not create that unsoundness. It **feeds** it a new source of arrays, by making `result` one.

**The measured-empty population changes the schedule and not the disclosure.** The implementation
plan's census finds no corpus wildcard resolving to either type, which is why `ARR-RANGE-NAME` is not
a blocking prerequisite and needs a guard test rather than a queue position. A disclosure in
`§5.3.5`, however, has to be true of every program a user writes, not of the 318 files in this tree.
A census keyed to the corpus is incorrect the first time a program outside it resolves an unannotated
return to `bytes[n]`. **Do not weaken the disclosure on the strength of an empty bucket.**

**The words the disclosure needs.** Not Rev 2's. A `verified` verdict may rest on a ground range fact
that the emitter injects for an array whose bytes-rootedness was decided from a variable-name suffix
rather than from evidence, and RET-RESOLVE can newly make `result` such an array. Route the sentence
to `LLMLL.md §5.3.5` and to the parent finding's trust-boundary note, and cross-reference
`ARR-RANGE-NAME`.

**If `ARR-RANGE-NAME` closes, this disclosure dissolves too.** Once `bytesRootedArr` decides on
evidence instead of on a default-true name test, 4c reduces to 4b's position: a fact about a type the
type channel has established. The disclosure is therefore scoped to the life of that row, and it
should say so, so that a later reader does not carry a warning past the defect it describes.

## Gates

**A byte-identical corpus `.fq` is a strong gate and it is NOT a complete one.** Rev 2 called it
complete. That was wrong, and the implementation plan measured the counterexample class. Sorts, lhs
facts and rhs obligations are all rendered in the file, so the gate certifies several invariants
rather than one, and the corpus prediction stays "empty diff". **What it cannot see is a function with
no contract.** Such a function emits no constraint, so a resolution change inside it moves nothing in
the `.fq` and the gate reports agreement it did not check. Four corpus candidates sit in exactly that
position: `life_sexp/world.llmll :: evolve`, `life_json/world.ast.json :: evolve`,
`hangman_json_verifier/hangman.ast.json :: game-won?` and `hangman_json/hangman.ast.json :: game-won?`.
Measured: `world.llmll` emits a 32-line `.fq` carrying no constraint at all. **A second half is
therefore owed**, comparing the resolved map itself rather than its downstream rendering, and the
implementation plan's byte-identity procedure carries it. Per-channel fixtures are needed where the
corpus is silent:

1. Channel 1: the nine crash shapes with annotated controls.
2. Channel 2: `X_rectree`, asserting the tier flip and its diagnostic, not merely the absence of a crash.
3. Channel 3: `Y_alias`, asserting the emitted rhs conjunct set.
4. Channel 4b: a call-site witness asserting that the callee post moves from dropped to assumed, and
   that the caller's assumed clause is the callee's written post rather than the resolved-augmented
   one. `Z_bytes` is retargeted to this site; its Rev 2 form asserted the injected `bytesLen` fact,
   which no longer exists.
5. Channel 4c: a guard test rather than a verdict test, because the reaching population is empty.
   Assert that `injectRangeFacts` fires for a `result` whose resolved type is `bytes[n]`, and that the
   verdict records `ARR-RANGE-NAME` as what the range fact rests on.
6. Channel 5: a `wholeArrEqClause` witness asserting the move from body-faithful to contract-only, and
   asserting `postCause` reports `FallbackContractPost` or `FallbackContractPre`. Rev 2 had no witness
   for this channel because it did not know the channel existed.

Plus the three re-widening guards T1–T3 from the parent finding, the three SC witnesses (hole body
retained, concrete `τ⁰` not revised, anchorless cycle unchanged), tier invariance, and CDP
invariance. The typecheck-acceptance diff that RET-BRANCH-PREF Stage 2 would have needed is **not**
required here, because SC2′ makes acceptance invariant by construction.

Any corpus file whose diff is non-empty is adjudicated per channel with its direction named. The
three census heads the reader cannot type (`hangman_sexp`, `life_sexp` ×2) are the expected sources
of surprise.

## Invariants

- **I1.** No function loses `verified` except through an enumerated repair, each with a named channel
  and a witness. (`X_rectree` is the only enumerated case.)
- **I2.** No function gains `verified` on the strength of a fact derived from a type unless the
  function that **declared** that type has itself discharged the corresponding obligation, and the
  dependency is recorded.

I2 is a gate as stated and becomes a theorem where its antecedent is establishable. The theorem is a
conservative-extension statement: the VC set emitted under RET-RESOLVE equals the VC set of the
*elaborated* program in which every unannotated return is replaced by its resolved type, provable by
simulation over the emission function in the style of the `§3.4.5` erasure theorem, **modulo
type-channel soundness for the class in question**. That modulus is not vacuous:
[`finding-arg-position-false-safe.md`](finding-arg-position-false-safe.md) is the counterexample for
the array class, and WILD-ASSUME closes it. After WILD-ASSUME the theorem holds unconditionally for
the array and map classes and I2 remains a gate elsewhere. State it that way, not unconditionally.
The class index is not an artifact of the statement: at scalar types a laundered wildcard yields a
sort disagreement that fails closed (`L_mono`), and at data-carrying types it yields sort agreement
with a false fact that fails open (`Q1_argpos`).

## Migration staging

The wildcard is the gradual dynamic type without casts. `compatibleWith (TVar _) _ = True` (`:2185`)
plus the non-transitivity already documented at `LLMLL.md:401` is the Siek–Taha consistency relation
(2006); erasure (`§3.4.5`) forecloses the cast insertion its soundness argument requires, so there is
no blame point (Wadler and Findler, ESOP 2009) and no gradual guarantee (Siek, Vitousek, Cimini and
Boyland, SNAPL 2015). `L_mono` is the canonical consequence.

**This proposal ships stage 1 only.** Stages 2 and 3 are recorded and not proposed, which is the
disposition RET-BRANCH-PREF Stage 2 established on this line.

1. **Stage 1 (this proposal).** Solve in the verification channel; acceptance frozen by SC2′.
2. **Stage 2 (recorded).** Solve and *warn* where the solution is inconsistent with a use. `L_mono`
   is the positive witness and the trigger is decidable, since the pass already computes the
   inconsistency. What is missing is the corpus count of programs that would warn, which is a
   measurement using the census instrument, not a design question. FALLBACK-VISIBLE's withdrawal is
   the precedent for not shipping a diagnostic ahead of a measured trigger.
3. **Stage 3 (recorded).** Promote the warning to an error, under a flag and then by default. The
   one-type-system precedent is `noImplicitAny` in TypeScript and `--disallow-untyped-defs` in mypy;
   the migration-analysis tooling is Campora, Chen, Erwig and Walkingshaw, *Migrating Gradual Types*
   (POPL 2018), with Rastogi, Chaudhuri and Hosmer (POPL 2012) and Garcia and Cimini (POPL 2015) on
   solving in the presence of the dynamic type.

The property to preserve across all three is I1 and I2 as stated above, not the gradual guarantee,
which LLMLL forfeits by construction.

## Residue

- **`L_mono`.** `(let [(r (g n))] (+ r 1))` with `g` returning bool type-checks today and crashes in
  the solver. `τ⁰` is `int`, so SC1 forbids revision and the crash persists. Not closed by any
  version of this proposal; it is stage 2/3 territory.
- **`R_result`.** `typeToSort _ = FQInt` (`:2441`) keeps a `Result`-returning unannotated callee's
  call binder mis-sorted and its verdict reachable. **This hygiene fix must not land before
  WILD-ASSUME**: it is the coupling that currently masks the return-position variant of the
  array-class false SAFE (see the finding's step 5).
- **Brief fidelity.** `Checkout.hs:1106` renders `feReturn = maybe "?" typeLabel mRet` from the raw
  statement, so a brief tells an agent `"?"` for a callee whose return type the verifier knows
  precisely. The resolved map makes rendering `τ_ret` possible. Not folded in: the checkout brief is
  the sole information channel a hole-filling agent receives, so a change to it deserves its own
  fixtures and its own adjudication. Interim disclosure precedent: `LLMLL.md:1854`.

## Verification mapping

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| post over a `bool`-sorted `result` | contract | QF-LIA + Bool, auto-discharged | `LLMLL.md §5.3.3` |
| post over a `Str`-sorted `result` | contract | QF-LIA + QF-EUF, interned constants (STRLIT) | `§5.3.3` |
| post over a `Pair2`-sorted `result` | contract | QF-LIA + acyclic datatype theory, polite combination | `§5.3.3`, `:955` |
| post over a non-admissible `Result` return | contract | **outside `Σ_auto`**; `erBodyFallback`, tier `asserted` | `:955` firewall |
| folded refinement-alias return predicate | contract | QF-LIA `p[result/x]` | `§3.4.1`, `§3.4.6`; `augmentContractPost :688` |
| `bytesLen(result) = n` plus array-sorted binder | contract | QF arrays + QF-LIA, polite-combined, decidable | `§5.3.3` array class `:956` |
| anchorless-cycle `result` | contract | QF-LIA at `FQInt`, unchanged | `§5.3.3` |
| ill-typed body under concrete `τ⁰` (`L_mono`) | neither | not emitted; fails closed | `§3.4.5`, the missing-cast residue |

No new obligation class, nothing nonlinear, nothing escapes to Lean. Two rows move across the
`Σ_auto` boundary in opposite directions, which is why I1 and I2 are stated as a pair.

## Affected surface

1. `compiler/src/LLMLL/TypeCheck.hs`, `typeCheckWithCacheModeRet'`: the sandboxed pass between
   `runState` and the returned pair; `tcRetTypes st` becomes the resolved map. This is the single
   seam, and its report-only wrapper `typeCheckWithCacheMode'` discards the map, which is why a change
   here cannot reach the type channel's accept or reject set.
2. `compiler/src/LLMLL/Module.hs`, `loadModule`: seed extension with the cached modules' `meRetTypes`.
3. `compiler/src/LLMLL/TypeCheck.hs`, `preferConcreteOnSelfCall`: stays as shipped for the type
   channel; SC3′ is a separate SCC-conditioned variant used only by the pass. Widening the existing
   function in place reintroduces Stage 2's acceptance hazard.
4. `compiler/src/LLMLL/FixpointEmit.hs`: **no code change.** Every consumer already reads the map
   through `effRet`, which `emitFixpointWithCache` and `seedImportedContracts` map over the ContractEnv
   third slot and which the definition-site emitters take directly. Behavior changes anyway, across
   **five** channels, not the four Rev 2 counted.
5. `compiler/src/LLMLL/VerifiedCache.hs`, `checkerSoundnessVersion` (currently `"2"`): increase it
   **only if** the corpus sweep shows a verdict move on a function carrying `verified` evidence.
   **Rev 2 named the wrong stamp.** It asked for `codegen_semantics_version` in
   `ProofArtifact.hs`. That stamp tracks int against machine-int codegen semantics and is `INT-3`'s
   re-arm discriminator; spending it on a checker change would leave `INT-3` without one.
   `VerifiedCache.hs` says so in terms. A checker change takes the checker stamp.
6. Docs, documentation-lead: the `LLMLL.md §3.4.6` sentence naming the channels needs the corrected
   count; `§3.4.6` gains the Siek–Taha citation; `§5.3.5` and the parent finding's trust-boundary note
   gain the **channel-4c** disclosure in the words given above, plus the channel-3 asymmetry; the
   roadmap residual text is corrected with `E_str` named as a v0.14.72 conversion.
7. Schema: JSON-AST unchanged, no version bump, `.verified.json` shape unchanged.
8. Freeze policy: not applicable, lifted at v0.11 (`docs/compiler-team-roadmap.md:234`).
9. `compiler/app/Main.hs`, `emitSynthetic`: a **third** consumer of `tau_ret` that Rev 2 missed. It
   builds the CDP or weakness candidate program and calls `typeCheckWithCacheRet` for its map, so
   `--cdp` and `--weakness-check` read the resolved map and their verdicts are in the gate's scope.
10. Research-track: this proposal **anticipates** declaration-group inference (`LLMLL.md:1603`, the
   `do`-step carve-out, which the parent finding routes to that track) and deliberately does not
   deliver it, because SC2′ forbids the resolved map from reaching `expectPairType`.

## Errata routed

Two, both with zero corpus exposure and neither affecting an in-tree verdict.

1. **v0.14.72 changed effective postconditions** for an unannotated function whose body synthesizes a
   refinement-aliased value. Measured on `Y_alias`: at v0.14.71 the emitted rhs for the caller is
   `(result = (n + 1))`; at v0.14.72 it is `(result = (n + 1)) && (result > 0)`, the alias predicate
   folded by `augmentContractPost` from a synthesized `TCustom`. The parent finding's "no prior
   verdict is affected" is accurate for sorts and does not cover obligations.
2. **`FixpointEmit.hs:412-413` is false.** The comment states that `augmentContractPost` "folds only
   refinement ALIASES, which are annotation-only and never synthesized". Aliases are synthesized:
   `inferExpr` on a call to an alias-returning function yields the alias. This comment was the stated
   safety argument for stage (a) on the non-sort consumers and it carried a design turn. Route as a
   code-comment correction with the `Y_alias` measurement attached.

## Ordering

**Every ordering constraint this section stated is discharged. RET-RESOLVE is unblocked.** The chain
as filed, with the status each entry has at v0.23.0:

| Prerequisite | Status | Evidence |
|---|---|---|
| `SAFE-ARG` | SHIPPED v0.14.73 | roadmap Closed table row |
| `WILD-ASSUME`, bytes arm | SHIPPED v0.14.73 | roadmap; `wildAssumeRejects` in `TypeAdmissibility` |
| `WILD-ASSUME-2`, map arm | SHIPPED v0.14.74 | roadmap; `admits = boolValuedMapTy` |
| `FACT-AG-LEN` Stages 1 to 3 | SHIPPED v0.14.76 to v0.14.78 | roadmap; `bytesLenParamPre`, the `bodyToPredM` axiom equation, `bytesLenRetPost` |
| `ARR-RANGE-NAME` | OPEN, **not blocking** | reaching population measured empty; it needs a guard test, not a queue position |

**The entry that carried the blocking argument is the one that dissolved it.** Rev 2 made
`WILD-ASSUME` the precondition "that makes this proposal's channel 4 sound". Channel 4a is deleted, so
that specific dependency no longer exists. `WILD-ASSUME` and `WILD-ASSUME-2` still carry
invariant I2's unconditional form over the array and map classes, which is a different claim and is
stated under "Invariants". The channel that replaced 4a is 4b, and 4b is sound for the reason
FACT-AG-LEN exists: the callee proves the length it exports.

`ARR-RANGE-NAME` is the one open row this proposal touches, and it is a **disclosure** dependency
rather than a scheduling one. See "The trust-base claim, re-derived". The row does not gate the
patch; the patch owes the row a sentence in `§5.3.5`.

## Review log

Four standalone professor review rounds, transcribed at
[`docs/archive/professor-reviews/ret-resolve-proposal-review.md`](../archive/professor-reviews/ret-resolve-proposal-review.md), ready for fold-and-archive per
DOC-CONSOLIDATE M2. Rev 0 → Rev 1 folded the SCC condition on the join preference, the admissibility
channel, the corrected deferral rationale, the gradual-`Dyn` reclassification, sandboxing, the brief
asymmetry, and the join-notation correction. Rev 1 → Rev 2 folded the effective-post channel, added
the assumption-injection channel and its witness, measured the v0.14.72 erratum, restated the gate as
byte-identity, and added I1/I2. Rounds 3 and 4 produced no change to the rule; they produced
WILD-ASSUME and then the live false SAFE, both of which left this proposal's text intact and moved it
to third in the queue.

The rule text has not changed since Rev 1. Where the rounds were spent is recorded in the finding's
"Provenance" section, and the transferable point is that testing a claim in the previous turn's own
text was productive five times out of five, while arguing about the rule produced nothing after Rev 1.
