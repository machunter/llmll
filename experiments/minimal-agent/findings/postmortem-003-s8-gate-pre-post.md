# Postmortem 003 — §8 Empirical Validation Gate: Pre/Post Comparison on `001-two-agent-auth`

**Date:** 2026-05-28
**Harness SHA:** `54d24b2`
**Compiler version:** llmll 0.10.8 (rebuilt from source at HEAD; prior binary was 0.10.6)
**Experiment:** `001-two-agent-auth`
**Run IDs:**
- Pre-arm (GrammarLegacy): `20260528T012230Z` — 6 attempts
- Post-arm (GrammarCoreInversion): `20260528T014158Z` — 6 attempts

---

## Headline finding

The §8 gate **cannot produce valid data in this configuration**: `--grammar=core-inversion` is not enforced for `.ast.json` input files. `ParserJSON.hs` ignores `GrammarMode` entirely. All 6 post-arm agents submitted `def-logic` solutions, the compiler accepted them with exit 0, and the post-arm grade distribution is identical to the pre-arm baseline (12/12 B, 0 verified, 0 proof-required across both arms). The null result is an artifact of the enforcement gap, not evidence about grammar difficulty. One post-arm agent (claude-opus-4-7-try03) explicitly logged `def-logic` under core-inversion grammar as a spec ambiguity in `PROBLEMS.md` — the agent was aware of the conflict but correctly inferred from compiler output that `def-logic` was accepted.

---

## Sample composition

| Arm | Batch | Grammar mode | Models | Tries | e001 attempts |
|-----|-------|-------------|--------|-------|---------------|
| Pre | `20260528T012230Z` | `GrammarLegacy` | claude-opus-4-7, gemini-3-pro-preview | 3 each | 6 |
| Post | `20260528T014158Z` | `GrammarCoreInversion` | claude-opus-4-7, gemini-3-pro-preview | 3 each | 6 |

**Historical reference (informational only):** `20260511T043023Z` — 6 e001 attempts, llmll 0.10.6, older LLMLL.md (pre-§12 LT-INV grammar update). Not in the gate cell; LLMLL.md version differs.

All attempts ran to completion. No timeouts. 12/12 harness status: passed.

---

## Gate-axis summary

Per `docs/compiler-team-roadmap.md:180-183`, the gate measures four axes. Results below are recorded but not interpretable as gate evidence due to F-GATE-1.

| Axis | Pre (6 attempts) | Post (6 attempts) | Gate implication |
|------|-----------------|-------------------|-----------------|
| (a) Overall pass rate | 6/6 (100%) | 6/6 (100%) | Null — no change |
| (a) Grade distribution | 6× B, 0× A/C/F | 6× B, 0× A/C/F | Null |
| (b) `verified` evidence fraction | 0/6 | 0/6 | Null |
| (c) `?proof-required` emission | 0/6 | 0/6 | Null |
| Boundary-form usage (`def` vs `def-shell` vs `def-logic`) | 12/12 `def-logic` | 12/12 `def-logic` | Null — **zero `def`/`def-shell` usage in post-arm** |

The null across all four axes is the expected result when enforcement is absent.

---

## Verified findings

### F-GATE-1. `GrammarCoreInversion` not enforced for `.ast.json` input

**Priority:** Blocker — gate cannot run until resolved.
**Consumer:** compiler-engineer

#### Evidence

`ParserJSON.hs` has no `GrammarMode` parameter and no reference to `GrammarMode` in any form (confirmed: `grep -n "GrammarMode" compiler/src/LLMLL/ParserJSON.hs` returns no output).

`loadStatements` in `Main.hs:376-386` routes `.ast.json` files to the JSON parser, which never receives `GrammarMode`. The S-expression parser (`Parser.hs:137`) correctly gates on `GrammarCoreInversion`:

```haskell
GrammarCoreInversion -> [pDef, pDefShell]
```

But all agents write `solution.ast.json` (JSON-AST format), so the S-expression gate is never reached.

Confirmed by direct test: `llmll --grammar=core-inversion check <post-arm-solution.ast.json> --strict` → exit 0, `OK (5 statements)`, with the solution containing two `{"kind":"def-logic"}` statements. Run directory: `runs/20260528T014158Z/20260528T014158Z-claude-opus-4-7-try01-of-03-e001/`.

Post-arm boundary-form distribution: 12/12 statements across 6 solutions used `kind:"def-logic"`. Zero `kind:"def"` or `kind:"def-shell"` emitted. The gate's axis-4 measurement (boundary-form usage distribution) cannot produce a non-trivial signal.

#### Why we saw what we saw

`GrammarMode` was designed for the S-expression parser path, where `def`/`def-shell`/`def-logic` are distinct keywords. In JSON-AST, the distinction is encoded as `"kind":"def"` vs `"kind":"def-shell"` vs `"kind":"def-logic"`. The JSON parser did not receive grammar-enforcement logic when LT-INV was implemented. The typechecker's `checkStatement (SDefLogic ...)` path (`TypeCheck.hs:635`) also has no grammar-mode gate — it type-checks `SDefLogic` identically regardless of `tcGrammarMode`. The flag is structurally correct but operationally inert for the JSON-AST path.

#### Implication for compiler-engineer

`ParserJSON.hs` must reject `{"kind":"def-logic"}` statements when `GrammarMode == GrammarCoreInversion`. Two enforcement points are available:

1. **Parser-level (preferred):** Pass `GrammarMode` to the JSON-AST parser's top-level dispatch (`parseStatement` or equivalent). When `GrammarCoreInversion` and `kind == "def-logic"`, emit a `core-grammar-violation` diagnostic with the statement pointer and exit 1. The diagnostic kind is already defined (`Diagnostic.hs:300`).

2. **Typechecker-level (alternative):** In `checkStatement (SDefLogic ...)` at `TypeCheck.hs:635`, read `tcGrammarMode` from the `TC` environment. When `GrammarCoreInversion`, emit the diagnostic before type-checking proceeds.

Parser-level is preferable because it gates early (before type inference runs on ill-formed input) and is consistent with how S-expression enforcement works (parse-time rejection).

#### Acceptance

`llmll --grammar=core-inversion check solution.ast.json` with a `{"kind":"def-logic"}` statement exits non-zero with a `core-grammar-violation` diagnostic. Re-running the post-arm with a fixed compiler produces at least one attempt where the agent encounters the rejection, corrects to `def`/`def-shell`, and the boundary-form axis returns a non-trivial distribution.

---

### F-GATE-2. Agent awareness of grammar mode is present but compiler feedback was absent

**Priority:** Observation — informs retry-count prediction.
**Consumer:** language-team, experiment-lead

#### Evidence

Post-arm run `runs/20260528T014158Z/20260528T014158Z-claude-opus-4-7-try03-of-03-e001/logs/agent.stdout.log` contains:

> "PROBLEMS.md records ... five decisions (**`def-logic` under core-inversion grammar**) with spec citations"

The agent read LLMLL.md §4.1 (which documents `--grammar=core-inversion` and the `def`/`def-shell` split), noticed the tension with its use of `def-logic`, and logged it as a spec ambiguity. It correctly inferred from `llmll check --strict` exit 0 that `def-logic` was accepted and proceeded. This is 1 of 6 post-arm agents that surfaced the ambiguity; the other 5 either did not notice or did not log it.

#### Why we saw what we saw

The agent's reasoning was empirically sound: the compiler gave no rejection signal, so `def-logic` was the rational choice. The LLMLL.md §4.1 note says `--grammar=core-inversion` *activates* `def`/`def-shell` but does not explicitly say `def-logic` is *rejected*. Once the compiler enforces rejection (F-GATE-1 fix), agents will receive a `core-grammar-violation` diagnostic and have grounds to switch to `def`/`def-shell`.

#### Implication for language-team

LLMLL.md §4.1 note should explicitly state that `def-logic` is *not accepted* under `--grammar=core-inversion`, not merely that `def`/`def-shell` are activated. The current phrasing leaves agents to infer rejection, and at least one inferred incorrectly (or charitably: correctly inferred that the current build doesn't enforce it).

This is a small spec-text clarification, not a new design decision.

---

## Duration analysis

| Model | Pre-arm mean (s) | Post-arm mean (s) | Delta |
|-------|-----------------|-------------------|-------|
| claude-opus-4-7 | 241.6 | 228.9 | −12.7 |
| gemini-3-pro-preview | 114.0 | 159.2 | +45.2 |

Gemini post-arm duration is 40% higher than pre-arm. With n=3 per cell this is within variance; it is not interpretable as a retry-count effect. No agent logs show a grammar-rejection-driven retry loop (because no rejection was issued). This axis cannot be evaluated until F-GATE-1 is fixed.

---

## Null results

**Hypothesis:** under `--grammar=core-inversion`, agents would adapt from `def-logic` to `def`/`def-shell`, producing a non-trivial boundary-form distribution and potentially higher verified-evidence fraction.

**Data:** all 12 post-arm attempts used `def-logic`. Boundary-form distribution: `def-logic` 100%, `def` 0%, `def-shell` 0%.

**Reason null, not evidence of failure:** the compiler did not enforce the grammar mode, removing the condition that would drive adaptation. This is not a null result about agent capability — it is a null result about compiler enforcement.

---

## Withdrawn items

None. No pre-run hypotheses were disconfirmed by evidence independent of F-GATE-1.

---

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---------|----------|----------|-----------------|
| **F-GATE-1** | JSON-AST parser does not enforce GrammarCoreInversion | compiler-engineer | Blocker | Low — parse-time dispatch change in `ParserJSON.hs` |
| **F-GATE-2** | §4.1 note should state `def-logic` is rejected under core-inversion | language-team | Medium | Trivial — one sentence |

---

## Next steps

1. **Route F-GATE-1 to compiler-engineer.** Fix `ParserJSON.hs` to emit `core-grammar-violation` for `kind:"def-logic"` under `GrammarCoreInversion`. The pre-arm results (`20260528T012230Z`) remain valid as the baseline and do not need to be rerun.

2. **Re-run post-arm only** using `manifest.s8-post-e001.json` against the fixed compiler. The batch will produce a different timestamp; compare against `20260528T012230Z` pre-arm.

3. **Route F-GATE-2 to language-team** for the §4.1 prose clarification. Small touch; can land in the same compiler release.

---

## Findings file fragments

See `experiments/minimal-agent/findings.md` — H2 sections `## Compiler-engineer` (F-GATE-1) and `## Language-team` (F-GATE-2) updated below.
