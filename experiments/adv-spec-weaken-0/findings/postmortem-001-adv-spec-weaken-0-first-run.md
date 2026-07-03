# Postmortem 001 — adv-spec-weaken-0 first run (+ F-001 fix verification)

## Headline finding

Across n=8 fixtures × 4 CLI configs (32 cells, 0 errors, definitive run `runs/20260703T001150Z/`), every pre-registered adversarial prediction confirmed and zero null results occurred. The self-attestation mitigation (`over-annotation-warning`) was structurally absent from `--json` output regardless of `:intentional` ratio (F-001) — **fixed in this session**, commit pending on branch `fix/trust-report-over-annotation-json`, `compiler/src/LLMLL/TrustReport.hs`. The closed candidate set Ω cannot detect a surgically-narrow contract weakening on either an arithmetic or a measure-class (`list-length`) quantity (F-003, unfixed by design) — a genuinely wrong, refuted-against-the-honest-spec implementation reports `verified (liquid-fixpoint)` with a diagnostic profile byte-identical to the honest baseline. The module-level ratio guardrail has a floor a targeted single-function attack clears for free once diluted below 30% (F-002, **settled** as a design-scope limitation, not a coding defect — `LLMLL.md §4.4.6` clarified; no second automated signal, per the self-attestation framing the CDP proposal and professor review already established).

## Self-correction note (read before citing run `20260702T232009Z`)

The first run (`runs/20260702T232009Z/`) mis-scored `ax1-04-diluted-below-threshold` as `silent` across all four CLI configs. Root cause: the fixture's `double-it`/`negate-it` filler functions used `(* 2 x)`, which `def`'s core-grammar syntactic check rejects unconditionally (any `*`, regardless of one operand being a literal, requires `def-shell` — confirmed by direct reproduction, not a compiler bug). The fixture never compiled; `llmll` exited nonzero with a parse-time error and printed no JSON. The driver (`scripts/run_adv_weaken.py`) set `"status": "ok"` for any subprocess that ran without a Python-level exception, regardless of `returncode` — so the empty `json_lines` list from the failed invocation was indistinguishable from a genuine "no diagnostic fired" silence, and `summarize_cell` reported `silent`. This was caught before publication by re-verifying the F-001 fix against `ax1-04` directly (`stack exec llmll -- --json verify --cdp --trust-report ax1-04...` printed the raw grammar error, not JSON). Fixed: the fixture's `double-it` now uses `(+ x x)` in place of `(* 2 x)`; the driver now sets `"status": "compiler-error"` on nonzero exit, which `summarize_cell` reports as `ERROR`, not `silent`, so this class of mistake cannot recur silently. **`runs/20260702T232009Z/` is superseded; `runs/20260703T001150Z/` is the definitive dataset for every finding below.** All other 7 fixtures' data was unaffected by this bug and reproduced identically across both runs.

## Sample composition

- 8 fixtures (`experiments/adv-spec-weaken-0/fixtures/*.llmll`), each run under 4 CLI configs (`experiments/adv-spec-weaken-0/manifest.json` `cli_configs`): `weakness-check-json` (`--weakness-check --json`), `cdp-json` (`--cdp --trust-report --json`), `strict-verify-json` (`--strict-verify --json`), `strict-verify-text` (`--strict-verify`, no `--json`).
- 32 cells total, 0 timeouts, 0 parse errors (post-correction).
- Compiler: `llmll 0.14.4`, commit `4d104c5` (base), plus the uncommitted F-001 fix on branch `fix/trust-report-over-annotation-json` at the time of the definitive run.
- Definitive run directory: `experiments/adv-spec-weaken-0/runs/20260703T001150Z/` (`results.json`, `summary.md`, `per-fixture/*.json`).

## Fixture corpus

| ID | Axis | Mechanism |
|---|---|---|
| `ax1-00-honest-baseline` | control | tight `(= result (- balance amount))`, correct impl |
| `ax1-01-loud-naked` | AX1 (self-attestation) | post weakened to `(>= result 0)`; no annotation |
| `ax1-02-loud-laundered-singlefn` | AX1 | same weakening + `(spec-entropy :intentional)`, 1-fn module (ratio 100%) |
| `ax1-03-diluted-above-threshold` | AX1 | same laundering, 2-fn module (ratio 50%, above 30% threshold) |
| `ax1-04-diluted-below-threshold` | AX1 | same laundering, 5-fn module (ratio 20%, below 30% threshold); filler functions use `(+ x x)`/`(- 0 x)`/`(+ x 1)` (post-correction) |
| `ax2-00-list-honest-baseline` | control | tight `(= result (+ (list-length xs) 1))`, correct impl |
| `ax2-01-arith-tolerance-band` | AX2 (Ω blind spot) | post widened to `±1` band around `(- balance amount)`; wrong impl bugs at `balance == amount`; no annotation |
| `ax2-02-list-length-trapdoor` | AX2 | same pattern over `(list-length xs)`; wrong impl bugs at `list-length xs == 3` |

## Verified findings

### F-001. `over-annotation-warning` never appeared in any `--json` output — FIXED

**Priority:** Blocker
**Consumer:** compiler-engineer
**Status:** Fixed this session. `compiler/src/LLMLL/TrustReport.hs`: new `OverAnnotationInfo` record + `trOverAnnotation` field on `TrustReport`, computed inside `buildTrustReportWithCDP` from `overAnnotationRatio entryStmts` / `overAnnotationThreshold` (`CDP.hs:189-208`), emitted as a top-level `"over_annotation": {"ratio": <float>, "threshold": 0.3, "warning": <bool>}` object in `formatTrustReportJson`. No `trust_report_version` bump (stays `1.4.0`), following the `joint_pbt_witnesses`/`overflow_tainted_fns`/`refuted_fns` additive-field precedent. Branch `fix/trust-report-over-annotation-json`, not yet committed (pending user review-ready signal).

#### Evidence (pre-fix)
`compiler/app/Main.hs:1479-1488`:
```haskell
let intentRatio = overAnnotationRatio stmts
when (intentRatio > overAnnotationThreshold) $
  unless json $ TIO.putStrLn $ "   ⚠ over-annotation-warning: " <> ...
```
`ax1-02-loud-laundered-singlefn` (ratio 100%) and `ax1-03-diluted-above-threshold` (ratio 50%, above `overAnnotationThreshold = 0.30` at `CDP.hs:193`): both showed `over-annotation-warning` in `strict-verify-text` and its complete absence — no key anywhere in the parsed JSON — in `weakness-check-json`, `cdp-json`, `strict-verify-json` (confirmed in both `runs/20260702T232009Z/` and reproduced again pre-fix during implementation).

#### Evidence (post-fix, acceptance confirmed)
`runs/20260703T001150Z/per-fixture/ax1-02-loud-laundered-singlefn.json` and `ax1-03-diluted-above-threshold.json`, `cdp-json`/`strict-verify-json` cells: `over_annotation:ratio=1,warning=True` and `over_annotation:ratio=0.5,warning=True` respectively — now present. `ax1-00-honest-baseline`, `ax2-00`, `ax2-01`, `ax2-02` (no `:intentional` anywhere): `over_annotation:ratio=0,warning=False`. `ax1-04-diluted-below-threshold` (ratio 20%, below threshold): `over_annotation:ratio=0.2,warning=False` — correctly non-firing, not a residual bug (see F-002).

#### Why we saw what we saw
`overAnnotationRatio`/`overAnnotationThreshold` (`CDP.hs:189-208`) computed and compared correctly; the emission call site was `unless json`-gated with no corresponding write into the JSON output path. The value was real and correctly thresholded — it simply never reached any machine-readable surface pre-fix.

#### Implication
Any programmatic consumer of `--json` output (CI gate, agent, trust-report tooling) can now observe the guardrail the CDP proposal (§10 Risk #3) names against bulk self-attestation gaming, whenever `--trust-report` is requested (via `--cdp --trust-report` or `--strict-verify`). `--weakness-check --json` alone and `--cdp --json` alone (without `--trust-report`) remain out of scope — both already lacked any comparable module-level JSON surface before this fix, and adding one there would be a new shape rather than a fill of an existing gap (see the approved plan's "Risks and unknowns" §3).

### F-002. Single-function laundering evades detection entirely once diluted below 30% module ratio

**Priority:** High
**Consumer:** compiler-engineer, language-team
**Status:** **Settled** — design-scope limitation, not a coding defect; `LLMLL.md §4.4.6` clarified (abuse-rate-vs-per-instance framing + external-policy path). Adjudicated jointly by language-team (settle-as-designed — no automated per-instance oracle exists on a self-attestation channel) and compiler-engineer (defer-to-CI — per-function score + annotation are already machine-readable, so no compiler change). No second automated signal added; the optional `:intentional`-reason-string enhancement is a separate, user-elected proposal, not part of this close-out.

#### Evidence
`ax1-04-diluted-below-threshold` (5-fn module, 1 laundered contract, ratio 20%, `runs/20260703T001150Z/per-fixture/ax1-04-diluted-below-threshold.json`): per-function `withdraw` entry shows `entropy=intentional` with an empty per-function `warnings` list (suppressed, as designed for `:intentional`), and the now-visible module-level `over_annotation` field correctly reports `ratio=0.2, warning=False` — genuinely below threshold, not a bug in the F-001 fix. Contrast `ax1-01-loud-naked` (same weakening, no annotation, no dilution): `weakness-check-diag x2`, `cdp:withdraw:identity-satisfies-post,const-satisfies-post`, `score=0.10175559829607284`.

#### Why we saw what we saw
`raiseLowDP` (`compiler/src/LLMLL/Syntax.hs:362-364`) suppresses the per-function diagnostic on any `:intentional` annotation regardless of module composition (shared gate consumed at `Main.hs:1667` for `--weakness-check` and `CDP.hs:397` for `--cdp`). The module-level ratio check — now visible in JSON per F-001 — is the only remaining guardrail, and a ratio-over-the-whole-module check is defeated by construction when diluted with enough honestly-contracted functions. This is not an edge case; it is the mechanism's designed shape, and the F-001 fix makes the (correct, as-designed) non-firing at 20% newly auditable rather than changing the underlying detection gap.

#### Design-level framing
Matches the CDP proposal's own scoping (§10 Risk #3 Rev 2): "the 30% threshold is... an *abuse-rate* check, not a *per-instance-justification* check." The finding is that the abuse-rate check has a floor a targeted single-function attack clears for free in any module with ≥4 contracted functions — zero defense-in-depth, not a bug relative to stated scope. F-001's fix makes this floor observable in JSON (an agent or CI gate can now compute the ratio itself and decide its own stricter policy); it does not close the floor.

#### Implication
For compiler-engineer: whether a second, non-ratio-based signal (e.g., diff-aware: annotation added in the same change that weakened the contract) is feasible. For language-team: `LLMLL.md §4.4.6`'s self-attestation framing should reflect that the ratio threshold provides no protection against a single targeted instance in a module of ordinary size — this is now more actionable than before, since F-001 makes the ratio a machine-readable quantity a stricter external policy could threshold differently (e.g., a CI gate could refuse any nonzero `:intentional` count in a module below N functions, tighter than the compiler's built-in 30%).

#### Acceptance
No acceptance condition within the current single-ratio design — this is a scope limitation of the abuse-rate check as specified. Acceptance would require a design decision (a second signal) out of this benchmark's authority to propose.

### F-003. Closed candidate set Ω cannot detect a surgically-narrow contract weakening

**Priority:** High (as empirical grounding of a documented caveat)
**Consumer:** language-team, documentation-lead
**Status:** Descriptive — no action implied beyond awareness; not applicable to the F-001 fix (orthogonal mechanism, no annotation involved).

#### Evidence
`ax2-01-arith-tolerance-band` and `ax2-02-list-length-trapdoor` (`runs/20260703T001150Z/per-fixture/`): both report `effective_level: "verified (liquid-fixpoint)"`, `headline: "spec-too-tight-for-omega"`, `score: null`, `warnings: ["spec-too-tight-for-omega"]`, `over_annotation:ratio=0` — identical in every field to `ax1-00-honest-baseline` and `ax2-00-list-honest-baseline` respectively. Both adversarial implementations are refuted against their fixture's original tight postcondition (verifiable by hand: `ax2-01`'s body returns `balance - amount + 1` when `balance == amount`, violating `= result (- balance amount)`) and verified against the widened one.

#### Why we saw what we saw
Ω is closed and finite (`LLMLL.md §4.4.6`, candidate-set proposal §4.3.1: consts, per-param identity, small enumerations). A tolerance band tracking an unbounded per-input quantity (`balance - amount`, `list-length xs`) by a fixed small margin cannot be satisfied by any fixed-value or identity candidate for arbitrary inputs — both the honest tight contract and the adversarially-widened one land on the same "no Ω candidate satisfies" branch, so the score computation cannot distinguish them.

#### Implication
Not a defect — `LLMLL.md §4.4.6`'s "observational, not semantic" caveat already discloses this boundedness abstractly. This is a concrete, minimal, worked confirmation that the caveat is load-bearing against a realistic minimal attack shape (a single-input ±1 boundary bug), holding across two distinct type-classes (arithmetic, list-length/measure via local theory extension). For documentation-lead (via user routing, not directly): a ready-made worked counterexample if `§4.4.6` is ever extended with an example.

#### Acceptance
Not fixable within the current Ω design without changing the candidate-set class itself (e.g., per-input-relative candidates) — a language-team-scope design question, not raised as an action item here.

## Minor finding

**`if`-guard directly over a raw `(list-length xs)` call falls back to `body_fallback`** (`effective_level` downgrades to `asserted`, no SMT check at all) rather than translating. `(let [(n (list-length xs))] (if (= n 3) ...))` translates cleanly (`body_faithful`). Observed while constructing `ax2-02-list-length-trapdoor.llmll`; workaround applied in the shipped fixture (see its header comment). Not traced further — would require reading `GuardClassifier.hs`/`bodyToPredM`, out of scope here. Consumer: compiler-engineer, Priority: Low, unscoped.

## Harness bug found and fixed during this session

**`run_adv_weaken.py`'s `run_one` conflated a nonzero compiler exit with a genuine "no diagnostic" silence** (see Self-correction note above). Fixed: `status` is now `"ok"` only on `returncode == 0`, else `"compiler-error"`; `summarize_cell` already reported any non-`"ok"` status as `ERROR`, so this one-line fix (`scripts/run_adv_weaken.py`, `run_one`) closes the gap. This is a harness defect, in-scope for experiment-lead's own documentation surface (per `experiments/<harness>/` ownership) — not routed elsewhere.

## Withdrawn items

None on the substantive findings. The `ax1-04` `silent`-across-all-configs characterization from the first run (`20260702T232009Z`) is withdrawn and replaced by the corrected `runs/20260703T001150Z/` data (see Self-correction note) — the corrected data still supports F-002's claim (no per-function or module-level signal at 20% ratio), so F-002 itself is not withdrawn, only its original evidence citation.

## Null results

None. Both pre-registered null conditions — H1 (self-attestation) failing to reproduce in ≥3 of 4 cells; H2 (`ax2-02` failing to reproduce `ax2-01`'s pattern, indicating the blind spot is arithmetic-only) — did not occur.

## Priority matrix

| # | Finding | Consumer | Priority | Status |
|---|---|---|---|---|
| F-001 | `over-annotation-warning` absent from all `--json` output | compiler-engineer | Blocker | **Fixed** (branch `fix/trust-report-over-annotation-json`, uncommitted) |
| F-002 | Module-ratio guardrail has a trivial-to-clear floor | compiler-engineer, language-team | High | **Settled** — design-scope limitation; §4.4.6 clarified, no compiler change |
| F-003 | Ω blind spot confirmed on 2 type-classes | language-team, documentation-lead | High (descriptive) | Open — awareness only |
| minor | `if`-guard-over-raw-measure body-fallback | compiler-engineer | Low | Open — unscoped, workaround exists |

## Findings file(s) written

- `experiments/adv-spec-weaken-0/findings.md` — updated to reflect F-001 fixed status.
- `experiments/adv-spec-weaken-0/findings/postmortem-001-adv-spec-weaken-0-first-run.md` — this file (rewritten to fold in the F-001 fix verification and the ax1-04 self-correction).
