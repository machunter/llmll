---
name: pair-refine-entry-proposal
title: "PAIR-REFINE-ENTRY-1: a refinement on a pair component is checked where the pair enters and assumed where it is read"
status: "Rev 1, SETTLED 2026-11-04 (user-approved). The user accepted the recommendation: Option A: a pair component is an introduction site at any depth. No professor pass: the proposal applies a settled rule."
date: 2026-11-04
author: language-team
rows: "PAIR-REFINE-ENTRY-1 (G1, PLAN after settlement). Filed from docs/design/clause-welldef-proposal.md Rev 2 (D6, site S7, E19). Related: CLAUSE-WELLDEF-1 (G1, DECIDE, Rev 2 draft) parity rule."
consumers: [user, compiler-engineer, documentation-lead]
---

# PAIR-REFINE-ENTRY-1: a refinement on a pair component

**Status: Rev 1, SETTLED 2026-11-04.** The language-team wrote Rev 1 on 2026-11-04 and measured each case on 0.36.0. The user accepted the recommendations the same day. The row moves from DECIDE to PLAN.

All measurements are on `llmll 0.36.0`, built from main `a339fbb8` with `stack build`, and liquid-fixpoint 0.9.6.3.7. The witness programs were run outside the repository; the engineer adds them as fixtures with the names used below.

## Restatement

A refinement alias such as `Idx ≜ (where [i: int] (and (>= i 0) (< i 4)))` can appear as a component of a pair type, for example `p: (Idx, int)`. Today the verifier ignores it on both sides. A caller can pass `(pair 9 n)` with no obligation, and the callee cannot use `0 ≤ first p < 4`. The row asks one question: is a pair component a §3.4.1 introduction site, or is a refinement there refused?

## Decisions (settled by the user, 2026-11-04)

The user accepted each recommendation below.

**Question.** When a parameter or return type has a refinement alias at a pair component, does the verifier (A) prove the predicate where the pair enters and assume it where the pair is read, as for a scalar parameter, or (B) refuse the type at `check`?

**Recommendation.** Option A. Treat each pair component, at any nesting depth, as an introduction site. The predicate goes into the effective pre at a parameter and into the effective post at a return, instantiated at the selector path (`first p`, `second (first p)`, and so on).

## Context located

1. `docs/compiler-team-roadmap.md` row `PAIR-REFINE-ENTRY-1`: the DECIDE and the acceptance (the witness call fails, the post in `h` verifies).
2. `docs/design/clause-welldef-proposal.md` Rev 2, D6, site S7 and E19: the source of the row. Its parity rule says: if callers prove the fact, `h` must assume it too.
3. `compiler/src/LLMLL/FixpointEmit.hs:6485-6489` `resolveAllRefinements`: follows `TDependent` and `TCustom` only. It returns `[]` for a `TPair`, so no consumer sees a component refinement.
4. `FixpointEmit.hs:6571-6588` `paramRefinementPre` / `augmentContractPre` and `:6632-6648` `returnRefinementPost` / `augmentContractPost`: the scalar route. The predicate joins the effective pre or post, so §5.3.4's call rule proves it at callers and the callee assumes it.
5. `FixpointEmit.hs:6540-6545`: the note says `payloadRefinement` must not see extra facts from `resolveAllRefinements` ("COMPONENT positions, a deliberate exclusion"). So the change must not go into `resolveAllRefinements` itself. It needs a separate function, as `bytesLenParamPre` is.
6. `FixpointEmit.hs:2272-2310`: COMP-4 (b) payload subtyping for sum payloads. That is the only component position the verifier enforces today.
7. `compiler/src/LLMLL/PBT.hs:542-570`: the property-test generator draws a `TDependent` by rejection sampling "at any depth", and it recurses into `TPair`. So the `tested` channel already treats `(Idx, int)` as a domain restriction. The verifier channel does not. This is a disagreement between two channels on one type.
8. `LLMLL.md §3.4.1`, `§3.4.2` non-goal 1: a refinement creates an obligation only "at concrete introduction sites". The spec does not say whether a pair component is one. This is a spec gap, not drift.
9. `LLMLL.md §3.4.5` (erasure theorem): its hypothesis is that every refinement-typed value comes from a checked introduction site. Refinement aliases have no run-time check. Today `(pair 9 n)` reaches `h` with no check in any channel, so the hypothesis is false for that program and nothing reports it.
10. `examples/netpbm-swarm/types.llmll:35-44`: declares `Channels` and `MaxVal` but types `Fmt` as `(int, int)`, not `(Channels, MaxVal)`, and states each requirement as an explicit `pre`. This is a user workaround for this gap.

No design record exists on this topic other than CLAUSE-WELLDEF-1 D6 (`docs/design/INDEX.md`, checked).

## Measurements

| Witness | Today | Meaning |
|---|---|---|
| `pc3.llmll`: `c` calls `h (pair 9 n)`, `h [p: (Idx, int)]` | SAFE | no obligation at the call |
| `pc2.llmll`: `h` post `(< (first p) 4)` | refuted | the callee does not assume the component fact |
| `e19.llmll`: post `(>= (bytes-get b (first p)) 0)` | SAFE | definedness not checked (CLAUSE-WELLDEF-1 S7) |
| `scal.llmll`: the same with `i: Idx` scalar, call `(h 9 n)` | call-pre refuted | the scalar rule works |
| `ret.llmll`: `mk -> (Idx, int)` returns `(pair 9 n)` | `mk` verified | the return component is not proved |
| `nest.llmll`: `((Idx, int), int)`, call with `(pair (pair 9 n) n)` | SAFE | same gap at depth 2 |
| `payload.llmll`: sum `Box (| Full Idx)`, call `(h (Full 9))` | payload-sub refuted | sum payloads are enforced (COMP-4 b) |
| `payload_ok.llmll`: the same with `(Full 3)` | payload-sub refuted | COMP-4 (b) refuses every constructed argument (see E7) |

**Spec-local emulation of option A.** The files `emu_9.llmll`, `emu_3.llmll`, `emu_ret.llmll`, `emu_str_*.llmll` write by hand the pre and post that option A would generate, over `(int, int)` and `(string, int)`.

- `emu_9`: the call `(h (pair 9 n))` is refuted at the call-pre. `emu_3`: the call `(h (pair 3 n))` verifies.
- In both, `h` with post `(< (first p) 4)` verifies, and `hb` with post `(>= (bytes-get b (first p)) 0)` verifies.
- `g [q: (int, int)]`, which forwards `q`, verifies. `gn`, which forwards `(first q)` from a nested pair, verifies.
- `emu_ret`: `mk` returning `(pair 9 n)` is refuted. `mk2` returning `(pair 2 n)` verifies. `use`, which reads `(first (mk2 n))`, verifies with post `(< result 4)`.
- `emu_str_empty` is refuted and `emu_str_ab` verifies, so a measure-class component (`string-length`) also works.

So option A needs no new solver capability. The selector-over-constructor reduction (`pair2_0 (pair2 a b) = a`) is already in the datatype class.

**How common the type is.** No maintained program (`examples/`, `stdlib`, `tools/`, `scripts/tests/`) puts a refinement alias inside a pair, list or map. In agent runs under `experiments/*/runs/`, 84 files do it in a pair-shaped position, for example `(type Account (string, Balance))` with `Balance ≜ (where [v: int] (>= v 0))`. Agents write this type without being asked. Today it gives them nothing, and they are not told.

## Options

**Option A. Pair components are introduction sites (recommended).** For a parameter `p : τ` and each path π of `first`/`second` selectors to a component of `τ` whose type carries refinements, conjoin `p_A[π(p)/x]` into the effective pre. Apply the same rule at `result` for the return type, into the effective post. Pair aliases are followed (`(type Account (string, Balance))`). The existing machinery then proves the predicate at each call and at each return, and assumes it in the callee and at each call result.

**Option B. Refuse a refinement alias at a pair component in a signature.** `check` reports an error that names the component and tells the author to use a `pre`. This is sound and small. It removes a type that agents write often (84 run files). It also leaves `PBT.hs` reading the type one way while the checker refuses it.

**Option C. Keep the type, do not enforce it, and disclose it.** `check` warns that the component refinement has no effect. The spec says a pair component is not an introduction site. This is the cheapest. It keeps a type annotation that states a fact nothing checks, and the erasure theorem must then exclude pair components by name.

## Why option A is sound

The argument is the §5.3.4 assume-guarantee argument for a scalar parameter, applied to a selector term.

1. **Every entry is checked or disclosed.** A call from a verified function proves `p_A[π(a)/x]` for the argument term `a`, by the existing call-pre rule. A call from a fallback function, a hole, `main`, or an FFI boundary is the same trust carve-out a scalar parameter has (`LLMLL.md §3.4.3`, out-of-process-agent carve-out). The trust report already discloses it ("call-pre unchecked", seen in `emu_rec.llmll`).
2. **The fact cannot change between entry and use.** Pairs are immutable. The value `π(p)` that the caller proved is the value the callee reads. Strict immutability is what this step rests on.
3. **The selector term means the component.** `first`/`second` reflect to the `Pair2` selectors of a non-recursive datatype. The datatype theory evaluates a selector applied to a constructor. The pair `compare` unfolding (`LLMLL.md` generics paragraph) already relies on this.
4. **No new axiom and no new symbol.** `Σ_auto` is unchanged. The new conjuncts use symbols the verifier already emits.
5. **Parity.** The same conjunct is proved on one side and assumed on the other, from one function. So the CLAUSE-WELLDEF-1 parity rule holds: S7 stops being an `ill-defined` site, because the fact is now in `H`.

The change also makes the §3.4.5 hypothesis true again for pairs: a refinement-typed pair component now comes from a checked introduction site.

## Design proposal

**Semantics.** Define a component-path set for a type, after alias expansion:

```
paths(τ) = { (ε, x, p) | (x, p) ∈ refs(τ) }
         ∪ { (first·π, x, p) | τ ≡ (τ1, τ2), (π, x, p) ∈ paths(τ1) }
         ∪ { (second·π, x, p) | τ ≡ (τ1, τ2), (π, x, p) ∈ paths(τ2) }
```

Here `refs` is `resolveAllRefinements`. Then:

```
effPre(f)  = pre(f)  ∧ ⋀ { p[π(v)/x] | (v : τ) ∈ params(f), (π, x, p) ∈ paths(τ) }
effPost(f) = post(f) ∧ ⋀ { p[π(result)/x] | (π, x, p) ∈ paths(ret(f)) }
```

The `ε` path is today's scalar rule, so the definition is an extension, not a replacement.

**Positions in scope.** Parameter and return, at any pair depth, through pair aliases and through generic type arguments (a copy `f@[(Idx, int)]` gets the conjuncts from `augmentContractPre` with no extra work, `LLMLL.md` generics paragraph). An annotated `let` follows whatever the scalar rule does there. The S-expression parser has no `let` annotation (`Parser.hs` `pLetBinding`), so that site is reachable only through JSON-AST. This proposal does not measure it.

**Positions out of scope.** A list element (`list[Idx]`) and a map value. A predicate on every element is a quantified fact, outside QF-LIA. These are the same kind of gap, but a different fix. Filing a sibling row is recommended (see Risks, item 3).

**Surface and schema.** No change. No new syntax, no JSON-AST delta.

**Spec text for `LLMLL.md §3.4.1`** (for the doc-lead after the engineer ships): "A pair component is an introduction site. For a parameter or return of pair type, the refinement of each component is instantiated at its selector path and joins the effective pre or post, at any depth. A list element and a map value are not introduction sites."

## Edge cases and degenerate inputs

E1. **Positive witness, the call that must fail.** `pc3.llmll`: `(type Idx (where [i: int] (and (>= i 0) (< i 4))))`, `h [p: (Idx, int)]`, and `c [n: int]` with body `(h (pair 9 n))`. Expected: the call-pre obligation `0 ≤ first (pair 9 n) < 4` is refuted in `c`. Channel: contract. Measured on the emulation `emu_9.llmll`.

E2. **The post that must verify.** `pc2.llmll`, post `(< (first p) 4)`. Expected: verified, because `effPre(h)` holds `0 ≤ first p < 4`. Channel: contract. Measured on `emu_3.llmll`.

E3. **A forwarded pair.** `fwd.llmll`: `g [q: (Idx, int)]` calls `(h q)`. Expected: the call-pre is proved from `g`'s own effective pre. No obligation reaches `g`'s callers that was not there. Channel: contract. Measured on `emu_3.llmll` (`g`).

E4. **Nested pair and partial projection.** `nest.llmll`, `((Idx, int), int)`. Expected: the conjunct is at `first (first p)`. A call `(h2 (first q))` where `h2 : (Idx, int)` is proved from `q`'s fact. Channel: contract. Measured on `emu_3.llmll` (`gn`).

E5. **Return position.** `ret.llmll`: `mk -> (Idx, int)` with body `(pair 9 n)`. Expected: `mk` is refuted on the return conjunct. A caller of a correct `mk` assumes `0 ≤ first result < 4`. Channel: contract. Measured on `emu_ret.llmll`.

E6. **The other component is not sortable.** `emu_rec.llmll`: `h [p: (int, Tree)]` with `Tree` recursive. Expected: today `sortableComponent` is false, so both functions fall back and the call shows "call-pre unchecked: c -> h". Option A changes nothing here. The new conjunct is unchecked and disclosed on the trust channel, like any pre of a fallback callee. Channel: trust.

E7. **A component predicate outside the fragment.** For example a component alias with a nonlinear predicate. Expected: the effective pre does not translate, so the function falls back with `contract-pre-outside-fragment`, as a scalar parameter with the same alias does today (CLAUSE-WELLDEF-1 S4). A function that verified before can change to fallback. That is a correct change in verdict, and the census reports it. Channel: trust.

E8. **Sum payload inside a pair.** `(Box, int)` where `Box (| Full Idx)`. Expected: the `Idx` refinement belongs to the payload, not the pair component. COMP-4 (b) payload subtyping handles it only for a parameter of sum type. A sum inside a pair is not handled by COMP-4 (b) or by this proposal. Spec is silent (gap, flag). Note also that COMP-4 (b) refuses a constructed argument such as `(Full 3)` (`payload_ok.llmll`), because it gives every non-forwarded argument the payload fact `true` (`FixpointEmit.hs:2272-2283`). That is sound, but it is less complete than the selector route proposed here. It is not part of this row.

E9. **List of a refined type.** `lst.llmll`, `xs: list[Idx]`. Expected: unchanged. The element fact is not assumed and not proved. The property-test generator respects it (`PBT.hs`). Spec is silent (gap, flag). See Risks, item 3.

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| `p[π(a)/x]` at a call, for argument term `a` | contract (call-pre, PROVE) | (a) QF-LIA plus acyclic datatype selectors, or the measure class when `p` uses a length measure. Auto-discharged. `LLMLL.md §5.3.3` (datatype class, measure class) |
| `p[π(p)/x]` assumed in the callee | contract (effective pre, ASSUME) | (a), same terms |
| `p[π(result)/x]` at a return | contract (effective post, PROVE in the body VC; ASSUME at callers) | (a) |
| A component predicate outside `Σ_auto` | trust (fallback, `contract-pre-outside-fragment` or `contract-post-outside-fragment`) | (b), handled by the existing firewall (§3.4.5); no Lean route is added |

No obligation escapes to Lean.

## Affected surface

1. `compiler/src/LLMLL/FixpointEmit.hs`: a new function next to `bytesLenParamPre` that returns the path-instantiated conjuncts; call it from `paramRefinementPre` and `returnRefinementPost`. Do not change `resolveAllRefinements` (its note at `:6540-6545` gives the reason).
2. `compiler/src/LLMLL/Feasibility.hs:164-170`: the no-miracle gate builds its own parameter and return refinements from `resolveAllRefinements`. It must read the same conjuncts, or it reasons over fewer hypotheses than the VC. That direction is conservative, but the two should agree.
3. `compiler/src/LLMLL/Checkout.hs:1047`: `resolveRefinement` for checkout briefs. A hole brief should list a component fact as an assumption. This is quality, not soundness.
4. `LLMLL.md §3.4.1` (the sentence above), `§3.4.5` (the hypothesis now covers pair components), `§5.3.5` row for the `TCustom` alias predicate.
5. `docs/design/clause-welldef-proposal.md` site S7 and E19: change from "`ill-defined` is correct" to "the fact is in `H`; verified". This is a revision of that draft, the language-team's slot.
6. `examples/netpbm-swarm/types.llmll`: the comment that explains the `(int, int)` workaround becomes optional. No change is required.

No addition: no new builtin, construct, capability or FFI tier.

## Risks and open questions

1. **Verdict changes in the census.** Classification: verification-ergonomics. A function whose signature has a refined pair component and that verified before can now be refuted (a caller that does not prove the fact) or fall back (E7). Each such change is a correct verdict. The bite: complicates the release; the census diff must be read. No maintained program is affected (scan above), so the expected diff is empty.
2. **CLAUSE-WELLDEF-1 is not settled.** Classification: spec-drift. Its S7 text assumes today's behaviour. If this row ships first, S7 must change. The bite: complicates; one paragraph in that draft.
3. **List and map elements stay unenforced.** Classification: soundness of the §3.4.5 hypothesis. `list[Idx]` has the same problem as `(Idx, int)`: no channel checks it, and `PBT.hs` assumes it. A quantified element fact is outside QF-LIA, so the fix is option B or C for those positions, not option A. The bite: does not block this row. Recommend filing `LIST-REFINE-ENTRY-1` (G1, DECIDE) with that choice.
4. **A pair inside a sum payload, or a sum inside a pair.** Classification: scope. Neither COMP-4 (b) nor this rule covers it (E8). The bite: only matters at scale.

No question for the professor. The soundness argument is the existing assume-guarantee rule applied to a selector term. The emulation measures every step.

## Acceptance

The row's acceptance holds: the call in `pc3.llmll` fails and the post in `pc2.llmll` verifies. Add: `ret.llmll`'s `mk` is refuted, `fwd.llmll` and `nest.llmll` (with a correct argument) verify, `e19.llmll` stays verified with the fact now in `H`, and the census shows no change outside these files.
