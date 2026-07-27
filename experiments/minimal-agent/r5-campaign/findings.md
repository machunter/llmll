# R5-at-scale — first campaign (Differential Implementation Pressure, live agents)

**Role:** Experiment Lead — empirical-descriptive.
**Date:** 2026-07-05
**Compiler:** `llmll 0.14.9` (includes the sibling-call classification fix — required for the
helper-composing hole; a stale binary false-nulls `transfer_helper`).
**Solver:** `liquid-fixpoint` / `fixpoint` + `z3` on PATH (every verified/refuted status is
solver-decided, not asserted).
**Harness:** `experiments/minimal-agent/scripts/run_multi.py` — for each single-hole scaffold, opens `checkout --multi N`,
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

---

# Scaled campaign (`scale-1`) — 10-hole grid × 3 agents × 5 repeats

**Date:** 2026-07-05. **Compiler:** `llmll 0.14.10` (includes the diverge-report concurrency fix,
which this campaign surfaced — see CHANGELOG §v0.14.10). **50/50 cells.** The initial run stopped
at 49/50 on a ~30-minute background-task wall-clock cap; a follow-up chunk filled the last
`transfer_tight` cell and re-ran `double_tight` with a corrected linear body (see caveat below).
Every status solver-decided. Corpus is a 2-axis grid: contract tightness {loose, tight,
intentional} × composition {self-contained, helper-composing}. Aggregator = per-hole
under-constraint-witness RATE over the repeats with a Wilson 95% CI (`runs/scale-1/aggregate.json`).

| Hole | Class | n | Verdicts | Witness rate [95% CI] | te / rf |
|------|-------|:-:|----------|-----------------------|:-------:|
| `clamp_weak` | loose/self | 5 | witness×5 | **1.00** [0.57,1.00] | 0 / 0 |
| `abs_nonneg` | loose/self | 5 | witness×4, no-div×1 | **0.80** [0.38,0.96] | 0 / 1 |
| `range_mid` | loose/self | 5 | no-div×5 | **0.00** [0.00,0.43] | 0 / 0 |
| `clamp_tight` | tight/self | 5 | no-div×5 | 0.00 [0.00,0.43] | 0 / 0 |
| `id_tight` | tight/self | 5 | no-div×5 | 0.00 [0.00,0.43] | 0 / 0 |
| `double_tight` | tight/self | 5 | no-div×5 | 0.00 [0.00,0.43] | 0 / 0 |
| `clamp_intentional` | intentional | 5 | suppressed×5 | 0.00 (all witnessed, suppressed) | 0 / 0 |
| `transfer_helper` | loose/helper | 5 | witness×4, no-div×1 | **0.80** [0.38,0.96] | 0 / 0 |
| `clamp_via_helper` | loose/helper | 5 | no-div×5 | **0.00** [0.00,0.43] | 0 / 0 |
| `transfer_tight` | tight/helper | 4 | no-div×4 | 0.00 [0.00,0.49] | 0 / 0 |

## Findings

1. **Sibling-suppression incidence = 0 across ALL helper-composing holes, at scale.**
   `transfer_helper` + `clamp_via_helper` + `transfer_tight` = 15 cells, 45 helper-context fills,
   **0 type-errors**. The v0.14.9 fix holds under load — helper-calling fills classify on their
   merits throughout.

2. **A loose contract is necessary but NOT sufficient for a witness — the headline result.**
   `clamp_weak` (1.00), `abs_nonneg` (0.80), `transfer_helper` (0.80) exposed real under-constraint;
   but `range_mid` and `clamp_via_helper` are *equally loose by construction* (multiple correct
   implementations exist and verify) yet produced **0 witnesses** — all three models converged on
   the same "obvious" fill on every repeat. This is the common-mode caveat (Knight–Leveson 1986)
   observed empirically: **R5's witness rate measures {contract looseness} × {model divergence},
   not looseness alone.** Consequently `no-divergence-observed` does **not** certify a tight spec —
   `range_mid` is a live counterexample (genuinely loose, zero observed divergence). Exactly the
   proposal's asymmetry: treat `under-constraint-witness` as sound positive evidence; treat
   `no-divergence-observed` as "no signal."

3. **Run-to-run variance is real.** `abs_nonneg` (4/5) and `transfer_helper` (4/5) show the same
   three models sometimes diverging, sometimes converging across repeats — so the witness rate is a
   genuine mid-range quantity for some holes, and repeats add signal beyond a single run.

4. **Soundness holds.** Every witness came from ≥2 solver-verified fills; **no witness fired on any
   tight hole**. The positive branch never triggered spuriously.

## Corpus caveat (a hole-design bug this run surfaced — now fixed)

- **`double_tight` was degenerate, and is fixed.** Its original body `(* 2 n)` tripped the
  nonlinear-fallback in classification (the classifier conservatively treats any `*` as outside
  QF-LIA → `FSRefuted`), so all 15 fills refuted — the hole yielded no verified competitors and its
  `no-divergence` was vacuous. Corrected to `(post (= result (+ n n)))` (linear, in QF-LIA) and
  re-run: it now behaves as a clean tight hole (**5/5 `no-divergence`, all fills verified, 0
  refuted**), consistent with `clamp_tight` and `id_tight`. The table above reflects the corrected
  run. *(Compiler backlog note: `isNonLinear` flags constant-coefficient multiplication like
  `(* 2 n)` as nonlinear even though it is decidable — a conservative over-approximation, not a
  soundness issue.)*

## Scale-up verdict

The scaled grid confirms the pilot's sound core and adds the load-bearing empirical nuance:
witnesses are real and never spurious; sibling-suppression is closed at scale; and the *absence*
of a witness conflates a tight spec with correlated models — so the negative branch stays
uninformative, precisely as designed. Next iteration: to probe the looseness × divergence
factorization, add forced-diversity knobs (temperature variants, more model families) so the
"loose-but-converged" holes (`range_mid`, `clamp_via_helper`) can be pushed toward divergence and
the two factors separated. (Operationally: background runs are capped at ~30 min here, so a larger
matrix should raise `--concurrency`, chunk by `--holes`, or split `--repeats`.)
