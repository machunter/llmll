# MATCH-WIDEN Slice 1 — implementation note

**Status:** Construction path DONE + validated (full suite 1064/0). Mixed-arm *match* path scoped (not yet implemented). Not committed.

## What shipped (construction — the goto-fail leaf)

Mixed nullary+payload sum **construction** now verifies body-faithful. Two edits to
`compiler/src/LLMLL/FixpointEmit.hs`, both reflecting a bare nullary constructor of a mixed/payload
sum as its FQData nullary term (`FQApp (toLower c) []`), mirroring the existing payload-ctor path:

1. `exprToPred (EVar v)` (was `Just (FQVar v)`): now, for an uppercase `v`, `Just (FQApp (toLower v) [])`.
2. `bodyToPredM … (EVar v)`: new guarded clause before the generic variable clause — uppercase `v`
   → `SimpleVC [] (FQApp (toLower v) [])`.

**Why it was falling back:** a nullary ctor of a mixed sum (e.g. `Verified` in
`Verdict = (| Verified) (| Rejected int)`) is *not* int-tag-desugared — `buildCtorTagMap`
(FixpointEmit.hs:1115) only tags **all-nullary** sums — so it arrives at the translators as a bare
`EVar "Verified"`, which the generic variable clause returned `Nothing` (fallback) for. The sort side
was already correct (`typeToSortA` gives `FQData` when `hasRealPayload`, which a mixed sum satisfies;
`typeSorts` already emits the mixed decl with the nullary ctor's empty field list).

**Soundness of the guard:** an uppercase `EVar` reaching these translators is *necessarily* a
mixed-sum nullary constructor, because `desugarCtorValues` (run on contracts at :207 and bodies at
:601) has already lowered every all-nullary-enum ctor to an int-tag `ELit`. So there is no ambiguity
with variables (lowercase) or with int-tag enums (already `ELit`).

## Acceptance results (llmll 0.14.11, freshly built)

| Case | Result |
|---|---|
| `final-verdict` mixed-sum construction (goto-fail leaf) | **body-faithful, SAFE** ✅ |
| goto-fail twin (`Verified` unconditional) | **refuted** (constraint #0) ✅ |
| classify / settle / safe-withdraw / channel (regression) | SAFE ✅ |
| classify-bad / settle-bad / withdraw-outcome-bad (bad twins) | refuted ✅ |
| **full `cabal test`** | **1064 examples, 0 failures** ✅ |

## Remaining Slice 1 work — the mixed-arm *match*

A mixed-arm `match` (`(match s ((Continue) …) ((Abort c) …))`) is still gated at
`isCoreBodySyntactic` ("unrestricted match"). Admitting it is a **4-site seeding refactor** — slightly
more than the R1 spike's "just relax `adtKeys`":

1. `Syntax.hs:683–694` — add a disjunct admitting a two-arm sum whose arms are each nullary *or*
   single-payload (subsumes the two existing 2-arm shapes + mixed).
2. `FixpointEmit.hs:2236` `classifyTwoArmAdtArms` — return type assumes a payload var per arm
   (`(c1,v1,b1,c2,v2,b2)`); generalize to `Maybe` payload var per arm (nullary → `Nothing`).
3. `FixpointEmit.hs:1830` `buildOpaqueSumBranch` — takes a payload `(var,sort,ref)` per arm; make the
   payload optional so a nullary arm contributes only its guard branch, no selector/sort binding.
4. `FixpointEmit.hs:629` `adtKeys` — seed a payload sort key only for the arm that has one.

The discrimination guard (`_match_success` `BranchVC`, first-match already `¬prior`) is unchanged;
this is purely admitting the mixed shape into the existing 2-arm opaque-sum elimination. Est. **M**.
Construction (above) already unblocks the goto-fail leaf, which uses `if`+construction, not a match.
