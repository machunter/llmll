# Experiment Lead — Findings from Experiment 001

**Source:** Integrated postmortem of 18 attempts × 5 models on `001-two-agent-auth`
**Date:** 2026-05-10
**Re-routed:** 2026-05-10 — split from former `language-team.md` (E1–E3) and `documentation-team.md` (D1.1, D4) under the new five-role pipeline. `experiment-lead` owns the `experiments/minimal-agent/` harness end-to-end: scripts, manifests, prompts, evaluator rubric.

This file covers two work units:

- **EL-A — Evaluator overhaul** (E1 + E2 + E3): all changes in `evaluate_run.py` to make B/C separation grounded, feature-scan signals independent, and experiment 001's contract expectation internally consistent.
- **EL-B — Agent-instructions revision** (D1.1 + D4): edits to `experiments/minimal-agent/prompts/agent-instructions.md` to require `--strict` and to elicit *structured* protocol uncertainty rather than reward bullet-count compliance.

---

## EL-A · Evaluator overhaul

### E1. Delegation-Dependency Exclusion Uses Label Keywords, Not Call-Graph Reachability

**Priority:** Blocker for meaningful B/C separation

#### Evidence

[evaluate_run.py L420–441](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L420-L441). Two mechanisms run in parallel:

1. Structural inspection of the check block's own AST (L430) — rarely fires because checks call the function under test rather than inlining its body.
2. Label regex (L432): `\b(delegate|delegation|fallback|fail-closed|failed|fire-and-forget)\b` — does most of the work.

Same solution → B if the label hits the keyword set, C otherwise. Four of five functional models hit this boundary at the same 67% rate, indicating the boundary is naming-driven rather than evidence-driven.

#### Fix

Replace the label regex with transitive-callees analysis on the function call graph. A check `c` is delegation-dependent iff the transitive closure of functions reachable from `c` contains any expression of `kind ∈ {hole-delegate, hole-delegate-async, await}`.

**Soundness conditions:**

- Cycle-safe DFS (mutual recursion must not loop).
- Indirect calls conservatively over-approximated: any function whose definition contains a delegation marker contaminates every check that reaches it via any path.
- Conditional reachability over-approximated: any reachable delegation marks the check, regardless of branch coverage.

#### Acceptance

`is_delegation_dependent(check, solution_ast)` returns `true` iff a path through the call graph from any callee in `check` reaches a delegation hole, computed with cycle-safe traversal and a conservative treatment of indirection. Re-running 001 against the same five-model panel produces a B/C distribution that is no longer collinear with whether the check label contains a delegation keyword.

---

### E2. The Feature Scanner Conflates Type Usage with Helper-Call Usage

**Priority:** Quality of grading (not a blocker, can land in parallel)

#### Evidence

[evaluate_run.py L316–347](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L316-L347). The scanner sets `found["Result"] = True` for `kind:"result"`, for `constructor ∈ {Success, Error}`, and for `fn ∈ {Success, Error}`. A single signal feeds `missing_required`.

#### Why This Matters

Gemini-2.5-pro try02 was correctly graded F because its delegate `return_type` was the primitive `string` rather than `kind:"result"`, even though the body called `err()`. The current type-anchored signal caught the defect. Adding `fn ∈ {ok, err, is-ok}` to the same signal would mask it.

#### Fix

Three independent signals:

| Signal | What it tracks | Drives `missing_required`? |
|--------|---------------|---------------------------|
| `Result-type` | `kind:"result"` in any type position | Yes |
| `Result-helpers` | `fn ∈ {ok, err, is-ok, unwrap, unwrap-or}` | No (informational) |
| `Result-pattern` | `match` `constructor ∈ {Success, Error}` | No (informational) |

#### Acceptance

`feature_scan.required` for experiment 001 lists `Result-type`. The other two signals appear in evaluation output (informational columns in `matrix_summary.md` and `evaluation.json`) but do not drive the F grade.

---

### E3. Experiment 001's Contract Expectation Is Internally Inconsistent

**Priority:** Blocker for grade-A signal

#### Evidence

[evaluate_run.py L69–71](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L69-L71) sets `login-handler.pre.proof_required: False`. The experiment spec mandates `?delegate` inside `login-handler`. The verification matrix (`LLMLL.md §5.3.5`) and the README boundary (`README.md:81,89`) make contracts on functions containing delegation holes structurally `asserted`. With `proof_required: False`, the agent's `?proof-required` marker is silently ignored at [evaluate_run.py L497–513](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L497-L513), yielding `asserted_without_proof = 1` and a B ceiling at [evaluate_run.py L741–748](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/scripts/evaluate_run.py#L741-L748).

These three commitments are not jointly satisfiable.

#### Fix (pick one)

1. **Set `login-handler.pre.proof_required: True`.** The agent's `?proof-required` becomes the documented escape; grade A is reachable.
2. **Restructure the experiment** so the contracted function does not directly contain the delegation hole. Encapsulate `?delegate` in an uncontracted helper and put `pre` on the wrapper.

"Document max grade B" is not a fix — it preserves the inconsistency and trains agents to expect the ceiling rather than exercising the verification surface the rubric is designed to measure.

#### Acceptance

A grade-A solution sketch exists for the chosen formulation and is referenced from the experiment markdown (`experiments/minimal-agent/experiments/001-two-agent-auth.md`).

---

## EL-B · Agent-instructions revision

### D1.1. Agent Instructions Must Require `--strict`

**Priority:** High leverage, trivial

#### Problem

[agent-instructions.md L25](file:///Users/burcsahinoglu/Documents/llmll/experiments/minimal-agent/prompts/agent-instructions.md#L25) requires non-strict `llmll check`. Non-strict is sketch-mode tolerance for forward references and holes; finalised solutions should run under `--strict`. The CLI text-mode renderer suppresses warnings on success and prints only `OK`, so the agent never sees the diagnostic unless `--strict` (warnings → errors with nonzero rc) or `--json` (structured output) is requested.

#### Evidence

Flash try1 called `is-Result(...)`. Non-strict check exited 0. The agent concluded the solution was valid. The evaluator ran `--strict` → exit code 1 → grade F.

#### Fix

Update `agent-instructions.md` to require `llmll check solution.ast.json --strict`.

The companion compiler-side fix (surface accumulated warnings on text-mode success) is a `compiler-engineer` item — see `findings/compiler-engineer.md` D1.2. Either fix is independently sufficient; doing both is preferred.

#### Acceptance

Re-running experiment 001 against the same five-model panel produces zero attempts where `--strict` reverses a non-strict pass.

---

### D4. Audit Agent Instructions for Protocol Salience

**Priority:** Process quality

#### Problem

The original report recommended requiring at least one `PROBLEMS.md` bullet (only GPT-5.5 complied across 18 attempts). This is metric-shaping that rewards compliance theatre. The actual signal — agents not surfacing protocol uncertainties — is a prompt-design gap.

#### Fix

Audit `experiments/minimal-agent/prompts/agent-instructions.md` for whether the protocol is *structured* — for example a section instructing "Before finalising, list any spec ambiguity you resolved by guessing, with the section you consulted and the decision you made" — rather than whether a count threshold is met. The structured form elicits useful uncertainty data; the count threshold rewards padding.

#### Acceptance

The instructions contain at least one structured uncertainty-elicitation section that does not specify a minimum bullet count. Re-running experiment 001 produces protocol-uncertainty entries that vary in count across runs (i.e., the format is doing work, not satisfying a threshold).

---

## Withdrawn

**"Require at least one `PROBLEMS.md` bullet"** — withdrawn. Original report framed compliance count as the metric. This is metric-shaping; D4 above replaces it with structured uncertainty elicitation.

**"Extend feature scanner to match `ok`/`err`/`is-ok` calls as evidence of Result usage"** — withdrawn. The scanner's type-anchored check is doing real work: it correctly graded gemini-2.5-pro try02 F because the delegate `return_type` was the primitive `string` rather than `kind:"result"`. Relaxing to fn-call evidence would mask defects. Replaced by E2's three-signal split.

---

## Priority

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| **E1** | Call-graph delegation analysis | Blocker for B/C separation | Medium |
| **E3** | Contract expectation inconsistency | Blocker for grade-A signal | Low |
| **D1.1** | Require `--strict` in instructions | High leverage, trivial | Low |
| **E2** | Three-signal feature scan | Quality of grading | Low |
| **D4** | Structured uncertainty elicitation | Process quality | Low |

## Hand-offs

- **`compiler-engineer`** — companion item D1.2 (text-mode warning surface in `llmll check`). See `findings/compiler-engineer.md`.
- **`language-team`** — none from this file. EL-A and EL-B are self-contained within harness scope.
