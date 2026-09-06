---
name: critique-2026-09-05-triage
title: "External readings triage 2026-09-05: two reviewers, eleven items, six routed"
status: "Settled 2026-09-06. Of the six routed items, two shipped the same day (v0.19.0 and v0.19.1) and four are open roadmap rows. The declined and already-true items are recorded here and nowhere else."
date: 2026-09-05
author: language-team
consumers: [user, documentation-lead, compiler-engineer, professor]
style: "ASD-STE100 Simplified Technical English."
---

# External Readings Triage — 2026-09-05

> **Status:** Record of two outside readings of `main` at [`172f311`](https://github.com/machunter/llmll/commit/172f31115b634a938035f5bd25ec58eb73d1dab3) (`v0.18.0`, 2026-09-05), adjudicated by the user on 2026-09-05 from the language-team review. Six items were routed. Two shipped on 2026-09-06 as `v0.19.0` and `v0.19.1`. Four are open roadmap rows. The declined and already-true items are recorded here and nowhere else, so a later reader does not adjudicate them twice.
> **Prior triage:** [`critique-2026-07-19-triage.md`](critique-2026-07-19-triage.md).

---

## 1. The two readings, in one sentence each

**Reading A** says the drift-gate family (DRIFT-CT-2, DRIFT-DOC-4) is the right instrument aimed at the cheapest targets. It asks for the same instrument on normative spec claims, on the body-faithful census, and on fallback causes; for execution as a ship gate; for a cheap experiment to price `RESP-FACT-1` against `CMD-A`; and it warns against hand reconciliation and against slowing the cadence.

**Reading B** says to stop widening the language and harden a small publishable core. It asks for a frozen fragment with a written semantics, strict verification as the flagship path, a narrower Lean claim, the known trust-boundary gaps marked, the trust report as the product centerpiece, and positioning around agent coordination.

The two do not conflict. The adopted reading is: keep the cadence, and spend it on gates instead of on new `wasi.*` names.

## 2. Routing table

Every claim below was checked against the tree before it was routed. The check that mattered most is named in the Verdict column.

| Tag | Item | Verdict | Owner | Status |
|-----|------|---------|-------|--------|
| **NORM-CLAIM-1** | A1: gate normative spec claims the way CLI claims are gated | ROUTED, and cheaper than stated. DRIFT-CT-2 exists and four of its sixteen fixtures already target `LLMLL.md`. The missing piece is direction: it checks that a claim which exists still holds, and nothing checks that a claim has anything under it. Every `[SPEC]` row in the roadmap (about 24) was found as a side effect of other work. | language-team, then doc-lead and engineer | **OPEN**, design owed. Four dispositions per tagged claim: `fixture`, `falsified-by`, `row`, `assumed`. Pilot on §0.1 and §1. |
| **FALLBACK-CENSUS-1** | A2: make the body-faithful census a tracked metric | ROUTED. The denominator is already functions. The figure appears in no committed file, and no sidecar can yield it: the writer emits `body_faithful` only when true, so 503 sidecars carry 1407 flags and zero `false`. The source is the trust-report JSON, per run. | engineer | **OPEN** |
| **FALLBACK-REASON-CONST-1** | A3: aggregate fallback reasons | ROUTED after correcting the premise. The compiler did not know why a function fell back: `fallback_reason` was one constant string. Six causes now, attributed to the clause that caused the refusal. | engineer | **SHIPPED v0.19.0** |
| **BUILTIN-BODY-1** residue (1) | A4: make execution a ship gate | ROUTED as the class fix, not the eight instances: the build fixture calls all twelve hand-written equations, and the unit fold pins that every hand-written equation has a call site. Five of the twelve were invisible to the prefix classifier. | engineer | **SHIPPED v0.19.1** |
| **RESP-FACT-2** | A5: price the fact mechanism with a second and third fact | ROUTED. `wasi.fs.sha256` answers an `RText` of length 64, which `FACT-AG-LEN` would consume. One row in the table keeps the interim; a new delivery rule moves `CMD-A` up. | language-team, then engineer | **OPEN** |
| (policy) | A: do not hand-reconcile `LLMLL.md` against the compiler | ADOPTED. `oblig-0-spec` Rev 9 is the precedent the reading names. A hand pass resets the clock and does not change the rate. | all roles | no row |
| (policy) | A: do not slow the cadence | ADOPTED. The release rate did not produce `SAFE-ARG`; shipping surface before executing it did. | user | no row |
| (deferred) | A: an external check, blinded fuzzing of one verified module | DEFERRED to publication time. No row. | experiment-lead | no row |
| **TRUST-BASE-1** | B1: freeze a Core fragment and write its formal story | DECLINED as posed. `LLMLL.md` §0.1 records the reference-implementation stance on purpose: the generated Haskell is the semantics and there is no separate formal document. Reversing that is a larger commitment than the reading acknowledges. One piece survives: §0.1 asserts soundness and never names what the assertion rests on. | doc-lead | **OPEN**, filed 2026-09-06: one paragraph naming the trusted base |
| (measure first) | B2: make strict verification the flagship path | PARTIAL, already. `--strict-verify` runs the solver and marks refuted, because it sets `--cdp` and that routes past the trust-report early exit. It does not imply `--strict-verified-core`. Whether it should is decided by a count, not an argument: run `--strict-verified-core` over the examples tree and count the refusals. | engineer, then user | unfiled; measurement owed before a decision |
| (already true) | B3: narrow the Lean claim | ALREADY TRUE. README labels Leanstral experimental and opt-in, and states that general Lean verification is designed but not shipped. | none | no row |
| (already tracked) | B4: fix the trust-boundary gaps before strong claims | REPRODUCES the project's own open rows: `CAP-1-REAL`, `SHELL-FALLBACK-SILENT-1`, `SHA1-DOMAIN-1`, `EVENT-CAPTURE-1`, and `BUILTIN-BODY-1`. Corroboration of the tracking, not a finding. Its real content is B5. | none | rows exist |
| **DISCLOSE-ROW-1** | B5: the trust report as a nutrition label | ROUTED as its concrete shape. The report already discloses assumed facts (`AssumedFact`, RESP-FACT-1). It does not disclose the open `[SPEC]` rows a program's surface touches, so a reader of a report never learns that a `capability` clause is declarative. | engineer, after NORM-CLAIM-1 | **OPEN** |
| (positioning) | B6: write the paper around AI coordination | NOT ADJUDICATED HERE. It belongs to [`strategic-positioning.md`](strategic-positioning.md). | user | no row |
| (policy) | B: avoid full dependent types, broad Lean translation, rich effects, production security claims | CONSISTENT with the feature-freeze policy. Nothing to do. | none | no row |
| **SPEC-LAYOUT-1** | found on the way: hspec block nesting | Every block appended after `describe "v0.3.3 Agent Orchestration"` reports under it; a `do` at the same indentation as its `describe` swallows every later block. Verdicts are unaffected; failure paths are wrong. | engineer | **OPEN**, cosmetic, filed 2026-09-06 |

## 3. Findings made while adjudicating, and where each lives

1. `fiFallbackReason` was a constant for every fallback. Same class as `CAP-1-REAL`: a field whose name promises what its value does not carry. Lives in the `FALLBACK-REASON-CONST-1` closed row and the `v0.19.0` CHANGELOG entry.
2. The soundness sentence in `LLMLL.md` §0.1 does have artifacts under it: the refute-crux suite, 13 suites and 89 cases, gated in CI, is its falsification instrument, and `SAFE-ARG` is its one recorded falsification. That is the `falsified-by` disposition in `NORM-CLAIM-1`. The first draft of the review said "nothing sits under it" and was wrong. **Corrected 2026-09-06:** the count in this item does not reproduce. `refutecrux.llmll` lists twelve suites, and the twelve `EXPECTED_VERDICTS.json` files hold 80 `cases` entries: 36 in [`tools/llmll-driver/EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json) and 44 across the eleven suites under examples. The instrument is unchanged; the figure was wrong. Recorded as finding F7 in [`norm-claim-proposal.md`](norm-claim-proposal.md), whose `falsified-by` target names the gate and never a count.
3. Sidecars cannot yield the census. Lives in the `FALLBACK-CENSUS-1` row.
4. Five hand-written lowering equations keep the mangled head and differ only inside their arguments, so a prefix classifier cannot see them. Lives in the `v0.19.1` CHANGELOG entry and the `BUILTIN-BODY-1` closed row.
5. Eight well-typed shapes fail body-VC translation before the mixed-tail fallback site; only an ill-typed emitter-level witness reaches it. Whether a typechecked program can is open. Lives in the `v0.19.0` CHANGELOG entry and the `FALLBACK-REASON-CONST-1` closed row.
6. A committed sidecar exists for a program that fails `check` at HEAD. Lives in the `TOTP-CHECK-1` row.
7. A professor question was drafted and withdrawn: "is a soundness claim relative to a compiler-defined semantics vacuous?" It fails the negative test. The claim has been falsified once and repaired, so it is not vacuous; the publication-grade version of the question belongs with B6.

## 4. Order adopted

1. `FALLBACK-REASON-CONST-1` (shipped v0.19.0).
2. `BUILTIN-BODY-1` residue (1) (shipped v0.19.1).
3. `NORM-CLAIM-1`, design first.
4. `FALLBACK-CENSUS-1`, after 1.
5. `RESP-FACT-2`.
6. `DISCLOSE-ROW-1`, after 3.

The declined alternative to item 3 is on record in its roadmap row: one paragraph in `LLMLL.md` stating that normative sentences are ungated.
