# Postmortem 009 — DEF-RET `expected_return_type` A/B: Fill-the-Hole Regime Built, Run Gated on a Stale Binary

**Date:** 2026-06-21
**Harness SHA:** `ae6fb55` (`main`, tag `v0.13.2`) + this session's uncommitted harness work (experiment `005`, scaffold template `seeded-return-holes`, `prepare_run.py`/`run_matrix.py` `--context-expected-return-type` hook, `evaluate_run.py` `REQUIRED_FEATURES[5]` + scaffold-required generalization, `manifest.defret-e005.json`).
**Compiler version (source tree):** llmll 0.13.2 (`compiler/package.yaml`; DEF-RET landed `main`, commits `a948deb` + `0b27be5`, tags `v0.13.1`/`v0.13.2`).
**Compiler version (`llmll` on PATH):** **0.12.1** — `llmll version` confirmed. Predates DEF-RET.
**Experiment:** `005-seeded-return-holes` (A/B `context_expected_return_type` on/off). **First fill-the-hole regime in the minimal-agent harness.**
**Manifest:** `experiments/minimal-agent/manifest.defret-e005.json`
**Run ID:** none — **gated** (see Headline). The A/B was not launched.
**Excluded from analysis:** n/a (no data).

---

## Headline finding

The A/B postmortem-008 specified is now **built and harness-verified**, but the run is **gated** on a hard prerequisite that is not met in this environment: the `llmll` binary on PATH is **0.12.1**, which predates DEF-RET. The DEF-RET surface (`return_type` on `def`/`def-shell`, schema `Program.schemaVersion 0.7.0`, the `expected_return_type` checkout field) lives in the source tree at `0.13.2` and on tags `v0.13.1`/`v0.13.2`, but no `0.13.x` binary is installed. A 0.12.1 binary rejects a `0.7.0` program and does not parse a declared return type, so `check`/`holes`/`verify` would fail on **both** arms — a false-null with zero information about the field's payoff. **Do not launch until `llmll version` reports ≥ 0.13.2.** Independently, the sandbox in this session denies all `llmll` subcommands except `version` and denies the LLM-dispatch CLIs' execution path, so even with a correct binary this agent could not have launched the matrix; per the postmortem-008 discipline (design first; run only if cheap and self-contained), the run is surfaced for the user, not auto-launched. Everything short of compiler/LLM dispatch is built and tested: the seeded-hole fixture, the injection hook (byte-identical `problem.md` across arms except the brief), and the matrix-scale prepare path all verified green on a `--prepare-only` dry run.

## What was built (the fill-the-hole regime — the postmortem-008 prerequisite)

postmortem-008 found `expected_return_type` dormant because every prior experiment is blank-slate authoring — no pre-seeded hole, so the checkout/holes brief surface where the field lives is never exercised. This session closes that standing instrument gap by adding the harness's **first fill-the-hole experiment**.

| Artefact | Path | Role |
|---|---|---|
| Experiment def | `experiments/minimal-agent/experiments/005-seeded-return-holes.md` | Fill-the-hole task: fill 2 seeded body holes, do not author |
| Seeded fixture | `experiments/minimal-agent/scaffold-templates/seeded-return-holes/scaffold.ast.json` | Pre-authored program; types + interface + 2 signatures written; 2 `hole-named` bodies remain |
| Injection hook | `prepare_run.py` `RETURN_TYPE_BRIEF_BLOCKS` + `--context-expected-return-type` | Condition-A append of the holes' `expected_return_type` brief |
| Matrix threading | `run_matrix.py` per-agent `context_expected_return_type` | Parallel to the existing `context_effect_summary` plumbing |
| Non-vacuity gate | `evaluate_run.py` `REQUIRED_FEATURES[5]` + `problem_id in {3,5}` scaffold-required | Stops the evaluator grading stub bodies A (the F-B0-3 lesson) |
| Manifest | `manifest.defret-e005.json` | 3 models × {A,B} × 3 tries = 18 attempts; `_feasibility_gate` banner |

### Fixture design (the non-obvious-return requirement)

Two seeded holes, each on a function whose return type is **not** inferable from the param list alone (the postmortem-007 saturation trap is avoided — condition B cannot read the type off the params):

- `clamp-to-word : int -> Word` (`def`), hole `clamp-to-word-body`. `Word = (where [w: int] (and (>= w 0) (<= w 65535)))` — a **refinement-aliased** `int`. The param is a plain `int`; the return is the 16-bit-bounded refinement, carrying the §3.4.1 return obligation. An agent without the type would plausibly return a plain `int`.
- `find-account : string -> Result[Account, LookupError]` (`def-shell`), hole `find-account-body`. The param is a `string`; the return is a **two-channel sum** (`Result`), not a bare `Account` or `string`. An agent without the type would plausibly return a bare value or use the wrong constructors.

**The fixture's defs deliberately OMIT the DEF-RET `return_type` field.** This is a harness-shape accommodation, not an oversight, and it is the load-bearing methodological decision of this postmortem — see F-009.1.

## A/B design (as finalized; mirrors postmortem-007 layout)

- **Hypothesis:** populating `expected_return_type` for a function-body hole raises first-round fill correctness. **Null:** delta ≈ 0 (the return type is recoverable from the behavioral spec in `problem.md` + the seeded signatures without the brief). **Failure-of-instrument:** both arms ceiling (the markdown over-telegraphs the type, or the task is too easy) — pre-empted by withholding the type from the markdown prose and choosing non-obvious returns.
- **Metric:** first-round fill correctness = evaluator `status: "passed"` on the first attempt — `check --strict` clean, `holes --deps` reports no remaining holes, `test` passes, `verify` accepts both bodies against their declared returns. This is the existing whole-run stop policy; no stop-policy change (the harness stays a first-round instrument, `README.md:222-237`). `quality_grade` is secondary signal.
- **Sample:** 3 model families (`claude-opus-4-8`, `gemini-3-pro` cmd `gemini-3-pro-preview`, `gpt-5.5` cmd bare `codex exec`) × {A, B} × 3 tries = **18 attempts** (9 A / 9 B). The A−B delta in pass-rate is the DEF-RET verdict.
- **Confound controls:** (1) byte-identical `problem.md` across arms except the injected brief block — verified by dry run (arm A ends at "Hole brief"; arm B ends at "Acceptance"); (2) same seeded fixture both arms (`scaffold_templates_provided: ["seeded-return-holes"]` in both); (3) condition B not at ceiling by construction (non-obvious returns + markdown withholds the type); (4) model versions + harness SHA pinned here and in the manifest banner.

## What was verified (no compiler, no LLM — pure-Python harness path)

A `--prepare-only` matrix dry run (`run_matrix.py manifest.defret-e005.json --prepare-only --run-count 1`, output to /tmp, since removed) produced all 6 cells and confirmed:

- **Differential correct:** `-A` cells' `problem.md` carries the `## Hole brief — expected return types (DEF-RET, condition A)` block with both holes' `expected_return_type` (`Word`; `Result[Account, LookupError]`); `-B` cells' `problem.md` omits it and is otherwise identical.
- **Fixture delivered:** each cell contains `.llmll/templates/seeded-return-holes/scaffold.ast.json` (4259 bytes) and records `scaffold_templates_provided: ["seeded-return-holes"]`, so the evaluator's `scaffold` requirement and `REQUIRED_FEATURES[5]` fire.
- **Hook threads end-to-end:** manifest per-agent `context_expected_return_type: true` → `run_matrix.prepare_run` → `--context-expected-return-type` → `prepare_one` → `RETURN_TYPE_BRIEF_BLOCKS["005"]` appended.

The dry run exercises every line of the new harness code except the compiler invocation in `evaluate_run.py` (which `--prepare-only` skips) and the agent dispatch in `run_agent.py`. Both of those are blocked in this session.

---

## Verified findings

### F-009.1. Fill-the-hole A/B with raw-AST agents forces the seed to omit `return_type`; the field's *real* (compiler-emitted) value is one step removed
**Priority:** Medium · **Consumer:** experiment-lead (owner) / user (methodology adjudication)

#### Evidence
The harness agents consume `solution.ast.json` directly — they do not call `llmll checkout`/`holes` to obtain a brief (`AGENT_INSTRUCTIONS.md:5-8`, `evaluate_run.py:226` runs `holes --deps` for *grading*, never `checkout`). The DEF-RET field `expected_return_type` is populated *from* a declared `-> RetType` on the def (`a948deb`; CheckoutToken, `docs/llmll-ast.schema.json:1070`). So if the seeded fixture declares `return_type`, **both** arms read it off the raw AST and condition B is at ceiling (the postmortem-007 trap). The only way to withhold the type from arm B, for a raw-AST agent, is to keep `return_type` out of the fixture AST (`scaffold.ast.json` `_fixture_note`). Condition A then re-supplies it via the injected brief — a **hand-rendering** of what `llmll checkout` would emit for a def carrying that return, not a value the compiler produced for this exact fixture.

#### Why we saw what we saw
The minimal-agent harness measures raw-AST authoring; the DEF-RET payoff lives in the *interactive checkout brief*, a surface this harness does not put agents through. The mismatch is structural — it is the same instrument gap postmortem-008 named, now narrowed to its residue: even with a fill-the-hole fixture, the brief is simulated (injected) rather than fetched.

#### Implication
The A/B as built is a **clean isolation of the field's information content** (does telling an agent the exact return type raise fill correctness?), which is the hypothesis postmortem-008 stated. It is **not** an end-to-end test of the `checkout`→`patch` agent loop. Implication for experiment-lead: the ecologically valid successor is a **checkout-native fill-the-hole harness** where the agent calls `llmll checkout <pointer>`, receives the *compiler-emitted* `expected_return_type`, and submits via `llmll patch` — the on/off would then be a real brief field, not an injected stand-in, and the seed would declare `return_type` honestly. That is a sibling harness (cf. the repair-loop harness), not a patch to this one. Treat the 005 A/B as the information-content measurement and label it as such in any writeup; do not over-claim it as a workflow measurement.

#### Acceptance
Closed when either (a) the 005 A/B runs on a ≥ 0.13.2 binary and reports a non-degenerate A/B delta with condition B below ceiling, or (b) a checkout-native harness supersedes it. Until then this finding stands as the scope caveat on any 005 result.

### F-009.2. Stale `llmll` on PATH (0.12.1) blocks the run — hard launch prerequisite
**Priority:** Blocker (for launching 005) · **Consumer:** user (environment) / experiment-lead

#### Evidence
`llmll version` → `llmll 0.12.1`. `compiler/package.yaml` `version: 0.13.2`; tags `v0.13.1`, `v0.13.2` present; DEF-RET commits `a948deb` (parse `return_type`) + `0b27be5` (Unit 2 discharge) on `main`. The fixture uses `schemaVersion 0.7.0` (the DEF-RET Program version; the schema notes it "was 0.6.0 in v0.11"). A 0.12.1 binary rejects 0.7.0 and has no `return_type`-on-def parse path.

#### Why we saw what we saw
The installed binary was not rebuilt after the DEF-RET cut. Independent of DEF-RET, the same staleness silently mis-measures **any** experiment whose fixtures use a feature newer than 0.12.1.

#### Implication
Implication for the user: before launching `manifest.defret-e005.json`, install/rebuild `llmll` from `main` HEAD (`stack install` in `compiler/`, or point `--llmll-cmd` at the freshly-built binary) and confirm `llmll version` ≥ 0.13.2. Then probe the field is live: re-add `return_type` to the two fixture defs in a scratch copy and run `llmll --json checkout` (or `holes`) — `expected_return_type` must appear. If it does not, DEF-RET did not survive the build and the A/B is still dormant (re-open postmortem-008). This is a standing harness-hygiene gap: the harness pins the *source* compiler version in metadata but never asserts the *binary* on PATH matches — see F-009.3.

#### Acceptance
Closed when `llmll version` ≥ 0.13.2 and a checkout/holes probe on the seeded fixture (with `return_type` re-declared) surfaces `expected_return_type`.

### F-009.3. The harness does not assert the PATH binary matches the pinned source version
**Priority:** Defence-in-depth · **Consumer:** experiment-lead (harness)

#### Evidence
`prepare_run.py` records `experiment_source` and copies `LLMLL.md`/`llmll-ast.schema.json` from the source tree, but nothing checks that `$(llmll version)` corresponds to those docs. `evaluate_run.py` runs `llmll` commands without a version assertion. F-009.2 (a 0.12.1 binary against a 0.13.2 fixture) would run silently to a false-null with no warning.

#### Why we saw what we saw
Version pinning has been a *reporting* discipline (write the version into the postmortem) not an *enforcement* one (fail fast if the binary is wrong).

#### Implication
Implication for experiment-lead: add a cheap preflight to `run_matrix.py` (or a `prepare_run.py --assert-min-version X.Y.Z`) that parses `llmll version` and refuses to launch when the binary is older than the manifest's declared minimum. This is harness code (experiment-lead-owned); low effort. It would have converted F-009.2 from a silent false-null into a launch-time stop. Not done this session (out of the task's `experiments/`-only build scope vs. would need a small new manifest field `min_llmll_version`); surfaced as the recommended follow-on.

#### Acceptance
Closed when a matrix launch against a binary older than the manifest's `min_llmll_version` aborts before dispatching any agent.

---

## Withdrawn items

- **"The 003 ecommerce scaffold could be reused as the DEF-RET seed."** Disconfirmed: 003's holes sit on `def-logic` (SDefLogic), which DEF-RET does not touch (postmortem-008 table; `a948deb` only added the surface to `SDef`/`SDefShell`), and its `return_type` keys are on `def-interface` signatures, not def bodies. A new `def`/`def-shell` seed was required; reuse was not viable.

## Null results

- None to report — **no run executed**, so there is no empirical null. The structural gate (F-009.2) is a launch prerequisite, not a measured null. (The dormancy null itself is postmortem-008's; this postmortem builds the instrument that would convert it to a measurement.)

## Estimated cost (for the gated launch)

18 attempts (3 models × {A,B} × 3 tries), one fill-the-hole task each. Per-attempt agent work is bounded by the fixture size (2 small holes against a ~130-line scaffold) — materially cheaper than the blank-slate 001-004 tasks. Order-of-magnitude: comparable to or below the `b0-e004` 18-attempt pilot. `timeout_seconds: 1800` per cell is a ceiling, not an expectation. Wall-clock dominated by the slowest model family and any gemini-3-pro throttling (step down to `gemini-2.5-pro` if it throttles, per project memory). LLM API spend is the user's tier; not estimable here.

## Exact launch command (for the user, after F-009.2 is cleared)

```bash
# 0. Build a DEF-RET binary and put it first on PATH (or pass --llmll-cmd to point at it):
#    cd compiler && stack install   # then confirm:
llmll version            # must report >= 0.13.2

# 1. Dry run — confirm the A/B differential and fixture delivery (no agents, no spend):
python3 experiments/minimal-agent/scripts/run_matrix.py \
  experiments/minimal-agent/manifest.defret-e005.json --prepare-only
#    then diff an -A vs -B problem.md in the prepared batch — only the
#    "## Hole brief" block should differ.

# 2. Launch the A/B (18 attempts):
python3 experiments/minimal-agent/scripts/run_matrix.py \
  experiments/minimal-agent/manifest.defret-e005.json
#    (add  --llmll-cmd is NOT a run_matrix flag; set llmll_cmd in the manifest
#     if the DEF-RET binary is not the bare `llmll` on PATH.)

# 3. Read matrix_summary.md in the batch dir; the A-pass-rate minus B-pass-rate is the verdict.
```

## Routing

- **experiment-lead (owner):** fixture + hook + manifest built and dry-run-verified; the run is gated on F-009.2. Follow-on: F-009.3 (version preflight) and the F-009.1 checkout-native successor harness.
- **compiler-engineer:** no bug. Descriptive note: confirm DEF-RET parsing/`expected_return_type` population survived into a shippable binary; F-009.2 is an environment/build-install gap, not a code defect.
- **language-team:** no spec implication — DEF-RET is shipped surface; the payoff measurement is now instrument-ready, pending a non-stale binary.
- **documentation-lead:** if the withdraw-demo / examples adopt `-> RetType` on real def bodies, those become natural checkout-native seed fixtures (the F-009.1 successor inherits ecological validity), but that is downstream of a run, not a current doc gap.

## Recommended next move

1. **Clear F-009.2:** install a ≥ 0.13.2 `llmll`; probe `expected_return_type` is live on the fixture.
2. **Dry-run, then launch** `manifest.defret-e005.json` (command above) — cheap, self-contained, 18 attempts.
3. **On results:** A−B pass-rate delta is the verdict; report condition B's absolute pass-rate to confirm it was below ceiling (else the result is instrument-saturated, not a null).
4. **Then** (optional, F-009.1): scope the checkout-native fill-the-hole successor harness for the workflow-level measurement.
