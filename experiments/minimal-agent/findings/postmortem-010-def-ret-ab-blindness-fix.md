# Postmortem 010 — DEF-RET `expected_return_type` A/B: Validity Bug Fix (Arm B Was Not Blind)

**Date:** 2026-06-21
**Harness SHA:** `9149638` (`main`) + this session's uncommitted experiment-`005` fix (scaffold `seeded-return-holes/scaffold.ast.json`, experiment `005-seeded-return-holes.md`, `prepare_run.py` `RETURN_TYPE_BRIEF_BLOCKS` + evaluator comments).
**Compiler version (source tree):** llmll 0.13.2 (`compiler/package.yaml`).
**Compiler version (`llmll` on PATH):** 0.12.1 (unchanged from postmortem-009; F-009.2 launch gate still stands — this fix does not clear it).
**Experiment:** `005-seeded-return-holes` (A/B `context_expected_return_type` on/off).
**Manifest:** `experiments/minimal-agent/manifest.defret-e005.json` (unchanged).
**Run ID:** none — pure-Python `prepare`/dry-run verification only; no agent dispatch, no LLM spend, no benchmark.

---

## Headline finding

The 005 A/B as shipped (postmortem-009) had a **validity bug that would false-null the experiment**: arm B (the blind control) was **not blind to the answer return types**, so the A−B delta would be attenuated toward zero regardless of the field's true payoff — the saturation trap postmortem-007 warned of, now realized in the control arm. The leak directly contradicts this experiment's own stated requirement (postmortem-009 F-009.1: "the only way to withhold the return type from condition B is to keep it out of the AST"). The shipped fixture honored the *letter* of that (the two hole-bearing defs do omit `return_type`) but violated the *intent* in two other materials both arms read. **The fix is implemented and re-verified by pure-Python prepare: arm B's task materials now contain neither `Word` nor `Result[Account`; arm A contains them via the injected brief only; the two prompts are byte-identical except the brief block.** The run remains gated on F-009.2 (stale `llmll` on PATH) — unchanged.

## The bug (two confirmed leaks in materials both arms read)

The orchestrator flagged two leaks. Empirical check of the on-disk fixture (pre-fix) refines the *mechanism* of leak #1 but confirms both as real:

1. **Seed scaffold leak — via the `_fixture_note`, not the def nodes.** The two hole-bearing defs (`clamp-to-word`, `find-account`) correctly omitted `return_type`. But the scaffold's `_fixture_note` prose named the answers verbatim — `"... a def carrying `-> Word` / `-> Result[Account, LookupError]` ... clamp-to-word ... must return the 16-bit-bounded refinement `Word`; find-account ... must return `Result[Account, LookupError]`"` — and the seed declared a `type-decl` literally named `Word`. The scaffold dir is copied wholesale (`prepare_run.py:426` `shutil.copytree`), so a raw-AST arm-B agent reads `Word` and `Result[Account, LookupError]` straight out of the seed it edits.
   - Pre-fix grep (arm B seed): `scaffold.ast.json:5` (`_fixture_note`, both literals) and `scaffold.ast.json:9` (`"name": "Word"`).
2. **Shared header leak — `problem.md` / `005-*.md`.** Line 5 ("v0.13 features exercised: ... refinement-aliased return (`Word`), `Result[t, E]` return ...") and lines 10–11 ("The types (`Word`, `Account`, `LookupError`) ... are already in place") name the answers in the shared experiment body, delivered identically to both arms.
   - Pre-fix grep (arm B problem.md): `problem.md:5` (`Word`, `Result[t, E]`), `problem.md:10` (`Word`), `problem.md:11` (`LookupError`).

Both leaks sit in materials delivered byte-for-byte to **both** arms, so condition B was reading the field-under-test off the fixture — the A/B's `context_expected_return_type` on/off injection ceased to be the only differential carrying the type.

## Design decision: Option (a) — blind-seed first-cut

Chosen: **Option (a)** (drop the type from everything both arms read; arm A's injected brief becomes the only source). Rationale:

- postmortem-009 F-009.1 already establishes this harness measures **raw-AST authoring**, not the `checkout`→`patch` loop, and routes the checkout-native version (Option (b)) to a *sibling harness*, not a patch to this one. Option (a) is the in-scope fix that restores validity to the **information-content** measurement the 005 A/B was designed to make ("does naming the exact return type raise first-round fill correctness?").
- Option (b) (checkout-native) remains the ecologically-valid successor and is left as the F-009.1 follow-on; it is not built this session.

**Explicit caveat (stated, per the Option-(a) requirement):** because the seed no longer declares the return, the injected arm-A brief is a *proxy* for the checkout brief, not a value the compiler emitted for this exact fixture. In a real `checkout`, `expected_return_type` populates *because* the return is declared on the def; here it is hand-rendered. This is an acceptable first-cut signal for the field's information content, but it is **not** a workflow-level (`checkout`→`patch`) measurement. Label any 005 result accordingly. (This is the same scope caveat as F-009.1; the fix does not change it.)

### Files changed (all under `experiments/minimal-agent/`)

| File | Change |
|---|---|
| `scaffold-templates/seeded-return-holes/scaffold.ast.json` | (1) **Removed the `type-decl` named `Word`** (hole 1's answer); the clamp return's refinement alias is no longer pre-declared. (2) **Rewrote `_fixture_note`** to drop the verbatim `-> Word` / `-> Result[Account, LookupError]` answers and the "non-obvious return" spoilers; added the BLINDNESS INVARIANT statement. Kept `Account`, `LookupError`, `def-interface AccountStore` (constructible vocabulary for hole 2, supplied to both arms; their names are not the forbidden literals). JSON validated. |
| `experiments/005-seeded-return-holes.md` | Scrubbed the type-name leak from the shared header: line 5 features-exercised (`Word`, `Result[t, E]` → "a refinement-aliased return, a two-channel (success / error) return"); the "What is provided" block (no longer names `Word`; states the seed leaves each return type **undeclared**); the task instruction now tells the agent it **must** declare each return type and may add the refinement-alias `type` the clamp return needs (the seed no longer provides it). Behavioral spec (lines describing "the refinement alias the signature requires" / "two-channel shape") retained — that is the inference signal both arms share. |
| `scripts/prepare_run.py` | Updated the `RETURN_TYPE_BRIEF_BLOCKS["005"]` comment to record the blindness invariant (seed + shared header must not name the type; the brief is the only source). The brief block content (arm-A injection) is **unchanged** — it remains the on/off differential. |
| `scripts/evaluate_run.py` | Updated the `REQUIRED_FEATURES[5]` comment: `type` is now satisfied by the seeded `Account`/`LookupError` aliases carried into the solution plus the refinement alias the agent ADDS for the clamp return (seed no longer pre-declares it). The scan already reads the **solution** (`scan_features`, `evaluate_run.py:350`), not the seed — consistent with Option (a) requiring the agent to add the return annotation. No logic change. |

The evaluator's REQUIRED_FEATURES[5] = `["type", "check", "post", ["Result-type", "Result-pattern"]]` + scaffold (when provided) is **solution-side already** and needed no logic change: `scan_features` reads `solution.ast.json` (`evaluate_run.py:350`), so it scores the agent's added return annotation / refinement / Result, not the seed's. Option (a)'s "score the SOLUTION's return_type, not the seed's" requirement was already met by construction.

## Re-verification (pure-Python; no compiler, no LLM, no benchmark)

`prepare_run.py --experiment 005` run into temp dirs under `runs/_defret_verify_tmp/` (since removed): arm A with `--context-expected-return-type`, arm B without. Plus a `run_matrix.py manifest.defret-e005.json --prepare-only --run-count 1` dry run (6 cells: 3 models × {A,B}).

- **Arm B is blind (grep evidence).** In arm B's task materials — `problem.md`, `AGENT_INSTRUCTIONS.md`, the seed `scaffold.ast.json` it edits, and `PROBLEMS.md` — `grep "Word"` → **no matches**; `grep "Result\[Account"` → **no matches**; `grep "Result"` (any) → **no matches**. (Lowercase `clamp-to-word` is the *function* name, present in both arms by design; lowercase `"kind": "result"` survives only in the seed's `AccountStore.raw-lookup` interface method, which returns an inline `Result[pair, string]` — a different shape than find-account's withheld answer, not a type-name leak.)
- **Arm A carries the type names via the brief only.** In arm A's `problem.md`, `Word` and `Result[Account, LookupError]` appear **only** at the appended `## Hole brief` block (lines 72–73), nowhere else.
- **Prompts byte-identical except the brief.** `diff` of arm B vs arm A `problem.md` shows a single hunk: the 8-line `## Hole brief` block appended in arm A (absent in arm B). The seed `scaffold.ast.json` and `AGENT_INSTRUCTIONS.md` are byte-identical across arms (`diff` → empty).
- **Matrix threading produces blind B cells.** In the `--prepare-only` batch, all six `-B` cells' task materials (`problem.md` / `AGENT_INSTRUCTIONS.md` / seed) contain neither `Word` nor `Result[Account`. (`Word`/`Result` do appear in the shared `LLMLL.md` / `llmll-ast.schema.json` reference docs copied into *every* cell of *every* experiment — symmetric across arms and unrelated to this task; see residual note below.)
- **`--prepare-only` exits 0.** `run_matrix.py manifest.defret-e005.json --prepare-only --run-count 1` → returncode 0, empty stderr, all 6 cells created.
- **exp-001 regression unaffected.** `prepare_run.py --experiment 001` prepares clean; the `--context-expected-return-type` flag is a verified **no-op** on exp-001 (problem.md byte-identical with/without the flag — the brief block is keyed to `"005"`).
- **Cleanup.** All temp dirs (`runs/_defret_verify_tmp/`) removed after verification.

## Residual note (not a blindness defect; future polish)

The experiment's chosen refinement-type name `Word` **collides with a spec example name**: `LLMLL.md` defines an unrelated `Word ≜ (where [s: string] (> (string-length s) 0))` (a non-empty *string*, used in the hangman worked examples) — a different type from this task's intended `(where [w: int] (and (>= w 0) (<= w 65535)))` (a 16-bit *int* refinement). Because `LLMLL.md` is copied identically into both arms, this is **symmetric** (no differential leak), and the spec's `Word` is a string refinement, so it does **not** telegraph this task's int-bounded answer (if anything it points the wrong way). It is therefore not a blindness defect by the task bar. But it forces a "different `Word`" caveat on the blindness argument. **Recommended polish (deferred, not done):** rename this experiment's refinement (and the arm-A brief's name for it) to a label not used in `LLMLL.md` (e.g. avoid `Word`/`Letter`/`PositiveInt`/`BlockID`), making the blindness argument airtight without the caveat. Out of necessary scope for this fix; the task bar is met as-is.

## Updated launch instructions (supersedes postmortem-009's only where noted)

The F-009.2 gate (stale `llmll`) and the launch command in postmortem-009 §"Exact launch command" are **unchanged** by this fix. Two additions to the pre-launch dry-run step:

```bash
# 0. (unchanged) Build a DEF-RET binary first on PATH; confirm:
llmll version            # must report >= 0.13.2  (F-009.2 — still open)

# 1. Dry run (no agents, no spend) — now also assert arm-B blindness:
python3 experiments/minimal-agent/scripts/run_matrix.py \
  experiments/minimal-agent/manifest.defret-e005.json --prepare-only
#    a) diff an -A vs -B problem.md  → only the "## Hole brief" block differs.
#    b) grep an -B cell's problem.md, AGENT_INSTRUCTIONS.md, and
#       .llmll/templates/seeded-return-holes/scaffold.ast.json for
#       'Word' and 'Result\[Account'  → MUST be empty (blindness invariant).
#       (Ignore matches in the shared LLMLL.md / llmll-ast.schema.json — those
#       are symmetric spec-reference docs, not task materials.)

# 2. (unchanged) Launch the A/B (18 attempts):
python3 experiments/minimal-agent/scripts/run_matrix.py \
  experiments/minimal-agent/manifest.defret-e005.json

# 3. (unchanged) matrix_summary.md: A-pass-rate − B-pass-rate is the verdict.
#    Report B's ABSOLUTE pass-rate to confirm it was below ceiling (else the
#    result is instrument-saturated). The blindness fix is what makes a below-
#    ceiling B observable at all; postmortem-009's fixture would have ceilinged B.
```

When the run completes, also note F-009.1's standing caveat: a non-null A−B delta is evidence the field's *information content* helps, **not** that the `checkout`→`patch` workflow surface helps — that is the F-009.1 checkout-native successor's question.

## Routing

- **experiment-lead (owner):** validity bug fixed and dry-run-verified; the 005 A/B is now a sound information-content instrument. Run still gated on F-009.2. Two follow-ons stand: F-009.1 (checkout-native successor harness) and F-009.3 (version preflight); plus the residual `Word` naming-collision polish above.
- **compiler-engineer:** no bug; no change. (F-009.2 remains an environment/build-install gap, not a code defect.)
- **language-team:** no spec implication — DEF-RET is shipped surface; the measurement is now valid and instrument-ready, pending a non-stale binary.
- **documentation-lead:** none.
