# Postmortem 012 — Assume-Guarantee Ordering: The Adjudicating Experiment Returns 15/15 B

**Date:** 2026-07-24
**Compiler:** llmll 0.14.63.
**Experiment:** `011-assume-guarantee-order` (solver-catches; withheld callee **precondition**, not a post).
**Models:** claude-opus-4-8, gpt-5.5, gemini-3.1-pro-preview.
**Batch:** `runs/20260724T151500Z` (15 attempts).

---

## Headline

The experiment the professor and language-team **independently converged on** as the arbiter of their disagreement — an in-fragment (QF-LIA + arrays) sequential assume-guarantee task where a wrong call order passes a blind PBT but the solver refutes a withheld call-pre — returned **15/15 grade B, 0 caught.** All three frontier models, every try, wrote the correct order `(consume (guard bal k) k)` (guard establishes non-negativity; consume requires it), verified body-faithfully. The wrong order (`consume` on the raw input) refutes body-faithfully in isolation — confirmed pre-run through the real grader — but no agent produced it.

## The pre-registered adjudication (stated before the run)

- **Professor's position:** the decidable body-faithful fragment is coextensive with what frontier models find trivial, mediated by the induction wall; a fully-briefed in-fragment task will not elicit a subtly-wrong fill. *Prediction: all-B.*
- **Language-team's position:** the coupling is a fixture artifact; the sequential assume-guarantee chain is an in-fragment "decidable-yet-hard" cell where a wrong ordering is reachable. *Prediction: some grade-A.* Its own Risk #1 conceded: "if the chain fixture ALSO returns 30/30 B, the professor gains real support; my artifact claim weakens from 'shown' to 'argued'."

**Observed: all-B.** On the specific test both agreed would settle it, the language-team's own proposed exemplar did not produce a catch.

## Scope of what this does and does not settle

- **Settles (for this shape):** a short (two-call), **honestly briefed** (Post-8: the "guard first" requirement was stated in the prose) in-fragment ordering task does not elicit grade-A from the current frontier. This is consistent with the professor's *mechanism*, not just the outcome: a fully-briefed spec is followed, so the naive error does not occur (professor Hazard 3).
- **Does not settle:** (a) a longer *n*-call chain, or a less-explicit brief, was not tested — the language-team's design gestured at threading *n* calls, and two is the shortest; (b) the out-of-fragment / measure-supply route (the professor's ranked-#1 pivot) is untested; (c) the metatheory crux (is decidability-of-VC separated from program descriptive-complexity, or is there a synthesis-side coupling theorem) is a question for the professor's literature reach, not this experiment.

## Compiler note (fed the F-011.3 line)

Building the fixture surfaced that the call-pre discrimination only emits when `process` carries an anchor post; a naive anchorless map-returning body falls back — the same Lever A residue class as F-011.3 (map-store conditional bodies), fixed this session (commit `893a2f6`). The validated fixture supplies the anchor post.

## Bottom line

Across three fixture shapes now — trivial (007/008), discriminative-by-value (009/010), and discriminative-by-ordering (011) — the minimal-agent solver-catches harness has produced **0 grade-A across 69 frontier-model attempts.** The verifier's error-catching value remains established by construction (hand-written wrong fills refute) and unobserved on any real agent fill. The framing verdict (does this decide the professor/language-team crux, and how much) is left to the user; the empirical record is the tally.
