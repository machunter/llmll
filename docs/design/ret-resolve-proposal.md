---
name: ret-resolve-proposal
title: "RET-RESOLVE: resolve a wildcard `τ_ret` transitively in a verification-facing pass"
status: "Rev 2, SETTLED (four professor review rounds folded). Queued THIRD, behind SAFE-ARG and WILD-ASSUME"
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

## What the pass changes: four channels

Every consumer reads the post-`effRet` value on the definition-site path (`:529-566`). Sorts were
the only channel Rev 0 counted; the count moved three times.

| # | Channel | Site | Direction | Witness |
|---|---|---|---|---|
| 1 | Sort lowering of `result` and call binders | `:850`, `:1204`, `:3165-3168` | crash → verdict | the nine shapes |
| 2 | Admissibility gating | `contractSigGuardsBlock :1668-1673`, `:842` | verdict → `asserted` | `X_rectree` |
| 3 | Effective-post augmentation | `augmentContractPost :688` | obligation added; `verified` → `refuted` possible | `Y_alias` |
| 4 | Assumption injection | `resultLenFact :1212`, `wholeArrEqClause :1714` | crash or `refuted` → **`verified`** | `Z_bytes` |

Channel 4 is qualitatively different: it adds a fact to the antecedent, so a post that cannot be
discharged today is discharged after. **After RET-RESOLVE, some `verified` verdicts rest on the
resolution pass**, where none do today. That is an expansion of the trust base, not a repair, and it
must be disclosed in `§5.3.5` and in the finding's trust-boundary note. Channel 4's soundness has a
precondition: see "Ordering" below.

Channel 2 means the pass is not verdict-preserving in general. `X_rectree` (three lines: a recursive
`(type Tree (| Leaf) (| Node Tree))`, a `def-shell` returning `(ok (Node (Leaf)))`, and a contracted
caller) is today reported **body-faithful** with `result : int` standing for a `Result[Tree, …]` and
reaches a verdict; after the pass `resultReturnUnsafe` (`:2515-2518`) fires and it becomes
`erBodyFallback` / `asserted`. That demotion is a **repair**: the prior verdict was computed on a
binder whose sort misrepresents the value, which is the window documented in
[`finding-fq-result-sort-default.md`](finding-fq-result-sort-default.md) §"Trust-boundary note".

## Gates

**A byte-identical corpus `.fq` is a complete gate across all four channels**, because sorts, lhs
facts, and rhs obligations are all rendered in the file. The corpus prediction is therefore "empty
diff", certifying four invariants rather than one. Per-channel fixtures are needed only where the
corpus is silent:

1. Channel 1: the nine crash shapes with annotated controls.
2. Channel 2: `X_rectree`, asserting the tier flip and its diagnostic, not merely the absence of a crash.
3. Channel 3: `Y_alias`, asserting the emitted rhs conjunct set.
4. Channel 4: `Z_bytes`, asserting the binder sort, the injected `bytesLen` fact, and that the
   resulting `verified` records the fact it rests on.

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

1. `compiler/src/LLMLL/TypeCheck.hs:817-827`: the sandboxed pass between `runState` and the returned
   pair; `tcRetTypes st` becomes the resolved map.
2. `compiler/src/LLMLL/Module.hs:189-190, 246-276`: seed extension with imported `meRetTypes`.
3. `compiler/src/LLMLL/TypeCheck.hs:367-378`: `preferConcreteOnSelfCall` stays as shipped for the
   type channel; SC3′ is a separate SCC-conditioned variant used only by the pass. Widening the
   existing function in place reintroduces Stage 2's acceptance hazard.
4. `compiler/src/LLMLL/FixpointEmit.hs`: **no code change.** Both consumers already read the map
   through `effRet` (`:417-419`, applied `:337` and `:529-566`). Behavior changes anyway, across four
   channels.
5. `compiler/src/LLMLL/ProofArtifact.hs`: `codegen_semantics_version` bump, advisory only until a
   reader exists (see the finding, which gives the stamp its first real consumer).
6. Docs, documentation-lead: `LLMLL.md §3.4.6:399` sentence naming all four channels;
   `§3.4.6:401` gains the Siek–Taha citation; `§5.3.5` and the parent finding's trust-boundary note
   gain the I2 disclosure; `docs/compiler-team-roadmap.md:53` residual text corrected with `E_str`
   named as a v0.14.72 conversion.
7. Schema: JSON-AST unchanged, no version bump, `.verified.json` shape unchanged.
8. Freeze policy: not applicable, lifted at v0.11 (`docs/compiler-team-roadmap.md:234`).
9. Research-track: this proposal **anticipates** declaration-group inference (`LLMLL.md:1603`, the
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

Three patches, three releases, in this order. Do not bundle: all three move the same `.fq` lines, and
each one's expected diff is empty for a different reason, so an unexpected non-empty diff in a bundle
is not attributable.

1. **SAFE-ARG** — [`finding-arg-position-false-safe.md`](finding-arg-position-false-safe.md), a
   correctness advisory closing a live false SAFE. Independent of this proposal.
2. **WILD-ASSUME** — the general rule with the `map` arm and the criterion in the spec. It is also
   the precondition that makes this proposal's channel 4 sound.
3. **RET-RESOLVE** — this proposal, unchanged.

## Review log

Four standalone professor review rounds, transcribed at
[`ret-resolve-proposal-review.md`](ret-resolve-proposal-review.md), ready for fold-and-archive per
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
