# Postmortem 008 — DEF-RET `expected_return_type` Payoff: Dormant in the Minimal-Agent Harness (Null, Instrument Gap)

**Date:** 2026-06-21
**Harness SHA:** branch `oblig-1-followon/expected-return-type`, HEAD `f493bf4` (one past feature commit `a948deb`).
**Compiler version:** llmll 0.13.0 (`compiler/package.yaml`; 0.13.1-in-dev on branch).
**Experiment:** none run — payoff assessment of DEF-RET (`expected_return_type` population for function-body holes).
**Run ID:** none (no benchmark launched; nothing to measure on current fixtures).
**Excluded from analysis:** n/a.

---

## Headline finding

`expected_return_type` is **dormant in the minimal-agent harness** — it cannot fire on any current fixture, for a structural reason independent of DEF-RET, so the harness produces **zero evidence** for or against the hypothesis (telling a hole-filling agent the exact return type it must produce raises first-round fill correctness). The field populates only when a body hole is `EHole (HNamed _)` **and** its enclosing `def`/`def-shell` declares `-> RetType` (commit `a948deb`: `HoleAnalysis.collectHolesStmtIdx` SDef/SDefShell arms; surfaced via `inferredTypeLabel`/`inferredTypeJson` in `Sketch.hs` → checkout brief `Checkout.hs:219` and holes report). The minimal-agent experiments are **blank-slate authoring** tasks — the agent writes the whole program from `problem.md`; there is no pre-seeded hole, so the checkout/holes brief never carries a body-hole-under-declared-return. `grep -rn expected_return_type experiments/` returns nothing; the evaluator runs `holes --deps` but never `checkout`.

## Is the field exercised by any fixture? No.

| Fixture | Seeds a hole? | Def form | Declares `-> RetType`? | Fires `expected_return_type`? |
|---|---|---|---|---|
| 001 / 002 / 004 | No (blank-slate authoring) | n/a | n/a | No |
| 003 scaffold | Yes (4 named body holes) | `def-logic` (SDefLogic) | No | No |

The single seeded-hole fixture (003, `scaffold-templates/ecommerce-order-handler/scaffold.ast.json`) misses for **two independent reasons**: its holes sit on `def-logic` (untouched by DEF-RET, slated for removal per the v0.12.1 work-order) and carry no `return_type` (the `return_type` keys in that file are on `def-interface` signatures, not def bodies).

## Standing instrument gap (the substantive finding)

The minimal-agent harness has **no fill-the-hole regime** — every experiment is whole-program authoring, so the entire checkout/holes-brief context surface (`expected_return_type`, `in_scope`, `contract_pre`, `postcondition_goal`, `consumed_guarantees`) is **untested by any fixture**. DEF-RET is the first feature whose payoff lives *entirely* in that surface, which is why it lands dormant. This is a standing instrument gap, not a DEF-RET-specific one.

## A/B design (specified; prerequisites stated, not launched)

- **Hypothesis:** populating `expected_return_type` for a function-body hole raises first-round fill correctness. **Null:** delta ≈ 0 (the type is already inferable from params/contract/problem text). **Failure-of-instrument:** both arms ceiling at 100% (cf. postmortem-007 — a self-telegraphing trap cannot move a saturated ceiling).
- **Fixture shape (the missing prerequisite):** a *new* seeded-hole experiment whose `solution.ast.json` ships pre-authored with one or more `def`/`def-shell` statements carrying `-> RetType` and a bare `{"kind":"hole-named"}` body; the agent's task is to *fill the hole*, not author the program. The return type must be non-obvious from the param list alone (refinement-aliased return, `Result[t,E]`, or sum type) so the field carries real information.
- **Metric:** first-round fill correctness — `check --strict` + `holes --deps` (no remaining holes) + `verify` pass on the first attempt, per the existing stop policy. Pass@k under a repair budget is a sibling regime (repair-loop harness); do not retrofit it here.
- **Confound controls:** (1) byte-identical `problem.md` across arms except the injected field — reuse the `context_effect_summary` injection pattern (`prepare_run.py` / `run_matrix.py`), adding a parallel `context_expected_return_type` hook; (2) same seeded fixture both arms — only the brief differs; (3) pre-check that condition B (no type given) is not already near-ceiling; (4) pin model versions + harness SHA; mirror postmortem-007's 3-model × {A,B} × 3-tries layout.

## What was run

Nothing executable. The dormancy finding is a structural property of the fixtures and the gating code, both read directly; it does not depend on running the compiler. (Compiler-probe Bash calls were sandbox-denied in the assessing agent; a `stack build`/run is outside the cheap/self-contained budget.)

## Routing

- **experiment-lead (owner):** author the seeded-hole `def … -> RetType` fixture + the `context_expected_return_type` injection hook; closing the fill-the-hole regime gap is the prerequisite to any measurement.
- **language-team:** no spec implication — DEF-RET is shipped surface; the *payoff is unmeasured pending fixtures*, not a design problem.
- **compiler-engineer:** no bug. Descriptive note: `def-logic`/SDefLogic was correctly not given the return-type surface and is slated for removal, so the 003 scaffold's `def-logic` holes will never trigger the field; if 003 is meant to exercise it, the scaffold must migrate to `def`/`def-shell` with annotations.

## Recommended next move

1. **Do not launch a benchmark yet** — no fixture exercises the field; a run today measures nothing.
2. **Prerequisite:** seeded-hole fixture + injection hook (experiment-lead-owned harness work).
3. **Gate the A/B on DEF-RET demo adoption** — if the withdraw-demo / examples adopt `-> RetType` on real def bodies (documentation-lead track, this session), those become natural seed fixtures and the A/B inherits ecological validity instead of a synthetic fixture.
