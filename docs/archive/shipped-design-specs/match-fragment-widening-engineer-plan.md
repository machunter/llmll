---
name: match-fragment-widening-engineer-plan
title: "MATCH-WIDEN — engineer feasibility read & implementation plan"
status: "Feasibility read (compiler-engineer) for match-fragment-widening-proposal.md Rev 1"
date: 2026-07-06
consumes: docs/design/match-fragment-widening-proposal.md
---

# MATCH-WIDEN — engineer feasibility read

## 1. The two shipped-code findings — both come back CLEAN

**(a) First-match ordering: SOUND. Not a bug.** The Rev 1 worry (professor hazard 1) was that the
shipped enum path might assume non-overlapping arms. It does not. `desugarCtorValues`/`buildChain`
(`FixpointEmit.hs:1136`ff) lowers an all-nullary/wildcard match to a **right-nested ordered `EIf`**
over tag equalities; a `PVar`/`PWildcard` arm "becomes the else, ignoring later arms" (the buildChain
catch-all case) — i.e. first-match by construction, shadowing included. Empirically confirmed:

| probe | verdict |
|---|---|
| `(match c (_ 0) ((Red) 5))`, post `c=Red ⇒ result=5` (wildcard shadows Red) | `body-faithful` → **REFUTED (constraint #0)** ✅ correct |
| same, correct order `((Red) 5) (_ 0)` | **SAFE** ✅ |

The VC correctly sees the wildcard fire first (result=0≠5). No latent soundness bug; the ordered
nested-`if` structure is the reason.

**(b) Exhaustiveness severity: ERROR. Not a bug.** `checkExhaustive` (`TypeCheck.hs:1446`, wired
`:1136`) → `tcEmitNonExhaustive` is **error-severity**: a non-exhaustive user-ADT match fails
compilation (`exit=1`) under both plain `verify` and `--strict-verified-core`, so it cannot reach
`verified`. Confirmed empirically. `CodegenHs.hs:673`'s "trust the type-checker" is justified.

**Consequence:** neither finding requires a pre-req bug-fix. MATCH-WIDEN is a pure capability
extension, not a soundness repair. The professor's "latent in shipped code" flag is discharged.

## 2. The implementation fork (this is the real decision)

The current fragment has **two separate discharge mechanisms**, and MATCH-WIDEN must pick which to
generalize:

- **Int-tag desugar (`buildChain`)** — all-nullary enums → ordered nested `EIf` over `(= scr tag_c)`.
  Ordered (first-match) for free. Reuses the shipped, sound `EIf` VC path. But it is **int-tag only**
  — no payloads.
- **Skolem-branch opaque-sum elimination** (`FixpointEmit.hs:600–650`, seeding + `:1782`) — the 2-arm
  Result/both-payload path. Binds each arm payload as an **independent skolem**; per-arm, **not
  ordered** (fine today because 2 distinct exhaustive arms cannot overlap).

**Strategy A — generalize the int-tag desugar to payloads (RECOMMENDED).** Extend `buildChain` so a
payload constructor arm lowers to `EIf (is-C scr) (body[x := sel-C scr]) (rest)` — ordered nested
`EIf` over datatype **testers/selectors** instead of int-tag equality. First-match falls out for free
(same as today's enum path); nested/sequential matches become nested/sequential `EIf`, handled by the
already-sound `EIf` VC path; the professor's ordered `VC-Match` rule is then **realized structurally**
rather than hand-threaded. *Cost:* requires first-class **tester emission** (`is-C`) in the FQ IR.
Selectors already exist (the field name is the selector, `FixpointIR.hs:300`); testers are the new
piece. SMT datatype theory supports testers natively, so this is FQ-IR plumbing, not a theory
extension — but it is the single biggest unknown (see Risk R1).

**Strategy B — extend the skolem-branch path with explicit ordering.** Keep opaque-sum elimination;
generalize the param-scoped seeding (`resultKeys`/`adtKeys`, both currently require
`[(c1,Just t1),(c2,Just t2)]`) to mixed/N-arm/nested, and add the `⋀_{j<i}¬patⱼ` prior-pattern
negations by hand for catch-all correctness. *Cost:* reuses more existing code, but re-implements
ordering that Strategy A gets for free, and inherits the branch-skolem interaction with R5 stage-3
(DIP `:36`).

**Recommendation: Strategy A if tester emission is ≤ M; else B.** A is the smaller *conceptual*
surface (one ordered-desugar mechanism subsumes Slices 1–3, reuses the proven `EIf` VC), and it
sidesteps the branch-skolem/R5 interaction. The go/no-go is R1.

## 3. Slices & effort (assuming Strategy A)

| Slice | Work | Effort |
|---|---|---|
| **1 — mixed nullary/payload 2-arm sums** | widen `isCoreBodySyntactic` EMatch clause (`Syntax.hs:683–694`) to admit a mixed arm-set — **S**; emit tester+selector for the mixed 2-arm desugar (or extend seeding to `[(c,Nothing),(c,Just t)]` under Strategy B) — **M**. No ordering needed (2 distinct exhaustive arms don't overlap). **Unblocks the goto-fail leaf/single-gate.** | **M** |
| **2 — sequential matches (let-bound)** | ensure multiple top-level matches each lower/seed; `aNormalizeBody` already let-binds. Under Strategy A this is automatic (sequential `EIf`s). | **M** |
| **3 — nested + N-arm with catch-alls** | ordered nested desugar into arm bodies; **no depth budget** (Rev 1 — passive-form/`EIf` nesting is linear). Under Strategy A, mostly falls out; the only genuinely new logic is catch-all shadowing for N>2 payload arms. | **M** |
| **R1 spike — FQ-IR tester emission** | prove `is-C` testers discharge through liquid-fixpoint for a mixed sum. Gates Strategy A. | **S–M (spike first)** |

**Total: M–L.** Slice 1 (the goto-fail unblocker) is **M** and independently shippable. If R1 shows
testers are expensive, fall to Strategy B (total drifts toward **L** and re-opens the R5 interaction).

## 4. Recommended sequencing
1. **R1 spike** (tester emission) — decides Strategy A vs B. Do this first; everything hinges on it.
2. **Slice 1** — mixed 2-arm sums. Ships the goto-fail leaf. Acceptance: `finalize … -> Verdict`
   mixed-arm gate `body-faithful`; skip-twin `refuted`.
3. **Slice 2**, then **Slice 3** — the full pipeline; Post-4 of the goto-fail series.

## 5. Risks / where the proposal is optimistic
- **R1 (feasibility gate):** tester emission in the FQ IR is unproven. Selectors exist; testers do
  not appear to be emitted today (the 2-arm path uses skolem branches, not `is-C`). If liquid-fixpoint's
  datatype-theory tester support is awkward to reach through the current FQ IR, Strategy A cost rises.
  *Blocks the strategy choice, not the proposal.*
- **R2 (proposal underestimate):** the proposal frames Gap 2 as "generalize the seeding." Under
  Strategy A the real work is a **desugar rewrite** (payload-aware `buildChain`), not seeding tweaks —
  different module locus (`desugarCtorValues`, not just `:600–650`). Under Strategy B the seeding
  framing is right but ordering must be added. Either way, one of the two mechanisms must absorb
  ordering + payloads; the proposal treats them as a small extension of the existing seeding, which
  is optimistic.
- **R3 (mixed FQData construction):** composing a nullary-tag term with a payload sibling in one sum
  (`FixpointIR.hs:299`, "nullary ctors emit `{}`") is claimed to already work; verify the mixed
  `Verdict = (|Verified)(|Rejected int)` constructs and discharges (the shipped `classify.llmll` uses
  a **both-payload** sum, so mixed is unproven — the earlier `body-fallback` on a nullary-arm sum is
  evidence it does not yet). Small, but it is real new work, not free.
- **R4 (R5 interaction, Strategy B only):** more branch-skolem bodies shrink R5 stage-3 eligibility
  (DIP `:36`). Strategy A avoids this; another reason to prefer A.

## 6. Bottom line
Feasible, no blocking soundness debt, and the two suspected shipped bugs are clean. The whole plan
reduces to one question — **can the FQ IR emit datatype testers cheaply (R1 spike)?** If yes, Strategy
A subsumes all three slices into a payload-aware ordered desugar reusing the proven `EIf` VC path, and
Slice 1 ships the goto-fail leaf at **M** effort. If no, Strategy B is the fallback at higher cost.
Recommend authorizing the R1 spike + Slice 1 together.
