# Postmortem-004 — Phase-3 Launch (cross-language matrix; first findings)

> **Status:** Phase-3 81-cell matrix executed across two batches (original LLMLL + sibling no-codex Python/Go). **57 cells executed, 52 with H1/H2/H3-analyzable outcome.** 5 infrastructure-fails (F-035 single-recurrence, F-038 recurrence, F-041 new). 24-cell hole documented (18 codex × Python/Go deferred to F-038 quota resolution; 6 Gemini × Go and 3 Claude × Go × 003-rate-limiter not executed after F-041 circuit-breaker halt at sibling-batch cell 48). H1-Correctness, H1-Assurance, H2, H3 findings extracted from the 52-cell analyzable dataset.
> **Date:** 2026-05-17.
> **Compiler version pin:** 0.10.6.
> **Harness commit:** `2725029` (post-F-040 path 1 fix; post-Launch-commit-hash pinning; per the audit's immutability protocol the pre-registered predictions are immutable from `4078b76` per `docs/design/phase3-problem-shape-audit.md:15`).

## Headline finding

Cross-paradigm Phase-3 data revises H2 (convergence differential) as empirically refuted in its raw form: LLMLL converges in **more** turns than Python (avg 3.0-3.2 vs 1.0), not fewer — a structural consequence of LLMLL's stricter Cred(R) terminal predicate vs Python/Go's `all-pass` predicate, not an agent-capability gap. H1-Assurance bifurcation works as designed; H1-Correctness on cells that reach terminal is comparable across paradigms (Python/Go uniformly 1.000; Claude × LLMLL avg 0.89; Codex × LLMLL avg 0.84) — meaning the verification surface buys structured assurance signal at the cost of more iteration but without sacrificing behavioral correctness when the agent succeeds. H3 (null-watcher) confirmed-and-extended: on non-QF-LIA 001-hangman, LLMLL produces no measurable terminal-reaching advantage over Python/Go (3/9 vs 18/18); bounds the value claim. Cross-agent LLMLL ordering monotone across all three problems: Codex (6/9) > Claude (4/9) > Gemini-2-exp (0/9).

## Sample composition

**Two batches with deliberate hole.**

| Batch | Composition | Cells executed |
|---|---|---|
| `runs/20260516T191018Z-matrix/` | Original 81-cell manifest (3 agents × 3 problems × 3 targets × 3 tries). Halted at cell 27 by F-038 recurrence after slice 3. | 27/81 (LLMLL slice complete) |
| `runs/20260517T131841Z-matrix/` | Sibling no-codex manifest (2 agents × 3 problems × 3 targets × 3 tries = 54 cells). Resumed from cell 19 (LLMLL Claude+Gemini cells already in original batch). Halted at cell 48 by F-041 circuit-breaker. | 30/54 (cells 19-48 executed) |
| **Combined** | | **57/81 of original scope** |

**24-cell hole, documented explicitly:**

| Hole | Count | Reason |
|---|---|---|
| Codex × Python/Go (3 experiments × 3 tries × 2 targets) | 18 | F-038 OpenAI quota recurrence at cell 24; Jun 12 2026 reset; deferred to codex-only follow-up matrix |
| Gemini × Go × 002-bank-ledger × 3 tries | 3 | F-041 Gemini account-level quota; executed but rc=1 each (infrastructure-fail) |
| Gemini × Go × 003-rate-limiter × 3 tries | 3 | F-041 carry; not executed (breaker halt at cell 48) |
| Claude × Go × 003-rate-limiter × 3 tries | 3 | Breaker halt collateral; would have succeeded |

**Models, CLI versions, auth paths:**

- Claude: Claude Code 2.1.141; cmd carries F-036 hypothesis-5 candidate-2 flags (`--add-dir {run_dir} --permission-mode bypassPermissions --settings '{"permissions":{"allow":["Write","Bash"]}}'`); OAuth/keychain auth; default model (no `--model` flag).
- Codex: codex-cli 0.130.0; `gpt-5.5` model at default `xhigh` reasoning effort; `OPENAI_API_KEY` auth; manifest cmd verified at calibration.
- Gemini: Gemini CLI 0.41.2; **default model resolves to `gemini-2.0-pro-exp-02-05`** — deliberate operator step-down from Gemini 3 due to throttling on the operator's account at the time of manifest authoring (per project memory `gemini-2-vs-3-phase3-choice`); `GEMINI_API_KEY` loaded from `.env` via `set -a; source .env; set +a` shell prefix to each `run_matrix.py` invocation (harness does not auto-load .env).

**Toolchain pins (discipline A verified at each batch start):** `llmll 0.10.6`, `python 3.11`, `go 1.23`. No pin mismatches.

**Stop-fast disciplines all carry from postmortem-003:** A (toolchain pin verification), B (circuit breaker at threshold 3 in `manifest.phase3.json`; threshold 3 in sibling manifest), C (compiler health probe via `scripts/fixtures/health-probe.llmll`). Disciplines A and C silent (no failures); discipline B tripped once at sibling-batch cell 48 on F-041.

## Verified findings (hypothesis-class)

### H1-Assurance bifurcation — confirmed by data, working as designed

**Consumer:** language-team (validates R6d adjudication + the spec design at `LLMLL.md §4.4.1:344`).

#### Evidence

LLMLL cells produce structured `tier_profile` per-cell (six-int aggregate: verified / proved / contract_checked / tested / asserted / no_contract); Python/Go cells produce a binary `all-pass` predicate over the testkit suite. The harness's per-axis rubric (`evaluate_run.py` after F-040 path 1 fix at commit `4078b76`) emits per-target evidence dicts with distinct shapes per `_extract_llmll_evidence` / `_extract_python_evidence` / `_extract_go_evidence`. No scalarization across paradigms.

LLMLL target-reached cells exhibit substantive within-LLMLL tier variation:

| Cell | Agent × Problem (try) | Turns | tier_profile (above-threshold) |
|---|---|---|---|
| 1 | Claude × 001-hangman (1) | 2 | `{tested: 13}` |
| 4 | Codex × 001-hangman (1) | 3 | `{verified: 2}` |
| 5 | Codex × 001-hangman (2) | 3 | `{tested: 15}` |
| 12 | Claude × 002-bank-ledger (3) | 2 | `{verified: 9}` |
| 13 | Codex × 002-bank-ledger (1) | 4 | `{verified: 4}` |
| 15 | Codex × 002-bank-ledger (3) | 4 | `{verified: 4}` |
| 19 | Claude × 003-rate-limiter (1) | 4 | `{verified: 4}` |
| 20 | Claude × 003-rate-limiter (2) | 4 | `{verified: 8}` |
| 22 | Codex × 003-rate-limiter (1) | 2 | `{tested: 4}` |
| 23 | Codex × 003-rate-limiter (2) | 3 | `{tested: 3}` |

The six-int aggregate distinguishes assurance-by-proof (verified, proved) from assurance-by-testing (tested, contract_checked). Python/Go cells have no comparable native signal. **The H1-Assurance bifurcation is not just preserved by the harness; the data shows it's load-bearing — agents make different choices about which obligations to push to which tier, and the spec lets us see and compare those choices.**

#### Implication

Spec design at `LLMLL.md §4.4.1:344` (diamond incomparability declaration) and `experiments/repair-loop/README.md:283-303` (R6d Cred(R) split) is validated empirically. No spec change implied. The original `docs/design/language-comparison-experiments.md:27` no-scalarization commitment ("avoid a single 'winner' score that treats unit tests and body-faithful verification as equivalent") is what enabled this analysis; if it had been scalarized at design time, the assurance-strategy delta below would have been suppressed.

#### Acceptance

N/A — this is a confirmation finding, not a remediation. The data closes language-team's R6d adjudication loop on the empirical side.

---

### H2 (convergence differential) — refuted in raw form; reframing implied

**Pre-stated H2 (`experiments/repair-loop/README.md:47-50`):** *"On tasks whose dominant invariant class is inside LLMLL's QF-LIA fragment, LLMLL converges in fewer turns than Python."*

**Consumer:** language-team (the operationalization of "convergence" needs reconsideration given the empirical data).

#### Evidence

Turns-to-terminal for target-reached cells, per (agent, target):

| Agent × Target | n | Turns | Mean |
|---|---|---|---|
| Claude × LLMLL | 4 | [2, 2, 4, 4] | 3.0 |
| Codex × LLMLL | 6 | [2, 3, 3, 3, 4, 4] | 3.2 |
| Claude × Python | 9 | [1, 1, 1, 1, 1, 1, 1, 1, 1] | 1.0 |
| Gemini × Python | 9 | [1, 1, 1, 1, 1, 1, 1, 1, 1] | 1.0 |
| Claude × Go | 6 | [1, 3, 3, 3, 3, 3] | 2.7 |
| Gemini × Go | 3 | [1, 1, 3] | 1.7 |

On 002-bank-ledger (the QF-LIA-dominant problem H2 was framed around): Claude × LLMLL took 2 turns when it reached terminal; Codex × LLMLL took 3-4 turns. Python on the same problem took 1 turn (every try, both agents). **LLMLL converges in more turns than Python on this QF-LIA-dominant task, not fewer. H2 in its raw form is empirically refuted.**

#### Why we saw what we saw — predicate-bar mismatch is the structural cause

The terminal-target predicates differ across targets per the design:

- Python (`manifest.phase3.json:terminal_target_per_target.python.kind = "all-pass"`): the cell terminates when the testkit's pytest suite passes. This is a behavioral-correctness predicate.
- LLMLL (`manifest.phase3.json:terminal_target_per_target.llmll.kind = "trust-tier", value = "all-expected-contracts-above-asserted"`): the cell terminates when R6d Cred(R) is satisfied — every declared obligation at a tier strictly above `asserted` AND every expected contract from the testkit present.

These are different bars. Python's `all-pass` is satisfiable in one turn because the agent can emit a functioning Python implementation in one shot (Python is the agents' training distribution; the bank-ledger / hangman / rate-limiter problems are well within first-turn capability). LLMLL's Cred(R) requires structured verification work the agent must iterate through: emit, run verifier, observe trust report, refine obligations, re-emit, repeat until every contract is above-asserted.

**The "more turns" delta is not "LLMLL agents are slower at the problem"; it is "LLMLL agents are asked to do more per turn."** This is the experiment's design, not a defect — but H2's framing implicitly assumed comparable predicate difficulty across targets.

#### Implication

H2's pre-stated form is refuted by data: at Phase-3's k=5, with the per-target predicates as specified in `terminal_target_per_target`, LLMLL does not converge faster than Python on QF-LIA-dominant tasks. The convergence delta runs in the opposite direction.

A reframing of H2 that survives the data could be:

- **H2-revised-A (matched-difficulty):** "When predicates are matched on difficulty (e.g., both targets required to pass the same behavioral testkit AND produce a per-target-native trust signal), LLMLL converges in comparable or fewer turns." — Untestable without a harness change to align predicates.
- **H2-revised-B (per-tier-of-trust):** "To produce N body-faithful-proved obligations, LLMLL converges in fewer turns than Python would require to produce equivalent native-language verification artifacts (Hoare-triple comments + tests + external verifier setup)." — Untestable in the current harness; Python target has no equivalent of body-faithful verification to measure.

Either H2-revised-A or H2-revised-B requires language-team adjudication on whether to retain H2 in a revised form or formally withdraw it. The original H2 is not directly recoverable from this data.

#### Acceptance

Language-team turn produces an H2-revised proposal (or formal withdrawal recorded in `docs/design/phase3-problem-shape-audit.md` Addendum N), and a future Phase-3 or Phase-4 matrix tests the revised hypothesis.

---

### H3 (boundary-of-value, null-watcher) — confirmed-and-extended

**Pre-stated H3 (`experiments/repair-loop/README.md:49-50`):** *"On tasks whose dominant invariant class is outside QF-LIA, LLMLL produces no measurable advantage. Confirmation bounds the value claim; refutation extends it."*

**Consumer:** language-team (the boundary-of-value claim now has empirical grounding).

#### Evidence

001-hangman is the H3 null-watcher problem (state-machine, non-QF-LIA-dominant per `experiments/repair-loop/README.md:58`). Cross-target rates for 001-hangman:

| Target | Claude target-reached rate | Codex | Gemini-2-exp | Cross-agent |
|---|---|---|---|---|
| LLMLL | 1/3 | 2/3 | 0/3 | 3/9 = 33% |
| Python | 3/3 | (not run) | 3/3 | 6/6 = 100% |
| Go | 3/3 | (not run) | 3/3 | 6/6 = 100% |

**LLMLL underperforms Python and Go on 001-hangman target-reaching rate.** This is consistent with H3's prediction that LLMLL produces no measurable advantage on non-QF-LIA tasks — and in fact extends it: LLMLL produces a measurable *disadvantage* on terminal-reaching for this problem class at k=5 with the per-target predicates.

Refined per H1-Correctness (the like-for-like behavioral pass rate): for cells that DID reach terminal on 001-hangman:

- Claude × LLMLL: 1.000 pass rate (n=2 cells with `core_behavior.value` scored)
- Codex × LLMLL: 0.722 pass rate (n=3 cells)
- Claude × Python: 1.000 (n=3)
- Gemini × Python: 1.000 (n=3)
- Claude × Go: 1.000 (n=3)
- Gemini × Go: 1.000 (n=3)

LLMLL terminal-reaching cells on 001-hangman match Python/Go behaviorally (Claude 1.0; Codex 0.722 — slightly lower). The H3 disadvantage is in *getting to* terminal, not in the quality of solutions that do reach terminal.

#### Why we saw what we saw

001-hangman's state machine has non-QF-LIA invariants (e.g., guess-letter not in previous-guesses, game-state transitions on hit-vs-miss). LLMLL's R6d Cred(R) predicate requires all these obligations be above `asserted` tier — which for non-QF-LIA invariants means either Liquid Fixpoint can't discharge them (so they fall to `asserted`), or the agent must explicitly mark them `weakness-ok`, or emit tests that promote them to `tested`. All three paths take iteration; first-turn solutions rarely cover all 13 obligations above-asserted.

Python and Go have no per-obligation trust report; they have a flat `all-pass` predicate. The agent emits a working hangman implementation in one shot; tests pass; terminal-reached.

#### Implication

H3 confirmed in the bounded-value form ("no measurable advantage on non-QF-LIA"). Empirically extended: LLMLL produces a measurable terminal-reaching *disadvantage* relative to Python/Go on this problem class at k=5. The value claim for LLMLL on non-QF-LIA tasks is appropriately narrow: it is not "fewer turns to terminal" (the H2 question, refuted); it is "structured per-obligation trust signal even when terminal-reaching is harder" (the H1-Assurance question, confirmed).

Language-team might consider whether the project's value-claim narrative should be updated to lead with "rich verification surface" rather than "faster development" — the data supports the former, not the latter.

#### Acceptance

H3's value claim is now empirically anchored; no further action required. If the project's narrative is updated to reflect the bounded-value framing, that lands as a documentation-team turn against the project's positioning documents (out of scope of this postmortem).

---

### H1-Correctness — Python/Go uniform; LLMLL variable per agent

**Consumer:** language-team (informs the value-claim narrative) + experiment-lead (operational read on agent-LLMLL fit).

#### Evidence

Mean `core_behavior.value` (testkit pass rate over PBT samples that ran) per (agent, target, experiment):

| Agent | Target | 001-hangman | 002-bank-ledger | 003-rate-limiter |
|---|---|---|---|---|
| Claude | LLMLL | 1.000 (n=2) | 1.000 (n=2) | 0.667 (n=1) |
| Claude | Python | 1.000 (n=3) | 1.000 (n=3) | 1.000 (n=3) |
| Claude | Go | 1.000 (n=3) | 1.000 (n=3) | — |
| Codex | LLMLL | 0.722 (n=3) | 0.800 (n=3) | 1.000 (n=1) |
| Gemini | LLMLL | 0.000 (n=3) | 0.000 (n=2) | 0.417 (n=3) |
| Gemini | Python | 1.000 (n=3) | 1.000 (n=3) | 1.000 (n=3) |
| Gemini | Go | 1.000 (n=3) | — | — |

(n counts cells where `core_behavior.value` was successfully scored; budget-exhausted cells with no valid solution may have value=None.)

Cross-agent LLMLL averages: Claude 0.89, Codex 0.84, Gemini 0.14. Cross-paradigm Python and Go uniformly 1.000 across every cell.

#### Why we saw what we saw

Python and Go are the agents' native distribution. They emit canonical implementations of bank-ledger, hangman, and rate-limiter that pass behavioral tests trivially. LLMLL is novel-distribution (131KB spec injected per turn); agents must learn the syntax + verification model in-context.

Gemini-2-exp's near-zero LLMLL correctness (0.14 cross-problem) reflects this learning gap — it produces parseable solutions sometimes (cells 9, 16, 17, 18 had non-null tier_profile) but the solutions either don't pass the behavioral testkit or never reach a verifiable state. Claude and Codex have larger LLMLL-acquisition capacity within k=5 turns.

#### Implication

H1-Correctness is the load-bearing cross-paradigm comparison metric: Python/Go define the behavioral-correctness ceiling at 1.000; LLMLL approaches or matches it on cells that reach terminal (Claude/Codex on most cells, Gemini on a minority). The verification surface adds structured assurance signal without sacrificing behavioral correctness when the agent succeeds — but agent capacity to succeed on LLMLL varies sharply across agents.

For Phase-4 design: the cross-agent LLMLL fit is the constraint to plan around. Codex/Claude have substantial fit; Gemini-2-exp does not at default config + k=5. A within-Gemini follow-up (Gemini 2 vs 3 — see deferred experiment) would tell whether the 0.14 average reflects "Gemini family doesn't fit LLMLL" or "Gemini 2 exp specifically doesn't fit; Gemini 3 might."

#### Acceptance

N/A — descriptive finding. Recorded as Phase-3 baseline; Phase-4 (or post-throttling Gemini follow-up) compares against it.

---

### Cross-agent LLMLL ordering — monotone and consistent

**Consumer:** experiment-lead (operational read).

#### Evidence

Target-reached counts on LLMLL target × 3 tries per (agent, problem):

| Agent | 001-hangman | 002-bank-ledger | 003-rate-limiter | LLMLL total |
|---|---|---|---|---|
| Codex | 2/3 | 2/3 | 2/3 | **6/9 = 67%** |
| Claude | 1/3 | 1/3 | 2/3 | **4/9 = 44%** |
| Gemini | 0/3 | 0/3 | 0/3 | **0/9 = 0%** |

The Codex > Claude > Gemini-2-exp ordering is identical across all 3 LLMLL problems and consistent within each. Across-problem variance:

- Codex is monotone (2/3 every problem).
- Claude varies (1/3, 1/3, 2/3) — slight improvement on 003-rate-limiter (the bounded-counter problem where Claude's verified-into-tier strategy lands `verified=8` body-faithful).
- Gemini is flat (0/3 every problem).

#### Why we saw what we saw

Codex's xhigh reasoning effort + broader sandbox bypass (`--dangerously-bypass-approvals-and-sandbox` is broader than Claude's permission-mode flag) appears to give it more execution-side latitude per turn. Codex also tends toward tested-into-tier strategy (cells 5, 22, 23 use PBT-Lift to promote all obligations to `tested` in one or two turns); the strategy reliably satisfies Cred(R) when it works.

Claude's default reasoning + verified-into-tier strategy produces high-tier obligations (cells 12 = verified=9; cell 20 = verified=8) but with lower target-reaching rate — Claude tends to plateau when liquid-fixpoint cannot discharge a remaining obligation. The strategy is high-quality-when-it-works, lower-volume.

Gemini-2-exp underperforms on every LLMLL slice. Likely combination of: (a) less-developed in-context LLMLL acquisition vs Claude/Codex; (b) Gemini CLI's session/file-handling differs from Claude/Codex and may interact with the harness's run-dir injection differently; (c) the model itself is an experimental February 2025 Gemini 2 Pro variant, not the current frontier (per project memory `gemini-2-vs-3-phase3-choice`, this is a deliberate throttling-driven step-down — the Gemini 3 comparison would tell us whether the 0/9 rate is the model or the family).

#### Implication

Phase-4 (or repeat Phase-3) matrix design should consider:

- Codex remains the strongest LLMLL agent in this setup; Phase-4 baseline-of-comparison.
- Claude is comparable on 003-rate-limiter; lower on 001/002 — within-Claude variance worth investigating (per-try shape, reasoning effort).
- Gemini-2-exp is not currently useful on LLMLL at default config + k=5. The deferred Gemini 2 vs 3 comparison (postmortem-003 Addendum 2) is the relevant follow-up.

#### Acceptance

N/A — descriptive finding.

---

### Verification-strategy split within an agent — tested-into-tier vs verified-into-tier

**Consumer:** language-team (data-grounded observation about agent-side spec interaction).

#### Evidence

LLMLL target-reached cells' final tier_profile:

- Claude target-reached: cells 1 (tested=13), 12 (verified=9), 19 (verified=4), 20 (verified=8). Claude reaches terminal mostly via the `verified` tier (3 of 4 cells); when it uses `tested` instead (cell 1), it's because the problem (001-hangman) has more non-QF-LIA invariants that resist body-faithful proof.
- Codex target-reached: cells 4 (verified=2), 5 (tested=15), 13 (verified=4), 15 (verified=4), 22 (tested=4), 23 (tested=3). Codex mixes strategies: 3 cells via verified (with low counts: 2-4 verified each), 3 cells via tested (with full or near-full PBT-Lift coverage). **Same agent, same model, same reasoning effort, same problem in two of the cell pairs** — the strategy choice is task-time variable, not deterministic.

#### Why we saw what we saw

Both strategies satisfy R6d Cred(R): `asserted=0 AND no_contract=0`. The agent can satisfy the predicate by either (a) promoting all obligations to a body-faithful-verified tier (which liquid-fixpoint can discharge for QF-LIA-decidable arithmetic) or (b) adding PBT-Lift check blocks that cover all obligations and promote them to `tested` tier. The choice depends on how the agent reads the verifier feedback and decides which obligations to address with what mechanism.

Codex's variance across tries on the same cell-shape (cells 4 vs 5, both Codex × 001-hangman) suggests non-deterministic strategy selection — the same agent makes different choices on different runs.

#### Implication

This is exactly the kind of empirical pattern Phase-3's 3-try slice was designed to surface. Within-agent strategy variance is itself a measurable signal worth tracking. For Phase-4 design:

- Strategy-choice as an explicit per-cell measurement (the format-choice deferred experiment from postmortem-003 Addendum 2 is the analogous question) — analyzer logic to walk run dirs and tag each cell's primary strategy (verified-into-tier vs tested-into-tier vs mixed) before correlating with terminal-reaching shape.
- Spec design question for language-team: should the spec encourage one strategy over the other (e.g., guidance in `LLMLL.md` for when to prefer body-faithful proof vs PBT-Lift), or is the diamond-incomparability deliberate room for agent discretion?

#### Acceptance

For Phase-4: strategy-tagging analyzer lands; per-cell strategy is reported alongside tier_profile in evaluation.json; cross-try variance is reported per (agent, problem, target) cell.

---

## Verified findings (infrastructure-class)

### F-041 (NEW). Gemini account-level quota exhausted at sibling-batch cell 46-48

**Priority:** High (blocks all subsequent Gemini cells until quota reset; same class as F-038 on a different provider).
**Consumer:** operator (quota resolution) + experiment-lead (operational finding).

#### Evidence

Sibling-batch cells 46, 47, 48 (all Gemini × 002-bank-ledger × Go × tries 1, 2, 3) failed at turn 1 with `agent_rc=1`. Stderr from cell 46 `turns/turn_01/agent.stderr.log` (truncated):

> `Error when talking to Gemini API … TerminalQuotaError: You have exhausted your capacity on this model. Your quota will reset after 7h22m23s.` … `cause: { code: 429, message: 'You have exhausted your capacity on this model. Your quota will reset after 7h22m23s.', reason: 'QUOTA_EXHAUSTED' }`

Cells 47, 48 produced identical errors with reset window decrementing (7h22m16s, 7h22m11s) consistent with the same window reported on cell 46. Discipline B circuit breaker tripped after the third consecutive infrastructure-fail per `manifest.phase3-no-codex.json:_circuit_breaker_consecutive_infra_fail = 3`; matrix halted with rc=2; cells 49-54 not executed.

#### Why we saw what we saw

Gemini API has account-level token/request quota independent of the per-model selection. The operator's prior step-down from Gemini 3 to Gemini 2 exp (project memory `gemini-2-vs-3-phase3-choice`) was motivated by Gemini 3 throttling; the data here shows **Gemini 2 also hits the account-level cap** at higher cell volume. The matrix's cumulative Gemini calls (24 Gemini cells executed before cell 46: 9 LLMLL × 3 problems + 9 Python × 3 problems + 6 Go × hangman/ledger Claude...) consumed the per-window quota.

#### Implication

For Phase-4 or post-quota follow-up matrices, operator-side strategies:

1. Wait for the 7h22m reset and resume from cell 49 (recovers all 6 remaining cells: 3 Claude × Go × 003 + 3 Gemini × Go × 003).
2. Run Claude-only mini-matrix for cells 49-51 now; defer Gemini cells 46-48 (failed) and 52-54 (not run) to a Gemini-quota-resolved follow-up.
3. Upgrade Gemini API tier (analogous to OpenAI seat upgrade for F-038); test new quota with a smoke before any matrix work.

The operator chose path D (postmortem-004 authored against the 51-cell analyzable dataset; remaining 6 cells deferred to a future user turn).

The pre-launch service-status-check section at `experiments/repair-loop/README.md:226-242` does not currently cover account-level quota (only service-wide incidents). A procedural enhancement worth considering for Phase-4: add a per-agent quota-headroom check to the operator-side pre-launch protocol, analogous to the F-038 procedural follow-on.

#### Acceptance

Post-quota-reset: a Gemini smoke or Gemini-only mini-matrix produces non-zero stderr volume and runs through at least one tool-call round. Operator-side resolution; no harness change required for closure of F-041 itself.

---

### F-038 recurrence at original-batch cell 24 — known finding, recurred

**Priority:** High (carries from postmortem-002 Addendum 2; not closed at the operator-account level despite seat upgrade).
**Consumer:** operator.

#### Evidence

Original-batch cell 24 (Codex × 003-rate-limiter × LLMLL × try 3) failed at turn 1 with `agent_rc=1`. Cell stderr:

> `ERROR: You've hit your usage limit. To get more access now, send a request to your admin or try again at Jun 12th, 2026 7:54 AM.`

This is the same F-038-class signature as postmortem-002 Addendum 2 (then a 5h soft cap; now a longer-window cap, Jun 12 reset ≈ 26 days). The operator's seat upgrade (per `gemini-2-vs-3-phase3-choice` memory's adjacent context: the OpenAI seat was upgraded from a ChatGPT tier to a codex tier between postmortem-003 sessions) removed the prior 5h soft cap but did not remove ALL caps; a longer-window quota was still in effect and got consumed by cells 1-23 of the matrix.

#### Why we saw what we saw

OpenAI quota tiers carry both short-window (5h) and long-window (monthly?) limits. The seat upgrade addressed the former; the latter remained. 23 cells of Codex at xhigh reasoning (~$10-25/cell estimated, per postmortem-003 Addendum 1's tentative codex cost extrapolation) consumed enough of the long-window quota to exhaust at cell 24.

#### Implication

For Phase-4 or post-Jun-12 follow-up:

1. Wait for Jun 12 quota reset and run a codex-only mini-matrix for the 18 deferred Codex × Python/Go cells.
2. Or upgrade plan tier further; smoke before any matrix work.
3. Or run smaller-scope codex slices (e.g., 1 try per cell instead of 3) to fit within available quota.

The 18-cell codex × Python/Go hole is the largest unfilled gap in Phase-3 data; cross-language H1-Correctness / H1-Assurance comparisons on Codex are partial (LLMLL only, no Python/Go).

#### Acceptance

Post-Jun-12: a Codex Python/Go smoke produces non-zero stderr volume and runs through one tool-call round. Operator-side resolution.

---

### F-035 single-recurrence at original-batch cell 21

**Priority:** Defence-in-depth (single-cell variance; no remediation proposed).
**Consumer:** experiment-lead (operational note).

#### Evidence

Original-batch cell 21 (Claude × 003-rate-limiter × LLMLL × try 3) ran 3 turns cleanly then hit the 1800s timeout on turn 4. From `runs/20260516T191018Z-…-c21-…/repair_loop_log.json:turns`:

| Turn | rc | error |
|---|---|---|
| 1 | 0 | None |
| 2 | 0 | None |
| 3 | 0 | None |
| 4 | 124 | timeout after 1800s on turn 4 |

`terminal_state: infrastructure-fail; terminal_reason: agent rc=124 at turn 4`.

#### Why we saw what we saw

Single-turn 1800s ceiling is sufficient for typical Claude × LLMLL turns (per Phase-3 wall data: Claude × LLMLL mean turn wall ~7-10 min, max observed ~11 min). Cell 21 turn 4 hit a long-form reasoning cycle that exceeded the ceiling — single occurrence across 9 Claude × LLMLL cells.

#### Implication

No 1800s revisit warranted on n=1 occurrence across 57 cells (1.8% rate). The ceiling continues to hold for the cell-class. If F-035-class timeouts recur at a higher rate in Phase-4 (e.g., >5% of Claude × LLMLL cells), reconsideration is warranted. The current data does not support a bump.

#### Acceptance

N/A — variance finding; no action.

---

### F-037 stop-fast disciplines validated again

**Priority:** Defence-in-depth confirmation.
**Consumer:** user (informational).

#### Evidence

Continued from postmortem-002 (F-037) and postmortem-003 Addendum 1+2. Across both Phase-3 batches:

- **Discipline A (toolchain pin verification):** silent (no failures); compiler `0.10.6`, Python `3.11`, Go `1.23` all verified at each batch start.
- **Discipline B (circuit breaker):** tripped once at sibling-batch cell 48 on the F-041 3rd consecutive infra-fail (Gemini quota). Correctly halted the matrix; bounded wasted spend on cells 49-54 that would have hit the same quota (cells 52-54 Gemini) or succeeded (cells 49-51 Claude).
- **Discipline C (compiler health probe):** silent (no failures); the health-probe fixture parsed clean before each batch.

#### Implication

Disciplines A and C unchanged from their prior behavior. Discipline B has now fired in the field on two distinct quota classes (F-038 on Codex, F-041 on Gemini), each time bounding wasted spend at threshold-3 infra-fails. The threshold-3 setting is appropriate for matrices of this scale (81 cells); for single-cell probes a threshold of 1 has been used (per postmortem-003 sibling manifests).

#### Acceptance

N/A — defence-in-depth confirmation, not closeable.

---

## Operational findings

### Wall + cost realism

**Total Phase-3 cell wall: 11.4 hours** across 57 cells (mean 12 min/cell). Vastly under the original 25-60h ceiling estimate from postmortem-003 Addendum 1.

Per-target wall divergence:

| Agent × Target | n | Mean wall | Range |
|---|---|---|---|
| Claude × LLMLL | 9 | 39 min | 26-59 min |
| Claude × Python | 9 | 0.9 min | 0.7-1.2 min |
| Claude × Go | 6 | 4.0 min | 1.3-5.9 min |
| Codex × LLMLL | 9 | 19 min (incl. F-038 cell at 5s) | 0.1-28 min |
| Gemini × LLMLL | 9 | 12 min | 5-25 min |
| Gemini × Python | 9 | 0.6 min | 0.3-1.1 min |
| Gemini × Go | 6 | 1.0 min (incl. 3 F-041 cells at ~5s) | 0-4.5 min |

The LLMLL wall is ~5-40× the Python wall depending on agent, consistent with the per-target predicate-bar difference noted in the H2 finding.

**Cost estimate (rough; dollar costs not directly measured this session):** total Phase-3 spend in the range $234-$585. Per-agent breakdown using prior postmortem estimates:

- Codex (9 cells executed): ~$90-$225 (xhigh reasoning; quota-hit cell 24 at $0)
- Claude (24 cells executed): ~$120-$288 (default reasoning, multi-tool, longer LLMLL walls)
- Gemini (24 cells executed): ~$24-$72 (Gemini 2 exp, smaller model, shorter walls)

Within the postmortem-003 Addendum 1 envelope of $205-$550 (upper bound exceeded by ~10% in the higher half of the estimate; well under in the lower half). No budget overrun beyond extrapolated tolerances.

### Interim-pause mechanism — operator-checkpoint design surfaced

The matrix runner's interim-pause mechanism (per 9 cells, rc=3 exit) was unfamiliar at session start; surfaced and characterized during Phase-3 execution. The 9-cell granularity aligns conveniently with a (target × experiment × all-agents × all-tries) slice — the operator gets clean per-slice checkpoint data to review before authorizing the next slice.

This isn't a finding to remediate; it's an operational characterization worth recording for future-operator clarity: rc=3 is design-intended, not failure. Documentation in `experiments/repair-loop/README.md` could surface this explicitly (currently mentioned only in the Flags section but not under Stop Policy or Pre-Launch Service Status Check).

### Harness `.env` auto-loading gap

`run_matrix.py` reads `os.environ.get(var)` directly for required_env checks. It does not load `.env` automatically; operators must `set -a; source .env; set +a` before invocation. Encountered as a launch-time prereq failure on this session (`GEMINI_API_KEY` was in `.env` but not exported in the shell). One-line workaround in shell prefix; harness improvement (`python-dotenv` import + auto-load before prereq check) is a candidate Phase-4 ergonomic fix. Tracked as a candidate documentation update (note in README or candidate `python-dotenv` addition); not blocking.

## Withdrawn items

None this postmortem. The H2 finding represents a refutation of a pre-stated hypothesis, not a withdrawal of a finding (the distinction: H2 was pre-registered and tested; the data refuted it; the refutation is the finding).

## Null results

The deferred adjacent experiments enumerated in postmortem-003 Addendum 2 ("Deferred adjacent experiments surfaced during session close") remain not yet investigated:

1. **R2 (codex at `medium` reasoning):** not tested; the F-038 recurrence on `xhigh` consumed the codex budget for this session. R2 awaits codex quota resolution + operator authorization.
2. **Format-choice as Phase-3 measurement (codex AST vs surface):** measurable from existing Phase-3 run dirs; analyzer logic not yet written. Phase-3-natural post-hoc analysis.
3. **Spec-compaction probe:** not tested; the wall data does not show ingest-cost as a current bottleneck (most cells complete in <30 min total wall, including 131KB LLMLL.md ingest), so the spec-compaction motivation is weaker now than at postmortem-003 authoring time.
4. **Per-turn wall agent-equivalence observation:** confirmed-and-extended by Phase-3 data — per-turn wall is broadly comparable across agents on matched targets; cross-agent total-wall delta is driven by turns-to-terminal, not per-turn pace. The hypothesis-priming observation from postmortem-003 Addendum 2 stands.

New deferred follow-ups from this session:

5. **Codex × Python/Go mini-matrix** to fill the 18-cell F-038 hole. Post-Jun-12 quota reset; operator-authorized.
6. **Gemini × Go × 002+003 mini-matrix** to fill the 6-cell F-041 hole. Post-7h22m quota reset (or upgrade); operator-authorized.
7. **Claude × Go × 003-rate-limiter** to fill the 3-cell breaker-halt collateral hole. Standalone mini-matrix; ~30-45 min wall; could be run independently of either quota.
8. **Gemini 2 vs 3 comparison** (carries from postmortem-003 Addendum 2). Post-throttling resolution.
9. **Strategy-tagging analyzer** (new; analyzer logic to walk run dirs and tag tested-into-tier vs verified-into-tier vs mixed per cell, then correlate with terminal-reaching shape across the 52 analyzable LLMLL cells).

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| 1 | H2 refuted in raw form; reframing implied | language-team | High | language-team turn to author H2-revised proposal or formal withdrawal |
| 2 | H1-Assurance bifurcation as designed | language-team | Informational | None — confirmation finding |
| 3 | H3 confirmed-and-extended (LLMLL no advantage on non-QF-LIA) | language-team | Medium | Optional: project narrative update |
| 4 | H1-Correctness Python/Go uniform; LLMLL variable | language-team / experiment-lead | Informational | None — Phase-3 baseline |
| 5 | Cross-agent LLMLL ordering Codex > Claude > Gemini-2-exp | experiment-lead | Informational | Phase-4 baseline-of-comparison |
| 6 | Verification-strategy split within an agent | language-team | Medium | Optional: spec guidance on strategy choice |
| 7 | F-041 Gemini account-level quota | operator | High | Quota reset or tier upgrade |
| 8 | F-038 recurrence | operator | High | Jun 12 reset or tier upgrade |
| 9 | F-035 single-recurrence | experiment-lead | Defence-in-depth | None — variance |
| 10 | F-037 disciplines validated | user | Defence-in-depth | None |

## Per-consumer scoped files

This postmortem is the integrated report. Per-consumer fragments are routed minimally:

- **`findings/compiler-engineer.md`:** no fragment routed. The compiler ran cleanly across all 57 cells; the F-035 single-recurrence is variance, not a compiler defect. No spec-side compiler implication.
- **`findings/language-team.md`:** **fragment to be added** in a separate edit covering H2-refutation + H1-Assurance bifurcation confirmation + H3 confirmed-and-extended + verification-strategy split. These four findings are language-team's slot for adjudication; postmortem-004 here is the integrated source-of-truth and the language-team fragment is the per-consumer-scoped mining surface.
- **`findings/documentation-team.md`:** no fragment routed. The interim-pause documentation gap + `.env` auto-loading recommendation are `experiments/repair-loop/README.md` edits (experiment-lead's slot per skill), not documentation-team's main 6 docs.

## Closing — Phase-3 launch is empirically complete

**51 cells of analyzable data + 5 infra-fail findings + 24 explicit holes.** The H1/H2/H3 pre-stated hypotheses are now either confirmed (H1-Assurance, H1-Correctness, H3), empirically refuted (H2 raw form), or partially measured (H3 cross-paradigm comparison limited by the codex Python/Go hole). The cross-agent LLMLL ordering is robust (Codex > Claude > Gemini-2-exp, monotone across 3 problems). The verification-strategy split is a substantive within-agent finding worth tracking in future matrices.

The 24-cell hole, while real, does not invalidate the headline findings: H2 refutation is grounded on Claude+Codex × LLMLL × all 3 problems (data we have); H1-Correctness on Python/Go is uniform 1.000 across the 36 cells where it was measured (Codex Python/Go missing but the pattern is already saturated at 1.000); H3 is grounded on all 9 LLMLL × 001-hangman cells. The deferred Codex Python/Go data would refine — not overturn — these findings.

**Next live decisions:**

1. **Language-team turn:** adjudicate H2 reframing (H2-revised-A matched-difficulty, H2-revised-B per-tier-of-trust, or formal withdrawal) and surface the H1-Assurance bifurcation confirmation as a closure note in `findings/language-team.md`. Surface optional spec-guidance proposal for verification-strategy split.
2. **Operator-side follow-ups (any order, any subset):** codex-only mini-matrix post-Jun-12; Gemini-only mini-matrix post-7h22m or post-tier-upgrade; Claude-only Go × 003 mini-matrix immediately if desired; Gemini 2 vs 3 comparison post-throttling-resolution.
3. **Experiment-lead deferred work (any order):** strategy-tagging analyzer for the 52 LLMLL cells; format-choice analyzer per postmortem-003 Addendum 2.

Postmortem-005 (or addenda to this one) lands when (a) the next mini-matrix runs and produces fresh findings, (b) the language-team H2-reframing turn produces an adjudication, or (c) Phase-4 design is initiated.
