# Postmortem 001 — Apparatus Validation

> **Phase:** 1 (apparatus validation, golden cell)
> **Date:** 2026-05-11
> **Author role:** experiment-lead
> **Status:** apparatus passed; Phase 2 unblocked pending user approval

## Headline finding

The repair-loop orchestrator closes the loop cleanly across `k=3` turns on a
golden-cell run using the deterministic stub agent (n=1 cell, 3 turns, 5
verifier commands per turn = 15 verifier invocations captured). All 10
apparatus-validation checks pass. Per-turn verifier output is captured
structurally and re-injected into the next turn's agent context; the
re-injection is empirically proven by the stub recording the prior turn's
context filename in its own stdout. The apparatus is ready for Phase 2 (real
agent on a known-tractable cell to exercise the terminal-target accept path).

## Sample composition

- **Cells:** 1 (n=1)
- **Agent:** stub (deterministic; not a real model)
- **Experiment:** `002-bank-ledger` (problem text from `problems/002-bank-ledger.md`)
- **Target:** `llmll`
- **Tries:** 1
- **Repair budget *k*:** 3
- **Turns executed:** 3 (full budget; terminal target not reached, by design — stub solution is intentionally invalid)
- **Compiler version pin:** `llmll 0.10.2` (captured automatically into `repair_loop_log.json:compiler_version_pin`)
- **Harness commit:** working tree post-`bb5b07e`; orchestrator and evaluator scaffolded this turn, not yet committed
- **Run directory:** `experiments/repair-loop/runs/20260511T132025Z-golden-cell-e002-bank-ledger-llmll/`
- **Terminal state:** `budget-exhausted` (expected; stub never produces a verifying solution)

## Verified findings

### F-001. Loop closes cleanly across the full repair budget

**Priority:** N/A (Phase 1 acceptance criterion satisfied)
**Consumer:** user

#### Evidence

`experiments/repair-loop/runs/20260511T132025Z-golden-cell-e002-bank-ledger-llmll/evaluation.json:apparatus.checks` records 10 of 10 apparatus checks passing. Of those, six are per-turn (artefact existence + verifier-result non-emptiness for each of turns 01/02/03), two are loop-level (terminal-state legal, ≥1 turn), and two are stub-specific (re-injection — see F-002).

#### Why we saw what we saw

`scripts/run_repair_loop.py:_run_one_turn` invokes the agent, runs the verifier chain via `_run_verifier_chain`, writes both `turns/turn_NN/verifier.json` and `context/turn_NN_verifier.json`, and evaluates the terminal predicate. The loop in `main` iterates up to `k` times, early-exits on terminal match or infrastructure failure, and sets `terminal_state` exhaustively (`target-reached` / `infrastructure-fail` / `budget-exhausted`). All three branches are reachable in code; this run exercised the `budget-exhausted` branch.

#### Implication

Phase 1 acceptance criterion is met: the apparatus is ready to be exercised on a real agent. No language-team or compiler-engineer hand-off is implied by this finding.

#### Acceptance

A second stub-agent run with `k=5` and the same configuration should also produce 10/10 apparatus checks passing and `terminal_state: budget-exhausted` with 5 turns. (Not run; not required for closing F-001.)

---

### F-002. Verifier-output re-injection is empirically proven

**Priority:** N/A (load-bearing design property; validation requirement of Phase 1)
**Consumer:** user

#### Evidence

`turns/turn_02/agent.stdout.log` line 2: `prior contexts: ['turn_01_verifier.json']`. `turns/turn_03/agent.stdout.log` analogously records seeing `turn_02_verifier.json`. The apparatus checks `stub-saw-prior-context-02` and `stub-saw-prior-context-03` both pass in `evaluation.json:apparatus.checks[6-7]`.

#### Why we saw what we saw

The stub at `scripts/run_repair_loop.py:_invoke_stub_agent` reads `context/turn_*_verifier.json` from the run directory at the start of each turn and writes the filenames into its own stdout. The orchestrator writes the prior turn's verifier output to `context/turn_NN_verifier.json` *before* invoking the agent for turn N+1, so the stub's read of the context directory between turns shows monotonic growth.

#### Implication

The orchestrator's re-injection seam — write context file → invoke agent → agent reads context file — is sound for stub. For a *real* agent (Claude / Gemini / Codex), the same seam will surface the verifier output to the agent through its file-reading tool. No additional plumbing is required between Phase 1 and Phase 2.

#### Acceptance

Closed by this run. Re-validates on every subsequent stub run as a regression sentinel.

---

### F-003. Verifier output is structurally usable for re-injection

**Priority:** Defence-in-depth
**Consumer:** user (forward-looking for Phase 2/3)

#### Evidence

Per-turn `verifier.json` captures all five LLMLL verifier commands (`check`, `check-strict`, `holes`, `test`, `verify`) with their `exit_code`, full `stdout`, full `stderr`, and parsed JSON where the command emits JSON. Truncation cap is 16k chars per channel (`_truncate` in `run_repair_loop.py`); on parse-error outputs the cap did not engage (largest captured stdout: ~1.1k chars).

Sample captured from turn 1, `check` command:

```
(error :phase parse :file "solution.llmll" :line 1 :col 1 :message "|
1 | ; stub agent — turn 1
  | ^
unexpected ';'
exp..."
```

JSON channels (`holes`, `verify`) produce parseable JSON even on rejection (e.g., `{"code":"E001","col":1,"file":"solution.llmll",...}`).

#### Why we saw what we saw

`llmll`'s diagnostic surface already emits structured S-expression or JSON on every command path, including the parse-error path. The orchestrator preserves both stdout and `parsed_json` so the next turn's agent context contains a fully machine-readable payload, not just truncated text.

#### Implication

Verifier-output ergonomics for repair-loop consumption appear adequate at the parse-error layer. **Open question for Phase 2/3:** whether the success-path payloads (specifically the trust report from `llmll verify`) are equally clean to consume; F-004 below names this as a Phase 2 prerequisite.

#### Acceptance

Phase 2 turns produce parseable trust reports that the orchestrator can read via `_count_bad_trust_tiers` without falling through to the schema-tolerant default.

---

### F-004. Terminal-target accept-path is unexercised by Phase 1

**Priority:** Medium (Phase 2 prerequisite)
**Consumer:** experiment-lead (self, Phase 2 design)

#### Evidence

`run_repair_loop.py:_evaluate_terminal_target` and `_count_bad_trust_tiers` contain the success-path predicate logic. In the Phase 1 stub run, every turn's `check` command fails at parse phase (`exit_code=1`), so the predicate short-circuits at `first_fail is not None` and the trust-report traversal never executes. The accept-branch (`return True, "all expected contracts verified or asserted"`) has zero coverage in Phase 1 runs.

#### Why we saw what we saw

The stub is engineered to produce an invalid solution, so the verifier chain fails immediately. The accept-branch of the predicate cannot be reached without a syntactically-valid LLMLL solution. This is by design for Phase 1 (we are testing the loop, not the predicate).

#### Implication

Phase 2 must include at least one cell where a real (or carefully crafted near-real) solution intentionally reaches `terminal_state: target-reached`, so the trust-tier traversal logic is empirically validated before Phase 3 commits to a full 81-cell matrix. Until F-004 is closed, the terminal-target predicate is *plausibly* correct but not *empirically* correct.

#### Acceptance

A Phase 2 cell produces `terminal_state: target-reached` with `terminal_reason: "all expected contracts verified or asserted"`. The `_count_bad_trust_tiers` traversal executes and returns 0.

---

### F-005. Compiler version pin is captured per-run automatically

**Priority:** N/A (skill-contract requirement satisfied)
**Consumer:** user

#### Evidence

`repair_loop_log.json:compiler_version_pin = {"version": "0.10.2"}`. Captured by `_capture_compiler_version` running `llmll version --json` (per `targets/llmll.json:version_pin_command`) at the start of the orchestrator run.

#### Implication

Reproducibility constraint satisfied without manual pin discipline. Future runs against later compiler versions will record the pin automatically; cross-run comparisons can filter on it.

## Withdrawn items

None. This is the first run; no prior claims to verify against.

## Null results

The run's `terminal_state: budget-exhausted` is itself an *expected null* on the convergence axis: the stub agent is engineered to not converge. This is not a failure mode of the apparatus or the language. It is documented here so future readers do not misread `budget-exhausted` as evidence against H1/H2/H3 — those hypotheses are evaluated only under Phase 3, and only against real agents.

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| F-001 | Loop closes cleanly | user | N/A (closed) | - |
| F-002 | Re-injection empirically proven | user | N/A (closed) | - |
| F-003 | Verifier output structurally usable | user | Defence-in-depth | tracked into Phase 2 |
| F-004 | Accept-path unexercised | experiment-lead | Medium | resolved by Phase 2 calibration cell (1 cell) |
| F-005 | Version pin captured automatically | user | N/A (closed) | - |

## Per-consumer scoped files

None written for this run. Phase 1 findings are integrated only. Per-consumer scoped files (`findings/compiler-team.md`, `findings/language-team.md`, `findings/documentation-team.md`) will be authored as Phase 2/3 surface findings against those consumers.

## Phase 2 readiness

Phase 1 satisfies its stated acceptance criterion. Phase 2 (calibration) prerequisites:

1. **F-004 resolution.** Phase 2 must include at least one cell where the terminal target is reached. Recommended: a 1-cell calibration run with `claude-opus-4-7` on `002-bank-ledger × llmll × k=5 × 1 try`, deliberately targeting a verifying solution.
2. **Python and Go target adapters.** Phase 2's calibration matrix spans 3 languages. The `llmll` target adapter is built; `python` and `go` adapters need to be authored. Approx 30-60 min per adapter following the shape of `targets/llmll.json`. (Original plan named Rust as the second control; switched to Go per Addendum 3 below.)
3. **Test kits for `002-bank-ledger` per language.** Empty `testkits/002-bank-ledger/{llmll,python,go}/` directories exist; per-language black-box tests need authoring against the spec in `problems/002-bank-ledger.md`.
4. **Phase 2 user approval.** Per my skill contract, separate approval from Phase 1.

Phase 2 estimated cost (indicative, pending separate approval): ≤ 45 agent invocations, ≤ $50 API spend, ≤ 6 hours wall-clock serial.

---

## Addendum — k=1 Real-Agent Cell (kink-finding)

> **Added:** 2026-05-11
> **Purpose:** Exercise the real-agent code path through the orchestrator before committing to Phase 2. The stub run validated the loop but, by construction, never produced a verifying solution; the accept-path of the terminal-target predicate was untested (F-004).

### Sample composition

- **Cell:** 1 (n=1)
- **Agent:** real-mode shim that copies `examples/banking_ledger/banking.llmll` into the run directory as `solution.llmll` (the in-tree compositional-verification example becomes the agent's emission)
- **Experiment:** `002-bank-ledger`
- **Target:** `llmll`
- **Repair budget *k*:** 1 (smallest exercisable budget; pre-Phase-2 sanity check)
- **Compiler version pin:** `0.10.2` (auto-captured)
- **Manifest:** `experiments/repair-loop/manifest.kink-test.json` (ad-hoc; preserved for future kink runs)
- **Run directories:** `runs/20260511T132932Z-k1-kink-e002-bank-ledger-llmll/` (pre-fix), `runs/20260511T133355Z-k1-kink-fixed-e002-bank-ledger-llmll/` (post-fix)

### Kinks found and fixed

#### F-006. No CLI override for `repair_budget_k`

**Priority:** Low (ergonomic)
**Consumer:** experiment-lead (self, future enhancement)

#### Evidence

`scripts/run_repair_loop.py:main` reads `k` from `manifest.get("repair_budget_k", 3)` only; no `--k` argparse override. Surfaced when trying to run the kink test with `k=1` against the existing `manifest.example.json` which pins `k=3`. Workaround: created `manifest.kink-test.json` with `k=1`.

#### Implication

For Phase 2/3 matrix runs the manifest is canonical, so this kink does not block. For ad-hoc one-off exercises (small calibration probes, recovery debugging) a `--k` override would prevent the manifest-proliferation pattern. Defer until Phase 2 design pass.

#### Acceptance

`scripts/run_repair_loop.py` gains a `--k` CLI flag that overrides `manifest.repair_budget_k`. Not fixed in this addendum.

---

#### F-007. `verify` argv missing top-level `--json` flag

**Priority:** High (blocker for terminal-target predicate accuracy)
**Consumer:** experiment-lead (fixed in this addendum)

#### Evidence

Pre-fix run: `runs/20260511T132932Z-k1-kink-.../context/turn_01_verifier.json:verifier_results[verify]` shows `exit_code=0` but `parsed_json=null` and `stdout` begins with `"Trust Report\n──────...\n  clamp-withdraw:\n    pre:  asserted  |  post: asserted\n..."` — human-readable text, not JSON.

`llmll verify --help` clarifies: `--trust-report` (subcommand flag) prints a human-readable summary; the structured JSON variant requires the top-level `--json` flag (per the existing `holes` invocation pattern in `targets/llmll.json`).

#### Why we saw what we saw

The original `targets/llmll.json` `verify` argv read `["llmll", "verify", "{solution}", "--trust-report", ...]` — the top-level `--json` flag was omitted. Stub runs masked the defect because every command failed at parse phase; the orchestrator short-circuited the predicate at `first_fail is not None` before reaching the trust-report traversal.

#### Fix applied (no commit)

`targets/llmll.json` `verify` argv updated to `["llmll", "--json", "verify", "{solution}", "--trust-report", "--weakness-check", "--spec-coverage"]`. Note added in the adapter explaining the flag position.

#### Acceptance

Post-fix run (`runs/20260511T133355Z-k1-kink-fixed-...`) shows verify's `parsed_json` is now a populated dict; predicate's JSON-parse fallthrough no longer engages. Closed.

---

#### F-008. `_count_bad_trust_tiers` traversed wrong schema

**Priority:** High (blocker; coupled to F-007)
**Consumer:** experiment-lead (fixed in this addendum)

#### Evidence

Pre-fix predicate logic looked for `parsed.get("trust_report")` and per-entry `tier` field. The actual JSON schema emitted by `llmll --json verify --trust-report` is:

```json
{
  "entries": [
    {"name": "safe-subtract",
     "effective_level": "asserted",
     "pre_level": "asserted",
     "post_level": "verified (liquid-fixpoint)",
     "dependencies": [...], "drifts": []},
    ...
  ],
  "summary": {"verified": 0, "contract_checked": 0, "tested": 0,
              "asserted": 6, "no_contract": 0, "drifts": 0},
  "suppressions": []
}
```

Top-level key is `entries`, per-entry level field is `effective_level`. The post-fix run captures this schema verbatim into `context/turn_01_verifier.json:verifier_results[verify].parsed_json`.

#### Why we saw what we saw

Wrote `_count_bad_trust_tiers` against a guessed schema, did not verify against the live compiler output before stub validation. Stub runs masked the defect (predicate never reached the traversal). The k=1 real-agent run is the smallest empirical instrument that could have surfaced this. Validates the experiment-lead skill's "read the code to verify the spec" discipline applied to harness adapters as well.

#### Fix applied (no commit)

`scripts/run_repair_loop.py:_count_bad_trust_tiers` updated to look up `entries` (with fallback to legacy keys for tolerance), per-entry `effective_level` (with fallback to legacy keys), and added `_normalize_level` to strip parenthetical engine tags (`"verified (liquid-fixpoint)"` → `"verified"`). The accepted-level set expanded to `{verified, proved, asserted, contract-checked, contract_checked, checked, tested}`.

#### Acceptance

Post-fix run produces `terminal_state: target-reached`, `terminal_reason: "terminal predicate matched at turn 1"`. The summary block's `asserted: 6, no_contract: 0` tallies match `_count_bad_trust_tiers` returning 0. Closed.

---

### F-004 status update — **CLOSED**

Per the original F-004 acceptance criterion ("A Phase-2 cell produces `terminal_state: target-reached` with `terminal_reason: 'all expected contracts verified or asserted'`. The `_count_bad_trust_tiers` traversal executes and returns 0."): satisfied by the post-fix k=1 run (`runs/20260511T133355Z-k1-kink-fixed-e002-bank-ledger-llmll/evaluation.json`). The predicate's accept-path is empirically validated. F-004 closes.

### Cross-cutting meta-finding — **stub validation is necessary but not sufficient**

F-007 and F-008 were both schema-coupling defects that the stub run could not have surfaced, because stub solutions never advance past the parse-failure short-circuit. The k=1 real-agent cell — at a cost of zero API spend (because the "agent" was a `cp` shim against an in-tree example) — found both. This pattern argues that **every Phase-1 harness ramp-up should include at least one real-agent cell against a known-verifying solution** before promoting to a paid matrix. Phase 2's calibration step should embed this discipline as a structural prerequisite, not a one-off practice. Recorded as guidance, not a finding requiring action.

### Updated priority matrix (post-addendum)

| # | Finding | Consumer | Priority | Effort estimate | Status |
|---|---|---|---|---|---|
| F-001 | Loop closes cleanly | user | N/A | - | Closed |
| F-002 | Re-injection empirically proven | user | N/A | - | Closed |
| F-003 | Verifier output structurally usable | user | Defence-in-depth | tracked | Open (reinforced by addendum) |
| F-004 | Accept-path unexercised | experiment-lead | Medium | - | **Closed by addendum** |
| F-005 | Version pin captured automatically | user | N/A | - | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | 15 min | Open (deferred) |
| F-007 | `verify` missing `--json` flag | experiment-lead | High | (fixed) | Closed by addendum |
| F-008 | Trust-report schema mismatch | experiment-lead | High | (fixed) | Closed by addendum |

### Phase 2 readiness (revised)

The original Phase 2 readiness list is unchanged with one addition: F-004 now closes, so the predicate's accept-path is no longer a Phase-2 prerequisite to validate — it is empirically established. The remaining Phase-2 prerequisites (Python/Go target adapters, per-language test kits, user approval; see Addendum 3 for the Rust→Go switch rationale) are unchanged.

---

## Addendum 2 — k=1 Real-Agent Cell, JSON-AST Form (F-009)

> **Added:** 2026-05-11
> **Purpose:** Close F-009 below. The first k=1 real-agent cell ran against `solution.llmll` (S-expression form, priority-2 in the solution-file lookup). The JSON-AST form (priority-1, the AI-canonical schema-constrained variant — `docs/llmll-ast.schema.json` is shipped into every minimal-agent run for this reason) was unexercised. F-009 records the gap; this addendum closes it.

### Sample composition

- **Cell:** 1 (n=1)
- **Agent:** real-mode shim that copies `examples/withdraw-demo/withdraw.ast.json` into the run directory as `solution.ast.json`. The `withdraw-demo/` directory ships both `.llmll` and `.ast.json` forms, so the JSON-AST is verifying-by-construction.
- **Experiment:** `002-bank-ledger`
- **Target:** `llmll`
- **Repair budget *k*:** 1
- **Run directory:** `runs/20260511T134926Z-k1-kink-ast-e002-bank-ledger-llmll/`
- **Terminal state:** `target-reached`

### F-009. JSON-AST solution-file path unexercised by Phase-1 apparatus validation

**Priority:** High (closed by this addendum, but high-class while open — same class as F-007/F-008)
**Consumer:** experiment-lead (closed in this addendum)

#### Evidence

The first kink test (Addendum 1) used `cp examples/banking_ledger/banking.llmll solution.llmll`. The orchestrator's `_find_solution` walks `expected_files_priority = ["solution.ast.json", "solution.llmll"]` from `targets/llmll.json` and selected priority-2 because priority-1 did not exist. Every verifier command across that run received `solution.llmll` as `{solution}`. The priority-1 branch of `_find_solution` returned the first match without ever being exercised through verifier-command construction or `_evaluate_terminal_target` on JSON-AST output.

Confirmed empirically in the post-fix run's `context/turn_01_verifier.json`: every `argv` ends with `solution.llmll`, none with `solution.ast.json`.

#### Why we saw what we saw

I chose `examples/banking_ledger/` for the shim because it was the in-tree compositional-verification example most aligned with the `002-bank-ledger` problem. That directory ships only `.llmll`; I did not engineer the shim to materialize a `.ast.json` form (e.g., via `llmll build --emit json-ast` from the source). The `.ast.json` path through the orchestrator was simply not exercised — same failure mode in shape as the F-004 stub gap, one level lower.

#### Fix applied (no compiler/orchestrator change)

Re-ran the kink test against `examples/withdraw-demo/withdraw.ast.json`, which ships pre-built JSON-AST. Run directory: `runs/20260511T134926Z-k1-kink-ast-e002-bank-ledger-llmll/`. All five verifier commands resolved `{solution}` to `solution.ast.json` (confirmed in `context/turn_01_verifier.json:verifier_results[*].argv`). All five exited rc=0. Terminal predicate matched. Apparatus status: passed.

#### Acceptance

Closed. Both solution-file forms (`.llmll` priority-2, `.ast.json` priority-1) are now empirically validated end-to-end through the orchestrator. Predicate logic is form-agnostic — `_count_bad_trust_tiers` operates on `verify`'s structured JSON output regardless of which source form produced it.

### Cross-cutting meta-finding — **canonical-form-first kink discipline**

Restated as guidance, parallel to Addendum 1's stub-validation-is-not-sufficient finding: **every Phase-1 harness ramp-up should additionally include at least one real-agent cell against the priority-1 (canonical) solution form**, not only the fallback form. JSON-AST is the AI-canonical form for LLMLL; `docs/llmll-ast.schema.json` is shipped into every minimal-agent run for this reason. A kink test that exercises only the fallback form will miss schema-coupling defects specific to the JSON-AST path, the same way stub runs miss success-path predicate defects. For Phase 2 calibration, the prerequisite list expands to include this discipline.

### Updated priority matrix (post-addendum-2)

| # | Finding | Consumer | Priority | Effort estimate | Status |
|---|---|---|---|---|---|
| F-001 | Loop closes cleanly | user | N/A | - | Closed |
| F-002 | Re-injection empirically proven | user | N/A | - | Closed |
| F-003 | Verifier output structurally usable | user | Defence-in-depth | tracked | Open |
| F-004 | Accept-path unexercised | experiment-lead | Medium | - | Closed by Addendum 1 |
| F-005 | Version pin captured automatically | user | N/A | - | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | 15 min | Open (deferred) |
| F-007 | `verify` missing `--json` flag | experiment-lead | High | (fixed) | Closed by Addendum 1 |
| F-008 | Trust-report schema mismatch | experiment-lead | High | (fixed) | Closed by Addendum 1 |
| F-009 | JSON-AST path unexercised | experiment-lead | High | (validated via shim swap) | **Closed by Addendum 2** |

### Phase 2 readiness (re-revised)

The Phase 2 prerequisite list is unchanged except that the meta-finding above is now an explicit prerequisite: Phase-2 calibration must include both fallback-form and canonical-form kink cells before paid agent matrices. Other prerequisites (Python/Go target adapters, per-language test kits, user approval; see Addendum 3 for the Rust→Go switch rationale) are unchanged.

---

## Addendum 3 — Control-arm refinement: Python + Go (not Python + Rust)

> **Added:** 2026-05-11
> **Origin:** User question, this session: *"Why Rust vs. Go?"* My original Run Plan named Rust as the second non-LLMLL control without justifying it against Go. The Run Plan also deviated silently from `docs/design/language-comparison-experiments.md:594-602` (the *Recommended First Milestone* which lists `python`, `go`, `typescript` — Rust does not appear). This addendum records the deviation, surfaces the tradeoff, and reverts to the design-doc-aligned choice.

### Decision

Phase 2 and Phase 3 controls switch from **Python + Rust** to **Python + Go**. Rust moves to a deferred Phase 4 as a stretch ceiling test, contingent on Phase 3 results showing Go is beaten on the assurance axis.

### Rationale

Three confounder reasons favor Go for a first paid run, against the one sharp-test reason that favored Rust:

1. **Agent friction is lower with Go.** Cross-language LLM-agent benchmarks (HumanEval-X, MultiPL-E) consistently report Rust as the highest agent-failure-rate target — the borrow checker traps lifetime-incorrect emissions that are otherwise logically correct. That noise blurs the H1/H2 signal the experiment is designed to isolate ("does the verification surface help?" — not "is the language easy to write?"). Go's static type surface admits cleaner agent output, which makes the LLMLL-vs-control delta more interpretable.
2. **Toolchain reliability favors Go.** `go build` and `go test` are deterministic and fast. Cargo can fail opaquely (network, lockfile drift, target installation). The design doc's "report toolchain failures distinctly" discipline (`docs/design/language-comparison-experiments.md:241`) is satisfiable with either, but Go has materially fewer excluded `toolchain-fail` cells in practice.
3. **Wall-clock and cost favor Go.** Rust compile times across an 81-cell Phase-3 matrix add real elapsed time and billable tool-time. Go compiles sub-second. The Phase-3 wall-clock estimate I quoted earlier (~10 days serial) is dominated by Rust compile latency; switching to Go shaves a non-trivial fraction.

Against these, the case for Rust was: it's the harshest assurance baseline among the design-doc's four candidates. H1 ("LLMLL terminal assurance > controls") is a *strong* test if LLMLL beats Rust. That sharpness is real but premature for Phase 3.

### Sequencing

The correct empirical hygiene is **baseline-then-ceiling**, not both simultaneously. Phase 3 establishes whether LLMLL beats a typical static-typed control (Go) — the floor claim. If yes, Phase 4 tests whether LLMLL beats a strong-typed control (Rust) — the ceiling claim. Running both controls in Phase 3 conflates two distinct hypothesis tests and produces results that cannot be unambiguously attributed.

### Affected sections of this postmortem (already updated)

- *Phase 2 readiness (initial)*: `python` and `rust` adapter prerequisite → `python` and `go`.
- *Phase 2 readiness (revised)*: same.
- *Phase 2 readiness (re-revised)*: same.
- *testkits/002-bank-ledger/{...}/* directory list: `{llmll,python,rust}` → `{llmll,python,go}`.

### Affected sections of `experiments/repair-loop/README.md` (already updated)

- *Phases* table: added Phase 4 row for the deferred Rust stretch baseline; Phase 1 status moved to *Closed*; Phase 2/3 sample line names the languages explicitly.
- *Hypotheses* §H1: "Python or Rust agents" → "Python or Go agents"; parenthetical cross-reference to this addendum added.

### No empirical action this turn

This is a design-time decision recorded post-hoc; no run was launched. The Phase-1 apparatus validation results are unaffected because the apparatus is target-adapter-agnostic at the orchestrator and evaluator layer. The change manifests only in Phase 2/3 prerequisite text and (in the future) in which adapter files get authored.

---

## Addendum 4 — Phase-1.5: Go target adapter built and validated; Python toolchain blocked

> **Added:** 2026-05-11
> **Purpose:** Build and validate the second control-arm target adapter (Go, per Addendum 3). Author per-target adapter scaffolding, exercise it through the orchestrator with a shim agent, and surface any schema-coupling defects — the F-007/F-008/F-009 equivalent work for Go. Also surfaces the Python toolchain situation for user direction.

### Sample composition (Go arm)

- **Cell:** 1 (n=1)
- **Agent:** real-mode shim that copies `testkits/002-bank-ledger/go/solution.go` into the run directory as `solution.go`. Stub is a minimal but correct Go bank-ledger implementation; not the Phase-2/3 reference solution (agents will write their own).
- **Experiment:** `002-bank-ledger`
- **Target:** `go`
- **Repair budget *k*:** 1
- **Toolchain pin:** `go version go1.23.0 darwin/amd64` (captured as `raw` string; `go version` does not emit JSON, so `_capture_compiler_version` stored it under the `raw` fallback)
- **Run directory:** `runs/20260511T151119Z-k1-go-kink-e002-bank-ledger-go/`
- **Terminal state:** `target-reached` on turn 1; predicate kind `all-pass` matched after `go vet` and `go build` both exited 0.

### F-010. Go target adapter built and end-to-end validated

**Priority:** N/A (Phase-1.5 acceptance criterion satisfied for Go)
**Consumer:** experiment-lead (closed by this addendum)

#### Evidence

`targets/go.json` authored with `expected_files_priority: ["solution.go"]`, verifier commands `go vet {solution}` and `go build -o /dev/null {solution}`, and `terminal_target_predicates.all-verifier-commands-pass`. `testkits/002-bank-ledger/go/solution.go` contains a minimal working stub (94 lines). The orchestrator ran both verifier commands successfully (`runs/20260511T151119Z-.../context/turn_01_verifier.json`), captured the toolchain version, and the predicate matched. All 4 apparatus checks pass in `evaluation.json:apparatus.checks`.

#### Implication

The cross-language methodology validates: the orchestrator, evaluator, and predicate-dispatch logic are target-adapter-agnostic when the adapter declares the right schema. No code changes were required to the orchestrator's core loop for the Go target beyond the dispatch refactor (F-012 below).

### F-011. Python toolchain not installed; adapter blocked

**Priority:** High (Phase-2 calibration blocker)
**Consumer:** user (routing decision required)

#### Evidence

Toolchain probe at the start of Phase 1.5: `which pyright` → not found, `which pytest` → not found, `python3 --version` → `Python 3.9.6` (system Python on macOS; the Run Plan quoted `3.11`). The Python adapter as originally scoped — `pyright solution.py` for type-check, `pytest` for tests — cannot be authored without installing the toolchain, and the Python version differs from the Run Plan's assumption.

#### Why we saw what we saw

I scoped the Python adapter against my Run Plan's assumption without first probing the environment. The toolchain reality (pyright + pytest absent, Python 3.9.6 rather than 3.11) is a real Phase-2 prerequisite gap that the user routes.

#### Implication

Four routing options the user must pick from before the Python adapter can be authored:

| Option | What changes | Cost | Trade-off |
|---|---|---|---|
| **(A) Install pyright + pytest, upgrade to 3.11+** | System install; matches Run Plan | One-time setup; ~5 min | Cleanest; pyright is the strongest Python type-check signal |
| **(B) Use mypy + pytest** | Substitute mypy for pyright; install both | One-time setup; ~5 min | mypy is weaker on inference than pyright but still substantial |
| **(C) Use built-in Python tooling only** | `python3 -m py_compile` (syntax check only) + `python3 -m unittest` | None (built-in) | Much weaker assurance signal; pyright provides type checking that py_compile does not |
| **(D) Defer the Python adapter** | Phase 2 calibration runs Go-only as control | None | Loses Python (the most common AI-agent baseline) from Phase 2/3; defeats the design-doc-aligned first-milestone choice |

My recommendation: (A) if the user is comfortable installing toolchain locally (pip is the right channel for both pyright and pytest, though pyright also has an npm distribution). (B) is the second-best — mypy is a real type checker, just weaker than pyright on inference. (C) is technically possible but degrades the Python arm's assurance signal beyond utility. (D) loses too much.

#### Acceptance

User picks one of the four options above. If (A) or (B): I author `targets/python.json` + `testkits/002-bank-ledger/python/solution.py` + a Python kink manifest, run the kink test, and close F-011 in an Addendum 5.

### F-012. Orchestrator predicate dispatch refactored to support non-LLMLL targets

**Priority:** N/A (closed by this addendum)
**Consumer:** experiment-lead (closed)

#### Evidence

`scripts/run_repair_loop.py:_evaluate_terminal_target` previously hardcoded LLMLL trust-report logic — every call to the predicate ran `_count_bad_trust_tiers` regardless of target. Phase 1.5 required adding the Go adapter whose terminal-target predicate is "all verifier commands exit 0" — a fundamentally different shape from the trust-report predicate. The fix: dispatch on `terminal_target.kind` declared in the manifest. Two kinds supported:

- `"trust-tier"` (LLMLL): existing `_eval_trust_tier_predicate` logic
- `"all-pass"` (Go, future Python, future Rust): new `_eval_all_pass_predicate` — checks `first_fail is None`, plus a sanity check that at least one command ran

The orchestrator passes `terminal_target` through three call layers (`main` → `_run_one_turn` → `_run_verifier_chain` → `_evaluate_terminal_target`).

#### Regression check

Re-ran the existing LLMLL kink cell (`cp examples/withdraw-demo/withdraw.ast.json solution.ast.json`, manifest pinned to `trust-tier`) after the refactor: `runs/20260511T151023Z-regression-after-refactor-...` produces `terminal_state: target-reached`, predicate matched, all 4 apparatus checks pass. The LLMLL accept-path is unaffected by the dispatch refactor.

#### Implication

The orchestrator is now structurally cross-language-clean at the predicate layer. Future adapters (Python, Rust if Phase 4 happens) can pin `kind: "all-pass"` or — if a target gains a richer assurance-evidence channel — declare a new kind with a corresponding `_eval_<kind>_predicate` helper.

### Cross-cutting note — path-counting kink (minor)

First draft of `manifest.kink-test-go.json` had `cp ../../../testkits/...` (three levels up) as the shim path. From the run directory at `experiments/repair-loop/runs/<timestamp>/`, the correct path to `experiments/repair-loop/testkits/...` is `../../testkits/...` (two levels up). The earlier LLMLL kink test used `../../../../examples/...` (four levels up to repo root, then down to `examples/`), which I had pattern-matched incorrectly. Fixed before run launch; surfaced here as a small ergonomic finding. A future refactor could expose `{harness_root}` and `{repo_root}` interpolation tokens to the shim command, eliminating the by-hand path counting. Defer; no priority.

### Updated priority matrix (post-addendum-4)

| # | Finding | Consumer | Priority | Effort estimate | Status |
|---|---|---|---|---|---|
| F-001 | Loop closes cleanly | user | N/A | - | Closed |
| F-002 | Re-injection empirically proven | user | N/A | - | Closed |
| F-003 | Verifier output structurally usable | user | Defence-in-depth | tracked | Open |
| F-004 | Accept-path unexercised | experiment-lead | Medium | - | Closed by Addendum 1 |
| F-005 | Version pin captured automatically | user | N/A | - | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | 15 min | Open (deferred) |
| F-007 | `verify` missing `--json` flag | experiment-lead | High | (fixed) | Closed by Addendum 1 |
| F-008 | Trust-report schema mismatch | experiment-lead | High | (fixed) | Closed by Addendum 1 |
| F-009 | JSON-AST path unexercised | experiment-lead | High | (validated via shim swap) | Closed by Addendum 2 |
| F-010 | Go target adapter built and validated | experiment-lead | N/A | - | **Closed by Addendum 4** |
| F-011 | Python toolchain not installed | user | High (Phase-2 blocker) | (routing required) | **Open — user picks option (A) / (B) / (C) / (D)** |
| F-012 | Predicate dispatch refactored | experiment-lead | N/A | - | **Closed by Addendum 4** |

### Phase 2 readiness (post-addendum-4)

The Phase 2 prerequisite list is updated:

- ☑ Go target adapter built and validated (F-010).
- ☑ Orchestrator predicate dispatch supports non-LLMLL targets (F-012).
- ☐ Python target adapter — blocked on F-011 routing decision.
- ☐ Per-language test kits proper (with assurance/correctness scoring) — Phase 1.75.
- ☐ User approval for paid Phase 2 calibration run.

---

## Addendum 5 — Phase-1.5: Python target adapter built and validated (F-011 closed)

> **Added:** 2026-05-11
> **Purpose:** Close F-011. The user selected option (A) — install pyright + pytest. This addendum records the install path, the Python adapter authoring, and the end-to-end kink-cell validation.

### Toolchain install (one-time, user-authorized)

Two commands run under user authorization:

```bash
pip3 install --user pytest    # → ~/Library/Python/3.11/bin/pytest (pytest 9.0.3)
npm install -g pyright        # → ~/.local/state/fnm_multishells/.../bin/pyright (1.1.409)
```

`pip3` and `npm` both resolve to Homebrew-managed Python 3.11 and fnm-managed Node, respectively. Both targets are user-writable; no sudo required. Both reversible via the corresponding uninstall command.

### F-013. pytest entry point not on default PATH

**Priority:** Low (resolved by `-m pytest` convention)
**Consumer:** experiment-lead (closed inline in the adapter)

#### Evidence

Post-install probe: `which pyright` → `/Users/burcsahinoglu/.local/state/fnm_multishells/.../bin/pyright` (on PATH). `which pytest` → not found, although `~/Library/Python/3.11/bin/pytest` exists. The Homebrew Python user-install directory is not on the macOS default PATH.

#### Why we saw what we saw

macOS does not put `~/Library/Python/3.x/bin` on PATH automatically; that requires explicit shell-config addition. Modifying shell config is out of scope for harness setup.

#### Fix applied (adapter-level)

`targets/python.json` invokes pytest as `python3.11 -m pytest -v test_solution.py` rather than `pytest -v test_solution.py`. The `-m` form sidesteps PATH discovery, pins the Python version explicitly (avoiding the system `python3` → 3.9.6 vs. Homebrew 3.11 ambiguity), and is the standard portable Python testing convention. No shell config modification required.

#### Acceptance

Closed by the post-install kink-cell run.

### F-011 closure — Sample composition (Python arm)

- **Cell:** 1 (n=1)
- **Agent:** real-mode shim that copies both `testkits/002-bank-ledger/python/solution.py` and `testkits/002-bank-ledger/python/test_solution.py` into the run directory. Two `cp` invocations chained by `&&` because the orchestrator's `_find_solution` looks only for the priority-1 file; the test file is co-injected as a Phase-1.5 pre-testkit pattern.
- **Experiment:** `002-bank-ledger`
- **Target:** `python`
- **Repair budget *k*:** 1
- **Toolchain pin:** `Python 3.11.x` (captured as `{"raw": "Python 3.11.x"}`; `python3.11 --version` does not emit JSON); pyright `1.1.409`; pytest `9.0.3`.
- **Run directory:** `runs/20260511T151907Z-k1-python-kink-e002-bank-ledger-python/`
- **Terminal state:** `target-reached` on turn 1 (`all-pass` predicate).

### F-011 closure — Evidence

Verifier chain on the post-install Python kink cell:

- `pyright solution.py` → rc=0; stdout: `0 errors, 0 warnings, 0 informations` (clean type-check on the dataclass-based solution stub).
- `python3.11 -m pytest -v test_solution.py` → rc=0; 6 tests passed (`test_create_ledger_preserves_balances`, `test_successful_transfer_updates_both_accounts`, `test_transfer_preserves_total_balance`, `test_insufficient_funds_rejected`, `test_missing_account_rejected`, `test_non_positive_amount_rejected`).
- Apparatus 4/4 checks pass.

F-011 is closed.

### Cross-cutting note — testkit injection pattern

The Python kink test introduced a new pattern: the shim copies *two* files (solution + colocated test) into the run directory. The Go kink test copied only one (`solution.go`; no test file in the verifier chain yet). The LLMLL kink test copied only one (the agent's tests are in-source via `(check ...)` blocks; `llmll test` discovers them in the same file).

This is an early surface of an asymmetry that Phase 1.75 will need to handle structurally: per-language test-file injection. Three patterns observed:

| Target | Pattern | File count emitted into run_dir |
|---|---|---|
| `llmll` | In-source check blocks; agent emits one solution file | 1 (`solution.llmll` or `solution.ast.json`) |
| `python` | Adjacent test file; testkit must inject it | 2 (`solution.py` + `test_solution.py`) |
| `go` | Adjacent `_test.go` file; Go test discovery + module structure | 2+ when `go test` lands in Phase 1.75 (`solution.go` + `solution_test.go` + `go.mod`) |

Phase 1.75 should formalize this with adapter-declared `testkit_files: [...]` plus orchestrator logic to inject them from `testkits/<experiment>/<target>/` into the run directory at prep-time. The shim-copy workaround is fine for kink tests but does not scale to a paid matrix.

### Updated priority matrix (post-addendum-5)

| # | Finding | Consumer | Priority | Effort estimate | Status |
|---|---|---|---|---|---|
| F-001 | Loop closes cleanly | user | N/A | - | Closed |
| F-002 | Re-injection empirically proven | user | N/A | - | Closed |
| F-003 | Verifier output structurally usable | user | Defence-in-depth | tracked | Open |
| F-004 | Accept-path unexercised | experiment-lead | Medium | - | Closed by Addendum 1 |
| F-005 | Version pin captured automatically | user | N/A | - | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | 15 min | Open (deferred) |
| F-007 | `verify` missing `--json` flag | experiment-lead | High | (fixed) | Closed by Addendum 1 |
| F-008 | Trust-report schema mismatch | experiment-lead | High | (fixed) | Closed by Addendum 1 |
| F-009 | JSON-AST path unexercised | experiment-lead | High | - | Closed by Addendum 2 |
| F-010 | Go target adapter built and validated | experiment-lead | N/A | - | Closed by Addendum 4 |
| F-011 | Python toolchain not installed | user | High (Phase-2 blocker) | (install authorized) | **Closed by Addendum 5** |
| F-012 | Predicate dispatch refactored | experiment-lead | N/A | - | Closed by Addendum 4 |
| F-013 | pytest entry point not on default PATH | experiment-lead | Low | - | **Closed by Addendum 5 (adapter uses `python3.11 -m pytest`)** |

### Phase 2 readiness (post-addendum-5)

The Phase 2 prerequisite list is updated again:

- ☑ Go target adapter built and validated (F-010).
- ☑ Python target adapter built and validated (F-011, F-013).
- ☑ Orchestrator predicate dispatch supports non-LLMLL targets (F-012).
- ☐ **Phase 1.75: testkit injection pattern + assurance/correctness scoring extension.** Three open sub-items:
  1. Adapter-declared `testkit_files: [...]` + orchestrator pre-injection.
  2. `evaluate_run.py` extension to compute correctness + assurance scores from per-target verifier outputs (currently `scoring.status = "pending"` for real runs).
  3. Per-language testkit content for `002-bank-ledger` beyond the Phase-1.5 smoke tests (LLMLL check blocks, Go `_test.go`, Python `test_solution.py` expanded to the harness-test list in `problems/002-bank-ledger.md`).
- ☐ User approval for paid Phase 2 calibration run.

Phase 1.5 is fully closed. Phase 1.75 (testkit infrastructure + scoring) is the next bounded engineering work before Phase 2 calibration becomes meaningful.

---

## Addendum 6 — Phase-1.75: testkit-injection seam (sub-item #1 of three)

> **Added:** 2026-05-11
> **Purpose:** Close the first of three Phase-1.75 sub-items: adapter-declared file injection. The orchestrator now pre-injects harness-owned files (test files, fixtures) into the run directory before the agent runs, separating the *harness-owned* artefact channel from the *agent-emitted* one.

### F-014. `harness_files` adapter declaration + orchestrator pre-injection

**Priority:** Phase 1.75 prerequisite (closed by this addendum)
**Consumer:** experiment-lead (closed)

#### Design

Each target adapter may declare a `harness_files: [filenames]` field. At run-directory prep time, the orchestrator's new `_inject_harness_files` reads this list and copies each file from `testkits/<experiment>/<target>/<filename>` into the run directory. Adapters without `harness_files` get no injection (backward-compat). Source-file absence is a hard error (`SystemExit`), surfaced before any agent invocation — better than silent skipping that would only manifest later as a verifier failure.

#### Why this is the right seam

Three asymmetric patterns surfaced in Phase 1.5 (Addendum 5's cross-cutting note table):

| Target | Solution emission | Harness-owned artefacts |
|---|---|---|
| `llmll` | `solution.llmll` (in-source `(check ...)` blocks) | None (`harness_files: []`) |
| `python` | `solution.py` | `test_solution.py` |
| `go` | `solution.go` | (Phase 1.75 next: `go.mod`, `solution_test.go`) |

Without a structural seam, shim agents (and real agents) would have to write harness files themselves — a contract violation. The `harness_files` mechanism makes the harness/agent boundary explicit in the adapter schema.

#### Evidence

- `scripts/run_repair_loop.py` adds `_inject_harness_files`; `_prepare_run_dir` calls it after writing `AGENT_INSTRUCTIONS.md`.
- `targets/python.json` declares `harness_files: ["test_solution.py"]`.
- `manifest.kink-test-python.json` shim simplified to a single `cp solution.py` (no longer chains the test-file cp).
- Validation cell: `runs/20260511T152256Z-k1-python-injection-...` — pyright clean, pytest 6 passed, predicate matched. `ls *.py` shows both `solution.py` (from shim) and `test_solution.py` (from injection).
- Regression cells:
  - LLMLL (`harness_files` absent): `runs/20260511T152257Z-regression-after-injection-llmll-...` — `target-reached`. Backward compat confirmed.
  - Go (`harness_files` absent): `runs/20260511T152257Z-regression-after-injection-go-...` — `target-reached`. Backward compat confirmed.

#### Acceptance

Closed. Phase 1.75 sub-item #1 complete.

### Updated priority matrix (post-addendum-6)

| # | Finding | Consumer | Priority | Effort estimate | Status |
|---|---|---|---|---|---|
| F-001..F-005 | (Phase 1) | various | various | - | Closed (Addendum 0/1/2) |
| F-006 | No CLI override for *k* | experiment-lead | Low | 15 min | Open (deferred) |
| F-007..F-013 | (Phase 1.5) | various | various | - | Closed (Addenda 1/2/4/5) |
| F-014 | `harness_files` injection seam | experiment-lead | Phase-1.75 prereq | - | **Closed by Addendum 6** |

### Phase 1.75 readiness (post-addendum-6)

Three sub-items, ordered:

1. ☑ **Adapter-declared `harness_files` + orchestrator pre-injection** — closed by this addendum.
2. ☐ **Per-language testkit content expansion** for `002-bank-ledger`:
   - Python: expand `test_solution.py` from 6 smoke tests to full harness-test list per `problems/002-bank-ledger.md` (sequence-preservation, leave-unchanged-on-failure semantics).
   - Go: author `go.mod` + `solution_test.go`; switch Go adapter from single-file mode (`go vet solution.go`) to module mode (`go vet ./...`, `go build ./...`, `go test ./...`); add `harness_files: ["go.mod", "solution_test.go"]`.
   - LLMLL: relies on agent-emitted `(check ...)` blocks; no harness-owned testkit (documented asymmetry). Scoring will measure check-block density and contract diversity directly from solution.
3. ☐ **`evaluate_run.py` scoring extension**: implement two-axis scoring per `docs/design/language-comparison-experiments.md:198-226`. Minimum viable: score the categories with clean per-target evidence (Build/typecheck = 15 pts, API conformance = 15 pts, Core behavior = 35 pts via test pass rate, Proof or trust evidence = 20 pts for LLMLL only). Stub the rest with placeholder + TODO. Currently `scoring.status = "pending"` for real runs; this becomes a real score.

---

## Addendum 8 — Phase-1.75: scoring extension (sub-item #3) + F-018 + F-019

> **Added:** 2026-05-11
> **Purpose:** Close Phase-1.75 sub-item #3. Implements the per-axis scoring rubric settled by `language-team` v2 (Addenda 6/7 of this postmortem, plus the language-team `revise` turn after professor critique). Surfaces F-018 (compiler-engineer routing required), closes F-019 (orchestrator adapter fix). Empirically validates the v2 rubric against three target adapters via re-evaluation of existing kink cells plus two new LLMLL cells with the verify-fixpoint chain.

### F-018. PBT static evaluator's `FuncEnv` does not include imported-module def-logic

**Priority:** High (blocks LLMLL harness-test injection; defers but does not stall Phase 2)
**Consumer:** compiler-engineer

#### Evidence

R1 smoke cell (`/tmp/llmll-r1-smoke/`, three variants):

| Cell | check discovered | property evaluated | outcome |
|---|---|---|---|
| `(open solution) ... (check (plus-one n) ...)` (cross-module via open) | yes (1 property) | no | 0 Passed, 1 Skipped (1000 discards) |
| `(import solution) ... (check (solution.plus-one n) ...)` (cross-module via qualified name) | yes (1 property) | no | 0 Passed, 1 Skipped (1000 discards) |
| All inline in one file (host-module call) | yes | yes | **1 Passed, 0 Skipped** |

#### Why we saw what we saw

`llmll test` traverses the module graph and discovers cross-file `(check ...)` blocks; the discovery surface works. The **PBT static evaluator's `FuncEnv`** (per v0.10.2 CHANGELOG entry on `runPropertyWith` threading top-level def-logic environments — likely in `compiler/src/LLMLL/Contracts.hs` or `PBT.hs`) is built from the host module's `def-logic` statements only. Cross-module `def-logic` reached via `(open ...)` or qualified names is in type-checker scope but **not** in PBT evaluator scope. The property body cannot reduce to a literal Bool when the imported function is encountered, producing `Skipped` per `LLMLL.md §5.1` outcome semantics.

This is spec/code drift: `LLMLL.md §8.6` ([line 867](../../../LLMLL.md)) promises `(open path)` bare-name injection; the PBT evaluator does not honor it. The type-checker honors it (cross-module type-check works, per `compiler/src/LLMLL/Module.hs:checkInterfaceMismatch`).

#### Implication

For compiler-engineer: extend the FuncEnv builder used by `runPropertyWith` to merge def-logic statements from imported modules, mirroring how `buildModuleEnv` populates the type-checker's `TypeEnv` (`Module.hs:mergeModuleEnvs`). The fix is bounded: PBT scope should follow type-checker scope under `(open ...)`. Until this lands, the language-team's recommended cross-module harness-test pattern (Addenda 6/7) cannot be used; LLMLL agents are scored on their own in-source `(check ...)` blocks only, not on a harness-injected baseline.

#### Acceptance

R1's `(open solution)` variant reports `Passed: 1` instead of `Skipped: 1` after the fix. The LLMLL adapter then gains `harness_files: ["test_solution.llmll"]`; the LLMLL testkit at `testkits/002-bank-ledger/llmll/` is authored against the imported solution.

---

### F-019. Orchestrator's verify chain did not produce a `.verified.json` sidecar

**Priority:** High (blocks verified-tier signal in trust report; blocked the entire `locally_verified_obligations` and `compositionally_verified_module_rate` evidence channel)
**Consumer:** experiment-lead (fixed in this addendum)

#### Evidence

Pre-fix `targets/llmll.json` verifier chain: `check` → `check-strict` → `holes` → `test` → `verify` (with `--trust-report --weakness-check --spec-coverage`). Per `llmll verify --help`: *"--trust-report: Print transitive trust summary **instead of** running fixpoint."* The chain never invoked liquid-fixpoint; no `.verified.json` sidecar was written; the trust report floored at `asserted` even for QF-LIA-verifiable programs.

Empirical confirmation: a fresh `llmll --json verify banking-fresh.llmll --trust-report` (no prior bare-verify) reports `post_level: asserted` on all 6 functions. After a bare `llmll verify banking-fresh.llmll` runs liquid-fixpoint and writes the sidecar, the same `--json verify --trust-report` invocation reports `post_level: "verified (liquid-fixpoint)"` on all 6 functions.

#### Why we saw what we saw

I designed the verify chain against the spec text in `LLMLL.md` without empirically verifying that `--trust-report` triggered the fixpoint discharge. Mirror image of F-007/F-008 (the predicate design failure that wrote against a guessed schema rather than the live compiler output). Same Day-1 design pattern; same outside-PL discipline reminder: read the live `--help` output before scoping the verifier chain.

#### Fix applied (no compiler change)

`targets/llmll.json` adds a new verifier command `verify-fixpoint` *before* the existing `verify`:

```
"name": "verify-fixpoint",
"argv": ["llmll", "verify", "{solution}"],
"capture": "exit_and_text"
```

The bare invocation runs liquid-fixpoint, writes `solution.{llmll,ast.json}.verified.json` in the run directory, exits 0 on SAFE. The subsequent `verify` (with `--json --trust-report ...`) reads the sidecar and reports `post_level: verified` where the fixpoint discharged. The chain now has six commands per LLMLL cell.

#### Acceptance

Two re-run LLMLL kink cells under the new chain:

- `runs/20260511T174356Z-k1-f019-banking-...` (banking_ledger.llmll): `locally_verified_obligations: 6` ✓, `outstanding_trust_acknowledgments: 0` ✓, `compositionally_verified_module_rate: 0.0` ✓.
- `runs/20260511T174412Z-k1-f019-withdraw-...` (withdraw-demo.ast.json): `locally_verified_obligations: 0` (verify-fixpoint stdout reports `body-fallback: withdraw` — the `PositiveInt` refinement-type predicate is not body-faithfully discharged), `compositionally_verified_module_rate: 0.0` ✓.

Both runs `target-reached` on turn 1. Apparatus 4/4 passes. F-019 closed.

#### Cross-cutting observation

The two LLMLL cells now distinguish each other on the proof-evidence axis: 6 vs. 0 `locally_verified_obligations`. This is exactly the v2 rubric's design intent — the local-proof channel carries information that the compositional-verification rate does not (both cells score 0.0 there, but the local-proof split tells you which program reached body-faithful verification). The professor's G2 concern about double-counting was correct in principle; the v2 split is also correct: `effective_level` is derived, `pre_level`/`post_level` are independent.

---

### F-020. Phase-1.75 sub-item #3 — per-axis scoring rubric implemented end-to-end

**Priority:** Phase-1.75 prerequisite (closed by this addendum)
**Consumer:** experiment-lead (closed)

#### Implementation

`scripts/evaluate_run.py` `_evaluate_scoring` replaced. New structure:

- 12 sub-categories total (6 correctness + 6 assurance).
- 8 implemented end-to-end across the three targets (LLMLL, Go, Python).
- 4 stubbed with explicit `status: "TODO(sub-3-v2)"` and per-target rationale notes.
- 1 hard-deferred (`specification_adequacy`); also `determinism_isolation` is hard-deferred via `status: "deferred"`.
- No 100-pt aggregate (professor G3); per-axis subscores only.
- Two headline metrics for LLMLL: `trust_declarations_per_kloc` and `compositionally_verified_module_rate` (replaces the dropped aggregate).
- "Test quality" is itself split into three independent sub-axes per the v2 rubric: `example_based_test_pass_rate`, `pbt_sample_pass_rate`, `agent_emitted_test_count`. None aggregated.
- "Proof or trust evidence" is split into three sub-axes for LLMLL: `locally_verified_obligations`, `outstanding_trust_acknowledgments`, `compositionally_verified_module_rate`. Reports `null` with note for non-LLMLL targets (no analogous channel).

#### Per-target evidence parsers (new)

- `_parse_llmll_test_results` — regex for `Passed:`/`Failed:`/`Skipped:` from `llmll test` text output.
- `_parse_go_test_results` — count `--- PASS:`, `--- FAIL:`, `--- SKIP:` markers from `go test -v` output.
- `_parse_pytest_results` — regex for `N passed`, `M failed`, `K skipped` from pytest summary.
- `_parse_pyright_results` — regex for `N errors, M warnings` from pyright summary.
- `_summarize_trust_report` — read the live JSON schema for `entries[].pre_level`/`post_level`/`effective_level`, compute locally_verified and compositionally_verified rates.
- `_count_llmll_check_blocks` / `_count_llmll_trust_declarations` — dual-path source parsing (regex for `.llmll`, JSON-AST traversal for `.ast.json`).
- `_count_program_kloc` — line-count for `.llmll`, statement-count × 5 approximation for `.ast.json`.

#### Validation evidence — five re-evaluated cells

| Cell | Target | core_behavior pass rate | locally_verified | comp_rate | trust_per_kloc |
|---|---|---|---|---|---|
| `20260511T174356Z-k1-f019-banking` | llmll | n/a (no checks) | 6 | 0.0 | 0.0 |
| `20260511T174412Z-k1-f019-withdraw` | llmll | n/a (no checks) | 0 (body-fallback) | 0.0 | 0.0 |
| `20260511T153812Z-k1-go-module` | go | 1.0 (8/8) | n/a | n/a | n/a |
| `20260511T161928Z-k1-python-expanded` | python | 1.0 (8/8) | n/a | n/a | n/a |
| `20260511T134926Z-k1-kink-ast` (pre-F-019) | llmll | n/a | 0 (no fixpoint run) | 0.0 | 0.0 |

The pre-F-019 cell's `locally_verified=0` is now correctly read as "the orchestrator never ran fixpoint" — the scorer is the right tool to surface adapter-chain defects retrospectively.

#### Acceptance

Closed. The per-axis subscores are computed and emitted into `evaluation.json` for any cell with a real (non-stub) agent. Phase-2 calibration cells will produce meaningful empirical numbers on the implemented axes; the 4 stubbed sub-categories carry `status: "TODO(sub-3-v2)"` markers visible in the JSON for downstream review.

### Cross-cutting note — sample/test-quality and proof-evidence asymmetries are now empirically observable

Three target asymmetries now visible in the scoring output (where pre-Phase-1.75 they were structural-but-unmeasured):

1. **Test channel asymmetry.** Go/Python `core_behavior` populates from `example_based_test_pass_rate`; LLMLL from `pbt_sample_pass_rate`. Both report `value` under `core_behavior` so the subscore is comparable per-cell. The underlying evidence type is distinguished by the `channel` field (`go-example-based`, `python-example-based`, `llmll-pbt`).
2. **Proof-evidence asymmetry.** Only LLMLL contributes `proof_or_trust_evidence` subscores; Go and Python report `null` with explicit `note: "Target has no analogous proof-evidence channel."` This is the principled cross-language posture — the assurance axis does NOT aggregate across targets; the LLMLL contribution is reported, the absence in Go/Python is reported.
3. **Harness-test asymmetry.** F-018 blocks LLMLL from receiving a harness-injected test baseline; Go/Python receive harness `_test.go`/`test_solution.py` via the `harness_files` seam. The `agent_emitted_test_count` axis is populated for LLMLL only; for Go/Python it currently reports `null` because the shim agents copy stubs without their own tests, but the field is in place for Phase-2/3 real agents.

### Updated priority matrix (post-addendum-8)

| # | Finding | Consumer | Priority | Status |
|---|---|---|---|---|
| F-001..F-016 | (Phase 1 / 1.5 / 1.75 sub-items #1, #2) | various | various | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | Open (deferred) |
| F-017 | LLMLL in-source-test asymmetry (revised by language-team v2; no longer a structural gap, blocked on F-018 instead) | experiment-lead | (revised) | Closed by Addendum 7, F-018 supersedes |
| F-018 | PBT FuncEnv lacks imported-module def-logic | compiler-engineer | High | **Open (route to /compiler-engineer)** |
| F-019 | verify chain missing fixpoint-discharge step | experiment-lead | High (fixed) | **Closed by Addendum 8** |
| F-020 | Per-axis scoring rubric implemented | experiment-lead | Phase-1.75 prereq | **Closed by Addendum 8** |

### Phase 1.75 readiness (post-addendum-8)

All three sub-items closed:

- ☑ Adapter-declared `harness_files` + orchestrator pre-injection (Addendum 6, F-014).
- ☑ Per-language testkit content expansion (Addendum 7, F-015/F-016/F-017).
- ☑ `evaluate_run.py` scoring extension per v2 rubric (Addendum 8, F-019/F-020).

Phase 2 (paid calibration) is now ready, conditional on:

1. **F-018 routing decision.** If user routes F-018 to compiler-engineer and the fix lands, Phase 2 runs with full cross-target test-quality coverage. If F-018 is deferred, Phase 2 runs with the documented LLMLL harness-baseline-test asymmetry (LLMLL contributes 0 on the harness-baseline subscore, agent-emitted check blocks only).
2. **User approval for paid agent matrix.** The calibration run remains ≤45 agent invocations, ~$50 API spend, ~6 hours wall-clock serial.

### Open question for the user

**Phase-2 launch decision.** The harness is end-to-end ready. F-018 is the only remaining quality-of-life issue; it does not block Phase 2 launch, but it does affect the defensibility of LLMLL's test-quality subscore. Two paths:

1. Route F-018 to `compiler-engineer` first, land the fix, then launch Phase 2 with clean cross-target coverage.
2. Launch Phase 2 now under the documented asymmetry; route F-018 in parallel.

Both are defensible. The first produces cleaner Phase-2 numbers; the second is faster to data. User adjudicates.

---

## Addendum 9 — Phase-2.0 probe (gemini × llmll × 002-bank-ledger × k=1)

> **Added:** 2026-05-11
> **Purpose:** Pre-calibration gap-finding probe. Two runs: an initial probe (`phase2-probe`, infrastructure-fail at 240s timeout on Gemini's sandboxed-read denials) that surfaced F-021 and F-023; a re-launched probe (`phase2-probe-2`, k=1, 540s budget) after the fixes that completed cleanly and demonstrated the apparatus is Phase-2-ready.

### Sample composition

- **Cells:** 2 (one infra-fail under F-021/F-023; one budget-exhausted post-fix that produced real scoring).
- **Agent:** `gemini-default` (Gemini CLI 0.41.2, default model; `-y --skip-trust -p '...'`).
- **Experiment:** `002-bank-ledger`.
- **Target:** `llmll`.
- **Repair budget *k*:** 2 (original probe; infra-fail) → 1 (re-launch after F-022 timeout-cap reduction).
- **Toolchain pins:** `llmll 0.10.2`; gemini `0.41.2`.
- **Run directories:**
  - `runs/20260511T183006Z-phase2-probe-...` (infra-fail; surfaced F-021 + F-022)
  - `runs/20260511T183807Z-phase2-probe-2-...` (clean; primary hypothesis met)

### F-021. Orchestrator does not seed `LLMLL.md` and `llmll-ast.schema.json` into the run dir

**Priority:** High (blocks LLMLL agent operation; closed by this addendum)
**Consumer:** experiment-lead (closed)

#### Evidence

First-probe stderr (`runs/20260511T183006Z-phase2-probe-.../turns/turn_01/agent.stderr.log`) contained four `Error executing tool read_file: Path not in workspace` errors. Gemini CLI's workspace sandbox blocks file reads outside the cwd. The agent attempted: `/Users/burcsahinoglu/Documents/llmll/LLMLL.md`, `/Users/burcsahinoglu/Documents/llmll/docs/design/language-comparison-experiments.md`, plus the home-directory `.llmll` and `.gemini` discovery probes. All denied. Without the spec, Gemini fell back to priors and emitted a 3-line non-LLMLL fragment before timing out at 240s.

Precedent: `experiments/minimal-agent/scripts/prepare_run.py:267-268` copies both `LLMLL.md` and `docs/llmll-ast.schema.json` into every run dir as a load-bearing precondition. The repair-loop orchestrator's `_prepare_run_dir` (which I authored) cargo-culted the file list partially and omitted both. Day-1 design omission on my part.

#### Fix applied (no commit yet; bundled into Phase-2.0 commit)

`scripts/run_repair_loop.py:_prepare_run_dir` now copies `LLMLL.md` and `docs/llmll-ast.schema.json` into the run directory conditionally on `args.target == "llmll"`. Mirrors the minimal-agent precedent. Uses `REPO_ROOT` already defined at module top.

#### Acceptance

Re-launched probe (`runs/20260511T183807Z-phase2-probe-2-...`) shows zero "Path not in workspace" errors in stderr. Closed.

---

### F-022. Agent timeout calibration — 240s was insufficient under F-021 conditions

**Priority:** Medium (resolved by reducing `repair_budget_k` from 2 to 1 in the probe manifest, allowing a wider per-turn budget within Bash's 10-min cap)
**Consumer:** experiment-lead (closed)

#### Evidence

First probe: agent rc=124 (TimeoutExpired from `_invoke_real_agent`) at 240s. The agent was making many tool calls (most denied by F-021's workspace sandbox) and presumably still emitting when the timeout fired. Whether 240s is sufficient *under* F-021-fixed conditions is unknown — the re-launched probe used 540s, which completed (Gemini emitted ~60 lines of well-structured LLMLL plus an own check block within budget, though the total turn time is unmeasured precisely from the artefacts).

#### Implication

Phase 2 calibration's `timeout_seconds_per_turn` should remain ≥ 540s for LLMLL cells. The 9-cell matrix runs serially; each cell can take up to 540s × 5 turns = 2700s = 45 min. Worst-case Phase-2 wall-clock with 9 cells is ~7 hours serial, ~2.5 hours with reasonable parallelism. Within the originally-estimated `~6 hours wall-clock serial`.

The wider implication for the experiment-lead's tooling: my Bash subprocess cap (10 min) is *below* a full Phase-2 cell's worst-case latency. For the actual Phase-2 matrix launch, the user should invoke the orchestrator directly from their own shell, not via my Bash tool. Or use `run_matrix.py` (which doesn't exist yet for repair-loop but is the natural next harness addition).

#### Acceptance

Closed (resolved by manifest revision). Wider Phase-2 timeout discipline noted for the calibration run.

---

### F-023. `AGENT_INSTRUCTIONS.md` should advertise spec-local availability and sandbox boundary

**Priority:** Low (closed inline alongside F-021)
**Consumer:** experiment-lead (closed)

#### Fix applied

`_agent_instructions` for LLMLL targets now includes:

> ## LLMLL spec and JSON-AST schema
>
> `LLMLL.md` and `llmll-ast.schema.json` are present in the run directory. These are your authoritative language references. Read them before emitting. Do not attempt to read repo-level files outside this directory — your sandbox is the run directory; reads outside it will be denied.

This pre-empts the discovery-probe pattern F-021 surfaced (agent fishes for spec in repo root, hits sandbox-deny errors, falls back to priors).

#### Acceptance

Re-launched probe shows the agent emitted spec-aligned LLMLL (`(module ...)`, refinement types, pre/post contracts, `?proof-required` markers, Result types). Closed.

---

### F-024. Gemini's match-arm surface drifts from the §17 grammar (revised diagnosis 2026-05-11)

**Priority:** Medium (downstream; agent-vs-language friction; documentation surface)
**Consumer:** language-team (canonical match-arm surface decision) + documentation-lead (§3.3 example correction)
**Status:** revised 2026-05-11 after isolation testing disconfirmed both prior diagnoses

#### Original hypothesis (withdrawn)

The probe report attributed the parse failure to Gemini's snake_case identifiers (`create_ledger`, `account_id`). Bisection against `llmll 0.10.2` shows snake_case identifiers parse cleanly in isolation; the §2.1 identifier character class accepts both `_` and `-`, and the canonical-form pedagogy in §2.5 (shipped in commit `2c80eec`) clarifies this for future agents. The original diagnosis is withdrawn.

A second hypothesis raised during the revision pass — that Gemini invented a user-defined sum-type surface LLMLL does not support — is also withdrawn. LLMLL §3.3 ships user-defined sum types with the exact `(type Name (| Constructor Payload))` form Gemini emitted, and `(type Transaction (| Transfer (string, (string, Amount))))` parses cleanly in isolation against `llmll 0.10.2`. R3 (sum-types non-goal callout) is withdrawn — the data does not support it.

#### Revised root cause (verified by bisection)

The actual parse failure is match-arm wrapping. `LLMLL.md` §17 grammar line 1618:

```
match-arm = "(" pattern expr ")"
```

Each arm shares one set of parens around pattern and body. Gemini emitted siblings:

```
(match ledger
  (LedgerState (pair accounts _))     ;; pattern in its own parens
  (map-get accounts account_id))      ;; body as sibling form
```

The parser, having closed the pattern at the end of line 31, expects the closing `)` of the `match` form. The bare `(map-get accounts account_id)` at line 32 col 25 produces the `unexpected 'a' expecting ')'` token. Re-wrapping the arm parses cleanly:

```
(match ledger
  ((LedgerState (pair accounts _)) (map-get accounts account_id)))
```

Bisection runs (`llmll 0.10.2`, n=1 each, `/tmp/*.llmll`):

| Minimal pair | Result |
|---|---|
| Bare snake_case (`def-logic create_ledger [accounts: ...]`) | parses OK |
| Gemini's literal sum-type `(type Transaction (\| Transfer (string, (string, Amount))))` | parses OK |
| Full match arm with snake_case body, sibling form | fails at col 25 with `unexpected 'a' expecting ')'` |
| Same match arm with kebab-case identifiers throughout, sibling form | fails at col 25 with same error |
| Same match arm with arms wrapped per §17 grammar, snake_case body | parses OK |

The variable that drives parse / no-parse is the arm wrapping, not the casing and not the sum-type declaration.

#### Cross-evidence: spec self-inconsistency

LLMLL §3.3 lines 206–213 give informal `match` examples in the *sibling* form:

```
(match status
  (Red)              "stop"
  (Green _)          "go"
  (Blue)             "wait")
```

The §17 grammar rejects this form. The same parser error fires verbatim on the §3.3 informal example when copy-pasted into a complete module. The §3.3 example surface drifts from the shipping grammar. Shipping examples (e.g., `examples/pair_type_test/pair_destruct_let.llmll:14`) already use the wrapped form, which points to §17 being correct and §3.3's informal example being the documentation defect.

#### Implication

For `language-team`: decide which match-arm surface is canonical. Options:

- (a) §17 grammar is canonical (arms wrapped). §3.3 informal examples must be corrected to `((Red) "stop") ((Green _) "go") ...` form. Shipping `examples/` already use this form, so no compiler or example change is needed.
- (b) §3.3 informal surface is canonical (sibling form). The §17 grammar and parser must extend to accept it.

Empirical evidence (shipping `examples/`, surviving repair-loop solutions, current parser behaviour) points to (a). The §3.3 informal example is then a documentation defect.

For `documentation-lead`: after the `language-team` decision, publish whichever side is correct. If (a): patch §3.3 examples to wrapped form. If (b): patch §17 grammar.

For Phase-2/3 H1/H2 measurement: this remains the kind of agent-vs-spec friction the matrix is meant to capture. The decision above governs the expected noise floor — under (a) with §3.3 corrected, LLMLL agents that read the spec consistently should converge on wrapped arms.

#### Acceptance

- `language-team` produces a canonical-form decision and writes it to `docs/design/` or directly into `LLMLL.md` §3.3 / §17.
- `documentation-lead` patches the losing side.
- A k=1 re-probe with Gemini on `002-bank-ledger` produces a `solution.llmll` that parses (assuming the spec is internally consistent and Gemini reads the corrected §3.3).

#### Related: §2.5 naming pedagogy (closed)

The naming-convention noise source addressed by §2.5 in commit `2c80eec` is closed as originally intended, even though naming was not F-024's actual root cause. §2.5 removes a separate friction source from future cells and remains valuable.

---

### Primary hypothesis: MET

The apparatus produced a non-degenerate scoreable cell from a real agent invocation. Verified via `runs/20260511T183807Z-phase2-probe-2-.../evaluation.json`:

- `apparatus.status: passed` (4/4 checks)
- `scoring.status: scored` (8 sub-categories produced values; 4 with `TODO(sub-3-v2)`; 1 deferred)
- `correctness_subscores.solution_discovery.value: true` (agent emitted a file)
- `correctness_subscores.build_typecheck.value: false` (correctly captured the parse failure from F-024)
- `correctness_subscores.core_behavior: passed=0/failed=0/skipped=0` (no PBT could run; parse blocked)
- `assurance_subscores.test_quality.agent_emitted_test_count: 1` (Gemini emitted one `(check ...)` block — the agent intent was captured even though execution failed)
- `assurance_subscores.proof_or_trust_evidence.locally_verified_obligations: 0` (no fixpoint discharge possible without parse)
- `headline_metrics.trust_declarations_per_kloc: 0.0` (Gemini emitted no `(trust ...)` declarations)

This is the EVIDENCE PATTERN a parse-failing LLMLL cell will produce in Phase-2/3. The v2 rubric carries the signal: the agent tried (file emitted), structured (test block emitted), but failed at the parser. Distinguishable from an agent that didn't emit at all (where `solution_discovery` would be false).

### Secondary hypothesis: not tested

The k=1 probe does not exercise turn-2-vs-turn-1 differences. Two options for closing the secondary:

1. **One follow-up probe at k=2.** Single additional Gemini call (~$0.50–2). Validates the turn-2-context-injection path under real agents.
2. **Let it surface naturally in Phase 2 calibration.** k=5 cells will exercise it across all three agents. If turn 2 systematically equals turn 1 (i.e., agents ignore `context/turn_NN_verifier.json`), the Phase-2 result will surface it as a finding.

### Apparatus changes bundled into the post-probe commit (uncommitted)

`scripts/run_repair_loop.py`:
- F-021 fix: copy `LLMLL.md` and `docs/llmll-ast.schema.json` into LLMLL run dirs.
- F-023 fix: extend `_agent_instructions` with spec-availability block for LLMLL targets.
- Per-turn solution snapshot (`_snapshot_solution` helper + `_run_one_turn` call site) — landed earlier in this session as a probe-preparation change.

`manifest.phase2-probe-llmll.json` (new):
- Phase-2.0 manifest with `gemini-default` agent cmd, k=1, 540s per-turn budget.

### Updated priority matrix (post-addendum-9)

| # | Finding | Consumer | Priority | Status |
|---|---|---|---|---|
| F-001..F-016 | (earlier addenda) | various | various | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | Open (deferred) |
| F-018 | PBT FuncEnv lacks imported-module def-logic | compiler-engineer | High | Open |
| F-019 | verify chain missing fixpoint-discharge step | experiment-lead | High | Closed by Addendum 8 |
| F-020 | Per-axis scoring rubric implemented | experiment-lead | Phase-1.75 prereq | Closed by Addendum 8 |
| F-021 | Run dir does not seed LLMLL.md + schema | experiment-lead | High | **Closed by Addendum 9** |
| F-022 | Agent timeout calibration (240s insufficient under F-021) | experiment-lead | Medium | **Closed by Addendum 9 (manifest reduction to k=1 + 540s)** |
| F-023 | AGENT_INSTRUCTIONS.md needs spec-availability note | experiment-lead | Low | **Closed by Addendum 9** |
| F-024 | Match-arm wrapping drift (§3.3 informal examples vs §17 grammar); naming-convention surface closed via §2.5 / `2c80eec` | language-team + documentation-lead | Medium | **Revised 2026-05-11 — match-arm canonical form open; §2.5 naming pedagogy closed; R3 sum-types non-goal withdrawn** |

### Phase 2 calibration readiness (post-probe)

Apparatus is **Phase-2-ready**. The probe found and closed three real gaps (F-021, F-022, F-023) plus surfaced one downstream agent-side finding (F-024) that is itself the kind of evidence Phase-2 should produce.

Phase-2 launch decision:

1. **Pre-Phase-2: tooling caveat.** My Bash subprocess cap (10 min) is below a worst-case Phase-2 cell's latency (~45 min at 540s × 5 turns + verifier). The user should launch the Phase-2 matrix from their own shell, not via this conversation's Bash tool. Alternatively, a `run_matrix.py` script can be authored for the repair-loop harness (mirroring the minimal-agent precedent) and the user invokes it directly.
2. **Phase 2 cost estimate (revised).** 9 cells × ≤45 min per cell ≈ 7 hours serial wall-clock. API spend depends on agent mix; under $50 at typical token costs across Claude Opus + Sonnet + Gemini.
3. **F-024 routing decision (revised 2026-05-11).** Route to `language-team` for §3.3-vs-§17 match-arm canonical-form decision (recommended; this gates the parse-error noise floor for any match-heavy problem in Phase 2/3). The original naming-convention TARGET.md callout question is moot — §2.5 pedagogy in commit `2c80eec` already closed the naming surface, and bisection showed naming was not the actual root cause anyway.
4. **Optional follow-up k=2 probe.** Single Gemini call to validate secondary hypothesis (turn-2 reads turn-1 context). Recommended if F-024 isn't routed via TARGET.md change, since a k=2 cell with parse failure on turn 1 would directly demonstrate whether the agent ATTEMPTS to consume the parse-error diagnostic on turn 2.

Phase 2 (paid calibration) still gated on (2) and (3) plus user approval.

---

## Addendum 7 — Phase-1.75: testkit content expansion (sub-item #2 of three)

> **Added:** 2026-05-11
> **Purpose:** Close the second of three Phase-1.75 sub-items: per-language testkit content. Go switches from single-file mode to module mode with `go.mod` + `solution_test.go`; Python `test_solution.py` expands from 6 smoke tests to 8 harness tests matching the harness-test list in `problems/002-bank-ledger.md`; LLMLL's in-source-test asymmetry is confirmed and documented.

### F-015. Go testkit upgraded to module mode with 8-test harness suite

**Priority:** Phase 1.75 prerequisite (closed by this addendum)
**Consumer:** experiment-lead (closed)

#### Design and evidence

Three changes:

1. **Solution stub refactor.** `testkits/002-bank-ledger/go/solution.go` renames the previous `Transfer` type to `TransferRecord`, freeing the function name `Transfer` (formerly `Transferr` — a one-r hack from Phase 1.5 to avoid the type/function collision). The renaming is cosmetic; the public API surface for harness tests is now idiomatic Go (`Transfer(...) (*Ledger, error)`).
2. **Module structure added.** `testkits/002-bank-ledger/go/go.mod` declares `module solution; go 1.23`. The harness now operates in module mode, which is the prerequisite for `go test ./...`.
3. **Test file added.** `testkits/002-bank-ledger/go/solution_test.go` carries 8 tests against the harness-test list in `problems/002-bank-ledger.md`:
   - `TestCreateLedgerPreservesBalances`
   - `TestSuccessfulTransferUpdatesBothAccounts`
   - `TestTransferPreservesTotalBalanceSingleStep`
   - `TestSequenceOfTransfersPreservesTotalBalance`
   - `TestInsufficientFundsRejected`
   - `TestInsufficientFundsLeavesLedgerUnchanged` (covers the "failed transfer leaves ledger unchanged" requirement)
   - `TestMissingAccountRejected`
   - `TestNonPositiveAmountRejected`

`targets/go.json` declares `harness_files: ["go.mod", "solution_test.go"]` and switches `verifier_commands` from single-file mode (`go vet solution.go`, `go build solution.go`) to module mode (`go vet ./...`, `go build ./...`, `go test ./...`).

Validation cell `runs/20260511T153812Z-k1-go-module-...`: `vet rc=0`, `build rc=0`, `test rc=0` with all 8 tests passing in 0.586s. Run dir contains `go.mod` (injected), `solution.go` (shimmed), `solution_test.go` (injected).

#### Acceptance

Closed. The Go target adapter is ready for Phase 2 calibration.

### F-016. Python testkit expanded to 8-test harness suite

**Priority:** Phase 1.75 prerequisite (closed by this addendum)
**Consumer:** experiment-lead (closed)

#### Design and evidence

`testkits/002-bank-ledger/python/test_solution.py` expands from 6 Phase-1.5 smoke tests to 8 tests matching the Go list:

- 2 tests renamed for clarity (`test_transfer_preserves_total_balance` → `test_transfer_preserves_total_balance_single_step`).
- 2 tests added: `test_sequence_of_transfers_preserves_total_balance` (covers the "sequence of valid transfers" harness requirement), `test_insufficient_funds_leaves_ledger_unchanged` (covers the "leaves ledger unchanged on failure" requirement; Python's frozen dataclass design guarantees immutability structurally, but the test asserts it explicitly for cross-language symmetry).
- 6 tests preserved unchanged.

Validation cell `runs/20260511T161928Z-k1-python-expanded-...`: pyright clean, pytest `8 passed in 0.01s`.

#### Cross-language parity

Go and Python testkits now exercise identical behavioral coverage. The two test lists are line-by-line equivalent (modulo language-idiomatic assertion syntax). This makes Phase-3 H1/H2 comparisons defensible at the "same product specification, same behavioral test surface" axis required by [language-comparison-experiments.md:234](../../../docs/design/language-comparison-experiments.md#L234).

#### Acceptance

Closed.

### F-017. LLMLL in-source-test asymmetry confirmed; no testkit content authored

**Priority:** N/A (documented, not blocking)
**Consumer:** experiment-lead (closed by note)

#### Evidence

LLMLL's testing model is in-source `(check ...)` blocks within the solution file (`llmll test solution.llmll` runs them). There is no separate harness-test-file pattern in LLMLL today, and engineering one — via `(open <module>)` cross-file imports against an agent-emitted solution module — is out of scope for Phase 1.75 (requires module-system features and design work that belongs in `language-team`, not `experiment-lead`).

Consequence: `targets/llmll.json` continues to declare no `harness_files`; the LLMLL testkit at `testkits/002-bank-ledger/llmll/` remains empty (its existence is documentary).

#### Implication for Phase-2/3 scoring

For Go and Python, "Test quality" (assurance rubric, 20 pts) is split across two evidence sources: harness-owned tests (the baseline guaranteed by injection) and agent-emitted tests (additive — agents can add their own). For LLMLL, harness-owned tests do not exist; "Test quality" is entirely derived from agent-emitted `(check ...)` blocks. This asymmetry must be reflected in the scoring extension (sub-item #3) — LLMLL's test-quality score should reward check-block density and contract-coverage diversity, not raw test-pass count.

Documented here as a Phase 1.75 sub-item #3 constraint. Will be cited in Addendum 8 when scoring lands.

### Updated priority matrix (post-addendum-7)

| # | Finding | Consumer | Priority | Effort estimate | Status |
|---|---|---|---|---|---|
| F-001..F-013 | (Phase 1 / 1.5) | various | various | - | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | 15 min | Open (deferred) |
| F-014 | `harness_files` injection seam | experiment-lead | Phase-1.75 prereq | - | Closed by Addendum 6 |
| F-015 | Go module-mode + 8-test suite | experiment-lead | Phase-1.75 prereq | - | **Closed by Addendum 7** |
| F-016 | Python 8-test suite (parity with Go) | experiment-lead | Phase-1.75 prereq | - | **Closed by Addendum 7** |
| F-017 | LLMLL in-source-test asymmetry | experiment-lead | N/A | - | **Closed by Addendum 7 (documented)** |

### Phase 1.75 readiness (post-addendum-7)

Three sub-items, ordered:

1. ☑ Adapter-declared `harness_files` + orchestrator pre-injection (Addendum 6).
2. ☑ Per-language testkit content expansion (Addendum 7).
3. ☐ `evaluate_run.py` scoring extension — the final Phase-1.75 prerequisite before Phase 2 calibration can run with real (non-placeholder) correctness/assurance numbers.

---

## Addendum 10 — F-024 revised diagnosis + Phase-2 cell pin

> **Added:** 2026-05-11
> **Revised:** 2026-05-11 (second pass — see below; original sum-type-non-goal framing withdrawn)
> **Purpose:** Correct the F-024 record from Addendum 9 (misdiagnosed as snake_case parse failure), document the naming pedagogy that landed in `LLMLL.md §2.5`, and pin the Phase-2 cell composition for a downstream launcher turn.

### F-024 revised — real cause is match-arm wrapping (§3.3 informal vs §17 grammar)

Addendum 9's record at line 948 named the parse failure as `Gemini emits snake_case identifiers`. That diagnosis is wrong. A first-pass revision of this addendum then attributed the failure to user-defined sum-type surface invention; that diagnosis is also wrong. Re-bisection against `llmll 0.10.2` against the verbatim probe artefact ([turns/turn_01/solution.llmll](runs/20260511T183807Z-phase2-probe-2-e002-bank-ledger-llmll/turns/turn_01/solution.llmll)):

| Snippet under test | Result |
|---|---|
| Bare snake_case (`def-logic create_ledger [accounts: ...]`) | parses OK |
| Bare kebab-case (`def-logic plus-one [n-val: int] ...`) | parses OK |
| Gemini's literal sum-type `(type Transaction (\| Transfer (string, (string, Amount))))` — single tuple payload | **parses OK** |
| Multi-arg constructor `(type T (\| Cons string string int))` — different surface, not what Gemini emitted | fails at col 40 (LLMLL constructors take one payload type per §3.3) |
| Full match arm with snake_case body, sibling form (Gemini's emission) | **fails at col 25** with `unexpected 'a' expecting ')'` |
| Same match arm with kebab-case identifiers throughout, sibling form | **fails at col 25** with same error |
| Same match arm with arms wrapped per §17 grammar, snake_case body | parses OK |

The probe's actual parse failure at `solution.llmll:32:25` reproduces only when the match arm is unwrapped. Snake_case and the sum-type declaration are both innocent.

`LLMLL.md §17` line 1618 grammar: `match-arm = "(" pattern expr ")"`. Each arm shares one set of parens around pattern and body. Gemini emitted:

```
(match ledger
  (LedgerState (pair accounts _))     ;; pattern alone in parens
  (map-get accounts account_id))      ;; body as a sibling form
```

The §3.3 informal example at LLMLL.md lines 206–213 uses this same sibling form:

```
(match status
  (Red)              "stop"
  (Green _)          "go"
  (Blue)             "wait")
```

That informal example does not parse. The §3.3 example surface drifts from the shipping §17 grammar. Shipping examples (e.g., `examples/pair_type_test/pair_destruct_let.llmll:14`) already use the wrapped form, so the grammar is correct and §3.3's informal example is the defect.

Gemini's match arm form mirrors the §3.3 informal example. The most likely mechanism is that Gemini read §3.3 and reproduced the surface there, not the §17 grammar.

### Resolution — naming pedagogy landed; match-arm canonical-form decision pending

**Surface-style portion (closed):** `LLMLL.md §2.5 Naming Conventions` shipped in commit `2c80eec` (2026-05-11). Pedagogical only; grammar unchanged. CHANGELOG entry under `Unreleased`. Promoted from a `/language-team` proposal via `/documentation-lead` spec-track hand-off. Closes the naming-convention noise source, even though naming was not F-024's actual root cause.

**Withdrawn (R3 — user-defined sum-types non-goal callout):** The proposal to add a non-goal callout for user-defined sum types is withdrawn. LLMLL §3.3 ships user-defined sum types and the parser accepts Gemini's literal emission of `(type Transaction (| Transfer (string, (string, Amount))))`. The first-pass bisection table that triggered this proposal used the multi-arg constructor form `(| Transfer string string int)` — a synthetic surface Gemini did not emit. Synthetic snippet → synthetic finding. Withdrawn.

**R5 — match-arm canonical form (new, open):** §3.3 informal `match` examples disagree with the §17 grammar. Decision options:

- **R5a:** §17 grammar is canonical (arms wrapped). Patch §3.3 informal examples to wrapped form. Shipping `examples/` already use wrapped form; no compiler or example change is needed. Smallest spec change.
- **R5b:** §3.3 informal surface is canonical (sibling form). Patch the §17 grammar and parser to accept it. Larger compiler change.
- **R5c:** Leave silent; accept Phase-2/3 evidence noise.

Empirical evidence (shipping `examples/`, the parser's current behaviour, the working solutions on disk) points to **R5a**. Closure depends on user routing via a separate `/language-team` turn followed by a `/documentation-lead` patch.

### Phase 2 launch-readiness — cell composition pinned

Gate (3) from Addendum 9 ("F-024 routing decision") is **partially decided**. The original Addendum-9 framing (TARGET.md naming callout) is moot — §2.5 pedagogy in commit `2c80eec` closed the naming surface independently. The real F-024 root cause (match-arm wrapping, R5 above) is a separate item routed to `language-team` + `documentation-lead`; Phase-2 can launch in parallel with that turn, since match-arm wrapping affects the noise floor but does not gate the apparatus.

**Phase 2 cell composition (pinned for launcher turn):**

- **Problem:** `002-bank-ledger` (only problem on disk; QF-LIA-dominant per `README.md:56`).
- **Targets:** `llmll`, `python`, `go` (per `targets/*.json` adapters).
- **Agent:** `gemini-default` recommended for continuity with the Phase-2.0 probe (same model, same invocation pattern). Phase 2 is k-calibration on a *known-tractable* cell; rotating the agent introduces a confound with k. Phase 3 rotates agents.
- **Tries per cell:** 3 (per `README.md:27`).
- **k (repair budget):** 5 (per `README.md:27`).
- **Cell count:** 1 problem × 3 targets × 3 tries = 9 cells.
- **Wall-clock estimate:** 9 cells × ≤45 min (540s × 5 turns + verifier) ≈ 6.75 h serial.
- **Cost estimate:** under $20 at typical Gemini token costs (Gemini-only mix; Claude/Codex deferred to Phase 3).

### Remaining gap before Phase 2 kick-off

No `run_matrix.py` exists for the repair-loop harness. `run_repair_loop.py` runs one cell per invocation. Options:

- **Option A (recommended):** Author `experiments/repair-loop/scripts/run_matrix.py` that iterates cells from a Phase-2 manifest and supports `--resume-from-cell N`. Mirrors the `experiments/minimal-agent/scripts/run_matrix.py` precedent. ~1 hour of work; amortizes across Phase 2 + Phase 3 (Phase 3 multiplies by 3 agents × 3 problems = 81 cells).
- **Option B:** Bash loop the user pastes. Trades reproducibility for speed.

A `manifest.phase2-calibration.json` also needs to be written, with the cell composition above. Recommended payload: clone `manifest.phase2-probe-llmll.json`, set `repair_budget_k: 5`, set `run_count: 3`, expand `targets: ["llmll", "python", "go"]`, keep `experiments: ["002-bank-ledger"]` and the `gemini-default` agent. Recommended downstream-turn invocation:

```
/experiment-lead Phase 2 launcher: author manifest.phase2-calibration.json
(composition pinned in postmortem-001 Addendum 10) and run_matrix.py with
--resume-from-cell N support. Cells: 1 problem × 3 targets × 3 tries = 9 cells.
Agent: gemini-default. k=5, 540s per turn.
```

### Priority matrix delta

F-024 row updated to point to this addendum. Status (post-second-revision): `Surface-style closed (LLMLL.md §2.5, commit 2c80eec); match-arm canonical form open (R5); R3 sum-types non-goal withdrawn`.

## Addendum 11 — Phase 2 calibration outcomes (gemini × 002-bank-ledger × 3 targets × k=5 × 3 tries)

> **Added:** 2026-05-12
> **Purpose:** Record Phase-2 calibration outcomes from the 9-cell matrix authorized in Addendum 10. Two cells of data: the apparatus event (Plan Mode regression diagnosed, fixed, validated — F-025) and the experimental data itself (F-026 through F-030). The integrated headline: apparatus held cleanly on relaunch; **experiment design has structural issues that gate Phase 3**.

### Sample composition

- **Cells run:** 9 / 9 (1 problem × 3 targets × 3 tries).
- **Agent:** `gemini-default` (Gemini CLI 0.41.2, default model; `gemini -y --skip-trust -p '...'`).
- **Experiment:** `002-bank-ledger`.
- **Targets:** `llmll`, `python`, `go`.
- **Repair budget *k*:** 5; **timeout per turn:** 540s.
- **Toolchain pins:** `llmll 0.10.2`; gemini `0.41.2`; harness git SHA stamped per-batch into `matrix_manifest.json` (`944be1a...`, dirty).
- **Active batch:** `runs/20260512T031938Z-matrix/`.
- **Aborted batch (apparatus event, evidence preserved):** `runs/20260512T015249Z-matrix/` + per-cell `cells/` and run dirs; see `ABORTED.md` in that batch.

### Headline by-target

| Target | target-reached | budget-exhausted | Convergence turns | Predicate kind |
|---|---|---|---|---|
| `llmll` | 1 / 3 | 2 / 3 | {5, –, –} | `trust-tier` |
| `python` | 3 / 3 | 0 / 3 | {1, 2, 1} | `all-pass` |
| `go` | 3 / 3 | 0 / 3 | {1, 1, 1} | `all-pass` |

The LLMLL win used the full k=5 budget; Python and Go converged in 1–2 turns each. Cross-target turn comparison is **confounded by predicate-strictness asymmetry** (F-026 below) — the bars are not equivalent. Calibration interpretation requires unpacking before the numbers carry weight.

---

### F-025. Workspace-scoped agent state pinned Plan Mode across the matrix relaunch

**Priority:** High (closed by user intervention; capability-probe proposal preserved for prereq path)
**Consumer:** experiment-lead (closed) + harness-design (open recommendation)

#### Evidence

First Phase-2 launch (`runs/20260512T015249Z-matrix/`) put cell 1 through 5 turns of structural failure. Each turn's stderr (`runs/20260512T015250Z-gemini-default-try01-of-03-c01-e002-bank-ledger-llmll/turns/turn_01/agent.stderr.log:6-8`):

```
YOLO mode is enabled. All tool calls will be automatically approved.
Error executing tool write_file: Tool execution denied by policy. You are in Plan Mode...
Error executing tool run_shell_command: Tool "run_shell_command" not found...
```

YOLO and Plan Mode are independent policy axes; `-y` engaged YOLO but did not unset Plan Mode. The agent's stdout simultaneously **hallucinated successful completion** — claimed file emissions that the stderr proved were denied. `_find_solution` returned None each turn; the cell budget-exhausted with no solution written. Cell 2 was killed mid-turn-1 on user halt; cells 3–9 never launched.

Root cause: per-project Plan Mode pin at `~/.gemini/tmp/llmll/`, set by an interactive Gemini session against this repo between the Phase-2.0 probe (which succeeded) and this matrix launch. The Gemini CLI walks up from cwd to a `.git` root, resolves the project to `llmll`, and inherits the pinned mode. `--skip-trust` and `-y` do not override `/plan-mode`. The Phase-2.0 probe (`runs/20260511T183807Z-phase2-probe-2-...`) succeeded under identical flags because Plan Mode had not yet been pinned for the `llmll` project at probe time.

#### Diagnosis sequence

1. Verify scaffold (`/tmp/verify_gemini_writes.sh`) reproduced from a `/tmp/`-scoped scratch dir — file write **succeeded** under the same `-y --skip-trust` flags. cwd was outside the `.git` ancestry; project root resolved to a fresh, unpinned project.
2. Hypothesis: pin is project-scoped. Inspection of `~/.gemini/tmp/llmll/chats/session-2026-05-12T02-09-d8b58aed.jsonl` confirmed an interactive `/plan-mode off` issued by the user at 02:09Z, mid-diagnosis. The session log's model response acknowledged *exiting* plan mode — proving the project had been *in* plan mode prior.
3. In-repo verify scaffold (`/tmp/verify_in_repo.sh`, probe A) wrote `hello.txt` cleanly from inside the LLMLL repo with the same flags; `/plan-mode off` stuck.

#### Fix applied

User-side, not harness-side: the interactive `/plan-mode off` at 02:09Z unpinned the project state. Matrix relaunch on this corrected state produced 0 Plan Mode hits across 9 cells × all turns. No code change to the manifest or harness.

#### Implication (proposed harness change, deferred)

The `required_executables` and `required_env` prereq checks in `run_matrix.py` (Addendum 10's launcher) verify the agent binary is present and authenticates — they do not verify the agent can *do work from cwd*. The hallucination-while-blocked failure mode (rc=0 + persuasive stdout + zero successful tool calls) is invisible to single-cell apparatus validation. A pre-flight **capability probe** is the next prereq layer:

- From a scratch dir under the harness root (so the agent's project-root walk matches the matrix condition), invoke the agent with a trivial "write a file" prompt.
- Verify the file lands with expected content.
- Fail-fast before launching cell 1 if not.

This generalizes beyond Plan Mode: every additional agent (Claude CLI, codex, Antigravity-flavored variants) will bring its own workspace-scoped state the manifest doesn't see. Routed as a Phase-2-postmortem item to experiment-lead's next harness turn; deliberately not bundled into the F-026/F-027 design gate.

#### Acceptance

Relaunched batch shows **0 Plan Mode hits across 9 cells × every turn**. 9/9 cells wrote real solution files (3.2–5.0 KB for LLMLL, 2.4–4.2 KB for Python, 2.2–3.2 KB for Go). Apparatus closed for this batch.

---

### F-026. Cross-target predicate-strictness asymmetry — the matrix cannot answer H1 as configured

**Priority:** High (blocks Phase 3 H1 read)
**Consumer:** experiment-lead (apparatus / experiment design) + language-team (predicate-vocabulary decision)

#### Evidence

LLMLL cells use `terminal_target.kind = trust-tier`; Python and Go cells use `kind = all-pass` (per `manifest.phase2-calibration.json:terminal_target_per_target` and the per-cell synthetic manifests under `runs/20260512T031938Z-matrix/cells/cell_NN/manifest.json`).

What each predicate measures:

- **`trust-tier`** (LLMLL): all verifier commands rc=0, AND every entry in the `--trust-report` is at `asserted` tier or above. Per `run_repair_loop.py:_count_bad_trust_tiers:538-562`, the accepted set includes `verified`, `proved`, `asserted`, `contract-checked`, `contract_checked`, `checked`, `tested`. **`asserted` is the weakest tier** — the obligation exists in the source but has not been discharged by SMT, runtime check, or test.
- **`all-pass`** (Python/Go): all verifier commands rc=0. For Python, `pyright` + `pytest`; for Go, `gofmt` + `go vet` + `go test`. The testkit ships 8 behavioral tests per target (`testkits/002-bank-ledger/{python,go}/test_solution.py` / `solution_test.go`).

In this batch, Python and Go matched the predicate by **passing 8/8 behavioral tests** — real behavioral correctness signal. LLMLL matched the predicate (cell 02 only) by **producing a trust report with 6 entries all at `asserted` tier** — declared obligations, zero discharged. The bars are not equivalent.

| Cell | Target | Status | core_behavior | test_quality | proof_or_trust_evidence |
|---|---|---|---|---|---|
| 1 | llmll | budget-exhausted | 0.0 (0/0/3 skipped) | pbt_pass_rate=0.0, tests=3 | verified=0, ack=0, comp=0.0 |
| 2 | llmll | target-reached | 0.0 (0/0/2 skipped) | pbt_pass_rate=0.0, tests=2 | verified=0, ack=0, comp=0.0 |
| 3 | llmll | budget-exhausted | 0.0 (0/0/2 skipped) | pbt_pass_rate=0.0, tests=2 | verified=0, ack=0, comp=0.0 |
| 4–6 | python | target-reached | 1.0 (8/0/0 passed) | (target-N/A) | (target-N/A) |
| 7–9 | go | target-reached | 1.0 (8/0/0 passed) | (target-N/A) | (target-N/A) |

#### Why we saw what we saw

H1 in the README hypothesis block reads: *"at fixed k, LLMLL agents reach a higher terminal assurance score than Python or Go agents on the same problem, holding correctness constant."* The matrix design implicitly assumes the terminal-target predicate is *comparable* across targets — i.e., that target-reached means equivalent "done" semantics across LLMLL / Python / Go. It doesn't. LLMLL's predicate is satisfied by *declared* obligations; Python/Go's predicate is satisfied by *executed* behavioral tests. A cross-target turn-count or pass-rate comparison conflates these two axes.

#### Implication

This is an experiment-design item, not a compiler-engineer item. Two options for downstream `/language-team`:

- **R6a (tighten the trust-tier predicate):** remove `asserted` from the accepted-levels set; require at least one of `verified` / `contract_checked` / `tested` per entry. Under this rule, all three LLMLL cells in this batch invert to budget-exhausted — Phase 2 reads as 0/3 LLMLL wins. n=3 is small but the directional signal is strong: gemini-default does not push past `asserted` under k=5 on this cell.
- **R6b (split the predicate into two axes):** keep `target-reached` as a binary signal ("the agent stopped without an open error") and add an *assurance score* extracted from the trust report as the H1 measurement. Cross-target comparison happens on the assurance score, not on terminal-reached status.

Empirical evidence (this batch's data) does not adjudicate R6a vs R6b — both are coherent design moves. Surfaced to `/language-team` for routing.

#### Acceptance

Closure when `manifest.phase2-calibration.json:terminal_target_per_target` is rewritten under one of R6a / R6b and a re-probe cell is run to confirm the predicate behaves as designed.

---

### F-027. The `asserted` trust tier is a no-op in the current predicate

**Priority:** High (tightly coupled to F-026; logically a refinement)
**Consumer:** language-team (predicate-vocabulary decision) + compiler-engineer (if R6a routes through a compiler check)

#### Evidence

Across n=3 LLMLL cells × the final-turn trust report:

| Cell | Status | Entries | `verified` | `proved` | `contract_checked` | `tested` | `asserted` | `null` (no_contract) |
|---|---|---|---|---|---|---|---|---|
| 01 | budget-exhausted | 7 | 0 | 0 | 0 | 0 | **7** | 0 |
| 02 | target-reached | 6 | 0 | 0 | 0 | 0 | **6** | 0 |
| 03 | budget-exhausted | 6 | 0 | 0 | 0 | 0 | 3 | 3 |

**Across 19 obligations declared by the agent in this batch, 0 reached `verified` / `proved` / `contract_checked` / `tested` tier.** Every clause the agent wrote remained at `asserted` (declared, not validated). Cell 02's target-reached status is structurally a *match on stated intentions*, not on verified evidence.

#### Why we saw what we saw

Two non-exclusive readings, distinguishable only with more data:

- **Agent-side:** gemini-default declares obligations (it wrote 6–7 `(post)` clauses, 1 `(pre)` clause, 2–4 `(where)` refinement-type predicates per cell, plus `:source "..."` annotations) but does not push toward `(check ...)`-runs that engage the test channel or toward fixpoint-friendly obligation shapes that SMT can discharge. The repair loop's feedback channel may not be routing the agent toward this.
- **Compiler-side:** the verifier's discharge channels (SMT / liquid-fixpoint / contract-runner / PBT) may not be firing on these obligation shapes. The trust-tier ladder includes `verified` and `tested` and `contract_checked` as nominal targets, but if the verifier cannot reach them, the agent has no path to push obligations past `asserted` no matter how it iterates. F-028 below partially probes this.

#### Implication

The current trust-tier predicate is satisfied by *any* well-formed solution with declared obligations — including a solution where the agent has put zero effort into making those obligations true. The predicate doesn't reward verification; it rewards declaration. Phase 3 with this predicate produces a measurable that the experiment cannot defend (H1 cannot be evaluated; only "did the agent declare obligations at all").

#### Acceptance

Closure shared with F-026 — either the predicate accepts only above-`asserted` tiers (R6a), or terminal-reached and assurance score split (R6b), so that `asserted` is no longer a free pass.

---

### F-028. verify-fixpoint diagnostics are not captured — the repair loop's feedback channel is partially blind on the LLMLL side

**Priority:** High (compromises the repair-loop hypothesis)
**Consumer:** compiler-engineer (primary) + harness-design (orchestrator stderr capture)

#### Evidence

`verify-fixpoint` exit codes per turn distinguish the three LLMLL cells more cleanly than any other signal:

| Cell | turn 1 | turn 2 | turn 3 | turn 4 | turn 5 |
|---|---|---|---|---|---|
| 01 | fail | fail | **pass** | fail | fail |
| 02 | fail | fail | **pass** | pass | pass |
| 03 | fail | fail | fail | fail | fail |

But across 15 LLMLL turns, **verify-fixpoint's stderr is empty in every single failing turn** (sampled via `repair_loop_log.json:turns[*].verifier_results`). The harness captures exit code, no other diagnostic. Whatever caused verify-fixpoint to fail in cell 03's turn 5, or in cell 01's turn 4 (regression — see F-029), is not visible to the agent's next turn.

#### Why we saw what we saw

Two possibilities to disambiguate:

- The verifier emits diagnostics on stdout (not stderr) and the orchestrator's verifier-chain capture loses them. `_run_verifier_chain` in `run_repair_loop.py:383-440` captures both, but the per-turn `verifier_results[*].stdout` / `stderr` payload may be truncated or the verifier may emit to a side channel.
- The verifier emits nothing on failure — exit-1 is the entire signal. If so, the agent's next turn has no actionable information about *what* the fixpoint discharger objected to.

Either way, the repair-loop hypothesis (H1/H2/H3 in the README) rests on the agent being able to *use* verifier feedback to iterate. F-028 says: for the failure mode that empirically distinguishes win from lose in this batch, the feedback channel is silent.

#### Implication

Compiler-engineer item: probe `llmll verify-fixpoint` invocation on cell 01's turn-4 solution to determine what (if anything) the discharger emits on failure. If diagnostic surface exists but the harness drops it: harness fix. If diagnostic surface doesn't exist: compiler-engineer plan to add it. Either fix unblocks the H1/H2 cycle.

#### Acceptance

Closure when verify-fixpoint failures produce a non-empty diagnostic payload that the orchestrator captures into `context/turn_NN_verifier.json`, and a re-probe of cell 01-shape solution shows the next turn's agent receives the payload.

---

### F-029. Non-monotonic repair — the agent broke its own previously-passing solution

**Priority:** Medium (design observation; informs Phase-3 sample sizing)
**Consumer:** experiment-lead (Phase-3 sample-size review) + language-team (informs H2 measurement design)

#### Evidence

Cell 01's verify-fixpoint trajectory (above): fail / fail / **pass** / fail / fail. The agent reached a verify-fixpoint-passing solution at turn 3, then the turn-4 emission regressed to failing again. The solution.llmll snapshot at `runs/20260512T031939Z-gemini-default-try01-of-03-c01-e002-bank-ledger-llmll/turns/turn_03/solution.llmll` versus turn 4's snapshot would isolate which lines the agent rewrote between them; not extracted in this addendum, but the artefact is on disk for a follow-up turn.

Cell 02 (the winner): fail / fail / **pass** / pass / pass. Once it reached, it stayed.

#### Implication

Repair-loop progress is not strictly monotonic in turns. n=3 already shows it. Phase-3 sample sizes must be wide enough to characterize regression rate, not just terminal-state directionality. Rough estimate: at the rate of 1 regression in 15 LLMLL turns observed here, n=3 per cell will misestimate regression frequency in either direction; n≥8 per cell is closer to the bar for a stable rate estimate, though that number wants a power calc before Phase 3 commits.

The wider H2 measurement implication: turns-to-converge as a univariate signal undersells what the repair loop is doing. A per-turn fixpoint-status trajectory captures the regression signal that aggregate convergence-rate does not.

#### Acceptance

Closure when Phase-3 sample sizing (or a preliminary re-probe) records regression rate per cell as a first-class signal alongside terminal turn count.

---

### F-030. LLMLL in-source test channel does not land — F-017 confirmed empirically

**Priority:** Medium (cross-references Addendum 7's F-017)
**Consumer:** language-team (test-channel design) + experiment-lead (in-source-test prerequisite for trust-tier credit)

#### Evidence

All three LLMLL solutions in this batch emitted `(check ...)` blocks (cell 01: 3 checks; cells 02–03: 2 checks each). Per the v2 scoring rubric's `core_behavior` sub-score, all three cells scored 0.0 with `passed=0, failed=0, skipped=2-3, channel=llmll-pbt`. The PBT runner saw the tests but skipped them.

The trust-report entries for these solutions are all at `asserted`, never at `tested` — the in-source `(check ...)` blocks do not engage the test channel that would lift entries to `tested` tier.

This is **F-017** (Addendum 7's "LLMLL in-source-test asymmetry") observed live in Phase-2 data rather than predicted from structural analysis.

#### Implication

LLMLL's in-source `(check ...)` form is documented but is not currently a path by which the verifier elevates obligations above `asserted` tier in the trust report. F-018 (Addendum 8 — PBT FuncEnv lacks imported-module def-logic, open against compiler-engineer) may be the underlying mechanism — but n=3 in this batch is not enough to establish that. The empirical observation stands independent of the mechanism: under current conditions, the test channel does not produce trust-tier credit on this problem with this agent.

#### Acceptance

Closure shared with F-018 (compiler-engineer). When F-018 lands, a re-probe cell should show `tested` entries in the trust report on `(check ...)`-engaged solutions, and `core_behavior` should produce a non-zero PBT pass rate.

---

### Withdrawn items (none new this addendum)

No claims withdrawn during this analysis pass. The pre-scoring read I gave ("LLMLL solutions had zero contracts") was wrong (wrong grep patterns — `(contract )` instead of `(post )` / `(pre )` / `(where )`); corrected before this addendum drafted, did not propagate to a finding.

### Null results

- **H2 (convergence differential on QF-LIA) — not evaluable from this matrix.** The cross-target turn comparison is confounded by F-026; Python/Go's 1–2 turns vs LLMLL's 5 is uninterpretable until predicate strictness is comparable. **n=9 was not enough to test H2; the design wasn't.**
- **Apparatus regression rate — null.** 0 Plan Mode hits across 9 cells × all turns post-fix. n=9 is small but supports "the F-025 fix held for this batch under user-side discipline (no interactive Gemini sessions on the repo mid-run)."

### What the data tells us — synthesized

Five lessons of unequal weight, ordered by Phase-3 blocking importance:

1. **The matrix as configured cannot answer H1.** F-026 + F-027: LLMLL's trust-tier predicate accepts `asserted` (declared-but-unverified) and Python/Go's all-pass requires 8/8 behavioral tests. Different bars. Cell 02's "win" is a vacuous predicate match in the strict sense (verifier discharged nothing) even though the solution contains substantive `(pre)` / `(post)` / `(where)` machinery. Phase 3 with this predicate produces a number that doesn't measure H1's claim.

2. **gemini-default engages LLMLL's verification surface but doesn't push it.** This was the surprise — the agent wrote 6–7 `(post)` clauses per cell, refinement-typed `Balance`, `:source` annotations, the lot. But not one obligation crossed from `asserted` into `verified` / `contract_checked` / `tested`. Two readings — agent-side or compiler-side — distinguishable only with F-028 resolved.

3. **verify-fixpoint diagnostics are silent, so the repair loop is partially blind on LLMLL.** F-028. Without verify-fixpoint stderr, the agent's iteration on LLMLL solutions is informed only by exit codes. The repair-loop hypothesis's *whole point* is that verifier feedback drives the agent toward terminal state; missing fixpoint diagnostics undermines that feedback channel where it matters most.

4. **Repair-loop progress is non-monotonic.** F-029. Cell 01 reached fixpoint pass at turn 3 then broke it at turn 4. n=3 already showed this; Phase-3 sample size needs to characterize variance, not just centrality.

5. **The apparatus has an environment-state dimension we didn't model.** F-025. The Phase-2.0 probe's success was insufficient to predict Phase-2 success — the Plan Mode pin was set between them in state the manifest doesn't see. The capability-probe proposal is the next prereq layer; deferred (deliberately) to a post-Phase-3-gate harness turn, since Phase 3 won't launch until F-026/F-027/F-028 land.

### Combined implication for Phase 3

Do not launch Phase 3 as currently designed. Three items gate it:

- **F-026 (experiment design):** route to `/language-team` for R6a vs R6b decision. The predicate vocabulary needs to either tighten (exclude `asserted`) or split (binary terminal-reached + numeric assurance score).
- **F-027 (predicate refinement):** logically follows F-026; same routing.
- **F-028 (compiler / harness):** route to `/compiler-engineer` for diagnostic-surface probe on verify-fixpoint. Can land in parallel with F-026/F-027.

The cheapest data move that advances the question is a **small re-probe** (k≥5, 1–2 cells) of one LLMLL cell with the F-026 predicate tightened and F-028 diagnostics surfaced, to see whether gemini-default can push past `asserted` under repair pressure when the feedback channel is informative. If yes, Phase 3 is worth the spend. If no, the experiment design needs a third channel (agent-prompted toward proof-obligation discharge — possibly via expansion of AGENT_INSTRUCTIONS.md for LLMLL targets) before the matrix carries weight.

### R5 status (Addendum 10's open item — match-arm canonical form)

Unchanged by this batch. Gemini emitted wrapped-form match arms in cell 02's solution (`runs/20260512T033017Z-.../solution.llmll`) and the parser accepted them across all 5 turns — empirical confirmation that the §17 grammar holds under repair iteration, no observable noise in the matrix data attributable to match-arm wrapping. R5 closure still depends on the separate `/language-team` + `/documentation-lead` turn to canonicalize §3.3 informal examples (recommended option R5a per Addendum 10). Not a Phase-3 gate; tracked as Addendum 10's open item.

### Apparatus changes in this addendum

`experiments/repair-loop/manifest.phase2-calibration.json` (new, landed pre-Phase-2 per Addendum 10): no further changes.

`experiments/repair-loop/scripts/run_matrix.py` (new, landed pre-Phase-2 per Addendum 10): no further changes. Proposed addition (capability-probe in prereq path, F-025) deferred to a post-Phase-3-gate harness turn.

`experiments/repair-loop/runs/20260512T015249Z-matrix/ABORTED.md` (new): documents the Plan-Mode-pin batch abort for evidence-trail integrity.

### Updated priority matrix (post-addendum-11)

| # | Finding | Consumer | Priority | Status |
|---|---|---|---|---|
| F-001..F-016 | (earlier addenda) | various | various | Closed |
| F-006 | No CLI override for *k* | experiment-lead | Low | Open (deferred) |
| F-018 | PBT FuncEnv lacks imported-module def-logic | compiler-engineer | High | Open |
| F-019 | verify chain missing fixpoint-discharge step | experiment-lead | High | Closed by Addendum 8 |
| F-020 | Per-axis scoring rubric implemented | experiment-lead | Phase-1.75 prereq | Closed by Addendum 8 |
| F-021 | Run dir does not seed LLMLL.md + schema | experiment-lead | High | Closed by Addendum 9 |
| F-022 | Agent timeout calibration | experiment-lead | Medium | Closed by Addendum 9 |
| F-023 | AGENT_INSTRUCTIONS.md spec-availability note | experiment-lead | Low | Closed by Addendum 9 |
| F-024 | Match-arm wrapping drift + unit-payload pedagogy | language-team + documentation-lead | Medium | **Closed 2026-05-12 — spec-side: `ecdf42f` (§3.3/§9/§13.5) + `f5dce77` (§3.2/§3.3); empirical: `runs/20260512T164907Z-f024-reprobe-…` (n=1, Gemini, k=1, `check.rc=0`). See Addendum 13.** |
| F-025 | Workspace-scoped agent state pinned Plan Mode | experiment-lead | High | **Closed by user `/plan-mode off` 2026-05-12; capability-probe proposal preserved** |
| F-026 | Cross-target predicate-strictness asymmetry | experiment-lead + language-team | High (Phase-3 gate) | **Open** |
| F-027 | `asserted` trust tier is a no-op in current predicate | language-team + compiler-engineer | High (Phase-3 gate; couples F-026) | **Open** |
| F-028 | verify-fixpoint diagnostics not captured | compiler-engineer + harness-design | High (Phase-3 gate) | **Open** |
| F-029 | Non-monotonic repair (turn-3 pass → turn-4 fail) | experiment-lead + language-team | Medium | **Open** (sample-sizing input) |
| F-030 | LLMLL `(check)` blocks skip — F-017 confirmed live | language-team + experiment-lead | Medium (couples F-018) | **Open** |

### Phase 3 readiness (post-Addendum-11)

Apparatus is Phase-3-ready (F-025 closed, harness held over 9 cells). Experiment design is **not** Phase-3-ready — F-026, F-027, F-028 are the gate. Recommended downstream-turn invocations:

```
/language-team Phase-2 calibration surfaced F-026 (cross-target predicate
asymmetry) and F-027 (`asserted` trust tier as no-op). Adjudicate R6a (tighten
trust-tier predicate to exclude `asserted`) vs R6b (split terminal-reached
binary from numeric assurance score). See postmortem-001 Addendum 11.
```

```
/compiler-engineer Phase-2 surfaced F-028 (verify-fixpoint stderr empty across
15 LLMLL turns; the repair loop's actionable-feedback channel is silent on the
failure mode that distinguishes win/lose). Probe diagnostic surface on
verify-fixpoint failure; propose harness or compiler patch as evidence
indicates. See postmortem-001 Addendum 11.
```

Phase-3 manifest authoring waits on those two turns landing. The small re-probe described in "Combined implication" is the data move that decides Phase-3 spend.

## Addendum 12 — F-024 spec-side closure (both R5 sub-axes)

> **Added:** 2026-05-12
> **Purpose:** Record the spec-side closure of F-024. Both R5 sub-axes
> identified in the Addendum 10 re-bisection table have now landed in
> `LLMLL.md`. Empirical acceptance (a re-probe Gemini run on `002-bank-ledger`
> that produces a parsing `solution.llmll`) is the remaining sub-condition.

### Spec landings

**R5a — match-arm canonical form (closed).** Commit `ecdf42f`
(`docs(spec): correct match-arm informal examples in LLMLL.md §3.3 / §9
/ §13.5 (R5a)`) selects R5a (§17 grammar canonical; arms wrapped) and
patches the §3.3 / §9 / §13.5 informal examples to the wrapped form. No
grammar or parser change. Closes the surface drift documented in
Addendum 10 lines 1211–1230.

**R5 second sub-axis — unit-payload vs nullary constructor pedagogy
(closed).** Commit `f5dce77` (`docs(spec): correct unit-payload vs
nullary constructor pedagogy in §3.2 / §3.3`) clarifies the unit-payload
vs nullary constructor distinction in §3.2 / §3.3. Addresses the
secondary surface confusion that the Addendum 10 bisection table
surfaced implicitly (lines 1203–1207, 1219–1226 — pattern shapes such
as `(Red)` / `(Blue)` and the single-tuple-payload constructor form).

### Acceptance status

The F-024 acceptance criterion has two halves. The **spec-side half is
met**: both informal-surface defects that the Addendum 10 re-bisection
isolated are now patched in `LLMLL.md`, and the shipping `examples/`
already use the canonical forms.

The **empirical half remains open**: a re-probe cell — Gemini on
`002-bank-ledger` against the `llmll` target, post-`ecdf42f`/`f5dce77`
spec state — must produce a `solution.llmll` that parses on the first
turn (i.e., the parse-failure mode bisected to match-arm wrapping in
Addendum 10 does not recur). Not a Phase-3 gate. Recommended bundle:
fold into the small re-probe described in Addendum 11's "Combined
implication for Phase 3" (which is currently scoped to F-026 / F-028 on
the LLMLL cell anyway), so the F-024 empirical close lands as a
by-product of the F-026/F-028 probe rather than a separate run.

### Priority matrix delta

F-024 row in the Addendum 11 priority matrix (line 1570) updates to:

| F-024 | Match-arm wrapping drift + unit-payload pedagogy | language-team + documentation-lead | Medium | **Spec-side closed 2026-05-12 (R5a → `ecdf42f` §3.3/§9/§13.5; unit-payload → `f5dce77` §3.2/§3.3); empirical re-probe pending — bundle with F-026/F-028 re-probe per Addendum 11** |

## Addendum 13 — F-024 empirical close

> **Added:** 2026-05-12
> **Purpose:** Record empirical closure of F-024. The spec-side patches in
> Addendum 12 (`ecdf42f` match-arm wrapping; `f5dce77` unit-payload pedagogy)
> were exercised against a fresh Gemini cell on `002-bank-ledger × llmll ×
> k=1 × 1 try`. The Addendum-10 parse-failure mode does not recur.

### Sample composition

- **Cells:** 1 (n=1)
- **Agent:** `gemini-default` (Gemini CLI 0.41.2, default model — continuity
  with the original F-024 probe and the Addendum 9 Phase-2.0 probe)
- **Experiment:** `002-bank-ledger`; **Target:** `llmll`
- **Repair budget *k*:** 1; **Tries:** 1
- **Compiler version pin:** `0.10.2`
- **Harness commit:** `f5dce77` (working tree; orchestrator code unchanged
  since the Phase-2.0 probe)
- **Run directory:**
  `experiments/repair-loop/runs/20260512T164907Z-f024-reprobe-e002-bank-ledger-llmll/`
- **Terminal state:** `budget-exhausted` (expected at k=1; downstream
  verification could not close in a single turn — see "out-of-scope" note
  below)
- **Manifest:** `experiments/repair-loop/manifest.phase2-probe-llmll.json`
  (reused verbatim from the original F-024 probe)

### F-024 acceptance criterion — met

`evaluation.json:correctness_subscores`:
- `solution_discovery.value = true`
- `build_typecheck.value = true` (parse + typecheck (non-strict) on turn 1)

`repair_loop_log.json:turns[0].verifier_results[name="check"].exit_code = 0`,
with stdout `✅ solution.llmll — OK (6 statements, 7 warnings)`. Compare the
original F-024 probe (`runs/20260511T183807Z-phase2-probe-2-…`):
`build_typecheck.value = false`; `check.exit_code = 1` with parse-phase
error at `solution.llmll:32:25`.

Full verifier-rc breakdown for this turn:

| Command | rc | Note |
|---|---|---|
| `check` | 0 | 6 statements, 7 warnings (unknown-function warnings on `map-*`) |
| `check-strict` | 1 | unknown-function errors on `map-*` (out-of-scope for F-024 — see below) |
| `holes` | 0 | one non-blocking `?proof-required` hole at `def-logic transfer [post]` |
| `test` | 0 | 0 properties defined; 0 fail |
| `verify-fixpoint` | 1 | same `map-*` errors as `check-strict` |
| `verify` | 1 | same `map-*` errors as `check-strict` |

### Match-arm form in the new emission

Wrapped form, per `LLMLL.md §17` grammar and the §3.3 informal examples
patched in `ecdf42f`. Citation: `solution.llmll:13-15, 29-39`:

```
(match (map-get ledger id)
  ((Success b) (ok b))
  ((Error _)   (err "account missing")))
```

Each arm is `(pattern body)`. No sibling-form arms anywhere in the
emission. No nullary-vs-unit-payload constructor confusion in the
constructor usage either (`Success x`, `Error x` carry payloads
consistently). The `f5dce77` pedagogy patch and `ecdf42f` example patch
are both empirically vindicated by this single cell at n=1.

### F-024 status

Closed. Both halves:

- **Spec-side:** closed per Addendum 12 (`ecdf42f` + `f5dce77`).
- **Empirical:** closed per this run.

F-024 row in the Addendum 11 priority matrix (line 1570) updates to:

| F-024 | Match-arm wrapping drift + unit-payload pedagogy | language-team + documentation-lead | Medium | **Closed 2026-05-12 — spec-side: `ecdf42f` (§3.3/§9/§13.5) + `f5dce77` (§3.2/§3.3); empirical: `runs/20260512T164907Z-f024-reprobe-…` (n=1, Gemini, k=1, `check.rc=0`). See Addendum 13.** |

### Out-of-scope for F-024 — candidate finding F-031 flagged for Phase-2 calibration

`check-strict`, `verify`, and `verify-fixpoint` all reject the emission
with `call to unknown function 'map-get' | 'map-set' | 'map-values'`. The
names appear in `LLMLL.md:133` (§2.5 Naming Conventions example list) and
`LLMLL.md:1464` (a §13 reasoning example), implying they are spec'd
builtins. `compiler/src/LLMLL/TypeCheck.hs:68-145` registers `builtinEnv`
across §13.1 (arithmetic) – §13.9 (commands) and §13.11 (crypto); no map
operations are registered. The agent inferred from the spec surface that
map ops exist; the compiler disagrees.

This is a distinct surface from F-024 (parse-only acceptance bar) and is
**not** rolled into F-024's closure. Routing decision deferred to the
Phase-2 calibration matrix
(`experiments/repair-loop/manifest.phase2-calibration.json`): the 9-cell
matrix at k=5 × 3 tries on `002-bank-ledger × {llmll, python, go}` will
surface the issue at higher n if it is real. If it surfaces on ≥2/3 LLMLL
cells, open as a new finding **F-031** (next free index after F-030,
line 1576) routed to `language-team` (decide: register `map-*` builtins
in §13.X, or remove the misleading example mentions). If `language-team`
resolves toward registration, downstream consumer is `compiler-engineer`
(add to `builtinEnv` with appropriate signatures for a polymorphic map
type).

No spec-side or compiler-side action this turn. F-031 is flagged but not
opened — n=1 is below the bar for routing a new finding.

### Withdrawn items

None this turn.

### Null results

None this turn. Pre-stated null definition (parse succeeds but emission
is semantically empty, e.g., a single hole) is not met: the emission has
6 non-trivial statements + one well-targeted `?proof-required`
post-condition hole on `transfer`.

### Implications

- **Phase-2 calibration unblocked on the F-024 axis.** The match-arm parse
  failure was the highest-priority pedagogical noise source identified by
  Addendum 10 after F-021/F-022/F-023 closure. Calibration cells should
  now reach the `check rc=0` floor on first turn for any match-heavy
  LLMLL solution; this is the empirical precondition the matrix needs.
- **No `language-team` or `compiler-engineer` hand-off this turn.** F-024
  is closed; the map-builtin candidate (F-031) is flagged but not yet
  routed — pending Phase-2 calibration evidence.
- **No `documentation-lead` hand-off this turn.** The §2.5 / §3.3 patches
  have already shipped through the doc-track.

## Addendum 14 — F-028 reframing + F-031 Phase-2 evidence check

> **Added:** 2026-05-12
> **Purpose:** Correct the F-028 framing landed in Addendum 11. The `verify-fixpoint` diagnostic surface is **not** silent — diagnostics are emitted on stdout (not stderr) and the harness already captures and propagates them. My Addendum 11 evidence pass checked the wrong field. Also: verify that Addendum 13's flagged F-031 candidate (`map-*` spec/compiler disagreement) does not retroactively explain Phase-2's LLMLL budget-exhaustions. Both corrections are read-only retrospective analysis against existing Phase-2 artefacts; no new run.

### F-028 reframed — diagnostics exist; agent does not productively iterate on them

Phase-2 LLMLL cells' `verifier_results[*].stdout` for the `verify-fixpoint` command (final turn, `runs/20260512T031938Z-matrix/...`):

- **Cell 02 (target-reached), turn 5 — `verify-fixpoint.exit_code = 0`:**
  > `.fq written to /tmp/solution.fq | body-fallback: map_get, map_insert, create_ledger, balance, total_balance, transfer | Running liquid-fixpoint ... ✅ solution.llmll — SAFE (liquid-fixpoint) | .verified.json written to solution.llmll.verified.json`
- **Cell 01 (budget-exhausted), turn 3 — `verify-fixpoint.exit_code = 0`** (the reach point in the regression sequence):
  > `.fq written to /tmp/solution.fq | body-fallback: update-balance, transfer | Running liquid-fixpoint ... ✅ solution.llmll — SAFE (liquid-fixpoint) | .verified.json written to solution.llmll.verified.json`
- **Cell 01 (budget-exhausted), turn 4 — `verify-fixpoint.exit_code = 1`** (the regression point one turn later):
  > `(error :phase parse :file "solution.llmll" :line 52 :col 10 :message "reserved word post used as identifier" :hint "use def-logic, type, import, or check at the top level (v0.1.1 single-file model)")`
- **Cell 03 (budget-exhausted), turn 5 — `verify-fixpoint.exit_code = 1`:**
  > `.fq written to /tmp/solution.fq | body-fallback: total-balance, update-account, transfer | Running liquid-fixpoint ... ERROR: liquid-fixpoint: Liquid-Fixpoint Copyright 2013-21 Regents of the U...` (continues with the fixpoint solver's diagnostic body, truncated at the 16,000-char harness cap)

These stdout payloads are present in `repair_loop_log.json:turns[*].verifier_results[name="verify-fixpoint"].stdout` for every turn of every LLMLL cell. The orchestrator at `scripts/run_repair_loop.py:_run_verifier_chain:383-440` captures both stdout and stderr per command and writes them to `context/turn_NN_verifier.json`, which is the agent's next-turn input. The feedback channel is intact end-to-end.

Addendum 11 §F-028 (postmortem-001:1431-1465) claimed "verify-fixpoint stderr is empty across 15 LLMLL turns" and concluded "the feedback channel is silent on the failure mode that empirically distinguishes win from lose." The stderr observation was correct but the conclusion did not follow — I never sampled stdout. The diagnostics live there.

**Reframed claim:** the diagnostic *surface* is present and actionable; the *agent* does not productively iterate on it in n=3 LLMLL cells. Cell 01 most starkly: a Liquid-Fixpoint-SAFE solution at turn 3, broken to a parse-phase error at turn 4 by the agent's own edit (mis-placing `(post ...)` as a non-top-level identifier per the turn-4 diagnostic above), and not recovered by turn 5. The agent had structurally clean Liquid-Fixpoint and parse-phase feedback to act on and did not converge.

#### Status update

F-028 as written in Addendum 11 — **closed by this addendum** (mis-framed; diagnostics exist).

The open question that F-028's framing pointed at (why does gemini-default not push LLMLL obligations past `asserted` tier?) reattaches to **F-029 (non-monotonic repair)** — same agent-capability axis, not a harness or compiler-surface defect. F-029 stays open, sized accordingly.

#### Implication for Phase-3 gate

F-028 is removed from the Phase-3 gate. The remaining experiment-lead-routed gates are:

- **F-026 + F-027** (language-team, predicate vocabulary R6a/R6b/R6c). UNCHANGED.
- **F-018 / F-030** (compiler-engineer, PBT FuncEnv visibility). UNCHANGED.

#### Acceptance

Closed inline. No re-probe, no spec touch, no compiler patch.

---

### F-031 status check against Phase-2 evidence — does not retroactively apply

Addendum 13 (postmortem-001:1724-1749) flagged F-031: gemini emitted calls to `map-get` / `map-set` / `map-values` referenced as examples in `LLMLL.md:133` (§2.5) and `:1464` (§13), but `compiler/src/LLMLL/TypeCheck.hs:68-145` does not register map operations in `builtinEnv`. At n=1 (the F-024 re-probe cell), routing was deferred to Phase-2 evidence.

Phase-2 LLMLL cells' final-turn `solution.llmll`, surveyed for usage of spec'd-but-unregistered `map-*` operations:

- **Cell 01 (budget-exhausted):** kebab-case agent-defined `def-logic` for `find-balance`, `update-balance`, `has-account?`, `create-ledger`, `balance`, `total-balance`, `transfer`. No `map-get` / `map-set` / `map-values` calls. The agent constructed its own balance-lookup machinery in-solution.
- **Cell 02 (target-reached):** snake_case agent-defined `def-logic` for `map_get`, `map_insert`, `create_ledger`, `balance`, `total_balance`, `transfer`. Calls in-module only; no reference to spec'd `map-*` builtins.
- **Cell 03 (budget-exhausted):** agent-defined `update-account`, `total-balance`, `transfer`. Same pattern.

None of the three Phase-2 LLMLL cells trip the F-031 mechanism. The agent worked around the spec/compiler disagreement by emitting its own map ops as `def-logic` in-module. F-031 stays at n=1 from Addendum 13's re-probe; the Phase-2 LLMLL budget-exhaustions have a different mechanism (F-029-shaped — agent regression under repair pressure, as documented above).

#### Status update

F-031 — **flagged at n=1; routing remains deferred per Addendum 13.** Phase 3 will produce more data on it if real. No retrospective routing change.

---

### Revised "What the data tells us — synthesized" (correction to Addendum 11)

Addendum 11 §"What the data tells us" lesson 3 (line 1530) read: *"verify-fixpoint diagnostics are silent, so the repair loop is partially blind on LLMLL."* This is wrong as established above. The corrected synthesis:

3'. **Diagnostics are present; agent capability is the bottleneck.** `verify-fixpoint` emits actionable stdout (Liquid-Fixpoint SAFE / ERROR; parse-phase errors with file:line:col + reserved-word hints). The harness captures and propagates them. n=3 LLMLL cells show the agent does not consistently converge under repair pressure even when feedback is clean — cell 01's turn-3 reach followed by turn-4 self-inflicted parse error is the starkest example. **This collapses F-028 into F-029**: the open question is agent capability against extant diagnostics, not diagnostic absence. The question routes to experiment design (does AGENT_INSTRUCTIONS.md need explicit guidance toward obligation discharge?) and to language-team (does the trust-tier ladder reward the iterative behaviour we want?), not to compiler-engineer.

Addendum 11 lessons 1, 2, 4, 5 stand as written. Lesson 4 (F-029, non-monotonic repair) absorbs F-028's substance and should be read as the load-bearing agent-capability finding from this batch.

### Apparatus changes in this addendum

None. Documentation correction only. No change to:
- `experiments/repair-loop/scripts/run_matrix.py` / `run_repair_loop.py` — the orchestrator's stdout/stderr capture path was correct as shipped.
- `experiments/repair-loop/manifest.phase2-calibration.json` — Phase-3 launch still depends on language-team predicate decision.
- `LLMLL.md` — no spec touch from this correction.
- `compiler/src/LLMLL/` — no compiler patch from this correction.

The companion file `experiments/repair-loop/findings/compiler-engineer.md` §CE-A is revised to a closure note in the same turn — see that file's edit.

### Updated priority matrix (post-addendum-14)

| # | Finding | Consumer | Priority | Status |
|---|---|---|---|---|
| F-024 | Match-arm wrapping drift + unit-payload pedagogy | language-team + documentation-lead | Medium | Closed 2026-05-12 (see Addendum 12 + 13) |
| F-025 | Workspace-scoped agent state pinned Plan Mode | experiment-lead | High | Closed 2026-05-12 (Addendum 11); capability-probe deferred |
| F-026 | Cross-target predicate-strictness asymmetry | experiment-lead + language-team | High (Phase-3 gate) | **Open** |
| F-027 | `asserted` trust tier is a no-op in current predicate | language-team + compiler-engineer | High (Phase-3 gate; couples F-026) | **Open** |
| F-028 | (mis-framed) verify-fixpoint diagnostics not captured | compiler-engineer + harness-design | (was High; was Phase-3 gate) | **Closed by this addendum** — diagnostics are emitted on stdout; collapses into F-029 |
| F-029 | Non-monotonic repair (turn-3 SAFE → turn-4 parse error) | experiment-lead + language-team | Medium (absorbs F-028's substance; agent-capability axis) | **Open** (broadened) |
| F-030 | LLMLL `(check)` blocks skip — F-017 confirmed live | language-team + experiment-lead | Medium (couples F-018) | Open |
| F-031 | `map-*` spec/compiler disagreement (Addendum 13) | language-team (decide) → compiler-engineer | Medium (deferred at n=1) | Flagged, not routed. Phase-2 evidence (Addendum 14) confirms Phase-2 LLMLL cells did not trip it |

### Phase-3 readiness (post-Addendum-14)

The Phase-3 gate narrows to **two open items**, both routed in Addendum 11:

- **F-026 + F-027 (language-team)** — predicate vocabulary decision R6a / R6b / R6c. Until adjudicated, the matrix cannot evaluate H1 cross-target.
- **F-018 / F-030 (compiler-engineer)** — PBT FuncEnv extension to see imported-module def-logic. Until this lands, LLMLL `(check ...)` blocks cannot elevate obligations to `tested` tier under any tightened predicate.

No new experiment-lead action is productive until at least one of those gates lands. The previously-recommended cheap re-probe (Addendum 11's "Combined implication for Phase 3") is **narrowed**: with F-028 closed, the re-probe scope reduces to "1–2 LLMLL cells under whatever predicate R6a/R6b/R6c lands, plus the F-018-patched compiler" — the F-028-diagnostics-surfaced rider drops out. F-025 capability-probe in the harness prereq path stays deferred.

### Answer to the framing question

The experiment-lead's work on Phase 2 is **complete**. Phase-3 launch waits on `/language-team` (R6a/R6b/R6c adjudication) and `/compiler-engineer` (F-018 patch). The role is paused on downstream; the harness, manifest, and analysis are in a coherent state to resume when those land.

---

## Addendum 15 — R6d adoption + §LT-A / F-026 / F-027 empirical close (2026-05-13)

**Status:** F-026, F-027, §LT-A → **CLOSED**. Phase-3 readiness on the predicate-vocabulary axis restored. The two upstream gates named in Addendum 14's framing — language-team's R6a/R6b/R6c adjudication and compiler-engineer's F-018 — have both landed (F-018 in v0.10.3 / MOD-PBT-1 on 2026-05-12; R6d in `bb1bd98` + `bbab67b` + the harness patch on 2026-05-12 → 2026-05-13).

### Resolution

The `/language-team` adjudication of R6a / R6b / R6c (`findings/language-team.md` §LT-A, settled 2026-05-12 after a `/professor` pass) produced a fourth option, **R6d**:

- **Universal `Cred(R)`** (R6a-style tightening, lattice-meet reading) — the predicate refuses any cell with one or more `asserted` or `no_contract` entries.
- **Six-Int `tier_profile` aggregate** emitted by the compiler in the trust-report JSON (`docs/llmll-trust-report.schema.json`, introduced in `bb1bd98`) — replaces R6b's cardinal-weighted `S(R)` with a fixed-arity profile that respects `LLMLL.md §4.4.1:344` diamond incomparability between `contract_checked` and `tested`.
- **Spec-vs-tool boundary** — the consumer predicate and the H1 split are hosted in `experiments/repair-loop/README.md` ("Credibility predicate and the H1 split (R6d)"), not in `LLMLL.md`, per professor critique of R6c's spec-side hosting.
- **H1 bifurcation** restored — H1-Correctness (cross-target testkit, LLMLL via `CodegenHs`) + H1-Assurance (per-target profile, never scalarized cross-paradigm). Realigns with `docs/design/language-comparison-experiments.md:29-35`'s prior commitment that R6c had walked back.

The R6c cardinal-weighted scalar `S(R)` was withdrawn on professor critique — any total order over `contract_checked` vs `tested` weights collapses the §4.4.1 diamond into a total order, contradicting the load-bearing epistemic-status note at `LLMLL.md §4.4.1:346-347`. This empirical batch did not arbitrate that withdrawal; the spec contradiction did.

### Sample composition (re-probe)

- **Cells:** 3 × LLMLL × `002-bank-ledger` × gemini-default × k=5 — the same three cells from Addendum 11's Phase-2 calibration batch (cell IDs c01, c02, c03 in `runs/20260512T031938Z-matrix/matrix_report.json`). No new agent runs.
- **Compiler:** `llmll version` reports `0.10.3` (cabal pin not yet bumped to v0.10.4); binary contains R6d code from `bb1bd98` merged into `main` 2026-05-12. Verified by `which llmll` → `/Users/burcsahinoglu/.local/bin/llmll` (stack-install path) and a behavioural sanity check on cell_02's final-turn solution showing `trust_report_version: "1.0.0"` + `tier_profile` in the trust-report JSON.
- **Harness:** `main` at `bbab67b` plus four working-tree harness edits (`experiments/repair-loop/README.md` new R6d section; `scripts/run_repair_loop.py:_count_bad_trust_tiers` `accepted_levels` drops `"asserted"`, `_run_turn` captures `tier_profile`; `scripts/evaluate_run.py:_summarize_trust_report` extended with `tier_profile` / `cred` / `trust_report_version`; `manifest.phase2-calibration.json` `terminal_target.value` relabelling).
- **Re-probe method:** re-verify each cell's final-turn `solution.llmll` under the patched compiler (two-step: `llmll verify` to refresh `.verified.json` sidecar, then `llmll --json verify ... --trust-report --weakness-check --spec-coverage` to emit the R6d trust-report shape). No re-run of the repair loop. No new API spend.

### Per-cell results

| Cell | Final turn | `n_entries` | `tier_profile` (non-zero fields) | R6d `Cred` | Old predicate (2026-05-11) |
|---|---|---|---|---|---|
| c01 | turn_05 | 7 | `asserted=7` | **false** | budget-exhausted |
| c02 | turn_05 | 6 | `asserted=6` | **false** | **target-reached** (the false win) |
| c03 | turn_05 | 6 | `asserted=3, no_contract=3` | **false** | budget-exhausted |

All three trust reports emit `trust_report_version: "1.0.0"`. Cell c02's inversion (target-reached → `Cred=false`) is the empirical correction R6d was designed to make. The §LT-A finding "all 3 land at `asserted` under k=5" holds — and is now refused as terminal.

### Sub-finding (cell c01 non-monotonicity, unchanged from Addendum 11 / 14)

c01's R6d `Cred=false` agrees with the old predicate's `budget-exhausted`, but the *route* differs. Under the old predicate c01 was budget-exhausted because turn_05's verifier chain had a rc>0 command (the agent's self-inflicted parse error per Addendum 14, caught by `_eval_trust_tier_predicate`'s first-fail short-circuit). Under R6d the trust-tier composition itself (7/7 `asserted`) would have refused c01 regardless. Both predicates agree on c01's terminal_state via different paths. The asymmetry is worth noting for Phase-3 sample-size reasoning: the predicate has two routes to refuse a cell; tier-composition is the R6d route; rc>0 short-circuit is the structural route, unchanged.

### Sub-finding (cell c03's `no_contract` half, surfaced by R6d's profile)

c03's `tier_profile` shows 3 obligations at `asserted` and 3 at `no_contract` — meaning the agent declared contracts for only half the obligation sites in its solution. The pre-R6d `summary.no_contract: 3` field carried this signal but the predicate flattened it (any below-`asserted` entry already disqualified the cell). R6d's `tier_profile` preserves the distinction at the consumer level: cells with contract-omission are visibly different from cells with stated-but-unverified contracts. A hypothetical scalar `S(R)` averaging the `R6c` weights (`asserted=0.0`, `no_contract=0.0`, etc.) would have collapsed c02 (6 asserted) and c03 (3 asserted + 3 no_contract) to the same number — R6d's six-Int profile differentiates them, which is the empirical justification for the no-scalarization discipline beyond the §4.4.1 spec argument.

### Withdrawn items

- **R6c cardinal-weighted assurance score `S(R)`.** Withdrawn 2026-05-12 per the professor pass; the §4.4.1 diamond-lattice contradiction was the load-bearing reason, not this empirical batch. Recorded here for hygiene per the experiment-lead findings discipline (`findings/language-team.md:180-188` precedent for Withdrawn Items section).

### Acceptance — closed

- ✅ Predicate vocabulary decision (R6d) documented in `experiments/repair-loop/README.md` "Credibility predicate and the H1 split (R6d)" section.
- ✅ Harness predicate dispatch in `experiments/repair-loop/scripts/run_repair_loop.py:_count_bad_trust_tiers` updated (`accepted_levels` drops `"asserted"`; docstrings cite R6d).
- ✅ Re-probe cells' fresh trust-report JSON reflects the new measurable (`tier_profile` + `trust_report_version` extracted by patched `_summarize_trust_report`).
- ✅ Phase-2 calibration manifest's `terminal_target` block uses updated `value` labelling (`"all-expected-contracts-above-asserted"`).

### Implication

Phase-3 readiness on the predicate-vocabulary axis is restored. The matrix can now evaluate H1 as bifurcated **H1-Correctness** (cross-target testkit, structurally comparable) + **H1-Assurance** (per-target profile, never scalarized cross-paradigm). The Correctness / Assurance split prescribed in `docs/design/language-comparison-experiments.md:29-35` is now operationalized in the harness, restoring the discipline R6c had walked back.

### Status of adjacent findings

- **F-028 (verify-fixpoint diagnostics):** unchanged from Addendum 14 closure. Not engaged by R6d work.
- **F-029 (non-monotonic repair):** unchanged. Still routed to experiment-lead + language-team. R6d's predicate tightening makes the *empirical* signal of non-monotonicity more visible (trust-tier composition is the R6d gate, not just rc>0) but does not change the agent-capability question.
- **F-018 / F-030 / CE-B (PBT FuncEnv imported-module def-logic):** closed 2026-05-12 by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`). LT-B's contingent "does `(check ...)` elevate obligations to `tested` under the patched compiler" question was *not* directly tested in the R6d re-probe — the re-probe was re-verify only, not re-test. A focused LT-B re-probe (`llmll test` on the three Phase-2 cells' solutions under v0.10.4-pre) is a follow-up question outside the R6d closure scope; tracked under `findings/language-team.md` §LT-B.

### Phase-3 readiness

With §LT-A closed and F-018 / CE-B closed, the two gates Addendum 14 named are both resolved. Phase 3 launch is unblocked on the empirical-apparatus axis. Remaining open items before Phase-3 launch are scope decisions (matrix composition, agent set, k value, problem set) and the v0.10.4 release cut (cabal version bump + doc-lead CHANGELOG / roadmap close-out + tag), not apparatus blockers.
