# R5-at-scale — first campaign (Differential Implementation Pressure, live agents)

**Role:** Experiment Lead — empirical-descriptive.
**Date:** 2026-07-05
**Compiler:** `llmll 0.14.9` (includes the sibling-call classification fix — required for the
helper-composing hole; a stale binary false-nulls `transfer_helper`).
**Solver:** `liquid-fixpoint` / `fixpoint` + `z3` on PATH (every verified/refuted status is
solver-decided, not asserted).
**Harness:** `scripts/run_multi.py` — for each single-hole scaffold, opens `checkout --multi N`,
N forced-diverse agents each fill the ONE hole into an isolated scratch, fills are injected and
`diverge-report` classifies observational divergence over Ω. Corpus + manifest under
`r5-campaign/`.

## Design

4 single-hole `def-shell` scaffolds × 3 forced-diverse frontier families
(`claude-opus-4-8`, `gpt-5.5` via codex, `gemini-3.1-pro` via agy). Contract tightness is the
independent variable; helper-composition is a second axis (`transfer_helper` calls the verified
sibling `debit`). Pre-registered expectation: witnesses on the loose holes, none on the tight
hole, suppression on the intentional hole, and — post-v0.14.9 — **no** sibling-suppression on the
helper hole.

## Results

| Hole | Contract | Verdict | verified | Witness |
|------|----------|---------|:--------:|---------|
| `clamp_weak` | weak `(>= result lo)` | **under-constraint-witness** | 2/3 | `{x:0, lo:-1}` |
| `clamp_tight` | equality `(= result (- n 1))` | no-divergence-observed | 3/3 | — |
| `clamp_intentional` | weak + `(spec-entropy :intentional)` | **suppressed-intentional** | 3/3 | `{x:0, lo:-1}` (suppressed) |
| `transfer_helper` | `(>= result 0)`, calls `debit` | **under-constraint-witness** | 3/3 | `{balance:0, amount:-1}` |

**Qualitative — real divergence between independent frontier models:**
- `clamp_weak`: claude wrote a real clamp `(if (>= x lo) x lo)`; gpt-5.5 wrote the constant `lo`.
  Both verify against `(>= result lo)`; they differ at `(x=0, lo=-1)` → 0 vs -1. A replayable
  proof the contract admits ≥2 intended behaviours.
- `transfer_helper`: claude and gemini both wrote the **helper-calling**
  `(if (>= balance amount) (debit balance amount) balance)`; gpt-5.5 wrote constant `balance`.
  Two observational buckets, all three verified. **This hole only yields a witness because of the
  v0.14.9 fix** — pre-fix the two `debit`-calling fills would both classify `type-error` and drop,
  leaving n=1 verified → no signal.

## The four measurements

1. **Under-constraint-witness rate.** All **3/3 loose-contract holes** exhibited observable
   divergence among independently-authored, all-verifying fills (2 emitted actionable witnesses;
   the intentional one was witnessed but suppressed by design). The **1/1 tight hole** showed
   none. R5 fires precisely where the contract is genuinely under-specified.
2. **Convergence rate.** The tight-equality hole → `no-divergence-observed` (all three models
   agree on `n-1`). No tightness *claim* is drawn beyond the verdict wording (the common-mode
   caveat still applies to the negative branch).
3. **Sibling-suppression incidence: 0.** `transfer_helper` (helper-composing) → 3/3 verified, 0
   `type-error`. The only `type-error` in the campaign was gemini's **missing** fill on
   `clamp_weak` (agy flakily failed to locate `AGENT_INSTRUCTIONS.md` on that one call —
   self-resolved on its other three holes), **not** a sibling drop. Pre-v0.14.9 the entire
   `transfer_helper` hole would have been all-`type-error`.
4. **Soundness (spurious-witness check).** Every witness came from ≥2 fills that **both verified
   against the real solver**; a witness cannot be manufactured (both fills provably satisfy the
   contract, so the contract provably admits ≥2 behaviours). The status partition is
   solver-decided throughout.

## Operational notes

- **11/12 agent cells produced fills.** The one miss (agy/gemini on `clamp_weak`) was agent
  flakiness — it reported "couldn't find AGENT_INSTRUCTIONS.md" despite the file being present,
  and succeeded on its other three holes. The harness degraded gracefully (that scratch stayed an
  unfilled hole → `type-error` → the witness still emerged from the two good fills). A retry
  and/or passing the instructions path absolutely would close it.
- `agy` (Antigravity) replaced the retired `gemini` CLI; headless via
  `agy -p '…' --model 'Gemini 3.1 Pro (High)' --dangerously-skip-permissions`.

## Verdict

R5-at-scale works end-to-end with live frontier models and produces the intended, sound signal:
**loose contracts → replayable under-constraint witnesses from genuinely divergent
implementations; tight contracts → convergence with no false witness; intentional looseness →
suppressed; helper-composing (realistic) holes → witnessed, with zero sibling-suppression** (the
v0.14.9 fix's payoff, observed exactly where predicted). This is a small pilot (n=1 run per hole,
3 agents); a scaled run would add repeats per cell for rate CIs and more holes spanning the
contract-tightness axis.
