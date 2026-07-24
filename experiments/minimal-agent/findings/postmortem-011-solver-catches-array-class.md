# Postmortem 011 — Solver-Catches on the Lever A Array Class: Frontier Models One-Shot the Fixtures (0/54 Caught)

**Date:** 2026-07-24
**Compiler version:** llmll 0.14.63 (`compiler/package.yaml`; map/bytes PBT test-path evaluator landed this session, commits `a707a75` + release `9df3c64`).
**Harness:** the `007/008/009/010` solver-catches fixtures, `prepare_run.py`/`evaluate_run.py` wiring, and manifests committed alongside this postmortem.
**Experiments:** `007-map-revocation`, `008-bytes-scaled-read` (trivial round), `009-transfer-conservation`, `010-byte-saturate` (discriminative redesign).
**Models:** `claude-opus-4-8`, `gpt-5.5` (`codex exec`), `gemini-3.1-pro-preview` (paid tier; see Operational notes).
**Batches:** `runs/20260723T224420Z` (007/008/006, interrupted), `runs/20260724T002039Z` (009/010, opus+gpt), `runs/20260724T053641Z` (009/010, gemini-3.1-pro).

---

## Headline finding

Across **54 completed attempts, zero grade-A (solver-caught) cells.** On the discriminative fixtures (009/010), **30/30 grade B** across three frontier models — opus, gpt-5.5, and gemini-3.1-pro each wrote a body-faithful-verifiable correct fill on every attempt; on the trivial fixtures (007/008), 24/24 B (opus+gpt, before the batch was interrupted). Frontier models are **one-shot-correct on Lever A array-class fills, robustly — even on tasks deliberately built with a plausible subtle-error surface** (a transfer where forgetting the debit leg breaks conservation; a saturating add where forgetting the clamp overflows 255). None made the induced error. The solver's *catch* value is validated in isolation (wrong fills refute body-faithfully) but never triggered by a real agent fill.

## Sample composition

| Round | Fixtures | Models × tries | Result |
|---|---|---|---|
| Discriminative | 009 (map[int,int] transfer), 010 (bytes[8] saturate) | opus 5, gpt-5.5 5, gemini-3.1-pro 5, ×2 exp | **30/30 B** |
| Trivial | 007 (map[int,string] revoke), 008 (bytes read) | opus 5, gpt-5.5 5 (gemini unrun; batch interrupted) | 24/24 B |

All grade-B cells are `measured` with `all_targets_body_faithful=True` and `test_passed=True` (the visible non-adversarial check ran green; the withheld post verified). Spot-checked fills are the canonical correct ones (`map-put`-nested debit/credit; `if`-clamped saturating add).

## Verified findings

### F-011.1. Frontier one-shot correctness on the Lever A array class — **positive**
**Priority:** High · **Consumer:** user / language-team (positive signal)
**Evidence:** 30/30 B on 009/010 across three models (`runs/20260724T002039Z`, `runs/20260724T053641Z`); genuine correct fills (`solution.ast.json` per cell). The v0.14.32→62 depth arc's array class (`map[{int,string},{int,bool,string}]`, `bytes[n]`) is authored correctly first-try by current frontier models, and it holds under a designed error surface.
**Implication:** the depth arc delivers one-shot correctness on the array class for the frontier. No action; this is the empirical answer to the question that motivated the campaign.

### F-011.2. The solver-catches benchmark measures one-shot correctness, not catch-rate, on frontier models — **null for the catch hypothesis**
**Priority:** Medium · **Consumer:** experiment-lead / user
**Evidence:** `Solver caught (grader-gap): 0/N` in every `matrix_summary.md`; 0/54 grade-A over two fixture designs (trivial and discriminative).
**Why:** the grade-A signal requires a fill that passes the blind visible check yet violates the withheld post. Frontier models do not produce such fills on these tasks; they write the correct body. Making the tasks hard enough to induce a catch is an escalation game against strong models, with diminishing value.
**Implication:** to exhibit catch-value empirically, either (a) run a genuinely weaker model (likely to fail to author valid LLMLL at all → grade F, not a catch), or (b) accept that the benchmark, on the frontier, is a one-shot-correctness instrument. The catch-value remains established by construction (isolated wrong fills refute), not by an agent trace.

### F-011.3. `if` in a map-store body falls back from body-faithful verification — **compiler**
**Priority:** Medium · **Consumer:** compiler-engineer
**Evidence:** during 009 design, `(if c (map-put …) bal)` (map-valued `if`) and `(map-put bal a (if c …))` (conditional stored value) both verify as `body-fallback: <fn>` under `--strict-verified-core`, while straight-line stores and each branch alone reflect (a straight-line wrong fill refutes body-faithfully). Forced 009's correct fill to be straight-line. An int-returning `if`-clamp (010's brighten) is unaffected.
**Implication:** the body-faithful map fragment is currently limited to straight-line store bodies; a conditional in a map-store body routes to fallback. Route to compiler-engineer as a Lever A residue ticket.

### F-011.4. `verify` bytes body-faithfulness is intact for the e010 shape — **reconciliation**
**Priority:** Defence-in-depth · **Consumer:** user (memory)
**Evidence:** full `verify --strict-verified-core` on a wrong `brighten` body through the real grade path: `body-faithful: brighten`, `call-pre obligations: brighten`, `Running liquid-fixpoint`, `refuted: brighten` (rc 1); every e010 run cell is `bodyfaithful=True, verified`.
**Implication:** the recalled `project_verify_bytes_fallback_01463` note ("verify falls back to contract-only for bytes-param fns, wrong bodies pass SAFE") does **not** hold for the e010 shape (bytes param, `bytes-get` body, int return, range post). It may hold for another bytes shape (its own caveat flagged it "unconfirmed"); it should not be generalized. Worth updating that memory.

## Operational notes (gemini)

Getting gemini to run consumed most of the session's friction and is recorded so the next run avoids it:
- **Folder-trust:** the gemini CLI refuses untrusted dirs; the user trusting `.../llmll/experiments` propagated to the per-cell run dirs (no `--skip-trust` needed).
- **Auth shadow:** the repo-root `.env` `GEMINI_API_KEY` shadowed the paid key in `~/.gemini/.env` — gemini walks *up* from the run dir and stops at the first `.env`, so cells authenticated with the (free-tier) repo key (`free_tier ... limit 0/20`). Fixed by putting the paid key in the repo `.env`.
- **Model availability:** `gemini-2.0-pro-exp-02-05` is retired (ModelNotFound); `gemini-2.5-pro` is "no longer available to new users" on the paid key. Slot settled on **`gemini-3.1-pro-preview`** (the project Phase-3 gemini-2 step-down was a free-tier throttling workaround, moot on paid). Manifest `manifest.gemini-rerun.json` is correct and reusable.

## Null results

- **Solver-catch hypothesis** (expected a non-trivial grade-A/B split on the discriminative fixtures): **null**, 0/30 grade-A. Would have required a fill that is subtly wrong yet blind-test-passing; frontier models did not produce one.

## Priority matrix

| # | Finding | Consumer | Priority |
|---|---|---|---|
| F-011.1 | Frontier one-shot correctness on the array class | user / language-team | High (positive) |
| F-011.2 | Benchmark measures one-shot correctness, not catch-rate | experiment-lead / user | Medium |
| F-011.3 | `if`-in-map-store body-faithful fallback | compiler-engineer | Medium |
| F-011.4 | e010 bytes verify body-faithful (memory reconciliation) | user | Defence-in-depth |
