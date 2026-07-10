# Cross-Language Agent Comparison Experiments

> **Status:** Design note
> **Purpose:** Capture a proposed experiment family for comparing LLMLL against mainstream programming languages as AI-agent implementation targets.

---

## Core Question

The existing `experiments/minimal-agent/` framework measures whether an agent can produce a first-round LLMLL solution from a small, isolated context. It is intentionally LLMLL-specific: the run directory contains `LLMLL.md`, `llmll-ast.schema.json`, `problem.md`, and the evaluator runs LLMLL compiler, test, hole, and verification commands.

The cross-language experiment family should ask a different question:

> Given the same product specification, how successfully does an AI agent realize it in LLMLL compared with mainstream implementation languages?

This should be a sibling framework, not a replacement for `minimal-agent`.

---

## Soundness Assessment

The comparison is only meaningful if it separates two things that are often conflated:

1. **Product correctness:** Does the delivered program behave according to the task specification?
2. **Assurance evidence:** What machine-checkable evidence supports that behavior?

LLMLL has an explicit verification story: contracts, trust reports, weakness checks, specification coverage, proof-required markers, and a known SMT verification boundary. Python, Go, TypeScript, Rust, and similar languages do not provide the same evidence by default. A fair comparison should therefore avoid a single "winner" score that treats unit tests and body-faithful verification as equivalent.

Recommended framing:

- Maintain a **Correctness Score** based on build success, API conformance, black-box tests, and edge-case behavior.
- Maintain an **Assurance Score** based on contracts, static types, property tests, runtime assertions, proof obligations, and explicit trust labels.
- Report **agent friction** separately: time, command failures, diagnostic quality, number of stopped runs, and recorded issues.

This lets LLMLL's verification surface matter without making the experiment unfair to languages that were not designed to express the same proof obligations.

> **Operationalization (2026-05-13, v0.10.4).** The Correctness / Assurance separation prescribed above is now implemented in the repair-loop harness; see `experiments/repair-loop/README.md` "Credibility predicate and the H1 split (R6d)" for the harness-side `Cred(R)` predicate, the `tier_profile` Assurance signal emitted by the compiler in the trust-report JSON (`docs/llmll-trust-report.schema.json`, `trust_report_version: "1.0.0"`), and the no-scalarization discipline. The single-winner-score prohibition above was tested and held: a tentative R6c proposal (cardinal-weighted scalar `S(R)` with `verified=1.0, contract_checked=0.75, tested=0.5, …`) was withdrawn on `/professor` critique because any total order over `contract_checked` vs `tested` collapses `LLMLL.md §4.4.1:344`'s diamond — exactly the conflation this section forbids. Full lineage: `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 15; `findings/language-team.md` §LT-A Resolution.

---

## Proposed Framework Shape

```text
experiments/repair-loop/
  README.md
  manifest.example.json
  problems/
    001-hangman.md
    002-bank-ledger.md
    003-rate-limiter.md
  prompts/
    agent-instructions.md
  targets/
    llmll.json
    python.json
    go.json
    typescript.json
    rust.json
  testkits/
    001-hangman/
      python/
      go/
      typescript/
      rust/
      llmll/
  scripts/
    prepare_run.py
    run_agent.py
    run_matrix.py
    evaluate_run.py
    compare_runs.py
```

**Implementation status (2026-05-15).** This framework shape is implemented at `experiments/repair-loop/` (the directory name is historical — the harness originated as repair-loop apparatus validation and matured into the cross-language harness over Phase 1 / Phase 2). The shape above describes the *intended* surface; the actual repair-loop has three targets (`llmll`, `python`, `go`), three scripts (`evaluate_run.py`, `run_matrix.py`, `run_repair_loop.py`) absorbing the work of the five sketched, and one of three problems (`002-bank-ledger`) with full Python + Go testkits. TypeScript / Rust adapters and the `001-hangman` / `003-rate-limiter` problem-and-testkit subtrees are pending in-place extension before Phase-3 launch. The framework shape above remains the canonical *design* statement; deltas relative to it are tracked in `experiments/language-comparison-backlog.md` and addressed by the experiment-lead.

The split between `problems/`, `targets/`, and `testkits/` is the main design point.

- `problems/` contain language-neutral requirements.
- `targets/` define the expected output files, toolchain commands, and language-specific API adapter.
- `testkits/` contain per-language black-box tests for the same behavioral contract.
- `evaluate_run.py` normalizes all target-specific evidence into a common report.

---

## Target Languages

The first target set should be small and intentionally boring:

| Target | Role in the comparison |
|---|---|
| `llmll` | The language under test. Measures schema-constrained generation, contracts, trust reporting, and verification ergonomics. |
| `python` | Strong AI-agent baseline. Dynamic, fast to write, weak static assurance unless tests and assertions are added. |
| `go` | Simple static baseline with predictable tooling and easy CLI/package conventions. |
| `typescript` | Common AI-agent target with optional static checking and strong ecosystem familiarity. |
| `rust` | Harder static baseline. Useful for observing whether strong type systems help or slow agents on small tasks. |

Other targets can be added later, such as Java, Kotlin, C#, Swift, or Haskell. They should be introduced only when the evaluator can run them reliably in the experiment environment.

---

## Manifest Shape

```json
{
  "experiments": ["001-hangman", "002-bank-ledger"],
  "targets": ["llmll", "python", "go", "typescript", "rust"],
  "run_count": 3,
  "timeout_seconds": 1800,
  "agents": [
    {
      "name": "agent-a",
      "cmd": "replace with agent command"
    },
    {
      "name": "agent-b",
      "cmd": "replace with another agent command"
    }
  ]
}
```

Each matrix cell is:

```text
agent x problem x target x attempt
```

The runner should prepare an isolated directory containing:

- `problem.md`
- `TARGET.md` or `target.json`
- `AGENT_INSTRUCTIONS.md`
- `PROBLEMS.md`
- target-specific test files
- target-specific wrapper commands, when needed
- for LLMLL runs only: `LLMLL.md`, `llmll-ast.schema.json`, and `bin/llmll`

---

## Target Adapter Shape

Each target adapter should define what counts as a solution and how to evaluate it.

Example Python adapter:

```json
{
  "target": "python",
  "expected_files": ["solution.py"],
  "commands": [
    {
      "name": "syntax",
      "argv": ["python3", "-m", "py_compile", "solution.py"]
    },
    {
      "name": "tests",
      "argv": ["python3", "-m", "pytest", "tests"]
    }
  ],
  "api": {
    "module": "solution",
    "required_symbols": ["initialize_game", "apply_guess", "render_state", "game_status"]
  }
}
```

Example LLMLL adapter:

```json
{
  "target": "llmll",
  "expected_files": ["solution.ast.json", "solution.llmll"],
  "commands": [
    {
      "name": "check",
      "argv": ["llmll", "check", "{solution}"]
    },
    {
      "name": "check-strict",
      "argv": ["llmll", "check", "{solution}", "--strict"]
    },
    {
      "name": "holes",
      "argv": ["llmll", "--json", "holes", "--deps", "{solution}"]
    },
    {
      "name": "test",
      "argv": ["llmll", "test", "{solution}"]
    },
    {
      "name": "verify",
      "argv": ["llmll", "verify", "{solution}", "--trust-report", "--weakness-check", "--spec-coverage"]
    }
  ]
}
```

The evaluator should not require every target to expose identical source syntax. It should require equivalent behavior through an adapter.

The `prediction_match` field defined at §"Reporting Output" is **not** an adapter-emitted field. Adapters report what they mechanically observe (commands run, exit codes, parsed outputs); `prediction_match` is added at the aggregator/reporting layer by post-hoc comparison against the immutable problem-shape audit (§"Experimental Controls" #7a). Adapter implementations should not look for this field, emit it, or model it.

---

## Scoring Model

### Correctness Score

Suggested 100-point scale:

| Category | Points | Notes |
|---|---:|---|
| Solution discovery | 10 | Expected file exists and uses allowed files only. |
| Build/typecheck/syntax | 15 | Language-specific compile or syntax pass. |
| API conformance | 15 | Required functions, CLI, or exported types are present. |
| Core behavior | 35 | Black-box tests for the central task. |
| Edge cases | 15 | Boundary cases, invalid input, repeated operations, empty data. |
| Determinism and isolation | 10 | No ambient network, time, randomness, or hidden filesystem dependency unless requested. |

### Assurance Score

Suggested 100-point scale:

| Category | Points | Notes |
|---|---:|---|
| Static structure | 15 | Types, interfaces, schemas, or clear data models. |
| Runtime checks | 10 | Input validation and explicit failure handling. |
| Test quality | 20 | Meaningful self-tests or properties beyond harness tests. |
| Contract strength | 25 | LLMLL `pre`/`post`, Rust type invariants, Go/TS validation boundaries, Python assertions. |
| Proof or trust evidence | 20 | LLMLL trust report, proof-required markers, spec coverage, or target-equivalent evidence. |
| Specification adequacy | 10 | Avoids trivial, weak, or vacuous specs. |

For LLMLL, the assurance score can use `--trust-report`, `--weakness-check`, and `--spec-coverage` directly. For other languages, the score is necessarily weaker and should be labeled as evidence, not proof.

---

## Experimental Controls

These controls matter more than the language list.

1. **Same natural-language problem.** The product spec should be identical across targets.
2. **Target-specific adapter, not target-specific product requirements.** Python should not be asked to do less than Rust or LLMLL.
3. **No hidden implementation hints.** Testkits should enforce behavior, not leak solution structure.
4. **No internet unless explicitly part of the condition.** Otherwise the experiment measures package lookup ability.
5. **Fixed stop policy.** Keep the current first-error policy for first-round effectiveness, or define a separate repair-loop experiment.
6. **Separate CLI and core logic.** Prefer pure core functions with a thin CLI. This makes cross-language tests cleaner.
7. **Record problems.** Keep `PROBLEMS.md` so agent confusion is observable.
7a. **Pre-register expected problem-shape engagement.** Before the matrix launches, the language-team produces a problem-shape audit at `experiments/repair-loop/findings/phase3-problem-shape-audit.md` recording, per problem, the verification paths each problem is expected to engage (e.g., `OBLIG-PBT-4 :subjects` opt-in, multi-callee writeback guard, body-faithful arithmetic, `?proof-required` escape, `letrec` + `:decreases` totality). The audit is **apparatus, not subject** — it is not shipped into per-cell agent run-prep; the agent never reads it. Post-hoc analysis compares predicted-vs-observed engagement; cells whose observed engagement diverges from the audit's prediction are flagged for separate discussion via the `prediction_match` field (§"Reporting Output"), not silently absorbed into aggregate signal.

    The audit's predictions are immutable from a fixed git commit hash that precedes matrix launch. Post-hoc analysis cites the audit at that commit, not at HEAD; any post-launch revision is recorded as a dated addendum appended to `experiments/repair-loop/findings/phase3-problem-shape-audit.md` (following the `## Addendum N (YYYY-MM-DD) — <title>` voice established at `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md`), never as an in-place edit. The immutability property — that registered predictions cannot be silently retuned to fit observed data — is the discipline that distinguishes pre-registration from re-narratable expectation (Nosek, Ebersole, DeHaven & Mellor, *The preregistration revolution*, PNAS 115(11):2600–2606, 2018).
8. **Report toolchain failures distinctly.** A Rust install failure and a Rust program failure are different outcomes.
9. **Do not collapse proof into tests.** Tests are falsification evidence; LLMLL verification is a stronger but bounded evidence type.

---

## Example Experiment 001: Hangman Core

### Purpose

Small game logic benchmark. Tests state modeling, pure transition functions, edge cases, and CLI discipline without needing complex IO.

### Specification

Build the core logic for a command-line Hangman game.

Required state:

- Secret word.
- Guessed letters.
- Remaining incorrect attempts.
- Current game status: `playing`, `won`, or `lost`.

Required API:

- `initialize_game(secret)` creates a new game state with 6 remaining incorrect attempts.
- `apply_guess(state, guess)` returns the next game state.
- `render_state(state)` returns a display string where unknown letters are `_`.
- `game_status(state)` returns `playing`, `won`, or `lost`.

Behavioral requirements:

- Guesses are one alphabetic character.
- Guess matching is case-insensitive.
- Repeated guesses do not consume attempts.
- Correct guesses reveal every matching position.
- Incorrect new guesses consume exactly one attempt.
- The game is won when all letters have been revealed.
- The game is lost when remaining attempts reaches zero.
- Once won or lost, further guesses do not change the state.

Suggested LLMLL assurance requirements:

- Contract on `initialize-game`: remaining attempts equals 6.
- Contract on `apply-guess`: remaining attempts never increases.
- Contract on repeated guess behavior if expressible; otherwise mark as `?proof-required` or cover with `check` blocks.

Harness tests:

- `banana` plus guess `a` renders `_ a _ a _ a` or equivalent normalized display.
- Repeating wrong guess `x` consumes at most one attempt.
- Six distinct wrong guesses lose the game.
- Guessing all unique letters wins the game.
- Guessing after win leaves status unchanged.

---

## Example Experiment 002: Bank Ledger

### Purpose

Financial invariant benchmark. Tests integer arithmetic, transaction validation, failure handling, and conservation-style invariants.

### Specification

Build an in-memory bank ledger for accounts and transfers.

Required state:

- A mapping from account ID to integer balance in cents.
- A transaction log recording successful transfers.

Required API:

- `create_ledger(accounts)` creates a ledger from initial balances.
- `balance(ledger, account_id)` returns the account balance or an explicit error.
- `transfer(ledger, from_account, to_account, amount)` returns a new ledger or an explicit error.
- `total_balance(ledger)` returns the sum of all account balances.

Behavioral requirements:

- Account IDs are strings.
- Balances are non-negative integers.
- Transfer amount must be positive.
- Transfer fails if either account is missing.
- Transfer fails if the source account has insufficient funds.
- Failed transfers do not modify balances or append successful log entries.
- Successful transfers debit the source, credit the destination, and append one log entry.
- Total balance is preserved by every successful transfer.

Suggested LLMLL assurance requirements:

- `pre` on `transfer`: amount is positive.
- `post` on successful transfer: total balance is unchanged.
- `post` on successful transfer: source decreases by amount and destination increases by amount.
- If map reasoning exceeds the current SMT fragment, use targeted checks and explicit proof-required markers rather than silent assertion.

Harness tests:

- Transfer 250 cents from `alice` to `bob` updates both balances.
- Transfer with insufficient funds returns an error and leaves ledger unchanged.
- Transfer to missing account returns an error.
- Zero or negative transfer amount is rejected.
- A sequence of valid transfers preserves total balance.

---

## Example Experiment 003: Token Bucket Rate Limiter

### Purpose

State-machine benchmark. Tests bounded counters, time-step handling, deterministic updates, and off-by-one behavior.

### Specification

Build a deterministic token bucket rate limiter.

Required state:

- Capacity.
- Current token count.
- Refill rate, in tokens per tick.
- Last observed tick.

Required API:

- `new_limiter(capacity, refill_rate)` creates a limiter initially full.
- `allow(state, tick)` returns `(new_state, allowed)` for one request at the given tick.
- `tokens(state)` returns the current token count.

Behavioral requirements:

- Capacity must be positive.
- Refill rate must be non-negative.
- Ticks are monotonically non-decreasing inputs.
- Before each request, tokens refill by `(tick - last_tick) * refill_rate`.
- Tokens never exceed capacity.
- A request is allowed when at least one token is available.
- Allowed requests consume exactly one token.
- Denied requests consume no token.
- Calls at the same tick do not refill.

Suggested LLMLL assurance requirements:

- `pre` on `new-limiter`: capacity > 0 and refill rate >= 0.
- `post` on `allow`: token count is between 0 and capacity.
- Multiplication in refill arithmetic may require runtime assertion or `?proof-required` depending on the chosen encoding.

Harness tests:

- A limiter with capacity 2 allows two same-tick requests and denies the third.
- A later tick refills tokens according to the refill rate.
- Token count never exceeds capacity after a large tick jump.
- Denied requests leave token count unchanged.
- Same-tick repeated calls do not refill.

---

## Example Experiment 004: Todo CLI Core

### Purpose

Product-style CRUD benchmark. Tests parsing, data modeling, deterministic updates, and simple persistence boundaries without requiring a database.

### Specification

Build the core of a todo-list command-line application.

Required state:

- A list of todo items.
- Each item has an integer ID, text, and completion flag.
- The next unused ID.

Required API:

- `empty_store()` creates an empty todo store.
- `add_item(store, text)` returns a new store and the created item ID.
- `complete_item(store, item_id)` marks an item complete or returns an explicit error.
- `delete_item(store, item_id)` removes an item or returns an explicit error.
- `list_items(store, include_completed)` returns visible items in insertion order.

Behavioral requirements:

- Empty text is rejected.
- IDs are unique and monotonically increasing.
- Completing a missing item returns an error and does not change the store.
- Deleting a missing item returns an error and does not change the store.
- Listing with `include_completed = false` hides completed items.
- Listing preserves insertion order for remaining visible items.

Suggested LLMLL assurance requirements:

- `post` on `add-item`: returned ID is unique in the previous store.
- `post` on `add-item`: next ID increases by one.
- `post` on failed operations: store is unchanged.
- Some list uniqueness/order properties may need checks or proof-required markers.

Harness tests:

- Adding two items returns distinct IDs in increasing order.
- Completing an item hides it from active-only listing.
- Deleting one item does not delete others.
- Missing complete/delete operations are explicit errors.
- Empty item text is rejected.

---

## Example Experiment 005: Password Reset Tokens

### Purpose

Security-adjacent benchmark. Tests explicit failure handling, expiry, one-time use, deterministic token validation, and avoidance of ambient randomness in the core.

### Specification

Build the core logic for password reset tokens. The harness supplies token strings and timestamps; the solution must not depend on real time or random generation for core validation.

Required state:

- A mapping from token string to token record.
- Each token record has a user ID, expiry timestamp, and used flag.

Required API:

- `issue_token(state, user_id, token, expires_at)` stores a new token or returns an explicit error.
- `validate_token(state, token, now)` returns the user ID or an explicit error.
- `consume_token(state, token, now)` validates and marks the token as used, returning the new state or an explicit error.

Behavioral requirements:

- User ID and token must be non-empty strings.
- Expiry timestamp must be positive.
- Duplicate token issuance is rejected.
- Unknown tokens are rejected.
- Expired tokens are rejected.
- Used tokens are rejected.
- Consuming a valid token marks it used exactly once.
- Failed validation or consumption does not mutate state.

Suggested LLMLL assurance requirements:

- `pre` on `issue-token`: non-empty user ID, non-empty token, positive expiry.
- `post` on successful `consume-token`: token is marked used.
- `post` on failed `consume-token`: state is unchanged.
- Map update and lookup invariants may require proof-required markers or focused checks.

Harness tests:

- Valid token before expiry returns the user ID.
- Token at or after expiry is rejected.
- Consumed token cannot be consumed again.
- Duplicate token issuance is rejected.
- Failed consume leaves the token usable if the failure was unrelated to that token.

---

## Example Experiment 006: CSV Sales Aggregator

### Purpose

Data transformation benchmark. Tests parsing, validation, grouping, aggregation, sorting, and malformed-row handling.

### Specification

Build a pure CSV sales aggregation module.

Input rows have these fields:

```text
date,region,sku,quantity,unit_price_cents
```

Required API:

- `parse_row(line)` returns a sale record or an explicit error.
- `parse_csv(text)` returns valid sale records and row-level errors.
- `revenue_by_region(records)` returns total revenue per region.
- `top_skus(records, limit)` returns SKUs sorted by total revenue descending, then SKU ascending.

Behavioral requirements:

- Quantity must be a positive integer.
- Unit price must be a non-negative integer.
- Region and SKU must be non-empty strings.
- Malformed rows are reported without aborting the entire parse.
- Revenue is `quantity * unit_price_cents`.
- Region totals sum revenue for all valid records in that region.
- `top_skus` respects the requested limit.
- Ties in `top_skus` are deterministic.

Suggested LLMLL assurance requirements:

- `pre` on `top-skus`: limit >= 0.
- `post` on `revenue-by-region`: all totals are non-negative.
- Multiplication and sorting properties likely exceed the current SMT fragment; mark those obligations explicitly or cover them with checks.

Harness tests:

- Valid rows aggregate by region correctly.
- Malformed rows are returned as errors while valid rows are retained.
- Negative quantity is rejected.
- Zero unit price is accepted and contributes zero revenue.
- `top_skus` sorts by revenue descending with deterministic tie-breaking.

---

## Reporting Output

Each run should write an `evaluation.json` with normalized fields:

```json
{
  "experiment_id": "001",
  "experiment_slug": "hangman",
  "target": "python",
  "agent": "agent-a",
  "status": "passed",
  "correctness_score": 87,
  "assurance_score": 42,
  "prediction_match": "unaudited",
  "first_error": null,
  "commands": [],
  "api_conformance": {},
  "test_summary": {},
  "assurance_summary": {},
  "problems_md": {}
}
```

The `prediction_match` field records whether the cell's observed verification-path engagement matched the language-team's pre-registered prediction in `experiments/repair-loop/findings/phase3-problem-shape-audit.md` (§"Experimental Controls" #7a). Value vocabulary `{match, divergence, unaudited}`; default `unaudited` for any cell not covered by the audit at its pinned commit. The field is **not emitted by the per-target adapter** (see §"Target Adapter Shape"); it is added at the aggregator/reporting layer by post-hoc comparison against the immutable audit (human judgment now; automatable later if the cross-language harness grows audit-parsing logic). Aggregation rule: cells with `divergence` are excluded from primary H1-Assurance aggregation and reported separately, so that unexpected engagement patterns surface as a distinct signal rather than being silently absorbed into the primary number. Direction and interpretation of any `divergence` cell are written in the post-hoc analysis prose, not pre-coded in the field — the field is a gate, not a score.

The batch summary should include both scores:

| Agent | Problem | Target | Attempt | Status | Correctness | Assurance | First Error |
|---|---|---|---:|---|---:|---:|---|
| agent-a | hangman | llmll | 1 | passed | 82 | 78 | - |
| agent-a | hangman | python | 1 | passed | 96 | 35 | - |
| agent-a | hangman | rust | 1 | failed | 30 | 20 | build |

This reporting shape supports a nuanced result: Python may score highest on quick behavioral delivery, while LLMLL may score higher on visible assurance and specification quality.

---

## Open Design Questions

1. Should the first version require only pure APIs, or include CLI behavior from day one?
2. Should agents be allowed to add their own tests, and should those tests affect the assurance score?
3. Should LLMLL receive its full documentation while other targets receive only short target instructions, or should every target receive a compact language-specific guide?

    **Resolution (Phase-3 launch scope).** The launch matrix ships full `LLMLL.md` to LLMLL cells and short target-specific instructions to Python / Go / TypeScript / Rust cells — the asymmetric joint-as-subject framing. This is the *declared scope* of the launch comparison, not an empirical refutation of the rival hypothesis "Python/Go would have won at matched documentation surface." Naming what varies and what is held fixed in cross-language programmer studies has prior discipline in the literature (Hanenberg, *An experiment about static and dynamic type systems*, OOPSLA 2010; Endrikat, Hanenberg, Robbes & Stefik, *How do API documentation and static typing affect API usability?*, ICSE 2014); under that discipline the launch is measuring agent-with-LLMLL-spec-surface joint, not agent-with-symmetric-documentation. A symmetric-documentation dose-response side-arm — a compact LLMLL-flavored discipline guide for Python / Go on one problem at ~⅓ per-cell budget — is registered as an open follow-on, deliberately deferred from the launch matrix. Trigger condition: "after launch matrix completes and H1-Assurance read is on record." (The discipline-guide itself is a non-trivial design artifact — not "LLMLL.md verbatim handed to a Python agent" but a symmetric-in-shape document at matched token weight and matched verification-discipline density — and is the experiment-lead's authoring scope when the trigger fires.)
4. Should the same agent command be reused across all targets, or should target-specialized agent prompts be allowed?
5. Should the evaluator permit package dependencies, or require standard-library-only solutions for the first benchmark set?
6. How should equivalent evidence be scored for Rust and TypeScript without overstating what their type systems prove?

---

## Recommended First Milestone

Implement the smallest useful version:

- Targets: `llmll`, `python`, `go`, `typescript`.
- Problems: `001-hangman`, `002-bank-ledger`, `003-rate-limiter`.
- Run count: 3.
- Correctness scoring: implemented.
- Assurance scoring: coarse but explicit.
- No external dependencies.
- Pure core APIs only; CLI is optional or omitted.

This keeps the first comparison focused on agent implementation quality and evidence quality, not package management or interactive IO.

---

## Deferred External Benchmarks

> **Source:** Language-team revision, 2026-05-25, per [`positioning-constraint-decay-proposal.md`](../archive/shipped-design-specs/positioning-constraint-decay-proposal.md) Rev 1 §§5–6 (settled with professor review folded).

### Dente et al. (2026) constraint-decay benchmark

Dente, Satriani, and Papotti, *Constraint decay: The Fragility of LLM Agents in Backend Code Generation* (arXiv 2605.06445, May 2026), ship an open-source agent benchmark on the RealWorld Conduit OpenAPI contract. They layer non-functional constraints (Clean Architecture pattern, PostgreSQL/SQLite backend, mandatory ORM — SQLAlchemy or Sequelize) across eight backend frameworks (Python: Flask, FastAPI, Django, aiohttp; Node.js: Express, Fastify, Hono, Koa), two agent scaffolds (Mini-SWE-Agent, OpenHands), and ten LLMs across five providers (open and closed; Mistral, Qwen, MiniMax, Moonshot, OpenAI) across ~5B tokens (~4.69B input + 43.3M output), and measure assertion pass rate and pass@1 collapse across L0 → L3. Their measurement set is exactly the external anchor the LLMLL design premise points at — see [`specification-sources.md §1`](specification-sources.md) and [`strategic-positioning.md`](strategic-positioning.md) §"External Empirical Anchor — Constraint Decay" for the full positioning treatment.

Running this benchmark on LLMLL is **deferred indefinitely**. The deferral is a recorded scope position, not a scheduling decision.

Two costs are in tension. Running the Conduit benchmark on LLMLL would constitute *benchmark-driven spec design*: under benchmark pressure, the project would commit to one HTTP-framework binding among several candidates (Servant vs. raw warp vs. some `wasi.http`-plus-router hybrid), a database-and-ORM story currently absent from the spec, and a verification axis for query composition (refinement-predicates over a relational algebra? capability-typed query effects? `?proof-required` carriers for SQL?) — each a multi-quarter design effort whose outcome the project has deliberately not yet shaped, and each interacting with the v0.11 architectural-correction cluster ([`core-shell-inversion-proposal.md`](../archive/shipped-design-specs/core-shell-inversion-proposal.md) LT-INV, [`contract-discriminative-power-proposal.md`](../archive/shipped-design-specs/contract-discriminative-power-proposal.md) LT-CDP, [`proof-required-predicate-carrier-proposal.md`](../archive/shipped-design-specs/proof-required-predicate-carrier-proposal.md) LT-PPR, [`int-2-boundary-shims.md`](../archive/shipped-design-specs/int-2-boundary-shims.md) LT-INT) currently in flight. *Not* running the benchmark, equivalently, leaves the field's strongest currently-published empirical anchor for the failure mode unaddressed by LLMLL, creating an asymmetry external readers will notice. The project records its choice as **design-discipline over empirical-anchor-completeness**, anchored to the avoid-design-by-benchmark commitment implicit in §Soundness Assessment above.

The deferral is overridable by explicit team consensus with a written soundness argument through the normal design → review → ship pipeline; it is not a permanent foreclosure.

### Perpendicular-axis admission

The `experiments/repair-loop/` harness specified in this document measures the *language-axis* variant of constraint-bearing agent authorship — *agent × problem × target language × attempt* on a *fixed constraint set*. Dente et al. measure the *constraint-stacking* variant — *constraint stack* on a *fixed language × fixed agent × fixed contract*. The axes are perpendicular. The Correctness/Assurance split this document specifies in §Soundness Assessment is orthogonal to Dente et al.'s L0 → L3 axis: Correctness/Assurance measures the *kind of evidence the same constraint set produces*; L0 → L3 measures *how constraints accumulate*.

Both can be measured by the project, but they are different empirical regimes; conflating them in external positioning would not survive contact with a careful reader. The constraint-layering axis is currently unmeasured under LLMLL and would require a sibling harness variant — separate problem set parametrized by constraint layer, fixed target language, fixed agent scaffold, no language-cross dimension. Recorded here as a deferred experiment, not a current capability. If the project later authorizes the constraint-layering harness, the natural place for it is `experiments/constraint-stacking/` as a sibling to `experiments/repair-loop/` and `experiments/minimal-agent/`, with its own manifest, problem set, and findings discipline; the per-harness role discipline in [`doc-consolidation-2026-05-24-proposal.md`](doc-consolidation-2026-05-24-proposal.md) §4.3 applies unchanged.
