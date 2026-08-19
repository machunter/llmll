---
name: resp-fact-proposal
title: "RESP-FACT-1: an effect's result carries a proved property to its caller"
status: "Rev 1, PROPOSED. Not reviewed by professor. Not scheduled."
date: 2026-08-19
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# RESP-FACT-1: an effect's result carries a proved property to its caller

**One line.** A builtin that establishes a property cannot hand it to the program, so the caller
writes a runtime guard and the builtin's behaviour never enters the logic. The fix attaches the
fact to the **match-arm binder**, not to the `Response` value.

---

## 1. What was measured, at `llmll 0.16.2`

| Probe | Result |
|---|---|
| `rg -c 'Response' compiler/src/LLMLL/FixpointEmit.hs` | **0 occurrences** |
| `Response` arm set (`TypeCheck.hs:292-300`) | `RNone`, `RText string`, `RCode int`, `RErr string`, `RList list[string]` |
| Who constructs a `Response` | Codegen. `llmll_publish (RCode (fromIntegral code))`, `CodegenHs.hs:530` |
| A pure `def` matching on `Response` | Falls back from body-faithful VC. An identically shaped user sum behaves the same (`driver-ll-open-work.md` §5) |

So `RCode` reaches the program as a bare `TInt`. A program that issues `wasi.fs.stat` receives an
integer with no lower bound. It must guard or re-prove what the builtin already guaranteed.

**Six ports routed around this and none filed it**, because writing a guard looks like ordinary
programming. The row was reached independently by language-team from the verification mapping and
by the professor from the primitive-assumption literature.

## 2. Two problems, and only one of them is this proposal's

**P1. There is no fact.** No surface lets a builtin declare a property of what it delivers, and
`FixpointEmit.hs` has no emission path for one.

**P2. A contract clause naming a `Response` param by bare name falls back.** `Response` is a
payload-bearing sum, so `clauseOverOpaqueSumParam` (`FixpointEmit.hs:1515-1526`) fires and forces
contract-only verification. An opaque sum has no value sort in the current encoding, and a clause
naming one would leave the variable unsorted and crash liquid-fixpoint.

**This proposal solves P1 and deliberately does not solve P2.** The shape below never names the
`Response` value in a clause, so P2 never fires on it. P2 stays open and belongs with `MATCH-WIDEN`.

## 3. The mechanism already exists

This is not new machinery. `FixpointEmit.hs:3414-3416` states the shape:

> A `CallVC` with `cvPreObligation = Nothing` and `cvPostAssumption = Just p` IS an axiom: an
> ASSUME-polarity fact with no PROVE side.

Two builtins ship this today. `bytes-set` carries a length-preservation fact. `bytes-zero` carries a
constructor axiom, `r = Map_default(0) ∧ bytesLen(r) = n`. The comment at `FixpointEmit.hs:3421-3423`
records the justification: the axiom holds because codegen reads the same annotation to emit the
value, so it rides the `codegen_semantics_version` stamp (`LLMLL.md` §3.5). Its validity is a
**TRUST-channel dependency, not a contract discharge.**

Codegen also constructs every `Response` (`CodegenHs.hs:521-572`). So a fact about a `Response`
payload rides the identical stamp, for the identical reason.

## 4. Design proposal

### 4.1 Shape: refine the arm payload, not the sum

A builtin declares a refinement on the payload of the arms it can deliver. The fact reaches the
program at the **match-arm binder**.

```lisp
;; wasi.fs.stat delivers an age in seconds, clamped at zero.
;; The program writes an ordinary match. The binder `n` arrives refined.
(match r
  ((RCode n)  (advancing n))     ;; n : {v : int | v >= 0} in this arm
  ((RErr  e)  (fail e))
  (_          (fail "unexpected")))
```

The program writes no guard. `advancing`'s precondition `(>= newest-artifact-age 0)` discharges
from the binder.

**Why the arm binder and not the sum.** Three reasons, each sufficient. The binder is an `int`, so
the fact stays in QF-LIA and needs no value sort for `Response`. The clause never names the
`Response` param, so `clauseOverOpaqueSumParam` does not fire. And the seam already exists:
`MATCH-TERM-EQ-1` shipped at v0.16.2 by having `emitParamBind` (`FixpointEmit.hs:1471-1504`) consult
a type-level function, `nullaryEnumArity` (`TypeAdmissibility.hs:461`), and put a domain on a binder.
This proposal adds a sibling of that consultation at the match-arm binder seam.

### 4.2 Where the fact is declared

Builtins are declared in `builtinEnv`, in Haskell, not in LLMLL source. The fact table is therefore
compiler-side, beside `builtinEnv`, and the admissibility predicate belongs in
`TypeAdmissibility.hs` next to `nullaryEnumArity`. `LLMLL.md` §13 documents each fact, because a
reader cannot see a compiler-side table.

### 4.3 Which arms may carry a fact in Rev 1

| Arm | Payload | Rev 1 |
|---|---|---|
| `RCode` | `int` | **Admitted.** Linear integer bounds. QF-LIA |
| `RList` | `list[string]` | **Admitted for length only.** `listLen` is already an admitted measure (`FixpointEmit.hs:2913`) |
| `RText`, `RErr` | `string` | **Excluded.** String structure sits outside Σ_auto (`STRLIT-BODY-1`); word equations over runtime strings are not automated |
| `RNone` | none | No payload, so no fact |

## 5. The distinction this proposal must not get wrong

`emitParamBind`'s own comment (`FixpointEmit.hs:1477-1483`) records a defect the project already
paid for. A `bytes[n]` length fact used to ride the param binder. That put it in every VC antecedent
with **nothing discharging it**, which is `SAFE-ARG`. It moved to the effective precondition, so
callers prove it and the body assumes it.

So a fact on a binder is correct only when something that **runs** guarantees it. Three categories,
and the discriminator is who guarantees the fact:

| Category | Guaranteed by | Placement | Example |
|---|---|---|---|
| Caller obligation | The caller | Effective precondition | `bytes[n]` length (`bytesLenParamPre`) |
| Type fact | The checker | Binder antecedent | `nullaryEnumArity` (`MATCH-TERM-EQ-1`) |
| **Runtime guarantee** | **Codegen** | **Binder antecedent, TRUST-channel justification** | `bytes-zero`, `bytes-set`, **and this proposal** |

A `Response` fact is the third category. It enters as an environment antecedent, so it can only
weaken an obligation and never strengthen one. Its justification is codegen, so it is disclosed as
a trust dependency rather than proved.

## 6. Edge cases and degenerate inputs

1. **Positive witness, concrete.** `wasi.fs.stat` declares `RCode` payload `{v : int | v >= 0}`.
   A `def` with `(post (>= result 0))` whose body is the match in §4.1 and returns `n`.
   Today: the binder is unconstrained, so the post is not derivable and the caller must guard.
   Under this proposal: verified, body-faithful, from the binder alone.
   **Channel: contract. Fragment: QF-LIA.**
2. **A builtin with no declared fact.** The arm binder gets `FQTrue`, exactly today's behaviour.
   This is the migration story: zero corpus movement until a fact is declared.
   **Channel: spec is silent (intentional).**
3. **A string arm.** `RErr e` binds `e` with no refinement, per §4.3.
   **Channel: spec is silent (intentional), and `STRLIT-BODY-1` is the reason.**
4. **A program that drops the `RErr` arm.** The fact is per-arm and licenses nothing about
   exhaustiveness. A non-exhaustive match is rejected as it is today.
   **Channel: type.**
5. **A wrong fact in the table.** The single unsound direction, identical in kind to a wrong arity
   in `nullaryEnumArity`. It must be pinned by tests, and it is a trust dependency rather than a
   contract discharge, so it is disclosed rather than proved.
   **Channel: trust.**
6. **A program whose own contract names the `Response` param by bare name.** Still falls back via
   `clauseOverOpaqueSumParam`. **Not fixed here. Spec is silent (gap, and it is P2).**

## 7. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| `RCode` payload bound at a match-arm binder | contract | **QF-LIA**, auto-discharged by liquid-fixpoint. `LLMLL.md` §5.3.3 |
| `RList` length at a match-arm binder | contract | **QF-LIA**, via the admitted `listLen` measure |
| A string-payload property | contract | **Outside Σ_auto.** Excluded in Rev 1, per `STRLIT-BODY-1` |
| The fact's own validity | **trust** | Not discharged. Rides `codegen_semantics_version` (`LLMLL.md` §3.5), as `bytes-zero` does |

No new sort. No new theory. No new predicate vocabulary.

## 8. Coupling: this proposal increases the population `TRUST-AXIOM` names

`TRUST-AXIOM` (roadmap, OPEN) records that a builtin's assumed fact reaches the solver on **no
channel of the trust report**. Every fact this proposal adds is such a fact. Shipping RESP-FACT-1
alone therefore increases the number of undisclosed assumed facts a verified verdict rests on.

**Recommendation: ship them coupled, or make RESP-FACT-1's facts the first population `TRUST-AXIOM`
discloses.** Shipping this proposal while the report stays silent would let a program reach
`verified` on a fact the report never names, which is the shape `LLMLL.md` §4.1's anti-laundering
clause exists to prevent.

## 9. Drift found while writing this

**The `FS-STAT-1` and `RESP-FACT-1` rows disagree, and one must move.**

`RESP-FACT-1` (roadmap :87) states that `FS-STAT-1`'s clamp was withdrawn, and that the sentence
claiming the clamp "discharges `[S12-DOM]`'s first conjunct by construction" was wrong even while
the clamp stood.

`FS-STAT-1` (roadmap :60) still states in bold that the clamp "discharges `[S12-DOM]`'s first
conjunct (`(>= newest-artifact-age 0)`) **by construction**".

Both cannot hold at HEAD. **This proposal resolves it in `FS-STAT-1`'s favour, conditionally:** the
discharge claim is false today and becomes true once a `Response` fact has a channel. So
**RESP-FACT-1 is a prerequisite of `FS-STAT-1`**, and `FS-STAT-1`'s row should say so rather than
claim a discharge it cannot perform. Routed to doc-lead, not fixed here.

## 10. Affected surface

- `compiler/src/LLMLL/TypeAdmissibility.hs` — the fact predicate, beside `nullaryEnumArity`
- `compiler/src/LLMLL/FixpointEmit.hs` — the match-arm binder seam, sibling of `emitParamBind`'s
  `nullaryEnumArity` consultation. The module has **zero** `Response` occurrences today, so this is
  new emission rather than an adjustment
- `compiler/src/LLMLL/TypeCheck.hs` — the per-builtin fact table beside `builtinEnv`
- `LLMLL.md` §13 (per-builtin facts), §9.7 (`Response`), §5.3.3 and §5.3.5 (the boundary)
- `docs/design/fs-capability-trio-proposal.md` §5 — this proposal supersedes that placeholder
- Roadmap rows `RESP-FACT-1`, `TRUST-AXIOM` (§8), `FS-STAT-1` (§9)

## 11. Risks

1. **Undisclosed assumed facts multiply.** Trust. `TRUST-AXIOM`, and §8 above.
   **Bite: complicates. Ship coupled.**
2. **The fact and the codegen must land together.** Soundness. A declared fact whose runtime does
   not enforce it is simply false. `wasi.fs.stat`'s clamp is the concrete instance.
   **Bite: blocks. One commit, not two.**
3. **String arms stay out.** Verification-ergonomics. `STRLIT-BODY-1`. Several open builtin rows
   deliver `RText`, so they gain nothing from Rev 1.
   **Bite: only matters at scale.**
4. **P2 stays open.** Spec-drift. A bare `Response` param in a clause still falls back (§2).
   **Bite: complicates. Name it; do not imply it is fixed.**
5. **A binder-antecedent fact repeats `SAFE-ARG` if miscategorised.** Soundness. §5 is the guard
   against this, and the discriminator is who guarantees the fact.
   **Bite: blocks if ignored, and §5 is the whole answer.**
