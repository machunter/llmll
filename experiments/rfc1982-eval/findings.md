# RFC 1982 evaluation run — findings

> **Experiment:** the §4 evaluation plan of [`docs/design/spec-from-rfc-pipeline.md`](../../docs/design/spec-from-rfc-pipeline.md) — run the S0→S5 pipeline **by procedure** on an RFC not yet in the repo, and score the pipeline against its own six success criteria. Subject: **RFC 1982 (DNS serial number arithmetic)**, primary candidate named by the doc. Executed 2026-07-12 at v0.14.38; artifact: [`examples/rfc1982_serial/`](../../examples/rfc1982_serial/). This run closes gap **G4** (the doc's promotion-to-done criterion) and delivers the first persisted **G1** clause-inventory artifact.

## Criterion scores (§4, all six)

| # | Criterion | Result |
|---|---|---|
| i | Persisted S1 clause inventory, every normative clause dispositioned into C1–C6 | **PASS** — 9/9 clauses (Q1–Q9) in `VERIFICATION_SCOPE.md`; the template future runs copy |
| ii | ≥1 core invariant body-faithful `verified` | **PASS, exceeded** — 3/3 (`serial-add`/`serial-lt`/`serial-gt`); trust report `verified: 3, asserted: 0` — the tcp-class ceiling |
| iii | Every contracted clause carries `:source` | **PASS** — 6/6 pre/post clauses (one `pre` per function, so the G2 and-combination drop never triggers) |
| iv | Authored mutant refuted + localized | **PASS ×2** — `serial-lt-bad` (the historical naive-`<` DNS bug) `refuted: serial-lt`; `serial-add-bad` (no wrap) `refuted: serial-add` |
| v | Weak-spec co-evolution exhibit | **PASS** — `serial-lt-weak` (same naive body SAFE under a partial §3.2 reading); inventory row Q5 makes the gap enumerable |
| vi | 100% effective coverage, every `⊘` citing the RFC | **PASS** — 100% (3/3), zero `⊘` needed (no opaque clause; the `⊘` half is vacuous for this RFC) |

**Clause inventory summary:** C2 ×6 (space bound; addition formula as a linear conditional subtraction under the n-bound; n-range/undefined; equality-folded; lt; gt), C2-derived+C5 ×1 (the neither-lt-nor-gt pair at distance 2³¹ — implied by the biconditionals, demonstrated by a passing property), C6 ×1 (implementation-freedom prose), C5 ×1 (§5 vectors, width-adapted to 32 bits). SERIAL_BITS = 32. The S0 decision that mattered: §3.1's `modulo` was dispositioned into a linear conditional subtraction **before** authoring — the pipeline's fragment-scoping stage doing exactly its job.

**Withdrawn items: none. No taxonomy gap, no S0 scoping error, no actor-assignment error observed** (n=1 operator run — a blind-agent repetition would be needed to claim S0 is agent-doable).

## Findings

- **F-1982-1 → compiler-engineer (Medium — TERM-REPORT-PLAIN family):** `--spec-coverage`'s tier column prints `Verified: 0 / Asserted: 3` while the same tree's trust report says `verified: 3, asserted: 0` — the coverage summary does not read solver evidence. Reproduced with and without `--strict-verified-core`, and independently re-reproduced at merge time. Tracked as **COVERAGE-TIER** on the roadmap.
- **F-1982-2 → compiler-engineer (Low):** the PBT multi-callee diagnostic says "wait for `:subject` metadata in OBLIG-PBT-4," but `:subjects [f g]` is shipped and works (warning clears, witnesses 1→3). Stale message text; folded into the COVERAGE-TIER row as a same-visit item.
- **F-1982-3 → language-team (Low, doc revision):** C5 test vectors are width-parametric — RFC 1982's §5 examples (SERIAL_BITS = 2/8) don't transfer verbatim to a 32-bit instance; the pipeline doc's §1.2 C5 row should require a recorded width adaptation.
- **F-1982-4 → language-team (Low, doc precision):** S4.4's "no flag fires" claim is shape-dependent (n=2 across 2 RFCs): nothing fires on tcp's totality-omission shape, but `--weakness-check` **does** fire on the implication-only bool post ("indistinguishable from `(lambda [...] true)`"). The human-loop conclusion stands; the mechanized floor is higher than stated for one shape class.
- **F-1982-5 → language-team (doc revision):** S1's stated inputs should include access to the RFC source text — verbatim quotes needed a fetch; memory-paraphrase would fail the §2 audit.
- **CDP null result:** `[spec-inconsistent-or-unproven]` with 0 reliable candidates on all three functions — no adequacy signal from CDP on biconditional-bool/case-split shapes (consistent with tcp's recorded caveat).

## Reproduce

All commands and expected outputs are in [`examples/rfc1982_serial/README.md`](../../examples/rfc1982_serial/README.md); the verdicts are frozen in the family's `EXPECTED_VERDICTS.json` and run under `make refute-crux-gate`.
