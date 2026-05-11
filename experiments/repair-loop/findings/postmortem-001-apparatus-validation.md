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
